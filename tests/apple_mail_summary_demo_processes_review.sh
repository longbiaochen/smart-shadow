#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/reports" "$TMP_DIR/var/inbox/events" "$TMP_DIR/fixtures"

MAIL_FIXTURE="$TMP_DIR/fixtures/apple-mail-summary.json"
CONFIG="$TMP_DIR/config/smart-shadow.json"

cat > "$MAIL_FIXTURE" <<'EOF'
[
  {
    "source_id": "mail-demo-001",
    "sender": "em@editorialmanager.com",
    "subject": "New Manuscript submitted for your Editor Assignment",
    "summary": "A new manuscript requires editorial review. Please decide whether to invite reviewers by Friday.",
    "mailbox": "INBOX",
    "received_at": "2026-06-02T08:30:00Z"
  }
]
EOF

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
    "apple_mail_summary": {
      "enabled": false,
      "messages_file": "$MAIL_FIXTURE",
      "max_items": 10
    }
  }
}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" accept-source apple_mail_summary --limit 5 > "$TMP_DIR/accept.json"

if ! rg -q '"source"[[:space:]]*:[[:space:]]*"apple_mail_summary"' "$TMP_DIR/accept.json"; then
  echo "expected acceptance output for apple_mail_summary"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

if ! rg -q '"review_count"[[:space:]]*:[[:space:]]*1' "$TMP_DIR/accept.json"; then
  echo "expected editorial mail to need review"
  cat "$TMP_DIR/accept.json"
  exit 1
fi

"$ROOT/bin/smart-shadow" --config "$CONFIG" enable-source apple_mail_summary > "$TMP_DIR/enable.json"
"$ROOT/bin/smart-shadow" --config "$CONFIG" run-once --dry-run --no-reminders > "$TMP_DIR/run.json"

if ! rg -q '"processed_count"[[:space:]]*:[[:space:]]*1' "$TMP_DIR/run.json"; then
  echo "expected one mail signal to be processed"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"create_review_reminder"' "$TMP_DIR/run.json"; then
  echo "expected editorial mail to produce a review action"
  cat "$TMP_DIR/run.json"
  exit 1
fi

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"dry_run"' "$TMP_DIR/run.json"; then
  echo "expected demo processing to remain non-mutating"
  cat "$TMP_DIR/run.json"
  exit 1
fi
