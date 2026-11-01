import { assert, assertEquals, assertRejects } from "./assertions.ts";
import {
  createEncryptedInvitationSecret,
  decryptInvitationSecret,
  invitationAadContext,
} from "../../_shared/communications/invitation-crypto.ts";
import {
  classifyExpoReceipt,
  sendExpoPush,
  sendResendEmail,
} from "../../_shared/communications/providers.ts";
import {
  type DeliveryContext,
  renderEmail,
  renderPush,
} from "../../_shared/communications/templates.ts";
import {
  isResendDomainCommunication,
  RESEND_DOMAIN_COMMUNICATION_TAG,
  resendWebhookPersistenceStatus,
  verifyResendWebhook,
} from "../../_shared/communications/resend-webhook.ts";
import { rpcSqlstateHttpStatus } from "../../_shared/communications/rpc-errors.ts";

Deno.test("Invitation credentials round-trip only with matching versioned AES-GCM context", async () => {
  const key = crypto.getRandomValues(new Uint8Array(32));
  const expiresAt = "2030-01-02T03:04:05.678Z";
  assertEquals(
    invitationAadContext(
      "organization",
      " New-Org@Example.Test ",
      "2030-01-01T00:00:00.000Z",
      Uint8Array.from({ length: 32 }, () => 0x22),
    ),
    "petcare.invitation.organization.v1|recipient_email_hex=" +
      "6e65772d6f7267406578616d706c652e74657374" +
      "|expires_at_ms=1893456000000|acceptance_digest_hex=" + "22".repeat(32),
  );
  const envelope = await createEncryptedInvitationSecret(
    "organization",
    7,
    key,
    "Recipient@Example.test",
    expiresAt,
  );
  assertEquals(envelope.keyVersion, 7);
  assertEquals(envelope.nonce.byteLength, 12);
  assert(envelope.ciphertext.byteLength > envelope.secret.length);
  assertEquals(
    await decryptInvitationSecret(
      envelope.ciphertext,
      envelope.nonce,
      envelope.aadContext,
      key,
    ),
    envelope.secret,
  );
  await assertRejects(() =>
    decryptInvitationSecret(
      envelope.ciphertext,
      envelope.nonce,
      invitationAadContext(
        "guardianship",
        "Recipient@Example.test",
        expiresAt,
        envelope.digest,
      ),
      key,
    )
  );
  await assertRejects(() =>
    decryptInvitationSecret(
      envelope.ciphertext,
      envelope.nonce,
      invitationAadContext(
        "organization",
        "another-recipient@example.test",
        expiresAt,
        envelope.digest,
      ),
      key,
    )
  );
  await assertRejects(() =>
    decryptInvitationSecret(
      envelope.ciphertext,
      envelope.nonce,
      invitationAadContext(
        "organization",
        "Recipient@Example.test",
        "2030-01-03T03:04:05.678Z",
        envelope.digest,
      ),
      key,
    )
  );
});

Deno.test("Appointment push is privacy-minimized and Invitation secret is email-only", async () => {
  const appointmentId = crypto.randomUUID();
  const petId = crypto.randomUUID();
  const appointment: DeliveryContext = {
    communication_id: crypto.randomUUID(),
    communication_type: "APPOINTMENT_CONFIRMED",
    locale: "es-ES",
    recipient: "ExponentPushToken[test]",
    appointment_id: appointmentId,
    pet_id: petId,
    pet_name: "Luna",
    clinic_name: "Animalia",
    scheduled_start_at: "2030-01-02T09:00:00Z",
    timezone_name: "Europe/Madrid",
  };
  const push = renderPush(appointment);
  assertEquals(push.title, "MenizVet");
  assert(push.body.includes("Luna"));
  assert(!JSON.stringify(push).includes("Animalia"));
  assert(!JSON.stringify(push).includes("2030"));
  assertEquals(push.data.route, "appointment");
  assertEquals(push.data.appointment_id, appointmentId);
  assertEquals(push.data.pet_id, petId);

  const missingPetId: DeliveryContext = { ...appointment, pet_id: null };
  await assertRejects(() => Promise.resolve(renderPush(missingPetId)));

  const invitation: DeliveryContext = {
    communication_id: crypto.randomUUID(),
    communication_type: "ORGANIZATION_INVITATION",
    locale: "es-ES",
    recipient: "recipient@example.test",
    organization_invitation_id: crypto.randomUUID(),
    organization_name: "Animalia",
  };
  const email = renderEmail(
    invitation,
    "https://app.example.test",
    "one-time-secret",
  );
  assert(email.text.includes("#secret=one-time-secret"));
  assert(!email.text.includes("&secret="));
  await assertRejects(() => Promise.resolve(renderPush(invitation)));
});

