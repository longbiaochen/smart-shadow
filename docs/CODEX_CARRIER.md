# SmartShadow Codex Carrier

SmartShadow is delivered as a Codex decision layer plus a local `shadowd`
system-service bridge, not as a separate full project-management app.

The source of truth remains this repository:

```text
/Users/longbiao/Projects/smart-shadow
```

The active Codex assembly lives in:

```text
~/.codex
```

## Architecture

```text
entry layer = phone/computer intent capture and voice routing
Codex = decision brain for life line / Project / Issue and Project-thread execution
SmartShadow skill = repeatable decision and behavior rules
shadowd = sensing/feedback bridge and Mac system service
native apps = intent, response, context, and feedback surfaces
external systems = intent, collaboration, response, or feedback surfaces
```

The entry layer captures user intent from phone and computer surfaces: visible
AI shadow controls in apps, star/favorite/share/mark operations, the Mac menu-bar
app, global hotkey voice, and the phone lightweight app after QR-code binding.
Voice interactions ultimately route back to `shadowd` on the Mac. Mac apps can
also expose explicit or bounded implicit intent through user operation, polling, or
monitoring. `shadowd` prepares the context and connects to Codex. Codex creates
or resumes the corresponding Project thread, uses local software to move the
work forward, and then `shadowd` creates feedback for the user. The default
feedback location is the platform channel where the user posted the task.

Reminders and Calendar are not the core management center. They are software
surfaces with specific semantics:

- Reminders carries responses, reminders, review cards, blockers, and follow-ups.
- Calendar carries meetings, time blocks, deadlines, milestones, and rhythm.
- Finder, Notes, Contacts, Photos, Music, GitHub, Feishu, Mail, WeChat, and
  other apps carry Project / Issue context, responses, collaboration, or feedback
  when the Project calls for them.

The four life lines are a design philosophy, not a requirement that all life
areas live in one app. Current defaults:

- Work-related tasks use the user's Feishu platform and are tracked on Feishu
  task boards through Feishu CLI.
- Life-related tasks use Apple Reminders and are tracked on the corresponding
  Reminders boards or lists.
- GitHub remains the code, PR, Issue, CI, open-source feedback, and
  repo-centered execution surface.
- Calendar carries time blocks and deadlines; Finder, Notes, Contacts, Photos,
  and Music carry supporting assets.

Codex may choose another software surface by Project semantics and user
preference, but the reason should be explainable and Project / Issue mappings
must remain stable.

## Host Sync Policy

The repository-backed carrier definition lives in `config/codex/AGENTS.md` and
`skills/smart-shadow/`. Active host files under `~/.codex` should only be synced
through an explicit follow-up operation with a dated backup under
`~/Documents/Codex/`.

This definition update does not install into `~/.codex`, rewrite active desktop
config, or restart Codex Desktop.

Before host-level cleanup, create a full backup under `~/Documents/Codex/`.

Do not patch, re-sign, or edit `/Applications/Codex.app`. The supported mutation surface is `~/.codex` plus the SmartShadow repository.

## Verification

For a future host sync, verify the active assembly with:

```sh
python3 - <<'PY'
import tomllib
with open('/Users/longbiao/.codex/config.toml', 'rb') as f:
    tomllib.load(f)
print('config_ok')
PY

find ~/.codex/skills -maxdepth 2 -type f -name SKILL.md
bin/shadowd --help
```

Expected active skill:

```text
smart-shadow/SKILL.md
```

## Runtime Reload

Codex Desktop reads global config, plugin state, and discovered skills when a
thread/session starts. After a carrier restructure, the file state is already
installed, but existing live Codex Desktop windows may still carry the old
in-memory tool and skill list.

To make the active desktop runtime match any future host sync, cold restart
Codex Desktop after saving the current work.

Do not patch or re-sign `/Applications/Codex.app` as part of this reload.
