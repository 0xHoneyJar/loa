---
name: validating-construct-manifest
description: Pre-install / pre-publish manifest linter for construct packs. Emits Verdict stream rows on findings. Gates `constructs install` and `constructs publish` against F28-class breakage and SEED §12 grimoires-convention drift.
---

# Validating Construct Manifest

> Caught at install-time is cheap. Caught at publish-time still cheap. Caught by an operator at `/feel` not resolving is expensive.

## Purpose

Validate a construct pack directory before it lands in a registry or a local install. Surfaces:

1. **Required-field gates** — missing `schema_version`, `slug`, `name`, `version`, `description` in `construct.yaml`
2. **Path resolution** — `skills[].path` and `commands[].path` entries that don't resolve
3. **F28 closure** — pack declares neither `commands:` nor persona handles (operator can only route by slug/name)
4. **Stream declarations** — empty `reads:` / `writes:` arrays (doctrine §3 pipe compatibility is ambiguous)
5. **SEED §12 grimoires convention** — `CLAUDE.md` must contain an explicit `grimoires/<path>` read/write declaration; known drift surfaces here

Each finding is a **Verdict stream row** (doctrine §3.2) — severity-tagged, evidence-cited, pipeable downstream.

## Invocation

```bash
# Run directly (shell-first, no agent needed)
.claude/scripts/construct-validate.sh <pack-path>
.claude/scripts/construct-validate.sh <pack-path> --json     # Verdict[] on stdout
.claude/scripts/construct-validate.sh <pack-path> --strict   # MEDIUM → exit 1
```

Install / publish integration:

- `constructs-install.sh` calls the validator after license check. Findings print to the console. Set `LOA_STRICT_VALIDATION=1` to abort install on HIGH/CRITICAL.
- `constructs-publish.sh` adds a `manifest_validate` check to the 10-point pre-publish report.

## Severity tiers

| Tier | Meaning | Install behavior | Publish behavior |
|------|---------|------------------|------------------|
| `critical` | `construct.yaml` missing or unparseable | Always blocks | Always blocks |
| `high`     | Required field missing / broken path | Warn by default, block with `LOA_STRICT_VALIDATION=1` | Blocks |
| `medium`   | F28 route gap, §12 grimoires drift | Advisory | Advisory (unless `--strict`) |
| `low`      | Empty stream declarations | Advisory | Advisory |
| `info`     | All checks passed | — | — |

## Checks in detail

### 1 · construct.yaml presence + parseability (`critical`)

The manifest must exist and yq must parse it. This is the only unrecoverable failure.

### 2 · Required fields (`high`)

`schema_version`, `slug`, `name`, `version`, `description` must all be non-empty. These power the registry listing + resolver tiers.

### 3 · Skill path resolution (`high`)

Every entry in `skills: [{path}]` must resolve to a directory (or symlink) under the pack root.

### 4 · Command path resolution (`high`)

Every entry in `commands: [{path}]` must resolve to a file. Rosenzu-class breakage (commands pointing at skill directories) surfaces here.

### 5 · F28 route declaration (`medium`)

If the pack declares no `commands:` AND no persona handles (either via `personas:` in yaml or `identity/<HANDLE>.md` filenames), the operator can only route by slug/name. This surfaces the gap that made `/feel` un-resolvable in cycle-004.

### 6 · Stream declarations (`low`)

Per doctrine §3, packs should declare `reads:` and `writes:` stream types so the composition runner can verify pipe compatibility. Empty arrays are advisory-level.

### 7 · SEED §12 grimoires convention (`medium`)

`CLAUDE.md` must reference `grimoires/<path>` AND include at least one of: `Writes to`, `Reads from`, `writes:`, `reads:`. This is the convention the `construct-base` template already enforces; installed packs that pre-date the template drifted.

The canary here is `artisan` — its `construct.yaml` declares grimoire paths, but its `CLAUDE.md` does not mirror them. L6 butterfreezone adapter regenerates the missing section.

## Output shape

Default (human-readable):

```
# construct-validate · /Users/.../packs/artisan
  [low] [streams] construct declares no 'reads:' stream types — pipe composition will be ambiguous
    → /Users/.../packs/artisan/construct.yaml
  [medium] [grimoires_section] CLAUDE.md contains no grimoires/ path reference — SEED §12
    → /Users/.../packs/artisan/CLAUDE.md
# worst: medium · total: 2
```

`--json` emits a JSON array of Verdict rows conforming to `.claude/schemas/verdict.schema.json`. Each row carries:

- `stream_type: "Verdict"`
- `severity`: critical | high | medium | low
- `verdict`: `[<check>] <message>`
- `evidence`: `[<file path>]`
- `subject`: pack path
- `tags`: `[<check name>]`

Downstream tools (e.g. `constructs-publish.sh`, dashboard surfaces, CI lint jobs) can consume this array directly.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | No HIGH or CRITICAL findings (MEDIUM passes unless `--strict`) |
| 1 | At least one HIGH/CRITICAL finding, or MEDIUM with `--strict` |
| 2 | Pack path does not exist / required tooling missing |

## Relationship to other validators

- `constructs-loader.sh validate-pack` — license validation, retained alongside
- `validate-pack-manifests.mjs` — Zod-based manifest schema check (sandbox packs)
- `construct-validate.sh` (this) — ecosystem-wide cycle-005 checks, Verdict-emitting

## Related

- Script: `.claude/scripts/construct-validate.sh`
- Schema: `.claude/schemas/verdict.schema.json`
- Doctrine: `grimoires/loa-constructs-seed-2026-04-21/bonfire-construct-pipe-doctrine.md` §3.2, §14.2
- SEED: `grimoires/loa-constructs-seed-2026-04-21/cycle-005-SEED-runtime-integration.md` L4 + §12
- Sibling skills: `publishing-constructs`, `browsing-constructs`
