import { execa } from "execa";

export const TYPING_REACTION_EMOJI = "Typing";

export interface FeishuMessageResult {
  messageId?: string;
  threadId?: string;
}

export function buildReplyArgs(input: { chatId: string; messageId?: string; text: string; replyInThread?: boolean }): string[] {
  if (input.messageId) {
    const args = ["im", "+messages-reply", "--as", "bot", "--message-id", input.messageId, "--text", input.text];
    if (input.replyInThread) args.push("--reply-in-thread");
    return args;
  }
  return ["im", "+messages-send", "--as", "bot", "--chat-id", input.chatId, "--text", input.text];
}

export function buildAddReactionArgs(input: { messageId: string; emojiType?: string }): string[] {
  return [
    "im",
    "reactions",
    "create",
    "--as",
    "bot",
    "--params",
    JSON.stringify({ message_id: input.messageId }),
    "--data",
    JSON.stringify({ reaction_type: { emoji_type: input.emojiType ?? TYPING_REACTION_EMOJI } })
  ];
}

export function buildDeleteReactionArgs(input: { messageId: string; reactionId: string }): string[] {
  return [
    "im",
    "reactions",
    "delete",
    "--as",
    "bot",
    "--params",
    JSON.stringify({ message_id: input.messageId, reaction_id: input.reactionId })
  ];
}

function extractReactionId(stdout: string): string | undefined {
  const parsed = JSON.parse(stdout) as { data?: { reaction_id?: unknown } };
  return typeof parsed.data?.reaction_id === "string" ? parsed.data.reaction_id : undefined;
}

export function extractMessageResult(stdout: string): FeishuMessageResult {
  if (!stdout.trim()) return {};
  const parsed = JSON.parse(stdout) as {
    data?: {
      message_id?: unknown;
      thread_id?: unknown;
      message?: { message_id?: unknown; thread_id?: unknown };
    };
  };
  const data = parsed.data ?? {};
  const message = data.message ?? {};
  return {
    messageId: typeof data.message_id === "string" ? data.message_id : typeof message.message_id === "string" ? message.message_id : undefined,
    threadId: typeof data.thread_id === "string" ? data.thread_id : typeof message.thread_id === "string" ? message.thread_id : undefined
  };
}

export class FeishuReplier {
  constructor(private readonly options: { cliBin: string; dryRunReply: boolean }) {}

  async addTypingReaction(input: { messageId: string }): Promise<string | undefined> {
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run feishu reaction] add ${TYPING_REACTION_EMOJI} message=${input.messageId}\n`);
      return undefined;
    }
    const result = await execa(this.options.cliBin, buildAddReactionArgs(input), { stdin: "ignore" });
    return extractReactionId(result.stdout);
  }

  async deleteReaction(input: { messageId: string; reactionId?: string }): Promise<void> {
    if (!input.reactionId) return;
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run feishu reaction] delete message=${input.messageId} reaction=${input.reactionId}\n`);
      return;
    }
    await execa(this.options.cliBin, buildDeleteReactionArgs({ messageId: input.messageId, reactionId: input.reactionId }), { stdin: "ignore" });
  }

  async reply(input: { chatId: string; threadId?: string; messageId?: string; text: string; replyInThread?: boolean }): Promise<FeishuMessageResult> {
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run feishu reply] chat=${input.chatId} thread=${input.threadId ?? ""} message=${input.messageId ?? ""} replyInThread=${input.replyInThread ? "true" : "false"}\n${input.text}\n`);
      return {};
    }
    const result = await execa(this.options.cliBin, buildReplyArgs(input), { stdin: "ignore" });
    return extractMessageResult(result.stdout);
  }
}
