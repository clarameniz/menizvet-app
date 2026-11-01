-- SPEC-MED-001 BR-6 / BR-34 / BR-36 — Appointment-backed Clinical Encounter
-- establishment after the Appointment was completed (Migration 2 of the
-- optional-Encounter model; Migration 1 was
-- 20261011090000_lightweight_appointment_completion.sql).
--
-- All three paths become valid:
--   CONFIRMED -> COMPLETED
--   CONFIRMED -> Encounter -> COMPLETED
--   CONFIRMED -> COMPLETED -> Encounter established later for that care
-- under one invariant: an Appointment-backed Encounter represents care that
-- started between the Appointment's single legitimate confirmation and, once
-- completed, its completion. The delay may be in documentation (`created_at`),
-- never in when care began (`started_at`). There is no documentation window.
--
-- Only `assert_clinical_encounter_establishment` (the BEFORE INSERT
-- establishment rule on public.clinical_encounters) changes. Relative to
-- 20260829120000_clinical_care.sql it:
--   * accepts an Appointment that is CONFIRMED or COMPLETED (was CONFIRMED
--     only); REQUESTED, CANCELLED, NO_SHOW, and EXPIRED stay rejected;
--   * keeps the existing proof of a legitimate confirmation (exactly one
--     REQUESTED -> CONFIRMED Lifecycle Event, started_at at or after it), and
--     for a COMPLETED Appointment additionally requires exactly one
--     CONFIRMED -> COMPLETED Event with started_at at or before its effective
--     time (SPEC-MED-001 BR-34 rules 7, 10);
--   * requires, for every Encounter (Appointment-backed or Clinical Intake),
--     that the responsible Veterinarian Clinic Assignment is current at
--     establishment and began at or before started_at (SPEC-MED-001 BR-6,
--     BR-34 rule 11). This also closes the pre-existing gap where a
--     Veterinarian assigned at 15:00 could record care as having begun at
--     10:00. No fallback to an ended Assignment exists.
-- Every other establishment rule is carried over verbatim (finite and
-- non-future timestamps, Clinic/Organization agreement, ACTIVE Care
-- Authorization matching Pet/Clinic/Organization, start not before the grant,
-- VCA/User provider context, CLINICAL_INTAKE vs APPOINTMENT_CARE shape).
--
-- Unchanged and relied upon:
--   * create_clinical_encounter(uuid, timestamptz, uuid) — signature and
--     body: the acting Veterinarian context, CLINICAL_CARE capability and
--     Entitlement are resolved at documentation time; the Appointment row and
--     then the Care Authorization row are locked FOR UPDATE before the
--     one-Encounter-per-Authorization check, which keeps concurrent creation
--     serialized; the Care Authorization must be ACTIVE (a Guardian
--     revocation blocks retrospective creation);
--   * assert_clinical_encounter_appointment_coherence and
--     assert_appointment_lifecycle_coherence (Migration 1) already accept an
--     Encounter on a COMPLETED Appointment whose care began no later than the
--     completion, and still reject any Encounter on a CANCELLED, NO_SHOW, or
--     EXPIRED Appointment;
--   * establishing an Encounter writes no Appointment state, Lifecycle Event,
--     Schedule Revision, or Communication; a COMPLETED Appointment stays
--     terminal and its Care Authorization stays as it is.
--
-- No table, column, index, constraint, trigger, grant, or existing row
-- changes.

begin;

create or replace function public.assert_clinical_encounter_establishment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_organization_id uuid,
    p_responsible_veterinarian_clinic_assignment_id uuid,
    p_created_by_user_id uuid,
    p_care_authorization_id uuid,
    p_appointment_id uuid,
    p_started_at timestamptz,
    p_created_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    clinic_organization_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    appointment_record public.appointments%rowtype;
    confirmation_event_count integer;
    confirmation_effective_at timestamptz;
    completion_event_count integer;
    completion_effective_at timestamptz;
    assignment_effective_start timestamptz;
