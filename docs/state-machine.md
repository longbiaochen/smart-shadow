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

- `voice`: voice issue.
- `ready` or `ss/state:ready-for-execution`: voice transcription already
  produced the final task description.
- `blocked`, `waiting-user`, or similar labels: external review is needed.

Labels are hints, not the intake filter.

## Issue Classes

### Voice Issue

A voice issue is identified by compact Smart Shadow metadata in the issue body,
an `audio_path` field, or a `voice` label.

Rendered issue body order:

1. Final task description first.
2. No raw transcript section.
3. Compact metadata in a folded or otherwise low-noise block.

If a voice issue is already ready, `shadowd` no-ops. If it still has legacy raw
transcript formatting, `shadowd` plans a body cleanup or clarification comment.

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
