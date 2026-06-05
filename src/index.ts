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
import type { CandidateThread, DispatchDecision, KnownProject, ShadowMessage, ThreadBinding } from "./shadow/types.js";

function bindingKey(msg: ShadowMessage): string {
  return `feishu:${msg.chat.id}:${msg.thread.id ?? msg.message.id}`;
}

function uniqueThreads(items: CandidateThread[]): CandidateThread[] {
  const seen = new Set<string>();
  return items.filter((item) => {
    if (seen.has(item.threadId)) return false;
    seen.add(item.threadId);
    return true;
  });
}

function resolveCwd(cwd: string): string {
  return path.isAbsolute(cwd) ? cwd : path.resolve(process.cwd(), cwd);
}

function cwdAllowed(cwd: string | undefined, projects: KnownProject[], msg: ShadowMessage): boolean {
  if (!cwd) return false;
  if (projects.some((project) => resolveCwd(project.cwd) === resolveCwd(cwd))) return true;
  return msg.message.text.includes(cwd);
}

async function collectCandidates(input: {
  msg: ShadowMessage;
  binding?: ThreadBinding;
  codex: CodexThreads;
  projects: KnownProject[];
  limit: number;
}): Promise<CandidateThread[]> {
  const candidates: CandidateThread[] = [];
  if (input.binding) {
    candidates.push({ threadId: input.binding.codexThreadId, cwd: input.binding.cwd, updatedAt: input.binding.updatedAt });
  }
  candidates.push(...await input.codex.listCandidates({ limit: input.limit }));
  candidates.push(...await input.codex.listCandidates({ searchTerm: input.msg.message.text.slice(0, 80), limit: input.limit }));
  for (const project of input.projects) {
    candidates.push(...await input.codex.listCandidates({ cwd: project.cwd, limit: 5 }));
  }
  return uniqueThreads(candidates).slice(0, input.limit);
}

async function handleDecision(input: {
  msg: ShadowMessage;
  decision: DispatchDecision;
  candidates: CandidateThread[];
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
    const allowed = input.candidates.some((item) => item.threadId === decision.targetThreadId);
    if (!decision.targetThreadId || !allowed) return "我需要更多信息才能判断应该恢复哪个 Codex thread。";
    await codex.resumeThread({ threadId: decision.targetThreadId, cwd: decision.cwd });
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
  const maxEventsArg = process.argv.find((arg) => arg.startsWith("--max-events="));
  const timeoutArg = process.argv.find((arg) => arg.startsWith("--timeout="));
  const maxEvents = maxEventsArg ? Number(maxEventsArg.split("=")[1]) : undefined;
  const timeoutMs = timeoutArg ? Number(timeoutArg.split("=")[1].replace(/s$/, "")) * 1000 : undefined;
  const logger = createLogger(config.service.logLevel);
  if (config.feishu.allowedUsers.length === 0 && config.feishu.allowedChats.length === 0) {
    logger.warn("allowedUsers and allowedChats are empty; local development mode allows all Feishu messages");
  }
  const registry = new Registry(config.registry.path);
  await registry.load();
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
    if (!msg.message.text.trim()) {
      await replier.reply({ chatId: msg.chat.id, threadId: msg.thread.id, messageId: msg.message.id, text: "暂不支持此消息类型。" });
      registry.markProcessed(msg.message.id, "unsupported_message_type");
      await registry.save();
      return;
    }
    const key = bindingKey(msg);
    const binding = registry.getBinding(key);
    const projects = registry.getProjects();
    const candidates = await collectCandidates({ msg, binding, codex, projects, limit: config.routing.maxCandidateThreads });
    const decision = await dispatchMessage({ msg, projects, candidateThreads: candidates, existingBinding: binding, codex, registry });
    const text = await handleDecision({ msg, decision, candidates, bindingKey: key, codex, registry, replier, projects });
    await replier.reply({ chatId: msg.chat.id, threadId: msg.thread.id, messageId: msg.message.id, text });
    registry.markProcessed(msg.message.id, decision.action);
    await registry.save();
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
