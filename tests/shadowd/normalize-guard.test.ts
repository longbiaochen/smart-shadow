import assert from "node:assert/strict";
import test from "node:test";

import { defaultConfig } from "../../src/config.js";
import { normalizeFeishuEvent } from "../../src/shadow/normalize.js";
import { isAllowedMessage, shouldProcessMessage } from "../../src/shadow/guard.js";
import { Registry } from "../../src/shadow/registry.js";

test("normalizes a Feishu text event into a ShadowMessage without routing business logic", () => {
  const raw = {
    event_id: "event-1",
    header: { event_type: "im.message.receive_v1" },
    event: {
      sender: { sender_id: { user_id: "ou-user-1" }, sender_type: "user", name: "Long" },
      message: {
        message_id: "om-message-1",
        chat_id: "oc-chat-1",
        chat_type: "group",
        thread_id: "omt-thread-1",
        root_id: "om-root-1",
        message_type: "text",
        content: JSON.stringify({ text: "在智能影子项目里更新 README" })
      }
    }
  };

  const msg = normalizeFeishuEvent(raw, "im.message.receive_v1");

  assert.equal(msg.id, "event-1");
  assert.equal(msg.sender.id, "ou-user-1");
  assert.equal(msg.chat.id, "oc-chat-1");
  assert.equal(msg.chat.type, "group");
  assert.equal(msg.thread.id, "omt-thread-1");
  assert.equal(msg.message.id, "om-message-1");
  assert.equal(msg.message.type, "text");
  assert.equal(msg.message.text, "在智能影子项目里更新 README");
  assert.deepEqual(msg.raw, raw);
});

test("normalizes lark-cli flattened message events", () => {
  const raw = {
    type: "im.message.receive_v1",
    event_id: "event-flat-1",
    message_id: "om-flat-1",
    chat_id: "oc-flat-1",
    chat_type: "p2p",
    sender_id: "ou-flat-sender",
    message_type: "text",
    content: "Smart Shadow current-app 链路测试"
  };

  const msg = normalizeFeishuEvent(raw, "im.message.receive_v1");

  assert.equal(msg.id, "event-flat-1");
  assert.equal(msg.sender.id, "ou-flat-sender");
  assert.equal(msg.chat.id, "oc-flat-1");
  assert.equal(msg.chat.type, "p2p");
  assert.equal(msg.message.id, "om-flat-1");
  assert.equal(msg.message.type, "text");
  assert.equal(msg.message.text, "Smart Shadow current-app 链路测试");
});

test("guard enforces allow lists and message de-duplication", async () => {
  const msg = normalizeFeishuEvent({
    event: {
      sender: { sender_id: { user_id: "u-1" } },
      message: {
        message_id: "m-1",
        chat_id: "c-1",
        chat_type: "p2p",
        message_type: "text",
        content: JSON.stringify({ text: "hello" })
      }
    }
  }, "im.message.receive_v1");

  const config = {
    ...defaultConfig,
    feishu: { ...defaultConfig.feishu, allowedUsers: ["u-2"], allowedChats: [] }
  };
  assert.deepEqual(isAllowedMessage(msg, config), { allowed: false, reason: "sender_not_allowed" });

  const devConfig = {
    ...defaultConfig,
    feishu: { ...defaultConfig.feishu, allowedUsers: [], allowedChats: [] }
  };
  assert.deepEqual(isAllowedMessage(msg, devConfig), { allowed: true });

  const registry = new Registry(":memory:");
  await registry.load();
  assert.deepEqual(shouldProcessMessage(msg, registry), { shouldProcess: true });
  registry.markProcessed("m-1", "done");
  assert.deepEqual(shouldProcessMessage(msg, registry), { shouldProcess: false, reason: "already_processed" });
});
