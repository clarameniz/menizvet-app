-- Staff Responsibility Editing + Veterinarian Enablement — Phase 1
-- (SPEC-ORG-006 §14–§15, SPEC-ORG-009 BR-1/BR-5/§7, SPEC-ORG-002 BR-17,
-- SPEC-ORG-005 §11, SPEC-VET-001 §13, SPEC-VET-004 §13, SPEC-VET-005 §13,
-- SPEC-VET-006; REQ-ORG-005/006/008, REQ-VET-001..005).
--
-- Contract/read/hardening only. No table, column, constraint, trigger,
-- capability, responsibility mapping, Entitlement, or backfill change.
--
--   1. get_organization_staff: each current Grant entry gains
--      responsibility_grant_id; every other field, filter and the ACL are
--      unchanged (CREATE OR REPLACE).
--   2. Client-safe Responsibility operations, Organization-keyed so the
--      Organization and ORGANIZATION_GRANT_RESPONSIBILITIES are decided (and
--      re-decided under the Organization lock) before any target row:
--        add_staff_responsibility, replace_staff_responsibility,
--        end_staff_responsibility.
--      Order: 28000 -> 42501 (Organization/capability, then unknown or
--      other-Organization target, identical) -> 22023 INVALID_SCOPE /
--      INVALID_CLINIC -> 23514 OWNER_GRANT / OWNER_MEMBERSHIP /
--      SELF_MEMBERSHIP -> 23514 MEMBERSHIP_INACTIVE; ended Grant ->
--      ALREADY_ENDED / ALREADY_CHANGED / GRANT_ENDED -> 23514 NO_OP /
--      DUPLICATE / LAST_RESPONSIBILITY / VETERINARIAN_ASSIGNMENTS_ACTIVE.
--      Writes delegate to the existing statement-instant writers
--      (20261026080000), so there is one writer per lifecycle change.
--   3. create_my_veterinarian_professional_profile: self only, serialized on
--      the acting User; CREATED / ALREADY_EXISTS (exact normalized replay,
--      same ids) / PROFILE_CREDENTIAL_MISMATCH. Delegates to the existing
--      Profile + Credential writer.
--   4. get_organization_veterinarian_workforce: Members with a current
--      VETERINARIAN Grant or a current Clinic Assignment, Profile existence
--      only, current Assignments with Clinic identity. No credential, Profile
--      id, User/Auth id or email. STABLE, non-locking, one snapshot.
--   5. assign_staff_veterinarian_to_clinic (Membership-keyed, Profile derived
--      server-side, requires a current Organization-scoped VETERINARIAN
--      Grant) and end_staff_veterinarian_clinic_assignment (no Grant
--      required). Clinic-in-Organization + CLINIC_MANAGE_VETERINARIAN_
--      ASSIGNMENTS first; statement-instant timestamps; lock order
--      Organization -> Clinic -> Membership/Assignment.
--   6. ACL: every new operation is executable by authenticated only. The
--      generic Responsibility, Assignment and Profile operations (which
--      disclose existence/lifecycle before authorization or raise raw
--      database errors) are withdrawn from public, anon and authenticated
--      and keep service_role for trusted compatibility. Provisioning and
--      suites move to the client-safe operations.
begin;

-- ==================================================================
-- 1. Organization Staff read: Grant identifiers (SPEC-ORG-009 BR-1/BR-5)
-- ==================================================================

