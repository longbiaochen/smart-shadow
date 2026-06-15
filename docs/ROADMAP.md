# Roadmap

Smart Shadow MVP is an entry-layer-first, Mac-service-backed personal shadow
loop. The entry layer includes the phone lightweight app, Mac menu bar, global
hotkey voice, in-app AI shadow controls, star/favorite/share/mark operations,
and other configured user operations. Voice and entry events route back to local
`shadowd`; Codex creates or resumes the corresponding Project thread and uses
local software to move the work forward; `shadowd` creates feedback on the
origin channel.

The long-running local assistant capabilities remain important support
infrastructure, but they are no longer the product headline for the MVP and must
not become broad daemon sensing by default.

## Current Verified Slice

- iOS target `SmartShadowIOS` exists as one entry-layer surface for Smart Shadow.
- Voice intake, menu-bar/hotkey entry, and GitHub-backed delivery work are
  represented in the iOS and companion-app docs.
- Swift-native executable and CLI control surface.
- User LaunchAgent install/start/stop/status support.
- JSON event inbox processing with explicit-intent metadata and SQLite persistence.
- Rule registry validation, rule-change previewing, and local rule feedback.
- Explicit intent source acceptance reports before adapter enablement.
- Source diagnostics through `source-doctor`, including confirmed Mail decision projection.
- Runtime diagnostics through `service-status`.
- EventKit status and foreground access-request commands.
- Apple Reminders review-card creation only for explicit or user-confirmed follow-up signals.
- Calendar/Reminders projection mapping to prevent unrelated duplicate work-panel items.
- Command-level regression tests for source gates, EventKit gates, source readiness, and service status.
- Swift-native `shadowd` reconciler for the Life OS Project: whole-Project
  intake, GitHub Issue / Project / PR source of truth, no local authoritative
  task database, and fixture-backed CLI tests.

## Next Milestones

1. Bring the iPhone app in line with the matrix flow: capture/input,
   confirmation, Reminders/Calendar placement, and linked native-app handoff.
2. Implement the structured Project/Issue contract: life line, project, issue,
   context, target output, acceptance criteria, priority, urgency, risk, and
   time implications.
3. Connect confirmed app tasks to Reminders and Calendar through Swift/EventKit
   with stable projection mappings.
4. Make `shadowd` map external issue streams such as GitHub, Mail, Feishu, and
   browser/share inputs into Project / Issue candidates before execution.
5. Expose simplified app state from the matrix: Inbox, Active, Needs Attention,
   Review, and Done.
6. Add push notifications only for key matrix changes: Needs Attention, Review,
   Done, Failed, long blocked, or explicitly watched Project/Issue updates.
7. Run repeated live SOL dry-runs for the Life OS Project reconciler, then
   enable narrow GitHub writes only for unambiguous comments/status alignment.
8. Harden in-place EventKit updates for existing Reminders and Calendar
   projections after foreground permission is granted.
9. Rebuild review-card status reading through Swift + EventKit.
10. Add Smart Shadow-first native app workflows for creating, opening, and
   repairing Reminders, Calendar events, Finder folders, Notes links, Contacts,
   Photos, Music, GitHub, and Feishu projections while preserving mapping IDs.
11. Add model-routing telemetry for low-cost text and multimodal side channels
   without making expensive models the default organizer.

## Open Decisions

- Whether the iPhone app should create/update GitHub Issues directly or submit
  through a supported server path before GitHub mutation.
- How much project selection UI is acceptable when app-side project context is
  ambiguous; the PRD target is minimal confirmation, not a complex chooser.
- Which push notification transport should own app-visible lifecycle changes.
- Whether Apple Reminders Inbox should be explicit-task context only or also a strict projection mirror.
- Whether Calendar should create only explicit appointments/deadlines or also user-confirmed suggested focus windows.
- Which confirmed Mail decision executor set, if any, should own production read/write responses.
- Which approval semantics allow low-risk outbound messages to send automatically.
- Whether approved-review processing may run automatically in the daemon after explicit user confirmation.
- Whether page content or full mail bodies are ever worth the privacy cost after the user explicitly shares or marks an item; browser history remains out of scope.
- Which remote Codex or Janus environment should own full closed-loop Feishu-to-Codex-to-GitHub-to-X acceptance runs.
- How ready Life OS Project issues should hand off to Codex execution after
  Project reconcile behavior is proven.

## Boundaries

- MVP does not build a full ChatGPT-style chat product.
- MVP does not replace GitHub Issue / PR / CI / Wiki.
- MVP does not build a complex Feishu workspace, multi-user project-management
  backend, full prototype-design tool, independent code host, or broad
  information feed.
- MVP does not build an environment-signal automatic processing hub.
- MVP does not build a proactive social agent or full event-source filter.
- No direct writes to Apple Calendar or Reminders databases.
- No destructive file responses.
- No private content upload to third-party model providers without explicit task-level disclosure.
- High-risk responses remain review-card only until approval semantics are implemented and accepted.
- Runtime evidence stays under ignored local paths; durable architecture and safety rules belong in formal docs and `AGENTS.md`.
- GitHub pushes and X posts for skill updates remain explicit-approval responses; nightly maintenance may draft them but must not publish them unattended.
