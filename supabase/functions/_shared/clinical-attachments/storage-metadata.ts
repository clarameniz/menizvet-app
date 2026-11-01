import { ATTACHMENT_POLICY } from "./policy.ts";

export type StorageMetadataRejectionCode =
  | "STORAGE_SIZE_INVALID"
  | "STORAGE_OBJECT_EMPTY"
  | "STORAGE_OBJECT_TOO_LARGE"
  | "STORAGE_CONTENT_TYPE_MISMATCH"
  | "STORAGE_CACHE_CONTROL_MISMATCH";

export interface StoredObjectInfo {
  readonly size?: unknown;
  readonly contentType?: unknown;
  readonly cacheControl?: unknown;
}

export type StoredObjectMetadataResult =
  | Readonly<{
    accepted: true;
    size: number;
  }>
  | Readonly<{
    accepted: false;
    rejectionCode: StorageMetadataRejectionCode;
  }>;

function isApprovedZeroCacheControl(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === ATTACHMENT_POLICY.uploadCacheControl ||
    /^max-age\s*=\s*0$/u.test(normalized);
}

export function validateStoredObjectMetadata(
  info: StoredObjectInfo,
): StoredObjectMetadataResult {
  if (typeof info.size !== "number" || !Number.isSafeInteger(info.size)) {
    return Object.freeze({
      accepted: false,
      rejectionCode: "STORAGE_SIZE_INVALID",
    });
  }
  if (info.size < 1) {
    return Object.freeze({
      accepted: false,
      rejectionCode: "STORAGE_OBJECT_EMPTY",
    });
  }
  if (info.size > ATTACHMENT_POLICY.maxBytes) {
    return Object.freeze({
      accepted: false,
      rejectionCode: "STORAGE_OBJECT_TOO_LARGE",
    });
  }
  if (
    typeof info.contentType !== "string" ||
    info.contentType.toLowerCase().split(";", 1)[0].trim() !==
      ATTACHMENT_POLICY.mimeType
  ) {
    return Object.freeze({
      accepted: false,
      rejectionCode: "STORAGE_CONTENT_TYPE_MISMATCH",
    });
  }
  if (!isApprovedZeroCacheControl(info.cacheControl)) {
    return Object.freeze({
      accepted: false,
      rejectionCode: "STORAGE_CACHE_CONTROL_MISMATCH",
    });
  }
  return Object.freeze({ accepted: true, size: info.size });
}

interface StorageErrorLike {
  readonly code?: unknown;
}

export function isStorageObjectNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const candidate = error as StorageErrorLike;
  return candidate.code === "NoSuchKey";
}
