import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import { defaultConfig, loadConfigFromObject } from "../../src/config.js";
import { shouldRouteGitHubMessage } from "../../src/github/guard.js";
import { GitHubWebhookListener } from "../../src/github/listen.js";
import { buildGitHubAckComment, buildGitHubFinalComment, buildGitHubLabelArgs, buildGitHubReplyArgs } from "../../src/github/reply.js";
import { normalizeGitHubWebhook } from "../../src/github/normalize.js";
import { verifyGitHubSignature } from "../../src/github/verify.js";
import { toGitHubIssueTask } from "../../src/github/adapter.js";
import { branchForTask, buildShadowIssuePrompt, lockKeyForTask, runGitHubIssueWorkflow, splitTrustedCommand, statusCommentAccepted } from "../../src/github/workflow.js";
import { Registry } from "../../src/shadow/registry.js";

function signature(secret: string, body: string): string {
  return `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`;
}

const issuePayload = {
  action: "assigned",
  repository: { full_name: "longbiaochen/smart-shadow" },
  sender: { login: "longbiaochen" },
  assignee: { login: "shadow" },
  issue: {
    id: 221,
    number: 221,
    title: "Smart Shadow webhook task",
    body: "请口袋处理这个任务",
    html_url: "https://github.com/longbiaochen/smart-shadow/issues/221",
    labels: [],
    assignees: [{ login: "shadow" }],
    created_at: "2026-06-08T00:00:00Z"
  }
};

test("verifies GitHub webhook signatures against the raw body", () => {
  const body = JSON.stringify(issuePayload);

  assert.equal(verifyGitHubSignature({ rawBody: body, signature256: signature("secret", body), secret: "secret" }), true);
  assert.equal(verifyGitHubSignature({ rawBody: body, signature256: signature("wrong", body), secret: "secret" }), false);
  assert.equal(verifyGitHubSignature({ rawBody: body, signature256: undefined, secret: "secret" }), false);
});

test("normalizes a shadow-assigned issue into a GitHub ShadowMessage", () => {
  const msg = normalizeGitHubWebhook({
    eventName: "issues",
    deliveryId: "delivery-1",
    payload: issuePayload
  });

  assert.equal(msg.source, "github");
  assert.equal(msg.id, "github:delivery-1");
  assert.equal(msg.eventKey, "issues:assigned");
  assert.equal(msg.sender.id, "longbiaochen");
  assert.equal(msg.chat.id, "longbiaochen/smart-shadow");
  assert.equal(msg.thread.id, "issue:221");
  assert.equal(msg.message.id, "github:issue:221:assigned");
  assert.equal(msg.message.type, "text");
  assert.match(msg.message.text, /Smart Shadow webhook task/);
  assert.match(msg.message.text, /请口袋处理这个任务/);
  assert.equal(msg.github?.repository, "longbiaochen/smart-shadow");
  assert.equal(msg.github?.owner, "longbiaochen");
  assert.equal(msg.github?.repo, "smart-shadow");
  assert.equal(msg.github?.eventName, "issues");
  assert.equal(msg.github?.action, "assigned");
  assert.equal(msg.github?.trigger, "assigned");
  assert.equal(msg.github?.issueTitle, "Smart Shadow webhook task");
  assert.equal(msg.github?.issueBody, "请口袋处理这个任务");
  assert.deepEqual(msg.github?.labels, []);
  assert.deepEqual(msg.github?.assignees, ["shadow"]);
});

