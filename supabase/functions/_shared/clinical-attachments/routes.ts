/**
 * The clinical-attachments Edge Function's routes (SPEC-MED-010 BR-19, BR-24;
 * stage M4 of docs/CLINICAL_DOCUMENTATION_TRANSITION.md).
 *
 * - `guardian-download`: a Guardian's signed download of an AVAILABLE
 *   Attachment of a Pet they currently guard.
 * - `maintenance`: the server-to-server Storage validation and cleanup pass,
 *   authenticated only by the maintenance secret.
 *
 * The professional routes (`initiate`, `complete`, `remove`,
 * `professional-download`) are retired: SPEC-MED-010 ships no professional
 * client Attachment workflow, and every other name is NOT_FOUND.
 */
export const CLINICAL_ATTACHMENT_ROUTES = [
  "guardian-download",
  "maintenance",
] as const;
export type ClinicalAttachmentRoute =
  (typeof CLINICAL_ATTACHMENT_ROUTES)[number];

/** The route a request names by its trailing path segment, or `null` for any other. */
export function clinicalAttachmentRoute(
  url: string,
): ClinicalAttachmentRoute | null {
  const pathname = new URL(url).pathname.replace(/\/+$/u, "");
  const name = pathname.split("/").at(-1) ?? "";
  return CLINICAL_ATTACHMENT_ROUTES.find((route) => route === name) ?? null;
}
