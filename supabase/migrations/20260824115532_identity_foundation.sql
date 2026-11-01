begin;

create table public.users (
    id uuid not null default gen_random_uuid(),
    created_at timestamptz not null default transaction_timestamp(),
    constraint users_pkey primary key (id)
);

create table public.user_authentication_identities (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    provider text not null default 'supabase_auth',
    issuer text not null default 'primary',
    provider_subject uuid not null,
    linked_at timestamptz not null default transaction_timestamp(),
    constraint user_auth_identities_pkey primary key (id),
    constraint user_auth_identities_user_id_fkey
        foreign key (user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint user_auth_identities_subject_fkey
        foreign key (provider_subject)
        references auth.users (id)
        on update no action
        on delete restrict,
    constraint user_auth_identities_user_id_key unique (user_id),
    constraint user_auth_identities_provider_issuer_subject_key
        unique (provider, issuer, provider_subject),
    constraint user_auth_identities_provider_check
        check (provider = 'supabase_auth'),
    constraint user_auth_identities_issuer_check
        check (issuer = 'primary')
);

create table public.user_profiles (
    user_id uuid not null,
    display_name text,
    avatar_reference text,
    constraint user_profiles_pkey primary key (user_id),
    constraint user_profiles_user_id_fkey
        foreign key (user_id)
        references public.users (id)
        on update no action
        on delete restrict
);

alter table public.users enable row level security;
alter table public.user_authentication_identities enable row level security;
alter table public.user_profiles enable row level security;

revoke all privileges on table public.users
    from public, anon, authenticated;
revoke all privileges on table public.user_authentication_identities
    from public, anon, authenticated;
revoke all privileges on table public.user_profiles
    from public, anon, authenticated;

create function public.current_domain_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select identity_link.user_id
    from public.user_authentication_identities as identity_link
    where identity_link.provider = 'supabase_auth'
      and identity_link.issuer = 'primary'
      and identity_link.provider_subject = auth.uid()
$$;

revoke all privileges on function public.current_domain_user_id()
    from public, anon;
grant execute on function public.current_domain_user_id()
    to authenticated;

grant select, insert, update on table public.user_profiles
    to authenticated;

create policy user_profiles_select_own
on public.user_profiles
for select
to authenticated
using (
    user_id = (select public.current_domain_user_id())
);

create policy user_profiles_insert_own
on public.user_profiles
for insert
to authenticated
with check (
    user_id = (select public.current_domain_user_id())
);

create policy user_profiles_update_own
on public.user_profiles
for update
to authenticated
using (
    user_id = (select public.current_domain_user_id())
)
with check (
    user_id = (select public.current_domain_user_id())
);

create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    domain_user_id uuid;
begin
    insert into public.users default values
    returning id into domain_user_id;

    insert into public.user_authentication_identities (
        user_id,
        provider,
        issuer,
        provider_subject
    )
    values (
        domain_user_id,
        'supabase_auth',
        'primary',
        new.id
    );

    return new;
end;
$$;

revoke all privileges on function public.handle_new_auth_user()
    from public, anon, authenticated;

create trigger on_auth_user_created_create_domain_user
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

commit;