Deno.test("Appointment email links to the detail route with the Pet identity", async () => {
  const appointmentId = crypto.randomUUID();
  const petId = crypto.randomUUID();
  const appointment: DeliveryContext = {
    communication_id: crypto.randomUUID(),
    communication_type: "APPOINTMENT_CONFIRMED",
    locale: "es-ES",
    recipient: "guardian@example.test",
    appointment_id: appointmentId,
    pet_id: petId,
    pet_name: "Luna",
  };
  const expectedUrl =
    `https://app.example.test/appointments/${appointmentId}?petId=${petId}`;
  const email = renderEmail(appointment, "https://app.example.test/ignored");
  assertEquals(
    email.text,
    `La cita de Luna se ha confirmado. Consulta el estado actual: ${expectedUrl}`,
  );
  assertEquals(
    email.html,
    `<p>La cita de Luna se ha confirmado.</p><p><a href="${expectedUrl}">Consultar estado actual</a></p>`,
  );
  assertEquals(email.subject, "Actualización de la cita de Luna");

  const encoded = renderEmail(
    { ...appointment, appointment_id: "a/b", pet_id: "c&d" },
    "https://app.example.test",
  );
  assert(
    encoded.text.endsWith(
      "https://app.example.test/appointments/a%2Fb?petId=c%26d",
    ),
  );
  assert(
    encoded.html.includes(
      'href="https://app.example.test/appointments/a%2Fb?petId=c%26d"',
    ),
  );

  await assertRejects(() =>
    Promise.resolve(
      renderEmail({ ...appointment, pet_id: null }, "https://app.example.test"),
    )
  );
});

Deno.test("Alternative time copy says it is a proposal for the request and not yet confirmed", () => {
  const appointmentId = crypto.randomUUID();
  const petId = crypto.randomUUID();
  const alternative: DeliveryContext = {
    communication_id: crypto.randomUUID(),
    communication_type: "APPOINTMENT_ALTERNATIVE_TIME_PROPOSED",
    locale: "es-ES",
    recipient: "guardian@example.test",
    appointment_id: appointmentId,
    pet_id: petId,
    pet_name: "Luna",
    clinic_name: "Animalia",
    // The proposed start, as get_communication_delivery_context resolves it.
    scheduled_start_at: "2035-03-06T11:00:00Z",
    timezone_name: "Europe/Madrid",
    reschedule_proposal_id: crypto.randomUUID(),
  };
  const expectedUrl =
    `https://app.example.test/appointments/${appointmentId}?petId=${petId}`;
  const email = renderEmail(alternative, "https://app.example.test");
  assert(
    email.text.startsWith(
      "La clínica Animalia propone otro horario para la solicitud de cita de Luna: ",
    ),
  );
  assert(email.text.includes("12:00"));
  assert(email.text.includes("La cita aún no está confirmada."));
  assert(email.text.endsWith(expectedUrl));
  assert(email.html.includes("La cita aún no está confirmada."));
  assert(!email.text.includes("se ha confirmado"));
  assert(!email.text.includes("se ha reprogramado"));
  assertEquals(
    email.subject,
    "La clínica propone otro horario para la cita de Luna",
  );

  const withoutClinic = renderEmail(
    { ...alternative, clinic_name: null, scheduled_start_at: null },
    "https://app.example.test",
  );
  assert(
    withoutClinic.text.startsWith(
      "La clínica propone otro horario para la solicitud de cita de Luna. La cita aún no está confirmada.",
    ),
  );

  const push = renderPush({
    ...alternative,
    recipient: "ExponentPushToken[t]",
  });
  assertEquals(
    push.body,
    "La clínica propone otro horario para la solicitud de cita de Luna. La cita aún no está confirmada.",
  );
  assert(!JSON.stringify(push).includes("Animalia"));
  assert(!JSON.stringify(push).includes("2035"));
  assertEquals(push.data.route, "appointment");
  assertEquals(push.data.appointment_id, appointmentId);
  assertEquals(push.data.pet_id, petId);

  // The confirmed-reschedule proposal keeps its own, unchanged wording.
  const confirmedProposal = renderEmail(
    { ...alternative, communication_type: "APPOINTMENT_RESCHEDULE_PROPOSED" },
    "https://app.example.test",
  );
  assert(
    confirmedProposal.text.startsWith(
      "La cita de Luna en Animalia tiene una propuesta de cambio de horario para ",
    ),
  );
  assertEquals(
    renderPush({
      ...alternative,
      communication_type: "APPOINTMENT_RESCHEDULE_PROPOSED",
    }).body,
    "Hay una actualización sobre la cita de Luna.",
  );
});

