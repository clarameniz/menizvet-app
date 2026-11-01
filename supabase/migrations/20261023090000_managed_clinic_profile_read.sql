-- Clinic self-service Phase 1, Slice A: the managed Clinic configuration read
-- (SPEC-CLI-007 BR-1–BR-6).
--
-- Adds `get_managed_clinic_profile(p_clinic_id uuid) returns jsonb`, the read
-- side of Clinic self-service. It returns exactly
--
--   {
--     "clinic_id": uuid,
--     "is_published": boolean,
--     "scheduling_timezone_name": text | null,
--     "public_profile": null | { "display_name", "description", "public_phone",
--                                "public_email", "website" }  -- each text | null
--     "location": null | { "address_text": text, "latitude": float8,
--                          "longitude": float8 }
--   }
--
-- with every member always present and values exactly as stored. It returns
-- no standard duration, Appointment Availability, Opening Hours, Service
-- Offerings, Subscription, or Entitlement data (BR-6).
--
-- Authorization (BR-2–BR-4): an authenticated domain User holding, for the
-- Clinic, at least one of CLINIC_MANAGE_PUBLIC_PROFILE, CLINIC_MANAGE_LOCATION,
-- CLINIC_MANAGE_PUBLICATION, or CLINIC_MANAGE_OPENING_HOURS, evaluated with the
-- same non-locking user_has_clinic_capability(...) every management read uses
-- since 20261014090000. No Entitlement and no publication are required, so an
-- unpublished Clinic is readable. A nonexistent Clinic and an inaccessible one
-- fail alike with 42501 "Applicable Clinic-management capability is
-- required" (user_has_clinic_capability is false for an unknown Clinic).
--
-- Consistency and locking (BR-5): STABLE, no row lock; the payload is built by
-- one SELECT, so publication, timezone, profile, and location come from one
-- snapshot.
--
-- Additive only: no table, column, constraint, index, trigger, grant on a
-- table, write RPC, or existing data changes. The four Clinic self-service
-- writes and their disclosure-order gaps are untouched (Slices B and C).

begin;

create function public.get_managed_clinic_profile(
    p_clinic_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    profile_result jsonb;
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

    -- False for an unknown Clinic as for an inaccessible one (BR-4).
    if not exists (
        select 1
        from unnest(array[
            'CLINIC_MANAGE_PUBLIC_PROFILE',
            'CLINIC_MANAGE_LOCATION',
            'CLINIC_MANAGE_PUBLICATION',
            'CLINIC_MANAGE_OPENING_HOURS'
        ]) as self_service_capability (capability)
        where public.user_has_clinic_capability(
            acting_user_id,
            p_clinic_id,
            self_service_capability.capability
        )
    ) then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    -- One statement, one snapshot (BR-5).
    select jsonb_build_object(
        'clinic_id', clinic.id,
        'is_published', clinic.is_published,
        'scheduling_timezone_name', clinic.scheduling_timezone_name,
        'public_profile', case
            when profile.clinic_id is null then null
            else jsonb_build_object(
                'display_name', profile.display_name,
                'description', profile.description,
                'public_phone', profile.public_phone,
                'public_email', profile.public_email,
                'website', profile.website
            )
        end,
        'location', case
            when location.clinic_id is null then null
            else jsonb_build_object(
                'address_text', location.address_text,
                'latitude', location.latitude,
                'longitude', location.longitude
            )
        end
    )
    into profile_result
    from public.clinics as clinic
    left join public.clinic_public_profiles as profile
      on profile.clinic_id = clinic.id
    left join public.clinic_locations as location
      on location.clinic_id = clinic.id
    where clinic.id = p_clinic_id;

    if profile_result is null then
        raise exception 'Applicable Clinic-management capability is required'
            using errcode = '42501';
    end if;

    return profile_result;
end;
$$;

revoke all privileges
on function public.get_managed_clinic_profile(uuid)
from public, anon, authenticated;

grant execute
on function public.get_managed_clinic_profile(uuid)
to authenticated;

commit;
