-- Editable Clinical Record Entries with preserved versions — Punto 8, stage M5
-- (ADR-011; SPEC-MED-010 BR-4, BR-5, BR-7, BR-18, BR-20, BR-22, BR-23,
-- BR-23b, BR-24, BR-25; SPEC-MED-004 as superseded by it;
-- docs/CLINICAL_DOCUMENTATION_TRANSITION.md).
--
-- Requires M2–M4. To the Veterinarian an Entry becomes editable by its author;
-- in persistence nothing is overwritten:
--
--   0. Fail-closed guard: the M4 contract is present.
--   1. Clinical Amendments become the version log. Existing rows are kind
--      ADDENDUM (reason + additive text, unchanged). New rows are kind EDIT:
--      the complete new version — version_number (the Entry itself is
--      version 1), category, OTHER context, content (amendment_content), no
--      reason — by the Entry's author, numbered without gaps (unique per
--      Entry), append-only. No new ADDENDUM can be written.
--   2. New Entries carry no clinical event time: the only date is the
--      server's recording time. clinical_event_at stays as recorded on older
--      Entries and keeps their history order.
--   3. Version helpers; every read presents the current version, its time
--      (edited_at), and every earlier version, under the Entry's own read
--      permission only.
--   4. create_appointment_clinical_entry without event-time arguments (the
--      eight-argument form is dropped; the request digest keeps its shape).
--   5. edit_appointment_clinical_entry (BR-23b): author only, idempotent,
--      stale-version safe, no Entitlement, independent of the Care
--      Authorization.
--   6. The reason-and-addition operations are dropped
--      (create_appointment_clinical_amendment, create_clinical_amendment).
--
-- No row is updated or deleted. No DROP ... CASCADE is used.
begin;

-- ==================================================================
-- 0. Fail-closed guard.
-- ==================================================================

do $guard$
begin
    if to_regprocedure('public.authorize_guardian_clinical_attachment_download(uuid, uuid)') is null
       or to_regprocedure('public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean)') is null then
        raise exception 'M5 refused: the M2–M4 documentation contract is not in place'
            using errcode = '55000';
    end if;
    if exists (
        select 1 from public.clinical_amendments as amendment
        join public.clinical_record_entries as entry on entry.id = amendment.original_clinical_record_entry_id
        where amendment.amending_user_id <> entry.created_by_user_id
    ) then
        raise exception 'M5 refused: an existing Amendment is not by its Entry''s author'
            using errcode = '55000';
    end if;
end;
$guard$;

-- ==================================================================
-- 1. Clinical Amendments as the version log.
-- ==================================================================

-- Adding a column with a default writes no row and fires no row trigger:
-- every existing Amendment becomes ADDENDUM with its facts unchanged.
alter table public.clinical_amendments
    add column change_kind text not null default 'ADDENDUM',
    add column version_number integer,
    add column category text,
    add column other_category_context text;
alter table public.clinical_amendments alter column change_kind drop default;
alter table public.clinical_amendments alter column reason drop not null;

alter table public.clinical_amendments
    add constraint clinical_amendments_change_kind_check
        check (change_kind in ('ADDENDUM', 'EDIT')),
    add constraint clinical_amendments_change_shape_check check (
        (change_kind = 'ADDENDUM'
         and reason is not null and reason <> ''
         and version_number is null and category is null and other_category_context is null)
        or (change_kind = 'EDIT'
            and reason is null
            and version_number >= 2
            and amendment_content <> ''
            and category in ('EXAMINATION', 'DIAGNOSIS', 'TREATMENT', 'PROCEDURE', 'VACCINATION',
                             'PRESCRIPTION', 'LABORATORY_RESULT', 'IMAGING_RESULT', 'CLINICAL_NOTE', 'OTHER')
            and (category = 'OTHER' or other_category_context is null)
            and (other_category_context is null
                 or (other_category_context <> ''
                     and other_category_context = btrim(other_category_context, E' \t\n\r\f\013'))))
    ),
    add constraint clinical_amendments_entry_version_key
        unique (original_clinical_record_entry_id, version_number);

create or replace function public.enforce_clinical_amendment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    record_entry public.clinical_record_entries%rowtype;
    entry_clinic_id uuid;
    entry_organization_id uuid;
    current_version integer;
