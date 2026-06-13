import type { Config } from "../config.js";
import type { ShadowMessage } from "../shadow/types.js";

export interface GitHubIssueTask {
  source: "github";
  agentName: string;
  daemonName: string;
  trigger: "assigned" | "comment";
  owner: string;
  repo: string;
  repoFullName: string;
  issueNumber: number;
  issueTitle: string;
  issueBody: string;
  issueUrl: string;
  sender: string;
  command?: string;
  labels: string[];
  assignees: string[];
}

export function toGitHubIssueTask(msg: ShadowMessage, config: Config): GitHubIssueTask {
  if (!msg.github || msg.github.itemType !== "issue" || !msg.github.number) {
    throw new Error("GitHub message is not an actionable issue task.");
  }
  if (!msg.github.trigger) {
    throw new Error("GitHub issue task is missing a supported shadow trigger.");
  }
  return {
    source: "github",
    agentName: config.github.agentName,
    daemonName: config.github.daemonName,
    trigger: msg.github.trigger,
    owner: msg.github.owner,
    repo: msg.github.repo,
    repoFullName: msg.github.repository,
    issueNumber: msg.github.number,
    issueTitle: msg.github.issueTitle ?? msg.message.text.split(/\r?\n/, 1)[0] ?? `Issue #${msg.github.number}`,
    issueBody: msg.github.issueBody ?? "",
    issueUrl: msg.github.url ?? `https://github.com/${msg.github.repository}/issues/${msg.github.number}`,
    sender: msg.sender.id,
    command: msg.github.command,
    labels: msg.github.labels,
    assignees: msg.github.assignees
  };
}
