# Implementation Report: Sprint 3 — Bridgebuilder Review Fixes

**Implementer**: Claude Opus 4.6
**Sprint**: sprint-3 (cycle-001, Bug Mode #278)
**Date**: 2026-02-11
**Source**: [Bridgebuilder Review on PR #279](https://github.com/0xHoneyJar/loa/pull/279#issuecomment-3881433049)

---

## Tasks Completed

### Task 3.1: Fix Schema Drift — Make `target` Conditional in index.yaml

**Finding**: `target` was `required: true` but bug mode doesn't provide it. Schema lied to consumers.

**File**: `.claude/skills/run-mode/index.yaml` (line 49-53)

**Change**:
- `required: true` → `required: false`
- Description updated: "Required for sprint mode; generated during triage for bug mode."

**Verification**:
- Bug mode inputExamples (lines 27-31) have no `target` field — now valid
- Sprint mode inputExamples (lines 15-25) still have `target` — still valid
- SKILL.md runtime logic unchanged — handles both paths correctly

### Task 3.2: Add Explicit Ordering Contract for Sprint ID Validation Bypass

**Finding**: `_gp_validate_sprint_id` regex won't match `sprint-bug-N`, but this is intentional because bug routing happens before validation. Implicit dependency should be explicit.

**File**: `.claude/scripts/golden-path.sh` (lines 460-463)

**Change**: Added 3-line comment above `_gp_validate_sprint_id`:
```
# Note: Bug sprint IDs (sprint-bug-N) bypass this validation entirely via
# golden_detect_active_bug() early return in golden_resolve_truename("build").
# User-provided overrides still pass through this check.
```

**Verification**: No functional changes. Comment follows existing `#`-comment style in file.

### Task 3.3: Implement State Transition Validation Function

**Finding**: State transitions documented but not enforced by code. Critical for Hounfour multi-model future where less capable models may attempt invalid transitions.

**File**: `.claude/scripts/golden-path.sh` (lines 405-440)

**Change**: New function `golden_validate_bug_transition()`:
- Takes `(current_state, proposed_state)`, returns 0 (valid) or 1 (invalid)
- Encodes full transition table from SDD Appendix E
- `ANY → HALTED` always valid
- `COMPLETED` and `HALTED` are terminal (no transitions out)
- Uses `case/esac` for O(1) lookup
- Placed in Bug Detection section alongside other bug helpers

**Transition table encoded**:
```
TRIAGE → IMPLEMENTING        ✓
IMPLEMENTING → REVIEWING     ✓
REVIEWING → IMPLEMENTING     ✓ (loop back)
REVIEWING → AUDITING         ✓
AUDITING → IMPLEMENTING      ✓ (loop back)
AUDITING → COMPLETED         ✓
ANY → HALTED                 ✓
COMPLETED → *                ✗ (terminal)
HALTED → *                   ✗ (terminal)
TRIAGE → AUDITING            ✗ (invalid skip)
IMPLEMENTING → COMPLETED     ✗ (skip review+audit)
```

---

## Files Changed

| File | Lines Changed | Type |
|------|--------------|------|
| `.claude/skills/run-mode/index.yaml` | 2 | Schema fix |
| `.claude/scripts/golden-path.sh` | +39 (3 comment + 36 function) | Code + documentation |
| `grimoires/loa/sprint.md` | +55 | Sprint plan update |
| `grimoires/loa/ledger.json` | 2 | Ledger registration |

## Cross-References

- Bridgebuilder Finding 1 → Task 3.1 (schema drift)
- Bridgebuilder Finding 2 → Task 3.2 (ordering contract)
- Bridgebuilder Finding 3 → Task 3.3 (state enforcement)
- SDD Appendix E (state transitions) → Task 3.3
- Hounfour RFC (loa-finn #31) → Task 3.3 rationale
