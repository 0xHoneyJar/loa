# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The PR (cycle-126 sprint-247, 65 files) makes every size decision a policy over the resolved catalog entry: a new `loa_cheval/routing/ceiling.py` (I1 output-budget shrink, I2 probed/calibrated/derived/observed bound, provider context-limit parsing, an observed-bound store), the pre-flight and chain-walk in `cheval.py` consume it, the Anthropic adapter gains `count_tokens`, `anthropic-beta` allowlisting and a models-endpoint health probe, `temperature` leaves the wire unless set, non-Anthropic hops get catalog-driven output defaults, pricing gets a long-context tier, Flatline sizes `--max-tokens` from the catalog, and Bridgebuilder's generated tables carry `maxOutput` and a reasoning flag. The design is coherent and well documented (`multi-model-reference.md`), the generated maps are drift-free (regenerated from the head catalog and diffed: identical), and the test files are substantive (12 Python files, 2 new bats files, 1 new TS test).

Five defects block the merge. Two are on the default path: the chain-walk gate still compares the chars/3.5 heuristic against the policy bound after the pre-flight replaced it with the provider's count, so the head hop is skipped exactly in the cases D-1.4 exists for; and Bridgebuilder's default model is now the alias `opus`, which no truncation table knows, so the raised 200K default input budget is no longer clamped to the model's dispatchable input. Three sit on the D-1.1b arms: `_ceiling_unverified` is computed for the head entry and reused on every fallback hop; the retry layer's one-shot output-budget shrink can land on the final loop iteration and degrade the provider's size verdict into `RetriesExhaustedError` (which cheval then walks, violating "never walked"); and the long-context premium tests `input_tokens` alone while Anthropic's `input_tokens` excludes cache tokens.

**Verification performed here:** the head catalog regenerated through `gen-adapter-maps.sh` matches `generated-model-maps.sh` byte-for-byte (comment lines aside); every head `.py` compiles; the touched bats files were run on an overlay — 19 of the PR-relevant tests pass (FMT, MPE, CR-8, LSP-5, B1–B4, ED-8, CM-1..5), the 9 failures were all `model-adapter.sh: Permission denied` from a noexec temp mount and are not attributable to the PR; the Python tests that import `cheval.py` could not be executed because the only framework tree available is a newer revision whose untouched modules import symbols the PR's `types.py` lacks — their assertions were read instead. TS tests were not run (no `node_modules`); `dist/` was spot-checked against `resources/` (reasoning table 31 entries, maxOutput 32000 ×12 in both).

