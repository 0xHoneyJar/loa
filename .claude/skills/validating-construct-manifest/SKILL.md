---
name: validating-construct-manifest
description: Pre-install / pre-publish manifest linter for construct packs. Emits Verdict stream rows on findings. Checks required manifest fields, path resolution, route declarations, and the CLAUDE.md grimoires-section convention.
---

# Validating Construct Manifest

> Caught at install-time is cheap. Caught at publish-time still cheap. Caught by an operator at a slash command not resolving is expensive.

## Purpose

Validate a construct pack directory before it lands in a registry or a local install. Surfaces:

1. **Required-field gates** — missing `schema_version`, `slug`, `name`, `version`, `description` in `construct.yaml`
2. **Path resolution** — `skills[].path` and `commands[].path` entries that don't resolve
3. **Route declaration** — pack declares neither `commands:` nor persona handles, so an operator can only route by slug/name (skill bindings unreachable)
4. **Stream declarations** — empty `reads:` / `writes:` arrays make pipe composition ambiguous
5. **Grimoires-section convention** — `CLAUDE.md` must contain an explicit `grimoires/<path>` read/write declaration so the pack's interface contract is legible

Each finding is a **Verdict stream row** — severity-tagged, evidence-cited, pipeable downstream into another construct or a CI lint job.

## Concepts referenced by these checks

The validator's checks operationalize three conventions used by the construct typed-stream model:

- **Typed streams**: stream rows carry `stream_type`, `schema_version`, `timestamp`, `source`. The five canonical stream types — `Signal`, `Verdict`, `Artifact`, `Intent`, `Operator-Model` — have schemas at `.claude/schemas/<type>.schema.json`. Packs declare which stream types they `reads:` and `writes:` so a composition runner can verify pipe compatibility before stages execute.
- **Route declaration (Check 5)**: a pack must expose at least one *operator-callable* entry point — either via the `commands:` array in `construct.yaml`, or via a persona definition (a `personas:` list in `construct.yaml`, or `identity/<HANDLE>.md` files where `<HANDLE>` is uppercase). Without either, the operator can't dispatch into the pack's skills directly. This was a routing-gap class of breakage observed during cycle-004.
- **Grimoires-section convention (Check 7)**: the pack's `CLAUDE.md` is the operator-facing description, and the `grimoires/<path>` declarations in it are the pack's interface contract — they tell every other construct in the network what state this pack reads and writes. CLAUDE.md without a grimoires section means the pack is opaque to composition planning.

## Invocation

```bash
# Run directly (shell-first, no agent needed)
.claude/scripts/construct-validate.sh <pack-path>
.claude/scripts/construct-validate.sh <pack-path> --json     # Verdict[] on stdout
.claude/scripts/construct-validate.sh <pack-path> --strict   # MEDIUM → exit 1
```

Install / publish integration:

- `constructs-install.sh` does **not yet** call this validator. Wiring it in (after the existing license check) is tracked for a follow-up cycle. Until then, run `construct-validate.sh` manually before publishing.
- `constructs-publish.sh` (when it lands) is the natural integration point — a `manifest_validate` check fits cleanly in its pre-publish report.

## Severity tiers

| Tier | Meaning | Install behavior (when wired) | Publish behavior (when wired) |
|------|---------|------------------|------------------|
| `critical` | `construct.yaml` missing or unparseable | Always blocks | Always blocks |
| `high`     | Required field missing / broken path | Warn by default, block with `LOA_STRICT_VALIDATION=1` | Blocks |
| `medium`   | Route gap, grimoires-section drift | Advisory | Advisory (unless `--strict`) |
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

Every entry in `commands: [{path}]` must resolve to a **file**. A common drift class is commands pointing at skill *directories* — that fails resolution at install time.

### 5 · Route declaration (`medium`)

If the pack declares no `commands:` AND no persona handles (either via `personas:` in yaml or `identity/<HANDLE>.md` filenames), the operator can only route by slug/name. Cycle-004 surfaced this as the gap that made certain commands unresolvable.

### 6 · Stream declarations (`low`)

Packs should declare `reads:` and `writes:` stream types so the composition runner can verify pipe compatibility. Empty arrays are advisory-level — composition still runs, but with no edge-of-pipe type guarantee.

### 7 · Grimoires-section convention (`medium`)

`CLAUDE.md` must reference `grimoires/<path>` AND include at least one of: `Writes to`, `Reads from`, `writes:`, `reads:`. This is the convention the `construct-base` template enforces; installed packs that pre-date that template tend to drift.

## Output shape

Default (human-readable):

```
# construct-validate · /path/to/packs/example-pack
  [low] [streams] construct declares no 'reads:' stream types — pipe composition will be ambiguous
    → /path/to/packs/example-pack/construct.yaml
  [medium] [grimoires_section] CLAUDE.md contains no grimoires/ path reference
    → /path/to/packs/example-pack/CLAUDE.md
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
- Stream-type schemas: `.claude/schemas/{signal,verdict,artifact,intent,operator-model}.schema.json`
- Sibling skills: `browsing-constructs` (existing). A `publishing-constructs` skill is referenced for forward composition; it lands in a follow-up cycle.
