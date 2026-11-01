begin;

-- Slice 14 corrective migration.
--
-- Defect: enforce_transactional_communication_integrity() re-evaluated the
-- "Appointment Communication recipient must be a current Guardian" assertion on
-- every UPDATE, including the trusted bookkeeping write that
-- materialize_communication_delivery_jobs() performs to freeze
-- fanout_materialized_at. That assertion tests
-- `guardianship.effective_end is null` as of statement time, so once a
-- recipient's Guardianship ended, the fanout-freeze UPDATE raised SQLSTATE
-- 23514 and aborted materialize_communication_delivery_jobs() (and therefore
-- claim_communication_delivery_jobs(), which calls it first). One
-- not-yet-materialized former-Guardian Appointment Communication could wedge
-- all Communications dispatch deployment-wide.
--
-- Correction: the current-Guardian rule is an establishment-time invariant. A
-- Communication legitimately created for a then-current Guardian remains valid
-- historical intent after that Guardianship ends; whether it is still
-- deliverable is already decided by communication_delivery_is_currently_eligible
-- and the materialize/claim/context suppression machinery (a former Guardian is
-- suppressed, not notified). The assertion is therefore scoped to INSERT only.
-- Recipient, appointment, origin, type, and created_at remain immutable on
-- UPDATE via the existing tg_op = 'UPDATE' branch, so no establishment-time
-- protection is lost. Nothing else in the function changes.
--
-- The previous migration (20260901120000_communications.sql) is unchanged.
-- CREATE OR REPLACE preserves ownership and privileges; the revoke is repeated
-- verbatim for explicitness. The BEFORE INSERT OR UPDATE trigger
-- transactional_communications_enforce_integrity is left in place because the
-- function itself now distinguishes TG_OP.

