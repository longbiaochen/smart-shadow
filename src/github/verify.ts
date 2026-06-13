import { createHmac, timingSafeEqual } from "node:crypto";

export function verifyGitHubSignature(input: { rawBody: string | Buffer; signature256?: string; secret?: string }): boolean {
  if (!input.signature256 || !input.secret) return false;
  const expected = `sha256=${createHmac("sha256", input.secret).update(input.rawBody).digest("hex")}`;
  const actual = input.signature256.trim();
  const expectedBuffer = Buffer.from(expected, "utf8");
  const actualBuffer = Buffer.from(actual, "utf8");
  return expectedBuffer.length === actualBuffer.length && timingSafeEqual(expectedBuffer, actualBuffer);
}
