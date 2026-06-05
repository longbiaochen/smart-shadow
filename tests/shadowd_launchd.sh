#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$("$ROOT/bin/smart-shadowd" render-plist --stdout)"

for pattern in \
  "me.longbiaochen.smart-shadowd" \
  "$ROOT/bin/smart-shadowd" \
  "<string>run</string>" \
  "$ROOT/config/smart-shadow.yaml" \
  "$ROOT/var/logs/smart-shadowd.out.log" \
  "$ROOT/var/logs/smart-shadowd.err.log" \
  "<key>KeepAlive</key>" \
  "<key>RunAtLoad</key>"
do
  if [[ "$OUT" != *"$pattern"* ]]; then
    echo "expected rendered plist to contain: $pattern" >&2
    exit 1
  fi
done
