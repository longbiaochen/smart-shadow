import assert from "node:assert/strict";
import test from "node:test";

import { dispatchMessage, parseDispatchDecision } from "../../src/codex/dispatcher.js";
import { buildDispatcherPrompt, buildWorkingThreadPrompt } from "../../src/codex/prompts.js";
import { Registry } from "../../src/shadow/registry.js";
import type { CandidateThread, KnownProject, ShadowMessage } from "../../src/shadow/types.js";

const msg: ShadowMessage = {
  id: "event-1",
  source: "feishu",
  eventKey: "im.message.receive_v1",
  receivedAt: "2026-06-05T00:00:00.000Z",
  sender: { id: "u-1", name: "Long" },
  chat: { id: "c-1", type: "group", name: "Ops" },
  thread: { id: "t-1", rootId: "r-1" },
  message: { id: "m-1", type: "text", text: "在智能影子项目里更新 README", raw: {} },
  raw: {}
};

const projects: KnownProject[] = [
  { key: "smart-shadow", name: "智能影子", cwd: "/repo/smart-shadow", aliases: ["智能影子", "Smart Shadow"] }
];

const candidates: CandidateThread[] = [
  { threadId: "thread-1", title: "old README work", cwd: "/repo/smart-shadow" }
];

test("dispatcher prompt requires JSON-only routing and uses known projects and candidate threads", () => {
  const prompt = buildDispatcherPrompt({ msg, projects, candidateThreads: candidates, existingBinding: undefined });

  assert.match(prompt, /Return JSON only/);
  assert.match(prompt, /Do not invent thread ids/);
  assert.match(prompt, /"key": "smart-shadow"/);
  assert.match(prompt, /"threadId": "thread-1"/);
  assert.match(prompt, /在智能影子项目里更新 README/);
});

test("working prompt is Feishu-ready and blocks unsafe actions without approval", () => {
  const prompt = buildWorkingThreadPrompt({
    msg,
    decision: {
      action: "start_thread",
      confidence: 0.9,
      reason: "smart-shadow implied",
      projectKey: "smart-shadow",
      cwd: "/repo/smart-shadow",
      riskLevel: "low",
      requiresApproval: false
    }
  });

  assert.match(prompt, /Source:/);
  assert.match(prompt, /Do not send Feishu messages/);
  assert.match(prompt, /Final response must be Feishu-ready/);
  assert.match(prompt, /Status: done \/ blocked \/ needs_approval \/ failed/);
});

test("parseDispatchDecision extracts fenced JSON and validates action shape", () => {
  const decision = parseDispatchDecision("```json\n{\"action\":\"reply_only\",\"confidence\":0.8,\"reason\":\"simple\",\"replyText\":\"收到\",\"riskLevel\":\"low\",\"requiresApproval\":false}\n```");

  assert.equal(decision.action, "reply_only");
  assert.equal(decision.replyText, "收到");
});

test("dispatchMessage returns ask_user when dispatcher output is invalid JSON", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  const codex = {
    ensureMainThread: async () => "main-thread",
    startTurn: async () => ({ turnId: "turn-1" }),
    waitForTurnCompleted: async () => ({ finalText: "not json", raw: {} })
  };

  const decision = await dispatchMessage({
    msg,
    projects,
    candidateThreads: candidates,
    codex,
    registry
  });

  assert.equal(decision.action, "ask_user");
  assert.equal(decision.confidence, 0);
  assert.match(decision.question ?? "", /补充项目或目录/);
});
