# Engineer Feedback: Sprint-73 (cycle-040, bug-flatline-3model)

## Decision: ALL GOOD

---

## Task-by-Task Verification

### T1: Add tertiary cross-scoring CLI arguments -- PASS

Four new argument cases added to the parser (lines 636-651):
- `--tertiary-scores-opus` -> `tertiary_scores_opus_file`
- `--tertiary-scores-gpt` -> `tertiary_scores_gpt_file`
- `--gpt-scores-tertiary` -> `gpt_scores_tertiary_file`
- `--opus-scores-tertiary` -> `opus_scores_tertiary_file`

Each follows the standard `shift 2` pattern matching all other flag-value pairs. The `*)` catch-all (line 672) will no longer fire for these flags. Verified: all 4 variables initialized to empty string at declaration (lines 597-600).

### T2: Pass tertiary scores to calculate_consensus() -- PASS

Both call sites pass the 4 new file paths:
- **With blockers** (lines 760-773): positions 10-13 after skeptic files
- **Without blockers** (lines 775-786): empty strings for skeptic positions 7-9, then tertiary at 10-13

Function signature (lines 106-109) receives them as `${10:-}` through `${13:-}` with proper defaults to empty string.

### T3: Integrate tertiary scores into consensus jq logic -- PASS

The jq logic correctly:
1. Builds 6 score maps (lines 190-197): `$gpt_map`, `$opus_map`, `$g_tert_map`, `$o_tert_map`, `$t_opus_map`, `$t_gpt_map`
2. Collects all unique IDs including tertiary-authored items (lines 200-201)
3. Resolves effective score pair per item (lines 227-232): primary pair for existing items, GPT+Opus pair for tertiary-authored items
4. Calculates tertiary confirmation score as max of non-zero tertiary cross-scores (line 235)
5. Classifies using same thresholds (lines 268-276): HIGH (both>700), DISPUTED (delta>300), LOW (both<400), else MEDIUM

The classification logic is sound. Verified via manual execution:
- IMP-001 (gpt=850, opus=800): HIGH_CONSENSUS (correct)
- IMP-003 (gpt=750, opus=300): DISPUTED with delta=450 (correct)
- TIMP-001 (gpt=900, opus=850): HIGH_CONSENSUS tertiary-authored (correct)
- TIMP-002 (gpt=350, opus=300): LOW_VALUE tertiary-authored (correct)

### T4: Backward compatibility -- PASS

Verified by execution: 2-model mode (no tertiary args) produces:
- `models: 2`, `tertiary_items: 0`, `confidence: "full"`
- Same classification results as before: IMP-001=HIGH, IMP-003=DISPUTED, IMP-002=MEDIUM
- Output keys identical: `consensus_summary`, `high_consensus`, `disputed`, `low_value`, `blockers`, `confidence`, `degraded`, `degraded_model`

All tertiary variables default to `'{"scores":[]}'` (lines 142-145) and empty `build_score_map` produces `{}`, so `$all_ids` only includes items from `$gpt.scores` and `$opus.scores`.

### T5: Update usage() help text -- PASS

Lines 548-551 add all 4 new options with descriptive text matching the header comment (lines 19-22). Verified via `--help` test.

### T6: Unit tests -- PASS (15/15)

Test coverage:
| Category | Tests | Coverage |
|----------|-------|----------|
| 2-model backward compat | 4 | Args accepted, HIGH classification, models=2, tertiary_items=0 |
| 3-model full | 6 | Args accepted, models=3, tertiary items present, TIMP-001=HIGH, TIMP-002=LOW, tertiary_score field |
| Skeptic dedup | 1 | 3-source concerns deduplicated by exact text match, blocker count=2 |
| Degraded mode | 3 | Empty files, partial tertiary, nonexistent files |
| Help text | 1 | All 4 options present |

All 15 tests pass. Existing `flatline-model-validation.bats` (13 tests) also passes -- no regressions.

### T7: End-to-end smoke test -- NOT VERIFIED (requires API keys)

This is expected; the smoke test requires `OPENAI_API_KEY`, `GOOGLE_API_KEY`, and `ANTHROPIC_API_KEY` with a configured tertiary model. Cannot run in review.

---

## Code Quality Assessment

### Strengths

1. **Graceful degradation**: Each tertiary file is independently loaded with `jq -c '.' ... 2>/dev/null || fallback` pattern. Missing, empty, or invalid files do not crash the engine.

2. **jq parameter binding**: All data passed via `--argjson`, never interpolated into the jq program string. Consistent with the established jq injection prevention pattern (PR #215).

3. **Skeptic dedup**: `group_by(.concern) | map(.[0])` correctly deduplicates identical concern text across 3 sources (line 290). The comment (lines 280-284) explicitly documents the design choice and future consideration for fuzzy dedup.

4. **Minimal footprint**: Only `scoring-engine.sh` modified + 1 new test file + fixtures. No unnecessary changes.

5. **Source tracking**: Each classified item includes `source: "gpt_scored" | "opus_scored" | "tertiary_authored" | "unknown"` for downstream traceability.

### Minor Observations (non-blocking)

1. **`has_tertiary` detection asymmetry** (lines 147-163): The flag is only set to `true` when `gpt_scores_tertiary_file` is valid. If only `tertiary_scores_opus` and `tertiary_scores_gpt` are provided (without `gpt_scores_tertiary`), the output reports `models: 2` even though tertiary cross-scores are loaded and used. In practice, the orchestrator always sends all 4 tertiary args together (lines 1109-1114 of flatline-orchestrator.sh), so this path is unlikely. If desired, the check could be broadened to any tertiary file being valid, but this is cosmetic.

2. **`medium_value` not in output JSON**: The `$classified.medium_value` array is used for agreement percentage but not emitted in the output object. This is pre-existing behavior (not introduced by this fix) and is consistent across both modes.

3. **Test fixtures created in setup()**: The BATS `setup()` creates fixtures on every test run via `cat > $FIXTURES/...`. The fixtures also exist as committed files in `tests/fixtures/scoring-engine/`. This means the committed fixtures are always overwritten by setup(). The duplication is harmless but slightly redundant -- the committed files serve as documentation of test data.

---

## Interface Contract Verification

Verified the orchestrator-to-scoring-engine interface:

| Orchestrator (lines 1109-1113) | Scoring Engine Parser |
|--------------------------------|----------------------|
| `--tertiary-scores-opus` | line 637 |
| `--tertiary-scores-gpt` | line 641 |
| `--gpt-scores-tertiary` | line 645 |
| `--opus-scores-tertiary` | line 649 |

All 4 flag names match exactly. The root cause of the bug (unknown option error) is resolved.

---

## Verdict

The fix is correct, minimal, backward-compatible, well-tested (15 new tests, 0 regressions), and follows established patterns. The `has_tertiary` asymmetry is a cosmetic nit that does not affect correctness in the real call path. Ship it.
