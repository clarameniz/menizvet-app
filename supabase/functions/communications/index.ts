import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuredInvitationKey,
  createEncryptedInvitationSecret,
  type InvitationKind,
  postgresBytea,
} from "../_shared/communications/invitation-crypto.ts";
import {
  createStaffOrganizationInvitation,
  StaffInvitationError,
} from "../_shared/communications/organization-invitation.ts";
import { rpcSqlstateHttpStatus } from "../_shared/communications/rpc-errors.ts";

const CORS_HEADERS = Object.freeze({
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
});
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

class ResponseError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
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

function optionalUuid(value: unknown, name: string): string | null {
  return value === null || value === undefined
    ? null
    : requiredUuid(value, name);
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${name} is required`);
  }
  return value.trim();
}

async function requestBody(request: Request): Promise<Record<string, unknown>> {
  const body: unknown = await request.json();
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new TypeError("JSON object body is required");
  }
  return body as Record<string, unknown>;
}

function bearerToken(request: Request): string {
  const match = request.headers.get("authorization")?.match(
    /^Bearer\s+(.+)$/iu,
  );
  if (!match) throw new ResponseError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}

function jwtPayload(token: string): Record<string, unknown> {
  try {
    const encoded = token.split(".")[1];
    if (!encoded) throw new Error();
    const normalized = encoded.replaceAll("-", "+").replaceAll("_", "/");
    return JSON.parse(
      atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")),
    );
  } catch {
    throw new ResponseError(401, "AUTHENTICATION_REQUIRED");
  }
}

async function authenticatedContext(
  admin: SupabaseClient,
  request: Request,
): Promise<{ subject: string; sessionId: string | null }> {
  const token = bearerToken(request);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new ResponseError(401, "AUTHENTICATION_REQUIRED");
  }
  const sessionClaim = jwtPayload(token).session_id;
  const sessionId = sessionClaim === undefined
    ? null
    : requiredUuid(sessionClaim, "session_id");
  return { subject: data.user.id, sessionId };
}

function rpcValue<T>(
  data: T | null,
  error: { message: string; code?: string } | null,
): T {
  if (error || data === null) {
    throw new ResponseError(
      rpcSqlstateHttpStatus(error?.code),
      "DOMAIN_OPERATION_REJECTED",
    );
  }
  return data;
}

function activeKeyVersion(): number {
  const version = Number(Deno.env.get("INVITATION_SECRET_ACTIVE_KEY_VERSION"));
  if (!Number.isInteger(version) || version < 1) {
    throw new Error("Invitation active key version is missing");
  }
  return version;
}

async function invitationEnvelope(
  kind: InvitationKind,
  recipientEmail: string,
  expiresAt: string,
) {
  const version = activeKeyVersion();
  return await createEncryptedInvitationSecret(
    kind,
    version,
    configuredInvitationKey(version),
    recipientEmail,
    expiresAt,
  );
}

async function registerPush(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  const auth = await authenticatedContext(admin, request);
  if (!auth.sessionId) {
    throw new ResponseError(401, "SESSION_BOUNDARY_REQUIRED");
  }
  const body = await requestBody(request);
  const result = await admin.rpc("upsert_session_push_registration", {
    p_auth_subject: auth.subject,
    p_auth_session_id: auth.sessionId,
    p_device_installation_id: requiredUuid(
      body.device_installation_id,
      "device_installation_id",
    ),
    p_provider_token: requiredString(body.expo_push_token, "expo_push_token"),
    p_platform: requiredString(body.platform, "platform").toUpperCase(),
    p_application_id: requiredString(body.application_id, "application_id"),
  });
  return response({
    registration_id: rpcValue(result.data as string | null, result.error),
  });
}

async function disablePush(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  const auth = await authenticatedContext(admin, request);
  if (!auth.sessionId) {
    throw new ResponseError(401, "SESSION_BOUNDARY_REQUIRED");
  }
  const body = await requestBody(request);
  const result = await admin.rpc("invalidate_session_push_registration", {
    p_auth_subject: auth.subject,
    p_auth_session_id: auth.sessionId,
    p_registration_id: requiredUuid(body.registration_id, "registration_id"),
  });
  return response({
    invalidated: rpcValue(result.data as boolean | null, result.error),
  });
}

function expiration(value: unknown): string {
  const date = new Date(requiredString(value, "expires_at"));
  if (Number.isNaN(date.valueOf()) || date <= new Date()) {
    throw new TypeError("expires_at must be future ISO-8601 time");
  }
  return date.toISOString();
}

// Staff Phase 1 contract (SPEC-ORG-002 §10): the acting User is the verified
// subject; the creation instant and 7-day expiry are fixed server-side.
async function createOrganizationInvitation(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  const auth = await authenticatedContext(admin, request);
  const body = await requestBody(request);
  return response(
    await createStaffOrganizationInvitation(
      (name, args) => admin.rpc(name, args),
      (recipientEmail, expiresAt) =>
        invitationEnvelope("organization", recipientEmail, expiresAt),
      postgresBytea,
      auth.subject,
      body,
    ),
    201,
  );
}

async function createGuardianshipInvitation(
  admin: SupabaseClient,
  request: Request,
): Promise<Response> {
  const auth = await authenticatedContext(admin, request);
  const body = await requestBody(request);
  const recipientEmail = requiredString(
    body.recipient_email,
    "recipient_email",
  );
  const expiresAt = expiration(body.expires_at);
  const envelope = await invitationEnvelope(
    "guardianship",
    recipientEmail,
    expiresAt,
  );
  const result = await admin.rpc(
    "create_guardianship_invitation_with_communication",
    {
      p_auth_subject: auth.subject,
      p_pet_id: requiredUuid(body.pet_id, "pet_id"),
      p_inviting_guardianship_id: requiredUuid(
        body.inviting_guardianship_id,
        "inviting_guardianship_id",
      ),
      p_recipient_user_id: optionalUuid(
        body.recipient_user_id,
        "recipient_user_id",
      ),
      p_recipient_email: recipientEmail,
      p_expires_at: expiresAt,
      p_acceptance_secret_digest: postgresBytea(envelope.digest),
      p_secret_key_version: envelope.keyVersion,
      p_secret_nonce: postgresBytea(envelope.nonce),
      p_secret_ciphertext: postgresBytea(envelope.ciphertext),
    },
  );
  return response({
    invitation_id: rpcValue(result.data as string | null, result.error),
  }, 201);
}

function routeName(request: Request): string {
  const pathname = new URL(request.url).pathname.replace(/\/+$/u, "");
  return pathname.split("/").at(-1) ?? "";
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
    switch (routeName(request)) {
      case "register-push":
        return await registerPush(admin, request);
      case "disable-push":
        return await disablePush(admin, request);
      case "create-organization-invitation":
        return await createOrganizationInvitation(admin, request);
      case "create-guardianship-invitation":
        return await createGuardianshipInvitation(admin, request);
      default:
        return response({ error: "NOT_FOUND" }, 404);
    }
  } catch (error) {
    if (
      error instanceof ResponseError || error instanceof StaffInvitationError
    ) {
      return response({ error: error.code }, error.status);
    }
    if (error instanceof TypeError || error instanceof SyntaxError) {
      return response({ error: "INVALID_REQUEST" }, 400);
    }
    console.error(
      "communications request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return response({ error: "INTERNAL_ERROR" }, 500);
  }
});
