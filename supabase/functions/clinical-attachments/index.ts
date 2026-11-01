import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  DatabaseOperationError,
  expectedDatabaseHttpError,
  rpcData,
} from "../_shared/clinical-attachments/database-errors.ts";
import { ATTACHMENT_POLICY } from "../_shared/clinical-attachments/policy.ts";
import { reconcileStaleUpload } from "../_shared/clinical-attachments/reconciliation.ts";
import { clinicalAttachmentRoute } from "../_shared/clinical-attachments/routes.ts";
import {
  attachmentObjectPath,
  signedDownloadOptions,
} from "../_shared/clinical-attachments/storage.ts";
import {
  isStorageObjectNotFound,
  type StoredObjectInfo,
  validateStoredObjectMetadata,
} from "../_shared/clinical-attachments/storage-metadata.ts";
import {
  deriveTrustedValidationFacts,
  postgresByteaFromHex,
  rejectedStorageMetadataFacts,
  type TrustedValidationFacts,
} from "../_shared/clinical-attachments/validation-service.ts";

const CORS_HEADERS = Object.freeze({
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, content-type, x-maintenance-secret",
  "access-control-allow-methods": "POST, OPTIONS",
});
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

interface ValidationTarget {
  attachment_id: string;
  storage_object_id: string;
}

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function requiredUuid(value: unknown, name: string): string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new TypeError(`${name} must be a UUID`);
  }
  return value.toLowerCase();
}

async function requestBody(request: Request): Promise<Record<string, unknown>> {
  const value: unknown = await request.json();
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("JSON object body is required");
  }
  return value as Record<string, unknown>;
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  const match = header?.match(/^Bearer\s+(.+)$/iu);
  return match?.[1] ?? null;
}

async function verifiedAuthSubject(
  admin: SupabaseClient,
  request: Request,
): Promise<string> {
  const token = bearerToken(request);
  if (!token) throw new ResponseError(401, "AUTHENTICATION_REQUIRED");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new ResponseError(401, "AUTHENTICATION_REQUIRED");
  }
  return data.user.id;
}

class ResponseError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

async function deleteKnownObject(
  admin: SupabaseClient,
  target: ValidationTarget,
): Promise<boolean> {
  const path = attachmentObjectPath(target.storage_object_id);
  const { error: deleteError } = await admin.storage
    .from(ATTACHMENT_POLICY.bucketName)
    .remove([path]);
  if (deleteError) return false;
  const { error: markError } = await admin.rpc(
    "mark_clinical_attachment_object_deleted",
    {
      p_attachment_id: target.attachment_id,
      p_storage_object_id: target.storage_object_id,
    },
  );
  return markError === null;
}

async function expireMissingStaleUpload(
  admin: SupabaseClient,
  target: ValidationTarget,
): Promise<Record<string, unknown>> {
  const expiration = await admin.rpc(
    "expire_missing_stale_clinical_attachment_upload",
    {
      p_attachment_id: target.attachment_id,
      p_storage_object_id: target.storage_object_id,
    },
  );
  return rpcData<Record<string, unknown>>(
    expiration.data,
    expiration.error,
  );
}

async function inspectKnownObject(
  admin: SupabaseClient,
  target: ValidationTarget,
): Promise<
  | Readonly<{ kind: "EXISTS"; info: StoredObjectInfo }>
  | Readonly<{ kind: "MISSING" }>
> {
  const path = attachmentObjectPath(target.storage_object_id);
  const { data, error } = await admin.storage
    .from(ATTACHMENT_POLICY.bucketName)
    .info(path);
  if (error) {
    if (isStorageObjectNotFound(error)) {
      return Object.freeze({ kind: "MISSING" });
    }
    throw new ResponseError(503, "STORAGE_INFO_UNAVAILABLE");
  }
  if (!data) throw new ResponseError(503, "STORAGE_INFO_UNAVAILABLE");
  return Object.freeze({ kind: "EXISTS", info: data });
}

