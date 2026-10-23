# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff` (cycle-126 sprint-247, 65 files): the input bound becomes a policy over the catalog entry (`loa_cheval/routing/ceiling.py`), the provider's own size verdict is typed and never walked, output defaults and temperature follow the entry for every provider, Flatline and Bridgebuilder size their budgets from the generated catalog maps, and the probe tool can write a calibration back into the catalog. The design is coherent and well documented, the generated artifacts are in sync with the catalog (I re-derived `MODEL_MAX_OUTPUT`, `GENERATED_TOKEN_BUDGETS` and `GENERATED_REASONING` from `head/.claude/defaults/model-config.yaml`: 31 entries, zero mismatches), and the new unit tests are thorough for the policy module in isolation.

Three defects block the merge, all in the end-to-end seams the unit tests do not cross:

1. the chain-walk gate re-estimates the input with the heuristic and discards the provider count the pre-flight just declared authoritative, so a request the provider confirmed fits is refused `CHAIN_EXHAUSTED`;
2. the retry layer's one-shot output-budget shrink `continue`s without an attempt left, so the provider's typed verdict degrades into a walkable `RetriesExhaustedError` (reproduced, output below);
3. the long-context premium triggers on uncached `input_tokens` only, so a request whose cached prefix pushes it over the threshold is ledgered at base rates (reproduced).

Process note: the implementation report (`pr/PR.md`) is a title line only — there is no `## AC Verification` walkthrough. In this evaluation layout the PR files are the whole input, so I reviewed the code directly; the verdict below rests on the code findings.

