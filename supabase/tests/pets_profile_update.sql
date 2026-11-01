-- Regression suite for the SPEC-PET-005 (Update Pet Profile) backend
-- completion delivered in 20260906090000_pet_profile_update_completion.sql.
-- This is a completion of already-approved Pet/Guardianship functionality
-- (Slice 5), not new roadmap scope.
--
-- Run only against an isolated database with all source-controlled
-- migrations applied, through the completion migration above. All fixtures
-- and assertions are rolled back; nothing is retained. Superuser test
-- execution is used only to provision synthetic auth/domain identities and
-- to fabricate a historical (already-ended) Guardianship that no Phase 1
-- RPC can itself produce (see docs/decisions/ADR-003-temporal-guardianship-
-- foundation.md) and to inspect authoritative row state between calls made
-- as simulated authenticated actors.
begin;

-- ===========================================================================
-- Helpers
-- ===========================================================================

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
    if p_condition is distinct from true then raise exception '%', p_message; end if;
end;
$$;

create function pg_temp.assert_sqlstate(p_statement text, p_expected text)
returns void language plpgsql as $$
begin
    begin
        execute p_statement;
    exception when others then
        if sqlstate = p_expected then return; end if;
        raise exception 'Expected SQLSTATE %, received %: %', p_expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', p_expected;
end;
$$;

-- Builds the update_pet_profile(...) call text from typed arguments so
-- callers of assert_sqlstate never hand-quote SQL literals.
create function pg_temp.update_call_sql(
    p_pet_id uuid,
    p_expected_revision bigint,
    p_name text,
    p_species text,
    p_breed text,
    p_sex text,
    p_dob date,
    p_adob date,
    p_chip text,
    p_image text,
    p_behavior text
)
returns text language sql as $$
    select format(
        'select public.update_pet_profile(%L::uuid, %L::bigint, %L::text, %L::text, %L::text, %L::text, %L::date, %L::date, %L::text, %L::text, %L::text)',
        p_pet_id, p_expected_revision, p_name, p_species, p_breed, p_sex, p_dob, p_adob, p_chip, p_image, p_behavior
    )
$$;

-- Captures (sqlstate, message) of a failed update_pet_profile call without
-- aborting the enclosing transaction, so two failure shapes can be compared
-- for the non-disclosure requirement (nonexistent Pet vs. non-Guardian of an
-- existing Pet must be indistinguishable to the caller).
create function pg_temp.capture_update_error(
    p_pet_id uuid,
    p_expected_revision bigint,
    p_name text,
    p_species text,
    p_breed text,
    p_sex text,
    p_dob date,
    p_adob date,
    p_chip text,
    p_image text,
    p_behavior text,
    out o_sqlstate text,
    out o_message text
)
language plpgsql as $$
begin
    perform public.update_pet_profile(
        p_pet_id, p_expected_revision, p_name, p_species, p_breed, p_sex,
        p_dob, p_adob, p_chip, p_image, p_behavior
    );
    o_sqlstate := null;
    o_message := 'STATEMENT SUCCEEDED (expected failure)';
exception when others then
    o_sqlstate := sqlstate;
    o_message := sqlerrm;
end;
$$;

-- Cross-block scratch storage: do $$ ... $$ blocks each have their own
-- local variable scope, so ids captured while acting as one simulated actor
-- are handed to later blocks through this table instead.
create table pg_temp.fixture_ids (label text primary key, value uuid);
create table pg_temp.fixture_bigints (label text primary key, value bigint);

