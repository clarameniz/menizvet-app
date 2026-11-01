import { assert } from "./assertions.ts";
import { ATTACHMENT_POLICY } from "../../_shared/clinical-attachments/policy.ts";

Deno.test("bucket configuration matches the Attachment policy constants", async () => {
  const config = await Deno.readTextFile(
    new URL("../../../config.toml", import.meta.url),
  );
  assert(config.includes("[storage.buckets.clinical-attachments]"));
  assert(config.includes("public = false"));
  assert(config.includes('file_size_limit = "10MiB"'));
  assert(
    config.includes(`allowed_mime_types = ["${ATTACHMENT_POLICY.mimeType}"]`),
  );
});

Deno.test("database permanent validation constants match Edge policy", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../../migrations/20260831120000_clinical_attachments.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes(
      `trusted_byte_size between 1 and ${ATTACHMENT_POLICY.maxBytes}`,
    ),
  );
  assert(
    migration.includes(
      `validation_policy_version = '${ATTACHMENT_POLICY.validationPolicyVersion}'`,
    ),
  );
  assert(migration.includes("current_count >= 5"));
  assert(migration.includes("interval '3 hours'"));
});

Deno.test("database validation callback shapes are null-safe", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../../migrations/20260831120000_clinical_attachments.sql",
      import.meta.url,
    ),
  );
  assert(migration.includes("if p_outcome is null"));
  assert(
    migration.includes(
      "p_validation_policy_version is distinct from 'phase1-pdf-v1'",
    ),
  );
  assert(
    migration.indexOf("Trusted REJECTED facts are malformed") <
      migration.indexOf(
        "Conflicting terminal Attachment validation callback",
      ),
  );
});

Deno.test("M4 retires the professional operations and keeps a Guardian-only download", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../../migrations/20261115090000_retire_professional_attachment_routes.sql",
      import.meta.url,
    ),
  );
  for (
    const retired of [
      "drop function public.initiate_clinical_attachment_upload(uuid, uuid, uuid, uuid, text);",
      "drop function public.resolve_clinical_attachment_completion_target(uuid, uuid);",
      "drop function public.remove_draft_clinical_attachment(uuid, uuid);",
      "drop function public.authorize_clinical_attachment_download(uuid, uuid, text, text, uuid, uuid, uuid);",
    ]
  ) {
    assert(migration.includes(retired));
  }
  const guardian = migration.slice(
    migration.indexOf(
      "create function public.authorize_guardian_clinical_attachment_download(",
    ),
  );
  assert(
    guardian.includes("    p_auth_subject uuid,\n    p_attachment_id uuid\n)"),
  );
  for (
    const professional of [
      "p_access_context",
      "p_professional_scope",
      "p_accessing_clinic_id",
      "p_care_authorization_id",
      "encounter",
    ]
  ) {
    assert(!guardian.includes(professional));
  }
  assert(guardian.includes("p_actor_context => 'GUARDIAN'"));
  assert(guardian.includes("to service_role;"));
});

Deno.test("the Edge Function calls only the Guardian download authorization", async () => {
  const source = await Deno.readTextFile(
    new URL("../index.ts", import.meta.url),
  );
  assert(source.includes('"authorize_guardian_clinical_attachment_download"'));
  for (
    const retired of [
      "initiate_clinical_attachment_upload",
      "resolve_clinical_attachment_completion_target",
      "remove_draft_clinical_attachment",
      '"authorize_clinical_attachment_download"',
      "clinical_encounter_id",
      "care_authorization_id",
      "accessing_clinic_id",
      "uploader_vca_id",
      "professional_scope",
    ]
  ) {
    assert(!source.includes(retired));
  }
});

Deno.test("database stale reconciliation and missing-object integrity contracts are explicit", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../../migrations/20260831120000_clinical_attachments.sql",
      import.meta.url,
    ),
  );
  assert(migration.includes("'action', 'RECONCILE'"));
  assert(
    migration.includes(
      "expire_missing_stale_clinical_attachment_upload(uuid, uuid)",
    ),
  );
  assert(
    migration.includes(
      "Authorized Clinical Attachment Storage object is missing",
    ),
  );
  assert(migration.includes("using errcode = 'XX001'"));
  assert(migration.includes("new.removed_by_vca_id, new.removed_by_user_id"));
});
