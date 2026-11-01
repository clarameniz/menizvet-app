-- SPEC-ORG-007 — View My Professional Context.
--
-- Adds the self-scoped, advisory professional-context read
-- `public.get_my_professional_context()` and makes the Phase 1 capability
-- catalog (SPEC-ORG-005 §5) and the responsibility-to-capability mapping
-- single-sourced, so that the read and every protected operation share one
-- authoritative evaluation:
--
-- 1. `professional_capability_catalog()` is the single authoritative complete
--    catalog of Phase 1 capability identifiers. The scoped helpers below
--    remain the authoritative responsibility-to-capability mapping and
--    legitimately contain responsibility-specific subsets (for example the
--    RECEPTIONIST and VETERINARIAN capability sets). The professional-context
--    read and every protected operation use those same helpers.
-- 2. `user_has_organization_capability` is redefined to consult the catalog
--    instead of an inline list. Its signature, attributes, and observable
--    behavior are unchanged.
-- 3. The body of `user_has_clinic_capability` is split, without behavior
--    change, into two internal predicates:
--      - `user_has_organization_scoped_clinic_capability` (Organization-scoped
--        `OWNER`, `ADMINISTRATOR`, and `RECEPTIONIST` grants);
--      - `user_has_clinic_scoped_clinic_capability` (Clinic-scoped
--        `ADMINISTRATOR` and `RECEPTIONIST` grants, and the `VETERINARIAN`
--        branch requiring a current Veterinarian Clinic Assignment).
--    `user_has_clinic_capability` keeps its signature and attributes and is
--    now exactly the disjunction of the two. Every existing protected
--    operation therefore keeps its current authorization, and the
--    professional-context read uses the same predicates to report capability
--    scope.
--
-- No table, column, index, constraint, grant on a table, or existing data is
-- changed. No Entitlement, Subscription, Commercial Onboarding, or
-- Organization-establishment behavior is changed.

begin;

-- ==================================================================
-- 1. Phase 1 capability catalog (SPEC-ORG-005 §5).
--
-- capability_context identifies how a capability is evaluated:
--   ORGANIZATION — evaluated for a Veterinary Organization
--                  (user_has_organization_capability);
--   CLINIC       — evaluated for a Clinic (user_has_clinic_capability),
--                  possibly through an Organization-scoped responsibility.
-- ==================================================================

create function public.professional_capability_catalog()
returns table (
    capability text,
    capability_context text
)
language sql
immutable
set search_path = ''
as $$
    select catalog_entry.capability, catalog_entry.capability_context
    from (
        values
            ('ORGANIZATION_INVITE_MEMBERS', 'ORGANIZATION'),
            ('ORGANIZATION_REVOKE_INVITATIONS', 'ORGANIZATION'),
            ('ORGANIZATION_END_MEMBERSHIPS', 'ORGANIZATION'),
            ('ORGANIZATION_GRANT_RESPONSIBILITIES', 'ORGANIZATION'),
            ('ORGANIZATION_CREATE_CLINICS', 'ORGANIZATION'),
            ('ORGANIZATION_MANAGE_SUBSCRIPTION', 'ORGANIZATION'),
            ('CLINIC_MANAGE_LOCATION', 'CLINIC'),
            ('CLINIC_MANAGE_PUBLICATION', 'CLINIC'),
            ('CLINIC_MANAGE_PUBLIC_PROFILE', 'CLINIC'),
            ('CLINIC_MANAGE_SERVICES', 'CLINIC'),
            ('CLINIC_MANAGE_OPENING_HOURS', 'CLINIC'),
            ('CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS', 'CLINIC'),
            ('APPOINTMENT_VIEW_SCHEDULE', 'CLINIC'),
            ('APPOINTMENT_CONFIRM', 'CLINIC'),
            ('APPOINTMENT_CANCEL', 'CLINIC'),
            ('APPOINTMENT_RESCHEDULE', 'CLINIC'),
            ('APPOINTMENT_ASSIGN_VETERINARIAN', 'CLINIC'),
            ('APPOINTMENT_COMPLETE', 'CLINIC'),
            ('APPOINTMENT_MARK_NO_SHOW', 'CLINIC'),
            ('APPOINTMENT_MANAGE_AVAILABILITY', 'CLINIC'),
            ('CLINICAL_CARE', 'CLINIC'),
            ('CLINICAL_DOCUMENTATION', 'CLINIC')
    ) as catalog_entry (capability, capability_context)
$$;

revoke all privileges
on function public.professional_capability_catalog()
from public, anon, authenticated;

-- ==================================================================
-- 2. Organization-context capabilities (behavior unchanged; the inline
--    identifier list is replaced by the catalog).
-- ==================================================================

