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
    "chrome_bookmarks": { "enabled": false }
  }
}
EOF

cat > "$TMP_DIR/var/reports/source-acceptance-chrome_bookmarks-2099-01-01T000000Z.md" <<'EOF'
# 感知源验收报告

生成时间：2099-01-01T00:00:00Z
感知源：chrome_bookmarks
状态：error
采集数量：0
需审核数量：0
EOF

set +e
"$ROOT/bin/smart-shadow" --config "$CONFIG" enable-source chrome_bookmarks > "$TMP_DIR/out.txt" 2> "$TMP_DIR/err.txt"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected enable-source to reject a failed latest acceptance report"
  cat "$TMP_DIR/out.txt"
  exit 1
fi

if ! rg -q "acceptance report.*not ok|状态.*error|not ok" "$TMP_DIR/err.txt"; then
  echo "expected error to explain the failed acceptance report"
  cat "$TMP_DIR/err.txt"
  exit 1
fi

if ! rg -q '"enabled"[[:space:]]*:[[:space:]]*false' "$CONFIG"; then
  echo "expected source to remain disabled"
  cat "$CONFIG"
  exit 1
fi
