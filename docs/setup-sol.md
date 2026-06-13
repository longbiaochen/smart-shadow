# shadowd Setup On SOL

`shadowd` runs locally on the SOL MacBook as a Swift-native user service. It
reconciles the Life OS GitHub Project and uses GitHub as the workflow source of
truth.

It does not require a Python daemon, a local task database, Cloudflare, or a
message queue.

## Config

`bin/shadowd` chooses config in this order:

1. `SMART_SHADOW_CONFIG` when it points to a `.json` file.
2. `config/smart-shadow.json` when present.
3. `config/smart-shadow.example.json` as the checked-in fallback.

For local verification, start with:

```bash
cp config/smart-shadow.example.json config/smart-shadow.json
swift build --product shadowd
bin/shadowd once --dry-run
```

`shadowd` defaults to:

- GitHub owner: `longbiaochen`
- Project number: `1`
- Repository filter: `longbiaochen/life-os`

Override these for diagnostics:

```bash
bin/shadowd once --dry-run --owner longbiaochen --project 1 --repo longbiaochen/life-os
```

## GitHub Access

`shadowd` uses `gh api graphql` for Project reads. Authenticate `gh` with an
account or token that can read the Life OS Project and the `life-os` issues:

```bash
gh auth status
```

The reconciler must not rely on `smartshadow` labels. Project membership is the
intake boundary.

## Smoke Test

Run the fixture-backed test first:

```bash
tests/github_issue_workflow_cli.sh
```

Then run a live dry-run:

```bash
bin/shadowd once --dry-run
```

Expected output includes:

- `mode: github_project_reconciler`
- `source_of_truth: github_project_issue_pr`
- `local_task_db: false`
- `requires_smartshadow_label: false`

`bin/shadowd once` and `bin/shadowd run` are write-gated. They compute the
same reconcile plan but do not write GitHub comments unless `--write-comments`
is supplied.

## Continuous Run

```bash
bin/shadowd install
bin/shadowd status
bin/shadowd logs
```

The LaunchAgent label is `me.longbiaochen.shadowd`. It runs:

```bash
bin/shadowd run
```

Logs are written under:

```text
var/logs/shadowd.out.log
var/logs/shadowd.err.log
```