async function validateKnownObject(
  admin: SupabaseClient,
  target: ValidationTarget,
  knownInfo?: StoredObjectInfo,
): Promise<Record<string, unknown>> {
  const path = attachmentObjectPath(target.storage_object_id);
  const inspection = knownInfo === undefined
    ? await inspectKnownObject(admin, target)
    : Object.freeze({ kind: "EXISTS" as const, info: knownInfo });
  if (inspection.kind === "MISSING") {
    // Completion does not expire a missing upload. Only stale maintenance may
    // call the narrow expiration primitive after rechecking the exact path.
    throw new ResponseError(409, "OBJECT_NOT_AVAILABLE_FOR_VALIDATION");
  }
  const metadata = validateStoredObjectMetadata(inspection.info);

  const stored = await admin.rpc("mark_clinical_attachment_object_stored", {
    p_attachment_id: target.attachment_id,
    p_storage_object_id: target.storage_object_id,
  });
  const storedState = rpcData<Record<string, unknown>>(
    stored.data,
    stored.error,
  );
  if (storedState.status === "REMOVED") {
    await deleteKnownObject(admin, target);
    return { status: "REMOVED" };
  }
  if (storedState.status !== "PENDING") {
    return { status: storedState.status, idempotent_retry: true };
  }

  let facts: TrustedValidationFacts;
  if (metadata.accepted) {
    const { data: objectBlob, error: downloadError } = await admin.storage
      .from(ATTACHMENT_POLICY.bucketName)
      .download(path);
    if (downloadError || !objectBlob) {
      throw new ResponseError(409, "OBJECT_NOT_AVAILABLE_FOR_VALIDATION");
    }
    const bytes = new Uint8Array(await objectBlob.arrayBuffer());
    if (bytes.byteLength !== metadata.size) {
      throw new ResponseError(409, "OBJECT_CHANGED_DURING_VALIDATION");
    }
    facts = await deriveTrustedValidationFacts(
      bytes,
      ATTACHMENT_POLICY.mimeType,
    );
  } else {
    facts = rejectedStorageMetadataFacts(metadata.rejectionCode);
  }

  const completion = await admin.rpc(
    "complete_clinical_attachment_validation",
    {
      p_attachment_id: target.attachment_id,
      p_storage_object_id: target.storage_object_id,
      p_outcome: facts.outcome,
      p_trusted_media_type: facts.trustedMediaType,
      p_trusted_byte_size: facts.trustedByteSize,
      p_integrity_value: postgresByteaFromHex(facts.integrityHex),
      p_validation_policy_version: ATTACHMENT_POLICY.validationPolicyVersion,
      p_rejection_code: facts.rejectionCode,
    },
  );
  const result = rpcData<Record<string, unknown>>(
    completion.data,
    completion.error,
  );
  if (facts.outcome === "REJECTED") await deleteKnownObject(admin, target);
  return result;
}

// The Guardian route reads only `attachment_id`: the acting User comes from
// the verified token, and authority is decided by the database from the
// Guardianship of the Attachment's own Pet. No other body field is forwarded.
async function guardianDownload(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  const authSubject = await verifiedAuthSubject(admin, request);
  const body = await requestBody(request);
  const authorized = await admin.rpc(
    "authorize_guardian_clinical_attachment_download",
    {
      p_auth_subject: authSubject,
      p_attachment_id: requiredUuid(body.attachment_id, "attachment_id"),
    },
  );
  const permission = rpcData<Record<string, unknown>>(
    authorized.data,
    authorized.error,
  );
  if (permission.status !== "PERMITTED") {
    return response({ status: "DENIED" }, 403);
  }

  // Authorization and VIEW_CLINICAL_ATTACHMENT audit commit in the RPC before
  // any URL is signed. A signing failure leaves the committed PERMITTED audit.
  const path = attachmentObjectPath(
    requiredUuid(permission.storage_object_id, "storage_object_id"),
  );
  const originalFilename = typeof permission.original_filename === "string"
    ? permission.original_filename
    : null;
  const signed = await admin.storage.from(ATTACHMENT_POLICY.bucketName)
    .createSignedUrl(
      path,
      ATTACHMENT_POLICY.downloadSignedUrlExpiresInSeconds,
      signedDownloadOptions(),
    );
  if (signed.error || !signed.data?.signedUrl) {
    throw new ResponseError(503, "SIGNED_DOWNLOAD_UNAVAILABLE");
  }
  // expiresIn=60 is requested from the provider, but an already-issued URL can
  // remain technically usable through provider caching. It is not a strict
  // byte-access/revocation boundary. Each new URL request reruns this RPC.
  return response({
    status: "PERMITTED",
    signed_download_url: signed.data.signedUrl,
    original_filename: originalFilename,
    expires_in_seconds: ATTACHMENT_POLICY.downloadSignedUrlExpiresInSeconds,
  });
}

