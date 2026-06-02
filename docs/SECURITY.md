# Security and Privacy

Smart Shadow is local-first. The repository is public, but runtime state and personal data are not project artifacts.

## Public Repository Boundary

Do not commit:

- SQLite state files.
- Audit JSONL logs.
- Run reports or source acceptance reports.
- Generated config backups.
- Local absolute paths that reveal private data locations unless they are clearly placeholders.
- API keys, provider secrets, cookies, browser credentials, payment data, or tokens.

## Local Data Handling

- File sensing is metadata-only unless a future task explicitly expands it.
- Browser bookmark sensing reads bookmark metadata, not page content, history, cookies, or logged-in session data.
- Mail processing has two paths: `apple_mail_summary` for offline replay from local summary JSON, and `apple_mail_app` for configured Mail.app intake/execution. Acceptance previews do not mutate Mail.app; non-dry-run processing may call configured low-risk executors after source enablement.
- Lark sensing runs configured local read-only commands and stores compact summaries; this project does not store Lark credentials.
- Reminders sensing uses Swift + EventKit and requires official authorization.

## Third-Party Models

External model calls must go through an explicit routing layer that records purpose, cost, input type, and privacy level. Private files, photos, chats, and mail bodies must not be bulk uploaded unless the task explicitly requires it and the external-send risk has been stated.

High-risk decisions, code edits, browser verification, security judgments, credential handling, and destructive operations remain under primary Codex/operator control.

## Forbidden Paths

- Do not write directly to Apple Calendar or Reminders databases.
- Do not mutate Mail.app without an enabled Mail.app source, an explicit executor, and an audit entry.
- Do not bypass macOS permissions or app security boundaries.
- Do not automatically perform high-value payments, investments, loans, contracts, or irreversible deletes.
- Do not automatically send relationship-sensitive, legally sensitive, reputation-sensitive, or commitment-bearing outbound messages without the implemented review/authorization semantics.
