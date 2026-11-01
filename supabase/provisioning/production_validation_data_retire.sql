-- ============================================================================
-- MenizVet — Production pre-release validation dataset (RETIREMENT)
--
-- INTENTIONAL PRODUCTION SCRIPT. READ BEFORE RUNNING.
--
-- * Retires the synthetic dataset created by
--   production_validation_data.sql. The domain model blocks DELETE for
--   Organizations, Memberships, Grants, Clinics, Subscriptions,
--   Veterinarian Clinic Assignments, Appointments, Care Authorizations and
--   Communications, so nothing is deleted: the dataset is made
--   non-discoverable and non-bookable, and all history stays intact.
-- * This is NOT a migration and must never be moved into supabase/migrations.
--   It is never auto-run. Review it before every execution and run it
--   deliberately with psql, passing three required variables:
--       -v expected_project_ref=<production project ref>
--       -v owner_email="<OWNER Auth user e-mail>"
--       -v confirm=RETIRE_PRODUCTION_VALIDATION_DATA
-- * Steps, in order, in one transaction:
--     1. identify ONLY this dataset (Subscription marker -> Organization ->
--        its Clinics, each carrying the description marker);
--     2. clear recurring Clinic Appointment Availability and the OWNER's
--        Veterinarian Availability through the trusted RPCs (while the
--        scheduling Entitlement still exists);
--     3. unpublish only these Clinics (see note below);
--     4. transition the dataset Subscription to EXPIRED through the trusted
--        apply_subscription_state_transition(...) lifecycle;
--     5. report what remains.
-- * Unpublication note: this script predates unpublish_clinic(uuid), added by
--   20261025090000 (Clinic self-service Slice C). That RPC is an
--   authenticated, capability-checked, one-Clinic operation that only sets
--   is_published = false. Step 3 remains an equivalent single, narrowly-scoped
--   privileged UPDATE of clinics.is_published, restricted to this dataset's
--   Clinic ids. The column is mutable (clinics_preserve_identity only freezes
--   id/organization_id/created_at) and unpublication always satisfies the
--   publication-integrity trigger.
-- * It never removes the OWNER Auth identity, never ends Memberships,
--   Grants, Veterinarian Clinic Assignments, Care Authorizations or
--   Appointments, never disables RLS and never changes grants/policies.
-- * Idempotent: re-running against an already retired dataset changes
--   nothing and only reports.
-- ============================================================================

\set ON_ERROR_STOP on

\if :{?expected_project_ref}
\else
\set expected_project_ref ''
\endif

\if :{?confirm}
\else
\set confirm ''
\endif

\if :{?owner_email}
\else
\set owner_email ''
\endif

begin;

select set_config('menizvet_validation.expected_project_ref', :'expected_project_ref', true);
select set_config('menizvet_validation.confirm', :'confirm', true);
select set_config('menizvet_validation.owner_email', :'owner_email', true);

do $owner_email_guard$
begin
    if nullif(btrim(coalesce(current_setting('menizvet_validation.owner_email', true), '')), '') is null then
        raise exception 'Refusing to run: pass -v owner_email="<OWNER Auth user e-mail>"';
    end if;
end;
$owner_email_guard$;

-- Must stay identical to production_validation_data.sql.
create temp table mvv_settings on commit drop as
select
    btrim(current_setting('menizvet_validation.owner_email'))::text as owner_email,
    'Red Veterinaria de Validación MenizVet'::text as org_name,
    'menizvet-production-validation-dataset-v1'::text as sub_source,
    '596e9d75-65b4-40a2-95b3-00381eaa1887'::uuid as sub_key,
    'Clínica ficticia: datos de demostración para validar MenizVet.'::text as marker,
    'menizvet-production-validation-retire-v1'::text as retire_source_system;

create temp table mvv_retire_state (
    organization_id uuid not null,
    subscription_id uuid not null,
    clinic_ids uuid[] not null,
    clinics_unpublished integer not null,
    clinic_availability_cleared integer not null,
    veterinarian_availability_cleared integer not null,
    subscription_state_before text not null,
    subscription_state_after text not null,
    availability_clearing_skipped_reason text
) on commit drop;

do $retire$
declare
    settings record;
    v_expected_ref text := coalesce(current_setting('menizvet_validation.expected_project_ref', true), '');
    v_confirm text := coalesce(current_setting('menizvet_validation.confirm', true), '');
    v_dispatch_url text;
    v_missing text;
    v_count integer;
    v_org_id uuid;
    v_org_name text;
    v_subscription_id uuid;
    v_state_before text;
    v_state_after text;
    v_clinic_ids uuid[];
    v_clinic_id uuid;
    v_assignment_ids uuid[];
    v_assignment_id uuid;
    v_owner_auth_id uuid;
    v_owner_user_id uuid;
    v_skip_reason text;
    v_clinics_cleared integer := 0;
    v_assignments_cleared integer := 0;
    v_unpublished integer := 0;
