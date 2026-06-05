import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";

export interface FeishuEventListenerOptions {
  cliBin: string;
  eventKey: string;
  identity: "bot" | "user" | "auto";
  maxEvents?: number;
  timeoutMs?: number;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export class FeishuEventListener {
  private child?: ChildProcessWithoutNullStreams;
  private stopped = false;

  constructor(private readonly options: FeishuEventListenerOptions) {}

  async start(onEvent: (event: unknown) => Promise<void>): Promise<void> {
    this.stopped = false;
    let restartDelay = 500;
    while (!this.stopped) {
      const code = await this.runOnce(onEvent);
      if (this.stopped || this.options.maxEvents) break;
      process.stderr.write(`[smart-shadowd] lark-cli exited code=${code}; restarting in ${restartDelay}ms\n`);
      await sleep(restartDelay);
      restartDelay = Math.min(restartDelay * 2, 30_000);
    }
  }

  async stop(): Promise<void> {
    this.stopped = true;
    if (!this.child) return;
    const child = this.child;
    child.kill("SIGTERM");
    await new Promise<void>((resolve) => child.once("exit", () => resolve()));
  }

  private async runOnce(onEvent: (event: unknown) => Promise<void>): Promise<number | null> {
    const args = ["event", "consume", this.options.eventKey, "--as", this.options.identity];
    this.child = spawn(this.options.cliBin, args, { stdio: ["pipe", "pipe", "pipe"] });
    this.child.stdin.write("\n");
    let seen = 0;
    const deadline = this.options.timeoutMs ? setTimeout(() => void this.stop(), this.options.timeoutMs) : undefined;

    createInterface({ input: this.child.stderr }).on("line", (line) => {
      process.stderr.write(`[lark-cli] ${line}\n`);
      if (line.includes(`[event] ready event_key=${this.options.eventKey}`)) {
        process.stderr.write(`[smart-shadowd] Feishu listener ready for ${this.options.eventKey}\n`);
      }
    });

    createInterface({ input: this.child.stdout }).on("line", async (line) => {
      if (!line.trim()) return;
      try {
        await onEvent(JSON.parse(line));
        seen++;
        if (this.options.maxEvents && seen >= this.options.maxEvents) await this.stop();
      } catch (error) {
        process.stderr.write(`[smart-shadowd] failed to process event: ${(error as Error).message}\n`);
      }
    });

    return await new Promise((resolve) => {
      this.child?.once("exit", (code) => {
        if (deadline) clearTimeout(deadline);
        this.child = undefined;
        resolve(code);
      });
    });
  }
}
