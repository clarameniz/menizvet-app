import type {
  AppointmentClinicalEntry,
  AppointmentClinicalRecord,
  ClinicalCreateResult,
  ClinicalDocumentationUnavailableReason,
  ClinicalEditResult,
  ClinicalEntryFields,
  ClinicalRecordRejection,
  ClinicalWriteFailure,
} from '@/data/appointment-clinical-record';
import type { ClinicalRecordEntryCategory } from '@/data/clinical-history';
import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure model of the professional Appointment clinical record (SPEC-MED-010
 * Part F). Everything here is advisory presentation: the client operations
 * re-validate every rule. No clinical time is asked for or sent — the server
 * records its own — and an Entry is shown in its current version.
 */

// The backend's btrim set: decides completeness and dirtiness only.
const trim = (value: string) => value.replace(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g, '');

// ---------------------------------------------------------------------------
// Record section
// ---------------------------------------------------------------------------

const UNAVAILABLE_KEYS: Record<ClinicalDocumentationUnavailableReason, TranslationKey> = {
  APPOINTMENT_STATE: 'clinicalRecord.unavailableAppointmentState',
  NO_VETERINARIAN_ASSIGNED: 'clinicalRecord.unavailableNoVeterinarian',
  NOT_ASSIGNED_VETERINARIAN: 'clinicalRecord.unavailableNotAssigned',
  CLINICAL_SERVICE_UNAVAILABLE: 'clinicalRecord.serviceUnavailable',
};

/** The single calm line shown instead of "Add record", or `null` when the reader can record. */
export function documentationUnavailableKey(
  record: AppointmentClinicalRecord,
): TranslationKey | null {
  if (record.canRecord) return null;
  return UNAVAILABLE_KEYS[record.unavailableReason ?? 'APPOINTMENT_STATE'];
}

/**
 * "Edit" — only on the reader's own Entry (`may_edit`, SPEC-MED-010 BR-18).
 * Advisory: the operation re-authorizes every save.
 */
export function canEditEntry(entry: AppointmentClinicalEntry): boolean {
  return entry.mayEdit;
}

/**
 * "Add a clarifying record" — only on another Veterinarian's Entry, and only
 * when the reader may record new Entries now (SPEC-MED-010 Part F). It opens
 * the ordinary new-record editor; the clarification carries no reference.
 */
export function canClarifyEntry(
  entry: AppointmentClinicalEntry,
  record: AppointmentClinicalRecord,
): boolean {
  return !entry.recordedByMe && record.canRecord;
}

/** "View changes" — only when earlier versions or historical corrections exist. */
export function hasEntryChanges(entry: {
  previousVersions: readonly unknown[];
  amendments: readonly unknown[];
}): boolean {
  return entry.previousVersions.length > 0 || entry.amendments.length > 0;
}

// ---------------------------------------------------------------------------
// Editor draft
// ---------------------------------------------------------------------------

export type ClinicalEntryDraft = {
  category: ClinicalRecordEntryCategory | null;
  content: string;
  otherContext: string;
};

/** A new Entry: nothing preselected (SPEC-MED-010 Part F). */
export const EMPTY_CLINICAL_ENTRY_DRAFT: ClinicalEntryDraft = {
  category: null,
  content: '',
  otherContext: '',
};

/** "Edit" opens the editor filled with the Entry's current version. */
export function draftFromEntry(entry: AppointmentClinicalEntry): ClinicalEntryDraft {
  return {
    category: entry.category,
    content: entry.clinicalContent,
    otherContext: entry.otherCategoryContext ?? '',
  };
}

export type ClinicalEntryField = 'category' | 'content' | 'otherContext';

export type EntryFieldsResult =
  | { kind: 'ok'; fields: ClinicalEntryFields }
  | { kind: 'issue'; field: ClinicalEntryField; messageKey: TranslationKey };

