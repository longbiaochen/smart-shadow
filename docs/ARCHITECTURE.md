# Architecture

Smart Shadow is an iPhone-first, Mac-service-backed personal shadow system with
an entry layer, `shadowd` as the local Mac system service, and Codex as the
decision brain. The entry layer can appear as in-app AI shadow controls,
star/favorite/share/mark operations, the Mac menu-bar app, global hotkey voice, or
a phone lightweight app invoked after QR-code binding. Voice interactions
eventually route back to `shadowd` on the Mac. `shadowd` senses and prepares
context, connects the task to Codex, Codex creates or resumes the corresponding
Project thread and uses local software to move the work forward, and `shadowd`
tracks state and creates feedback for the user.

The architecture has three stable roles:

1. `shadowd` is the system service for entry routing, sensing, connection,
   state tracking, audit, recovery, origin-channel mapping, and feedback.
2. Codex is the decision brain for life lines, Projects, Issues, priority, risk,
   task decomposition, planning, corresponding Project-thread creation/resume,
   local software use, review, and target-surface choice.
3. The entry layer turns user operations on phone or computer surfaces into
   explicit intent events.
4. Apps on the Mac and external systems are intent surfaces, context sources,
   response tools, collaboration surfaces, and feedback surfaces.

The four life lines remain a design philosophy, not a requirement that every
life area live inside one app. The current default routing is:

1. Work-related Projects and Issues use the user's Feishu platform and are
   tracked on Feishu task boards through Feishu CLI.
2. Personal and life-related responses use Apple Reminders and are tracked on the
   corresponding Reminders boards or lists.
3. GitHub remains the code, PR, Issue, CI, open-source feedback, and
   repo-centered execution surface; it does not replace the Feishu work task
   board by default.
4. Calendar carries time blocks, deadlines, and rhythms. Finder, Notes,
   Contacts, Photos, and Music carry supporting files, knowledge, people, and
   media assets.

Codex chooses the target software by Project semantics, risk, collaboration
context, and user preference. Deviations from the defaults should be explainable
and preserve Project / Issue mappings.

The canonical flow is:

```text
entry layer event / voice -> shadowd on Mac -> Codex Project thread -> local software response -> shadowd origin-channel feedback -> user
```

The detailed product model is documented in [SPACE_TIME_MATRIX.md](SPACE_TIME_MATRIX.md).

## Codex Extension Model

Smart Shadow should be understood as a Codex second-development layer plus a
Swift-native Mac system service, not as a separate AI product that competes with
Codex. Codex provides reasoning, decomposition, planning, local code editing,
terminal control, and tool orchestration. Smart Shadow defines the rules,
memory, skills, scripts, mappings, approval boundaries, and `shadowd` bridges
that make Codex and the user's installed software behave as a personal shadow.

The durable product boundary is:

1. Agent rules and docs define how Codex should act for Smart Shadow work.
2. Skills and tests package repeatable workflows so future Codex sessions keep
   the same behavior.
3. `shadowd` runs as the local system service: explicit intake, implicit intent
   monitoring, source dedupe, context preparation, Codex connection, durable
   state, mapping, EventKit writes, native app bridges, launchd lifecycle, audit
   logs, recovery, bridge dispatch, and origin-channel feedback.
4. Apple native apps and external systems remain software surfaces for intent,
   context, response, collaboration, and feedback. Codex and `shadowd` coordinate
   them through stable identities and approval boundaries.

This means Smart Shadow does not need a second general chat backend, a second
ASR/text-polish backend, or a separate universal project-management UI by
default. Those capabilities should be added only when Codex plus `shadowd` plus
the user's existing software cannot provide the required experience.

## shadowd Codex App Server Routing

`shadowd` uses the `smart-shadow` project as the task intake entry point for
Codex dispatch. Intake threads are dispatcher threads, not execution threads:
they parse the incoming task, identify the likely Project / Issue context, decide
whether an existing thread should continue, and produce a routeable decision for
`shadowd` to validate.

`shadowd` must reuse the App Server already used by Codex App. It must not start
or introduce a separate long-running App Server, secondary chat backend, or
parallel model service for dispatch. The supported local integration path is to
connect to the managed Codex App Server control path or equivalent app-server
protocol surface and call the thread APIs there.

After parsing a task, `shadowd` should be able to open, resume, or activate the
appropriate Codex thread under the project it determines to be relevant:

1. Receive the external task into the Smart Shadow dispatcher context.
2. Ask Codex, under Smart Shadow rules, to classify the task and choose the best
   target project and thread response.
3. Validate the chosen project, cwd, and thread id against local registry and
   Codex-visible thread state.
