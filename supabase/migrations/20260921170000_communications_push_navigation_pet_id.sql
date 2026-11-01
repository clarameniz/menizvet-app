begin;

-- Slice 14 corrective migration (forward-only; does not modify
-- 20260901120000_communications.sql or any other deployed migration).
--
-- Context: the mobile Push tap-to-navigate implementation (Milestone H)
-- found that its push `data` payload — { route: 'appointment',
-- appointment_id } — is insufficient for the Guardian appointment-detail
-- route, which is Pet-scoped (get_pet_appointments(pet_id)) because there is
-- no Guardian-scoped "get one Appointment by id" read. The mobile-only
-- workaround (fetching every currently-guarded Pet's Appointments to find
-- the owner) is authorization-safe but does needless client-side fan-out for
-- information the backend already has in hand.
--
-- get_communication_delivery_context(...) already joins
-- public.pets as pet on pet.id = appointment.pet_id
-- in its APPOINTMENT_* branch (to resolve pet.name for pet_name) — pet.id is
-- already in scope there at zero additional cost. This migration adds
-- exactly one key, 'pet_id', to that branch's jsonb_build_object output.
--
-- Privacy: pet_id is a plain domain identifier, not a name or medical
-- content. SPEC-COM-002 BR-26/BR-27 and the Communications Operational
-- Policy's "Push content privacy" list (Appointment reason, diagnosis,
-- medical history, Clinical Attachments, Care Authorization internals,
-- recipient email, provider token) do not cover it; it is the same category
-- of "opaque identifier for navigation" the policy already permits for
-- appointment_id, which this payload already carries. SPEC-COM-002 BR-28 and
-- SPEC-COM-003 BR-43 continue to hold unchanged: this navigation reference
-- does not grant authorization by itself — the existing Guardian-scoped
-- current-Guardianship check inside get_pet_appointments (called by the
-- mobile Appointment-detail screen's own fresh authoritative read) remains
-- the actual authorization boundary, exactly as before this migration.
--
-- Scope: the exact push `data` payload shape is implementation detail, not
-- Spec-fixed — SPEC-COM-003 §15 Out of Scope explicitly excludes "exact
-- notification wording" and "notification template implementation". No
-- Specification, ADR, or domain invariant changes.
--
-- Nothing else in this function changes: preconditions, locking,
-- eligibility suppression, the raw-token load, and every other jsonb key are
-- byte-identical to the deployed version. CREATE OR REPLACE preserves
-- ownership and privileges; the revoke/grant pair is repeated verbatim for
-- explicitness, matching the established convention (see
-- 20260903120000_communications_recipient_guardian_establishment_hotfix.sql).

create or replace function public.get_communication_delivery_context(
    p_delivery_job_id uuid,
    p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt_record public.communication_delivery_jobs%rowtype;
    communication_record public.transactional_communications%rowtype;
    resolved_destination text;
    result jsonb;
begin
    select attempt.* into attempt_record
    from public.communication_delivery_jobs as attempt
    where attempt.id = p_delivery_job_id
      and attempt.state = 'CLAIMED'
      and attempt.lease_token = p_lease_token
      and attempt.lease_expires_at > clock_timestamp()
      and attempt.active_submission_started_at is null
    for update;

    if not found then
        raise exception 'A live delivery claim is required' using errcode = '55000';
    end if;

    if not public.communication_delivery_is_currently_eligible(
        attempt_record.communication_id, attempt_record.channel,
        attempt_record.push_registration_id,
        attempt_record.destination_snapshot
    ) then
        update public.communication_delivery_jobs
        set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
            last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
            lease_token = null, lease_expires_at = null,
            active_submission_started_at = null
        where id = attempt_record.id;
        return null;
    end if;

    select communication.* into communication_record
    from public.transactional_communications as communication
    where communication.id = attempt_record.communication_id;

    resolved_destination := attempt_record.destination_snapshot;
    if attempt_record.channel = 'PUSH' then
        -- The raw provider token lives only on the private Registration. Load
        -- it after final registration/session revalidation and lock both rows
        -- for the remainder of this imminent trusted provider operation.
        select registration.provider_token into resolved_destination
        from public.push_registrations as registration
        join public.user_authentication_identities as identity_record
          on identity_record.user_id = registration.user_id
         and identity_record.provider = 'supabase_auth'
         and identity_record.issuer = 'primary'
        join auth.sessions as auth_session
          on auth_session.id = registration.auth_session_id
         and auth_session.user_id = identity_record.provider_subject
        where registration.id = attempt_record.push_registration_id
          and registration.user_id = communication_record.recipient_user_id
          and registration.invalidated_at is null
          and attempt_record.destination_snapshot = 'sha256:' ||
              encode(registration.provider_token_digest, 'hex')
        for key share of registration, auth_session;

        if not found then
            update public.communication_delivery_jobs
            set state = 'SUPPRESSED', resolved_at = clock_timestamp(),
                last_error_code = 'RECIPIENT_OR_ORIGIN_NO_LONGER_ELIGIBLE',
                lease_token = null, lease_expires_at = null,
                active_submission_started_at = null
            where id = attempt_record.id;
            return null;
        end if;
    end if;

    result := jsonb_build_object(
        'communication_id', communication_record.id,
        'communication_type', communication_record.communication_type,
        'locale', communication_record.locale,
        'recipient', resolved_destination,
        'channel', attempt_record.channel,
        'appointment_id', communication_record.appointment_id,
        'organization_invitation_id', communication_record.organization_invitation_id,
        'guardianship_invitation_id', communication_record.guardianship_invitation_id,
        'secret_envelope_version', communication_record.secret_envelope_version,
        'secret_key_version', communication_record.secret_key_version,
        'secret_algorithm', communication_record.secret_algorithm,
        'secret_aad_context', communication_record.secret_aad_context,
        'secret_nonce', communication_record.secret_nonce,
        'secret_ciphertext', communication_record.secret_ciphertext
    );

    if communication_record.organization_invitation_id is not null then
        select result || jsonb_build_object(
            'organization_name', organization.display_name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.organization_invitations as invitation
        join public.veterinary_organizations as organization
          on organization.id = invitation.organization_id
        where invitation.id = communication_record.organization_invitation_id;
    elsif communication_record.guardianship_invitation_id is not null then
        select result || jsonb_build_object(
            'pet_name', pet.name,
            'invitation_expires_at', invitation.expires_at
        ) into result
        from public.guardianship_invitations as invitation
        join public.pets as pet on pet.id = invitation.pet_id
        where invitation.id = communication_record.guardianship_invitation_id;
    elsif communication_record.appointment_id is not null then
        select result || jsonb_build_object(
            'pet_id', pet.id,
            'pet_name', pet.name,
            'clinic_name', coalesce(profile.display_name, organization.display_name),
            'appointment_state', appointment.lifecycle_state,
            'scheduled_start_at', coalesce(
                selected_revision.scheduled_start_at,
                proposal.proposed_start_at,
                latest_revision.scheduled_start_at
            ),
            'scheduled_end_at', coalesce(
                selected_revision.scheduled_end_at,
                proposal.proposed_end_at,
                latest_revision.scheduled_end_at
            ),
            'timezone_name', coalesce(
                selected_revision.establishment_timezone_name,
                proposal.proposed_timezone_name,
                latest_revision.establishment_timezone_name
            ),
            'reschedule_proposal_id', communication_record.appointment_reschedule_proposal_id
        ) into result
        from public.appointments as appointment
        join public.pets as pet on pet.id = appointment.pet_id
        join public.clinics as clinic on clinic.id = appointment.clinic_id
        join public.veterinary_organizations as organization
          on organization.id = clinic.organization_id
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        left join public.appointment_schedule_revisions as selected_revision
          on selected_revision.id = communication_record.appointment_schedule_revision_id
        left join public.appointment_reschedule_proposals as proposal
          on proposal.id = communication_record.appointment_reschedule_proposal_id
         and communication_record.communication_type = 'APPOINTMENT_RESCHEDULE_PROPOSED'
        left join lateral (
            select revision.*
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = appointment.id
              and (
                  (communication_record.communication_type = 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'REQUESTED')
                  or
                  (communication_record.communication_type <> 'APPOINTMENT_REQUESTED'
                   and revision.revision_context = 'CONFIRMED')
              )
            order by revision.revision_sequence desc
            limit 1
        ) as latest_revision on true
        where appointment.id = communication_record.appointment_id;
    end if;

    return result;
end;
$$;

revoke all privileges on function public.get_communication_delivery_context(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_communication_delivery_context(uuid, uuid)
to service_role;

commit;
