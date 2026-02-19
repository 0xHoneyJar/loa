# Construct Workflow Activation Protocol

> **Version**: 1.0.0
> **Status**: Active
> **Added**: v1.40.0 (cycle-029)
> **Philosophy**: "Constructs compose the pipeline at their chosen depth."

---

## Overview

When a construct pack declares a `workflow` section in its `manifest.json`, Loa's constraint enforcement yields for gates the construct marks as `skip`. This protocol defines how construct SKILL.md files activate and deactivate workflow ownership.

---

## Design Principles

1. **Explicit activation**: Constructs opt-in to workflow ownership by calling the activation script
2. **Fail-closed**: If activation fails, the full pipeline applies (no silent bypass)
3. **Installed packs only**: Manifest must be within `.claude/constructs/packs/` (no runtime injection)
4. **Observable**: Every activation/deactivation is logged to `.run/audit.jsonl`
5. **Clean lifecycle**: Deactivation always runs, even if the workflow fails

---

## Activation Preamble for SKILL.md

Construct SKILL.md files should include this preamble at the start of their workflow:

```bash
# ── Construct Workflow Activation ──────────────────────
# Check if this pack declares workflow ownership
MANIFEST_PATH=".claude/constructs/packs/<pack-slug>/manifest.json"
PACK_NAME="<Pack Name>"
PACK_SLUG="<pack-slug>"

if jq -e '.workflow' "$MANIFEST_PATH" >/dev/null 2>&1; then
  .claude/scripts/construct-workflow-activate.sh activate \
    --construct "$PACK_NAME" \
    --slug "$PACK_SLUG" \
    --manifest "$MANIFEST_PATH"
fi
```

And this cleanup at the end:

```bash
# ── Construct Workflow Deactivation ────────────────────
.claude/scripts/construct-workflow-activate.sh deactivate
```

If the construct's workflow doesn't include audit (i.e., `audit: skip`), use `--complete` to create the COMPLETED marker:

```bash
.claude/scripts/construct-workflow-activate.sh deactivate --complete sprint-22
```

---

## Script Reference

### construct-workflow-read.sh

Reads and validates the `workflow` section from a pack manifest.

```bash
# Full read — outputs workflow JSON to stdout
.claude/scripts/construct-workflow-read.sh <manifest_path>
# Exit 0: valid workflow | Exit 1: no workflow | Exit 2: validation error

# Query specific gate
.claude/scripts/construct-workflow-read.sh <manifest_path> --gate review
# Outputs: skip | visual | textual | both
```

### construct-workflow-activate.sh

Manages workflow state and lifecycle events.

| Subcommand | Description | Exit 0 | Exit 1 |
|------------|-------------|--------|--------|
| `activate` | Creates `.run/construct-workflow.json`, logs started event | Success | — |
| `deactivate` | Removes state file, logs completed event | Success (even if no active workflow) | — |
| `check` | Returns current state as JSON | Active workflow exists | No active workflow |
| `gate <name>` | Returns value of specific gate | Gate found | No active workflow |

#### activate

```bash
.claude/scripts/construct-workflow-activate.sh activate \
  --construct "GTM Collective" \
  --slug "gtm-collective" \
  --manifest ".claude/constructs/packs/gtm-collective/manifest.json"
```

#### deactivate

```bash
# Simple deactivation
.claude/scripts/construct-workflow-activate.sh deactivate

# With COMPLETED marker for audit-skip constructs
.claude/scripts/construct-workflow-activate.sh deactivate --complete sprint-22
```

#### check

```bash
# Returns JSON state or exit 1
state=$(.claude/scripts/construct-workflow-activate.sh check) || echo "no active construct"
```

#### gate

```bash
# Returns gate value (e.g., "skip", "full", "visual")
review_gate=$(.claude/scripts/construct-workflow-activate.sh gate review)
```

---

## State File Schema

### .run/construct-workflow.json

```json
{
  "construct": "GTM Collective",
  "slug": "gtm-collective",
  "manifest_path": ".claude/constructs/packs/gtm-collective/manifest.json",
  "activated_at": "2026-02-19T20:00:00Z",
  "depth": "light",
  "app_zone_access": true,
  "gates": {
    "prd": "skip",
    "sdd": "skip",
    "sprint": "condense",
    "implement": "required",
    "review": "visual",
    "audit": "skip"
  },
  "verification": {
    "method": "visual"
  }
}
```

**Lifecycle**:
- **Created**: On `activate` subcommand
- **Read**: By command pre-flight checks (`skip_when` conditions)
- **Deleted**: On `deactivate` subcommand
- **Staleness**: Ignored if >24h old (treated as no active workflow)
- **Never persisted to git**: `.run/` is gitignored

---

## Security Invariants

| Invariant | Enforcement |
|-----------|-------------|
| Only installed packs can activate | Manifest path must be within `.claude/constructs/packs/` |
| `implement: required` cannot be `skip` | Validated by reader; exit 2 on violation |
| System Zone always protected | Safety hooks unchanged; construct_yield does not affect hooks |
| Fail-closed on errors | Parse failure → exit 1 → no workflow → full pipeline |
| Observable | Every activation/deactivation logged to audit trail |

---

## Audit Trail

Events are logged to `.run/audit.jsonl`:

```jsonl
{"timestamp":"2026-02-19T20:00:00Z","event":"construct.workflow.started","construct":"gtm-collective","depth":"light","gates":{"prd":"skip","sdd":"skip","sprint":"condense","implement":"required","review":"visual","audit":"skip"},"constraints_yielded":["C-PROC-001","C-PROC-003","C-PROC-004"]}
{"timestamp":"2026-02-19T21:00:00Z","event":"construct.workflow.completed","construct":"gtm-collective","outcome":"success","duration_seconds":3600}
```

---

## Related

- `.claude/data/constraints.json` — Constraint definitions with `construct_yield` field
- `.claude/scripts/generate-constraints.sh` — Renders constraints into CLAUDE.md
- `.claude/commands/audit-sprint.md` — Pre-flight checks with `skip_when` conditions
- `.claude/commands/review-sprint.md` — Context files with `skip_when` conditions