test("normalizes issue comments and pull request review comments to stable conversations", () => {
  const issueComment = normalizeGitHubWebhook({
    eventName: "issue_comment",
    deliveryId: "delivery-2",
    payload: {
      action: "created",
      repository: { full_name: "longbiaochen/smart-shadow" },
      sender: { login: "longbiaochen" },
      issue: { number: 221, title: "Smart Shadow", html_url: "https://github.com/longbiaochen/smart-shadow/issues/221", labels: [] },
      comment: { id: 9001, body: "口袋继续", html_url: "https://github.com/longbiaochen/smart-shadow/issues/221#issuecomment-9001", created_at: "2026-06-08T00:01:00Z" }
    }
  });
  assert.equal(issueComment.github?.conversationKey, "github:longbiaochen/smart-shadow:issue:221");
  assert.equal(issueComment.message.id, "github:comment:9001");
  assert.match(issueComment.message.text, /口袋继续/);

  const reviewComment = normalizeGitHubWebhook({
    eventName: "pull_request_review_comment",
    deliveryId: "delivery-3",
    payload: {
      action: "created",
      repository: { full_name: "longbiaochen/smart-shadow" },
      sender: { login: "reviewer" },
      pull_request: { number: 42, title: "Webhook channel", html_url: "https://github.com/longbiaochen/smart-shadow/pull/42", labels: [{ name: "agent" }] },
      comment: { id: 7001, body: "Smart Shadow 处理这里", html_url: "https://github.com/longbiaochen/smart-shadow/pull/42#discussion_r7001", created_at: "2026-06-08T00:02:00Z" }
    }
  });
  assert.equal(reviewComment.github?.conversationKey, "github:longbiaochen/smart-shadow:pull:42");
  assert.equal(reviewComment.thread.id, "pull:42");
});

test("GitHub guard routes only configured repos, senders, assignees and @shadow comments", () => {
  const config = loadConfigFromObject({
    github: {
      enabled: true,
      events: ["issues", "issue_comment"],
      assignee: "shadow",
      repos: {
        "longbiaochen/smart-shadow": {
          localPath: "/tmp/smart-shadow",
          defaultBase: "main",
          allowedSenders: ["longbiaochen"]
        }
      },
      dryRunReply: true
    }
  });
  const msg = normalizeGitHubWebhook({ eventName: "issues", deliveryId: "delivery-1", payload: issuePayload });
  assert.deepEqual(shouldRouteGitHubMessage(msg, config), { allowed: true });

  const wrongAssignee = normalizeGitHubWebhook({
    eventName: "issues",
    deliveryId: "delivery-ordinary",
    payload: {
      ...issuePayload,
      assignee: { login: "someone-else" },
      issue: { ...issuePayload.issue, assignees: [{ login: "someone-else" }] }
    }
  });
  assert.deepEqual(shouldRouteGitHubMessage(wrongAssignee, config), { allowed: false, reason: "assignee_not_shadow" });

  const labeled = normalizeGitHubWebhook({
    eventName: "issues",
    deliveryId: "delivery-labeled",
    payload: {
      ...issuePayload,
      action: "labeled",
      label: { name: "agent:shadow" },
      issue: { ...issuePayload.issue, labels: [{ name: "task" }, { name: "agent:shadow" }] }
    }
  });
  assert.deepEqual(shouldRouteGitHubMessage(labeled, config), { allowed: false, reason: "trigger_not_matched" });

  const commentCommand = normalizeGitHubWebhook({
    eventName: "issue_comment",
    deliveryId: "delivery-command",
    payload: {
      ...issuePayload,
      action: "created",
      comment: { id: 100, body: "@shadow fix\nplease handle", html_url: "https://github.com/longbiaochen/smart-shadow/issues/221#issuecomment-100" }
    }
  });
  assert.equal(commentCommand.github?.command, "@shadow fix");
  assert.deepEqual(shouldRouteGitHubMessage(commentCommand, config), { allowed: true });

  const oldSlashCommand = normalizeGitHubWebhook({
    eventName: "issue_comment",
    deliveryId: "delivery-old-command",
    payload: {
      ...issuePayload,
      action: "created",
      comment: { id: 102, body: "/shadow fix\nplease handle", html_url: "https://github.com/longbiaochen/smart-shadow/issues/221#issuecomment-102" }
    }
  });
  assert.equal(oldSlashCommand.github?.command, undefined);
  assert.deepEqual(shouldRouteGitHubMessage(oldSlashCommand, config), { allowed: false, reason: "comment_command_not_matched" });

  const ordinaryComment = normalizeGitHubWebhook({
    eventName: "issue_comment",
    deliveryId: "delivery-comment",
    payload: {
      ...issuePayload,
      action: "created",
      comment: { id: 101, body: "ordinary comment", html_url: "https://github.com/longbiaochen/smart-shadow/issues/221#issuecomment-101" }
    }
  });
  assert.deepEqual(shouldRouteGitHubMessage(ordinaryComment, config), { allowed: false, reason: "comment_command_not_matched" });

  const disallowedRepo = normalizeGitHubWebhook({
    eventName: "issues",
    deliveryId: "delivery-repo",
    payload: { ...issuePayload, repository: { full_name: "someone/else" } }
  });
  assert.deepEqual(shouldRouteGitHubMessage(disallowedRepo, config), { allowed: false, reason: "repository_not_allowed" });

  const disallowedSender = normalizeGitHubWebhook({
    eventName: "issues",
    deliveryId: "delivery-sender",
    payload: {
      ...issuePayload,
      sender: { login: "someone-else" }
    }
  });
  assert.deepEqual(shouldRouteGitHubMessage(disallowedSender, config), { allowed: false, reason: "sender_not_allowed" });
});

