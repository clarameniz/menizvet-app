export type StaleObjectInspection<T> =
  | Readonly<{ kind: "EXISTS"; info: T }>
  | Readonly<{ kind: "MISSING" }>;

export async function reconcileStaleUpload<TInfo, TResult>(
  inspection: StaleObjectInspection<TInfo>,
  validateExisting: (info: TInfo) => Promise<TResult>,
  expireMissing: () => Promise<TResult>,
): Promise<TResult> {
  return inspection.kind === "EXISTS"
    ? await validateExisting(inspection.info)
    : await expireMissing();
}
