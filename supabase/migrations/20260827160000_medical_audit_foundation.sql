begin;

-- ==================================================================
-- SLICE 11 — MEDICAL AUDIT FOUNDATION
--
-- Additive-only migration. Establishes the trusted, append-only
-- Medical Access Audit Event foundation required before any protected
-- medical-access behavior (Slice 12+). It introduces exactly:
--
--   1. public.medical_access_audit_events            (append-only, A/I)
--   2. append-only immutability trigger + function
--   3. BEFORE INSERT establishment identity/context-coherence
--      trigger + function
--   4. public.establish_medical_access_audit_event(...) — one internal
--      trusted capture primitive, no client EXECUTE
--   5. RLS + full client privilege lockdown
--
-- Out of scope (Slice 12/13 or explicitly unresolved architecture):
-- Clinical Encounter / Record Entry / Amendment / Attachment tables,
-- protected medical reads, Medical Access Decision, process actor
-- identity, denial_reason, correlation_id, Audit Session, any generic
-- Actor/Principal/Permission/Role model, secondary indexes, any
-- client-facing RPC or audit-history read, and any historical
-- backfill. No Slice 1-10 object is modified.
-- ==================================================================

-- ==================================================================
-- 1. medical_access_audit_events
--
-- Append-only historical security evidence for audit-required
-- protected medical-access operations. Every column is frozen at
-- INSERT (immutability trigger below). Controlled values use narrow
-- CHECK constraints rather than editable lookup tables. Every foreign
-- key is ON DELETE RESTRICT / ON UPDATE NO ACTION: audit evidence must
-- survive ordinary lifecycle changes and must never cascade-delete.
--
-- Establishment-time coherence (see the trigger) validates relational
-- identity/context only. It never evaluates temporal currentness,
-- Care Authorization ACTIVE state, capability, Entitlement, least
-- privilege, or whether the outcome should be PERMITTED/DENIED, so a
-- DENIED Event may legitimately preserve ended/revoked evaluated
-- context or omit an authority relationship whose absence caused the
-- denial.
-- ==================================================================

