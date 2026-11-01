import { supabase } from '@/lib/supabase';

/**
 * Mirrors public.user_profiles (supabase/migrations/20260824115532_identity_foundation.sql).
 * avatar_reference is intentionally not exposed for editing anywhere in this
 * module's callers: it is a bare `text` column with no defined format, no
 * Storage bucket, no upload path, and no ADR/Spec describing a mobile-safe
 * mechanism for it (SPEC-ID-006 leaves the exact avatar mechanism
 * unspecified). It is still read here so a future, explicitly approved
 * milestone can wire it up without another backend round trip added later.
 */
export type UserProfile = {
  userId: string;
  displayName: string | null;
  avatarReference: string | null;
};

export type ProfileResult<T> = { data: T; error: null } | { data: null; error: string };

export type ProfileRow = {
  user_id: string;
  display_name: string | null;
  avatar_reference: string | null;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface, so testing it directly (rather than only
// indirectly through the async Supabase-backed functions below, which would
// require mocking the whole client) is a justified exception, not exposing
// an internal solely for tests' sake.
export function fromRow(row: ProfileRow): UserProfile {
  return {
    userId: row.user_id,
    displayName: row.display_name,
    avatarReference: row.avatar_reference,
  };
}

/**
 * Reads the caller's own profile. Never accepts a user id: the table's RLS
 * policies (user_profiles_select_own) already scope every row to
 * current_domain_user_id(), derived server-side from auth.uid(), so a bare
 * select can only ever return this caller's own row.
 *
 * handle_new_auth_user() (same migration) only creates public.users and
 * public.user_authentication_identities on sign-up — never a user_profiles
 * row — so { data: null, error: null } (no row yet) is an expected, normal
 * outcome here, not an error condition.
 */
export async function getCurrentUserProfile(): Promise<ProfileResult<UserProfile | null>> {
  const { data, error } = await supabase
    .from('user_profiles')
    .select('user_id, display_name, avatar_reference')
    .maybeSingle();

  if (error) {
    return { data: null, error: error.message };
  }

  return { data: data ? fromRow(data as ProfileRow) : null, error: null };
}

/**
 * Creates the caller's profile row if it does not exist yet, or updates
 * display_name if it does. Pass null to clear display_name (SPEC-ID-006 BR-9
 * /BR-10 treat it as optional, removable information — an empty value is a
 * valid state, not an invalid submission).
 *
 * avatar_reference is never included in the upsert payload, so Postgres's
 * ON CONFLICT DO UPDATE only SETs display_name — an existing avatar
 * reference is left untouched either way (SPEC-ID-006 BR-28: updating one
 * field must not silently clear another).
 *
 * user_id is required by the table (no column default) but is never accepted
 * from a caller of this function — it is read from the already-approved
 * current_domain_user_id() RPC, i.e. the caller's own id, never an arbitrary
 * target. RLS's own WITH CHECK still independently enforces this.
 */
export async function saveDisplayName(
  displayName: string | null,
): Promise<ProfileResult<UserProfile>> {
  const { data: userId, error: idError } = await supabase.rpc('current_domain_user_id');

  if (idError || !userId) {
    return { data: null, error: idError?.message ?? 'No se pudo identificar al usuario.' };
  }

  const { data, error } = await supabase
    .from('user_profiles')
    .upsert({ user_id: userId, display_name: displayName }, { onConflict: 'user_id' })
    .select('user_id, display_name, avatar_reference')
    .single();

  if (error) {
    return { data: null, error: error.message };
  }

  return { data: fromRow(data as ProfileRow), error: null };
}