begin
    if tg_op in ('UPDATE', 'DELETE') then
        raise exception 'Clinical Amendments are append-only' using errcode = '23514';
    end if;

    -- SPEC-MED-010 BR-18: only versioned edits are written since M5.
    if new.change_kind is distinct from 'EDIT' then
        raise exception 'Only EDIT versions may be added to a Clinical Record Entry' using errcode = '23514';
    end if;

    select entry_row.* into record_entry
    from public.clinical_record_entries as entry_row
    where entry_row.id = new.original_clinical_record_entry_id
    for share;
    if not found then
        raise exception 'Clinical Amendment requires its original Clinical Record Entry' using errcode = '23503';
    end if;

    if new.amending_user_id is distinct from record_entry.created_by_user_id then
        raise exception 'Only the original author may amend a Clinical Record Entry' using errcode = '23514';
    end if;

    if new.created_at < record_entry.created_at or new.created_at > clock_timestamp() then
        raise exception 'Clinical Amendment time must follow the Entry and not be in the future'
            using errcode = '23514';
    end if;

    -- Versions are numbered without gaps; the unique key rejects a duplicate.
    select coalesce(max(amendment.version_number), 1) into current_version
    from public.clinical_amendments as amendment
    where amendment.original_clinical_record_entry_id = new.original_clinical_record_entry_id;
    if new.version_number is distinct from current_version + 1 then
        raise exception 'A Clinical Record Entry version must follow its current version'
            using errcode = '23514';
    end if;

    select appointment.clinic_id, clinic.organization_id
    into entry_clinic_id, entry_organization_id
    from public.appointments as appointment
    join public.clinics as clinic on clinic.id = appointment.clinic_id
    where appointment.id = record_entry.appointment_id;
    perform public.assert_vca_user_provider_context(
        new.amending_veterinarian_clinic_assignment_id, new.amending_user_id,
        entry_clinic_id, entry_organization_id
    );

    return new;
end;
$$;

-- ==================================================================
-- 2. New Entries carry no clinical event time.
-- ==================================================================

create or replace function public.enforce_clinical_record_entry_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    appointment_record public.appointments%rowtype;
    clinic_organization_id uuid;
    assigned_clinic_assignment_id uuid;
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinical Record Entries cannot be deleted' using errcode = '23514';
    end if;
    if tg_op = 'UPDATE' then
        raise exception 'A recorded Clinical Record Entry is immutable' using errcode = '23514';
    end if;

    if new.created_at > clock_timestamp() then
        raise exception 'Clinical Record Entry cannot be recorded with a future timestamp'
            using errcode = '22023';
    end if;
    -- SPEC-MED-010 BR-5 (M5): the recording time is the only date.
    if new.clinical_event_at is not null then
        raise exception 'A new Clinical Record Entry carries no clinical event time'
            using errcode = '22023';
    end if;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = new.appointment_id;
    if not found then
        raise exception 'Clinical Record Entry requires its Appointment' using errcode = '23503';
    end if;
    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'A Clinical Record Entry requires a legitimately confirmed CONFIRMED or COMPLETED Appointment'
            using errcode = '23514';
    end if;

    select clinic.organization_id into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = appointment_record.clinic_id;
    perform public.assert_vca_user_provider_context(
        new.creator_veterinarian_clinic_assignment_id, new.created_by_user_id,
        appointment_record.clinic_id, clinic_organization_id
    );

    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = new.appointment_id
      and assignment.effective_end is null;
    if assigned_clinic_assignment_id is distinct from new.creator_veterinarian_clinic_assignment_id
       or not public.appointment_veterinarian_is_eligible(
           new.creator_veterinarian_clinic_assignment_id, appointment_record.clinic_id) then
        raise exception 'A Clinical Record Entry must be recorded by the Appointment''s current eligible assigned Veterinarian'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

-- ==================================================================
-- 3. Versions. Internal helpers: never client-executable.
-- ==================================================================

-- Every version of one Entry: the Entry itself (version 1) and its EDITs.
create function public.clinical_entry_versions(p_entry_id uuid)
returns table (
    version_number integer,
    category text,
    other_category_context text,
    clinical_content text,
    created_at timestamptz,
    author_user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
    select 1, entry.category, entry.other_category_context, entry.clinical_content,
           entry.created_at, entry.created_by_user_id
    from public.clinical_record_entries as entry
    where entry.id = p_entry_id
    union all
    select amendment.version_number, amendment.category, amendment.other_category_context,
           amendment.amendment_content, amendment.created_at, amendment.amending_user_id
    from public.clinical_amendments as amendment
    where amendment.original_clinical_record_entry_id = p_entry_id
      and amendment.change_kind = 'EDIT'
$$;

-- The current version; edited_at is null for an Entry never edited.
create function public.clinical_entry_current(p_entry_id uuid)
returns table (
    version_number integer,
    category text,
    other_category_context text,
    clinical_content text,
    edited_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select version.version_number, version.category, version.other_category_context,
           version.clinical_content,
           case when version.version_number > 1 then version.created_at end
    from public.clinical_entry_versions(p_entry_id) as version
    order by version.version_number desc
    limit 1
$$;

-- The earlier versions, oldest first, at most 100.
create function public.clinical_entry_previous_versions(p_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'version', earlier.version_number,
               'category', earlier.category,
               'other_category_context', earlier.other_category_context,
               'clinical_content', earlier.clinical_content,
               'created_at', earlier.created_at
           ) order by earlier.version_number), '[]'::jsonb)
    from (
        select version.*
        from public.clinical_entry_versions(p_entry_id) as version
        where version.version_number < (
            select max(every_version.version_number)
            from public.clinical_entry_versions(p_entry_id) as every_version)
        order by version.version_number
        limit 100
    ) as earlier
