# Smart Shadow Visual System

Smart Shadow should look like a quiet macOS system companion: local, auditable,
low-interruption, and precise. The interface should make state, risk, source,
and next action obvious without becoming a chat app, marketing dashboard, or
decorative AI surface.

This document defines the durable visual system for the menu-bar app, operator
reports, review cards, source diagnostics, and future Calendar/Reminders
projection surfaces.

## Repo-First Shadow Console

The iOS and macOS companion apps are no longer ordinary task-list surfaces. They
are repo-first shadow consoles for GitHub-backed life projects.

Primary navigation:

- iOS: bottom tab bar with `WORK`, `MONEY`, `HEALTH`, `NETWORK`, and `我的`.
- macOS: left sidebar with the same five destinations.

Board model:

- Every main tab shows repositories, not issues.
- Repositories are grouped in this fixed order: `IMPORTANT`, `URGENT`,
  `DOING`, `TODO`.
- A repository appears in exactly one group at a time.
- Repository cards must expose name, one-line description, next action, open
  issue count, open PR count, primary labels, status, updated time, review date,
  and agent state.
- The next action is the dominant line after the repo name. Counts and labels
  stay compact and scannable.

Detail model:

- Repo detail shows repo name, status, next action, issue count, PR count,
  labels, last sync time, then the issue list.
- Issue rows show number, title, status, labels, assignee, updated time,
  comment count, linked PR state, and whether user decision is needed.
- Issue detail shows number, title, repo, status, labels, assignee, linked PR,
  summary, timeline, and comments.

Platform layout:

- iOS uses `NavigationStack` drill-down: Tab Home -> Repo Detail -> Issue
  Detail.
- macOS uses three columns: Sidebar / Repo Board / Detail. Selecting a repo
  should immediately populate the right detail column.
- The default macOS launch surface is the console, not a login dialog. GitHub
  login is opened from `我的` or Settings only.

Shadow Orb:

- Every repo list, repo detail, and issue detail page has a bottom-centered
  Shadow Orb.
- Tap opens the text/voice panel. Long press enters voice input. Swipe up opens
  the command panel.
- States are visual, not chatty: idle breathing, listening ripple, thinking
  rotation, executing progress ring, done flash, error red edge, confirm orange
  pulse.

macOS command shortcuts:

- `Command-K`: command panel.
- `Command-R`: sync GitHub.
- `Command-N`: new repo/project.
- `Command-I`: new issue.
- `Command-Return`: execute current Shadow suggestion.

macOS local visual acceptance:

On macOS 26, Xcode/DerivedData app bundles may inherit provenance metadata that
causes `open` to create the app as `launched-suspended` at `_dyld_start`. For
local visual acceptance without a Mac Development certificate, run:

```bash
scripts/run-macos-companion-clean.sh
```

The script builds the companion app, copies it to `/tmp`, clears extension
attributes where possible, ad-hoc signs the copied bundle, verifies the bundle,
and opens it with `open -F -n`. The copied app is an acceptance artifact only;
the source of truth remains the Xcode project and checked-in Swift sources.

## Design Principles

1. Native first

   Use SwiftUI, SF Symbols, Dynamic Type, semantic materials, system controls,
   system accent behavior, and platform spacing before inventing custom chrome.
   Smart Shadow is a local Mac service and should feel installed, trusted, and
   boring in the best sense.

2. State before personality

   The first scan should answer: is the service running, what needs attention,
   what changed, what source produced it, what risk level applies, and what can
   the operator safely do next.

3. Low interruption

   Avoid oversized hero treatments, glowing AI motifs, animated assistants,
   chat bubbles, ornamental gradients, and noisy notification colors. Use small
   badges, compact rows, and clear grouping.

4. Explainable by default

   Every important item should expose its source, confidence, rule, risk, and
   projection target close to the action. Do not hide audit context in vague
   visual decoration.

5. Human-visible, machine-auditable

   User-facing text stays calm and readable. Internal metadata belongs in local
   logs, not in Reminder titles, visible notes, or overloaded UI labels.

