#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/empty-bin" "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events"

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
    "lark_calendar_events": {
      "enabled": false,
      "argv": ["lark-cli", "calendar", "+agenda", "--as", "user", "--format", "json"]
    },
    "lark_tasks": {
      "enabled": false,
      "argv": ["lark-cli", "task", "+get-my-tasks", "--as", "user", "--complete=false", "--page-all", "--format", "json"]
    },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": { "enabled": false }
  }
}
EOF

cat > "$TMP_DIR/var/reports/source-acceptance-lark_calendar_events-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

感知源：lark_calendar_events
状态：ok
EOF

cat > "$TMP_DIR/var/reports/source-acceptance-lark_tasks-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

感知源：lark_tasks
状态：ok
EOF

PATH="$TMP_DIR/empty-bin:/usr/bin:/bin" "$ROOT/bin/smart-shadow" --config "$CONFIG" source-doctor > "$TMP_DIR/out.json"

if ! rg -q '"name"[[:space:]]*:[[:space:]]*"lark_calendar_events"' "$TMP_DIR/out.json"; then
  echo "expected lark calendar source in source doctor"
  cat "$TMP_DIR/out.json"
  exit 1
fi

if ! rg -q '"lark_cli_missing"' "$TMP_DIR/out.json"; then
  echo "expected lark_cli_missing blocker"
  cat "$TMP_DIR/out.json"
  exit 1
fi