begin
    select * into strict settings from pg_temp.mvv_settings;

    -- 1. Deliberate-execution and target-identity guards ----------------------

    if v_confirm <> 'RETIRE_PRODUCTION_VALIDATION_DATA' then
        raise exception 'Refusing to run: pass -v confirm=RETIRE_PRODUCTION_VALIDATION_DATA';
    end if;

    if v_expected_ref !~ '^[a-z0-9]{20}$' then
        raise exception 'Refusing to run: pass -v expected_project_ref=<20-character Supabase project ref>';
    end if;

    if to_regclass('vault.decrypted_secrets') is null then
        raise exception 'Target identity check failed: Supabase Vault is not available';
    end if;

    select secret.decrypted_secret
    into v_dispatch_url
    from vault.decrypted_secrets as secret
    where secret.name = 'communications_dispatch_url';

    if v_dispatch_url is null
       or v_dispatch_url not like 'https://' || v_expected_ref || '.supabase.co/%' then
        raise exception 'Target identity check failed: this database is not project %', v_expected_ref;
    end if;

    select string_agg(signature, ', ')
    into v_missing
    from unnest(array[
        'public.derive_organization_subscription_current_state(uuid)',
        'public.organization_has_professional_entitlement(uuid,text)',
        'public.apply_subscription_state_transition(uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,text)',
        'public.get_managed_clinic_appointment_availability(uuid)',
        'public.replace_clinic_appointment_availability(uuid,jsonb,bigint)',
        'public.replace_veterinarian_availability(uuid,jsonb)',
        'public.veterinarian_clinic_assignment_is_current(uuid)',
        'public.user_has_clinic_capability(uuid,uuid,text)'
    ]) as signature
    where to_regprocedure(signature) is null;

    if v_missing is not null then
        raise exception 'Preflight failed: required functions are missing: %', v_missing;
    end if;

    if not pg_has_role(current_user, 'authenticated', 'MEMBER')
       or not pg_has_role(current_user, 'anon', 'MEMBER') then
        raise exception 'Preflight failed: session role % cannot SET ROLE authenticated/anon', current_user;
    end if;

    if not has_function_privilege(
        current_user,
        'public.apply_subscription_state_transition(uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,text)',
        'EXECUTE'
    ) then
        raise exception 'Preflight failed: session role % cannot execute apply_subscription_state_transition', current_user;
    end if;

    -- 2. Identify ONLY this dataset -----------------------------------------

    select count(*)
    into v_count
    from public.organization_subscriptions as subscription
    where subscription.establishment_idempotency_key = settings.sub_key
       or subscription.establishment_source = settings.sub_source;

    if v_count <> 1 then
        raise exception 'Dataset not identified: % Subscriptions carry the dataset marker (expected 1)', v_count;
    end if;

    select subscription.id, subscription.organization_id
    into v_subscription_id, v_org_id
    from public.organization_subscriptions as subscription
    where subscription.establishment_idempotency_key = settings.sub_key
      and subscription.establishment_source = settings.sub_source;

    if v_subscription_id is null then
        raise exception 'Dataset not identified: a Subscription carries only part of the dataset marker';
    end if;

    select organization.display_name
    into v_org_name
    from public.veterinary_organizations as organization
    where organization.id = v_org_id;

    if v_org_name is distinct from settings.org_name then
        raise exception 'Dataset not identified: marker Subscription belongs to Organization "%", expected "%"',
            v_org_name, settings.org_name;
    end if;

    select array_agg(clinic.id order by clinic.id)
    into v_clinic_ids
    from public.clinics as clinic
    where clinic.organization_id = v_org_id;

    if v_clinic_ids is null then
        raise exception 'Dataset not identified: Organization "%" has no Clinics', settings.org_name;
    end if;

    if exists (
        select 1
        from unnest(v_clinic_ids) as dataset_clinic(id)
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = dataset_clinic.id
        where profile.description is null
           or position(settings.marker in profile.description) = 0
    ) then
        raise exception 'Refusing to retire: a Clinic in "%" does not carry the synthetic-data marker',
            settings.org_name;
    end if;

    select derived.current_state
    into v_state_before
    from public.derive_organization_subscription_current_state(v_subscription_id) as derived;

    -- 3. Clear recurring Availability through the trusted RPCs ----------------
    --    Requires the OWNER identity, its availability capability and the
    --    PROFESSIONAL_SCHEDULING Entitlement (i.e. before expiry / valid_until).

    select array_agg(assignment.id order by assignment.id)
    into v_assignment_ids
    from public.veterinarian_clinic_assignments as assignment
    where assignment.clinic_id = any(v_clinic_ids)
      and public.veterinarian_clinic_assignment_is_current(assignment.id)
      and exists (
          select 1
          from public.veterinarian_availability_periods as period
          where period.veterinarian_clinic_assignment_id = assignment.id
      );

    if not exists (
        select 1 from public.clinic_appointment_availability_periods as period
        where period.clinic_id = any(v_clinic_ids)
    ) and v_assignment_ids is null then
        v_skip_reason := 'nothing to clear';
    else
        select auth_user.id
        into v_owner_auth_id
        from auth.users as auth_user
        where lower(auth_user.email) = lower(settings.owner_email)
          and auth_user.email_confirmed_at is not null;

        select identity_link.user_id
        into v_owner_user_id
        from public.user_authentication_identities as identity_link
        where identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and identity_link.provider_subject = v_owner_auth_id;

        if v_owner_user_id is null then
            v_skip_reason := 'OWNER Auth identity/link unavailable';
        elsif not public.organization_has_professional_entitlement(v_org_id, 'PROFESSIONAL_SCHEDULING') then
            v_skip_reason := 'PROFESSIONAL_SCHEDULING Entitlement already lapsed';
        elsif exists (
            select 1
            from unnest(v_clinic_ids) as dataset_clinic(id)
            where not public.user_has_clinic_capability(
                v_owner_user_id, dataset_clinic.id, 'APPOINTMENT_MANAGE_AVAILABILITY'
            )
        ) then
            v_skip_reason := 'OWNER lacks Availability-management capability';
        end if;
    end if;

    if v_skip_reason is null then
        perform set_config('request.jwt.claim.sub', v_owner_auth_id::text, true);
        perform set_config(
            'request.jwt.claims',
            jsonb_build_object('sub', v_owner_auth_id, 'role', 'authenticated')::text,
            true
        );

        set local role authenticated;

        if v_assignment_ids is not null then
            foreach v_assignment_id in array v_assignment_ids loop
                perform public.replace_veterinarian_availability(v_assignment_id, '[]'::jsonb);
                v_assignments_cleared := v_assignments_cleared + 1;
            end loop;
        end if;

        foreach v_clinic_id in array v_clinic_ids loop
            -- Weekly stale-edit token (SPEC-APT-013 BR-74) from the management read.
            perform public.replace_clinic_appointment_availability(
                v_clinic_id,
                '[]'::jsonb,
                (
                    select managed.weekly_appointment_availability_revision
                    from public.get_managed_clinic_appointment_availability(v_clinic_id) as managed
                )
            );
            v_clinics_cleared := v_clinics_cleared + 1;
        end loop;

        reset role;
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('request.jwt.claims', '', true);
    elsif v_skip_reason <> 'nothing to clear' then
        raise warning 'Availability NOT cleared (%). Unpublication and Subscription expiry still apply; any remaining recurring Availability is reported below.',
            v_skip_reason;
    end if;

    -- 4. Unpublish only these Clinics (privileged UPDATE; see header) ---------

    update public.clinics as clinic
    set is_published = false
    where clinic.id = any(v_clinic_ids)
      and clinic.organization_id = v_org_id
      and clinic.is_published;

    get diagnostics v_unpublished = row_count;

    -- 5. Expire the dataset Subscription through its trusted lifecycle --------

    -- Every non-EXPIRED Phase 1 state may move to EXPIRED except PENDING
    -- (SPEC-SUB-002 §5); the dataset is established ACTIVE. The effective
    -- instant is the statement instant: future-dated transitions are rejected
    -- and clock_timestamp() is later than statement_timestamp() (ADR-006).
    if v_state_before <> 'EXPIRED' then
        perform public.apply_subscription_state_transition(
            v_subscription_id,
            'EXPIRED',
            statement_timestamp(),
            null::timestamptz,
            null::timestamptz,
            settings.retire_source_system,
            null::text
        );
    end if;

    select derived.current_state
    into v_state_after
    from public.derive_organization_subscription_current_state(v_subscription_id) as derived;

    -- 6. Post-retirement verification -----------------------------------------

    if v_state_after <> 'EXPIRED' then
        raise exception 'Retirement failed: Subscription state is %', v_state_after;
    end if;

    if public.organization_has_professional_entitlement(v_org_id, 'APPOINTMENT_MANAGEMENT')
       or public.organization_has_professional_entitlement(v_org_id, 'PROFESSIONAL_SCHEDULING')
       or public.organization_has_professional_entitlement(v_org_id, 'CLINICAL_CARE')
       or public.organization_has_professional_entitlement(v_org_id, 'CLINICAL_DOCUMENTATION') then
        raise exception 'Retirement failed: a professional Entitlement is still granted';
    end if;

    if exists (
        select 1 from public.clinics as clinic
        where clinic.id = any(v_clinic_ids) and clinic.is_published
    ) then
        raise exception 'Retirement failed: a dataset Clinic is still published';
    end if;

    set local role anon;

    select count(*)
    into v_count
    from public.published_clinic_public_profiles as published
    where published.clinic_id = any(v_clinic_ids);

    reset role;

    if v_count <> 0 then
        raise exception 'Retirement failed: % dataset Clinics still visible to anon Discovery', v_count;
    end if;

    insert into pg_temp.mvv_retire_state (
        organization_id, subscription_id, clinic_ids, clinics_unpublished,
        clinic_availability_cleared, veterinarian_availability_cleared,
        subscription_state_before, subscription_state_after,
        availability_clearing_skipped_reason
    )
    values (
        v_org_id, v_subscription_id, v_clinic_ids, v_unpublished,
        v_clinics_cleared, v_assignments_cleared,
        v_state_before, v_state_after, v_skip_reason
    );

    raise notice 'Retirement complete: % Clinics unpublished now, Subscription % -> %',
        v_unpublished, v_state_before, v_state_after;
