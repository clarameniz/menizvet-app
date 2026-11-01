import type { ClinicalRecordEntryCategory } from '@/data/clinical-history';
import {
  CLINICAL_ENTRY_CATEGORIES,
  isClinicalEntryCategory,
  isVersionNumber,
  parsePreviousVersions,
  type ClinicalEntryVersion,
} from '@/data/clinical-entry-versions';
import { supabase } from '@/lib/supabase';

/**
 * Appointment-owned clinical documentation: the Appointment-keyed client
 * contract (supabase/migrations/20261116090000_editable_clinical_record_versions.sql;
 * SPEC-MED-010 BR-18, BR-20, BR-23, BR-23b, BR-24). Every call is keyed by the
 * Clinic and Appointment the professional Appointment detail shows; the server
 * derives the Pet and the acting Veterinarian context. No Care Authorization,
 * User, or Clinic Assignment identifier is ever sent or received, and no
 * clinical time is sent: the server records its own. Clinical content is never
 * logged and never stored on the device.
 *
 * No function here throws or retries. A write without a trustworthy answer
 * is `uncertain`: the caller re-reads the clinical record and may resubmit the
 * same intent only with the same idempotency key.
 */

/** The SPEC-MED-006 Phase 1 taxonomy, in presentation order. No default is implied. */
export const CLINICAL_RECORD_CATEGORIES = CLINICAL_ENTRY_CATEGORIES;

/** Why the reader cannot record a new Entry now (SPEC-MED-010 BR-20), first applicable. */
export const CLINICAL_DOCUMENTATION_UNAVAILABLE_REASONS = [
  'APPOINTMENT_STATE',
  'NO_VETERINARIAN_ASSIGNED',
  'NOT_ASSIGNED_VETERINARIAN',
  'CLINICAL_SERVICE_UNAVAILABLE',
] as const;
export type ClinicalDocumentationUnavailableReason =
  (typeof CLINICAL_DOCUMENTATION_UNAVAILABLE_REASONS)[number];

/**
 * A reason-and-addition correction recorded before Entries became editable
 * (SPEC-MED-010 BR-18, kind ADDENDUM). Read only: none can be added any more.
 * Authorship is only relative to the reader.
 */
export type AppointmentClinicalAmendment = {
  amendmentId: string;
  reason: string;
  amendmentContent: string;
  createdAt: string;
  amendedByMe: boolean;
};

/** One recorded Entry of the Appointment, shown in its current version (BR-20). */
export type AppointmentClinicalEntry = {
  entryId: string;
  /** The current version's fields. */
  category: ClinicalRecordEntryCategory;
  otherCategoryContext: string | null;
  clinicalContent: string;
  /** Only on Entries recorded before stage M5; never shown as the record's date. */
  clinicalEventAt: string | null;
  /** When the Entry was recorded: its one date, unchanged by edits. */
  recordedAt: string;
  recordedByMe: boolean;
  /** The reader is the Entry's author (BR-18): "Edit". Advisory. */
  mayEdit: boolean;
  /** The current version: 1 until the first edit. */
  version: number;
  /** When the current version was saved; `null` for an Entry never edited. */
  editedAt: string | null;
  /** Every earlier version, oldest first. */
  previousVersions: ClinicalEntryVersion[];
  previousVersionsTruncated: boolean;
  /** Historical reason-and-addition corrections, oldest first. */
  amendments: AppointmentClinicalAmendment[];
  amendmentsTruncated: boolean;
};

export type AppointmentClinicalRecord = {
  appointmentId: string;
  appointmentLifecycleState: string;
  /** Advisory: every write re-validates. */
  canRecord: boolean;
  unavailableReason: ClinicalDocumentationUnavailableReason | null;
  /** Oldest first by recording time, at most 100. */
  entries: AppointmentClinicalEntry[];
  entriesTruncated: boolean;
};

export type AppointmentClinicalRecordRead =
  | { kind: 'permitted'; record: AppointmentClinicalRecord }
  | { kind: 'denied' }
  | { kind: 'authenticationRequired' }
  | { kind: 'failed' };

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
const isId = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);
const isTimestamp = (value: unknown): value is string =>
  typeof value === 'string' && TIMESTAMP.test(value);
const isText = (value: unknown): value is string =>
  typeof value === 'string' && value.trim() !== '';
const isNullableText = (value: unknown): value is string | null => value === null || isText(value);
const isUnavailableReason = (value: unknown): value is ClinicalDocumentationUnavailableReason =>
  typeof value === 'string' &&
  (CLINICAL_DOCUMENTATION_UNAVAILABLE_REASONS as readonly string[]).includes(value);

function parseAmendment(raw: unknown): AppointmentClinicalAmendment | null {
  if (!isRecord(raw)) return null;
  const { amendment_id, reason, amendment_content, created_at, amended_by_me } = raw;
  if (
    !isId(amendment_id) ||
    !isText(reason) ||
    !isText(amendment_content) ||
    !isTimestamp(created_at) ||
    typeof amended_by_me !== 'boolean'
  )
    return null;
  return {
    amendmentId: amendment_id,
    reason,
    amendmentContent: amendment_content,
    createdAt: created_at,
    amendedByMe: amended_by_me,
  };
}

