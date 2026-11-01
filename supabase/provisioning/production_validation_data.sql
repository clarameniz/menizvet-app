-- ============================================================================
-- MenizVet — Production pre-release validation dataset (PROVISIONING)
--
-- INTENTIONAL PRODUCTION SCRIPT. READ BEFORE RUNNING.
--
-- * Purpose: create one clearly synthetic Veterinary Organization with 20
--   published synthetic Clinics so the already-implemented Guardian mobile
--   flows (list, Nearby, map, Clinic detail, requestable times, request,
--   reschedule, cancel, Appointment list/detail) can be validated against
--   MenizVet Production before the Play release.
-- * This is NOT a migration and must never be moved into supabase/migrations.
--   It is never auto-run: nothing in the Supabase CLI applies
--   supabase/provisioning/, and there is no seed.sql.
-- * It must be reviewed before every execution and run deliberately with
--   psql, passing three required variables:
--       -v expected_project_ref=<production project ref>
--       -v owner_email="<OWNER Auth user e-mail>"
--       -v confirm=PROVISION_PRODUCTION_VALIDATION_DATA
-- * It creates NO Supabase Auth user. The OWNER Auth user identified by
--   owner_email must already exist and be email-confirmed.
-- * The Organization, its OWNER and its initial ACTIVE Subscription are
--   established by ONE trusted call, establish_veterinary_organization(...)
--   (ADR-009, SPEC-ORG-001 §10), made as the session role for the OWNER's
--   domain User (resolved read-only from owner_email below). Establishment
--   involves no OWNER impersonation and no separate Subscription call.
-- * The later configuration steps (Professional Profile, Clinics, schedules,
--   Assignments) are the OWNER's own authenticated application operations,
--   so they run as the OWNER exactly as the rollback-only suites under
--   supabase/tests/ do (request.jwt.claim.sub + SET LOCAL ROLE
--   authenticated). RLS is never disabled; no grant or policy is changed.
-- * Idempotent: the dataset is identified by its establishment key (below),
--   never by display name. A re-run against a correctly provisioned dataset
--   replays the establishment (ALREADY_ESTABLISHED, same ids), re-applies the
--   same configuration through the same RPCs and changes nothing material. A
--   dataset provisioned before migration 20261101090000 (Organization without
--   an establishment key, found by its Subscription key) is verified and
--   reconfigured, never re-established. Any unexpected existing state aborts
--   the whole transaction.
-- * Retire (never delete) with production_validation_data_retire.sql.
--
-- Dataset identification markers (shared with the retire script):
--   Organization display name : Red Veterinaria de Validación MenizVet
--   Subscription source       : menizvet-production-validation-dataset-v1
--   Establishment / Subscription idempotency key : 596e9d75-65b4-40a2-95b3-00381eaa1887
--   Clinic description suffix : Clínica ficticia: datos de demostración para validar MenizVet.
--   Professional credential   : MENIZVET-VALIDACION-0001
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

-- ----------------------------------------------------------------------------
-- 1. Dataset constants
-- ----------------------------------------------------------------------------

create temp table mvv_settings on commit drop as
select
    btrim(current_setting('menizvet_validation.owner_email'))::text as owner_email,
    'Red Veterinaria de Validación MenizVet'::text as org_name,
    'menizvet-production-validation-dataset-v1'::text as sub_source,
    '596e9d75-65b4-40a2-95b3-00381eaa1887'::uuid as sub_key,
    -- Fixed (not now()) so the establishment stays idempotent: a re-run
    -- must present the identical requested facts.
    '2026-09-25 00:00:00+00'::timestamptz as sub_initial_effective_at,
    -- Safety kill-switch: 2027-01-01 00:00 Europe/Madrid. After this instant
    -- every professional Entitlement lapses automatically (no requestable
    -- times, no new Appointment requests, no availability/duration changes).
    -- Deliberately finite TEST DATA: a real manually managed customer is an
    -- open-ended ACTIVE (SPEC-SUB-002 §14). Kept unchanged so a re-run stays
    -- idempotent against an already provisioned dataset.
    '2026-12-31 23:00:00+00'::timestamptz as sub_valid_until,
    'Clínica ficticia: datos de demostración para validar MenizVet.'::text as marker,
    'MENIZVET-VALIDACION-0001'::text as credential_registration_identifier,
    'Credencial ficticia para validación interna de MenizVet (no emitida por ningún colegio profesional)'::text
        as credential_issuing_context,
    'Europe/Madrid'::text as timezone_name,
    20::integer as expected_clinic_count;

-- ----------------------------------------------------------------------------
-- 2. Weekly schedule profiles (ISO weekday 1 = Monday ... 7 = Sunday).
--    Recurring periods only, no dated exceptions. No period touches
--    02:00-03:00, so the Europe/Madrid DST transitions never apply.
--    Appointment Availability is kept inside Opening Hours (a separate
--    domain concept; the schema does not require containment).
-- ----------------------------------------------------------------------------

create function pg_temp.mvv_periods(
    p_weekdays integer[],
    p_start_time text,
    p_end_time text
)
returns jsonb
language sql
immutable
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'iso_weekday', weekday,
                'start_time', p_start_time,
                'end_time', p_end_time
            )
            order by weekday
        ),
        '[]'::jsonb
    )
    from unnest(p_weekdays) as weekday
$$;

create temp table mvv_schedule_profile (
    profile_key text primary key,
    opening_periods jsonb not null,
    availability_periods jsonb not null
) on commit drop;

insert into mvv_schedule_profile (profile_key, opening_periods, availability_periods)
values
    -- Split weekday schedule, closed at weekends.
    (
        'PARTIDO',
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:30', '13:30')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '16:30', '20:00'),
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:30', '13:30')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '16:30', '20:00')
    ),
    -- Split weekday schedule plus Saturday morning.
    (
        'PARTIDO_SABADO',
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:00', '14:00')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '17:00', '20:30')
            || pg_temp.mvv_periods(array[6], '10:00', '13:30'),
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:00', '13:30')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '17:00', '20:00')
            || pg_temp.mvv_periods(array[6], '10:00', '13:00')
    ),
    -- Continuous weekday opening plus Saturday morning; appointments keep a
    -- midday gap.
    (
        'CONTINUO_SABADO',
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:00', '20:00')
            || pg_temp.mvv_periods(array[6], '09:30', '14:00'),
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:30', '14:00')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '16:00', '19:30')
            || pg_temp.mvv_periods(array[6], '10:00', '13:30')
    ),
    -- Weekday mornings only.
    (
        'MANANAS',
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '08:30', '15:00'),
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '09:00', '14:30')
    ),
    -- Long weekday hours, Saturday and a short Sunday opening (Sunday has no
    -- appointment availability).
    (
        'AMPLIO',
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '10:00', '14:00')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '16:00', '21:00')
            || pg_temp.mvv_periods(array[6], '10:00', '14:00')
            || pg_temp.mvv_periods(array[7], '11:00', '13:00'),
        pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '10:00', '14:00')
            || pg_temp.mvv_periods(array[1, 2, 3, 4, 5], '16:00', '20:30')
            || pg_temp.mvv_periods(array[6], '10:00', '13:30')
    );