4. Resume the selected thread when the task is a continuation, or start a new
   thread in the target project cwd when no existing thread is appropriate.
5. Persist the intake id, dispatcher thread id, target project, target thread id,
   decision reason, status, and origin feedback channel so later progress and
   writeback are explainable.

The dispatcher thread must not perform the substantive task work itself except
for direct low-risk replies. Real work runs in the selected project thread so
Codex has the correct cwd, project instructions, files, and verification path.

The current implementation is Swift-native across the iOS app and local Mac
service surfaces. The Mac side includes CLI commands, launchd lifecycle support,
GitHub issue handling, EventKit integration, SQLite state, audit logs, and report
generation.

Smart Shadow is not an unbounded environment-signal processing hub. It does not
take over all Mail, messaging, news, feeds, calendar, contacts, file system, or
browser history. `shadowd` may sense bounded implicit intent from configured
surfaces, such as a new file in a Project folder, a Calendar item, a WeChat File
Transfer message, a selected Mail thread, a Feishu item, a bookmark/link save,
GitHub `@shadow`, or explicit confirmation of a generated suggestion. Such
signals default to record, explain, complete context, dry-run, or ask for
confirmation before response.

GitHub, Feishu, Mail, WeChat, Xiaohongshu, Twitter, Zhihu, Finder, Calendar, and
similar systems can be intent surfaces, collaboration surfaces, or response
surfaces. They are not forced into one canonical Project board, but each
accepted item can become a Smart Shadow Issue under a Project. Mail is
especially close to an Issue stream: one message or thread usually represents
one concrete matter, while Project membership is determined later by the Smart
Shadow board, user confirmation, or explicit rules.

Finder, Contacts, Notes, Photos, Music, and other local or personal apps can
receive responses, context, and feedback from life lines, Projects, and Issues;
they do not become scheduling or priority systems unless the Project semantics
explicitly call for that role.

The `life-os` workflow is the current GitHub-backed MVP coordination surface:
`shadowd` reconciles the Life OS GitHub Project and derives next responses from
GitHub Issue / Project / PR state. It does not maintain a separate authoritative
task database.

## Component Model

- `SmartShadowIOS` is the primary product surface. It owns voice capture, transcript display, task-card confirmation, task status display, follow-up capture, and push-notification landing.
- `shadow` is the unified agent identity shown to the user. The user should not need to pick among local Codex agents.
- Codex is the decision brain for task understanding, decomposition, planning, corresponding Project-thread creation/resume, local software use, tool choice, risk review, and explanation. Smart Shadow constrains Codex through Agent rules, skills, workflow docs, local services, and approval boundaries.
- `shadowd` is the sensing and feedback bridge. It connects intent surfaces to Codex, tracks state, audits responses, and creates user feedback on the platform channel where the task was posted by default.
- Reminders and Calendar are response/time surfaces. They receive Project / Issue updates like Finder, Contacts, Notes, Photos, Music, GitHub, Feishu, Mail, and other surfaces when their semantics fit.
- GitHub Issue is an external collaboration and code-review record for development work, open-source feedback, and repo-centered execution. It may mirror or carry a Project Issue, but it is not the universal management center.
- The user GitHub identity writes only the user's explicit intent: new task issues, follow-up comments, and replies to Shadow questions after local confirmation.
- The Shadow GitHub App bot identity writes execution state: acknowledgements, plans, progress, labels/status updates, branches, commits, and PRs.
- Pull Requests are created only when code changes are ready for review. They are not used for routine progress logging.
- `shadowd` owns explicit intake, bounded implicit sensing, webhook intake, GitHub reconcile, repo/project mapping, Codex connection, idempotency, progress comments, branch/commit/PR creation, status synchronization, origin-channel mapping, and user feedback.
- `shadowd` does not record audio, store audio, transcribe speech, polish user text, or write GitHub content as the user.
- ChatType Runtime/Polish is the local ASR and text-cleanup capability used by the iOS/macOS front end before GitHub submission.
- Existing source adapters collect bounded local signals: JSON event files, file metadata, structured Lark calendar/task reads, Google Calendar/Tasks/Contacts reads, local command summaries, browser bookmark metadata, EventKit Reminders reads, and local mail-summary JSON. They are explicit or bounded implicit intent adapters, debug fixtures, migration aids, or context sources, not broad autonomous takeover.
- The rule registry in `config/rules.json` decides domain, priority, risk, review requirement, and default response for local assistant flows.
- The projection engine maps one canonical work item into Apple Reminders, Apple Calendar, or an explicitly requested low-risk Mail response. These surfaces support the broader local assistant, but they are not the MVP task master record.
- Reports summarize review items, background context, source coverage, GitHub task state, and recent rule feedback.

