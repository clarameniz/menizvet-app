-- Corrective migration: manually-raised SQLSTATE 40001
-- ('serialization_failure') causes PostgREST 14 to automatically retry the
-- failing transaction, on the assumption 40001 always means a genuine
-- SERIALIZABLE-isolation conflict, which is transient and can legitimately
-- succeed on retry with the exact same statement and parameters. This
-- project never runs any transaction at SERIALIZABLE isolation (confirmed:
-- no db-tx-isolation-level override in supabase/config.toml, and no
-- function anywhere sets a SERIALIZABLE isolation level explicitly), so
-- Postgres itself can never generate a genuine 40001 here — every 40001
-- this system could ever produce is one of the manually-raised ones below,
-- and PostgREST's retry-on-40001 behavior is never appropriate for any of
-- them.
--
-- A first pass at this correction (superseded before ever being deployed)
-- replaced the deterministic write-path cases with SQLSTATE 'PT409'
-- (PostgREST's documented "PTxyz -> HTTP xyz" convention, i.e. HTTP 409
-- Conflict) instead of 40001. That is insufficient on its own: current
-- Supabase JS client versions can themselves automatically retry an HTTP
-- 409 response to a PostgREST RPC POST, for the same reason PostgREST
-- retries 40001 — 409 is conventionally treated as a possibly-transient
-- conflict worth one more attempt. A deterministic optimistic-concurrency
-- mismatch (the caller's p_expected_*_revision no longer matches the
-- current row) is not transient at either layer: retrying the identical
-- request, with the identical stale revision the caller already sent, will
-- deterministically fail again every time, at PostgREST's layer or the
-- client's. This migration instead uses plain, ordinary
-- `raise exception '<message>'` with no special errcode override, which
-- defaults to SQLSTATE P0001 ('raise_exception') — PostgREST maps this to
-- an ordinary HTTP 400 Bad Request, a status neither PostgREST nor
-- supabase-js treats as retry-worthy.
--
-- This pass also re-audits every manually-raised 40001 by transitive
-- reachability through the complete client call graph, not only by
-- checking each raising function's own grants directly. A helper function
-- with no grant of its own is still client-reachable if some other,
-- authenticated/anon-granted function calls it without an intervening
-- EXCEPTION block — the inner exception propagates unchanged to whichever
-- PostgREST-exposed function was actually invoked. That re-audit found two
-- more reachable occurrences beyond the three already identified (Pet
-- Profile and both Clinical Draft Entry write paths), neither previously
-- caught because each looked unreachable when checked only for its own
-- direct grant:
--
--   - revoke_care_authorization_after_guardianship_lock(...) has no grant
--     of its own (revoked from public/anon/authenticated with no
--     compensating grant), but is called, with no exception handling in
--     between, by TWO separately-granted authenticated RPCs:
--     revoke_pet_care_authorization(...) and
--     revoke_appointment_care_authorization(...)
--     (both in 20260829120000_clinical_care.sql). Its 'Care Authorization
--     Pet changed during revocation' 40001 is therefore reachable through
--     either call path.
--   - view_clinical_record_entry(uuid)'s original body (in
--     20260829120000_clinical_care.sql) was renamed to
--     slice12_view_clinical_record_entry(uuid) by
--     20260831120000_clinical_attachments.sql, which revoked all privileges
--     on the renamed function and created a new, thin
--     view_clinical_record_entry(uuid) wrapper (a plain SQL function, which
--     cannot itself catch exceptions) granted to authenticated. Its
--     'Clinical resource changed during exact Entry access' 40001 is
--     therefore still reachable, transitively, through that wrapper.
--
-- Complete inventory and disposition of every manually-raised 40001 across
-- all migrations:
--
--   1. update_pet_profile(...) [20260906090000]: 'Stale Pet Profile
--      revision'. Deterministic client-input revision mismatch, granted
--      directly to authenticated. CORRECTED -> plain P0001 below.
--   2. update_draft_clinical_record_entry(...) [20260829120000]: 'Stale
--      Draft revision'. Deterministic client-input revision mismatch,
--      granted directly to authenticated. CORRECTED -> plain P0001 below.
--   3. finalize_clinical_record_entry(...), active body from
--      20260831120000 (superseding the original 20260829120000 definition
--      via CREATE OR REPLACE, same signature): 'Stale Draft revision'.
--      Deterministic client-input revision mismatch, granted directly to
--      authenticated. CORRECTED -> plain P0001 below (the already-
--      superseded original definition in 20260829120000_clinical_care.sql
--      is dead code and is not, and cannot be, edited here).
--   4. revoke_care_authorization_after_guardianship_lock(...)
--      [20260829120000]: 'Care Authorization Pet changed during
--      revocation'. Reachable transitively (see above) through two
--      authenticated RPCs. The guarded condition
--      (care_authorizations.pet_id changing after being read) cannot
--      actually occur — enforce_care_authorization_immutability()
--      (20260827090000_care_authorization_and_appointment_cancellation.sql)
--      already blocks any UPDATE that changes pet_id — so this is a
--      defensive assertion against a schema-enforced invariant, not an
--      ordinary business-rule violation. This project's own convention for
--      "this should never happen" assertions (used extensively, e.g.
--      20260825170004_pet_and_guardianship.sql's minimum-cardinality
--      trigger) is SQLSTATE 55000 ('object_not_in_prerequisite_state'), not
--      P0001. CORRECTED -> 55000 below, for consistency with that
--      convention.
--   5. slice12_view_clinical_record_entry(uuid) (renamed from
--      view_clinical_record_entry, 20260829120000, renamed by 20260831120000):
--      'Clinical resource changed during exact Entry access'. Reachable
--      transitively (see above) through the view_clinical_record_entry
--      wrapper. This is a read-only re-verification with no client-supplied
--      expected-revision input, unlike (1)-(3); it is still corrected here
--      because it is a manually-raised 40001 reachable through an
--      authenticated PostgREST RPC, which is unsafe regardless of whether
--      the specific condition is deterministic client-input staleness or a
--      read-time consistency recheck: PostgREST/supabase-js retry logic
--      does not and cannot distinguish the two, and this project has no
--      genuine SERIALIZABLE-generated 40001 to protect either way.
--      CORRECTED -> plain P0001 below.
--
-- No authorization, locking order, optimistic-concurrency comparison,
-- revision-increment, or retry/backoff behavior changes anywhere in this
-- migration, for any of the five functions. Only the SQLSTATE each raises
-- changes; every human-readable message is preserved unchanged (mobile's
-- mapPetErrorToKey and the SQL regression suite both match on message
-- text, not SQLSTATE, so nothing downstream of the message text changes).
begin;

