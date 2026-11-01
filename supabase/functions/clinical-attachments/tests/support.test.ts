import {
  bytesToHex,
  computeSha256,
} from "../../_shared/clinical-attachments/integrity.ts";
import { ATTACHMENT_POLICY } from "../../_shared/clinical-attachments/policy.ts";
import {
  attachmentObjectPath,
  signedDownloadOptions,
} from "../../_shared/clinical-attachments/storage.ts";
import { assertEquals, assertRejects } from "./assertions.ts";

Deno.test("Phase-1 policy constants remain exact", () => {
  assertEquals(ATTACHMENT_POLICY.mimeType, "application/pdf");
  assertEquals(ATTACHMENT_POLICY.maxBytes, 10_485_760);
  assertEquals(ATTACHMENT_POLICY.maxCurrentAttachmentsPerEntry, 5);
  assertEquals(ATTACHMENT_POLICY.validationPolicyVersion, "phase1-pdf-v1");
  assertEquals(ATTACHMENT_POLICY.downloadSignedUrlExpiresInSeconds, 60);
  assertEquals(ATTACHMENT_POLICY.uploadStaleAfterSeconds, 10_800);
  assertEquals(ATTACHMENT_POLICY.uploadCacheControl, "0");
});

Deno.test("SHA-256 matches the published abc test vector", async () => {
  const digest = await computeSha256(new TextEncoder().encode("abc"));
  assertEquals(
    bytesToHex(digest),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("signed downloads are attachments with no other option", () => {
  assertEquals(signedDownloadOptions().download, true);
  assertEquals(Object.keys(signedDownloadOptions()).length, 1);
});

Deno.test("object path is opaque and versioned", async () => {
  const id = "018f7f65-89ab-7def-8abc-0123456789ab";
  assertEquals(attachmentObjectPath(id), `v1/${id}`);
  await assertRejects(
    () => attachmentObjectPath("../../pet/report.pdf"),
    "canonical UUID",
  );
});
