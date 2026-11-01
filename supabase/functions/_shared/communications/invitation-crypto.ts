export type InvitationKind = "organization" | "guardianship";

export interface EncryptedInvitationSecret {
  readonly secret: string;
  readonly digest: Uint8Array;
  readonly keyVersion: number;
  readonly nonce: Uint8Array;
  readonly ciphertext: Uint8Array;
  readonly aadContext: string;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/u,
    "",
  );
}

export function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function postgresBytea(bytes: Uint8Array): string {
  return `\\x${
    Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")
  }`;
}

export function postgresByteaToBytes(value: unknown): Uint8Array {
  if (
    typeof value !== "string" || !/^\\x[0-9a-f]+$/iu.test(value) ||
    value.length % 2 !== 0
  ) {
    throw new TypeError("Invalid PostgreSQL bytea value");
  }
  const hex = value.slice(2);
  return Uint8Array.from(
    hex.match(/.{2}/gu) ?? [],
    (pair) => Number.parseInt(pair, 16),
  );
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

export function invitationAadContext(
  kind: InvitationKind,
  recipientEmail: string,
  expiresAt: string,
  acceptanceDigest: Uint8Array,
): string {
  const normalizedEmail = recipientEmail.trim().toLowerCase();
  const expirationMilliseconds = new Date(expiresAt).valueOf();
  if (
    normalizedEmail === "" || !Number.isSafeInteger(expirationMilliseconds) ||
    acceptanceDigest.byteLength !== 32
  ) {
    throw new TypeError("Invitation AAD inputs are invalid");
  }
  const emailHex = bytesToHex(new TextEncoder().encode(normalizedEmail));
  return `petcare.invitation.${kind}.v1|recipient_email_hex=${emailHex}` +
    `|expires_at_ms=${expirationMilliseconds}` +
    `|acceptance_digest_hex=${bytesToHex(acceptanceDigest)}`;
}

function ownedBuffer(bytes: Uint8Array): ArrayBuffer {
  return Uint8Array.from(bytes).buffer;
}

export async function createEncryptedInvitationSecret(
  kind: InvitationKind,
  keyVersion: number,
  rawKey: Uint8Array,
  recipientEmail: string,
  expiresAt: string,
): Promise<EncryptedInvitationSecret> {
  if (
    !Number.isInteger(keyVersion) || keyVersion < 1 || rawKey.byteLength !== 32
  ) {
    throw new TypeError("Invitation encryption configuration is invalid");
  }
  const random = crypto.getRandomValues(new Uint8Array(32));
  const secret = bytesToBase64Url(random);
  const plaintext = new TextEncoder().encode(secret);
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", plaintext),
  );
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const aadContext = invitationAadContext(
    kind,
    recipientEmail,
    expiresAt,
    digest,
  );
  const key = await crypto.subtle.importKey(
    "raw",
    ownedBuffer(rawKey),
    "AES-GCM",
    false,
    [
      "encrypt",
    ],
  );
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv: ownedBuffer(nonce),
        additionalData: new TextEncoder().encode(aadContext).buffer,
        tagLength: 128,
      },
      key,
      plaintext.buffer,
    ),
  );
  return Object.freeze({
    secret,
    digest,
    keyVersion,
    nonce,
    ciphertext,
    aadContext,
  });
}

export async function decryptInvitationSecret(
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  aadContext: string,
  rawKey: Uint8Array,
): Promise<string> {
  if (
    rawKey.byteLength !== 32 || nonce.byteLength !== 12 ||
    ciphertext.byteLength < 16
  ) {
    throw new TypeError("Invitation envelope is invalid");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    ownedBuffer(rawKey),
    "AES-GCM",
    false,
    [
      "decrypt",
    ],
  );
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: ownedBuffer(nonce),
      additionalData: new TextEncoder().encode(aadContext).buffer,
      tagLength: 128,
    },
    key,
    ownedBuffer(ciphertext),
  );
  return new TextDecoder("utf-8", { fatal: true }).decode(plaintext);
}

export function configuredInvitationKey(version: number): Uint8Array {
  const encoded = Deno.env.get(`INVITATION_SECRET_KEY_V${version}`);
  if (!encoded) {
    throw new Error(`Invitation secret key version ${version} is unavailable`);
  }
  const key = base64ToBytes(encoded);
  if (key.byteLength !== 32) {
    throw new Error("Invitation secret key must decode to 32 bytes");
  }
  return key;
}