create or replace function public.user_has_organization_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'ORGANIZATION'
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where membership.user_id = p_user_id
              and membership.organization_id = p_organization_id
              and membership.effective_end is null
              and grant_record.effective_end is null
              and grant_record.scope_type = 'ORGANIZATION'
              and grant_record.responsibility in ('OWNER', 'ADMINISTRATOR')
        )
$$;

revoke all privileges
on function public.user_has_organization_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 3. Clinic-context capability provided by an Organization-scoped
--    responsibility. It applies to every Clinic of the Organization
--    (SPEC-ORG-005 §6).
-- ==================================================================

create function public.user_has_organization_scoped_clinic_capability(
    p_user_id uuid,
    p_organization_id uuid,
    p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'CLINIC'
        )
        and exists (
            select 1
            from public.organization_memberships as membership
            join public.organization_responsibility_grants as responsibility_grant
              on responsibility_grant.membership_id = membership.id
            where membership.organization_id = p_organization_id
              and membership.user_id = p_user_id
              and membership.effective_end is null
              and responsibility_grant.effective_end is null
              and responsibility_grant.scope_type = 'ORGANIZATION'
              and responsibility_grant.clinic_id is null
              and (
                (
                  responsibility_grant.responsibility in ('OWNER', 'ADMINISTRATOR')
                  and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                )
                or (
                  responsibility_grant.responsibility = 'RECEPTIONIST'
                  and p_capability in (
                    'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                    'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                    'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                    'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                  )
                )
              )
        )
$$;

revoke all privileges
on function public.user_has_organization_scoped_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 4. Clinic-context capability provided only for one specific Clinic:
--    Clinic-scoped ADMINISTRATOR / RECEPTIONIST, and VETERINARIAN through a
--    current Veterinarian Clinic Assignment (SPEC-ORG-005 §6).
-- ==================================================================

