import { execa } from "execa";

export interface FeishuTaskResult {
  guid?: string;
  url?: string;
  summary?: string;
}

export function buildCreateTaskArgs(input: {
  summary: string;
  description?: string;
  idempotencyKey?: string;
  asIdentity?: "bot" | "user";
}): string[] {
  const args = ["task", "+create", "--as", input.asIdentity ?? "bot", "--summary", input.summary];
  if (input.description) args.push("--description", input.description);
  if (input.idempotencyKey) args.push("--idempotency-key", input.idempotencyKey);
  return args;
}

function visitJson(value: unknown, visitor: (key: string, value: unknown) => void, key = ""): void {
  if (Array.isArray(value)) {
    for (const item of value) visitJson(item, visitor);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [childKey, childValue] of Object.entries(value)) {
    visitor(childKey, childValue);
    visitJson(childValue, visitor, childKey);
  }
}

export function extractTaskResult(stdout: string): FeishuTaskResult {
  if (!stdout.trim()) return {};
  const parsed = JSON.parse(stdout) as unknown;
  const result: FeishuTaskResult = {};
  visitJson(parsed, (key, value) => {
    if (typeof value !== "string") return;
    if (!result.url && key === "url" && /^https?:\/\//.test(value)) result.url = value;
    if (!result.guid && ["guid", "task_guid"].includes(key)) result.guid = value;
    if (!result.summary && ["summary", "title"].includes(key)) result.summary = value;
  });
  return result;
}

export class FeishuTaskClient {
  constructor(private readonly options: { cliBin: string; dryRun: boolean }) {}

  async createTask(input: { summary: string; description?: string; idempotencyKey?: string }): Promise<FeishuTaskResult> {
    const args = buildCreateTaskArgs({ ...input, asIdentity: "bot" });
    if (this.options.dryRun) {
      process.stdout.write(`[dry-run feishu task create] ${args.join(" ")}\n`);
      return { summary: input.summary };
    }
    const result = await execa(this.options.cliBin, args, { stdin: "ignore" });
    return extractTaskResult(result.stdout);
  }
}
