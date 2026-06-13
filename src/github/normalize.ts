import type { ShadowMessage } from "../shadow/types.js";

type GitHubPayload = Record<string, any>;

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

function labelNames(item: { labels?: unknown }): string[] {
  return Array.isArray(item.labels)
    ? item.labels.map((label) => typeof label?.name === "string" ? label.name : undefined).filter((name): name is string => Boolean(name))
    : [];
}

function assigneeNames(item: { assignees?: unknown; assignee?: unknown }): string[] {
  const names = Array.isArray(item.assignees)
    ? item.assignees.map((assignee) => typeof assignee?.login === "string" ? assignee.login : undefined).filter((name): name is string => Boolean(name))
    : [];
  const single = typeof (item.assignee as { login?: unknown } | undefined)?.login === "string"
    ? String((item.assignee as { login: string }).login)
    : undefined;
  return Array.from(new Set([...names, ...(single ? [single] : [])]));
}

function commandFromComment(body?: string): string | undefined {
  const firstLine = (body ?? "").trimStart().split(/\r?\n/, 1)[0]?.trim() ?? "";
  const match = firstLine.match(/^@shadow(?:\s+(fix|continue|test|explain))?(?:\s|$)/i);
  if (!match) return undefined;
  return match[1] ? `@shadow ${match[1].toLowerCase()}` : "@shadow";
}

function triggerFor(eventName: string, action: string, payload: GitHubPayload, command?: string): "assigned" | "comment" | undefined {
  if (eventName === "issues" && action === "assigned") return "assigned";
  if (eventName === "issue_comment" && action === "created" && command) return "comment";
  return undefined;
}

function isPullLikeIssue(issue: GitHubPayload): boolean {
  return Boolean(issue.pull_request);
}

function issueOrPull(payload: GitHubPayload): { item: GitHubPayload; itemType: "issue" | "pull"; number?: number; title: string; url?: string; labels: string[] } {
  const explicitPull = payload.pull_request;
  if (explicitPull) {
    return {
      item: explicitPull,
      itemType: "pull",
      number: numberValue(explicitPull.number),
      title: stringValue(explicitPull.title, "(untitled pull request)"),
      url: stringValue(explicitPull.html_url) || undefined,
      labels: labelNames(explicitPull)
    };
  }

  const issue = payload.issue ?? {};
  const itemType = isPullLikeIssue(issue) ? "pull" : "issue";
  return {
    item: issue,
    itemType,
    number: numberValue(issue.number),
    title: stringValue(issue.title, itemType === "pull" ? "(untitled pull request)" : "(untitled issue)"),
    url: stringValue(issue.html_url) || undefined,
    labels: labelNames(issue)
  };
}

function messageIdFor(eventName: string, action: string, payload: GitHubPayload, itemType: "issue" | "pull" | "workflow", number?: number): string {
  const commentId = numberValue(payload.comment?.id);
  if (commentId) return `github:comment:${commentId}`;
  const reviewId = numberValue(payload.review?.id);
  if (reviewId) return `github:review:${reviewId}`;
  const runId = numberValue(payload.workflow_run?.id);
  if (runId) return `github:workflow_run:${runId}:${stringValue(payload.workflow_run?.status, action)}:${stringValue(payload.workflow_run?.conclusion)}`;
  const jobId = numberValue(payload.workflow_job?.id);
  if (jobId) return `github:workflow_job:${jobId}:${stringValue(payload.workflow_job?.status, action)}:${stringValue(payload.workflow_job?.conclusion)}`;
  return `github:${itemType}:${number ?? "unknown"}:${action || eventName}`;
}

function textFor(input: { title: string; body?: string; commentBody?: string; url?: string }): string {
  return [
    input.title,
    input.commentBody ?? input.body ?? "",
    input.url ?? ""
  ].filter(Boolean).join("\n\n").trim();
}

export function normalizeGitHubWebhook(input: { eventName: string; deliveryId: string; payload: GitHubPayload }): ShadowMessage {
  const { eventName, deliveryId, payload } = input;
  const repository = stringValue(payload.repository?.full_name, "unknown/unknown");
  const [owner = "unknown", repo = "unknown"] = repository.split("/");
  const action = stringValue(payload.action, "");
  const sender = stringValue(payload.sender?.login, "unknown");
  const receivedAt = stringValue(payload.comment?.created_at)
    || stringValue(payload.issue?.updated_at)
    || stringValue(payload.pull_request?.updated_at)
    || stringValue(payload.workflow_run?.updated_at)
    || stringValue(payload.workflow_job?.completed_at)
    || new Date().toISOString();

  let itemType: "issue" | "pull" | "workflow";
  let number: number | undefined;
  let title = eventName;
  let url: string | undefined;
  let labels: string[] = [];
  let assignees: string[] = [];
  let body = "";
  let commentBody: string | undefined;

  if (eventName === "workflow_run" || eventName === "workflow_job") {
    itemType = "workflow";
    const workflow = payload.workflow_run ?? payload.workflow_job ?? {};
    number = numberValue(workflow.id);
    title = stringValue(workflow.name, eventName);
    url = stringValue(workflow.html_url) || undefined;
    body = [stringValue(workflow.status), stringValue(workflow.conclusion)].filter(Boolean).join(" ");
  } else {
    const item = issueOrPull(payload);
    itemType = item.itemType;
    number = item.number;
    title = item.title;
    url = stringValue(payload.comment?.html_url) || item.url;
    labels = item.labels;
    assignees = assigneeNames(item.item);
    body = stringValue(item.item.body);
    commentBody = stringValue(payload.comment?.body) || stringValue(payload.review?.body) || undefined;
  }

  const threadId = itemType === "pull" ? `pull:${number ?? "unknown"}` : itemType === "issue" ? `issue:${number ?? "unknown"}` : `workflow:${number ?? "unknown"}`;
  const conversationKey = `github:${repository}:${threadId}`;
  const messageId = messageIdFor(eventName, action, payload, itemType, number);
  const command = commandFromComment(commentBody);
  const trigger = triggerFor(eventName, action, payload, command);

  return {
    id: `github:${deliveryId}`,
    source: "github",
    eventKey: `${eventName}:${action}`,
    receivedAt,
    sender: { id: sender, name: sender },
    chat: { id: repository, type: "unknown", name: repository },
    thread: { id: threadId, rootId: threadId },
    message: {
      id: messageId,
      type: "text",
      text: textFor({ title, body, commentBody, url }),
      raw: payload.comment ?? payload.review ?? payload.issue ?? payload.pull_request ?? payload.workflow_run ?? payload.workflow_job ?? payload
    },
    github: {
      repository,
      owner,
      repo,
      eventName,
      action,
      deliveryId,
      conversationKey,
      itemType,
      number,
      url,
      issueTitle: title,
      issueBody: body,
      commentBody,
      command,
      trigger,
      labels,
      assignees
    },
    raw: payload
  };
}
