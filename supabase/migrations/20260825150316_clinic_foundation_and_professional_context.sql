begin;

create table public.clinics (
    id uuid not null default gen_random_uuid(),
    organization_id uuid not null,
    created_at timestamptz not null default transaction_timestamp(),
    is_published boolean not null default false,
    constraint clinics_pkey primary key (id),
    constraint clinics_organization_id_fkey
        foreign key (organization_id)
        references public.veterinary_organizations (id)
        on update no action
        on delete restrict
);

alter table public.organization_invitation_responsibilities
add column clinic_id uuid;

alter table public.organization_responsibility_grants
add column clinic_id uuid;

alter table public.organization_invitation_responsibilities
add constraint organization_invitation_responsibilities_clinic_id_fkey
foreign key (clinic_id)
references public.clinics (id)
on update no action
on delete restrict;

alter table public.organization_responsibility_grants
add constraint organization_responsibility_grants_clinic_id_fkey
foreign key (clinic_id)
references public.clinics (id)
on update no action
on delete restrict;

create unique index organization_invitation_responsibilities_organization_key
on public.organization_invitation_responsibilities (
    invitation_id,
    responsibility
)
where scope_type = 'ORGANIZATION';

create unique index organization_invitation_responsibilities_clinic_key
on public.organization_invitation_responsibilities (
    invitation_id,
    responsibility,
    clinic_id
)
where scope_type = 'CLINIC';

create index organization_invitation_responsibilities_clinic_idx
on public.organization_invitation_responsibilities (
    clinic_id,
    invitation_id
)
where clinic_id is not null;

create unique index organization_responsibility_grants_active_organization_key
on public.organization_responsibility_grants (
    membership_id,
    responsibility
)
where effective_end is null and scope_type = 'ORGANIZATION';

create unique index organization_responsibility_grants_active_clinic_key
on public.organization_responsibility_grants (
    membership_id,
    responsibility,
    clinic_id
)
where effective_end is null and scope_type = 'CLINIC';

create index organization_responsibility_grants_clinic_history_idx
on public.organization_responsibility_grants (
    clinic_id,
    membership_id,
    effective_start
)
where clinic_id is not null;

alter table public.organization_invitation_responsibilities
drop constraint organization_invitation_responsibilities_semantic_key;

alter table public.organization_invitation_responsibilities
drop constraint organization_invitation_responsibilities_scope_type_check;

alter table public.organization_responsibility_grants
drop constraint organization_responsibility_grants_scope_type_check;

drop index public.organization_responsibility_grants_active_key;

alter table public.organization_invitation_responsibilities
add constraint organization_invitation_responsibilities_scope_check
check (
    (
        scope_type = 'ORGANIZATION'
        and clinic_id is null
        and responsibility in (
            'ADMINISTRATOR',
            'RECEPTIONIST',
            'VETERINARIAN'
        )
    )
    or
    (
        scope_type = 'CLINIC'
        and clinic_id is not null
        and responsibility in (
            'ADMINISTRATOR',
            'RECEPTIONIST'
        )
    )
);

alter table public.organization_responsibility_grants
add constraint organization_responsibility_grants_scope_check
check (
    (
        scope_type = 'ORGANIZATION'
        and clinic_id is null
        and responsibility in (
            'OWNER',
            'ADMINISTRATOR',
            'RECEPTIONIST',
            'VETERINARIAN'
        )
    )
    or
    (
        scope_type = 'CLINIC'
        and clinic_id is not null
        and responsibility in (
            'ADMINISTRATOR',
            'RECEPTIONIST'
        )
    )
);

create table public.clinic_locations (
    clinic_id uuid not null,
    address_text text not null,
    latitude double precision not null,
    longitude double precision not null,
    constraint clinic_locations_pkey primary key (clinic_id),
    constraint clinic_locations_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_locations_address_text_check
        check (
            address_text = btrim(address_text, E' \t\n\r\f\013')
            and address_text <> ''
        ),
    constraint clinic_locations_latitude_check
        check (latitude between -90.0 and 90.0),
    constraint clinic_locations_longitude_check
        check (longitude between -180.0 and 180.0)
);

create table public.clinic_public_profiles (
    clinic_id uuid not null,
    display_name text,
    description text,
    public_phone text,
    public_email text,
    website text,
    constraint clinic_public_profiles_pkey primary key (clinic_id),
    constraint clinic_public_profiles_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint clinic_public_profiles_nonempty_check
        check (
            display_name is not null
            or description is not null
            or public_phone is not null
            or public_email is not null
            or website is not null
        ),
    constraint clinic_public_profiles_display_name_check
        check (
            display_name is null
            or (
                display_name = btrim(display_name, E' \t\n\r\f\013')
                and display_name <> ''
            )
        ),
    constraint clinic_public_profiles_description_check
        check (
            description is null
            or (
                description = btrim(description, E' \t\n\r\f\013')
                and description <> ''
            )
        ),
    constraint clinic_public_profiles_public_phone_check
        check (
            public_phone is null
            or (
                public_phone = btrim(public_phone, E' \t\n\r\f\013')
                and public_phone <> ''
            )
        ),
    constraint clinic_public_profiles_public_email_check
        check (
            public_email is null
            or (
                public_email = btrim(public_email, E' \t\n\r\f\013')
                and public_email <> ''
            )
        ),
    constraint clinic_public_profiles_website_check
        check (
            website is null
            or (
                website = btrim(website, E' \t\n\r\f\013')
                and website <> ''
            )
        )
);

create table public.veterinarian_clinic_assignments (
    id uuid not null default gen_random_uuid(),
    professional_profile_id uuid not null,
    supporting_membership_id uuid not null,
    clinic_id uuid not null,
    effective_start timestamptz not null,
    effective_end timestamptz,
    constraint veterinarian_clinic_assignments_pkey primary key (id),
    constraint veterinarian_clinic_assignments_profile_id_fkey
        foreign key (professional_profile_id)
        references public.veterinarian_professional_profiles (id)
        on update no action
        on delete restrict,
    constraint veterinarian_clinic_assignments_membership_id_fkey
        foreign key (supporting_membership_id)
        references public.organization_memberships (id)
        on update no action
        on delete restrict,
    constraint veterinarian_clinic_assignments_clinic_id_fkey
        foreign key (clinic_id)
        references public.clinics (id)
        on update no action
        on delete restrict,
    constraint veterinarian_clinic_assignments_effective_period_check
        check (
            effective_end is null
            or effective_end >= effective_start
        )
);