-- Postgres does not grant table privileges to PUBLIC by default (unlike
-- EXECUTE on functions), so the role-switched sections below need these
-- explicit grants to write into cross-block scratch storage while acting as
-- a simulated authenticated actor. Local to this rolled-back transaction.
grant select, insert, update on pg_temp.fixture_ids to authenticated;
grant select, insert, update on pg_temp.fixture_bigints to authenticated;

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- U1 registers Pet P1 (the real register_pet path) and is its first current
-- Guardian. U2 is added as a *second* current Guardian of P1 via a direct
-- insert (a plain INSERT never fires the update/delete-only immutability
-- triggers, and the deferred minimum-cardinality constraint trigger never
-- fires before this transaction's rollback, so no trigger bypass is
-- needed). U3 has an already-ended ("former") Guardianship of P1, fabricated
-- directly since no Phase 1 operation can produce Guardianship termination.
-- U4 has never guarded any pet. U5 registers an unrelated Pet P2, used only
-- so "existing Pet the caller doesn't guard" is a genuinely different case
-- from "Pet id that doesn't exist at all".

insert into auth.users (id, email, email_confirmed_at) values
    ('05000000-0000-4000-8000-000000000001', 'pet005-u1@example.test', clock_timestamp()),
    ('05000000-0000-4000-8000-000000000002', 'pet005-u2@example.test', clock_timestamp()),
    ('05000000-0000-4000-8000-000000000003', 'pet005-u3@example.test', clock_timestamp()),
    ('05000000-0000-4000-8000-000000000004', 'pet005-u4@example.test', clock_timestamp()),
    ('05000000-0000-4000-8000-000000000005', 'pet005-u5@example.test', clock_timestamp());

insert into pg_temp.fixture_ids (label, value)
select 'domain_' || right(provider_subject::text, 2), user_id
from public.user_authentication_identities
where provider_subject in (
    '05000000-0000-4000-8000-000000000001',
    '05000000-0000-4000-8000-000000000002',
    '05000000-0000-4000-8000-000000000003',
    '05000000-0000-4000-8000-000000000004',
    '05000000-0000-4000-8000-000000000005'
);

do $$
begin
    perform pg_temp.assert_true(
        (select count(*) from pg_temp.fixture_ids where label like 'domain_%') = 5,
        'handle_new_auth_user() provisioned exactly one domain User per synthetic auth User'
    );
end;
$$;

-- Act as U1: register P1 with every mutable field populated, so later
-- scenarios can exercise "change", "remove via null", and "leave untouched"
-- against real starting values.
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_ids (label, value)
select 'p1', public.register_pet(
    'Fixture Pet One', 'Dog', 'Labrador', 'Female',
    date '2020-05-10', null, '123456789012345',
    'pets/p1/photo.jpg', 'Nervous around loud noises.'
);

reset role;

-- U2: second current Guardian of P1, added directly (not via
-- register_pet, and not via the invitation flow — this fixture only needs
-- the *fact* of concurrent current Guardianship, not how it was reached).
insert into public.guardianships (user_id, pet_id, effective_start)
values (
    (select value from pg_temp.fixture_ids where label = 'domain_02'),
    (select value from pg_temp.fixture_ids where label = 'p1'),
    clock_timestamp() - interval '1 day'
);

-- U3: former Guardian of P1 — Guardianship already ended before this test
-- run, fabricated directly since ADR-003 confirms Phase 1 has no
-- Guardianship-termination operation at all.
insert into public.guardianships (user_id, pet_id, effective_start, effective_end)
values (
    (select value from pg_temp.fixture_ids where label = 'domain_03'),
    (select value from pg_temp.fixture_ids where label = 'p1'),
    clock_timestamp() - interval '30 days',
    clock_timestamp() - interval '15 days'
);

