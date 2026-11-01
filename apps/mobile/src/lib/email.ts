/**
 * Matches the backend's own email-comparison normalization
 * (`lower(btrim(recipient_email, ...))`, see
 * supabase/migrations/20260825170004_pet_and_guardianship.sql), so a value
 * the user perceives as "the same email" behaves consistently on both sides.
 * This is a UX normalization only; it is not a security or uniqueness
 * boundary, which Supabase Auth enforces server-side regardless.
 */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}