## MVP Data Flow

1. The user opens the iPhone app and records a task.
2. The app stores only a short-lived local audio cache, transcribes and polishes the text locally, recognizes intent, and builds a structured task card with title, type, project, background, target output, acceptance criteria, priority, PR need, and confirmation requirement.
3. The user confirms, edits, cancels, re-records, or adds a follow-up.
4. Confirmed tracked work creates or updates a GitHub Issue or Issue Comment with the user's GitHub identity. GitHub stores only the final text task and compact Smart Shadow metadata, never raw audio.
5. `shadowd` reads the confirmed Project / Issue state or external surface state, maps it to a local repo or project context, and connects to Codex.
6. Codex creates or resumes the corresponding Project thread, decomposes and plans the task, invokes the selected local software or agent path, and records local operational evidence.
7. `shadowd` and the assigned agent write meaningful progress as the Shadow bot identity. Feedback defaults to the platform channel where the user posted the task. If code changes are ready for review, `shadowd` creates a linked PR.
8. The app refreshes task state from the GitHub-backed record and uses push notifications only for key state changes: need input, PR ready, done, failed, long blocked, or watched-task update.
9. The user confirms completion, requests changes, or adds a new follow-up.

## Explicit Intent Adapter Data Flow

The repository still supports local adapter previews and EventKit projection:

1. A source adapter places or returns a structured `IntentSignal`.
2. The signal records `origin.user_action`, `source`, `captured_at`, `payload`, `requires_confirmation`, `user_approved`, and `follow_up_task_id` when available.
3. `accept-source` previews the adapter and rule decision without writing runtime state.
4. `run-once` or the daemon may ingest enabled adapters, but follow-up responses require a clear `origin.user_action`, `user_approved=true`, or a confirmed `project-mail-decision`.
5. Inputs without explicit intent can be recorded for debugging, used as bounded implicit-intent candidates, or used for strict context, but cannot trigger reminders, archive/delete/reply/forward responses, social outreach, or external commitments without confirmation and risk checks.
6. Responses, decisions, and projection IDs are recorded for later explanation and dedupe.
7. Reports and audit logs provide operator-facing and technical evidence.

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
dry-run reports, and bounded caches. Codex remains the user-facing processing
center; Reminders, Calendar, and GitHub carry projections for response, time,
development, open-source feedback, code review, and external collaboration
cases.

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

Reminders is a response surface. It carries completable work: review cards, follow-ups, blockers, approvals, due tasks, completion state, priority, and supported native fields.

Calendar is a time surface. It carries time occupancy: meetings, appointments, focus blocks, sleep or health blocks, explicit start/end times, deadlines, and milestones.

Reminders board organization uses two dimensions. Lists represent the four life domains: money, health, relationships, and work. Sections inside each list represent the GTD and Eisenhower-style work quadrants: `IMPORTANT`, `URGENT`, `DOING`, and `TODO`.

Calendar does not carry GTD or quadrant section semantics. It only carries time windows, milestones, and time occupancy.

A work item may appear in both only when the projections mean different things. The canonical projection mapping records EventKit external IDs so later runs can reuse existing work-panel items instead of creating unrelated duplicates.

## Cross-App Projection Identity

Smart Shadow may project the same Project or Issue into multiple Apple native apps and external systems: Finder folders, Reminders tasks, Calendar events, Notes links or exported notes, GitHub issues, Feishu documents, Contacts entries, Photos albums, and Music playlists.

These projections are not independent tasks. They must all point back to a single internal Project or Issue identity stored in the local registry/state layer. Every projection record must include:

- the internal Project or Issue ID,
- the target surface,
- the target object's stable external identifier when the API exposes one,
- the target path or URL when the surface is file- or web-based,
- the projection role, such as reminder response, calendar time block, knowledge note, asset album, code repository, or work document,
- creation/update timestamps and last verified state.

Cross-app synchronization must use this mapping table as the only authority for updates, completion, moves, deletion, and dedupe. Matching by title, note body, date, file path fragment, sender, or other user-editable content is allowed only as a dry-run repair heuristic that produces a reviewable suggestion.

If a mapping is missing, ambiguous, points to a deleted object, or conflicts with a user-edited native app object, `shadowd` must stop before mutation and produce a dry-run repair plan or ask for user confirmation. It must not silently create a duplicate projection, sever an existing link, or delete a user-visible asset.

## Native App Interaction Model