function maintenanceAuthorized(request: Request): boolean {
  const configured = Deno.env.get("CLINICAL_ATTACHMENTS_MAINTENANCE_SECRET");
  const supplied = request.headers.get("x-maintenance-secret");
  if (!configured || !supplied) return false;
  const expected = new TextEncoder().encode(configured);
  const actual = new TextEncoder().encode(supplied);
  if (expected.length !== actual.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected[index] ^ actual[index];
  }
  return difference === 0;
}

async function maintenance(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  if (!maintenanceAuthorized(request)) {
    throw new ResponseError(401, "MAINTENANCE_AUTHENTICATION_REQUIRED");
  }
  const body = await requestBody(request);
  const requestedLimit = body.limit === undefined ? 25 : Number(body.limit);
  if (!Number.isInteger(requestedLimit) || requestedLimit < 1) {
    throw new TypeError("limit must be a positive integer");
  }
  const claimed = await admin.rpc("claim_clinical_attachment_maintenance", {
    p_limit: Math.min(requestedLimit, 50),
  });
  const tasks = rpcData<Array<Record<string, unknown>>>(
    claimed.data,
    claimed.error,
  );
  const results: Array<Record<string, unknown>> = [];
  for (const task of tasks) {
    const target: ValidationTarget = {
      attachment_id: requiredUuid(task.attachment_id, "attachment_id"),
      storage_object_id: requiredUuid(
        task.storage_object_id,
        "storage_object_id",
      ),
    };
    try {
      if (task.action === "VALIDATE") {
        results.push({
          attachment_id: target.attachment_id,
          action: "VALIDATE",
          result: await validateKnownObject(admin, target),
        });
      } else if (task.action === "RECONCILE") {
        const inspection = await inspectKnownObject(admin, target);
        results.push({
          attachment_id: target.attachment_id,
          action: "RECONCILE",
          result: await reconcileStaleUpload(
            inspection,
            (info) => validateKnownObject(admin, target, info),
            () => expireMissingStaleUpload(admin, target),
          ),
        });
      } else if (task.action === "DELETE") {
        results.push({
          attachment_id: target.attachment_id,
          action: "DELETE",
          complete: await deleteKnownObject(admin, target),
        });
      }
    } catch (error) {
      results.push({
        attachment_id: target.attachment_id,
        action: task.action,
        complete: false,
        retryable_error: error instanceof ResponseError
          ? error.code
          : "MAINTENANCE_TASK_FAILED",
      });
    }
  }
  return response({ status: "COMPLETE", processed: results.length, results });
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Supabase service configuration is missing");
}
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  try {
    // The retired professional routes are NOT_FOUND like any other name,
    // before any authentication or body is read.
    switch (clinicalAttachmentRoute(request.url)) {
      case "guardian-download":
        return await guardianDownload(admin, request);
      case "maintenance":
        return await maintenance(admin, request);
      default:
        return response({ error: "NOT_FOUND" }, 404);
    }
  } catch (error) {
    if (error instanceof ResponseError) {
      return response({ error: error.code }, error.status);
    }
    if (error instanceof DatabaseOperationError) {
      const expected = expectedDatabaseHttpError(error);
      if (expected) return response(expected.body, expected.status);
    }
    if (error instanceof TypeError || error instanceof SyntaxError) {
      return response({ error: "INVALID_REQUEST" }, 400);
    }
    console.error("clinical-attachments request failed", error);
    return response({ error: "INTERNAL_ERROR" }, 500);
  }
});
