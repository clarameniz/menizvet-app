import type {
  ClinicalRecordEntryCategory,
  GuardianMedicalHistoryAccess,
  GuardianMedicalHistoryCursor,
  GuardianMedicalHistoryEntry,
} from '@/data/clinical-history';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure presentation helpers for the Guardian medical-history screen
 * (pets/[id]/medical-history.tsx) and its entry card — kept out of the route
 * component so pagination/category/attachment decisions are unit-testable
 * without component-rendering test infrastructure, which this repo does not
 * have (see AGENTS.md's testing conventions).
 */

const CATEGORY_LABEL_KEYS: Record<ClinicalRecordEntryCategory, TranslationKey> = {
  EXAMINATION: 'clinicalHistory.categoryExamination',
  DIAGNOSIS: 'clinicalHistory.categoryDiagnosis',
  TREATMENT: 'clinicalHistory.categoryTreatment',
  PROCEDURE: 'clinicalHistory.categoryProcedure',
  VACCINATION: 'clinicalHistory.categoryVaccination',
  PRESCRIPTION: 'clinicalHistory.categoryPrescription',
  LABORATORY_RESULT: 'clinicalHistory.categoryLaboratoryResult',
  IMAGING_RESULT: 'clinicalHistory.categoryImagingResult',
  CLINICAL_NOTE: 'clinicalHistory.categoryClinicalNote',
  OTHER: 'clinicalHistory.categoryOther',
};

/**
 * The localized-label i18n key for a clinical event category — the raw
 * backend enum value must never be shown directly (same rationale as
 * lib/appointment-lifecycle.ts's lifecycleLabelKey). A Draft may exist
 * without a category, but view_guardian_pet_medical_history only ever
 * returns FINALIZED Entries, which always have one — `null` is handled here
 * defensively rather than assumed impossible.
 */
export function categoryLabelKey(category: ClinicalRecordEntryCategory | null): TranslationKey {
  return category === null ? 'clinicalHistory.categoryUnknown' : CATEGORY_LABEL_KEYS[category];
}

/** `originalFilename` when the Attachment has one, otherwise a generic label. */
export function resolveAttachmentLabel(
  originalFilename: string | null,
  genericLabel: string,
): string {
  return originalFilename ?? genericLabel;
}

/** Whole kilobytes, rounded, with a floor of 1 KB so a small PDF never displays as "0 KB". */
export function formatAttachmentSizeKb(trustedByteSize: number): number {
  return Math.max(1, Math.round(trustedByteSize / 1024));
}

/**
 * Device-local date/time display for a clinical timestamp. Unlike Appointment
 * scheduling times (SPEC-APT-013 BR-47/53, CONVENTIONS.md §8: the device
 * timezone must never become the authoritative interpretation of a confirmed
 * Appointment time), these are plain informational instants with no
 * associated Clinic scheduling timezone in this payload — there is no
 * authoritative zone to prefer over the device's own, and SPEC-MED-005 §4
 * leaves the exact visual presentation to the UI.
 */
export function formatClinicalInstant(isoInstant: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(isoInstant));
}

export type HistoryPageState = {
  entries: GuardianMedicalHistoryEntry[];
  cursor: GuardianMedicalHistoryCursor | null;
};

/**
 * Appends a newly-fetched page after the entries already on screen, in
 * server order, and adopts the new page's own cursor verbatim (never
 * reconstructed) — `null` means no further page, so a caller checking
 * `.cursor === null` after this knows to stop offering "Load more". An Entry
 * already shown is never appended a second time: the one on screen stays.
 */
export function appendHistoryPage(
  current: HistoryPageState,
  next: HistoryPageState,
): HistoryPageState {
  const shown = new Set(current.entries.map((entry) => entry.id));
  return {
    entries: [...current.entries, ...next.entries.filter((entry) => !shown.has(entry.id))],
    cursor: next.cursor,
  };
}

export type HistoryLoadOutcome = { kind: 'denied' } | ({ kind: 'loaded' } & HistoryPageState);

/**
 * Distinguishes the RPC's typed DENIED domain state (no current Guardianship,
 * or the Pet doesn't exist — see data/clinical-history.ts) from a normal
 * loaded page, which may itself legitimately have zero entries (empty
 * history is valid, SPEC-MED-005 BR-35) — that is never confused with
 * `denied` here.
 */
export function deriveHistoryLoadOutcome(access: GuardianMedicalHistoryAccess): HistoryLoadOutcome {
  if (access.status === 'DENIED') return { kind: 'denied' };
  return { kind: 'loaded', entries: access.page.entries, cursor: access.page.cursor };
}
