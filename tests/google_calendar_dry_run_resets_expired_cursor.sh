#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events"

MOCK="$TMP_DIR/google-mock.json"
cat > "$MOCK" <<'JSON'
{
  "calendarLists": [
    { "id": "primary", "summary": "Primary" }
  ],
  "calendarEvents": {
    "primary": {
      "items": [
        {
          "id": "evt_001",
          "status": "cancelled",
          "summary": "Cancelled item",
          "start": { "dateTime": "2026-06-04T09:00:00+08:00" },
          "end": { "dateTime": "2026-06-04T09:30:00+08:00" }
        }
      ],
      "nextSyncToken": "calendar-token-after-reset"
    }
  }
}
JSON

CONFIG="$TMP_DIR/config/smart-shadow.json"
cat > "$CONFIG" <<EOF
{
  "project_root": "$ROOT",
  "runtime_root": "$TMP_DIR/var",
  "rules_file": "$ROOT/config/rules.json",
  "poll_seconds": 10,
  "sources": {
    "event_inbox": "$TMP_DIR/var/inbox/events",
    "file_metadata": { "enabled": false },
    "lark_daily_context": { "enabled": false },
    "lark_calendar_events": { "enabled": false },
    "lark_tasks": { "enabled": false },
    "google_calendar_events": {
      "enabled": true,
      "mock_file": "$MOCK",
      "calendar_ids": ["primary"],
      "max_items": 10
    },
    "google_tasks": { "enabled": false },
    "google_contacts": { "enabled": false },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": { "enabled": false }
  },
  "reminders": { "enabled": true },
  "actions": {
    "auto_create_review_reminders": true,
    "auto_archive_low_value": true
  }
}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" health > /dev/null
/usr/bin/sqlite3 "$TMP_DIR/var/state.sqlite" \
  "insert into sync_cursors (source, google_collection_id, cursor_type, cursor_value, updated_at) values ('google_calendar_events', 'primary', 'syncToken', 'force-410', '2026-06-03T00:00:00Z');"

"$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --dry-run > "$TMP_DIR/run.json"

if ! rg -Fq '"cursor_reset" : true' "$TMP_DIR/run.json"; then
  echo "expected dry-run to report cursor reset"
  cat "$TMP_DIR/run.json"
  exit 1
fi

remaining="$(/usr/bin/sqlite3 "$TMP_DIR/var/state.sqlite" "select count(*) from sync_cursors where source='google_calendar_events' and google_collection_id='primary' and cursor_type='syncToken';")"
if [[ "$remaining" != "0" ]]; then
  echo "expected expired sync cursor to be cleared"
  /usr/bin/sqlite3 "$TMP_DIR/var/state.sqlite" "select * from sync_cursors;"
  exit 1
fi

if ! rg -Fq '"skipped" : 1' "$TMP_DIR/run.json"; then
  echo "expected unmapped cancelled Google event to be skipped"
  cat "$TMP_DIR/run.json"
  exit 1
fi
