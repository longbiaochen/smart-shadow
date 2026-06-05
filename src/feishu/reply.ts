import { execa } from "execa";

export class FeishuReplier {
  constructor(private readonly options: { cliBin: string; dryRunReply: boolean }) {}

  async reply(input: { chatId: string; threadId?: string; messageId?: string; text: string }): Promise<void> {
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run feishu reply] chat=${input.chatId} thread=${input.threadId ?? ""} message=${input.messageId ?? ""}\n${input.text}\n`);
      return;
    }
    // TODO: confirm the exact send command against `lark-cli im --help` on this Mac.
    await execa(this.options.cliBin, ["im", "send", "--chat-id", input.chatId, "--text", input.text], { stdin: "ignore" });
  }
}
