import type { DispatchDecision, ShadowMessage, ThreadBinding } from "../shadow/types.js";

export function buildDispatcherPrompt(input: {
  msg: ShadowMessage;
  existingBinding?: ThreadBinding;
}): string {
  const channelName = input.msg.source === "github" ? "GitHub" : "飞书";
  const minimalMessage = {
    source: input.msg.source,
    event_id: input.msg.id,
    message_id: input.msg.message.id,
    chat_id: input.msg.chat.id,
    chat_type: input.msg.chat.type,
    thread_id: input.msg.thread.id,
    sender_id: input.msg.sender.id,
    received_at: input.msg.receivedAt,
    text: input.msg.message.text,
    github: input.msg.github
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

你是运行在 Smart Shadow 项目里的 shadowd 路由器。
你的职责不是执行任务，而是判断任务应该在哪里运行。
来自飞书的 main session 默认创建在 Smart Shadow 项目里。GitHub channel 也复用 Smart Shadow main session 作为 dispatcher。这个 dispatcher thread 只做路由决策，然后选择真正执行工作的目标项目或 thread。
路由时使用 Codex 自己可见的项目和会话清单。shadowd 会在执行前校验 cwd 和 thread 选择，所以不要要求 shadowd 把所有项目或会话粘贴进这个 prompt。
只返回 JSON，不要包含 Markdown 代码块。

允许的 action：
- reply_only
- resume_thread
- start_thread
- ask_user
- reject

决策规则：
1. 来自飞书或 GitHub 的路由和工作流规则类对话，默认归入 Smart Shadow 项目。
2. 如果用户明确提到“智能影子”、“Smart Shadow”、“SmartShader”、“Smart Shader”、“smartshadow”，或要求创建/修改 shadowd、Smart Shadow、工作流规则、skill 发布，选择 smart-shadow 项目的 cwd。
3. 如果任务明显属于另一个 Codex 可见项目，选择那个项目。
4. 如果存在“已有绑定”，并且它明显仍匹配当前飞书 thread，选择 resume_thread，并使用其中精确的 targetThreadId。
5. 如果 Codex 可见的已有 session 明显是当前任务的延续，选择 resume_thread，并使用精确的 targetThreadId。
6. 如果没有明确匹配的已有 thread，在最佳 cwd 中选择 start_thread。
7. 不要编造 thread id。
8. 除非用户明确给出路径，否则 cwd 必须来自 Codex 可见项目。
9. 如果置信度低于 0.6，选择 ask_user，不要猜项目。
10. 不要在 dispatcher thread 里执行高风险动作。
11. 如果消息很简单且可以直接回答，选择 reply_only。
12. 对实质性 channel 任务，优先给出简短 threadTitle；它也会作为任务/主题标题。
13. 不要在 dispatcher thread 里创建飞书任务、GitHub issue、commit、push 或任何外部写回。

必需 JSON 结构：
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

${channelName}消息：
${JSON.stringify(minimalMessage, null, 2)}

已有绑定：
${binding ? JSON.stringify(binding, null, 2) : "无"}
`;
}

export function buildWorkingThreadPrompt(input: { msg: ShadowMessage; decision: DispatchDecision }): string {
  const { msg, decision } = input;
  const sourceDetails = msg.source === "github"
    ? [
        "- source: github",
        `- repository: ${msg.github?.repository ?? msg.chat.id}`,
        `- conversation_key: ${msg.github?.conversationKey ?? ""}`,
        `- event: ${msg.github?.eventName ?? ""}:${msg.github?.action ?? ""}`,
        `- thread_id: ${msg.thread.id ?? ""}`,
        `- message_id: ${msg.message.id}`,
        `- url: ${msg.github?.url ?? ""}`,
        `- sender_id: ${msg.sender.id}`,
        `- received_at: ${msg.receivedAt}`
      ].join("\n")
    : [
        "- source: feishu",
        `- chat_id: ${msg.chat.id}`,
        `- thread_id: ${msg.thread.id ?? ""}`,
        `- message_id: ${msg.message.id}`,
        `- sender_id: ${msg.sender.id}`,
        `- received_at: ${msg.receivedAt}`
      ].join("\n");
  const finalSurface = msg.source === "github" ? "GitHub issue/PR comment" : "飞书";
  return `$smart-shadow

你正在执行一个来自${msg.source === "github" ? " GitHub" : "飞书"}的 Smart Shadow 任务。

来源：
${sourceDetails}

路由：
- project_key: ${decision.projectKey ?? ""}
- cwd: ${decision.cwd ?? ""}

用户请求：
${msg.message.text}

dispatcher 判断原因：
${decision.reason}

执行规则：
1. 在当前 cwd 中工作。
2. 先收集只读上下文。
3. 只有在确实需要对应 channel 读写动作时才使用 Feishu CLI 或 GitHub API。
4. 未经明确授权，不要发送飞书消息、修改飞书文档/多维表/任务、关闭 GitHub issue、merge PR、删除文件、git push、运行破坏性 shell 命令或操作生产服务器。
5. 永远不要泄露 token、secret、cookie、refresh token、SSH key 或任何凭证。
6. 如果被阻塞，说明原因和需要什么。
7. Smart Shadow main dispatcher 只承担结构性分派；不要把实质工作重新路由回 dispatcher。
8. 对编码任务，判断本地 Codex 执行还是 GitHub Issue/Copilot/CI 跟踪更合适；但凡需要本机私有文件、应用状态、Apple API 或真实浏览器/GUI 验收，都保留在本地 Codex 执行。
9. 飞书任务创建属于共享外部写入。只有当前请求明确授权、且任务适合共享飞书表面时，才能创建或更新飞书任务；个人、健康、财务、关系、安全或私人生活任务默认保留在私有 Apple-native 或内部表面。

最终回复必须适合直接发回${finalSurface}：
状态：done / blocked / needs_approval / failed
摘要：
关键结果：
文件/命令/路径：
风险或未完成项：
下一步：
`;
}