**Process note:** `reviewer.md` is the PR title only — no `## AC Verification` section, no assumptions, no self-check (formatter / `tsc --noEmit`) record. Under the skill's rules that alone forces CHANGES_REQUIRED; it is moot given the findings below but should be supplied on resubmission. `br` is not installed here, so no beads comments were recorded.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the chain-walk gate discards the provider count

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2119` — the per-hop walk gate recomputes `estimate_tokens(messages)` (the chars/3.5 heuristic) and compares it to the policy bound, after the pre-flight replaced the heuristic with the `count_tokens` result and stored it in `_walk_estimate` (`head/.claude/adapters/cheval.py:1842`). When heuristic > bound ≥ count the pre-flight dispatches and the walk skips the head hop.
**File:** `head/.claude/adapters/cheval.py:2119`
**Issue:** Two different input numbers are judged against the same bound inside one hop. Concrete input: a CJK-dense or tool-heavy prompt the heuristic puts at 185K on an uncalibrated `claude-opus-5` (probed 180K). Pre-flight: 185K ≥ 0.9 × 180K → `count_tokens` → 172K → `dispatch`. Walk gate: `_lookup_max_input_tokens` returns 180K, `_estimated` = 185K > 180K → `ROUTING_MISS`, `continue` → the request runs on the fallback (`claude-opus-4-8` / `claude-headless`), the count call was wasted, and the envelope's `estimated_input_tokens` (172K) contradicts the `models_failed` message (185K). The per-hop I1 fit a few lines above (`cheval.py:2090`) already uses `_walk_estimate`, so the inconsistency is local.
**Why This Matters:** D-1.4 ("near the bound the provider's count is authoritative") is silently defeated at the head hop — precisely for the high-uncertainty content classes it was added for. Operators see a dispatch on a model they did not select. `test_ceiling_e2e.py:167` does not catch it because its count (611K) exceeds the heuristic (600K) and both sit under the derived bound.
**Required Fix:** Compare `_walk_estimate` (when set) in the walk gate instead of re-estimating, or re-estimate only for hops after the head. Add an e2e case with `count ≤ bound < heuristic` asserting one dispatch on the head model.

### 2. Functionality — Bridgebuilder's default model is an alias the budget tables cannot clamp

- **HIGH** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — the default `model` becomes `"opus"` while `maxInputTokens` rises to 200_000 (`config.ts:176`); neither `truncation.generated.ts` nor the generator (`head/.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts:277-290`) emits an alias table, so `getTokenBudget("opus")` resolves to `TOKEN_BUDGETS["default"]` and the operator budget is never clamped to the model's 160K dispatchable input.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172`
**Issue:** Before this PR the default `claude-opus-4-7` was a known id, so the budget was clamped to the generated `maxInput` (180K ceiling − 20K headroom = 160K). Now an unknown id keeps the operator budget: 200K tokens at BB's 0.25/char coefficient is 800K chars, which cheval estimates at 800K / 3.5 ≈ 229K tokens — above the 180K probed bound — so a review that fills the default budget is preempted `CONTEXT_TOO_LARGE` at cheval's gate. The persona files (`personas/security.md:2`, `personas/quick.md:2`) changed the same way but are commented-out lines `main.ts` ignores, so they are harmless.
**Why This Matters:** The largest reviews (the ones the 1M-window family was adopted for) fail at the gate with the shipped defaults; smaller ones silently lose the ceiling-aware clamp. `truncation-registry.test.ts` and `config.test.ts` assert the new constants but no test resolves the default model to a budget.
**Required Fix:** Either keep a concrete default id, or have `gen-bb-registry.ts` emit the catalog `aliases:` block as `GENERATED_MODEL_ALIASES` and resolve it in `truncation.ts` `budgetId` (and `effectiveInputBudget`); keep the default `maxInputTokens` at or below the clamped value, or document that cheval's I2 bound is the real limit. Add a test: `getTokenBudget("opus").maxInput === 160_000`.

### 3. Error handling — `_ceiling_unverified` is a head-entry fact applied to every fallback hop

- **HIGH** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — the `RateLimitError` arm (and the `ProviderContextLimitError` classification at `head/.claude/adapters/cheval.py:2256`) consult `_ceiling_unverified`, set once from the head's pre-flight outcome (`cheval.py:1843`) and never recomputed per hop.
**File:** `head/.claude/adapters/cheval.py:2297`
**Issue:** Under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, head `claude-opus-5` (uncalibrated, 250K estimate → `warn`) fails for a walkable reason (`ProviderUnavailableError`, `AuthRevokedError`); the walk reaches `claude-headless` (a CLI hop with no HTTP ceiling) or a calibrated entry; that hop returns 429 → not walked, exit `RATE_LIMITED`, and a `RATE_LIMIT_UNVERIFIED` row is written for the fallback model. A fallback's genuine context verdict is likewise classed `CEILING_UNVERIFIED_LIMIT` although for that entry it is the catalog's error. Conversely an unverified fallback reached from a verified head misses the handling entirely.
**Why This Matters:** The declared chain shape is the operator's contract; this cuts it short on an unrelated hop's throttle and writes misattributed calibration rows into `.run/ceiling-observed.json`. Both dissent voices raised it independently (DISS-002, DISS-C-002b).
**Required Fix:** Compute "above the probed bound" per hop from that hop's entry, budget and `_walk_estimate` (the `input_bound` call already exists in `_lookup_max_input_tokens`), and use that per-hop flag in both arms.

### 4. Error handling — the retry layer's output-budget shrink can swallow the provider's size verdict

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/retry.py:495` — the one-shot shrink does `continue` inside `for attempt in range(max_retries + 1)` without checking that another iteration exists and without setting `last_typed_error` / `last_error`.
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:495`
**Issue:** When the shrinkable `ProviderContextLimitError` arrives on the final iteration (`max_retries: 0` in `retry_config`, or after earlier 429 / 5xx attempts consumed the allowance), the loop ends and the post-loop `RetriesExhaustedError` fires (`retry.py:529`) carrying the earlier error's text or `None`. cheval's `except ProviderContextLimitError` arm never runs: no observed-bound record, no `calibration_needed`, and the `RetriesExhaustedError` arm walks the same oversized payload to the next hop — the behaviour D-1.1b says must never happen. The shrunk request is also never sent.
**Why This Matters:** The self-correction loop (record → bound → calibrate) is the sprint's core deliverable and is bypassed in exactly the degraded-provider conditions where size verdicts cluster with throttles. `test_ceiling_retry.py` covers only `max_retries ≥ 1` with the context error on the first attempt.
**Required Fix:** On the shrink path, if `attempt >= max_retries` (or the global budget is spent) re-raise the typed error instead of `continue`; otherwise perform the retry outside the attempt budget (it is not a transient failure). Set `last_typed_error = e` so an exhausted run still carries the context class. Add a test with `max_retries=0`.

