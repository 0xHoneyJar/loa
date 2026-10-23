# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)

---

## Overall Assessment

The PR (cycle-126 sprint-247, 65 files) replaces the single input-ceiling literal with a policy over the
catalog entry (`loa_cheval/routing/ceiling.py`: I1 fit, probed/calibrated/derived/observed bounds, a count
endpoint near the bound, self-correction via `.run/ceiling-observed.json`), gives every provider a
catalog-driven output default, drops the implicit 0.7 temperature, adds `anthropic-beta` allowlisting, a
long-context pricing tier, and re-sizes Flatline and Bridgebuilder from the same catalog rows. The design is
sound and well tested where it is tested: the PR's own Python tests pass (163/164 in an overlay tree; the one
failure is caused by this snapshot's newer `.loa.config.yaml`, not the PR) and its bats tests pass (the
failing bats cases are environmental: a `model-adapter.sh` exec bit lost by my copy and a newer loader
WARN line on stderr).

The self-correction arm (D-1.1b) ships with three defects I reproduced against the head code: a plain
requests-per-minute 429 ends the chain, the "unverified" flag of the head entry is inherited by every
fallback hop, and the observed-bound store loses rows under concurrent writers. Bridgebuilder's new default
model is the alias `opus`, which has no row in either budget table, so the default review runs on the
fallback budget (or the raw 200K operator budget, above cheval's 180K probed bound). The dissent voices
added four medium findings I verified (long-context threshold ignores cached tokens; the retry-layer shrink
is lost on the last attempt; the non-Anthropic output default raises the adapter's own refusal line; the
count-vs-heuristic mismatch between gate and adapter).

Test-run caveat: this snapshot's untouched modules are newer than the PR's base, so the overlay used the
snapshot's `loa_cheval/types.py` (a superset of the head's) to import; every finding below was confirmed
by reading the head files or by a repro that imports only head code.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the D-1.1b short-circuit catches every 429, not the token-limit class

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2297` — any `RateLimitError` while `_ceiling_unverified` is set ends the invocation (RATE_LIMIT_UNVERIFIED, exit RATE_LIMITED) instead of walking the chain.
**File:** `head/.claude/adapters/cheval.py:2297`
**Issue:** The PR's own comment (lines 2298–2301) scopes this arm to "the token-limit class", but `RateLimitError` carries no class in this PR and the code tests only `_ceiling_unverified`. A requests-per-minute 429 (the common shape under load) on a request that proceeded above the probed bound under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` is treated as a size verdict.
**Why This Matters:** The operator's declared chain is the contract; here the fallback voice is never tried, the call fails with RATE_LIMITED, and a RATE_LIMIT_UNVERIFIED row is appended to the store for a 429 that said nothing about payload size. Reproduced with the PR's e2e harness: `_run(SIX, errors=[RateLimitError("anthropic")])` under the opt-in dispatches once and exits 1 with `classes=['RATE_LIMIT_UNVERIFIED']`; the PR's own `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` (`head/.claude/adapters/tests/test_ceiling_e2e.py:247-251`) pins this behaviour for a classless 429.
**Required Fix:** Mark the 429 in the adapters (`RateLimitError(..., token_limited=...)` from the 429 body: "tokens per minute", "(TPM)", `context_length_exceeded`, or a context-limit message) and short-circuit only when `token_limited` is true; a request-rate 429 walks as it does under the bound. Update the e2e test to use a token-limited 429 and add the request-rate case (walks, no store row).