-- update_pet_profile — SPEC-PET-005. Body copied verbatim from
-- 20260906090000_pet_profile_update_completion.sql except for the single
-- errcode change on the stale-revision check (40001 -> plain P0001, i.e.
-- errcode omitted, PL/pgSQL's default for a bare RAISE EXCEPTION).
create or replace function public.update_pet_profile(
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

    -- Deterministic client-input mismatch: retrying this exact request
    -- with the same stale p_expected_profile_revision can never succeed,
    -- so this must not carry a SQLSTATE that triggers automatic retry at
    -- PostgREST or the client. Plain RAISE EXCEPTION defaults to P0001.
    if pet_record.profile_revision <> p_expected_profile_revision then
        raise exception 'Stale Pet Profile revision';
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

-- update_draft_clinical_record_entry — body copied verbatim from
-- 20260829120000_clinical_care.sql except for the single errcode change on
-- the stale-revision check (40001 -> plain P0001).
create or replace function public.update_draft_clinical_record_entry(
    p_entry_id uuid,
    p_expected_draft_revision bigint,
    p_clinical_content text,
    p_category text,
    p_other_category_context text,
    p_clinical_event_at timestamptz
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    normalized_content text;
    normalized_other_context text;
    operation_timestamp timestamptz;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;

    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then raise exception 'Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;

    select * into professional_context
    from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id for update;

    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care Draft update requires the existing Care Authorization to remain ACTIVE'
            using errcode = '42501';
    end if;

    if record_entry.lifecycle_state <> 'DRAFT' then raise exception 'Only a DRAFT Entry may be updated' using errcode = '23514'; end if;
    if record_entry.draft_revision <> p_expected_draft_revision then raise exception 'Stale Draft revision'; end if;
    normalized_content := nullif(btrim(p_clinical_content, E' \t\n\r\f\013'), '');
    normalized_other_context := nullif(btrim(p_other_category_context, E' \t\n\r\f\013'), '');

    if record_entry.clinical_content is not distinct from normalized_content
       and record_entry.category is not distinct from p_category
       and record_entry.other_category_context is not distinct from normalized_other_context
       and record_entry.clinical_event_at is not distinct from p_clinical_event_at then
        return record_entry.draft_revision;
    end if;

    operation_timestamp := clock_timestamp();
    update public.clinical_record_entries
    set clinical_content = normalized_content, category = p_category,
        other_category_context = normalized_other_context,
        clinical_event_at = p_clinical_event_at,
        draft_revision = record_entry.draft_revision + 1,
        last_modified_at = operation_timestamp
    where id = p_entry_id;

    if professional_context.veterinarian_clinic_assignment_id is distinct from
       record_entry.creator_veterinarian_clinic_assignment_id then
        insert into public.clinical_record_entry_contributors (
            clinical_record_entry_id, veterinarian_clinic_assignment_id, first_contributed_at
        ) values (
            p_entry_id, professional_context.veterinarian_clinic_assignment_id, operation_timestamp
        ) on conflict do nothing;
    end if;
    return record_entry.draft_revision + 1;
end;
$$;

revoke all privileges on function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz)
from public, anon, authenticated;
grant execute on function public.update_draft_clinical_record_entry(uuid, bigint, text, text, text, timestamptz) to authenticated;

-- finalize_clinical_record_entry — body copied verbatim from the currently
-- active definition (20260831120000_clinical_attachments.sql's replacement,
-- which added the Attachment-state checks) except for the single errcode
-- change on the stale-revision check (40001 -> plain P0001).
create or replace function public.finalize_clinical_record_entry(
    p_entry_id uuid,
    p_expected_draft_revision bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    attachment_record public.clinical_attachments%rowtype;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then raise exception 'Clinical Record Entry does not exist' using errcode = '23503'; end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select * into professional_context from public.resolve_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id for update;
    select encounter_row.* into encounter_record
    from public.clinical_encounters as encounter_row
    where encounter_row.id = encounter_record.id for update;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id for update;
    for attachment_record in
        select attachment.* from public.clinical_attachments as attachment
        where attachment.clinical_record_entry_id = p_entry_id and attachment.removed_at is null
        order by attachment.id for update
    loop
        if attachment_record.validation_state = 'PENDING' then
            raise exception 'A Clinical Record Entry with a current PENDING Attachment cannot be finalized'
                using errcode = '23514';
        end if;
        if attachment_record.validation_state = 'AVAILABLE' and not exists (
            select 1 from storage.objects as object_record
            where object_record.bucket_id = 'clinical-attachments'
              and object_record.name = 'v1/' || attachment_record.storage_object_id::text
        ) then
            raise exception 'A current AVAILABLE Attachment is missing its Storage object'
                using errcode = '23514';
        end if;
    end loop;
    if encounter_record.lifecycle_state = 'CONCLUDED'
       and care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Post-care finalization requires the existing Care Authorization to remain ACTIVE'
            using errcode = '42501';
    end if;
    if record_entry.lifecycle_state <> 'DRAFT' then raise exception 'Only a DRAFT Entry may be finalized' using errcode = '23514'; end if;
    if record_entry.draft_revision <> p_expected_draft_revision then raise exception 'Stale Draft revision'; end if;
    if record_entry.clinical_content is null or record_entry.category is null
       or (record_entry.category = 'OTHER' and record_entry.other_category_context is null) then
        raise exception 'Clinical Record Entry is not finalizable' using errcode = '23514';
    end if;
    update public.clinical_record_entries
    set lifecycle_state = 'FINALIZED', finalized_at = clock_timestamp(),
        finalized_by_user_id = acting_user_id,
        finalizer_veterinarian_clinic_assignment_id = professional_context.veterinarian_clinic_assignment_id
    where id = p_entry_id;
    return p_entry_id;
end;
$$;

revoke all privileges on function public.finalize_clinical_record_entry(uuid, bigint)
from public, anon, authenticated;
grant execute on function public.finalize_clinical_record_entry(uuid, bigint) to authenticated;

-- revoke_care_authorization_after_guardianship_lock — body copied verbatim
-- from 20260829120000_clinical_care.sql except for the single errcode
-- change (40001 -> 55000, this project's existing convention for a
-- defensive "this should never happen" assertion against a
-- schema-enforced invariant — see enforce_care_authorization_immutability()
-- in 20260827090000_care_authorization_and_appointment_cancellation.sql,
-- which already prevents care_authorizations.pet_id from ever changing).
-- No grant statement follows: this function has never had, and still does
-- not have, any direct grant to any role — it remains reachable only
-- indirectly, through revoke_pet_care_authorization(...) and
-- revoke_appointment_care_authorization(...), both already granted to
-- authenticated and both unchanged by this migration.
create or replace function public.revoke_care_authorization_after_guardianship_lock(
    p_care_authorization_id uuid,
    p_acting_user_id uuid,
    p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_pet_id uuid;
    care_auth_record public.care_authorizations%rowtype;
    normalized_reason text;
begin
    select care_auth.pet_id into target_pet_id
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id;
    if not found then
        raise exception 'Care Authorization does not exist' using errcode = '23503';
    end if;

    perform 1 from public.guardianships as guardianship
    where guardianship.pet_id = target_pet_id
      and guardianship.user_id = p_acting_user_id
      and guardianship.effective_start <= clock_timestamp()
      and guardianship.effective_end is null
    for update;
    if not found then
        raise exception 'Current Guardianship of the Pet is required' using errcode = '42501';
    end if;

    select care_auth.* into care_auth_record
    from public.care_authorizations as care_auth
    where care_auth.id = p_care_authorization_id
    for update;
    if care_auth_record.pet_id is distinct from target_pet_id then
        raise exception 'Care Authorization Pet changed during revocation' using errcode = '55000';
    end if;
    if care_auth_record.lifecycle_state <> 'ACTIVE' then
        raise exception 'Only an ACTIVE Care Authorization may be revoked' using errcode = '23514';
    end if;

    normalized_reason := nullif(btrim(p_reason, E' \t\n\r\f\013'), '');
    update public.care_authorizations
    set lifecycle_state = 'REVOKED',
        revoked_at = clock_timestamp(),
        revoking_user_id = p_acting_user_id,
        revocation_reason = normalized_reason
    where id = p_care_authorization_id;
    return p_care_authorization_id;
end;
$$;

revoke all privileges
on function public.revoke_care_authorization_after_guardianship_lock(uuid, uuid, text)
from public, anon, authenticated;

-- slice12_view_clinical_record_entry — body copied verbatim from
-- view_clinical_record_entry(uuid)'s original definition in
-- 20260829120000_clinical_care.sql (before 20260831120000_clinical_attachments.sql
-- renamed it to this name and replaced the client-facing
-- view_clinical_record_entry(uuid) with a thin wrapper), except for the
-- single errcode change (40001 -> plain P0001). No grant statement follows:
-- this function has never had, and still does not have, any direct grant
-- to any role since the rename — it remains reachable only indirectly,
-- through the unchanged view_clinical_record_entry(uuid) wrapper, already
-- granted to authenticated.
create or replace function public.slice12_view_clinical_record_entry(p_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    acting_user_id uuid;
    record_entry public.clinical_record_entries%rowtype;
    encounter_record public.clinical_encounters%rowtype;
    care_auth_record public.care_authorizations%rowtype;
    professional_context record;
    normal_entitlement boolean := false;
    permitted boolean := false;
    professional_context_available boolean := false;
    entry_payload jsonb;
begin
    if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
    acting_user_id := public.current_domain_user_id();
    if acting_user_id is null then raise exception 'No coherent domain User exists' using errcode = '28000'; end if;
    select record_entry_row.* into record_entry from public.clinical_record_entries as record_entry_row
    where record_entry_row.id = p_entry_id;
    if not found then return jsonb_build_object('status', 'DENIED'); end if;
    select encounter_row.* into encounter_record from public.clinical_encounters as encounter_row
    where encounter_row.id = record_entry.clinical_encounter_id;
    select care_auth.* into care_auth_record from public.care_authorizations as care_auth
    where care_auth.id = encounter_record.care_authorization_id;

    select * into professional_context
    from public.find_current_veterinarian_context_after_lock(
        acting_user_id, encounter_record.clinic_id, 'CLINICAL_DOCUMENTATION', null
    );
    professional_context_available := found;
    if professional_context_available then
        select care_auth.* into care_auth_record
        from public.care_authorizations as care_auth
        where care_auth.id = encounter_record.care_authorization_id
        for share;
        select encounter_row.* into encounter_record
        from public.clinical_encounters as encounter_row
        where encounter_row.id = record_entry.clinical_encounter_id
          and encounter_row.care_authorization_id = care_auth_record.id
        for share;
        select record_entry_row.* into record_entry
        from public.clinical_record_entries as record_entry_row
        where record_entry_row.id = p_entry_id
          and record_entry_row.clinical_encounter_id = encounter_record.id
        for share;
        if not found then
            raise exception 'Clinical resource changed during exact Entry access';
        end if;
        normal_entitlement := public.organization_has_professional_entitlement(
            professional_context.organization_id, 'CLINICAL_DOCUMENTATION'
        );
        permitted := (
            care_auth_record.lifecycle_state = 'ACTIVE' and normal_entitlement
        ) or encounter_record.lifecycle_state = 'ACTIVE'
          or (
              encounter_record.lifecycle_state = 'CONCLUDED'
              and care_auth_record.lifecycle_state = 'ACTIVE'
          );
    end if;

    if not permitted then
        perform public.establish_medical_access_audit_event(
            acting_user_id, encounter_record.pet_id, 'VIEW_CLINICAL_RECORD_ENTRY', 'DENIED',
            'PROFESSIONAL_CLINICAL', 'CLINICAL_RECORD_ENTRY', clock_timestamp(),
            null, care_auth_record.id, encounter_record.clinic_id, encounter_record.organization_id,
            encounter_record.appointment_id,
            case when professional_context_available then professional_context.organization_membership_id else null end,
            case when professional_context_available then professional_context.organization_responsibility_grant_id else null end,
            case when professional_context_available then professional_context.veterinarian_clinic_assignment_id else null end,
            encounter_record.id, record_entry.id, null
        );
        return jsonb_build_object('status', 'DENIED');
    end if;

    select jsonb_build_object(
        'id', record_entry.id,
        'clinical_encounter_id', record_entry.clinical_encounter_id,
        'lifecycle_state', record_entry.lifecycle_state,
        'clinical_content', record_entry.clinical_content,
        'category', record_entry.category,
        'other_category_context', record_entry.other_category_context,
        'clinical_event_at', record_entry.clinical_event_at,
        'draft_revision', record_entry.draft_revision,
        'created_at', record_entry.created_at,
        'last_modified_at', record_entry.last_modified_at,
        'created_by_user_id', record_entry.created_by_user_id,
        'creator_veterinarian_clinic_assignment_id', record_entry.creator_veterinarian_clinic_assignment_id,
        'finalized_at', record_entry.finalized_at,
        'finalized_by_user_id', record_entry.finalized_by_user_id,
        'finalizer_veterinarian_clinic_assignment_id', record_entry.finalizer_veterinarian_clinic_assignment_id,
        'encounter', jsonb_build_object(
            'pet_id', encounter_record.pet_id, 'clinic_id', encounter_record.clinic_id,
            'organization_id', encounter_record.organization_id,
            'responsible_veterinarian_clinic_assignment_id', encounter_record.responsible_veterinarian_clinic_assignment_id,
            'started_at', encounter_record.started_at, 'lifecycle_state', encounter_record.lifecycle_state,
            'concluded_at', encounter_record.concluded_at
        ),
        'contributors', coalesce((select jsonb_agg(jsonb_build_object(
            'veterinarian_clinic_assignment_id', contributor.veterinarian_clinic_assignment_id,
            'first_contributed_at', contributor.first_contributed_at
        ) order by contributor.first_contributed_at, contributor.veterinarian_clinic_assignment_id)
        from (
            select contributor_source.*
            from public.clinical_record_entry_contributors as contributor_source
            where contributor_source.clinical_record_entry_id = record_entry.id
            order by contributor_source.first_contributed_at,
                     contributor_source.veterinarian_clinic_assignment_id
            limit 100
        ) as contributor), '[]'::jsonb),
        'contributor_count', (
            select count(*) from public.clinical_record_entry_contributors as contributor_count_source
            where contributor_count_source.clinical_record_entry_id = record_entry.id
        ),
        'contributors_truncated', (
            select count(*) > 100 from public.clinical_record_entry_contributors as contributor_count_source
            where contributor_count_source.clinical_record_entry_id = record_entry.id
        ),
        'amendments', case when record_entry.lifecycle_state = 'FINALIZED' then coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', clinical_amendment.id, 'reason', clinical_amendment.reason,
                'amendment_content', clinical_amendment.amendment_content,
                'amending_user_id', clinical_amendment.amending_user_id,
                'amending_veterinarian_clinic_assignment_id', clinical_amendment.amending_veterinarian_clinic_assignment_id,
                'created_at', clinical_amendment.created_at
            ) order by clinical_amendment.created_at, clinical_amendment.id)
            from (
                select amendment_source.*
                from public.clinical_amendments as amendment_source
                where amendment_source.original_clinical_record_entry_id = record_entry.id
                order by amendment_source.created_at, amendment_source.id
                limit 100
            ) as clinical_amendment
        ), '[]'::jsonb) else '[]'::jsonb end,
        'amendment_count', (
            select count(*) from public.clinical_amendments as amendment_count_source
            where amendment_count_source.original_clinical_record_entry_id = record_entry.id
        ),
        'amendments_truncated', (
            select count(*) > 100 from public.clinical_amendments as amendment_count_source
            where amendment_count_source.original_clinical_record_entry_id = record_entry.id
        )
    ) into entry_payload;

    perform public.establish_medical_access_audit_event(
        acting_user_id, encounter_record.pet_id, 'VIEW_CLINICAL_RECORD_ENTRY', 'PERMITTED',
        'PROFESSIONAL_CLINICAL', 'CLINICAL_RECORD_ENTRY', clock_timestamp(),
        null, care_auth_record.id, encounter_record.clinic_id, encounter_record.organization_id,
        encounter_record.appointment_id, professional_context.organization_membership_id,
        professional_context.organization_responsibility_grant_id,
        professional_context.veterinarian_clinic_assignment_id,
        encounter_record.id, record_entry.id, null
    );
    return jsonb_build_object('status', 'PERMITTED', 'payload', entry_payload);
end;
$$;

revoke all privileges on function public.slice12_view_clinical_record_entry(uuid)
from public, anon, authenticated;

commit;
