export async function computeSha256(bytes: Uint8Array): Promise<Uint8Array> {
  // A copy backed by a plain ArrayBuffer, as Web Crypto's BufferSource requires.
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
  );
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join(
    "",
  );
}
