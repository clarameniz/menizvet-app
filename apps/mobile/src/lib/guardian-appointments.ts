import type { GuardianAppointment } from '@/data/guardian-appointments';
import type { TranslationKey } from '@/i18n/i18n';

/** A list row: the read's row plus its Clinic's published name, `null` when unavailable. */
export type GuardianAppointmentListItem<T extends GuardianAppointment = GuardianAppointment> = T & {
  clinicDisplayName: string | null;
};

/**
 * Attaches the published Clinic names (data/clinics.ts) to a page's rows. A
 * Clinic absent from `names` (unpublished, unknown) or a failed lookup
 * (`names` null) leaves `null`, shown as "Clinic unavailable" — exactly as
 * the Pet-scoped list did; no other Clinic surface is read.
 */
export function withClinicNames<T extends GuardianAppointment>(
  rows: readonly T[],
  names: ReadonlyMap<string, { displayName: string | null }> | null,
): GuardianAppointmentListItem<T>[] {
  return rows.map((row) => ({
    ...row,
    clinicDisplayName: names?.get(row.clinicId)?.displayName ?? null,
  }));
}

/**
 * A row's secondary tag (SPEC-APT-011 BR-40, SPEC-APT-019 §5): `proposal`
 * when the Guardian's answer to a Clinic proposal is due, `awaitingClinic`
 * when the Guardian already accepted the Clinic's alternative and the Clinic
 * has to confirm it. Never a lifecycle state; acting on either stays in the
 * detail.
 */
export type GuardianAppointmentRowTag = {
  kind: 'proposal' | 'awaitingClinic';
  labelKey: TranslationKey;
};

/**
 * The row's tags, in display order. A proposal tag only for an actionable
 * Clinic proposal — another time for a request (SPEC-APT-019), a new time for
 * a confirmed Appointment (SPEC-APT-006); a Guardian's own proposal waits for
 * the Clinic and gets none. The awaiting tag only when the backend reports it
 * (BR-37). Both are shown when both apply, the proposal first.
 */
export function guardianAppointmentRowTags(
  row: Pick<
    GuardianAppointment,
    'lifecycleState' | 'pendingProposalContext' | 'awaitingClinicConfirmation'
  >,
): GuardianAppointmentRowTag[] {
  const tags: GuardianAppointmentRowTag[] = [];
  if (row.pendingProposalContext === 'CLINIC' && row.lifecycleState === 'REQUESTED') {
    tags.push({ kind: 'proposal', labelKey: 'appointments.alternativeTimeProposedIndicator' });
  } else if (row.pendingProposalContext === 'CLINIC' && row.lifecycleState === 'CONFIRMED') {
    tags.push({ kind: 'proposal', labelKey: 'appointments.pendingRescheduleIndicator' });
  }
  if (row.awaitingClinicConfirmation) {
    tags.push({
      kind: 'awaitingClinic',
      labelKey: 'appointments.awaitingClinicConfirmationIndicator',
    });
  }
  return tags;
}

/**
 * The row's accessible name: what it shows, in reading order, with the full
 * date instead of the short one and the tags last.
 */
export function guardianAppointmentRowLabel(parts: {
  fullDate: string;
  time: string;
  petName: string;
  clinicLabel: string;
  lifecycleLabel: string;
  tagLabels: readonly string[];
}): string {
  return [
    parts.petName,
    parts.clinicLabel,
    parts.fullDate,
    parts.time,
    parts.lifecycleLabel,
    ...parts.tagLabels,
  ]
    .filter(Boolean)
    .join(', ');
}