create or replace function public.get_organization_staff(p_organization_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
    acting_user_id uuid;
    staff_result jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- One payload statement/snapshot and one temporal evaluation instant.
    -- The materialized authorization gate precedes every sensitive projection.
    with evaluation as materialized (
        select statement_timestamp() as instant
    ), authorized_organization as materialized (
        select organization.id, organization.display_name
        from public.veterinary_organizations as organization
        where organization.id = p_organization_id
          and (
              public.user_has_organization_capability(
                  acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'
              ) or public.user_has_organization_capability(
                  acting_user_id, p_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'
              )
          )
    )
    select jsonb_build_object(
        'organization_id', organization.id,
        'organization_display_name', organization.display_name,
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                'membership_id', membership.id,
                'effective_start', membership.effective_start,
                'is_self', membership.user_id = acting_user_id,
                'display_name', profile.display_name,
                'invitation_recipient_email', origin.recipient_email_normalized,
                'responsibilities', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'responsibility_grant_id', grant_record.id,
                        'responsibility', grant_record.responsibility,
                        'scope_type', grant_record.scope_type,
                        'clinic', case when grant_record.scope_type = 'CLINIC' then
                            jsonb_build_object('clinic_id', clinic.id,
                                'clinic_display_name', clinic_profile.display_name)
                            else null end
                    ) order by grant_record.responsibility, grant_record.scope_type,
                               grant_record.clinic_id)
                    from public.organization_responsibility_grants as grant_record
                    left join public.clinics as clinic
                      on clinic.id = grant_record.clinic_id
                     and clinic.organization_id = organization.id
                    left join public.clinic_public_profiles as clinic_profile
                      on clinic_profile.clinic_id = clinic.id
                    where grant_record.membership_id = membership.id
                      and grant_record.effective_start <= evaluation.instant
                      and grant_record.effective_end is null
                      and (grant_record.scope_type = 'ORGANIZATION' or clinic.id is not null)
                ), '[]'::jsonb)
            ) order by membership.effective_start, membership.id)
            from public.organization_memberships as membership
            left join public.user_profiles as profile on profile.user_id = membership.user_id
            left join public.organization_invitations as origin
              on origin.id = membership.originating_invitation_id
             and origin.organization_id = organization.id
            where membership.organization_id = organization.id
              and membership.effective_start <= evaluation.instant
              and membership.effective_end is null
        ), '[]'::jsonb),
        'pending_invitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'invitation_id', invitation.id,
                'recipient_email', invitation.recipient_email_normalized,
                'responsibilities', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'responsibility', intended.responsibility,
                        'scope_type', intended.scope_type,
                        'clinic', case when intended.scope_type = 'CLINIC' then
                            jsonb_build_object('clinic_id', clinic.id,
                                'clinic_display_name', clinic_profile.display_name)
                            else null end
                    ) order by intended.responsibility, intended.scope_type, intended.clinic_id)
                    from public.organization_invitation_responsibilities as intended
                    left join public.clinics as clinic
                      on clinic.id = intended.clinic_id
                     and clinic.organization_id = organization.id
                    left join public.clinic_public_profiles as clinic_profile
                      on clinic_profile.clinic_id = clinic.id
                    where intended.invitation_id = invitation.id
                      and (intended.scope_type = 'ORGANIZATION' or clinic.id is not null)
                ), '[]'::jsonb),
                'created_at', invitation.created_at,
                'expires_at', invitation.expires_at
            ) order by invitation.created_at, invitation.id)
            from public.organization_invitations as invitation
            where invitation.organization_id = organization.id
              and invitation.revoked_at is null
              and invitation.rejected_at is null
              and invitation.expires_at > evaluation.instant
              and not exists (
                  select 1 from public.organization_memberships as accepted
                  where accepted.originating_invitation_id = invitation.id
              )
        ), '[]'::jsonb)
    ) into staff_result
    from authorized_organization as organization cross join evaluation;

    if staff_result is null then
        raise exception 'Organization Staff unavailable' using errcode = '42501';
    end if;
    return staff_result;
end;
$$;

-- ==================================================================
-- 2. Private predicates (executable by no client or trusted role)
-- ==================================================================

-- Owner protection follows the conservative ended/non-ended target model of
-- end_organization_staff_membership: a non-ended OWNER Grant protects.
create function public.staff_membership_holds_owner(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and grant_record.responsibility = 'OWNER'
          and grant_record.effective_end is null
    )
$$;

create function public.membership_supports_current_veterinarian_assignment(
    p_membership_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.veterinarian_clinic_assignments as assignment
        where assignment.supporting_membership_id = p_membership_id
          and public.veterinarian_clinic_assignment_is_current(assignment.id)
    )
$$;

