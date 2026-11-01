begin;

create table public.veterinarian_professional_profiles (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    constraint veterinarian_professional_profiles_pkey primary key (id),
    constraint veterinarian_professional_profiles_user_id_key unique (user_id),
    constraint veterinarian_professional_profiles_user_id_fkey
        foreign key (user_id)
        references public.users (id)
        on update no action
        on delete restrict
);

create table public.veterinarian_professional_credentials (
    id uuid not null default gen_random_uuid(),
    professional_profile_id uuid not null,
    registration_identifier text not null,
    issuing_context text not null,
    constraint veterinarian_professional_credentials_pkey primary key (id),
    constraint veterinarian_professional_credentials_profile_id_key
        unique (professional_profile_id),
    constraint veterinarian_professional_credentials_profile_id_fkey
        foreign key (professional_profile_id)
        references public.veterinarian_professional_profiles (id)
        on update no action
        on delete restrict,
    constraint veterinarian_professional_credentials_registration_identifier_check
        check (btrim(registration_identifier, E' \t\n\r\f\013') <> ''),
    constraint veterinarian_professional_credentials_issuing_context_check
        check (btrim(issuing_context, E' \t\n\r\f\013') <> '')
);

create function public.enforce_veterinarian_professional_profile_credential()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_schema = 'public'
       and tg_table_name = 'veterinarian_professional_profiles'
       and tg_op = 'INSERT' then
        if exists (
            select 1
            from public.veterinarian_professional_profiles as profile
            where profile.id = new.id
        ) and not exists (
            select 1
            from public.veterinarian_professional_credentials as credential
            where credential.professional_profile_id = new.id
        ) then
            raise exception
                'Veterinarian Professional Profile % requires exactly one Professional Credential',
                new.id
                using errcode = '23514';
        end if;

    elsif tg_table_schema = 'public'
          and tg_table_name = 'veterinarian_professional_credentials'
          and tg_op = 'DELETE' then
        if exists (
            select 1
            from public.veterinarian_professional_profiles as profile
            where profile.id = old.professional_profile_id
        ) and not exists (
            select 1
            from public.veterinarian_professional_credentials as credential
            where credential.professional_profile_id = old.professional_profile_id
        ) then
            raise exception
                'Veterinarian Professional Profile % requires exactly one Professional Credential',
                old.professional_profile_id
                using errcode = '23514';
        end if;

    elsif tg_table_schema = 'public'
          and tg_table_name = 'veterinarian_professional_credentials'
          and tg_op = 'UPDATE' then
        if old.professional_profile_id is distinct from new.professional_profile_id then
            if exists (
                select 1
                from public.veterinarian_professional_profiles as profile
                where profile.id = old.professional_profile_id
            ) and not exists (
                select 1
                from public.veterinarian_professional_credentials as credential
                where credential.professional_profile_id = old.professional_profile_id
            ) then
                raise exception
                    'Veterinarian Professional Profile % requires exactly one Professional Credential',
                    old.professional_profile_id
                    using errcode = '23514';
            end if;

            if exists (
                select 1
                from public.veterinarian_professional_profiles as profile
                where profile.id = new.professional_profile_id
            ) and not exists (
                select 1
                from public.veterinarian_professional_credentials as credential
                where credential.professional_profile_id = new.professional_profile_id
            ) then
                raise exception
                    'Veterinarian Professional Profile % requires exactly one Professional Credential',
                    new.professional_profile_id
                    using errcode = '23514';
            end if;
        end if;

    else
        raise exception
            'Unexpected trigger invocation for Professional Profile Credential integrity'
            using errcode = '55000';
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_veterinarian_professional_profile_credential()
from public, anon, authenticated;

create constraint trigger veterinarian_professional_profiles_require_credential
after insert on public.veterinarian_professional_profiles
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_professional_profile_credential();

create constraint trigger veterinarian_professional_credentials_delete_preserves_profile
after delete on public.veterinarian_professional_credentials
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_professional_profile_credential();

create constraint trigger veterinarian_professional_credentials_update_preserves_profiles
after update of professional_profile_id
on public.veterinarian_professional_credentials
deferrable initially deferred
for each row
execute function public.enforce_veterinarian_professional_profile_credential();

alter table public.veterinarian_professional_profiles enable row level security;
alter table public.veterinarian_professional_credentials enable row level security;

revoke all privileges on table public.veterinarian_professional_profiles
    from public, anon, authenticated;
revoke all privileges on table public.veterinarian_professional_credentials
    from public, anon, authenticated;

create function public.create_veterinarian_professional_profile(
    p_registration_identifier text,
    p_issuing_context text
)
returns table (
    professional_profile_id uuid,
    professional_credential_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    domain_user_id uuid;
    normalized_registration_identifier text;
    normalized_issuing_context text;
    created_profile_id uuid;
    created_credential_id uuid;
begin
    authenticated_subject_id := auth.uid();

    if authenticated_subject_id is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    domain_user_id := public.current_domain_user_id();

    if domain_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from auth.users as auth_user
        where auth_user.id = authenticated_subject_id
          and auth_user.email_confirmed_at is not null
    ) then
        raise exception 'A verified email address is required'
            using errcode = '42501';
    end if;

    normalized_registration_identifier :=
        btrim(p_registration_identifier, E' \t\n\r\f\013');
    normalized_issuing_context :=
        btrim(p_issuing_context, E' \t\n\r\f\013');

    if normalized_registration_identifier is null
       or normalized_registration_identifier = '' then
        raise exception 'Professional registration identifier must not be blank'
            using errcode = '22023';
    end if;

    if normalized_issuing_context is null
       or normalized_issuing_context = '' then
        raise exception 'Professional issuing context must not be blank'
            using errcode = '22023';
    end if;

    insert into public.veterinarian_professional_profiles (user_id)
    values (domain_user_id)
    returning id into created_profile_id;

    insert into public.veterinarian_professional_credentials (
        professional_profile_id,
        registration_identifier,
        issuing_context
    )
    values (
        created_profile_id,
        normalized_registration_identifier,
        normalized_issuing_context
    )
    returning id into created_credential_id;

    return query
    select created_profile_id, created_credential_id;
end;
$$;

revoke all privileges
on function public.create_veterinarian_professional_profile(text, text)
from public, anon, authenticated;

grant execute
on function public.create_veterinarian_professional_profile(text, text)
to authenticated;

commit;
