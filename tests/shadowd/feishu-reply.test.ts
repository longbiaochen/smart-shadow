import assert from "node:assert/strict";
import test from "node:test";
import { buildAddReactionArgs, buildDeleteReactionArgs, buildReplyArgs } from "../../src/feishu/reply.js";

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

test("buildAddReactionArgs adds the Feishu typing reaction to the source message", () => {
  assert.deepEqual(buildAddReactionArgs({ messageId: "om-1" }), [
    "im",
    "reactions",
    "create",
    "--as",
    "bot",
    "--params",
    "{\"message_id\":\"om-1\"}",
    "--data",
    "{\"reaction_type\":{\"emoji_type\":\"Typing\"}}"
  ]);
});

test("buildDeleteReactionArgs removes the Feishu typing reaction by id", () => {
  assert.deepEqual(buildDeleteReactionArgs({ messageId: "om-1", reactionId: "reaction-1" }), [
    "im",
    "reactions",
    "delete",
    "--as",
    "bot",
    "--params",
    "{\"message_id\":\"om-1\",\"reaction_id\":\"reaction-1\"}"
  ]);
});