/**
 * The payload of a save, or the first missing field (advisory BR-5 check).
 * `OTHER` context is sent only with `OTHER`.
 */
export function entryFieldsFromDraft(draft: ClinicalEntryDraft): EntryFieldsResult {
  if (draft.category === null)
    return { kind: 'issue', field: 'category', messageKey: 'clinicalRecord.categoryRequired' };
  const other = trim(draft.otherContext);
  if (draft.category === 'OTHER' && other === '')
    return {
      kind: 'issue',
      field: 'otherContext',
      messageKey: 'clinicalRecord.otherContextRequired',
    };
  const content = trim(draft.content);
  if (content === '')
    return { kind: 'issue', field: 'content', messageKey: 'clinicalRecord.contentRequired' };
  return {
    kind: 'ok',
    fields: {
      category: draft.category,
      clinicalContent: content,
      otherCategoryContext: draft.category === 'OTHER' ? other : null,
    },
  };
}

/**
 * Whether leaving now would lose something the Veterinarian typed or chose:
 * anything at all in a new record, any difference from the version an edit
 * was opened on.
 */
export function isEntryDraftDirty(
  draft: ClinicalEntryDraft,
  initial: ClinicalEntryDraft = EMPTY_CLINICAL_ENTRY_DRAFT,
): boolean {
  return (
    draft.category !== initial.category ||
    trim(draft.content) !== trim(initial.content) ||
    (draft.category === 'OTHER' && trim(draft.otherContext) !== trim(initial.otherContext))
  );
}

function sameFields(
  entry: Pick<AppointmentClinicalEntry, 'category' | 'clinicalContent' | 'otherCategoryContext'>,
  fields: ClinicalEntryFields,
): boolean {
  return (
    entry.category === fields.category &&
    entry.clinicalContent === fields.clinicalContent &&
    entry.otherCategoryContext === fields.otherCategoryContext
  );
}

/**
 * How a lost save response is reconciled from the re-read: an Entry by the
 * reader, not in the record when the editor last saw it, with exactly these
 * fields.
 */
export function findSubmittedEntry(
  record: AppointmentClinicalRecord | null,
  fields: ClinicalEntryFields,
  knownEntryIds: ReadonlySet<string>,
): AppointmentClinicalEntry | null {
  return (
    record?.entries.find(
      (entry) =>
        entry.recordedByMe && !knownEntryIds.has(entry.entryId) && sameFields(entry, fields),
    ) ?? null
  );
}

/**
 * How a lost edit response is reconciled from the re-read: the Entry has a
 * version newer than the one the editor was opened on, and that current
 * version has exactly the submitted fields.
 */
