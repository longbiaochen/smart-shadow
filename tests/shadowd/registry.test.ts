import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { Registry } from "../../src/shadow/registry.js";

test("registry creates default file and persists projects bindings and processed messages", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "smart-shadow-registry-"));
  const registryPath = path.join(dir, "nested", "registry.json");

  try {
    const registry = new Registry(registryPath);
    const data = await registry.load();

    assert.equal(data.version, 1);
    assert.equal(data.projects[0]?.key, "smart-shadow");
    assert.equal(registry.hasProcessed("m-1"), false);

    registry.upsertProject({ key: "docs", name: "Docs", cwd: "/tmp/docs", aliases: ["文档"] });
    registry.setBinding("feishu:c:t", {
      codexThreadId: "codex-thread-1",
      projectKey: "docs",
      cwd: "/tmp/docs",
      updatedAt: "2026-06-05T00:00:00.000Z"
    });
    registry.markProcessed("m-1", "done");
    await registry.save();

    const loaded = new Registry(registryPath);
    await loaded.load();
    assert.equal(loaded.getProjects().find((project) => project.key === "docs")?.cwd, "/tmp/docs");
    assert.equal(loaded.getBinding("feishu:c:t")?.codexThreadId, "codex-thread-1");
    assert.equal(loaded.hasProcessed("m-1"), true);

    const raw = JSON.parse(await readFile(registryPath, "utf8"));
    assert.equal(raw.processedMessages["m-1"].status, "done");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
