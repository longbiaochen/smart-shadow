import type { Config } from "../config.js";
import type { ShadowMessage } from "../shadow/types.js";

function equalsIgnoreCase(left: string | undefined, right: string | undefined): boolean {
  return Boolean(left && right && left.toLowerCase() === right.toLowerCase());
}

function configuredRepositories(config: Config): string[] {
  return Array.from(new Set([...config.github.repositories, ...Object.keys(config.github.repos)]));
}

function assignedLogin(msg: ShadowMessage): string | undefined {
  const raw = msg.raw as { assignee?: { login?: unknown } };
  return typeof raw.assignee?.login === "string" ? raw.assignee.login : undefined;
}

export function shouldRouteGitHubMessage(msg: ShadowMessage, config: Config): { allowed: boolean; reason?: string } {
  if (!config.github.enabled) return { allowed: false, reason: "github_disabled" };
  if (!msg.github) return { allowed: false, reason: "missing_github_metadata" };
  if (!configuredRepositories(config).includes(msg.github.repository)) return { allowed: false, reason: "repository_not_allowed" };
  if (!config.github.events.includes(msg.github.eventName)) return { allowed: false, reason: "event_not_allowed" };
  if (msg.github.itemType !== "issue") return { allowed: false, reason: "github_item_not_issue" };

  const repoConfig = config.github.repos[msg.github.repository];
  if (!repoConfig) return { allowed: false, reason: "repository_mapping_missing" };
  if (repoConfig.allowedSenders.length > 0 && !repoConfig.allowedSenders.includes(msg.sender.id)) {
    return { allowed: false, reason: "sender_not_allowed" };
  }

  if (msg.github.eventName === "issues" && msg.github.action === "assigned") {
    const assignee = assignedLogin(msg) ?? msg.github.assignees.at(-1);
    return equalsIgnoreCase(assignee, config.github.assignee)
      ? { allowed: true }
      : { allowed: false, reason: "assignee_not_shadow" };
  }

  if (msg.github.eventName === "issue_comment" && msg.github.action === "created") {
    if (!msg.github.command) return { allowed: false, reason: "comment_command_not_matched" };
    if (!config.github.allowedCommentCommands.includes(msg.github.command)) return { allowed: false, reason: "comment_command_not_allowed" };
    return { allowed: true };
  }

  return { allowed: false, reason: "trigger_not_matched" };
}
