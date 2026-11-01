import { supabase } from '@/lib/supabase';

/**
 * Mirrors public.pets and the exact contracts in
 * supabase/migrations/20260825170004_pet_and_guardianship.sql,
 * supabase/migrations/20260906090000_pet_profile_update_completion.sql, and
 * supabase/migrations/20260917120000_postgrest_conflict_status_correction.sql,
 * verified directly against that SQL (not assumed from a prior summary):
 *
 * - get_my_pets() — granted to authenticated, returns every profile field
 *   (including profile_revision, added by the completion migration) for
 *   Pets under the caller's own current (effective_end is null)
 *   Guardianships. No ORDER BY, so no ordering guarantee — callers that
 *   want a stable display order must sort client-side themselves.
 * - register_pet(...) — granted to authenticated. Creates the Pet and its
 *   initial Guardianship atomically; requires a verified email
 *   (auth.users.email_confirmed_at) in addition to authentication.
 * - update_pet_profile(...) — granted to authenticated. Full-replacement
 *   update of every mutable Pet field, re-verifying current Guardianship at
 *   execution time (never trusting client-side authorization) and using
 *   optimistic concurrency via p_expected_profile_revision: a mismatch
 *   raises plain SQLSTATE P0001 ("Stale Pet Profile revision") — not the
 *   originally-shipped 40001 (PostgREST 14 automatically, and wastefully,
 *   retries any 40001 on the assumption it's a transient serialization
 *   conflict, which a deterministic stale-revision mismatch never is) and
 *   not the briefly-considered PT409 either (current Supabase JS client
 *   versions can themselves auto-retry an HTTP 409 response to an RPC
 *   POST, for the same reason). An absent/lost current Guardianship
 *   (including a nonexistent Pet, indistinguishably) raises 42501
 *   ("Current Guardianship of the Pet is required"). There is still no
 *   grant of any kind (select/insert/update) directly on public.pets — all
 *   access goes through these RPCs.
 *
 * profile_image_reference is read here (it's part of the row) and, for
 * update_pet_profile, must be round-tripped unchanged since it's a
 * full-replacement RPC — but it's still never exposed for editing or
 * rendered: it's a bare `text` column with no defined format, no Storage
 * bucket, and no approved mobile interpretation anywhere in the repository
 * (see SPEC-PET-001/004/005 and these migrations).
 */
export type Pet = {
  id: string;
  name: string;
  species: string;
  breed: string | null;
  sex: string | null;
  dateOfBirth: string | null;
  approximateDateOfBirth: string | null;
  microchipIdentifier: string | null;
  profileImageReference: string | null;
  behavioralSafetyInformation: string | null;
  profileRevision: number;
  createdAt: string;
};

export type PetsResult<T> = { data: T; error: null } | { data: null; error: string };

