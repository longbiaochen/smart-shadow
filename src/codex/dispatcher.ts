import { z } from "zod";

import { buildDispatcherPrompt } from "./prompts.js";
import { extractJsonObject } from "../shadow/json.js";
import type { Registry } from "../shadow/registry.js";
import type { DispatchDecision, ShadowMessage, ThreadBinding } from "../shadow/types.js";

const DispatchDecisionSchema = z.object({
  action: z.enum(["reply_only", "resume_thread", "start_thread", "ask_user", "reject"]),
  confidence: z.number().min(0).max(1),
  reason: z.string(),
  projectKey: z.string().optional(),
  cwd: z.string().optional(),
  targetThreadId: z.string().optional(),
  targetThreadTitle: z.string().optional(),
  threadTitle: z.string().optional(),
  initialPrompt: z.string().optional(),
  replyText: z.string().optional(),
  question: z.string().optional(),
  riskLevel: z.enum(["low", "medium", "high"]),
  requiresApproval: z.boolean()
});

export function parseDispatchDecision(text: string): DispatchDecision {
  return DispatchDecisionSchema.parse(extractJsonObject(text));
}

export async function dispatchMessage(input: {
  msg: ShadowMessage;
  existingBinding?: ThreadBinding;
  codex: {
    ensureMainThread(registry: Registry): Promise<string>;
    startTurn(input: { threadId: string; prompt: string; cwd?: string }): Promise<{ turnId: string }>;
    waitForTurnCompleted(input: { threadId: string; timeoutMs?: number }): Promise<{ finalText: string; raw: unknown }>;
  };
  registry: Registry;
}): Promise<DispatchDecision> {
  const threadId = await input.codex.ensureMainThread(input.registry);
  const prompt = buildDispatcherPrompt(input);
  await input.codex.startTurn({ threadId, prompt });
  const completed = await input.codex.waitForTurnCompleted({ threadId, timeoutMs: 120_000 });
  try {
    return parseDispatchDecision(completed.finalText);
  } catch {
    return {
      action: "ask_user",
      confidence: 0,
      reason: "dispatcher output is not valid JSON",
      question: "我没有成功判断应该在哪个项目执行，请补充项目或目录。",
      riskLevel: "low",
      requiresApproval: false
    };
  }
}
