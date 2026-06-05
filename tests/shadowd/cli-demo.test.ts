import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { discoverLocalProjects, parseCliArgs } from "../../src/index.js";
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

test("discoverLocalProjects exposes project slugs and compact aliases for Chats routing", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "shadowd-projects-"));
  try {
    await mkdir(path.join(dir, "chat-type"));
    await mkdir(path.join(dir, ".ignored"));

    const projects = await discoverLocalProjects(dir);

    assert.deepEqual(projects.map((project) => project.key), ["chat-type"]);
    assert.equal(projects[0]?.cwd, path.join(dir, "chat-type"));
    assert.ok(projects[0]?.aliases.includes("chattype"));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