6. Four life domains, one operating language

   Health, Money, Relationships, and Work are the stable domain axes. Urgency,
   priority, risk, review state, and execution state are separate dimensions and
   must not be encoded as competing category colors.

## Brand Character

- Name: `Smart Shadow` in English contexts, `智能影子` in Chinese operator UI.
- Voice: calm, direct, local-first, accountable.
- Avoid: mystical AI language, agent hype, social-media productivity copy,
  anthropomorphic mascots, and gamified streak language.
- Preferred verbs: `Review`, `Approve`, `Project`, `Explain`, `Replay`,
  `Dry Run`, `Stop`, `Start`, `Refresh`, `Open Logs`.
- Preferred Chinese verbs: `审核`, `授权`, `投影`, `解释`, `回放`, `试运行`,
  `停止`, `启动`, `刷新`, `打开日志`.

## Logo And Mark

The product mark should be a restrained system mark, not a character.

- Primary symbol: SF Symbol `moon.stars.fill`.
- Secondary symbol for audit surfaces: `checkmark.seal`.
- Service dot: a small status dot anchored at the lower-right of the mark.
- Shape: 52 x 52 pt circular system material in the menu panel.
- Do not use custom SVG logo drawings in SwiftUI unless a real brand asset is
  later created and checked in.

Recommended mark structure:

```swift
ZStack {
    Circle().fill(.primary.opacity(0.08))
    Circle().strokeBorder(statusColor.opacity(0.45), lineWidth: 1)
    Image(systemName: "moon.stars.fill")
    Circle().fill(statusColor).frame(width: 10, height: 10)
}
```

## Color System

Use semantic system colors wherever possible. Custom colors should be tokenized
and reserved for stable meaning.

### Neutral Tokens

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `surface.base` | system window background | system window background | Panel base |
| `surface.raised` | primary 4-6% opacity | primary 6-8% opacity | Metric tiles, compact grouped blocks |
| `surface.warning` | orange 8-10% opacity | orange 12-16% opacity | Attention banner background |
| `surface.danger` | red 8-10% opacity | red 12-16% opacity | Error banner background |
| `border.subtle` | primary 8-12% opacity | primary 10-16% opacity | Tile borders and dividers |
| `text.primary` | primary | primary | Main labels |
| `text.secondary` | secondary | secondary | Supporting metadata |
| `text.tertiary` | tertiary | tertiary | Timestamps, commands, low-emphasis data |

### Service State Tokens

| State | Token | Color | SF Symbol | Meaning |
| --- | --- | --- | --- | --- |
| Running | `state.running` | green | `checkmark.circle.fill` | Service healthy and recent |
| Attention | `state.attention` | orange | `exclamationmark.triangle.fill` | Human review or stale signal |
| Stopped | `state.stopped` | secondary | `pause.circle.fill` | Service intentionally stopped or unloaded |
| Unknown | `state.unknown` | red | `questionmark.circle.fill` | Control plane unavailable |
| Working | `state.working` | accent | `arrow.clockwise` | Command in progress |

### Life Domain Tokens

Domain colors should be used as narrow accents, chips, dots, row leading marks,
or chart keys. They should not flood panels.

| Domain | Token | Suggested Light | Suggested Dark | Symbol |
| --- | --- | --- | --- | --- |
| Health | `domain.health` | `#0E9F6E` | `#34D399` | `heart.text.square` |
| Money | `domain.money` | `#B7791F` | `#F6C85F` | `chart.line.uptrend.xyaxis` |
| Relationships | `domain.relationships` | `#C05680` | `#F687B3` | `person.2.wave.2` |
| Work | `domain.work` | `#2563EB` | `#60A5FA` | `briefcase` |

### Quadrant Tokens

Quadrants describe work status and importance, not life domain. Prefer labels,
order, and iconography over saturated color.

