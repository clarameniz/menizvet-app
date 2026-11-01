import { assert, assertEquals, assertRejects } from "./assertions.ts";
import {
  createEncryptedInvitationSecret,
  decryptInvitationSecret,
  type EncryptedInvitationSecret,
  invitationAadContext,
  postgresBytea,
} from "../../_shared/communications/invitation-crypto.ts";
import {
  createStaffOrganizationInvitation,
  INVITATION_VALIDITY_MILLISECONDS,
  type RpcError,
  StaffInvitationError,
} from "../../_shared/communications/organization-invitation.ts";

const SUBJECT = "0b8c9a51-3c55-4d7e-9a43-2f0f6d1e5a10";
const ORGANIZATION = "6a3f2a49-9d0e-4f3e-8a43-1d2c3b4a5f60";
const CLINIC = "9d1e5c7b-2a4f-4b6e-8c1d-3e5f7a9b1c2d";
const CREATED = "8e2f4a6c-1b3d-4e5f-9a7b-0c1d2e3f4a5b";
// Shape returned by PostgREST for the database's timestamptz.
const DATABASE_INSTANT = "2030-03-30T23:59:59.123+00:00";
const CREATED_AT = "2030-03-30T23:59:59.123Z";
const EXPIRES_AT = "2030-04-06T23:59:59.123Z";

type Call = { name: string; args: Record<string, unknown> };
type Responses = Record<string, { data: unknown; error: RpcError | null }>;

function harness(responses: Responses = {}) {
  const calls: Call[] = [];
  const envelopes: EncryptedInvitationSecret[] = [];
  const key = crypto.getRandomValues(new Uint8Array(32));
  const rpc = (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args });
    return Promise.resolve(
      responses[name] ??
        (name === "authorize_organization_invitation_creation"
          ? { data: DATABASE_INSTANT, error: null }
          : { data: CREATED, error: null }),
    );
  };
  const envelope = async (recipientEmail: string, expiresAt: string) => {
    const created = await createEncryptedInvitationSecret(
      "organization",
      1,
      key,
      recipientEmail,
      expiresAt,
    );
    envelopes.push(created);
    return created;
  };
  const invite = (body: Record<string, unknown>) =>
    createStaffOrganizationInvitation(
      rpc,
      envelope,
      postgresBytea,
      SUBJECT,
      body,
    );
  return { calls, envelopes, key, invite };
}

function request(overrides: Record<string, unknown> = {}) {
  return {
    organization_id: ORGANIZATION,
    recipient_email: "Laura@Example.Test",
    responsibility: "ADMINISTRATOR",
    scope_type: "ORGANIZATION",
    clinic_id: null,
    ...overrides,
  };
}

async function failure(action: () => Promise<unknown>) {
  try {
    await action();
  } catch (error) {
    if (error instanceof StaffInvitationError) {
      return `${error.status}:${error.code}`;
    }
    throw error;
  }
  throw new Error("Expected the invitation to fail");
}

