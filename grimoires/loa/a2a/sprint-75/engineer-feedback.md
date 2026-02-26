# Sprint 75 (Sprint 2) — Senior Technical Lead Review

**Reviewer**: Senior Technical Lead
**Date**: 2026-02-26
**Verdict**: All good

---

## Checklist

- [x] **T1: Step 0.5 integration in SKILL.md** -- Vision loading between Context Synthesis and Interview
- [x] **T2: Presentation template** with Explore/Defer/Skip choices
- [x] **T3: Case-insensitive sanitization strengthening** (audit ADVISORY-2)
- [x] **T4: Shadow graduation detection and prompt**
- [x] **T5: Integration tests** (10 E2E tests)

## Test Results

- Unit tests: 53/53 passing (32 vision-lib + 21 vision-registry-query)
- Integration tests: 10/10 passing
- Total: 63 tests, 0 failures

---

## Task-by-Task Review

### T1: SKILL.md Step 0.5 (lines 666-789)

**File**: `.claude/skills/discovering-requirements/SKILL.md`

Correctly placed between Phase 0 (Context Synthesis, line 524) and Phase 0.5 (Targeted Interview, line 792). The step:

1. Gates on `vision_registry.enabled` with proper `yq eval` fallback to `false` (line 673)
2. Derives work context tags from sprint file paths, user request keywords, and PRD headers in documented priority order (lines 680-686)
3. Routes to shadow mode or active mode based on `vision_registry.shadow_mode` config (lines 700-720)
4. Shadow mode correctly pipes to `/dev/null` so nothing is presented to user (line 711)
5. Active mode presents the template with Explore/Defer/Skip choices (lines 722-740)

The `IMPORTANT` note on line 742 about not LLM-generating relevance explanations is a good guard against hallucinated rationales. The decision logging format (lines 754-764) provides full audit trail per choice.

### T2: Presentation Template (lines 722-740)

The template is clean and well-structured. It includes all required fields: title, source, matched tags, score breakdown, and sanitized insight text (capped at 500 chars). The three user choices (Explore, Defer, Skip) each have documented side effects in the decision table (lines 748-752). Explore triggers both `vision_update_status()` and `vision_record_ref()`, which is correct -- it advances lifecycle and tracks usage.

### T3: Case-Insensitive Sanitization (vision-lib.sh lines 349-361)

**File**: `.claude/scripts/vision-lib.sh`

Three-layer defense:

1. **Character-class patterns** (lines 351-355): Manual `[sS][yY][sS]...` patterns for `<system>`, `<prompt>`, `<instructions>` tag pairs with content. This approach is portable across all sed implementations.
2. **Remaining tag strip** (line 358): Uses `sed -E ... //gI` flag for case-insensitive stripping of any remaining bare `<system>`, `<prompt>`, `<instructions>`, `<context>`, `<role>`, `<user>`, `<assistant>` tags. The `I` flag works on GNU sed (confirmed on this platform).
3. **Indirect instruction patterns** (line 361): `grep -viE` with expanded pattern list: "ignore previous", "forget all", "you are now", "act as", "pretend to be", "disregard", "override", "ignore all", "ignore the above", "do not follow", "new instructions", "reset context".

The `|| true` on line 361 is necessary to prevent `set -e` from exiting when grep finds no matches (exit code 1). Good.

The semantic threat fixture (`tests/fixtures/vision-registry/entry-semantic-threat.md`) covers mixed-case variants: `<SYSTEM>`, `IGNORE ALL`, `IGNORE THE ABOVE`, `ACT AS`, `You Are Now`, `FORGET ALL`, `RESET CONTEXT`, `Do Not Follow`, `New Instructions`, `PRETEND TO BE`. The corresponding test (vision-lib.bats lines 182-199) asserts all are stripped.

**Portability note**: The `I` flag on line 358 is GNU sed-specific. On macOS BSD sed, this flag is not supported. The character-class patterns on lines 351-355 provide the primary defense and ARE portable. The `I` flag on line 358 is a secondary catch-all for bare tags. Since the Loa framework primarily targets Linux (per the CI environment), this is acceptable, but worth noting for future macOS compatibility work.

### T4: Shadow Graduation Detection (vision-registry-query.sh lines 302-364)