| Quadrant | Token | Weight | Symbol | Visual Treatment |
| --- | --- | --- | --- | --- |
| `URGENT` | `quadrant.urgent` | Highest | `bolt.fill` | Orange label, top placement |
| `IMPORTANT` | `quadrant.important` | High | `star.fill` | Accent label, stable placement |
| `DOING` | `quadrant.doing` | Active | `progress.indicator` | Blue/accent label, progress affordance |
| `TODO` | `quadrant.todo` | Normal | `circle` | Neutral label |

### Risk Tokens

Risk colors override domain color when an action could affect money, privacy,
identity, legal exposure, health, relationships, or external commitments.

| Risk | Token | Treatment |
| --- | --- | --- |
| Low | `risk.low` | Green text or subtle chip |
| Medium | `risk.medium` | Orange chip and review hint |
| High | `risk.high` | Red chip, explicit approval button, no auto action |
| Blocked | `risk.blocked` | Red banner with source and blocker |

## Typography

Use the system font through SwiftUI. Do not set custom font families unless a
future brand refresh explicitly adds one.

| Role | SwiftUI | Usage |
| --- | --- | --- |
| Panel title | `.title3.weight(.semibold)` | `智能影子`, top-level panel header |
| Section title | `.subheadline.weight(.semibold)` | `来源`, `注意项`, `最近事项` |
| Metric value | `.subheadline.weight(.medium)` | Counts, fresh/stale labels |
| Row title | `.caption.weight(.semibold)` | Attention item title |
| Body metadata | `.caption` | Source messages, descriptions |
| Dense metadata | `.caption2` | Commands, timestamps, rule IDs |
| Report H1 | `.title2.weight(.semibold)` | Native report surfaces |
| Report body | `.body` | Longer operator explanations |

Rules:

- Letter spacing remains `0`.
- Avoid all-caps except fixed protocol labels like `URGENT`, `DOING`, and `TODO`.
- Use `.lineLimit(1)` for compact status labels and `.minimumScaleFactor(0.8)`
  only for metrics that must stay inside fixed tiles.
- Chinese and English text may mix in the same row, but commands and rule IDs
  should use monospaced styling only when the view supports it cleanly.

## Spacing And Layout

Smart Shadow uses compact macOS density with stable dimensions.

| Token | Value | Usage |
| --- | --- | --- |
| `space.2` | 2 pt | Tight metadata stacks |
| `space.3` | 3 pt | Row title/detail gap |
| `space.6` | 6 pt | Source rows |
| `space.8` | 8 pt | Buttons, row separators, section internals |
| `space.10` | 10 pt | Tile padding |
| `space.12` | 12 pt | Action bar padding |
| `space.14` | 14 pt | Main panel content gap |
| `space.16` | 16 pt | Panel edge padding |

Panel defaults:

- Menu panel content width: 380-440 pt.
- Scroll max height: 640 pt.
- Metric grid: two equal columns, 8 pt gap.
- Metric tile minimum height: 72 pt.
- Mark size: 52 x 52 pt.
- Section radius: 8 pt maximum unless macOS system control style dictates.

Do not nest decorative cards inside page-like cards. In the menu panel, a
`SectionBlock` is an unframed grouping; repeated data items may use raised
tiles or compact row groups.

## Iconography

Use SF Symbols through `Image(systemName:)`.

| Concept | Symbol |
| --- | --- |
| Smart Shadow | `moon.stars.fill` |
| Refresh | `arrow.clockwise` |
| Start | `play.fill` |
| Stop | `stop.fill` |
| Report | `doc.text` |
| Logs | `doc.text.magnifyingglass` |
| Project folder | `folder` |
| Calendar | `calendar` |
| Reminders | `checklist` |
| Source ready | `checkmark.circle.fill` |
| Source blocked | `exclamationmark.circle.fill` |
| Audit | `checkmark.seal` |
| Replay | `memories` |
| Rule | `slider.horizontal.3` |
| Privacy | `lock.shield` |
| Approval required | `hand.raised.fill` |

Icon rules:

- Buttons use icons by default with `.help(...)` tooltips.
- Dense rows may combine icon + text when scanability matters.
- Do not use emoji for product states.
- Do not hand-draw icons with SVG or custom paths while an SF Symbol exists.

