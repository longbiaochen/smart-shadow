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

if [[ "${1:-}" == "calendar" && "${2:-}" == "calendars" && "${3:-}" == "list" ]]; then
  cat <<'JSON'
{
  "code": 0,
  "data": {
    "calendar_list": [
      {
        "calendar_id": "cal_primary",
        "summary": "陈龙彪",
        "type": "primary"
      },
      {
        "calendar_id": "cal_social",
        "summary": "应酬",
        "type": "shared"
      }
    ],
    "has_more": false
  },
  "msg": "success"
}
JSON
  exit 0
fi

if [[ "${1:-}" == "calendar" && "${2:-}" == "events" && "${3:-}" == "instance_view" ]]; then
  printf '%s\n' "$*" >> "$SMART_SHADOW_TEST_CALLS"
  cat <<'JSON'
{
  "code": 0,
  "data": {
    "items": [
      {
        "event_id": "social_evt_001",
        "summary": "应酬：客户晚餐",
        "start_time": {
          "timestamp": "1780502400",
          "timezone": "Asia/Shanghai"
        },
        "end_time": {
          "timestamp": "1780506000",
          "timezone": "Asia/Shanghai"
        },
        "location": {
          "name": "餐厅"
        },
        "app_link": "https://applink.feishu.cn/calendar/event/social_evt_001",
        "description": "和客户确认下周合作。",
        "organizer_calendar_id": "cal_social",
        "self_rsvp_status": "accept"
      }
    ]
  },
  "msg": "success"
}
JSON
  exit 0
fi

cat <<'JSON'
{
  "items": []
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
        "argv": ["lark-cli", "calendar", "+agenda", "--as", "user", "--format", "json", "--start", "2026-06-03T00:00:00+08:00", "--end", "2026-06-04T00:00:00+08:00"],
        "primary_calendar_summary": "陈龙彪",
        "source_calendar_domains": {
          "陈龙彪": "work",
          "应酬": "relationship"
        },
        "extra_calendar_summaries": ["应酬"],
        "timeout_seconds": 5,
        "window_past_days": 0,
      "window_future_days": 0,
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

SMART_SHADOW_TEST_CALLS="$TMP_DIR/calls.txt" PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source lark_calendar_events --limit 10 > "$TMP_DIR/accept.json"

if ! rg -Fq '"title" : "应酬：客户晚餐"' "$TMP_DIR/accept.json"; then
  echo "expected social calendar event to be collected"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"source_calendar_summary" : "应酬"' "$TMP_DIR/accept.json"; then
  echo "expected source calendar summary metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"expected_domain" : "relationship"' "$TMP_DIR/accept.json"; then
  echo "expected social calendar source to map to FAMILY calendar domain"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"domain" : "relationship"' "$TMP_DIR/accept.json"; then
  echo "expected social calendar decision to inherit FAMILY calendar domain"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"source_calendar_id" : "cal_social"' "$TMP_DIR/accept.json"; then
  echo "expected source calendar id metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"calendar_start" : "2026-06-03T16:00:00Z"' "$TMP_DIR/accept.json"; then
  echo "expected timestamp start to be normalized to ISO"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"canonical_key" : "lark:calendar:cal_social:social_evt_001"' "$TMP_DIR/accept.json"; then
  echo "expected canonical key to include source calendar id"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"calendar_id":"cal_social"' "$TMP_DIR/calls.txt"; then
  echo "expected instance_view to be called for the named social calendar"
  cat "$TMP_DIR/calls.txt"
  exit 1
fi