### 5. Metering — the long-context premium threshold ignores cache tokens

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — `if threshold is not None and input_tokens > threshold` decides the premium on `input_tokens` alone, while the multipliers are then applied to `cr_cost` / `cw_cost` (`pricing.py:171-173`).
**File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
**Issue:** Anthropic's `usage.input_tokens` excludes `cache_read_input_tokens` and `cache_creation_input_tokens` (the adapter reads them as separate fields, `anthropic_adapter.py:557-562`, and the ledger records them separately, `ledger.py:132-134`); the provider's 1M-window premium applies to the full prompt. A 150K-cached + 100K-fresh request (250K prompt) is billed here at base rates with `long_context` unset, while the invoice carries 2.0× / 1.5×. The multipliers are also applied to already-floored per-category costs (`int(cost * m)`), a secondary rounding drift of up to 1 µUSD per category.
**Why This Matters:** The cost ledger drives `cost-budget-enforcer` and `cost-report.sh`'s new `long_context_rows`; it under-reports on exactly the cache-heavy, long-context workloads the 5-family is dispatched for. Both dissent voices raised it (DISS-003, DISS-C-005).
**Required Fix:** Test `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`; apply the multiplier to the product before flooring. Extend `test_long_context_pricing.py` with a cached case.

---

## Observations

### 1. Concurrency and state hygiene

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/routing/ceiling.py:279` — `record_observed` is load → append → `mkstemp`+`os.replace` with no lock. Two cheval processes (the adversarial review runs two voices in parallel) that hit provider limits concurrently race on the read-modify-write and one row is lost. The repo's ledgers all take `flock` for this reason (issue #689).
**Suggestion:** Take an `fcntl.flock` on a sidecar lock file around load+write (O_NOFOLLOW on the lock path as the other writers do).
**Benefit:** No lost observations; the bound tightens on the first verdict, not the second.

- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2005` — `_obs` falls back to `int(_walk_estimate or 0)`; with `LOA_CHEVAL_DISABLE_INPUT_GATE=1` `_walk_estimate` is `None`, so a provider verdict without numbers records `observed_input_tokens: 0`. `observed_for` ignores it (`_pos_int`), but `loa-status.sh:813` takes `min` over the raw field and prints `ceiling: observed -1`. Separately `ceiling.py:122` applies `observed − 1` with no plausibility floor, so a stray row of 1 would collapse the bound to 0 until hand-edited.
**Suggestion:** Skip the record when there is no positive observation; ignore (and warn once on) observations outside a sane band of the context window, in both the Python reducer and the jq.

