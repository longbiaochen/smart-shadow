import type { Config } from "../config.js";
import type { Registry } from "./registry.js";
import type { ShadowMessage } from "./types.js";

export function isAllowedMessage(msg: ShadowMessage, config: Config): { allowed: boolean; reason?: string } {
  if (config.feishu.allowedUsers.length > 0 && !config.feishu.allowedUsers.includes(msg.sender.id)) {
    return { allowed: false, reason: "sender_not_allowed" };
  }
  if (config.feishu.allowedChats.length > 0 && !config.feishu.allowedChats.includes(msg.chat.id)) {
    return { allowed: false, reason: "chat_not_allowed" };
  }
  if (msg.chat.type === "group" && config.feishu.requireMentionInGroup && !/@|智能影子|Smart Shadow|smartshadow/i.test(msg.message.text)) {
    return { allowed: false, reason: "mention_required" };
  }
  return { allowed: true };
}

export function shouldProcessMessage(msg: ShadowMessage, registry: Registry): { shouldProcess: boolean; reason?: string } {
  if (registry.hasProcessed(msg.message.id) || registry.hasProcessed(msg.id)) {
    return { shouldProcess: false, reason: "already_processed" };
  }
  return { shouldProcess: true };
}
