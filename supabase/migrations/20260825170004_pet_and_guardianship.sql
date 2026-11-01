begin;

create table public.pets (
    id uuid not null default gen_random_uuid(),
    name text not null,
    species text not null,
    breed text,
    sex text,
    date_of_birth date,
    approximate_date_of_birth date,
    microchip_identifier text,
    profile_image_reference text,
    behavioral_safety_information text,
    created_at timestamptz not null,
    constraint pets_pkey primary key (id),
    constraint pets_name_check
        check (
            name = btrim(name, E' \t\n\r\f\013')
            and name <> ''
        ),
    constraint pets_species_check
        check (
            species = btrim(species, E' \t\n\r\f\013')
            and species <> ''
        ),
    constraint pets_breed_check
        check (
            breed is null
            or (
                breed = btrim(breed, E' \t\n\r\f\013')
                and breed <> ''
            )
        ),
    constraint pets_sex_check
        check (
            sex is null
            or (
                sex = btrim(sex, E' \t\n\r\f\013')
                and sex <> ''
            )
        ),
    constraint pets_birth_date_exclusivity_check
        check (
            not (
                date_of_birth is not null
                and approximate_date_of_birth is not null
            )
        ),
    constraint pets_microchip_identifier_check
        check (
            microchip_identifier is null
            or (
                microchip_identifier = btrim(
                    microchip_identifier,
                    E' \t\n\r\f\013'
                )
                and microchip_identifier <> ''
            )
        ),
    constraint pets_profile_image_reference_check
        check (
            profile_image_reference is null
            or (
                profile_image_reference = btrim(
                    profile_image_reference,
                    E' \t\n\r\f\013'
                )
                and profile_image_reference <> ''
            )
        ),
    constraint pets_behavioral_safety_information_check
        check (
            behavioral_safety_information is null
            or (
                behavioral_safety_information = btrim(
                    behavioral_safety_information,
                    E' \t\n\r\f\013'
                )
                and behavioral_safety_information <> ''
            )
        )
);

