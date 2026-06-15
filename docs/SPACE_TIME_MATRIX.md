# ShadowD / Codex Operating Matrix

ShadowD supports an operating matrix for the user's life lines. It should not
grow into a generic dashboard for every app, source, or data type. The new model
has three primary handles:

- **Entry layer** captures user intent from phone and computer surfaces: visible
  AI shadow controls, star/favorite/share/mark operations, Mac menu-bar operations,
  global hotkey voice, and the QR-bound phone lightweight app. Voice interaction
  ultimately routes back to `shadowd` on the Mac.
- **shadowd** is the Mac system service and bridge for sensing, context
  preparation, Codex connection, bridge dispatch, tracking, audit, recovery,
  origin-channel mapping, and feedback.
- **Codex** is the decision brain for user intent, reasoning, prioritization,
  task decomposition, execution planning, corresponding Project-thread
  creation/resume, local software use, tool choice, review, explanation, and
  routing across life lines, Projects, and Issues.

The managed hierarchy is:

```text
Life line -> Project -> Issue
```

Life lines, Projects, and Issues are interpreted by Codex under Smart Shadow
rules. `shadowd` then uses Reminders, Calendar, Finder, Contacts, Notes, Photos,
Music, GitHub, Feishu, Mail, WeChat, and other software surfaces for responses,
context, collaboration, and feedback when the Project semantics call for them.

ShadowD is not a competing AI brain. It is the runtime bridge around Codex that
keeps identity mappings, native app responses, service lifecycle, auditability,
and cross-session continuity.

## Interface Model

The main interface is a three-loop flow:

```text
entry layer event / voice -> ShadowD on Mac -> Codex Project thread -> local software response -> ShadowD origin-channel feedback -> user
```

- **Entry layer**
  - The phone lightweight app can be invoked after QR-code binding.
  - Mac menu bar and global hotkey voice are first-class local entry points.
  - App-level AI shadow controls, star, favorite, share, and mark operations are
    explicit user intent operations.
  - Mac apps can also expose bounded implicit intent through user operation,
    polling, or monitoring.

- **ShadowD system service**
  - ShadowD senses intent, preserves source context, deduplicates signals,
    connects to Codex, dispatches approved responses, tracks status, and creates
    feedback on the platform channel where the user posted the task by default.

- **Codex decision brain**
  - Codex handles intent, triage, Project / Issue structure, priority, risk,
    decomposition, planning, corresponding Project-thread creation/resume, local
    software use, review, target-surface choice, and explanation.

- **Software surfaces**
  - Reminders, Calendar, Finder, Contacts, Notes, Photos, Music, Feishu, GitHub,
    Mail, WeChat, and other local or external apps.
  - Reminders carries responses, reminders, review cards, blockers, and follow-up
    tasks.
  - Calendar carries meetings, time blocks, deadlines, milestones, and rhythm.
  - Work-related tasks default to Feishu task boards through Feishu CLI.
  - Personal and life-related tasks default to the corresponding Apple
    Reminders boards or lists.
  - GitHub is reserved for code, PR, Issue, CI, open-source feedback, and
    repo-centered execution.

## Data Flow

1. The user interacts through the phone or computer.
2. ShadowD receives explicit intent or records a bounded implicit candidate.
3. Codex determines the life line, Project, Issue, risk, priority, execution
   path, review need, and target software.
4. Codex creates or resumes the corresponding Project thread and uses local
   software or an agent to move the work forward.
5. ShadowD creates user feedback, defaulting to the platform channel where the
   user posted the task.
6. Responses, time blocks, documents, media, contacts, knowledge, collaboration
   records, and status feedback remain linked to the same Project / Issue.

## Product Rules

- Codex is the decision brain for life lines, Projects, and Issues.
- ShadowD is the system service for entry routing, sensing, connection,
  continuity, feedback, and auditability around Codex.
- Reminders, Calendar, Finder, Contacts, Notes, Photos, Music, GitHub, Feishu,
  Mail, WeChat, and other systems are not forced into one project-management
  body. Current defaults are Feishu task boards for work and Apple Reminders
  boards/lists for life-related responses.
- External and local systems can be intent surfaces, response tools,
  collaboration surfaces, feedback surfaces, or durable memory depending on the
  Project.
- ShadowD owns mapping, sync, repair, native app responses, service continuity,
  and auditability around Codex.
- Every cross-surface projection must preserve a stable Project / Issue identity
  and explicit mapping.
