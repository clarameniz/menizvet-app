import type { RenderedEmail, RenderedPush } from "./templates.ts";
import { RESEND_DOMAIN_COMMUNICATION_TAG } from "./resend-webhook.ts";

export type ProviderOutcome = Readonly<{
  outcome:
    | "ACCEPTED"
    | "DELIVERED"
    | "RETRYABLE"
    | "PERMANENT_FAILURE"
    | "UNKNOWN";
  messageId?: string;
  status?: string;
  errorCode?: string;
  retryAfterSeconds?: number;
}>;

export type ExpoReceiptOutcome = Readonly<{
  outcome:
    | "UPSTREAM_ACCEPTED"
    | "RETRYABLE"
    | "PERMANENT_FAILURE"
    | "PENDING";
  status: string;
  errorCode?: string;
  retryAfterSeconds?: number;
}>;

export function classifyExpoReceipt(
  receipt:
    | { status?: string; message?: string; details?: { error?: string } }
    | undefined,
): ExpoReceiptOutcome {
  const errorCode = receipt?.details?.error;
  if (receipt?.status === "ok") {
    return {
      outcome: "UPSTREAM_ACCEPTED",
      status: receipt.message ?? "receipt_ok",
    };
  }
  if (receipt?.status === "error" && errorCode === "MessageRateExceeded") {
    return {
      outcome: "RETRYABLE",
      status: receipt.message ?? "receipt_error",
      errorCode,
      retryAfterSeconds: 300,
    };
  }
  if (receipt?.status === "error") {
    return {
      outcome: "PERMANENT_FAILURE",
      status: receipt.message ?? "receipt_error",
      errorCode: errorCode ?? "UNKNOWN_RECEIPT_ERROR",
    };
  }
  return {
    outcome: "PENDING",
    status: receipt?.message ?? receipt?.status ?? "receipt_pending",
    retryAfterSeconds: 300,
  };
}

function retryAfter(response: Response): number {
  const parsed = Number(response.headers.get("retry-after"));
  return Number.isFinite(parsed) && parsed >= 1
    ? Math.min(Math.ceil(parsed), 86400)
    : 60;
}

export async function sendResendEmail(
  apiKey: string,
  from: string,
  to: string,
  message: RenderedEmail,
  idempotencyKey: string,
  fetcher: typeof fetch = fetch,
): Promise<ProviderOutcome> {
  try {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
        "idempotency-key": idempotencyKey,
      },
      signal: AbortSignal.timeout(15_000),
      body: JSON.stringify({
        from,
        to: [to],
        ...message,
        tags: [RESEND_DOMAIN_COMMUNICATION_TAG],
      }),
    });
    let payload: Record<string, unknown> = {};
    try {
      payload = await response.json() as Record<string, unknown>;
    } catch {
      // Status classification remains authoritative even without JSON.
    }
    if (response.ok && typeof payload.id === "string") {
      return { outcome: "ACCEPTED", messageId: payload.id, status: "accepted" };
    }
    const code = typeof payload.name === "string"
      ? payload.name
      : `HTTP_${response.status}`;
    if (response.status === 429 || response.status >= 500 || response.ok) {
      return {
        outcome: "RETRYABLE",
        errorCode: code,
        retryAfterSeconds: retryAfter(response),
      };
    }
    return {
      outcome: "PERMANENT_FAILURE",
      errorCode: code,
      status: "rejected",
    };
  } catch {
    // An ambiguous timeout is retried with the same Resend idempotency key.
    return {
      outcome: "RETRYABLE",
      errorCode: "AMBIGUOUS_PROVIDER_TIMEOUT",
      retryAfterSeconds: 60,
    };
  }
}

export async function sendExpoPush(
  accessToken: string | null,
  to: string,
  message: RenderedPush,
  fetcher: typeof fetch = fetch,
): Promise<ProviderOutcome> {
  try {
    const headers: Record<string, string> = {
      accept: "application/json",
      "accept-encoding": "gzip, deflate",
      "content-type": "application/json",
    };
    if (accessToken) headers.authorization = `Bearer ${accessToken}`;
    const response = await fetcher("https://exp.host/--/api/v2/push/send", {
      method: "POST",
      headers,
      signal: AbortSignal.timeout(15_000),
      body: JSON.stringify({ to, sound: "default", ...message }),
    });
    if (response.status === 429 || response.status >= 500) {
      return {
        outcome: "RETRYABLE",
        errorCode: `HTTP_${response.status}`,
        retryAfterSeconds: retryAfter(response),
      };
    }
    const payload = await response.json() as {
      data?: {
        status?: string;
        id?: string;
        message?: string;
        details?: { error?: string };
      };
    };
    const ticket = payload.data;
    if (response.ok && ticket?.status === "ok" && ticket.id) {
      return { outcome: "ACCEPTED", messageId: ticket.id, status: "ticket_ok" };
    }
    if (response.ok && ticket?.status !== "error") {
      return {
        outcome: "UNKNOWN",
        errorCode: "AMBIGUOUS_PROVIDER_RESPONSE",
      };
    }
    const error = ticket?.details?.error ?? `HTTP_${response.status}`;
    const permanent = [
      "DeviceNotRegistered",
      "MessageTooBig",
      "MismatchSenderId",
      "InvalidCredentials",
    ].includes(error);
    return permanent
      ? {
        outcome: "PERMANENT_FAILURE",
        errorCode: error,
        status: ticket?.message,
      }
      : { outcome: "RETRYABLE", errorCode: error, retryAfterSeconds: 60 };
  } catch {
    // Expo has no per-message provider idempotency key. A lost response cannot
    // prove whether the provider accepted the operation, so automatic
    // resubmission would risk a duplicate Push.
    return {
      outcome: "UNKNOWN",
      errorCode: "AMBIGUOUS_PROVIDER_TIMEOUT",
    };
  }
}
