# Operations

## Setup

```sh
cp config/smart-shadow.example.json config/smart-shadow.json
swift build
bin/smart-shadow init
bin/smart-shadow validate-rules
```

`config/smart-shadow.json` is local operator configuration. Keep personal paths, enabled source choices, and runtime settings out of public commits.

## Foreground Checks

```sh
bin/smart-shadow source-doctor
bin/smart-shadow service-status
bin/smart-shadow health
bin/smart-shadow report
```

`source-doctor` explains which sources are ready and which gates are blocking them. `service-status` summarizes launchd state, runtime paths, log paths, latest report freshness, audit status, EventKit status, and suggested actions.

## Source Acceptance

Run acceptance before enabling daemon sensing:

```sh
bin/smart-shadow accept-source file_metadata
bin/smart-shadow accept-source lark_calendar_events
bin/smart-shadow accept-source lark_tasks
bin/smart-shadow accept-source google_calendar_events
bin/smart-shadow accept-source google_tasks
bin/smart-shadow accept-source google_contacts
bin/smart-shadow accept-source chrome_bookmarks
bin/smart-shadow accept-source apple_reminders_inbox
bin/smart-shadow accept-source apple_mail_summary
bin/smart-shadow enable-source chrome_bookmarks
```

`enable-source` requires the latest acceptance report for that source to be `ok` unless `--force` is used. EventKit-backed sources also require official macOS authorization.

`lark_calendar_events` and `lark_tasks` also require a working local `lark-cli` user login with calendar/task read permission. These are read-only sensing sources. Mail processing does not need Lark task write permission, because mail decisions must not create or update Lark tasks.

For team work mail routing, Codex Automation must submit `projection_target=apple_reminder`, `action=create_review_reminder`, and `domain=work`. Smart Shadow projects the item to the Apple Reminders `WORK` list and only uses Apple Calendar when the payload contains a real scheduled time block.

Project a Codex Automation mail decision into the board system:

```sh
bin/smart-shadow project-mail-decision --input tests/fixtures/mail-decision-work.json --dry-run
```

Google sources use Google REST APIs directly and do not use macOS Internet Accounts. Configure `google.oauth_client_id`, then run:

```sh
bin/smart-shadow google-auth login
bin/smart-shadow google-auth status
bin/smart-shadow contacts-request-access
bin/smart-shadow eventkit-request-access all
```

Tokens are stored in macOS Keychain under the Smart Shadow Google OAuth service. `google_calendar_events`, `google_tasks`, and `google_contacts` are one-way strict mirrors into Apple Calendar, Reminders, and Contacts; only objects with Smart Shadow `sync_mappings` may be deleted during mirror cleanup. Gmail/Mail is intentionally not connected in this version.

## EventKit Permissions

```sh
bin/smart-shadow eventkit-status
bin/smart-shadow eventkit-request-access all
bin/smart-shadow eventkit-list
```

Request access from a foreground terminal so macOS can show the permission prompt. Real Reminders and Calendar writes should not be tested through direct database writes.

Plan Reminder quadrant placement without mutating Reminders:

```sh
bin/smart-shadow reminders-plan-quadrants --dry-run
```

This command reads configured `MONEY`, `HEALTH`, `NETWORK`, and `WORK` lists through EventKit and returns suggested `IMPORTANT`, `URGENT`, `DOING`, or `TODO` sections. It does not create native Reminders sections, move items into sections, edit titles, or write notes.

Inspect the private Reminders stores read-only when diagnosing section/list drift:

```sh
bin/smart-shadow reminders-db-doctor
```

`reminders-db-doctor` opens SQLite stores with `SQLITE_OPEN_READONLY` and reports section/list/reminder table availability and counts. It must not be used as a write path.

Contacts access is separate:

```sh
bin/smart-shadow contacts-status
bin/smart-shadow contacts-request-access
```

## launchd Lifecycle

```sh
bin/smart-shadow install-launchd
bin/smart-shadow start
bin/smart-shadow stop
bin/smart-shadow service-status
```

The checked-in plist template uses placeholders. `install-launchd` generates the concrete user LaunchAgent with the current project path, executable path, config path, watch path, and log paths.

## Nightly Skill Maintenance

The nightly Smart Shadow / SmartShader skill-maintenance timer is specified but not installed yet. Its intended label is `me.longbiaochen.smart-shadow-skill-nightly`.

Before installing it, implement and verify a dry-run command that:

- extracts only accepted workflow rules from Smart Shadow's durable rule surfaces and same-day workflow evidence;
- drafts a skill/docs patch, changelog, and X post text under ignored `var/` paths;
- runs `pnpm test:shadowd`, `pnpm typecheck:shadowd`, and any narrow CLI validation affected by the draft;
- stops before `git push`, Feishu writes, or X posting unless the exact diff and post text have explicit approval.

The timer must have explicit logs, status checks, a stop path, and failure reports under `var/`. Full closed-loop acceptance should run in a remote Codex environment such as Janus when available, not as a required step for every local development change.

## Testing

```sh
swift build --scratch-path "$PWD/.build" --cache-path "$PWD/.build/swiftpm-cache" --manifest-cache local
bin/smart-shadow-test
bin/smart-shadow --config config/smart-shadow.example.json validate-rules
```

The test runner builds the Swift executable and runs command-level shell regressions for source gates, EventKit authorization behavior, diagnostics, and service status.

## Menu Bar App

```sh
script/build_and_run.sh --verify
script/build_and_run.sh
```

The menu app can use `SMART_SHADOW_PROJECT_ROOT` when launched outside the repository checkout.
