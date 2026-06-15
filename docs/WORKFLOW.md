# Smart Shadow Workflow

This document captures durable workflow rules for the Smart Shadow MVP task
loop, Feishu-originated Codex work, Smart Shadow rule refinement, skill
publishing, and closed-loop verification.

## ShadowD / Codex Operating Model

Smart Shadow workflows start in an entry layer and are backed by the Mac
`shadowd` service. The entry layer can be a phone lightweight app, Mac menu-bar
app, global hotkey voice, in-app AI shadow control, or user operations such as
star, favorite, share, and mark. Voice interactions eventually route back to
`shadowd` on the Mac. The default assumption is:

```text
entry layer event / voice -> shadowd sensing bridge -> Codex Project thread -> local software response -> shadowd origin-channel feedback -> user
```

Codex owns interpretation, task decomposition, planning, corresponding
Project-thread creation/resume, local software use, risk review, tool choice,
execution reasoning, and user-facing explanation. `shadowd` owns durable local
service duties that a chat session should not hold in memory forever:
explicit intake, bounded implicit sensing, source dedupe, context preparation,
Codex connection, mappings, queues, EventKit writes, native app bridges, audit
logs, health checks, recovery, bridge dispatch, origin-channel mapping, and
feedback.

Durable rules must be written into `AGENTS.md`, this workflow document, other
formal docs, skills, configuration, or tests. A one-off chat answer is guidance,
not a stable Smart Shadow rule, until it is captured in those surfaces.

When the user interacts with Smart Shadow from phone, Mac menu bar, global
hotkey voice, Feishu, GitHub, Mail, browser, Finder, Calendar, WeChat, or
another app, the entry layer should preserve the source and route the event back
to `shadowd`. `shadowd` should preserve context, then connect the task to Codex.
Codex should apply the same Smart Shadow hierarchy: life line -> Project ->
Issue. It then chooses the needed software surface: Reminders for responses,
Calendar for time, Finder for files, Notes for knowledge, Contacts for people,
Photos/Music for media, and GitHub/Feishu/Mail/WeChat for external
collaboration or communication records.

## MVP Task Loop

The PRD-level workflow is entry-layer-first:

1. The user expresses intent through the entry layer: phone lightweight app,
   Mac menu bar, global hotkey voice, in-app AI shadow control, star/favorite,
   share, mark, or another configured operation.
2. Voice or entry events route back to `shadowd` on the Mac. The relevant entry
   app transcribes when needed, recognizes intent, and creates a structured task
   card or intent payload.
3. The user confirms, edits, cancels, re-records, or adds context.
4. Confirmed tracked work is submitted to the unified agent identity `shadow`.
5. Codex is the decision brain for the user's life lines, Projects, and Issues.
   Reminders, Calendar, GitHub Issue / Comment / PR, Finder, Notes, Contacts,
   Photos, Music, Feishu, Mail, and WeChat are created or updated only when
   their software semantics fit the task.
6. Local `shadowd` maps the task to the right Project/repo, connects Codex to
   create or resume the corresponding Project thread, and Codex uses local
   software or a Codex agent to move the work forward.
7. `shadowd` creates feedback for the user. The default feedback location is the
   platform channel where the user posted the task. PRs are created only for
   reviewable code changes.
8. The app shows Draft, Submitted, Queued, Running, Need Input, PR Ready, Done,
   Failed, or Cancelled state and lands push notifications on the relevant task.
9. The user confirms completion, requests changes, or creates follow-up work.

Feishu is the user's current default work-task tracking platform. Work-related
Projects and Issues should be tracked on Feishu task boards through Feishu CLI
when the task is confirmed and the write boundary is satisfied. Feishu still
must not redefine Smart Shadow as a complex Feishu workbench; it is the default
work task surface, while Codex keeps the life line -> Project -> Issue
philosophy and `shadowd` preserves mappings and feedback channels.