end;
$retire$;

-- ----------------------------------------------------------------------------
-- Report: what was done and what intentionally remains (historical rows).
-- ----------------------------------------------------------------------------

select
    retire_state.organization_id,
    retire_state.subscription_id,
    cardinality(retire_state.clinic_ids) as dataset_clinics,
    retire_state.clinics_unpublished,
    retire_state.clinic_availability_cleared,
    retire_state.veterinarian_availability_cleared,
    retire_state.subscription_state_before,
    retire_state.subscription_state_after,
    retire_state.availability_clearing_skipped_reason
from pg_temp.mvv_retire_state as retire_state;

with dataset as (
    select retire_state.organization_id, retire_state.clinic_ids
    from pg_temp.mvv_retire_state as retire_state
)
select 'veterinary_organizations' as retained, count(*) as row_count
from public.veterinary_organizations as organization, dataset
where organization.id = dataset.organization_id
union all
select 'clinics (all unpublished)', count(*)
from public.clinics as clinic, dataset
where clinic.id = any(dataset.clinic_ids)
union all
select 'clinics still published', count(*)
from public.clinics as clinic, dataset
where clinic.id = any(dataset.clinic_ids) and clinic.is_published
union all
select 'clinic_locations', count(*)
from public.clinic_locations as location, dataset
where location.clinic_id = any(dataset.clinic_ids)
union all
select 'clinic_public_profiles (kept for historical provenance)', count(*)
from public.clinic_public_profiles as profile, dataset
where profile.clinic_id = any(dataset.clinic_ids)
union all
select 'clinic_service_offerings', count(*)
from public.clinic_service_offerings as offering, dataset
where offering.clinic_id = any(dataset.clinic_ids)
union all
select 'clinic_opening_periods', count(*)
from public.clinic_opening_periods as period, dataset
where period.clinic_id = any(dataset.clinic_ids)
union all
select 'clinic_appointment_availability_periods (expect 0)', count(*)
from public.clinic_appointment_availability_periods as period, dataset
where period.clinic_id = any(dataset.clinic_ids)
union all
select 'clinic_appointment_availability_exceptions', count(*)
from public.clinic_appointment_availability_exceptions as exception_record, dataset
where exception_record.clinic_id = any(dataset.clinic_ids)
union all
select 'veterinarian_clinic_assignments (current)', count(*)
from public.veterinarian_clinic_assignments as assignment, dataset
where assignment.clinic_id = any(dataset.clinic_ids)
  and assignment.effective_end is null
union all
select 'veterinarian_availability_periods (expect 0)', count(*)
from public.veterinarian_availability_periods as period
join public.veterinarian_clinic_assignments as assignment
  on assignment.id = period.veterinarian_clinic_assignment_id, dataset
where assignment.clinic_id = any(dataset.clinic_ids)
union all
select 'organization_memberships (active)', count(*)
from public.organization_memberships as membership, dataset
where membership.organization_id = dataset.organization_id
  and membership.effective_end is null
union all
select 'subscription_state_transitions', count(*)
from public.subscription_state_transitions as transition
join public.organization_subscriptions as subscription
  on subscription.id = transition.subscription_id, dataset
where subscription.organization_id = dataset.organization_id
union all
select 'appointments: ' || appointment.lifecycle_state, count(*)
from public.appointments as appointment, dataset
where appointment.clinic_id = any(dataset.clinic_ids)
group by appointment.lifecycle_state
union all
select 'care_authorizations: ' || care_authorization.lifecycle_state, count(*)
from public.care_authorizations as care_authorization, dataset
where care_authorization.clinic_id = any(dataset.clinic_ids)
group by care_authorization.lifecycle_state
order by 1;

commit;