export function isSubmittedEditCurrent(
  record: AppointmentClinicalRecord | null,
  entryId: string,
  openedVersion: number,
  fields: ClinicalEntryFields,
): boolean {
  const entry = record?.entries.find((candidate) => candidate.entryId === entryId);
  return entry !== undefined && entry.version > openedVersion && sameFields(entry, fields);
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

const REJECTION_KEYS: Record<ClinicalRecordRejection, TranslationKey> = {
  KEY_REQUIRED: 'clinicalRecord.invalidFields',
  CATEGORY_REQUIRED: 'clinicalRecord.categoryRequired',
  INVALID_CATEGORY: 'clinicalRecord.invalidFields',
  CONTENT_REQUIRED: 'clinicalRecord.contentRequired',
  OTHER_CONTEXT_REQUIRED: 'clinicalRecord.otherContextRequired',
  OTHER_CONTEXT_NOT_ALLOWED: 'clinicalRecord.invalidFields',
  KEY_CONFLICT: 'clinicalRecord.keyConflict',
  APPOINTMENT_STATE_INVALID: 'clinicalRecord.unavailableAppointmentState',
  NO_VETERINARIAN_ASSIGNED: 'clinicalRecord.unavailableNoVeterinarian',
  NOT_ASSIGNED_VETERINARIAN: 'clinicalRecord.unavailableNotAssigned',
  ENTRY_AUTHOR_REQUIRED: 'clinicalRecord.editAuthorOnly',
  INVALID_VERSION: 'clinicalRecord.invalidFields',
  STALE_VERSION: 'clinicalRecord.staleVersion',
};

export function clinicalRejectionKey(reason: ClinicalRecordRejection): TranslationKey {
  return REJECTION_KEYS[reason];
}

export type ClinicalNotice = { tone: 'info' | 'error'; messageKey: TranslationKey };

function failureNotice(
  result: Exclude<ClinicalWriteFailure, { kind: 'uncertain' }>,
  deniedKey: TranslationKey,
): ClinicalNotice {
  switch (result.kind) {
    case 'authenticationRequired':
      return { tone: 'error', messageKey: 'errors.sessionExpired' };
    case 'serviceUnavailable':
      return { tone: 'error', messageKey: 'clinicalRecord.serviceUnavailable' };
    case 'denied':
      return { tone: 'error', messageKey: deniedKey };
    case 'rejected':
      return { tone: 'error', messageKey: clinicalRejectionKey(result.reason) };
  }
}

/**
 * The outcome of "Save record" after the authoritative re-read. Saved when the
 * server says so, or when a lost response is shown by the re-read to have been
 * recorded; otherwise the editor keeps the text, and an uncertain answer may
 * be resubmitted with the same key.
 */
export type EntrySaveOutcome = { kind: 'saved' } | { kind: 'kept'; notice: ClinicalNotice };

export function entrySaveOutcome(
  result: ClinicalCreateResult,
  submitted: AppointmentClinicalEntry | null,
): EntrySaveOutcome {
  if (result.kind === 'outcome') return { kind: 'saved' };
  if (result.kind === 'uncertain')
    return submitted !== null
      ? { kind: 'saved' }
      : { kind: 'kept', notice: { tone: 'error', messageKey: 'clinicalRecord.unconfirmedSave' } };
  return { kind: 'kept', notice: failureNotice(result, 'clinicalRecord.saveDenied') };
}

/**
 * The outcome of "Save changes" after the authoritative re-read. `stale`: the
 * Entry changed since the editor opened — the text stays and the newer
 * version is shown before anything else is saved. A lost response confirmed
 * by the re-read is saved; otherwise a retry reuses the same key.
 */
export type EditSaveOutcome =
  | { kind: 'saved'; notice: ClinicalNotice }
  | { kind: 'stale' }
  | { kind: 'kept'; notice: ClinicalNotice };

export function editSaveOutcome(
  result: ClinicalEditResult,
  confirmedByReRead: boolean,
): EditSaveOutcome {
  if (result.kind === 'outcome')
    return {
      kind: 'saved',
      notice: {
        tone: 'info',
        messageKey:
          result.outcome === 'UNCHANGED'
            ? 'clinicalRecord.noChanges'
            : 'clinicalRecord.changesSaved',
      },
    };
  if (result.kind === 'uncertain')
    return confirmedByReRead
      ? { kind: 'saved', notice: { tone: 'info', messageKey: 'clinicalRecord.changesSaved' } }
      : { kind: 'kept', notice: { tone: 'error', messageKey: 'clinicalRecord.unconfirmedEdit' } };
  if (result.kind === 'rejected' && result.reason === 'STALE_VERSION') return { kind: 'stale' };
  return { kind: 'kept', notice: failureNotice(result, 'clinicalRecord.editDenied') };
}

/**
 * Whether a rejected save means the assignment changed under the editor
 * (SPEC-MED-010 Part F): the client then re-reads who has the Appointment.
 */
export function isAssignmentRejection(result: ClinicalCreateResult): boolean {
  return (
    result.kind === 'rejected' &&
    (result.reason === 'NOT_ASSIGNED_VETERINARIAN' || result.reason === 'NO_VETERINARIAN_ASSIGNED')
  );
}
