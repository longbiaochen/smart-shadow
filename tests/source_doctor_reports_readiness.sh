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

cat > "$TMP_DIR/var/reports/source-acceptance-file_metadata-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

感知源：file_metadata
状态：ok
EOF

cat > "$TMP_DIR/var/reports/source-acceptance-apple_reminders_inbox-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

感知源：apple_reminders_inbox
状态：ok
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" source-doctor > "$TMP_DIR/out.json"

if ! rg -q '"name"[[:space:]]*:[[:space:]]*"file_metadata"' "$TMP_DIR/out.json"; then
  echo "expected file_metadata source in source-doctor output"
  cat "$TMP_DIR/out.json"
  exit 1
fi

if ! rg -q '"ready_to_enable"[[:space:]]*:[[:space:]]*true' "$TMP_DIR/out.json"; then
  echo "expected at least one source ready to enable"
  cat "$TMP_DIR/out.json"
  exit 1
fi

if "$ROOT/bin/smart-shadow" eventkit-status | rg -q '"reminders"[[:space:]]*:[[:space:]]*"not_determined"'; then
  if ! rg -q '"name"[[:space:]]*:[[:space:]]*"apple_reminders_inbox"' "$TMP_DIR/out.json"; then
    echo "expected apple_reminders_inbox source in source-doctor output"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
  if ! rg -q '"eventkit_reminders_not_determined"' "$TMP_DIR/out.json"; then
    echo "expected EventKit Reminders blocker while authorization is not_determined"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
fi
