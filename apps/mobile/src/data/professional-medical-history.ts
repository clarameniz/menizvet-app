import type { ClinicalRecordEntryCategory } from '@/data/clinical-history';
import {
  isClinicalEntryCategory,
  isVersionNumber,
  parsePreviousVersions,
  type ClinicalEntryVersion,
} from '@/data/clinical-entry-versions';
import { supabase } from '@/lib/supabase';

/**
 * Professional Longitudinal / Cross-Clinic Medical History — Phase 1: the
 * Appointment-keyed client read (SPEC-MED-005 §15, SPEC-MED-010 BR-14/BR-22;
 * supabase/migrations/20261116090000_editable_clinical_record_versions.sql).
 * Each Entry is presented in its current version, with every earlier version.
 *
 * `view_appointment_professional_medical_history(p_clinic_id,
 * p_appointment_id, p_limit, p_before_history_order_at, p_before_entry_id)`.
 * Keyed only by the Clinic and Appointment the professional Appointment detail
 * shows; the server derives the Pet and the access basis. Every
 * call is one audited protected read, so callers read only on an explicit
 * action, retry or load more — never on mount of the Appointment detail and
 * never on every focus.
 *
 * The payload carries no User, Membership, Clinic Assignment, Care
 * Authorization, Clinic, Organization or other-Appointment
 * identifier. Veterinarian provenance is a display name (possibly null, for
 * which the UI shows a neutral fallback) plus `isMe`; it is self-entered and
 * unverified, so no professional title is ever added. Clinical content is
 * never logged. No function here throws or retries.
 */

export type ProfessionalHistoryIdentity = {
  /** The historically attributed User's current display name, or null. */
  displayName: string | null;
  isMe: boolean;
};

export type ProfessionalHistoryAmendment = {
  amendmentId: string;
  reason: string;
  amendmentContent: string;
  createdAt: string;
  author: ProfessionalHistoryIdentity;
};

export type ProfessionalHistoryEntry = {
  entryId: string;
  category: ClinicalRecordEntryCategory;
  otherCategoryContext: string | null;
  /** The current version's content. */
  clinicalContent: string;
  clinicalEventAt: string | null;
  /** coalesce(clinical event, recording time): the primary clinical date. */
  historyOrderAt: string;
  /** When the Entry was recorded — and published, in the same act (SPEC-MED-010 BR-4). */
  finalizedAt: string;
  clinicDisplayName: string | null;
  organizationDisplayName: string | null;
  isThisAppointment: boolean;
  author: ProfessionalHistoryIdentity;
  /** The current version: 1 until the author first edits the Entry. */
  version: number;
  /** When the current version was saved; `null` for an Entry never edited. */
  editedAt: string | null;
  /** Every earlier version, oldest first; all by the Entry's author. */
  previousVersions: ClinicalEntryVersion[];
  previousVersionsTruncated: boolean;
  /** Historical reason-and-addition corrections, oldest first. */
  amendments: ProfessionalHistoryAmendment[];
  amendmentCount: number;
  amendmentsTruncated: boolean;
};

export type ProfessionalHistoryCursor = {
  beforeHistoryOrderAt: string;
  beforeEntryId: string;
};

export type ProfessionalHistoryPage = {
  entries: ProfessionalHistoryEntry[];
  cursor: ProfessionalHistoryCursor | null;
};

export type ProfessionalHistoryRead =
  | { kind: 'permitted'; page: ProfessionalHistoryPage }
  /** Uniform: no access now, an unknown or foreign target, or a closed window. */
  | { kind: 'denied' }
  | { kind: 'authenticationRequired' }
  | { kind: 'failed' };

export const PROFESSIONAL_HISTORY_PAGE_SIZE = 50;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;
const ENTRY_KEYS = [
  'amendment_count',
  'amendments',
  'amendments_truncated',
  'author',
  'category',
  'clinic_display_name',
  'clinical_content',
  'clinical_event_at',
  'edited_at',
  'entry_id',
  'finalized_at',
  'finalizer',
  'history_order_at',
  'is_this_appointment',
  'organization_display_name',
  'other_category_context',
  'previous_versions',
  'previous_versions_truncated',
  'version',
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
/** Exactly these keys: an unexpected one (for example a leaked identifier) is malformed. */
function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const keys = Object.keys(value).sort();
  return keys.length === expected.length && keys.every((key, index) => key === expected[index]);
}
const IDENTITY_KEYS = ['display_name', 'is_me'];
const AMENDMENT_KEYS = ['amendment_content', 'amendment_id', 'author', 'created_at', 'reason'];
const isId = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);
const isTimestamp = (value: unknown): value is string =>
  typeof value === 'string' && TIMESTAMP.test(value);
const isText = (value: unknown): value is string =>
  typeof value === 'string' && value.trim() !== '';
const isNullableText = (value: unknown): value is string | null => value === null || isText(value);
const isCount = (value: unknown): value is number =>
  typeof value === 'number' && Number.isInteger(value) && value >= 0;

function parseIdentity(raw: unknown): ProfessionalHistoryIdentity | null {
  if (!isRecord(raw) || !hasExactKeys(raw, IDENTITY_KEYS)) return null;
  const { display_name, is_me } = raw;
  if (!isNullableText(display_name) || typeof is_me !== 'boolean') return null;
  return { displayName: display_name, isMe: is_me };
}

