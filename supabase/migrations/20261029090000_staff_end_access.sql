-- Staff access lifecycle Phase 1, Slice C (SPEC-ORG-004 §10 BR-20–BR-28,
-- SPEC-ORG-005, SPEC-VET-005 BR-22; REQ-ORG-002/003/004/005/006).
--
-- end_organization_staff_membership(p_membership_id uuid) returns jsonb
--   authenticated only. The client supplies only the Membership id; the acting
--   User comes from auth.uid(). Order (BR-23):
--     1. authentication + coherent domain User (28000);
--     2. target resolution and ORGANIZATION_END_MEMBERSHIPS together, decided
--        under the target Organization's lock — a nonexistent Membership and
--        one the caller cannot manage (including an already ended one) fail
--        identically: 42501 "Organization Membership unavailable";
--     3. own Membership (23514, hint SELF_MEMBERSHIP) and a Membership holding
--        an active OWNER Grant (23514, hint OWNER_MEMBERSHIP), regardless of
--        how many Owners exist (BR-22);
--     4. lifecycle: an ended Membership returns ALREADY_ENDED with its original
--        effective end and changes nothing (BR-26);
--     5. every active Grant and the Membership end at one instant
--        greatest(statement_timestamp(), Membership start, latest active Grant
--        start) — the hardened writer instant of 20261026080000 — with the
--        acting User as ending User (BR-24).
--   Lock order Organization -> Membership -> active Grants (id order), the
--   order of add/replace/end Responsibility, so the operations serialize.
--   Nothing is deleted; Invitations, Communications, Veterinarian Clinic
--   Assignments, Appointments and every authored row are untouched. Authority
--   ends at commit because every evaluator reads live Membership/Grant state.
--
-- BR-27: the generic end_organization_membership (self-departure, non-sole
-- Owner removal, lifecycle before authorization) is withdrawn from public,
-- anon and authenticated; it remains for trusted compatibility only.
--
-- No table, column, constraint, capability, Communication type or backfill.
begin;

create function public.end_organization_staff_membership(p_membership_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    effective_instant timestamptz;
begin
    -- 1. Authentication and a coherent domain User.
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- 2. Target and capability together. Nothing is locked for a caller who
    -- cannot manage the target; the decision is repeated under the lock.
    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if target_organization_id is null
       or not public.user_has_organization_capability(
           acting_user_id, target_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'
       ) then
        raise exception 'Organization Membership unavailable'
            using errcode = '42501';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if not found or not public.user_has_organization_capability(
        acting_user_id, target_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'
    ) then
        raise exception 'Organization Membership unavailable'
            using errcode = '42501';
    end if;

    -- 3. Protected targets (BR-22).
    if membership_record.user_id = acting_user_id then
        raise exception 'Own Organization Membership cannot be ended through Staff'
            using errcode = '23514', hint = 'SELF_MEMBERSHIP';
    end if;

    perform 1
    from public.organization_responsibility_grants as grant_record
    where grant_record.membership_id = p_membership_id
      and grant_record.effective_end is null
    order by grant_record.id
    for update;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and grant_record.effective_end is null
          and grant_record.responsibility = 'OWNER'
    ) then
        raise exception 'An Owner Membership cannot be ended through Staff'
            using errcode = '23514', hint = 'OWNER_MEMBERSHIP';
    end if;

    -- 4. Lifecycle: an ended Membership is reported, never rewritten (BR-26).
    if membership_record.effective_end is not null then
        return jsonb_build_object(
            'membership_id', membership_record.id,
            'effective_end', membership_record.effective_end,
            'outcome', 'ALREADY_ENDED'
        );
    end if;

    -- 5. One instant ends every active Grant and the Membership; never before
    -- the Membership or any of those Grants started.
    effective_instant := greatest(
        statement_timestamp(),
        membership_record.effective_start,
        (
            select max(grant_record.effective_start)
            from public.organization_responsibility_grants as grant_record
            where grant_record.membership_id = p_membership_id
              and grant_record.effective_end is null
        )
    );

    update public.organization_responsibility_grants
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where membership_id = p_membership_id
      and effective_end is null;

    update public.organization_memberships
    set effective_end = effective_instant,
        ended_by_user_id = acting_user_id
    where id = p_membership_id;

    return jsonb_build_object(
        'membership_id', membership_record.id,
        'effective_end', effective_instant,
        'outcome', 'ENDED'
    );
end;
$$;

revoke all privileges
on function public.end_organization_staff_membership(uuid)
from public, anon, authenticated, service_role;
grant execute
on function public.end_organization_staff_membership(uuid)
to authenticated;

-- BR-27: no client path to the more permissive generic operation. Its
-- service_role grant (trusted compatibility) is left as it was.
revoke all privileges
on function public.end_organization_membership(uuid)
from public, anon, authenticated;

commit;
