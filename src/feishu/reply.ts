import { execa } from "execa";

export function buildReplyArgs(input: { chatId: string; messageId?: string; text: string }): string[] {
  if (input.messageId) {
    return ["im", "+messages-reply", "--as", "bot", "--message-id", input.messageId, "--text", input.text];
  }
  return ["im", "+messages-send", "--as", "bot", "--chat-id", input.chatId, "--text", input.text];
}

export class FeishuReplier {
  constructor(private readonly options: { cliBin: string; dryRunReply: boolean }) {}

  async reply(input: { chatId: string; threadId?: string; messageId?: string; text: string }): Promise<void> {
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run feishu reply] chat=${input.chatId} thread=${input.threadId ?? ""} message=${input.messageId ?? ""}\n${input.text}\n`);
      return;
    }
    await execa(this.options.cliBin, buildReplyArgs(input), { stdin: "ignore" });
  }
}
