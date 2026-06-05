import { dispatchMessage } from "./codex/dispatcher.js";
import { defaultConfig } from "./config.js";
import { normalizeFeishuEvent } from "./shadow/normalize.js";
import { Registry } from "./shadow/registry.js";

export async function runFixtureDemo(): Promise<string> {
  const lines: string[] = [];
  const rawEvent = {
    event_id: "demo-event-1",
    header: { event_type: "im.message.receive_v1" },
    event: {
      sender: { sender_id: { user_id: "demo-user" }, name: "Demo User" },
      message: {
        message_id: "demo-message-1",
        chat_id: "demo-chat",
        chat_type: "p2p",
        message_type: "text",
        content: JSON.stringify({ text: "Smart Shadow 测试：请回复你收到了。" })
      }
    }
  };
  const msg = normalizeFeishuEvent(rawEvent, defaultConfig.feishu.eventKey);
  const registry = new Registry(":memory:");
  await registry.load();
  const projects = registry.getProjects();
  const codex = {
    ensureMainThread: async () => "demo-main-thread",
    startTurn: async () => ({ turnId: "demo-turn" }),
    waitForTurnCompleted: async () => ({
      finalText: JSON.stringify({
        action: "reply_only",
        confidence: 0.95,
        reason: "demo acknowledgement",
        replyText: "Smart Shadow 收到：Feishu -> shadowd -> dispatcher -> dry-run reply 链路正常。",
        riskLevel: "low",
        requiresApproval: false
      }),
      raw: {}
    })
  };

  lines.push(`received Feishu message: ${msg.message.id} text="${msg.message.text}"`);
  const decision = await dispatchMessage({ msg, projects, candidateThreads: [], codex, registry });
  lines.push(`dispatcher decision: ${decision.action} confidence=${decision.confidence}`);
  const replyText = decision.replyText ?? decision.reason;
  lines.push(`[dry-run feishu reply] chat=${msg.chat.id} thread=${msg.thread.id ?? ""} message=${msg.message.id}`);
  lines.push(replyText);
  return `${lines.join("\n")}\n`;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runFixtureDemo().then((text) => process.stdout.write(text)).catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