create index clinics_organization_idx
on public.clinics (organization_id, id);

create index clinics_published_idx
on public.clinics (id)
where is_published;

create unique index veterinarian_clinic_assignments_open_membership_key
on public.veterinarian_clinic_assignments (
    professional_profile_id,
    clinic_id,
    supporting_membership_id
)
where effective_end is null;

create index veterinarian_clinic_assignments_profile_history_idx
on public.veterinarian_clinic_assignments (
    professional_profile_id,
    effective_start
);

create index veterinarian_clinic_assignments_clinic_history_idx
on public.veterinarian_clinic_assignments (
    clinic_id,
    effective_start
);

create index veterinarian_clinic_assignments_active_clinic_idx
on public.veterinarian_clinic_assignments (
    clinic_id,
    professional_profile_id
)
where effective_end is null;

create index veterinarian_clinic_assignments_membership_history_idx
on public.veterinarian_clinic_assignments (
    supporting_membership_id,
    effective_start
);

create function public.enforce_clinic_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Clinics cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.organization_id is distinct from new.organization_id
       or old.created_at is distinct from new.created_at then
        raise exception 'Clinic identity, Organization, and creation time are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_clinic_immutability()
from public, anon, authenticated;

create trigger clinics_preserve_identity
before update or delete on public.clinics
for each row
execute function public.enforce_clinic_immutability();

create function public.lock_clinic_configuration_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_clinic_id uuid;
begin
    if tg_op = 'UPDATE'
       and old.clinic_id is distinct from new.clinic_id then
        raise exception 'Clinic configuration cannot be reassigned to another Clinic'
            using errcode = '23514';
    end if;

    if tg_op = 'DELETE' then
        target_clinic_id := old.clinic_id;
    else
        target_clinic_id := new.clinic_id;
    end if;

    perform 1
    from public.clinics as clinic
    where clinic.id = target_clinic_id
    for update;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.lock_clinic_configuration_context()
from public, anon, authenticated;

create trigger clinic_locations_lock_context
before insert or update or delete on public.clinic_locations
for each row
execute function public.lock_clinic_configuration_context();

create trigger clinic_public_profiles_lock_context
before insert or update or delete on public.clinic_public_profiles
for each row
execute function public.lock_clinic_configuration_context();

create function public.assert_clinic_publication_integrity(
    p_clinic_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    clinic_is_published boolean;
begin
    select clinic.is_published
    into clinic_is_published
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found or not clinic_is_published then
        return;
    end if;

    if not exists (
        select 1
        from public.clinic_locations as location
        where location.clinic_id = p_clinic_id
    ) then
        raise exception 'Published Clinic % requires a current Location',
            p_clinic_id
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.clinic_public_profiles as profile
        where profile.clinic_id = p_clinic_id
          and profile.display_name is not null
          and profile.display_name = btrim(
              profile.display_name,
              E' \t\n\r\f\013'
          )
          and profile.display_name <> ''
    ) then
        raise exception 'Published Clinic % requires a valid public display name',
            p_clinic_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_clinic_publication_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_clinic_publication_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'clinics' then
        perform public.assert_clinic_publication_integrity(new.id);
    elsif tg_op = 'INSERT' then
        perform public.assert_clinic_publication_integrity(new.clinic_id);
    elsif tg_op = 'DELETE' then
        perform public.assert_clinic_publication_integrity(old.clinic_id);
    elsif tg_op = 'UPDATE' then
        perform public.assert_clinic_publication_integrity(old.clinic_id);
        if old.clinic_id is distinct from new.clinic_id then
            perform public.assert_clinic_publication_integrity(new.clinic_id);
        end if;
    else
        raise exception 'Unexpected Clinic publication-integrity trigger invocation'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_clinic_publication_integrity()
from public, anon, authenticated;

create constraint trigger clinics_enforce_publication_integrity
after insert or update on public.clinics
deferrable initially deferred
for each row
execute function public.enforce_clinic_publication_integrity();

create function public.assert_invitation_responsibility_clinic_context(
    p_invitation_responsibility_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        join public.organization_invitations as invitation
          on invitation.id = intended.invitation_id
        join public.clinics as clinic
          on clinic.id = intended.clinic_id
        where intended.id = p_invitation_responsibility_id
          and intended.scope_type = 'CLINIC'
          and clinic.organization_id <> invitation.organization_id
    ) then
        raise exception 'Clinic-scoped Invitation Responsibility must target a Clinic in the invited Organization'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_invitation_responsibility_clinic_context(uuid)
from public, anon, authenticated;

