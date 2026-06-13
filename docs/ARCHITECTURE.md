# Architecture

Smart Shadow is an iPhone-first personal task entry system with a local,
auditable execution backend. The MVP loop is:

1. The iPhone app captures a voice task through a single primary button.
2. The app keeps only a short-lived local audio cache, uses local ChatType
   runtime/polish capabilities for transcription and cleanup, and turns the
   final text into a structured task card.
3. The user confirms the task before it is submitted to `shadow`.
4. GitHub Issue / Comment / PR becomes the durable task record.
5. Local `shadowd` assigns the task to a Codex agent, records progress, and
   synchronizes status back to the app.

The current implementation is Swift-native across the iOS app and local Mac
service surfaces. The Mac side includes CLI commands, launchd lifecycle support,
GitHub issue handling, EventKit integration, SQLite state, audit logs, and report
generation.

The `life-os` workflow is the current GitHub-backed MVP coordination surface:
`shadowd` reconciles the Life OS GitHub Project and derives next actions from
GitHub Issue / Project / PR state. It does not maintain a separate authoritative
task database.

## Component Model

- `SmartShadowIOS` is the primary product surface. It owns voice capture, transcript display, task-card confirmation, task status display, follow-up capture, and push-notification landing.
- `shadow` is the unified agent identity shown to the user. The user should not need to pick among local Codex agents.
- GitHub Issue is the task master record for development work and other tracked work. Issue comments carry meaningful progress updates, blockers, user follow-up, PR links, and completion summaries.
- The user GitHub identity writes only the user's explicit intent: new task issues, follow-up comments, and replies to Shadow questions after local confirmation.
- The Shadow GitHub App bot identity writes execution state: acknowledgements, plans, progress, labels/status updates, branches, commits, and PRs.
- Pull Requests are created only when code changes are ready for review. They are not used for routine progress logging.
- `shadowd` owns webhook intake, GitHub reconcile, repo/project mapping, Codex agent assignment, idempotency, progress comments, branch/commit/PR creation, and status synchronization.
- `shadowd` does not record audio, store audio, transcribe speech, polish user text, or write GitHub content as the user.
- ChatType Runtime/Polish is the local ASR and text-cleanup capability used by the iOS/macOS front end before GitHub submission.
- Existing sensing sources collect bounded local signals: JSON event files, file metadata, structured Lark calendar/task reads, Google Calendar/Tasks/Contacts reads, local command summaries, browser bookmark metadata, EventKit Reminders reads, and local mail-summary JSON.
- The rule registry in `config/rules.json` decides domain, priority, risk, review requirement, and default action for local assistant flows.
- The projection engine maps one canonical work item into Apple Reminders, Apple Calendar, or an explicitly requested low-risk Mail action. These surfaces support the broader local assistant, but they are not the MVP task master record.
- Reports summarize review items, background context, source coverage, GitHub task state, and recent rule feedback.

## MVP Data Flow

1. The user opens the iPhone app and records a task.
2. The app stores only a short-lived local audio cache, transcribes and polishes the text locally, recognizes intent, and builds a structured task card with title, type, project, background, target output, acceptance criteria, priority, PR need, and confirmation requirement.
3. The user confirms, edits, cancels, re-records, or adds a follow-up.
4. Confirmed tracked work creates or updates a GitHub Issue or Issue Comment with the user's GitHub identity. GitHub stores only the final text task and compact Smart Shadow metadata, never raw audio.
5. `shadowd` reads the GitHub task state, maps it to a local repo or management project, assigns a local Codex agent, and records local operational evidence.
6. `shadowd` and the assigned agent write meaningful progress as the Shadow bot identity. If code changes are ready for review, `shadowd` creates a linked PR.
7. The app refreshes task state from the GitHub-backed record and uses push notifications only for key state changes: need input, PR ready, done, failed, long blocked, or watched-task update.
8. The user confirms completion, requests changes, or adds a new follow-up.

## Local Assistant Data Flow

The repository still supports local assistant sensing and EventKit projection:

1. A source places or returns structured signals.
2. `run-once` or the daemon ingests the signal and records it in SQLite.
3. Rules classify the signal and choose an action.
4. High-value or high-risk personal items become review work through EventKit projections; mail enters this path only when Codex Automation submits an explicit decision.
5. Actions, decisions, and projection IDs are recorded for later explanation and dedupe.
6. Reports and audit logs provide operator-facing and technical evidence.

## GitHub Task Reconcile Flow

The backend loop uses GitHub as the durable coordination surface:

1. `bin/shadowd once` reads open issues from the Life OS GitHub Project.
2. Each issue is classified from issue body metadata, labels, Project fields,
   comments, and linked PRs.
3. Smart Shadow-created issues are treated as already-transcribed user intent.
   `shadowd` must not retrieve audio or run ASR from GitHub state.