function parseAmendments(raw: unknown): AppointmentClinicalAmendment[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed: AppointmentClinicalAmendment[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const amendment = parseAmendment(item);
    if (amendment === null || seen.has(amendment.amendmentId)) return null;
    seen.add(amendment.amendmentId);
    parsed.push(amendment);
  }
  return parsed;
}

function parseEntry(raw: unknown): AppointmentClinicalEntry | null {
  if (!isRecord(raw)) return null;
  const {
    entry_id,
    category,
    other_category_context,
    clinical_content,
    clinical_event_at,
    recorded_at,
    recorded_by_me,
    may_edit,
    version,
    edited_at,
    previous_versions_truncated,
    amendments_truncated,
  } = raw;
  if (!isVersionNumber(version) || typeof previous_versions_truncated !== 'boolean') return null;
  // An edit time exactly when the Entry has been edited.
  let editedAt: string | null = null;
  if (version > 1) {
    if (!isTimestamp(edited_at)) return null;
    editedAt = edited_at;
  } else if (edited_at !== null) return null;
  const previousVersions = parsePreviousVersions(
    raw.previous_versions,
    version,
    previous_versions_truncated,
  );
  const amendments = parseAmendments(raw.amendments);
  if (
    previousVersions === null ||
    amendments === null ||
    typeof amendments_truncated !== 'boolean' ||
    !isId(entry_id) ||
    !isClinicalEntryCategory(category) ||
    !isNullableText(other_category_context) ||
    !isText(clinical_content) ||
    !(clinical_event_at === null || isTimestamp(clinical_event_at)) ||
    !isTimestamp(recorded_at) ||
    typeof recorded_by_me !== 'boolean' ||
    typeof may_edit !== 'boolean'
  )
    return null;
  return {
    entryId: entry_id,
    category,
    otherCategoryContext: other_category_context,
    clinicalContent: clinical_content,
    clinicalEventAt: clinical_event_at,
    recordedAt: recorded_at,
    recordedByMe: recorded_by_me,
    mayEdit: may_edit,
    version,
    editedAt,
    previousVersions,
    previousVersionsTruncated: previous_versions_truncated,
    amendments,
    amendmentsTruncated: amendments_truncated,
  };
}

/**
 * Exported for unit testing. `null` = malformed; a denial is its own typed
 * state, never mixed with a payload.
 */
export function parseAppointmentClinicalRecord(
  raw: unknown,
): { kind: 'permitted'; record: AppointmentClinicalRecord } | { kind: 'denied' } | null {
  if (!isRecord(raw)) return null;
  if (raw.status === 'DENIED') return { kind: 'denied' };
  if (
    raw.status !== 'PERMITTED' ||
    !isRecord(raw.appointment) ||
    !isRecord(raw.documentation) ||
    !Array.isArray(raw.entries) ||
    typeof raw.entries_truncated !== 'boolean'
  )
    return null;
  const { appointment_id, lifecycle_state } = raw.appointment;
  const { can_record, unavailable_reason } = raw.documentation;
  if (
    !isId(appointment_id) ||
    typeof lifecycle_state !== 'string' ||
    typeof can_record !== 'boolean' ||
    !(unavailable_reason === null || isUnavailableReason(unavailable_reason)) ||
    can_record !== (unavailable_reason === null)
  )
    return null;
  const entries: AppointmentClinicalEntry[] = [];
  const seen = new Set<string>();
  for (const item of raw.entries) {
    const entry = parseEntry(item);
    if (entry === null || seen.has(entry.entryId)) return null;
    seen.add(entry.entryId);
    entries.push(entry);
  }
  return {
    kind: 'permitted',
    record: {
      appointmentId: appointment_id,
      appointmentLifecycleState: lifecycle_state,
      canRecord: can_record,
      unavailableReason: unavailable_reason,
      entries,
      entriesTruncated: raw.entries_truncated,
    },
  };
}

/**
 * SPEC-MED-010 BR-20/BR-21: a permitted read of an Appointment with Entries is
 * one audited medical access, so callers read only where the record is shown.
 */
export async function viewAppointmentClinicalRecord(
  clinicId: string,
  appointmentId: string,
): Promise<AppointmentClinicalRecordRead> {
  try {
    const { data, error } = await supabase.rpc('view_appointment_clinical_record', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
    });
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      if (error.code === '42501') return { kind: 'denied' };
      return { kind: 'failed' };
    }
    return parseAppointmentClinicalRecord(data) ?? { kind: 'failed' };
  } catch {
    return { kind: 'failed' };
  }
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

