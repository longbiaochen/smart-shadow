#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/var" "$TMP_DIR/input"
CONFIG="$TMP_DIR/config/smart-shadow.json"
FIXTURE="$TMP_DIR/input/life-os-project.json"

cat > "$CONFIG" <<EOF
{
  "project_root": "$ROOT",
  "runtime_root": "$TMP_DIR/var",
  "rules_file": "$ROOT/config/rules.json",
  "poll_seconds": 10,
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

cat > "$FIXTURE" <<'EOF'
{
  "items": [
    {
      "repo": "longbiaochen/life-os",
      "number": 123,
      "title": "新任务",
      "state": "OPEN",
      "project_status": "Todo",
      "labels": ["smart-shadow", "shadow:inbox"],
      "body": "请实现本地语音提交 GitHub issue。\n\n---\n\n<!-- smart-shadow\nsource: macos\ninput: voice\naudio: not_uploaded\ncreated_by: user\nshadow_status: inbox\n-->\n"
    },
    {
      "repo": "longbiaochen/life-os",
      "number": 225,
      "title": "Buy milk and schedule planning review",
      "state": "OPEN",
      "project_status": "Ready",
      "labels": ["ready", "voice"],
      "body": "Buy milk tomorrow morning and schedule a 30-minute planning review.\n\n<details><summary>Smart Shadow Metadata</summary>\n\n```json\n{\"audio_path\":\"life-os-input-voice/2026/06/08/task.m4a\"}\n```\n\n</details>\n"
    },
    {
      "repo": "longbiaochen/life-os",
      "number": 5,
      "title": "Ordinary board item",
      "state": "OPEN",
      "project_status": "In Progress",
      "custom_status": "完成",
      "labels": [],
      "item_id": "PVTI_item_5",
      "project_id": "PVT_project_1",
      "status_field_id": "PVTSSF_status",
      "done_option_id": "done_option",
      "body": "Plain issue body"
    },
    {
      "repo": "longbiaochen/life-os",
      "number": 216,
      "title": "Needs template",
      "state": "OPEN",
      "project_status": "Todo",
      "labels": [],
      "body": "Please make this better."
    },
    {
      "repo": "longbiaochen/life-os",
      "number": 300,
      "title": "Templated ordinary task",
      "state": "OPEN",
      "project_status": "Todo",
      "labels": [],
      "body": "## Background\nContext.\n\n## Goal\nOutcome.\n\n## Scope\n\n### In scope\n- Work\n\n### Out of scope\n- Other\n\n## Acceptance Criteria\n- [ ] Done\n\n## Constraints\n- Technical: Swift\n\n## Suggested Starting Points\n- Relevant files: Sources/SmartShadowMacCore/main.swift\n\n## Agent Instructions\n- First inspect code."
    }
  ]
}
EOF

"$ROOT/bin/smart-shadow" --config "$CONFIG" shadowd once --dry-run --fixture "$FIXTURE" > "$TMP_DIR/reconcile.json"

if ! rg -q '"local_task_db"[[:space:]]*:[[:space:]]*false' "$TMP_DIR/reconcile.json"; then
  echo "expected ShadowD to report no local task DB"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"requires_smartshadow_label"[[:space:]]*:[[:space:]]*false' "$TMP_DIR/reconcile.json"; then
  echo "expected whole Project scope, not smartshadow label scope"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"reason"[[:space:]]*:[[:space:]]*"legacy_voice_audio_needs_final_text"' "$TMP_DIR/reconcile.json"; then
  echo "expected #225-style legacy audio issue to request final text instead of waiting for transcription"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q 'Smart Shadow no longer processes raw audio in shadowd' "$TMP_DIR/reconcile.json"; then
  echo "expected legacy audio clarification to mention shadowd raw-audio boundary"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"reason"[[:space:]]*:[[:space:]]*"smart_shadow_text_issue_ready_for_triage"' "$TMP_DIR/reconcile.json"; then
  echo "expected final-text SmartShadow issue to plan triage handoff"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"to_label"[[:space:]]*:[[:space:]]*"shadow:triaging"' "$TMP_DIR/reconcile.json"; then
  echo "expected final-text SmartShadow issue to move to shadow:triaging"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"update_project_status"' "$TMP_DIR/reconcile.json"; then
  echo "expected #5-style custom done issue to plan Project Status alignment"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"action"[[:space:]]*:[[:space:]]*"comment_question"' "$TMP_DIR/reconcile.json"; then
  echo "expected missing template issue to produce a clarification comment"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if ! rg -q '"reason"[[:space:]]*:[[:space:]]*"github_state_already_consistent"' "$TMP_DIR/reconcile.json"; then
  echo "expected complete ordinary template issue to no-op"
  cat "$TMP_DIR/reconcile.json"
  exit 1
fi

if [[ -f "$TMP_DIR/var/state.sqlite" ]]; then
  if /usr/bin/sqlite3 "$TMP_DIR/var/state.sqlite" ".tables" | rg -q 'agent_tasks'; then
    echo "ShadowD must not create an agent_tasks table"
    exit 1
  fi
fi

"$ROOT/bin/shadowd" render-plist --stdout > "$TMP_DIR/plist.xml"
if ! rg -q "$ROOT/bin/shadowd" "$TMP_DIR/plist.xml" || ! rg -q "me.longbiaochen.shadowd" "$TMP_DIR/plist.xml"; then
  echo "expected launchd plist to point at bin/shadowd with canonical label"
  cat "$TMP_DIR/plist.xml"
  exit 1
fi