create function public.staff_responsibility_scope_is_supported(
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select coalesce(
        (
            p_scope_type = 'ORGANIZATION'
            and p_clinic_id is null
            and p_responsibility in ('ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')
        )
        or (
            p_scope_type = 'CLINIC'
            and p_clinic_id is not null
            and p_responsibility in ('ADMINISTRATOR', 'RECEPTIONIST')
        ),
        false
    )
$$;

-- The Clinic belongs to the named Organization and the actor holds the
-- Assignment-management capability for it (SPEC-VET-004 BR-19/BR-20).
create function public.user_manages_veterinarian_assignments_at(
    p_user_id uuid,
    p_organization_id uuid,
    p_clinic_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = p_organization_id
          and public.user_has_clinic_capability(
              p_user_id, p_clinic_id, 'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'
          )
    )
$$;

revoke all privileges on function public.staff_membership_holds_owner(uuid)
from public, anon, authenticated, service_role;
revoke all privileges on function public.membership_supports_current_veterinarian_assignment(uuid)
from public, anon, authenticated, service_role;
revoke all privileges on function public.staff_responsibility_scope_is_supported(text, text, uuid)
from public, anon, authenticated, service_role;
revoke all privileges on function public.user_manages_veterinarian_assignments_at(uuid, uuid, uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 3. Client-safe Responsibility operations (SPEC-ORG-006 §14)
-- ==================================================================

create function public.add_staff_responsibility(
    p_organization_id uuid,
    p_membership_id uuid,
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    membership_record public.organization_memberships%rowtype;
    existing_grant public.organization_responsibility_grants%rowtype;
    created_grant_id uuid;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Organization and capability, re-decided under the Organization lock.
    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    -- 3. Input. Clinic identity and Organization are immutable, so the
    -- Clinic is locked later by the writer in the shared lock order.
    if not public.staff_responsibility_scope_is_supported(
        p_responsibility, p_scope_type, p_clinic_id
    ) then
        raise exception 'Responsibility role or scope is not supported'
            using errcode = '22023', hint = 'INVALID_SCOPE';
    end if;

    if p_scope_type = 'CLINIC' and not exists (
        select 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = p_organization_id
    ) then
        raise exception 'Responsibility Clinic is not a Clinic of the Organization'
            using errcode = '22023', hint = 'INVALID_CLINIC';
    end if;

    -- 4. Target within the named Organization.
    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = p_organization_id
    for update;

    if not found then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    -- 5. Protected target: another actor's Owner Membership (BR-51).
    if membership_record.user_id <> acting_user_id
       and public.staff_membership_holds_owner(membership_record.id) then
        raise exception 'An Owner Membership cannot be changed through Staff'
            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';
    end if;

    -- 6. Lifecycle.
    if not (
        membership_record.effective_start <= statement_timestamp()
        and membership_record.effective_end is null
    ) then
        raise exception 'Organization Membership is not current'
            using errcode = '23514', hint = 'MEMBERSHIP_INACTIVE';
    end if;

    -- 7. An equivalent active Grant already exists: nothing is written.
    select grant_record.*
    into existing_grant
    from public.organization_responsibility_grants as grant_record
    where grant_record.membership_id = membership_record.id
      and grant_record.responsibility = p_responsibility
      and grant_record.scope_type = p_scope_type
      and grant_record.clinic_id is not distinct from p_clinic_id
      and grant_record.effective_end is null;

    if found then
        return jsonb_build_object(
            'outcome', 'ALREADY_PRESENT',
            'membership_id', membership_record.id,
            'responsibility_grant_id', existing_grant.id,
            'effective_start', existing_grant.effective_start
        );
    end if;

    created_grant_id := public.add_organization_responsibility(
        membership_record.id, p_responsibility, p_scope_type, p_clinic_id
    );

    return jsonb_build_object(
        'outcome', 'ADDED',
        'membership_id', membership_record.id,
        'responsibility_grant_id', created_grant_id,
        'effective_start', (
            select grant_record.effective_start
            from public.organization_responsibility_grants as grant_record
            where grant_record.id = created_grant_id
        )
    );
end;
$$;

create function public.replace_staff_responsibility(
    p_organization_id uuid,
    p_responsibility_grant_id uuid,
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    membership_record public.organization_memberships%rowtype;
    source_grant public.organization_responsibility_grants%rowtype;
    replacement_grant public.organization_responsibility_grants%rowtype;
    target_is_owner boolean;
    created_grant_id uuid;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Organization and capability, re-decided under the Organization lock.
    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    -- 3. Input.
    if not public.staff_responsibility_scope_is_supported(
        p_responsibility, p_scope_type, p_clinic_id
    ) then
        raise exception 'Responsibility role or scope is not supported'
            using errcode = '22023', hint = 'INVALID_SCOPE';
    end if;

    if p_scope_type = 'CLINIC' and not exists (
        select 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = p_organization_id
    ) then
        raise exception 'Responsibility Clinic is not a Clinic of the Organization'
            using errcode = '22023', hint = 'INVALID_CLINIC';
    end if;

    -- 4. Target within the named Organization; Membership then Grant locks.
    select grant_record.membership_id
    into target_membership_id
    from public.organization_responsibility_grants as grant_record
    join public.organization_memberships as membership
      on membership.id = grant_record.membership_id
    where grant_record.id = p_responsibility_grant_id
      and membership.organization_id = p_organization_id;

    if not found then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = p_organization_id
    for update;

    select grant_record.*
    into source_grant
    from public.organization_responsibility_grants as grant_record
    where grant_record.id = p_responsibility_grant_id
      and grant_record.membership_id = target_membership_id
    for update;

    -- 5. Protected targets.
    if source_grant.responsibility = 'OWNER' then
        raise exception 'An OWNER Responsibility cannot be changed through Staff'
            using errcode = '23514', hint = 'OWNER_GRANT';
    end if;

    target_is_owner := public.staff_membership_holds_owner(membership_record.id);

    if target_is_owner and membership_record.user_id <> acting_user_id then
        raise exception 'An Owner Membership cannot be changed through Staff'
            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';
    end if;

    if membership_record.user_id = acting_user_id and not target_is_owner then
        raise exception 'Own Responsibilities cannot be changed through Staff'
            using errcode = '23514', hint = 'SELF_MEMBERSHIP';
    end if;

    -- 6. Lifecycle.
    if not (
        membership_record.effective_start <= statement_timestamp()
        and membership_record.effective_end is null
    ) then
        raise exception 'Organization Membership is not current'
            using errcode = '23514', hint = 'MEMBERSHIP_INACTIVE';
    end if;

    if source_grant.effective_end is not null then
        -- Proof that exactly this change already happened: the requested
        -- Grant began, and is still active, at the instant the named one ended.
        select grant_record.*
        into replacement_grant
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = membership_record.id
          and grant_record.responsibility = p_responsibility
          and grant_record.scope_type = p_scope_type
          and grant_record.clinic_id is not distinct from p_clinic_id
          and grant_record.effective_start = source_grant.effective_end
          and grant_record.effective_end is null;

        if found then
            return jsonb_build_object(
                'outcome', 'ALREADY_CHANGED',
                'membership_id', membership_record.id,
                'replaced_responsibility_grant_id', source_grant.id,
                'responsibility_grant_id', replacement_grant.id,
                'effective_instant', source_grant.effective_end
            );
        end if;

        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514', hint = 'GRANT_ENDED';
    end if;

    -- 7. Rules.
    if source_grant.responsibility = p_responsibility
       and source_grant.scope_type = p_scope_type
       and source_grant.clinic_id is not distinct from p_clinic_id then
        raise exception 'The requested Responsibility is unchanged'
            using errcode = '23514', hint = 'NO_OP';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = membership_record.id
          and grant_record.responsibility = p_responsibility
          and grant_record.scope_type = p_scope_type
          and grant_record.clinic_id is not distinct from p_clinic_id
          and grant_record.effective_end is null
    ) then
        raise exception 'An equivalent active Responsibility already exists'
            using errcode = '23514', hint = 'DUPLICATE';
    end if;

    if source_grant.responsibility = 'VETERINARIAN'
       and p_responsibility <> 'VETERINARIAN'
       and public.membership_supports_current_veterinarian_assignment(membership_record.id) then
        raise exception 'Current Veterinarian Clinic Assignments must be ended first'
            using errcode = '23514', hint = 'VETERINARIAN_ASSIGNMENTS_ACTIVE';
    end if;

    created_grant_id := public.replace_organization_responsibility(
        source_grant.id, p_responsibility, p_scope_type, p_clinic_id
    );

    return jsonb_build_object(
        'outcome', 'REPLACED',
        'membership_id', membership_record.id,
        'replaced_responsibility_grant_id', source_grant.id,
        'responsibility_grant_id', created_grant_id,
        'effective_instant', (
            select grant_record.effective_start
            from public.organization_responsibility_grants as grant_record
            where grant_record.id = created_grant_id
        )
    );
end;
$$;

create function public.end_staff_responsibility(
    p_organization_id uuid,
    p_responsibility_grant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    membership_record public.organization_memberships%rowtype;
    source_grant public.organization_responsibility_grants%rowtype;
    target_is_owner boolean;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Organization and capability, re-decided under the Organization lock.
    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    -- 4. Target within the named Organization; Membership then Grant locks.
    select grant_record.membership_id
    into target_membership_id
    from public.organization_responsibility_grants as grant_record
    join public.organization_memberships as membership
      on membership.id = grant_record.membership_id
    where grant_record.id = p_responsibility_grant_id
      and membership.organization_id = p_organization_id;

    if not found then
        raise exception 'Organization Responsibilities unavailable'
            using errcode = '42501';
    end if;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = p_organization_id
    for update;

    select grant_record.*
    into source_grant
    from public.organization_responsibility_grants as grant_record
    where grant_record.id = p_responsibility_grant_id
      and grant_record.membership_id = target_membership_id
    for update;

    -- 5. Protected targets.
    if source_grant.responsibility = 'OWNER' then
        raise exception 'An OWNER Responsibility cannot be ended through Staff'
            using errcode = '23514', hint = 'OWNER_GRANT';
    end if;

    target_is_owner := public.staff_membership_holds_owner(membership_record.id);

    if target_is_owner and membership_record.user_id <> acting_user_id then
        raise exception 'An Owner Membership cannot be changed through Staff'
            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';
    end if;

    if membership_record.user_id = acting_user_id and not target_is_owner then
        raise exception 'Own Responsibilities cannot be changed through Staff'
            using errcode = '23514', hint = 'SELF_MEMBERSHIP';
    end if;

    -- 6. Lifecycle.
    if not (
        membership_record.effective_start <= statement_timestamp()
        and membership_record.effective_end is null
    ) then
        raise exception 'Organization Membership is not current'
            using errcode = '23514', hint = 'MEMBERSHIP_INACTIVE';
    end if;

    if source_grant.effective_end is not null then
        return jsonb_build_object(
            'outcome', 'ALREADY_ENDED',
            'membership_id', membership_record.id,
            'responsibility_grant_id', source_grant.id,
            'effective_end', source_grant.effective_end
        );
    end if;

    -- 7. Rules.
    if not exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = membership_record.id
          and grant_record.id <> source_grant.id
          and grant_record.effective_start <= statement_timestamp()
          and grant_record.effective_end is null
    ) then
        raise exception 'The last current Responsibility is ended through End access'
            using errcode = '23514', hint = 'LAST_RESPONSIBILITY';
    end if;

    if source_grant.responsibility = 'VETERINARIAN'
       and public.membership_supports_current_veterinarian_assignment(membership_record.id) then
        raise exception 'Current Veterinarian Clinic Assignments must be ended first'
            using errcode = '23514', hint = 'VETERINARIAN_ASSIGNMENTS_ACTIVE';
    end if;

    perform public.end_organization_responsibility(source_grant.id);

    return jsonb_build_object(
        'outcome', 'ENDED',
        'membership_id', membership_record.id,
        'responsibility_grant_id', source_grant.id,
        'effective_end', (
            select grant_record.effective_end
            from public.organization_responsibility_grants as grant_record
            where grant_record.id = source_grant.id
        )
    );
end;
$$;

-- ==================================================================
-- 4. Client-safe self Professional Profile (SPEC-VET-001 §13)
-- ==================================================================

create function public.create_my_veterinarian_professional_profile(
    p_registration_identifier text,
    p_issuing_context text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    acting_user_id uuid;
    normalized_registration_identifier text;
    normalized_issuing_context text;
    existing_profile_id uuid;
    existing_credential_id uuid;
    existing_registration_identifier text;
    existing_issuing_context text;
    created_profile_id uuid;
    created_credential_id uuid;
begin
    authenticated_subject_id := auth.uid();

    if authenticated_subject_id is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from auth.users as auth_user
        where auth_user.id = authenticated_subject_id
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'A verified email address is required'
            using errcode = '42501', hint = 'ACCOUNT_VERIFICATION_REQUIRED';
    end if;

    -- The writer's normalization (20260825092836).
    normalized_registration_identifier :=
        btrim(p_registration_identifier, E' \t\n\r\f\013');
    normalized_issuing_context :=
        btrim(p_issuing_context, E' \t\n\r\f\013');

    if normalized_registration_identifier is null
       or normalized_registration_identifier = '' then
        raise exception 'Professional registration identifier must not be blank'
            using errcode = '22023', hint = 'REGISTRATION_IDENTIFIER_REQUIRED';
    end if;

    if normalized_issuing_context is null
       or normalized_issuing_context = '' then
        raise exception 'Professional issuing context must not be blank'
            using errcode = '22023', hint = 'ISSUING_CONTEXT_REQUIRED';
    end if;

    -- One Profile per User: concurrent creations by the same User serialize
    -- here, so the later one observes the committed Profile.
    perform 1
    from public.users as domain_user
    where domain_user.id = acting_user_id
    for update;

    select profile.id,
           credential.id,
           credential.registration_identifier,
           credential.issuing_context
    into existing_profile_id,
         existing_credential_id,
         existing_registration_identifier,
         existing_issuing_context
    from public.veterinarian_professional_profiles as profile
    left join public.veterinarian_professional_credentials as credential
      on credential.professional_profile_id = profile.id
    where profile.user_id = acting_user_id;

    if found then
        if existing_registration_identifier is not distinct from normalized_registration_identifier
           and existing_issuing_context is not distinct from normalized_issuing_context then
            return jsonb_build_object(
                'outcome', 'ALREADY_EXISTS',
                'professional_profile_id', existing_profile_id,
                'professional_credential_id', existing_credential_id
            );
        end if;

        raise exception 'A Veterinarian Professional Profile already exists with different details'
            using errcode = '23514', hint = 'PROFILE_CREDENTIAL_MISMATCH';
    end if;

    select created.professional_profile_id, created.professional_credential_id
    into created_profile_id, created_credential_id
    from public.create_veterinarian_professional_profile(
        normalized_registration_identifier,
        normalized_issuing_context
    ) as created;

    return jsonb_build_object(
        'outcome', 'CREATED',
        'professional_profile_id', created_profile_id,
        'professional_credential_id', created_credential_id
    );
end;
$$;

-- ==================================================================
-- 5. Organization Veterinarian workforce read (SPEC-VET-006)
-- ==================================================================

create function public.get_organization_veterinarian_workforce(p_organization_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
    acting_user_id uuid;
    workforce_result jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- One snapshot and one evaluation instant; the materialized gate precedes
    -- every sensitive projection.
    with evaluation as materialized (
        select statement_timestamp() as instant
    ), authorized_organization as materialized (
        select organization.id
        from public.veterinary_organizations as organization
        where organization.id = p_organization_id
          and public.user_has_organization_capability(
              acting_user_id, p_organization_id, 'ORGANIZATION_GRANT_RESPONSIBILITIES'
          )
    ), current_membership as (
        select membership.id, membership.user_id, membership.effective_start
        from public.organization_memberships as membership
        join authorized_organization as organization
          on organization.id = membership.organization_id
        cross join evaluation
        where membership.effective_start <= evaluation.instant
          and membership.effective_end is null
    ), current_assignment as (
        select assignment.id, assignment.clinic_id, assignment.supporting_membership_id
        from public.veterinarian_clinic_assignments as assignment
        join current_membership
          on current_membership.id = assignment.supporting_membership_id
        join public.clinics as clinic
          on clinic.id = assignment.clinic_id
        join authorized_organization as organization
          on organization.id = clinic.organization_id
        where assignment.effective_end is null
          and public.veterinarian_clinic_assignment_is_current(assignment.id)
    ), listed_membership as (
        select current_membership.*
        from current_membership
        cross join evaluation
        where exists (
                select 1
                from public.organization_responsibility_grants as grant_record
                where grant_record.membership_id = current_membership.id
                  and grant_record.responsibility = 'VETERINARIAN'
                  and grant_record.scope_type = 'ORGANIZATION'
                  and grant_record.effective_start <= evaluation.instant
                  and grant_record.effective_end is null
            )
           or exists (
                select 1
                from current_assignment
                where current_assignment.supporting_membership_id = current_membership.id
            )
    )
    select jsonb_build_object(
        'organization_id', organization.id,
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                'membership_id', listed.id,
                'has_veterinarian_professional_profile', exists (
                    select 1
                    from public.veterinarian_professional_profiles as profile
                    where profile.user_id = listed.user_id
                ),
                'clinic_assignments', coalesce((
                    select jsonb_agg(jsonb_build_object(
                        'veterinarian_clinic_assignment_id', current_assignment.id,
                        'clinic', jsonb_build_object(
                            'clinic_id', current_assignment.clinic_id,
                            'clinic_display_name', clinic_profile.display_name
                        )
                    ) order by current_assignment.clinic_id, current_assignment.id)
                    from current_assignment
                    left join public.clinic_public_profiles as clinic_profile
                      on clinic_profile.clinic_id = current_assignment.clinic_id
                    where current_assignment.supporting_membership_id = listed.id
                ), '[]'::jsonb)
            ) order by listed.effective_start, listed.id)
            from listed_membership as listed
        ), '[]'::jsonb)
    ) into workforce_result
    from authorized_organization as organization;

    if workforce_result is null then
        raise exception 'Organization Veterinarian workforce unavailable' using errcode = '42501';
    end if;
    return workforce_result;
end;
$$;

-- ==================================================================
-- 6. Client-safe Clinic Assignment operations (SPEC-VET-004/005 §13)
-- ==================================================================

create function public.assign_staff_veterinarian_to_clinic(
    p_organization_id uuid,
    p_membership_id uuid,
    p_clinic_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    membership_record public.organization_memberships%rowtype;
    target_profile_id uuid;
    existing_assignment public.veterinarian_clinic_assignments%rowtype;
    created_assignment public.veterinarian_clinic_assignments%rowtype;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Clinic of the Organization and capability, re-decided under the
    -- Organization and Clinic locks.
    if not public.user_manages_veterinarian_assignments_at(
        acting_user_id, p_organization_id, p_clinic_id
    ) then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = p_organization_id
    for update;

    if not public.user_manages_veterinarian_assignments_at(
        acting_user_id, p_organization_id, p_clinic_id
    ) then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    -- 3. Target Membership within the named Organization.
    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = p_organization_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    -- 4. Lifecycle and prerequisites.
    if not (
        membership_record.effective_start <= statement_timestamp()
        and membership_record.effective_end is null
    ) then
        raise exception 'Organization Membership is not current'
            using errcode = '23514', hint = 'MEMBERSHIP_INACTIVE';
    end if;

    if not exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = membership_record.id
          and grant_record.responsibility = 'VETERINARIAN'
          and grant_record.scope_type = 'ORGANIZATION'
          and grant_record.clinic_id is null
          and grant_record.effective_start <= statement_timestamp()
          and grant_record.effective_end is null
    ) then
        raise exception 'A current VETERINARIAN Responsibility is required'
            using errcode = '23514', hint = 'VETERINARIAN_RESPONSIBILITY_REQUIRED';
    end if;

    -- The Profile is derived from the Membership's User, never client input.
    select profile.id
    into target_profile_id
    from public.veterinarian_professional_profiles as profile
    where profile.user_id = membership_record.user_id;

    if not found then
        raise exception 'A Veterinarian Professional Profile is required'
            using errcode = '23514', hint = 'PROFILE_REQUIRED';
    end if;

    -- 5. An equivalent open Assignment already exists: nothing is written.
    select assignment.*
    into existing_assignment
    from public.veterinarian_clinic_assignments as assignment
    where assignment.professional_profile_id = target_profile_id
      and assignment.supporting_membership_id = membership_record.id
      and assignment.clinic_id = p_clinic_id
      and assignment.effective_end is null;

    if found then
        return jsonb_build_object(
            'outcome', 'ALREADY_ASSIGNED',
            'veterinarian_clinic_assignment_id', existing_assignment.id,
            'membership_id', membership_record.id,
            'clinic_id', existing_assignment.clinic_id,
            'effective_start', existing_assignment.effective_start
        );
    end if;

    -- Statement instant, never before the supporting Membership started.
    insert into public.veterinarian_clinic_assignments (
        professional_profile_id,
        supporting_membership_id,
        clinic_id,
        effective_start
    )
    values (
        target_profile_id,
        membership_record.id,
        p_clinic_id,
        greatest(statement_timestamp(), membership_record.effective_start)
    )
    returning * into created_assignment;

    return jsonb_build_object(
        'outcome', 'ASSIGNED',
        'veterinarian_clinic_assignment_id', created_assignment.id,
        'membership_id', membership_record.id,
        'clinic_id', created_assignment.clinic_id,
        'effective_start', created_assignment.effective_start
    );
end;
$$;

create function public.end_staff_veterinarian_clinic_assignment(
    p_organization_id uuid,
    p_clinic_id uuid,
    p_veterinarian_clinic_assignment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    assignment_record public.veterinarian_clinic_assignments%rowtype;
    effective_instant timestamptz;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Clinic of the Organization and capability, re-decided under the
    -- Organization and Clinic locks. No VETERINARIAN Grant is required.
    if not public.user_manages_veterinarian_assignments_at(
        acting_user_id, p_organization_id, p_clinic_id
    ) then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = p_organization_id
    for update;

    if not public.user_manages_veterinarian_assignments_at(
        acting_user_id, p_organization_id, p_clinic_id
    ) then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    -- 3. The Assignment at the named Clinic.
    select assignment.*
    into assignment_record
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_veterinarian_clinic_assignment_id
      and assignment.clinic_id = p_clinic_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment unavailable'
            using errcode = '42501';
    end if;

    -- 4. Lifecycle: an ended Assignment is reported, never rewritten.
    if assignment_record.effective_end is not null then
        return jsonb_build_object(
            'outcome', 'ALREADY_ENDED',
            'veterinarian_clinic_assignment_id', assignment_record.id,
            'effective_end', assignment_record.effective_end
        );
    end if;

    -- Statement instant, never before the Assignment started.
    effective_instant := greatest(statement_timestamp(), assignment_record.effective_start);

    update public.veterinarian_clinic_assignments
    set effective_end = effective_instant
    where id = assignment_record.id;

    return jsonb_build_object(
        'outcome', 'ENDED',
        'veterinarian_clinic_assignment_id', assignment_record.id,
        'effective_end', effective_instant
    );
end;
$$;

-- ==================================================================
-- 7. ACL
-- ==================================================================

revoke all privileges on function public.add_staff_responsibility(uuid, uuid, text, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.add_staff_responsibility(uuid, uuid, text, text, uuid)
to authenticated;

revoke all privileges on function public.replace_staff_responsibility(uuid, uuid, text, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.replace_staff_responsibility(uuid, uuid, text, text, uuid)
to authenticated;

revoke all privileges on function public.end_staff_responsibility(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.end_staff_responsibility(uuid, uuid)
to authenticated;

revoke all privileges on function public.create_my_veterinarian_professional_profile(text, text)
from public, anon, authenticated, service_role;
grant execute on function public.create_my_veterinarian_professional_profile(text, text)
to authenticated;

revoke all privileges on function public.get_organization_veterinarian_workforce(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_organization_veterinarian_workforce(uuid)
to authenticated;

revoke all privileges on function public.assign_staff_veterinarian_to_clinic(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.assign_staff_veterinarian_to_clinic(uuid, uuid, uuid)
to authenticated;

revoke all privileges on function public.end_staff_veterinarian_clinic_assignment(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.end_staff_veterinarian_clinic_assignment(uuid, uuid, uuid)
to authenticated;

-- Generic operations: no client path; service_role keeps trusted
-- compatibility (its grant is left as it was).
revoke all privileges on function public.add_organization_responsibility(uuid, text)
from public, anon, authenticated;
revoke all privileges on function public.add_organization_responsibility(uuid, text, text, uuid)
from public, anon, authenticated;
revoke all privileges on function public.replace_organization_responsibility(uuid, text)
from public, anon, authenticated;
revoke all privileges on function public.replace_organization_responsibility(uuid, text, text, uuid)
from public, anon, authenticated;
revoke all privileges on function public.end_organization_responsibility(uuid)
from public, anon, authenticated;
revoke all privileges on function public.assign_veterinarian_to_clinic(uuid, uuid, uuid)
from public, anon, authenticated;
revoke all privileges on function public.end_veterinarian_clinic_assignment(uuid)
from public, anon, authenticated;
revoke all privileges on function public.create_veterinarian_professional_profile(text, text)
from public, anon, authenticated;

commit;