## Components

### Status Hero

Purpose: communicate service health in the first scan.

Required elements:

- Product mark with status dot.
- Product name.
- Status capsule.
- One-line service subtitle.
- Refreshed timestamp.
- Small progress indicator while working.

Tone:

- Healthy: quiet confidence.
- Attention: clear but not alarming.
- Unknown/error: direct and actionable.

### Status Capsule

Shape: capsule, horizontal padding 8 pt, vertical padding 3 pt.

States:

- Running: green text on green 12% background.
- Attention: orange text on orange 12% background.
- Stopped: secondary text on primary 6% background.
- Unknown: red text on red 10% background.

### Metric Tile

Purpose: compact operational telemetry.

Structure:

- Leading SF Symbol, 18 pt width.
- Caption title.
- Medium value.
- Caption2 detail.
- 10 pt padding, 8 pt radius, raised surface.

Use for run freshness, processed/error counts, EventKit status, source count,
pending review count, and last projection result.

### Attention Row

Purpose: show only items that require operator attention.

Structure:

- Leading warning or blocker icon.
- Title in semibold caption.
- Optional source chip or source text.
- Message, two lines max.
- Suggested command or next action in tertiary caption2.

Do not create attention rows for background trivia or low-value events.

### Review Card

Purpose: prepare a human approval decision.

Required sections:

- Clean task title.
- Domain and quadrant.
- Source and confidence.
- Risk level and why review is required.
- Recommended action.
- Alternatives.
- Projection preview: Reminders action and Calendar time block if applicable.
- Buttons: approve, adjust, defer, reject.

High-risk review cards must make the safe default visually obvious. The primary
button may be `Review` or `Approve Draft`; destructive or external actions are
never the default visual action.

### Source Diagnostic Row

Purpose: show source readiness without making operators parse logs.

Fields:

- Source name.
- Enabled state.
- Readiness state.
- Blocker count or reason.
- Last acceptance report age.
- Action: open report or run doctor.

Ready rows should be visually quiet. Blocked rows should expose the blocker
inline and use orange or red only for the blocker portion.

### Rule Row

Purpose: make decision logic inspectable.

Fields:

- Rule name.
- Scope/source.
- Trigger summary.
- Default action.
- Risk.
- Confirmation requirement.
- Last changed reason.

Use compact table/list styling. Rule editing should favor native forms and
segmented controls over custom cards.

### Projection Preview

Purpose: prevent duplicate or semantically wrong Calendar/Reminders output.

Show:

- Canonical work item identity.
- Reminder list/domain.
- Reminder section/quadrant.
- Native due date, priority, flagged state when applicable.
- Calendar title, start, end, and calendar name when applicable.
- Existing projection mapping or new projection indicator.

Use side-by-side compact columns for Calendar and Reminders when space allows.
On narrow surfaces, stack Reminders first, Calendar second.

### Operator Report

Purpose: daily or run-level human summary.

Order:

1. Important items.
2. Needs review.
3. Rule changes or source changes.
4. Projection results.
5. Cost/privacy notes.
6. Failures and root cause.
7. Next repair.

Reports should be readable as plain Markdown and render well in a native or web
surface. Avoid dumping raw JSON into user-visible reports.

## Screen Patterns

### Menu-Bar Panel

Priority order:

1. Status hero.
2. Error banner when present.
3. Metric grid.
4. Attention list.
5. Source overview.
6. Recent items.
7. Fixed action bar.

Actions stay safe: refresh, start, stop, report, open project, open logs, quit.
No Calendar/Reminders write action should be triggered from this panel without a
clear review or dry-run path.

### Review Inbox

Design as a dense work queue, not a social feed.

- Left column: filters for domain, risk, source, state.
- Main column: review cards.
- Detail panel: evidence, rule explanation, projection preview.
- Footer: keyboard-friendly approve/adjust/defer/reject controls.

### Source Center

Design as diagnostics and readiness, not settings sprawl.

