# Smart Shadow iOS App

The iOS app is one Smart Shadow entry-layer surface. It is an iPhone-first
explicit-intent entry for the broader Mac-service-backed loop: voice is an
important mobile entry, but Smart Shadow also accepts Mac menu-bar operations,
global hotkey voice, in-app AI shadow controls, star/favorite/share/mark
operations, and other configured entry-layer events. The phone lightweight app
can be invoked after QR-code binding, captures voice or text, transcribes and
polishes local audio when needed, turns natural language or selected content
into a structured task card, asks the user to confirm, and routes the final
intent back to `shadowd` on the Mac.

It does not try to become ChatGPT, GitHub Mobile, a project-management suite, or
a Feishu workspace. It also does not take over Mail, messaging, feeds, browser
history, contacts, or proactive social replies. The app owns mobile explicit
task intake, confirmation, status visibility, follow-up capture,
push-notification landing, and completion confirmation.
ShadowD owns Mac-side intake routing, Codex connection, state tracking,
origin-channel feedback mapping, and repo/project routing. Codex executes in
the corresponding Project thread and uses local software or agents to move work
forward. ShadowD does not own recording, audio storage, speech transcription,
text polish, or user-identity GitHub writes.

The product PRD is saved in [PRD.md](PRD.md).

## Setup

Generate the Xcode project:

```bash
xcodegen generate
```

The iPhone app target is `SmartShadowIOS` with bundle id
`me.longbiaochen.smart-shadow`. It uses automatic signing with Apple Developer
Team `YRQ5DV25KM`.

The app stores:

- GitHub owner and repo in UserDefaults.
- GitHub token in the iOS Keychain.
- Recent local delivery and task status in UserDefaults.

The default repository settings are:

