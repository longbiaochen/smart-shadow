import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import type { KnownProject, MainThread, RegistryData, ThreadBinding } from "./types.js";

const defaultData = (): RegistryData => ({
  version: 1,
  mainThread: { threadId: "", cwd: "", title: "smart-shadow-main" },
  projects: [
    { key: "smart-shadow", name: "智能影子", cwd: ".", aliases: ["智能影子", "Smart Shadow", "smartshadow"] }
  ],
  bindings: {},
  processedMessages: {}
});

export class Registry {
  private data: RegistryData = defaultData();

  constructor(private readonly filePath: string) {}

  async load(): Promise<RegistryData> {
    if (this.filePath === ":memory:") {
      this.data = defaultData();
      return this.data;
    }
    try {
      const raw = await readFile(this.filePath, "utf8");
      this.data = { ...defaultData(), ...JSON.parse(raw) };
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== "ENOENT") throw error;
      this.data = defaultData();
      await this.save();
    }
    return this.data;
  }

  async save(): Promise<void> {
    if (this.filePath === ":memory:") return;
    await mkdir(path.dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, `${JSON.stringify(this.data, null, 2)}\n`, "utf8");
  }

  getMainThread(): MainThread | undefined {
    return this.data.mainThread.threadId ? this.data.mainThread : undefined;
  }

  setMainThread(thread: MainThread): void {
    this.data.mainThread = thread;
  }

  getProjects(): KnownProject[] {
    return this.data.projects;
  }

  upsertProject(project: KnownProject): void {
    const index = this.data.projects.findIndex((item) => item.key === project.key);
    if (index >= 0) this.data.projects[index] = project;
    else this.data.projects.push(project);
  }

  getBinding(key: string): ThreadBinding | undefined {
    return this.data.bindings[key];
  }

  setBinding(key: string, binding: ThreadBinding): void {
    this.data.bindings[key] = binding;
  }

  hasProcessed(messageId: string): boolean {
    return Boolean(this.data.processedMessages[messageId]);
  }

  markProcessed(messageId: string, status: string): void {
    this.data.processedMessages[messageId] = { processedAt: new Date().toISOString(), status };
  }
}
