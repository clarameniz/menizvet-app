-- Staff access lifecycle Phase 1, Slice B2 (SPEC-ORG-003 §10–§13, BR-18–BR-25;
-- REQ-ORG-002/003/004/005).
--
-- Two authenticated-only bearer-secret operations. The client supplies only the
-- Invitation reference and the plaintext secret from the email link; the
-- accepting User comes from auth.uid(), every responsibility/scope/Clinic and
-- the Organization come from the stored Invitation, and the secret is hashed
-- here (SHA-256 of the exact UTF-8 string, the digest the Communications Edge
-- stored at creation) and compared with the stored digest. Nothing decrypts the
-- delivery envelope, nothing calls the Communications Edge, and the Auth email
-- is never used as proof.
--
--   preview_organization_invitation(id, secret) returns jsonb  (STABLE, no lock)
--     1 authentication -> 2 same-User provenance (ACCEPTED_BY_YOU) -> 3 proof
--     (uniform 42501 "Invitation unavailable") -> 4 lifecycle at one instant.
--     No confirmed email required (BR-22).
--   accept_my_organization_invitation(id, secret) returns jsonb
--     1 authentication + coherent domain User (28000) -> 2 confirmed email
--     (42501, hint ACCOUNT_VERIFICATION_REQUIRED) -> 3 Organization ->
--     Invitation lock (unknown = uniform) -> 4 same-User provenance
--     (ALREADY_ACCEPTED, creates nothing) -> 5 proof (uniform) -> 6 lifecycle
--     (nothing written) -> 7 Clinics in id order, Membership + exactly the
--     intended Grants at one effective start, digest erased, atomically.
--
-- Post-proof lifecycle precedence (both operations): revoked, rejected,
-- expired, bound to another User, responsibilities no longer valid, caller
-- already an active Member. Recorded terminal facts precede elapsed time,
-- matching revoke_organization_invitation (SPEC-ORG-010).
--
-- The trusted service-role accept_organization_invitation keeps its contract,
-- error outcomes and ACL (no client role may execute it, BR-19); it now shares
-- the responsibility-validity predicate and the Membership/Grant/digest writer
-- with the authenticated operation so the two cannot drift.
--
-- No table, column, constraint, capability, Communication type, or backfill.
-- Acceptance creates no Communication (BR-23).
begin;

-- ---------------------------------------------------------------------------
-- Shared private internals
-- ---------------------------------------------------------------------------

-- Every intended responsibility is still valid for assignment in the invited
-- Organization (SPEC-ORG-003 §5 "Responsibility is no longer valid").
create function public.organization_invitation_responsibilities_are_acceptable(
    p_invitation_id uuid,
    p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
    ) and not exists (
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
                      or clinic.organization_id is distinct from p_organization_id
                  )
              )
              or intended.scope_type not in ('ORGANIZATION', 'CLINIC')
          )
    )
$$;

revoke all privileges
on function public.organization_invitation_responsibilities_are_acceptable(uuid, uuid)
from public, anon, authenticated, service_role;

