---
task: T2.2 (D2.2)
sprint: sprint-2
cycle: cycle-103-provider-unification
deliverable: D2.2 — KF-002 layer-2 structural-vs-vendor-side classification report
status: complete
classification: STRUCTURAL — closed by cycle-102 sprint-4A streaming substrate
date: 2026-05-12
---

# KF-002 Layer 2 — Empirical Classification Report

## Verdict

**RESOLVED-STRUCTURAL.** KF-002 layer 2 ("claude-opus-4-7 returns empty content at 40K+ input tokens") **did not reproduce** on the cycle-102 sprint-4A streaming substrate. The bug class is operationally closed by the streaming-default transport. No additional Loa-side code change required; no upstream vendor issue required.

## AC-2.1 Decision Rule

From sprint.md L144:
> "Decision-rule: 'structural fix viable' requires ≥80% full_content at empirically-safe threshold across 5 trials"

**Met decisively.** 30K, 40K, 50K, and 60K input sizes all show **100% full_content** across 30 trials each (5 trials × 3 thinking_budgets × 2 max_tokens configs). Threshold of ≥80% is exceeded by 20 percentage points.

## Methodology

| Parameter | Value |
|-----------|-------|
| Model under test | `claude-opus-4.7` (the cycle-102/103 production primary) |
| Substrate | cheval Python httpx streaming transport (cycle-102 sprint-4A default) |
| Test gate | `LOA_RUN_LIVE_TESTS=1` (operator-authorized live API) |
| Total cells | 150 (5 sizes × 5 trials × 3 thinking × 2 max_tokens) |
| Wall time | 1h 17m 51s |
| Budget consumed | ~\$3 (matches PRD §8 estimate) |
| Test artifact | `tests/replay/test_opus_empty_content_thresholds.py` |
| Raw results | `grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-20260511T133435Z.jsonl` |
| Disposition aggregate | `grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-20260511T133435Z.summary.json` |
| pytest exit | 0 / 151 passed |

## Per-Input-Size Results

| Input size | n | full_content | partial_content | empty_content | full% |
|------------|---|--------------|-----------------|---------------|-------|
| 30K | 30 | 30 | 0 | 0 | **100%** |
| 40K | 30 | 30 | 0 | 0 | **100%** |
| 50K | 30 | 30 | 0 | 0 | **100%** |
| 60K | 30 | 30 | 0 | 0 | **100%** |
| 80K | 30 | 27 | 3 | 0 | **90%** |
| **Total** | **150** | **147** | **3** | **0** | **98%** |

**Zero empty_content across the entire matrix.** This is the load-bearing finding — the original bug class (model returns nothing at high input) is gone.

## Per-Config Breakdown (degradation at 80K)

| Input | max_tokens | thinking_budget | n | full% | Notes |
|-------|------------|-----------------|---|-------|-------|
| 80K | 4096 | none | 5 | 80% | 1 partial |
| 80K | 4096 | 2000 | 5 | 100% | — |
| 80K | 4096 | 4000 | 5 | 100% | — |
| 80K | 8000 | none | 5 | 100% | — |
| 80K | 8000 | 2000 | 5 | 100% | — |
| 80K | 8000 | 4000 | 5 | **60%** | 2 partial — likely thinking-budget vs visible-output interaction |
| All other sizes (30K–60K) × all configs | | | 120 | 100% | — |

The 80K degradation is concentrated in two specific config combos (`max_tokens=4096, thinking=none` at 80%; `max_tokens=8000, thinking=4000` at 60%). It is NOT a hard cap — most 80K configs are 100%. The signal suggests a thinking-budget + visible-output interaction at high input, not a streaming-transport limit.

## Classification Reasoning

### Why STRUCTURAL, not VENDOR-SIDE

The KF-002 layer 2 entry in `known-failures.md` was authored when:
- BB / Flatline / Red Team called provider APIs via the **non-streaming HTTP path** (`http_post_json` in `cheval/providers/base.py`)
- Opus would close the connection mid-stream at high input without ever emitting bytes
- The Loa-side gate (`_lookup_max_input_tokens`) refused prompts above the empirically-observed 36K wall