begin
    if p_started_at is null or not isfinite(p_started_at)
       or p_created_at is null or not isfinite(p_created_at) then
        raise exception 'Clinical Encounter timestamps must be finite'
            using errcode = '22023';
    end if;

    if p_started_at > clock_timestamp()
       or p_created_at > clock_timestamp() then
        raise exception 'Clinical Encounter cannot be established with a future timestamp'
            using errcode = '22023';
    end if;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found or clinic_organization_id <> p_organization_id then
        raise exception 'Clinical Encounter Clinic and Organization must agree'
            using errcode = '23514';
    end if;

    select care_auth.*
    into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;

    if not found then
        raise exception 'Clinical Encounter requires its Care Authorization'
            using errcode = '23503';
    end if;

    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'A new Clinical Encounter requires an ACTIVE Care Authorization'
            using errcode = '23514';
    end if;

    if care_auth_record.pet_id <> p_pet_id
       or care_auth_record.clinic_id <> p_clinic_id
       or care_auth_record.organization_id <> p_organization_id then
        raise exception 'Clinical Encounter must match its Care Authorization Pet and provider context'
            using errcode = '23514';
    end if;

    if p_started_at < care_auth_record.granted_at then
        raise exception 'Clinical Encounter cannot begin before its Care Authorization was granted'
            using errcode = '23514';
    end if;

    perform public.assert_vca_user_provider_context(
        p_responsible_veterinarian_clinic_assignment_id,
        p_created_by_user_id,
        p_clinic_id,
        p_organization_id
    );

    -- SPEC-MED-001 BR-6: the responsible Clinic Assignment is current now and
    -- already covered the start of care. Phase 1 reconstructs no historical
    -- authority, so an ended Assignment never qualifies.
    select assignment.effective_start
    into assignment_effective_start
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_responsible_veterinarian_clinic_assignment_id;

    if not public.veterinarian_clinic_assignment_is_current(
        p_responsible_veterinarian_clinic_assignment_id
    ) then
        raise exception 'Clinical Encounter requires a current responsible Veterinarian Clinic Assignment'
            using errcode = '23514';
    end if;

    if p_started_at < assignment_effective_start then
        raise exception 'Clinical Encounter cannot begin before its responsible Veterinarian Clinic Assignment'
            using errcode = '23514';
    end if;

    if care_auth_record.purpose = 'CLINICAL_INTAKE' then
        if p_appointment_id is not null
           or care_auth_record.appointment_id is not null then
            raise exception 'CLINICAL_INTAKE Encounter must not reference an Appointment'
                using errcode = '23514';
        end if;

        return;
    end if;

    if care_auth_record.purpose <> 'APPOINTMENT_CARE'
       or p_appointment_id is null
       or care_auth_record.appointment_id is distinct from p_appointment_id then
        raise exception 'Appointment-backed Encounter requires the exact APPOINTMENT_CARE Authorization Appointment'
            using errcode = '23514';
    end if;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment-backed Clinical Encounter requires its Appointment'
            using errcode = '23503';
    end if;

    -- SPEC-MED-001 BR-34 rule 6: CONFIRMED, or COMPLETED after a legitimate
    -- confirmation; never REQUESTED, CANCELLED, NO_SHOW, or EXPIRED.
    if appointment_record.lifecycle_state not in ('CONFIRMED', 'COMPLETED') then
        raise exception 'Appointment-backed Clinical Encounter requires a CONFIRMED Appointment at establishment, or a COMPLETED one'
            using errcode = '23514';
    end if;

    if appointment_record.pet_id <> p_pet_id
       or appointment_record.clinic_id <> p_clinic_id then
        raise exception 'Clinical Encounter and Appointment Pet and Clinic must agree'
            using errcode = '23514';
    end if;

    -- BR-34 rules 7 and 8: exactly one legitimate confirmation, and care did
    -- not start before it.
    select count(*), min(lifecycle_event.effective_at)
    into confirmation_event_count, confirmation_effective_at
    from public.appointment_lifecycle_events as lifecycle_event
    where lifecycle_event.appointment_id = p_appointment_id
      and lifecycle_event.from_state = 'REQUESTED'
      and lifecycle_event.to_state = 'CONFIRMED';

    if confirmation_event_count <> 1 then
        raise exception 'Appointment-backed Clinical Encounter requires exactly one confirmation Lifecycle Event'
            using errcode = '23514';
    end if;

    if p_started_at < confirmation_effective_at then
        raise exception 'Appointment-backed Clinical Encounter cannot begin before Appointment confirmation'
            using errcode = '23514';
    end if;

    -- BR-34 rule 10: for a COMPLETED Appointment, care did not start after
    -- the Clinic declared the visit completed. The Encounter may be created
    -- (documented) at any later time.
    if appointment_record.lifecycle_state = 'COMPLETED' then
        select count(*), min(lifecycle_event.effective_at)
        into completion_event_count, completion_effective_at
        from public.appointment_lifecycle_events as lifecycle_event
        where lifecycle_event.appointment_id = p_appointment_id
          and lifecycle_event.from_state = 'CONFIRMED'
          and lifecycle_event.to_state = 'COMPLETED';

        if completion_event_count <> 1 then
            raise exception 'Appointment-backed Clinical Encounter requires exactly one completion Lifecycle Event for a COMPLETED Appointment'
                using errcode = '23514';
        end if;

        if p_started_at > completion_effective_at then
            raise exception 'Appointment-backed Clinical Encounter cannot begin after Appointment completion'
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinical_encounter_establishment(
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz
)
from public, anon, authenticated;

commit;
