import { createClient } from "@supabase/supabase-js";
import {
  isResendDomainCommunication,
  resendWebhookPersistenceStatus,
  verifyResendWebhook,
} from "../_shared/communications/resend-webhook.ts";

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET");
if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
  throw new Error("Resend webhook configuration is missing");
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
  const rawBody = await request.text();
  if (!await verifyResendWebhook(rawBody, request.headers, webhookSecret)) {
    return response({ error: "INVALID_WEBHOOK_SIGNATURE" }, 401);
  }
  try {
    const event: unknown = JSON.parse(rawBody);
    if (typeof event !== "object" || event === null || Array.isArray(event)) {
      throw new TypeError();
    }
    const record = event as Record<string, unknown>;
    const data = record.data;
    if (
      typeof record.type !== "string" ||
      typeof record.created_at !== "string" || typeof data !== "object" ||
      data === null || Array.isArray(data)
    ) {
      throw new TypeError();
    }
    const dataRecord = data as Record<string, unknown>;
    if (!isResendDomainCommunication(dataRecord.tags)) {
      return response({ accepted: true, state: "IGNORED" });
    }
    const emailId = dataRecord.email_id;
    const eventId = request.headers.get("svix-id");
    if (typeof emailId !== "string" || !eventId) throw new TypeError();
    const occurredAt = new Date(record.created_at);
    if (Number.isNaN(occurredAt.valueOf())) throw new TypeError();
    const result = await admin.rpc("record_resend_delivery_event", {
      p_provider_event_id: eventId,
      p_event_type: record.type,
      p_provider_message_id: emailId,
      p_occurred_at: occurredAt.toISOString(),
    });
    if (result.error) throw new Error("Webhook persistence failed");
    const persistenceStatus = resendWebhookPersistenceStatus(result.data);
    if (persistenceStatus !== 200) {
      return response({ accepted: false, state: "UNMATCHED" }, 503);
    }
    return response({ accepted: true, state: result.data });
  } catch (error) {
    if (error instanceof TypeError || error instanceof SyntaxError) {
      return response({ error: "INVALID_EVENT" }, 400);
    }
    console.error(
      "Resend webhook failed",
      error instanceof Error ? error.message : "unknown",
    );
    return response({ error: "INTERNAL_ERROR" }, 500);
  }
});