### 2. Functionality — `_ceiling_unverified` is head-scoped but applied to every fallback hop

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:1843` — the flag is computed once from the head entry's pre-flight and read at `head/.claude/adapters/cheval.py:2256` and `head/.claude/adapters/cheval.py:2297` for every hop of the walk.
**File:** `head/.claude/adapters/cheval.py:1843`, `2256`, `2297`
**Issue:** "Above the probed bound" is a property of a hop's own entry and budget. A fallback that is calibrated (or whose bound exceeds the estimate) runs the same payload verified, yet inherits the head's `unverified`.
**Why This Matters:** Reproduced with the PR's e2e harness (head above its probed bound under the opt-in, fails 503 and walks; fallback `claude-opus-4-8` calibrated at 900K): a plain 429 on the fallback yields `classes=['PROVIDER_OUTAGE', 'RATE_LIMIT_UNVERIFIED']` and writes a `('claude-opus-4-8', 'RATE_LIMIT_UNVERIFIED')` row against the calibrated model; a provider verdict on the same fallback is classed `CEILING_UNVERIFIED_LIMIT` instead of `PROVIDER_CONTEXT_LIMIT`. The store and the envelope then misattribute calibration evidence to the wrong entry, and the head's envelope flag (`ceiling_unverified`) becomes indistinguishable from the fallback's state.
**Required Fix:** Compute `_hop_unverified` per hop inside the walk loop (`input_bound(_hop_entry, max_tokens=_hop_budget, observed=..., policy=...)`; unverified iff not calibrated and `_walk_estimate > decision.probed`) and use it at both arms; keep the head's `ceiling_unverified` on the envelope as the pre-flight record only.

### 3. Data loss — `record_observed` has no inter-process lock

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:279-299` — read → append → `os.replace` with no lock; concurrent writers overwrite each other's rows.
**File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:279-299`
**Issue:** `load_observed(path)` at line 279 and `os.replace(tmp, path)` at line 299 are not serialised across processes. The docstring calls the store "append-only history", and `observed_for` reduces it to the tightest bound.
**Why This Matters:** Flatline dispatches three voices and the adversarial review two voices concurrently against the same provider with the same payload size, so simultaneous provider verdicts are the normal case, not a corner. Repro importing only `head/.../routing/ceiling.py`: 4 forked writers × 25 rows retained 26, 30 and 27 of 100 rows in three trials. A lost PROVIDER_CONTEXT_LIMIT row means the bound is not lowered and the next call repeats the paid failure.
**Required Fix:** Hold an exclusive `fcntl.flock` on a sibling lock file (`<store>.lock`, opened `O_NOFOLLOW`, refused when a symlink or not a regular file, per the repo's atomic-write symlink defences) around load → append → replace; keep temp + `os.replace` for lock-free readers. Add a multi-process test (N writers × M rows all retained).

### 4. Regression — Bridgebuilder's new default model has no token budget

- **HIGH** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — `DEFAULTS.model` becomes the alias `opus`, which is a key in neither `GENERATED_TOKEN_BUDGETS` (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19-56`, model ids only) nor the hand table.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172`, `head/.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts:284-292`, `head/.claude/skills/bridgebuilder-review/resources/personas/quick.md:2`, `head/.claude/skills/bridgebuilder-review/resources/personas/security.md:2`
**Issue:** The budget lookup is by model id; the previous default `claude-opus-4-7` had a row (160K/8192). `getTokenBudget("opus")` now falls to the `default` row (100K input, 4096 output) and the effective input budget for an unknown id is the raw operator budget, which this PR raises to 200_000 (`config.ts:176`). Verified by loading head's generated table into the truncation module: `opus → {maxInput:100000,maxOutput:4096}`, `effectiveInputBudget(200000,"opus") = 200000`; `tiny` (the quick persona) behaves the same. Bridgebuilder dispatches through cheval (`adapters/cheval-delegate.ts`), whose probed bound for the alias target is 180K.
**Why This Matters:** Under the default configuration a large PR review is built to 200K estimated tokens and preempted by cheval's pre-flight (CONTEXT_TOO_LARGE, exit 7) where it used to be truncated to 160K; a smaller one runs on a 100K/4096 budget instead of 160K/32K. Either way the "every size decision derives from the resolved catalog entry" goal is not met for the default model, and the PR's new `truncation-registry.test.ts` checks concrete ids only.
**Required Fix:** Have `gen-bb-registry.ts` emit the catalog's `aliases:` block as `GENERATED_MODEL_ALIASES` (provider-qualified targets, self-maps dropped) and resolve an alias to its target id before the budget lookup; add a test that `getTokenBudget("opus")` equals the target's row and that `effectiveInputBudget(200000, "opus")` is clamped to it.

---

## Observations

### 1. Pricing (FR-1.9)

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — the long-context tier triggers on `input_tokens > threshold` only; `cache_read_tokens` / `cache_creation_tokens` are, per `ledger.create_ledger_entry`'s contract (`head/.claude/adapters/loa_cheval/metering/ledger.py:133`, "not part of input_tokens"), separate. A prompt-cached run of 150K cached + 100K fresh tokens is billed at the premium by the provider but recorded at base rates, and `long_context` is absent from the row, so `cost-report.sh` does not count it either. Flatline and Bridgebuilder are exactly this workload (cycle-124 FR-4 cache_control). (Dissent DISS-001 / DISS-C-004, verified.)
**Suggestion:** Compare `input_tokens + cache_read_tokens + cache_creation_tokens` with the threshold; add a test with cached tokens above the threshold.

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/metering/pricing.py:171-175` — the multipliers are applied to the already-floored per-category micro costs and the remainders (`inp_rem`, `cr_rem`, …) are not recomputed. Repro on head: 3 tokens × 1.25 µUSD × 1.5 = 5.625 → head bills 4 (floor(floor(3.75) × 1.5)), exact floor is 5. Small in money, but the remainder accounting that exists to carry sub-micro amounts is silently discarded on the premium path.
**Suggestion:** Compute `floor(tokens × rate × multiplier / 1e6)` per category with the multiplier as an exact decimal, and scale the remainder the same way.

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/metering/pricing.py:290-295` — `_mult` accepts non-finite values: `float("inf")` and `"1e309"` pass `m > 0`, and `int(inp_cost * inf)` at line 171 raises `OverflowError`. Repro on head: `find_pricing` parses `input_multiplier: .inf` as `inf`; `calculate_total_cost(10, 10, 0, entry)` raises. `budget_hook.post_call` (`head/.claude/adapters/cheval.py:2210`) runs inside the walk-loop `try`, so the exception lands in the catch-all (`cheval.py:2402-2420`) and a completed, billed answer is reported as API_ERROR. The parser's own docstring promises "a malformed … block means no premium tier".
**Suggestion:** `math.isfinite(m) and m > 0` (and reject booleans) in `_mult`; add the `.inf` / `nan` / `1e309` cases to `test_long_context_pricing.py`.

### 2. Retry layer (D-1.1b)

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:472-496` — the one-shot shrink does `request = replace(request, max_tokens=room); continue` inside `for attempt in range(max_retries + 1)` and never sets `last_typed_error` / `last_error`. When the context-limit error arrives on the final iteration (always under `retry.max_retries: 0`; otherwise when earlier attempts were spent on 429/503 backoffs) the loop ends without sending the shrunk request, and the post-loop `RetriesExhaustedError` (line 530) carries the previous transient error's text. cheval's `except RetriesExhaustedError` (`head/.claude/adapters/cheval.py:2338`) walks, so the identical oversize payload reaches the next voice, no observation is recorded, and the exit is CHAIN_EXHAUSTED rather than CONTEXT_TOO_LARGE. (Dissent DISS-002 / DISS-C-001, verified by reading.)
**Suggestion:** Give the shrink its own retry outside the attempt counter (or re-raise the `ProviderContextLimitError` when no attempt remains), and set `last_typed_error`.