create function public.enforce_invitation_responsibility_clinic_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op in ('INSERT', 'UPDATE') then
        perform public.assert_invitation_responsibility_clinic_context(new.id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_invitation_responsibility_clinic_context()
from public, anon, authenticated;

create constraint trigger organization_invitation_responsibilities_enforce_clinic_context
after insert or update on public.organization_invitation_responsibilities
deferrable initially deferred
for each row
execute function public.enforce_invitation_responsibility_clinic_context();

create function public.assert_responsibility_grant_clinic_context(
    p_grant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        join public.organization_memberships as membership
          on membership.id = grant_record.membership_id
        join public.clinics as clinic
          on clinic.id = grant_record.clinic_id
        where grant_record.id = p_grant_id
          and grant_record.scope_type = 'CLINIC'
          and clinic.organization_id <> membership.organization_id
    ) then
        raise exception 'Clinic-scoped Responsibility Grant must target a Clinic in the Membership Organization'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_responsibility_grant_clinic_context(uuid)
from public, anon, authenticated;

create function public.enforce_responsibility_grant_clinic_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op in ('INSERT', 'UPDATE') then
        perform public.assert_responsibility_grant_clinic_context(new.id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_responsibility_grant_clinic_context()
from public, anon, authenticated;

create constraint trigger organization_responsibility_grants_enforce_clinic_context
after insert or update on public.organization_responsibility_grants
deferrable initially deferred
for each row
execute function public.enforce_responsibility_grant_clinic_context();

create or replace function public.enforce_organization_grant_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Organization Responsibility Grants cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.membership_id is distinct from new.membership_id
       or old.responsibility is distinct from new.responsibility
       or old.scope_type is distinct from new.scope_type
       or old.clinic_id is distinct from new.clinic_id
       or old.effective_start is distinct from new.effective_start
       or old.granted_by_user_id is distinct from new.granted_by_user_id
       or old.originating_invitation_responsibility_id is distinct from
           new.originating_invitation_responsibility_id then
        raise exception 'Organization Responsibility Grant historical facts are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null
       and (
           old.effective_end is distinct from new.effective_end
           or old.ended_by_user_id is distinct from new.ended_by_user_id
       ) then
        raise exception 'Ended Organization Responsibility Grant facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create function public.enforce_veterinarian_clinic_assignment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Veterinarian Clinic Assignments cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.professional_profile_id is distinct from new.professional_profile_id
       or old.supporting_membership_id is distinct from new.supporting_membership_id
       or old.clinic_id is distinct from new.clinic_id
       or old.effective_start is distinct from new.effective_start then
        raise exception 'Veterinarian Clinic Assignment identity and historical context are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null
       and old.effective_end is distinct from new.effective_end then
        raise exception 'Ended Veterinarian Clinic Assignment facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_clinic_assignment_immutability()
from public, anon, authenticated;

create trigger veterinarian_clinic_assignments_preserve_history
before update or delete on public.veterinarian_clinic_assignments
for each row
execute function public.enforce_veterinarian_clinic_assignment_immutability();

create function public.enforce_veterinarian_clinic_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    membership_user_id uuid;
    membership_organization_id uuid;
    membership_effective_start timestamptz;
    membership_effective_end timestamptz;
    profile_user_id uuid;
    clinic_organization_id uuid;
begin
    if new.effective_end is not null then
        raise exception 'A newly established Veterinarian Clinic Assignment must be active'
            using errcode = '23514';
    end if;

    select membership.user_id, membership.organization_id
    into membership_user_id, membership_organization_id
    from public.organization_memberships as membership
    where membership.id = new.supporting_membership_id;

    if not found then
        raise exception 'Supporting Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = membership_organization_id
    for update;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = new.clinic_id
    for update;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    select membership.user_id,
           membership.organization_id,
           membership.effective_start,
           membership.effective_end
    into membership_user_id,
         membership_organization_id,
         membership_effective_start,
         membership_effective_end
    from public.organization_memberships as membership
    where membership.id = new.supporting_membership_id
    for update;

    if not found then
        raise exception 'Supporting Organization Membership does not exist'
            using errcode = '23503';
    end if;

    select profile.user_id
    into profile_user_id
    from public.veterinarian_professional_profiles as profile
    where profile.id = new.professional_profile_id;

    if not found then
        raise exception 'Veterinarian Professional Profile does not exist'
            using errcode = '23503';
    end if;

    if membership_effective_end is not null then
        raise exception 'Veterinarian Clinic Assignment requires an active Organization Membership'
            using errcode = '23514';
    end if;

    if new.effective_start < membership_effective_start then
        raise exception 'Veterinarian Clinic Assignment cannot start before its supporting Membership'
            using errcode = '23514';
    end if;

    if profile_user_id <> membership_user_id then
        raise exception 'Veterinarian Professional Profile and supporting Membership must belong to the same User'
            using errcode = '23514';
    end if;

    if clinic_organization_id <> membership_organization_id then
        raise exception 'Clinic and supporting Membership must belong to the same Organization'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_clinic_assignment_context()
from public, anon, authenticated;

create trigger veterinarian_clinic_assignments_enforce_context
before insert on public.veterinarian_clinic_assignments
for each row
execute function public.enforce_veterinarian_clinic_assignment_context();

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
        coalesce(
            p_capability in (
                'ORGANIZATION_INVITE_MEMBERS',
                'ORGANIZATION_REVOKE_INVITATIONS',
                'ORGANIZATION_END_MEMBERSHIPS',
                'ORGANIZATION_GRANT_RESPONSIBILITIES',
                'ORGANIZATION_CREATE_CLINICS'
            ),
            false
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

create function public.user_has_clinic_capability(
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
        coalesce(
            p_capability in (
                'CLINIC_MANAGE_LOCATION',
                'CLINIC_MANAGE_PUBLIC_PROFILE',
                'CLINIC_MANAGE_PUBLICATION',
                'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'
            ),
            false
        )
        and exists (
            select 1
            from public.clinics as clinic
            join public.organization_memberships as membership
              on membership.organization_id = clinic.organization_id
            join public.organization_responsibility_grants as grant_record
              on grant_record.membership_id = membership.id
            where clinic.id = p_clinic_id
              and membership.user_id = p_user_id
              and membership.effective_end is null
              and grant_record.effective_end is null
              and (
                  (
                      grant_record.scope_type = 'ORGANIZATION'
                      and grant_record.clinic_id is null
                      and grant_record.responsibility in (
                          'OWNER',
                          'ADMINISTRATOR'
                      )
                  )
                  or
                  (
                      grant_record.scope_type = 'CLINIC'
                      and grant_record.clinic_id = p_clinic_id
                      and grant_record.responsibility = 'ADMINISTRATOR'
                  )
              )
        )
$$;

revoke all privileges
on function public.user_has_clinic_capability(uuid, uuid, text)
from public, anon, authenticated;

create constraint trigger clinic_locations_enforce_publication_integrity
after insert or update or delete on public.clinic_locations
deferrable initially deferred
for each row
execute function public.enforce_clinic_publication_integrity();

create constraint trigger clinic_public_profiles_enforce_publication_integrity
after insert or update or delete on public.clinic_public_profiles
deferrable initially deferred
for each row
execute function public.enforce_clinic_publication_integrity();

create or replace function public.assert_organization_invitation_acceptance_integrity(
    p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_record public.organization_invitations%rowtype;
    membership_record public.organization_memberships%rowtype;
begin
    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        return;
    end if;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.originating_invitation_id = p_invitation_id;

    if not found then
        if exists (
            select 1
            from public.organization_responsibility_grants as grant_record
            join public.organization_invitation_responsibilities as intended
              on intended.id = grant_record.originating_invitation_responsibility_id
            where intended.invitation_id = p_invitation_id
        ) then
            raise exception 'Invitation-derived Grant requires the resulting Membership for Invitation %',
                p_invitation_id
                using errcode = '23514';
        end if;

        return;
    end if;

    if invitation_record.revoked_at is not null
       or invitation_record.rejected_at is not null then
        raise exception 'Accepted Organization Invitation % cannot also be revoked or rejected',
            p_invitation_id
            using errcode = '23514';
    end if;

    if invitation_record.acceptance_secret_digest is not null then
        raise exception 'Accepted Organization Invitation % must not retain its acceptance credential',
            p_invitation_id
            using errcode = '23514';
    end if;

    if membership_record.organization_id <> invitation_record.organization_id then
        raise exception 'Invitation-derived Membership must belong to the invited Organization'
            using errcode = '23514';
    end if;

    if invitation_record.recipient_user_id is not null
       and membership_record.user_id <> invitation_record.recipient_user_id then
        raise exception 'Invitation-derived Membership User must match the bound recipient User'
            using errcode = '23514';
    end if;

    if membership_record.effective_start < invitation_record.created_at
       or membership_record.effective_start >= invitation_record.expires_at then
        raise exception 'Organization Invitation acceptance must occur during its validity period'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
          and not exists (
              select 1
              from public.organization_responsibility_grants as grant_record
              where grant_record.originating_invitation_responsibility_id = intended.id
                and grant_record.membership_id = membership_record.id
                and grant_record.responsibility = intended.responsibility
                and grant_record.scope_type = intended.scope_type
                and grant_record.clinic_id is not distinct from intended.clinic_id
                and grant_record.effective_start = membership_record.effective_start
                and grant_record.granted_by_user_id = invitation_record.inviting_user_id
          )
    ) then
        raise exception 'Accepted Organization Invitation % requires every intended Grant',
            p_invitation_id
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        join public.organization_invitation_responsibilities as intended
          on intended.id = grant_record.originating_invitation_responsibility_id
        where intended.invitation_id = p_invitation_id
          and (
              grant_record.membership_id <> membership_record.id
              or grant_record.responsibility <> intended.responsibility
              or grant_record.scope_type <> intended.scope_type
              or grant_record.clinic_id is distinct from intended.clinic_id
              or grant_record.effective_start <> membership_record.effective_start
              or grant_record.granted_by_user_id <> invitation_record.inviting_user_id
          )
    ) then
        raise exception 'Invitation-derived Grants must preserve their exact Invitation origin'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        join public.organization_invitation_responsibilities as intended
          on intended.id = grant_record.originating_invitation_responsibility_id
        where grant_record.membership_id = membership_record.id
          and intended.invitation_id <> p_invitation_id
    ) then
        raise exception 'Invitation-derived Membership cannot contain Grants from another Invitation'
            using errcode = '23514';
    end if;
end;
$$;

create function public.create_scoped_organization_invitation(
    p_acting_user_id uuid,
    p_organization_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_intended_responsibilities jsonb,
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    normalized_recipient_email text;
    operation_timestamp timestamptz;
    created_invitation_id uuid;
begin
    if p_acting_user_id is null then
        raise exception 'A trusted acting domain User is required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = p_acting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The acting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    normalized_recipient_email := btrim(
        p_recipient_email,
        E' \t\n\r\f\013'
    );

    if normalized_recipient_email is null
       or normalized_recipient_email = '' then
        raise exception 'Organization Invitation recipient email must not be blank'
            using errcode = '22023';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Organization Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    if jsonb_typeof(p_intended_responsibilities) is distinct from 'array' then
        raise exception 'Intended Organization responsibilities must be a JSON array'
            using errcode = '22023';
    end if;

    if jsonb_array_length(p_intended_responsibilities) = 0 then
        raise exception 'Intended Organization responsibilities must not be empty'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        where jsonb_typeof(requested.item) is distinct from 'object'
    ) then
        raise exception 'Every intended Organization responsibility must be a JSON object'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        cross join lateral jsonb_object_keys(requested.item) as member(member_name)
        where member.member_name not in (
            'responsibility',
            'scope_type',
            'clinic_id'
        )
    ) then
        raise exception 'Intended Organization responsibility contains an unsupported member'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        where not (requested.item ? 'responsibility')
           or not (requested.item ? 'scope_type')
           or jsonb_typeof(requested.item -> 'responsibility') is distinct from 'string'
           or jsonb_typeof(requested.item -> 'scope_type') is distinct from 'string'
    ) then
        raise exception 'Every intended responsibility requires string responsibility and scope_type members'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        where requested.item ->> 'responsibility' not in (
                  'ADMINISTRATOR',
                  'RECEPTIONIST',
                  'VETERINARIAN'
              )
           or requested.item ->> 'scope_type' not in (
                  'ORGANIZATION',
                  'CLINIC'
              )
           or (
               requested.item ->> 'scope_type' = 'ORGANIZATION'
               and requested.item ? 'clinic_id'
               and jsonb_typeof(requested.item -> 'clinic_id') is distinct from 'null'
           )
           or (
               requested.item ->> 'scope_type' = 'CLINIC'
               and (
                   not (requested.item ? 'clinic_id')
                   or jsonb_typeof(requested.item -> 'clinic_id') is distinct from 'string'
                   or btrim(
                       requested.item ->> 'clinic_id',
                       E' \t\n\r\f\013'
                   ) = ''
               )
           )
           or (
               requested.item ->> 'scope_type' = 'CLINIC'
               and requested.item ->> 'responsibility' not in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST'
               )
           )
    ) then
        raise exception 'Invitation contains an invalid responsibility scope'
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        group by
            requested.item ->> 'responsibility',
            requested.item ->> 'scope_type',
            case
                when requested.item ->> 'scope_type' = 'CLINIC'
                    then (requested.item ->> 'clinic_id')::uuid
                else null
            end
        having count(*) > 1
    ) then
        raise exception 'Invitation must not contain duplicate responsibility scopes'
            using errcode = '22023';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    if exists (
        select 1
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        left join public.clinics as clinic
          on clinic.id = (requested.item ->> 'clinic_id')::uuid
        where requested.item ->> 'scope_type' = 'CLINIC'
          and (
              clinic.id is null
              or clinic.organization_id <> p_organization_id
          )
    ) then
        raise exception 'Clinic-scoped Invitation Responsibility must target a Clinic in the invited Organization'
            using errcode = '23514';
    end if;

    perform 1
    from public.clinics as clinic
    join (
        select distinct (requested.item ->> 'clinic_id')::uuid as clinic_id
        from jsonb_array_elements(p_intended_responsibilities) as requested(item)
        where requested.item ->> 'scope_type' = 'CLINIC'
    ) as requested_clinic
      on requested_clinic.clinic_id = clinic.id
    order by clinic.id
    for update of clinic;

    operation_timestamp := clock_timestamp();

    if p_expires_at is null or p_expires_at <= operation_timestamp then
        raise exception 'Organization Invitation expiration must follow creation'
            using errcode = '22023';
    end if;

    if not public.user_has_organization_capability(
        p_acting_user_id,
        p_organization_id,
        'ORGANIZATION_INVITE_MEMBERS'
    ) then
        raise exception 'Organization Invitation capability is required'
            using errcode = '42501';
    end if;

    if p_recipient_user_id is not null
       and exists (
           select 1
           from public.organization_memberships as membership
           where membership.organization_id = p_organization_id
             and membership.user_id = p_recipient_user_id
             and membership.effective_end is null
       ) then
        raise exception 'Recipient already has an active Organization Membership'
            using errcode = '23505';
    end if;

    if exists (
        select 1
        from public.organization_invitations as invitation
        where invitation.organization_id = p_organization_id
          and invitation.revoked_at is null
          and invitation.rejected_at is null
          and invitation.expires_at > operation_timestamp
          and not exists (
              select 1
              from public.organization_memberships as resulting_membership
              where resulting_membership.originating_invitation_id = invitation.id
          )
          and (
              (
                  p_recipient_user_id is not null
                  and invitation.recipient_user_id = p_recipient_user_id
              )
              or invitation.recipient_email_normalized = lower(
                  btrim(normalized_recipient_email, E' \t\n\r\f\013')
              )
          )
    ) then
        raise exception 'An equivalent pending Organization Invitation already exists'
            using errcode = '23505';
    end if;

    insert into public.organization_invitations (
        organization_id,
        inviting_user_id,
        recipient_user_id,
        recipient_email,
        created_at,
        expires_at,
        acceptance_secret_digest
    )
    values (
        p_organization_id,
        p_acting_user_id,
        p_recipient_user_id,
        normalized_recipient_email,
        operation_timestamp,
        p_expires_at,
        p_acceptance_secret_digest
    )
    returning id into created_invitation_id;

    insert into public.organization_invitation_responsibilities (
        invitation_id,
        responsibility,
        scope_type,
        clinic_id
    )
    select
        created_invitation_id,
        requested.item ->> 'responsibility',
        requested.item ->> 'scope_type',
        case
            when requested.item ->> 'scope_type' = 'CLINIC'
                then (requested.item ->> 'clinic_id')::uuid
            else null
        end
    from jsonb_array_elements(p_intended_responsibilities) as requested(item);

    return created_invitation_id;
