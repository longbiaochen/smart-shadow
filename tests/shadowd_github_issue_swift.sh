#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var" "$TMP_DIR/input" "$TMP_DIR/repo"
CONFIG="$TMP_DIR/config/smart-shadow.json"
ASSIGNED="$TMP_DIR/input/assigned.json"
COMMENT="$TMP_DIR/input/comment.json"
LABELED="$TMP_DIR/input/labeled.json"

cat > "$CONFIG" <<EOF
{
  "project_root": "$ROOT",
  "runtime_root": "$TMP_DIR/var",
  "rules_file": "$ROOT/config/rules.json",
  "poll_seconds": 10,
  "github": {
    "enabled": true,
    "agentName": "shadow",
    "daemonName": "shadowd",
    "assignee": "shadow",
    "allowedCommentCommands": ["@shadow", "@shadow fix", "@shadow continue", "@shadow test", "@shadow explain"],
    "events": ["issues", "issue_comment"],
    "repos": {
      "longbiaochen/smart-shadow": {
        "localPath": "$TMP_DIR/repo",
        "defaultBase": "main",
        "allowedSenders": ["longbiaochen"],
        "testCommand": "pnpm test:shadowd",
        "codexSandbox": "workspace-write"
      }
    }
  },
  "reminders": { "enabled": false, "domain_lists": {} },
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
    "apple_mail_summary": { "enabled": false }
  }
}
EOF

cat > "$ASSIGNED" <<'EOF'
{
  "action": "assigned",
  "repository": { "full_name": "longbiaochen/smart-shadow" },
  "sender": { "login": "longbiaochen" },
  "assignee": { "login": "shadow" },
  "issue": {
    "number": 221,
    "title": "Smart Shadow webhook task",
    "body": "Please fix the typo.",
    "html_url": "https://github.com/longbiaochen/smart-shadow/issues/221",
    "labels": [],
    "assignees": [{ "login": "shadow" }]
  }
}
EOF

cat > "$COMMENT" <<'EOF'
{
  "action": "created",
  "repository": { "full_name": "longbiaochen/smart-shadow" },
  "sender": { "login": "longbiaochen" },
  "issue": {
    "number": 222,
    "title": "Continue task",
    "body": "Please continue.",
    "html_url": "https://github.com/longbiaochen/smart-shadow/issues/222",
    "labels": [],
    "assignees": []
  },
  "comment": {
    "id": 9001,
    "body": "@shadow continue\nplease continue",
    "html_url": "https://github.com/longbiaochen/smart-shadow/issues/222#issuecomment-9001"
  }
}
EOF

cat > "$LABELED" <<'EOF'
{
  "action": "labeled",
  "repository": { "full_name": "longbiaochen/smart-shadow" },
  "sender": { "login": "longbiaochen" },
  "label": { "name": "agent:shadow" },
  "issue": {
    "number": 223,
    "title": "Old label trigger",
    "body": "This must not route.",
    "html_url": "https://github.com/longbiaochen/smart-shadow/issues/223",
    "labels": [{ "name": "agent:shadow" }],
    "assignees": []
  }
}
EOF

SMART_SHADOW_CONFIG="$CONFIG" "$ROOT/bin/shadowd" github-issue --dry-run --payload "$ASSIGNED" --event issues --delivery delivery-assigned > "$TMP_DIR/assigned.out"
SMART_SHADOW_CONFIG="$CONFIG" "$ROOT/bin/shadowd" github-issue --dry-run --payload "$COMMENT" --event issue_comment --delivery delivery-comment > "$TMP_DIR/comment.out"
SMART_SHADOW_CONFIG="$CONFIG" "$ROOT/bin/shadowd" github-issue --dry-run --payload "$LABELED" --event issues --delivery delivery-labeled > "$TMP_DIR/labeled.out"

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"no_changes"' "$TMP_DIR/assigned.out"; then
  echo "expected assigned issue dry-run to execute Swift github issue workflow"
  cat "$TMP_DIR/assigned.out"
  exit 1
fi

if ! rg -q 'shadow\\?/issue-221-smart-shadow-webhook-task' "$TMP_DIR/assigned.out"; then
  echo "expected shadow branch prefix for assigned issue"
  cat "$TMP_DIR/assigned.out"
  exit 1
fi

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"no_changes"' "$TMP_DIR/comment.out"; then
  echo "expected @shadow comment dry-run to execute Swift github issue workflow"
  cat "$TMP_DIR/comment.out"
  exit 1
fi

if ! rg -q '"status"[[:space:]]*:[[:space:]]*"ignored"' "$TMP_DIR/labeled.out" || ! rg -q '"reason"[[:space:]]*:[[:space:]]*"trigger_not_matched"' "$TMP_DIR/labeled.out"; then
  echo "expected label event to be ignored"
  cat "$TMP_DIR/labeled.out"
  exit 1
fi

if ! find "$TMP_DIR/var/logs/github-issue-workflow" -type f | rg -q .; then
  echo "expected Swift shadowd github issue workflow to write a local log"
  exit 1
fi
