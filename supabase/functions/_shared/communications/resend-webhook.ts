function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

export const RESEND_DOMAIN_COMMUNICATION_TAG = Object.freeze({
  name: "petcare_source",
  value: "domain_communication",
});

export function isResendDomainCommunication(tags: unknown): boolean {
  if (Array.isArray(tags)) {
    return tags.some((tag) =>
      typeof tag === "object" && tag !== null &&
      (tag as Record<string, unknown>).name ===
        RESEND_DOMAIN_COMMUNICATION_TAG.name &&
      (tag as Record<string, unknown>).value ===
        RESEND_DOMAIN_COMMUNICATION_TAG.value
    );
  }
  return typeof tags === "object" && tags !== null &&
    (tags as Record<string, unknown>)[RESEND_DOMAIN_COMMUNICATION_TAG.name] ===
      RESEND_DOMAIN_COMMUNICATION_TAG.value;
}

function base64Bytes(value: string): Uint8Array | null {
  try {
    const binary = atob(value);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

export function resendWebhookPersistenceStatus(state: unknown): number {
  return state === "UNMATCHED" ? 503 : 200;
}

export async function verifyResendWebhook(
  body: string,
  headers: Headers,
  webhookSecret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  const messageId = headers.get("svix-id");
  const timestampValue = headers.get("svix-timestamp");
  const signatures = headers.get("svix-signature");
  const timestamp = Number(timestampValue);
  if (
    !messageId || !timestampValue || !signatures || !Number.isInteger(timestamp)
  ) return false;
  if (Math.abs(nowSeconds - timestamp) > 300) return false;

  const encodedSecret = webhookSecret.startsWith("whsec_")
    ? webhookSecret.slice("whsec_".length)
    : webhookSecret;
  const secret = base64Bytes(encodedSecret);
  if (!secret) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(secret).buffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = new TextEncoder().encode(
    `${messageId}.${timestampValue}.${body}`,
  );
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, signed),
  );

  return signatures.split(/\s+/u).some((candidate) => {
    const separator = candidate.indexOf(",");
    if (separator < 0 || candidate.slice(0, separator) !== "v1") return false;
    const supplied = base64Bytes(candidate.slice(separator + 1));
    return supplied !== null && constantTimeEqual(expected, supplied);
  });
}
