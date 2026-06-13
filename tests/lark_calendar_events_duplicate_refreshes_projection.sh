#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/config" "$TMP_DIR/var/inbox/events"

cat > "$TMP_DIR/bin/lark-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "lark-cli version test"
  exit 0
fi
python3 - <<'PY'
import json
import os
import sys

payload = {
    "items": [
        {
            "event_id": "evt_refresh",
            "summary": "重复同步投影刷新",
            "start_time": "2026-06-03T10:00:00+08:00",
            "end_time": "2026-06-03T10:30:00+08:00",
            "url": "https://applink.feishu.cn/calendar/event/evt_refresh",
            "description": "第二次同步也要刷新 Calendar 字段。",
        }
    ]
}
print(json.dumps(payload, ensure_ascii=False))
PY
EOF
chmod +x "$TMP_DIR/bin/lark-cli"

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
      "enabled": true,
      "argv": ["lark-cli", "calendar", "+agenda", "--as", "user", "--format", "json", "--start", "2026-06-03T00:00:00+08:00", "--end", "2026-06-04T00:00:00+08:00"],
      "primary_calendar_summary": "应酬",
      "timeout_seconds": 5,
      "max_items": 10
    },
    "lark_tasks": { "enabled": false },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": { "enabled": false }
  }
}
EOF

PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --dry-run > "$TMP_DIR/first.json"
python3 - "$CONFIG" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    config = json.load(handle)
config["sources"]["lark_calendar_events"]["source_calendar_domains"] = {"应酬": "relationship"}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, ensure_ascii=False, indent=2)
PY
PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --dry-run > "$TMP_DIR/second.json"

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"refreshed_duplicate"' "$TMP_DIR/second.json"; then
  echo "expected duplicate Lark calendar signal to refresh its projection"
  cat "$TMP_DIR/second.json"
  exit 1
fi

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"dry_run"' "$TMP_DIR/second.json"; then
  echo "expected duplicate projection refresh to execute through dry-run action"
  cat "$TMP_DIR/second.json"
  exit 1
fi

if ! rg -q '"domain"[[:space:]]*:[[:space:]]*"relationship"' "$TMP_DIR/second.json"; then
  echo "expected duplicate refresh to use current source calendar domain"
  cat "$TMP_DIR/second.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" health > "$TMP_DIR/health.json"
python3 - "$TMP_DIR/health.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
counts = payload["counts"]
if counts["signals"] != 1 or counts["decisions"] != 1 or counts["actions"] != 1 or counts["pending_actions"] != 0:
    raise SystemExit(f"expected duplicate refresh to avoid growing history tables, got {counts}")
PY