-- ----------------------------------------------------------------------------
-- 3. Service Offering sets (categories from clinic_service_offerings check).
-- ----------------------------------------------------------------------------

create temp table mvv_service_set (
    service_set_key text primary key,
    service_offerings jsonb not null
) on commit drop;

insert into mvv_service_set (service_set_key, service_offerings)
values
    (
        'BASICO',
        '[
            {"service_category": "GENERAL_CONSULTATION", "public_description": "Revisiones, consultas generales y seguimiento"},
            {"service_category": "VACCINATION", "public_description": null}
        ]'::jsonb
    ),
    (
        'COMPLETO',
        '[
            {"service_category": "GENERAL_CONSULTATION", "public_description": null},
            {"service_category": "VACCINATION", "public_description": "Plan vacunal y desparasitación"},
            {"service_category": "SURGERY", "public_description": "Cirugía programada de tejidos blandos"},
            {"service_category": "DIAGNOSTIC_IMAGING", "public_description": "Radiología y ecografía"},
            {"service_category": "LABORATORY", "public_description": null}
        ]'::jsonb
    ),
    (
        'URGENCIAS',
        '[
            {"service_category": "GENERAL_CONSULTATION", "public_description": null},
            {"service_category": "VACCINATION", "public_description": null},
            {"service_category": "EMERGENCY_CARE", "public_description": "Atención de urgencias durante el horario de apertura"},
            {"service_category": "HOSPITALIZATION", "public_description": "Hospitalización de día"},
            {"service_category": "SURGERY", "public_description": null}
        ]'::jsonb
    ),
    (
        'DENTAL',
        '[
            {"service_category": "GENERAL_CONSULTATION", "public_description": null},
            {"service_category": "VACCINATION", "public_description": null},
            {"service_category": "DENTISTRY", "public_description": "Limpieza dental y revisión bucal"},
            {"service_category": "OTHER", "public_description": "Peluquería y baño para perros y gatos"}
        ]'::jsonb
    ),
    (
        'DIAGNOSTICO',
        '[
            {"service_category": "GENERAL_CONSULTATION", "public_description": "Medicina interna y segundas opiniones"},
            {"service_category": "DIAGNOSTIC_IMAGING", "public_description": null},
            {"service_category": "LABORATORY", "public_description": "Analíticas con resultados en el día"},
            {"service_category": "OTHER", "public_description": "Asesoramiento nutricional y control de peso"}
        ]'::jsonb
    );

-- ----------------------------------------------------------------------------
-- 4. Clinic manifest. Names are invented; addresses are neutral area labels
--    (no street or number); coordinates are rounded city-area points, not
--    landmarks and not real clinic addresses. No phone numbers are published.
--    E-mail/web use example.com (RFC 2606) or NULL.
-- ----------------------------------------------------------------------------

create temp table mvv_clinic_manifest (
    ordinal integer primary key,
    clinic_key text not null unique,
    city text not null,
    display_name text not null unique,
    description_body text not null,
    address_text text not null,
    latitude double precision not null,
    longitude double precision not null,
    public_email text,
    website text,
    duration_minutes integer not null,
    schedule_profile text not null,
    service_set text not null
) on commit drop;

