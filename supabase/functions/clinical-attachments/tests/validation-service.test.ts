import { assertEquals } from "./assertions.ts";
import { minimalValidPdf } from "./pdf-fixtures.ts";
import {
  deriveTrustedValidationFacts,
  postgresByteaFromHex,
} from "../../_shared/clinical-attachments/validation-service.ts";

Deno.test("trusted validation derives PDF facts and SHA-256", async () => {
  const bytes = minimalValidPdf();
  const facts = await deriveTrustedValidationFacts(bytes, "application/pdf");
  assertEquals(facts.outcome, "AVAILABLE");
  if (facts.outcome === "AVAILABLE") {
    assertEquals(facts.trustedByteSize, bytes.byteLength);
    assertEquals(facts.integrityHex.length, 64);
    assertEquals(
      postgresByteaFromHex(facts.integrityHex),
      `\\x${facts.integrityHex}`,
    );
  }
});

Deno.test("trusted validation rejects a mismatched observed media type", async () => {
  const facts = await deriveTrustedValidationFacts(
    minimalValidPdf(),
    "text/plain; charset=utf-8",
  );
  assertEquals(facts.outcome, "REJECTED");
  if (facts.outcome === "REJECTED") {
    assertEquals(facts.rejectionCode, "MEDIA_TYPE_MISMATCH");
  }
});
