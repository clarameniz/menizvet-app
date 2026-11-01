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
): Promise<void> {
  try {
    await action();
  } catch {
    return;
  }
  throw new Error("Expected operation to reject");
}
