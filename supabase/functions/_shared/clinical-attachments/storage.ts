import { ATTACHMENT_POLICY } from "./policy.ts";

const CANONICAL_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;

export function attachmentObjectPath(storageObjectId: string): string {
  if (!CANONICAL_UUID.test(storageObjectId)) {
    throw new TypeError("storage_object_id must be a canonical UUID");
  }
  return `${ATTACHMENT_POLICY.objectKeyVersion}/${storageObjectId}`;
}

export function signedDownloadOptions(): Readonly<{ download: true }> {
  return Object.freeze({ download: true });
}