test("registry deduplicates GitHub delivery and conversation object IDs", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  assert.equal(registry.hasProcessedGitHubDelivery("delivery-1"), false);
  registry.markProcessedGitHubDelivery("delivery-1", "issues:opened");
  assert.equal(registry.hasProcessedGitHubDelivery("delivery-1"), true);

  registry.setBinding("github:longbiaochen/smart-shadow:issue:221", {
    codexThreadId: "650e8400-e29b-41d4-a716-446655440000",
    projectKey: "smart-shadow",
    cwd: "/Users/longbiao/Projects/smart-shadow",
    updatedAt: "2026-06-08T00:00:00.000Z"
  });
  assert.equal(registry.getBinding("github:longbiaochen/smart-shadow:issue:221")?.projectKey, "smart-shadow");
});

test("GitHub replier builds safe dry-run/API requests for comments and labels", () => {
  assert.deepEqual(buildGitHubReplyArgs({
    repository: "longbiaochen/smart-shadow",
    itemType: "issue",
    number: 221,
    body: "hello"
  }), ["api", "--method", "POST", "/repos/longbiaochen/smart-shadow/issues/221/comments", "-f", "body=hello"]);

  assert.deepEqual(buildGitHubLabelArgs({
    repository: "longbiaochen/smart-shadow",
    number: 221,
    labels: ["doing", "ready-for-review"]
  }), ["api", "--method", "POST", "/repos/longbiaochen/smart-shadow/issues/221/labels", "-f", "labels[]=doing", "-f", "labels[]=ready-for-review"]);

  assert.match(buildGitHubAckComment("task-1"), /"status": "doing"/);
  assert.match(buildGitHubFinalComment("done", "task-1", "完成"), /完成/);
});

test("GitHub issue adapter and prompt preserve the shadow/shadowd naming contract", () => {
  const config = loadConfigFromObject({
    github: {
      enabled: true,
      repos: {
        "longbiaochen/smart-shadow": {
          localPath: "/tmp/smart-shadow",
          defaultBase: "main",
          allowedSenders: ["longbiaochen"],
          testCommand: "pnpm test:shadowd",
          codexSandbox: "workspace-write"
        }
      }
    }
  });
  const msg = normalizeGitHubWebhook({ eventName: "issues", deliveryId: "delivery-task", payload: issuePayload });
  const task = toGitHubIssueTask(msg, config);

  assert.equal(task.source, "github");
  assert.equal(task.agentName, "shadow");
  assert.equal(task.daemonName, "shadowd");
  assert.equal(task.trigger, "assigned");
  assert.equal(task.repoFullName, "longbiaochen/smart-shadow");
  assert.equal(lockKeyForTask(task), "github:longbiaochen/smart-shadow#221:shadow");
  assert.equal(branchForTask(task), "shadow/issue-221-smart-shadow-webhook-task");

  const prompt = buildShadowIssuePrompt({ task, comments: "alice: please fix it" });
  assert.match(prompt, /You are shadow/);
  assert.match(prompt, /executed by shadowd/);
  assert.match(prompt, /Smart Shadow webhook task/);
  assert.match(prompt, /请口袋处理这个任务/);
  assert.match(prompt, /alice: please fix it/);
  assert.match(statusCommentAccepted(task), /`shadow` 已接单/);
});