- Top summary: enabled, blocked, ready-to-enable, last doctor run.
- Source table grouped by local, Apple, Lark, Google, browser, mail.
- Each source exposes acceptance report age and blocker.
- Enablement requires acceptance status to be visible.

### Rule Registry

Design as auditable policy management.

- Use table density for browsing.
- Use native form density for editing.
- Changes require reason text.
- Preview affected examples before saving.

### Calendar/Reminders Acceptance

Design for visual verification.

- Show generated projection preview.
- Show native app acceptance checklist.
- Distinguish precheck, EventKit write result, and Apple UI verification.
- Never mark a Calendar/Reminders flow visually complete before native UI
  acceptance is recorded.

## Motion

Motion should be rare and functional.

- Progress: native `ProgressView`.
- Refresh: no custom spinner unless needed.
- Status changes: subtle opacity or scale transition under 150 ms.
- Avoid looping decorative animation.
- Avoid animated assistant avatars.

## Accessibility

- Respect light/dark mode and increased contrast.
- Do not rely on color alone; pair state colors with labels and symbols.
- Maintain 4.5:1 contrast for text where possible.
- Keep button hit targets at native macOS control sizes.
- All icon-only buttons must have `.help(...)`.
- Use stable row heights for dense controls to avoid layout jump.
- Support Chinese and English strings without truncating the core action.

## SwiftUI Token Sketch

Use this as the naming direction for implementation. Values may wrap platform
semantic colors instead of hardcoded hex values.

```swift
enum ShadowColor {
    static let surfaceRaised = Color.primary.opacity(0.045)
    static let borderSubtle = Color.primary.opacity(0.10)

    static let running = Color.green
    static let attention = Color.orange
    static let stopped = Color.secondary
    static let unknown = Color.red

    static let health = Color(red: 0.05, green: 0.62, blue: 0.43)
    static let money = Color(red: 0.72, green: 0.47, blue: 0.12)
    static let relationships = Color(red: 0.75, green: 0.34, blue: 0.50)
    static let work = Color(red: 0.15, green: 0.39, blue: 0.92)
}

enum ShadowSpace {
    static let xs: CGFloat = 3
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
    static let panel: CGFloat = 16
}

enum ShadowRadius {
    static let tile: CGFloat = 8
    static let banner: CGFloat = 8
}
```

## Content Rules

Reminder titles:

- Clean, human-readable action only.
- No internal IDs.
- No synthetic prefixes.
- No source/risk metadata in the title.

Reminder notes:

- Human-readable background.
- Suggested next action.
- Relevant source summary.
- No raw audit blobs.

Calendar titles:

- Describe the time block, appointment, or milestone.
- Avoid GTD/quadrant labels.
- Avoid duplicate Reminder semantics.

Status text:

- Prefer `无法连接本地控制面` over generic `Error`.
- Prefer `来源未就绪` over `source_blocked` in visible UI.
- Keep machine codes available in details, logs, or tooltips.

## Anti-Patterns

Do not use:

- Chat bubbles as the main UI model.
- Oversized landing-page hero sections.
- Purple-blue AI gradients as the dominant visual identity.
- Decorative abstract blobs, fake glass panels, or glowing agent avatars.
- Emoji state indicators.
- Custom inline SVG approximations for icons.
- Reminder title prefixes to fake internal metadata.
- Color-only risk or domain encoding.
- Full raw JSON in user-facing report sections.

## Acceptance Checklist

Before shipping a Smart Shadow UI surface:

- The first scan answers service health, attention count, and next safe action.
- Domain, quadrant, risk, and execution state are visually separate dimensions.
- Every high-risk action has a review-first visual treatment.
- Calendar and Reminders projections are semantically distinct.
- Colors work in light and dark mode.
- Icon-only controls have tooltips.
- Text fits in Chinese and English at compact menu-panel width.
- Runtime evidence and audit metadata are accessible without polluting user
  titles or notes.
- The UI has been visually verified on the official Codex/Browser surface when
  web-based, or in the native macOS app surface when SwiftUI/native.
