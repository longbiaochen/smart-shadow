#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var/inbox/events"

CONFIG="$TMP_DIR/config/smart-shadow.json"
cat > "$CONFIG" <<EOF
{
  "project_root": "$ROOT",
  "runtime_root": "$TMP_DIR/var",
  "rules_file": "$ROOT/config/rules.json",
  "reminders": {
    "enabled": true,
    "domain_lists": {
      "money": "MONEY",
      "health": "HEALTH",
      "relationship": "NETWORK",
      "work": "WORK"
    }
  },
  "sources": {
    "event_inbox": "$TMP_DIR/var/inbox/events"
  }
}
EOF

set +e
"$ROOT/bin/smart-shadow" --config "$CONFIG" reminders-plan-quadrants > "$TMP_DIR/no-dry-run.json" 2> "$TMP_DIR/no-dry-run.err"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected reminders-plan-quadrants to require --dry-run"
  cat "$TMP_DIR/no-dry-run.json"
  exit 1
fi

if ! rg -q "requires --dry-run" "$TMP_DIR/no-dry-run.err"; then
  echo "expected explicit --dry-run error"
  cat "$TMP_DIR/no-dry-run.err"
  exit 1
fi

set +e
"$ROOT/bin/smart-shadow" --config "$CONFIG" reminders-plan-quadrants --dry-run > "$TMP_DIR/dry-run.json" 2> "$TMP_DIR/dry-run.err"
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  if rg -q "EventKit reminders access is" "$TMP_DIR/dry-run.err"; then
    exit 0
  fi
  echo "expected dry-run success or EventKit authorization gate"
  cat "$TMP_DIR/dry-run.err"
  exit 1
fi

for pattern in \
  '"mode"[[:space:]]*:[[:space:]]*"dry_run"' \
  '"eventkit_mutates_sections"[[:space:]]*:[[:space:]]*false' \
  '"sections"[[:space:]]*:' \
  '"IMPORTANT"' \
  '"URGENT"' \
  '"DOING"' \
  '"TODO"'
do
  if ! rg -q "$pattern" "$TMP_DIR/dry-run.json"; then
    echo "expected dry-run output to contain pattern: $pattern"
    cat "$TMP_DIR/dry-run.json"
    exit 1
  fi
done
