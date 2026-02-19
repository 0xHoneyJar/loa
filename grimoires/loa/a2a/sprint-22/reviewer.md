# Implementation Report: Sprint 1 — Manifest Reader + Workflow Activator

**Sprint**: sprint-1 (global sprint-22)
**Cycle**: cycle-029 — Construct-Aware Constraint Yielding
**Date**: 2026-02-19

---

## Task 1.1: Manifest Workflow Reader Script

**File**: `.claude/scripts/construct-workflow-read.sh` (NEW, 156 lines)
**Status**: COMPLETE

### Implementation

Shell script that reads and validates `workflow` section from pack manifest.json. Two modes:
- **Full read** (`--read`): Validates all fields, outputs workflow JSON to stdout
- **Gate query** (`--gate <name>`): Outputs single gate value

### Validation Rules Implemented

| Field | Valid Values | Default | Enforced |
|-------|-------------|---------|----------|
| `depth` | light, standard, deep, full | full | Exit 2 on invalid |
| `app_zone_access` | true, false | false | Exit 2 on non-boolean |
| `gates.prd` | skip, condense, full | full | Exit 2 on invalid |
| `gates.sdd` | skip, condense, full | full | Exit 2 on invalid |
| `gates.sprint` | skip, condense, full | full | Exit 2 on invalid |
| `gates.implement` | required | required | Exit 2 on `skip` |
| `gates.review` | skip, visual, textual, both | textual | Exit 2 on invalid |
| `gates.audit` | skip, lightweight, full | full | Exit 2 on invalid |
| `verification.method` | visual, tsc, build, test, manual | test | Exit 2 on invalid |

### Key Behaviors

- **`condense` advisory**: Accepted but logs `ADVISORY: condense treated as full this cycle` to stderr
- **Fail-closed**: jq parse errors → exit 1 (no workflow, full pipeline applies)
- **`implement: skip` blocked**: Always exit 2 — cannot bypass implementation
- **Defaults applied**: Missing optional fields get conservative defaults

### Smoke Test Results

| Test | Result |
|------|--------|
| Valid manifest with all gates | PASS — JSON output correct |
| Gate query (--gate review) | PASS — returns "visual" |
| No workflow section | PASS — exit 1 |
| implement: skip rejection | PASS — exit 2 with error message |
| condense advisory | PASS — advisory logged to stderr |

---

## Task 1.2: Construct Workflow Activator Script

**File**: `.claude/scripts/construct-workflow-activate.sh` (NEW, 209 lines)
**Status**: COMPLETE

### Implementation

Four subcommands managing `.run/construct-workflow.json` lifecycle:

| Subcommand | Action | Exit 0 | Exit 1 | Exit 2 |
|------------|--------|--------|--------|--------|
| `activate` | Creates state file, logs started event | Success | — | Validation error |
| `deactivate` | Removes state file, logs completed event | Always (idempotent) | — | — |
| `check` | Returns current state JSON | Active | Not active | — |
| `gate <name>` | Returns specific gate value | Found | Not active | Invalid gate |

### Security Invariants Enforced

1. **Manifest path validation**: `realpath` checked against `.claude/constructs/packs/` prefix — rejects any manifest outside the packs directory
2. **Reader delegation**: Calls `construct-workflow-read.sh` internally for validation — no duplicate validation logic
3. **Staleness check**: State files >24h old treated as inactive (stale)

### Lifecycle Events

Both `activate` and `deactivate` log to `.run/audit.jsonl`:

- `construct.workflow.started`: timestamp, construct, depth, gates, constraints_yielded
- `construct.workflow.completed`: timestamp, construct, outcome, duration_seconds

### Constraint Yield Computation

On activation, computes which C-PROC constraints would yield:
- C-PROC-001/003: Always yielded (construct has implement: required by definition)
- C-PROC-004: Yielded when review OR audit is "skip"
- C-PROC-008: Yielded when sprint is "skip"

### `--complete` Flag

`deactivate --complete <sprint_id>` creates COMPLETED marker at `grimoires/loa/a2a/<sprint_id>/COMPLETED` for constructs that skip the audit gate.

### Smoke Test Results

| Test | Result |
|------|--------|
| Activate with valid manifest | PASS — state file created with all fields |
| Security: manifest outside packs/ | PASS — exit 2, rejected |
| Check when active | PASS — JSON output |
| Check when not active | PASS — exit 1 |
| Gate query (review) | PASS — returns "skip" |
| Deactivate | PASS — state file removed |
| Deactivate when already inactive | PASS — exit 0 (idempotent) |
| Audit log: started event | PASS — correct schema |
| Audit log: completed event | PASS — correct schema with duration |
| Constraints yielded computation | PASS — all 4 C-PROC constraints yielded for full-skip manifest |

---

## Task 1.3: Activation Protocol Document

**File**: `.claude/protocols/construct-workflow-activation.md` (NEW, 175 lines)
**Status**: COMPLETE

### Content

- Activation preamble pattern for construct SKILL.md files
- Full script reference with subcommands and exit codes
- State file schema documentation
- Security invariants table
- Audit trail format with examples
- Related files reference

---

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `.claude/scripts/construct-workflow-read.sh` | NEW | 156 |
| `.claude/scripts/construct-workflow-activate.sh` | NEW | 209 |
| `.claude/protocols/construct-workflow-activation.md` | NEW | 175 |

**Total**: 3 new files, 540 lines.

## Acceptance Criteria Checklist

### Task 1.1
- [x] Reads `workflow` section from manifest.json via jq
- [x] Exit 0 with valid workflow JSON on stdout
- [x] Exit 1 when no workflow section
- [x] Exit 2 on validation error
- [x] `--gate <name>` mode outputs single gate value
- [x] Validates all gate values against allowed sets
- [x] `implement: required` enforced
- [x] `condense` accepted with advisory
- [x] Defaults applied for missing fields
- [x] Fail-closed on parse errors

### Task 1.2
- [x] `activate` creates `.run/construct-workflow.json`
- [x] State file contains all required fields
- [x] Activation calls reader internally
- [x] Activation fails on reader errors
- [x] `deactivate` removes state file (idempotent)
- [x] `deactivate --complete` creates COMPLETED marker
- [x] `check` returns JSON when active, exit 1 when not
- [x] `gate` returns value when active, exit 1 when not
- [x] Manifest path validated within packs directory

### Task 1.3
- [x] Protocol document with activation sequence
- [x] Example preamble code
- [x] All subcommands and exit codes documented
- [x] Security invariants referenced
