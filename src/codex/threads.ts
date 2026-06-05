import type { Config } from "../config.js";
import type { Registry } from "../shadow/registry.js";
import type { CandidateThread } from "../shadow/types.js";
import type { CodexAppServerClient, JsonRpcNotification } from "./appserver.js";

export class CodexThreads {
  private completed = new Map<string, { finalText: string; raw: unknown }>();

  constructor(private readonly client: CodexAppServerClient, private readonly config: Config) {
    this.client.onNotification((msg) => this.handleNotification(msg));
  }

  async listCandidates(input: { searchTerm?: string; cwd?: string; limit?: number }): Promise<CandidateThread[]> {
    const result = await this.client.request<unknown>("thread/list", input);
    const items = Array.isArray(result) ? result : Array.isArray((result as { threads?: unknown[] })?.threads) ? (result as { threads: unknown[] }).threads : [];
    return items.slice(0, input.limit ?? this.config.routing.maxCandidateThreads).map((item) => {
      const thread = item as Record<string, unknown>;
      return {
        threadId: String(thread.threadId ?? thread.id ?? ""),
        title: typeof thread.title === "string" ? thread.title : undefined,
        cwd: typeof thread.cwd === "string" ? thread.cwd : undefined,
        updatedAt: typeof thread.updatedAt === "string" ? thread.updatedAt : undefined,
        summary: typeof thread.summary === "string" ? thread.summary : undefined
      };
    }).filter((item) => item.threadId.length > 0);
  }

  async ensureMainThread(registry: Registry): Promise<string> {
    const existing = registry.getMainThread();
    if (existing) return existing.threadId;
    const threadId = await this.startThread({ cwd: this.config.codex.defaultCwd, title: this.config.codex.dispatcherThreadTitle });
    registry.setMainThread({ threadId, cwd: this.config.codex.defaultCwd, title: this.config.codex.dispatcherThreadTitle });
    await registry.save();
    return threadId;
  }

  async startThread(input: { cwd: string; title?: string }): Promise<string> {
    const result = await this.client.request<unknown>("thread/start", input);
    const record = result as Record<string, unknown>;
    return String(record.threadId ?? record.id);
  }

  async resumeThread(input: { threadId: string; cwd?: string }): Promise<void> {
    await this.client.request("thread/resume", input);
  }

  async startTurn(input: { threadId: string; cwd?: string; prompt: string }): Promise<{ turnId: string }> {
    const base = {
      threadId: input.threadId,
      input: [{ type: "text", text: input.prompt }],
      model: this.config.codex.model,
      cwd: input.cwd,
      approvalPolicy: this.config.codex.approvalPolicy,
      sandbox: this.config.codex.sandbox
    };
    const attempts = [base, { ...base, sandbox: undefined }, { threadId: input.threadId, input: base.input }];
    let lastError: unknown;
    for (const params of attempts) {
      try {
        const result = await this.client.request<unknown>("turn/start", params);
        const record = result as Record<string, unknown>;
        return { turnId: String(record.turnId ?? record.id ?? "") };
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError instanceof Error ? lastError : new Error(String(lastError));
  }

  async waitForTurnCompleted(input: { threadId: string; timeoutMs?: number }): Promise<{ finalText: string; raw: unknown }> {
    const deadline = Date.now() + (input.timeoutMs ?? 300_000);
    while (Date.now() < deadline) {
      const completed = this.completed.get(input.threadId);
      if (completed) {
        this.completed.delete(input.threadId);
        return completed;
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    throw new Error(`timeout waiting for thread ${input.threadId}`);
  }

  private handleNotification(msg: JsonRpcNotification): void {
    if (!/turn.*(complete|completed|finish|finished)/i.test(msg.method)) return;
    const params = (msg.params ?? {}) as Record<string, unknown>;
    const threadId = String(params.threadId ?? params.thread_id ?? "");
    if (!threadId) return;
    const finalText = String(params.finalText ?? params.text ?? params.message ?? params.output ?? "");
    this.completed.set(threadId, { finalText, raw: msg });
  }
}