$$;

-- Legacy reason-and-addition corrections only (kind ADDENDUM).
create or replace function public.clinical_history_amendments(p_entry_id uuid)
returns table (
    amendment_id uuid,
    reason text,
    amendment_content text,
    created_at timestamptz,
    amending_user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
    select amendment.id, amendment.reason, amendment.amendment_content,
           amendment.created_at, amendment.amending_user_id
    from public.clinical_amendments as amendment
    where amendment.original_clinical_record_entry_id = p_entry_id
      and amendment.change_kind = 'ADDENDUM'
    order by amendment.created_at, amendment.id
    limit 100
$$;

-- The shared history page now carries the current version.
drop function public.clinical_history_page(uuid, integer, timestamptz, uuid);
create function public.clinical_history_page(
    p_pet_id uuid,
    p_limit integer,
    p_before_history_order_at timestamptz,
    p_before_entry_id uuid
)
returns table (
    entry_id uuid,
    history_order_at timestamptz,
    category text,
    other_category_context text,
    clinical_content text,
    clinical_event_at timestamptz,
    finalized_at timestamptz,
    clinic_display_name text,
    organization_display_name text,
    appointment_id uuid,
    created_by_user_id uuid,
    amendment_count integer,
    current_version integer,
    edited_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select record_entry.id,
           -- The order follows the original recording (or a historical event
           -- time); an edit never moves an Entry.
           coalesce(record_entry.clinical_event_at, record_entry.created_at),
           current_version.category,
           current_version.other_category_context,
           current_version.clinical_content,
           record_entry.clinical_event_at,
           -- Recording is publication (BR-4).
           record_entry.created_at,
           (select profile.display_name
            from public.clinic_public_profiles as profile
            where profile.clinic_id = appointment.clinic_id),
           (select organization.display_name
            from public.veterinary_organizations as organization
            where organization.id = clinic.organization_id),
           record_entry.appointment_id,
           record_entry.created_by_user_id,
           (select count(*)::integer
            from public.clinical_amendments as amendment
            where amendment.original_clinical_record_entry_id = record_entry.id
              and amendment.change_kind = 'ADDENDUM'),
           current_version.version_number,
           current_version.edited_at
    from public.clinical_record_entries as record_entry
    join public.appointments as appointment
      on appointment.id = record_entry.appointment_id
    join public.clinics as clinic
      on clinic.id = appointment.clinic_id
    cross join lateral public.clinical_entry_current(record_entry.id) as current_version
    where appointment.pet_id = p_pet_id
      and (p_before_history_order_at is null
           or (coalesce(record_entry.clinical_event_at, record_entry.created_at), record_entry.id)
              < (p_before_history_order_at, p_before_entry_id))
    order by coalesce(record_entry.clinical_event_at, record_entry.created_at) desc,
             record_entry.id desc
    limit p_limit + 1
$$;

do $grants$
declare signature text;
begin
    foreach signature in array array[
        'public.clinical_entry_versions(uuid)',
        'public.clinical_entry_current(uuid)',
        'public.clinical_entry_previous_versions(uuid)',
        'public.clinical_history_amendments(uuid)',
        'public.clinical_history_page(uuid, integer, timestamptz, uuid)'
    ] loop
        execute format('revoke all privileges on function %s from public, anon, authenticated, service_role', signature);
    end loop;
end;
$grants$;

-- ==================================================================
-- 3b. Reads present the current version and its history.
-- ==================================================================

create or replace function public.view_appointment_clinical_record(
    p_clinic_id uuid,
    p_appointment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    actor_found boolean := false;
    appointment_record public.appointments%rowtype;
    care_auth_id uuid;
    clinic_organization_id uuid;
    assigned_clinic_assignment_id uuid;
    has_entries boolean;
    unavailable_reason text;
    entries_payload jsonb;
    entries_truncated boolean;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    select * into actor
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    actor_found := found;

    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id;
    if not found then
        return jsonb_build_object('status', 'DENIED');
    end if;

    select clinic.organization_id into clinic_organization_id
    from public.clinics as clinic where clinic.id = appointment_record.clinic_id;
    select care_auth.id into care_auth_id
    from public.care_authorizations as care_auth
    where care_auth.appointment_id = appointment_record.id
      and care_auth.purpose = 'APPOINTMENT_CARE';
    has_entries := exists (
        select 1 from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
    );

    if not actor_found then
        if has_entries then
            perform public.establish_medical_access_audit_event(
                p_acting_user_id => acting_user_id,
                p_pet_id => appointment_record.pet_id,
                p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD',
                p_outcome => 'DENIED',
                p_actor_context => 'PROFESSIONAL_CLINICAL',
                p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
                p_occurred_at => clock_timestamp(),
                p_care_authorization_id => care_auth_id,
                p_accessing_clinic_id => appointment_record.clinic_id,
                p_accessing_organization_id => clinic_organization_id,
                p_appointment_id => appointment_record.id
            );
        end if;
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- Advisory documentation state (BR-20); every write re-validates.
    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = appointment_record.id
      and assignment.effective_end is null;
    unavailable_reason := case
        when not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state)
            then 'APPOINTMENT_STATE'
        when assigned_clinic_assignment_id is null
            then 'NO_VETERINARIAN_ASSIGNED'
        when assigned_clinic_assignment_id <> actor.veterinarian_clinic_assignment_id
             or not public.appointment_veterinarian_is_eligible(assigned_clinic_assignment_id, p_clinic_id)
            then 'NOT_ASSIGNED_VETERINARIAN'
        when not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE')
            then 'CLINICAL_SERVICE_UNAVAILABLE'
    end;

    select coalesce(jsonb_agg(jsonb_build_object(
               'entry_id', page.id,
               'category', current_version.category,
               'other_category_context', current_version.other_category_context,
               'clinical_content', current_version.clinical_content,
               'clinical_event_at', page.clinical_event_at,
               'recorded_at', page.created_at,
               'recorded_by_me', page.created_by_user_id = acting_user_id,
               'may_edit', page.created_by_user_id = acting_user_id,
               'version', current_version.version_number,
               'edited_at', current_version.edited_at,
               'previous_versions', public.clinical_entry_previous_versions(page.id),
               'previous_versions_truncated', current_version.version_number - 1 > 100,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'amendment_id', amendment.amendment_id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at,
                       'amended_by_me', amendment.amending_user_id = acting_user_id
                   ) order by amendment.created_at, amendment.amendment_id)
                   from public.clinical_history_amendments(page.id) as amendment
               ), '[]'::jsonb),
               'amendments_truncated', (
                   select count(*) > 100 from public.clinical_amendments as counted
                   where counted.original_clinical_record_entry_id = page.id
                     and counted.change_kind = 'ADDENDUM')
           ) order by page.created_at, page.id), '[]'::jsonb)
    into entries_payload
    from (
        select entry.*
        from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
        order by entry.created_at, entry.id
        limit 100
    ) as page
    cross join lateral public.clinical_entry_current(page.id) as current_version;
    entries_truncated := (
        select count(*) > 100 from public.clinical_record_entries as entry
        where entry.appointment_id = appointment_record.id
    );

    -- One audit event per read that returns medical information, written
    -- before release (ADR-004).
    if has_entries then
        perform public.establish_medical_access_audit_event(
            p_acting_user_id => acting_user_id,
            p_pet_id => appointment_record.pet_id,
            p_operation => 'VIEW_APPOINTMENT_CLINICAL_RECORD',
            p_outcome => 'PERMITTED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'APPOINTMENT_CLINICAL_RECORD',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => care_auth_id,
            p_accessing_clinic_id => p_clinic_id,
            p_accessing_organization_id => actor.organization_id,
            p_appointment_id => appointment_record.id,
            p_organization_membership_id => actor.organization_membership_id,
            p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
            p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id
        );
    end if;

    return jsonb_build_object(
        'status', 'PERMITTED',
        'appointment', jsonb_build_object(
            'appointment_id', appointment_record.id,
            'lifecycle_state', appointment_record.lifecycle_state),
        'documentation', jsonb_build_object(
            'can_record', unavailable_reason is null,
            'unavailable_reason', unavailable_reason),
        'entries', entries_payload,
        'entries_truncated', entries_truncated
    );