### 2. Design of the D-1.1b arms

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — by design, any `RateLimitError` on a request that ran above the probed bound ends the run (`RATE_LIMIT_UNVERIFIED`, exit 1) and writes a store row. The exception carries no discriminator between a requests-per-minute throttle and an input-tokens-per-minute one, so an ordinary RPM 429 (already backed off by the transport) overrides the chain. Both voices flagged it (DISS-001, DISS-C-002a); the PR's own test asserts the behaviour, so this is a design question for the SDD owner rather than a defect.
**Suggestion:** Only take the non-walk path when the 429 body names a token-rate limit (`tokens per minute`, `input tokens`); walk otherwise.

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/routing/ceiling.py:159` — the marker `"too many tokens"` also matches throttle text ("Too many tokens, please wait before trying again"). Only the `status in (400, 413)` gate (`anthropic_adapter.py:361`, `:503`) keeps a throttle from becoming a terminal `CONTEXT_TOO_LARGE` that lowers the bound; a proxy that maps 429 to 400 would cross it.
**Suggestion:** Check throttle markers first, or require a parsed number for the bound-lowering classes.

### 3. Output budgets and transports

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:1027` — every Anthropic voice now receives an explicit `--max-tokens 64000`. An explicit value bypasses `default_max_tokens`' transport awareness (`_hop_max_tokens` only clamps to `max_output_tokens`), so under `LOA_CHEVAL_DISABLE_STREAMING` the non-streaming call carries a 64K budget (the 16K default existed for that path) and under `LOA_CHEVAL_LEGACY_WIRE` the 4096 kill-switch default is bypassed. The cycle-124 rationale the test header still states (`head/tests/unit/cycle-124-dispatch-budgets.bats:8`: "timeouts never meet a 64K generation") is now contradicted by the tests below it.
**Suggestion:** Pass no `--max-tokens` for Anthropic entries whose catalog value exceeds the cap (cheval's own default is already `min(64K|16K, max_output_tokens)`), or make the cap transport-aware; refresh the bats header.

- **MEDIUM** (confidence: low) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672` — `health_check` returns `False` for any non-200/non-404 answer from `GET /models`. Proxies that front only the Messages API commonly answer 401/403/405/501 for unknown routes; the previous one-token probe would have succeeded there.
**Suggestion:** Fall through to the tiny-model probe on 404, 405, 501 (and arguably any non-2xx other than 401/403), not 404 alone.

### 4. Legacy wire, tests and simplicity

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:241` — under `LOA_CHEVAL_LEGACY_WIRE`, `wire_temperature(None)` returns 0.7 (`base.py:184`) and the old `!= 0.7` guard is gone, so every call to a `temperature_supported: false` entry logs "temperature 0.7 dropped" (WARNING first, INFO after) for a value no caller set.
**Suggestion:** Only log when `request.temperature is not None`.

- **LOW** (confidence: high) GOAL-DRIVEN: `head/.claude/adapters/tests/test_ceiling_e2e.py:167` covers count > heuristic only (see Change 1); `head/tests/unit/flatline-call-model-schema.bats:48` still greps the removed `FLATLINE_(REVIEW|SCORE)_MAX_TOKENS` constants (dead, harmless).

- **LOW** (confidence: low) SIMPLICITY[native]: `head/.claude/scripts/lib-multipass.sh:98` — `_multipass_is_anthropic` is a hand-maintained regex (`opus|sonnet|haiku|fable|tiny$|cheap$`) duplicating the catalog's `aliases:` block; `generated-model-maps.sh` already carries alias → provider. Lean otherwise: `gate()` is ~75 lines but is the single decision point and reads linearly. net: −6 lines possible.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (primary `gpt-5.5-pro`, companion `claude-headless`, both completed, `counted_as: independent_voice`; 12 findings, 0 advisory voices). Verified and folded in above: DISS-001/DISS-C-002a (Observation 2), DISS-002/DISS-C-002b (Change 3), DISS-003/DISS-C-005 (Change 5), DISS-004/DISS-C-003 (Change 4), DISS-C-001 (Change 1), DISS-C-006 (Observation 4), DISS-C-007 (Observation 1), DISS-C-008 (Observation 3). Not adopted: DISS-C-004 (raw provider text in `message_redacted` / stderr) — every pre-existing arm in `cmd_invoke` builds the field the same way (`cheval.py:2155`, `:2243`, `:2268`, …) and the MODELINV emitter redacts on write; the test the voice cites does not exist in the PR. Pre-existing pattern, not introduced here.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` is zero bytes.

---

## Previous Feedback Status

Not applicable — first review of this sprint.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required 1–5 above; `reviewer.md` lacks an AC Verification walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Every size decision derives from the resolved catalog entry | Fail | Bridgebuilder default budget is unclamped for the `opus` alias (Change 2); Flatline's explicit 64K bypasses the transport-aware default (Observation 3) |
| I1 / I2 bound enforced consistently across pre-flight and walk | Fail | Walk gate uses the heuristic after the count replaced it (Change 1) |
| Provider size verdict never walked; observed bound recorded | Fail | Final-attempt shrink degrades to `RetriesExhaustedError` and walks (Change 4); per-hop unverified flag inherited (Change 3) |
| Long-context premium billed per the provider rule | Fail | Threshold excludes cache tokens (Change 5) |
| Generated maps / tables in sync with the catalog | Pass | `gen-adapter-maps.sh` output identical to the committed map; `dist/` matches `resources/` |
| Temperature off the wire unless set; beta headers allowlisted; health probe via `/v1/models` | Pass | Verified in all four adapters, `_beta_header_value`, `health_check` (Observation 3 on the 404-only fallthrough) |
| Tests accompany each seam | Pass (partial) | Substantive coverage; gaps named in Observation 4 |

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:44:00Z"} -->
