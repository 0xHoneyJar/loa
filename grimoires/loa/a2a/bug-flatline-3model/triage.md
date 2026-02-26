# Bug Triage: Flatline 3-Model Scoring Engine Crash

## Bug ID: bug-flatline-3model

## Classification
- **Severity**: HIGH — Flatline 3-model mode completely broken at consensus stage
- **Category**: Interface contract mismatch (orchestrator → scoring engine)
- **Regression**: No — FR-3 tertiary scoring was dormant until cycle-040 activated it
- **Introduced by**: PR #414 (activated dormant FR-3 code path)

## Root Cause Analysis

The `flatline-orchestrator.sh` (line 1109-1114) passes 4 tertiary cross-scoring files to `scoring-engine.sh`:

```
--tertiary-scores-opus <file>     # Tertiary model's scores of Opus improvements
--tertiary-scores-gpt <file>      # Tertiary model's scores of GPT improvements
--gpt-scores-tertiary <file>      # GPT's scores of Tertiary improvements
--opus-scores-tertiary <file>     # Opus's scores of Tertiary improvements
```

But `scoring-engine.sh` argument parser (line 502-558) only handles:
- `--gpt-scores`, `--opus-scores` (required 2-model scores)
- `--skeptic-gpt`, `--skeptic-opus`, `--skeptic-tertiary` (skeptic concerns)

The 4 tertiary cross-scoring arguments hit the `*)` catch-all at line 553:
```bash
*) error "Unknown option: $1"; exit 1 ;;
```

### Why This Wasn't Caught

The FR-3 infrastructure was built in two halves:
1. **Orchestrator side** (complete): Generates all 6 Phase 2 cross-scoring calls and passes results
2. **Scoring engine side** (incomplete): Only handles `--skeptic-tertiary`, not the 4 cross-scoring files

Since `hounfour.flatline_tertiary_model` was empty until cycle-040 set it to `gemini-2.5-pro`, the `tertiary_args` array was always empty and `"${tertiary_args[@]}"` expanded to nothing.

## Reproduction

```bash
# Requires: OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY
# Requires: .loa.config.yaml with hounfour.flatline_tertiary_model: gemini-2.5-pro
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```

**Expected**: Consensus JSON with 3-model triangular scoring
**Actual**: `ERROR: Unknown option: --tertiary-scores-opus` (exit 1)

## Secondary Issue

1 of 6 Phase 1 calls failed (opus-skeptic) — degraded mode. This may be transient (API timeout/rate limit) but should be investigated.

## Affected Files

| File | Role | Fix Needed |
|------|------|------------|
| `.claude/scripts/scoring-engine.sh` | Consensus calculator | Add 4 tertiary CLI args + integrate into `calculate_consensus()` |
| `.claude/scripts/flatline-orchestrator.sh` | Orchestrator | No changes (caller is correct) |

## Fix Design

### 1. Add 4 new CLI arguments to `scoring-engine.sh`

In the argument parser (`main()`, line 502-558), add cases for:
- `--tertiary-scores-opus`
- `--tertiary-scores-gpt`
- `--gpt-scores-tertiary`
- `--opus-scores-tertiary`

### 2. Pass to `calculate_consensus()`

The function currently takes 9 positional args. Add 4 more for tertiary cross-scores (positions 10-13).

### 3. Integrate tertiary scores into jq consensus logic

Current 2-model consensus: `gpt_map[$id]` vs `opus_map[$id]` → classify by thresholds.

3-model consensus should use **median-of-three** or **2-of-3 majority** voting:
- Each improvement is scored by 2 of 3 models (the two that didn't author it)
- HIGH_CONSENSUS: 2-of-3 cross-scorers rate >700
- DISPUTED: scores span >300 delta across any pair
- LOW_VALUE: 2-of-3 cross-scorers rate <400

For tertiary-authored improvements (scored by GPT and Opus), they join the same pool.

### 4. Update usage/help text

Add the 4 new options to the `usage()` function.

## Acceptance Criteria

- [ ] `scoring-engine.sh` accepts all 4 tertiary cross-scoring arguments without error
- [ ] 3-model consensus uses all 6 cross-scoring relationships in classification
- [ ] 2-model mode (no tertiary) continues to work unchanged (backward compat)
- [ ] Flatline smoke test passes: `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json` returns valid consensus JSON
- [ ] Unit tests cover: 2-model mode, 3-model mode, degraded mode (missing tertiary scores)