4. Ordinary Project issues are reconciled from Project status, custom status,
   issue template completeness, comments, labels, and PR state.
5. If custom status is `完成` but Project `Status` is not done, `shadowd` plans
   Project Status alignment.
6. If required template sections are missing, `shadowd` plans a clarification
   comment instead of starting implementation.
7. If GitHub state already matches the desired state, `shadowd` no-ops.

`shadowd` stores only local operational evidence, such as logs, audit JSONL,
dry-run reports, and bounded caches. GitHub remains the cross-device source of
truth for the MVP task lifecycle.

## MVP Status Model

The app-facing task state is intentionally small:

| State | Meaning |
|---|---|
| Draft | Recognized but not submitted |
| Submitted | Confirmed and sent to `shadow` |
| Queued | `shadowd` received the task and is waiting to execute |
| Running | A Codex agent is executing |
| Need Input | User input is required |
| PR Ready | A linked PR is ready for review |
| Done | Work is complete |
| Failed | Execution failed |
| Cancelled | User cancelled the task |

## EventKit Projection Model

Reminders carries completable work: review cards, follow-ups, blockers, approvals, due tasks, completion state, priority, and supported native fields.

Calendar carries time occupancy: meetings, appointments, focus blocks, sleep or health blocks, explicit start/end times, deadlines, and milestones.

Reminders board organization uses two dimensions. Lists represent the four life domains: money, health, relationships, and work. Sections inside each list represent the GTD and Eisenhower-style work quadrants: `IMPORTANT`, `URGENT`, `DOING`, and `TODO`.

Calendar does not carry GTD or quadrant section semantics. It only carries time windows, milestones, and time occupancy.

A work item may appear in both only when the projections mean different things. The canonical projection mapping records EventKit external IDs so later runs can reuse existing work-panel items instead of creating unrelated duplicates.

## Reminders Control Surface Policy

Smart Shadow uses a layered control policy for Apple Reminders:

- P0 internal semantics: canonical work items, life-domain lists, quadrant suggestions, projection mappings, and audit logs live in Smart Shadow state.
- P1 production writes: routine reminder creation, updates, completion, list moves, due dates, priorities, and notes use Swift + EventKit.
- P2 AppleScript supplement: narrowly scoped AppleScript is allowed only for Reminders scripting-dictionary fields that EventKit does not expose, such as `flagged` or `show`, with small serialized batches and verification.
- P3 native sections: Reminders sections and columns are native App UI state. They must be created, renamed, sorted, or populated through the Reminders App UI or supervised Accessibility automation with visual acceptance.
- P4 private diagnostics: private ReminderKit and the Reminders SQLite stores are read-only diagnostic surfaces. They are not production write paths.

The CLI exposes this boundary through `reminders-plan-quadrants --dry-run` for EventKit-based section suggestions and `reminders-db-doctor` for read-only private-store diagnostics.

Lark calendar events use stable `lark:calendar:<id>` canonical keys and project to Calendar as time occupancy. Lark tasks use stable `lark:task:<guid>` canonical keys and project to Reminders as completable work; task start/end fields stay task metadata and must not create Calendar time blocks.

Mail uses stable `apple_mail:<message-id-or-source-id>` canonical keys, but Smart Shadow no longer classifies mail in its daemon loop. Codex Automation decides the domain, action, and projection target, then calls `project-mail-decision`. Smart Shadow validates that explicit payload, performs the projection, and records projection IDs for dedupe. Mail decisions are not allowed to create Lark tasks; work mail goes to Apple Reminders `WORK`, with optional Apple Calendar projection for real time blocks.

Google Calendar events, Google Tasks, and Google Contacts are one-way strict-mirror sync sources. Google is the source of truth. Smart Shadow writes Calendar/Reminders through EventKit and Contacts through Contacts.framework, preferring iCloud-backed writable containers when available. Deletion is allowed only for Apple objects present in `sync_mappings`; the sync must never delete a user-created Apple item by matching title, email address, date, or other content.

## Runtime State

Runtime state is local and ignored by Git:

- `var/state.sqlite`: signals, decisions, actions, projection mappings.
- `var/state.sqlite`: Google sync cursors and Google-to-Apple mappings for strict mirror behavior.
- `var/logs/audit.jsonl`: behavior-changing events and execution evidence.
- `var/reports/`: run reports, source acceptance reports, rule-change previews.
- `var/rule-feedback.jsonl`: accepted, adjusted, retired, and rejected rule outcomes.

## Control Surfaces

- `bin/smart-shadow`: primary operator CLI.
- `bin/smart-shadow-test`: command-level regression test runner.
- `smart-shadow-menu`: optional SwiftUI menu-bar control surface for status and actions.
- `launchd/me.longbiaochen.smart-shadow.plist.template`: illustrative checked-in template.
- `install-launchd`: generates the concrete local LaunchAgent with absolute local paths.
