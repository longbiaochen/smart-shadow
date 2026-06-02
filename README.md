# Smart Shadow

Smart Shadow is a Swift-native macOS assistant core. It ingests local signals, applies an auditable rule registry, prepares review work, and projects important items into Apple Reminders and Apple Calendar through EventKit.

The project is intentionally local-first: runtime state, audit logs, reports, and personal source data stay under ignored local paths. The public repository contains the core, rules, examples, and documentation.

## Architecture

```mermaid
flowchart LR
    subgraph Sources["Sensing sources"]
        Inbox["JSON event inbox"]
        Files["File metadata"]
        Lark["Local command summaries"]
        Bookmarks["Browser bookmark metadata"]
        RemindersIn["EventKit Reminders read"]
        Mail["Local mail summary JSON"]
    end

    subgraph Core["Swift Mac Core"]
        Ingest["Ingest and dedupe"]
        Rules["Rule registry"]
        Decide["Domain, priority, risk, action"]
        Project["Projection engine"]
        Execute["Approved local executors"]
    end

    subgraph Apple["Apple work panel"]
        R["Reminders: review and action"]
        C["Calendar: time blocks and milestones"]
    end

    subgraph Evidence["Local evidence"]
        DB["SQLite state"]
        Audit["Audit JSONL"]
        Reports["Operator reports"]
        Feedback["Rule feedback ledger"]
    end

    Launchd["launchd service"] --> Core
    Sources --> Ingest
    Ingest --> Rules --> Decide --> Project
    Decide --> Execute
    Project -->|EventKit| R
    Project -->|EventKit| C
    Ingest --> DB
    Decide --> DB
    Project --> Audit
    Execute --> Audit
    Audit --> Reports
    Feedback --> Reports
```

## Quick Start

Requirements:

- macOS 14 or newer
- Swift 6 toolchain
- EventKit permissions for real Calendar or Reminders writes

```sh
cp config/smart-shadow.example.json config/smart-shadow.json
swift build
bin/smart-shadow init
bin/smart-shadow validate-rules
bin/smart-shadow sample-event
bin/smart-shadow run-once --dry-run --no-reminders
bin/smart-shadow health
```

The dry run does not write to Apple Reminders or Apple Calendar. For real EventKit writes, request permission in the foreground first:

```sh
bin/smart-shadow eventkit-request-access all
```

## Current Verified Slice

- SwiftPM executable: `smart-shadow-mac-core`
- Optional SwiftUI menu-bar executable: `smart-shadow-menu`
- User-level launchd service support
- JSON event inbox processing
- Source acceptance previews before enabling daemon sensing
- Rule registry validation and rule feedback ledger
- SQLite state, audit JSONL, and reports under ignored `var/`
- Apple Reminders review-card creation through EventKit
- Calendar/Reminders projection mapping to avoid unrelated duplicates
- Source diagnostics through `source-doctor`, including Mail.app-backed intake before enabling daemon sensing
- LaunchAgent/runtime diagnostics through `service-status`

## Common Commands

```sh
bin/smart-shadow sources
bin/smart-shadow source-doctor
bin/smart-shadow accept-source file_metadata
bin/smart-shadow accept-source chrome_bookmarks
bin/smart-shadow accept-source apple_reminders_inbox
bin/smart-shadow accept-source apple_mail_summary
bin/smart-shadow accept-source apple_mail_app
bin/smart-shadow enable-source chrome_bookmarks
bin/smart-shadow disable-source chrome_bookmarks
bin/smart-shadow run-once
bin/smart-shadow run-once --dry-run --no-reminders
bin/smart-shadow service-status
bin/smart-shadow report
bin/smart-shadow rule-feedback
bin/smart-shadow install-launchd
bin/smart-shadow start
bin/smart-shadow stop
script/build_and_run.sh --verify
```

`enable-source` requires a latest `ok` acceptance report unless `--force` is used. EventKit-backed Reminders sensing also requires official Reminders authorization. `apple_mail_app` uses a configured Mail.app reader for real mail intake; acceptance previews decisions without mutating Mail.app, while non-dry-run processing may call configured executors such as low-value archive.

## Menu Bar Status Panel

`smart-shadow-menu` is a SwiftUI menu-bar control panel for the local daemon. It does not replace the `me.longbiaochen.smart-shadow` LaunchAgent and does not write directly to Calendar, Reminders, source configs, or app databases. The panel reads `service-status` and `health`, then offers only safe controls: refresh, start, stop, report, open project, and open logs.

Run it with:

```sh
./script/build_and_run.sh
```

The script builds `smart-shadow-menu`, stages `dist/SmartShadowMenu.app`, and launches it as an `LSUIElement` menu-bar app without a Dock icon.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Operations](docs/OPERATIONS.md)
- [Security](docs/SECURITY.md)
- [Roadmap](docs/ROADMAP.md)
- [Agent implementation rules](AGENTS.md)

## Verification

```sh
swift build --scratch-path "$PWD/.build" --cache-path "$PWD/.build/swiftpm-cache" --manifest-cache local
bin/smart-shadow-test
bin/smart-shadow --config config/smart-shadow.example.json validate-rules
```

The regression suite covers source enablement gates, EventKit authorization gates, source readiness diagnostics, and service status reporting.
