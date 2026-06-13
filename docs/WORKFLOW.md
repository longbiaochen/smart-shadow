# Smart Shadow Workflow

This document captures durable workflow rules for the Smart Shadow MVP task
loop, Feishu-originated Codex work, Smart Shadow rule refinement, skill
publishing, and closed-loop verification.

## MVP Task Loop

The PRD-level workflow is iPhone-first:

1. The user speaks a task through the iPhone Shadow Button.
2. The app transcribes, recognizes intent, and creates a structured task card.
3. The user confirms, edits, cancels, re-records, or adds context.
4. Confirmed tracked work is submitted to the unified agent identity `shadow`.
5. GitHub Issue / Comment / PR becomes the durable lifecycle record.
6. Local `shadowd` maps the task to the right project/repo, assigns a Codex
   agent, writes progress comments, and creates PRs only for reviewable code
   changes.
7. The app shows Draft, Submitted, Queued, Running, Need Input, PR Ready, Done,
   Failed, or Cancelled state and lands push notifications on the relevant task.
8. The user confirms completion, requests changes, or creates follow-up work.

Feishu remains an auxiliary or legacy coordination channel. It must not redefine
the MVP product surface as a Feishu workbench.

## Feishu To Codex Routing

Feishu-originated main sessions are created in the Smart Shadow project by default. `shadowd` remains a thin bridge: it consumes Feishu events, starts or resumes the Smart Shadow dispatcher session through Codex AppServer, records routing state, and sends approved replies.

The Smart Shadow dispatcher session does not execute engineering work. It decides whether to reply directly, resume a bound working thread, start a new working thread, ask for clarification, or reject the request. Actual work may still be dispatched to another Codex project when the message clearly belongs elsewhere.

Routing rules:

- Use the Smart Shadow project as the default `mainProjectKey` and dispatcher `cwd`.
- Resume an existing Feishu-to-Codex binding when the binding clearly still matches the Feishu chat/thread.
- Start a working thread in another project only when the task text, existing binding, or known project inventory clearly identifies that project.
- Use Smart Shadow for workflow-rule conversations, Smart Shadow or SmartShader skill changes, Feishu bridge changes, and rule-publication work.
- Ask the user instead of guessing when confidence is below the configured routing threshold.

## Feishu Execution Layer

For each substantive user task received through Feishu, Smart Shadow should keep the Feishu-side coordination surface separate from the Codex working surface:

- `shadowd` performs intake, immediate typing indication, task/topic scaffolding, acknowledgement, routing, and final writeback.
- The Smart Shadow dispatcher thread performs routing only and must not execute the substantive task.
- The working thread executes the task in the routed project `cwd` and returns a Feishu-ready result.

Immediate response state is implemented as a `Typing` reaction on the source Feishu message before dispatcher work begins. The reaction is removed after the final reply path finishes or fails.

Topic/thread handling:

- Prefer replying with Feishu `reply_in_thread=true` for substantive user tasks, so each source message becomes a separate Feishu thread when the current chat supports threaded replies.
- When the reply response returns a `thread_id`, save a registry binding for both the original message key and the returned Feishu thread key. This keeps future replies in the same Feishu topic connected to the same Codex working thread.
- If the incoming event already has a Feishu `thread_id`, treat it as the coordination key and resume the bound Codex thread when appropriate.
- Current Feishu OpenAPI and `lark-cli` expose creating a thread by replying in thread, forwarding threads, listing thread messages, and switching a group to thread-message mode. They do not expose a supported "rename this individual thread/topic title" API. Do not simulate title changes by editing private Feishu state.
- If a stable title is required, derive a concise task title before the first acknowledgement and make the source/root message or first bot thread reply carry that title. For ordinary incoming user messages, Smart Shadow can influence the first bot reply but cannot rename the user's original message title through a supported API.

Feishu task item handling:

- Create Feishu Tasks only for work/collaboration items where a shared Feishu task is appropriate. Personal, health, finance, relationship, security, or private-life tasks default to Apple Reminders/Calendar or internal Smart Shadow review state unless the user explicitly authorizes a shared Feishu task.
- For an approved Feishu task, populate `summary`, `description`, `members` with assignee/follower roles, `due` when a deadline can be extracted, `origin.href` or `extra` with source metadata, and optional custom fields for risk/priority when the target tasklist supports them.
- Use source metadata sparingly: include Feishu `chat_id`, `message_id`, `thread_id`, received time, routed project, and Codex thread id in internal audit or compact task `extra`; do not paste private full message text into shared task descriptions when a concise human summary is enough.
- Task creation and updates are Feishu write operations. They require an explicit approval boundary unless the user has already authorized the exact class of shared write.

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

### Life OS Project Reconciler

`shadowd` is the Swift-native reconciler for the Life OS GitHub Project. It uses
GitHub Issue / Project / PR state as the lifecycle source of truth and must not
store task lifecycle state in a local SQLite table.

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
