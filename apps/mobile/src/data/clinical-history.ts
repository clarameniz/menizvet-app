import { FunctionsHttpError, FunctionsRelayError } from '@supabase/supabase-js';

import type { ClinicalEntryVersion } from '@/data/clinical-entry-versions';
import { supabase } from '@/lib/supabase';

/**
 * Mirrors the exact deployed contracts for Guardian-facing Milestone G
 * (session/work-planning label only — not a repository roadmap concept; the
 * repository's own operational checkpoint uses Slices, see
 * docs/IMPLEMENTATION_STATUS.md) reads, verified directly against the SQL and
 * Edge Function source (not assumed from a prior summary):
 *
 * - view_guardian_pet_medical_history(p_pet_id, p_limit=50,
 *   p_before_history_order_at=null, p_before_entry_id=null) — called here
 *   with GUARDIAN_MEDICAL_HISTORY_PAGE_SIZE (20) per page — originally
 *   defined in supabase/migrations/20260829120000_clinical_care.sql, later
 *   renamed to slice12_view_guardian_pet_medical_history and re-wrapped
 *   (adding only an `attachments` property per entry via
 *   decorate_clinical_attachment_read) by
 *   supabase/migrations/20260831120000_clinical_attachments.sql. Granted to
 *   authenticated. Returns a jsonb envelope, never a table:
 *   `{status:'DENIED'}` when the Pet doesn't exist or the caller has no
 *   *current* Guardianship (never had one, or it ended) — this is a normal,
 *   audited authorization outcome, not a technical failure; or
 *   `{status:'PERMITTED', payload:{entries:[...]}, cursor:{...}|null}`.
 *   `cursor` is `null` exactly when there is no further page — it is the
 *   verbatim `(history_order_at, id)` of the last visible item, produced
 *   server-side by a strict keyset comparison, never an offset. Zero
 *   finalized entries for an authorized caller is a valid, non-error
 *   PERMITTED result with an empty `entries` array (SPEC-MED-005 BR-35).
 *
 * - There is no single-Entry read for Guardians: the former professional
 *   single-Entry read is retired as a client path (SPEC-MED-010 BR-25). A
 *   Guardian "detail" view must be populated from the entry object already
 *   present in a view_guardian_pet_medical_history page, never from a second
 *   read.
 *
 * - Edge Function `clinical-attachments`, route `guardian-download`
 *   (supabase/functions/clinical-attachments/index.ts) — invoked as
 *   `clinical-attachments/guardian-download` (the function dispatches on the
 *   trailing path segment). Body: `{attachment_id}` only; the Guardian route
 *   reads nothing else and takes no professional context. Success (HTTP
 *   200): `{status:'PERMITTED', signed_download_url, original_filename,
 *   expires_in_seconds: 60}`. `signed_download_url` is produced with Storage's
 *   `{download:true}` option (Content-Disposition: attachment) and no
 *   filename override — whether expo-web-browser renders or downloads this
 *   is unverified and out of scope for this data-only pass. DENIED is HTTP
 *   403 with body `{status:'DENIED'}`. Every other failure is a JSON body
 *   `{error:'<CODE>'}` (AUTHENTICATION_REQUIRED 401, INVALID_REQUEST 400,
 *   SIGNED_DOWNLOAD_UNAVAILABLE 503, INTERNAL_ERROR 500, NOT_FOUND 404,
 *   METHOD_NOT_ALLOWED 405).
 *
 *   The installed @supabase/functions-js (node_modules/@supabase/functions-js/
 *   dist/main/FunctionsClient.js) throws FunctionsHttpError for any non-2xx
 *   response and returns `{data:null, error, response}`, where `response` is
 *   the raw, not-yet-consumed Response object — so DENIED (403) and every
 *   error code above surface as an "error" at the transport level and must be
 *   distinguished by reading that Response's JSON body here, not by treating
 *   every non-null `error` as a technical failure. The Authorization header
 *   is attached automatically from the active session by the shared
 *   `supabase` client (per @supabase/functions-js's own FunctionsClient.invoke
 *   doc comment) — no manual header wiring is added here.
 *
 * DENIED representation: matching the existing precedent in data/pets.ts's
 * getMyPetById (a Pet the caller no longer guards resolves to
 * `{data:null,error:null}` — absence encoded as a legitimate value, never as
 * `error`), DENIED here is a typed successful domain state carried inside
 * `data` (`{status:'DENIED'}`), never mapped to the `error` string. `error`
 * stays reserved for RPC/network failures and malformed payloads, consistent
 * with data/pets.ts and data/appointments.ts.
 *
 * Since 20261105090000_professional_longitudinal_history.sql (SPEC-MED-005
 * BR-46) the Guardian read is built from the shared finalized-history
 * projection and carries no internal identifier: each Entry has only `id`,
 * category, contents, clinical event / history order / recording times, the Clinic
 * and Organization display names, its Amendments (`id`, `reason`,
 * `amendment_content`, `created_at`), `amendment_count`,
 * `amendments_truncated` and `attachments`. Since
 * 20261116090000_editable_clinical_record_versions.sql (SPEC-MED-010 BR-22)
 * the category, contents and OTHER context are the Entry's current version,
 * with `version`, `edited_at` and every earlier version (`previous_versions`,
 * `previous_versions_truncated`); Amendments are then only the historical
 * reason-and-addition corrections. No User, Clinic Assignment,
 * Appointment, Clinic or Organization identifier and no Veterinarian name reach
 * the Guardian. Add a field here only when the read provides it and a
 * concrete Guardian screen needs it.
 *
 * Every exported function settles into `{data,error}` and never rejects,
 * matching the network-rejection guard established by data/pets.ts's
 * updatePetProfile and used throughout data/appointments.ts.
 */