**Verification status.** The PR's Python tests could not be executed against the PR tree: `pr/head/` holds only the touched files and the workspace checkout is a later, divergent revision (its `headless_cli.py` imports a symbol the PR's `types.py` lacks). I verified the three blocking findings by code reading and, for two of them, by standalone repro scripts against the identical module text (`retry.py` is byte-identical between head and workspace; `pricing.py` was imported from `pr/head` in isolation). The PR's new bats suites pass against an overlay of the head scripts: FMT-1..6, MPE-1..3, CR-8, LSP-5, c124-B1..B4, ED-8, CM-1..5. The bats failures I saw (c124-B5/B6/B8, ED-4..7, CR-7) are environment artefacts of the overlay (`model-adapter.sh` not executable in the scratch tree; CR-7 is untouched by this PR) and are not attributed to the change. The TypeScript tests were not run (no `node_modules` offline); the generated tables they assert were cross-checked programmatically instead.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the walk gate discards the authoritative count (FR-1.4 / D-1.4 does not hold end to end)

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2119` — the per-hop input gate calls `estimate_tokens(messages)` (the heuristic) and compares it with the policy bound, ignoring `_walk_estimate`, which the pre-flight set to the provider's `count_tokens` result at `head/.claude/adapters/cheval.py:1842`. Scenario (default `probed` policy, English prose, probed bound 180,000): heuristic 185,000 ≥ 0.9 × bound → the pre-flight counts, the provider says 165,000 → `dispatch`. The chain loop then re-estimates 185,000 > 180,000 → `ROUTING_MISS` on the head, walks to `claude-opus-4-8` (same probed bound) → `ROUTING_MISS` → `CHAIN_EXHAUSTED`. The request the provider confirmed fits is refused, and the envelope says `preflight_decision: dispatch` next to two routing misses.
**File:** `head/.claude/adapters/cheval.py:2119`
**Issue:** two estimators of record for the same request; the one the design calls authoritative loses.
**Why This Matters:** the whole point of D-1.4 is that the count settles the gate near the bound; `chars/3.5` overcounts English prose by ~15 %, so exactly the near-bound band the count was added for is where the walk gate undoes it. The e2e tests never hit this because under the `derived` opt-in the walk threshold is 936K.
**Required Fix:** compare the walk gate against `_walk_estimate` when it is set (it already carries the count for the head and the heuristic otherwise), e.g. `_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)`; add an e2e case with heuristic > bound ≥ count asserting one dispatch and no `ROUTING_MISS`.

### 2. Error handling — the output-budget shrink can swallow the provider's typed verdict

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:495` — the `ProviderContextLimitError` arm sets `_context_shrink_done`, replaces the request and `continue`s without checking that another iteration exists and without recording `last_typed_error`. When the context verdict arrives on the final permitted attempt (`max_retries: 0`, or earlier attempts consumed by 429/5xx), the `for` loop ends and the function raises `RetriesExhaustedError`, which cheval treats as walkable: the fallback hop receives the same oversized payload (the thing D-1.1b forbids), no `.run/ceiling-observed.json` row is written, and no `calibration_needed` lands in the envelope. Reproduced against the identical module text:
```
max_retries=0, context error on first attempt -> RetriesExhaustedError (typed error LOST; walkable) seen [64000] msg= [cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: unknown
max_retries=1, 429 then context error on last attempt -> RetriesExhaustedError (typed error LOST; walkable) seen [64000, 64000] msg= [cheval] RETRIES_EXHAUSTED: Failed after 2 attempts: [cheval] RATE_LIMITED: ...
```
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:472-495`
**Issue:** the promised "one retry at the budget that fits" is never dispatched on the last attempt; the error class is rewritten.
**Why This Matters:** the non-walk guarantee and the self-correction record are the safety net for dispatching above the probed bound; losing both at once on a bounded retry budget is the worst case.
**Required Fix:** before `continue`, require `attempt < max_retries` and the global attempt budget; otherwise `raise` the original error. Set `last_typed_error = e` in the arm. Add the `max_retries: 0` case and the "429 then context error on the last attempt" case to `test_ceiling_retry.py`.

### 3. Metering — the long-context premium ignores cached input

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — `if threshold is not None and input_tokens > threshold` tests the uncached count only. `calculate_total_cost`'s own docstring (`pricing.py:127-129`) says `cache_read_tokens` / `cache_creation_tokens` are NOT included in `input_tokens`, and the provider's published 1M-window rule applies the tier to the request's total input. Reproduced with the head module: input 150,000 + cache_read 100,000 (250,000 total) → `long_context_applied = False`, total 1,050,000 µUSD; the same 250,000 uncached → `True`, 2,875,000 µUSD. The code then multiplies `cr_cost` / `cw_cost` once triggered, so the intent clearly includes cache traffic — only the trigger is wrong.
**File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
**Issue:** ledger under-reports the premium whenever a cached prefix (which cycle-124's `cache_control` blocks make the common shape for Flatline/BB) carries the request over the threshold; `long_context_rows` in `cost-report.sh` is wrong by the same rows.
**Why This Matters:** the budget enforcer reads this ledger; a 2× input / 1.5× output under-count on exactly the large requests this cycle enables is a budget-control gap.
**Required Fix:** trigger on `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`; add a `test_long_context_pricing.py` case with cache tokens straddling the threshold; say so next to `verified: false` in the catalog block.

---

## Observations

### 1. Chain semantics (opt-in zone)

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:1843` — `_ceiling_unverified` is computed once from the HEAD entry's gate outcome and then consulted for every hop at `head/.claude/adapters/cheval.py:2256` (error class of a provider verdict) and `head/.claude/adapters/cheval.py:2297` (the 429 short-circuit). Scenario: head warns above its probed bound, fails with a walkable 5xx, the fallback is a calibrated entry (or a CLI hop) — a 429 there ends the chain as `RATE_LIMIT_UNVERIFIED` and a provider verdict there is recorded as `CEILING_UNVERIFIED_LIMIT` against an entry that was never unverified. Compute the flag per hop from `input_bound(_hop_entry, …)` and `_walk_estimate` (the per-hop I1 block already has both).
- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — under the opt-in, EVERY `RateLimitError` ends the invocation (exit `RATE_LIMITED`, calibration row), including an ordinary requests-per-minute 429 that has nothing to do with the token limit. The e2e test `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` encodes this as intended, so it is a design choice rather than a slip — but it trades the operator's declared chain shape for a calibration hint on a signal the code cannot distinguish. Consider gating the short-circuit on a token-limit indication from the 429 body (Anthropic names `input tokens per minute`) and letting request-rate 429s walk as before.