Deno.test("valid invite: verified subject, database instant, exact 7-day envelope, reference-only response", async () => {
  const { calls, envelopes, key, invite } = harness();
  const response = await invite(request());
  assertEquals(
    JSON.stringify(response),
    JSON.stringify({ invitation_id: CREATED }),
  );
  assertEquals(
    calls.map((call) => call.name).join(","),
    [
      "authorize_organization_invitation_creation",
      "create_staff_organization_invitation_with_communication",
    ].join(","),
  );
  assertEquals(
    JSON.stringify(calls[0].args),
    JSON.stringify({
      p_auth_subject: SUBJECT,
      p_organization_id: ORGANIZATION,
    }),
  );
  const created = calls[1].args;
  assertEquals(
    Object.keys(created).sort().join(","),
    [
      "p_acceptance_secret_digest",
      "p_auth_subject",
      "p_clinic_id",
      "p_created_at",
      "p_organization_id",
      "p_recipient_email",
      "p_responsibility",
      "p_scope_type",
      "p_secret_ciphertext",
      "p_secret_key_version",
      "p_secret_nonce",
    ].join(","),
  );
  assertEquals(created.p_auth_subject, SUBJECT);
  assertEquals(created.p_created_at, CREATED_AT);
  assertEquals(created.p_responsibility, "ADMINISTRATOR");
  assertEquals(created.p_scope_type, "ORGANIZATION");
  assertEquals(created.p_clinic_id, null);
  assertEquals(created.p_recipient_email, "Laura@Example.Test");
  assertEquals(INVITATION_VALIDITY_MILLISECONDS, 604_800_000);

  // The envelope opens only with the database's context for T + 7 days.
  assertEquals(envelopes.length, 1);
  const [envelope] = envelopes;
  assertEquals(
    created.p_acceptance_secret_digest,
    postgresBytea(envelope.digest),
  );
  assertEquals(created.p_secret_nonce, postgresBytea(envelope.nonce));
  assertEquals(created.p_secret_ciphertext, postgresBytea(envelope.ciphertext));
  const opened = await decryptInvitationSecret(
    envelope.ciphertext,
    envelope.nonce,
    invitationAadContext(
      "organization",
      "Laura@Example.Test",
      EXPIRES_AT,
      envelope.digest,
    ),
    key,
  );
  assertEquals(opened, envelope.secret);
  for (
    const wrong of ["2030-04-06T23:59:59.122Z", "2030-04-06T23:59:59.124Z"]
  ) {
    await assertRejects(() =>
      decryptInvitationSecret(
        envelope.ciphertext,
        envelope.nonce,
        invitationAadContext(
          "organization",
          "Laura@Example.Test",
          wrong,
          envelope.digest,
        ),
        key,
      )
    );
  }

  // Nothing secret leaves through the response.
  const serialized = JSON.stringify(response);
  const hex = (bytes: Uint8Array) => postgresBytea(bytes).slice(2);
  for (
    const secret of [
      envelope.secret,
      hex(envelope.digest),
      hex(envelope.nonce),
      hex(envelope.ciphertext),
    ]
  ) {
    assert(!serialized.includes(secret), "response leaks credential material");
  }
});

Deno.test("the four Phase 1 role/scope combinations pass through as one responsibility", async () => {
  for (
    const [responsibility, scope_type, clinic_id] of [
      ["ADMINISTRATOR", "ORGANIZATION", null],
      ["RECEPTIONIST", "ORGANIZATION", undefined],
      ["ADMINISTRATOR", "CLINIC", CLINIC.toUpperCase()],
      ["RECEPTIONIST", "CLINIC", CLINIC],
    ] as const
  ) {
    const { calls, invite } = harness();
    const body: Record<string, unknown> = request({
      responsibility,
      scope_type,
    });
    if (clinic_id === undefined) delete body.clinic_id;
    else body.clinic_id = clinic_id;
    await invite(body);
    const created = calls[1].args;
    assertEquals(created.p_responsibility, responsibility);
    assertEquals(created.p_scope_type, scope_type);
    assertEquals(
      created.p_clinic_id,
      scope_type === "CLINIC" ? CLINIC : null,
    );
  }
});

Deno.test("client-supplied expiry, recipient User, arrays and unknown members are rejected before any call", async () => {
  for (
    const extra of [
      { expires_at: "2030-01-01T00:00:00Z" },
      { recipient_user_id: SUBJECT },
      { intended_responsibilities: [] },
      { membership_id: CREATED },
      { p_auth_subject: SUBJECT },
      { acceptance_secret: "x" },
      { created_at: "2030-01-01T00:00:00Z" },
    ]
  ) {
    const { calls, envelopes, invite } = harness();
    assertEquals(
      await failure(() => invite({ ...request(), ...extra })),
      "400:INVALID_REQUEST",
    );
    assertEquals(calls.length + envelopes.length, 0);
  }
  for (
    const malformed of [
      { organization_id: "not-a-uuid" },
      { organization_id: undefined },
      { recipient_email: 7 },
      { responsibility: ["ADMINISTRATOR"] },
      { scope_type: null },
      { clinic_id: 5 },
    ]
  ) {
    const { calls, invite } = harness();
    assertEquals(
      await failure(() => invite({ ...request(), ...malformed })),
      "400:INVALID_REQUEST",
    );
    assertEquals(calls.length, 0);
  }
});