/** Every stable rejection hint of the record and edit operations. */
export const CLINICAL_RECORD_REJECTIONS = [
  'KEY_REQUIRED',
  'CATEGORY_REQUIRED',
  'INVALID_CATEGORY',
  'CONTENT_REQUIRED',
  'OTHER_CONTEXT_REQUIRED',
  'OTHER_CONTEXT_NOT_ALLOWED',
  'KEY_CONFLICT',
  'APPOINTMENT_STATE_INVALID',
  'NO_VETERINARIAN_ASSIGNED',
  'NOT_ASSIGNED_VETERINARIAN',
  'ENTRY_AUTHOR_REQUIRED',
  'INVALID_VERSION',
  /** The Entry changed since the editor was opened (BR-23b). */
  'STALE_VERSION',
] as const;
export type ClinicalRecordRejection = (typeof CLINICAL_RECORD_REJECTIONS)[number];

export type ClinicalWriteFailure =
  | { kind: 'rejected'; reason: ClinicalRecordRejection }
  /** The uniform 42501: no access, or an unknown/foreign target. */
  | { kind: 'denied' }
  /** The Organization's clinical service is unavailable (Entitlement; new Entries only). */
  | { kind: 'serviceUnavailable' }
  | { kind: 'authenticationRequired' }
  | { kind: 'uncertain' };

export type ClinicalCreateResult =
  | { kind: 'outcome'; outcome: 'CREATED' | 'ALREADY_CREATED'; entryId: string }
  | ClinicalWriteFailure;

export type ClinicalEditResult =
  | { kind: 'outcome'; outcome: 'EDITED' | 'ALREADY_EDITED' | 'UNCHANGED'; version: number }
  | ClinicalWriteFailure;

type RpcError = { code?: string; hint?: string | null } | null;

function mapError(error: RpcError): ClinicalWriteFailure {
  const code = error?.code ?? '';
  if (code === '28000') return { kind: 'authenticationRequired' };
  if (code === '42501')
    return error?.hint === 'CLINICAL_SERVICE_UNAVAILABLE'
      ? { kind: 'serviceUnavailable' }
      : { kind: 'denied' };
  const reason = CLINICAL_RECORD_REJECTIONS.find((candidate) => candidate === error?.hint);
  return reason !== undefined ? { kind: 'rejected', reason } : { kind: 'uncertain' };
}

async function callWrite<Result>(
  rpc: string,
  args: Record<string, unknown>,
  parse: (data: Record<string, unknown>) => Result | null,
): Promise<Result | ClinicalWriteFailure> {
  try {
    const { data, error } = await supabase.rpc(rpc, args);
    if (error) return mapError(error);
    return (isRecord(data) ? parse(data) : null) ?? { kind: 'uncertain' };
  } catch {
    return { kind: 'uncertain' };
  }
}

/** The fields of one version of an Entry. No time: the server records its own. */
export type ClinicalEntryFields = {
  category: ClinicalRecordEntryCategory;
  clinicalContent: string;
  otherCategoryContext: string | null;
};

/**
 * SPEC-MED-010 BR-23: records one Entry, immediately clinical history. One
 * caller-generated key per record intent; repeating it with the same fields is
 * safe (`ALREADY_CREATED`), a different payload is `KEY_CONFLICT`.
 */
export function createAppointmentClinicalEntry(
  clinicId: string,
  appointmentId: string,
  idempotencyKey: string,
  fields: ClinicalEntryFields,
): Promise<ClinicalCreateResult> {
  return callWrite(
    'create_appointment_clinical_entry',
    {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
      p_idempotency_key: idempotencyKey,
      p_category: fields.category,
      p_clinical_content: fields.clinicalContent,
      p_other_category_context: fields.otherCategoryContext,
    },
    (data) => {
      const outcome = data.outcome;
      return (outcome === 'CREATED' || outcome === 'ALREADY_CREATED') && isId(data.entry_id)
        ? { kind: 'outcome', outcome, entryId: data.entry_id }
        : null;
    },
  );
}

/**
 * SPEC-MED-010 BR-23b: the author saves a new version of their own Entry of
 * this Appointment, opened on `expectedVersion`. Nothing is overwritten: the
 * earlier version stays in the history. One caller-generated key per edit;
 * repeating it with the same fields is safe (`ALREADY_EDITED`); an Entry that
 * changed meanwhile is `STALE_VERSION`; saving it unchanged is `UNCHANGED`.
 */
export function editAppointmentClinicalEntry(
  clinicId: string,
  appointmentId: string,
  entryId: string,
  idempotencyKey: string,
  expectedVersion: number,
  fields: ClinicalEntryFields,
): Promise<ClinicalEditResult> {
  return callWrite(
    'edit_appointment_clinical_entry',
    {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
      p_entry_id: entryId,
      p_idempotency_key: idempotencyKey,
      p_expected_version: expectedVersion,
      p_category: fields.category,
      p_clinical_content: fields.clinicalContent,
      p_other_category_context: fields.otherCategoryContext,
    },
    (data) => {
      const outcome = data.outcome;
      return (outcome === 'EDITED' || outcome === 'ALREADY_EDITED' || outcome === 'UNCHANGED') &&
        isVersionNumber(data.version)
        ? { kind: 'outcome', outcome, version: data.version }
        : null;
    },
  );
}