- owner: `longbiaochen`
- repo: `life-os`

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
repo read:user
```

For a private `life-os` repository, the classic OAuth `repo` scope is the
practical capability for issue/comment writes through the user's identity. The
returned access token is stored only in the iOS Keychain.

The token must be able to create issues and issue comments in the selected
default task repository. It is used only for user-confirmed writes: new tasks,
follow-up context, and replies to Shadow questions.

Do not commit the Client ID if you prefer to keep it local, and never paste the
access token into logs.

## MVP Task Flow

The app supports five core screens:

1. Home / Shadow Button: one primary voice button plus recent task status.
2. Voice Input: recording, transcript display, re-record, and follow-up capture.
3. Task Confirmation: structured card with task type, project, output, and
   acceptance criteria.
4. Task Detail: status, progress comments, Issue link, PR link, blockers,
   follow-up, completion confirmation, and change requests.
5. Task Feed: recent tasks and key updates, refreshed on open, pull-to-refresh,
   push landing, and local task changes.

The structured task card contains at least:

| Field | Meaning |
|---|---|
| title | One-sentence task title |
| type | Development, product, project-management, research/organizing, follow-up, status query, or completion confirmation |
| project | Repo, document project, or management project |
| context | Background from the user's voice input |
| target_output | Desired deliverable |
| acceptance_criteria | How the user and agent know the task is complete |
| priority | Normal by default, voice-overridable |
| needs_pr | Usually true for development tasks |
| needs_user_confirmation | True by default before submission |

MVP task states:

| State | Meaning |
|---|---|
| Draft | Recognized but not submitted |
| Submitted | Sent to `shadow` |
| Queued | `shadowd` received the task and is waiting to execute |
| Running | A Codex agent is executing |
| Need Input | User input is required |
| PR Ready | A linked PR is ready for review |
| Done | Work is complete |
| Failed | Execution failed |
| Cancelled | User cancelled the task |

## Local Voice Processing Contract

Each recording may create only short-lived local audio cache while the user is
capturing a task. The app must process that audio locally before GitHub
submission:

1. Capture audio from the interaction ball.
2. Keep the raw audio in local temporary storage only.
3. Call the local ChatType Runtime abstraction for speech-to-text.
4. Call the local ChatType Polish abstraction for cleanup and task phrasing.
5. Show the final text and structured task card to the user.
6. Let the user confirm, edit, cancel, re-record, or add follow-up context.
7. After confirmation, create a GitHub issue or issue comment with the user's
   GitHub identity.

GitHub issue/comment content must contain the final text task and compact client
metadata only. It must not include raw audio, an uploaded audio path, a temporary
recording repository pointer, or a raw transcript dump.

ShadowD treats GitHub issue/comment text as the already-confirmed task input. It
must not wait for a packet-ready marker, fetch audio, or run transcription.

On macOS, the companion command panel can use a local ChatType-compatible CLI by
setting `SMART_SHADOW_CHATTYPE_CLI` to an executable that accepts:

```bash
process --audio /path/to/audio.m4a --format json
```

The command should return JSON with `transcript` and `polished_text`. If this is
not configured, the companion falls back to the built-in local Speech framework
adapter and leaves polish as deterministic text cleanup.

## Universal Links

The app declares:

```text
applinks:smart-shadow.bozhi.ai
```

Supported route:

```text
https://smart-shadow.bozhi.ai/followup?repo=<owner/repo>&issue=<number>
```

When opened from this URL, the next recording uses:

```json
{
  "mode": "follow_up",
  "target": {
    "type": "github_issue",
    "repo": "<owner/repo>",
    "issue_number": 123
  }
}
```

After local transcription, polish, and user confirmation, the app creates a
comment on that issue with the user's GitHub identity. The app should validate
enough to avoid obvious wrong-repo writes; ShadowD performs execution-time
validation before acting.

The domain must also host a valid Apple App Site Association file before true
universal links work on device.

## Development Test Flow

Use this order for every iOS change:

1. Codex implements and self-tests on iOS Simulator.
2. Codex performs Simulator interaction acceptance in the Codex in-app browser
   via `serve-sim`.
3. Only after Simulator acceptance passes, build/install on iPhone Air for user
   acceptance.
4. The user performs final true-device acceptance for device permissions, GitHub
   login, voice input, and real external-service effects.

Do not skip directly to iPhone Air for ordinary UI or workflow debugging.

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
  -destination 'platform=iOS Simulator,id=6E4DC09E-3214-4419-988B-AE90616BCD6A' \
  CODE_SIGNING_ALLOWED=NO
```

After build and tests pass, install and launch on the simulator:

```bash
APP=$(xcodebuild -project SmartShadow.xcodeproj -scheme SmartShadowIOS -showBuildSettings \
  -destination 'platform=iOS Simulator,id=6E4DC09E-3214-4419-988B-AE90616BCD6A' 2>/dev/null \
  | awk -F ' = ' '/TARGET_BUILD_DIR/ {dir=$2} /FULL_PRODUCT_NAME/ {name=$2} END {print dir "/" name}')

xcrun simctl install 6E4DC09E-3214-4419-988B-AE90616BCD6A "$APP"
xcrun simctl launch 6E4DC09E-3214-4419-988B-AE90616BCD6A \
  me.longbiaochen.smart-shadow \
  -SmartShadowPreviewAuthenticated
```

Mirror the simulator into the Codex in-app browser:

```bash
npx --yes serve-sim@latest 6E4DC09E-3214-4419-988B-AE90616BCD6A
```

Open the printed localhost URL in the Codex in-app browser and verify the changed
flow there. Computer Use is only needed for native desktop boundaries such as
system permission prompts, Xcode account setup, or true-device trust flows.

## iPhone Air Verification

Run this only after Simulator build, tests, and interaction screenshots have
passed.

The local iPhone Air currently uses UDID:

```text
00008150-0002185C21F0401C
```

Keep the phone unlocked, awake, trusted, and on the same local network. Verify
Developer Disk Image services first:

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

If signing fails, open Xcode Settings, sign in to the Apple Developer account for
Team `YRQ5DV25KM`, and let Xcode create the development provisioning profile.

If DDI mount fails with `kAMDMobileImageMounterDeviceLocked`, unlock the phone
and retry.
