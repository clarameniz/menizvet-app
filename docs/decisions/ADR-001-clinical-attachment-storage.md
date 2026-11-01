# ADR-001 — Store Clinical Attachments in Private Object Storage

**Status:** ACCEPTED

## Context

Clinical Attachments may contain sensitive veterinary medical information such
as laboratory reports, diagnostic images, clinical photographs, and supporting
documents.

Binary clinical files require secure storage, controlled access, integrity
protection, and the ability to evolve independently from the medical domain
model.

Storing binary content directly in PostgreSQL would unnecessarily couple file
storage to the relational domain model.

Clinical Attachment identity and metadata should also remain independent from
the underlying storage provider.

## Decision

Clinical Attachment binary content will be stored in private object storage.

For the initial architecture, Supabase Storage will be used.

Clinical Attachment domain metadata and relationships will be stored in
PostgreSQL.

The medical domain will reference stored binary content through an opaque
technical object reference.

Storage object paths must use opaque identifiers and must not encode sensitive
domain information such as:

- Pet names;
- Guardian names;
- diagnoses;
- clinical descriptions;
- human-readable medical information.

Clinical files must be stored in private buckets.

Permanent public URLs must not be used.

Access to binary content must be authorized using the application's current
Medical Access Control rules.

Authenticated private access should be preferred where practical.

Short-lived signed URLs may be used when required by client-side viewers or
equivalent technical constraints.

Supported file types and size limits will be controlled through application and
storage configuration.

Files must satisfy the required validation and security checks before becoming
available as Clinical Attachments.

Finalized Clinical Attachments must preserve sufficient content-integrity
information to detect unintended or unauthorized binary modification.

A cryptographic checksum such as SHA-256 may be used for this purpose.

## Domain Separation

The Clinical Attachment domain entity must remain independent from the storage
provider.

Conceptually:

    Clinical Record Entry
            ↓
    Clinical Attachment
            ↓
    protected binary object

PostgreSQL owns the clinical metadata and relationships.

Object storage owns the binary content.

The storage provider must not become the source of truth for clinical
provenance or medical authorization.

## Consequences

### Positive

- binary files remain outside the relational database;
- sensitive files remain private by default;
- existing authentication and authorization infrastructure can be reused;
- file storage can scale independently from PostgreSQL;
- the medical domain remains independent from the storage implementation;
- Supabase Storage can later be replaced without redefining Clinical
  Attachment identity.

### Negative

- file and metadata operations require consistency management across PostgreSQL
  and object storage;
- secure file validation and delivery must be implemented;
- temporary or failed uploads require cleanup behavior;
- access-control policies must remain synchronized with the application's
  medical authorization model.

## Alternatives Considered

### Store binary files directly in PostgreSQL

Rejected because it unnecessarily couples large binary content to the
relational database and medical domain model.

### Google Cloud Storage

Technically suitable, but rejected for the initial architecture because it
would introduce an additional storage and authorization boundary without a
current requirement that justifies the added complexity.

It remains a viable future storage provider because the Clinical Attachment
domain model is provider-independent.

### Public object storage with unguessable URLs

Rejected.

URL secrecy is not an acceptable authorization mechanism for protected medical
information.

## Related Specifications

- SPEC-MED-007 — Add Clinical Attachment
- SPEC-MED-003 — Finalize Clinical Record Entry
- SPEC-MED-005 — View Pet Medical History
- SPEC-ACC-001 — Grant Pet Care Authorization
- SPEC-ACC-002 — Revoke Pet Care Authorization