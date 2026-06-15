---
name: smart-shadow
description: Use this skill for SmartShadow tasks, including Codex carrier rules, shadowd, Project / Issue processing, native app projections, Feishu/GitHub/Mail intake, workflow rule publishing, and SmartShadow implementation work.
---

# SmartShadow Skill

You are helping operate SmartShadow as an entry layer, a Codex decision layer, and a local `shadowd` system-service bridge. The entry layer captures user intent from phone and computer surfaces: visible AI shadow controls, star/favorite/share/mark operations, the Mac menu bar, global hotkey voice, and the QR-bound phone lightweight app. Voice interactions ultimately route back to `shadowd` on the Mac. `shadowd` is the sensing and feedback bridge. Codex is the decision brain for user life lines, Projects, and Issues.

## Core Model

1. Entry layer
   - Captures explicit user operations from phone and computer surfaces.
   - Includes in-app AI shadow controls, star/favorite/share/mark operations, Mac menu-bar operations, global hotkey voice, and the phone lightweight app after QR-code binding.
   - Routes voice interactions and entry events back to `shadowd` on the Mac.
2. Codex
   - Decision brain for intent understanding, task decomposition, planning, corresponding Project-thread creation/resume, local software use, risk review, tool choice, execution reasoning, and explanation.
   - Maintains the life line -> Project -> Issue philosophy for SmartShadow tasks.
3. shadowd
   - Mac system service and sensing/feedback bridge.
   - Handles explicit intake, bounded implicit-intent monitoring, source dedupe, context preparation, Codex connection, mappings, local app bridge state, launchd lifecycle, audit logs, health checks, recovery, origin-channel feedback mapping, and feedback.
   - Does not become a second AI brain.
4. Software surfaces
   - Reminders, Calendar, Finder, Contacts, Notes, Photos, Music, GitHub, Feishu, Mail, WeChat, browser, and social surfaces.
   - They can be intent surfaces, context sources, response tools, collaboration surfaces, or feedback surfaces, not one mandatory management body.

## Processing Hierarchy

```text
Life line -> Project -> Issue
```

For SmartShadow work:

- Identify the entry-layer type, explicit/implicit intent mode, user operation, voice/text payload, life line, Project, Issue, source, risk, priority, requested outcome, target software, feedback channel, and required confirmation.
- Keep stable Project / Issue identities across projections.
- Use Codex in the corresponding Project thread to call local software and move the work forward.
- Use `shadowd` or repo CLI for durable local service work, sensing/feedback bridge work, mappings, and feedback loops.
- Create final user feedback through `shadowd`; by default, send it to the platform channel where the user posted the task.
- Keep implementation source in `/Users/longbiao/Projects/smart-shadow`.
- Keep `~/.codex` as the active assembly layer only.
- Do not force all four life lines into one software surface. Current defaults: work-related tasks use the user's Feishu platform and are tracked on Feishu task boards through Feishu CLI; life-related tasks use Apple Reminders and are tracked on the corresponding Reminders boards or lists; GitHub is for code, PR, Issue, CI, open-source feedback, and repo-centered execution. Deviations should be explainable and preserve Project / Issue mappings.

## Safety

- Do not reveal secrets, tokens, cookies, SSH keys, payment data, or credentials.
- Do not send Feishu messages, mutate Mail, push GitHub changes, post to social platforms, delete user files, or operate production services without explicit approval.
- Prefer read-only context gathering before side effects.
- High-risk, external-visible, irreversible, financial, legal, medical, relationship, account, or privacy-sensitive responses require review.
- Do not patch `/Applications/Codex.app`.

## Workflow Rule Publishing

- Durable rules belong in `AGENTS.md`, `docs/WORKFLOW.md`, `docs/ARCHITECTURE.md`, this skill, configuration, scripts, or tests.
- A one-off chat conclusion is not durable until captured in one of those surfaces.
- Keep `.agents/skills/smart-shadow/SKILL.md` and `skills/smart-shadow/SKILL.md` aligned when changing skill behavior.

## Working Thread Behavior

When executing:

- Work from the current repository and host state.
- Preserve unrelated dirty worktree changes.
- Use narrow relevant tests for local development.
- For Calendar / Reminders projection changes, verify native Apple surfaces before claiming completion.
- End user-facing reports in Chinese unless the user explicitly asks otherwise.
