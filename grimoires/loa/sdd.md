# SDD: Construct-Aware Constraint Yielding

> Cycle: cycle-029 | Author: janitooor + Claude
> Source PRD: `grimoires/loa/prd.md` ([#376](https://github.com/0xHoneyJar/loa/issues/376))
> Related: [loa-constructs#129](https://github.com/0xHoneyJar/loa-constructs/issues/129)

---

## 1. Executive Summary

This cycle makes Loa's constraint enforcement construct-aware. When a construct pack declares a `workflow` section in its manifest, Loa yields pipeline constraints for gates the construct marks as `skip`. The implementation touches three enforcement layers: the constraint data model (JSON), the constraint renderer (shell script), and command pre-flight checks (YAML frontmatter in .md files). A new state file (`.run/construct-workflow.json`) bridges construct detection to pre-flight enforcement.

**Key design principle**: All changes are additive. Default behavior is unchanged. Constructs without a `workflow` section use the full pipeline exactly as they do today.

---

## 2. System Architecture

### 2.1 Three-Layer Enforcement Model

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: Prompt-Level (constraints.json → CLAUDE.md) │
│  ┌─────────────┐    ┌──────────────────┐             │
│  │ constraints  │───▶│ generate-        │───▶ CLAUDE.md│
│  │ .json        │    │ constraints.sh   │    tables    │
│  │ +construct   │    │ (yield clause    │             │
│  │  _yield      │    │  rendering)      │             │
│  └─────────────┘    └──────────────────┘             │
├─────────────────────────────────────────────────────┤
│  Layer 2: Pre-flight (command .md YAML frontmatter)  │
│  ┌─────────────┐    ┌──────────────────┐             │
│  │ .run/        │◀───│ construct-       │             │
│  │ construct-   │    │ workflow-        │             │
│  │ workflow.json│    │ activate.sh      │             │
│  └──────┬──────┘    └──────────────────┘             │
│         │                                             │
│         ▼                                             │
│  ┌─────────────┐                                     │
│  │ audit-sprint │ reads construct-workflow.json       │
│  │ .md preflight│ skips "All good" check if          │
│  │              │ construct declares review: skip     │
│  └─────────────┘                                     │
├─────────────────────────────────────────────────────┤
│  Layer 3: Safety Hooks (NO CHANGES)                  │
│  block-destructive-bash.sh, team-skill-guard.sh      │
│  These protect System Zone, not pipeline flow.        │
└─────────────────────────────────────────────────────┘
```

### 2.2 Component Overview

| Component | Type | File(s) | FR |
|-----------|------|---------|-----|
| Manifest Workflow Reader | Shell script | `.claude/scripts/construct-workflow-read.sh` | FR-1 |
| Construct Workflow Activator | Shell script | `.claude/scripts/construct-workflow-activate.sh` | FR-2 |
| Construct Workflow State | JSON state file | `.run/construct-workflow.json` | FR-2 |
| Constraint Data Model | JSON fields | `.claude/data/constraints.json` | FR-3 |
| Constraint Renderer | Shell script patch | `.claude/scripts/generate-constraints.sh` | FR-3 |
| Command Pre-flight Checks | YAML frontmatter | `.claude/commands/audit-sprint.md`, `review-sprint.md` | FR-4 |
| Lifecycle Event Logger | Shell script | `.claude/scripts/construct-workflow-activate.sh` (reused) | FR-5 |
| Test Suite | Bash tests | `tests/test_construct_workflow.sh` | All |

---

## 3. Component Design

### 3.1 Manifest Workflow Reader (`construct-workflow-read.sh`)

**Purpose**: Read and validate the `workflow` section from a pack's manifest.json.

**Location**: `.claude/scripts/construct-workflow-read.sh`

**Interface**:
```bash
# Read workflow from manifest
construct-workflow-read.sh <manifest_path>
# → Outputs JSON workflow object to stdout
# → Exit 0: valid workflow found
# → Exit 1: no workflow section (pack uses default pipeline)
# → Exit 2: validation error (invalid values)

# Validate a specific gate
construct-workflow-read.sh <manifest_path> --gate <gate_name>
# → Outputs gate value (skip|condense|full|required|visual|textual|both|lightweight)
# → Exit 0: gate found
# → Exit 1: no workflow section
# → Exit 2: invalid gate value
```

**Validation Rules**:

| Field | Valid Values | Default | Constraint |
|-------|-------------|---------|------------|
| `workflow.depth` | `light`, `standard`, `deep`, `full` | `full` | — |
| `workflow.app_zone_access` | `true`, `false` | `false` | — |
| `workflow.gates.prd` | `skip`, `condense`, `full` | `full` | — |
| `workflow.gates.sdd` | `skip`, `condense`, `full` | `full` | — |
| `workflow.gates.sprint` | `skip`, `condense`, `full` | `full` | — |
| `workflow.gates.implement` | `required` | `required` | Cannot be `skip` |
| `workflow.gates.review` | `skip`, `visual`, `textual`, `both` | `textual` | — |
| `workflow.gates.audit` | `skip`, `lightweight`, `full` | `full` | — |
| `workflow.verification.method` | `visual`, `tsc`, `build`, `test`, `manual` | `test` | — |

**`condense` handling**: Accepted as valid value but logged as advisory. Treated as `full` for enforcement purposes this cycle.

**Implementation**:
```bash
#!/usr/bin/env bash
set -euo pipefail

MANIFEST="$1"
MODE="${2:---read}"  # --read or --gate

# Fail-closed: any parse error → exit 1 (no workflow)
workflow=$(jq -e '.workflow // empty' "$MANIFEST" 2>/dev/null) || exit 1

if [[ "$MODE" == "--gate" ]]; then
    GATE="$3"
    value=$(echo "$workflow" | jq -r --arg g "$GATE" '.gates[$g] // "full"')

    # Validate implement cannot be skip
    if [[ "$GATE" == "implement" && "$value" == "skip" ]]; then
        echo "ERROR: implement gate cannot be skip" >&2
        exit 2
    fi

    # Log condense advisory
    if [[ "$value" == "condense" ]]; then
        echo "ADVISORY: condense treated as full this cycle" >&2
    fi

    echo "$value"
else
    # Full validation
    validate_workflow "$workflow" || exit 2
    echo "$workflow"
fi
```

### 3.1.1 Activation Integration Point

**Who calls activate?** Construct SKILL.md files include an activation preamble. When a construct agent starts, it checks if its pack manifest declares `workflow` and calls `construct-workflow-activate.sh activate` before beginning work. This is consistent with existing patterns (e.g., beads sync at session start).

**Protocol addition**: `.claude/protocols/construct-workflow-activation.md` documents the activation contract. Construct SKILL.md files reference this protocol.

**Activation sequence**:
1. User invokes construct skill (e.g., `/observe`)
2. Agent reads its SKILL.md which includes activation protocol reference
3. Agent calls `construct-workflow-activate.sh activate --manifest <path>`
4. State file created → pre-flight checks can read it
5. On workflow completion, agent calls `construct-workflow-activate.sh deactivate`

### 3.2 Construct Workflow Activator (`construct-workflow-activate.sh`)

**Purpose**: Write/clear `.run/construct-workflow.json` and log lifecycle events.

**Location**: `.claude/scripts/construct-workflow-activate.sh`

**Interface**:
```bash
# Activate construct workflow
construct-workflow-activate.sh activate \
    --construct "pack-name" \
    --slug "pack-slug" \
    --manifest "/path/to/manifest.json"
# → Creates .run/construct-workflow.json
# → Logs construct.workflow.started to .run/audit.jsonl
# → Exit 0: success

# Deactivate construct workflow
construct-workflow-activate.sh deactivate
# → Removes .run/construct-workflow.json
# → Logs construct.workflow.completed to .run/audit.jsonl
# → Exit 0: success (also if no active workflow)

# Check if construct workflow is active
construct-workflow-activate.sh check
# → Exit 0: active (outputs JSON)
# → Exit 1: not active

# Check specific gate
construct-workflow-activate.sh gate <gate_name>
# → Outputs gate value
# → Exit 0: construct active and gate found
# → Exit 1: no active construct
```

### 3.3 Construct Workflow State File

**Location**: `.run/construct-workflow.json`

**Schema**:
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
- **Created**: When a skill from a pack with `workflow` declaration is invoked
- **Read**: By command pre-flight checks to determine gate status
- **Deleted**: When construct workflow completes or session ends
- **Never persisted to git**: `.run/` is gitignored

### 3.4 Constraint Data Model Changes

**File**: `.claude/data/constraints.json`

Add `construct_yield` field to four constraints:

```json
{
    "id": "C-PROC-001",
    "name": "no_code_outside_implement",
    "construct_yield": {
        "enabled": true,
        "condition": "construct with workflow.gates is active",
        "yield_text": "OR when a construct with declared `workflow.gates` owns the current workflow",
        "yield_on_gates": ["implement"]
    },
    ...existing fields...
}
```

| Constraint | `construct_yield.yield_text` | `yield_on_gates` |
|-----------|------------------------------|-------------------|
| C-PROC-001 | "OR when a construct with declared `workflow.gates` owns the current workflow" | `["implement"]` |
| C-PROC-003 | "OR when a construct with `workflow.gates` declares pipeline composition" | `["implement"]` |
| C-PROC-004 | "Yield when construct declares `review: skip` or `audit: skip`" | `["review", "audit"]` |
| C-PROC-008 | "Yield when construct declares `sprint: skip`" | `["sprint"]` |

**`yield_on_gates`** specifies which gates must be non-skip for the yield to apply. The name reads as "yield this constraint on these gates" — i.e., the constraint yields when these specific gates are declared by the construct. For C-PROC-001/003, the construct must still declare `implement: required` to yield the constraint. This prevents a construct from skipping ALL gates.

### 3.5 Constraint Renderer Changes

**File**: `.claude/scripts/generate-constraints.sh`

Modify the jq template for `process_compliance_never` and `process_compliance_always` sections to include yield clauses when `construct_yield.enabled` is true.

**Current render** (from jq template):
```
| NEVER {text} | {why} |
```

**New render** when `construct_yield` present:
```
| NEVER {text} ({yield_text}) | {why} |
```

**Implementation**: Add a jq filter that appends yield_text:

```jq
# In the process_compliance_never template
.text as $text |
if .construct_yield.enabled then
    "\($text) (\(.construct_yield.yield_text))"
else
    $text
end
```

The `generate-constraints.sh` script already uses `insert_generated_section()` with hash-based change detection, so regeneration is idempotent.

### 3.6 Command Pre-flight Changes

#### audit-sprint.md

**Current pre-flight** (line 64-67):
```yaml
- check: "content_contains"
  path: "grimoires/loa/a2a/$RESOLVED_SPRINT_ID/engineer-feedback.md"
  pattern: "All good"
  error: "Sprint has not been approved by senior lead."
```

**New pre-flight** — add construct-aware conditional:
```yaml
- check: "content_contains"
  path: "grimoires/loa/a2a/$RESOLVED_SPRINT_ID/engineer-feedback.md"
  pattern: "All good"
  error: "Sprint has not been approved by senior lead."
  skip_when:
    construct_gate: "review"
    gate_value: "skip"
```

The `skip_when` field is new. When present, the pre-flight check reads `.run/construct-workflow.json`, extracts the specified gate, and if the value matches `gate_value`, the check is skipped.

**Similarly for the file_exists check on engineer-feedback.md** (line 60-62):
```yaml
- check: "file_exists"
  path: "grimoires/loa/a2a/$RESOLVED_SPRINT_ID/engineer-feedback.md"
  error: "Sprint has not been reviewed."
  skip_when:
    construct_gate: "review"
    gate_value: "skip"
```

#### review-sprint.md

**Sprint.md dependency is in `context_files`, not `pre_flight`**: In review-sprint.md, the sprint.md requirement is listed under `context_files` with `required: true`. The `skip_when` mechanism applies to both pre-flight checks AND context file entries:

```yaml
context_files:
  - path: "grimoires/loa/sprint.md"
    required: true
    skip_when:
      construct_gate: "sprint"
      gate_value: "skip"
```

When `skip_when` is present on a context file entry, Claude treats the file as optional if the construct condition is met — the file is loaded if available but its absence does not block the command.

**Note**: The `skip_when` mechanism is interpreted by Claude when reading the command YAML frontmatter. Claude reads `.run/construct-workflow.json` to evaluate the condition. This is prompt-level enforcement, not programmatic — consistent with how all command frontmatter works today (Claude reads the YAML and follows the instructions). The mechanism applies uniformly to both `pre_flight` checks and `context_files` entries.

### 3.7 COMPLETED Marker for Construct Workflows

**Current**: Only `audit-sprint` creates the COMPLETED marker.

**New**: Add a `construct-workflow-complete.sh` script that creates the COMPLETED marker when a construct workflow finishes:

```bash
# construct-workflow-activate.sh deactivate --complete <sprint_id>
# → Creates grimoires/loa/a2a/<sprint_id>/COMPLETED
# → Clears .run/construct-workflow.json
# → Logs construct.workflow.completed
```

This is only used when the construct's declared workflow doesn't include audit (i.e., `audit: skip`). When audit IS included, the existing audit-sprint flow creates COMPLETED as before.

### 3.8 Lifecycle Event Logging

Events are appended to `.run/audit.jsonl` (existing audit log).

**Event schema**:
```json
{
    "timestamp": "2026-02-19T20:00:00Z",
    "event": "construct.workflow.started",
    "construct": "gtm-collective",
    "depth": "light",
    "gates": {"prd": "skip", "sdd": "skip", ...},
    "constraints_yielded": ["C-PROC-001", "C-PROC-003", "C-PROC-004"]
}
```

```json
{
    "timestamp": "2026-02-19T21:00:00Z",
    "event": "construct.workflow.completed",
    "construct": "gtm-collective",
    "outcome": "success",
    "duration_seconds": 3600
}
```

---

## 4. Data Architecture

### 4.1 New Fields in constraints.json

```json
{
    "construct_yield": {
        "enabled": true,
        "condition": "string — human-readable condition",
        "yield_text": "string — appended to constraint text in CLAUDE.md",
        "yield_on_gates": ["string — gates that trigger this yield"]
    }
}
```

Added to: C-PROC-001, C-PROC-003, C-PROC-004, C-PROC-008 (4 constraints).

### 4.2 New State File

`.run/construct-workflow.json` — schema defined in Section 3.3.

### 4.3 Manifest Extension (Reader Expectations)

The reader expects this structure in pack `manifest.json`:
```json
{
    "workflow": {
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
}
```

**Note**: The schema definition lives in loa-constructs#129. This SDD defines only what the Loa-side reader expects to parse.

---

## 5. Security Architecture

### 5.1 Trust Boundary

| Trust Level | What | How Enforced |
|-------------|------|--------------|
| **Installed construct** | Pack in `.claude/constructs/packs/` with valid license | License validation via `constructs-loader.sh` |
| **Declared workflow** | `workflow` section in pack manifest.json | Validated by `construct-workflow-read.sh` at activation time |
| **Runtime claim** | Dynamic claim of construct status | **BLOCKED** — construct-workflow.json can only be created by `construct-workflow-activate.sh` which reads the manifest |

### 5.2 Invariants

| Invariant | Enforcement |
|-----------|-------------|
| `implement: required` cannot be `skip` | Validated in construct-workflow-read.sh; exit 2 on violation |
| System Zone always protected | Safety hooks unchanged; construct_yield does not affect hook enforcement |
| Only installed packs can declare workflows | Activation requires manifest_path within `.claude/constructs/packs/` |
| Fail-closed on parse errors | jq parse failure → exit 1 → no workflow active → full pipeline |

### 5.3 Audit Trail

Every constraint yield is logged to `.run/audit.jsonl` with:
- Which constraint was yielded
- Which construct declared the yield
- What gate value triggered the yield
- Timestamp

This provides post-hoc auditability — if a construct bypassed review, the audit trail shows exactly when and why.

---

## 6. Testing Strategy

### 6.1 Test File

**Location**: `tests/test_construct_workflow.sh`

### 6.2 Test Cases

| Test | Description | FR |
|------|-------------|-----|
| Manifest read — valid workflow | Reads workflow from manifest with all gates | FR-1 |
| Manifest read — missing workflow | Returns exit 1 for pack without workflow | FR-1 |
| Manifest read — implement: skip rejected | Returns exit 2 when implement is skip | FR-1 |
| Manifest read — condense advisory | Accepts condense, logs advisory | FR-1 |
| Manifest read — invalid gate value | Returns exit 2 for unrecognized value | FR-1 |
| Activate — writes state file | Creates .run/construct-workflow.json | FR-2 |
| Activate — logs started event | Event in audit.jsonl | FR-2, FR-5 |
| Deactivate — clears state file | Removes .run/construct-workflow.json | FR-2 |
| Deactivate — logs completed event | Event in audit.jsonl | FR-2, FR-5 |
| Check — active construct | Returns 0 with JSON | FR-2 |
| Check — no active construct | Returns 1 | FR-2 |
| Gate check — returns gate value | Correct value from state file | FR-2 |
| Constraint yield text — rendered | CLAUDE.md includes yield clause | FR-3 |
| Constraint yield text — not rendered | Without construct_yield, no change | FR-3 |
| Audit pre-flight — review skip | "All good" check skipped when review: skip | FR-4 |
| Audit pre-flight — review full | "All good" check enforced when review: full | FR-4 |
| COMPLETED marker — construct workflow | Marker created via deactivate --complete | FR-4 |
| Default behavior — no manifest | Full pipeline enforced | NF-1 |
| Fail-closed — corrupt manifest | Parse error → full pipeline | NF-4 |

### 6.3 Existing Test Regression

All existing tests must pass unchanged:
- audit-logger.test.ts (19 tests)
- pii-redactor.test.ts (27 tests)
- test_run_state_verify.sh (7 tests)
- auth.test.ts (8 tests)
- All Python tests (24 tests)

---

## 7. File Change Summary

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/construct-workflow-read.sh` | **NEW** | Manifest workflow reader |
| `.claude/scripts/construct-workflow-activate.sh` | **NEW** | State file management + lifecycle events |
| `.claude/data/constraints.json` | MODIFY | Add `construct_yield` to 4 constraints |
| `.claude/scripts/generate-constraints.sh` | MODIFY | Render yield clause in constraint tables |
| `.claude/commands/audit-sprint.md` | MODIFY | Add `skip_when` to pre-flight checks |
| `.claude/commands/review-sprint.md` | MODIFY | Add `skip_when` for sprint.md check |
| `grimoires/loa/ledger.json` | MODIFY | Sprint registration (auto) |
| `tests/test_construct_workflow.sh` | **NEW** | Test suite |

**Total**: 3 new files, 5 modified files.

---

## 8. Risks & Mitigations

### Risk: generate-constraints.sh Template Change Breaks Existing Output

**Mitigation**: The script uses hash-based idempotency. Run `generate-constraints.sh --dry-run` to preview changes before committing. Test that all 4 modified constraints render correctly with yield text and that all OTHER constraints render identically to before.

### Risk: skip_when Misinterpreted by Claude

**Mitigation**: `skip_when` is a new field type in command YAML frontmatter. Claude reads this as an instruction — "skip this check when condition is met." Include clear comments in the YAML explaining the semantics. Test with both active and inactive construct workflows.

### Risk: Stale construct-workflow.json Left Behind

**Mitigation**: The deactivation script is called explicitly. Additionally, all Loa session-end hooks should clean `.run/construct-workflow.json` as a safety net. If the file exists but is >24h old, treat it as stale and ignore it.

---

## 9. Implementation Order

| Sprint | Tasks | Dependencies |
|--------|-------|-------------|
| Sprint 1 | FR-1 (manifest reader) + FR-2 (activator + state file) | None |
| Sprint 2 | FR-3 (constraints.json + renderer) + FR-4 (command pre-flights) | Sprint 1 |
| Sprint 3 | FR-5 (lifecycle events) + test suite + integration verification | Sprint 2 |
