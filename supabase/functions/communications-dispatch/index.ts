import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuredInvitationKey,
  decryptInvitationSecret,
  postgresByteaToBytes,
} from "../_shared/communications/invitation-crypto.ts";
import {
  classifyExpoReceipt,
  type ProviderOutcome,
  sendExpoPush,
  sendResendEmail,
} from "../_shared/communications/providers.ts";
import {
  type DeliveryContext,
  renderEmail,
  renderPush,
} from "../_shared/communications/templates.ts";

const JSON_HEADERS = Object.freeze({
  "content-type": "application/json; charset=utf-8",
});

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function constantTimeSecret(
  expected: string | undefined,
  supplied: string | null,
): boolean {
  if (!expected || !supplied) return false;
  const left = new TextEncoder().encode(expected);
  const right = new TextEncoder().encode(supplied);
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function rpcValue<T>(data: T | null, error: { message: string } | null): T {
  if (error || data === null) throw new Error("Database operation failed");
  return data;
}

interface ClaimedJob {
  delivery_job_id: string;
  lease_token: string;
  communication_type: string;
  channel: "EMAIL" | "PUSH";
  provider: "RESEND" | "EXPO";
  provider_idempotency_key: string;
}

class DeliveryCompletionError extends Error {
  constructor(readonly providerOutcome: ProviderOutcome) {
    super("Delivery completion persistence failed");
  }
}

async function invitationSecret(
  context: Record<string, unknown>,
): Promise<string | undefined> {
  if (
    context.secret_envelope_version === null ||
    context.secret_envelope_version === undefined
  ) return undefined;
  if (
    context.secret_envelope_version !== 1 ||
    context.secret_algorithm !== "AES-256-GCM"
  ) {
    throw new Error("Unsupported Invitation envelope");
  }
  const version = Number(context.secret_key_version);
  if (
    !Number.isInteger(version) || typeof context.secret_aad_context !== "string"
  ) throw new Error("Invitation envelope metadata is invalid");
  return await decryptInvitationSecret(
    postgresByteaToBytes(context.secret_ciphertext),
    postgresByteaToBytes(context.secret_nonce),
    context.secret_aad_context,
    configuredInvitationKey(version),
  );
}

async function completeJob(
  admin: SupabaseClient,
  job: ClaimedJob,
  outcome: ProviderOutcome,
): Promise<string> {
  const result = await admin.rpc("complete_communication_delivery_job", {
    p_delivery_job_id: job.delivery_job_id,
    p_lease_token: job.lease_token,
    p_outcome: outcome.outcome,
    p_provider_message_id: outcome.messageId ?? null,
    p_provider_status: outcome.status ?? null,
    p_error_code: outcome.errorCode ?? null,
    p_retry_after_seconds: outcome.retryAfterSeconds ?? 60,
  });
  return rpcValue(result.data as string | null, result.error);
}

async function dispatchJob(
  admin: SupabaseClient,
  job: ClaimedJob,
): Promise<Record<string, unknown>> {
  const contextResult = await admin.rpc("get_communication_delivery_context", {
    p_delivery_job_id: job.delivery_job_id,
    p_lease_token: job.lease_token,
  });
  if (contextResult.error) throw new Error("Database operation failed");
  if (contextResult.data === null) {
    return {
      delivery_job_id: job.delivery_job_id,
      channel: job.channel,
      state: "SUPPRESSED",
    };
  }
  const context = contextResult.data as Record<string, unknown>;
  if (typeof context.recipient !== "string" || context.recipient === "") {
    throw new Error("Eligible delivery destination is missing");
  }
  const destination = context.recipient;
  let submitToProvider: () => Promise<ProviderOutcome>;
  if (job.channel === "EMAIL") {
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const resendFrom = Deno.env.get("RESEND_FROM_EMAIL");
    const publicAppUrl = Deno.env.get("COMMUNICATIONS_PUBLIC_APP_URL");
    if (!resendApiKey || !resendFrom || !publicAppUrl) {
      throw new Error("Email provider configuration is missing");
    }
    const secret = await invitationSecret(context);
    const message = renderEmail(
      context as unknown as DeliveryContext,
      publicAppUrl,
      secret,
    );
    submitToProvider = () =>
      sendResendEmail(
        resendApiKey,
        resendFrom,
        destination,
        message,
        job.provider_idempotency_key,
      );
  } else {
    const message = renderPush(context as unknown as DeliveryContext);
    submitToProvider = () =>
      sendExpoPush(
        Deno.env.get("EXPO_ACCESS_TOKEN") ?? null,
        destination,
        message,
      );
  }
  const startResult = await admin.rpc(
    "mark_communication_delivery_submission_started",
    {
      p_delivery_job_id: job.delivery_job_id,
      p_lease_token: job.lease_token,
    },
  );
  const startState = rpcValue(
    startResult.data as string | null,
    startResult.error,
  );
  if (startState === "SUPPRESSED") {
    return {
      delivery_job_id: job.delivery_job_id,
      channel: job.channel,
      state: startState,
    };
  }
  if (startState !== "STARTED") {
    throw new Error("Provider submission start was not established");
  }
  const providerOutcome = await submitToProvider();
  let state: string;
  try {
    state = await completeJob(admin, job, providerOutcome);
  } catch {
    throw new DeliveryCompletionError(providerOutcome);
  }
  return {
    delivery_job_id: job.delivery_job_id,
    channel: job.channel,
    state,
  };
}

async function processReceipts(admin: SupabaseClient): Promise<number> {
  const claimed = await admin.rpc("claim_expo_push_receipts", {
    p_limit: 100,
    p_lease_seconds: 120,
  });
  const receipts = rpcValue(
    claimed.data as
      | Array<{
        delivery_job_id: string;
        lease_token: string;
        ticket_id: string;
      }>
      | null,
    claimed.error,
  );
  if (receipts.length === 0) return 0;

  const headers: Record<string, string> = {
    accept: "application/json",
    "content-type": "application/json",
  };
  const accessToken = Deno.env.get("EXPO_ACCESS_TOKEN");
  if (accessToken) headers.authorization = `Bearer ${accessToken}`;
  let payload: {
    data?: Record<
      string,
      { status?: string; message?: string; details?: { error?: string } }
    >;
  } = {};
  try {
    const providerResponse = await fetch(
      "https://exp.host/--/api/v2/push/getReceipts",
      {
        method: "POST",
        headers,
        signal: AbortSignal.timeout(15_000),
        body: JSON.stringify({
          ids: receipts.map((receipt) => receipt.ticket_id),
        }),
      },
    );
    if (providerResponse.ok) payload = await providerResponse.json();
  } catch {
    // Each receipt is released as pending below.
  }

  for (const receipt of receipts) {
    const providerReceipt = payload.data?.[receipt.ticket_id];
    const evidence = classifyExpoReceipt(providerReceipt);
    const completed = await admin.rpc("complete_expo_push_receipt", {
      p_delivery_job_id: receipt.delivery_job_id,
      p_lease_token: receipt.lease_token,
      p_outcome: evidence.outcome,
      p_provider_status: evidence.status,
      p_error_code: evidence.errorCode ?? null,
      p_retry_after_seconds: evidence.retryAfterSeconds ?? 300,
    });
    rpcValue(completed.data as string | null, completed.error);
  }
  return receipts.length;
}

async function run(admin: SupabaseClient, request: Request): Promise<Response> {
  if (
    !constantTimeSecret(
      Deno.env.get("COMMUNICATIONS_MAINTENANCE_SECRET"),
      request.headers.get("x-maintenance-secret"),
    )
  ) {
    return response({ error: "MAINTENANCE_AUTHENTICATION_REQUIRED" }, 401);
  }
  let remindersCreated: number | null = null;
  let reminderError: string | null = null;
  const advanceHours = Number(
    Deno.env.get("REMINDER_ADVANCE_HOURS") ?? "24",
  );
  const catchupHours = Number(
    Deno.env.get("REMINDER_CATCHUP_HOURS") ?? "6",
  );
  if (
    !Number.isFinite(advanceHours) || advanceHours <= 0 ||
    !Number.isFinite(catchupHours) || catchupHours < 0
  ) {
    reminderError = "INVALID_REMINDER_CONFIGURATION";
  } else {
    const reminder = await admin.rpc("establish_due_appointment_reminders", {
      p_reference_time: new Date().toISOString(),
      p_advance: `${advanceHours} hours`,
      p_catchup: `${catchupHours} hours`,
      p_locale: Deno.env.get("COMMUNICATIONS_DEFAULT_LOCALE") ?? "es-ES",
    });
    if (reminder.error || reminder.data === null) {
      reminderError = "REMINDER_ESTABLISHMENT_FAILED";
    } else {
      remindersCreated = Number(reminder.data);
    }
  }
  const claimed = await admin.rpc("claim_communication_delivery_jobs", {
    p_limit: 10,
    p_lease_seconds: 300,
  });
  const jobs = rpcValue(
    claimed.data as ClaimedJob[] | null,
    claimed.error,
  );
  const results: Array<Record<string, unknown>> = [];
  for (const job of jobs) {
    try {
      results.push(await dispatchJob(admin, job));
    } catch (error) {
      try {
        const completion = error instanceof DeliveryCompletionError
          ? error.providerOutcome
          : {
            outcome: "RETRYABLE" as const,
            errorCode: "DISPATCHER_FAILURE",
            retryAfterSeconds: 60,
          };
        const state = await completeJob(admin, job, completion);
        results.push({
          delivery_job_id: job.delivery_job_id,
          channel: job.channel,
          state,
        });
      } catch {
        results.push({
          delivery_job_id: job.delivery_job_id,
          channel: job.channel,
          state: "LEASED_UNRESOLVED",
        });
      }
    }
  }
  const receiptsProcessed = await processReceipts(admin);
  return response({
    status: "COMPLETE",
    reminders_created: remindersCreated,
    reminder_error: reminderError,
    jobs_processed: results.length,
    receipts_processed: receiptsProcessed,
    results,
  });
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
  if (request.method !== "POST") {
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  try {
    return await run(admin, request);
  } catch (error) {
    console.error(
      "communications dispatch failed",
      error instanceof Error ? error.message : "unknown",
    );
    return response({ error: "INTERNAL_ERROR" }, 500);
  }
});
