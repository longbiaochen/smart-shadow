import { readFile } from "node:fs/promises";
import path from "node:path";
import YAML from "yaml";
import { z } from "zod";

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
  codex: {
    appServer: { command: "codex", args: ["app-server", "--stdio"] },
    model: "gpt-5.5",
    defaultCwd: ".",
    mainProjectKey: "smart-shadow",
    dispatcherThreadTitle: "smart-shadow-main",
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
  return ConfigSchema.parse({
    service: { ...defaultConfig.service, ...parsed.service },
    feishu: { ...defaultConfig.feishu, ...parsed.feishu },
    codex: {
      ...defaultConfig.codex,
      ...parsed.codex,
      appServer: { ...defaultConfig.codex.appServer, ...parsed.codex?.appServer }
    },
    routing: { ...defaultConfig.routing, ...parsed.routing },
    registry: { ...defaultConfig.registry, ...parsed.registry }
  });
}

export async function loadConfig(inputPath = process.env.SMART_SHADOW_CONFIG ?? "config/smart-shadow.yaml"): Promise<Config> {
  const text = await readFile(inputPath, "utf8");
  const loaded = YAML.parse(text);
  const config = mergeConfig(loaded);
  config.registry.path = path.isAbsolute(config.registry.path) ? config.registry.path : path.resolve(config.registry.path);
  return config;
}