insert into mvv_clinic_manifest (
    ordinal, clinic_key, city, display_name, description_body, address_text,
    latitude, longitude, public_email, website, duration_minutes,
    schedule_profile, service_set
)
values
    (1, 'valverde-norte', 'Valverde del Camino', 'Clínica Veterinaria Los Alcornoques',
     'Consulta de medicina general y vacunación para perros y gatos, con citas de mañana y tarde.',
     'Zona norte, Valverde del Camino (Huelva) · ubicación aproximada',
     37.5838, -6.7581, 'alcornoques@example.com', null, 30, 'PARTIDO', 'BASICO'),
    (2, 'valverde-sur', 'Valverde del Camino', 'Centro Veterinario Monte Jara',
     'Centro de proximidad con cirugía programada, diagnóstico por imagen y laboratorio propio.',
     'Zona sur, Valverde del Camino (Huelva) · ubicación aproximada',
     37.5712, -6.7496, 'montejara@example.com', 'https://example.com/monte-jara', 30, 'PARTIDO_SABADO', 'COMPLETO'),
    (3, 'huelva', 'Huelva', 'Clínica Veterinaria Punta Salinera',
     'Equipo con atención de urgencias en horario de apertura y hospitalización de día.',
     'Zona norte, Huelva · ubicación aproximada',
     37.2660, -6.9395, 'puntasalinera@example.com', 'https://example.com/punta-salinera', 30, 'CONTINUO_SABADO', 'URGENCIAS'),
    (4, 'ayamonte', 'Ayamonte', 'Centro Veterinario Guadiana Azul',
     'Consultas rápidas de mañana para revisiones y vacunas.',
     'Zona centro, Ayamonte (Huelva) · ubicación aproximada',
     37.2168, -7.4035, null, null, 20, 'MANANAS', 'BASICO'),
    (5, 'sevilla-este', 'Sevilla', 'Clínica Veterinaria Patio de Azahar',
     'Salud dental, peluquería y medicina preventiva en un ambiente tranquilo.',
     'Zona este, Sevilla · ubicación aproximada',
     37.3840, -5.9730, 'patiodeazahar@example.com', null, 30, 'PARTIDO_SABADO', 'DENTAL'),
    (6, 'sevilla-oeste', 'Sevilla', 'Centro Veterinario Ribera del Arenal',
     'Centro orientado al diagnóstico: imagen, analíticas y consultas de medicina interna.',
     'Zona oeste, Sevilla · ubicación aproximada',
     37.3862, -6.0045, null, 'https://example.com/ribera-del-arenal', 30, 'AMPLIO', 'DIAGNOSTICO'),
    (7, 'utrera', 'Utrera', 'Clínica Veterinaria Campiña Clara',
     'Clínica familiar para el cuidado diario de tus mascotas.',
     'Zona centro, Utrera (Sevilla) · ubicación aproximada',
     37.1822, -5.7768, 'campinaclara@example.com', null, 30, 'PARTIDO', 'BASICO'),
    (8, 'jerez', 'Jerez de la Frontera', 'Centro Veterinario Viña Alta',
     'Cirugía, diagnóstico por imagen y laboratorio, con citas de 45 minutos.',
     'Zona norte, Jerez de la Frontera (Cádiz) · ubicación aproximada',
     36.6905, -6.1180, 'vinaalta@example.com', 'https://example.com/vina-alta', 45, 'CONTINUO_SABADO', 'COMPLETO'),
    (9, 'cadiz', 'Cádiz', 'Clínica Veterinaria Brisa Atlántica',
     'Odontología veterinaria y peluquería, con horario de mañanas.',
     'Zona extramuros, Cádiz · ubicación aproximada',
     36.5120, -6.2780, null, null, 30, 'MANANAS', 'DENTAL'),
    (10, 'cordoba', 'Córdoba', 'Centro Veterinario Patio de las Rejas',
     'Diagnóstico, analíticas y asesoramiento nutricional para perros y gatos.',
     'Zona oeste, Córdoba · ubicación aproximada',
     37.8930, -4.7880, 'patiodelasrejas@example.com', null, 30, 'PARTIDO', 'DIAGNOSTICO'),
    (11, 'malaga-norte', 'Málaga', 'Clínica Veterinaria Jazmín de Levante',
     'Atención de urgencias en horario de apertura, hospitalización de día y cirugía.',
     'Zona norte, Málaga · ubicación aproximada',
     36.7290, -4.4155, 'jazmindelevante@example.com', 'https://example.com/jazmin-de-levante', 30, 'CONTINUO_SABADO', 'URGENCIAS'),
    (12, 'malaga-oeste', 'Málaga', 'Centro Veterinario Montes del Lagar',
     'Consultas ágiles de 20 minutos para revisiones y vacunación.',
     'Zona oeste, Málaga · ubicación aproximada',
     36.7195, -4.4400, null, null, 20, 'PARTIDO_SABADO', 'BASICO'),
    (13, 'marbella', 'Marbella', 'Clínica Veterinaria Pinar de la Sierra',
     'Servicio completo con cirugía y diagnóstico, abierto también el domingo por la mañana.',
     'Zona norte, Marbella (Málaga) · ubicación aproximada',
     36.5125, -4.8900, 'pinardelasierra@example.com', 'https://example.com/pinar-de-la-sierra', 30, 'AMPLIO', 'COMPLETO'),
    (14, 'granada', 'Granada', 'Centro Veterinario Carmen del Aljibe',
     'Cuidado dental, peluquería y medicina general.',
     'Zona sur, Granada · ubicación aproximada',
     37.1700, -3.6050, null, 'https://example.com/carmen-del-aljibe', 30, 'PARTIDO', 'DENTAL'),
    (15, 'almeria', 'Almería', 'Clínica Veterinaria Cabo Lucero',
     'Diagnóstico por imagen y laboratorio con horario de mañanas.',
     'Zona norte, Almería · ubicación aproximada',
     36.8420, -2.4580, 'cabolucero@example.com', null, 30, 'MANANAS', 'DIAGNOSTICO'),
    (16, 'jaen', 'Jaén', 'Centro Veterinario Olivar de Poniente',
     'Medicina preventiva y consultas generales, también los sábados.',
     'Zona norte, Jaén · ubicación aproximada',
     37.7860, -3.7800, null, null, 30, 'PARTIDO_SABADO', 'BASICO'),
    (17, 'madrid', 'Madrid', 'Clínica Veterinaria Glorieta Verde',
     'Clínica urbana con cirugía, imagen y laboratorio.',
     'Zona norte, Madrid · ubicación aproximada',
     40.4300, -3.6800, 'glorietaverde@example.com', 'https://example.com/glorieta-verde', 30, 'CONTINUO_SABADO', 'COMPLETO'),
    (18, 'barcelona', 'Barcelona', 'Centre Veterinari Plaça del Til·ler',
     'Atención de urgencias en horario de apertura y hospitalización de día.',
     'Zona Eixample, Barcelona · ubicación aproximada',
     41.3985, 2.1610, 'placadeltiller@example.com', null, 30, 'AMPLIO', 'URGENCIAS'),
    (19, 'valencia', 'Valencia', 'Clínica Veterinaria Barraca Blanca',
     'Consultas de diagnóstico de 45 minutos, con analíticas y asesoramiento nutricional.',
     'Zona sur, Valencia · ubicación aproximada',
     39.4640, -0.3700, null, 'https://example.com/barraca-blanca', 45, 'PARTIDO', 'DIAGNOSTICO'),
    (20, 'zaragoza', 'Zaragoza', 'Centro Veterinario Cierzo Amable',
     'Odontología, peluquería y medicina general en horario de mañanas.',
     'Zona oeste, Zaragoza · ubicación aproximada',
     41.6450, -0.8900, 'cierzoamable@example.com', null, 30, 'MANANAS', 'DENTAL');

-- Fully resolved per-Clinic payloads, exactly as sent to the RPCs.
create temp table mvv_resolved_clinic on commit drop as
select
    manifest.ordinal,
    manifest.clinic_key,
    manifest.city,
    manifest.display_name,
    manifest.description_body || ' ' || settings.marker as description,
    manifest.address_text,
    manifest.latitude,
    manifest.longitude,
    manifest.public_email,
    manifest.website,
    manifest.duration_minutes,
    schedule.opening_periods,
    schedule.availability_periods,
    service.service_offerings
from mvv_clinic_manifest as manifest
cross join mvv_settings as settings
join mvv_schedule_profile as schedule
  on schedule.profile_key = manifest.schedule_profile
join mvv_service_set as service
  on service.service_set_key = manifest.service_set;