Deno.test("Alternative time push reaches the Guardian device as a not-yet-confirmed request update", async () => {
  const appointmentId = crypto.randomUUID();
  const petId = crypto.randomUUID();
  const proposalId = crypto.randomUUID();
  // The PUSH delivery context get_communication_delivery_context returns for
  // a live alternative: the Guardian's own provider token and the proposed
  // (not the current requested) start.
  const pushContext: DeliveryContext = {
    communication_id: crypto.randomUUID(),
    communication_type: "APPOINTMENT_ALTERNATIVE_TIME_PROPOSED",
    locale: "es-ES",
    recipient: "ExponentPushToken[guardian-device]",
    appointment_id: appointmentId,
    pet_id: petId,
    pet_name: "Luna",
    clinic_name: "Animalia",
    scheduled_start_at: "2035-03-07T10:00:00Z",
    timezone_name: "Europe/Madrid",
    reschedule_proposal_id: proposalId,
  };
  const push = renderPush(pushContext);
  assertEquals(push.title, "MenizVet");
  assertEquals(
    push.body,
    "La clínica propone otro horario para la solicitud de cita de Luna. La cita aún no está confirmada.",
  );
  for (
    const forbidden of ["se ha confirmado", "se ha reprogramado", "ha cambiado"]
  ) {
    assert(!push.body.includes(forbidden), `push body reads as "${forbidden}"`);
  }
  // Privacy-minimized: no Clinic, time, Proposal or token in the payload.
  const payload = JSON.stringify(push);
  for (
    const secret of [
      "Animalia",
      "2035",
      "11:00",
      proposalId,
      "ExponentPushToken",
    ]
  ) {
    assert(!payload.includes(secret), `push payload leaks ${secret}`);
  }
  assertEquals(
    JSON.stringify(push.data),
    JSON.stringify({
      route: "appointment",
      appointment_id: appointmentId,
      pet_id: petId,
    }),
  );
  assertEquals(
    renderPush({ ...pushContext, pet_name: null }).body,
    "La clínica propone otro horario para la solicitud de cita de tu mascota. La cita aún no está confirmada.",
  );

  // Submitted to Expo for exactly the context's recipient device.
  let submitted: Record<string, unknown> = {};
  const outcome = await sendExpoPush(
    null,
    pushContext.recipient,
    push,
    ((_url: string, init: RequestInit) => {
      submitted = JSON.parse(String(init.body));
      return Promise.resolve(
        new Response(
          JSON.stringify({ data: { status: "ok", id: "ticket-alt" } }),
          { status: 200 },
        ),
      );
    }) as typeof fetch,
  );
  assertEquals(outcome.outcome, "ACCEPTED");
  assertEquals(submitted.to, "ExponentPushToken[guardian-device]");
  assertEquals(submitted.body, push.body);
  assertEquals(JSON.stringify(submitted.data), JSON.stringify(push.data));

  // Every other Appointment push, the CONFIRMED reschedule types included,
  // keeps the unchanged generic wording.
  for (
    const type of [
      "APPOINTMENT_RESCHEDULE_PROPOSED",
      "APPOINTMENT_RESCHEDULE_ACCEPTED",
      "APPOINTMENT_CONFIRMED",
      "APPOINTMENT_REQUESTED",
    ]
  ) {
    const unchanged = renderPush({ ...pushContext, communication_type: type });
    assertEquals(
      unchanged.body,
      "Hay una actualización sobre la cita de Luna.",
    );
    assertEquals(JSON.stringify(unchanged.data), JSON.stringify(push.data));
  }
});

