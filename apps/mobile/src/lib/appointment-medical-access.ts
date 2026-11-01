import type { MedicalAccessState, MedicalAccessWithdrawal } from '@/data/appointments';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * What the Guardian Appointment detail shows about medical access
 * (SPEC-ACC-002 §16 mobile presentation, SPEC-APT-011 BR-35). It depends on the
 * medical-access state alone, never on the Appointment lifecycle. Medical access
 * is the clinic's prior-history access (SPEC-MED-010 BR-14); completion ends it
 * (BR-16), so a COMPLETED Appointment shows nothing to manage.
 *
 * - `offerWithdrawal` — ACTIVE: the active status, a short explanation, and the
 *   secondary "Manage medical access" that opens the withdrawal panel;
 * - `withdrawn` — REVOKED: the calm "Medical access withdrawn" state;
 * - `none` — INACTIVE: access ended with the Appointment; nothing to manage.
 */
export type MedicalAccessView = 'offerWithdrawal' | 'withdrawn' | 'none';

export function medicalAccessView(state: MedicalAccessState): MedicalAccessView {
  if (state === 'ACTIVE') return 'offerWithdrawal';
  if (state === 'REVOKED') return 'withdrawn';
  return 'none';
}

/**
 * The consequences the management panel states before a withdrawal
 * (SPEC-ACC-002 §16, SPEC-MED-010 BR-12): the Appointment stays, prior history
 * closes, and the care the clinic actually provides can still be documented —
 * nothing is deleted. ACTIVE access exists only before completion, so there is
 * one wording.
 */
export function medicalAccessConsequenceKeys(): TranslationKey[] {
  return [
    'medicalAccess.consequenceStays',
    'medicalAccess.consequenceClinic',
    'medicalAccess.consequenceIrreversible',
  ];
}

export type MedicalAccessNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

/**
 * The message after a withdrawal attempt, decided by the authoritative re-read
 * first and the operation's own result only when the re-read is unavailable.
 * A REVOKED re-read needs no notice — the withdrawn state says it — whatever
 * the attempt returned, so a lost response or an exact retry is never shown as
 * an error. An INACTIVE re-read means cancellation, no-show or expiry ended the
 * access first.
 */
export function medicalAccessWithdrawalNotice(
  result: MedicalAccessWithdrawal,
  refreshedState: MedicalAccessState | null,
): MedicalAccessNotice | null {
  if (refreshedState === 'REVOKED') return null;
  if (refreshedState === 'INACTIVE') {
    return { tone: 'info', messageKey: 'medicalAccess.noLongerActive' };
  }
  switch (result.kind) {
    case 'withdrawn':
      return { tone: 'info', messageKey: 'medicalAccess.withdrawn' };
    case 'alreadyInactive':
      return { tone: 'info', messageKey: 'medicalAccess.noLongerActive' };
    case 'unavailable':
      return { tone: 'error', messageKey: 'medicalAccess.unavailable' };
    case 'authenticationRequired':
      return { tone: 'error', messageKey: 'errors.sessionExpired' };
    case 'failed':
      return { tone: 'error', messageKey: 'medicalAccess.failed' };
  }
}