The long-term interaction model is Smart Shadow first, Apple native apps second. Users should be able to start from Smart Shadow when they want to create, inspect, route, repair, or continue a Project or Issue, and Smart Shadow should open or update the right native app surface with the correct projection mapping.

Apple native apps remain the user's familiar asset and review surfaces. Reminders can show responses, Calendar can show time blocks, Finder can show project files, Notes can hold user-curated knowledge, Contacts can hold people, Photos and Music can hold media assets, and GitHub or Feishu can hold external collaboration artifacts. Codex owns the user-facing processing layer; Smart Shadow / `shadowd` owns the cross-surface identity, sync intent, repair workflow, and explanation layer.

Direct user edits in native apps are allowed and expected, but they are treated as external changes that must be reconciled through the mapping layer. Smart Shadow must never assume exclusive ownership of native app state, and future UI/CLI commands should prefer "open/edit through Smart Shadow" flows that preserve mappings over undocumented direct edits in each app.

## Reminders Control Surface Policy

Smart Shadow uses a layered control policy for Apple Reminders:

- P0 internal semantics: canonical work items, life-domain lists, quadrant suggestions, projection mappings, and audit logs live in Smart Shadow state.
- P1 production writes: routine reminder creation, updates, completion, list moves, due dates, priorities, and notes use Swift + EventKit.
- P2 AppleScript supplement: narrowly scoped AppleScript is allowed only for Reminders scripting-dictionary fields that EventKit does not expose, such as `flagged` or `show`, with small serialized batches and verification.
- P3 native sections: Reminders sections and columns are native App UI state. They must be created, renamed, sorted, or populated through the Reminders App UI or supervised Accessibility automation with visual acceptance.
- P4 private diagnostics: private ReminderKit and the Reminders SQLite stores are read-only diagnostic surfaces. They are not production write paths.

The CLI exposes this boundary through `reminders-plan-quadrants --dry-run` for EventKit-based section suggestions and `reminders-db-doctor` for read-only private-store diagnostics.

Lark calendar events use stable `lark:calendar:<id>` canonical keys and project to Calendar as time occupancy. Lark tasks use stable `lark:task:<guid>` canonical keys and project to Reminders as completable work; task start/end fields stay task metadata and must not create Calendar time blocks.

Mail uses stable `apple_mail:<message-id-or-source-id>` canonical keys. Smart Shadow does not classify all mail in its daemon loop, but user-selected mail is a first-class external Issue channel alongside GitHub and Feishu. A selected message or thread becomes an external issue candidate with source identity, sender, subject, received time, thread/message IDs, and a compact user-approved summary. Smart Shadow then attaches it to an existing Project or creates a new Project / Issue after confirmation. The original Mail thread remains the communication surface; Smart Shadow owns Project membership, internal Issue identity, and cross-surface projections.

Mail enters only through user-marked mail, a confirmed local debug input, or a `project-mail-decision` payload from Codex Automation. Smart Shadow validates that explicit payload, performs the projection, and records projection IDs for dedupe. Mail decisions are not allowed to create Lark tasks; confirmed work mail can go to Apple Reminders `WORK`, with optional Apple Calendar projection for real time blocks. It must not automatically reply, forward, archive, delete, or make outside commitments.

Bookmarks represent user-saved links, not browsing history. A bookmark can become follow-up context only because the user saved or shared it.

Google Calendar events, Google Tasks, and Google Contacts are context/projection adapters for explicit tasks or one-way strict mirrors when deliberately enabled. Google is the source of truth. Smart Shadow writes Calendar/Reminders through EventKit and Contacts through Contacts.framework, preferring iCloud-backed writable containers when available. Deletion is allowed only for Apple objects present in `sync_mappings`; the sync must never delete a user-created Apple item by matching title, email address, date, or other content.

## Runtime State

Runtime state is local and ignored by Git:

- `var/state.sqlite`: signals, decisions, responses, projection mappings.
- `var/state.sqlite`: Google sync cursors and Google-to-Apple mappings for strict mirror behavior.
- `var/logs/audit.jsonl`: behavior-changing events and execution evidence.
- `var/reports/`: run reports, source acceptance reports, rule-change previews.
- `var/rule-feedback.jsonl`: accepted, adjusted, retired, and rejected rule outcomes.

## Control Surfaces

- `bin/smart-shadow`: primary operator CLI.
- `bin/smart-shadow-test`: command-level regression test runner.
- `smart-shadow-menu`: optional SwiftUI menu-bar control surface for status and responses.
- `launchd/me.longbiaochen.smart-shadow.plist.template`: illustrative checked-in template.
- `install-launchd`: generates the concrete local LaunchAgent with absolute local paths.