Deno.test("authorization precedes every value judgement and secret generation", async () => {
  for (
    const [hint, expected] of [
      ["ORGANIZATION_UNAVAILABLE", "403:ORGANIZATION_UNAVAILABLE"],
      ["ACCOUNT_VERIFICATION_REQUIRED", "403:ACCOUNT_VERIFICATION_REQUIRED"],
      [null, "403:ORGANIZATION_UNAVAILABLE"],
    ] as const
  ) {
    for (
      const body of [
        request(),
        request({ responsibility: "OWNER", recipient_email: "  " }),
        request({ scope_type: "CLINIC", clinic_id: "nope" }),
      ]
    ) {
      const { calls, envelopes, invite } = harness({
        authorize_organization_invitation_creation: {
          data: null,
          error: { code: "42501", hint, message: "denied" },
        },
      });
      assertEquals(await failure(() => invite(body)), expected);
      assertEquals(calls.length, 1);
      assertEquals(envelopes.length, 0);
    }
  }
  const { invite } = harness({
    authorize_organization_invitation_creation: {
      data: null,
      error: { code: "28000", message: "no coherent User" },
    },
  });
  assertEquals(
    await failure(() => invite(request())),
    "401:AUTHENTICATION_REQUIRED",
  );
});

Deno.test("Owner, Clinic Veterinarian and malformed scopes are rejected after authorization without a secret", async () => {
  for (
    const [overrides, expected] of [
      [{ responsibility: "OWNER" }, "400:INVALID_ROLE_SCOPE"],
      [
        { responsibility: "OWNER", scope_type: "CLINIC", clinic_id: CLINIC },
        "400:INVALID_ROLE_SCOPE",
      ],
      [{
        responsibility: "VETERINARIAN",
        scope_type: "CLINIC",
        clinic_id: CLINIC,
      }, "400:INVALID_ROLE_SCOPE"],
      [{ responsibility: "administrator" }, "400:INVALID_ROLE_SCOPE"],
      [{ scope_type: "REGION" }, "400:INVALID_ROLE_SCOPE"],
      [{ clinic_id: CLINIC }, "400:INVALID_ROLE_SCOPE"],
      [{ scope_type: "CLINIC" }, "400:INVALID_ROLE_SCOPE"],
      [{ scope_type: "CLINIC", clinic_id: "clinic-1" }, "400:INVALID_CLINIC"],
      [{ recipient_email: " \t " }, "400:INVALID_RECIPIENT"],
      [{ recipient_email: " laura@example.test" }, "400:INVALID_RECIPIENT"],
    ] as const
  ) {
    const { calls, envelopes, invite } = harness();
    assertEquals(await failure(() => invite(request(overrides))), expected);
    assertEquals(
      calls.map((call) => call.name).join(","),
      "authorize_organization_invitation_creation",
    );
    assertEquals(envelopes.length, 0);
  }
});

Deno.test("Organization-scoped Veterinarian remains a valid backend shape (SPEC-ORG-002 §10, BR-17)", async () => {
  const { calls, invite } = harness();
  await invite(request({ responsibility: "VETERINARIAN" }));
  assertEquals(calls[1].args.p_responsibility, "VETERINARIAN");
});

Deno.test("recipient address uses the database trim set for both storage and envelope", async () => {
  const { calls, envelopes, key, invite } = harness();
  await invite(request({ recipient_email: "\t Laura@Example.Test \n" }));
  assertEquals(calls[1].args.p_recipient_email, "Laura@Example.Test");
  assertEquals(
    await decryptInvitationSecret(
      envelopes[0].ciphertext,
      envelopes[0].nonce,
      invitationAadContext(
        "organization",
        "laura@example.test",
        EXPIRES_AT,
        envelopes[0].digest,
      ),
      key,
    ),
    envelopes[0].secret,
  );
});

