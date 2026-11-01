begin;

-- ==================================================================
-- 1. care_authorizations — stable Pet-, Clinic-, Organization-,
--    purpose-, and care-context-specific authorization basis.
--    Phase 1 supports exactly one creation workflow (Appointment
--    request); appointment_id remains physically nullable for future
--    relational-model extensibility, but purpose = 'APPOINTMENT_CARE'
--    currently requires it (see the shape check below).
-- ==================================================================

create table public.care_authorizations (
    id uuid not null default gen_random_uuid(),
    pet_id uuid not null,
    clinic_id uuid not null,
    organization_id uuid not null,
    granting_guardianship_id uuid not null,
    granted_at timestamptz not null,
    purpose text not null,
    appointment_id uuid,
    lifecycle_state text not null default 'ACTIVE',
    revoked_at timestamptz,
    revoking_user_id uuid,
    revocation_reason text,
    ended_at timestamptz,
    ended_reason text,
    constraint care_authorizations_pkey primary key (id),
    constraint care_authorizations_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_granting_guardianship_id_fkey
        foreign key (granting_guardianship_id)
        references public.guardianships (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_revoking_user_id_fkey
        foreign key (revoking_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint care_authorizations_appointment_id_key
        unique (appointment_id),
    constraint care_authorizations_purpose_check
        check (purpose in ('APPOINTMENT_CARE')),
    constraint care_authorizations_appointment_care_requires_appointment_check
        check (purpose <> 'APPOINTMENT_CARE' or appointment_id is not null),
    constraint care_authorizations_lifecycle_state_check
        check (lifecycle_state in ('ACTIVE', 'REVOKED', 'ENDED')),
    constraint care_authorizations_ended_reason_check
        check (ended_reason is null or ended_reason in ('APPOINTMENT_CANCELLED')),
    constraint care_authorizations_revocation_reason_check
        check (
            revocation_reason is null
            or (
                revocation_reason = btrim(revocation_reason, E' \t\n\r\f\013')
                and revocation_reason <> ''
            )
        ),
    constraint care_authorizations_granted_at_finite_check
        check (isfinite(granted_at)),
    constraint care_authorizations_revoked_at_finite_check
        check (revoked_at is null or isfinite(revoked_at)),
    constraint care_authorizations_ended_at_finite_check
        check (ended_at is null or isfinite(ended_at)),
    -- Stored-fact-only chronology (not wall-clock-dependent): a terminal
    -- time can never precede the grant it terminates.
    constraint care_authorizations_revoked_at_after_grant_check
        check (revoked_at is null or revoked_at >= granted_at),
    constraint care_authorizations_ended_at_after_grant_check
        check (ended_at is null or ended_at >= granted_at),
    -- Permanent row-shape integrity: ACTIVE carries no terminal facts;
    -- REVOKED and ENDED are mutually exclusive and each carry exactly
    -- their own required facts. No ending User/actor-context column
    -- exists on this table for the cancellation-derived ENDED case —
    -- that context remains derivable through the matching Appointment
    -- Lifecycle Event (see the deferred coherence trigger below).
    constraint care_authorizations_shape_check
        check (
            (
                lifecycle_state = 'ACTIVE'
                and revoked_at is null
                and revoking_user_id is null
                and revocation_reason is null
                and ended_at is null
                and ended_reason is null
            )
            or
            (
                lifecycle_state = 'REVOKED'
                and revoked_at is not null
                and revoking_user_id is not null
                and ended_at is null
                and ended_reason is null
            )
            or
            (
                lifecycle_state = 'ENDED'
                and ended_at is not null
                and ended_reason is not null
                and revoked_at is null
                and revoking_user_id is null
                and revocation_reason is null
            )
        )
);

create index care_authorizations_pet_history_idx
on public.care_authorizations (pet_id, granted_at, id);

create index care_authorizations_clinic_history_idx
on public.care_authorizations (clinic_id, granted_at, id);

create index care_authorizations_organization_idx
on public.care_authorizations (organization_id);

create index care_authorizations_granting_guardianship_idx
on public.care_authorizations (granting_guardianship_id);

-- ==================================================================
-- 2. Establishment-time integrity — BEFORE INSERT, following the
--    repository's established appointment_veterinarian_assignments
--    establishment-trigger pattern. Validates the new row against
--    already-existing foreign context; never re-fires later, so it
--    cannot become an ongoing "Guardianship must stay current
--    forever" invariant. Establishment requires a Guardianship that
--    is CURRENTLY active (effective_end is null), not merely active
--    as of a caller-supplied granted_at.
-- ==================================================================

create function public.assert_care_authorization_establishment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_organization_id uuid,
    p_granting_guardianship_id uuid,
    p_granted_at timestamptz,
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    clinic_organization_id uuid;
    guardianship_record public.guardianships%rowtype;
    appointment_record public.appointments%rowtype;
begin
    if p_granted_at is null or not isfinite(p_granted_at) then
        raise exception 'Care Authorization grant time must be finite'
            using errcode = '22023';
    end if;

    if p_granted_at > clock_timestamp() then
        raise exception 'Care Authorization cannot be granted at a future time'
            using errcode = '22023';
    end if;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    if clinic_organization_id <> p_organization_id then
        raise exception 'Care Authorization Organization must match the target Clinic Organization'
            using errcode = '23514';
    end if;

    select guardianship.*
    into guardianship_record
    from public.guardianships as guardianship
    where guardianship.id = p_granting_guardianship_id
    for update;

    if not found then
        raise exception 'Granting Guardianship does not exist'
            using errcode = '23503';
    end if;

    if guardianship_record.pet_id <> p_pet_id then
        raise exception 'Granting Guardianship must concern the Care Authorization Pet'
            using errcode = '23514';
    end if;

    if guardianship_record.effective_end is not null then
        raise exception 'Care Authorization establishment requires a currently active granting Guardianship'
            using errcode = '23514';
    end if;

    if guardianship_record.effective_start > p_granted_at then
        raise exception 'Granting Guardianship must have started before the Care Authorization grant time'
            using errcode = '23514';
    end if;

    if p_appointment_id is not null then
        -- Appointment identity columns (pet_id, clinic_id,
        -- requesting_user_id) are immutable once inserted, enforced by
        -- enforce_appointment_immutability(); a lock-free read is safe.
        select appointment.*
        into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id;

        if not found then
            raise exception 'Appointment-linked Care Authorization requires its Appointment'
                using errcode = '23503';
        end if;

        if appointment_record.pet_id <> p_pet_id then
            raise exception 'Appointment-linked Care Authorization must match the Appointment Pet'
                using errcode = '23514';
        end if;

        if appointment_record.clinic_id <> p_clinic_id then
            raise exception 'Appointment-linked Care Authorization must match the Appointment Clinic'
                using errcode = '23514';
        end if;

        if appointment_record.requesting_user_id <> guardianship_record.user_id then
            raise exception 'Appointment-linked Care Authorization granting Guardianship User must match the Appointment requesting User'
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_care_authorization_establishment(
    uuid, uuid, uuid, uuid, timestamptz, uuid
)
from public, anon, authenticated;

create function public.enforce_care_authorization_establishment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- A Care Authorization must always begin its life ACTIVE. The shape
    -- check already forbids terminal facts on an ACTIVE row; this closes
    -- the remaining gap by rejecting direct establishment as REVOKED or
    -- ENDED outright. A legitimate grant-then-terminal sequence remains
    -- possible only as INSERT ACTIVE followed by a separate UPDATE
    -- through the one-way lifecycle.
    if new.lifecycle_state <> 'ACTIVE' then
        raise exception 'Care Authorization must be established as ACTIVE'
            using errcode = '23514';
    end if;

    perform public.assert_care_authorization_establishment(
        new.pet_id, new.clinic_id, new.organization_id,
        new.granting_guardianship_id, new.granted_at, new.appointment_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_care_authorization_establishment()
from public, anon, authenticated;

create trigger care_authorizations_establishment
before insert on public.care_authorizations
for each row
execute function public.enforce_care_authorization_establishment();

-- ==================================================================
-- 3. Immutability — identity/grant context permanent; once terminal,
--    no further UPDATE at all (stronger than the "append-forward"
--    idiom used elsewhere, because a Care Authorization has exactly
--    one terminal transition ever, never a second one).
-- ==================================================================

create function public.enforce_care_authorization_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Care Authorizations cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.organization_id is distinct from new.organization_id
       or old.granting_guardianship_id is distinct from new.granting_guardianship_id
       or old.granted_at is distinct from new.granted_at
       or old.purpose is distinct from new.purpose
       or old.appointment_id is distinct from new.appointment_id then
        raise exception 'Care Authorization identity and grant context are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state <> 'ACTIVE' then
        raise exception 'A terminal Care Authorization cannot be modified further'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_care_authorization_immutability()
from public, anon, authenticated;

create trigger care_authorizations_preserve_identity
before update or delete on public.care_authorizations
for each row
execute function public.enforce_care_authorization_immutability();

-- ==================================================================
-- 4. Appointment CANCELLED lifecycle — widen the Slice 9 schema.
--    Slice 9 implementations are specialized around REQUESTED and
--    CONFIRMED only; every object below is extended to the minimum
--    degree required for CANCELLED. COMPLETED and NO_SHOW remain
--    physically unreachable.
-- ==================================================================

alter table public.appointments
drop constraint appointments_lifecycle_state_check;

alter table public.appointments
add constraint appointments_lifecycle_state_check
check (lifecycle_state in ('REQUESTED', 'CONFIRMED', 'CANCELLED'));

create or replace function public.enforce_appointment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Appointments cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.clinic_id is distinct from new.clinic_id
       or old.requesting_user_id is distinct from new.requesting_user_id
       or old.reason_for_visit is distinct from new.reason_for_visit
       or old.guardian_notes is distinct from new.guardian_notes
       or old.created_at is distinct from new.created_at then
        raise exception 'Appointment identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.lifecycle_state = new.lifecycle_state then
        return new;
    end if;

    if not (
        (old.lifecycle_state = 'REQUESTED' and new.lifecycle_state = 'CONFIRMED')
        or (
            old.lifecycle_state in ('REQUESTED', 'CONFIRMED')
            and new.lifecycle_state = 'CANCELLED'
        )
    ) then
        raise exception 'Unsupported Appointment lifecycle transition'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_appointment_immutability()
from public, anon, authenticated;

alter table public.appointment_lifecycle_events
drop constraint appointment_lifecycle_events_transition_check;

alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_transition_check
check (
    (from_state = 'REQUESTED' and to_state = 'CONFIRMED')
    or (from_state in ('REQUESTED', 'CONFIRMED') and to_state = 'CANCELLED')
);

-- Scoped to cancellation only — the existing REQUESTED-to-CONFIRMED
-- Event predates and remains unaffected by both new checks below.
alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_cancellation_actor_context_check
check (
    to_state <> 'CANCELLED'
    or (actor_context is not null and actor_context in ('GUARDIAN', 'CLINIC'))
);

alter table public.appointment_lifecycle_events
add constraint appointment_lifecycle_events_clinic_cancellation_reason_check
check (
    to_state <> 'CANCELLED'
    or actor_context <> 'CLINIC'
    or reason is not null
);

-- At most one cancellation Event per Appointment — immediate, not
-- deferred, mirroring appointment_lifecycle_events_confirmation_key.
create unique index appointment_lifecycle_events_cancellation_key
on public.appointment_lifecycle_events (appointment_id)
where to_state = 'CANCELLED';

create or replace function public.assert_appointment_lifecycle_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    requested_revision_count integer;
    event_count integer;
    confirmed_revision_count integer;
    confirmation_event_count integer;
    cancellation_event_count integer;
    cancellation_from_state text;
    cancellation_effective_at timestamptz;
    confirmation_effective_at timestamptz;
begin
    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then
        return;
    end if;

    if appointment_record.lifecycle_state = 'REQUESTED' then
        select count(*)
        into requested_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = 'REQUESTED'
          and revision.revision_sequence = 1;

        if requested_revision_count <> 1 then
            raise exception 'REQUESTED Appointment % requires exactly one initial REQUESTED Schedule Revision',
                p_appointment_id
                using errcode = '23514';
        end if;

        select count(*)
        into event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id;

        if event_count <> 0 then
            raise exception 'REQUESTED Appointment % must have zero Lifecycle Events',
                p_appointment_id
                using errcode = '23514';
        end if;

        return;
    end if;

    if appointment_record.lifecycle_state = 'CONFIRMED' then
        select count(*)
        into event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id
          and event_row.from_state = 'REQUESTED'
          and event_row.to_state = 'CONFIRMED';

        if event_count <> 1 then
            raise exception 'CONFIRMED Appointment % requires exactly one REQUESTED to CONFIRMED Lifecycle Event',
                p_appointment_id
                using errcode = '23514';
        end if;

        select count(*)
        into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = p_appointment_id
          and revision.revision_context = 'CONFIRMED';

        if confirmed_revision_count < 1 then
            raise exception 'CONFIRMED Appointment % requires an applicable CONFIRMED Schedule Revision',
                p_appointment_id
                using errcode = '23514';
        end if;

        return;
    end if;

    if appointment_record.lifecycle_state = 'CANCELLED' then
        select count(*)
        into cancellation_event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id
          and event_row.to_state = 'CANCELLED';

        if cancellation_event_count <> 1 then
            raise exception 'CANCELLED Appointment % requires exactly one cancellation Lifecycle Event',
                p_appointment_id
                using errcode = '23514';
        end if;

        select event_row.from_state, event_row.effective_at
        into cancellation_from_state, cancellation_effective_at
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id
          and event_row.to_state = 'CANCELLED';

        select count(*)
        into confirmation_event_count
        from public.appointment_lifecycle_events as event_row
        where event_row.appointment_id = p_appointment_id
          and event_row.from_state = 'REQUESTED'
          and event_row.to_state = 'CONFIRMED';

        if cancellation_from_state = 'REQUESTED' then
            if confirmation_event_count <> 0 then
                raise exception 'Appointment % cancelled from REQUESTED must not have a confirmation Lifecycle Event',
                    p_appointment_id
                    using errcode = '23514';
            end if;
        elsif cancellation_from_state = 'CONFIRMED' then
            if confirmation_event_count <> 1 then
                raise exception 'Appointment % cancelled from CONFIRMED requires exactly one prior REQUESTED to CONFIRMED Lifecycle Event',
                    p_appointment_id
                    using errcode = '23514';
            end if;

            select count(*)
            into confirmed_revision_count
            from public.appointment_schedule_revisions as revision
            where revision.appointment_id = p_appointment_id
              and revision.revision_context = 'CONFIRMED';

            if confirmed_revision_count < 1 then
                raise exception 'Appointment % cancelled from CONFIRMED requires its applicable CONFIRMED Schedule Revision to remain',
                    p_appointment_id
                    using errcode = '23514';
            end if;

            select event_row.effective_at
            into confirmation_effective_at
            from public.appointment_lifecycle_events as event_row
            where event_row.appointment_id = p_appointment_id
              and event_row.from_state = 'REQUESTED'
              and event_row.to_state = 'CONFIRMED';

            if cancellation_effective_at < confirmation_effective_at then
                raise exception 'Appointment % cancellation from CONFIRMED must not precede the confirmation it transitions from',
                    p_appointment_id
                    using errcode = '23514';
            end if;
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_coherence(uuid)
from public, anon, authenticated;

-- The Slice 9 body unconditionally assumed every Lifecycle Event
-- implies a CONFIRMED Appointment with a CONFIRMED revision — correct
-- only because no other transition shape could previously exist.
-- Branch explicitly on the event's own to_state now that CANCELLED is
-- also legal, otherwise a legitimate cancellation Event would fail
-- this deferred check.
create or replace function public.assert_appointment_lifecycle_event_provenance(
    p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_appointment_id uuid;
    target_to_state text;
    appointment_state text;
    confirmed_revision_count integer;
begin
    select event_row.appointment_id, event_row.to_state
    into target_appointment_id, target_to_state
    from public.appointment_lifecycle_events as event_row
    where event_row.id = p_event_id;

    if not found then
        return;
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = target_appointment_id
    for update;

    select appointment.lifecycle_state
    into appointment_state
    from public.appointments as appointment
    where appointment.id = target_appointment_id;

    if not found then
        raise exception 'Appointment Lifecycle Event % requires its Appointment',
            p_event_id
            using errcode = '23514';
    end if;

    if target_to_state = 'CONFIRMED' then
        if appointment_state <> 'CONFIRMED' then
            raise exception 'Appointment confirmation Lifecycle Event % requires a CONFIRMED Appointment',
                p_event_id
                using errcode = '23514';
        end if;

        select count(*)
        into confirmed_revision_count
        from public.appointment_schedule_revisions as revision
        where revision.appointment_id = target_appointment_id
          and revision.revision_context = 'CONFIRMED';

        if confirmed_revision_count < 1 then
            raise exception 'Appointment confirmation Lifecycle Event % requires an applicable CONFIRMED Schedule Revision',
                p_event_id
                using errcode = '23514';
        end if;
    elsif target_to_state = 'CANCELLED' then
        if appointment_state <> 'CANCELLED' then
            raise exception 'Appointment cancellation Lifecycle Event % requires a CANCELLED Appointment',
                p_event_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_lifecycle_event_provenance(uuid)
from public, anon, authenticated;

-- appointment_lifecycle_events_confirmation_key (unique, scoped to
-- REQUESTED->CONFIRMED) and the three same-Veterinarian conflict
-- triggers (enforce_appointment_veterinarian_assignment_conflict,
-- enforce_appointment_schedule_revision_conflict,
-- enforce_appointment_lifecycle_conflict) require no change: each
-- filters on lifecycle_state = 'CONFIRMED', so a CANCELLED Appointment
-- passively stops matching without any active re-check.

-- ==================================================================
-- 5. Two-sided Appointment <-> Care Authorization deferred coherence.
--    One trigger per authoritative relation whose mutation could
--    create incoherence, so a direct write against either table is
--    independently caught, matching the file's established per-table
--    deferred-integrity philosophy.
-- ==================================================================

create function public.assert_appointment_care_authorization_coherence(
    p_appointment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    linked_count integer;
    linked_state text;
begin
    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    if not found then
        return;
    end if;

    select count(*)
    into linked_count
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = p_appointment_id;

    if linked_count <> 1 then
        raise exception 'Appointment % requires exactly one Appointment-derived Care Authorization',
            p_appointment_id
            using errcode = '23514';
    end if;

    if appointment_record.lifecycle_state = 'CANCELLED' then
        select care_auth.lifecycle_state
        into linked_state
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = p_appointment_id;

        if linked_state = 'ACTIVE' then
            raise exception 'Cancelled Appointment % must not retain an ACTIVE Appointment-derived Care Authorization',
                p_appointment_id
                using errcode = '23514';
        end if;
    end if;
end;
$$;

revoke all privileges
on function public.assert_appointment_care_authorization_coherence(uuid)
from public, anon, authenticated;

create function public.enforce_appointment_care_authorization_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_appointment_care_authorization_coherence(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_appointment_care_authorization_coherence()
from public, anon, authenticated;

create constraint trigger appointments_enforce_care_authorization_coherence
after insert or update of lifecycle_state on public.appointments
deferrable initially deferred
for each row
execute function public.enforce_appointment_care_authorization_coherence();

create function public.assert_care_authorization_appointment_coherence(
    p_care_authorization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    authorization_record public.care_authorizations%rowtype;
    appointment_state text;
    cancellation_effective_at timestamptz;
begin
    select care_auth.*
    into authorization_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;

    if not found then
        return;
    end if;

    if authorization_record.lifecycle_state <> 'ENDED'
       or authorization_record.ended_reason <> 'APPOINTMENT_CANCELLED' then
        return;
    end if;

    if authorization_record.appointment_id is null then
        raise exception 'Cancellation-derived ended Care Authorization % requires an Appointment',
            p_care_authorization_id
            using errcode = '23514';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = authorization_record.appointment_id
    for update;

    select appointment.lifecycle_state
    into appointment_state
    from public.appointments as appointment
    where appointment.id = authorization_record.appointment_id;

    if not found or appointment_state <> 'CANCELLED' then
        raise exception 'Care Authorization % ended as APPOINTMENT_CANCELLED but its Appointment is not CANCELLED',
            p_care_authorization_id
            using errcode = '23514';
    end if;

    select event_row.effective_at
    into cancellation_effective_at
    from public.appointment_lifecycle_events as event_row
    where event_row.appointment_id = authorization_record.appointment_id
      and event_row.to_state = 'CANCELLED';

    if not found then
        raise exception 'Care Authorization % ended as APPOINTMENT_CANCELLED but no cancellation Lifecycle Event exists',
            p_care_authorization_id
            using errcode = '23514';
    end if;

    if cancellation_effective_at is distinct from authorization_record.ended_at then
        raise exception 'Care Authorization % ended_at must match its Appointment cancellation effective time',
            p_care_authorization_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_care_authorization_appointment_coherence(uuid)
from public, anon, authenticated;

create function public.enforce_care_authorization_appointment_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_care_authorization_appointment_coherence(new.id);
    return null;
end;
$$;

revoke all privileges
on function public.enforce_care_authorization_appointment_coherence()
from public, anon, authenticated;

create constraint trigger care_authorizations_enforce_appointment_coherence
after insert or update of lifecycle_state on public.care_authorizations
deferrable initially deferred
for each row
execute function public.enforce_care_authorization_appointment_coherence();

-- ==================================================================
-- 6. Pre-existing Appointment guard. request_appointment did not
--    exist before this migration and the Slice 9 runtime harness
--    retained zero synthetic rows, so an empty appointments table is
--    strongly expected — but that is evidence, not proof, against a
--    manual/privileged insert. Fail the migration rather than
--    silently enabling an unenforced invariant or fabricating
--    Guardian consent for a row that never went through
--    request_appointment.
-- ==================================================================

do $$
begin
    if exists (
        select 1
        from public.appointments as appointment
        where not exists (
            select 1
            from public.care_authorizations as care_auth
            where care_auth.appointment_id = appointment.id
        )
    ) then
        raise exception 'Pre-existing Appointment rows without a matching Care Authorization exist; Slice 10 cannot safely enable the exact-one invariant. Resolve those rows explicitly before re-running this migration.'
            using errcode = '23514';
    end if;
end;
$$;

-- ==================================================================
-- 7. care_authorizations RLS / privilege boundary. No direct client
--    CRUD; every access path is a SECURITY DEFINER function below.
-- ==================================================================

alter table public.care_authorizations enable row level security;

revoke all privileges on table public.care_authorizations
from public, anon, authenticated;

-- ==================================================================
-- 8. APPOINTMENT_CANCEL capability — extend the existing capability
--    helper (already once replaced by Slice 9) exactly according to
--    SPEC-ORG-005 §5/§6: OWNER and ADMINISTRATOR (Organization- or
--    Clinic-scoped) and RECEPTIONIST. VETERINARIAN is deliberately
--    NOT extended — SPEC-ORG-005's VETERINARIAN mapping does not
--    include APPOINTMENT_CANCEL.
-- ==================================================================

create or replace function public.user_has_clinic_capability(
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
        coalesce(
            p_capability in (
                'CLINIC_MANAGE_LOCATION',
                'CLINIC_MANAGE_PUBLIC_PROFILE',
                'CLINIC_MANAGE_PUBLICATION',
                'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS',
                'CLINIC_MANAGE_SERVICES',
                'CLINIC_MANAGE_OPENING_HOURS',
                'APPOINTMENT_MANAGE_AVAILABILITY',
                'APPOINTMENT_VIEW_SCHEDULE',
                'APPOINTMENT_CONFIRM',
                'APPOINTMENT_RESCHEDULE',
                'APPOINTMENT_ASSIGN_VETERINARIAN',
                'APPOINTMENT_CANCEL'
            ),
            false
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as grant_record
                  on grant_record.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_end is null
                  and grant_record.effective_end is null
                  and (
                      (
                          grant_record.scope_type = 'ORGANIZATION'
                          and grant_record.clinic_id is null
                          and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
                      )
                      or
                      (
                          grant_record.scope_type = 'CLINIC'
                          and grant_record.clinic_id = p_clinic_id
                          and grant_record.responsibility = 'ADMINISTRATOR'
                      )
                      or
                      (
                          grant_record.responsibility = 'RECEPTIONIST'
                          and p_capability in (
                              'APPOINTMENT_MANAGE_AVAILABILITY',
                              'APPOINTMENT_VIEW_SCHEDULE',
                              'APPOINTMENT_CONFIRM',
                              'APPOINTMENT_RESCHEDULE',
                              'APPOINTMENT_ASSIGN_VETERINARIAN',
                              'APPOINTMENT_CANCEL'
                          )
                          and (
                              (
                                  grant_record.scope_type = 'ORGANIZATION'
                                  and grant_record.clinic_id is null
                              )
                              or
                              (
                                  grant_record.scope_type = 'CLINIC'
                                  and grant_record.clinic_id = p_clinic_id
                              )
                          )
                      )
                  )
            )
            or
            (
                p_capability = 'APPOINTMENT_VIEW_SCHEDULE'
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as grant_record
                      on grant_record.membership_id = membership.id
                    join public.veterinarian_professional_profiles as profile
                      on profile.user_id = p_user_id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.professional_profile_id = profile.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_end is null
                      and grant_record.effective_end is null
                      and grant_record.responsibility = 'VETERINARIAN'
                      and grant_record.scope_type = 'ORGANIZATION'
                      and grant_record.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 9. Mutation RPCs.
-- ==================================================================

-- Guardian-facing Appointment request (SPEC-APT-001). Authorization
-- order follows the deployed accept_appointment_reschedule_proposal
-- GUARDIAN-branch precedent: a lock-free Guardianship pre-check
-- protects commercial-Entitlement disclosure ordering, then
-- Organization -> Clinic locking and APPOINTMENT_MANAGEMENT
-- evaluation, then a locked, authoritative Guardianship
-- revalidation.
create function public.request_appointment(
    p_pet_id uuid,
    p_clinic_id uuid,
    p_start_local_date date,
    p_start_local_time time,
    p_start_utc_offset_seconds integer,
    p_end_local_date date,
    p_end_local_time time,
    p_end_utc_offset_seconds integer,
    p_reason_for_visit text,
    p_guardian_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    clinic_is_published boolean;
    guardianship_record public.guardianships%rowtype;
    resolved_interval record;
    normalized_reason text;
    normalized_notes text;
    operation_timestamp timestamptz;
    created_appointment_id uuid;
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

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = acting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The acting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    -- Disclosure pre-check: prove Guardian domain authority for the
    -- exact Pet before any Organization/Clinic lock is taken or
    -- Entitlement is evaluated, so a User without Guardianship cannot
    -- learn commercial Entitlement state through this operation's
    -- error ordering.
    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    target_organization_id := public.assert_clinic_organization_entitlement_after_lock(
        p_clinic_id, 'APPOINTMENT_MANAGEMENT'
    );

    select clinic.is_published
    into clinic_is_published
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not coalesce(clinic_is_published, false) then
        raise exception 'Appointment requests require a published Clinic'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of the exact current
    -- Guardianship row, after Organization -> Clinic locking.
    select guardianship.*
    into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;

    if not found then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    normalized_reason := btrim(p_reason_for_visit, E' \t\n\r\f\013');

    if normalized_reason is null or normalized_reason = '' then
        raise exception 'Appointment request requires a reason for visit'
            using errcode = '22023';
    end if;

    normalized_notes := case
        when p_guardian_notes is null then null
        else btrim(p_guardian_notes, E' \t\n\r\f\013')
    end;

    if normalized_notes = '' then
        raise exception 'Guardian notes must not be blank when supplied'
            using errcode = '22023';
    end if;

    select * into resolved_interval
    from public.resolve_clinic_appointment_interval(
        p_clinic_id,
        p_start_local_date, p_start_local_time, p_start_utc_offset_seconds,
        p_end_local_date, p_end_local_time, p_end_utc_offset_seconds
    );

    operation_timestamp := clock_timestamp();

    if resolved_interval.resolved_start_at <= operation_timestamp then
        raise exception 'Requested Appointment time must be in the future'
            using errcode = '22023';
    end if;

    if not public.clinic_appointment_interval_is_available(
        p_clinic_id,
        resolved_interval.resolved_start_at,
        resolved_interval.resolved_end_at
    ) then
        raise exception 'Clinic Appointment Availability does not cover the requested interval'
            using errcode = '23514';
    end if;

    insert into public.appointments (
        pet_id, clinic_id, requesting_user_id, reason_for_visit, guardian_notes,
        lifecycle_state, created_at
    )
    values (
        p_pet_id, p_clinic_id, acting_user_id, normalized_reason, normalized_notes,
        'REQUESTED', operation_timestamp
    )
    returning id into created_appointment_id;

    insert into public.appointment_schedule_revisions (
        appointment_id, revision_sequence, revision_context,
        scheduled_start_at, scheduled_end_at, establishment_timezone_name,
        established_by_user_id, source_proposal_id, created_at
    )
    values (
        created_appointment_id, 1, 'REQUESTED',
        resolved_interval.resolved_start_at, resolved_interval.resolved_end_at,
        resolved_interval.timezone_name, acting_user_id, null, operation_timestamp
    );

    insert into public.care_authorizations (
        pet_id, clinic_id, organization_id, granting_guardianship_id,
        granted_at, purpose, appointment_id, lifecycle_state
    )
    values (
        p_pet_id, p_clinic_id, target_organization_id, guardianship_record.id,
        operation_timestamp, 'APPOINTMENT_CARE', created_appointment_id, 'ACTIVE'
    );

    return created_appointment_id;
end;
$$;

revoke all privileges
on function public.request_appointment(
    uuid, uuid, date, time, integer, date, time, integer, text, text
)
from public, anon, authenticated;

grant execute
on function public.request_appointment(
    uuid, uuid, date, time, integer, date, time, integer, text, text
)
to authenticated;

-- Guardian revocation (SPEC-ACC-002). Targets the Appointment, never a
-- raw Care Authorization id, so the base table never needs a client
-- read surface. Lock order: Guardianship -> Care Authorization only —
-- no Organization/Clinic/Entitlement (not a paid operation), no
-- Appointment lock (revocation never reads or mutates Appointment
-- state).
create function public.revoke_appointment_care_authorization(
    p_appointment_id uuid,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_pet_id uuid;
    normalized_reason text;
    authorization_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
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

    select appointment.pet_id
    into appointment_pet_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.guardianships as guardianship
    where guardianship.pet_id = appointment_pet_id
      and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;

    if not found then
        raise exception 'Current Guardianship of the Appointment Pet is required'
            using errcode = '42501';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    select *
    into authorization_record
    from public.care_authorizations
    where appointment_id = p_appointment_id
    for update;

    if not found then
        raise exception 'Appointment has no Appointment-derived Care Authorization'
            using errcode = '23514';
    end if;

    if authorization_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Only an ACTIVE Care Authorization may be revoked'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    update public.care_authorizations
    set lifecycle_state = 'REVOKED',
        revoked_at = operation_timestamp,
        revoking_user_id = acting_user_id,
        revocation_reason = normalized_reason
    where id = authorization_record.id
      and lifecycle_state = 'ACTIVE';

    return authorization_record.id;
end;
$$;

revoke all privileges
on function public.revoke_appointment_care_authorization(uuid, text)
from public, anon, authenticated;

grant execute
on function public.revoke_appointment_care_authorization(uuid, text)
to authenticated;

-- Appointment cancellation (SPEC-APT-003), Guardian or Clinic actor.
-- The cancelling context is an explicit caller-supplied argument, not
-- inferred — a User who simultaneously holds current Guardianship of
-- the Pet AND applicable Clinic APPOINTMENT_CANCEL authority must
-- choose one context, and that choice, once independently authorized,
-- is exactly the actor_context persisted in the Lifecycle Event. No
-- automatic fallback from one context to the other. The Clinic branch
-- is deliberately capability-only via assert_clinic_capability_after_lock
-- — no Entitlement check, because cancellation is safe resolution that
-- must remain available after APPOINTMENT_MANAGEMENT loss (SPEC-SUB-004
-- BR-9/BR-38). The Guardian branch never touches Organization/Clinic
-- locks at all.
create function public.cancel_appointment(
    p_appointment_id uuid,
    p_cancelling_context text,
    p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    appointment_clinic_id uuid;
    appointment_pet_id uuid;
    normalized_reason text;
    appointment_record public.appointments%rowtype;
    authorization_record public.care_authorizations%rowtype;
    operation_timestamp timestamptz;
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

    if p_cancelling_context is null or p_cancelling_context not in ('GUARDIAN', 'CLINIC') then
        raise exception 'Cancelling context must be GUARDIAN or CLINIC'
            using errcode = '22023';
    end if;

    select appointment.pet_id, appointment.clinic_id
    into appointment_pet_id, appointment_clinic_id
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if not found then
        raise exception 'Appointment does not exist'
            using errcode = '23503';
    end if;

    if p_cancelling_context = 'GUARDIAN' then
        if not exists (
            select 1
            from public.guardianships as guardianship
            where guardianship.pet_id = appointment_pet_id
              and guardianship.user_id = acting_user_id
              and guardianship.effective_start <= clock_timestamp()
              and guardianship.effective_end is null
        ) then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    else
        -- Organization -> Clinic locked, capability-only authorization,
        -- no Entitlement evaluation.
        perform public.assert_clinic_capability_after_lock(
            acting_user_id, appointment_clinic_id, 'APPOINTMENT_CANCEL'
        );
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');

    if p_cancelling_context = 'CLINIC' and normalized_reason is null then
        raise exception 'A meaningful reason is required for a Clinic-initiated cancellation'
            using errcode = '22023';
    end if;

    perform 1
    from public.appointments as appointment
    where appointment.id = p_appointment_id
    for update;

    select appointment.*
    into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id;

    if appointment_record.lifecycle_state not in ('REQUESTED', 'CONFIRMED') then
        raise exception 'Only a REQUESTED or CONFIRMED Appointment may be cancelled through this workflow'
            using errcode = '23514';
    end if;

    -- Authoritative, locked revalidation of Guardian authority under
    -- the Appointment lock. A concurrent effective-end update either
    -- precedes this check (and makes it fail) or follows the
    -- committed cancellation.
    if p_cancelling_context = 'GUARDIAN' then
        perform 1
        from public.guardianships as guardianship
        where guardianship.pet_id = appointment_record.pet_id
          and guardianship.user_id = acting_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
        for update;

        if not found then
            raise exception 'Current Guardianship of the Appointment Pet is required'
                using errcode = '42501';
        end if;
    end if;

    select *
    into authorization_record
    from public.care_authorizations
    where appointment_id = p_appointment_id
    for update;

    if not found then
        raise exception 'Appointment has no Appointment-derived Care Authorization'
            using errcode = '23514';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.appointment_lifecycle_events (
        appointment_id, from_state, to_state, actor_user_id, actor_context,
        reason, effective_at, recorded_at
    )
    values (
        p_appointment_id, appointment_record.lifecycle_state, 'CANCELLED',
        acting_user_id, p_cancelling_context, normalized_reason,
        operation_timestamp, operation_timestamp
    );

    update public.appointments
    set lifecycle_state = 'CANCELLED'
    where id = p_appointment_id;

    -- If Guardian revocation already made this Authorization terminal
    -- (REVOKED) before anyone cancelled the Appointment, leave it
    -- untouched — never rewrite REVOKED into ENDED. If already ENDED,
    -- likewise leave it untouched.
    if authorization_record.lifecycle_state = 'ACTIVE' then
        update public.care_authorizations
        set lifecycle_state = 'ENDED',
            ended_at = operation_timestamp,
            ended_reason = 'APPOINTMENT_CANCELLED'
        where id = authorization_record.id
          and lifecycle_state = 'ACTIVE';
    end if;

    return p_appointment_id;
end;
$$;

revoke all privileges
on function public.cancel_appointment(uuid, text, text)
from public, anon, authenticated;

grant execute
on function public.cancel_appointment(uuid, text, text)
to authenticated;

commit;
