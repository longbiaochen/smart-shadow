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
    "source_id": "mail-processor-review-001",
    "sender": "em@editorialmanager.com",
    "subject": "Ordinary notification without generic trigger words",
    "summary": "This should still be surfaced because the migrated Mail Processor sender bucket requires review.",
    "mailbox": "INBOX",
    "received_at": "2026-06-02T10:00:00Z"
  },
  {
    "source_id": "mail-processor-archive-001",
    "sender": "scholaralerts-noreply@google.com",
    "subject": "New articles from Google Scholar",
    "summary": "Citation digest.",
    "mailbox": "INBOX",
    "received_at": "2026-06-02T10:01:00Z"
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
  "mail_processor_rules_file": "$ROOT/config/mail-processor-rules.json",
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

if ! rg -q 'mail_processor.review_required_senders' "$TMP_DIR/accept.json"; then
  echo "expected migrated review_required_senders to classify Editorial Manager mail"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q 'mail_processor.auto_archive_patterns' "$TMP_DIR/accept.json"; then
  echo "expected migrated auto_archive_patterns to classify Google Scholar mail"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" enable-source apple_mail_app > "$TMP_DIR/enable.json"
"$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --no-reminders > "$TMP_DIR/run.json"

if ! rg -q '"processed_count"[[:space:]]*:[[:space:]]*2' "$TMP_DIR/run.json"; then
  echo "expected two Mail.app signals to be processed"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"create_review_reminder"' "$TMP_DIR/run.json"; then
  echo "expected review-required mail to enter the board/review action path"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"archive_low_value"' "$TMP_DIR/run.json"; then
  echo "expected auto-archive mail to stay low-noise"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '^mail-processor-archive-001$' "$TMP_DIR/var/mail-archive.log"; then
  echo "expected only the auto-archive message to reach archive executor"
  cat "$TMP_DIR/run.json"
  exit 1
fi
