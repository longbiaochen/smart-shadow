import assert from "node:assert/strict";
import test from "node:test";

import { defaultConfig } from "../../src/config.js";
import { CodexThreads } from "../../src/codex/threads.js";
import { Registry } from "../../src/shadow/registry.js";

test("startThread extracts nested thread id from Codex AppServer response", async () => {
  const client = {
    onNotification: () => undefined,
    request: async () => ({
      thread: { id: "550e8400-e29b-41d4-a716-446655440000" }
    })
  };
  const threads = new CodexThreads(client as never, defaultConfig);

  assert.equal(await threads.startThread({ cwd: "." }), "550e8400-e29b-41d4-a716-446655440000");
});

test("startThread rejects missing or invalid thread ids", async () => {
  const client = {
    onNotification: () => undefined,
    request: async () => ({ thread: { id: "undefined" } })
  };
  const threads = new CodexThreads(client as never, defaultConfig);

  await assert.rejects(() => threads.startThread({ cwd: "." }), /invalid thread id/);
});

test("waitForTurnCompleted returns aggregated agent message deltas", async () => {
  let notificationHandler: ((msg: { method: string; params?: unknown }) => void) | undefined;
  const client = {
    onNotification: (handler: (msg: { method: string; params?: unknown }) => void) => {
      notificationHandler = handler;
    },
    request: async () => ({})
  };
  const threads = new CodexThreads(client as never, defaultConfig);
  const wait = threads.waitForTurnCompleted({ threadId: "550e8400-e29b-41d4-a716-446655440000", timeoutMs: 1000 });

  notificationHandler?.({
    method: "item/agentMessage/delta",
    params: { threadId: "550e8400-e29b-41d4-a716-446655440000", turnId: "turn-1", itemId: "item-1", delta: "{\"action\":\"" }
  });
  notificationHandler?.({
    method: "item/agentMessage/delta",
    params: { threadId: "550e8400-e29b-41d4-a716-446655440000", turnId: "turn-1", itemId: "item-1", delta: "reply_only\"}" }
  });
  notificationHandler?.({
    method: "turn/completed",
    params: { threadId: "550e8400-e29b-41d4-a716-446655440000", turn: { id: "turn-1" } }
  });

  assert.equal((await wait).finalText, "{\"action\":\"reply_only\"}");
});

test("ensureMainThread replaces stale or non-Chats registry thread ids", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  registry.setMainThread({
    threadId: "550e8400-e29b-41d4-a716-446655440000",
    cwd: ".",
    title: "smart-shadow-main"
  });
  const methods: string[] = [];
  const requests: Array<{ method: string; params?: unknown }> = [];
  const client = {
    onNotification: () => undefined,
    request: async (method: string, params?: unknown) => {
      methods.push(method);
      requests.push({ method, params });
      if (method === "thread/resume") throw new Error("thread not found");
      if (method === "thread/start") return { thread: { id: "650e8400-e29b-41d4-a716-446655440000" } };
      return {};
    }
  };
  const threads = new CodexThreads(client as never, defaultConfig);

  assert.equal(await threads.ensureMainThread(registry), "650e8400-e29b-41d4-a716-446655440000");
  assert.deepEqual(methods, ["thread/start"]);
  assert.deepEqual(requests[0]?.params, { title: "shadowd-router" });
  assert.equal(registry.getMainThread()?.threadId, "650e8400-e29b-41d4-a716-446655440000");
  assert.equal(registry.getMainThread()?.cwd, "");
});

test("ensureMainThread reuses the current Chats router thread", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  registry.setMainThread({
    threadId: "550e8400-e29b-41d4-a716-446655440000",
    cwd: "",
    title: "shadowd-router"
  });
  const methods: string[] = [];
  const client = {
    onNotification: () => undefined,
    request: async (method: string) => {
      methods.push(method);
      return {};
    }
  };
  const threads = new CodexThreads(client as never, defaultConfig);

  assert.equal(await threads.ensureMainThread(registry), "550e8400-e29b-41d4-a716-446655440000");
  assert.deepEqual(methods, ["thread/resume"]);
});