-- U5 registers an unrelated Pet P2 (U4 is a non-Guardian of this *existing*
-- Pet, distinct from a Pet id that doesn't exist at all).
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000005', true);
set local role authenticated;

insert into pg_temp.fixture_ids (label, value)
select 'p2', public.register_pet('Fixture Pet Two', 'Cat', null, null, null, null, null, null, null);

reset role;

-- Snapshot P1's Guardianship rows before any update_pet_profile call, to
-- prove at the end of the suite that update_pet_profile never touches
-- Guardianship state (scenario 17).
create table pg_temp.guardianship_snapshot as
select id, user_id, pet_id, effective_start, effective_end, originating_invitation_id
from public.guardianships
where pet_id = (select value from pg_temp.fixture_ids where label = 'p1')
order by id;

do $$
begin
    perform pg_temp.assert_true(
        (select count(*) from pg_temp.guardianship_snapshot) = 3,
        'Fixture P1 has exactly three Guardianships (U1 current, U2 current, U3 former) before any update_pet_profile call'
    );
    perform pg_temp.assert_true(
        (
            select profile_revision from public.pets
            where id = (select value from pg_temp.fixture_ids where label = 'p1')
        ) = 0,
        'Newly registered Pet starts at profile_revision 0'
    );
end;
$$;

-- ===========================================================================
-- Scenario 1 — current Guardian (U1, the registrant) update succeeds.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_1', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    0,
    'Fixture Pet One Updated', 'Dog', 'Labrador', 'Female',
    date '2020-05-10', null, '123456789012345',
    'pets/p1/photo.jpg', 'Nervous around loud noises.'
);

reset role;

do $$
begin
    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_1') = 1,
        'Scenario 1: material update by the registering current Guardian returns revision 1'
    );
    perform pg_temp.assert_true(
        (
            select name from public.pets
            where id = (select value from pg_temp.fixture_ids where label = 'p1')
        ) = 'Fixture Pet One Updated',
        'Scenario 1: the Pet row reflects the update'
    );
end;
$$;

-- ===========================================================================
-- Scenario 2 — another current Guardian (U2) sees the updated profile.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $$
declare
    seen_name text;
    seen_revision bigint;
begin
    select pet.name, pet.profile_revision into seen_name, seen_revision
    from public.get_my_pets() as pet
    where pet.id = (select value from pg_temp.fixture_ids where label = 'p1');

    perform pg_temp.assert_true(
        seen_name = 'Fixture Pet One Updated' and seen_revision = 1,
        'Scenario 2: a second current Guardian sees the update through get_my_pets()'
    );
end;
$$;

reset role;

-- ===========================================================================
-- Scenario 3 — a current Guardian who did not originally register the Pet
-- (U2) can update it.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000002', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_3', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    1,
    'Fixture Pet One Updated', 'Dog', 'Labrador', 'Female',
    date '2020-05-10', null, '123456789012345',
    'pets/p1/photo.jpg', 'Calmer now around loud noises.'
);

reset role;

do $$
begin
    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_3') = 2,
        'Scenario 3: a non-registering current Guardian can perform a material update'
    );
end;
$$;

-- ===========================================================================
-- Scenario 4 — a former Guardian (U3) is rejected.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000003', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 2,
        'Should Not Apply', 'Dog', 'Labrador', 'Female', date '2020-05-10', null,
        '123456789012345', 'pets/p1/photo.jpg', 'Calmer now around loud noises.'
    ),
    '42501'
);

reset role;

-- ===========================================================================
-- Scenario 5 — no resolvable authenticated subject is rejected (28000), and
-- separately, the anon role cannot even reach the function body (blocked at
-- the grant layer — exercised precisely as scenario 18's ACL check).
-- ===========================================================================
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 2,
        'Should Not Apply', 'Dog', 'Labrador', 'Female', date '2020-05-10', null,
        '123456789012345', 'pets/p1/photo.jpg', 'Calmer now around loud noises.'
    ),
    '28000'
);

reset role;

-- ===========================================================================
-- Scenario 6 — an authenticated non-Guardian (U4) is rejected.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000004', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 2,
        'Should Not Apply', 'Dog', 'Labrador', 'Female', date '2020-05-10', null,
        '123456789012345', 'pets/p1/photo.jpg', 'Calmer now around loud noises.'
    ),
    '42501'
);

reset role;

-- ===========================================================================
-- Scenario 7 — nonexistent Pet and an existing Pet the caller does not
-- guard must be indistinguishable (identical SQLSTATE and message), still
-- acting as U4.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000004', true);
set local role authenticated;

do $$
declare
    existing_state text;
    existing_message text;
    nonexistent_state text;
    nonexistent_message text;
