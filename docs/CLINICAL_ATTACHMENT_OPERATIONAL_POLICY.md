# Clinical Attachment Phase-1 Operational Policy

Clinical Attachments accept PDF (`application/pdf`) only, with an actual binary
size from 1 through 10,485,760 bytes (10 MiB). A Clinical Record Entry may have
at most five current Attachments; `removed_at IS NULL` defines current.

Every accepted object passes the bounded, fail-closed structural inspection
identified by `phase1-pdf-v1`. The validator parses and traverses PDF objects; it
does not make security decisions by scanning raw bytes for strings. It rejects
encryption, invalid or unresolved structures, JavaScript, actions, XFA,
embedded files, RichMedia/multimedia, unsupported active features, and resource
bound exhaustion. Phase 1 has no external malware-scanning service, so
`AVAILABLE` means only “passed `phase1-pdf-v1`,” not universally malware-free.
Trusted integrity is SHA-256.

The private `clinical-attachments` bucket uses exact signed uploads without
upsert. The signed token is used only with the documented
`uploadToSignedUrl(path, token, file, fileOptions)` flow. Phase 1 fixes
`contentType` to `application/pdf` and `cacheControl` to `"0"`; the client does
not select either value. Before materializing an object for PDF validation,
trusted Edge code checks the exact object's Storage metadata and rejects empty,
oversized, content-type-mismatched, or cache-policy-mismatched objects. The
provider's signed-upload credential is expected to remain valid for two hours;
the database stale-cleanup horizon is conservatively three hours. A stale row
is reconciled against the exact object before it can be expired, so a completed
upload whose client callback was lost is validated rather than deleted.
TUS/resumable upload is not part of Phase 1.

The validator's 1,500 ms processing budget is cooperative: it is evaluated
after parser load and throughout graph traversal, but it cannot preempt
synchronous parser work. Complete validator wall time on representative
compressed/object-stream adversarial PDFs is therefore a required Edge-runtime
deployment gate, not a claim of a hard execution timeout.

Downloads use private signed URLs with requested `expiresIn = 60`. Sixty
seconds is a token-expiry target, not a strict byte-access or instantaneous
revocation boundary: an already-issued URL may remain technically usable
through provider cache behavior. Every request for a new URL reauthorizes and
records a new medical-access audit event. Signed URLs and upload credentials
are never persisted.
