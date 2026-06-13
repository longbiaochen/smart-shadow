# shadowd State Model

`shadowd` is a GitHub Project reconciler. It does not own a task database and
does not decide from local task rows. The durable workflow state is:

- Life OS GitHub Project membership.
- Project fields such as `Status` and custom status fields.
- Issue title, body, labels, comments, and linked PRs.
- PR state and CI/review state when a PR exists.

Local files are operational evidence only: logs, audit JSONL, dry-run reports,
and temporary caches. They must not become the source of truth for the next
workflow step.

## Scope Boundary

The queue boundary is the whole Life OS GitHub Project. `shadowd` must inspect
Project items even when they do not have `smartshadow` or `SmartShadow` labels.

Labels may still help classify an issue:

- `smartshadow` or equivalent source labels: issue was created from Smart
  Shadow after local user confirmation.
- `ready` or `ss/state:ready-for-execution`: issue text is ready for execution.
- `blocked`, `waiting-user`, or similar labels: external review is needed.

Labels are hints, not the intake filter.

## Issue Classes

### Smart Shadow Text Issue

A Smart Shadow issue is created by the iOS/macOS front end after local audio
capture, local ChatType transcription, local polish, and user confirmation. It
contains the final text task plus compact source metadata. It does not contain
raw audio, an audio upload path, a temporary recording repository reference, or a
raw transcript dump.

Rendered issue body order:

1. Final task description first.
2. No raw audio reference or raw transcript section.
3. Compact metadata in a folded or otherwise low-noise block.

`shadowd` treats this issue as user intent ready for execution. If it still has
legacy `audio_path` or raw transcript formatting, `shadowd` plans a clarification
comment asking for the final text task instead of running ASR.

### Ordinary Project Issue

An ordinary issue has no voice metadata. `shadowd` never sends it through ASR.
It derives next steps from GitHub state:

- If custom status is `完成` but Project `Status` is not done, plan Project
  Status alignment.
- If required task-template sections are missing, append a clarification
  question instead of starting work.
- If Project state and issue content are consistent, no-op.

## Required Task Template

New work issues should use:

```markdown
## Background

说明为什么要做这个任务。

## Goal

说明希望最终实现什么。

## Scope

### In scope

-

### Out of scope

-

## Acceptance Criteria

- [ ]
- [ ]
- [ ]

## Constraints

- 技术约束：
- 兼容性约束：
- 安全约束：
- 时间约束：

## Suggested Starting Points

- 相关文件：
- 相关模块：
- 相关命令：
- 相关文档：

## Agent Instructions

- 先阅读相关代码再制定计划。
- 如果需求不清楚，先在 issue 中追加问题，不要直接大改。
- 如果需要修改代码，创建 branch 和 Draft PR。
- 阶段性进展追加到本 issue。
- 完成后在 PR 和 issue 中分别给出 summary。
```

## Idempotency

`shadowd` avoids duplicate work by comparing the desired transition with the
current GitHub state. It should not write a comment or status update when the
issue is already in the intended state.
