#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="SmartShadowCompanionMac.app"
DEST_APP="${SMART_SHADOW_MAC_APP_DEST:-/tmp/${APP_NAME}}"

cd "$ROOT_DIR"

xcodebuild \
  -project SmartShadow.xcodeproj \
  -scheme SmartShadowCompanionMac \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  build

SOURCE_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/Build/Products/${CONFIGURATION}/${APP_NAME}" \
  -print \
  | sort \
  | tail -1)"

if [[ -z "$SOURCE_APP" || ! -d "$SOURCE_APP" ]]; then
  echo "error: built app not found for configuration ${CONFIGURATION}" >&2
  exit 1
fi

pkill -x SmartShadowCompanionMac >/dev/null 2>&1 || true
rm -rf "$DEST_APP"
ditto --noextattr --noqtn "$SOURCE_APP" "$DEST_APP"
xattr -cr "$DEST_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$DEST_APP"
codesign --verify --deep --strict --verbose=2 "$DEST_APP"
open -F -n "$DEST_APP"

echo "$DEST_APP"