export type PetRow = {
  id: string;
  name: string;
  species: string;
  breed: string | null;
  sex: string | null;
  date_of_birth: string | null;
  approximate_date_of_birth: string | null;
  microchip_identifier: string | null;
  profile_image_reference: string | null;
  behavioral_safety_information: string | null;
  profile_revision: number;
  created_at: string;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as user-profile.ts's
// exported fromRow).
export function fromRow(row: PetRow): Pet {
  return {
    id: row.id,
    name: row.name,
    species: row.species,
    breed: row.breed,
    sex: row.sex,
    dateOfBirth: row.date_of_birth,
    approximateDateOfBirth: row.approximate_date_of_birth,
    microchipIdentifier: row.microchip_identifier,
    profileImageReference: row.profile_image_reference,
    behavioralSafetyInformation: row.behavioral_safety_information,
    profileRevision: row.profile_revision,
    createdAt: row.created_at,
  };
}

/**
 * Reads the caller's own Pets. Never accepts a user id: get_my_pets() scopes
 * to the caller's own current Guardianships server-side via
 * current_domain_user_id(), so there is nothing for a client parameter to
 * target even if one existed.
 */
export async function getMyPets(): Promise<PetsResult<Pet[]>> {
  const { data, error } = await supabase.rpc('get_my_pets');

  if (error) {
    return { data: null, error: error.message };
  }

  return { data: ((data ?? []) as PetRow[]).map(fromRow), error: null };
}

/**
 * Convenience read over the same approved get_my_pets() contract — not a
 * second read API. There is no single-Pet RPC in the backend; get_my_pets()
 * already returns full profile detail for every Pet the caller may see, so
 * this just finds the requested one in that same result. `data: null` (with
 * no error) means the id isn't among the caller's current Pets — e.g. no
 * such Pet, or the caller's Guardianship for it has ended.
 */
export async function getMyPetById(petId: string): Promise<PetsResult<Pet | null>> {
  const result = await getMyPets();

  if (result.error !== null) {
    return { data: null, error: result.error };
  }

  return { data: result.data.find((pet) => pet.id === petId) ?? null, error: null };
}

export type RegisterPetInput = {
  name: string;
  species: string;
  breed: string | null;
  sex: string | null;
  dateOfBirth: string | null;
  approximateDateOfBirth: string | null;
  microchipIdentifier: string | null;
  behavioralSafetyInformation: string | null;
};

/**
 * Calls only the approved register_pet RPC — never a manual insert into
 * pets/guardianships, which the trusted RPC establishes atomically. Callers
 * must pass null (not '') for an omitted optional field: the RPC treats an
 * empty string as an error ("must not be blank when supplied"), distinct
 * from omission.
 *
 * profile_image_reference is always sent as null — no approved mobile
 * mechanism exists to produce a value for it (see the module doc comment).
 *
 * Returns only the new Pet's id, matching the RPC's own return type exactly;
 * callers re-read via getMyPets()/getMyPetById() rather than this function
 * constructing a Pet from unvalidated client input (the RPC trims/normalizes
 * server-side).
 */
export async function registerPet(input: RegisterPetInput): Promise<PetsResult<{ id: string }>> {
  const { data, error } = await supabase.rpc('register_pet', {
    p_name: input.name,
    p_species: input.species,
    p_breed: input.breed,
    p_sex: input.sex,
    p_date_of_birth: input.dateOfBirth,
    p_approximate_date_of_birth: input.approximateDateOfBirth,
    p_microchip_identifier: input.microchipIdentifier,
    p_profile_image_reference: null,
    p_behavioral_safety_information: input.behavioralSafetyInformation,
  });

  if (error) {
    return { data: null, error: error.message };
  }

  return { data: { id: data as string }, error: null };
}

export type UpdatePetProfileInput = {
  id: string;
  expectedProfileRevision: number;
  name: string;
  species: string;
  breed: string | null;
  sex: string | null;
  dateOfBirth: string | null;
  approximateDateOfBirth: string | null;
  microchipIdentifier: string | null;
  profileImageReference: string | null;
  behavioralSafetyInformation: string | null;
};

/**
 * Calls only the approved update_pet_profile RPC — never a direct table
 * mutation, which remains denied to authenticated (no grant on public.pets;
 * see the module doc comment). This is a full-replacement operation: the
 * caller must submit every current mutable field, not only the ones the User
 * changed, including profileImageReference round-tripped byte-for-byte from
 * the Pet last read (mobile has no way to produce or edit that value yet).
 *
 * expectedProfileRevision must be the revision from the Pet data the edit
 * form was initialized from. A concurrent change elsewhere surfaces as the
 * RPC's SQLSTATE P0001 ("Stale Pet Profile revision"), mapped to a dedicated
 * product message by mapPetErrorToKey — never retried automatically and
 * never merged here.
 *
 * Returns only the new/current revision, matching the RPC's own return type;
 * callers re-read via getMyPets()/getMyPetById() rather than trusting the
 * submitted values as confirmed state.
 */
export async function updatePetProfile(
  input: UpdatePetProfileInput,
): Promise<PetsResult<{ profileRevision: number }>> {
  // supabase.rpc() is documented to resolve to {data, error} rather than
  // throw for ordinary Postgrest-level failures (including the P0001/42501
  // cases this RPC raises), but that is not a structural guarantee — a
  // transient network/fetch-level failure can still reject the underlying
  // promise. Without this try/catch, that rejection would propagate
  // uncaught to every caller, and a caller that only handles the resolved
  // {data, error} shape (as edit.tsx's submit handler does) would never run
  // its post-await cleanup, permanently stranding UI state such as a
  // loading flag. This function must always settle into the established
  // result shape, never reject.
  try {
    const { data, error } = await supabase.rpc('update_pet_profile', {
      p_pet_id: input.id,
      p_expected_profile_revision: input.expectedProfileRevision,
      p_name: input.name,
      p_species: input.species,
      p_breed: input.breed,
      p_sex: input.sex,
      p_date_of_birth: input.dateOfBirth,
      p_approximate_date_of_birth: input.approximateDateOfBirth,
      p_microchip_identifier: input.microchipIdentifier,
      p_profile_image_reference: input.profileImageReference,
      p_behavioral_safety_information: input.behavioralSafetyInformation,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    return { data: { profileRevision: data as number }, error: null };
  } catch (thrown) {
    // Never the raw thrown value's stack/details — just enough text for
    // mapPetErrorToKey to fall through to the generic localized message,
    // since this is not one of its known, mapped RPC error strings.
    return { data: null, error: thrown instanceof Error ? thrown.message : 'Unknown error' };
  }
}
