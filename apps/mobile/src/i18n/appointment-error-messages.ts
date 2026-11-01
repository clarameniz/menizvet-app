import type { TranslationKey } from '@/i18n/i18n';

/**
 * request_appointment / reschedule_requested_appointment / cancel_appointment
 * raise plain Postgres exceptions with a coarse, reused SQLSTATE per function
 * (e.g. 23514/22023 each cover several unrelated business-rule checks in the
 * same RPC — see
 * supabase/migrations/20260826163000_appointment_schema_and_scheduling_history.sql
 * and supabase/migrations/20260827090000_care_authorization_and_appointment_cancellation.sql,
 * and the final cancel_appointment/get_pet_appointments definitions in
 * supabase/migrations/20260829120000_clinical_care.sql), so — matching the
 * precedent established by i18n/pet-error-messages.ts — this matches on the
 * stable, hand-authored raised message text instead.
 *
 * 'current guardianship' is intentionally a single broad substring: the four
 * RPCs that can raise it word the message slightly differently ("Current
 * Guardianship of the Pet is required" / "...of the Appointment Pet is
 * required" / "Current Guardianship or applicable Clinic schedule-view
 * capability is required"), and all of them mean the same thing to a
 * Guardian — they no longer have current access to manage this Pet.
 *
 * Entitlement denial (APPOINTMENT_MANAGEMENT missing, SPEC-APT-001 BR-28) is
 * mapped to its own dedicated, calm message — an expected commercial state
 * for the target Clinic, not an infrastructure failure — per the approved
 * Milestone F review.
 *
 * 'no currently configured standard appointment duration' (SPEC-APT-001
 * BR-31 / SPEC-APT-004 BR-24, added by the Slice 16 Guardian
 * requestable-times enhancement) is deliberately its own distinct message,
 * not folded into `timeUnavailable`: it means the Clinic itself is not yet
 * ready to accept any request through this workflow, independent of which
 * time was chosen, whereas `timeUnavailable` means that specific time is no
 * longer free. A stale/no-longer-available candidate selected from
 * getRequestableAppointmentStartTimes surfaces as an ordinary
 * `timeUnavailable` (or, for a reschedule no-op, `sameTimeReschedule`) —
 * both already covered by the existing substrings below, since
 * request_appointment/reschedule_requested_appointment re-validate through
 * the exact same Availability check regardless of how the candidate was
 * chosen.
 */
const KNOWN_MESSAGE_SUBSTRINGS: readonly { substring: string; key: TranslationKey }[] = [
  {
    substring: 'the acting user must satisfy account verification requirements',
    key: 'errors.emailNotConfirmed',
  },
  { substring: 'authentication is required', key: 'errors.sessionExpired' },
  { substring: 'no coherent domain user exists', key: 'errors.sessionExpired' },
  {
    substring: 'applicable professional entitlement is required',
    key: 'appointmentErrors.entitlementDenied',
  },
  { substring: 'current guardianship', key: 'appointmentErrors.lostGuardianship' },
  {
    substring: 'appointment requests require a published clinic',
    key: 'appointmentErrors.clinicNotPublished',
  },
  {
    substring: 'clinic appointment availability does not cover the',
    key: 'appointmentErrors.timeUnavailable',
  },
  {
    substring: 'no currently configured standard appointment duration',
    key: 'appointmentErrors.noStandardDuration',
  },
  { substring: 'must be in the future', key: 'appointmentErrors.notFuture' },
  {
    substring: 'do not identify a valid occurrence of local civil time',
    key: 'appointmentErrors.invalidCivilTime',
  },
  {
    substring: 'rescheduled time must differ from the current requested time',
    key: 'appointmentErrors.sameTimeReschedule',
  },
  {
    substring: 'appointment request requires a reason for visit',
    key: 'appointmentErrors.missingReason',
  },
  {
    substring: 'only a requested appointment may be rescheduled',
    key: 'appointmentErrors.lifecycleChanged',
  },
  {
    substring: 'only a requested or confirmed appointment may be cancelled',
    key: 'appointmentErrors.lifecycleChanged',
  },
  {
    substring: 'appointment with clinical documentation cannot be cancelled',
    key: 'appointmentErrors.lifecycleChanged',
  },
  // SPEC-APT-001 BR-35: another current pending request already exists for
  // this Pet at this Clinic (possibly created by another Guardian).
  {
    substring: 'a pending appointment request already exists for this pet at this clinic',
    key: 'appointmentErrors.duplicatePendingRequest',
  },
  // SPEC-APT-003 BR-23 / SPEC-APT-004 BR-27: stale-screen fallbacks — the UI
  // already hides both actions once the requested start has passed, so these
  // only explain a backend rejection; nothing is relabelled EXPIRED locally.
  {
    substring: 'whose requested time has passed cannot be cancelled',
    key: 'appointmentErrors.lapsedRequestCancel',
  },
  {
    substring: 'whose requested time has passed cannot be rescheduled',
    key: 'appointmentErrors.lapsedRequestReschedule',
  },
  // SPEC-APT-003 BR-31: the backend closed Guardian cancellation of a
  // CONFIRMED Appointment because its confirmed start has been reached — the
  // device clock still offered Cancel. Calm and specific; never retried.
  {
    substring: 'cannot cancel a confirmed appointment whose confirmed start has been reached',
    key: 'appointmentErrors.confirmedStartReachedCancel',
  },
];

export function mapAppointmentErrorToKey(message: string): TranslationKey {
  const lowerMessage = message.toLowerCase();

  for (const { substring, key } of KNOWN_MESSAGE_SUBSTRINGS) {
    if (lowerMessage.includes(substring)) {
      return key;
    }
  }

  return 'common.genericError';
}
