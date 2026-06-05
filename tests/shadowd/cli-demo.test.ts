import assert from "node:assert/strict";
import test from "node:test";

import { parseCliArgs } from "../../src/index.js";
import { runFixtureDemo } from "../../src/demo.js";

test("parseCliArgs supports pnpm forwarded timeout and max-events flags", () => {
  assert.deepEqual(parseCliArgs(["node", "src/index.ts", "--", "--timeout=5s", "--max-events=1"]), {
    timeoutMs: 5000,
    maxEvents: 1
  });
});

test("fixture demo returns a Feishu dry-run reply transcript", async () => {
  const transcript = await runFixtureDemo();

  assert.match(transcript, /received Feishu message/);
  assert.match(transcript, /dispatcher decision: reply_only/);
  assert.match(transcript, /\[dry-run feishu reply\]/);
  assert.match(transcript, /Smart Shadow 收到/);
});