end;
$$;

revoke all privileges
on function public.create_scoped_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    jsonb,
    timestamptz,
    bytea
)
from public, anon, authenticated;

grant execute
on function public.create_scoped_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    jsonb,
    timestamptz,
    bytea
)
to service_role;

create or replace function public.create_organization_invitation(
    p_acting_user_id uuid,
    p_organization_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_responsibilities text[],
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    intended_responsibilities jsonb;
begin
    select jsonb_agg(
        jsonb_build_object(
            'responsibility', requested.responsibility,
            'scope_type', 'ORGANIZATION',
            'clinic_id', null
        )
    )
    into intended_responsibilities
    from unnest(p_responsibilities) as requested(responsibility);

    return public.create_scoped_organization_invitation(
        p_acting_user_id,
        p_organization_id,
        p_recipient_user_id,
        p_recipient_email,
        intended_responsibilities,
        p_expires_at,
        p_acceptance_secret_digest
    );
end;
$$;

revoke all privileges
on function public.create_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    text[],
    timestamptz,
    bytea
)
from public, anon, authenticated;

grant execute
on function public.create_organization_invitation(
    uuid,
    uuid,
    uuid,
    text,
    text[],
    timestamptz,
    bytea
)
to service_role;

create or replace function public.accept_organization_invitation(
    p_accepting_user_id uuid,
    p_invitation_id uuid,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_organization_id uuid;
    invitation_record public.organization_invitations%rowtype;
    operation_timestamp timestamptz;
    created_membership_id uuid;
begin
    if p_accepting_user_id is null then
        raise exception 'A trusted accepting domain User is required'
            using errcode = '28000';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Organization Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.user_authentication_identities as identity_link
        join auth.users as auth_user
          on auth_user.id = identity_link.provider_subject
        where identity_link.user_id = p_accepting_user_id
          and identity_link.provider = 'supabase_auth'
          and identity_link.issuer = 'primary'
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'The accepting User must satisfy account verification requirements'
            using errcode = '42501';
    end if;

    select invitation.organization_id
    into invitation_organization_id
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = invitation_organization_id
    for update;

    select invitation.*
    into invitation_record
    from public.organization_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        raise exception 'Organization Invitation does not exist'
            using errcode = '23503';
    end if;

    operation_timestamp := clock_timestamp();

    if operation_timestamp >= invitation_record.expires_at then
        raise exception 'Organization Invitation has expired'
            using errcode = '23514';
    end if;

    if invitation_record.revoked_at is not null
       or invitation_record.rejected_at is not null then
        raise exception 'Organization Invitation is no longer pending'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.originating_invitation_id = p_invitation_id
    ) then
        raise exception 'Organization Invitation has already been accepted'
            using errcode = '23505';
    end if;

    if invitation_record.acceptance_secret_digest is null
       or invitation_record.acceptance_secret_digest is distinct from
           p_acceptance_secret_digest then
        raise exception 'Organization Invitation recipient proof is invalid'
            using errcode = '42501';
    end if;

    if invitation_record.recipient_user_id is not null
       and invitation_record.recipient_user_id <> p_accepting_user_id then
        raise exception 'Organization Invitation is bound to another User'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_memberships as membership
        where membership.organization_id = invitation_record.organization_id
          and membership.user_id = p_accepting_user_id
          and membership.effective_end is null
    ) then
        raise exception 'User already has an active Organization Membership'
            using errcode = '23505';
    end if;

    if not exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        where intended.invitation_id = p_invitation_id
    ) or exists (
        select 1
        from public.organization_invitation_responsibilities as intended
        left join public.clinics as clinic
          on clinic.id = intended.clinic_id
        where intended.invitation_id = p_invitation_id
          and (
              intended.responsibility not in (
                  'ADMINISTRATOR',
                  'RECEPTIONIST',
                  'VETERINARIAN'
              )
              or (
                  intended.scope_type = 'ORGANIZATION'
                  and intended.clinic_id is not null
              )
              or (
                  intended.scope_type = 'CLINIC'
                  and (
                      intended.clinic_id is null
                      or intended.responsibility not in (
                          'ADMINISTRATOR',
                          'RECEPTIONIST'
                      )
                      or clinic.organization_id is distinct from
                          invitation_record.organization_id
                  )
              )
              or intended.scope_type not in ('ORGANIZATION', 'CLINIC')
          )
    ) then
        raise exception 'Organization Invitation contains invalid responsibilities'
            using errcode = '23514';
    end if;

    perform 1
    from public.clinics as clinic
    join public.organization_invitation_responsibilities as intended
      on intended.clinic_id = clinic.id
    where intended.invitation_id = p_invitation_id
    order by clinic.id
    for update of clinic;

    insert into public.organization_memberships (
        organization_id,
        user_id,
        effective_start,
        originating_invitation_id
    )
    values (
        invitation_record.organization_id,
        p_accepting_user_id,
        operation_timestamp,
        p_invitation_id
    )
    returning id into created_membership_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id,
        originating_invitation_responsibility_id
    )
    select
        created_membership_id,
        intended.responsibility,
        intended.scope_type,
        intended.clinic_id,
        operation_timestamp,
        invitation_record.inviting_user_id,
        intended.id
    from public.organization_invitation_responsibilities as intended
    where intended.invitation_id = p_invitation_id;

    update public.organization_invitations
    set acceptance_secret_digest = null
    where id = p_invitation_id;

    return created_membership_id;
