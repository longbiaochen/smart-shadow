import { randomUUID } from "node:crypto";

import { extractFeishuText } from "../feishu/parse.js";
import type { ShadowMessage } from "./types.js";

function pickString(...values: unknown[]): string | undefined {
  return values.find((value): value is string => typeof value === "string" && value.length > 0);
}

function getPath(source: unknown, path: string[]): unknown {
  let current = source;
  for (const key of path) {
    if (!current || typeof current !== "object") return undefined;
    current = (current as Record<string, unknown>)[key];
  }
  return current;
}

export function normalizeFeishuEvent(raw: unknown, eventKey: string): ShadowMessage {
  const event = getPath(raw, ["event"]) ?? raw;
  const message = getPath(event, ["message"]) ?? event;
  const sender = getPath(event, ["sender"]) ?? {};
  const senderId = getPath(sender, ["sender_id"]) ?? {};
  const messageType = pickString(getPath(message, ["message_type"]), getPath(message, ["type"])) ?? "unknown";
  const chatType = pickString(getPath(message, ["chat_type"])) ?? "unknown";
  const messageId = pickString(getPath(message, ["message_id"]), getPath(raw, ["message_id"])) ?? randomUUID();
  const id = pickString(getPath(raw, ["event_id"]), getPath(raw, ["uuid"]), messageId) ?? randomUUID();

  return {
    id,
    source: "feishu",
    eventKey: pickString(getPath(raw, ["header", "event_type"]), eventKey) ?? eventKey,
    receivedAt: new Date().toISOString(),
    sender: {
      id: pickString(
        getPath(senderId, ["user_id"]),
        getPath(senderId, ["open_id"]),
        getPath(senderId, ["union_id"]),
        getPath(event, ["sender_id"]),
        getPath(sender, ["user_id"]),
        getPath(sender, ["id"])
      ) ?? "unknown",
      name: pickString(getPath(sender, ["name"]), getPath(sender, ["sender_name"]))
    },
    chat: {
      id: pickString(getPath(message, ["chat_id"]), getPath(event, ["chat_id"])) ?? "unknown",
      type: chatType === "p2p" || chatType === "group" ? chatType : "unknown",
      name: pickString(getPath(message, ["chat_name"]), getPath(event, ["chat_name"]))
    },
    thread: {
      id: pickString(getPath(message, ["thread_id"]), getPath(message, ["parent_id"])),
      rootId: pickString(getPath(message, ["root_id"]))
    },
    message: {
      id: messageId,
      type: messageType === "text" || messageType === "post" || messageType === "image" || messageType === "file" ? messageType : "unknown",
      text: extractFeishuText(getPath(message, ["content"])),
      raw: message
    },
    raw
  };
}
