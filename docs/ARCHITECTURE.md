# Architecture

Smart Shadow is a Swift-native macOS core for a local, auditable assistant. The current implementation is a SwiftPM executable with CLI commands, launchd lifecycle support, EventKit integration, SQLite state, audit logs, and report generation.

The `life-os` workflow adds one narrow Swift-native loop inside the local core:
`shadowd` reconciles the whole Life OS GitHub Project and derives next actions
from GitHub Issue / Project / PR state. It does not maintain a separate task
database. Voice issues are one issue class inside that Project, not the queue
boundary.

## Component Model

- Sensing sources collect bounded local signals: JSON event files, file metadata, structured Lark calendar/task reads, Google Calendar/Tasks/Contacts reads, local command summaries, browser bookmark metadata, EventKit Reminders reads, and local mail-summary JSON.
- The ingest layer normalizes signals, writes them to SQLite, and deduplicates by source and source ID.
- The rule registry in `config/rules.json` decides domain, priority, risk, review requirement, and default action.
- The projection engine maps one canonical work item into Apple Reminders, Apple Calendar, or an explicitly requested low-risk Mail action. Lark task data is read-only input and is never a mail projection target.
- Local executors only run approved, low-risk actions. Draft-writing is the current safe executor shape.
- Reports summarize review items, background context, source coverage, and recent rule feedback.
- `shadowd` owns the GitHub Project reconcile loop for the Life OS Project dashboard. It may use labels as hints, but Project membership is the queue boundary.
- `chat-type-cli` is used only when a Project issue is explicitly a voice issue that still needs transcription.

## Data Flow

1. A source places or returns structured signals.
2. `run-once` or the daemon ingests the signal and records it in SQLite.
3. Rules classify the signal and choose an action.
4. High-value or high-risk personal items become review work through EventKit projections; mail enters this path only when Codex Automation submits an explicit decision.
5. Actions, decisions, and projection IDs are recorded for later explanation and dedupe.
6. Reports and audit logs provide operator-facing and technical evidence.

## Life OS Project Reconcile Flow

The backend loop uses GitHub as the durable coordination surface:

1. `bin/shadowd once` reads open issues from the Life OS GitHub Project.
2. Each issue is classified from issue body metadata, labels, Project fields,
   comments, and linked PRs.
3. Voice issues are handled by the voice path only when they include Smart
   Shadow metadata or an equivalent voice marker.
4. Ordinary Project issues are never sent through ASR. They are reconciled from
   Project status, custom status, issue template completeness, and PR state.
5. If custom status is `完成` but Project `Status` is not done, `shadowd` plans
   Project Status alignment.
6. If required template sections are missing, `shadowd` plans a clarification
   comment instead of starting implementation.
7. If GitHub state already matches the desired state, `shadowd` no-ops.

`shadowd` stores only local operational evidence, such as logs, audit JSONL,
dry-run reports, and bounded caches. GitHub remains the cross-device source of
truth.

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