### 3. Output defaults vs. the adapter's own window check (FR-1.3 / D-1.4)

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/base.py:187-203` with `head/.claude/adapters/cheval.py:2078-2087` — non-Anthropic hops jump from 4096 to `min(16000, max_output_tokens)`, but the walk-loop I1 fit only runs for entries carrying an HTTP ceiling (Anthropic). `enforce_context_window` (`head/.claude/adapters/loa_cheval/providers/base.py:1007-1024`) then evaluates `estimate + 16000 ≤ 128000` on gpt-5.2 (context 128K, `max_output_tokens: 16000`, no v2/v3 input fields, so no walk-gate line): a 115K prompt that fit before now raises `ContextTooLargeError` and walks. Silent, because the walk-gate threshold did not change. (Dissent DISS-C-002, catalog fields verified.)
**Suggestion:** Apply the I1 fit to every hop with a `context_window` (not only ceiling-bearing entries), or keep 4096 for entries without a ceiling.

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:1840-1842` — when the count endpoint runs, `_walk_estimate` becomes the provider count and the I1 fit grants `max_tokens = context_window − count`; the adapter's `enforce_context_window` (`base.py:1019`) still uses `estimate_tokens` (chars/3.5). For prose where the heuristic overcounts (English ≈ 4 chars/token) a request the gate approved near the window (count 130K on a 200K window with 64K requested: fits; heuristic 150K > 200K − 64K) is refused by the adapter and walked. The gate and the adapter now disagree on units. (Dissent DISS-C-003.)
**Suggestion:** Pass the gate's estimate (or the fitted decision) to the adapter, or have `enforce_context_window` accept an override estimate.