create table public.medical_access_audit_events (
    id uuid not null default gen_random_uuid(),
    occurred_at timestamptz not null,
    recorded_at timestamptz not null default clock_timestamp(),
    operation text not null,
    outcome text not null,
    actor_context text not null,
    protected_resource_scope text not null,
    acting_user_id uuid not null,
    pet_id uuid not null,
    guardianship_id uuid,
    care_authorization_id uuid,
    accessing_clinic_id uuid,
    accessing_organization_id uuid,
    appointment_id uuid,
    organization_membership_id uuid,
    organization_responsibility_grant_id uuid,
    veterinarian_clinic_assignment_id uuid,
    constraint medical_access_audit_events_pkey primary key (id),

    constraint medical_access_audit_events_acting_user_id_fkey
        foreign key (acting_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_guardianship_id_fkey
        foreign key (guardianship_id)
        references public.guardianships (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_care_authorization_id_fkey
        foreign key (care_authorization_id)
        references public.care_authorizations (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_accessing_clinic_id_fkey
        foreign key (accessing_clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_accessing_organization_id_fkey
        foreign key (accessing_organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_appointment_id_fkey
        foreign key (appointment_id)
        references public.appointments (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_organization_membership_id_fkey
        foreign key (organization_membership_id)
        references public.organization_memberships (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_org_responsibility_grant_id_fkey
        foreign key (organization_responsibility_grant_id)
        references public.organization_responsibility_grants (id)
        on update no action
        on delete restrict,
    constraint medical_access_audit_events_vet_clinic_assignment_id_fkey
        foreign key (veterinarian_clinic_assignment_id)
        references public.veterinarian_clinic_assignments (id)
        on update no action
        on delete restrict,

    -- Fixed controlled values (approved Phase 1 sets; do not extend here).
    constraint medical_access_audit_events_operation_check
        check (operation in (
            'VIEW_PET_MEDICAL_HISTORY',
            'VIEW_CLINICAL_RECORD_ENTRY',
            'VIEW_CLINICAL_ATTACHMENT',
            'ACCESS_FOR_APPOINTMENT_OPERATIONS',
            'ACCESS_FOR_CLINICAL_CARE',
            'ACCESS_FOR_POST_CARE_DOCUMENTATION'
        )),
    constraint medical_access_audit_events_outcome_check
        check (outcome in ('PERMITTED', 'DENIED')),
    constraint medical_access_audit_events_actor_context_check
        check (actor_context in (
            'GUARDIAN',
            'PROFESSIONAL_CLINICAL',
            'CLINIC_OPERATIONAL'
        )),
    constraint medical_access_audit_events_protected_resource_scope_check
        check (protected_resource_scope in (
            'LONGITUDINAL_MEDICAL_HISTORY',
            'CLINICAL_RECORD_ENTRY',
            'CLINICAL_AMENDMENT',
            'CLINICAL_ATTACHMENT',
            'ENCOUNTER_MEDICAL_INFORMATION'
        )),

    -- Stored-fact chronology only (never wall-clock-dependent). The
    -- establishment trigger additionally rejects a future occurred_at.
    constraint medical_access_audit_events_occurred_at_finite_check
        check (isfinite(occurred_at)),
    constraint medical_access_audit_events_recorded_at_finite_check
        check (isfinite(recorded_at)),
    constraint medical_access_audit_events_recording_order_check
        check (recorded_at >= occurred_at),

    -- Minimal row-shape integrity. Partitions the Guardian vs
    -- professional/operational actor contexts and pins the three
    -- VIEW_* operations to their resource scope. Deliberately NOT an
    -- authorization matrix: a DENIED Event may omit the authority
    -- relationship whose absence caused the denial, so no professional
    -- provenance FK is made mandatory by actor_context.
    constraint medical_access_audit_events_guardian_context_shape_check
        check (
            actor_context <> 'GUARDIAN'
            or (
                care_authorization_id is null
                and accessing_clinic_id is null
                and accessing_organization_id is null
                and appointment_id is null
                and organization_membership_id is null
                and organization_responsibility_grant_id is null
                and veterinarian_clinic_assignment_id is null
            )
        ),
    constraint medical_access_audit_events_professional_context_shape_check
        check (
            guardianship_id is null
            or actor_context = 'GUARDIAN'
        ),
    constraint medical_access_audit_events_operation_scope_pinning_check
        check (
            (operation = 'VIEW_PET_MEDICAL_HISTORY'
                and protected_resource_scope = 'LONGITUDINAL_MEDICAL_HISTORY')
            or (operation = 'VIEW_CLINICAL_RECORD_ENTRY'
                and protected_resource_scope = 'CLINICAL_RECORD_ENTRY')
            or (operation = 'VIEW_CLINICAL_ATTACHMENT'
                and protected_resource_scope = 'CLINICAL_ATTACHMENT')
            or operation in (
                'ACCESS_FOR_APPOINTMENT_OPERATIONS',
                'ACCESS_FOR_CLINICAL_CARE',
                'ACCESS_FOR_POST_CARE_DOCUMENTATION'
            )
        ),

    -- Provenance self-consistency. A supplied Responsibility Grant
    -- provenance requires its Membership provenance; a supplied
    -- Veterinarian Clinic Assignment provenance requires the accessing
    -- Clinic it is bound to. Scope-specific accessing-Organization /
    -- accessing-Clinic requirements depend on grant.scope_type and are
    -- enforced in the establishment trigger.
    constraint medical_access_audit_events_grant_requires_membership_check
        check (
            organization_responsibility_grant_id is null
            or organization_membership_id is not null
        ),
    constraint medical_access_audit_events_vca_requires_clinic_check
        check (
            veterinarian_clinic_assignment_id is null
            or accessing_clinic_id is not null
        )
);

-- ==================================================================
-- 2. RLS / privilege boundary. Audit evidence is itself protected.
--    No direct client CRUD, no RLS policies, no audit-history read
--    API in Slice 11. An audited User does not gain SELECT merely
--    because acting_user_id = that User. The only write path is the
--    internal SECURITY DEFINER capture primitive below.
-- ==================================================================

alter table public.medical_access_audit_events enable row level security;

revoke all privileges on table public.medical_access_audit_events
    from public, anon, authenticated;

-- ==================================================================
-- 3. Establishment-time identity / context coherence.
--
--    BEFORE INSERT, following the deployed
--    assert_care_authorization_establishment / trigger-wrapper
--    pattern. Ordinary (non-locking) reads are safe here: every
--    compared column on every referenced parent is immutable under an
--    already-deployed trigger. This boundary validates RELATIONAL
--    identity/context coherence only and never authorizes access.
-- ==================================================================

create function public.assert_medical_access_audit_event_establishment(
    p_acting_user_id uuid,
    p_pet_id uuid,
    p_occurred_at timestamptz,
    p_guardianship_id uuid,
    p_care_authorization_id uuid,
    p_accessing_clinic_id uuid,
    p_accessing_organization_id uuid,
    p_appointment_id uuid,
    p_organization_membership_id uuid,
    p_organization_responsibility_grant_id uuid,
    p_veterinarian_clinic_assignment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    guardianship_row public.guardianships%rowtype;
    care_auth_row public.care_authorizations%rowtype;
    appointment_row public.appointments%rowtype;
    membership_row public.organization_memberships%rowtype;
    responsibility_grant_row public.organization_responsibility_grants%rowtype;
    clinic_assignment_row public.veterinarian_clinic_assignments%rowtype;
    clinic_organization_id uuid;
    vca_membership_user_id uuid;
begin
    -- occurred_at: finite stored fact, never in the future. The table
    -- CHECK already enforces isfinite(); the future-time rejection is
    -- intentionally here because it is wall-clock dependent.
    if p_occurred_at is null or not isfinite(p_occurred_at) then
        raise exception 'Medical Access Audit Event occurred_at must be a finite timestamp'
            using errcode = '22023';
    end if;

    if p_occurred_at > clock_timestamp() then
        raise exception 'Medical Access Audit Event occurred_at cannot be in the future'
            using errcode = '22023';
    end if;

    -- Guardianship provenance: identity coherence only. Currentness
    -- (effective_end) is NOT checked, so a DENIED former-Guardian
    -- attempt can still preserve the ended period.
    if p_guardianship_id is not null then
        select guardianship.*
        into guardianship_row
        from public.guardianships as guardianship
        where guardianship.id = p_guardianship_id;

        if not found then
            raise exception 'Referenced Guardianship does not exist'
                using errcode = '23503';
        end if;

        if guardianship_row.user_id <> p_acting_user_id then
            raise exception 'Audit Event Guardianship must belong to the acting User'
                using errcode = '23514';
        end if;

        if guardianship_row.pet_id <> p_pet_id then
            raise exception 'Audit Event Guardianship must concern the Audit Event Pet'
                using errcode = '23514';
        end if;
    end if;

    -- Accessing Clinic / accessing Organization coherence (only when
    -- both are present).
    if p_accessing_clinic_id is not null
       and p_accessing_organization_id is not null then
        select clinic.organization_id
        into clinic_organization_id
        from public.clinics as clinic
        where clinic.id = p_accessing_clinic_id;

        if not found then
            raise exception 'Referenced accessing Clinic does not exist'
                using errcode = '23503';
        end if;

        if clinic_organization_id <> p_accessing_organization_id then
            raise exception 'Accessing Clinic must belong to the accessing Organization'
                using errcode = '23514';
        end if;
    end if;

    -- Care Authorization provenance: Pet coherence always; provider
    -- coherence only where the accessing provider context is present.
    -- lifecycle_state is NOT checked (REVOKED/ENDED remain valid
    -- DENIED-event provenance).
    if p_care_authorization_id is not null then
        select care_auth.*
        into care_auth_row
        from public.care_authorizations as care_auth
        where care_auth.id = p_care_authorization_id;

        if not found then
            raise exception 'Referenced Care Authorization does not exist'
                using errcode = '23503';
        end if;

        if care_auth_row.pet_id <> p_pet_id then
            raise exception 'Audit Event Care Authorization must concern the Audit Event Pet'
                using errcode = '23514';
        end if;

        if p_accessing_clinic_id is not null
           and care_auth_row.clinic_id <> p_accessing_clinic_id then
            raise exception 'Audit Event Care Authorization must match the accessing Clinic'
                using errcode = '23514';
        end if;

        if p_accessing_organization_id is not null
           and care_auth_row.organization_id <> p_accessing_organization_id then
            raise exception 'Audit Event Care Authorization must match the accessing Organization'
                using errcode = '23514';
        end if;
    end if;

    -- Appointment context: Pet coherence always; Clinic coherence only
    -- where the accessing Clinic is present.
    if p_appointment_id is not null then
        select appointment.*
        into appointment_row
        from public.appointments as appointment
        where appointment.id = p_appointment_id;

        if not found then
            raise exception 'Referenced Appointment does not exist'
                using errcode = '23503';
        end if;

        if appointment_row.pet_id <> p_pet_id then
            raise exception 'Audit Event Appointment must concern the Audit Event Pet'
                using errcode = '23514';
        end if;

        if p_accessing_clinic_id is not null
           and appointment_row.clinic_id <> p_accessing_clinic_id then
            raise exception 'Audit Event Appointment must match the accessing Clinic'
                using errcode = '23514';
        end if;
    end if;

    -- Organization Membership provenance: must belong to the acting
    -- User; Organization coherence only where accessing Organization
    -- is present. Currentness is NOT checked.
    if p_organization_membership_id is not null then
        select membership.*
        into membership_row
        from public.organization_memberships as membership
        where membership.id = p_organization_membership_id;

        if not found then
            raise exception 'Referenced Organization Membership does not exist'
                using errcode = '23503';
        end if;

        if membership_row.user_id <> p_acting_user_id then
            raise exception 'Audit Event Organization Membership must belong to the acting User'
                using errcode = '23514';
        end if;

        if p_accessing_organization_id is not null
           and membership_row.organization_id <> p_accessing_organization_id then
            raise exception 'Audit Event Organization Membership must match the accessing Organization'
                using errcode = '23514';
        end if;
    end if;

    -- Responsibility Grant provenance: must belong to the supplied
    -- Membership provenance; scope-specific provider coherence per the
    -- deployed grant shape (scope_type in ('ORGANIZATION','CLINIC'),
    -- clinic_id present only for CLINIC scope). Currentness is NOT
    -- checked.
    if p_organization_responsibility_grant_id is not null then
        if p_organization_membership_id is null then
            raise exception 'Audit Event Responsibility Grant provenance requires its Organization Membership provenance'
                using errcode = '23514';
        end if;

        select responsibility_grant.*
        into responsibility_grant_row
        from public.organization_responsibility_grants as responsibility_grant
        where responsibility_grant.id = p_organization_responsibility_grant_id;

        if not found then
            raise exception 'Referenced Organization Responsibility Grant does not exist'
                using errcode = '23503';
        end if;

        if responsibility_grant_row.membership_id <> p_organization_membership_id then
            raise exception 'Audit Event Responsibility Grant must belong to the Audit Event Organization Membership'
                using errcode = '23514';
        end if;

        if responsibility_grant_row.scope_type = 'ORGANIZATION' then
            if p_accessing_organization_id is null then
                raise exception 'Organization-scoped Responsibility Grant provenance requires an accessing Organization'
                    using errcode = '23514';
            end if;

            if membership_row.organization_id <> p_accessing_organization_id then
                raise exception 'Organization-scoped Responsibility Grant must belong to the accessing Organization'
                    using errcode = '23514';
            end if;
        elsif responsibility_grant_row.scope_type = 'CLINIC' then
            if p_accessing_clinic_id is null then
                raise exception 'Clinic-scoped Responsibility Grant provenance requires an accessing Clinic'
                    using errcode = '23514';
            end if;

            if responsibility_grant_row.clinic_id <> p_accessing_clinic_id then
                raise exception 'Clinic-scoped Responsibility Grant must match the accessing Clinic'
                    using errcode = '23514';
            end if;
        else
            raise exception 'Unsupported Responsibility Grant scope_type for Audit Event provenance'
                using errcode = '23514';
        end if;
    end if;

    -- Veterinarian Clinic Assignment provenance: bound to the
    -- accessing Clinic; resolves to the acting User through its
    -- immutable supporting Organization Membership. Slice 4 established
    -- Professional Profile User = supporting Membership User at VCA
    -- creation, and both veterinarian_clinic_assignments.supporting_membership_id
    -- and organization_memberships.user_id are immutable historical
    -- facts, so this derivation is safe with an ordinary read.
    -- Currentness is NOT checked.
    if p_veterinarian_clinic_assignment_id is not null then
        if p_accessing_clinic_id is null then
            raise exception 'Audit Event Veterinarian Clinic Assignment provenance requires an accessing Clinic'
                using errcode = '23514';
        end if;

        select clinic_assignment.*
        into clinic_assignment_row
        from public.veterinarian_clinic_assignments as clinic_assignment
        where clinic_assignment.id = p_veterinarian_clinic_assignment_id;

        if not found then
            raise exception 'Referenced Veterinarian Clinic Assignment does not exist'
                using errcode = '23503';
        end if;

        if clinic_assignment_row.clinic_id <> p_accessing_clinic_id then
            raise exception 'Audit Event Veterinarian Clinic Assignment must match the accessing Clinic'
                using errcode = '23514';
        end if;

        select supporting_membership.user_id
        into vca_membership_user_id
        from public.organization_memberships as supporting_membership
        where supporting_membership.id = clinic_assignment_row.supporting_membership_id;

        if not found then
            raise exception 'Veterinarian Clinic Assignment supporting Organization Membership does not exist'
                using errcode = '23503';
        end if;

        if vca_membership_user_id <> p_acting_user_id then
            raise exception 'Audit Event Veterinarian Clinic Assignment must resolve to the acting User'
                using errcode = '23514';
        end if;

        if p_organization_membership_id is not null
           and clinic_assignment_row.supporting_membership_id <> p_organization_membership_id then
            raise exception 'Audit Event Veterinarian Clinic Assignment must reference the Audit Event Organization Membership'
                using errcode = '23514';
        end if;
    end if;

    return;
end;
$$;

revoke all privileges
on function public.assert_medical_access_audit_event_establishment(
    uuid, uuid, timestamptz, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
)
from public, anon, authenticated;

create function public.enforce_medical_access_audit_event_establishment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.assert_medical_access_audit_event_establishment(
        new.acting_user_id,
        new.pet_id,
        new.occurred_at,
        new.guardianship_id,
        new.care_authorization_id,
        new.accessing_clinic_id,
        new.accessing_organization_id,
        new.appointment_id,
        new.organization_membership_id,
        new.organization_responsibility_grant_id,
        new.veterinarian_clinic_assignment_id
    );

    return new;
end;
$$;

revoke all privileges
on function public.enforce_medical_access_audit_event_establishment()
from public, anon, authenticated;

create trigger medical_access_audit_events_establishment
before insert on public.medical_access_audit_events
for each row
execute function public.enforce_medical_access_audit_event_establishment();

-- ==================================================================
-- 4. Immutability. Medical Access Audit Events are append-only
--    historical security evidence: there is no legitimate post-insert
--    transition. Every UPDATE and every DELETE is rejected. No
--    correction/replaced_by/superseded_by/soft-delete state. Future
--    approved correction, if any, remains append-only and belongs to
--    another slice.
-- ==================================================================

create function public.enforce_medical_access_audit_event_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Medical Access Audit Events cannot be deleted'
            using errcode = '23514';
    elsif tg_op = 'UPDATE' then
        raise exception 'Medical Access Audit Events are append-only; UPDATE is rejected'
            using errcode = '23514';
    else
        raise exception 'Unexpected operation on medical_access_audit_events immutability trigger'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_medical_access_audit_event_immutability()
from public, anon, authenticated;

create trigger medical_access_audit_events_preserve_history
before update or delete on public.medical_access_audit_events
for each row
execute function public.enforce_medical_access_audit_event_immutability();

-- ==================================================================
-- 5. Internal trusted capture primitive.
--
-- Records audit evidence and nothing else: NO authorization, NO
-- currentness evaluation, NO capability/Entitlement check, NO
-- medical-access decision. It never raises merely because
-- p_outcome = 'DENIED' — both PERMITTED and DENIED are valid evidence
-- values. Row-shape and identity/context coherence are enforced by
-- the table constraints and the establishment trigger. recorded_at
-- uses its table default and is not an argument.
--
-- TRUST BOUNDARY: there is NO client-facing audit-recording API in
-- Slice 11. EXECUTE is revoked from PUBLIC/anon/authenticated and is
-- NOT granted back to any client role. Only future trusted
-- SECURITY DEFINER protected operations, running under their trusted
-- execution identity, may call it. A DENIED Event must be committed
-- by a transaction that does not also roll back to signal the denial;
-- that durable denial-signalling architecture is a Slice 12 decision
-- and is intentionally not implemented here (no autonomous-transaction
-- hacks, no dblink, no pg_background, no orchestration).
-- ==================================================================

create function public.establish_medical_access_audit_event(
    p_acting_user_id uuid,
    p_pet_id uuid,
    p_operation text,
    p_outcome text,
    p_actor_context text,
    p_protected_resource_scope text,
    p_occurred_at timestamptz,
    p_guardianship_id uuid default null,
    p_care_authorization_id uuid default null,
    p_accessing_clinic_id uuid default null,
    p_accessing_organization_id uuid default null,
    p_appointment_id uuid default null,
    p_organization_membership_id uuid default null,
    p_organization_responsibility_grant_id uuid default null,
    p_veterinarian_clinic_assignment_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_event_id uuid;
begin
    insert into public.medical_access_audit_events (
        occurred_at,
        operation,
        outcome,
        actor_context,
        protected_resource_scope,
        acting_user_id,
        pet_id,
        guardianship_id,
        care_authorization_id,
        accessing_clinic_id,
        accessing_organization_id,
        appointment_id,
        organization_membership_id,
        organization_responsibility_grant_id,
        veterinarian_clinic_assignment_id
    )
    values (
        p_occurred_at,
        p_operation,
        p_outcome,
        p_actor_context,
        p_protected_resource_scope,
        p_acting_user_id,
        p_pet_id,
        p_guardianship_id,
        p_care_authorization_id,
        p_accessing_clinic_id,
        p_accessing_organization_id,
        p_appointment_id,
        p_organization_membership_id,
        p_organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id
    )
    returning id into new_event_id;

    return new_event_id;
end;
$$;

revoke all privileges
on function public.establish_medical_access_audit_event(
    uuid, uuid, text, text, text, text, timestamptz,
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
)
from public, anon, authenticated;

commit;
