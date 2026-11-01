-- Staff screen with tabs and pagination — Phase 1 (SPEC-ORG-009 §12).
--
-- Additive only: two keyset-paged reads for the Staff screen's Members and
-- pending Invitations tabs, one private authorization helper, and the two
-- partial indexes their orders need. get_organization_staff and every other
-- function keep their signature, body and grants; no table changes, no
-- backfill, no write.

-- ==================================================================
-- 1. Indexes for the two keyset orders.
-- ==================================================================

-- Members page (BR-13): current Memberships of one Organization in
-- (effective_start, id) order.
create index organization_memberships_active_organization_start_idx
on public.organization_memberships (organization_id, effective_start, id)
where effective_end is null;

-- Invitations page (BR-15): not-revoked, not-rejected Invitations of one
-- Organization in (created_at, id) order; expiry and acceptance are checked
-- per row (acceptance through the unique originating_invitation_id).
create index organization_invitations_open_organization_created_idx
on public.organization_invitations (organization_id, created_at, id)
where revoked_at is null and rejected_at is null;

-- ==================================================================
-- 2. Private authorization helper (BR-12 steps 1–2).
-- ==================================================================

-- The same gate as get_organization_staff (BR-2, BR-3): authentication first,
-- then one uniform 42501 for an unknown, null or inaccessible Organization.
-- Returns the acting domain User id. Executable by no client.
create function public.organization_staff_reader(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if p_organization_id is null
       or not exists (
           select 1
           from public.veterinary_organizations as organization
           where organization.id = p_organization_id
       )
       or not (
           public.user_has_organization_capability(
               acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'
           ) or public.user_has_organization_capability(
               acting_user_id, p_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'
           )
       ) then
        raise exception 'Organization Staff unavailable' using errcode = '42501';
    end if;

    return acting_user_id;
end;
$$;

revoke all privileges
on function public.organization_staff_reader(uuid)
from public, anon, authenticated, service_role;

-- ==================================================================
-- 3. Members page (SPEC-ORG-009 BR-13, BR-14).
-- ==================================================================

create function public.get_organization_staff_members(
    p_organization_id uuid,
    p_after_effective_start timestamptz default null,
    p_after_membership_id uuid default null,
    p_limit integer default 25
)
returns table (
    membership_id uuid,
    effective_start timestamptz,
    is_self boolean,
    display_name text,
    invitation_recipient_email text,
    display_name_is_shared boolean,
    responsibilities jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
begin
    acting_user_id := public.organization_staff_reader(p_organization_id);

    if p_limit is null or p_limit not between 1 and 50
       or num_nulls(p_after_effective_start, p_after_membership_id) not in (0, 2) then
        raise exception 'Staff page is invalid' using errcode = '22023';
    end if;

    -- One statement: one snapshot and one evaluation instant (BR-12). The
    -- page is cut on the key alone; only its members are projected.
    return query
    with evaluation as materialized (
        select statement_timestamp() as instant
    ),
    page as materialized (
        select membership.id as page_membership_id,
               membership.effective_start as page_effective_start,
               membership.user_id as page_user_id,
               membership.originating_invitation_id as page_origin_id,
               profile.display_name as page_display_name
        from public.organization_memberships as membership
        cross join evaluation
        left join public.user_profiles as profile
          on profile.user_id = membership.user_id
        where membership.organization_id = p_organization_id
          and membership.effective_end is null
          and membership.effective_start <= evaluation.instant
          and membership.effective_start >= coalesce(p_after_effective_start, '-infinity'::timestamptz)
          and (
              p_after_membership_id is null
              or membership.effective_start > p_after_effective_start
              or membership.id > p_after_membership_id
          )
        order by membership.effective_start, membership.id
        limit p_limit
    ),
    -- BR-14: names of this page shared by another current member, evaluated
    -- over every current member of the Organization.
    shared_names as materialized (
        select profile.display_name as shared_display_name
        from public.organization_memberships as membership
        cross join evaluation
        join public.user_profiles as profile
          on profile.user_id = membership.user_id
        where membership.organization_id = p_organization_id
          and membership.effective_end is null
          and membership.effective_start <= evaluation.instant
          and profile.display_name in (
              select page_row.page_display_name
              from page as page_row
              where page_row.page_display_name is not null
          )
        group by profile.display_name
        having count(*) > 1
    )
    select page.page_membership_id,
           page.page_effective_start,
           page.page_user_id = acting_user_id,
           page.page_display_name,
           origin.recipient_email_normalized,
           page.page_display_name is not null and exists (
               select 1
               from shared_names
               where shared_names.shared_display_name = page.page_display_name
           ),
           coalesce((
               select jsonb_agg(jsonb_build_object(
                   'responsibility_grant_id', grant_record.id,
                   'responsibility', grant_record.responsibility,
                   'scope_type', grant_record.scope_type,
                   'clinic', case when grant_record.scope_type = 'CLINIC' then
                       jsonb_build_object('clinic_id', clinic.id,
                           'clinic_display_name', clinic_profile.display_name)
                       else null end
               ) order by grant_record.responsibility, grant_record.scope_type,
                          grant_record.clinic_id)
               from public.organization_responsibility_grants as grant_record
               left join public.clinics as clinic
                 on clinic.id = grant_record.clinic_id
                and clinic.organization_id = p_organization_id
               left join public.clinic_public_profiles as clinic_profile
                 on clinic_profile.clinic_id = clinic.id
               where grant_record.membership_id = page.page_membership_id
                 and grant_record.effective_start <= evaluation.instant
                 and grant_record.effective_end is null
                 and (grant_record.scope_type = 'ORGANIZATION' or clinic.id is not null)
           ), '[]'::jsonb)
    from page
    cross join evaluation
    left join public.organization_invitations as origin
      on origin.id = page.page_origin_id
     and origin.organization_id = p_organization_id
    order by page.page_effective_start, page.page_membership_id;
end;
$$;

revoke all privileges
on function public.get_organization_staff_members(uuid, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;

grant execute
on function public.get_organization_staff_members(uuid, timestamptz, uuid, integer)
to authenticated;

-- ==================================================================
-- 4. Pending Invitations page (SPEC-ORG-009 BR-15).
-- ==================================================================

create function public.get_organization_pending_invitations(
    p_organization_id uuid,
    p_after_created_at timestamptz default null,
    p_after_invitation_id uuid default null,
    p_limit integer default 20
)
returns table (
    invitation_id uuid,
    recipient_email text,
    responsibilities jsonb,
    created_at timestamptz,
    expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform public.organization_staff_reader(p_organization_id);

    if p_limit is null or p_limit not between 1 and 50
       or num_nulls(p_after_created_at, p_after_invitation_id) not in (0, 2) then
        raise exception 'Staff page is invalid' using errcode = '22023';
    end if;

    return query
    with evaluation as materialized (
        select statement_timestamp() as instant
    ),
    page as materialized (
        select invitation.id as page_invitation_id,
               invitation.recipient_email_normalized as page_recipient_email,
               invitation.created_at as page_created_at,
               invitation.expires_at as page_expires_at
        from public.organization_invitations as invitation
        cross join evaluation
        where invitation.organization_id = p_organization_id
          and invitation.revoked_at is null
          and invitation.rejected_at is null
          and invitation.expires_at > evaluation.instant
          and not exists (
              select 1
              from public.organization_memberships as accepted
              where accepted.originating_invitation_id = invitation.id
          )
          and invitation.created_at >= coalesce(p_after_created_at, '-infinity'::timestamptz)
          and (
              p_after_invitation_id is null
              or invitation.created_at > p_after_created_at
              or invitation.id > p_after_invitation_id
          )
        order by invitation.created_at, invitation.id
        limit p_limit
    )
    select page.page_invitation_id,
           page.page_recipient_email,
           coalesce((
               select jsonb_agg(jsonb_build_object(
                   'responsibility', intended.responsibility,
                   'scope_type', intended.scope_type,
                   'clinic', case when intended.scope_type = 'CLINIC' then
                       jsonb_build_object('clinic_id', clinic.id,
                           'clinic_display_name', clinic_profile.display_name)
                       else null end
               ) order by intended.responsibility, intended.scope_type, intended.clinic_id)
               from public.organization_invitation_responsibilities as intended
               left join public.clinics as clinic
                 on clinic.id = intended.clinic_id
                and clinic.organization_id = p_organization_id
               left join public.clinic_public_profiles as clinic_profile
                 on clinic_profile.clinic_id = clinic.id
               where intended.invitation_id = page.page_invitation_id
                 and (intended.scope_type = 'ORGANIZATION' or clinic.id is not null)
           ), '[]'::jsonb),
           page.page_created_at,
           page.page_expires_at
    from page
    order by page.page_created_at, page.page_invitation_id;
end;
$$;

revoke all privileges
on function public.get_organization_pending_invitations(uuid, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;

grant execute
on function public.get_organization_pending_invitations(uuid, timestamptz, uuid, integer)
to authenticated;
