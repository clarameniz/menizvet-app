import type { EncryptedInvitationSecret } from "./invitation-crypto.ts";

/**
 * Staff Phase 1 `create-organization-invitation` (SPEC-ORG-002 §10).
 *
 * The client names one Organization, one recipient address, one
 * responsibility and one scope (plus a Clinic only for Clinic scope). Every
 * other member, including `expires_at`, `recipient_user_id` and an
 * `intended_responsibilities` array, is rejected. The acting User is the
 * verified Auth subject, never request data.
 *
 * Order (BR-22): the request shape is checked first (it depends on nothing
 * stored); then `authorize_organization_invitation_creation` decides
 * authentication, account verification, and Organization + capability
 * together, and returns the creation instant T from database time; only then
 * are the values judged and the one-time secret generated. The envelope binds
 * exactly T + 7 days, and the create command stores created_at = T and
 * derives the same expiry itself (BR-18). The secret, its digest and the
 * envelope never leave this function except towards the database command.
 */
export const INVITATION_VALIDITY_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;

const REQUEST_MEMBERS = new Set([
  "organization_id",
  "recipient_email",
  "responsibility",
  "scope_type",
  "clinic_id",
]);
const INVITABLE_RESPONSIBILITIES = new Set([
  "ADMINISTRATOR",
  "RECEPTIONIST",
  "VETERINARIAN",
]);
const CLINIC_RESPONSIBILITIES = new Set(["ADMINISTRATOR", "RECEPTIONIST"]);
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
// The database's btrim set; JavaScript trim() removes more characters.
const DATABASE_TRIM = /^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/gu;

export type StaffInvitationErrorCode =
  | "INVALID_REQUEST"
  | "AUTHENTICATION_REQUIRED"
  | "ACCOUNT_VERIFICATION_REQUIRED"
  | "ORGANIZATION_UNAVAILABLE"
  | "INVALID_RECIPIENT"
  | "INVALID_ROLE_SCOPE"
  | "INVALID_CLINIC"
  | "PENDING_INVITATION_EXISTS"
  | "ACTIVE_MEMBER"
  | "INTERNAL_ERROR";

export class StaffInvitationError extends Error {
  constructor(
    readonly status: number,
    readonly code: StaffInvitationErrorCode,
  ) {
    super(code);
  }
}

export type RpcError = {
  readonly code?: string;
  readonly hint?: string | null;
  readonly message: string;
};
export type Rpc = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: RpcError | null }>;
export type InvitationEnvelopeFactory = (
  recipientEmail: string,
  expiresAt: string,
) => Promise<EncryptedInvitationSecret>;
export type ByteaEncoder = (bytes: Uint8Array) => string;

type StaffInvitationRequest = {
  organizationId: string;
  recipientEmail: string;
  responsibility: string;
  scopeType: string;
  clinicId: string | null;
};

/** Contract shape only; nothing here depends on stored state. */
export function parseStaffInvitationRequest(
  body: Record<string, unknown>,
): StaffInvitationRequest {
  const invalid = () => new StaffInvitationError(400, "INVALID_REQUEST");
  if (Object.keys(body).some((member) => !REQUEST_MEMBERS.has(member))) {
    throw invalid();
  }
  const {
    organization_id,
    recipient_email,
    responsibility,
    scope_type,
    clinic_id,
  } = body;
  if (
    typeof organization_id !== "string" || !UUID.test(organization_id) ||
    typeof recipient_email !== "string" ||
    typeof responsibility !== "string" ||
    typeof scope_type !== "string" ||
    (clinic_id !== undefined && clinic_id !== null &&
      typeof clinic_id !== "string")
  ) {
    throw invalid();
  }
  return {
    organizationId: organization_id.toLowerCase(),
    recipientEmail: recipient_email,
    responsibility,
    scopeType: scope_type,
    clinicId: clinic_id ?? null,
  };
}