end;
$$;

create or replace function public.view_appointment_professional_medical_history(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    locked_actor record;
    actor_found boolean := false;
    authorized boolean := false;
    bounded_limit integer;
    appointment_record public.appointments%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    entries_payload jsonb;
    has_more boolean;
    next_order_at timestamptz;
    next_entry_id uuid;
begin
    -- 1. Authentication.
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Argument shape only; no stored data is consulted.
    if p_limit is null or p_limit < 1 then
        raise exception 'Page limit must be positive' using errcode = '22023', hint = 'INVALID_LIMIT';
    end if;
    if (p_before_history_order_at is null) <> (p_before_entry_id is null)
       or (p_before_history_order_at is not null and not isfinite(p_before_history_order_at)) then
        raise exception 'History cursor is invalid' using errcode = '22023', hint = 'INVALID_CURSOR';
    end if;
    bounded_limit := least(p_limit, 100);

    -- 3. Authority before any target: the current exact-Clinic Veterinarian
    --    context holding CLINICAL_CARE, share-locked so offboarding either
    --    precedes this read or waits for it, then decided again.
    select * into actor
    from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_CARE');
    if found then
        perform 1 from public.organization_memberships as membership
        where membership.id = actor.organization_membership_id for share;
        perform 1 from public.organization_responsibility_grants as grant_record
        where grant_record.id = actor.organization_responsibility_grant_id for share;
        perform 1 from public.veterinarian_clinic_assignments as assignment
        where assignment.id = actor.veterinarian_clinic_assignment_id for share;
        select context.* into locked_actor
        from public.clinical_actor_context_at(acting_user_id, p_clinic_id, 'CLINICAL_CARE') as context
        where context.organization_membership_id = actor.organization_membership_id
          and context.organization_responsibility_grant_id = actor.organization_responsibility_grant_id
          and context.veterinarian_clinic_assignment_id = actor.veterinarian_clinic_assignment_id;
        actor_found := found;
    end if;
    authorized := actor_found
        and public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE');

    -- 4. The Appointment of the named Clinic. Unknown or foreign: no Pet
    --    context, nothing audited, the same denial.
    if authorized then
        select appointment.* into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id
        for share;
    else
        select appointment.* into appointment_record
        from public.appointments as appointment
        where appointment.id = p_appointment_id
          and appointment.clinic_id = p_clinic_id;
    end if;
    if not found then
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- 5. Its Appointment-derived Care Authorization.
    if authorized then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE'
        for share;
    else
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.appointment_id = appointment_record.id
          and care_auth.purpose = 'APPOINTMENT_CARE';
    end if;

    -- 6. The history window; any refusal is one audited, uniform denial.
    if not authorized
       or not public.appointment_professional_history_accessible(appointment_record.id, clock_timestamp()) then
        perform public.establish_medical_access_audit_event(
            p_acting_user_id => acting_user_id,
            p_pet_id => appointment_record.pet_id,
            p_operation => 'VIEW_PET_MEDICAL_HISTORY',
            p_outcome => 'DENIED',
            p_actor_context => 'PROFESSIONAL_CLINICAL',
            p_protected_resource_scope => 'LONGITUDINAL_MEDICAL_HISTORY',
            p_occurred_at => clock_timestamp(),
            p_care_authorization_id => care_auth_record.id,
            p_accessing_clinic_id => appointment_record.clinic_id,
            p_accessing_organization_id => (
                select clinic.organization_id from public.clinics as clinic
                where clinic.id = appointment_record.clinic_id),
            p_appointment_id => appointment_record.id,
            p_organization_membership_id =>
                case when actor_found then actor.organization_membership_id end,
            p_organization_responsibility_grant_id =>
                case when actor_found then actor.organization_responsibility_grant_id end,
            p_veterinarian_clinic_assignment_id =>
                case when actor_found then actor.veterinarian_clinic_assignment_id end
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    -- 7. The Pet's complete history, from every Clinic and Organization, in
    --    each Entry's current version, assembled in one statement.
    with page as (
        select *
        from public.clinical_history_page(
            appointment_record.pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id
        )
    ), visible as (
        select * from page
        order by page.history_order_at desc, page.entry_id desc
        limit bounded_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
               'entry_id', visible.entry_id,
               'category', visible.category,
               'other_category_context', visible.other_category_context,
               'clinical_content', visible.clinical_content,
               'clinical_event_at', visible.clinical_event_at,
               'history_order_at', visible.history_order_at,
               'finalized_at', visible.finalized_at,
               'clinic_display_name', visible.clinic_display_name,
               'organization_display_name', visible.organization_display_name,
               'is_this_appointment', visible.appointment_id is not distinct from appointment_record.id,
               'author', jsonb_build_object(
                   'display_name', public.clinical_provenance_display_name(visible.created_by_user_id),
                   'is_me', visible.created_by_user_id = acting_user_id),
               -- An Entry is published by its own author when recorded.
               'finalizer', null,
               'version', visible.current_version,
               'edited_at', visible.edited_at,
               'previous_versions', public.clinical_entry_previous_versions(visible.entry_id),
               'previous_versions_truncated', visible.current_version - 1 > 100,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'amendment_id', amendment.amendment_id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at,
                       'author', jsonb_build_object(
                           'display_name', public.clinical_provenance_display_name(amendment.amending_user_id),
                           'is_me', amendment.amending_user_id = acting_user_id)
                   ) order by amendment.created_at, amendment.amendment_id)
                   from public.clinical_history_amendments(visible.entry_id) as amendment
               ), '[]'::jsonb),
               'amendment_count', visible.amendment_count,
               'amendments_truncated', visible.amendment_count > 100
           ) order by visible.history_order_at desc, visible.entry_id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page),
           (array_agg(visible.history_order_at order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit],
           (array_agg(visible.entry_id order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit]
    into entries_payload, has_more, next_order_at, next_entry_id
    from visible;

    -- 8. One meaningful protected access per page, before release, with the
    --    current access context (SPEC-MED-005 BR-45).
    perform public.establish_medical_access_audit_event(
        p_acting_user_id => acting_user_id,
        p_pet_id => appointment_record.pet_id,
        p_operation => 'VIEW_PET_MEDICAL_HISTORY',
        p_outcome => 'PERMITTED',
        p_actor_context => 'PROFESSIONAL_CLINICAL',
        p_protected_resource_scope => 'LONGITUDINAL_MEDICAL_HISTORY',
        p_occurred_at => clock_timestamp(),
        p_care_authorization_id => care_auth_record.id,
        p_accessing_clinic_id => p_clinic_id,
        p_accessing_organization_id => actor.organization_id,
        p_appointment_id => appointment_record.id,
        p_organization_membership_id => actor.organization_membership_id,
        p_organization_responsibility_grant_id => actor.organization_responsibility_grant_id,
        p_veterinarian_clinic_assignment_id => actor.veterinarian_clinic_assignment_id
    );

    return jsonb_build_object(
        'status', 'PERMITTED',
        'entries', entries_payload,
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at,
            'before_entry_id', next_entry_id
        ) end
    );
end;
$$;

create or replace function public.view_guardian_pet_medical_history(
    p_pet_id uuid,
    p_limit integer default 50,
    p_before_history_order_at timestamptz default null,
    p_before_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    guardianship_record public.guardianships%rowtype;
    bounded_limit integer;
    result_payload jsonb;
    has_more boolean;
    next_order_at timestamptz;
    next_entry_id uuid;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    if p_limit is null or p_limit < 1 then raise exception 'Page limit must be positive' using errcode = '22023'; end if;
    if (p_before_history_order_at is null) <> (p_before_entry_id is null) then
        raise exception 'History cursor components must be supplied together' using errcode = '22023';
    end if;
    if p_before_history_order_at is not null and not isfinite(p_before_history_order_at) then
        raise exception 'History cursor timestamp must be finite' using errcode = '22023';
    end if;
    bounded_limit := least(p_limit, 100);
    if not exists (select 1 from public.pets as pet where pet.id = p_pet_id) then
        return jsonb_build_object('status', 'DENIED');
    end if;
    select guardianship.* into guardianship_record
    from public.guardianships as guardianship
    where guardianship.pet_id = p_pet_id and guardianship.user_id = acting_user_id
      and guardianship.effective_start <= clock_timestamp() and guardianship.effective_end is null
    for share;
    if not found then
        select guardianship.* into guardianship_record
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = acting_user_id
        order by guardianship.effective_start desc, guardianship.id desc
        limit 1;
        perform public.establish_medical_access_audit_event(
            acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'DENIED',
            'GUARDIAN', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
            guardianship_record.id, null, null, null, null, null, null, null, null, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    with page as (
        select *
        from public.clinical_history_page(p_pet_id, bounded_limit, p_before_history_order_at, p_before_entry_id)
    ), visible as (
        select * from page
        order by page.history_order_at desc, page.entry_id desc
        limit bounded_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', visible.entry_id,
               'category', visible.category,
               'other_category_context', visible.other_category_context,
               'clinical_content', visible.clinical_content,
               'clinical_event_at', visible.clinical_event_at,
               'history_order_at', visible.history_order_at,
               'finalized_at', visible.finalized_at,
               'clinic_display_name', visible.clinic_display_name,
               'organization_display_name', visible.organization_display_name,
               'version', visible.current_version,
               'edited_at', visible.edited_at,
               'previous_versions', public.clinical_entry_previous_versions(visible.entry_id),
               'previous_versions_truncated', visible.current_version - 1 > 100,
               'amendments', coalesce((
                   select jsonb_agg(jsonb_build_object(
                       'id', amendment.amendment_id,
                       'reason', amendment.reason,
                       'amendment_content', amendment.amendment_content,
                       'created_at', amendment.created_at
                   ) order by amendment.created_at, amendment.amendment_id)
                   from public.clinical_history_amendments(visible.entry_id) as amendment
               ), '[]'::jsonb),
               'amendment_count', visible.amendment_count,
               'amendments_truncated', visible.amendment_count > 100,
               'attachments', public.clinical_attachment_metadata_for_entry(visible.entry_id, false)
           ) order by visible.history_order_at desc, visible.entry_id desc), '[]'::jsonb),
           (select count(*) > bounded_limit from page),
           (array_agg(visible.history_order_at order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit],
           (array_agg(visible.entry_id order by visible.history_order_at desc, visible.entry_id desc))[bounded_limit]
    into result_payload, has_more, next_order_at, next_entry_id
    from visible;

    perform public.establish_medical_access_audit_event(
        acting_user_id, p_pet_id, 'VIEW_PET_MEDICAL_HISTORY', 'PERMITTED',
        'GUARDIAN', 'LONGITUDINAL_MEDICAL_HISTORY', clock_timestamp(),
        guardianship_record.id, null, null, null, null, null, null, null, null, null
    );
    return jsonb_build_object(
        'status', 'PERMITTED', 'payload', jsonb_build_object('entries', result_payload),
        'cursor', case when has_more then jsonb_build_object(
            'before_history_order_at', next_order_at, 'before_entry_id', next_entry_id
        ) else null end
    );
end;
$$;

-- ==================================================================
-- 4. Recording without a clinical event time (BR-23).
-- ==================================================================

drop function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text, timestamptz, boolean);
create function public.create_appointment_clinical_entry(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_idempotency_key uuid,
    p_category text,
    p_clinical_content text,
    p_other_category_context text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    appointment_record public.appointments%rowtype;
    assigned_clinic_assignment_id uuid;
    normalized_content text;
    normalized_other_context text;
    requested_digest bytea;
    existing_entry public.clinical_record_entries%rowtype;
    created_entry_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 1. Authority before any target (BR-17), in the clinical lock order:
    --    Organization -> Clinic -> Membership/Grant/Assignment -> Appointment.
    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;
    select appointment.* into appointment_record
    from public.appointments as appointment
    where appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
    for share;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 2. Key.
    if p_idempotency_key is null then
        raise exception 'A creation key is required' using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;

    -- 3. Field rules (BR-5). No time is taken from the client.
    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');
    perform public.assert_clinical_entry_fields(
        p_category, normalized_content, normalized_other_context, null
    );

    -- 4. Reconciliation (BR-7). The digest keeps its former shape with an
    --    absent event time, so a request is the same request across M5.
    requested_digest := sha256(convert_to(jsonb_build_object(
        'appointment_id', appointment_record.id,
        'category', p_category,
        'clinical_content', normalized_content,
        'other_category_context', normalized_other_context,
        'clinical_event_at', null,
        'clinical_event_now', false
    )::text, 'UTF8'));
    select entry.* into existing_entry
    from public.clinical_record_entries as entry
    where entry.created_by_user_id = acting_user_id
      and entry.creation_idempotency_key = p_idempotency_key;
    if found then
        if existing_entry.creation_request_digest = requested_digest then
            return jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', existing_entry.id);
        end if;
        raise exception 'The creation key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    -- 5. Documentable Appointment (BR-3).
    if not public.appointment_accepts_clinical_documentation(appointment_record.id, appointment_record.lifecycle_state) then
        raise exception 'The Appointment cannot be documented'
            using errcode = '23514', hint = 'APPOINTMENT_STATE_INVALID';
    end if;

    -- 6. Current eligible assignee, read under the Appointment lock (BR-6).
    select assignment.veterinarian_clinic_assignment_id into assigned_clinic_assignment_id
    from public.appointment_veterinarian_assignments as assignment
    where assignment.appointment_id = appointment_record.id
      and assignment.effective_end is null;
    if assigned_clinic_assignment_id is null then
        raise exception 'No Veterinarian is assigned to this Appointment'
            using errcode = '23514', hint = 'NO_VETERINARIAN_ASSIGNED';
    end if;
    if assigned_clinic_assignment_id <> actor.veterinarian_clinic_assignment_id
       or not public.appointment_veterinarian_is_eligible(assigned_clinic_assignment_id, p_clinic_id) then
        raise exception 'Only the assigned Veterinarian can add records to this Appointment'
            using errcode = '23514', hint = 'NOT_ASSIGNED_VETERINARIAN';
    end if;

    -- 7. Commercial gate for every new Entry (BR-13).
    if not public.organization_has_professional_entitlement(actor.organization_id, 'CLINICAL_CARE') then
        raise exception 'Clinical care is currently unavailable for this Organization'
            using errcode = '42501', hint = 'CLINICAL_SERVICE_UNAVAILABLE';
    end if;

    -- 8. Recording at the server's instant; a concurrent request with the same
    --    key reconciles above on retry and is rejected by the unique key here.
    insert into public.clinical_record_entries (
        appointment_id, created_by_user_id, creator_veterinarian_clinic_assignment_id,
        created_at, category, clinical_content, other_category_context,
        creation_idempotency_key, creation_request_digest
    ) values (
        appointment_record.id, acting_user_id, actor.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_category, normalized_content, normalized_other_context,
        p_idempotency_key, requested_digest
    )
    on conflict (created_by_user_id, creation_idempotency_key) do nothing
    returning id into created_entry_id;

    if created_entry_id is null then
        select entry.* into existing_entry
        from public.clinical_record_entries as entry
        where entry.created_by_user_id = acting_user_id
          and entry.creation_idempotency_key = p_idempotency_key;
        if existing_entry.creation_request_digest = requested_digest then
            return jsonb_build_object('outcome', 'ALREADY_CREATED', 'entry_id', existing_entry.id);
        end if;
        raise exception 'The creation key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    return jsonb_build_object('outcome', 'CREATED', 'entry_id', created_entry_id);
end;
$$;

-- ==================================================================
-- 5. Editing (BR-23b).
-- ==================================================================

create function public.edit_appointment_clinical_entry(
    p_clinic_id uuid,
    p_appointment_id uuid,
    p_entry_id uuid,
    p_idempotency_key uuid,
    p_expected_version integer,
    p_category text,
    p_clinical_content text,
    p_other_category_context text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    actor record;
    entry_record public.clinical_record_entries%rowtype;
    normalized_content text;
    normalized_other_context text;
    existing_version public.clinical_amendments%rowtype;
    current_version record;
    created_version integer;
begin
    -- 1. Authentication.
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Authority before any target; no Entitlement (SPEC-SUB-004 BR-20).
    select * into actor
    from public.lock_clinical_actor_context(acting_user_id, p_clinic_id, 'CLINICAL_DOCUMENTATION');
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 3. The Entry of that Appointment of that Clinic, locked so edits of one
    --    Entry serialize; independent of the Care Authorization (BR-11).
    select entry.* into entry_record
    from public.clinical_record_entries as entry
    join public.appointments as appointment on appointment.id = entry.appointment_id
    where entry.id = p_entry_id
      and appointment.id = p_appointment_id
      and appointment.clinic_id = p_clinic_id
    for update of entry;
    if not found then
        raise exception 'Clinical record unavailable' using errcode = '42501';
    end if;

    -- 4. Only the Entry's own author edits it (BR-18).
    if entry_record.created_by_user_id is distinct from acting_user_id then
        raise exception 'Only the author of the record can edit it'
            using errcode = '23514', hint = 'ENTRY_AUTHOR_REQUIRED';
    end if;

    -- 5. The request.
    if p_idempotency_key is null then
        raise exception 'An edit key is required' using errcode = '22023', hint = 'KEY_REQUIRED';
    end if;
    if p_expected_version is null or p_expected_version < 1 then
        raise exception 'The edited version is required' using errcode = '22023', hint = 'INVALID_VERSION';
    end if;

    -- 6. Field rules (BR-5).
    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');
    perform public.assert_clinical_entry_fields(
        p_category, normalized_content, normalized_other_context, null
    );

    -- 7. Reconciliation of this User's key (unique across all Amendments).
    select amendment.* into existing_version
    from public.clinical_amendments as amendment
    where amendment.amending_user_id = acting_user_id
      and amendment.idempotency_key = p_idempotency_key;
    if found then
        if existing_version.change_kind = 'EDIT'
           and existing_version.original_clinical_record_entry_id = entry_record.id
           and existing_version.version_number = p_expected_version + 1
           and existing_version.category = p_category
           and existing_version.amendment_content = normalized_content
           and existing_version.other_category_context is not distinct from normalized_other_context then
            return jsonb_build_object('outcome', 'ALREADY_EDITED', 'version', existing_version.version_number);
        end if;
        raise exception 'The edit key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    -- 8. The version the editor was opened on must still be current.
    select * into current_version from public.clinical_entry_current(entry_record.id);
    if p_expected_version <> current_version.version_number then
        raise exception 'The record changed since it was opened'
            using hint = 'STALE_VERSION';
    end if;

    -- 9. Nothing to change.
    if current_version.category = p_category
       and current_version.clinical_content = normalized_content
       and current_version.other_category_context is not distinct from normalized_other_context then
        return jsonb_build_object('outcome', 'UNCHANGED', 'version', current_version.version_number);
    end if;

    -- 10. The next version, at the server's instant.
    insert into public.clinical_amendments (
        original_clinical_record_entry_id, change_kind, version_number, reason,
        category, other_category_context, amendment_content,
        amending_user_id, amending_veterinarian_clinic_assignment_id,
        created_at, idempotency_key
    ) values (
        entry_record.id, 'EDIT', current_version.version_number + 1, null,
        p_category, normalized_other_context, normalized_content,
        acting_user_id, actor.veterinarian_clinic_assignment_id,
        clock_timestamp(), p_idempotency_key
    )
    on conflict (amending_user_id, idempotency_key) do nothing
    returning version_number into created_version;

    if created_version is null then
        select amendment.* into existing_version
        from public.clinical_amendments as amendment
        where amendment.amending_user_id = acting_user_id
          and amendment.idempotency_key = p_idempotency_key;
        if existing_version.change_kind = 'EDIT'
           and existing_version.original_clinical_record_entry_id = entry_record.id
           and existing_version.version_number = p_expected_version + 1
           and existing_version.category = p_category
           and existing_version.amendment_content = normalized_content
           and existing_version.other_category_context is not distinct from normalized_other_context then
            return jsonb_build_object('outcome', 'ALREADY_EDITED', 'version', existing_version.version_number);
        end if;
        raise exception 'The edit key was already used for a different request'
            using errcode = '23505', hint = 'KEY_CONFLICT';
    end if;

    return jsonb_build_object('outcome', 'EDITED', 'version', created_version);
end;
$$;

revoke all privileges
on function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.create_appointment_clinical_entry(uuid, uuid, uuid, text, text, text)
to authenticated;
revoke all privileges
on function public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.edit_appointment_clinical_entry(uuid, uuid, uuid, uuid, integer, text, text, text)
to authenticated;

-- ==================================================================
-- 6. The reason-and-addition operations are retired (BR-25).
-- ==================================================================

drop function public.create_appointment_clinical_amendment(uuid, uuid, uuid, uuid, text, text);
drop function public.create_clinical_amendment(uuid, text, text, uuid);

commit;
