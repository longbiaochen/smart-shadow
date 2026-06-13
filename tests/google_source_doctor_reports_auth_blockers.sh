#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events"

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
    "google_calendar_events": { "enabled": false },
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

"$ROOT/bin/smart-shadow" --config "$CONFIG" source-doctor > "$TMP_DIR/doctor.json"

for source in google_calendar_events google_tasks google_contacts; do
  if ! rg -Fq "\"name\" : \"$source\"" "$TMP_DIR/doctor.json"; then
    echo "expected source-doctor item for $source"
    cat "$TMP_DIR/doctor.json"
    exit 1
  fi
done

if ! rg -Fq '"google_oauth_client_id_missing"' "$TMP_DIR/doctor.json"; then
  echo "expected missing Google OAuth client id blocker"
  cat "$TMP_DIR/doctor.json"
  exit 1
fi

if ! rg -Fq '"google_auth_missing"' "$TMP_DIR/doctor.json"; then
  echo "expected missing Google auth blocker"
  cat "$TMP_DIR/doctor.json"
  exit 1
fi

if ! rg -q '"suggested_command"[[:space:]]*:[[:space:]]*"bin\\?/smart-shadow google-auth login"' "$TMP_DIR/doctor.json"; then
  echo "expected Google auth suggested command"
  cat "$TMP_DIR/doctor.json"
  exit 1
fi