function parseAmendment(raw: unknown): ProfessionalHistoryAmendment | null {
  if (!isRecord(raw) || !hasExactKeys(raw, AMENDMENT_KEYS)) return null;
  const { amendment_id, reason, amendment_content, created_at } = raw;
  const author = parseIdentity(raw.author);
  if (
    author === null ||
    !isId(amendment_id) ||
    !isText(reason) ||
    !isText(amendment_content) ||
    !isTimestamp(created_at)
  )
    return null;
  return {
    amendmentId: amendment_id,
    reason,
    amendmentContent: amendment_content,
    createdAt: created_at,
    author,
  };
}

function parseEntry(raw: unknown): ProfessionalHistoryEntry | null {
  if (!isRecord(raw) || !hasExactKeys(raw, ENTRY_KEYS)) return null;
  const {
    entry_id,
    category,
    other_category_context,
    clinical_content,
    clinical_event_at,
    history_order_at,
    finalized_at,
    clinic_display_name,
    organization_display_name,
    is_this_appointment,
    amendment_count,
    amendments_truncated,
    version,
    edited_at,
    previous_versions_truncated,
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
  if (previousVersions === null) return null;
  const author = parseIdentity(raw.author);
  if (!Array.isArray(raw.amendments)) return null;
  const amendments: ProfessionalHistoryAmendment[] = [];
  const seen = new Set<string>();
  for (const item of raw.amendments) {
    const amendment = parseAmendment(item);
    if (amendment === null || seen.has(amendment.amendmentId)) return null;
    seen.add(amendment.amendmentId);
    amendments.push(amendment);
  }
  if (
    author === null ||
    // An Entry is published by its own author when recorded: never a finalizer.
    raw.finalizer !== null ||
    !isId(entry_id) ||
    !isClinicalEntryCategory(category) ||
    !isNullableText(other_category_context) ||
    !isText(clinical_content) ||
    !(clinical_event_at === null || isTimestamp(clinical_event_at)) ||
    !isTimestamp(history_order_at) ||
    !isTimestamp(finalized_at) ||
    !isNullableText(clinic_display_name) ||
    !isNullableText(organization_display_name) ||
    typeof is_this_appointment !== 'boolean' ||
    !isCount(amendment_count) ||
    typeof amendments_truncated !== 'boolean' ||
    amendment_count < amendments.length
  )
    return null;
  return {
    entryId: entry_id,
    category,
    otherCategoryContext: other_category_context,
    clinicalContent: clinical_content,
    clinicalEventAt: clinical_event_at,
    historyOrderAt: history_order_at,
    finalizedAt: finalized_at,
    clinicDisplayName: clinic_display_name,
    organizationDisplayName: organization_display_name,
    isThisAppointment: is_this_appointment,
    author,
    version,
    editedAt,
    previousVersions,
    previousVersionsTruncated: previous_versions_truncated,
    amendments,
    amendmentCount: amendment_count,
    amendmentsTruncated: amendments_truncated,
  };
}

/**
 * Exported for unit testing. `null` = malformed; a denial is its own typed
 * state and carries nothing else.
 */
export function parseProfessionalHistory(
  raw: unknown,
): { kind: 'permitted'; page: ProfessionalHistoryPage } | { kind: 'denied' } | null {
  if (!isRecord(raw)) return null;
  if (raw.status === 'DENIED') return Object.keys(raw).length === 1 ? { kind: 'denied' } : null;
  if (raw.status !== 'PERMITTED' || !Array.isArray(raw.entries)) return null;
  let cursor: ProfessionalHistoryCursor | null = null;
  if (raw.cursor !== null) {
    if (!isRecord(raw.cursor)) return null;
    const { before_history_order_at, before_entry_id } = raw.cursor;
    if (!isTimestamp(before_history_order_at) || !isId(before_entry_id)) return null;
    cursor = { beforeHistoryOrderAt: before_history_order_at, beforeEntryId: before_entry_id };
  }
  const entries: ProfessionalHistoryEntry[] = [];
  const seen = new Set<string>();
  for (const item of raw.entries) {
    const entry = parseEntry(item);
    if (entry === null || seen.has(entry.entryId)) return null;
    seen.add(entry.entryId);
    entries.push(entry);
  }
  return { kind: 'permitted', page: { entries, cursor } };
}

export async function viewAppointmentProfessionalMedicalHistory(
  clinicId: string,
  appointmentId: string,
  cursor: ProfessionalHistoryCursor | null = null,
  limit = PROFESSIONAL_HISTORY_PAGE_SIZE,
): Promise<ProfessionalHistoryRead> {
  try {
    const { data, error } = await supabase.rpc('view_appointment_professional_medical_history', {
      p_clinic_id: clinicId,
      p_appointment_id: appointmentId,
      p_limit: limit,
      p_before_history_order_at: cursor?.beforeHistoryOrderAt ?? null,
      p_before_entry_id: cursor?.beforeEntryId ?? null,
    });
    if (error) {
      if (error.code === '28000') return { kind: 'authenticationRequired' };
      return { kind: 'failed' };
    }
    return parseProfessionalHistory(data) ?? { kind: 'failed' };
  } catch {
    return { kind: 'failed' };
  }
}
