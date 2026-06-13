import assert from "node:assert/strict";
import test from "node:test";

import { dispatchMessage, parseDispatchDecision } from "../../src/codex/dispatcher.js";
import { buildDispatcherPrompt, buildWorkingThreadPrompt } from "../../src/codex/prompts.js";
import { appendTaskBoardLink, buildDispatchProgressMessage, createTaskBoardItem, handleDecision } from "../../src/index.js";
import { Registry } from "../../src/shadow/registry.js";
import type { KnownProject, ShadowMessage, ThreadBinding } from "../../src/shadow/types.js";

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

const binding: ThreadBinding = {
  codexThreadId: "550e8400-e29b-41d4-a716-446655440000",
  projectKey: "smart-shadow",
  cwd: "/repo/smart-shadow",
  updatedAt: "2026-06-05T00:01:00.000Z"
};

test("dispatcher prompt stays compact while preserving routing contract and binding context", () => {
  const prompt = buildDispatcherPrompt({ msg, existingBinding: binding });

  assert.match(prompt, /只返回 JSON/);
  assert.match(prompt, /Smart Shadow 项目/);
  assert.match(prompt, /来自飞书的 main session 默认创建在 Smart Shadow 项目里/);
  assert.match(prompt, /不要编造 thread id/);
  assert.match(prompt, /Codex 自己可见的项目和会话清单/);
  assert.doesNotMatch(prompt, /Known projects:/);
  assert.doesNotMatch(prompt, /Candidate threads:/);
  assert.doesNotMatch(prompt, /aliases/);
  assert.doesNotMatch(prompt, /"raw"/);
  assert.match(prompt, /"codexThreadId": "550e8400-e29b-41d4-a716-446655440000"/);
  assert.match(prompt, /"chat_id": "c-1"/);
  assert.match(prompt, /"thread_id": "t-1"/);
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

  assert.match(prompt, /来源：/);
  assert.match(prompt, /未经明确授权，不要发送飞书消息/);
  assert.match(prompt, /最终回复必须适合直接发回飞书/);
  assert.match(prompt, /状态：done \/ blocked \/ needs_approval \/ failed/);
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
    codex,
    registry
  });

  assert.equal(decision.action, "ask_user");
  assert.equal(decision.confidence, 0);
  assert.match(decision.question ?? "", /补充项目或目录/);
});

test("handleDecision starts a thread only for an allowed known project cwd", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  let started = false;
  const codex = {
    startThread: async () => {
      started = true;
      return "650e8400-e29b-41d4-a716-446655440000";
    },
    resumeThread: async () => undefined,
    startTurn: async () => ({ turnId: "turn-1" }),
    waitForTurnCompleted: async () => ({ finalText: "done", raw: {} })
  };

  const text = await handleDecision({
    msg,
    decision: {
      action: "start_thread",
      confidence: 0.9,
      reason: "smart-shadow implied",
      projectKey: "smart-shadow",
      cwd: "/repo/smart-shadow",
      riskLevel: "low",
      requiresApproval: false
    },
    bindingKey: "feishu:c-1:t-1",
    codex: codex as never,
    registry,
    replier: {} as never,
    projects
  });

  assert.equal(started, true);
  assert.equal(text, "done");
});

test("handleDecision rejects unknown cwd unless the user explicitly supplied that path", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  let started = false;
  const codex = {
    startThread: async () => {
      started = true;
      return "650e8400-e29b-41d4-a716-446655440000";
    },
    resumeThread: async () => undefined,
    startTurn: async () => ({ turnId: "turn-1" }),
    waitForTurnCompleted: async () => ({ finalText: "done", raw: {} })
  };

  const text = await handleDecision({
    msg,
    decision: {
      action: "start_thread",
      confidence: 0.9,
      reason: "model guessed a cwd",
      projectKey: "unknown",
      cwd: "/repo/not-known",
      riskLevel: "low",
      requiresApproval: false
    },
    bindingKey: "feishu:c-1:t-1",
    codex: codex as never,
    registry,
    replier: {} as never,
    projects
  });

  assert.equal(started, false);
  assert.match(text, /需要更多信息/);
});