Deno.test("database outcomes map to calm codes; failures are never retried and leak nothing", async () => {
  for (
    const [error, expected] of [
      [
        { code: "23505", hint: "PENDING_INVITATION_EXISTS" },
        "409:PENDING_INVITATION_EXISTS",
      ],
      [{ code: "23505", hint: "ACTIVE_MEMBER" }, "409:ACTIVE_MEMBER"],
      [{ code: "22023", hint: "INVALID_CLINIC" }, "400:INVALID_CLINIC"],
      [{ code: "22023", hint: "INVALID_RECIPIENT" }, "400:INVALID_RECIPIENT"],
      [{ code: "22023", hint: "INVALID_ROLE_SCOPE" }, "400:INVALID_ROLE_SCOPE"],
      [
        { code: "22023", hint: "CREATION_INSTANT_INVALID" },
        "500:INTERNAL_ERROR",
      ],
      [{ code: "22023", hint: "CREDENTIAL_INVALID" }, "500:INTERNAL_ERROR"],
      [
        { code: "42501", hint: "ORGANIZATION_UNAVAILABLE" },
        "403:ORGANIZATION_UNAVAILABLE",
      ],
      [{ code: "23514", hint: null }, "500:INTERNAL_ERROR"],
      [{ code: "XX000", hint: null }, "500:INTERNAL_ERROR"],
      [{ hint: null }, "500:INTERNAL_ERROR"],
    ] as const
  ) {
    const { calls, envelopes, invite } = harness({
      create_staff_organization_invitation_with_communication: {
        data: null,
        error: { ...error, message: 'relation "public.secret" detail' },
      },
    });
    let thrown: unknown;
    try {
      await invite(request());
    } catch (caught) {
      thrown = caught;
    }
    assert(thrown instanceof StaffInvitationError, "expected a mapped failure");
    assertEquals(`${thrown.status}:${thrown.code}`, expected);
    assertEquals(thrown.message, thrown.code);
    assert(!thrown.message.includes(envelopes[0].secret));
    assertEquals(
      calls.filter((call) =>
        call.name === "create_staff_organization_invitation_with_communication"
      ).length,
      1,
    );
  }
});

Deno.test("malformed database instant or reference fails closed", async () => {
  for (const data of [null, "yesterday", 42]) {
    const { envelopes, invite } = harness({
      authorize_organization_invitation_creation: { data, error: null },
    });
    assertEquals(await failure(() => invite(request())), "500:INTERNAL_ERROR");
    assertEquals(envelopes.length, 0);
  }
  const { invite } = harness({
    create_staff_organization_invitation_with_communication: {
      data: { invitation_id: CREATED, secret: "x" },
      error: null,
    },
  });
  assertEquals(await failure(() => invite(request())), "500:INTERNAL_ERROR");
});

Deno.test("route requires the verified JWT subject and uses only the Staff Phase 1 command", async () => {
  const source = await Deno.readTextFile(
    new URL("../index.ts", import.meta.url),
  );
  const route = source.slice(
    source.indexOf("async function createOrganizationInvitation("),
    source.indexOf("async function createGuardianshipInvitation("),
  );
  assert(route.indexOf("await authenticatedContext(admin, request)") >= 0);
  assert(
    route.indexOf("await authenticatedContext(admin, request)") <
      route.indexOf("await requestBody(request)"),
  );
  assert(route.includes("auth.subject"));
  assert(
    !route.includes("create_scoped_organization_invitation_with_communication"),
  );
  assert(!route.includes("expires_at"));
  assert(!route.includes("recipient_user_id"));
  assert(source.includes("admin.auth.getUser(token)"));
  assert(source.includes('case "create-organization-invitation":'));
});