-- Run state written by the provisioning block, read by postflight.
create temp table mvv_run_state (
    owner_auth_id uuid not null,
    owner_user_id uuid not null,
    organization_id uuid not null,
    owner_membership_id uuid not null,
    professional_profile_id uuid not null,
    subscription_id uuid not null,
    organization_created boolean not null
) on commit drop;

create temp table mvv_run_clinic (
    ordinal integer primary key,
    clinic_id uuid not null unique,
    veterinarian_clinic_assignment_id uuid not null,
    clinic_created boolean not null
) on commit drop;

create temp table mvv_postflight (
    ordinal integer primary key,
    candidate_count integer not null,
    nearby_result_count integer not null
) on commit drop;

-- ----------------------------------------------------------------------------
-- 5. Preflight + provisioning (single atomic transaction)
-- ----------------------------------------------------------------------------

do $provision$
declare
    settings record;
    v_expected_ref text := coalesce(current_setting('menizvet_validation.expected_project_ref', true), '');
    v_confirm text := coalesce(current_setting('menizvet_validation.confirm', true), '');
    v_dispatch_url text;
    v_missing text;
    v_count integer;
    v_manifest jsonb;
    v_item jsonb;
    v_distance_meters double precision;
    v_owner_auth_id uuid;
    v_owner_user_id uuid;
    v_org_id uuid;
    v_org_keyed boolean;
    v_membership_id uuid;
    v_org_created boolean := false;
    v_established jsonb;
    v_profile_id uuid;
    v_credential_identifier text;
    v_subscription_id uuid;
    v_subscription_org_id uuid;
    v_subscription_state text;
    v_clinic_id uuid;
    v_clinic_created boolean;
    v_assignment_id uuid;
