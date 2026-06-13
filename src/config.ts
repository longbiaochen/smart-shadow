import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import YAML from "yaml";
import { z } from "zod";

const smartShadowProjectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export const defaultConfig = {
  service: { name: "shadowd", logLevel: "info" },
  feishu: {
    cliBin: "lark-cli",
    eventKey: "im.message.receive_v1",
    identity: "bot" as const,
    allowedUsers: [] as string[],
    allowedChats: [] as string[],
    requireMentionInGroup: false,
    dryRunReply: false
  },
  github: {
    enabled: false,
    webhook: {
      publicUrl: "https://smart-shadow.bozhi.ai/channels/github/webhook",
      host: "127.0.0.1",
      port: 8787,
      path: "/channels/github/webhook",
      secretEnv: "SMART_SHADOW_GITHUB_WEBHOOK_SECRET"
    },
    agentName: "shadow",
    daemonName: "shadowd",
    assignee: "shadow",
    commentCommand: "@shadow",
    allowedCommentCommands: ["@shadow", "@shadow fix", "@shadow continue", "@shadow test", "@shadow explain"],
    repos: {
      "longbiaochen/smart-shadow": {
        localPath: smartShadowProjectRoot,
        defaultBase: "main",
        allowedSenders: ["longbiaochen"],
        testCommand: "pnpm test:shadowd",
        codexSandbox: "workspace-write"
      }
    } as Record<string, {
      localPath: string;
      defaultBase: string;
      allowedSenders: string[];
      testCommand?: string;
      codexSandbox?: string;
    }>,
    repositories: ["longbiaochen/smart-shadow"],
    events: ["issues", "issue_comment"],
    dryRunReply: true
  },
  codex: {
    appServer: { command: "codex", args: ["app-server", "--stdio"] },
    model: "gpt-5.5",
    defaultCwd: smartShadowProjectRoot,
    mainProjectKey: "smart-shadow",
    dispatcherThreadTitle: "shadowd-router",
    approvalPolicy: "unlessTrusted",
    sandbox: "workspaceWrite"
  },
  routing: { maxCandidateThreads: 10, confidenceThreshold: 0.6 },
  registry: { path: ".smart-shadow/registry.json" }
};

const ConfigSchema = z.object({
  service: z.object({ name: z.string(), logLevel: z.string() }),
  feishu: z.object({
    cliBin: z.string(),
    eventKey: z.string(),
    identity: z.enum(["bot", "user", "auto"]),
    allowedUsers: z.array(z.string()),
    allowedChats: z.array(z.string()),
    requireMentionInGroup: z.boolean(),
    dryRunReply: z.boolean()
  }),
  github: z.object({
    enabled: z.boolean(),
    webhook: z.object({
      publicUrl: z.string(),
      host: z.string(),
      port: z.number(),
      path: z.string(),
      secretEnv: z.string()
    }),
    agentName: z.string(),
    daemonName: z.string(),
    assignee: z.string(),
    commentCommand: z.string(),
    allowedCommentCommands: z.array(z.string()),
    repos: z.record(z.object({
      localPath: z.string(),
      defaultBase: z.string(),
      allowedSenders: z.array(z.string()),
      testCommand: z.string().optional(),
      codexSandbox: z.string().optional()
    })),
    repositories: z.array(z.string()),
    events: z.array(z.string()),
    dryRunReply: z.boolean()
  }),
  codex: z.object({
    appServer: z.object({ command: z.string(), args: z.array(z.string()) }),
    model: z.string(),
    defaultCwd: z.string(),
    mainProjectKey: z.string(),
    dispatcherThreadTitle: z.string(),
    approvalPolicy: z.string(),
    sandbox: z.string()
  }),
  routing: z.object({ maxCandidateThreads: z.number(), confidenceThreshold: z.number() }),
  registry: z.object({ path: z.string() })
});

export type Config = z.infer<typeof ConfigSchema>;

function mergeConfig(value: unknown): Config {
  const parsed = (value ?? {}) as Partial<Config>;
  const githubRepos = {
    ...defaultConfig.github.repos,
    ...(parsed.github as Partial<typeof defaultConfig.github> | undefined)?.repos
  };
  const repositories = (parsed.github as Partial<typeof defaultConfig.github> | undefined)?.repositories ?? Object.keys(githubRepos);
  return ConfigSchema.parse({
    service: { ...defaultConfig.service, ...parsed.service },
    feishu: { ...defaultConfig.feishu, ...parsed.feishu },
    github: {
      ...defaultConfig.github,
      ...parsed.github,
      repos: githubRepos,
      repositories,
      webhook: { ...defaultConfig.github.webhook, ...parsed.github?.webhook }
    },
    codex: {
      ...defaultConfig.codex,
      ...parsed.codex,
      appServer: { ...defaultConfig.codex.appServer, ...parsed.codex?.appServer }
    },
    routing: { ...defaultConfig.routing, ...parsed.routing },
    registry: { ...defaultConfig.registry, ...parsed.registry }
  });
}

export function loadConfigFromObject(value: unknown): Config {
  const config = mergeConfig(value);
  config.registry.path = path.isAbsolute(config.registry.path) ? config.registry.path : path.resolve(config.registry.path);
  return config;
}

export async function loadConfig(inputPath = process.env.SMART_SHADOW_CONFIG ?? "config/smart-shadow.yaml"): Promise<Config> {
  const text = await readFile(inputPath, "utf8");
  const loaded = YAML.parse(text);
  return loadConfigFromObject(loaded);
}