## Explicit And Implicit Intent

Smart Shadow starts from user intent. The entry layer includes explicit phone
and computer operations: visible AI shadow controls in apps, star/favorite/share
/mark operations, Mac menu-bar operations, global hotkey voice, and the phone
lightweight app after QR-code binding. Mac software can also reveal intent.
`shadowd` may watch configured surfaces for bounded implicit candidates:

- A new file under a mapped Project folder can become a proposed Issue or
  follow-up.
- A Calendar item can become a candidate for context completion, materials,
  reminders, or Project linkage.
- A WeChat File Transfer Assistant message can become a personal task candidate.
- User-selected or rule-matched Mail and Feishu items can become Project / Issue
  candidates.

Implicit candidates default to record, explain, complete context, dry-run, or
ask for confirmation. They must not automatically create external commitments,
reply/archive/delete Mail, write shared Feishu tasks, publish social content,
or mutate user-visible state unless the rule is explicit, low risk, reversible,
and authorized.

## Feishu To Codex Routing

Feishu-originated work enters through the Swift-native `bin/shadowd` bridge. The
bridge probes or polls `lark-cli`, records local routing state, and sends the
task into the Smart Shadow dispatcher context for Codex-based routing.

The Feishu bridge is not a separate Python, TypeScript, App Server, or model
daemon. It must reuse the App Server already used by Codex App; it must not start
or introduce a separate App Server for dispatch. The bridge handles explicit
intake, high-risk confirmation, app-server request/response handling,
session/thread mapping, local persistence, and approved replies.

Routing rules:

- Use the Smart Shadow project as the default intake entry point for `shadowd`
  tasks. The intake / dispatcher thread parses the task first, then selects the
  target project and thread for execution.
- Resume an existing Feishu-to-Codex binding when the configured project mode allows `resume_or_create` and the saved session id still belongs to that project.
- Start or activate work in another project only after the dispatcher determines
  that project is relevant and `shadowd` validates the chosen cwd or thread id.
- Use Smart Shadow for workflow-rule conversations, Smart Shadow or SmartShader skill changes, Feishu bridge changes, and rule-publication work.
- Ask the user instead of guessing when confidence is below the configured routing threshold.

## Feishu Execution Layer

For each substantive user task received through Feishu, Smart Shadow keeps the Feishu-side coordination surface separate from the Codex working surface:

- `shadowd` performs intake, dispatcher-thread routing, high-risk confirmation,
  Codex App Server thread/turn dispatch, local session/thread mapping, and final
  writeback.
- The Swift bridge performs only lightweight routing and must not bypass high-risk confirmation.
- The working thread executes the task in the routed project `cwd` and returns a concise result that can be sent back to Feishu.

The currently supported commands are:

- `bin/shadowd feishu-probe` for local `lark-cli` capability checks.
- `bin/shadowd feishu-mock --message TEXT` for local dry-run and routing verification.
- `bin/shadowd feishu-once` for one configured chat poll and optional reply.

Thread/topic handling is not a separate daemon feature today. If Feishu thread-specific routing is needed later, it must be added to the Swift bridge and tested there, not revived through a parallel Python or TypeScript runtime.

Feishu task item handling follows the work/default-surface rule:

- Work-related tasks default to Feishu task boards, using Feishu CLI as the
  supported control path.
- Personal, health, finance, relationship, security, or private-life tasks
  default to Codex / internal Smart Shadow review state, with optional updates
  to Apple Reminders, Calendar, or other private software surfaces when useful.
- Shared Feishu task creation or update is still an external write operation.
  It requires the implemented approval boundary, durable mapping, and Swift-side
  tests before unattended production use.

Coding-task execution policy:

- Local Codex remains the default implementation engine when the task depends on this Mac's local files, Apple APIs, installed apps, browser state, private credentials, or live GUI acceptance.
- GitHub Issues/Copilot/CI should be used when the work benefits from durable team-visible audit trails, reviewable issue specs, CI deployment checks, or remote execution that does not need local Mac state.
- Do not move a task to GitHub only because it is coding work. First decide whether the acceptance path is local and user-private or repo/CI-centered and shareable.
- For hybrid work, create or reference a GitHub Issue for durable tracking, but keep the local Codex working thread as the executor when local acceptance, secrets, or app/browser state are required.

## GitHub Lifecycle Channel

GitHub is a first-class Smart Shadow lifecycle channel, not a polling or MCP-driven side path. The canonical public webhook endpoint is `https://smart-shadow.bozhi.ai/channels/github/webhook`, backed locally by the configured `github.webhook.host`, `port`, and `path`.

`githubd` accepts GitHub repository webhook events, verifies `X-Hub-Signature-256` with `SMART_SHADOW_GITHUB_WEBHOOK_SECRET`, validates the repository and event allowlists, normalizes the payload into the same `ShadowMessage` routing shape used by Feishu, and sends eligible tasks through the Smart Shadow dispatcher.

GitHub routing rules:

- Subscribe to `issues`, `issue_comment`, `pull_request`, `pull_request_review`, `pull_request_review_comment`, `workflow_run`, and `workflow_job`.
- Smart Shadow handles GitHub lifecycle flow only for `longbiaochen/smart-shadow`. `longbiaochen/life-os` is a board/project surface and must not become a webhook execution flow.
- Route only intentional tasks: labels `codex`, `smart-shadow`, or `agent`; mentions `@codex`, `口袋`, `口袋子`, or `Smart Shadow`.
- Use `github:<owner>/<repo>:issue:<number>` or `github:<owner>/<repo>:pull:<number>` as the conversation key.
- Deduplicate by GitHub delivery id and object-level message ids before dispatch.

GitHub writeback rules:

- Acknowledge accepted tasks in the originating issue or PR with a JSON `doing` status comment and `doing` label.
- Write final results back to the same issue or PR with a result summary plus JSON status block.
- Use labels such as `ready-for-review`, `waiting-user`, `blocked`, or `done` to mirror channel state.
- Do not automatically close issues, merge PRs, push branches, edit Project priority/order, or perform destructive GitHub mutations without explicit approval.

GitHub CLI and GitHub MCP are supporting read/write tools. They are not the event bus. Polling may be used only for audit recovery or operations diagnostics; the user-facing GitHub channel path is webhook-first.

## Mail Issue Channel

Mail is a first-class external Issue channel, not merely a reminder source. A single email message or mail thread usually represents one matter; Smart Shadow should treat user-selected mail as an issue-oriented flow item that can be attached to an existing Project or used to create a new Project / Issue.

Mail intake rules:

- Accept mail only after an explicit user operation: flagging, marking, forwarding/sharing to Smart Shadow, selecting it in a review surface, or submitting a confirmed `project-mail-decision` payload.
- Normalize each accepted message/thread into an external issue candidate with source key, sender, subject, received time, message/thread identifiers, compact summary, requested outcome, risk level, and any deadlines.
- Resolve Project membership through the Smart Shadow board, explicit user choice, or configured rules. Do not assume the mailbox, sender, or subject alone defines the Project.
- Keep the original Mail thread as the external communication surface. Smart Shadow owns the internal Issue identity, Project membership, projection mappings, and execution state.
- User-visible follow-up may project to Reminders, Calendar, Finder project files, Notes knowledge entries, GitHub issues, or Feishu documents according to the Project context.

Mail mutation rules:

- Reading/summarizing selected mail for triage is not the same as permission to mutate Mail.app.
- Replies, forwards, archives, deletes, mailbox moves, unsubscribe responses, and external commitments require the implemented approval boundary and post-response verification.
- Do not create Feishu tasks or shared work artifacts from mail unless the user explicitly approves that target surface.
- Failed or unverifiable Mail mutations must close as explicit zero-response or dry-run reports, not as assumed success.

