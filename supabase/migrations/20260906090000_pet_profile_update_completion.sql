-- Completion of SPEC-PET-005 (Update Pet Profile), approved alongside
-- SPEC-PET-001/004 in 20260825170004_pet_and_guardianship.sql but never
-- given a backend implementation there. This is not new product scope: it
-- delivers exactly the already-approved Pet Profile update workflow that
-- Slice 5 left incomplete. No Specification or ADR changes accompany it.
begin;

alter table public.pets
add column profile_revision bigint not null default 0;

alter table public.pets
add constraint pets_profile_revision_check
    check (profile_revision >= 0);

-- get_my_pets() must be dropped, not CREATE OR REPLACE'd: PostgreSQL does
-- not allow CREATE OR REPLACE FUNCTION to change a RETURNS TABLE column
-- set in place. The projection below is otherwise byte-for-byte identical
-- to the original (same columns in the same order, same STABLE/SECURITY
-- DEFINER/search_path, same current-Guardianship scoping, same absence of
-- ORDER BY — no approved source requires ordering), with exactly one
-- addition: profile_revision, needed by update_pet_profile's optimistic
-- concurrency check below.
drop function public.get_my_pets();

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
    profile_revision bigint,
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
        pet.profile_revision,
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

-- update_pet_profile — SPEC-PET-005. Full-replacement update of every
-- mutable Pet Profile field (mirrors register_pet's own field list and
-- normalization rules exactly, including p_profile_image_reference, which
-- mobile does not currently expose for editing but which belongs in the
-- backend contract regardless — see the accompanying design report).
--
-- Authorization is current Guardianship of the Pet (BR-1/BR-3/BR-4),
-- re-verified here at execution time under row locks, not trusted from
-- whatever the caller believed when the request was constructed (BR-33/
-- BR-34 and the lost-authority race this completion pass was specifically
-- asked to close). Optimistic concurrency (p_expected_profile_revision)
-- protects BR-25 (concurrent updates must not silently lose unrelated
-- valid changes) using the same revision-counter idiom already established
-- by update_draft_clinical_record_entry's p_expected_draft_revision
-- (20260829120000_clinical_care.sql).
--
-- No email-verification precondition: SPEC-PET-005 section 2 lists no such
-- precondition (unlike SPEC-PET-001's explicit one for registration), and
-- no existing ongoing-resource mutation on an already-established
-- Guardian/Care relationship (grant_pet_care_authorization,
-- revoke_pet_care_authorization, update_draft_clinical_record_entry)
-- re-checks it either.
create function public.update_pet_profile(
    p_pet_id uuid,
    p_expected_profile_revision bigint,
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
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    authenticated_subject_id uuid;
    domain_user_id uuid;
    pet_record public.pets%rowtype;
    normalized_name text;
    normalized_species text;
    normalized_breed text;
    normalized_sex text;
    normalized_microchip_identifier text;
    normalized_profile_image_reference text;
    normalized_behavioral_safety_information text;
    new_profile_revision bigint;
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

    -- Pet locked before Guardianship: the same lock order already used by
    -- create_guardianship_invitation/accept_guardianship_invitation
    -- (20260825170004_pet_and_guardianship.sql), avoiding a deadlock-prone
    -- inverted order against those functions. A nonexistent Pet and an
    -- existing Pet the caller does not currently guard must not be
    -- distinguishable to the caller: both branches below raise the
    -- identical message and errcode, mirroring the non-disclosure
    -- precedent already established by grant_pet_care_authorization
    -- (20260829120000_clinical_care.sql).
    select pet.* into pet_record
    from public.pets as pet
    where pet.id = p_pet_id
    for update;

    if not found then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    -- Re-verified here, at execution time, under lock, inside the same
    -- transaction as the eventual write — never trusted from whatever the
    -- caller believed when the update was constructed. This is the check
    -- that must fail safely if a Guardianship that was current when the
    -- request was built is no longer current by the time this executes.
    if not exists (
        select 1
        from public.guardianships as guardianship
        where guardianship.pet_id = p_pet_id
          and guardianship.user_id = domain_user_id
          and guardianship.effective_start <= clock_timestamp()
          and guardianship.effective_end is null
        for update
    ) then
        raise exception 'Current Guardianship of the Pet is required'
            using errcode = '42501';
    end if;

    if pet_record.profile_revision <> p_expected_profile_revision then
        raise exception 'Stale Pet Profile revision'
            using errcode = '40001';
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

    -- Semantic no-op: every normalized value already matches the locked
    -- row. No UPDATE, no revision increment.
    if pet_record.name is not distinct from normalized_name
       and pet_record.species is not distinct from normalized_species
       and pet_record.breed is not distinct from normalized_breed
       and pet_record.sex is not distinct from normalized_sex
       and pet_record.date_of_birth is not distinct from p_date_of_birth
       and pet_record.approximate_date_of_birth is not distinct from
           p_approximate_date_of_birth
       and pet_record.microchip_identifier is not distinct from
           normalized_microchip_identifier
       and pet_record.profile_image_reference is not distinct from
           normalized_profile_image_reference
       and pet_record.behavioral_safety_information is not distinct from
           normalized_behavioral_safety_information
    then
        return pet_record.profile_revision;
    end if;

    new_profile_revision := pet_record.profile_revision + 1;

    update public.pets
    set name = normalized_name,
        species = normalized_species,
        breed = normalized_breed,
        sex = normalized_sex,
        date_of_birth = p_date_of_birth,
        approximate_date_of_birth = p_approximate_date_of_birth,
        microchip_identifier = normalized_microchip_identifier,
        profile_image_reference = normalized_profile_image_reference,
        behavioral_safety_information = normalized_behavioral_safety_information,
        profile_revision = new_profile_revision
    where id = p_pet_id;

    return new_profile_revision;
end;
$$;

revoke all privileges
on function public.update_pet_profile(
    uuid, bigint, text, text, text, text, date, date, text, text, text
)
from public, anon, authenticated;

grant execute
on function public.update_pet_profile(
    uuid, bigint, text, text, text, text, date, date, text, text, text
)
to authenticated;

commit;
