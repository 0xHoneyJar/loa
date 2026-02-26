# Bug Sprint: Flatline 3-Model Scoring Engine Fix

## Bug ID: bug-flatline-3model
## Sprint: bug-sprint (global: TBD — registered by /implement)

## Overview

Fix the scoring engine to accept and integrate tertiary cross-scoring files from the Flatline orchestrator, completing the FR-3 3-model adversarial review pipeline.

## Tasks

### T1: Add tertiary cross-scoring CLI arguments to scoring-engine.sh
**File**: `.claude/scripts/scoring-engine.sh` (lines 490-558)
**Action**: Add 4 new argument cases to the parser:
- `--tertiary-scores-opus` → `tertiary_scores_opus_file`
- `--tertiary-scores-gpt` → `tertiary_scores_gpt_file`
- `--gpt-scores-tertiary` → `gpt_scores_tertiary_file`
- `--opus-scores-tertiary` → `opus_scores_tertiary_file`

**Acceptance**: Arguments parsed without "Unknown option" error.

### T2: Pass tertiary scores to calculate_consensus()
**File**: `.claude/scripts/scoring-engine.sh` (lines 635-658)
**Action**: Pass the 4 new file paths into `calculate_consensus()` as additional positional parameters (positions 10-13).

**Acceptance**: Function receives all scoring files.

### T3: Integrate tertiary scores into consensus jq logic
**File**: `.claude/scripts/scoring-engine.sh` (lines 88-237)
**Action**:
1. Accept 4 additional params in `calculate_consensus()`
2. Load tertiary cross-score files via `--slurpfile` or `--argjson`
3. Build score maps for all 6 scoring relationships:
   - `gpt_scores_opus` (existing: GPT scored Opus items)
   - `opus_scores_gpt` (existing: Opus scored GPT items)
   - `tertiary_scores_opus` (new: Tertiary scored Opus items)
   - `tertiary_scores_gpt` (new: Tertiary scored GPT items)
   - `gpt_scores_tertiary` (new: GPT scored Tertiary items)
   - `opus_scores_tertiary` (new: Opus scored Tertiary items)
4. Classification logic: Each item has 2 cross-scores (from the 2 models that didn't author it)
   - HIGH_CONSENSUS: both cross-scores >700
   - DISPUTED: delta between cross-scores >300
   - LOW_VALUE: both cross-scores <400
5. Include tertiary-authored items in the pool alongside GPT and Opus items.

**Acceptance**: 3-model consensus JSON includes items from all 3 models, correctly classified.

### T4: Backward compatibility — 2-model mode unchanged
**File**: `.claude/scripts/scoring-engine.sh`
**Action**: When tertiary args are absent/empty, behavior is identical to current. The new args default to empty strings and the jq logic gracefully handles missing data.

**Acceptance**: Running with only `--gpt-scores` and `--opus-scores` produces identical output to before the fix.

### T5: Update usage() help text
**File**: `.claude/scripts/scoring-engine.sh` (lines 440-487)
**Action**: Add 4 new options to the usage output.

**Acceptance**: `scoring-engine.sh --help` shows tertiary scoring options.

### T6: Unit tests — scoring-engine 3-model consensus
**File**: `tests/unit/scoring-engine-3model.bats` (new)
**Action**: Create BATS tests covering:
1. 2-model mode (no tertiary args) — backward compat
2. 3-model mode — all 6 scoring files, verify classification
3. Degraded 3-model — missing tertiary scores gracefully handled
4. Edge case — empty tertiary scores files

**Acceptance**: All tests pass with `bats tests/unit/scoring-engine-3model.bats`.

### T7: End-to-end smoke test
**Action**: Run full Flatline Protocol with 3-model config:
```bash
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```
**Acceptance**: Returns valid consensus JSON with `confidence: "full"` and items from all 3 models.

## Dependencies
- T1 → T2 → T3 (sequential: parser → wiring → logic)
- T4 is a constraint on T3
- T5 is independent
- T6 depends on T3
- T7 depends on all

## Estimated Scope
- 1 file modified: `.claude/scripts/scoring-engine.sh`
- 1 file created: `tests/unit/scoring-engine-3model.bats`
- ~100-150 lines changed/added
