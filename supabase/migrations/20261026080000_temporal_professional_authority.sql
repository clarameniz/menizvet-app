-- Cross-cutting professional authority currentness (SPEC-ORG-005 BR-7/25,
-- SPEC-ORG-007 BR-2/5, SPEC-ORG-004 BR-8/13/18, SPEC-ORG-006 section 3,
-- SPEC-ORG-001 BR-3, SPEC-ORG-003 BR-5, SPEC-VET-004 BR-3/18). Separate
-- prerequisite for Staff Slice A.
--
-- One temporal instant per top-level statement, t = statement_timestamp():
--   * evaluation: a Membership/Grant is current at t iff start <= t AND
--     end IS NULL. Scheduled endings are not a Phase 1 workflow; a stored end
--     is terminal, including a structurally possible future-end fixture.
--   * lifecycle writes: establishing, accepting, adding, replacing and ending
--     a Membership/Grant record t as the effective start/end, never earlier
--     than the start of the Membership/Grant/Invitation they extend or
--     supersede (monotonic under Organization-serialized concurrency).
-- A relationship established earlier in a statement is therefore current for
-- the rest of that statement (create-then-act), and a replacement is
-- contiguous at one instant. Previously writes used clock_timestamp(), later
-- than t, so a composite trusted statement could not use what it created.
-- Historical coverage and provenance keep their existing interval rules.
-- No table/data/ACL change, capability mapping change, Entitlement change, or
-- new paid operation. Function attributes, signatures and caller ACLs are
-- preserved (CREATE OR REPLACE); audit timestamps are unchanged.
begin;

create or replace function public.user_has_organization_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'ORGANIZATION'
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where membership.user_id = p_user_id
              and membership.organization_id = p_organization_id
              and membership.effective_start <= statement_timestamp()
              and membership.effective_end is null
              and grant_record.effective_start <= statement_timestamp()
              and grant_record.effective_end is null
              and grant_record.scope_type = 'ORGANIZATION'
              and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
        )
$$;

create or replace function public.user_has_organization_scoped_clinic_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'CLINIC'
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as responsibility_grant
              on responsibility_grant.membership_id = membership.id
            where membership.organization_id = p_organization_id
              and membership.user_id = p_user_id
              and membership.effective_start <= statement_timestamp()
              and membership.effective_end is null
              and responsibility_grant.effective_start <= statement_timestamp()
              and responsibility_grant.effective_end is null
              and responsibility_grant.scope_type = 'ORGANIZATION'
              and responsibility_grant.clinic_id is null
              and (
                (
                  responsibility_grant.responsibility in ('OWNER', 'ADMINISTRATOR')
                  and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                )
                or (
                  responsibility_grant.responsibility = 'RECEPTIONIST'
                  and p_capability in (
                    'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                    'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                    'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                    'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                  )
                )
              )
        )
$$;