### 4. Flatline (FR-1.6)

- **MEDIUM** (confidence: low) `head/.claude/scripts/flatline-orchestrator.sh:129`, `936-946`, `1027` — the 64000 voice cap applies regardless of `LOA_CHEVAL_DISABLE_STREAMING`. cheval's own non-streaming Anthropic default is 16K (`base.py:187-203`) and `_nonstreaming_read_timeout` caps at 600 s (≈ 15K tokens at 25 tok/s); under the kill switch an explicit 64000 is clamped only to the catalog's 128K. The cycle-124 16000 literal was safe on both transports.
**Suggestion:** Cap at the transport default (16000 when the kill switch is set), or let cheval's per-model default decide by passing no `--max-tokens`.

### 5. Hardening and consistency

- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:2022` — `message_redacted: str(_exc)` and the stderr JSON at lines 2032-2037 are not passed through `sanitize_provider_error_message` at this new exit. The adapter sanitises `_extract_error_message`, so this is defence in depth, but every other `models_failed` writer in the file redacts at the recording site.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82`, `174` — `\d` matches Unicode digits and `re.match` with `$` accepts a trailing newline, so `"context-1m-٢٠٢٥-08-07"` or `"context-1m-2025-08-07\n"` pass the allowlist and fail later in the HTTP client (ValueError / UnicodeEncodeError) instead of as the promised `ConfigError`. Use `[0-9]` and `fullmatch`.
- **LOW** (confidence: medium) `head/.claude/scripts/loa-status.sh:806-808` — the model id is spliced into the yq expression text (use `strenv`); at `811-813` the jq `[.observed_input_tokens, …] | min` yields null when a row lacks `observed_input_tokens`, dropping a `provider_limit`-only row, and a `0` row (cheval records `int(_walk_estimate or 0)` when the gate is disabled and the message states no number, `cheval.py:2005`) renders `ceiling: observed -1` while `observed_for` ignores it.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/routing/ceiling.py:159` — the marker `"too many tokens"` also matches Bedrock's throttle text ("Too many tokens, please wait before trying again"). Only 400/413 reach it in the Anthropic adapter today, so no misfire yet; a throttle marker should outrank a context marker before this classifier is reused.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/base.py:998-1003` — `method = "tiktoken"` is reported whenever the module imports, even when `estimate_tokens` fell back to the heuristic (offline `get_encoding`), so the envelope's `estimator.method` can be wrong.
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:1888` and `2105-2109` — the operator-visible "max_tokens shrunk" line is an `elif` behind `action == "warn"` (a request both warned and shrunk prints only the warn), and a fallback-hop shrink writes only the envelope field with no stderr line. An explicit `--max-tokens 64000` can be cut to the 4,096 floor silently. (Dissent DISS-C-006.)
- **LOW** (confidence: low) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672-674` — the message probe runs only when `/models` returns exactly 404; a proxy answering 403/405/501 for unknown paths reports a healthy deployment as down. (Dissent DISS-C-005.) Minor because the pre-cycle probe targeted a retired id.
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2016` — on a CLI hop the calibrate hint is `--model claude-headless`, which `write_catalog` refuses (no block fields), and the observation is recorded against the CLI entry, which carries no HTTP ceiling.
- **LOW** (confidence: medium) `SIMPLICITY[shrink]`: `cmd_invoke` grows by ~250 lines; the pre-flight gate branch (`head/.claude/adapters/cheval.py:1805-1862`) nests four deep inside an already multi-thousand-line function, and `_calibration_needed_exit` is a 50-line closure over eleven enclosing names. Extract both to module-level helpers taking the state dict; `_tiny_model_id` (`anthropic_adapter.py:639-659`) can be a one-line `min()` over priced entries after the haiku check. net: -40 lines possible.

### 6. Process

- `reviewer.md` (= `pr/PR.md`) is a one-line title and has no `## AC Verification` walkthrough; per the review protocol this alone forces CHANGES_REQUIRED. Please add the per-FR verification (FR-1.1–FR-1.9) with `file:line` evidence.
- No CHANGELOG is present in this snapshot, so the per-task CHANGELOG entry could not be verified. `multi-model-reference.md` and the Bridgebuilder `SKILL.md` were updated.

