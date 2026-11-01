import {
  DatabaseOperationError,
  expectedDatabaseHttpError,
  rpcData,
} from "../../_shared/clinical-attachments/database-errors.ts";
import { reconcileStaleUpload } from "../../_shared/clinical-attachments/reconciliation.ts";
import {
  CLINICAL_ATTACHMENT_ROUTES,
  clinicalAttachmentRoute,
} from "../../_shared/clinical-attachments/routes.ts";
import {
  isStorageObjectNotFound,
  validateStoredObjectMetadata,
} from "../../_shared/clinical-attachments/storage-metadata.ts";
import { assertEquals } from "./assertions.ts";

const BASE = "http://127.0.0.1:54321/functions/v1/clinical-attachments";

Deno.test("only the Guardian download and maintenance routes exist", () => {
  assertEquals(
    CLINICAL_ATTACHMENT_ROUTES.join(","),
    "guardian-download,maintenance",
  );
  assertEquals(
    clinicalAttachmentRoute(`${BASE}/guardian-download`),
    "guardian-download",
  );
  assertEquals(
    clinicalAttachmentRoute(`${BASE}/guardian-download/`),
    "guardian-download",
  );
  assertEquals(clinicalAttachmentRoute(`${BASE}/maintenance`), "maintenance");
});

Deno.test("the retired professional routes and any other name are not found", () => {
  for (
    const name of [
      "initiate",
      "complete",
      "remove",
      "professional-download",
      "GUARDIAN-DOWNLOAD",
      "guardian-download.json",
      "",
    ]
  ) {
    assertEquals(clinicalAttachmentRoute(`${BASE}/${name}`), null);
  }
  // A route name smuggled in the query string never selects a route.
  assertEquals(
    clinicalAttachmentRoute(`${BASE}/initiate?route=guardian-download`),
    null,
  );
});

Deno.test("Storage metadata accepts only bounded PDF with zero-cache policy", () => {
  assertEquals(
    validateStoredObjectMetadata({
      size: 42,
      contentType: "application/pdf",
      cacheControl: "0",
    }).accepted,
    true,
  );
  assertEquals(
    validateStoredObjectMetadata({
      size: 42,
      contentType: "application/pdf; charset=binary",
      cacheControl: "max-age=0",
    }).accepted,
    true,
  );
});

for (
  const fixture of [
    {
      name: "invalid size metadata",
      info: {
        size: undefined,
        contentType: "application/pdf",
        cacheControl: "0",
      },
      code: "STORAGE_SIZE_INVALID",
    },
    {
      name: "empty",
      info: { size: 0, contentType: "application/pdf", cacheControl: "0" },
      code: "STORAGE_OBJECT_EMPTY",
    },
    {
      name: "oversized",
      info: {
        size: 10_485_761,
        contentType: "application/pdf",
        cacheControl: "0",
      },
      code: "STORAGE_OBJECT_TOO_LARGE",
    },
    {
      name: "content type mismatch",
      info: { size: 42, contentType: "text/plain", cacheControl: "0" },
      code: "STORAGE_CONTENT_TYPE_MISMATCH",
    },
    {
      name: "cache policy mismatch",
      info: {
        size: 42,
        contentType: "application/pdf",
        cacheControl: "max-age=3600",
      },
      code: "STORAGE_CACHE_CONTROL_MISMATCH",
    },
  ] as const
) {
  Deno.test(`Storage metadata rejects ${fixture.name} before download`, () => {
    const result = validateStoredObjectMetadata(fixture.info);
    assertEquals(result.accepted, false);
    if (!result.accepted) assertEquals(result.rejectionCode, fixture.code);
  });
}

Deno.test("Storage not-found classification requires the exact provider code", () => {
  assertEquals(isStorageObjectNotFound({ code: "NoSuchKey" }), true);
  assertEquals(isStorageObjectNotFound({ code: "NoSuchBucket" }), false);
  assertEquals(isStorageObjectNotFound({ code: "not_found" }), false);
  assertEquals(isStorageObjectNotFound({ status: 404 }), false);
  assertEquals(isStorageObjectNotFound({ status: 503 }), false);
});

Deno.test("uploaded object with lost completion validates during reconciliation", async () => {
  let validations = 0;
  let expirations = 0;
  const result = await reconcileStaleUpload(
    { kind: "EXISTS", info: { size: 42 } },
    (info) => {
      validations += 1;
      return Promise.resolve(`validated-${info.size}`);
    },
    () => {
      expirations += 1;
      return Promise.resolve("expired");
    },
  );
  assertEquals(result, "validated-42");
  assertEquals(validations, 1);
  assertEquals(expirations, 0);
});

Deno.test("confirmed missing stale upload invokes expiration only", async () => {
  let validations = 0;
  let expirations = 0;
  const result = await reconcileStaleUpload(
    { kind: "MISSING" },
    () => {
      validations += 1;
      return Promise.resolve("validated");
    },
    () => {
      expirations += 1;
      return Promise.resolve("expired");
    },
  );
  assertEquals(result, "expired");
  assertEquals(validations, 0);
  assertEquals(expirations, 1);
});

Deno.test("PostgREST error codes survive RPC extraction and map safely", () => {
  for (
    const fixture of [
      { databaseCode: "28000", status: 401, key: "error" },
      { databaseCode: "42501", status: 403, key: "status" },
    ] as const
  ) {
    try {
      rpcData(null, {
        code: fixture.databaseCode,
        message: "protected detail",
      });
      throw new Error("Expected database error");
    } catch (error) {
      if (!(error instanceof DatabaseOperationError)) throw error;
      assertEquals(error.databaseCode, fixture.databaseCode);
      const mapped = expectedDatabaseHttpError(error);
      if (!mapped) throw new Error("Expected mapped database error");
      assertEquals(mapped.status, fixture.status);
      assertEquals(Object.keys(mapped.body)[0], fixture.key);
      assertEquals(
        JSON.stringify(mapped.body).includes("protected detail"),
        false,
      );
    }
  }
});
