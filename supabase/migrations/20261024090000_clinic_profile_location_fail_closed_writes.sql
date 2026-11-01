-- Clinic self-service Phase 1, Slice B: fail-closed authorization and
-- disclosure order for the two writes the Profile and Location editors use
-- (SPEC-CLI-004 BR-15–BR-20, SPEC-CLI-002 BR-12–BR-17).
--
-- Forward-only. set_clinic_public_profile and set_clinic_location (both last
-- defined in 20260825150316_clinic_foundation_and_professional_context.sql)
-- are replaced in place: same signatures, results, attributes, and ACL.
--
-- Before, an unknown Clinic was reported as 23503 "Clinic does not exist"
-- before any capability check, and set_clinic_location validated its input
-- (22023) before establishing the Clinic or the caller's capability, so a
-- caller could probe whether a Clinic exists and learn how its input would be
-- judged. Now each write follows the approved order:
--
--   1. unauthenticated (no auth subject, or no coherent domain User) → 28000;
--   2. a nonexistent Clinic and a Clinic the caller may not manage → the same
--      42501 with the operation's existing capability message, whatever input
--      was submitted;
--   3. only for an authorized caller: input validation (location → 22023);
--   4. then state rules (a published Clinic keeps its display name → 23514).
--
-- Unchanged, deliberately: the Organization → Clinic FOR UPDATE lock order;
-- the capability each write requires; the backend whitespace set
-- E' \t\n\r\f\013'; whole-value replacement (one profile save replaces all
-- five values; one location save replaces address and both coordinates);
-- blank profile values stored as NULL and an all-absent unpublished profile
-- removed; no format or length validation; no location removal; no
-- Entitlement or publication requirement; last-write-wins (no revision); the
-- deferred publication-integrity triggers; every message text.
--
-- The shared helper assert_clinic_capability_after_lock (used by many other
-- writes, including set_clinic_scheduling_timezone and publish_clinic) is NOT
-- changed: Slice C normalizes the timezone and publication writes it owns.

begin;

create or replace function public.set_clinic_location(
    p_clinic_id uuid,
    p_address_text text,
    p_latitude double precision,
    p_longitude double precision
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    normalized_address_text text;
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

    -- 2. Resource authorization, under the Organization -> Clinic locks. An
    --    unknown Clinic is reported exactly like an inaccessible one, before
    --    anything about the submitted input is evaluated.
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic Location-management capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found
       or not public.user_has_clinic_capability(
           acting_user_id,
           p_clinic_id,
           'CLINIC_MANAGE_LOCATION'
       ) then
        raise exception 'Clinic Location-management capability is required'
            using errcode = '42501';
    end if;

    -- 3. Input validation, only for an authorized caller.
    normalized_address_text := btrim(
        p_address_text,
        E' \t\n\r\f\013'
    );

    if normalized_address_text is null or normalized_address_text = '' then
        raise exception 'Clinic Location address must not be blank'
            using errcode = '22023';
    end if;

    if p_latitude is null or p_latitude not between -90.0 and 90.0 then
        raise exception 'Clinic Location latitude must be between -90 and 90'
            using errcode = '22023';
    end if;

    if p_longitude is null or p_longitude not between -180.0 and 180.0 then
        raise exception 'Clinic Location longitude must be between -180 and 180'
            using errcode = '22023';
    end if;

    -- 4. Whole-location replacement (last-write-wins).
    insert into public.clinic_locations (
        clinic_id,
        address_text,
        latitude,
        longitude
    )
    values (
        p_clinic_id,
        normalized_address_text,
        p_latitude,
        p_longitude
    )
    on conflict (clinic_id) do update
    set address_text = excluded.address_text,
        latitude = excluded.latitude,
        longitude = excluded.longitude;

    return p_clinic_id;
end;
$$;

create or replace function public.set_clinic_public_profile(
    p_clinic_id uuid,
    p_display_name text,
    p_description text,
    p_public_phone text,
    p_public_email text,
    p_website text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    clinic_record public.clinics%rowtype;
    normalized_display_name text;
    normalized_description text;
    normalized_public_phone text;
    normalized_public_email text;
    normalized_website text;
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

    -- 2. Resource authorization, under the Organization -> Clinic locks. An
    --    unknown Clinic is reported exactly like an inaccessible one.
    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic Public Profile-management capability is required'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select clinic.*
    into clinic_record
    from public.clinics as clinic
    where clinic.id = p_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    if not found
       or not public.user_has_clinic_capability(
           acting_user_id,
           p_clinic_id,
           'CLINIC_MANAGE_PUBLIC_PROFILE'
       ) then
        raise exception 'Clinic Public Profile-management capability is required'
            using errcode = '42501';
    end if;

    -- 3. Normalization (the profile has no input error of its own): blank
    --    after trimming the backend whitespace set means absent.
    normalized_display_name := nullif(
        btrim(p_display_name, E' \t\n\r\f\013'),
        ''
    );
    normalized_description := nullif(
        btrim(p_description, E' \t\n\r\f\013'),
        ''
    );
    normalized_public_phone := nullif(
        btrim(p_public_phone, E' \t\n\r\f\013'),
        ''
    );
    normalized_public_email := nullif(
        btrim(p_public_email, E' \t\n\r\f\013'),
        ''
    );
    normalized_website := nullif(
        btrim(p_website, E' \t\n\r\f\013'),
        ''
    );

    -- 4. State rule: a published Clinic keeps its display name.
    if clinic_record.is_published
       and normalized_display_name is null then
        raise exception 'A published Clinic must retain a valid public display name'
            using errcode = '23514';
    end if;

    -- 5. Whole-profile replacement (last-write-wins); an all-absent profile
    --    of an unpublished Clinic is removed.
    if normalized_display_name is null
       and normalized_description is null
       and normalized_public_phone is null
       and normalized_public_email is null
       and normalized_website is null then
        delete from public.clinic_public_profiles as profile
        where profile.clinic_id = p_clinic_id;

        return p_clinic_id;
    end if;

    insert into public.clinic_public_profiles (
        clinic_id,
        display_name,
        description,
        public_phone,
        public_email,
        website
    )
    values (
        p_clinic_id,
        normalized_display_name,
        normalized_description,
        normalized_public_phone,
        normalized_public_email,
        normalized_website
    )
    on conflict (clinic_id) do update
    set display_name = excluded.display_name,
        description = excluded.description,
        public_phone = excluded.public_phone,
        public_email = excluded.public_email,
        website = excluded.website;

    return p_clinic_id;
end;
$$;

commit;
