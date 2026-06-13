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
- Smart Shadow voice entry keeps raw audio local and short-lived. GitHub issues/comments store only the user-confirmed final text task and compact metadata; raw audio must not be uploaded to GitHub, handed to `shadowd`, or sent through a cloud relay.
- Mail sensing and judgment are handled by Codex Automation, not by the Smart Shadow daemon. Smart Shadow accepts only explicit `project-mail-decision` payloads and projects the already-decided outcome to Apple Reminders/Calendar, records it, or executes an explicitly requested low-risk Mail action.
- Lark sensing runs configured local read-only commands and stores compact summaries. Mail decisions must not create Lark tasks because those tasks may be shared with a team. This project does not store Lark credentials.
- Google Calendar, Google Tasks, and Google Contacts sensing uses Google official REST APIs with OAuth tokens stored in macOS Keychain. Gmail/Mail is not connected in the current Google sync path.
- Reminders sensing uses Swift + EventKit and requires official authorization.
- Google strict mirror deletion is limited to Apple Calendar, Reminders, or Contacts objects recorded in local `sync_mappings`; never delete user-created iCloud data by content matching.

## Third-Party Models

External model calls must go through an explicit routing layer that records purpose, cost, input type, and privacy level. Private files, photos, chats, and mail bodies must not be bulk uploaded unless the task explicitly requires it and the external-send risk has been stated.

High-risk decisions, code edits, browser verification, security judgments, credential handling, and destructive operations remain under primary Codex/operator control.

## Forbidden Paths

- Do not write directly to Apple Calendar or Reminders databases.
- Do not use private ReminderKit or Reminders SQLite stores for production writes; read-only diagnostics only.
- Do not fake Reminders sections by adding quadrant prefixes to reminder titles or internal metadata to user-visible notes.
- Do not write directly to Apple Contacts databases.
- Do not mutate Mail.app without an enabled Mail.app source, an explicit executor, and an audit entry.
- Do not store Google OAuth tokens, refresh tokens, cookies, or provider secrets in repository files, reports, logs, or screenshots.
- Do not bypass macOS permissions or app security boundaries.
- Do not automatically perform high-value payments, investments, loans, contracts, or irreversible deletes.
- Do not automatically send relationship-sensitive, legally sensitive, reputation-sensitive, or commitment-bearing outbound messages without the implemented review/authorization semantics.
