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
  "reminders": {
    "enabled": true,
    "domain_lists": {
      "money": "MONEY",
      "health": "HEALTH",
      "relationship": "NETWORK",
      "work": "WORK"
    }
  },
  "actions": {
    "auto_create_review_reminders": true,
    "auto_archive_low_value": true
  },
  "sources": {
    "event_inbox": "$TMP_DIR/var/inbox/events",
    "file_metadata": { "enabled": false },
    "lark_daily_context": { "enabled": false },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": {
      "backend": "eventkit",
      "enabled": false,
      "list": "Inbox",
      "max_items": 10
    }
  }
}
EOF

set +e
"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source apple_reminders_inbox --limit 1 > "$TMP_DIR/out.txt" 2> "$TMP_DIR/err.txt"
STATUS=$?
set -e

if rg -q "Unsupported source: apple_reminders_inbox" "$TMP_DIR/err.txt"; then
  echo "expected apple_reminders_inbox to be a supported Swift/EventKit acceptance source"
  cat "$TMP_DIR/err.txt"
  exit 1
fi

if [[ "$STATUS" -ne 0 ]]; then
  if rg -q "EventKit reminders access is" "$TMP_DIR/err.txt"; then
    exit 0
  fi
  echo "expected success or an EventKit authorization gate"
  cat "$TMP_DIR/err.txt"
  exit 1
fi

if ! rg -q '"source"[[:space:]]*:[[:space:]]*"apple_reminders_inbox"' "$TMP_DIR/out.txt"; then
  echo "expected acceptance output for apple_reminders_inbox"
  cat "$TMP_DIR/out.txt"
  exit 1
fi

if ! rg -q "感知源：apple_reminders_inbox" "$TMP_DIR/var/reports"/source-acceptance-apple_reminders_inbox-*.md; then
  echo "expected a source acceptance report"
  find "$TMP_DIR/var/reports" -type f -maxdepth 1 -print
  exit 1
fi
