# GitHub Permissions For shadowd

`shadowd` uses GitHub GraphQL and selected `gh` CLI mutations against the
`life-os` repository and the Life OS GitHub Project.

## Required Repository Permissions

The authenticated `gh` account must be able to:

- Read repository contents.
- Read issues.
- Create issue comments.
- Edit issue titles, bodies, and labels only when a specific reconcile action
  requires it.

For a fine-grained personal access token, grant access to the `life-os` repo with:

- Contents: read.
- Issues: read and write.
- Metadata: read-only.

## Required Project Permission

`shadowd` must be able to read the Life OS GitHub Project because Project
membership is the queue boundary. When status alignment is enabled, it must also
be able to edit Project item fields.

The default Project address is user `longbiaochen`, Project number `1`.
Override it with CLI flags for diagnostics:

```bash
bin/shadowd once --dry-run --owner longbiaochen --project 1 --repo longbiaochen/life-os
```

Do not rely on the `smartshadow` label as the intake filter. The label is useful
for identifying Smart Shadow-created voice tasks, but `shadowd` must inspect the
whole Life OS Project.