---

## Cross-Model Observations

Two voices answered (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`); eight advisory/blocking findings, triaged above:

- DISS-001 / DISS-C-004 (threshold ignores cached tokens) → real, Observations §1 MEDIUM.
- DISS-002 / DISS-C-001 (shrink lost on the last attempt, falls through walkable) → real, Observations §2 MEDIUM.
- DISS-C-002 (non-Anthropic 16K default vs. adapter window check) → real, Observations §3 MEDIUM.
- DISS-C-003 (count vs. heuristic between gate and adapter) → real, Observations §3 MEDIUM.
- DISS-C-005 (health probe only on exactly 404) → real but minor, Observations §5 LOW.
- DISS-C-006 (shrink notice hidden / fallback shrink silent) → real, Observations §5 LOW.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` is 0 bytes.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1.1 input bound is a policy over the entry (I1/I2, probed default, opt-in derived, observed, legacy) | Partial | Policy module correct and tested; self-correction arm has the three HIGH defects above |
| FR-1.2 `anthropic-beta` from `params.beta_headers` only, allowlisted | Pass | Regex/fullmatch nit (LOW) |
| FR-1.3 output default `min(cap, max_output_tokens)` every provider; temperature unset by default | Partial | Non-Anthropic 16K default raises the adapter's refusal line on 128K entries (MEDIUM) |
| FR-1.4 estimator uncertainty + count endpoint near the bound | Partial | Adapter still checks the heuristic (MEDIUM) |
| FR-1.5 Bridgebuilder budgets/reasoning from the yaml; default model `opus` | Fail | Alias has no budget row (HIGH #4) |
| FR-1.6 Flatline per-voice `min(64000, max_output_tokens)` | Pass | Kill-switch interaction noted (MEDIUM, low confidence) |
| FR-1.7 health probe without a retired id | Pass | 404-only fallback (LOW) |
| FR-1.8 transport matrix test | Pass | |
| FR-1.9 long-context pricing tier + ledger/cost-report flag | Partial | Cached tokens, rounding, non-finite multiplier (3 × MEDIUM) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the retired probe model id is gone; no keys in the diff)
- [x] Input validation at trust boundaries — `beta_headers` allowlisted (regex nit above); `write_catalog` refuses unknown blocks/tiers
- [x] Error messages sanitised at the adapter; one new recording site skips the helper (LOW)
- [x] Atomic writes for the store and the catalog (temp + `os.replace`); the store needs a lock (HIGH #3) and the lock file the symlink defence
- [x] No new network egress beyond `/v1/models` and `/v1/messages/count_tokens` to the configured endpoint

---

## Code Quality Summary

**Strengths:**
- The ceiling policy is a pure, well-named module with every basis recorded on the decision and the envelope; the tests cover each basis and the kill switch.
- The e2e harness (`test_ceiling_e2e.py`) exercises the real gate with a fake transport, which made the defects above cheap to reproduce.
- Catalog edits are byte-preserving (`write_catalog`), and the generated maps keep Flatline and Bridgebuilder on the same rows.

**Areas for Improvement:**
- Per-hop state must be computed per hop (HIGH #2); the chain walk is the product's safety net.
- Concurrency on shared state files needs a lock, not only atomic replace (HIGH #3).
- Keep the gate's units and the adapter's units the same (count vs. heuristic).

---

## Next Steps

1. Fix the four Changes Required items (hop-scoped `unverified`, token-limit-only 429 short-circuit, store lock, alias budget row).
2. Address the pricing MEDIUMs together (threshold on total prompt, multiply before flooring, finite multipliers).
3. Re-run the adapter suite and the Bridgebuilder tests; add the repro cases named above.
4. Add `## AC Verification` to the report and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T02:50:00Z"} -->
