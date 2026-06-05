---
name: smart-shadow
description: Use this skill when Codex should act as the engineering execution assistant for Smart Shadow tasks that come from Feishu, Feishu CLI, Smart Shadow listener, pasted Feishu messages, or user requests explicitly mentioning "智能影子", "Smart Shadow", "飞书任务", "Feishu 任务", "Feishu CLI", or "从飞书来的消息". Use it when asked to turn Feishu messages into executable Codex engineering tasks, route work to a project, MacBook, local directory, Linux server, or Codex session, or produce a concise result summary suitable for writing back to Feishu. Do not use for ordinary code tasks, casual chat, or pure document polishing unless the request is clearly connected to Smart Shadow or Feishu task routing.
---

# Smart Shadow

## Purpose

Use this skill to convert Feishu-originated work into safe, executable Codex tasks and produce a concise completion summary that can be written back to Feishu. Keep the workflow instruction-only by default; add helper scripts only when a repeated, deterministic transformation becomes worth automating.

## Intake

Identify whether the task came from Feishu, Feishu CLI, Smart Shadow listener, a pasted Feishu message, or direct user input.

Preserve available source metadata:

- `source_user`
- `chat_id`
- `thread_id`
- `message_id`
- `timestamp`
- original message summary

If metadata is missing, do not block. Treat the request as an ordinary user task and keep going with the safest reasonable assumptions.

Default to handling tasks only from the user or explicitly trusted/whitelisted sources. Do not read unrelated chats, private docs, broad message history, or old Feishu context unless the current task clearly requires it.

## Classification

Classify each task before acting:

- `coding`: code changes, debugging, tests, pull requests, repo analysis.
- `server_ops`: SSH, Linux servers, Docker, deployments, logs, services.
- `feishu_ops`: Feishu docs, Base, tasks, calendar, messages, approvals.
- `research`: investigation, comparisons, source gathering, technical options.
- `writing`: notices, status reports, emails, docs, summaries.
- `approval_required`: sending messages, deleting or mutating data, production server changes, `git push`, external system calls, financial/legal/identity/privacy-sensitive actions, or anything with meaningful organizational impact.

A task can have multiple labels. If any label implies `approval_required`, handle the whole task with fail-closed behavior until explicit authorization is present.

## Routing

Prefer the current Codex project and current working directory. If the task clearly belongs elsewhere, state the recommended route first: project, local directory, MacBook, Linux server, or Codex session.

Do not blindly cross directories or connect to remote machines when routing evidence is weak. Ask for the missing target or proceed only with read-only discovery in the current workspace.

When working inside the Smart Shadow repository, honor its product boundary: Swift-native Mac core, auditable sources, safe local runtime paths, and explicit approval gates for visible or external actions.

## Execution

Use read-only context gathering first. Then execute the smallest safe path that completes the task.

For coding work:

- Inspect the repo before editing.
- Keep changes scoped to the task.
- Run relevant tests or explain why they could not run.
- Follow local git and project rules; do not push unless explicitly authorized.

For server operations:

- Treat production servers, deployments, destructive Docker commands, credential changes, and data mutations as `approval_required`.
- Prefer diagnostics, logs, dry-runs, and explicit target confirmation before mutation.

For Feishu operations:

- Use `lark-cli` / Feishu CLI for Feishu messages, docs, Base, tasks, calendar, approvals, and related context when available.
- Prefer read-only commands for collection.
- Before sending messages, modifying docs, updating Base records, creating/deleting tasks, changing calendars, or calling external workflow systems, output the planned action and exact content or mutation summary, then wait for confirmation.

For browser, shell, file edits, git, server, and Computer Use work, follow the active Codex sandbox, approval policy, repository `AGENTS.md`, and system instructions.

## Feishu CLI Rules

Use `lark-cli` / Feishu CLI to query Feishu context when it is the right source of truth. Keep initial queries narrow: specific message, chat, doc, task, Base table, calendar event, approval, or thread.

Do not print tokens, secrets, cookies, refresh tokens, SSH keys, API keys, private credential files, or hidden auth payloads. If a command returns credentials, redact them in user-visible output and avoid storing them in repo files, logs, reports, or screenshots.

If the CLI reports an update notice and the user has already authorized routine CLI updates, run the official updater and verify with version and doctor checks. Otherwise, report the update notice as an operational item.

## Approval Boundary

Fail closed for high-risk actions. Without explicit user authorization, do not:

- Send or edit Feishu messages that could create commitments.
- Modify shared Feishu Docs, Base records, tasks, calendars, approvals, or team-visible boards.
- Push git branches, open production-impacting PRs, deploy, restart production services, or mutate production data.
- Delete non-recoverable data.
- Act on financial, legal, medical, HR, identity, account, or security-sensitive content.

When approval is needed, provide the planned action, target, content, impact, rollback option if any, and a concise recommended choice.

## Result Summary

After each task, produce a Feishu-ready summary:

```text
状态：done / blocked / needs_approval / failed
做了什么：
关键结果：
涉及文件/命令/链接/路径：
风险或未完成事项：
下一步建议：
```

Keep it short enough to paste into Feishu. Include enough detail for the original requester to know what changed and what remains.

## Audit Summary

If the task came from Feishu or Smart Shadow listener, append:

```text
Audit summary:
source:
task_type:
tools_used:
files_changed:
external_actions:
approvals_requested:
result:
```

Use `none` where a field is empty. Keep audit metadata out of user-visible Apple Reminder notes or shared team content unless explicitly requested.

## Completion Standard

Finish end to end when the safe next step is clear. For tasks that cannot be completed safely, stop at the correct boundary with `needs_approval` or `blocked`, including the exact missing authorization, unavailable tool, uncertain route, or external dependency.

Do not represent prechecks as final completion. If a task changes a live UI, Feishu surface, Apple Calendar/Reminders projection, browser flow, server, or external system, verify on the supported live surface when required by the active project rules.