end;
$$;

create function public.add_organization_responsibility(
    p_membership_id uuid,
    p_responsibility text,
    p_scope_type text,
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    operation_timestamp timestamptz;
    created_grant_id uuid;
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

    if p_responsibility is null
       or p_scope_type is null
       or not (
           (
               p_scope_type = 'ORGANIZATION'
               and p_clinic_id is null
               and p_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST',
                   'VETERINARIAN'
               )
           )
           or
           (
               p_scope_type = 'CLINIC'
               and p_clinic_id is not null
               and p_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST'
               )
           )
       ) then
        raise exception 'Unsupported Organization responsibility scope'
            using errcode = '22023';
    end if;

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_membership_id;

    if not found then
        raise exception 'Organization Membership does not exist'
            using errcode = '23503';
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

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if p_scope_type = 'CLINIC' then
        perform 1
        from public.clinics as clinic
        where clinic.id = p_clinic_id
          and clinic.organization_id = target_organization_id
        for update;

        if not found then
            raise exception 'Clinic-scoped responsibility requires a Clinic in the Membership Organization'
                using errcode = '23514';
        end if;
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as grant_record
        where grant_record.membership_id = p_membership_id
          and grant_record.responsibility = p_responsibility
          and grant_record.scope_type = p_scope_type
          and grant_record.clinic_id is not distinct from p_clinic_id
          and grant_record.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id
    )
    values (
        p_membership_id,
        p_responsibility,
        p_scope_type,
        p_clinic_id,
        operation_timestamp,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

revoke all privileges
on function public.add_organization_responsibility(uuid, text, text, uuid)
from public, anon, authenticated;

grant execute
on function public.add_organization_responsibility(uuid, text, text, uuid)
to authenticated;

create or replace function public.add_organization_responsibility(
    p_membership_id uuid,
    p_responsibility text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
    return public.add_organization_responsibility(
        p_membership_id,
        p_responsibility,
        'ORGANIZATION',
        null
    );
end;
$$;

revoke all privileges
on function public.add_organization_responsibility(uuid, text)
from public, anon, authenticated;

grant execute
on function public.add_organization_responsibility(uuid, text)
to authenticated;

create function public.replace_organization_responsibility(
    p_grant_id uuid,
    p_new_responsibility text,
    p_new_scope_type text,
    p_new_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_membership_id uuid;
    target_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    grant_record public.organization_responsibility_grants%rowtype;
    operation_timestamp timestamptz;
    created_grant_id uuid;
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

    if p_new_responsibility is null
       or p_new_scope_type is null
       or not (
           (
               p_new_scope_type = 'ORGANIZATION'
               and p_new_clinic_id is null
               and p_new_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST',
                   'VETERINARIAN'
               )
           )
           or
           (
               p_new_scope_type = 'CLINIC'
               and p_new_clinic_id is not null
               and p_new_responsibility in (
                   'ADMINISTRATOR',
                   'RECEPTIONIST'
               )
           )
       ) then
        raise exception 'Unsupported replacement Organization responsibility scope'
            using errcode = '22023';
    end if;

    select source_grant.membership_id, membership.organization_id
    into target_membership_id, target_organization_id
    from public.organization_responsibility_grants as source_grant
    join public.organization_memberships as membership
      on membership.id = source_grant.membership_id
    where source_grant.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = target_membership_id
      and membership.organization_id = target_organization_id
    for update;

    select current_grant.*
    into grant_record
    from public.organization_responsibility_grants as current_grant
    where current_grant.id = p_grant_id
      and current_grant.membership_id = target_membership_id
    for update;

    if membership_record.effective_end is not null then
        raise exception 'Responsibilities require an active Organization Membership'
            using errcode = '23514';
    end if;

    if grant_record.effective_end is not null then
        raise exception 'Organization Responsibility Grant has already ended'
            using errcode = '23514';
    end if;

    if grant_record.responsibility = 'OWNER' then
        raise exception 'OWNER cannot be replaced through ordinary responsibility management'
            using errcode = '42501';
    end if;

    if grant_record.responsibility = p_new_responsibility
       and grant_record.scope_type = p_new_scope_type
       and grant_record.clinic_id is not distinct from p_new_clinic_id then
        raise exception 'No-op Organization responsibility replacement is not allowed'
            using errcode = '22023';
    end if;

    if p_new_scope_type = 'CLINIC' then
        perform 1
        from public.clinics as clinic
        where clinic.id = p_new_clinic_id
          and clinic.organization_id = target_organization_id
        for update;

        if not found then
            raise exception 'Clinic-scoped responsibility requires a Clinic in the Membership Organization'
                using errcode = '23514';
        end if;
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        target_organization_id,
        'ORGANIZATION_GRANT_RESPONSIBILITIES'
    ) then
        raise exception 'Organization responsibility-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.organization_responsibility_grants as equivalent_grant
        where equivalent_grant.membership_id = target_membership_id
          and equivalent_grant.responsibility = p_new_responsibility
          and equivalent_grant.scope_type = p_new_scope_type
          and equivalent_grant.clinic_id is not distinct from p_new_clinic_id
          and equivalent_grant.effective_end is null
    ) then
        raise exception 'Equivalent active Organization Responsibility Grant already exists'
            using errcode = '23505';
    end if;

    operation_timestamp := clock_timestamp();

    update public.organization_responsibility_grants
    set effective_end = operation_timestamp,
        ended_by_user_id = acting_user_id
    where id = p_grant_id;

    insert into public.organization_responsibility_grants (
        membership_id,
        responsibility,
        scope_type,
        clinic_id,
        effective_start,
        granted_by_user_id
    )
    values (
        target_membership_id,
        p_new_responsibility,
        p_new_scope_type,
        p_new_clinic_id,
        operation_timestamp,
        acting_user_id
    )
    returning id into created_grant_id;

    return created_grant_id;
