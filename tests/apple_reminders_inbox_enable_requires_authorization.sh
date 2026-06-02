#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_JSON="$("$ROOT/bin/smart-shadow" eventkit-status)"

if ! printf '%s\n' "$STATUS_JSON" | rg -q '"reminders"[[:space:]]*:[[:space:]]*"not_determined"'; then
  exit 0
fi

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

cat > "$TMP_DIR/var/reports/source-acceptance-apple_reminders_inbox-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

生成时间：2099-01-01T00:00:00Z
感知源：apple_reminders_inbox
状态：ok
采集数量：0
需审核数量：0
EOF

set +e
"$ROOT/bin/smart-shadow" --config "$CONFIG" enable-source apple_reminders_inbox > "$TMP_DIR/out.txt" 2> "$TMP_DIR/err.txt"
RESULT=$?
set -e

if [[ "$RESULT" -eq 0 ]]; then
  echo "expected enable-source apple_reminders_inbox to require current EventKit Reminders authorization"
  cat "$TMP_DIR/out.txt"
  exit 1
fi

if ! rg -q "EventKit reminders access is not_determined" "$TMP_DIR/err.txt"; then
  echo "expected an explicit EventKit reminders authorization error"
  cat "$TMP_DIR/err.txt"
  exit 1
fi

if ! rg -q '"enabled"[[:space:]]*:[[:space:]]*false' "$CONFIG"; then
  echo "expected apple_reminders_inbox to remain disabled"
  cat "$CONFIG"
  exit 1
fi