create or replace function public.user_has_clinic_scoped_clinic_capability(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'CLINIC'
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as responsibility_grant
                  on responsibility_grant.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_start <= statement_timestamp()
                  and membership.effective_end is null
                  and responsibility_grant.effective_start <= statement_timestamp()
                  and responsibility_grant.effective_end is null
                  and responsibility_grant.scope_type = 'CLINIC'
                  and responsibility_grant.clinic_id = p_clinic_id
                  and (
                    (
                      responsibility_grant.responsibility = 'ADMINISTRATOR'
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.responsibility = 'RECEPTIONIST'
                      and p_capability in (
                        'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                        'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                        'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                      )
                    )
                  )
            )
            or (
                p_capability in (
                    'APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE',
                    'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
                )
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as responsibility_grant
                      on responsibility_grant.membership_id = membership.id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.supporting_membership_id = membership.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    join public.veterinarian_professional_profiles as profile
                      on profile.id = clinic_assignment.professional_profile_id
                     and profile.user_id = p_user_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_start <= statement_timestamp()
                      and membership.effective_end is null
                      and responsibility_grant.effective_start <= statement_timestamp()
                      and responsibility_grant.effective_end is null
                      and responsibility_grant.membership_id = membership.id
                      and responsibility_grant.responsibility = 'VETERINARIAN'
                      and responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        )
$$;

create or replace function public.veterinarian_clinic_assignment_is_current(
    p_assignment_id uuid
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
        join public.veterinarian_professional_profiles as profile
          on profile.id = assignment.professional_profile_id
        join public.organization_memberships as membership
          on membership.id = assignment.supporting_membership_id
        join public.clinics as clinic
          on clinic.id = assignment.clinic_id
        where assignment.id = p_assignment_id
          and assignment.effective_end is null
          and membership.effective_start <= statement_timestamp()
          and membership.effective_end is null
          and profile.user_id = membership.user_id
          and clinic.organization_id = membership.organization_id
    )
$$;

create or replace function public.find_current_veterinarian_context_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text,
    p_entitlement_identifier text default null
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare resolved_organization_id uuid;
begin
    select clinic.organization_id into resolved_organization_id
    from public.clinics as clinic where clinic.id = p_clinic_id;
    if not found then return; end if;
    perform 1 from public.veterinary_organizations as organization_record
    where organization_record.id = resolved_organization_id for update;
    perform 1 from public.clinics as clinic
    where clinic.id = p_clinic_id and clinic.organization_id = resolved_organization_id for update;
    return query
    select resolved_organization_id, membership.id, responsibility_grant.id, clinic_assignment.id
    from public.organization_memberships as membership
    join public.organization_responsibility_grants as responsibility_grant
      on responsibility_grant.membership_id = membership.id
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.supporting_membership_id = membership.id
     and clinic_assignment.clinic_id = p_clinic_id
    join public.veterinarian_professional_profiles as professional_profile
      on professional_profile.id = clinic_assignment.professional_profile_id
     and professional_profile.user_id = p_user_id
    where membership.organization_id = resolved_organization_id
      and membership.user_id = p_user_id and membership.effective_start <= statement_timestamp()
      and membership.effective_end is null
      and responsibility_grant.responsibility = 'VETERINARIAN'
      and responsibility_grant.scope_type = 'ORGANIZATION'
      and responsibility_grant.clinic_id is null
      and responsibility_grant.effective_start <= statement_timestamp()
      and responsibility_grant.effective_end is null
      and clinic_assignment.effective_end is null
      and public.user_has_clinic_capability(p_user_id, p_clinic_id, p_capability)
      and (
        p_entitlement_identifier is null
        or public.organization_has_professional_entitlement(
            resolved_organization_id, p_entitlement_identifier
        )
      )
    for update of membership, responsibility_grant, clinic_assignment;
end;
$$;

create or replace function public.resolve_current_veterinarian_context_after_lock(
    p_user_id uuid,
    p_clinic_id uuid,
    p_capability text,
    p_entitlement_identifier text default null
)
returns table (
    organization_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_organization_id uuid;
    resolved_membership_id uuid;
    resolved_responsibility_grant_id uuid;
    resolved_clinic_assignment_id uuid;
begin
    select clinic.organization_id
    into resolved_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization_record
    where organization_record.id = resolved_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = resolved_organization_id
    for update;

    select membership.id,
           responsibility_grant.id,
           clinic_assignment.id
    into resolved_membership_id,
         resolved_responsibility_grant_id,
         resolved_clinic_assignment_id
    from public.organization_memberships as membership
    join public.organization_responsibility_grants as responsibility_grant
      on responsibility_grant.membership_id = membership.id
    join public.veterinarian_clinic_assignments as clinic_assignment
      on clinic_assignment.supporting_membership_id = membership.id
     and clinic_assignment.clinic_id = p_clinic_id
    join public.veterinarian_professional_profiles as professional_profile
      on professional_profile.id = clinic_assignment.professional_profile_id
    where membership.organization_id = resolved_organization_id
      and membership.user_id = p_user_id
      and membership.effective_start <= statement_timestamp()
      and membership.effective_end is null
      and responsibility_grant.responsibility = 'VETERINARIAN'
      and responsibility_grant.scope_type = 'ORGANIZATION'
      and responsibility_grant.clinic_id is null
      and responsibility_grant.effective_start <= statement_timestamp()
      and responsibility_grant.effective_end is null
      and clinic_assignment.effective_end is null
      -- Current Profile ownership is an independent current authorization
      -- requirement; it is not used as the historical VCA/User proof.
      and professional_profile.user_id = p_user_id
    for update of membership, responsibility_grant, clinic_assignment;

    if not found then
        raise exception 'Current exact-Clinic Veterinarian professional context is required'
            using errcode = '42501';
    end if;

    if not public.user_has_clinic_capability(
        p_user_id,
        p_clinic_id,
        p_capability
    ) then
        raise exception 'Applicable clinical or Appointment capability is required'
            using errcode = '42501';
    end if;

    if p_entitlement_identifier is not null
       and not public.organization_has_professional_entitlement(
           resolved_organization_id,
           p_entitlement_identifier
       ) then
        raise exception 'Applicable professional Entitlement is required'
            using errcode = '42501';
    end if;

    return query
    select resolved_organization_id,
           resolved_membership_id,
           resolved_responsibility_grant_id,
           resolved_clinic_assignment_id;
end;
$$;

create or replace function public.get_my_professional_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    context_result jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    with current_membership as (
        select
            membership.id as membership_id,
            membership.organization_id,
            organization.display_name as organization_display_name
        from public.organization_memberships as membership
        join public.veterinary_organizations as organization
          on organization.id = membership.organization_id
        where membership.user_id = acting_user_id
          and membership.effective_start <= statement_timestamp()
          and membership.effective_end is null
    ),
    current_grant as (
        select
            current_membership.membership_id,
            responsibility_grant.responsibility,
            responsibility_grant.scope_type,
            responsibility_grant.clinic_id
        from current_membership
        join public.organization_responsibility_grants as responsibility_grant
          on responsibility_grant.membership_id = current_membership.membership_id
        where responsibility_grant.effective_start <= statement_timestamp()
          and responsibility_grant.effective_end is null
    ),
    current_assignment as (
        select
            current_membership.membership_id,
            clinic_assignment.id as assignment_id,
            clinic_assignment.clinic_id
        from current_membership
        join public.veterinarian_clinic_assignments as clinic_assignment
          on clinic_assignment.supporting_membership_id = current_membership.membership_id
        join public.veterinarian_professional_profiles as profile
          on profile.id = clinic_assignment.professional_profile_id
        where profile.user_id = acting_user_id
          and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
    ),
    organization_scoped_capability as (
        select
            current_membership.membership_id,
            catalog_entry.capability
        from current_membership
        cross join public.professional_capability_catalog() as catalog_entry
        where (
                catalog_entry.capability_context = 'ORGANIZATION'
                and public.user_has_organization_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )
              )
           or (
                catalog_entry.capability_context = 'CLINIC'
                and public.user_has_organization_scoped_clinic_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )
              )
    ),
    candidate_clinic as (
        select current_grant.membership_id, current_grant.clinic_id
        from current_grant
        where current_grant.scope_type = 'CLINIC'
        union
        select current_assignment.membership_id, current_assignment.clinic_id
        from current_assignment
    ),
    clinic_scoped_capability as (
        select
            candidate_clinic.membership_id,
            candidate_clinic.clinic_id,
            catalog_entry.capability
        from candidate_clinic
        cross join public.professional_capability_catalog() as catalog_entry
        where catalog_entry.capability_context = 'CLINIC'
          and public.user_has_clinic_scoped_clinic_capability(
              acting_user_id, candidate_clinic.clinic_id, catalog_entry.capability
          )
          and not exists (
              select 1
              from organization_scoped_capability
              where organization_scoped_capability.membership_id = candidate_clinic.membership_id
                and organization_scoped_capability.capability = catalog_entry.capability
          )
    ),
    organization_entry as (
        select
            current_membership.organization_display_name,
            current_membership.organization_id,
            jsonb_build_object(
                'membership_id', current_membership.membership_id,
                'organization_id', current_membership.organization_id,
                'organization_display_name', current_membership.organization_display_name,
                'responsibilities', coalesce((
                    select jsonb_agg(
                        jsonb_build_object(
                            'responsibility', current_grant.responsibility,
                            'scope_type', current_grant.scope_type,
                            'clinic', case
                                when current_grant.clinic_id is null then null
                                else jsonb_build_object(
                                    'clinic_id', current_grant.clinic_id,
                                    'clinic_display_name', public_profile.display_name
                                )
                            end
                        )
                        order by current_grant.responsibility,
                                 current_grant.scope_type,
                                 current_grant.clinic_id
                    )
                    from current_grant
                    left join public.clinic_public_profiles as public_profile
                      on public_profile.clinic_id = current_grant.clinic_id
                    where current_grant.membership_id = current_membership.membership_id
                ), '[]'::jsonb),
                'capabilities', coalesce((
                    select jsonb_agg(capability_entry.entry order by capability_entry.sort_scope, capability_entry.sort_clinic, capability_entry.capability)
                    from (
                        select
                            jsonb_build_object(
                                'capability', organization_scoped_capability.capability,
                                'scope_type', 'ORGANIZATION',
                                'clinic', null
                            ) as entry,
                            0 as sort_scope,
                            null::uuid as sort_clinic,
                            organization_scoped_capability.capability
                        from organization_scoped_capability
                        where organization_scoped_capability.membership_id = current_membership.membership_id
                        union all
                        select
                            jsonb_build_object(
                                'capability', clinic_scoped_capability.capability,
                                'scope_type', 'CLINIC',
                                'clinic', jsonb_build_object(
                                    'clinic_id', clinic_scoped_capability.clinic_id,
                                    'clinic_display_name', public_profile.display_name
                                )
                            ),
                            1,
                            clinic_scoped_capability.clinic_id,
                            clinic_scoped_capability.capability
                        from clinic_scoped_capability
                        left join public.clinic_public_profiles as public_profile
                          on public_profile.clinic_id = clinic_scoped_capability.clinic_id
                        where clinic_scoped_capability.membership_id = current_membership.membership_id
                    ) as capability_entry
                ), '[]'::jsonb),
                'clinic_assignments', coalesce((
                    select jsonb_agg(
                        jsonb_build_object(
                            'veterinarian_clinic_assignment_id', current_assignment.assignment_id,
                            'clinic', jsonb_build_object(
                                'clinic_id', current_assignment.clinic_id,
                                'clinic_display_name', public_profile.display_name
                            )
                        )
                        order by current_assignment.clinic_id, current_assignment.assignment_id
                    )
                    from current_assignment
                    left join public.clinic_public_profiles as public_profile
                      on public_profile.clinic_id = current_assignment.clinic_id
                    where current_assignment.membership_id = current_membership.membership_id
                ), '[]'::jsonb),
                'entitlements', jsonb_build_object(
                    'APPOINTMENT_MANAGEMENT',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'APPOINTMENT_MANAGEMENT'
                    ),
                    'PROFESSIONAL_SCHEDULING',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'PROFESSIONAL_SCHEDULING'
                    ),
                    'CLINICAL_CARE',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'CLINICAL_CARE'
                    ),
                    'CLINICAL_DOCUMENTATION',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'CLINICAL_DOCUMENTATION'
                    )
                )
            ) as entry
        from current_membership
    )
    select jsonb_build_object(
        'has_veterinarian_professional_profile', exists (
            select 1
            from public.veterinarian_professional_profiles as profile
            where profile.user_id = acting_user_id
        ),
        'organizations', coalesce((
            select jsonb_agg(
                organization_entry.entry
                order by organization_entry.organization_display_name,
                         organization_entry.organization_id
            )
            from organization_entry
        ), '[]'::jsonb)
    )
    into context_result;

    return context_result;
