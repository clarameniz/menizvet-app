import type { ClinicalRecordEntryCategory } from '@/data/clinical-history';

/**
 * The earlier versions of one Clinical Record Entry (SPEC-MED-010 BR-18,
 * BR-20, BR-22; supabase/migrations/20261116090000_editable_clinical_record_versions.sql).
 * The recorded Entry is version 1; each edit by its author is the next version.
 * Reads carry the current version as the Entry's own fields and every earlier
 * one here, oldest first. Every version is by the Entry's author, so none
 * carries an author of its own.
 */
export type ClinicalEntryVersion = {
  version: number;
  category: ClinicalRecordEntryCategory;
  otherCategoryContext: string | null;
  clinicalContent: string;
  /** When this version was saved; for version 1, when the Entry was recorded. */
  createdAt: string;
};

export const CLINICAL_ENTRY_CATEGORIES: readonly ClinicalRecordEntryCategory[] = [
  'EXAMINATION',
  'DIAGNOSIS',
  'TREATMENT',
  'PROCEDURE',
  'VACCINATION',
  'PRESCRIPTION',
  'LABORATORY_RESULT',
  'IMAGING_RESULT',
  'CLINICAL_NOTE',
  'OTHER',
];

/** The server's bound on the earlier versions one read carries. */
export const MAX_PREVIOUS_VERSIONS = 100;

const VERSION_KEYS = [
  'category',
  'clinical_content',
  'created_at',
  'other_category_context',
  'version',
];
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
const isText = (value: unknown): value is string =>
  typeof value === 'string' && value.trim() !== '';

export const isClinicalEntryCategory = (value: unknown): value is ClinicalRecordEntryCategory =>
  typeof value === 'string' && (CLINICAL_ENTRY_CATEGORIES as readonly string[]).includes(value);

/** A version number: a positive integer. */
export const isVersionNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isInteger(value) && value >= 1;

function parseVersion(raw: unknown): ClinicalEntryVersion | null {
  if (!isRecord(raw)) return null;
  const keys = Object.keys(raw).sort();
  if (keys.length !== VERSION_KEYS.length || keys.some((key, index) => key !== VERSION_KEYS[index]))
    return null;
  const { version, category, other_category_context, clinical_content, created_at } = raw;
  if (
    !isVersionNumber(version) ||
    !isClinicalEntryCategory(category) ||
    !(other_category_context === null || isText(other_category_context)) ||
    !isText(clinical_content) ||
    typeof created_at !== 'string' ||
    !TIMESTAMP.test(created_at)
  )
    return null;
  return {
    version,
    category,
    otherCategoryContext: other_category_context,
    clinicalContent: clinical_content,
    createdAt: created_at,
  };
}

/**
 * Exported for unit testing. The earlier versions of an Entry whose current
 * version is `currentVersion`: exactly versions 1, 2, … in order, every one
 * below the current, and complete unless `truncated` (then the first
 * `MAX_PREVIOUS_VERSIONS`). `null` = malformed: a partial history is never shown.
 */
export function parsePreviousVersions(
  raw: unknown,
  currentVersion: number,
  truncated: boolean,
): ClinicalEntryVersion[] | null {
  if (!Array.isArray(raw)) return null;
  const expected = truncated ? MAX_PREVIOUS_VERSIONS : currentVersion - 1;
  if (raw.length !== expected || (truncated && currentVersion - 1 <= MAX_PREVIOUS_VERSIONS))
    return null;
  const versions: ClinicalEntryVersion[] = [];
  for (const [index, item] of raw.entries()) {
    const version = parseVersion(item);
    if (version === null || version.version !== index + 1) return null;
    versions.push(version);
  }
  return versions;
}