test("handleDecision resumes an existing binding and runs the working prompt", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  const calls: string[] = [];
  const codex = {
    startThread: async () => "650e8400-e29b-41d4-a716-446655440000",
    resumeThread: async () => {
      calls.push("resume");
    },
    startTurn: async () => {
      calls.push("turn");
      return { turnId: "turn-1" };
    },
    waitForTurnCompleted: async () => ({ finalText: "resumed", raw: {} })
  };

  const text = await handleDecision({
    msg,
    decision: {
      action: "resume_thread",
      confidence: 0.9,
      reason: "existing Feishu binding",
      targetThreadId: binding.codexThreadId,
      cwd: binding.cwd,
      projectKey: binding.projectKey,
      riskLevel: "low",
      requiresApproval: false
    },
    binding,
    bindingKey: "feishu:c-1:t-1",
    codex: codex as never,
    registry,
    replier: {} as never,
    projects
  });

  assert.deepEqual(calls, ["resume", "turn"]);
  assert.equal(text, "resumed");
});

test("handleDecision rejects an unresumable thread id instead of executing blindly", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  let turnStarted = false;
  const codex = {
    startThread: async () => "650e8400-e29b-41d4-a716-446655440000",
    resumeThread: async () => {
      throw new Error("thread not found");
    },
    startTurn: async () => {
      turnStarted = true;
      return { turnId: "turn-1" };
    },
    waitForTurnCompleted: async () => ({ finalText: "should not run", raw: {} })
  };

  const text = await handleDecision({
    msg,
    decision: {
      action: "resume_thread",
      confidence: 0.9,
      reason: "model guessed a thread",
      targetThreadId: "750e8400-e29b-41d4-a716-446655440000",
      cwd: "/repo/smart-shadow",
      projectKey: "smart-shadow",
      riskLevel: "low",
      requiresApproval: false
    },
    bindingKey: "feishu:c-1:t-1",
    codex: codex as never,
    registry,
    replier: {} as never,
    projects
  });

  assert.equal(turnStarted, false);
  assert.match(text, /应该恢复哪个 Codex thread/);
});

test("createTaskBoardItem creates a Feishu task only for working-thread decisions", async () => {
  const created = await createTaskBoardItem({
    msg,
    decision: {
      action: "start_thread",
      confidence: 0.9,
      reason: "smart-shadow implied",
      threadTitle: "更新 Smart Shadow README",
      projectKey: "smart-shadow",
      cwd: "/repo/smart-shadow",
      riskLevel: "low",
      requiresApproval: false
    },
    taskClient: {
      createTask: async (input) => ({
        summary: input.summary,
        url: "https://applink.feishu.cn/client/todo/task?guid=task_001"
      })
    }
  });

  assert.deepEqual(created, {
    created: true,
    title: "更新 Smart Shadow README",
    url: "https://applink.feishu.cn/client/todo/task?guid=task_001"
  });

  const skipped = await createTaskBoardItem({
    msg,
    decision: {
      action: "reply_only",
      confidence: 0.9,
      reason: "simple",
      replyText: "收到",
      riskLevel: "low",
      requiresApproval: false
    },
    taskClient: {
      createTask: async () => {
        throw new Error("should not create");
      }
    }
  });

  assert.equal(skipped, undefined);
});

test("dispatch progress and final replies expose the plain Feishu task URL", () => {
  const taskBoard = {
    created: true,
    title: "更新 Smart Shadow README",
    url: "https://applink.feishu.cn/client/todo/task?guid=task_001"
  };
  const decision = {
    action: "start_thread" as const,
    confidence: 0.9,
    reason: "smart-shadow implied",
    threadTitle: "更新 Smart Shadow README",
    projectKey: "smart-shadow",
    cwd: "/repo/smart-shadow",
    riskLevel: "low" as const,
    requiresApproval: false
  };

  const progress = buildDispatchProgressMessage(decision, taskBoard);
  assert.match(progress, /已完成分派/);
  assert.match(progress, /启动新的 Codex thread/);
  assert.match(progress, /任务看板：https:\/\/applink\.feishu\.cn\/client\/todo\/task\?guid=task_001/);

  assert.equal(
    appendTaskBoardLink("状态：done\n摘要：完成。", taskBoard),
    "状态：done\n摘要：完成。\n\n任务看板：https://applink.feishu.cn/client/todo/task?guid=task_001"
  );
});
