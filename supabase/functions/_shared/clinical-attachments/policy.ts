export const ATTACHMENT_POLICY = Object.freeze(
  {
    mimeType: "application/pdf",
    maxBytes: 10_485_760,
    maxCurrentAttachmentsPerEntry: 5,
    validationPolicyVersion: "phase1-pdf-v1",
    downloadSignedUrlExpiresInSeconds: 60,
    uploadStaleAfterSeconds: 3 * 60 * 60,
    bucketName: "clinical-attachments",
    objectKeyVersion: "v1",
    integrityAlgorithm: "SHA-256",
    uploadCacheControl: "0",
  } as const,
);

// These are deliberately conservative security controls for Supabase Edge's
// hosted execution envelope. Reaching a bound is a definitive fail-closed
// policy rejection; the values are versioned by phase1-pdf-v1.
export const PDF_VALIDATION_LIMITS = Object.freeze(
  {
    maxIndirectObjects: 20_000,
    maxTraversedObjects: 100_000,
    maxReferences: 100_000,
    maxTraversalDepth: 64,
    maxDictionaryEntries: 2_048,
    maxArrayEntries: 20_000,
    // Cooperative budget checked after parser load and during traversal. This
    // is not a preemptive execution timeout for synchronous parser work.
    maxValidationMilliseconds: 1_500,
  } as const,
);
