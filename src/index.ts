import { mkdir, readdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { CodexAppServerClient } from "./codex/appserver.js";
import { dispatchMessage } from "./codex/dispatcher.js";
import { buildWorkingThreadPrompt } from "./codex/prompts.js";
import { CodexThreads } from "./codex/threads.js";
import { loadConfig } from "./config.js";
import { FeishuEventListener } from "./feishu/listen.js";
import { FeishuReplier } from "./feishu/reply.js";
import { FeishuTaskClient, type FeishuTaskResult } from "./feishu/tasks.js";
import { shouldRouteGitHubMessage } from "./github/guard.js";
import { GitHubWebhookListener } from "./github/listen.js";
import { GitHubReplier } from "./github/reply.js";
import { runGitHubIssueWorkflow } from "./github/workflow.js";
import { createLogger } from "./logger.js";
import { isAllowedMessage, shouldProcessMessage } from "./shadow/guard.js";
import { normalizeFeishuEvent } from "./shadow/normalize.js";
import { Registry } from "./shadow/registry.js";
import type { DispatchDecision, KnownProject, ShadowMessage, ThreadBinding } from "./shadow/types.js";

export function parseCliArgs(argv = process.argv): { maxEvents?: number; timeoutMs?: number } {
  const maxEventsArg = argv.find((arg) => arg.startsWith("--max-events="));
  const timeoutArg = argv.find((arg) => arg.startsWith("--timeout="));
  const maxEvents = maxEventsArg ? Number(maxEventsArg.split("=")[1]) : undefined;
  const timeoutValue = timeoutArg?.split("=")[1];
  const timeoutMs = timeoutValue ? Number(timeoutValue.replace(/s$/, "")) * 1000 : undefined;
  return { maxEvents, timeoutMs };
}

function bindingKey(msg: ShadowMessage): string {
  if (msg.source === "github" && msg.github) return msg.github.conversationKey;
  return `feishu:${msg.chat.id}:${msg.thread.id ?? msg.message.id}`;
}

function resolveCwd(cwd: string): string {
  return path.isAbsolute(cwd) ? cwd : path.resolve(process.cwd(), cwd);
}

function projectAliases(slug: string): string[] {
  const compact = slug.replace(/[-_\s]/g, "");
  return Array.from(new Set([slug, compact, slug.replace(/-/g, " "), slug.replace(/-/g, "")].filter(Boolean)));
}

export async function discoverLocalProjects(projectsRoot = path.join(os.homedir(), "Projects")): Promise<KnownProject[]> {
  let entries;
  try {
    entries = await readdir(projectsRoot, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => ({
      key: entry.name,
      name: entry.name,
      cwd: path.join(projectsRoot, entry.name),
      aliases: projectAliases(entry.name)
    }))
    .sort((a, b) => a.key.localeCompare(b.key));
}

export async function knownProjectsForDispatch(registry: Registry): Promise<KnownProject[]> {
  const byKey = new Map<string, KnownProject>();
  for (const project of registry.getProjects()) {
    byKey.set(project.key, { ...project, cwd: resolveCwd(project.cwd) });
  }
  for (const project of await discoverLocalProjects()) {
    byKey.set(project.key, project);
  }
  return Array.from(byKey.values()).sort((a, b) => a.key.localeCompare(b.key));
}

function cwdAllowed(cwd: string | undefined, projects: KnownProject[], msg: ShadowMessage): boolean {
  if (!cwd) return false;
  if (projects.some((project) => resolveCwd(project.cwd) === resolveCwd(cwd))) return true;
  return msg.message.text.includes(cwd);
}

export interface TaskBoardStatus {
  created: boolean;
  title?: string;
  url?: string;
  error?: string;
}

function needsWorkingThread(decision: DispatchDecision): boolean {
  return decision.action === "start_thread" || decision.action === "resume_thread";
}

function truncateText(text: string, maxLength: number): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  return normalized.length <= maxLength ? normalized : `${normalized.slice(0, maxLength - 1)}...`;
}

function taskTitleForDecision(msg: ShadowMessage, decision: DispatchDecision): string {
  return truncateText(decision.threadTitle ?? decision.targetThreadTitle ?? msg.message.text, 120) || "Smart Shadow 任务";
}

function buildTaskDescription(msg: ShadowMessage, decision: DispatchDecision): string {
  const sourceLine = msg.source === "github" && msg.github
    ? `来源：GitHub ${msg.github.repository} ${msg.github.conversationKey} ${msg.github.url ?? ""}`
    : `来源：飞书 chat=${msg.chat.id} thread=${msg.thread.id ?? ""} message=${msg.message.id}`;
  return [
    "Smart Shadow 已接收并分派此任务。",
    "",
    sourceLine,
    `路由：${decision.action} project=${decision.projectKey ?? ""} cwd=${decision.cwd ?? ""}`,
    `原因：${decision.reason}`,
    "",
    "用户原始请求：",
    truncateText(msg.message.text, 1800)
  ].join("\n");
}

async function writeDeadLetter(input: { msg: ShadowMessage; error: unknown }): Promise<void> {
  await mkdir("var/github/dead-letter", { recursive: true });
  const id = `${Date.now()}-${(input.msg.github?.deliveryId ?? input.msg.id).replace(/[^a-zA-Z0-9_.-]/g, "_")}.json`;
  await writeFile(path.join("var/github/dead-letter", id), `${JSON.stringify({ message: input.msg, error: String(input.error) }, null, 2)}\n`, "utf8");
}

export async function createTaskBoardItem(input: {
  msg: ShadowMessage;
  decision: DispatchDecision;
  taskClient: Pick<FeishuTaskClient, "createTask">;
}): Promise<TaskBoardStatus | undefined> {
  if (!needsWorkingThread(input.decision)) return undefined;
  const title = taskTitleForDecision(input.msg, input.decision);
  try {
    const task: FeishuTaskResult = await input.taskClient.createTask({
      summary: title,
      description: buildTaskDescription(input.msg, input.decision),
      idempotencyKey: `smart-shadow:${input.msg.message.id}`
    });
    return { created: true, title: task.summary ?? title, url: task.url };
  } catch (error) {
    return { created: false, title, error: String(error) };
  }
}

function taskBoardLine(taskBoard?: TaskBoardStatus): string {
  if (!taskBoard) return "任务看板：无需创建独立任务";
  if (taskBoard.url) return `任务看板：${taskBoard.url}`;
  if (taskBoard.created) return `任务看板：任务已创建，但飞书返回中没有链接`;
  return `任务看板：创建失败（${taskBoard.error ?? "未知错误"}）`;
}

export function buildDispatchProgressMessage(decision: DispatchDecision, taskBoard?: TaskBoardStatus): string {
  if (!needsWorkingThread(decision)) {
    return `已收到，已完成判断：${decision.reason}`;
  }
  const route = decision.action === "resume_thread" ? "恢复已有 Codex thread" : "启动新的 Codex thread";
  return [
    "已收到，已完成分派。",
    `我准备这样做：${route}，把实际工作交给目标 thread 执行。`,
    `分配位置：${decision.projectKey ?? "未指定项目"} ${decision.cwd ?? ""}`.trim(),
    `接下来：main session 只负责看板和状态回传，工作 thread 完成后我会把 summary 发回这里。`,
    taskBoardLine(taskBoard)
  ].join("\n");
}

export function appendTaskBoardLink(text: string, taskBoard?: TaskBoardStatus): string {
  if (!taskBoard || !needsTaskBoardFooter(taskBoard)) return text;
  return `${text.trim()}\n\n${taskBoardLine(taskBoard)}`;
}

function needsTaskBoardFooter(taskBoard: TaskBoardStatus): boolean {
  return Boolean(taskBoard.url || taskBoard.created || taskBoard.error);
}

export async function handleDecision(input: {
  msg: ShadowMessage;
  decision: DispatchDecision;
  binding?: ThreadBinding;
  bindingKey: string;
  codex: CodexThreads;
  registry: Registry;
  replier: FeishuReplier;
  projects: KnownProject[];
}): Promise<string> {
  const { msg, decision, codex } = input;
  if (decision.action === "reply_only") return decision.replyText ?? decision.reason;
  if (decision.action === "ask_user") return decision.question ?? "我需要更多信息才能判断应该在哪个项目执行。";
  if (decision.action === "reject") return decision.reason;

  if (decision.action === "resume_thread") {
    if (!decision.targetThreadId) return "我需要更多信息才能判断应该恢复哪个 Codex thread。";
    try {
      await codex.resumeThread({ threadId: decision.targetThreadId, cwd: decision.cwd });
    } catch {
      return "我需要更多信息才能判断应该恢复哪个 Codex thread。";
    }
    const prompt = buildWorkingThreadPrompt({ msg, decision });
    await codex.startTurn({ threadId: decision.targetThreadId, cwd: decision.cwd, prompt });
    const completed = await codex.waitForTurnCompleted({ threadId: decision.targetThreadId });
    input.registry.setBinding(input.bindingKey, {
      codexThreadId: decision.targetThreadId,
      projectKey: decision.projectKey ?? "unknown",
      cwd: decision.cwd ?? "",
      updatedAt: new Date().toISOString()
    });
    return completed.finalText;
  }

  if (decision.action === "start_thread") {
    if (!cwdAllowed(decision.cwd, input.projects, msg)) return "我需要更多信息才能判断应该在哪个项目执行。";
    const cwd = decision.cwd ?? ".";
    const threadId = await codex.startThread({ cwd, title: decision.threadTitle });
    const prompt = buildWorkingThreadPrompt({ msg, decision });
    await codex.startTurn({ threadId, cwd, prompt: decision.initialPrompt ? `${decision.initialPrompt}\n\n${prompt}` : prompt });
    const completed = await codex.waitForTurnCompleted({ threadId });
    input.registry.setBinding(input.bindingKey, {
      codexThreadId: threadId,
      projectKey: decision.projectKey ?? "unknown",
      cwd,
      updatedAt: new Date().toISOString()
    });
    return completed.finalText;
  }

  return "无法处理该决策。";
}

async function main(): Promise<void> {
  const config = await loadConfig();
  const { maxEvents, timeoutMs } = parseCliArgs();
  const logger = createLogger(config.service.logLevel);
  logger.info({
    defaultCwd: config.codex.defaultCwd,
    mainProjectKey: config.codex.mainProjectKey,
    dispatcherThreadTitle: config.codex.dispatcherThreadTitle,
    registryPath: config.registry.path
  }, "shadowd codex routing config");
  if (config.feishu.allowedUsers.length === 0 && config.feishu.allowedChats.length === 0) {
    logger.warn("allowedUsers and allowedChats are empty; local development mode allows all Feishu messages");
  }
  const registry = new Registry(config.registry.path);
  await registry.load();
  const startupProjects = await knownProjectsForDispatch(registry);
  logger.info({ projectCount: startupProjects.length, firstProjects: startupProjects.slice(0, 12).map((project) => project.key) }, "loaded startup dispatch projects");
  const appServer = new CodexAppServerClient(config);
  await appServer.start();
  const codex = new CodexThreads(appServer, config);
  await codex.ensureMainThread(registry);
  const replier = new FeishuReplier({ cliBin: config.feishu.cliBin, dryRunReply: config.feishu.dryRunReply });
  const taskClient = new FeishuTaskClient({ cliBin: config.feishu.cliBin, dryRun: config.feishu.dryRunReply });
  const githubReplier = new GitHubReplier({ dryRunReply: config.github.dryRunReply });
  const githubListener = config.github.enabled ? new GitHubWebhookListener({
    config: config.github,
    secret: process.env[config.github.webhook.secretEnv],
    onMessage: async ({ deliveryId, message: msg }) => {
      logger.info({ deliveryId, repository: msg.github?.repository, eventKey: msg.eventKey }, "received GitHub webhook");
      if (registry.hasProcessedGitHubDelivery(deliveryId) || registry.hasProcessed(msg.message.id)) {
        logger.info({ deliveryId, messageId: msg.message.id }, "skipped duplicate GitHub event");
        return;
      }
      const routeCheck = shouldRouteGitHubMessage(msg, config);
      if (!routeCheck.allowed) {
        logger.info({ deliveryId, reason: routeCheck.reason }, "ignored GitHub event");
        registry.markProcessedGitHubDelivery(deliveryId, routeCheck.reason ?? "ignored");
        await registry.save();
        return;
      }
      if (!msg.github?.number || msg.github.itemType === "workflow") {
        registry.markProcessedGitHubDelivery(deliveryId, "unsupported_github_item");
        await registry.save();
        return;
      }

      try {
        const result = await runGitHubIssueWorkflow({ msg, config, registry, replier: githubReplier });
        await githubReplier.addLabels({ repository: msg.github.repository, number: msg.github.number, labels: [result.status === "pr_created" ? "ready-for-review" : "no-code-changes"] });
        registry.markProcessed(msg.message.id, result.status);
        registry.markProcessedGitHubDelivery(deliveryId, result.status);
        await registry.save();
      } catch (error) {
        await writeDeadLetter({ msg, error });
        registry.markProcessedGitHubDelivery(deliveryId, "failed");
        await registry.save();
        throw error;
      }
    }
  }) : undefined;
  const listener = new FeishuEventListener({
    cliBin: config.feishu.cliBin,
    eventKey: config.feishu.eventKey,
    identity: config.feishu.identity,
    maxEvents,
    timeoutMs
  });

  const stop = async () => {
    await githubListener?.stop();
    await listener.stop();
    await appServer.stop();
  };
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());

  try {
    await githubListener?.start();
    await listener.start(async (event) => {
      const msg = normalizeFeishuEvent(event, config.feishu.eventKey);
      logger.info({ messageId: msg.message.id, chatId: msg.chat.id, textPreview: msg.message.text.slice(0, 120) }, "received Feishu message");
      const allowed = isAllowedMessage(msg, config);
      if (!allowed.allowed) {
        logger.warn({ reason: allowed.reason, messageId: msg.message.id }, "rejected Feishu message");
        if (config.feishu.dryRunReply) await replier.reply({ chatId: msg.chat.id, messageId: msg.message.id, text: `无权限：${allowed.reason}` });
        return;
      }
      const processCheck = shouldProcessMessage(msg, registry);
      if (!processCheck.shouldProcess) {
        logger.info({ reason: processCheck.reason, messageId: msg.message.id }, "skipped Feishu message");
        return;
      }
      let typingReactionId: string | undefined;
      try {
        try {
          typingReactionId = await replier.addTypingReaction({ messageId: msg.message.id });
        } catch (error) {
          logger.warn({ messageId: msg.message.id, error: String(error) }, "failed to add Feishu typing reaction");
        }
        if (!msg.message.text.trim()) {
          await replier.reply({ chatId: msg.chat.id, threadId: msg.thread.id, messageId: msg.message.id, text: "暂不支持此消息类型。" });
          registry.markProcessed(msg.message.id, "unsupported_message_type");
          await registry.save();
          return;
        }
        const ackResult = await replier.reply({
          chatId: msg.chat.id,
          threadId: msg.thread.id,
          messageId: msg.message.id,
          text: "已收到，我开始判断任务路由。",
          replyInThread: true
        });
        const replyThreadId = msg.thread.id ?? ackResult.threadId;
        const key = bindingKey(msg);
        const binding = registry.getBinding(key);
        const projects = await knownProjectsForDispatch(registry);
        logger.info({ projectCount: projects.length, firstProjects: projects.slice(0, 8).map((project) => project.key) }, "loaded dispatch projects");
        const decision = await dispatchMessage({ msg, existingBinding: binding, codex, registry });
        const taskBoard = await createTaskBoardItem({ msg, decision, taskClient });
        await replier.reply({
          chatId: msg.chat.id,
          threadId: replyThreadId,
          messageId: msg.message.id,
          text: buildDispatchProgressMessage(decision, taskBoard),
          replyInThread: true
        });
        const text = await handleDecision({ msg, decision, binding, bindingKey: key, codex, registry, replier, projects });
        const replyResult = await replier.reply({
          chatId: msg.chat.id,
          threadId: replyThreadId,
          messageId: msg.message.id,
          text: appendTaskBoardLink(text, taskBoard),
          replyInThread: true
        });
        const boundThread = registry.getBinding(key);
        if (replyResult.threadId && boundThread) {
          registry.setBinding(`feishu:${msg.chat.id}:${replyResult.threadId}`, { ...boundThread, updatedAt: new Date().toISOString() });
        }
        registry.markProcessed(msg.message.id, decision.action);
        await registry.save();
      } finally {
        try {
          await replier.deleteReaction({ messageId: msg.message.id, reactionId: typingReactionId });
        } catch (error) {
          logger.warn({ messageId: msg.message.id, error: String(error) }, "failed to remove Feishu typing reaction");
        }
      }
    });
  } finally {
    await appServer.stop();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
