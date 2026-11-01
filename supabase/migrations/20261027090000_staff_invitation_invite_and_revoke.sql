-- Staff access lifecycle Phase 1, Slice B1 (SPEC-ORG-002 §10 BR-17–BR-23,
-- SPEC-ORG-010, SPEC-COM-001 BR-44–BR-46; REQ-ORG-002/005/006).
--
-- Invite: the Communications Edge route keeps generating the one-time secret
-- and its AES-GCM envelope (ADR-008), but now calls two service-role commands:
--   1. authorize_organization_invitation_creation(subject, organization)
--      fails closed (authentication, account verification, then nonexistent
--      and inaccessible Organization identically) before any input is judged,
--      and returns the creation instant T: this database's own clock,
--      truncated to the millisecond precision of the envelope context;
--   2. create_staff_organization_invitation_with_communication(...) re-checks
--      the same authority under the Organization lock, validates one
--      responsibility/scope, stores created_at = T and derives
--      expires_at = T + 168 hours itself (exact elapsed 7 days, independent of
--      any session timezone), and verifies the envelope context against that
--      derived expiry through the existing Communication integrity trigger.
-- The Edge binds exactly T + 7 days into the envelope, so the stored expiry
-- and the encrypted context share one trusted instant. T must not be later
-- than the command's own instant, so later lifecycle instants (revocation,
-- acceptance) can never precede created_at.
--
-- Revoke: authenticated revoke_organization_invitation(id) with the
-- Organization -> Invitation lock order of acceptance and idempotent outcomes.
--
-- Suppression: delivery eligibility already rejects a revoked, rejected,
-- expired, or accepted Invitation at materialization, claim, context and
-- submission start. The provider handoff now share-locks the Organization
-- Invitation before that final check, so it serializes with a concurrent
-- revocation: an email whose submission had not started is never sent after
-- revoke_organization_invitation returned REVOKED.
--
-- No table, column, constraint, capability, Communication type, or backfill.
-- The trusted legacy create_scoped_organization_invitation_with_communication
-- command is unchanged and keeps accepting every valid Invitation shape.
begin;

create function public.assert_organization_invitation_authority(
    p_auth_subject uuid,
    p_organization_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    select identity_record.user_id into acting_user_id
    from public.user_authentication_identities as identity_record
    where identity_record.provider = 'supabase_auth'
      and identity_record.issuer = 'primary'
      and identity_record.provider_subject = p_auth_subject;

    if acting_user_id is null then
        raise exception 'A coherent acting domain User is required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from auth.users as auth_user
        where auth_user.id = p_auth_subject
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'A verified email address is required'
            using errcode = '42501', hint = 'ACCOUNT_VERIFICATION_REQUIRED';
    end if;

    -- One outcome for a nonexistent Organization and one the caller cannot
    -- invite into (SPEC-ORG-002 BR-22).
    if not exists (
        select 1
        from public.veterinary_organizations as organization
        where organization.id = p_organization_id
    ) or not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'
    ) then
        raise exception 'Organization Invitation unavailable'
            using errcode = '42501', hint = 'ORGANIZATION_UNAVAILABLE';
    end if;

    return acting_user_id;
end;
$$;