test("trusted test command splitting keeps quoted config arguments together", () => {
  assert.deepEqual(splitTrustedCommand("pnpm test:shadowd"), ["pnpm", "test:shadowd"]);
  assert.deepEqual(splitTrustedCommand("npm run \"test unit\""), ["npm", "run", "test unit"]);
});

test("GitHub issue workflow builds branch, runs codex/tests, creates PR and comments without live network", async () => {
  const config = loadConfigFromObject({
    github: {
      enabled: true,
      dryRunReply: false,
      repos: {
        "longbiaochen/smart-shadow": {
          localPath: "/tmp/smart-shadow",
          defaultBase: "main",
          allowedSenders: ["longbiaochen"],
          testCommand: "pnpm test:shadowd",
          codexSandbox: "workspace-write"
        }
      }
    }
  });
  const msg = normalizeGitHubWebhook({ eventName: "issues", deliveryId: "delivery-run", payload: issuePayload });
  const registry = new Registry(":memory:");
  await registry.load();
  const calls: string[] = [];
  const comments: string[] = [];
  const result = await runGitHubIssueWorkflow({
    msg,
    config,
    registry,
    replier: {
      async comment(input) {
        comments.push(input.body);
      }
    },
    runner: async (command, args) => {
      calls.push([command, ...args].join(" "));
      if (command === "gh" && args[0] === "api") return { stdout: "alice: context comment", stderr: "", exitCode: 0 };
      if (command === "codex") return { stdout: "Summary\nFiles changed\nTests run", stderr: "", exitCode: 0 };
      if (command === "pnpm") return { stdout: "ok", stderr: "", exitCode: 0 };
      if (command === "git" && args.join(" ") === "status --porcelain") return { stdout: " M README.md", stderr: "", exitCode: 0 };
      if (command === "gh" && args[0] === "pr") return { stdout: "https://github.com/longbiaochen/smart-shadow/pull/9", stderr: "", exitCode: 0 };
      return { stdout: "", stderr: "", exitCode: 0 };
    }
  });

  assert.equal(result.status, "pr_created");
  assert.equal(result.branch, "shadow/issue-221-smart-shadow-webhook-task");
  assert.equal(result.prUrl, "https://github.com/longbiaochen/smart-shadow/pull/9");
  assert.ok(calls.includes("git checkout -B shadow/issue-221-smart-shadow-webhook-task"));
  assert.ok(calls.some((call) => call.startsWith("codex exec --sandbox workspace-write")));
  assert.ok(calls.includes("pnpm test:shadowd"));
  assert.ok(calls.includes("git commit -m Fix issue #221 via shadow"));
  assert.ok(calls.some((call) => call.includes("gh pr create")));
  assert.ok(comments.some((body) => body.includes("`shadow` 已接单")));
  assert.ok(comments.some((body) => body.includes("`shadow` 开始执行")));
  assert.ok(comments.some((body) => body.includes("`shadow` 已创建 PR")));
});

test("GitHub issue workflow returns no-change status without creating a PR", async () => {
  const config = loadConfigFromObject({
    github: {
      enabled: true,
      repos: {
        "longbiaochen/smart-shadow": {
          localPath: "/tmp/smart-shadow",
          defaultBase: "main",
          allowedSenders: ["longbiaochen"]
        }
      }
    }
  });
  const msg = normalizeGitHubWebhook({ eventName: "issues", deliveryId: "delivery-no-change", payload: issuePayload });
  const registry = new Registry(":memory:");
  await registry.load();
  const calls: string[] = [];
  const comments: string[] = [];
  const result = await runGitHubIssueWorkflow({
    msg,
    config,
    registry,
    replier: { async comment(input) { comments.push(input.body); } },
    runner: async (command, args) => {
      calls.push([command, ...args].join(" "));
      if (command === "codex") return { stdout: "Already fixed", stderr: "", exitCode: 0 };
      if (command === "git" && args.join(" ") === "status --porcelain") return { stdout: "", stderr: "", exitCode: 0 };
      return { stdout: "", stderr: "", exitCode: 0 };
    }
  });

  assert.equal(result.status, "no_changes");
  assert.ok(!calls.some((call) => call.includes("gh pr create")));
  assert.ok(comments.some((body) => body.includes("没有产生代码变更")));
});

