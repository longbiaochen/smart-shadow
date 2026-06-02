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
bin/smart-shadow accept-source chrome_bookmarks
bin/smart-shadow accept-source apple_reminders_inbox
bin/smart-shadow accept-source apple_mail_summary
bin/smart-shadow accept-source apple_mail_app
bin/smart-shadow enable-source chrome_bookmarks
```

`enable-source` requires the latest acceptance report for that source to be `ok` unless `--force` is used. EventKit-backed sources also require official macOS authorization.

## EventKit Permissions

```sh
bin/smart-shadow eventkit-status
bin/smart-shadow eventkit-request-access all
bin/smart-shadow eventkit-list
```

Request access from a foreground terminal so macOS can show the permission prompt. Real Reminders and Calendar writes should not be tested through direct database writes.

## launchd Lifecycle

```sh
bin/smart-shadow install-launchd
bin/smart-shadow start
bin/smart-shadow stop
bin/smart-shadow service-status
```

The checked-in plist template uses placeholders. `install-launchd` generates the concrete user LaunchAgent with the current project path, executable path, config path, watch path, and log paths.

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
