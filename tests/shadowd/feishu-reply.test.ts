import assert from "node:assert/strict";
import test from "node:test";
import { buildReplyArgs } from "../../src/feishu/reply.js";

test("buildReplyArgs replies to the source message with the current lark-cli command", () => {
  assert.deepEqual(buildReplyArgs({ chatId: "oc-1", messageId: "om-1", text: "收到" }), [
    "im",
    "+messages-reply",
    "--as",
    "bot",
    "--message-id",
    "om-1",
    "--text",
    "收到"
  ]);
});

test("buildReplyArgs falls back to sending to the chat when no message id exists", () => {
  assert.deepEqual(buildReplyArgs({ chatId: "oc-1", text: "收到" }), [
    "im",
    "+messages-send",
    "--as",
    "bot",
    "--chat-id",
    "oc-1",
    "--text",
    "收到"
  ]);
});
