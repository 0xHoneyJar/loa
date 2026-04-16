# Product Requirements Document: Fix spiral-harness budget boundary — audit gate skipped (#515)

**Date**: 2026-04-16
**Status**: Draft
**Issue**: [#515](https://github.com/0xHoneyJar/loa/issues/515)
**Cycle**: cycle-078

## 1. Problem Statement

`spiral-harness.sh` with `--profile light --budget 10` reproducibly hits the budget gate between REVIEW and AUDIT phases. Cumulative costs (DISCOVERY $1 + ARCHITECTURE $1 + PLANNING $1 + IMPLEMENTATION $5 + REVIEW $2 = $10) exactly equal the budget cap. The `_check_budget` function in `spiral-evidence.sh:217-228` uses `>=` comparison, so `spent >= max` evaluates to true and AUDIT never runs.

This defeats the "unskippable gates" design goal — the audit quality gate can be bypassed by normal cost variance.

## 2. Root Cause

`_check_budget()` in `.claude/scripts/spiral-evidence.sh` lines 217-228:
```bash
_check_budget() {
    local max_budget="$1"
    if jq -n --argjson spent "$spent" --argjson max "$max_budget" '$spent >= $max' | grep -q true; then
        ...
        return 1
    fi
}
```

Called at `spiral-harness.sh:208` before every phase: `_check_budget "$TOTAL_BUDGET" || { error "Budget exceeded before $phase"; exit 3; }`

When cumulative spend equals exactly $10, the `>=` check blocks AUDIT from starting.

## 3. Goals

1. **Reserve an audit floor** so the AUDIT phase always has budget headroom, regardless of cumulative spend from prior phases
2. **Change the comparison** from `>=` to `>` so a phase can START at exact budget (fail only if it exceeds mid-run)
3. **Add regression test** that verifies AUDIT runs when spend equals exactly the budget cap
4. **Update light profile budget** to $12 to match observed real-world cumulative costs

## 4. Chosen Fix: Combination of proposals 2 + 3 + 1

From the issue's 4 proposed fixes, we combine:
- **Proposal 2**: Change `>=` to `>` in `_check_budget` — allows AUDIT to start at exact budget
- **Proposal 3**: Reserve audit floor — subtract `$AUDIT_BUDGET` from effective cap for phases 1-6
- **Proposal 1**: Raise light profile default from $10 to $12 as a safety margin

This layered approach means:
- Even if pre-AUDIT phases consume the full non-reserved budget, AUDIT still runs
- The `>` comparison handles edge cases where spend equals the cap exactly
- The raised default provides additional margin for cost variance

## 5. Non-Goals

- Changing the budget tracking mechanism (flight recorder cost accumulation is fine)
- Modifying `claude -p` cost reporting (that's external)
- Changing non-light profiles (standard=$12 and full=$15 already have headroom)

## 6. Success Criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| SC-1 | AUDIT runs when cumulative spend equals exactly the budget cap | BATS test with mocked flight recorder |
| SC-2 | Light profile default budget is $12 (not $10) | BATS test / config check |
| SC-3 | Pre-AUDIT phases respect a reduced effective budget (cap minus audit reserve) | BATS test: budget check at REVIEW phase uses reduced cap |
| SC-4 | AUDIT phase uses the reserved amount, not the full cap | BATS test |
| SC-5 | All existing spiral-harness and spiral-evidence BATS tests pass | CI green |
| SC-6 | Standard and full profiles are not affected | BATS test |

## 7. System Zone Write Authorization

This fix requires editing files in `.claude/scripts/` (System Zone). Authorized for cycle-078.

**Files to modify:**
- `.claude/scripts/spiral-evidence.sh` — change `>=` to `>` in `_check_budget`
- `.claude/scripts/spiral-harness.sh` — add audit reserve logic + raise light profile default

**Files to create/extend:**
- `tests/unit/spiral-evidence.bats` or `tests/unit/spiral-harness.bats` — regression tests