### 2. Budget vs timeout (Flatline, FR-1.6)

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:129` — the per-voice budget becomes `min(64000, max_output_tokens)` (every Anthropic voice → 64,000, applied at `head/.claude/scripts/flatline-orchestrator.sh:1027`). The cycle-124 comment this PR deletes bounded Flatline at 16,000 precisely so "the 600 s per-call timeout never meets a 64K-output generation"; the timeout is unchanged here. A runaway reviewer/skeptic/scorer generation now runs to the timeout (and bills up to 64K output tokens) instead of being cut at 16K. If the catalog-derived budget is the goal, either raise the per-call timeout to match (`_nonstreaming_read_timeout` already scales 25 tok/s) or cap `FLATLINE_VOICE_MAX_TOKENS_CAP` at what 600 s can emit.

### 3. Provenance and consistency

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/base.py:1000` — `estimate_input` reports `method: "tiktoken"` whenever `import tiktoken` succeeds, but `estimate_tokens` (`base.py:925-937`) falls back to the heuristic when `get_encoding("cl100k_base")` fails (offline host, no cached encoding). The envelope's estimator provenance is then wrong. Derive the method from the branch that actually produced the number.
- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:813` — the jq reduction takes `min` over `observed_input_tokens` without a positivity filter; cheval writes `0` when it has no estimate (`cheval.py:2000`, gate disabled). `/loa` then prints `ceiling: observed -1`, while `observed_for` (`ceiling.py:252`) ignores non-positive rows. Filter `observed_input_tokens > 0` in the jq to match the Python rule.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:361` and `:503` — `is_context_limit_message` keys on generic markers (`context window`, `context length`, `input length`, `exceeds context`). A 400 of another kind that happens to mention the context window would be typed as the non-walkable provider verdict and, via `_calibration_needed_exit`, lower the entry's bound to the current estimate. Anchor the predicate on the two provider shapes `parse_context_limit` already knows plus 413, and do not lower the bound when neither `input_tokens` nor `limit` was parsed.
- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:1851` — an I1 preempt has `bound=None`, so the error JSON reports `effective_input_ceiling: 0`; emit the window or omit the field.

### 4. Simplicity / dead code

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:144` — SIMPLICITY[delete]: the branch `0 < requested < FLOOR_MAX_TOKENS and room >= requested` can never be true after line 139 returned on `estimate + requested <= context_window` (identical condition). Delete it; the test on `test_ceiling_policy.py:143` passes through line 139.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:300` — SIMPLICITY[shrink]: `_CONTEXT_FLOOR_MAX_TOKENS = 4_096` duplicates `routing.ceiling.FLOOR_MAX_TOKENS` with a comment promising equality that nothing enforces. Move the constant to `loa_cheval.types` (imported by both) or pin equality in a test.
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:65-69` — a conditional expression whose first operand is dead (`… if False else …`) wraps the real assertion; replace with the plain call.

### 5. Tooling

- **LOW** (confidence: high) `head/tools/ceiling-probe-live.py:173` — `_write_catalog_file` writes the catalog via `mkstemp` + `os.replace`; `mkstemp` creates the file 0600, so the live `model-config.yaml` loses its mode on every `--write-catalog` run (reproduced: 0664 → 0600). Copy the original mode (`os.chmod(tmp, stat.S_IMODE(os.stat(path).st_mode))`) before the replace, and unlink the temp file on failure as `record_observed` (`ceiling.py:300-305`) does.

Over-engineering pass: `net: -4 lines possible` (the dead `fit_max_tokens` branch and the duplicated floor constant).

---

## Cross-Model Observations

Two voices completed (primary `gpt-5.5-pro`, companion `claude-headless`, `counted_as: independent_voice`), 11 findings, none rejected. Triage:

- DISS-003 / DISS-C-003 (pricing threshold) and DISS-004 / DISS-C-002 (retry shrink on the last attempt) — confirmed; counted above as Changes Required 3 and 2.
- DISS-002 / DISS-C-001 (head-only `_ceiling_unverified`) — confirmed; Observation 1 (medium). The companion's claim that the PR's tests reference `token_limited=True`, `test_request_rate_429_while_unverified_walks_to_the_next_hop` or `test_unverified_status_is_per_hop_not_inherited_from_the_head` is false — no such symbols exist under `pr/head/` (grep: zero hits); the shipped e2e test encodes the opposite contract.
- DISS-001 (every 429 ends an unverified call) — a design choice the tests encode; Observation 1 (medium), not blocking.
- DISS-005 / DISS-C-004 (`str(_exc)` as `message_redacted`) — not counted: every other `models_failed` arm in the file uses the same pattern and the envelope writer redacts (`redact_payload_strings` / `assert_no_secret_shapes_remain` are patched out in the e2e test for that reason). No new exposure is introduced.
- DISS-C-005 (generic context-limit predicate) — Observation 3 (low).
- DISS-C-006 (duplicated floor literal) — Observation 4 (low).

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has no rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Every size decision derives from the resolved catalog entry | Partial | Policy module, adapters, Flatline and BB tables do; the chain-walk gate still trusts the heuristic over the count (CR-1); Flatline's 600 s timeout is now decoupled from its 64K budget (Obs. 2). |
| Provider size verdict is typed, never walked, and recorded | Fail | Holds except on the last retry attempt, where it becomes a walkable `RetriesExhaustedError` (CR-2). |
| Long-context premium billed above the threshold | Fail | Trigger ignores cached input (CR-3). |
| Generated maps / tables match the catalog | Pass | `MODEL_MAX_OUTPUT`, `GENERATED_TOKEN_BUDGETS`, `GENERATED_REASONING` re-derived from the yaml: 31 entries, no mismatch; dist/ mirrors resources/. |
| Shell consumers sized from the catalog | Pass | FMT-1..6, MPE-1..3, CR-8, LSP-5 pass on the head scripts. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries — `beta_headers` allowlisted (`_BETA_HEADER_RE`), observed store tolerant of malformed JSON, catalog writer refuses unknown blocks/tiers
- [x] Authentication/authorization — unchanged; `count_tokens` reuses the adapter's headers and fails closed to `None`
- [x] No injection — `write_catalog` is a line-level edit of a known block; `loa-status.sh` interpolates a model id read from the catalog itself
- [x] Dependencies — none added
- [x] Error messages — provider text follows the existing redaction path (see Cross-Model Observations)

---

## Code Quality Summary

**Strengths:**
- `ceiling.py` names every basis of a decision and threads it through the envelope, the log line and the tests; the policy is testable in isolation and the tests cover the I1/I2 corners well.
- The generated artifacts are regenerated faithfully and pinned by cross-checks (`test_transport_matrix.py` asserts BB and Flatline against the same catalog rows).
- The kill switches (`LOA_CHEVAL_LEGACY_CEILING`, `LOA_CHEVAL_LEGACY_WIRE`) keep today's wire bodies reachable.

**Areas for Improvement:**
- The seams between the pre-flight, the chain loop and the retry layer carry duplicated state (`_walk_estimate` vs a fresh heuristic, head-only `_ceiling_unverified`, two floor constants); each duplication produced a finding.
- The e2e suite exercises the `derived` opt-in heavily and the default `probed` policy near the bound hardly at all.

---

## Next Steps

1. Fix CR-1..3 (walk gate uses `_walk_estimate`; shrink arm checks the attempt budget and keeps the typed error; premium trigger sums cached input) and add the named tests.
2. Decide Observation 1 (per-hop unverified flag) and Observation 2 (Flatline timeout vs 64K budget) — both are one-line decisions worth recording in NOTES.
3. Re-run the Python suite on a full checkout (not possible in this layout) and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":3,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T05:40:00Z"} -->
