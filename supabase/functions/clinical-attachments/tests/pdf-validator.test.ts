import {
  ATTACHMENT_POLICY,
  PDF_VALIDATION_LIMITS,
} from "../../_shared/clinical-attachments/policy.ts";
import { validatePhase1Pdf } from "../../_shared/clinical-attachments/pdf-validator.ts";
import { assert, assertEquals } from "./assertions.ts";
import {
  additionalActionPdf,
  adversarialCompressedObjectStreamPdf,
  annotationPdf,
  cyclicReferencePdf,
  deeplyNestedPdf,
  embeddedFilePdf,
  encryptedPdf,
  incrementalRevisionPdf,
  javascriptPdf,
  launchActionPdf,
  minimalValidPdf,
  nearSizeLimitValidPdf,
  objectStreamPdf,
  openActionPdf,
  ordinaryMultiPagePdf,
  unresolvedReferencePdf,
  unsupportedFilterPdf,
  xfaPdf,
} from "./pdf-fixtures.ts";

async function assertAccepted(bytes: Uint8Array): Promise<void> {
  const result = await validatePhase1Pdf(bytes);
  assert(
    result.accepted,
    `Expected PDF acceptance, received ${
      result.accepted ? "accepted" : result.rejectionCode
    }`,
  );
  assert(
    result.stats.elapsedMilliseconds <=
      PDF_VALIDATION_LIMITS.maxValidationMilliseconds,
    "Accepted validation exceeded its processing budget",
  );
}

async function assertRejected(
  bytes: Uint8Array,
  rejectionCode: string,
): Promise<void> {
  const result = await validatePhase1Pdf(bytes);
  assert(!result.accepted, "Expected PDF rejection");
  assertEquals(result.rejectionCode, rejectionCode);
}

Deno.test("accepts a minimal structurally valid PDF", () =>
  assertAccepted(minimalValidPdf()));
Deno.test("accepts an ordinary multi-page PDF", () =>
  assertAccepted(ordinaryMultiPagePdf()));
Deno.test("accepts a PDF whose objects are stored in object streams", async () =>
  assertAccepted(await objectStreamPdf()));
Deno.test("complete validator handles adversarial compressed object-stream load within the runtime gate", async () => {
  const bytes = await adversarialCompressedObjectStreamPdf();
  assert(
    new TextDecoder().decode(bytes).includes("/ObjStm"),
    "Fixture must contain compressed object streams",
  );
  assert(bytes.byteLength <= ATTACHMENT_POLICY.maxBytes);
  const startedAt = performance.now();
  const result = await validatePhase1Pdf(bytes);
  const completeElapsedMilliseconds = performance.now() - startedAt;
  assert(
    result.accepted || result.rejectionCode === "PDF_RESOURCE_LIMIT",
    "Load-stress fixture must either validate or fail closed on its resource budget",
  );
  assert(
    completeElapsedMilliseconds <= 2_000,
    `TECHNICAL BLOCKER - PDF PARSER RUNTIME: ${completeElapsedMilliseconds} ms`,
  );
});
Deno.test("accepts a valid incremental revision", () =>
  assertAccepted(incrementalRevisionPdf()));
Deno.test("accepts a near-size-limit valid PDF within the processing budget", () =>
  assertAccepted(nearSizeLimitValidPdf()));
Deno.test("terminates safely on repeated cyclic references", () =>
  assertAccepted(cyclicReferencePdf()));

Deno.test("rejects an empty file", () =>
  assertRejected(new Uint8Array(), "PDF_EMPTY"));
Deno.test("rejects an oversized file before parsing", () =>
  assertRejected(
    new Uint8Array(ATTACHMENT_POLICY.maxBytes + 1),
    "PDF_TOO_LARGE",
  ));
Deno.test("rejects malformed input", () =>
  assertRejected(new TextEncoder().encode("not a PDF"), "PDF_PARSE_INVALID"));
Deno.test("rejects encryption", () =>
  assertRejected(encryptedPdf(), "PDF_ENCRYPTED"));
Deno.test("rejects JavaScript", () =>
  assertRejected(javascriptPdf(), "PDF_JAVASCRIPT"));
Deno.test("rejects OpenAction", () =>
  assertRejected(openActionPdf(), "PDF_ACTION_UNSUPPORTED"));
Deno.test("rejects additional actions", () =>
  assertRejected(additionalActionPdf(), "PDF_ACTION_UNSUPPORTED"));
Deno.test("rejects embedded files", () =>
  assertRejected(embeddedFilePdf(), "PDF_EMBEDDED_FILE"));
Deno.test("rejects Launch actions", () =>
  assertRejected(launchActionPdf(), "PDF_LAUNCH"));
Deno.test("rejects XFA", () => assertRejected(xfaPdf(), "PDF_XFA"));
Deno.test("rejects RichMedia", () =>
  assertRejected(annotationPdf("RichMedia"), "PDF_RICH_MEDIA"));
for (const subtype of ["Movie", "Sound", "Screen", "3D"]) {
  Deno.test(`rejects unsupported ${subtype} multimedia`, () =>
    assertRejected(annotationPdf(subtype), "PDF_MULTIMEDIA_UNSUPPORTED"));
}
Deno.test("rejects unsupported stream filters", () =>
  assertRejected(unsupportedFilterPdf(), "PDF_UNSUPPORTED_STRUCTURE"));
Deno.test("rejects excessive traversal depth", () =>
  assertRejected(deeplyNestedPdf(), "PDF_RESOURCE_LIMIT"));
Deno.test("rejects unresolved references", () =>
  assertRejected(unresolvedReferencePdf(), "PDF_UNRESOLVED_REFERENCE"));