create table public.guardianships (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    pet_id uuid not null,
    effective_start timestamptz not null,
    effective_end timestamptz,
    constraint guardianships_pkey primary key (id),
    constraint guardianships_user_id_fkey
        foreign key (user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint guardianships_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint guardianships_effective_period_check
        check (
            effective_end is null
            or effective_end >= effective_start
        )
);

create table public.guardianship_invitations (
    id uuid not null default gen_random_uuid(),
    pet_id uuid not null,
    inviting_guardianship_id uuid not null,
    recipient_user_id uuid,
    recipient_email text not null,
    recipient_email_normalized text generated always as (
        lower(btrim(recipient_email, E' \t\n\r\f\013'))
    ) stored not null,
    created_at timestamptz not null,
    expires_at timestamptz not null,
    acceptance_secret_digest bytea,
    revoked_at timestamptz,
    revoked_by_guardianship_id uuid,
    constraint guardianship_invitations_pkey primary key (id),
    constraint guardianship_invitations_pet_id_fkey
        foreign key (pet_id)
        references public.pets (id)
        on update no action
        on delete restrict,
    constraint guardianship_invitations_inviting_guardianship_id_fkey
        foreign key (inviting_guardianship_id)
        references public.guardianships (id)
        on update no action
        on delete restrict,
    constraint guardianship_invitations_recipient_user_id_fkey
        foreign key (recipient_user_id)
        references public.users (id)
        on update no action
        on delete restrict,
    constraint guardianship_invitations_revoking_guardianship_id_fkey
        foreign key (revoked_by_guardianship_id)
        references public.guardianships (id)
        on update no action
        on delete restrict,
    constraint guardianship_invitations_recipient_email_check
        check (
            recipient_email = btrim(
                recipient_email,
                E' \t\n\r\f\013'
            )
            and recipient_email <> ''
        ),
    constraint guardianship_invitations_expiration_check
        check (
            isfinite(created_at)
            and isfinite(expires_at)
            and expires_at > created_at
        ),
    constraint guardianship_invitations_secret_digest_check
        check (
            acceptance_secret_digest is null
            or octet_length(acceptance_secret_digest) = 32
        ),
    constraint guardianship_invitations_revocation_pair_check
        check (
            (revoked_at is null) =
            (revoked_by_guardianship_id is null)
        ),
    constraint guardianship_invitations_revocation_time_check
        check (
            revoked_at is null
            or revoked_at >= created_at
        )
);

alter table public.guardianships
add column originating_invitation_id uuid;

alter table public.guardianships
add constraint guardianships_originating_invitation_id_fkey
foreign key (originating_invitation_id)
references public.guardianship_invitations (id)
on update no action
on delete restrict;

alter table public.guardianships
add constraint guardianships_originating_invitation_id_key
unique (originating_invitation_id);

create unique index guardianships_active_user_pet_key
on public.guardianships (user_id, pet_id)
where effective_end is null;

create index guardianships_active_pet_user_idx
on public.guardianships (pet_id, user_id)
where effective_end is null;

create index guardianships_pet_history_idx
on public.guardianships (pet_id, effective_start, id);

create index guardianship_invitations_pet_history_idx
on public.guardianship_invitations (pet_id, created_at, id);

create index guardianship_invitations_inviting_guardianship_history_idx
on public.guardianship_invitations (
    inviting_guardianship_id,
    created_at,
    id
);

create index guardianship_invitations_bound_recipient_idx
on public.guardianship_invitations (pet_id, recipient_user_id)
where recipient_user_id is not null;

create index guardianship_invitations_contact_equivalence_idx
on public.guardianship_invitations (pet_id, recipient_email_normalized);

create function public.enforce_pet_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Pets cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.created_at is distinct from new.created_at then
        raise exception 'Pet identity and creation time are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_pet_immutability()
from public, anon, authenticated;

create trigger pets_preserve_identity
before update or delete on public.pets
for each row
execute function public.enforce_pet_immutability();

create function public.enforce_guardianship_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Guardianships cannot be deleted through ordinary operations'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.user_id is distinct from new.user_id
       or old.pet_id is distinct from new.pet_id
       or old.effective_start is distinct from new.effective_start
       or old.originating_invitation_id is distinct from
           new.originating_invitation_id then
        raise exception 'Guardianship identity, context, start, and origin are immutable'
            using errcode = '23514';
    end if;

    if old.effective_end is not null
       and old.effective_end is distinct from new.effective_end then
        raise exception 'Ended Guardianship facts are immutable'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_guardianship_immutability()
from public, anon, authenticated;

create trigger guardianships_preserve_history
before update or delete on public.guardianships
for each row
execute function public.enforce_guardianship_immutability();

create function public.enforce_guardianship_invitation_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Guardianship Invitations cannot be deleted'
            using errcode = '23514';
    end if;

    if old.id is distinct from new.id
       or old.pet_id is distinct from new.pet_id
       or old.inviting_guardianship_id is distinct from
           new.inviting_guardianship_id
       or old.recipient_user_id is distinct from new.recipient_user_id
       or old.recipient_email is distinct from new.recipient_email
       or old.created_at is distinct from new.created_at
       or old.expires_at is distinct from new.expires_at then
        raise exception 'Guardianship Invitation identity and context are immutable'
            using errcode = '23514';
    end if;

    if old.revoked_at is not null
       and (
           old.revoked_at is distinct from new.revoked_at
           or old.revoked_by_guardianship_id is distinct from
               new.revoked_by_guardianship_id
       ) then
        raise exception 'Guardianship Invitation revocation facts are immutable'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is null
       and new.acceptance_secret_digest is not null then
        raise exception 'Guardianship Invitation acceptance credential cannot be restored'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is not null
       and new.acceptance_secret_digest is not null
       and old.acceptance_secret_digest is distinct from
           new.acceptance_secret_digest then
        raise exception 'Guardianship Invitation acceptance credential cannot be replaced'
            using errcode = '23514';
    end if;

    if old.acceptance_secret_digest is not null
       and new.acceptance_secret_digest is null
       and new.revoked_at is null
       and not exists (
           select 1
           from public.guardianships as resulting_guardianship
           where resulting_guardianship.originating_invitation_id = old.id
       )
       and clock_timestamp() < old.expires_at then
        raise exception 'A valid pending Guardianship Invitation must retain its acceptance credential'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke all privileges
on function public.enforce_guardianship_invitation_immutability()
from public, anon, authenticated;

create trigger guardianship_invitations_preserve_history
before update or delete on public.guardianship_invitations
for each row
execute function public.enforce_guardianship_invitation_immutability();

create function public.assert_pet_has_guardianship(
    p_pet_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform 1
    from public.pets as pet
    where pet.id = p_pet_id
    for update;

    if not found then
        return;
    end if;

    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
    ) then
        raise exception 'Pet % requires at least one historical Guardianship',
            p_pet_id
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_pet_has_guardianship(uuid)
from public, anon, authenticated;

create function public.enforce_pet_guardianship_minimum()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    old_pet_id uuid;
    new_pet_id uuid;
begin
    if tg_table_schema = 'public'
       and tg_table_name = 'pets' then
        if tg_op = 'INSERT' then
            new_pet_id := new.id;
        elsif tg_op = 'DELETE' then
            old_pet_id := old.id;
        else
            raise exception 'Unexpected Pet minimum-cardinality trigger operation'
                using errcode = '55000';
        end if;
    elsif tg_table_schema = 'public'
          and tg_table_name = 'guardianships' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_pet_id := old.pet_id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_pet_id := new.pet_id;
        end if;
    else
        raise exception 'Unexpected Pet minimum-cardinality trigger invocation'
            using errcode = '55000';
    end if;

    if old_pet_id is not null then
        perform public.assert_pet_has_guardianship(old_pet_id);
    end if;

    if new_pet_id is not null
       and new_pet_id is distinct from old_pet_id then
        perform public.assert_pet_has_guardianship(new_pet_id);
    end if;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_pet_guardianship_minimum()
from public, anon, authenticated;

create constraint trigger pets_require_historical_guardianship
after insert on public.pets
deferrable initially deferred
for each row
execute function public.enforce_pet_guardianship_minimum();

create constraint trigger guardianships_preserve_pet_minimum
after insert or update or delete on public.guardianships
deferrable initially deferred
for each row
execute function public.enforce_pet_guardianship_minimum();

create function public.assert_guardianship_invitation_integrity(
    p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation_pet_id uuid;
    invitation_record public.guardianship_invitations%rowtype;
    inviting_guardianship_record public.guardianships%rowtype;
    revoking_guardianship_record public.guardianships%rowtype;
    resulting_guardianship_record public.guardianships%rowtype;
begin
    select invitation.pet_id
    into invitation_pet_id
    from public.guardianship_invitations as invitation
    where invitation.id = p_invitation_id;

    if not found then
        return;
    end if;

    perform 1
    from public.pets as pet
    where pet.id = invitation_pet_id
    for update;

    select invitation.*
    into invitation_record
    from public.guardianship_invitations as invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        return;
    end if;

    select guardianship.*
    into inviting_guardianship_record
    from public.guardianships as guardianship
    where guardianship.id = invitation_record.inviting_guardianship_id;

    if not found then
        raise exception 'Guardianship Invitation % requires its inviting Guardianship',
            p_invitation_id
            using errcode = '23514';
    end if;

    if inviting_guardianship_record.pet_id <> invitation_record.pet_id then
        raise exception 'Guardianship Invitation Pet must match its inviting Guardianship Pet'
            using errcode = '23514';
    end if;

    if inviting_guardianship_record.effective_start > invitation_record.created_at
       or (
           inviting_guardianship_record.effective_end is not null
           and invitation_record.created_at >
               inviting_guardianship_record.effective_end
       ) then
        raise exception 'Inviting Guardianship must be effective when the Invitation is created'
            using errcode = '23514';
    end if;

    select guardianship.*
    into resulting_guardianship_record
    from public.guardianships as guardianship
    where guardianship.originating_invitation_id = p_invitation_id;

    if found then
        if invitation_record.revoked_at is not null then
            raise exception 'Accepted Guardianship Invitation cannot also be revoked'
                using errcode = '23514';
        end if;

        if invitation_record.acceptance_secret_digest is not null then
            raise exception 'Accepted Guardianship Invitation must not retain its acceptance credential'
                using errcode = '23514';
        end if;

        if resulting_guardianship_record.pet_id <>
           invitation_record.pet_id then
            raise exception 'Invitation-derived Guardianship must concern the invited Pet'
                using errcode = '23514';
        end if;

        if invitation_record.recipient_user_id is not null
           and resulting_guardianship_record.user_id <>
               invitation_record.recipient_user_id then
            raise exception 'Invitation-derived Guardianship User must match the bound recipient User'
                using errcode = '23514';
        end if;

        if resulting_guardianship_record.effective_start <
               invitation_record.created_at
           or resulting_guardianship_record.effective_start >=
               invitation_record.expires_at then
            raise exception 'Guardianship Invitation acceptance must occur during its validity period'
                using errcode = '23514';
        end if;
    elsif invitation_record.revoked_at is not null then
        select guardianship.*
        into revoking_guardianship_record
        from public.guardianships as guardianship
        where guardianship.id =
            invitation_record.revoked_by_guardianship_id;

        if not found then
            raise exception 'Revoked Guardianship Invitation requires its revoking Guardianship'
                using errcode = '23514';
        end if;

        if revoking_guardianship_record.pet_id <>
           invitation_record.pet_id then
            raise exception 'Revoking Guardianship must concern the invited Pet'
                using errcode = '23514';
        end if;

        if revoking_guardianship_record.effective_start >
               invitation_record.revoked_at
           or (
               revoking_guardianship_record.effective_end is not null
               and invitation_record.revoked_at >
                   revoking_guardianship_record.effective_end
           ) then
            raise exception 'Revoking Guardianship must be effective at revocation time'
                using errcode = '23514';
        end if;

        if invitation_record.acceptance_secret_digest is not null then
            raise exception 'Revoked Guardianship Invitation must not retain its acceptance credential'
                using errcode = '23514';
        end if;
    elsif invitation_record.acceptance_secret_digest is null
          and clock_timestamp() < invitation_record.expires_at then
        raise exception 'A valid pending Guardianship Invitation must retain its acceptance credential'
            using errcode = '23514';
    end if;
end;
$$;

revoke all privileges
on function public.assert_guardianship_invitation_integrity(uuid)
from public, anon, authenticated;

create function public.enforce_guardianship_invitation_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    old_invitation_id uuid;
    new_invitation_id uuid;
    affected_invitation_id uuid;
    old_guardianship_id uuid;
    new_guardianship_id uuid;
begin
    if tg_table_schema = 'public'
       and tg_table_name = 'guardianship_invitations' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_invitation_id := old.id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_invitation_id := new.id;
        end if;
    elsif tg_table_schema = 'public'
          and tg_table_name = 'guardianships' then
        if tg_op in ('UPDATE', 'DELETE') then
            old_invitation_id := old.originating_invitation_id;
            old_guardianship_id := old.id;
        end if;
        if tg_op in ('INSERT', 'UPDATE') then
            new_invitation_id := new.originating_invitation_id;
            new_guardianship_id := new.id;
        end if;
    else
        raise exception 'Unexpected Guardianship Invitation integrity trigger invocation'
            using errcode = '55000';
    end if;

    if old_invitation_id is not null then
        perform public.assert_guardianship_invitation_integrity(
            old_invitation_id
        );
    end if;

    if new_invitation_id is not null
       and new_invitation_id is distinct from old_invitation_id then
        perform public.assert_guardianship_invitation_integrity(
            new_invitation_id
        );
    end if;

    for affected_invitation_id in
        select invitation.id
        from public.guardianship_invitations as invitation
        where invitation.inviting_guardianship_id in (
                  old_guardianship_id,
                  new_guardianship_id
              )
           or invitation.revoked_by_guardianship_id in (
                  old_guardianship_id,
                  new_guardianship_id
              )
        order by invitation.id
    loop
        if affected_invitation_id is distinct from old_invitation_id
           and affected_invitation_id is distinct from new_invitation_id then
            perform public.assert_guardianship_invitation_integrity(
                affected_invitation_id
            );
        end if;
    end loop;

    return null;
end;
$$;

revoke all privileges
on function public.enforce_guardianship_invitation_integrity()
from public, anon, authenticated;

create constraint trigger guardianship_invitations_enforce_integrity
after insert or update or delete on public.guardianship_invitations
deferrable initially deferred
for each row
execute function public.enforce_guardianship_invitation_integrity();

create constraint trigger guardianships_enforce_invitation_integrity
after insert or update or delete on public.guardianships
deferrable initially deferred
for each row
execute function public.enforce_guardianship_invitation_integrity();

alter table public.pets enable row level security;
alter table public.guardianships enable row level security;
alter table public.guardianship_invitations enable row level security;

revoke all privileges on table public.pets
from public, anon, authenticated;
revoke all privileges on table public.guardianships
from public, anon, authenticated;
revoke all privileges on table public.guardianship_invitations
from public, anon, authenticated;

create function public.register_pet(
    p_name text,
    p_species text,
    p_breed text,
    p_sex text,
    p_date_of_birth date,
    p_approximate_date_of_birth date,
    p_microchip_identifier text,
    p_profile_image_reference text,
    p_behavioral_safety_information text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    domain_user_id uuid;
    normalized_name text;
    normalized_species text;
    normalized_breed text;
    normalized_sex text;
    normalized_microchip_identifier text;
    normalized_profile_image_reference text;
    normalized_behavioral_safety_information text;
    operation_timestamp timestamptz;
    created_pet_id uuid;
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

    normalized_name := btrim(p_name, E' \t\n\r\f\013');
    normalized_species := btrim(p_species, E' \t\n\r\f\013');
    normalized_breed := case
        when p_breed is null then null
        else btrim(p_breed, E' \t\n\r\f\013')
    end;
    normalized_sex := case
        when p_sex is null then null
        else btrim(p_sex, E' \t\n\r\f\013')
    end;
    normalized_microchip_identifier := case
        when p_microchip_identifier is null then null
        else btrim(p_microchip_identifier, E' \t\n\r\f\013')
    end;
    normalized_profile_image_reference := case
        when p_profile_image_reference is null then null
        else btrim(p_profile_image_reference, E' \t\n\r\f\013')
    end;
    normalized_behavioral_safety_information := case
        when p_behavioral_safety_information is null then null
        else btrim(
            p_behavioral_safety_information,
            E' \t\n\r\f\013'
        )
    end;

    if normalized_name is null or normalized_name = '' then
        raise exception 'Pet name must not be blank'
            using errcode = '22023';
    end if;

    if normalized_species is null or normalized_species = '' then
        raise exception 'Pet species must not be blank'
            using errcode = '22023';
    end if;

    if normalized_breed = '' then
        raise exception 'Pet breed must not be blank when supplied'
            using errcode = '22023';
    end if;

    if normalized_sex = '' then
        raise exception 'Pet sex must not be blank when supplied'
            using errcode = '22023';
    end if;

    if normalized_microchip_identifier = '' then
        raise exception 'Pet microchip identifier must not be blank when supplied'
            using errcode = '22023';
    end if;

    if normalized_profile_image_reference = '' then
        raise exception 'Pet profile image reference must not be blank when supplied'
            using errcode = '22023';
    end if;

    if normalized_behavioral_safety_information = '' then
        raise exception 'Pet behavioral safety information must not be blank when supplied'
            using errcode = '22023';
    end if;

    if p_date_of_birth is not null
       and p_approximate_date_of_birth is not null then
        raise exception 'Exact and approximate Pet birth dates are mutually exclusive'
            using errcode = '22023';
    end if;

    operation_timestamp := clock_timestamp();

    insert into public.pets (
        name,
        species,
        breed,
        sex,
        date_of_birth,
        approximate_date_of_birth,
        microchip_identifier,
        profile_image_reference,
        behavioral_safety_information,
        created_at
    )
    values (
        normalized_name,
        normalized_species,
        normalized_breed,
        normalized_sex,
        p_date_of_birth,
        p_approximate_date_of_birth,
        normalized_microchip_identifier,
        normalized_profile_image_reference,
        normalized_behavioral_safety_information,
        operation_timestamp
    )
    returning id into created_pet_id;

    insert into public.guardianships (
        user_id,
        pet_id,
        effective_start
    )
    values (
        domain_user_id,
        created_pet_id,
        operation_timestamp
    );

    return created_pet_id;
end;
$$;

revoke all privileges
on function public.register_pet(
    text,
    text,
    text,
    text,
    date,
    date,
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute
on function public.register_pet(
    text,
    text,
    text,
    text,
    date,
    date,
    text,
    text,
    text
)
to authenticated;

create function public.create_guardianship_invitation(
    p_acting_user_id uuid,
    p_pet_id uuid,
    p_inviting_guardianship_id uuid,
    p_recipient_user_id uuid,
    p_recipient_email text,
    p_expires_at timestamptz,
    p_acceptance_secret_digest bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    inviting_guardianship_record public.guardianships%rowtype;
    normalized_recipient_email text;
    normalized_recipient_email_comparison text;
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
        raise exception 'Guardianship Invitation recipient email must not be blank'
            using errcode = '22023';
    end if;

    normalized_recipient_email_comparison := lower(
        normalized_recipient_email
    );

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Guardianship Invitation acceptance digest must be 32 bytes'
            using errcode = '22023';
    end if;

    perform 1
    from public.pets as pet
    where pet.id = p_pet_id
    for update;

    if not found then
        raise exception 'Pet does not exist'
            using errcode = '23503';
    end if;

    select guardianship.*
    into inviting_guardianship_record
    from public.guardianships as guardianship
    where guardianship.id = p_inviting_guardianship_id
    for update;

    if not found then
        raise exception 'Inviting Guardianship does not exist'
            using errcode = '23503';
    end if;

    operation_timestamp := clock_timestamp();

    if p_expires_at is null
       or not isfinite(p_expires_at)
       or p_expires_at <= operation_timestamp then
        raise exception 'Guardianship Invitation expiration must follow creation'
            using errcode = '22023';
    end if;

    if inviting_guardianship_record.user_id <> p_acting_user_id
       or inviting_guardianship_record.pet_id <> p_pet_id
       or inviting_guardianship_record.effective_start > operation_timestamp
       or inviting_guardianship_record.effective_end is not null then
        raise exception 'An active same-Pet Guardianship is required to create the Invitation'
            using errcode = '42501';
    end if;

    if p_recipient_user_id is not null then
        if not exists (
            select 1
            from public.users as recipient_user
            where recipient_user.id = p_recipient_user_id
        ) then
            raise exception 'Invitation recipient User does not exist'
                using errcode = '23503';
        end if;

        if exists (
            select 1
            from public.guardianships as guardianship
            where guardianship.pet_id = p_pet_id
              and guardianship.user_id = p_recipient_user_id
              and guardianship.effective_end is null
        ) then
            raise exception 'Recipient already has an active Guardianship for the Pet'
                using errcode = '23505';
        end if;
    end if;

    if exists (
        select 1
        from public.guardianship_invitations as invitation
        where invitation.pet_id = p_pet_id
          and invitation.revoked_at is null
          and invitation.expires_at > operation_timestamp
          and invitation.acceptance_secret_digest is not null
          and not exists (
              select 1
              from public.guardianships as resulting_guardianship
              where resulting_guardianship.originating_invitation_id =
                  invitation.id
          )
          and (
              (
                  p_recipient_user_id is not null
                  and invitation.recipient_user_id = p_recipient_user_id
              )
              or invitation.recipient_email_normalized =
                  normalized_recipient_email_comparison
          )
    ) then
        raise exception 'An equivalent pending Guardianship Invitation already exists'
            using errcode = '23505';
    end if;

    insert into public.guardianship_invitations (
        pet_id,
        inviting_guardianship_id,
        recipient_user_id,
        recipient_email,
        created_at,
        expires_at,
        acceptance_secret_digest
    )
    values (
        p_pet_id,
        p_inviting_guardianship_id,
        p_recipient_user_id,
        normalized_recipient_email,
        operation_timestamp,
        p_expires_at,
        p_acceptance_secret_digest
    )
    returning id into created_invitation_id;

    return created_invitation_id;
end;
$$;

revoke all privileges
on function public.create_guardianship_invitation(
    uuid,
    uuid,
    uuid,
    uuid,
    text,
    timestamptz,
    bytea
)
from public, anon, authenticated;

grant execute
on function public.create_guardianship_invitation(
    uuid,
    uuid,
    uuid,
    uuid,
    text,
    timestamptz,
    bytea
)
to service_role;

create function public.accept_guardianship_invitation(
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
    invitation_pet_id uuid;
    invitation_record public.guardianship_invitations%rowtype;
    operation_timestamp timestamptz;
    created_guardianship_id uuid;
begin
    if p_accepting_user_id is null then
        raise exception 'A trusted accepting domain User is required'
            using errcode = '28000';
    end if;

    if p_acceptance_secret_digest is null
       or octet_length(p_acceptance_secret_digest) <> 32 then
        raise exception 'Guardianship Invitation acceptance digest must be 32 bytes'
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

    select invitation.pet_id
    into invitation_pet_id
    from public.guardianship_invitations as invitation
    where invitation.id = p_invitation_id;

    if not found then
        raise exception 'Guardianship Invitation does not exist'
            using errcode = '23503';
    end if;

    perform 1
    from public.pets as pet
    where pet.id = invitation_pet_id
    for update;

    select invitation.*
    into invitation_record
    from public.guardianship_invitations as invitation
    where invitation.id = p_invitation_id
      and invitation.pet_id = invitation_pet_id
    for update;

    if not found then
        raise exception 'Guardianship Invitation does not exist for the expected Pet'
            using errcode = '23503';
    end if;

    operation_timestamp := clock_timestamp();

    if exists (
        select 1
        from public.guardianships as resulting_guardianship
        where resulting_guardianship.originating_invitation_id =
            p_invitation_id
    ) then
        raise exception 'Guardianship Invitation has already been accepted'
            using errcode = '23505';
    end if;

    if invitation_record.revoked_at is not null then
        raise exception 'Guardianship Invitation has been revoked'
            using errcode = '23514';
    end if;

    if operation_timestamp >= invitation_record.expires_at then
        raise exception 'Guardianship Invitation has expired'
            using errcode = '23514';
    end if;

    if invitation_record.acceptance_secret_digest is null
       or invitation_record.acceptance_secret_digest is distinct from
           p_acceptance_secret_digest then
        raise exception 'Guardianship Invitation recipient proof is invalid'
            using errcode = '42501';
    end if;

    if invitation_record.recipient_user_id is not null
       and invitation_record.recipient_user_id <> p_accepting_user_id then
        raise exception 'Guardianship Invitation is bound to another User'
            using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = invitation_record.pet_id
          and guardianship.user_id = p_accepting_user_id
          and guardianship.effective_end is null
    ) then
        raise exception 'User already has an active Guardianship for the Pet'
            using errcode = '23505';
    end if;

    insert into public.guardianships (
        user_id,
        pet_id,
        effective_start,
        originating_invitation_id
    )
    values (
        p_accepting_user_id,
        invitation_record.pet_id,
        operation_timestamp,
        p_invitation_id
    )
    returning id into created_guardianship_id;

    update public.guardianship_invitations
    set acceptance_secret_digest = null
    where id = p_invitation_id;

    return created_guardianship_id;
end;
$$;

revoke all privileges
on function public.accept_guardianship_invitation(uuid, uuid, bytea)
from public, anon, authenticated;

grant execute
on function public.accept_guardianship_invitation(uuid, uuid, bytea)
to service_role;

create function public.get_my_pets()
returns table (
    id uuid,
    name text,
    species text,
    breed text,
    sex text,
    date_of_birth date,
    approximate_date_of_birth date,
    microchip_identifier text,
    profile_image_reference text,
    behavioral_safety_information text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    domain_user_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication is required'
            using errcode = '28000';
    end if;

    domain_user_id := public.current_domain_user_id();

    if domain_user_id is null then
        raise exception 'No coherent domain User exists for the authenticated subject'
            using errcode = '28000';
    end if;

    return query
    select
        pet.id,
        pet.name,
        pet.species,
        pet.breed,
        pet.sex,
        pet.date_of_birth,
        pet.approximate_date_of_birth,
        pet.microchip_identifier,
        pet.profile_image_reference,
        pet.behavioral_safety_information,
        pet.created_at
    from public.pets as pet
    where exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = pet.id
          and guardianship.user_id = domain_user_id
          and guardianship.effective_end is null
    );
end;
$$;

revoke all privileges
on function public.get_my_pets()
from public, anon, authenticated;

grant execute
on function public.get_my_pets()
to authenticated;

commit;