begin
    select * into strict settings from pg_temp.mvv_settings;

    -- 5.1 Deliberate-execution and target-identity guards --------------------

    if v_confirm <> 'PROVISION_PRODUCTION_VALIDATION_DATA' then
        raise exception 'Refusing to run: pass -v confirm=PROVISION_PRODUCTION_VALIDATION_DATA';
    end if;

    if v_expected_ref !~ '^[a-z0-9]{20}$' then
        raise exception 'Refusing to run: pass -v expected_project_ref=<20-character Supabase project ref>';
    end if;

    -- The Communications scheduler Vault secret holds this project's own
    -- Edge Function URL (https://<ref>.supabase.co/functions/v1/...). Its
    -- value is compared, never printed.
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

    -- 5.2 Schema / migration / RPC preflight --------------------------------

    if to_regclass('supabase_migrations.schema_migrations') is null
       or not exists (
           select 1
           from supabase_migrations.schema_migrations as migration
           where migration.version = '20261102090000'
       ) then
        raise exception 'Preflight failed: migration 20261102090000 is not recorded as applied';
    end if;

    select string_agg(signature, ', ')
    into v_missing
    from unnest(array[
        'public.current_domain_user_id()',
        'public.establish_veterinary_organization(uuid,text,uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,jsonb)',
        'public.create_my_veterinarian_professional_profile(text,text)',
        'public.add_staff_responsibility(uuid,uuid,text,text,uuid)',
        'public.derive_organization_subscription_current_state(uuid)',
        'public.organization_has_professional_entitlement(uuid,text)',
        'public.create_clinic(uuid,uuid)',
        'public.set_clinic_location(uuid,text,double precision,double precision)',
        'public.set_clinic_public_profile(uuid,text,text,text,text,text)',
        'public.set_clinic_scheduling_timezone(uuid,text)',
        'public.publish_clinic(uuid)',
        'public.set_clinic_standard_appointment_duration(uuid,integer)',
        'public.replace_clinic_opening_hours(uuid,jsonb)',
        'public.get_managed_clinic_appointment_availability(uuid)',
        'public.replace_clinic_appointment_availability(uuid,jsonb,bigint)',
        'public.replace_clinic_service_offerings(uuid,jsonb)',
        'public.assign_staff_veterinarian_to_clinic(uuid,uuid,uuid)',
        'public.veterinarian_clinic_assignment_is_current(uuid)',
        'public.replace_veterinarian_availability(uuid,jsonb)',
        'public.clinic_interval_is_covered_by_timezone(uuid,timestamp with time zone,timestamp with time zone,text)',
        'public.get_requestable_appointment_start_times(uuid,date,date)',
        'public.get_published_clinic_location(uuid)',
        'public.get_published_clinic_service_offerings(uuid)',
        'public.get_published_clinic_opening_hours(uuid)',
        'public.discover_nearby_clinics(double precision,double precision,double precision,integer,double precision,uuid)',
        'public.discover_clinics_in_viewport(double precision,double precision,double precision,double precision,integer,uuid)'
    ]) as signature
    where to_regprocedure(signature) is null;

    if v_missing is not null then
        raise exception 'Preflight failed: required functions are missing: %', v_missing;
    end if;

    if to_regclass('public.published_clinic_public_profiles') is null then
        raise exception 'Preflight failed: view public.published_clinic_public_profiles is missing';
    end if;

    -- The session role must be able to act as the OWNER / anon for the
    -- configuration steps and postflight.
    if not pg_has_role(current_user, 'authenticated', 'MEMBER')
       or not pg_has_role(current_user, 'anon', 'MEMBER') then
        raise exception 'Preflight failed: session role % cannot SET ROLE authenticated/anon', current_user;
    end if;

    -- Organization establishment is trusted-only (ADR-009): one call as the
    -- session role, never as authenticated.
    if not has_function_privilege(
        current_user,
        'public.establish_veterinary_organization(uuid,text,uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,jsonb)',
        'EXECUTE'
    ) then
        raise exception 'Preflight failed: session role % cannot execute establish_veterinary_organization', current_user;
    end if;

    -- 5.3 Manifest sanity ----------------------------------------------------

    select jsonb_agg(to_jsonb(resolved) order by resolved.ordinal)
    into v_manifest
    from pg_temp.mvv_resolved_clinic as resolved;

    select count(*) into v_count from pg_temp.mvv_clinic_manifest;

    if v_count <> settings.expected_clinic_count
       or jsonb_array_length(v_manifest) <> settings.expected_clinic_count then
        raise exception 'Manifest error: expected % Clinics, found % (resolved %)',
            settings.expected_clinic_count, v_count, jsonb_array_length(v_manifest);
    end if;

    -- The two Valverde Clinics must be 1-2 km apart (Nearby radius is 10 km).
    select 2.0 * 6371000.0 * asin(sqrt(
               power(sin(radians(south.latitude - north.latitude) / 2.0), 2)
               + cos(radians(north.latitude)) * cos(radians(south.latitude))
                 * power(sin(radians(south.longitude - north.longitude) / 2.0), 2)
           ))
    into v_distance_meters
    from pg_temp.mvv_clinic_manifest as north
    join pg_temp.mvv_clinic_manifest as south
      on south.clinic_key = 'valverde-sur'
    where north.clinic_key = 'valverde-norte';

    if v_distance_meters is null or v_distance_meters not between 1000 and 2000 then
        raise exception 'Manifest error: Valverde Clinics are % m apart (expected 1000-2000 m)',
            round(v_distance_meters::numeric);
    end if;

    -- 5.4 OWNER Auth user and domain User link ----------------------------------

    select count(*)
    into v_count
    from auth.users as auth_user
    where lower(auth_user.email) = lower(settings.owner_email);

    if v_count <> 1 then
        raise exception 'Preflight failed: expected exactly one Auth user for %, found %',
            settings.owner_email, v_count;
    end if;

    select auth_user.id
    into v_owner_auth_id
    from auth.users as auth_user
    where lower(auth_user.email) = lower(settings.owner_email)
      and auth_user.email_confirmed_at is not null
      and auth_user.deleted_at is null;

    if v_owner_auth_id is null then
        raise exception 'Preflight failed: OWNER Auth user % is not email-confirmed or is deleted',
            settings.owner_email;
    end if;

    select identity_link.user_id
    into v_owner_user_id
    from public.user_authentication_identities as identity_link
    where identity_link.provider = 'supabase_auth'
      and identity_link.issuer = 'primary'
      and identity_link.provider_subject = v_owner_auth_id;

    if v_owner_user_id is null then
        raise exception 'Preflight failed: OWNER Auth user has no domain User identity link';
    end if;

    -- 5.5 Existing-state classification (fresh vs. already provisioned) -------
    -- The dataset is identified by its establishment key, shared by the
    -- Organization (established by establish_veterinary_organization) and its
    -- initial Subscription (also by a dataset provisioned before 20261101090000,
    -- whose Organization has no establishment key). Never by display name.

    select organization.id, organization.establishment_idempotency_key is not null
    into v_org_id, v_org_keyed
    from public.veterinary_organizations as organization
    where organization.establishment_idempotency_key = settings.sub_key;

    select count(*)
    into v_count
    from public.organization_subscriptions as subscription
    where subscription.establishment_idempotency_key = settings.sub_key
       or subscription.establishment_source = settings.sub_source;

    if v_count > 1 then
        raise exception 'Unexpected state: % Subscriptions carry the dataset marker', v_count;
    end if;

    select subscription.id, subscription.organization_id
    into v_subscription_id, v_subscription_org_id
    from public.organization_subscriptions as subscription
    where subscription.establishment_idempotency_key = settings.sub_key
      and subscription.establishment_source = settings.sub_source;

    if v_count = 1 and v_subscription_id is null then
        raise exception 'Unexpected state: a Subscription carries only part of the dataset marker';
    end if;

    if v_org_id is not null and v_subscription_org_id is distinct from v_org_id then
        raise exception 'Unexpected state: the dataset Subscription belongs to a different Organization';
    end if;

    if v_org_id is null and v_subscription_org_id is not null then
        -- Provisioned before 20261101090000: the Organization has no key.
        select organization.id, false
        into v_org_id, v_org_keyed
        from public.veterinary_organizations as organization
        where organization.id = v_subscription_org_id
          and organization.establishment_idempotency_key is null;

        if v_org_id is null then
            raise exception 'Unexpected state: the dataset Subscription belongs to an Organization established with another key';
        end if;
    end if;

    if v_org_id is not null
       and (select organization.display_name from public.veterinary_organizations as organization
            where organization.id = v_org_id) is distinct from settings.org_name then
        raise exception 'Unexpected state: the dataset Organization is not named "%"', settings.org_name;
    end if;

    if v_org_id is not null then
        select membership.id
        into v_membership_id
        from public.organization_memberships as membership
        join public.organization_responsibility_grants as grant_record
          on grant_record.membership_id = membership.id
        where membership.organization_id = v_org_id
          and membership.user_id = v_owner_user_id
          and membership.effective_end is null
          and grant_record.effective_end is null
          and grant_record.responsibility = 'OWNER'
          and grant_record.scope_type = 'ORGANIZATION';

        if v_membership_id is null then
            raise exception 'Unexpected state: Organization "%" exists but is not owned by %',
                settings.org_name, settings.owner_email;
        end if;

        if v_subscription_id is null then
            raise exception 'Unexpected state: Organization "%" exists without the dataset Subscription',
                settings.org_name;
        end if;

        select derived.current_state
        into v_subscription_state
        from public.derive_organization_subscription_current_state(v_subscription_id) as derived;

        if v_subscription_state <> 'ACTIVE' then
            raise exception 'Unexpected state: dataset Subscription is % (dataset retired?). Re-provisioning requires a new review.',
                v_subscription_state;
        end if;

        if exists (
            select 1
            from public.organization_memberships as membership
            where membership.organization_id = v_org_id
              and membership.effective_end is null
              and membership.user_id <> v_owner_user_id
        ) then
            raise exception 'Unexpected state: Organization "%" has active members other than the OWNER',
                settings.org_name;
        end if;

        -- Every existing Clinic must be one of ours (by name + marker) ...
        if exists (
            select 1
            from public.clinics as clinic
            left join public.clinic_public_profiles as profile
              on profile.clinic_id = clinic.id
            where clinic.organization_id = v_org_id
              and (
                  profile.display_name is null
                  or profile.description is null
                  or position(settings.marker in profile.description) = 0
                  or not exists (
                      select 1
                      from pg_temp.mvv_clinic_manifest as manifest
                      where manifest.display_name = profile.display_name
                  )
              )
        ) then
            raise exception 'Unexpected state: Organization "%" contains Clinics not in this manifest',
                settings.org_name;
        end if;

        -- ... with no duplicates ...
        if exists (
            select 1
            from public.clinics as clinic
            join public.clinic_public_profiles as profile
              on profile.clinic_id = clinic.id
            where clinic.organization_id = v_org_id
            group by profile.display_name
            having count(*) > 1
        ) then
            raise exception 'Unexpected state: duplicate Clinic display names in Organization "%"',
                settings.org_name;
        end if;

        -- ... and the manifest must already be complete (all-or-nothing runs).
        if exists (
            select 1
            from pg_temp.mvv_clinic_manifest as manifest
            where not exists (
                select 1
                from public.clinics as clinic
                join public.clinic_public_profiles as profile
                  on profile.clinic_id = clinic.id
                where clinic.organization_id = v_org_id
                  and profile.display_name = manifest.display_name
            )
        ) then
            raise exception 'Unexpected state: Organization "%" exists but some manifest Clinics are missing',
                settings.org_name;
        end if;

        raise notice 'Dataset already provisioned: verifying and re-applying configuration';
    else
        if v_subscription_id is not null then
            raise exception 'Unexpected state: dataset Subscription exists without its Organization';
        end if;

        select count(*) into v_count from public.veterinary_organizations;
        raise notice 'Fresh provisioning (unrelated existing Organizations in this project: %)', v_count;
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.user_id = v_owner_user_id
          and membership.effective_end is null
          and membership.organization_id is distinct from v_org_id
    ) then
        raise exception 'Unexpected state: % has an active Membership in another Organization',
            settings.owner_email;
    end if;

    select profile.id, credential.registration_identifier
    into v_profile_id, v_credential_identifier
    from public.veterinarian_professional_profiles as profile
    left join public.veterinarian_professional_credentials as credential
      on credential.professional_profile_id = profile.id
    where profile.user_id = v_owner_user_id;

    if v_profile_id is not null
       and v_credential_identifier is distinct from settings.credential_registration_identifier then
        raise exception 'Unexpected state: OWNER already has a non-synthetic Professional Profile';
    end if;

    -- 5.6 Provisioning --------------------------------------------------------
    -- Organization + OWNER Membership + OWNER Grant + initial ACTIVE
    -- Subscription (all four professional Entitlements, finite validity), in
    -- ONE trusted call as the session role for the OWNER's domain User
    -- (ADR-009). A re-run of a dataset established this way replays it.
    if v_org_id is null or v_org_keyed then
        v_established := public.establish_veterinary_organization(
            v_owner_user_id,
            settings.org_name,
            settings.sub_key,
            'ACTIVE',
            settings.sub_initial_effective_at,
            null::timestamptz,
            settings.sub_valid_until,
            settings.sub_source,
            null::jsonb
        );

        if v_org_id is null then
            if v_established ->> 'outcome' <> 'ESTABLISHED' then
                raise exception 'Provisioning failed: fresh establishment returned %', v_established ->> 'outcome';
            end if;
            v_org_id := (v_established ->> 'organization_id')::uuid;
            v_membership_id := (v_established ->> 'owner_membership_id')::uuid;
            v_subscription_id := (v_established ->> 'subscription_id')::uuid;
            v_org_created := true;
        elsif v_established ->> 'outcome' <> 'ALREADY_ESTABLISHED'
              or (v_established ->> 'organization_id')::uuid <> v_org_id
              or (v_established ->> 'owner_membership_id')::uuid <> v_membership_id
              or (v_established ->> 'subscription_id')::uuid <> v_subscription_id then
            raise exception 'Unexpected state: the dataset establishment did not replay to the existing ids';
        end if;
    end if;

    -- The OWNER's own configuration operations run as the OWNER
    -- (transaction-local), after establishment.
    perform set_config('request.jwt.claim.sub', v_owner_auth_id::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_owner_auth_id, 'role', 'authenticated')::text,
        true
    );

    -- OWNER as the single synthetic Veterinarian: Professional Profile +
    -- Credential, then an Organization-scoped VETERINARIAN Grant on the same
    -- Membership (required by the professional-context lookups).
    if v_profile_id is null then
        set local role authenticated;
        v_profile_id := (public.create_my_veterinarian_professional_profile(
            settings.credential_registration_identifier,
            settings.credential_issuing_context
        ) ->> 'professional_profile_id')::uuid;
        reset role;
    end if;

    if not exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = v_membership_id
          and grant_record.responsibility = 'VETERINARIAN'
          and grant_record.scope_type = 'ORGANIZATION'
          and grant_record.clinic_id is null
          and grant_record.effective_end is null
    ) then
        set local role authenticated;
        perform public.add_staff_responsibility(
            v_org_id, v_membership_id, 'VETERINARIAN', 'ORGANIZATION', null
        );
        reset role;
    end if;

    if not public.organization_has_professional_entitlement(v_org_id, 'PROFESSIONAL_SCHEDULING')
       or not public.organization_has_professional_entitlement(v_org_id, 'APPOINTMENT_MANAGEMENT') then
        raise exception 'Provisioning failed: dataset Subscription does not grant scheduling Entitlements now (valid_until passed?)';
    end if;

    -- Clinics.
    for v_item in select value from jsonb_array_elements(v_manifest) loop
        select clinic.id
        into v_clinic_id
        from public.clinics as clinic
        join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        where clinic.organization_id = v_org_id
          and profile.display_name = v_item ->> 'display_name';

        v_clinic_created := false;

        if v_clinic_id is null then
            if not v_org_created then
                raise exception 'Unexpected state: Clinic "%" missing from an existing dataset',
                    v_item ->> 'display_name';
            end if;

            set local role authenticated;
            -- One creation intent per missing Clinic (SPEC-CLI-001 §10); the
            -- surrounding transaction is the retry unit, so a fresh key is safe.
            v_clinic_id := public.create_clinic(v_org_id, gen_random_uuid()) ->> 'clinic_id';
            reset role;
            v_clinic_created := true;
        end if;

        set local role authenticated;

        perform public.set_clinic_location(
            v_clinic_id,
            v_item ->> 'address_text',
            (v_item ->> 'latitude')::double precision,
            (v_item ->> 'longitude')::double precision
        );

        perform public.set_clinic_public_profile(
            v_clinic_id,
            v_item ->> 'display_name',
            v_item ->> 'description',
            null,
            v_item ->> 'public_email',
            v_item ->> 'website'
        );

        perform public.set_clinic_scheduling_timezone(v_clinic_id, settings.timezone_name);
        perform public.publish_clinic(v_clinic_id);
        perform public.set_clinic_standard_appointment_duration(
            v_clinic_id,
            (v_item ->> 'duration_minutes')::integer
        );
        perform public.replace_clinic_opening_hours(v_clinic_id, v_item -> 'opening_periods');
        -- Weekly stale-edit token (SPEC-APT-013 BR-74), read through the
        -- management read in this transaction; an identical week is a no-op.
        perform public.replace_clinic_appointment_availability(
            v_clinic_id,
            v_item -> 'availability_periods',
            (
                select managed.weekly_appointment_availability_revision
                from public.get_managed_clinic_appointment_availability(v_clinic_id) as managed
            )
        );
        perform public.replace_clinic_service_offerings(v_clinic_id, v_item -> 'service_offerings');

        reset role;

        select assignment.id
        into v_assignment_id
        from public.veterinarian_clinic_assignments as assignment
        where assignment.professional_profile_id = v_profile_id
          and assignment.clinic_id = v_clinic_id
          and assignment.supporting_membership_id = v_membership_id
          and assignment.effective_end is null;

        set local role authenticated;

        if v_assignment_id is null then
            v_assignment_id := (public.assign_staff_veterinarian_to_clinic(
                v_org_id,
                v_membership_id,
                v_clinic_id
            ) ->> 'veterinarian_clinic_assignment_id')::uuid;
        end if;

        -- Veterinarian Availability mirrors the Clinic's Appointment
        -- Availability so the OWNER can later be assigned to Appointments.
        perform public.replace_veterinarian_availability(
            v_assignment_id,
            v_item -> 'availability_periods'
        );

        reset role;

        insert into pg_temp.mvv_run_clinic (
            ordinal, clinic_id, veterinarian_clinic_assignment_id, clinic_created
        )
        values (
            (v_item ->> 'ordinal')::integer, v_clinic_id, v_assignment_id, v_clinic_created
        );
    end loop;

    insert into pg_temp.mvv_run_state (
        owner_auth_id, owner_user_id, organization_id, owner_membership_id,
        professional_profile_id, subscription_id, organization_created
    )
    values (
        v_owner_auth_id, v_owner_user_id, v_org_id, v_membership_id,
        v_profile_id, v_subscription_id, v_org_created
    );

    raise notice 'Provisioning applied: Organization %, % Clinics', v_org_id, jsonb_array_length(v_manifest);
