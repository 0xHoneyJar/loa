# Implementation Report: Sprint 2 — Constraint Yielding + Pre-flight Integration

**Sprint**: sprint-2 (global sprint-23)
**Cycle**: cycle-029 — Construct-Aware Constraint Yielding
**Date**: 2026-02-19

---

## Task 2.1: Constraint Data Model — Add `construct_yield` Field

**File**: `.claude/data/constraints.json` (MODIFIED)
**Status**: COMPLETE

### Implementation

Added `construct_yield` object to four constraints:

| Constraint | `yield_text` | `yield_on_gates` |
|-----------|-------------|-------------------|
| C-PROC-001 | "OR when a construct with declared `workflow.gates` owns the current workflow" | `["implement"]` |
| C-PROC-003 | "OR when a construct with `workflow.gates` declares pipeline composition" | `["implement"]` |
| C-PROC-004 | "Yield when construct declares `review: skip` or `audit: skip`" | `["review", "audit"]` |
| C-PROC-008 | "Yield when construct declares `sprint: skip`" | `["sprint"]` |

Each `construct_yield` object contains:
- `enabled`: true
- `condition`: human-readable condition description
- `yield_text`: text appended to rendered constraint
- `yield_on_gates`: array of gates that trigger yielding

### Verification

- JSON validates: `jq empty constraints.json` → exit 0
- Exactly 4 constraints have `construct_yield`: verified with jq query
- All other constraints unchanged: no unintended modifications

---

## Task 2.2: Constraint Renderer — Yield Clause Rendering

**Files**: `.claude/templates/constraints/claude-loa-md-table.jq` (MODIFIED), `.claude/loa/CLAUDE.loa.md` (REGENERATED)
**Status**: COMPLETE

### Implementation

Modified the jq template to append yield_text in parentheses when `construct_yield.enabled` is true:

```jq
| (
    if .construct_yield and .construct_yield.enabled then
      $base_rule + " (" + .construct_yield.yield_text + ")"
    else
      $base_rule
    end
  ) as $rule
```

Backward compatible: constraints without `construct_yield` render identically.

### Regeneration

- `generate-constraints.sh --dry-run` showed expected diffs (4 yield clauses added)
- `generate-constraints.sh` executed successfully: 5 targets updated
- Idempotency verified: second `--dry-run` shows no diff
- `@loa-managed` hash updated automatically

### CLAUDE.loa.md Changes

NEVER table now includes:
- C-PROC-001: `(OR when a construct with declared workflow.gates owns the current workflow)`
- C-PROC-003: `(OR when a construct with workflow.gates declares pipeline composition)`
- C-PROC-004: `(Yield when construct declares review: skip or audit: skip)`

ALWAYS table now includes:
- C-PROC-008: `(Yield when construct declares sprint: skip)`

---

## Task 2.3: audit-sprint.md Pre-flight — Construct-Aware Skip

**File**: `.claude/commands/audit-sprint.md` (MODIFIED)
**Status**: COMPLETE

### Implementation

Added `skip_when` to two pre-flight checks:

1. **file_exists** check for `engineer-feedback.md`:
   ```yaml
   skip_when:
     construct_gate: "review"
     gate_value: "skip"
   ```

2. **content_contains** check for "All good":
   ```yaml
   skip_when:
     construct_gate: "review"
     gate_value: "skip"
   ```

Both include inline comments explaining the construct-aware semantics.

### Behavior

- Without active construct: checks enforced as before (no behavior change)
- With construct declaring `review: skip`: both checks skipped, allowing audit to proceed without prior review approval

---

## Task 2.4: review-sprint.md Context Files — Construct-Aware Skip

**File**: `.claude/commands/review-sprint.md` (MODIFIED)
**Status**: COMPLETE

### Implementation

Added `skip_when` to the sprint.md context_files entry:

```yaml
- path: "grimoires/loa/sprint.md"
  required: true
  skip_when:
    construct_gate: "sprint"
    gate_value: "skip"
```

### Behavior

- Without active construct: sprint.md is required as before
- With construct declaring `sprint: skip`: sprint.md becomes optional (loaded if available, absence doesn't block)

---

## Files Changed

| File | Action | Lines Changed |
|------|--------|--------------|
| `.claude/data/constraints.json` | MODIFIED | +24 (4 construct_yield objects) |
| `.claude/templates/constraints/claude-loa-md-table.jq` | MODIFIED | +6 (yield clause rendering) |
| `.claude/loa/CLAUDE.loa.md` | REGENERATED | 4 yield clauses in constraint tables |
| `.claude/commands/audit-sprint.md` | MODIFIED | +12 (2 skip_when blocks with comments) |
| `.claude/commands/review-sprint.md` | MODIFIED | +6 (1 skip_when block with comments) |

**Total**: 5 files modified, 1 regenerated.

## Regression Check

- `tests/test_run_state_verify.sh`: 7/7 tests passing
- `generate-constraints.sh --dry-run`: idempotent (no diff after regeneration)

## Acceptance Criteria Checklist

### Task 2.1
- [x] C-PROC-001: yield_text added, yield_on_gates: `["implement"]`
- [x] C-PROC-003: yield_text added, yield_on_gates: `["implement"]`
- [x] C-PROC-004: yield_text added, yield_on_gates: `["review", "audit"]`
- [x] C-PROC-008: yield_text added, yield_on_gates: `["sprint"]`
- [x] All other constraints unchanged
- [x] JSON validates with jq

### Task 2.2
- [x] `claude-loa-md-table.jq` modified: appends yield_text when construct_yield.enabled
- [x] Constraints WITHOUT construct_yield render identically (backward compatible)
- [x] Hash-based change detection works (idempotent regeneration)
- [x] `--dry-run` mode shows preview without modifying CLAUDE.md
- [x] `.claude/loa/CLAUDE.loa.md` regenerated with 4 yield clauses

### Task 2.3
- [x] file_exists check for engineer-feedback.md has skip_when
- [x] content_contains check for "All good" has skip_when
- [x] Default behavior unchanged without active construct
- [x] Comments in YAML explain skip_when semantics

### Task 2.4
- [x] context_files entry for sprint.md has skip_when
- [x] Default behavior unchanged without active construct
- [x] Comments explain skip_when semantics