### Life OS Project Reconciler

`shadowd` is the Swift-native reconciler for the Life OS GitHub Project when a
Project / Issue has a repo-centered execution or collaboration projection. It
uses GitHub Issue / Project / PR state as the external code-collaboration record
and must not treat local SQLite state as an authoritative user task database.

Minimum commands:

```sh
bin/shadowd once --dry-run
bin/shadowd once
bin/shadowd run
bin/shadowd inspect-issue --issue 123
```

Reconcile rules:

- Inspect the whole Life OS Project; do not require `smartshadow` or
  `SmartShadow` labels.
- Treat Smart Shadow-created issues/comments as already-confirmed text intent.
  The iOS/macOS front end owns local audio capture, ChatType transcription,
  polish, and user confirmation before GitHub submission.
- Never upload, fetch, store, or transcribe raw audio in `shadowd`. If a legacy
  issue still contains `audio_path`, raw transcript formatting, or a `voice`
  packet marker, classify it as legacy intake and ask for a final text task
  rather than starting ASR.
- Ordinary issues and Smart Shadow issues are reconciled from GitHub text state,
  labels, Project fields, comments, and linked PRs.
- If custom status is `完成` but Project `Status` is not done, plan Project
  Status alignment.
- If required task-template sections are missing, append a clarification
  question instead of starting implementation.
- If GitHub state already matches the desired state, no-op.
- GitHub writes are gated. `bin/shadowd once` and `bin/shadowd run` compute the
  plan by default; comments require explicit `--write-comments`.

Local state policy:

- Logs, audit JSONL, dry-run reports, and bounded caches are allowed.
- Local task databases such as `agent_tasks` are not allowed for `shadowd`
  lifecycle decisions.
- `gh`, GitHub MCP, and GraphQL are supporting access paths; GitHub remains the
  durable state surface.

PR policy:

- Create Draft PRs only for reviewable code, config, or documentation changes.
- Use `Related to #123` for partial PRs.
- Use `Fixes #123`, `Closes #123`, or `Resolves #123` only when the PR fully satisfies the issue acceptance criteria.
- Do not use PRs as routine progress logs; use issue comments only at meaningful lifecycle events.

## Cross-App Sync Rule

ShadowD workflows follow the bridge order:

```text
intent surface -> shadowd sensing/context -> Codex Project thread/response -> shadowd origin-channel feedback
```

GitHub, Feishu, Mail, browser, ChatGPT, WeChat, Twitter, Xiaohongshu, Zhihu,
Finder, Calendar, Reminders, Notes, Contacts, Photos, Music, and similar systems
can be intent surfaces, context sources, response tools, collaboration surfaces,
or feedback surfaces. Codex is the decision brain and `shadowd` is the sensing
and response bridge, so workflow implementations must not turn any single native
app, source adapter, or external system into the canonical task system.

Project and Issue data may be projected to Reminders, Notes, Calendar, Finder, GitHub, Feishu, Contacts, Photos, Music, and other native or external surfaces. These projections must never become separate unmanaged copies of the same work.

Before any workflow updates, completes, moves, deletes, deduplicates, or recreates a projected object, it must resolve the Smart Shadow internal Project/Issue identity and the stored projection mapping for that target surface. If the mapping is missing, ambiguous, stale, or conflicts with user-visible state, the workflow must stop at a dry-run repair plan or explicit user confirmation.

Title, body, date, sender, URL, file path, or asset name matching can help generate a proposed repair, but it is not enough authority for mutation. This rule is a functional safety constraint for every source adapter, native-app projection, external-system sync, and cleanup job.

Long term, user-facing workflows should start in Smart Shadow even when the final surface is an Apple native app. For example, creating a project reminder, opening a project folder, attaching a calendar block, linking a knowledge note, or collecting media assets should go through Smart Shadow commands or UI so the internal identity and projection mapping are created or verified at the same time.

