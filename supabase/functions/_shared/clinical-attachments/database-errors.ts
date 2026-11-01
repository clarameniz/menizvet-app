export interface PostgrestErrorLike {
  readonly message: string;
  readonly code?: string;
}

export class DatabaseOperationError extends Error {
  constructor(
    readonly databaseCode: string | null,
    message: string,
  ) {
    super(`Database operation failed: ${message}`);
  }
}

export function rpcData<T>(
  data: T | null,
  error: PostgrestErrorLike | null,
): T {
  if (error) {
    throw new DatabaseOperationError(error.code ?? null, error.message);
  }
  if (data === null) throw new Error("Database operation returned no result");
  return data;
}

export type ExpectedDatabaseHttpError = Readonly<{
  status: 401 | 403;
  body: Readonly<Record<string, string>>;
}>;

export function expectedDatabaseHttpError(
  error: DatabaseOperationError,
): ExpectedDatabaseHttpError | null {
  if (error.databaseCode === "28000") {
    return Object.freeze({
      status: 401,
      body: Object.freeze({ error: "AUTHENTICATION_REQUIRED" }),
    });
  }
  if (error.databaseCode === "42501") {
    return Object.freeze({
      status: 403,
      body: Object.freeze({ status: "DENIED" }),
    });
  }
  return null;
}