export type ClinicalHistoryResult<T> = { data: T; error: null } | { data: null; error: string };

function toErrorMessage(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : 'Unknown error';
}

// ---------------------------------------------------------------------------
// Shared clinical taxonomy
// ---------------------------------------------------------------------------

/**
 * public.clinical_record_entries_category_check
 * (supabase/migrations/20260829120000_clinical_care.sql) — a real database
 * CHECK constraint, so this is a closed union, not a broad `string`.
 */
export type ClinicalRecordEntryCategory =
  | 'EXAMINATION'
  | 'DIAGNOSIS'
  | 'TREATMENT'
  | 'PROCEDURE'
  | 'VACCINATION'
  | 'PRESCRIPTION'
  | 'LABORATORY_RESULT'
  | 'IMAGING_RESULT'
  | 'CLINICAL_NOTE'
  | 'OTHER';

// ---------------------------------------------------------------------------
// Amendments
// ---------------------------------------------------------------------------

export type ClinicalAmendmentRow = {
  id: string;
  reason: string;
  amendment_content: string;
  created_at: string;
};

export type ClinicalAmendment = {
  id: string;
  reason: string;
  amendmentContent: string;
  createdAt: string;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromClinicalAmendmentRow(row: ClinicalAmendmentRow): ClinicalAmendment {
  return {
    id: row.id,
    reason: row.reason,
    amendmentContent: row.amendment_content,
    createdAt: row.created_at,
  };
}

// ---------------------------------------------------------------------------
// Earlier versions (SPEC-MED-010 BR-22)
// ---------------------------------------------------------------------------

export type ClinicalEntryVersionRow = {
  version: number;
  category: ClinicalRecordEntryCategory;
  other_category_context: string | null;
  clinical_content: string;
  created_at: string;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromClinicalEntryVersionRow(row: ClinicalEntryVersionRow): ClinicalEntryVersion {
  return {
    version: row.version,
    category: row.category,
    otherCategoryContext: row.other_category_context,
    clinicalContent: row.clinical_content,
    createdAt: row.created_at,
  };
}

// ---------------------------------------------------------------------------
// Attachments
// ---------------------------------------------------------------------------

export type ClinicalAttachmentRow = {
  id: string;
  original_filename: string | null;
  created_at: string;
  trusted_media_type: string | null;
  trusted_byte_size: number | null;
  validation_completed_at: string | null;
};

export type ClinicalAttachment = {
  id: string;
  originalFilename: string | null;
  createdAt: string;
  /**
   * Non-null (unlike the raw column): clinical_attachment_metadata_for_entry's
   * non-workflow branch (used for this Guardian read) only ever returns rows
   * where validation_state='AVAILABLE' and object_state='STORED', and
   * complete_clinical_attachment_validation only sets validation_state to
   * 'AVAILABLE' together with trusted_media_type/trusted_byte_size/
   * validation_completed_at all set — an attachment can never appear in a
   * Guardian history read without them.
   */
  trustedMediaType: string;
  trustedByteSize: number;
  validationCompletedAt: string;
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromClinicalAttachmentRow(row: ClinicalAttachmentRow): ClinicalAttachment {
  return {
    id: row.id,
    originalFilename: row.original_filename,
    createdAt: row.created_at,
    // Safe by construction — see the ClinicalAttachment.trustedMediaType comment.
    trustedMediaType: row.trusted_media_type!,
    trustedByteSize: row.trusted_byte_size!,
    validationCompletedAt: row.validation_completed_at!,
  };
}

// ---------------------------------------------------------------------------
// view_guardian_pet_medical_history
// ---------------------------------------------------------------------------

export type GuardianMedicalHistoryEntryRow = {
  id: string;
  clinic_display_name: string | null;
  organization_display_name: string | null;
  clinical_content: string | null;
  category: ClinicalRecordEntryCategory | null;
  other_category_context: string | null;
  clinical_event_at: string | null;
  history_order_at: string;
  finalized_at: string | null;
  version: number;
  edited_at: string | null;
  previous_versions: ClinicalEntryVersionRow[];
  previous_versions_truncated: boolean;
  amendments: ClinicalAmendmentRow[];
  amendment_count: number;
  amendments_truncated: boolean;
  attachments: ClinicalAttachmentRow[];
};

export type GuardianMedicalHistoryEntry = {
  id: string;
  /**
   * Resolved server-side inside the already-authorized
   * view_guardian_pet_medical_history payload (the Clinic's
   * clinic_public_profiles.display_name, independent of current
   * is_published — see the migration doc comment in this module for the
   * provenance rationale). Nullable: a Clinic may have no public profile row,
   * or one with a null display_name.
   */
  clinicDisplayName: string | null;
  /**
   * Resolved the same way from veterinary_organizations.display_name. Always
   * present in practice (NOT NULL column, non-deletable FK), but kept
   * nullable here to mirror the row's actual JSON shape rather than assert a
   * guarantee this module doesn't independently verify.
   */
  organizationDisplayName: string | null;
  clinicalContent: string | null;
  category: ClinicalRecordEntryCategory | null;
  otherCategoryContext: string | null;
  clinicalEventAt: string | null;
  /**
   * The chronology field to sort/group history by (SPEC-MED-005 BR-21) — the
   * server's own coalesce(clinical_event_at, recorded time) (SPEC-MED-010
   * BR-22), taken verbatim from the payload. Never recompute this client-side.
   */
  historyOrderAt: string;
  /**
   * When the Entry was recorded. Non-null (unlike the raw column): every
   * Entry is published when recorded (SPEC-MED-010 BR-4), which sets it.
   */
  finalizedAt: string;
  /** The current version (1 until the Entry's author first edits it). */
  version: number;
  /** When the current version was saved; `null` for an Entry never edited. */
  editedAt: string | null;
  /** Every earlier version, oldest first: the Entry's history of changes. */
  previousVersions: ClinicalEntryVersion[];
  previousVersionsTruncated: boolean;
  /** Historical reason-and-addition corrections only. */
  amendments: ClinicalAmendment[];
  amendmentCount: number;
  amendmentsTruncated: boolean;
  attachments: ClinicalAttachment[];
};

// Exported for unit testing: pure, side-effect-free reshaping with no
// security/authorization surface (same rationale as data/pets.ts's fromRow).
export function fromGuardianMedicalHistoryEntryRow(
  row: GuardianMedicalHistoryEntryRow,
): GuardianMedicalHistoryEntry {
  return {
    id: row.id,
    clinicDisplayName: row.clinic_display_name,
    organizationDisplayName: row.organization_display_name,
    clinicalContent: row.clinical_content,
    category: row.category,
    otherCategoryContext: row.other_category_context,
    clinicalEventAt: row.clinical_event_at,
    historyOrderAt: row.history_order_at,
    // Safe by construction — see the GuardianMedicalHistoryEntry.finalizedAt comment.
    finalizedAt: row.finalized_at!,
    version: row.version,
    editedAt: row.edited_at,
    previousVersions: row.previous_versions.map(fromClinicalEntryVersionRow),
    previousVersionsTruncated: row.previous_versions_truncated,
    amendments: row.amendments.map(fromClinicalAmendmentRow),
    amendmentCount: row.amendment_count,
    amendmentsTruncated: row.amendments_truncated,
    attachments: row.attachments.map(fromClinicalAttachmentRow),
  };
}

export type GuardianMedicalHistoryCursor = {
  beforeHistoryOrderAt: string;
  beforeEntryId: string;
};

export type GuardianMedicalHistoryPage = {
  entries: GuardianMedicalHistoryEntry[];
  cursor: GuardianMedicalHistoryCursor | null;
};

/**
 * The typed result of a Guardian medical-history read: `DENIED` is a normal,
 * audited authorization outcome (no current Guardianship, or the Pet doesn't
 * exist), not a technical error — see this module's doc comment.
 */
export type GuardianMedicalHistoryAccess =
  { status: 'PERMITTED'; page: GuardianMedicalHistoryPage } | { status: 'DENIED' };

/**
 * Entries per Guardian medical-history page: the first page and every "Load
 * more". A client choice within the read's own `p_limit` (the server's default
 * is 50, its cap 100); the cursor and ordering are the server's either way.
 */
export const GUARDIAN_MEDICAL_HISTORY_PAGE_SIZE = 20;

type ViewGuardianPetMedicalHistoryResponse =
  | { status: 'DENIED' }
  | {
      status: 'PERMITTED';
      payload: { entries: GuardianMedicalHistoryEntryRow[] };
      cursor: { before_history_order_at: string; before_entry_id: string } | null;
    };

/**
 * Pet-scoped Guardian read (SPEC-MED-005). Pass `cursor` back verbatim from a
 * previous page's `page.cursor` to fetch the next page; omit it (or pass
 * `null`) for the first page. `cursor === null` on a page means end of
 * history — do not call again. There is no offset parameter in the deployed
 * contract, so none is exposed here. `limit` is forwarded as-is; the server
 * silently caps it at 100 (`least(p_limit, 100)`), so no client-side clamp is
 * duplicated here.
 */
export async function getGuardianPetMedicalHistory(
  petId: string,
  cursor: GuardianMedicalHistoryCursor | null = null,
  limit = GUARDIAN_MEDICAL_HISTORY_PAGE_SIZE,
): Promise<ClinicalHistoryResult<GuardianMedicalHistoryAccess>> {
  try {
    const { data, error } = await supabase.rpc('view_guardian_pet_medical_history', {
      p_pet_id: petId,
      p_limit: limit,
      p_before_history_order_at: cursor?.beforeHistoryOrderAt ?? null,
      p_before_entry_id: cursor?.beforeEntryId ?? null,
    });

    if (error) {
      return { data: null, error: error.message };
    }

    const response = data as ViewGuardianPetMedicalHistoryResponse | null;
    if (response === null) {
      return { data: null, error: 'Medical history response was empty' };
    }

    if (response.status === 'DENIED') {
      return { data: { status: 'DENIED' }, error: null };
    }

    const nextCursor: GuardianMedicalHistoryCursor | null = response.cursor
      ? {
          beforeHistoryOrderAt: response.cursor.before_history_order_at,
          beforeEntryId: response.cursor.before_entry_id,
        }
      : null;

    return {
      data: {
        status: 'PERMITTED',
        page: {
          entries: response.payload.entries.map(fromGuardianMedicalHistoryEntryRow),
          cursor: nextCursor,
        },
      },
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}

// ---------------------------------------------------------------------------
// clinical-attachments Edge Function: guardian-download
// ---------------------------------------------------------------------------

/**
 * The typed result of requesting a Guardian Attachment download URL: `DENIED`
 * is a normal, audited authorization outcome (Guardianship no longer current,
 * Entry not finalized, or Attachment not currently available/stored), not a
 * technical error — see this module's doc comment.
 */
export type ClinicalAttachmentDownloadAccess =
  | {
      status: 'PERMITTED';
      signedDownloadUrl: string;
      originalFilename: string | null;
      expiresInSeconds: number;
    }
  | { status: 'DENIED' };

type ClinicalAttachmentDownloadResponseBody =
  | { status: 'DENIED' }
  | {
      status: 'PERMITTED';
      signed_download_url: string;
      original_filename: string | null;
      expires_in_seconds: number;
    };

type EdgeFunctionErrorBody = { error: string };

function isEdgeFunctionErrorBody(value: unknown): value is EdgeFunctionErrorBody {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as { error?: unknown }).error === 'string'
  );
}

function isDeniedResponseBody(value: unknown): value is { status: 'DENIED' } {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { status?: unknown }).status === 'DENIED'
  );
}

/**
 * Requests a short-lived signed download URL for one Guardian-visible
 * Clinical Attachment via the deployed `clinical-attachments` Edge Function's
 * `guardian-download` route. The Authorization header is attached
 * automatically by the shared `supabase` client from the active session — no
 * header is set manually here.
 *
 * A non-2xx Edge Function response (this always includes the 403 DENIED
 * case) surfaces from supabase-js as a thrown-and-caught FunctionsHttpError/
 * FunctionsRelayError with the raw, not-yet-read Response on `response`; that
 * body must be parsed here to tell DENIED apart from an actual technical
 * failure (`{error:'<CODE>'}`) rather than treating every non-null `error` as
 * a network/technical failure.
 */
export async function getGuardianClinicalAttachmentDownloadUrl(
  attachmentId: string,
): Promise<ClinicalHistoryResult<ClinicalAttachmentDownloadAccess>> {
  try {
    const { data, error, response } = await supabase.functions.invoke(
      'clinical-attachments/guardian-download',
      { body: { attachment_id: attachmentId } },
    );

    if (error) {
      if (
        (error instanceof FunctionsHttpError || error instanceof FunctionsRelayError) &&
        response
      ) {
        let body: unknown = null;
        try {
          body = await response.json();
        } catch {
          body = null;
        }
        if (isDeniedResponseBody(body)) {
          return { data: { status: 'DENIED' }, error: null };
        }
        if (isEdgeFunctionErrorBody(body)) {
          return { data: null, error: body.error };
        }
      }
      return { data: null, error: toErrorMessage(error) };
    }

    const responseBody = data as ClinicalAttachmentDownloadResponseBody | null;
    if (responseBody === null) {
      return { data: null, error: 'Clinical Attachment download response was empty' };
    }
    if (responseBody.status === 'DENIED') {
      return { data: { status: 'DENIED' }, error: null };
    }

    return {
      data: {
        status: 'PERMITTED',
        signedDownloadUrl: responseBody.signed_download_url,
        originalFilename: responseBody.original_filename,
        expiresInSeconds: responseBody.expires_in_seconds,
      },
      error: null,
    };
  } catch (thrown) {
    return { data: null, error: toErrorMessage(thrown) };
  }
}
