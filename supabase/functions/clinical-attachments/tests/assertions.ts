export function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

export function assertEquals<T>(
  actual: T,
  expected: T,
  message?: string,
): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

export async function assertRejects(
  action: () => unknown | Promise<unknown>,
  messageIncludes?: string,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (messageIncludes && !message.includes(messageIncludes)) {
      throw new Error(
        `Expected rejection containing ${messageIncludes}, received ${message}`,
      );
    }
    return;
  }
  throw new Error("Expected operation to reject");
}
