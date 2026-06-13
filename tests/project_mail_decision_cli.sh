#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events" "$TMP_DIR/bin"

ARCHIVER="$TMP_DIR/bin/mail-archiver"
FAILING_READER="$TMP_DIR/bin/mail-reader-should-not-run"
CONFIG="$TMP_DIR/config/smart-shadow.json"

cat > "$ARCHIVER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$SMART_SHADOW_MAIL_SOURCE_ID" >> "$SMART_SHADOW_ARCHIVE_LOG"
EOF
chmod +x "$ARCHIVER"

cat > "$FAILING_READER" <<'EOF'
#!/usr/bin/env bash
echo "apple_mail_app reader should not be called by run-once" >&2
exit 42
EOF
chmod +x "$FAILING_READER"

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
    "lark_tasks": { "enabled": false },
    "google_calendar_events": { "enabled": false },
    "google_tasks": { "enabled": false },
    "google_contacts": { "enabled": false },
    "chrome_bookmarks": { "enabled": false },
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": {
      "enabled": true,
      "reader_argv": ["$FAILING_READER"],
      "archive_argv": ["$ARCHIVER"],
      "archive_log": "$TMP_DIR/var/mail-archive.log",
      "max_items": 10,
      "max_body_chars": 2000
    }
  }
}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" project-mail-decision --input "$ROOT/tests/fixtures/mail-decision-apple-reminder.json" --dry-run --no-reminders > "$TMP_DIR/reminder.json"
if ! rg -q '"projection_target"[[:space:]]*:[[:space:]]*"apple_reminder"' "$TMP_DIR/reminder.json"; then
  echo "expected explicit Apple Reminder projection target"
  cat "$TMP_DIR/reminder.json"
  exit 1
fi
if ! rg -q '"status"[[:space:]]*:[[:space:]]*"dry_run"' "$TMP_DIR/reminder.json"; then
  echo "expected dry-run reminder projection"
  cat "$TMP_DIR/reminder.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" project-mail-decision --input "$ROOT/tests/fixtures/mail-decision-work.json" --dry-run --no-reminders > "$TMP_DIR/work-mail.json"
if ! rg -q '"domain"[[:space:]]*:[[:space:]]*"work"' "$TMP_DIR/work-mail.json"; then
  echo "expected work mail to stay in the work domain"
  cat "$TMP_DIR/work-mail.json"
  exit 1
fi
if ! rg -q '"projection_target"[[:space:]]*:[[:space:]]*"apple_reminder"' "$TMP_DIR/work-mail.json"; then
  echo "expected work mail to project only to Apple Reminders"
  cat "$TMP_DIR/work-mail.json"
  exit 1
fi

cat > "$TMP_DIR/legacy-mail-lark.json" <<'JSON'
{
  "canonical_key": "apple_mail:legacy-lark-001",
  "source_id": "legacy-lark-001",
  "subject": "旧飞书邮件投影",
  "sender": "teacher@xmu.edu.cn",
  "received_at": "2026-06-04T08:00:00Z",
  "mailbox": "INBOX",
  "summary": "Legacy mail-to-Lark payload.",
  "projection_target": "lark_task",
  "action": "create_lark_task",
  "domain": "work",
  "priority": "high",
  "risk": "medium",
  "lark_tasklist": "课程建设",
  "reason": "legacy route",
  "suggested_action": "旧链路。"
}
JSON
if "$ROOT/bin/smart-shadow" --config "$CONFIG" project-mail-decision --input "$TMP_DIR/legacy-mail-lark.json" --dry-run --no-reminders > "$TMP_DIR/legacy-lark.out" 2>&1; then
  echo "expected legacy mail-to-Lark projection to be rejected"
  cat "$TMP_DIR/legacy-lark.out"
  exit 1
fi
if ! rg -q 'Unsupported projection_target for mail decision: lark_task' "$TMP_DIR/legacy-lark.out"; then
  echo "expected explicit lark_task rejection"
  cat "$TMP_DIR/legacy-lark.out"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" project-mail-decision --input "$ROOT/tests/fixtures/mail-decision-record-only.json" > "$TMP_DIR/record.json"
if ! rg -q '"action"[[:space:]]*:[[:space:]]*"record_only"' "$TMP_DIR/record.json"; then
  echo "expected record-only mail decision to remain record-only"
  cat "$TMP_DIR/record.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" project-mail-decision --input "$ROOT/tests/fixtures/mail-decision-mail-action.json" > "$TMP_DIR/mail-action.json"
if ! rg -q '^fixture-archive-001$' "$TMP_DIR/var/mail-archive.log"; then
  echo "expected explicit mail action to call configured archive executor"
  cat "$TMP_DIR/mail-action.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --dry-run --no-reminders > "$TMP_DIR/run.json"
if ! rg -q '"processed_count"[[:space:]]*:[[:space:]]*0' "$TMP_DIR/run.json"; then
  echo "expected run-once to ignore apple_mail_app as a daemon source"
  cat "$TMP_DIR/run.json"
  exit 1
fi