end;
$$;

revoke all privileges
on function public.replace_organization_responsibility(uuid, text, text, uuid)
from public, anon, authenticated;

grant execute
on function public.replace_organization_responsibility(uuid, text, text, uuid)
to authenticated;

create or replace function public.replace_organization_responsibility(
    p_grant_id uuid,
    p_new_responsibility text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    source_scope_type text;
begin
    select grant_record.scope_type
    into source_scope_type
    from public.organization_responsibility_grants as grant_record
    where grant_record.id = p_grant_id;

    if not found then
        raise exception 'Organization Responsibility Grant does not exist'
            using errcode = '23503';
    end if;

    if source_scope_type <> 'ORGANIZATION' then
        raise exception 'The Organization-only compatibility operation cannot replace a Clinic-scoped Grant'
            using errcode = '22023';
    end if;

    return public.replace_organization_responsibility(
        p_grant_id,
        p_new_responsibility,
        'ORGANIZATION',
        null
    );
end;
$$;

revoke all privileges
on function public.replace_organization_responsibility(uuid, text)
from public, anon, authenticated;

grant execute
on function public.replace_organization_responsibility(uuid, text)
to authenticated;

create function public.create_clinic(
    p_organization_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    operation_timestamp timestamptz;
    created_clinic_id uuid;
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

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = p_organization_id
    for update;

    if not found then
        raise exception 'Veterinary Organization does not exist'
            using errcode = '23503';
    end if;

    if not public.user_has_organization_capability(
        acting_user_id,
        p_organization_id,
        'ORGANIZATION_CREATE_CLINICS'
    ) then
        raise exception 'Clinic-creation capability is required'
            using errcode = '42501';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.clinics (
        organization_id,
        created_at
    )
    values (
        p_organization_id,
        operation_timestamp
    )
    returning id into created_clinic_id;

    return created_clinic_id;
end;
$$;

revoke all privileges
on function public.create_clinic(uuid)
from public, anon, authenticated;

grant execute
on function public.create_clinic(uuid)
to authenticated;

create function public.set_clinic_location(
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
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

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

    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
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

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_LOCATION'
    ) then
        raise exception 'Clinic Location-management capability is required'
            using errcode = '42501';
    end if;

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

revoke all privileges
on function public.set_clinic_location(uuid, text, double precision, double precision)
from public, anon, authenticated;

grant execute
on function public.set_clinic_location(uuid, text, double precision, double precision)
to authenticated;

create function public.set_clinic_public_profile(
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
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    acting_user_id := public.current_domain_user_id();

    if acting_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

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

    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
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

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_PUBLIC_PROFILE'
    ) then
        raise exception 'Clinic Public Profile-management capability is required'
            using errcode = '42501';
    end if;

    if clinic_record.is_published
       and normalized_display_name is null then
        raise exception 'A published Clinic must retain a valid public display name'
            using errcode = '23514';
    end if;

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

revoke all privileges
on function public.set_clinic_public_profile(uuid, text, text, text, text, text)
from public, anon, authenticated;

grant execute
on function public.set_clinic_public_profile(uuid, text, text, text, text, text)
to authenticated;

create function public.publish_clinic(
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
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

    select clinic.organization_id
    into target_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
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

    if not found then
        raise exception 'Clinic does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_PUBLICATION'
    ) then
        raise exception 'Clinic publication-management capability is required'
            using errcode = '42501';
    end if;

    if not exists (
        select 1
        from public.clinic_locations as location
        where location.clinic_id = p_clinic_id
    ) then
        raise exception 'Clinic publication requires a valid current Location'
            using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.clinic_public_profiles as profile
        where profile.clinic_id = p_clinic_id
          and profile.display_name is not null
          and profile.display_name = btrim(
              profile.display_name,
              E' \t\n\r\f\013'
          )
          and profile.display_name <> ''
    ) then
        raise exception 'Clinic publication requires a valid public display name'
            using errcode = '23514';
    end if;

    update public.clinics
    set is_published = true
    where id = p_clinic_id;

    return p_clinic_id;
end;
$$;

revoke all privileges
on function public.publish_clinic(uuid)
from public, anon, authenticated;

grant execute
on function public.publish_clinic(uuid)
to authenticated;

create function public.veterinarian_clinic_assignment_is_current(
    p_assignment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.veterinarian_clinic_assignments as assignment
        join public.veterinarian_professional_profiles as profile
          on profile.id = assignment.professional_profile_id
        join public.organization_memberships as membership
          on membership.id = assignment.supporting_membership_id
        join public.clinics as clinic
          on clinic.id = assignment.clinic_id
        where assignment.id = p_assignment_id
          and assignment.effective_end is null
          and membership.effective_end is null
          and profile.user_id = membership.user_id
          and clinic.organization_id = membership.organization_id
    )
$$;

revoke all privileges
on function public.veterinarian_clinic_assignment_is_current(uuid)
from public, anon, authenticated;

create function public.assign_veterinarian_to_clinic(
    p_professional_profile_id uuid,
    p_supporting_membership_id uuid,
    p_clinic_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    clinic_organization_id uuid;
    membership_record public.organization_memberships%rowtype;
    profile_user_id uuid;
    operation_timestamp timestamptz;
    created_assignment_id uuid;
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

    select membership.organization_id
    into target_organization_id
    from public.organization_memberships as membership
    where membership.id = p_supporting_membership_id;

    if not found then
        raise exception 'Supporting Organization Membership does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    select clinic.organization_id
    into clinic_organization_id
    from public.clinics as clinic
    where clinic.id = p_clinic_id
    for update;

    if not found then
        raise exception 'Clinic does not exist'
            using errcode = '23503';
    end if;

    select membership.*
    into membership_record
    from public.organization_memberships as membership
    where membership.id = p_supporting_membership_id
      and membership.organization_id = target_organization_id
    for update;

    if not found then
        raise exception 'Supporting Organization Membership does not exist in the expected Organization'
            using errcode = '23503';
    end if;

    if clinic_organization_id <> target_organization_id then
        raise exception 'Clinic and supporting Membership must belong to the same Organization'
            using errcode = '23514';
    end if;

    if membership_record.effective_end is not null then
        raise exception 'Veterinarian Clinic Assignment requires an active Organization Membership'
            using errcode = '23514';
    end if;

    select profile.user_id
    into profile_user_id
    from public.veterinarian_professional_profiles as profile
    where profile.id = p_professional_profile_id;

    if not found then
        raise exception 'Veterinarian Professional Profile does not exist'
            using errcode = '23503';
    end if;

    if profile_user_id <> membership_record.user_id then
        raise exception 'Veterinarian Professional Profile and supporting Membership must belong to the same User'
            using errcode = '23514';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id,
        p_clinic_id,
        'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'
    ) then
        raise exception 'Veterinarian Clinic Assignment-management capability is required'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.veterinarian_clinic_assignments as assignment
        join public.organization_memberships as supporting_membership
          on supporting_membership.id = assignment.supporting_membership_id
        where assignment.professional_profile_id = p_professional_profile_id
          and assignment.clinic_id = p_clinic_id
          and assignment.effective_end is null
          and supporting_membership.effective_end is null
    ) then
        raise exception 'Equivalent active Veterinarian Clinic Assignment already exists'
            using errcode = '23505';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.veterinarian_clinic_assignments (
        professional_profile_id,
        supporting_membership_id,
        clinic_id,
        effective_start
    )
    values (
        p_professional_profile_id,
        p_supporting_membership_id,
        p_clinic_id,
        operation_timestamp
    )
    returning id into created_assignment_id;

    return created_assignment_id;