begin
    select o_sqlstate, o_message into existing_state, existing_message
    from pg_temp.capture_update_error(
        (select value from pg_temp.fixture_ids where label = 'p2'), 0,
        'x', 'x', null, null, null, null, null, null, null
    );

    select o_sqlstate, o_message into nonexistent_state, nonexistent_message
    from pg_temp.capture_update_error(
        '00000000-0000-4000-8000-000000000000', 0,
        'x', 'x', null, null, null, null, null, null, null
    );

    perform pg_temp.assert_true(
        existing_state = '42501' and nonexistent_state = '42501',
        'Scenario 7: both a non-Guardian-of-an-existing-Pet call and a nonexistent-Pet call raise 42501'
    );
    perform pg_temp.assert_true(
        existing_message = nonexistent_message
        and existing_message = 'Current Guardianship of the Pet is required',
        'Scenario 7: nonexistent Pet and non-Guardian existing Pet produce an identical, non-disclosing message'
    );
end;
$$;

reset role;

-- ===========================================================================
-- Scenario 8 — direct table UPDATE remains denied; the Pet row is untouched.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    format(
        'update public.pets set name = %L where id = %L',
        'Hacked Directly', (select value from pg_temp.fixture_ids where label = 'p1')
    ),
    '42501'
);

reset role;

do $$
begin
    perform pg_temp.assert_true(
        (
            select name from public.pets
            where id = (select value from pg_temp.fixture_ids where label = 'p1')
        ) = 'Fixture Pet One Updated',
        'Scenario 8: the denied direct UPDATE left the Pet row unchanged'
    );
end;
$$;

-- ===========================================================================
-- Scenario 9 — required name/species cannot be blank.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 2,
        '   ', 'Dog', 'Labrador', 'Female', date '2020-05-10', null,
        '123456789012345', 'pets/p1/photo.jpg', 'Calmer now around loud noises.'
    ),
    '22023'
);

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 2,
        'Fixture Pet One Updated', '  ', 'Labrador', 'Female', date '2020-05-10', null,
        '123456789012345', 'pets/p1/photo.jpg', 'Calmer now around loud noises.'
    ),
    '22023'
);

reset role;

-- ===========================================================================
-- Scenario 10 — nullable text supports add / change / remove via null.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

-- Remove breed, microchip, image reference, and behavioral info.
insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_10a', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    2,
    'Fixture Pet One Updated', 'Dog', null, 'Female',
    date '2020-05-10', null, null, null, null
);

reset role;

do $$
declare
    pet_row public.pets%rowtype;
begin
    select * into pet_row from public.pets
    where id = (select value from pg_temp.fixture_ids where label = 'p1');

    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_10a') = 3,
        'Scenario 10a: removing nullable fields is a material change'
    );
    perform pg_temp.assert_true(
        pet_row.breed is null and pet_row.microchip_identifier is null
        and pet_row.profile_image_reference is null
        and pet_row.behavioral_safety_information is null,
        'Scenario 10a: nullable fields were removed'
    );
end;
$$;

-- Re-add/change them.
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_10b', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    3,
    'Fixture Pet One Updated', 'Dog', 'Poodle', 'Female',
    date '2020-05-10', null, '999999999999999', 'pets/p1/photo-2.jpg',
    'Friendly with other dogs.'
);

reset role;

do $$
declare
    pet_row public.pets%rowtype;
begin
    select * into pet_row from public.pets
    where id = (select value from pg_temp.fixture_ids where label = 'p1');

    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_10b') = 4,
        'Scenario 10b: re-adding nullable fields is a material change'
    );
    perform pg_temp.assert_true(
        pet_row.breed = 'Poodle' and pet_row.microchip_identifier = '999999999999999'
        and pet_row.profile_image_reference = 'pets/p1/photo-2.jpg'
        and pet_row.behavioral_safety_information = 'Friendly with other dogs.',
        'Scenario 10b: nullable fields were added/changed as submitted'
    );
end;
$$;