test("registry lock prevents duplicate GitHub issue execution", async () => {
  const registry = new Registry(":memory:");
  await registry.load();
  assert.equal(registry.acquireTaskLock("github:owner/repo#1:shadow"), true);
  assert.equal(registry.acquireTaskLock("github:owner/repo#1:shadow"), false);
  registry.releaseTaskLock("github:owner/repo#1:shadow", "done");
  assert.equal(registry.acquireTaskLock("github:owner/repo#1:shadow"), true);
});

test("default config includes the canonical GitHub webhook endpoint", () => {
  assert.equal(defaultConfig.github.webhook.publicUrl, "https://smart-shadow.bozhi.ai/channels/github/webhook");
  assert.equal(defaultConfig.github.webhook.secretEnv, "SMART_SHADOW_GITHUB_WEBHOOK_SECRET");
});

test("GitHub webhook listener enforces health, headers, event allowlist, repo allowlist and signature", async () => {
  const config = loadConfigFromObject({
    github: {
      enabled: true,
      webhook: { host: "127.0.0.1", port: 0, path: "/channels/github/webhook" },
      repositories: ["longbiaochen/smart-shadow"],
      events: ["issues"],
      dryRunReply: true
    }
  });
  const received: string[] = [];
  const listener = new GitHubWebhookListener({
    config: config.github,
    secret: "secret",
    onMessage: async ({ message }) => {
      received.push(message.github?.conversationKey ?? "");
    }
  });
  await listener.start();
  const address = listener.address();
  assert.equal(typeof address, "object");
  const base = `http://127.0.0.1:${address && typeof address === "object" ? address.port : 0}`;
  const body = JSON.stringify(issuePayload);

  try {
    assert.equal((await fetch(`${base}/channels/github/healthz`)).status, 200);

    const missingHeaders = await fetch(`${base}/channels/github/webhook`, { method: "POST", body });
    assert.equal(missingHeaders.status, 400);

    const invalidSignature = await fetch(`${base}/channels/github/webhook`, {
      method: "POST",
      body,
      headers: {
        "x-github-event": "issues",
        "x-github-delivery": "delivery-http-1",
        "x-hub-signature-256": signature("wrong", body)
      }
    });
    assert.equal(invalidSignature.status, 401);

    const unsupportedEvent = await fetch(`${base}/channels/github/webhook`, {
      method: "POST",
      body,
      headers: {
        "x-github-event": "push",
        "x-github-delivery": "delivery-http-2",
        "x-hub-signature-256": signature("secret", body)
      }
    });
    assert.equal(unsupportedEvent.status, 202);

    const disallowedRepoBody = JSON.stringify({ ...issuePayload, repository: { full_name: "someone/else" } });
    const disallowedRepo = await fetch(`${base}/channels/github/webhook`, {
      method: "POST",
      body: disallowedRepoBody,
      headers: {
        "x-github-event": "issues",
        "x-github-delivery": "delivery-http-3",
        "x-hub-signature-256": signature("secret", disallowedRepoBody)
      }
    });
    assert.equal(disallowedRepo.status, 202);

    const valid = await fetch(`${base}/channels/github/webhook`, {
      method: "POST",
      body,
      headers: {
        "x-github-event": "issues",
        "x-github-delivery": "delivery-http-4",
        "x-hub-signature-256": signature("secret", body)
      }
    });
    assert.equal(valid.status, 200);
    assert.deepEqual(received, ["github:longbiaochen/smart-shadow:issue:221"]);
  } finally {
    await listener.stop();
  }
});
