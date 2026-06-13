#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/inbox/events" "$TMP_DIR/var/reports" "$TMP_DIR/var/logs"

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
    "apple_reminders_inbox": { "enabled": false, "backend": "eventkit", "list": "Inbox" }
  }
}
EOF

cat > "$TMP_DIR/var/logs/audit.jsonl" <<EOF
{"timestamp":"2099-01-01T00:00:01Z","type":"source_acceptance_previewed","status":"ok","report_path":"$TMP_DIR/var/reports/missing.md"}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" service-status > "$TMP_DIR/out.json"

for pattern in \
  '"overall_state"[[:space:]]*:[[:space:]]*"attention_required"' \
  '"attention"[[:space:]]*:' \
  '"code"[[:space:]]*:[[:space:]]*"missing_run_report"' \
  '"code"[[:space:]]*:[[:space:]]*"audit_report_missing"'
do
  if ! rg -q "$pattern" "$TMP_DIR/out.json"; then
    echo "expected service-status attention output to contain pattern: $pattern"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
done

if "$ROOT/bin/smart-shadow" eventkit-status | rg -q '"reminders"[[:space:]]*:[[:space:]]*"not_determined"'; then
  if ! rg -q '"code"[[:space:]]*:[[:space:]]*"source_blocked"' "$TMP_DIR/out.json"; then
    echo "expected source_blocked attention when EventKit Reminders is not_determined"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
else
  if rg -q '"code"[[:space:]]*:[[:space:]]*"source_blocked"' "$TMP_DIR/out.json"; then
    echo "did not expect disabled source readiness to require service attention"
    cat "$TMP_DIR/out.json"
    exit 1
  fi
fi
