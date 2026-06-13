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
  "tasks": [
    {
      "guid": "task_001",
      "summary": "完成飞书任务同步",
      "due": "2026-06-05T18:00:00+08:00",
      "url": "https://applink.feishu.cn/client/todo/task?guid=task_001",
      "priority": "high",
      "completed": false
    },
    {
      "guid": "task_002",
      "summary": "补充验收报告",
      "due_time": "2026-06-06T12:00:00+08:00",
      "description": "把验收结论写进用户报告。",
      "completed": false
    },
    {
      "guid": "task_003",
      "summary": "带时间的任务也只同步提醒事项",
      "start_time": "2026-06-07T10:00:00+08:00",
      "end_time": "2026-06-07T11:00:00+08:00",
      "description": "飞书任务是可完成事项，不应制造 Calendar 时间块。",
      "completed": false
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
    "lark_calendar_events": { "enabled": false },
    "lark_tasks": {
      "enabled": false,
      "argv": ["lark-cli", "task", "+get-my-tasks", "--as", "user", "--complete=false", "--page-all", "--format", "json"],
      "timeout_seconds": 5
    },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": { "enabled": false }
  }
}
EOF

PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source lark_tasks --limit 10 > "$TMP_DIR/accept.json"

if ! rg -q '"source"[[:space:]]*:[[:space:]]*"lark_tasks"' "$TMP_DIR/accept.json"; then
  echo "expected lark_tasks acceptance output"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"collected_count"[[:space:]]*:[[:space:]]*3' "$TMP_DIR/accept.json"; then
  echo "expected three task signals"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"canonical_key"[[:space:]]*:[[:space:]]*"lark:task:task_001"' "$TMP_DIR/accept.json"; then
  echo "expected task canonical key"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"due_date" : "2026-06-05T18:00:00+08:00"' "$TMP_DIR/accept.json"; then
  echo "expected task due date metadata"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -Fq '"projection_target" : "reminder"' "$TMP_DIR/accept.json"; then
  echo "expected Lark tasks to target Reminders"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if rg -q '"projection_target"[[:space:]]*:[[:space:]]*"reminder_and_calendar"' "$TMP_DIR/accept.json"; then
  echo "expected Lark tasks not to target Calendar"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if rg -q '"calendar_start"[[:space:]]*:' "$TMP_DIR/accept.json"; then
  echo "expected Lark task metadata not to carry Calendar projection fields"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if [[ -f "$TMP_DIR/var/state.sqlite" ]]; then
  echo "accept-source must not create SQLite runtime state"
  exit 1
fi
