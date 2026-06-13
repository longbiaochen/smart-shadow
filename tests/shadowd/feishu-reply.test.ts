import assert from "node:assert/strict";
import test from "node:test";
import { buildAddReactionArgs, buildDeleteReactionArgs, buildReplyArgs, extractMessageResult } from "../../src/feishu/reply.js";
import { buildCreateTaskArgs, extractTaskResult } from "../../src/feishu/tasks.js";

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

test("buildReplyArgs can force a reply into a Feishu thread", () => {
  assert.deepEqual(buildReplyArgs({ chatId: "oc-1", messageId: "om-1", text: "收到", replyInThread: true }), [
    "im",
    "+messages-reply",
    "--as",
    "bot",
    "--message-id",
    "om-1",
    "--text",
    "收到",
    "--reply-in-thread"
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

test("extractMessageResult reads message and thread ids from lark-cli replies", () => {
  assert.deepEqual(extractMessageResult(JSON.stringify({ data: { message_id: "om-reply", thread_id: "omt-thread" } })), {
    messageId: "om-reply",
    threadId: "omt-thread"
  });
  assert.deepEqual(extractMessageResult(JSON.stringify({ data: { message: { message_id: "om-nested", thread_id: "omt-nested" } } })), {
    messageId: "om-nested",
    threadId: "omt-nested"
  });
});

test("buildCreateTaskArgs creates bot-owned Feishu task requests", () => {
  assert.deepEqual(
    buildCreateTaskArgs({
      summary: "更新 Smart Shadow README",
      description: "Smart Shadow 已接收并分派此任务。",
      idempotencyKey: "smart-shadow:m-1"
    }),
    [
      "task",
      "+create",
      "--as",
      "bot",
      "--summary",
      "更新 Smart Shadow README",
      "--description",
      "Smart Shadow 已接收并分派此任务。",
      "--idempotency-key",
      "smart-shadow:m-1"
    ]
  );
});

test("extractTaskResult reads nested task url, guid, and summary", () => {
  assert.deepEqual(
    extractTaskResult(
      JSON.stringify({
        data: {
          task: {
            guid: "task_001",
            summary: "更新 Smart Shadow README",
            url: "https://applink.feishu.cn/client/todo/task?guid=task_001"
          }
        }
      })
    ),
    {
      guid: "task_001",
      summary: "更新 Smart Shadow README",
      url: "https://applink.feishu.cn/client/todo/task?guid=task_001"
    }
  );
});