**File**: `.claude/scripts/vision-registry-query.sh`

Graduation logic at lines 352-353:
```bash
if [[ "$shadow_cycles" -ge "$config_threshold" && "$shadow_matches" -gt 0 ]]; then
```

This correctly requires BOTH conditions: enough shadow cycles completed AND at least one match observed. The threshold is read from config via `yq eval '.vision_registry.shadow_cycles_before_prompt // 2'` with a sensible default of 2.

The JSON output wraps results in `{results: ., graduation: {ready: true, shadow_cycles: N, total_matches: M}}` (lines 356-357), which the SKILL.md Step 0.5b (lines 767-788) consumes to present the graduation prompt with four user choices: enable active, adjust thresholds, keep shadow, or disable.

Shadow state is stored in `grimoires/loa/visions/.shadow-state.json` (not in `.loa.config.yaml`), which is correct -- runtime state should not pollute user config.

### T5: Integration Tests (10 tests)

**File**: `tests/integration/vision-planning-integration.bats`

| # | Test | Coverage |
|---|------|----------|
| 1 | Config disabled means query returns results | Verifies query script does not check config (caller's responsibility) |
| 2 | Shadow mode writes JSONL and updates state | End-to-end shadow pipeline: log creation, state file update, field verification |
| 3 | Active mode returns scored results with text | Verifies scoring, ordering (vision-001 first), and sanitized insight text |
| 4 | Ref tracking increments on interaction | Simulates Explore choice, verifies ref count incremented from 4 to 5 |
| 5 | Capture script --help still works | Backward compatibility for existing capture script |
| 6 | Capture --check-relevant with empty index | Empty registry returns nothing |
| 7 | Capture creates vision entries from findings | Full capture pipeline: findings JSON to entry file + index update |
| 8 | Graduation triggers after threshold | Pre-seeds state at threshold-1, runs one more cycle, asserts `graduation.ready: true` |
| 9 | Regression: Sprint 1 vision-lib tests pass | Runs full unit test suite to detect regressions |
| 10 | Regression: Sprint 1 query tests pass | Runs full unit test suite to detect regressions |

Test isolation is solid: each test creates its own `$TEST_TMPDIR` with proper directory structure, overrides `$PROJECT_ROOT`, and cleans up in `teardown()`.

### Shadow JSONL Compact Fix (vision-registry-query.sh line 323)

The `jq -cn` flag (compact + null input) correctly produces single-line JSON entries for the JSONL log. This was a bug fix identified during implementation -- good catch and documented in the reviewer report.

---

## Minor Observations (Non-Blocking)

1. **Dead code in regression test** (`tests/integration/vision-planning-integration.bats` line 250): The first `run bats "$PROJECT_ROOT/../../tests/unit/vision-lib.bats"` uses the overridden `$PROJECT_ROOT` (which is `$TEST_TMPDIR`), making the path invalid. The comment on line 251 acknowledges this, and line 253 correctly uses `$REAL_ROOT`. However, the `run` on line 250 executes unnecessarily and its result is discarded. Consider removing line 250 to avoid wasted work.

2. **Portability of `sed -E ... //gI`** (vision-lib.sh line 358): The `I` flag for case-insensitive matching is GNU sed-specific. The character-class patterns on lines 351-355 provide portable primary defense, but if macOS support becomes a priority, the `I` flag on line 358 would need a `compat-lib.sh` wrapper or character-class expansion.

3. **Shadow mode JSONL compact assertion**: The integration test (test #2) verifies the JSONL entry is parseable via `jq`, which implicitly validates compactness (multi-line JSON would fail `head -1 | jq`). An explicit `wc -l` assertion could make the single-line contract more visible, but this is a style preference, not a deficiency.

---

## Summary

All 5 tasks are implemented correctly. The SKILL.md integration is well-placed and properly gated. Sanitization is case-insensitive with a defense-in-depth approach (character classes + `I` flag + `grep -viE`). Shadow graduation logic correctly gates on both cycle count and match count. Integration tests provide comprehensive coverage including cross-sprint regression protection. 63 tests pass with 0 failures.

No injection vulnerabilities detected. Error handling is consistent (proper `|| true` for grep, `set -euo pipefail` throughout, `2>/dev/null` on optional reads). The implementation matches the SDD specification.
