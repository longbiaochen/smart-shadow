# Architecture

Smart Shadow is a Swift-native macOS core for a local, auditable assistant. The current implementation is a SwiftPM executable with CLI commands, launchd lifecycle support, EventKit integration, SQLite state, audit logs, and report generation.

## Component Model

- Sensing sources collect bounded local signals: JSON event files, file metadata, local command summaries, browser bookmark metadata, EventKit Reminders reads, and local mail-summary JSON.
- The ingest layer normalizes signals, writes them to SQLite, and deduplicates by source and source ID.
- The rule registry in `config/rules.json` decides domain, priority, risk, review requirement, and default action.
- The projection engine maps one canonical work item into Reminders, Calendar, or both according to semantics.
- Local executors only run approved, low-risk actions. Draft-writing is the current safe executor shape.
- Reports summarize review items, background context, source coverage, and recent rule feedback.

## Data Flow

1. A source places or returns structured signals.
2. `run-once` or the daemon ingests the signal and records it in SQLite.
3. Rules classify the signal and choose an action.
4. High-value or high-risk items become review work through EventKit projections.
5. Actions, decisions, and projection IDs are recorded for later explanation and dedupe.
6. Reports and audit logs provide operator-facing and technical evidence.

## EventKit Projection Model

Reminders carries completable work: review cards, follow-ups, blockers, approvals, due tasks, completion state, priority, and supported native fields.

Calendar carries time occupancy: meetings, appointments, focus blocks, sleep or health blocks, explicit start/end times, deadlines, and milestones.

A work item may appear in both only when the projections mean different things. The canonical projection mapping records EventKit external IDs so later runs can reuse existing work-panel items instead of creating unrelated duplicates.

## Runtime State

Runtime state is local and ignored by Git:

- `var/state.sqlite`: signals, decisions, actions, projection mappings.
- `var/logs/audit.jsonl`: behavior-changing events and execution evidence.
- `var/reports/`: run reports, source acceptance reports, rule-change previews.
- `var/rule-feedback.jsonl`: accepted, adjusted, retired, and rejected rule outcomes.

## Control Surfaces

- `bin/smart-shadow`: primary operator CLI.
- `bin/smart-shadow-test`: command-level regression test runner.
- `smart-shadow-menu`: optional SwiftUI menu-bar control surface for status and actions.
- `launchd/me.longbiaochen.smart-shadow.plist.template`: illustrative checked-in template.
- `install-launchd`: generates the concrete local LaunchAgent with absolute local paths.