-- Caller holds the Organization and Invitation locks and has decided every
-- precondition. One effective start for the Membership and every Grant
-- (SPEC-ORG-003 BR-5, BR-24); Grants keep their Invitation origin and inviting
-- User; the digest is erased in the same transaction.
create function public.establish_membership_from_organization_invitation(
    p_invitation_id uuid,
    p_organization_id uuid,
    p_inviting_user_id uuid,
    p_accepting_user_id uuid,
    p_effective_instant timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    created_membership_id uuid;
begin
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
        p_organization_id,
        p_accepting_user_id,
        p_effective_instant,
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
        p_effective_instant,
        p_inviting_user_id,
        intended.id
    from public.organization_invitation_responsibilities as intended
    where intended.invitation_id = p_invitation_id;

    update public.organization_invitations
    set acceptance_secret_digest = null
    where id = p_invitation_id;

    return created_membership_id;
end;
$$;

revoke all privileges
on function public.establish_membership_from_organization_invitation(uuid, uuid, uuid, uuid, timestamptz)
from public, anon, authenticated, service_role;

-- SPEC-ORG-003 §10: the normalized recipient address with its local part
-- reduced to its first character followed by `***`, keeping the full domain.
-- An address without a usable local part is fully masked.
create function public.mask_organization_invitation_recipient(
    p_normalized_email text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
    select case
        when p_normalized_email is null then null
        when p_normalized_email !~ '^[^@]+@' then '***'
        else left(p_normalized_email, 1) || '***@'
            || substring(p_normalized_email from '@([^@]*)$')
    end
$$;

revoke all privileges
on function public.mask_organization_invitation_recipient(text)
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Trusted service-role command: unchanged contract, shared internals
-- ---------------------------------------------------------------------------

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

    if not public.organization_invitation_responsibilities_are_acceptable(
        p_invitation_id, invitation_record.organization_id
    ) then
        raise exception 'Organization Invitation contains invalid responsibilities'
            using errcode = '23514';
    end if;

    return public.establish_membership_from_organization_invitation(
        p_invitation_id,
        invitation_record.organization_id,
        invitation_record.inviting_user_id,
        p_accepting_user_id,
        effective_instant
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- Authenticated preview (SPEC-ORG-003 §10)
-- ---------------------------------------------------------------------------

create function public.preview_organization_invitation(
    p_invitation_id uuid,
    p_acceptance_secret text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    invitation_record public.organization_invitations%rowtype;
    evaluation_instant timestamptz;
    preview_state text;
begin
    -- 1. Authentication.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if found and exists (
        -- 2. Same-User provenance (BR-21): the erased digest cannot re-prove.
        select 1
        from public.organization_memberships as accepted
        where accepted.originating_invitation_id = p_invitation_id
          and accepted.user_id = acting_user_id
          and accepted.effective_end is null
    ) then
        preview_state := 'ACCEPTED_BY_YOU';
    elsif not found
       or invitation_record.acceptance_secret_digest is null
       or p_acceptance_secret is null
       or sha256(convert_to(p_acceptance_secret, 'UTF8'))
           is distinct from invitation_record.acceptance_secret_digest then
        -- 3. Proof (BR-18, BR-20): one outcome for every unproven case.
        raise exception 'Invitation unavailable'
            using errcode = '42501';
    else
        -- 4. Lifecycle at one instant of backend time.
        evaluation_instant := greatest(statement_timestamp(), invitation_record.created_at);

        if invitation_record.revoked_at is not null then
            preview_state := 'REVOKED';
        elsif invitation_record.rejected_at is not null then
            preview_state := 'UNAVAILABLE';
        elsif evaluation_instant >= invitation_record.expires_at then
            preview_state := 'EXPIRED';
        elsif invitation_record.recipient_user_id is not null
              and invitation_record.recipient_user_id <> acting_user_id then
            preview_state := 'UNAVAILABLE';
        elsif not public.organization_invitation_responsibilities_are_acceptable(
            p_invitation_id, invitation_record.organization_id
        ) then
            preview_state := 'UNAVAILABLE';
        elsif exists (
            select 1
            from public.organization_memberships as membership
            where membership.organization_id = invitation_record.organization_id
              and membership.user_id = acting_user_id
              and membership.effective_end is null
        ) then
            preview_state := 'ALREADY_MEMBER';
        else
            preview_state := 'PENDING';
        end if;
    end if;

    if preview_state = 'UNAVAILABLE' then
        return jsonb_build_object(
            'invitation_id', invitation_record.id,
            'state', preview_state,
            'organization_display_name', null,
            'responsibilities', '[]'::jsonb,
            'masked_recipient_email', null,
            'invited_email_matches_current_account', null,
            'expires_at', null
        );
    end if;

    return jsonb_build_object(
        'invitation_id', invitation_record.id,
        'state', preview_state,
        'organization_display_name', (
            select organization.display_name
            from public.veterinary_organizations as organization
            where organization.id = invitation_record.organization_id
        ),
        'responsibilities', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'responsibility', intended.responsibility,
                    'scope_type', intended.scope_type,
                    'clinic', case
                        when intended.clinic_id is null then null
                        else jsonb_build_object(
                            'clinic_id', intended.clinic_id,
                            'clinic_display_name', public_profile.display_name
                        )
                    end
                )
                order by intended.responsibility, intended.scope_type, intended.clinic_id
            )
            from public.organization_invitation_responsibilities as intended
            left join public.clinic_public_profiles as public_profile
              on public_profile.clinic_id = intended.clinic_id
            where intended.invitation_id = invitation_record.id
        ), '[]'::jsonb),
        'masked_recipient_email', public.mask_organization_invitation_recipient(
            invitation_record.recipient_email_normalized
        ),
        -- Only the boolean; the caller's own account address is never echoed.
        'invited_email_matches_current_account', coalesce((
            select lower(btrim(auth_user.email, E' \t\n\r\f\013'))
                = invitation_record.recipient_email_normalized
            from auth.users as auth_user
            where auth_user.id = auth.uid()
        ), false),
        'expires_at', invitation_record.expires_at
    );