create function public.user_has_clinic_scoped_clinic_capability(
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
        exists (
            select 1
            from public.professional_capability_catalog() as catalog_entry
            where catalog_entry.capability = p_capability
              and catalog_entry.capability_context = 'CLINIC'
        )
        and (
            exists (
                select 1
                from public.clinics as clinic
                join public.organization_memberships as membership
                  on membership.organization_id = clinic.organization_id
                join public.organization_responsibility_grants as responsibility_grant
                  on responsibility_grant.membership_id = membership.id
                where clinic.id = p_clinic_id
                  and membership.user_id = p_user_id
                  and membership.effective_end is null
                  and responsibility_grant.effective_end is null
                  and responsibility_grant.scope_type = 'CLINIC'
                  and responsibility_grant.clinic_id = p_clinic_id
                  and (
                    (
                      responsibility_grant.responsibility = 'ADMINISTRATOR'
                      and p_capability not in ('CLINICAL_CARE', 'CLINICAL_DOCUMENTATION')
                    )
                    or (
                      responsibility_grant.responsibility = 'RECEPTIONIST'
                      and p_capability in (
                        'APPOINTMENT_MANAGE_AVAILABILITY', 'APPOINTMENT_VIEW_SCHEDULE',
                        'APPOINTMENT_CONFIRM', 'APPOINTMENT_RESCHEDULE',
                        'APPOINTMENT_ASSIGN_VETERINARIAN', 'APPOINTMENT_CANCEL',
                        'APPOINTMENT_COMPLETE', 'APPOINTMENT_MARK_NO_SHOW'
                      )
                    )
                  )
            )
            or (
                p_capability in (
                    'APPOINTMENT_VIEW_SCHEDULE', 'APPOINTMENT_COMPLETE',
                    'CLINICAL_CARE', 'CLINICAL_DOCUMENTATION'
                )
                and exists (
                    select 1
                    from public.clinics as clinic
                    join public.organization_memberships as membership
                      on membership.organization_id = clinic.organization_id
                    join public.organization_responsibility_grants as responsibility_grant
                      on responsibility_grant.membership_id = membership.id
                    join public.veterinarian_clinic_assignments as clinic_assignment
                      on clinic_assignment.supporting_membership_id = membership.id
                     and clinic_assignment.clinic_id = p_clinic_id
                    join public.veterinarian_professional_profiles as profile
                      on profile.id = clinic_assignment.professional_profile_id
                     and profile.user_id = p_user_id
                    where clinic.id = p_clinic_id
                      and membership.user_id = p_user_id
                      and membership.effective_end is null
                      and responsibility_grant.effective_end is null
                      and responsibility_grant.membership_id = membership.id
                      and responsibility_grant.responsibility = 'VETERINARIAN'
                      and responsibility_grant.scope_type = 'ORGANIZATION'
                      and responsibility_grant.clinic_id is null
                      and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
                )
            )
        )
$$;

revoke all privileges
on function public.user_has_clinic_scoped_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 5. Authoritative Clinic capability used by every protected operation:
--    exactly the disjunction of the two predicates above (behavior
--    unchanged from 20260829120000_clinical_care.sql).
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
        exists (
            select 1
            from public.clinics as clinic
            where clinic.id = p_clinic_id
              and public.user_has_organization_scoped_clinic_capability(
                  p_user_id, clinic.organization_id, p_capability
              )
        )
        or public.user_has_clinic_scoped_clinic_capability(
            p_user_id, p_clinic_id, p_capability
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

-- ==================================================================
-- 6. SPEC-ORG-007 — View My Professional Context.
--
-- Returned shape (jsonb):
--
--   {
--     "has_veterinarian_professional_profile": boolean,
--     "organizations": [
--       {
--         "membership_id": uuid,
--         "organization_id": uuid,
--         "organization_display_name": text,
--         "responsibilities": [
--           { "responsibility": text,
--             "scope_type": "ORGANIZATION" | "CLINIC",
--             "clinic": null | { "clinic_id": uuid,
--                                "clinic_display_name": text | null } }
--         ],
--         "capabilities": [
--           { "capability": text,
--             "scope_type": "ORGANIZATION" | "CLINIC",
--             "clinic": null | { "clinic_id": uuid,
--                                "clinic_display_name": text | null } }
--         ],
--         "clinic_assignments": [
--           { "veterinarian_clinic_assignment_id": uuid,
--             "clinic": { "clinic_id": uuid,
--                         "clinic_display_name": text | null } }
--         ],
--         "entitlements": {
--           "APPOINTMENT_MANAGEMENT": boolean,
--           "PROFESSIONAL_SCHEDULING": boolean,
--           "CLINICAL_CARE": boolean,
--           "CLINICAL_DOCUMENTATION": boolean
--         }
--       }
--     ]
--   }
--
-- Only current relationships are returned. Organization-scoped capabilities
-- apply to every Clinic of the Organization; a Clinic-scoped capability is
-- reported only where it is not already provided with Organization scope.
-- Capabilities and Entitlements are reported independently. The result is
-- advisory: protected operations re-evaluate everything themselves.
-- ==================================================================

create function public.get_my_professional_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    context_result jsonb;
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

    with current_membership as (
        select
            membership.id as membership_id,
            membership.organization_id,
            organization.display_name as organization_display_name
        from public.organization_memberships as membership
        join public.veterinary_organizations as organization
          on organization.id = membership.organization_id
        where membership.user_id = acting_user_id
          and membership.effective_end is null
    ),
    current_grant as (
        select
            current_membership.membership_id,
            responsibility_grant.responsibility,
            responsibility_grant.scope_type,
            responsibility_grant.clinic_id
        from current_membership
        join public.organization_responsibility_grants as responsibility_grant
          on responsibility_grant.membership_id = current_membership.membership_id
        where responsibility_grant.effective_end is null
    ),
    current_assignment as (
        select
            current_membership.membership_id,
            clinic_assignment.id as assignment_id,
            clinic_assignment.clinic_id
        from current_membership
        join public.veterinarian_clinic_assignments as clinic_assignment
          on clinic_assignment.supporting_membership_id = current_membership.membership_id
        join public.veterinarian_professional_profiles as profile
          on profile.id = clinic_assignment.professional_profile_id
        where profile.user_id = acting_user_id
          and public.veterinarian_clinic_assignment_is_current(clinic_assignment.id)
    ),
    organization_scoped_capability as (
        select
            current_membership.membership_id,
            catalog_entry.capability
        from current_membership
        cross join public.professional_capability_catalog() as catalog_entry
        where (
                catalog_entry.capability_context = 'ORGANIZATION'
                and public.user_has_organization_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )
              )
           or (
                catalog_entry.capability_context = 'CLINIC'
                and public.user_has_organization_scoped_clinic_capability(
                    acting_user_id, current_membership.organization_id, catalog_entry.capability
                )
              )
    ),
    candidate_clinic as (
        select current_grant.membership_id, current_grant.clinic_id
        from current_grant
        where current_grant.scope_type = 'CLINIC'
        union
        select current_assignment.membership_id, current_assignment.clinic_id
        from current_assignment
    ),
    clinic_scoped_capability as (
        select
            candidate_clinic.membership_id,
            candidate_clinic.clinic_id,
            catalog_entry.capability
        from candidate_clinic
        cross join public.professional_capability_catalog() as catalog_entry
        where catalog_entry.capability_context = 'CLINIC'
          and public.user_has_clinic_scoped_clinic_capability(
              acting_user_id, candidate_clinic.clinic_id, catalog_entry.capability
          )
          and not exists (
              select 1
              from organization_scoped_capability
              where organization_scoped_capability.membership_id = candidate_clinic.membership_id
                and organization_scoped_capability.capability = catalog_entry.capability
          )
    ),
    organization_entry as (
        select
            current_membership.organization_display_name,
            current_membership.organization_id,
            jsonb_build_object(
                'membership_id', current_membership.membership_id,
                'organization_id', current_membership.organization_id,
                'organization_display_name', current_membership.organization_display_name,
                'responsibilities', coalesce((
                    select jsonb_agg(
                        jsonb_build_object(
                            'responsibility', current_grant.responsibility,
                            'scope_type', current_grant.scope_type,
                            'clinic', case
                                when current_grant.clinic_id is null then null
                                else jsonb_build_object(
                                    'clinic_id', current_grant.clinic_id,
                                    'clinic_display_name', public_profile.display_name
                                )
                            end
                        )
                        order by current_grant.responsibility,
                                 current_grant.scope_type,
                                 current_grant.clinic_id
                    )
                    from current_grant
                    left join public.clinic_public_profiles as public_profile
                      on public_profile.clinic_id = current_grant.clinic_id
                    where current_grant.membership_id = current_membership.membership_id
                ), '[]'::jsonb),
                'capabilities', coalesce((
                    select jsonb_agg(capability_entry.entry order by capability_entry.sort_scope, capability_entry.sort_clinic, capability_entry.capability)
                    from (
                        select
                            jsonb_build_object(
                                'capability', organization_scoped_capability.capability,
                                'scope_type', 'ORGANIZATION',
                                'clinic', null
                            ) as entry,
                            0 as sort_scope,
                            null::uuid as sort_clinic,
                            organization_scoped_capability.capability
                        from organization_scoped_capability
                        where organization_scoped_capability.membership_id = current_membership.membership_id
                        union all
                        select
                            jsonb_build_object(
                                'capability', clinic_scoped_capability.capability,
                                'scope_type', 'CLINIC',
                                'clinic', jsonb_build_object(
                                    'clinic_id', clinic_scoped_capability.clinic_id,
                                    'clinic_display_name', public_profile.display_name
                                )
                            ),
                            1,
                            clinic_scoped_capability.clinic_id,
                            clinic_scoped_capability.capability
                        from clinic_scoped_capability
                        left join public.clinic_public_profiles as public_profile
                          on public_profile.clinic_id = clinic_scoped_capability.clinic_id
                        where clinic_scoped_capability.membership_id = current_membership.membership_id
                    ) as capability_entry
                ), '[]'::jsonb),
                'clinic_assignments', coalesce((
                    select jsonb_agg(
                        jsonb_build_object(
                            'veterinarian_clinic_assignment_id', current_assignment.assignment_id,
                            'clinic', jsonb_build_object(
                                'clinic_id', current_assignment.clinic_id,
                                'clinic_display_name', public_profile.display_name
                            )
                        )
                        order by current_assignment.clinic_id, current_assignment.assignment_id
                    )
                    from current_assignment
                    left join public.clinic_public_profiles as public_profile
                      on public_profile.clinic_id = current_assignment.clinic_id
                    where current_assignment.membership_id = current_membership.membership_id
                ), '[]'::jsonb),
                'entitlements', jsonb_build_object(
                    'APPOINTMENT_MANAGEMENT',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'APPOINTMENT_MANAGEMENT'
                    ),
                    'PROFESSIONAL_SCHEDULING',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'PROFESSIONAL_SCHEDULING'
                    ),
                    'CLINICAL_CARE',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'CLINICAL_CARE'
                    ),
                    'CLINICAL_DOCUMENTATION',
                    public.organization_has_professional_entitlement(
                        current_membership.organization_id, 'CLINICAL_DOCUMENTATION'
                    )
                )
            ) as entry
        from current_membership
    )
    select jsonb_build_object(
        'has_veterinarian_professional_profile', exists (
            select 1
            from public.veterinarian_professional_profiles as profile
            where profile.user_id = acting_user_id
        ),
        'organizations', coalesce((
            select jsonb_agg(
                organization_entry.entry
                order by organization_entry.organization_display_name,
                         organization_entry.organization_id
            )
            from organization_entry
        ), '[]'::jsonb)
    )
    into context_result;

    return context_result;
end;
$$;

revoke all privileges
on function public.get_my_professional_context()
from public, anon, authenticated;

grant execute
on function public.get_my_professional_context()
to authenticated;

commit;
