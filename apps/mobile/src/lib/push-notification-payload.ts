export type PushNavigationTarget = {
  screen: 'appointment';
  appointmentId: string;
  petId: string;
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function readValidUuid(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return UUID_PATTERN.test(trimmed) ? trimmed : null;
}

/**
 * Validates the exact Phase 1 push-navigation payload
 * (supabase/functions/_shared/communications/templates.ts::renderPush):
 * `{ route: 'appointment', appointment_id: <uuid>, pet_id: <uuid> }`.
 * `pet_id` (Milestone H push-navigation correction,
 * supabase/migrations/20260921170000_communications_push_navigation_pet_id.sql)
 * lets the mobile client navigate directly to the Guardian
 * appointment-detail route — which is Pet-scoped
 * (get_pet_appointments(pet_id)) — without a client-side fan-out lookup
 * across every currently-guarded Pet. Anything else — missing/blank/
 * malformed id, an unrecognized or future route, a non-object payload —
 * returns null rather than throwing. A malformed or unknown payload must
 * never crash notification handling, and this never builds a navigation
 * path from an untrusted string beyond the two validated ids
 * (SPEC-COM-002 BR-28/BR-29, SPEC-COM-003 BR-43/BR-44). Possession of these
 * ids still does not grant authorization: the Appointment-detail screen's
 * own fresh authoritative read (get_pet_appointments) re-verifies current
 * Guardianship server-side regardless of what this payload claims.
 */
export function parsePushNavigationTarget(data: unknown): PushNavigationTarget | null {
  if (typeof data !== 'object' || data === null) return null;

  const record = data as Record<string, unknown>;
  if (record.route !== 'appointment') return null;

  const appointmentId = readValidUuid(record, 'appointment_id');
  const petId = readValidUuid(record, 'pet_id');
  if (!appointmentId || !petId) return null;

  return { screen: 'appointment', appointmentId, petId };
}