Deno.test("Resend receives a stable provider idempotency key and ambiguous timeouts retry", async () => {
  let observedKey = "";
  let observedTags: unknown;
  const accepted = await sendResendEmail(
    "key",
    "MenizVet <noreply@example.test>",
    "recipient@example.test",
    { subject: "Subject", text: "Text", html: "<p>Text</p>" },
    "delivery-job-id",
    ((_input: RequestInfo | URL, init?: RequestInit) => {
      observedKey = new Headers(init?.headers).get("idempotency-key") ?? "";
      observedTags = JSON.parse(String(init?.body)).tags;
      return Promise.resolve(
        new Response(JSON.stringify({ id: "resend-message" }), {
          status: 200,
        }),
      );
    }) as typeof fetch,
  );
  assertEquals(observedKey, "delivery-job-id");
  assertEquals(
    JSON.stringify(observedTags),
    JSON.stringify([RESEND_DOMAIN_COMMUNICATION_TAG]),
  );
  assertEquals(accepted.outcome, "ACCEPTED");

  const ambiguous = await sendResendEmail(
    "key",
    "from@example.test",
    "to@example.test",
    { subject: "Subject", text: "Text", html: "<p>Text</p>" },
    "delivery-job-id",
    (() => Promise.reject(new TypeError("timeout"))) as typeof fetch,
  );
  assertEquals(ambiguous.outcome, "RETRYABLE");
  assertEquals(ambiguous.errorCode, "AMBIGUOUS_PROVIDER_TIMEOUT");
});

Deno.test("Resend webhook source correlation separates domain API mail from Auth SMTP mail", () => {
  assert(isResendDomainCommunication({
    petcare_source: "domain_communication",
  }));
  assert(isResendDomainCommunication([RESEND_DOMAIN_COMMUNICATION_TAG]));
  assert(!isResendDomainCommunication(undefined));
  assert(!isResendDomainCommunication({}));
  assert(!isResendDomainCommunication({ petcare_source: "supabase_auth" }));
  assert(
    !isResendDomainCommunication([
      { name: "auth_message", value: "password_recovery" },
    ]),
  );
});

Deno.test("Expo ambiguous submission closes UNKNOWN while proven rejection remains retryable", async () => {
  const ambiguous = await sendExpoPush(
    null,
    "ExponentPushToken[test]",
    { title: "MenizVet", body: "Update", data: { route: "appointment" } },
    (() => Promise.reject(new TypeError("response lost"))) as typeof fetch,
  );
  assertEquals(ambiguous.outcome, "UNKNOWN");
  assert(ambiguous.outcome !== "RETRYABLE");

  const rejectedBeforeAcceptance = await sendExpoPush(
    null,
    "ExponentPushToken[test]",
    { title: "MenizVet", body: "Update", data: { route: "appointment" } },
    (() =>
      Promise.resolve(new Response(null, { status: 503 }))) as typeof fetch,
  );
  assertEquals(rejectedBeforeAcceptance.outcome, "RETRYABLE");
});

Deno.test("Expo ticket and receipt preserve upstream-only evidence", async () => {
  const outcome = await sendExpoPush(
    null,
    "ExponentPushToken[test]",
    { title: "MenizVet", body: "Update", data: { route: "appointment" } },
    (() =>
      Promise.resolve(
        new Response(
          JSON.stringify({ data: { status: "ok", id: "ticket-1" } }),
          { status: 200 },
        ),
      )) as typeof fetch,
  );
  assertEquals(outcome.outcome, "ACCEPTED");
  assertEquals(outcome.messageId, "ticket-1");

  const receipt = classifyExpoReceipt({ status: "ok" });
  assertEquals(receipt.outcome, "UPSTREAM_ACCEPTED");
  assert((receipt.outcome as string) !== "DELIVERED");
});

Deno.test("Expo DeviceNotRegistered remains a permanent provider rejection", () => {
  const receipt = classifyExpoReceipt({
    status: "error",
    message: "Device is not registered",
    details: { error: "DeviceNotRegistered" },
  });
  assertEquals(receipt.outcome, "PERMANENT_FAILURE");
  assertEquals(receipt.errorCode, "DeviceNotRegistered");
});