Manual edits made directly in Reminders, Notes, Calendar, Finder, Contacts, Photos, Music, GitHub, or Feishu are valid user input, but they must be treated as external drift until Smart Shadow reconciles them. Sync jobs may report drift, propose repairs, or ask for confirmation; they must not silently reinterpret direct edits as authoritative mapping changes.

## Workflow Rule Refinement

Smart Shadow is the durable place where the user and Codex define and refine workflow rules. Normal conversations may produce new rules, but those rules only become durable after they are captured in one of these formal surfaces:

- [AGENTS.md](../AGENTS.md) for implementation constraints that should govern future agents in this repository.
- [docs/WORKFLOW.md](WORKFLOW.md) for Feishu routing, skill publishing, daily maintenance, and verification policy.
- [skills/smart-shadow/SKILL.md](../skills/smart-shadow/SKILL.md) for the publishable Smart Shadow or SmartShader skill behavior.
- Source code, config, or tests when the rule is executable behavior rather than only policy.

Rules should include scope, trigger, default behavior, approval boundary, and verification expectation. Do not rely on one-off chat history as the source of truth.

## Skill Publishing

Smart Shadow / SmartShader skill updates are derived from accepted workflow rules. The publishable skill source is [skills/smart-shadow/SKILL.md](../skills/smart-shadow/SKILL.md). The repo-local active copy under [.agents/skills/smart-shadow/SKILL.md](../.agents/skills/smart-shadow/SKILL.md) should be kept aligned when the local development environment needs to exercise the new behavior before publication.

Publishing is a guarded workflow:

1. Extract newly accepted rules from the day's Smart Shadow work.
2. Produce a proposed skill diff and a concise changelog.
3. Run local checks for syntax, routing prompt tests, and relevant shadowd tests.
4. Request approval before external side effects.
5. After approval, push the repository changes to GitHub.
6. Draft an X post from the approved changelog.
7. Post to X only after the post text is approved and the supported X posting workflow can verify the created `/status/` URL.

No API keys, cookies, private message content, Feishu identifiers, personal data, or credentials may be included in skill text, changelogs, GitHub-visible artifacts, or X posts.

## Nightly Maintenance Timer

The desired nightly workflow is a timer-driven maintenance pass that extracts the day's newly established rules into the Smart Shadow / SmartShader skill and prepares publication. It should be implemented as a separate user-level launchd job only after the dry-run workflow is proven.

Proposed label: `me.longbiaochen.smart-shadow-skill-nightly`.

Proposed phases:

- `collect`: read only repo-local accepted rule changes, durable docs, and today's Smart Shadow workflow evidence.
- `draft`: generate a skill/documentation patch and a changelog in an ignored runtime path.
- `verify`: run `pnpm test:shadowd`, `pnpm typecheck:shadowd`, and any narrow CLI validation affected by the change.
- `approval`: stop before `git push` or X posting unless approval exists for that exact change set and post text.
- `publish`: push to GitHub only after approval.
- `announce`: post to X only after approval and verify the live post URL through the supported browser surface.

Acceptance criteria before installing the timer:

- A dry-run command can produce a proposed patch, changelog, and X draft without mutating external systems.
- The generated diff is limited to approved workflow/spec/skill surfaces.
- Failures leave an audit report under `var/` and do not push, post, delete, or overwrite user data.
- The launchd plist has explicit logs, a stop path, and a documented status check.
- External publication and posting remain approval-gated.

## Testing Policy

Local development does not require a full Feishu-to-Codex-to-GitHub-to-X closed loop on every change. Local verification should run the narrow tests and type checks that cover the changed behavior.

Closed-loop tests are reserved for deliberate acceptance passes. When available, use a remote Codex environment such as Janus for full-loop testing so local development remains fast and low risk. A closed-loop run must still preserve the approval boundaries for Feishu writes, GitHub pushes, and X posting.
