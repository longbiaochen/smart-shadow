#!/usr/bin/env bash
set -euo pipefail

source_id="${SMART_SHADOW_MAIL_SOURCE_ID:-}"
archive_log="${SMART_SHADOW_ARCHIVE_LOG:-var/logs/mail-archive.log}"
mail_action="${SMART_SHADOW_MAIL_ACTION:-/Users/longbiao/Projects/apple-use/apple-mail/scripts/mail_action.sh}"

if [[ -z "$source_id" ]]; then
  echo "SMART_SHADOW_MAIL_SOURCE_ID is required" >&2
  exit 64
fi

if [[ ! "$source_id" =~ ^[0-9]+$ ]]; then
  echo "SMART_SHADOW_MAIL_SOURCE_ID must be the Apple Mail Envelope Index rowid for archive actions: $source_id" >&2
  exit 64
fi

if [[ ! -x "$mail_action" ]]; then
  echo "Mail action helper is not executable: $mail_action" >&2
  exit 66
fi

result="$("$mail_action" --id "$source_id" --action archive)"

mkdir -p "$(dirname "$archive_log")"
printf '%s\n' "$source_id" >> "$archive_log"
printf '%s\n' "$result"