end;
$provision$;

-- ----------------------------------------------------------------------------
-- 6. Postflight verification (still inside the transaction; any failure
--    rolls back everything above).
-- ----------------------------------------------------------------------------

do $postflight$
declare
    settings record;
    run_state record;
    v_clinic_ids uuid[];
    v_ordinals integer[];
    v_latitudes double precision[];
    v_longitudes double precision[];
    v_index integer;
    v_count integer;
    v_today date;
    v_result jsonb;
    v_after uuid;
    v_viewport_ids uuid[] := array[]::uuid[];
    v_candidate_counts integer[] := array[]::integer[];
    v_nearby_counts integer[] := array[]::integer[];
    v_valverde_ids uuid[];
    v_valverde_lat double precision;
    v_valverde_lon double precision;
    v_entitlement text;
begin
    select * into strict settings from pg_temp.mvv_settings;
    select * into strict run_state from pg_temp.mvv_run_state;

    select array_agg(run_clinic.clinic_id order by run_clinic.ordinal)
    into v_clinic_ids
    from pg_temp.mvv_run_clinic as run_clinic;

    -- 6.1 Exactly the intended Clinics exist in the dataset Organization.
    select count(*)
    into v_count
    from public.clinics as clinic
    where clinic.organization_id = run_state.organization_id;

    if v_count <> settings.expected_clinic_count
       or coalesce(array_length(v_clinic_ids, 1), 0) <> settings.expected_clinic_count then
        raise exception 'Postflight failed: Organization has % Clinics, expected %',
            v_count, settings.expected_clinic_count;
    end if;

    if exists (
        select 1
        from pg_temp.mvv_resolved_clinic as resolved
        join pg_temp.mvv_run_clinic as run_clinic
          on run_clinic.ordinal = resolved.ordinal
        join public.clinics as clinic
          on clinic.id = run_clinic.clinic_id
        left join public.clinic_public_profiles as profile
          on profile.clinic_id = clinic.id
        left join public.clinic_locations as location
          on location.clinic_id = clinic.id
        where clinic.organization_id is distinct from run_state.organization_id
           or clinic.is_published is distinct from true
           or clinic.scheduling_timezone_name is distinct from settings.timezone_name
           or clinic.standard_appointment_duration_minutes is distinct from resolved.duration_minutes
           or profile.display_name is distinct from resolved.display_name
           or profile.description is distinct from resolved.description
           or profile.public_phone is not null
           or location.latitude is distinct from resolved.latitude
           or location.longitude is distinct from resolved.longitude
           or not exists (select 1 from public.clinic_service_offerings as offering where offering.clinic_id = clinic.id)
           or not exists (select 1 from public.clinic_opening_periods as period where period.clinic_id = clinic.id)
           or not exists (select 1 from public.clinic_appointment_availability_periods as period where period.clinic_id = clinic.id)
           or exists (select 1 from public.clinic_appointment_availability_exceptions as exception_record where exception_record.clinic_id = clinic.id)
    ) then
        raise exception 'Postflight failed: at least one Clinic is not fully configured and published as intended';
    end if;

    -- 6.2 Entitlements and professional context.
    foreach v_entitlement in array array[
        'APPOINTMENT_MANAGEMENT', 'PROFESSIONAL_SCHEDULING', 'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
    ] loop
        if not public.organization_has_professional_entitlement(run_state.organization_id, v_entitlement) then
            raise exception 'Postflight failed: Entitlement % is not granted', v_entitlement;
        end if;
    end loop;

    if not exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = run_state.owner_membership_id
          and grant_record.responsibility = 'VETERINARIAN'
          and grant_record.scope_type = 'ORGANIZATION'
          and grant_record.effective_end is null
    ) then
        raise exception 'Postflight failed: OWNER has no active VETERINARIAN Grant';
    end if;

    if exists (
        select 1
        from pg_temp.mvv_run_clinic as run_clinic
        where not public.veterinarian_clinic_assignment_is_current(run_clinic.veterinarian_clinic_assignment_id)
           or not exists (
               select 1
               from public.veterinarian_availability_periods as period
               where period.veterinarian_clinic_assignment_id = run_clinic.veterinarian_clinic_assignment_id
           )
    ) then
        raise exception 'Postflight failed: a Veterinarian Clinic Assignment is not current or has no Availability';
    end if;

    -- 6.3 Anonymous Discovery surfaces (public list, Clinic detail, Nearby, map).
    select resolved.latitude, resolved.longitude
    into v_valverde_lat, v_valverde_lon
    from pg_temp.mvv_resolved_clinic as resolved
    where resolved.clinic_key = 'valverde-norte';

    select array_agg(run_clinic.clinic_id)
    into v_valverde_ids
    from pg_temp.mvv_run_clinic as run_clinic
    join pg_temp.mvv_resolved_clinic as resolved
      on resolved.ordinal = run_clinic.ordinal
    where resolved.city = 'Valverde del Camino';

    -- Everything read from pg_temp is collected here, as the session role:
    -- anon/authenticated have no privileges on these temp tables.
    select
        array_agg(resolved.ordinal order by resolved.ordinal),
        array_agg(resolved.latitude order by resolved.ordinal),
        array_agg(resolved.longitude order by resolved.ordinal)
    into v_ordinals, v_latitudes, v_longitudes
    from pg_temp.mvv_resolved_clinic as resolved;

    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    set local role anon;

    select count(*)
    into v_count
    from public.published_clinic_public_profiles as published
    where published.clinic_id = any(v_clinic_ids);

    if v_count <> settings.expected_clinic_count then
        reset role;
        raise exception 'Postflight failed: public Clinic list shows % of % dataset Clinics',
            v_count, settings.expected_clinic_count;
    end if;

    for v_index in 1 .. array_length(v_clinic_ids, 1) loop
        if not exists (select 1 from public.get_published_clinic_location(v_clinic_ids[v_index])) then
            raise exception 'Postflight failed: no published location for Clinic #%', v_ordinals[v_index];
        end if;

        if not exists (select 1 from public.get_published_clinic_service_offerings(v_clinic_ids[v_index])) then
            raise exception 'Postflight failed: no published Services for Clinic #%', v_ordinals[v_index];
        end if;

        if not exists (
            select 1
            from public.get_published_clinic_opening_hours(v_clinic_ids[v_index]) as hours
            where hours.scheduling_timezone_name = 'Europe/Madrid'
              and jsonb_array_length(hours.recurring_periods) > 0
        ) then
            raise exception 'Postflight failed: no published Opening Hours for Clinic #%', v_ordinals[v_index];
        end if;

        v_result := public.discover_nearby_clinics(v_latitudes[v_index], v_longitudes[v_index], 10000, 100);

        if not exists (
            select 1
            from jsonb_array_elements(v_result -> 'clinics') as clinic_item
            where (clinic_item ->> 'clinic_id')::uuid = v_clinic_ids[v_index]
        ) then
            raise exception 'Postflight failed: Nearby Discovery does not return Clinic #%', v_ordinals[v_index];
        end if;

        v_nearby_counts := v_nearby_counts || jsonb_array_length(v_result -> 'clinics');
    end loop;

    -- Both Valverde Clinics appear together within the 10 km Nearby radius.
    v_result := public.discover_nearby_clinics(v_valverde_lat, v_valverde_lon, 10000, 100);

    if (
        select count(*)
        from jsonb_array_elements(v_result -> 'clinics') as clinic_item
        where (clinic_item ->> 'clinic_id')::uuid = any(v_valverde_ids)
    ) <> 2 then
        reset role;
        raise exception 'Postflight failed: Nearby Discovery from Valverde does not return both Valverde Clinics';
    end if;

    -- Map/viewport covering mainland Spain returns every dataset Clinic.
    v_after := null;
    loop
        v_result := public.discover_clinics_in_viewport(35.5, 44.0, -10.0, 4.5, 100, v_after);

        v_viewport_ids := v_viewport_ids || array(
            select (clinic_item ->> 'clinic_id')::uuid
            from jsonb_array_elements(v_result -> 'clinics') as clinic_item
        );

        exit when not coalesce((v_result ->> 'has_more')::boolean, false);
        v_after := (v_result ->> 'next_after_clinic_id')::uuid;
    end loop;

    reset role;

    if not (v_clinic_ids <@ v_viewport_ids) then
        raise exception 'Postflight failed: map/viewport Discovery does not return every dataset Clinic';
    end if;

    -- 6.4 Candidate Appointment times (authenticated), 30 Clinic-local days.
    v_today := (clock_timestamp() at time zone settings.timezone_name)::date;

    perform set_config('request.jwt.claim.sub', run_state.owner_auth_id::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', run_state.owner_auth_id, 'role', 'authenticated')::text,
        true
    );
    set local role authenticated;

    for v_index in 1 .. array_length(v_clinic_ids, 1) loop
        v_candidate_counts := v_candidate_counts || (
            select count(*)::integer
            from public.get_requestable_appointment_start_times(
                v_clinic_ids[v_index], v_today, v_today + 30
            )
        );
    end loop;

    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    insert into pg_temp.mvv_postflight (ordinal, candidate_count, nearby_result_count)
    select entry.ordinal, entry.candidate_count, entry.nearby_count
    from unnest(v_ordinals, v_candidate_counts, v_nearby_counts)
        as entry(ordinal, candidate_count, nearby_count);

    if exists (select 1 from pg_temp.mvv_postflight as postflight where postflight.candidate_count = 0) then
        raise exception 'Postflight failed: at least one Clinic has no requestable Appointment times in the next 30 days';
    end if;

    raise notice 'Postflight passed for all % Clinics', settings.expected_clinic_count;
end;
$postflight$;

-- ----------------------------------------------------------------------------
-- 7. Report
-- ----------------------------------------------------------------------------

select
    run_state.organization_id,
    run_state.organization_created,
    run_state.subscription_id,
    run_state.professional_profile_id,
    run_state.owner_membership_id
from pg_temp.mvv_run_state as run_state;

select
    resolved.ordinal,
    resolved.city,
    resolved.display_name,
    run_clinic.clinic_id,
    run_clinic.clinic_created,
    resolved.duration_minutes,
    postflight.candidate_count as candidates_next_30_days,
    postflight.nearby_result_count as nearby_10km_results
from pg_temp.mvv_resolved_clinic as resolved
join pg_temp.mvv_run_clinic as run_clinic
  on run_clinic.ordinal = resolved.ordinal
join pg_temp.mvv_postflight as postflight
  on postflight.ordinal = resolved.ordinal
order by resolved.ordinal;

commit;
