import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";
import type { Config } from "../config.js";

export interface JsonRpcRequest {
  id: string | number;
  method: string;
  params?: unknown;
}

export interface JsonRpcNotification {
  method: string;
  params?: unknown;
}

type Pending = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export class CodexAppServerClient {
  private child?: ChildProcessWithoutNullStreams;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private notificationHandlers: Array<(msg: JsonRpcNotification) => void> = [];
  private requestHandlers: Array<(msg: JsonRpcRequest) => Promise<unknown>> = [];

  constructor(private readonly config: Config) {}

  async start(): Promise<void> {
    if (this.child) return;
    this.child = spawn(this.config.codex.appServer.command, this.config.codex.appServer.args, {
      stdio: ["pipe", "pipe", "pipe"]
    });
    createInterface({ input: this.child.stdout }).on("line", (line) => this.handleLine(line));
    createInterface({ input: this.child.stderr }).on("line", (line) => process.stderr.write(`[codex-appserver] ${line}\n`));
    this.child.once("exit", (code, signal) => {
      const error = new Error(`codex app-server exited code=${code ?? ""} signal=${signal ?? ""}`);
      for (const pending of this.pending.values()) pending.reject(error);
      this.pending.clear();
      this.child = undefined;
    });
    await this.request("initialize", {
      clientInfo: { name: "smart_shadow", title: "Smart Shadow Feishu Bridge", version: "0.1.0" },
      capabilities: { experimentalApi: true }
    });
    this.notify("initialized", {});
  }

  async stop(): Promise<void> {
    if (!this.child) return;
    const child = this.child;
    child.kill("SIGTERM");
    await new Promise<void>((resolve) => child.once("exit", () => resolve()));
  }

  async request<T>(method: string, params?: unknown): Promise<T> {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await this.sendRequest<T>(method, params);
      } catch (error) {
        if (!String((error as Error).message).toLowerCase().includes("overloaded") || attempt === 2) throw error;
        await sleep(250 * 2 ** attempt);
      }
    }
    throw new Error("unreachable");
  }

  notify(method: string, params?: unknown): void {
    this.write({ method, params });
  }

  onNotification(handler: (msg: JsonRpcNotification) => void): void {
    this.notificationHandlers.push(handler);
  }

  onServerRequest(handler: (msg: JsonRpcRequest) => Promise<unknown>): void {
    this.requestHandlers.push(handler);
  }

  private sendRequest<T>(method: string, params?: unknown): Promise<T> {
    const id = this.nextId++;
    this.write({ id, method, params });
    return new Promise((resolve, reject) => this.pending.set(id, { resolve: resolve as (value: unknown) => void, reject }));
  }

  private write(message: unknown): void {
    if (!this.child) throw new Error("codex app-server is not started");
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private async handleLine(line: string): Promise<void> {
    if (!line.trim()) return;
    const msg = JSON.parse(line) as Record<string, unknown>;
    if ("id" in msg && ("result" in msg || "error" in msg)) {
      const id = Number(msg.id);
      const pending = this.pending.get(id);
      if (!pending) return;
      this.pending.delete(id);
      if (msg.error) pending.reject(new Error(JSON.stringify(msg.error)));
      else pending.resolve(msg.result);
      return;
    }
    if ("id" in msg && typeof msg.method === "string") {
      const request = msg as unknown as JsonRpcRequest;
      for (const handler of this.requestHandlers) {
        await handler(request);
      }
      this.write({ id: request.id, error: { code: -32601, message: "server requests are not supported by smart-shadowd MVP" } });
      return;
    }
    if (typeof msg.method === "string") {
      for (const handler of this.notificationHandlers) handler(msg as unknown as JsonRpcNotification);
    }
  }
}