end;
$$;

revoke all privileges
on function public.assign_veterinarian_to_clinic(uuid, uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.assign_veterinarian_to_clinic(uuid, uuid, uuid)
to authenticated;

create function public.end_veterinarian_clinic_assignment(
    p_assignment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    target_organization_id uuid;
    target_clinic_id uuid;
    assignment_record public.veterinarian_clinic_assignments%rowtype;
    operation_timestamp timestamptz;
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

    select assignment.clinic_id, clinic.organization_id
    into target_clinic_id, target_organization_id
    from public.veterinarian_clinic_assignments as assignment
    join public.clinics as clinic
      on clinic.id = assignment.clinic_id
    where assignment.id = p_assignment_id;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.veterinary_organizations as organization
    where organization.id = target_organization_id
    for update;

    perform 1
    from public.clinics as clinic
    where clinic.id = target_clinic_id
      and clinic.organization_id = target_organization_id
    for update;

    select assignment.*
    into assignment_record
    from public.veterinarian_clinic_assignments as assignment
    where assignment.id = p_assignment_id
      and assignment.clinic_id = target_clinic_id
    for update;

    if not found then
        raise exception 'Veterinarian Clinic Assignment does not exist in the expected Clinic'
            using errcode = '23503';
    end if;

    if assignment_record.effective_end is not null then
        raise exception 'Veterinarian Clinic Assignment has already ended'
            using errcode = '23514';
    end if;

    if not public.user_has_clinic_capability(
        acting_user_id,
        target_clinic_id,
        'CLINIC_MANAGE_VETERINARIAN_ASSIGNMENTS'
    ) then
        raise exception 'Veterinarian Clinic Assignment-management capability is required'
            using errcode = '42501';
    end if;

    operation_timestamp := clock_timestamp();

    update public.veterinarian_clinic_assignments
    set effective_end = operation_timestamp
    where id = p_assignment_id;
end;
$$;

revoke all privileges
on function public.end_veterinarian_clinic_assignment(uuid)
from public, anon, authenticated;

grant execute
on function public.end_veterinarian_clinic_assignment(uuid)
to authenticated;

alter table public.clinics enable row level security;
alter table public.clinic_locations enable row level security;
alter table public.clinic_public_profiles enable row level security;
alter table public.veterinarian_clinic_assignments enable row level security;

revoke all privileges on table public.clinics
from public, anon, authenticated;
revoke all privileges on table public.clinic_locations
from public, anon, authenticated;
revoke all privileges on table public.clinic_public_profiles
from public, anon, authenticated;
revoke all privileges on table public.veterinarian_clinic_assignments
from public, anon, authenticated;

create view public.published_clinic_public_profiles
with (security_barrier = true)
as
select
    clinic.id as clinic_id,
    profile.display_name,
    profile.description,
    profile.public_phone,
    profile.public_email,
    profile.website
from public.clinics as clinic
join public.clinic_public_profiles as profile
  on profile.clinic_id = clinic.id
where clinic.is_published = true;

revoke all privileges on table public.published_clinic_public_profiles
from public, anon, authenticated;

grant select on table public.published_clinic_public_profiles
to anon, authenticated;

commit;
