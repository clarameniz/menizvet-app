-- SPEC-ORG-008 — View My Professional Clinics.
--
-- Adds the self-scoped, advisory read `public.get_my_professional_clinics()`.
--
-- No new authorization logic is introduced. A Clinic's effective
-- Clinic-context capabilities are exactly the `CLINIC`-context entries of
-- `professional_capability_catalog()` for which the authoritative predicate
-- used by every protected Clinic operation, `user_has_clinic_capability`,
-- holds for the acting User (SPEC-ORG-008 BR-2, BR-10). A Clinic is returned
-- if and only if that set is non-empty. There is no responsibility-to-
-- capability mapping in this function; it neither restates nor duplicates
-- the scoped helpers introduced by 20261001120000_professional_context_read.sql.
--
-- Candidate Clinics are every Clinic of every Veterinary Organization in
-- which the acting User holds a current Organization Membership. This bound
-- is complete, not a filter: every branch of `user_has_clinic_capability`
-- (Organization-scoped grant, Clinic-scoped grant, and the VETERINARIAN /
-- current Clinic Assignment path) requires a current Membership of the acting
-- User in the Organization that operates the Clinic. The bound only limits how
-- many predicate evaluations are performed; it never decides inclusion.
--
-- Subscription and Entitlement state are not consulted (SPEC-ORG-008 BR-11).
-- Publication state is neither consulted nor returned (BR-9). Pagination is
-- intentionally absent in Phase 1 (BR-16).
--
-- No table, column, index, constraint, table grant, existing function, or
-- existing data is changed.

begin;

-- ==================================================================
-- SPEC-ORG-008 — View My Professional Clinics.
--
-- Returned shape (jsonb):
--
--   {
--     "clinics": [
--       {
--         "clinic_id": uuid,
--         "clinic_display_name": text | null,
--         "organization_id": uuid,
--         "organization_display_name": text,
--         "capabilities": [text, ...]
--       }
--     ]
--   }
--
-- Ordering (BR-15): Organization display name, Organization id, Clinic
-- display name (nulls last), Clinic id. Capability identifiers are ordered by
-- identifier using binary ("C") collation so the order is independent of the
-- database locale. The result is advisory: protected operations re-evaluate
-- everything themselves (BR-13).
-- ==================================================================

create function public.get_my_professional_clinics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    clinics_result jsonb;
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

    with candidate_clinic as (
        select distinct
            clinic.id as clinic_id,
            clinic.organization_id
        from public.organization_memberships as membership
        join public.clinics as clinic
          on clinic.organization_id = membership.organization_id
        where membership.user_id = acting_user_id
          and membership.effective_end is null
    ),
    effective_clinic_capability as (
        select
            candidate_clinic.clinic_id,
            candidate_clinic.organization_id,
            catalog_entry.capability
        from candidate_clinic
        cross join public.professional_capability_catalog() as catalog_entry
        where catalog_entry.capability_context = 'CLINIC'
          and public.user_has_clinic_capability(acting_user_id, candidate_clinic.clinic_id, catalog_entry.capability)
    ),
    clinic_entry as (
        select
            effective_clinic_capability.clinic_id,
            effective_clinic_capability.organization_id,
            organization.display_name as organization_display_name,
            public_profile.display_name as clinic_display_name,
            jsonb_agg(
                effective_clinic_capability.capability
                order by effective_clinic_capability.capability collate "C"
            ) as capabilities
        from effective_clinic_capability
        join public.veterinary_organizations as organization
          on organization.id = effective_clinic_capability.organization_id
        left join public.clinic_public_profiles as public_profile
          on public_profile.clinic_id = effective_clinic_capability.clinic_id
        group by
            effective_clinic_capability.clinic_id,
            effective_clinic_capability.organization_id,
            organization.display_name,
            public_profile.display_name
    )
    select jsonb_build_object(
        'clinics', coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'clinic_id', clinic_entry.clinic_id,
                    'clinic_display_name', clinic_entry.clinic_display_name,
                    'organization_id', clinic_entry.organization_id,
                    'organization_display_name', clinic_entry.organization_display_name,
                    'capabilities', clinic_entry.capabilities
                )
                order by
                    clinic_entry.organization_display_name,
                    clinic_entry.organization_id,
                    clinic_entry.clinic_display_name nulls last,
                    clinic_entry.clinic_id
            ),
            '[]'::jsonb
        )
    )
    into clinics_result
    from clinic_entry;

    return clinics_result;
end;
$$;

revoke all privileges
on function public.get_my_professional_clinics()
from public, anon, authenticated;

grant execute
on function public.get_my_professional_clinics()
to authenticated;

commit;