end;
$$;

revoke all privileges
on function public.preview_organization_invitation(uuid, text)
from public, anon, authenticated, service_role;
grant execute
on function public.preview_organization_invitation(uuid, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- Authenticated acceptance (SPEC-ORG-003 §11)
-- ---------------------------------------------------------------------------

create function public.accept_my_organization_invitation(
    p_invitation_id uuid,
    p_acceptance_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    acting_user_id uuid;
    target_organization_id uuid;
    invitation_record public.organization_invitations%rowtype;
    accepted_membership_id uuid;
    effective_instant timestamptz;
begin
    -- 1. Authentication and a coherent domain User.
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

    -- 2. Confirmed email on the authenticated account (BR-18, BR-20).
    if not exists (
        select 1
        from auth.users as auth_user
        where auth_user.id = authenticated_subject_id
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'A verified email address is required'
            using errcode = '42501', hint = 'ACCOUNT_VERIFICATION_REQUIRED';
    end if;

    -- 3. Organization -> Invitation (BR-24, the order of revocation).
    select invitation.organization_id
    into target_organization_id
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if target_organization_id is null then
        raise exception 'Invitation unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
      and invitation.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Invitation unavailable'
            using errcode = '42501';
    end if;

    -- 4. Same-User provenance (BR-21): a lost response resolves as success,
    -- for this User only, while the resulting Membership is active.
    select accepted.id
    into accepted_membership_id
    from public.organization_memberships as accepted
    where accepted.originating_invitation_id = p_invitation_id
      and accepted.user_id = acting_user_id
      and accepted.effective_end is null;

    if found then
        return jsonb_build_object(
            'invitation_id', invitation_record.id,
            'organization_id', invitation_record.organization_id,
            'membership_id', accepted_membership_id,
            'outcome', 'ALREADY_ACCEPTED'
        );
    end if;

    -- 5. Proof (BR-18): the plaintext secret is hashed here, never stored.
    if invitation_record.acceptance_secret_digest is null
       or p_acceptance_secret is null
       or sha256(convert_to(p_acceptance_secret, 'UTF8'))
           is distinct from invitation_record.acceptance_secret_digest then
        raise exception 'Invitation unavailable'
            using errcode = '42501';
    end if;

    -- 6. Lifecycle after proof, at the single acceptance instant; nothing is
    -- written on any of these outcomes.
    effective_instant := greatest(statement_timestamp(), invitation_record.created_at);

    if invitation_record.revoked_at is not null then
        raise exception 'Organization Invitation has been revoked'
            using errcode = '23514', hint = 'INVITATION_REVOKED';
    end if;

    if invitation_record.rejected_at is not null then
        raise exception 'Organization Invitation cannot be accepted'
            using errcode = '23514', hint = 'INVITATION_UNAVAILABLE';
    end if;

    if effective_instant >= invitation_record.expires_at then
        raise exception 'Organization Invitation has expired'
            using errcode = '23514', hint = 'INVITATION_EXPIRED';
    end if;

    if (
        invitation_record.recipient_user_id is not null
        and invitation_record.recipient_user_id <> acting_user_id
    ) or not public.organization_invitation_responsibilities_are_acceptable(
        p_invitation_id, invitation_record.organization_id
    ) then
        raise exception 'Organization Invitation cannot be accepted'
            using errcode = '23514', hint = 'INVITATION_UNAVAILABLE';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.organization_id = invitation_record.organization_id
          and membership.user_id = acting_user_id
          and membership.effective_end is null
    ) then
        raise exception 'User already has an active Organization Membership'
            using errcode = '23505', hint = 'ALREADY_MEMBER';
    end if;

    -- 7. Clinics in id order, then Membership, Grants and digest erasure.
    accepted_membership_id := public.establish_membership_from_organization_invitation(
        p_invitation_id,
        invitation_record.organization_id,
        invitation_record.inviting_user_id,
        acting_user_id,
        effective_instant
    );

    return jsonb_build_object(
        'invitation_id', invitation_record.id,
        'organization_id', invitation_record.organization_id,
        'membership_id', accepted_membership_id,
        'outcome', 'ACCEPTED'
    );
end;
$$;

revoke all privileges
on function public.accept_my_organization_invitation(uuid, text)
from public, anon, authenticated, service_role;
grant execute
on function public.accept_my_organization_invitation(uuid, text)
to authenticated;

commit;
