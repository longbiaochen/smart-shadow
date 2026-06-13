#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events"

cat > "$TMP_DIR/bin/lark-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "lark-cli version test"
  exit 0
fi
cat <<'JSON'
{
  "items": [
    {
      "event_id": "evt_001",
      "summary": "Smart Shadow 飞书同步评审会",
      "start_time": "2026-06-03T10:00:00+08:00",
      "end_time": "2026-06-03T10:30:00+08:00",
      "location": "Zoom",
      "url": "https://applink.feishu.cn/calendar/event/evt_001",
      "description": "会前确认 macOS Calendar 投影字段。",
      "self_rsvp_status": "accepted"
    },
    {
      "event_id": "evt_002",
      "summary": "客户交付里程碑",
      "start_time": "2026-06-04T15:00:00+08:00",
      "end_time": "2026-06-04T16:00:00+08:00",
      "location": "会议室 A"
    }
  ]
}
JSON
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
      "enabled": false,
      "argv": ["lark-cli", "calendar", "+agenda", "--as", "user", "--format", "json", "--start", "2026-06-03T00:00:00+08:00", "--end", "2026-06-05T00:00:00+08:00"],
      "timeout_seconds": 5,
      "window_past_days": 7,
      "window_future_days": 30
    },
    "lark_tasks": { "enabled": false },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": { "enabled": false }
  }
}
EOF

PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source lark_calendar_events --limit 10 > "$TMP_DIR/accept.json"

if ! rg -q '"source"[[:space:]]*:[[:space:]]*"lark_calendar_events"' "$TMP_DIR/accept.json"; then
  echo "expected lark_calendar_events acceptance output"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"collected_count"[[:space:]]*:[[:space:]]*2' "$TMP_DIR/accept.json"; then
  echo "expected two calendar event signals"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"canonical_key"[[:space:]]*:[[:space:]]*"lark:calendar:evt_001"' "$TMP_DIR/accept.json"; then
  echo "expected calendar canonical key"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"calendar_start" : "2026-06-03T10:00:00+08:00"' "$TMP_DIR/accept.json"; then
  echo "expected calendar start metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if rg -Fq '"title" : "飞书日程: Smart Shadow 飞书同步评审会"' "$TMP_DIR/accept.json"; then
  echo "calendar event titles should not include the Lark prefix"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"title" : "Smart Shadow 飞书同步评审会"' "$TMP_DIR/accept.json"; then
  echo "expected clean calendar event title"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"description" : "会前确认 macOS Calendar 投影字段。"' "$TMP_DIR/accept.json"; then
  echo "expected Lark event notes metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! /usr/bin/python3 - "$TMP_DIR/accept.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

items = payload.get("items", [])
body = items[0].get("body") if items else None
sys.exit(0 if body == "会前确认 macOS Calendar 投影字段。" else 1)
PY
then
  echo "expected signal body to contain only Lark event notes"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

for unwanted in "标题:" "开始:" "结束:" "我的 RSVP:" "时间块用途"; do
  if rg -Fq "$unwanted" "$TMP_DIR/accept.json"; then
    echo "expected Lark event notes body to exclude generated field: $unwanted"
    cat "$TMP_DIR/accept.json"
    exit 1
  fi
done

if ! /usr/bin/python3 - "$TMP_DIR/accept.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

items = payload.get("items", [])
if not items:
    sys.exit(1)

sys.exit(0 if items[0].get("metadata", {}).get("url") == "https://applink.feishu.cn/calendar/event/evt_001" else 1)
PY
then
  echo "expected Lark event URL metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if rg -Fq '链接: https://applink.feishu.cn/calendar/event/evt_001' "$TMP_DIR/accept.json"; then
  echo "expected Lark event URL to stay out of the notes body"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if [[ -f "$TMP_DIR/var/state.sqlite" ]]; then
  echo "accept-source must not create SQLite runtime state"
  exit 1
fi
