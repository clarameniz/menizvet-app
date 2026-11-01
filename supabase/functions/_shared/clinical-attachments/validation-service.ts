import { bytesToHex, computeSha256 } from "./integrity.ts";
import { type PdfRejectionCode, validatePhase1Pdf } from "./pdf-validator.ts";
import { ATTACHMENT_POLICY } from "./policy.ts";
import type { StorageMetadataRejectionCode } from "./storage-metadata.ts";

export type TrustedValidationFacts =
  | {
    readonly outcome: "AVAILABLE";
    readonly trustedMediaType: typeof ATTACHMENT_POLICY.mimeType;
    readonly trustedByteSize: number;
    readonly integrityHex: string;
    readonly rejectionCode: null;
  }
  | {
    readonly outcome: "REJECTED";
    readonly trustedMediaType: null;
    readonly trustedByteSize: null;
    readonly integrityHex: null;
    readonly rejectionCode:
      | PdfRejectionCode
      | "MEDIA_TYPE_MISMATCH"
      | StorageMetadataRejectionCode;
  };

export async function deriveTrustedValidationFacts(
  bytes: Uint8Array,
  observedMediaType: string,
): Promise<TrustedValidationFacts> {
  if (
    observedMediaType.toLowerCase().split(";", 1)[0].trim() !==
      ATTACHMENT_POLICY.mimeType
  ) {
    return Object.freeze({
      outcome: "REJECTED",
      trustedMediaType: null,
      trustedByteSize: null,
      integrityHex: null,
      rejectionCode: "MEDIA_TYPE_MISMATCH",
    });
  }

  const validation = await validatePhase1Pdf(bytes);
  if (!validation.accepted) {
    return Object.freeze({
      outcome: "REJECTED",
      trustedMediaType: null,
      trustedByteSize: null,
      integrityHex: null,
      rejectionCode: validation.rejectionCode,
    });
  }
  const digest = await computeSha256(bytes);
  return Object.freeze({
    outcome: "AVAILABLE",
    trustedMediaType: ATTACHMENT_POLICY.mimeType,
    trustedByteSize: bytes.byteLength,
    integrityHex: bytesToHex(digest),
    rejectionCode: null,
  });
}

export function rejectedStorageMetadataFacts(
  rejectionCode: StorageMetadataRejectionCode,
): TrustedValidationFacts {
  return Object.freeze({
    outcome: "REJECTED",
    trustedMediaType: null,
    trustedByteSize: null,
    integrityHex: null,
    rejectionCode,
  });
}

export function postgresByteaFromHex(hex: string | null): string | null {
  if (hex === null) return null;
  if (!/^[0-9a-f]{64}$/u.test(hex)) {
    throw new TypeError("SHA-256 must be 32 bytes");
  }
  return `\\x${hex}`;
}
