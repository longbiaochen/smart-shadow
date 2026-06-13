# Roadmap

Smart Shadow MVP is an iPhone single-button task entry plus a local `shadowd`
execution loop. The durable work record is GitHub Issue / Comment / PR, and the
user-facing product loop is voice -> structured task -> confirmation -> `shadow`
execution -> status/progress -> user acceptance.

The long-running local assistant capabilities remain important support
infrastructure, but they are no longer the product headline for the MVP.

## Current Verified Slice

- iOS target `SmartShadowIOS` exists as the primary app surface for Smart Shadow.
- Voice intake and GitHub-backed delivery work are represented in the iOS and
  companion-app docs.
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
  intake, GitHub Issue / Project / PR source of truth, no local authoritative
  task database, and fixture-backed CLI tests.

## Next Milestones

1. Bring the iPhone app in line with the PRD page flow: Shadow Button, voice
   input, task confirmation, task detail, and task feed.
2. Implement the structured task-card contract: title, type, project, context,
   target output, acceptance criteria, priority, PR need, and confirmation state.
3. Connect confirmed app tasks to GitHub Issue creation/update with Smart Shadow
   source metadata, `shadow` execution identity, and the MVP status labels.
4. Make `shadowd` map GitHub tasks to local projects/repos, assign Codex agent
   execution, write meaningful Issue comments, and create PRs only for
   reviewable code changes.
5. Expose app task status from GitHub state: Draft, Submitted, Queued, Running,
   Need Input, PR Ready, Done, Failed, and Cancelled.
6. Add push notifications only for key state changes: Need Input, PR Ready,
   Done, Failed, long blocked, or explicitly watched task updates.
7. Run repeated live SOL dry-runs for the Life OS Project reconciler, then
   enable narrow GitHub writes only for unambiguous comments/status alignment.
8. Harden in-place EventKit updates for existing Reminders and Calendar
   projections after foreground permission is granted.
9. Rebuild review-card status reading through Swift + EventKit.
10. Add model-routing telemetry for low-cost text and multimodal side channels
   without making expensive models the default organizer.

## Open Decisions

- Whether the iPhone app should create/update GitHub Issues directly or submit
  through a supported server path before GitHub mutation.
- How much project selection UI is acceptable when app-side project context is
  ambiguous; the PRD target is minimal confirmation, not a complex chooser.
- Which push notification transport should own app-visible lifecycle changes.
- Whether Apple Reminders Inbox should be mirrored only or also moved/cleaned by this service.
- Whether Calendar should create only explicit appointments/deadlines or also suggested focus windows.
- Which Mail.app executor set should own production read/write actions beyond low-value archive.
- Which approval semantics allow low-risk outbound messages to send automatically.
- Whether approved-review processing may run automatically in the daemon.
- When browser history, page content, or full mail bodies are worth the privacy cost beyond the configured product sources.
- Which remote Codex or Janus environment should own full closed-loop Feishu-to-Codex-to-GitHub-to-X acceptance runs.
- How ready Life OS Project issues should hand off to Codex execution after
  Project reconcile behavior is proven.

## Boundaries

- MVP does not build a full ChatGPT-style chat product.
- MVP does not replace GitHub Issue / PR / CI / Wiki.
- MVP does not build a complex Feishu workspace, multi-user project-management
  backend, full prototype-design tool, independent code host, or broad
  information feed.
- No direct writes to Apple Calendar or Reminders databases.
- No destructive file actions.
- No private content upload to third-party model providers without explicit task-level disclosure.
- High-risk actions remain review-card only until approval semantics are implemented and accepted.
- Runtime evidence stays under ignored local paths; durable architecture and safety rules belong in formal docs and `AGENTS.md`.
- GitHub pushes and X posts for skill updates remain explicit-approval actions; nightly maintenance may draft them but must not publish them unattended.