Deno.test("Resend webhook verification rejects stale or changed payloads", async () => {
  const secretBytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of secretBytes) binary += String.fromCharCode(byte);
  const secret = `whsec_${btoa(binary)}`;
  const now = 2_000_000_000;
  const id = "msg_test";
  const body = '{"type":"email.delivered"}';
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(secretBytes).buffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${id}.${now}.${body}`),
    ),
  );
  let signatureBinary = "";
  for (const byte of signatureBytes) {
    signatureBinary += String.fromCharCode(byte);
  }
  const headers = new Headers({
    "svix-id": id,
    "svix-timestamp": String(now),
    "svix-signature": `v1,${btoa(signatureBinary)}`,
  });
  assert(await verifyResendWebhook(body, headers, secret, now));
  assert(!await verifyResendWebhook(`${body} `, headers, secret, now));
  assert(!await verifyResendWebhook(body, headers, secret, now + 301));
  assertEquals(resendWebhookPersistenceStatus("UNMATCHED"), 503);
  assertEquals(resendWebhookPersistenceStatus("DELIVERED"), 200);
});

Deno.test("client Edge maps only expected SQLSTATE classes to non-500 responses", () => {
  assertEquals(rpcSqlstateHttpStatus("28000"), 401);
  assertEquals(rpcSqlstateHttpStatus("42501"), 403);
  assertEquals(rpcSqlstateHttpStatus("22023"), 400);
  assertEquals(rpcSqlstateHttpStatus("23514"), 400);
  assertEquals(rpcSqlstateHttpStatus("23505"), 409);
  assertEquals(rpcSqlstateHttpStatus("55000"), 500);
  assertEquals(rpcSqlstateHttpStatus("XX001"), 500);
});

Deno.test("source-controlled backend boundary includes all three Edge functions and cutover guards", async () => {
  const config = await Deno.readTextFile(
    new URL("../../../config.toml", import.meta.url),
  );
  for (
    const name of [
      "communications",
      "communications-dispatch",
      "communications-resend-webhook",
    ]
  ) {
    assert(config.includes(`[functions.${name}]`));
  }
  const migration = await Deno.readTextFile(
    new URL(
      "../../../migrations/20260901120000_communications.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes(
      "create_scoped_organization_invitation_with_communication",
    ),
  );
  assert(
    migration.includes("create_guardianship_invitation_with_communication"),
  );
  assert(migration.includes("from service_role;"));
  assert(migration.includes("join auth.sessions as auth_session"));
  assert(migration.includes("create table public.communication_delivery_jobs"));
  assert(migration.includes("'UPSTREAM_ACCEPTED', 'UNKNOWN'"));
  assert(migration.includes("'AMBIGUOUS_WORKER_COMPLETION'"));
  assert(
    migration.includes("mark_communication_delivery_submission_started"),
  );
  assert(migration.includes("active_submission_started_at"));
  assert(migration.includes("expo_receipt_retention_horizon"));
  assert(migration.includes("fanout_materialized_at"));
  assert(migration.includes("for update skip locked"));
  assert(migration.includes("provider_token_digest"));
  assert(migration.includes("attempt.last_submitted_at <="));
  assert(
    migration.includes("organization_invitations_require_communication"),
  );
  assert(
    migration.includes("guardianship_invitations_require_communication"),
  );
  assert(migration.includes("new.proposing_context = 'CLINIC'"));
  assert(
    migration.includes(
      "Communication Delivery Attempts are append-only while retained",
    ),
  );
  assert(migration.includes("interval '24 hours'"));
  assert(migration.includes("interval '6 hours'"));
  const webhook = await Deno.readTextFile(
    new URL("../../communications-resend-webhook/index.ts", import.meta.url),
  );
  assert(webhook.includes("resendWebhookPersistenceStatus(result.data)"));
  assert(webhook.includes("}, 503)"));
  assert(webhook.includes('state: "IGNORED"'));
  assert(
    webhook.indexOf("if (!await verifyResendWebhook(") <
      webhook.indexOf("isResendDomainCommunication(dataRecord.tags)"),
  );
  assert(
    webhook.indexOf("isResendDomainCommunication(dataRecord.tags)") <
      webhook.indexOf('admin.rpc("record_resend_delivery_event"'),
  );
  const scheduler = await Deno.readTextFile(
    new URL(
      "../../../provisioning/communications_dispatch_scheduler.sql",
      import.meta.url,
    ),
  );
  assert(scheduler.includes("vault.decrypted_secrets"));
  assert(scheduler.includes("cron.schedule"));
  assert(!scheduler.includes("x-maintenance-secret', '"));
  assert(
    !migration.includes(
      "insert into public.transactional_communications\nselect",
    ) || migration.includes("on conflict do nothing"),
  );
});