-- ===========================================================================
-- Scenario 11 — exact/approximate DOB are mutually exclusive.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 4,
        'Fixture Pet One Updated', 'Dog', 'Poodle', 'Female',
        date '2020-05-10', date '2020-05-10', '999999999999999',
        'pets/p1/photo-2.jpg', 'Friendly with other dogs.'
    ),
    '22023'
);

reset role;

-- ===========================================================================
-- Scenario 12 — a stale revision is rejected.
-- Scenario 13 — the failed stale update leaves prior values untouched.
-- Scenario 14 — a successful material update increments the revision by
-- exactly one.
-- ===========================================================================
insert into pg_temp.fixture_bigints (label, value)
select 'rev_before_stale', profile_revision from public.pets
where id = (select value from pg_temp.fixture_ids where label = 'p1');

select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_stale_setup', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    4,
    'Fixture Pet One Final', 'Dog', 'Poodle', 'Female',
    date '2020-05-10', null, '999999999999999',
    'pets/p1/photo-2.jpg', 'Friendly with other dogs.'
);

-- Reuse the now-stale revision 4 for a second attempt. Plain P0001 (not
-- 40001, and not PT409 either): PostgREST 14 automatically retries a
-- transaction that fails with 40001 on the assumption it's a transient
-- SERIALIZABLE conflict, and current Supabase JS client versions can
-- likewise auto-retry an HTTP 409 (PT409's mapped status) on an RPC POST —
-- but a stale expected-revision mismatch is deterministic and would fail
-- identically on every retry at either layer. See
-- 20260917120000_postgrest_conflict_status_correction.sql.
select pg_temp.assert_sqlstate(
    pg_temp.update_call_sql(
        (select value from pg_temp.fixture_ids where label = 'p1'), 4,
        'Should Not Apply', 'Dog', 'Poodle', 'Female', date '2020-05-10', null,
        '999999999999999', 'pets/p1/photo-2.jpg', 'Friendly with other dogs.'
    ),
    'P0001'
);

reset role;

do $$
declare
    pet_row public.pets%rowtype;
begin
    select * into pet_row from public.pets
    where id = (select value from pg_temp.fixture_ids where label = 'p1');

    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_before_stale') = 4
        and (select value from pg_temp.fixture_bigints where label = 'rev_after_stale_setup') = 5,
        'Scenario 14: the successful material update incremented the revision by exactly one (4 -> 5)'
    );
    perform pg_temp.assert_true(
        pet_row.profile_revision = 5,
        'Scenario 12: the rejected stale-revision call did not change the stored revision'
    );
    perform pg_temp.assert_true(
        pet_row.name = 'Fixture Pet One Final',
        'Scenario 13: the rejected stale-revision call left the prior successful values untouched, not the stale payload''s "Should Not Apply"'
    );
end;
$$;

-- ===========================================================================
-- Scenario 15 — a semantic no-op leaves the revision unchanged, even when
-- the resubmitted text needs re-trimming to match the stored (already
-- trimmed) value.
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_noop', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    5,
    '  Fixture Pet One Final  ', 'Dog', 'Poodle', 'Female',
    date '2020-05-10', null, '999999999999999',
    'pets/p1/photo-2.jpg', 'Friendly with other dogs.'
);

reset role;

do $$
begin
    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_noop') = 5,
        'Scenario 15: a semantic no-op (post-normalization) returns the unchanged current revision'
    );
    perform pg_temp.assert_true(
        (
            select profile_revision from public.pets
            where id = (select value from pg_temp.fixture_ids where label = 'p1')
        ) = 5,
        'Scenario 15: the stored revision was not incremented by the no-op call'
    );
end;
$$;

-- ===========================================================================
-- Scenario 16 — full-replacement semantics: changing only one field while
-- resending every other current value leaves those other values exactly as
-- submitted (not nulled, not otherwise altered).
-- ===========================================================================
select set_config('request.jwt.claim.sub', '05000000-0000-4000-8000-000000000001', true);
set local role authenticated;

