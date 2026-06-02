#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_JSON="$("$ROOT/bin/smart-shadow" eventkit-status)"

if ! printf '%s\n' "$STATUS_JSON" | rg -q '"reminders"[[:space:]]*:[[:space:]]*"not_determined"'; then
  exit 0
fi

set +e
"$ROOT/bin/smart-shadow" accept-source apple_reminders_inbox --limit 1 > /tmp/smart-shadow-reminders-auth-out.txt 2> /tmp/smart-shadow-reminders-auth-err.txt
RESULT=$?
set -e

if [[ "$RESULT" -eq 0 ]]; then
  echo "expected apple_reminders_inbox acceptance to stop at the EventKit authorization gate when reminders status is not_determined"
  cat /tmp/smart-shadow-reminders-auth-out.txt
  exit 1
fi

if ! rg -q "EventKit reminders access is not_determined" /tmp/smart-shadow-reminders-auth-err.txt; then
  echo "expected an explicit EventKit reminders authorization error"
  cat /tmp/smart-shadow-reminders-auth-err.txt
  exit 1
fi