end;
$$;

create or replace function public.user_has_continuous_clinic_reschedule_authority_since(
    p_user_id uuid,
    p_clinic_id uuid,
    p_since timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    with recursive authority_intervals as (
        select
            greatest(membership.effective_start, grant_record.effective_start) as interval_start,
            least(
                coalesce(membership.effective_end, 'infinity'::timestamptz),
                coalesce(grant_record.effective_end, 'infinity'::timestamptz)
            ) as interval_end
        from public.clinics as clinic
        join public.organization_memberships as membership
          on membership.organization_id = clinic.organization_id
        join public.organization_responsibility_grants as grant_record
          on grant_record.membership_id = membership.id
        where clinic.id = p_clinic_id
          and membership.user_id = p_user_id
          and (
              (
                  grant_record.scope_type = 'ORGANIZATION'
                  and grant_record.clinic_id is null
                  and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR', 'RECEPTIONIST')
              )
              or
              (
                  grant_record.scope_type = 'CLINIC'
                  and grant_record.clinic_id = p_clinic_id
                  and grant_record.responsibility in ('ADMINISTRATOR', 'RECEPTIONIST')
              )
          )
          and greatest(membership.effective_start, grant_record.effective_start)
              <= least(
                  coalesce(membership.effective_end, 'infinity'::timestamptz),
                  coalesce(grant_record.effective_end, 'infinity'::timestamptz)
              )
    ),
    continuous_coverage (covered_until) as (
        select authority_period.interval_end
        from authority_intervals as authority_period
        where authority_period.interval_start <= p_since
          and authority_period.interval_end >= p_since

        union

        select authority_period.interval_end
        from continuous_coverage as coverage
        join authority_intervals as authority_period
          on authority_period.interval_start <= coverage.covered_until
         and authority_period.interval_end > coverage.covered_until
    )
    -- Historical interval coverage does not itself establish current authority.
    select public.user_has_clinic_capability(
        p_user_id, p_clinic_id, 'APPOINTMENT_RESCHEDULE'
    ) and exists (
        select 1
        from continuous_coverage as coverage
        where coverage.covered_until = 'infinity'::timestamptz
    )
$$;

-- ==================================================================
-- Lifecycle writers: effective start/end use the statement instant above
-- (monotonic clamp). Bodies otherwise unchanged from their latest
-- definitions in 20260825112945/20260825150316.
-- ==================================================================

create or replace function public.create_veterinary_organization(
    p_display_name text
)
returns table (
    organization_id uuid,
    membership_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    domain_user_id uuid;
    normalized_display_name text;
    effective_instant timestamptz;
    created_organization_id uuid;
    created_membership_id uuid;
begin
    authenticated_subject_id := auth.uid();

    if authenticated_subject_id is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    domain_user_id := public.current_domain_user_id();

    if domain_user_id is null then
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
            using errcode = '42501';
    end if;

    normalized_display_name := btrim(p_display_name, E' \t\n\r\f\013');

    if normalized_display_name is null or normalized_display_name = '' then
        raise exception 'Veterinary Organization display name must not be blank'
            using errcode = '22023';
    end if;

    -- Establishment instant (statement instant shared with authority evaluation).
    effective_instant := statement_timestamp();

    insert into public.veterinary_organizations (display_name)
    values (normalized_display_name)
    returning id into created_organization_id;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start
    )
    values (
        created_organization_id,
        domain_user_id,
        effective_instant
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        effective_start,
        granted_by_user_id
    )
    values (
        created_membership_id,
        'OWNER',
        'ORGANIZATION',
        effective_instant,
        domain_user_id
    );

    return query
    select created_organization_id, created_membership_id;
end;
$$;

create or replace function public.accept_organization_invitation(
    p_accepting_user_id uuid,
    p_invitation_id uuid,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_organization_id uuid;
    invitation_record public.organization_invitations%rowtype;
    effective_instant timestamptz;
    created_membership_id uuid;
begin
    if p_accepting_user_id is null then
        raise exception 'A trusted accepting domain User is required'
            using errcode = '28000';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Organization Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = p_accepting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The accepting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    select invitation.organization_id
    into invitation_organization_id
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = invitation_organization_id
    for update;

    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    -- One acceptance instant decides expiry and starts the Membership and
    -- every Grant (SPEC-ORG-003 BR-5); never before the Invitation existed.
    effective_instant := greatest(statement_timestamp(), invitation_record.created_at);

    if effective_instant >= invitation_record.expires_at then
        raise exception 'Organization Invitation has expired'
            using errcode = '23514';
    end if;

    if invitation_record.revoked_at is not null
       or invitation_record.rejected_at is not null then
        raise exception 'Organization Invitation is no longer pending'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.originating_invitation_id = p_invitation_id
    ) then
        raise exception 'Organization Invitation has already been accepted'
            using errcode = '23505';
    end if;

    if invitation_record.acceptance_secret_digest is null
       or invitation_record.acceptance_secret_digest is distinct from
           p_acceptance_secret_digest then
        raise exception 'Organization Invitation recipient proof is invalid'
            using errcode = '42501';
    end if;

    if invitation_record.recipient_user_id is not null
       and invitation_record.recipient_user_id <> p_accepting_user_id then
        raise exception 'Organization Invitation is bound to another User'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.organization_id = invitation_record.organization_id
          and membership.user_id = p_accepting_user_id
          and membership.effective_end is null
    ) then
        raise exception 'User already has an active Organization Membership'
            using errcode = '23505';
    end if;

    if not exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
    ) or exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        left join public.clinics as clinic
          on clinic.id = intended.clinic_id
        where intended.invitation_id = p_invitation_id
          and (
              intended.responsibility not in (
                  'ADMINISTRATOR',
                  'RECEPTIONIST',
                  'VETERINARIAN'
              )
              or (
                  intended.scope_type = 'ORGANIZATION'
                  and intended.clinic_id is not null
              )
              or (
                  intended.scope_type = 'CLINIC'
                  and (
                      intended.clinic_id is null
                      or intended.responsibility not in (
                          'ADMINISTRATOR',
                          'RECEPTIONIST'
                      )
                      or clinic.organization_id is distinct from
                          invitation_record.organization_id
                  )
              )
              or intended.scope_type not in ('ORGANIZATION', 'CLINIC')
          )
    ) then
        raise exception 'Organization Invitation contains invalid responsibilities'
            using errcode = '23514';
    end if;

    perform 1
    from public.clinics as clinic
    join public.organization_invitation_responsibilities as intended
      on intended.clinic_id = clinic.id
    where intended.invitation_id = p_invitation_id
    order by clinic.id
    for update of clinic;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start,
        originating_invitation_id
    )
    values (
        invitation_record.organization_id,
        p_accepting_user_id,
        effective_instant,
        p_invitation_id
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id,
        originating_invitation_responsibility_id
    )
    select
        created_membership_id,
        intended.responsibility,
        intended.scope_type,
        intended.clinic_id,
        effective_instant,
        invitation_record.inviting_user_id,
        intended.id
    from public.organization_invitation_responsibilities as intended
    where intended.invitation_id = p_invitation_id;

    update public.organization_invitations
    set acceptance_secret_digest = null
    where id = p_invitation_id;

    return created_membership_id;