Cycle-102 sprint-4A made **streaming the default transport** (`http_post_stream` → `parse_*_stream` for all three providers). The server emits the first token immediately; intermediaries never see an idle TCP connection that gets dropped.

The replay confirms what the streaming substrate's design intent claimed: the failure mode that motivated the 36K wall **doesn't manifest on streaming**. Layer 2 is closed by the cycle-102 work — the cycle-103 Sprint 2 replay is the empirical evidence, not a separate fix.

### Why no model-config.yaml change

The current production config (post-T3.4) has:

```yaml
claude-opus-4-7:
  max_input_tokens: 180000          # backward-compat fallback
  streaming_max_input_tokens: 180000
  legacy_max_input_tokens: 36000    # pre-Sprint-4A KF-002 wall
```

- The streaming ceiling (180K) is well above the largest replay-tested size (80K) where we observed 100%-in-most-configs.
- The legacy ceiling (36K) preserves the original wall as a safety net when an operator kills streaming via `LOA_CHEVAL_DISABLE_STREAMING=1`.
- Raising any threshold would require evidence that operators are hitting the existing ceiling. None observed.
- Lowering any threshold would be conservative-but-unjustified given the replay evidence.

The optimal decision is **no change** — the structural fix is already in place; the gate values are correct; the replay is the documentation that confirms them.

### Why T2.2b (vendor-side filing) is NOT required

- Zero empty_content trials means there is no observable vendor-side failure to file with Anthropic.
- Anthropic's API + Loa's streaming substrate jointly produce reliable output at the tested input sizes.
- Filing a vendor issue without reproducer evidence would be noise, not signal.

## Operator Guidance Derived from the Data

1. **Default operation (any input ≤ 60K):** No special config. Streaming transport at default settings produces 100% full_content rate. Use `claude-opus-4.7` as primary for adversarial review without hesitation.

2. **High input (60K–80K):** Acceptable with caveat. Avoid the specific combo `max_tokens=8000 + thinking_budget=4000` at this scale (60% rate observed). Either:
   - Drop `max_tokens` to ≤4096, OR
   - Drop `thinking_budget` to ≤2000, OR
   - Trust the 90%-overall rate and use the adversarial-review fallback chain to recover the 10% degraded trials.

3. **Very high input (>80K, untested):** No data. The replay matrix capped at 80K because that's the cycle-102 Sprint 4A threshold the cycle-103 work was designed to validate. Operators at higher inputs should consider the within-company fallback chain proposed in issue #847.

4. **Streaming kill-switch:** Setting `LOA_CHEVAL_DISABLE_STREAMING=1` reverts the input gate to the legacy 36K wall via the T3.4 streaming/legacy split. This is the documented safe behavior — operators who need to disable streaming for any reason (debugging, environment compatibility) automatically get the conservative wall.

## Sprint 2 Closure Status

| Task | Status |
|------|--------|
| T2.1 — Empirical replay scaffold | ✅ COMPLETE (`664de9e7`, then live execution today) |
| T2.2a — Structural-path fix in model-config | ✅ COMPLETE (no change required — current config is correct) |
| T2.2b — Vendor-side filing | ⏸ NOT REQUIRED (zero empty_content; no reproducer to file) |

**M4 cycle-exit invariant: SATISFIED.**

## Related

- KF-002 layer 2 entry: `grimoires/loa/known-failures.md` — updated with recurrence-6 row showing the replay outcome and LAYERS-2-AND-3-RESOLVED-STRUCTURAL status header
- Decision Log: `grimoires/loa/NOTES.md` 2026-05-12 entry
- Sprint plan: `grimoires/loa/cycles/cycle-103-provider-unification/sprint.md` § Sprint 2
- Cycle-104 follow-up: issue #847 (within-company fallback chains + headless mode) — KF-002 layer 2 motivation weakens for that proposal; KF-003 (gpt-5.5-pro empty content) + cross-company diversity preservation carry it

---

*Generated by autonomous closure work, cycle-103 Sprint 2 T2.2 — 2026-05-12*
