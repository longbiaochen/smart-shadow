import type { DispatchDecision, ShadowMessage, ThreadBinding } from "../shadow/types.js";

export function buildDispatcherPrompt(input: {
  msg: ShadowMessage;
  existingBinding?: ThreadBinding;
}): string {
  const minimalMessage = {
    source: input.msg.source,
    event_id: input.msg.id,
    message_id: input.msg.message.id,
    chat_id: input.msg.chat.id,
    chat_type: input.msg.chat.type,
    thread_id: input.msg.thread.id,
    sender_id: input.msg.sender.id,
    received_at: input.msg.receivedAt,
    text: input.msg.message.text
  };
  const binding = input.existingBinding
    ? {
        codexThreadId: input.existingBinding.codexThreadId,
        projectKey: input.existingBinding.projectKey,
        cwd: input.existingBinding.cwd,
        updatedAt: input.existingBinding.updatedAt
      }
    : undefined;
  return `$smart-shadow

You are the shadowd router running in ordinary Codex Chats.
Your job is NOT to execute the task. Your job is to decide where the task should run.
The default intake surface is Chats, not the smart-shadow project. Use this dispatcher thread only for routing decisions, then choose the target project/thread for actual work.
Use Codex's own visible project and session inventory for routing. shadowd will validate cwd and thread choices before executing them, so do not ask shadowd to paste all projects or sessions into this prompt.
Return JSON only. Do not include markdown fences.

Allowed actions:
- reply_only
- resume_thread
- start_thread
- ask_user
- reject

Decision rules:
1. Keep default routing decisions in Chats. Do not treat smart-shadow as the default project.
2. If the user explicitly mentions "智能影子", "Smart Shadow", "smartshadow", or asks to create/modify shadowd or Smart Shadow itself, choose the smart-shadow project cwd.
3. If the task clearly belongs to another Codex-visible project, choose that project.
4. If Existing binding is present and clearly still matches the Feishu thread, choose resume_thread and use that exact targetThreadId.
5. If a Codex-visible existing session is clearly the continuation, choose resume_thread and use that exact targetThreadId.
6. If no existing thread clearly matches, choose start_thread in the best cwd.
7. Do not invent thread ids.
8. cwd must come from Codex-visible projects unless the user explicitly gives a path.
9. If confidence is below 0.6, choose ask_user instead of guessing a project.
10. Do not execute high-risk actions in this dispatcher thread.
11. If the message is simple and can be answered directly, choose reply_only.

Required JSON shape:
{
  "action": "reply_only | resume_thread | start_thread | ask_user | reject",
  "confidence": 0.0,
  "reason": "...",
  "projectKey": "... optional",
  "cwd": "... optional",
  "targetThreadId": "... optional",
  "targetThreadTitle": "... optional",
  "threadTitle": "... optional",
  "initialPrompt": "... optional",
  "replyText": "... optional",
  "question": "... optional",
  "riskLevel": "low | medium | high",
  "requiresApproval": false
}

Feishu message:
${JSON.stringify(minimalMessage, null, 2)}

Existing binding:
${binding ? JSON.stringify(binding, null, 2) : "none"}
`;
}

export function buildWorkingThreadPrompt(input: { msg: ShadowMessage; decision: DispatchDecision }): string {
  const { msg, decision } = input;
  return `$smart-shadow

You are executing a Smart Shadow task from Feishu.

Source:
- source: feishu
- chat_id: ${msg.chat.id}
- thread_id: ${msg.thread.id ?? ""}
- message_id: ${msg.message.id}
- sender_id: ${msg.sender.id}
- received_at: ${msg.receivedAt}

Route:
- project_key: ${decision.projectKey ?? ""}
- cwd: ${decision.cwd ?? ""}

User request:
${msg.message.text}

Dispatcher reason:
${decision.reason}

Execution rules:
1. Work in the current cwd.
2. Gather read-only context first.
3. Use Feishu CLI only when needed for Feishu read/write actions.
4. Do not send Feishu messages, modify Feishu docs/bases, delete files, git push, run destructive shell commands, or operate production servers without explicit approval.
5. Never reveal tokens, secrets, cookies, refresh tokens, SSH keys, or credentials.
6. If blocked, explain why and what is needed.

Final response must be Feishu-ready:
Status: done / blocked / needs_approval / failed
Summary:
Key results:
Files/commands/paths:
Risks or unfinished items:
Next step:
`;
}
