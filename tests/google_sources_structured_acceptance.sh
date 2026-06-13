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
          "etag": "\"event-etag-1\"",
          "status": "confirmed",
          "summary": "Google planning block",
          "description": "Confirm Smart Shadow calendar fields.",
          "location": "Desk",
          "htmlLink": "https://calendar.google.com/event?eid=evt_001",
          "start": { "dateTime": "2026-06-04T09:00:00+08:00" },
          "end": { "dateTime": "2026-06-04T09:30:00+08:00" }
        }
      ],
      "nextSyncToken": "calendar-token-1"
    }
  },
  "taskLists": [
    { "id": "tasks_001", "title": "Default Tasks" }
  ],
  "tasks": {
    "tasks_001": {
      "items": [
        {
          "id": "task_001",
          "etag": "\"task-etag-1\"",
          "title": "Finish Google Tasks sync",
          "notes": "Task notes stay in Apple Reminders notes.",
          "status": "needsAction",
          "due": "2026-06-05T00:00:00.000Z"
        },
        {
          "id": "task_002",
          "title": "Completed mirror item",
          "status": "completed",
          "completed": "2026-06-03T08:00:00.000Z"
        }
      ]
    }
  },
  "connections": {
    "connections": [
      {
        "resourceName": "people/c001",
        "etag": "\"contact-etag-1\"",
        "names": [
          { "displayName": "Ada Lovelace", "givenName": "Ada", "familyName": "Lovelace" }
        ],
        "emailAddresses": [
          { "value": "ada@example.com", "type": "work" }
        ],
        "phoneNumbers": [
          { "value": "+1 555 0100", "type": "mobile" }
        ],
        "organizations": [
          { "name": "Analytical Engines", "title": "Founder" }
        ]
      }
    ],
    "nextSyncToken": "people-token-1"
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
      "enabled": false,
      "mock_file": "$MOCK",
      "calendar_ids": ["primary"],
      "max_items": 10
    },
    "google_tasks": {
      "enabled": false,
      "mock_file": "$MOCK",
      "task_list_ids": ["tasks_001"],
      "max_items": 10
    },
    "google_contacts": {
      "enabled": false,
      "mock_file": "$MOCK",
      "max_items": 10
    },
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

"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source google_calendar_events --limit 10 > "$TMP_DIR/calendar.json"
"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source google_tasks --limit 10 > "$TMP_DIR/tasks.json"
"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source google_contacts --limit 10 > "$TMP_DIR/contacts.json"

if ! rg -Fq '"source" : "google_calendar_events"' "$TMP_DIR/calendar.json"; then
  echo "expected google_calendar_events acceptance"
  cat "$TMP_DIR/calendar.json"
  exit 1
fi

if ! rg -Fq '"calendar_start" : "2026-06-04T01:00:00Z"' "$TMP_DIR/calendar.json"; then
  echo "expected normalized calendar start metadata"
  cat "$TMP_DIR/calendar.json"
  exit 1
fi

if ! rg -Fq '"projection_target" : "calendar"' "$TMP_DIR/calendar.json"; then
  echo "expected calendar projection target"
  cat "$TMP_DIR/calendar.json"
  exit 1
fi

if ! rg -Fq '"projection_target" : "reminder"' "$TMP_DIR/tasks.json"; then
  echo "expected task projection target"
  cat "$TMP_DIR/tasks.json"
  exit 1
fi

if ! rg -Fq '"status" : "completed"' "$TMP_DIR/tasks.json"; then
  echo "expected completed task status in preview"
  cat "$TMP_DIR/tasks.json"
  exit 1
fi

if ! rg -Fq '"projection_target" : "contact"' "$TMP_DIR/contacts.json"; then
  echo "expected contact projection target"
  cat "$TMP_DIR/contacts.json"
  exit 1
fi

if rg -Fq 'ada@example.com' "$TMP_DIR/contacts.json"; then
  echo "contact acceptance should not expose email addresses"
  cat "$TMP_DIR/contacts.json"
  exit 1
fi

if [[ -f "$TMP_DIR/var/state.sqlite" ]]; then
  echo "accept-source must not create SQLite runtime state"
  exit 1
fi
