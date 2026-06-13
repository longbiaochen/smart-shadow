#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events" "$TMP_DIR/bin"

EXPORTER="$TMP_DIR/bin/mail-exporter"
ARCHIVER="$TMP_DIR/bin/mail-archiver"
CONFIG="$TMP_DIR/config/smart-shadow.json"

cat > "$EXPORTER" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {
    "source_id": "mail-app-low-value-001",
    "sender": "newsletter@example.com",
    "subject": "Newsletter 低价值 订阅 优惠券",
    "summary": "A subscription promotion with no user action needed.",
    "body": "Subscription promotion body. No user action is needed.",
    "mailbox": "INBOX",
    "received_at": "2026-06-02T09:00:00Z"
  }
]
JSON
EOF
chmod +x "$EXPORTER"

cat > "$ARCHIVER" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$SMART_SHADOW_MAIL_SOURCE_ID" >> "$SMART_SHADOW_ARCHIVE_LOG"
EOF
chmod +x "$ARCHIVER"

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
    "apple_reminders_inbox": { "enabled": false },
    "apple_mail_summary": { "enabled": false },
    "apple_mail_app": {
      "enabled": false,
      "reader_argv": ["$EXPORTER"],
      "archive_argv": ["$ARCHIVER"],
      "archive_log": "$TMP_DIR/var/mail-archive.log",
      "max_items": 10,
      "max_body_chars": 2000
    }
  }
}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source apple_mail_app --limit 5 > "$TMP_DIR/accept.json"

if ! rg -q '"source"[[:space:]]*:[[:space:]]*"apple_mail_app"' "$TMP_DIR/accept.json"; then
  echo "expected acceptance output for apple_mail_app"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"body_read"[[:space:]]*:[[:space:]]*true' "$TMP_DIR/accept.json"; then
  echo "expected Mail.app source to preserve that body content was read"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"archive_low_value"' "$TMP_DIR/accept.json"; then
  echo "expected low-value Mail.app message to be classified for archive"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" enable-source apple_mail_app > "$TMP_DIR/enable.json"
"$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --no-reminders > "$TMP_DIR/run.json"

if ! rg -q '"processed_count"[[:space:]]*:[[:space:]]*1' "$TMP_DIR/run.json"; then
  echo "expected one Mail.app signal to be processed"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"done"' "$TMP_DIR/run.json"; then
  echo "expected Mail.app archive action to execute"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '^mail-app-low-value-001$' "$TMP_DIR/var/mail-archive.log"; then
  echo "expected archive executor to receive the Mail.app source id"
  cat "$TMP_DIR/run.json"
  exit 1
fi