insert into pg_temp.fixture_bigints (label, value)
select 'rev_after_16', public.update_pet_profile(
    (select value from pg_temp.fixture_ids where label = 'p1'),
    5,
    'Fixture Pet One Final', 'Dog', 'Poodle', 'Male',
    date '2020-05-10', null, '999999999999999',
    'pets/p1/photo-2.jpg', 'Friendly with other dogs.'
);

reset role;

do $$
declare
    pet_row public.pets%rowtype;
begin
    select * into pet_row from public.pets
    where id = (select value from pg_temp.fixture_ids where label = 'p1');

    perform pg_temp.assert_true(
        (select value from pg_temp.fixture_bigints where label = 'rev_after_16') = 6,
        'Scenario 16: changing exactly one field is a material change'
    );
    perform pg_temp.assert_true(
        pet_row.sex = 'Male',
        'Scenario 16: the one intentionally changed field was applied'
    );
    perform pg_temp.assert_true(
        pet_row.name = 'Fixture Pet One Final'
        and pet_row.species = 'Dog'
        and pet_row.breed = 'Poodle'
        and pet_row.date_of_birth = date '2020-05-10'
        and pet_row.approximate_date_of_birth is null
        and pet_row.microchip_identifier = '999999999999999'
        and pet_row.profile_image_reference = 'pets/p1/photo-2.jpg'
        and pet_row.behavioral_safety_information = 'Friendly with other dogs.',
        'Scenario 16: every resubmitted-but-unchanged field survived the full-replacement update exactly as submitted'
    );
end;
$$;

-- ===========================================================================
-- Scenario 17 — unrelated Guardianship facts for the Pet are unchanged by
-- any of the update_pet_profile calls above.
-- ===========================================================================
do $$
begin
    perform pg_temp.assert_true(
        not exists (
            select 1 from (
                select id, user_id, pet_id, effective_start, effective_end, originating_invitation_id
                from public.guardianships
                where pet_id = (select value from pg_temp.fixture_ids where label = 'p1')
                except
                select * from pg_temp.guardianship_snapshot
            ) as differences
        )
        and not exists (
            select 1 from (
                select * from pg_temp.guardianship_snapshot
                except
                select id, user_id, pet_id, effective_start, effective_end, originating_invitation_id
                from public.guardianships
                where pet_id = (select value from pg_temp.fixture_ids where label = 'p1')
            ) as differences
        ),
        'Scenario 17: P1''s Guardianship rows are byte-identical to the pre-test snapshot'
    );
end;
$$;

-- ===========================================================================
-- Scenario 18 — ACL / function grants are exact.
-- ===========================================================================
do $$
begin
    perform pg_temp.assert_true(
        has_function_privilege(
            'authenticated',
            'public.update_pet_profile(uuid, bigint, text, text, text, text, date, date, text, text, text)',
            'execute'
        ),
        'authenticated has EXECUTE on update_pet_profile'
    );
    perform pg_temp.assert_true(
        not has_function_privilege(
            'anon',
            'public.update_pet_profile(uuid, bigint, text, text, text, text, date, date, text, text, text)',
            'execute'
        ),
        'anon does not have EXECUTE on update_pet_profile'
    );
    perform pg_temp.assert_true(
        not has_function_privilege(
            'public',
            'public.update_pet_profile(uuid, bigint, text, text, text, text, date, date, text, text, text)',
            'execute'
        ),
        'the public pseudo-role does not have EXECUTE on update_pet_profile'
    );

    perform pg_temp.assert_true(
        has_function_privilege('authenticated', 'public.get_my_pets()', 'execute'),
        'authenticated has EXECUTE on the recreated get_my_pets()'
    );
    perform pg_temp.assert_true(
        not has_function_privilege('anon', 'public.get_my_pets()', 'execute'),
        'anon does not have EXECUTE on the recreated get_my_pets()'
    );
    perform pg_temp.assert_true(
        not has_function_privilege('public', 'public.get_my_pets()', 'execute'),
        'the public pseudo-role does not have EXECUTE on the recreated get_my_pets()'
    );
end;
$$;

do $$
begin
    raise notice 'pets_profile_update.sql: all assertions passed';
end;
$$;

rollback;
