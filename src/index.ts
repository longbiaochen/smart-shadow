import { readdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { CodexAppServerClient } from "./codex/appserver.js";
import { dispatchMessage } from "./codex/dispatcher.js";
import { buildWorkingThreadPrompt } from "./codex/prompts.js";
import { CodexThreads } from "./codex/threads.js";
import { loadConfig } from "./config.js";
import { FeishuEventListener } from "./feishu/listen.js";
import { FeishuReplier } from "./feishu/reply.js";
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
  const { msg, decision, codex, replier } = input;
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
  const listener = new FeishuEventListener({
    cliBin: config.feishu.cliBin,
    eventKey: config.feishu.eventKey,
    identity: config.feishu.identity,
    maxEvents,
    timeoutMs
  });

  const stop = async () => {
    await listener.stop();
    await appServer.stop();
  };
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());

  try {
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
        const key = bindingKey(msg);
        const binding = registry.getBinding(key);
        const projects = await knownProjectsForDispatch(registry);
        logger.info({ projectCount: projects.length, firstProjects: projects.slice(0, 8).map((project) => project.key) }, "loaded dispatch projects");
        const decision = await dispatchMessage({ msg, existingBinding: binding, codex, registry });
        const text = await handleDecision({ msg, decision, binding, bindingKey: key, codex, registry, replier, projects });
        await replier.reply({ chatId: msg.chat.id, threadId: msg.thread.id, messageId: msg.message.id, text });
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
