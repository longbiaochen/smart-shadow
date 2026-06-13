import { execa } from "execa";

export type GitHubItemType = "issue" | "pull";

export function buildGitHubReplyArgs(input: { repository: string; itemType: GitHubItemType; number: number; body: string }): string[] {
  return ["api", "--method", "POST", `/repos/${input.repository}/issues/${input.number}/comments`, "-f", `body=${input.body}`];
}

export function buildGitHubLabelArgs(input: { repository: string; number: number; labels: string[] }): string[] {
  return ["api", "--method", "POST", `/repos/${input.repository}/issues/${input.number}/labels`, ...input.labels.flatMap((label) => ["-f", `labels[]=${label}`])];
}

export function buildGitHubAckComment(taskId: string): string {
  return [
    "Smart Shadow accepted this GitHub task and is routing it.",
    "",
    "```json",
    JSON.stringify({
      task_id: taskId,
      status: "doing",
      current_step: "Smart Shadow accepted this GitHub task and is routing it.",
      next_action: "Dispatch to Codex working thread.",
      handoff_to_chatgpt: false,
      deliverables_ready: false
    }, null, 2),
    "```"
  ].join("\n");
}

export function buildGitHubFinalComment(status: string, taskId: string, body: string): string {
  return [
    body.trim(),
    "",
    "```json",
    JSON.stringify({
      task_id: taskId,
      status,
      current_step: "Smart Shadow completed GitHub channel processing.",
      next_action: status === "ready_for_review" || status === "done" ? "Review the delivered result." : "Resolve the blocker described above.",
      handoff_to_chatgpt: true,
      deliverables_ready: status === "ready_for_review" || status === "done"
    }, null, 2),
    "```"
  ].join("\n");
}

export class GitHubReplier {
  constructor(private readonly options: { cliBin?: string; dryRunReply: boolean }) {}

  async comment(input: { repository: string; itemType: GitHubItemType; number: number; body: string }): Promise<void> {
    const args = buildGitHubReplyArgs(input);
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run github comment] ${args.join(" ")}\n${input.body}\n`);
      return;
    }
    await execa(this.options.cliBin ?? "gh", args, { stdin: "ignore" });
  }

  async addLabels(input: { repository: string; number: number; labels: string[] }): Promise<void> {
    const args = buildGitHubLabelArgs(input);
    if (this.options.dryRunReply) {
      process.stdout.write(`[dry-run github labels] ${args.join(" ")}\n`);
      return;
    }
    await execa(this.options.cliBin ?? "gh", args, { stdin: "ignore" });
  }
}
