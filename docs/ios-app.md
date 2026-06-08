# Smart Shadow iOS App

The iOS MVP records a short voice memo, uploads the audio and metadata to the `life-os` repository, creates a GitHub issue, and adds the issue to the Life OS GitHub Project. `shadowd` discovers it from Project membership, not from a required label.

## Setup

Generate the Xcode project:

```bash
xcodegen generate
```

The iPhone app target is `SmartShadowIOS` with bundle id `me.longbiaochen.smart-shadow`. It uses automatic signing with Apple Developer Team `YRQ5DV25KM`.

The app stores:

- GitHub owner, repo, and project id in UserDefaults.
- GitHub token in the iOS Keychain.

The default repository settings are:

- owner: `longbiaochen`
- repo: `life-os`
- project id: `PVT_kwHOAAYDyc4BXUQe`

## GitHub OAuth

The app uses GitHub OAuth Device Flow. Create a GitHub OAuth App with Device
Flow enabled, then provide its Client ID either in the login screen or through a
local Xcode build setting:

```bash
xcodebuild build \
  -project SmartShadow.xcodeproj \
  -scheme SmartShadowIOS \
  -destination 'generic/platform=iOS Simulator' \
  SMART_SHADOW_GITHUB_CLIENT_ID=YOUR_CLIENT_ID
```

The app requests:

```text
repo project read:user
```

The returned access token is stored only in the iOS Keychain.

The token must be able to:

- create labels and issues in `life-os`;
- upload repository contents;
- add issues to the configured GitHub Project.

Do not commit the Client ID if you prefer to keep it local, and never paste the
access token into logs.

## Backend Contract

Each upload creates:

```text
life-os-input-voice/YYYY/MM/DD/task-YYYYMMDD-HHmmss-ios.m4a
life-os-input-voice/YYYY/MM/DD/task-YYYYMMDD-HHmmss.json
```

The issue may include labels:

```text
smart-shadow
source/ios
voice
agent/codex
project/life-os
ss/state:needs-transcription
```

`shadowd once` inspects the whole Life OS Project. For voice issues it should keep the final task description first, omit raw transcript text, and keep Smart Shadow metadata compact or folded. Ordinary Project issues without voice metadata are not sent through transcription.

## Development Test Flow

Use this order for every iOS change:

1. Codex implements and self-tests on iOS Simulator.
2. Codex performs Simulator interaction acceptance with screenshots for the changed flow.
3. Only after Simulator acceptance passes, build/install on iPhone Air for user acceptance.
4. The user performs final true-device acceptance for device permissions, GitHub login, voice input, and real external-service effects.

Do not skip directly to iPhone Air for ordinary UI or workflow debugging. True-device testing is reserved for final acceptance and device-only surfaces.

## Simulator Verification

```bash
xcodebuild build \
  -project SmartShadow.xcodeproj \
  -scheme SmartShadowIOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project SmartShadow.xcodeproj \
  -scheme SmartShadowIOS \
  -destination 'platform=iOS Simulator,id=DD43D198-4D4D-4E33-86D8-C18F9B757A99' \
  CODE_SIGNING_ALLOWED=NO
```

After build and tests pass, install and launch on the simulator, then capture screenshots of the changed flow:

```bash
APP=$(xcodebuild -project SmartShadow.xcodeproj -scheme SmartShadowIOS -showBuildSettings \
  -destination 'platform=iOS Simulator,id=DD43D198-4D4D-4E33-86D8-C18F9B757A99' 2>/dev/null \
  | awk -F ' = ' '/TARGET_BUILD_DIR/ {dir=$2} /FULL_PRODUCT_NAME/ {name=$2} END {print dir "/" name}')

xcrun simctl install DD43D198-4D4D-4E33-86D8-C18F9B757A99 "$APP"
xcrun simctl launch DD43D198-4D4D-4E33-86D8-C18F9B757A99 me.longbiaochen.smart-shadow
xcrun simctl io DD43D198-4D4D-4E33-86D8-C18F9B757A99 screenshot /tmp/smart-shadow-ios.png
```

For authenticated UI-only previews, use the DEBUG-only launch argument:

```bash
xcrun simctl launch DD43D198-4D4D-4E33-86D8-C18F9B757A99 \
  me.longbiaochen.smart-shadow \
  -SmartShadowPreviewAuthenticated
```

## iPhone Air Verification

Run this only after Simulator build, tests, and interaction screenshots have passed.

The local iPhone Air currently uses UDID:

```text
00008150-0002185C21F0401C
```

Keep the phone unlocked, awake, trusted, and on the same local network. Verify Developer Disk Image services first:

```bash
xcrun devicectl device info ddiServices \
  --device 00008150-0002185C21F0401C \
  --timeout 30
```

Then build for the phone:

```bash
xcodebuild build \
  -project SmartShadow.xcodeproj \
  -scheme SmartShadowIOS \
  -destination 'platform=iOS,id=00008150-0002185C21F0401C' \
  SMART_SHADOW_GITHUB_CLIENT_ID=YOUR_CLIENT_ID \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration
```

If signing fails, open Xcode Settings, sign in to the Apple Developer account for Team `YRQ5DV25KM`, and let Xcode create the development provisioning profile.

If DDI mount fails with `kAMDMobileImageMounterDeviceLocked`, unlock the phone and retry. If Xcode cannot find device support, run:

```bash
xcodebuild -downloadPlatform iOS
xcodebuild -prepareDeviceSupport -platform iOS -osVersion 26.4.2 -modelCode iPhone18,4 -architecture arm64e
xcrun devicectl manage ddis update --timeout 120
```
