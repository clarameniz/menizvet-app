-- Staff access lifecycle Phase 1, Slice A (SPEC-ORG-009 BR-1–BR-10,
-- SPEC-ID-006 BR-40; REQ-ORG-002/005/006/008, REQ-ID-006).
-- Additive read only: no tables, projections, backfill, or Staff writes.
begin;

create function public.get_organization_staff(p_organization_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
    acting_user_id uuid;
    staff_result jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required' using errcode = '28000';
    end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    -- One payload statement/snapshot and one temporal evaluation instant.
    -- The materialized authorization gate precedes every sensitive projection.
    with evaluation as materialized (
        select statement_timestamp() as instant
    ), authorized_organization as materialized (
        select organization.id, organization.display_name
        from public.veterinary_organizations as organization
        where organization.id = p_organization_id
          and (
              public.user_has_organization_capability(
                  acting_user_id, p_organization_id, 'ORGANIZATION_INVITE_MEMBERS'
              ) or public.user_has_organization_capability(
                  acting_user_id, p_organization_id, 'ORGANIZATION_END_MEMBERSHIPS'
              )
          )
    )
    select jsonb_build_object(
        'organization_id', organization.id,
        'organization_display_name', organization.display_name,
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                'membership_id', membership.id,
                'effective_start', membership.effective_start,
                'is_self', membership.user_id = acting_user_id,
                'display_name', profile.display_name,
                'invitation_recipient_email', origin.recipient_email_normalized,
                'responsibilities', coalesce((
                    select jsonb_agg(jsonb_build_object(
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
                     and clinic.organization_id = organization.id
                    left join public.clinic_public_profiles as clinic_profile
                      on clinic_profile.clinic_id = clinic.id
                    where grant_record.membership_id = membership.id
                      and grant_record.effective_start <= evaluation.instant
                      and grant_record.effective_end is null
                      and (grant_record.scope_type = 'ORGANIZATION' or clinic.id is not null)
                ), '[]'::jsonb)
            ) order by membership.effective_start, membership.id)
            from public.organization_memberships as membership
            left join public.user_profiles as profile on profile.user_id = membership.user_id
            left join public.organization_invitations as origin
              on origin.id = membership.originating_invitation_id
             and origin.organization_id = organization.id
            where membership.organization_id = organization.id
              and membership.effective_start <= evaluation.instant
              and membership.effective_end is null
        ), '[]'::jsonb),
        'pending_invitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'invitation_id', invitation.id,
                'recipient_email', invitation.recipient_email_normalized,
                'responsibilities', coalesce((
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
                     and clinic.organization_id = organization.id
                    left join public.clinic_public_profiles as clinic_profile
                      on clinic_profile.clinic_id = clinic.id
                    where intended.invitation_id = invitation.id
                      and (intended.scope_type = 'ORGANIZATION' or clinic.id is not null)
                ), '[]'::jsonb),
                'created_at', invitation.created_at,
                'expires_at', invitation.expires_at
            ) order by invitation.created_at, invitation.id)
            from public.organization_invitations as invitation
            where invitation.organization_id = organization.id
              and invitation.revoked_at is null
              and invitation.rejected_at is null
              and invitation.expires_at > evaluation.instant
              and not exists (
                  select 1 from public.organization_memberships as accepted
                  where accepted.originating_invitation_id = invitation.id
              )
        ), '[]'::jsonb)
    ) into staff_result
    from authorized_organization as organization cross join evaluation;

    if staff_result is null then
        raise exception 'Organization Staff unavailable' using errcode = '42501';
    end if;
    return staff_result;
end;
$$;

revoke all privileges on function public.get_organization_staff(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_organization_staff(uuid) to authenticated;
commit;