end;
$$;

create or replace function public.add_organization_responsibility(
    p_membership_id uuid,
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    effective_instant timestamptz;
    created_grant_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_responsibility is null
       or p_scope_type is null
       or not (
           (
               p_scope_type = 'ORGANIZATION'
               and p_clinic_id is null
               and p_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST',
                   'VETERINARIAN'
               )
           )
           or
           (
               p_scope_type = 'CLINIC'
               and p_clinic_id is not null
               and p_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST'
               )
           )
       ) then
        raise exception 'Unsupported Organization responsibility scope'
            using errcode = '22023';
    end if;

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if p_scope_type = 'CLINIC' then
        perform 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = target_organization_id
        for update;

        if not found then
            raise exception 'Clinic-scoped responsibility requires a Clinic in the Membership Organization'
                using errcode = '23514';
        end if;
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and grant_record.responsibility = p_responsibility
          and grant_record.scope_type = p_scope_type
          and grant_record.clinic_id is not distinct from p_clinic_id
          and grant_record.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    -- Statement instant, never before the Membership start it extends.
    effective_instant := greatest(statement_timestamp(), membership_record.effective_start);

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id
    )
    values (
        p_membership_id,
        p_responsibility,
        p_scope_type,
        p_clinic_id,
        effective_instant,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

create or replace function public.replace_organization_responsibility(
    p_grant_id uuid,
    p_new_responsibility text,
    p_new_scope_type text,
    p_new_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    grant_record public.organization_responsibility_grants%rowtype;
    effective_instant timestamptz;
    created_grant_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_new_responsibility is null
       or p_new_scope_type is null
       or not (
           (
               p_new_scope_type = 'ORGANIZATION'
               and p_new_clinic_id is null
               and p_new_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST',
                   'VETERINARIAN'
               )
           )
           or
           (
               p_new_scope_type = 'CLINIC'
               and p_new_clinic_id is not null
               and p_new_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST'
               )
           )
       ) then
        raise exception 'Unsupported replacement Organization responsibility scope'
            using errcode = '22023';
    end if;

    select source_grant.membership_id, membership.organization_id
    into target_membership_id, target_organization_id
    from public.organization_responsibility_grants as source_grant
    join public.organization_memberships as membership
      on membership.id = source_grant.membership_id
    where source_grant.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = target_organization_id
    for update;

    select current_grant.*
    into grant_record
    from public.organization_responsibility_grants as current_grant
    where current_grant.id = p_grant_id
      and current_grant.membership_id = target_membership_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if grant_record.effective_end is not null then
        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514';
    end if;

    if grant_record.responsibility = 'OWNER' then
        raise exception 'OWNER cannot be replaced through ordinary responsibility management'
            using errcode = '42501';
    end if;

    if grant_record.responsibility = p_new_responsibility
       and grant_record.scope_type = p_new_scope_type
       and grant_record.clinic_id is not distinct from p_new_clinic_id then
        raise exception 'No-op Organization responsibility replacement is not allowed'
            using errcode = '22023';
    end if;

    if p_new_scope_type = 'CLINIC' then
        perform 1
        from public.clinics as clinic
        where clinic.id = p_new_clinic_id
          and clinic.organization_id = target_organization_id
        for update;

        if not found then
            raise exception 'Clinic-scoped responsibility requires a Clinic in the Membership Organization'
                using errcode = '23514';
        end if;
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as equivalent_grant
        where equivalent_grant.membership_id = target_membership_id
          and equivalent_grant.responsibility = p_new_responsibility
          and equivalent_grant.scope_type = p_new_scope_type
          and equivalent_grant.clinic_id is not distinct from p_new_clinic_id
          and equivalent_grant.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    -- One instant ends the old Grant and starts its replacement; never before
    -- the Membership or superseded Grant started.
    effective_instant := greatest(
        statement_timestamp(),
        membership_record.effective_start,
        grant_record.effective_start
    );

    update public.organization_responsibility_grants
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where id = p_grant_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id
    )
    values (
        target_membership_id,
        p_new_responsibility,
        p_new_scope_type,
        p_new_clinic_id,
        effective_instant,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

create or replace function public.end_organization_responsibility(
    p_grant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    grant_record public.organization_responsibility_grants%rowtype;
    effective_instant timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select source_grant.membership_id, membership.organization_id
    into target_membership_id, target_organization_id
    from public.organization_responsibility_grants as source_grant
    join public.organization_memberships as membership
      on membership.id = source_grant.membership_id
    where source_grant.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = target_organization_id
    for update;

    select current_grant.*
    into grant_record
    from public.organization_responsibility_grants as current_grant
    where current_grant.id = p_grant_id
      and current_grant.membership_id = target_membership_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if grant_record.effective_end is not null then
        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514';
    end if;

    if grant_record.responsibility = 'OWNER' then
        raise exception 'OWNER cannot be removed through ordinary responsibility management'
            using errcode = '42501';
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    -- Statement instant, never before the Grant started.
    effective_instant := greatest(statement_timestamp(), grant_record.effective_start);

    update public.organization_responsibility_grants
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where id = p_grant_id;
end;
$$;

create or replace function public.end_organization_membership(
    p_membership_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    effective_instant timestamptz;
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

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
    end if;

    if membership_record.effective_end is not null then
        raise exception 'Organization Membership has already ended'
            using errcode = '23514';
    end if;

    if membership_record.user_id <> acting_user_id
       and not public.user_has_organization_capability(
           acting_user_id,
           target_organization_id,
           'ORGANIZATION_END_MEMBERSHIPS'
       ) then
        raise exception 'Organization Membership termination capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.organization_responsibility_grants as grant_record
    where grant_record.membership_id = p_membership_id
      and grant_record.effective_end is null
    order by grant_record.id
    for update;

    if exists (
        select 1
        from public.organization_responsibility_grants as target_owner
        where target_owner.membership_id = p_membership_id
          and target_owner.effective_end is null
          and target_owner.responsibility = 'OWNER'
          and target_owner.scope_type = 'ORGANIZATION'
    ) and not exists (
        select 1
        from public.organization_memberships as other_membership
        join public.organization_responsibility_grants as other_owner
          on other_owner.membership_id = other_membership.id
        where other_membership.organization_id = target_organization_id
          and other_membership.id <> p_membership_id
          and other_membership.effective_end is null
          and other_owner.effective_end is null
          and other_owner.responsibility = 'OWNER'
          and other_owner.scope_type = 'ORGANIZATION'
    ) then
        raise exception 'The sole active Organization Owner Membership cannot end'
            using errcode = '23514';
    end if;

    -- One instant ends every active Grant and the Membership (BR-18); never
    -- before the Membership or any of those Grants started.
    effective_instant := greatest(
        statement_timestamp(),
        membership_record.effective_start,
        (
            select max(grant_record.effective_start)
            from public.organization_responsibility_grants as grant_record
            where grant_record.membership_id = p_membership_id
              and grant_record.effective_end is null
        )
    );

    update public.organization_responsibility_grants
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where membership_id = p_membership_id
      and effective_end is null;

    update public.organization_memberships
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where id = p_membership_id;
end;
$$;

commit;
