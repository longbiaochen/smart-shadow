# Roadmap

Smart Shadow is a long-running local assistant, not a collection of one-off scripts.

## Current Verified Slice

- Swift-native executable and CLI control surface.
- User LaunchAgent install/start/stop/status support.
- JSON event inbox processing with SQLite persistence.
- Rule registry validation, rule-change previewing, and local rule feedback.
- Source acceptance reports before daemon enablement.
- Source diagnostics through `source-doctor`, including Mail.app-backed intake before daemon enablement.
- Runtime diagnostics through `service-status`.
- EventKit status and foreground access-request commands.
- Apple Reminders review-card creation for high-value or high-risk signals.
- Calendar/Reminders projection mapping to prevent unrelated duplicate work-panel items.
- Command-level regression tests for source gates, EventKit gates, source readiness, and service status.
- Swift-native `shadowd` reconciler for the Life OS Project: whole-Project
  intake, GitHub Issue / Project / PR source of truth, no local task database,
  and fixture-backed CLI tests.

## Next Milestones

1. Run repeated live SOL dry-runs for the Life OS Project reconciler, then
   enable narrow GitHub writes only for unambiguous comments/status alignment.
2. Harden in-place EventKit updates for existing Reminders and Calendar projections after foreground permission is granted.
3. Rebuild review-card status reading through Swift + EventKit.
4. Expand Calendar projection for scheduled work blocks, deadlines, and health/time-protection blocks.
5. Run repeated acceptance for file metadata, Lark context, Chrome bookmarks, Apple Reminders Inbox, mail summary replay, and Mail.app sources before enabling daemon collection.
6. Expand Mail.app into the first end-to-end product slice: sense, classify, archive low-value items, draft/review sensitive replies, sync follow-up work, and record audit evidence.
7. Add model-routing telemetry for low-cost text and multimodal side channels without making expensive models the default organizer.
8. Implement the nightly Smart Shadow / SmartShader skill-maintenance dry-run command, then add the approval-gated launchd timer after the dry-run and Janus closed-loop acceptance path are proven.

## Open Decisions

- Whether Apple Reminders Inbox should be mirrored only or also moved/cleaned by this service.
- Whether Calendar should create only explicit appointments/deadlines or also suggested focus windows.
- Which Mail.app executor set should own production read/write actions beyond low-value archive.
- Which approval semantics allow low-risk outbound messages to send automatically.
- Whether approved-review processing may run automatically in the daemon.
- When browser history, page content, or full mail bodies are worth the privacy cost beyond the configured product sources.
- Which remote Codex or Janus environment should own full closed-loop Feishu-to-Codex-to-GitHub-to-X acceptance runs.
- How ready Life OS Project issues should hand off to Codex execution after
  Project reconcile behavior is proven.
- Whether the eventual iPhone app should talk directly to GitHub or through a
  later supported server path.

## Boundaries

- No direct writes to Apple Calendar or Reminders databases.
- No destructive file actions.
- No private content upload to third-party model providers without explicit task-level disclosure.
- High-risk actions remain review-card only until approval semantics are implemented and accepted.
- Runtime evidence stays under ignored local paths; durable architecture and safety rules belong in formal docs and `AGENTS.md`.
- GitHub pushes and X posts for skill updates remain explicit-approval actions; nightly maintenance may draft them but must not publish them unattended.