create or replace function public.enforce_transactional_communication_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.organization_invitation_id is not null
       and not exists (
           select 1
           from public.organization_invitations as invitation
           where invitation.id = new.organization_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'organization', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Organization Invitation'
            using errcode = '23514';
    end if;

    if new.guardianship_invitation_id is not null
       and not exists (
           select 1
           from public.guardianship_invitations as invitation
           where invitation.id = new.guardianship_invitation_id
             and invitation.recipient_user_id is not distinct from new.recipient_user_id
             and invitation.recipient_email = new.recipient_email
             and new.secret_aad_context = public.build_invitation_secret_aad(
                 'guardianship', invitation.recipient_email,
                 invitation.expires_at, invitation.acceptance_secret_digest
             )
       ) then
        raise exception 'Communication recipient does not match its Guardianship Invitation'
            using errcode = '23514';
    end if;

    if new.appointment_lifecycle_event_id is not null
       and not exists (
           select 1 from public.appointment_lifecycle_events as event_record
           where event_record.id = new.appointment_lifecycle_event_id
             and event_record.appointment_id = new.appointment_id
             and (
                 (new.communication_type = 'APPOINTMENT_CONFIRMED' and event_record.to_state = 'CONFIRMED')
                 or (new.communication_type = 'APPOINTMENT_CANCELLED' and event_record.to_state = 'CANCELLED')
                 or (new.communication_type = 'APPOINTMENT_COMPLETED' and event_record.to_state = 'COMPLETED')
                 or (new.communication_type = 'APPOINTMENT_NO_SHOW' and event_record.to_state = 'NO_SHOW')
             )
       ) then
        raise exception 'Communication lifecycle origin does not match its Appointment and type'
            using errcode = '23514';
    end if;

    if new.appointment_reschedule_proposal_id is not null
       and not exists (
           select 1 from public.appointment_reschedule_proposals as proposal
           where proposal.id = new.appointment_reschedule_proposal_id
             and proposal.appointment_id = new.appointment_id
              and (
                  new.appointment_schedule_revision_id is null
                  or proposal.resulting_confirmed_revision_id = new.appointment_schedule_revision_id
              )
              and (
                  new.communication_type <> 'APPOINTMENT_RESCHEDULE_PROPOSED'
                  or proposal.proposing_context = 'CLINIC'
              )
       ) then
        raise exception 'Communication Proposal origin does not match its Appointment or revision'
            using errcode = '23514';
    end if;

    if new.appointment_schedule_revision_id is not null
       and not exists (
           select 1 from public.appointment_schedule_revisions as revision
           where revision.id = new.appointment_schedule_revision_id
             and revision.appointment_id = new.appointment_id
             and revision.revision_context = case
                 when new.communication_type = 'APPOINTMENT_REQUESTED'
                     then 'REQUESTED'
                 else 'CONFIRMED'
             end
       ) then
        raise exception 'Communication Schedule Revision origin does not match its Appointment'
            using errcode = '23514';
    end if;

    -- Establishment-time invariant only. A Communication created for a
    -- then-current Guardian stays valid historical intent after the
    -- Guardianship ends; later delivery eligibility is governed by
    -- communication_delivery_is_currently_eligible and the suppression sweeps.
    -- Re-checking here on an immutable-row bookkeeping UPDATE (for example the
    -- fanout_materialized_at freeze) would abort dispatch instead of suppressing
    -- the former-Guardian destination.
    if tg_op = 'INSERT'
       and new.recipient_user_id is not null
       and new.appointment_id is not null
       and not exists (
           select 1
           from public.appointments as appointment
           join public.guardianships as guardianship
             on guardianship.pet_id = appointment.pet_id
           where appointment.id = new.appointment_id
             and guardianship.user_id = new.recipient_user_id
             and guardianship.effective_start <= new.created_at
             and guardianship.effective_end is null
       ) then
        raise exception 'Appointment Communication recipient must be a current Guardian'
            using errcode = '23514';
    end if;

    if tg_op = 'UPDATE' then
        if old.id is distinct from new.id
           or old.communication_type is distinct from new.communication_type
           or old.recipient_user_id is distinct from new.recipient_user_id
           or old.recipient_email is distinct from new.recipient_email
           or old.locale is distinct from new.locale
           or old.organization_invitation_id is distinct from new.organization_invitation_id
           or old.guardianship_invitation_id is distinct from new.guardianship_invitation_id
           or old.appointment_id is distinct from new.appointment_id
           or old.appointment_lifecycle_event_id is distinct from new.appointment_lifecycle_event_id
           or old.appointment_reschedule_proposal_id is distinct from new.appointment_reschedule_proposal_id
           or old.appointment_schedule_revision_id is distinct from new.appointment_schedule_revision_id
           or old.secret_envelope_version is distinct from new.secret_envelope_version
           or old.secret_key_version is distinct from new.secret_key_version
           or old.secret_algorithm is distinct from new.secret_algorithm
           or old.secret_aad_context is distinct from new.secret_aad_context
           or old.created_at is distinct from new.created_at
           or (
               old.fanout_materialized_at is not null
               and new.fanout_materialized_at is distinct from
                   old.fanout_materialized_at
           )
           or (old.secret_consumed_at is not null and new.secret_consumed_at is distinct from old.secret_consumed_at)
           or (old.secret_consumed_at is null and new.secret_consumed_at is null and (
               old.secret_nonce is distinct from new.secret_nonce
               or old.secret_ciphertext is distinct from new.secret_ciphertext
           )) then
            raise exception 'Communication identity, origin, recipient, and encrypted handoff are immutable'
                using errcode = '23514';
        end if;

        if old.secret_consumed_at is null and new.secret_consumed_at is not null
           and (new.secret_nonce is not null or new.secret_ciphertext is not null) then
            raise exception 'Consuming an Invitation secret must erase its encrypted payload'
                using errcode = '23514';
        end if;
    end if;

    return new;
end;
$$;

revoke all privileges on function public.enforce_transactional_communication_integrity()
from public, anon, authenticated;

commit;