/** Maps the commands' SQLSTATE + hint to calm client outcomes; never raw errors. */
export function staffInvitationRpcFailure(
  error: RpcError,
): StaffInvitationError {
  switch (error.code) {
    case "28000":
      return new StaffInvitationError(401, "AUTHENTICATION_REQUIRED");
    case "42501":
      return new StaffInvitationError(
        403,
        error.hint === "ACCOUNT_VERIFICATION_REQUIRED"
          ? "ACCOUNT_VERIFICATION_REQUIRED"
          : "ORGANIZATION_UNAVAILABLE",
      );
    case "22023":
      if (
        error.hint === "INVALID_RECIPIENT" ||
        error.hint === "INVALID_ROLE_SCOPE" ||
        error.hint === "INVALID_CLINIC"
      ) {
        return new StaffInvitationError(400, error.hint);
      }
      // Trusted instant/credential material is never the client's fault.
      return new StaffInvitationError(500, "INTERNAL_ERROR");
    case "23505":
      return new StaffInvitationError(
        409,
        error.hint === "ACTIVE_MEMBER"
          ? "ACTIVE_MEMBER"
          : "PENDING_INVITATION_EXISTS",
      );
    default:
      return new StaffInvitationError(500, "INTERNAL_ERROR");
  }
}

function creationInstant(raw: unknown): Date {
  const instant = typeof raw === "string" ? new Date(raw) : null;
  if (instant === null || !Number.isSafeInteger(instant.valueOf())) {
    throw new StaffInvitationError(500, "INTERNAL_ERROR");
  }
  return instant;
}

/** After authorization: values mirror the database command, which decides. */
function validatedValues(request: StaffInvitationRequest): {
  recipientEmail: string;
  clinicId: string | null;
} {
  const recipientEmail = request.recipientEmail.replace(DATABASE_TRIM, "");
  if (recipientEmail === "" || recipientEmail !== recipientEmail.trim()) {
    throw new StaffInvitationError(400, "INVALID_RECIPIENT");
  }
  const { responsibility, scopeType, clinicId } = request;
  if (
    !INVITABLE_RESPONSIBILITIES.has(responsibility) ||
    (scopeType === "ORGANIZATION" && clinicId !== null) ||
    (scopeType === "CLINIC" &&
      (clinicId === null || !CLINIC_RESPONSIBILITIES.has(responsibility))) ||
    (scopeType !== "ORGANIZATION" && scopeType !== "CLINIC")
  ) {
    throw new StaffInvitationError(400, "INVALID_ROLE_SCOPE");
  }
  if (clinicId !== null && !UUID.test(clinicId)) {
    throw new StaffInvitationError(400, "INVALID_CLINIC");
  }
  return {
    recipientEmail,
    clinicId: clinicId === null ? null : clinicId.toLowerCase(),
  };
}

export async function createStaffOrganizationInvitation(
  rpc: Rpc,
  createEnvelope: InvitationEnvelopeFactory,
  bytea: ByteaEncoder,
  authSubject: string,
  body: Record<string, unknown>,
): Promise<{ invitation_id: string }> {
  const request = parseStaffInvitationRequest(body);

  const authorized = await rpc("authorize_organization_invitation_creation", {
    p_auth_subject: authSubject,
    p_organization_id: request.organizationId,
  });
  if (authorized.error) throw staffInvitationRpcFailure(authorized.error);
  const createdAt = creationInstant(authorized.data);

  const { recipientEmail, clinicId } = validatedValues(request);
  const expiresAt = new Date(
    createdAt.valueOf() + INVITATION_VALIDITY_MILLISECONDS,
  ).toISOString();
  const envelope = await createEnvelope(recipientEmail, expiresAt);

  // Never retried: a lost response is reconciled by the client's re-read.
  const created = await rpc(
    "create_staff_organization_invitation_with_communication",
    {
      p_auth_subject: authSubject,
      p_organization_id: request.organizationId,
      p_recipient_email: recipientEmail,
      p_responsibility: request.responsibility,
      p_scope_type: request.scopeType,
      p_clinic_id: clinicId,
      p_created_at: createdAt.toISOString(),
      p_acceptance_secret_digest: bytea(envelope.digest),
      p_secret_key_version: envelope.keyVersion,
      p_secret_nonce: bytea(envelope.nonce),
      p_secret_ciphertext: bytea(envelope.ciphertext),
    },
  );
  if (created.error) throw staffInvitationRpcFailure(created.error);
  if (typeof created.data !== "string" || !UUID.test(created.data)) {
    throw new StaffInvitationError(500, "INTERNAL_ERROR");
  }
  return { invitation_id: created.data.toLowerCase() };
}
