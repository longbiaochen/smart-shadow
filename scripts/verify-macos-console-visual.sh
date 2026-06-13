#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/var/artifacts"
APP_PATH="${1:-/tmp/SmartShadowMacDerivedData-ui/Build/Products/Debug/SmartShadowCompanionMac.app}"
OUT_PATH="${2:-$ARTIFACT_DIR/smart-shadow-macos-console-$(date +%Y%m%d-%H%M%S).png}"

mkdir -p "$ARTIFACT_DIR"

preflight_output="$(swift <<'SWIFT'
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let shieldOwners = windows.compactMap { window -> String? in
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    if owner == "loginwindow" || (owner == "Window Server" && name.localizedCaseInsensitiveContains("shield")) {
        return owner + ":" + name
    }
    return nil
}

if !shieldOwners.isEmpty {
    print("LOCKED_OR_SHIELDED")
    print(shieldOwners.joined(separator: "\n"))
    exit(75)
}

print("DISPLAY_READY")
SWIFT
)" || status=$?

if [[ "${status:-0}" -eq 75 ]]; then
  printf '%s\n' "$preflight_output" >&2
  echo "macOS visual verification requires an unlocked desktop; WindowServer is showing loginwindow/display shield." >&2
  exit 75
elif [[ "${status:-0}" -ne 0 ]]; then
  printf '%s\n' "$preflight_output" >&2
  exit "${status:-1}"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Build it first, for example:" >&2
  echo "  xcodegen generate && xcodebuild -project SmartShadow.xcodeproj -scheme SmartShadowCompanionMac -destination 'platform=macOS' -derivedDataPath /tmp/SmartShadowMacDerivedData-ui CODE_SIGNING_ALLOWED=NO build" >&2
  exit 66
fi

pkill -x SmartShadowCompanionMac >/dev/null 2>&1 || true
open -n "$APP_PATH" --args -SmartShadowPreviewAuthenticated -SmartShadowForcePreviewData

window_id=""
for _ in {1..30}; do
  window_id="$(swift <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let title = window[kCGWindowName as String] as? String ?? ""
    if owner == "SmartShadowCompanionMac", title == "Smart Shadow",
       let id = window[kCGWindowNumber as String] {
        print(id)
        exit(0)
    }
}
exit(1)
SWIFT
)" && break || true
  sleep 0.5
done

if [[ -z "$window_id" ]]; then
  echo "Smart Shadow main window did not appear." >&2
  exit 70
fi

if ! screencapture -x -l "$window_id" "$OUT_PATH"; then
  echo "Window exists but screencapture could not capture it. Check Screen Recording permission for the executing shell/Codex." >&2
  exit 74
fi

echo "$OUT_PATH"