revoke all privileges on function public.assert_organization_invitation_authority(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.authorize_organization_invitation_creation(
    p_auth_subject uuid,
    p_organization_id uuid
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform public.assert_organization_invitation_authority(
        p_auth_subject, p_organization_id
    );
    return date_trunc('milliseconds', statement_timestamp());
end;
$$;

revoke all privileges on function public.authorize_organization_invitation_creation(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.authorize_organization_invitation_creation(uuid, uuid)
to service_role;

create function public.create_staff_organization_invitation_with_communication(
    p_auth_subject uuid,
    p_organization_id uuid,
    p_recipient_email text,
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid,
    p_created_at timestamptz,
    p_acceptance_secret_digest bytea,
    p_secret_key_version integer,
    p_secret_nonce bytea,
    p_secret_ciphertext bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    operation_instant constant timestamptz := statement_timestamp();
    validity constant interval := interval '168 hours';
    acting_user_id uuid;
    invited_email text;
    created_invitation_id uuid;
begin
    -- 1–3: authentication, verification, Organization + capability.
    acting_user_id := public.assert_organization_invitation_authority(
        p_auth_subject, p_organization_id
    );

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    -- Authoritative under the Organization lock: a capability ended by a
    -- concurrent Staff write is not used after that write commits.
    if not public.user_has_organization_capability(
        acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'
    ) then
        raise exception 'Organization Invitation unavailable'
            using errcode = '42501', hint = 'ORGANIZATION_UNAVAILABLE';
    end if;

    -- 4: input. One responsibility and scope (BR-17); Owner never.
    invited_email := btrim(p_recipient_email, E' \t\n\r\f\013');
    if invited_email is null
       or char_length(invited_email) > 320
       or invited_email !~ '^[^[:space:]@]+@[^[:space:]@]+$' then
        raise exception 'Organization Invitation recipient email is invalid'
            using errcode = '22023', hint = 'INVALID_RECIPIENT';
    end if;

    if p_responsibility is null
       or p_responsibility not in ('ADMINISTRATOR', 'RECEPTIONIST', 'VETERINARIAN')
       or p_scope_type is null
       or p_scope_type not in ('ORGANIZATION', 'CLINIC')
       or (p_scope_type = 'ORGANIZATION' and p_clinic_id is not null)
       or (
           p_scope_type = 'CLINIC'
           and (
               p_clinic_id is null
               or p_responsibility not in ('ADMINISTRATOR', 'RECEPTIONIST')
           )
       ) then
        raise exception 'Organization Invitation role or scope is invalid'
            using errcode = '22023', hint = 'INVALID_ROLE_SCOPE';
    end if;

    if p_scope_type = 'CLINIC' then
        -- A nonexistent Clinic and another Organization's Clinic are one outcome.
        perform 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = p_organization_id
        for update;

        if not found then
            raise exception 'Organization Invitation Clinic is invalid'
                using errcode = '22023', hint = 'INVALID_CLINIC';
        end if;
    end if;

    -- Trusted Edge material: never client input.
    if p_created_at is null
       or not isfinite(p_created_at)
       or p_created_at <> date_trunc('milliseconds', p_created_at)
       or p_created_at > operation_instant
       or p_created_at <= operation_instant - interval '1 minute' then
        raise exception 'Organization Invitation creation instant is invalid'
            using errcode = '22023', hint = 'CREATION_INSTANT_INVALID';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32
       or p_secret_key_version is null
       or p_secret_key_version < 1
       or octet_length(p_secret_nonce) is distinct from 12
       or coalesce(octet_length(p_secret_ciphertext), 0) < 16 then
        raise exception 'Organization Invitation credential material is invalid'
            using errcode = '22023', hint = 'CREDENTIAL_INVALID';
    end if;

    -- 5: lifecycle (BR-19, BR-20), evaluated at this command's instant.
    if exists (
        select 1
        from public.organization_invitations as invitation
        where invitation.organization_id = p_organization_id
          and invitation.recipient_email_normalized = lower(invited_email)
          and invitation.revoked_at is null
          and invitation.rejected_at is null
          and invitation.expires_at > operation_instant
          and not exists (
              select 1
              from public.organization_memberships as accepted
              where accepted.originating_invitation_id = invitation.id
          )
    ) then
        raise exception 'An equivalent pending Organization Invitation already exists'
            using errcode = '23505', hint = 'PENDING_INVITATION_EXISTS';
    end if;

    -- Administrative Invitation provenance only; never an Auth email.
    if exists (
        select 1
        from public.organization_memberships as membership
        join public.organization_invitations as origin
          on origin.id = membership.originating_invitation_id
        where membership.organization_id = p_organization_id
          and membership.effective_start <= operation_instant
          and membership.effective_end is null
          and origin.recipient_email_normalized = lower(invited_email)
    ) then
        raise exception 'The recipient address belongs to an active Member'
            using errcode = '23505', hint = 'ACTIVE_MEMBER';
    end if;

    insert into public.organization_invitations (
        organization_id,
        inviting_user_id,
        recipient_user_id,
        recipient_email,
        created_at,
        expires_at,
        acceptance_secret_digest
    )
    values (
        p_organization_id,
        acting_user_id,
        null,
        invited_email,
        p_created_at,
        p_created_at + validity,
        p_acceptance_secret_digest
    )
    returning id into created_invitation_id;

    insert into public.organization_invitation_responsibilities (
        invitation_id,
        responsibility,
        scope_type,
        clinic_id
    )
    values (
        created_invitation_id,
        p_responsibility,
        p_scope_type,
        case when p_scope_type = 'CLINIC' then p_clinic_id end
    );

    -- The integrity trigger rejects an envelope context that does not bind
    -- exactly this recipient, derived expiry, and digest.
    insert into public.transactional_communications (
        communication_type, recipient_user_id, recipient_email, locale,
        organization_invitation_id, secret_envelope_version,
        secret_key_version, secret_algorithm, secret_aad_context,
        secret_nonce, secret_ciphertext
    ) values (
        'ORGANIZATION_INVITATION', null, invited_email, 'es-ES',
        created_invitation_id, 1, p_secret_key_version, 'AES-256-GCM',
        public.build_invitation_secret_aad(
            'organization', invited_email, p_created_at + validity,
            p_acceptance_secret_digest
        ),
        p_secret_nonce, p_secret_ciphertext
    );

    return created_invitation_id;
end;
$$;

revoke all privileges on function public.create_staff_organization_invitation_with_communication(
    uuid, uuid, text, text, text, uuid, timestamptz, bytea, integer, bytea, bytea
) from public, anon, authenticated, service_role;
grant execute on function public.create_staff_organization_invitation_with_communication(
    uuid, uuid, text, text, text, uuid, timestamptz, bytea, integer, bytea, bytea
) to service_role;

create function public.revoke_organization_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    invitation_record public.organization_invitations%rowtype;
    revocation_instant timestamptz;
    revocation_outcome text;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- A nonexistent Invitation and one in an Organization where the caller
    -- lacks the capability are one outcome; nothing is locked for them.
    select invitation.organization_id into target_organization_id
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if target_organization_id is null
       or not public.user_has_organization_capability(
           acting_user_id, target_organization_id, 'ORGANIZATION_REVOKE_INVITATIONS'
       ) then
        raise exception 'Organization Invitation unavailable' using errcode = '42501';
    end if;

    -- Organization -> Invitation, the lock order of acceptance (BR-11).
    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select invitation.* into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
      and invitation.organization_id = target_organization_id
    for update;

    if not found or not public.user_has_organization_capability(
        acting_user_id, target_organization_id, 'ORGANIZATION_REVOKE_INVITATIONS'
    ) then
        raise exception 'Organization Invitation unavailable' using errcode = '42501';
    end if;

    -- One revocation instant decides expiry and is recorded; never before the
    -- Invitation existed (same rule as acceptance).
    revocation_instant := greatest(statement_timestamp(), invitation_record.created_at);

    if exists (
        select 1
        from public.organization_memberships as accepted
        where accepted.originating_invitation_id = p_invitation_id
    ) then
        revocation_outcome := 'ACCEPTED';
    elsif invitation_record.revoked_at is not null then
        revocation_outcome := 'ALREADY_REVOKED';
    elsif invitation_record.rejected_at is not null then
        revocation_outcome := 'REJECTED';
    elsif revocation_instant >= invitation_record.expires_at then
        revocation_outcome := 'EXPIRED';
    else
        -- The acceptance-secret digest is retained (BR-10).
        update public.organization_invitations
        set revoked_at = revocation_instant,
            revoked_by_user_id = acting_user_id
        where id = p_invitation_id;
        revocation_outcome := 'REVOKED';
    end if;

    return jsonb_build_object(
        'invitation_id', p_invitation_id,
        'outcome', revocation_outcome
    );
end;
$$;

revoke all privileges on function public.revoke_organization_invitation(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.revoke_organization_invitation(uuid) to authenticated;

create or replace function public.mark_communication_delivery_submission_started(
    p_delivery_job_id uuid,
    p_lease_token uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    operation_timestamp timestamptz := clock_timestamp();
begin
    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.lease_expires_at > operation_timestamp
      and attempt.active_submission_started_at is null
    for update;

    if not found then
        raise exception 'A live pre-submission delivery claim is required'
            using errcode = '55000';
    end if;

    -- The provider handoff boundary serializes with Invitation revocation and
    -- acceptance, which update this row: after a concurrent revocation
    -- commits, the eligibility check below observes it (SPEC-COM-001 BR-45).
    perform 1
    from public.transactional_communications as communication
    join public.organization_invitations as invitation
      on invitation.id = communication.organization_invitation_id
    where communication.id = attempt_record.communication_id
    for share of invitation;

    if not public.communication_delivery_is_currently_eligible(
        attempt_record.communication_id, attempt_record.channel,
        attempt_record.push_registration_id,
        attempt_record.destination_snapshot
    ) then
        update public.communication_delivery_jobs
        set state = 'SUPPRESSED', resolved_at = operation_timestamp,
            last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
            lease_token = null, lease_expires_at = null,
            active_submission_started_at = null
        where id = attempt_record.id;
        return 'SUPPRESSED';
    end if;

    update public.communication_delivery_jobs
    set submission_count = submission_count + 1,
        first_submitted_at = coalesce(first_submitted_at, operation_timestamp),
        last_submitted_at = operation_timestamp,
        active_submission_started_at = operation_timestamp
    where id = attempt_record.id;

    return 'STARTED';
end;
$$;

commit;
