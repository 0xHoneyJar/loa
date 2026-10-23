# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Scope:** the cycle-126 sprint-247 PR "full-size adapters, Bridgebuilder and Flatline — every size decision derives from the resolved catalog entry", 65 files. Findings cite `head/<path>:<line>` with lines from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The security posture of the change is sound at the trust boundaries it adds: the `anthropic-beta` header is allowlisted before it reaches the wire (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82`, `:171-181`); `count_tokens` sends exactly the prompt the request would send to the same provider (`:591-618`); the retired hard-coded probe id is gone (`:638-660`); the observed-bound store is written atomically with unlink-on-failure (`head/.claude/adapters/loa_cheval/routing/ceiling.py:294-305`) and loaded fail-open (`:225-237`); no secret or credential-shaped literal is added outside test fixtures (`sk-ant-test`). `routing/ceiling.py` is a small pure policy with every basis named in the decision and good unit coverage.

Two defects block the merge, both confirmed independently of the review. The per-hop walk gate re-runs the chars/3.5 heuristic after the pre-flight has replaced the estimate with the provider's `count_tokens` answer, so a request the provider confirmed fits is refused `ROUTING_MISS` on every HTTP hop (`head/.claude/adapters/cheval.py:2119`). Bridgebuilder's new default model `opus` is a catalog alias that no table on the TypeScript side resolves — there is no alias export anywhere under `pr/head/.claude/skills/bridgebuilder-review/` — so the default review sizes from the 100K/4096 fallback row instead of the 160K/32K catalog row (`head/.claude/skills/bridgebuilder-review/resources/config.ts:172`). One security-relevant medium is added to the review's findings: numbers parsed from a provider error body (or, failing that, cheval's own estimate) become a persistent input bound with no plausibility check and no expiry, so one malformed or hostile 400 can preempt every later request to that model until an operator runs the paid probe (`head/.claude/adapters/cheval.py:2005`, `ceiling.py:122-123`, `:249-260`). The remaining mediums and lows are correctness and hardening items.

**Gate state.** `engineer-feedback.md` carries `CHANGES REQUIRED` (critical 0, high 2, medium 5, low 6, excluded 0), not "All good"; the task instruction for review-r11 is to run the audit regardless, so Phase 0 is recorded as a process gap and the audit proceeds. The implementation report is the PR title only (no `## AC Verification`) — a process gap, not counted. `grimoires/loa/known-failures.md` is unreadable on this mount (KF-SURFACE warning) — triaged without it. `pr/head/.claude/adapters/.run/audit.jsonl` is not in `pr/head.diff`; it is a tool-audit row written during the earlier review session (timestamp 2026-10-22T18:21:42Z, cwd under `pr/head/`), not part of the PR, and is out of scope.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 6 |
| Low | 8 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The walk gate discards the authoritative `count_tokens` estimate

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/adapters/cheval.py:2119`
**Issue:** The pre-flight replaces the heuristic with the provider's count — `_preflight_estimated = _preflight_outcome.estimate.tokens` / `_walk_estimate = _preflight_estimated` (`cheval.py:1841-1842`; `gate()` at `head/.claude/adapters/loa_cheval/routing/ceiling.py:409-412`) — and the per-hop I1 fit consumes `_walk_estimate` (`cheval.py:2090`). The walk gate then does
```python
from loa_cheval.providers.base import estimate_tokens
_estimated = estimate_tokens(messages)
if _estimated > _input_threshold:
```
(`cheval.py:2118-2120`) and compares the raw chars/3.5 number against the same bound `_lookup_max_input_tokens` just computed with the policy (`cheval.py:741-756`).
**Failure scenario:** English prose, heuristic 190,000, provider count 166,000, probed bound 180,000. Pre-flight: 190K ≥ 0.9 × 180K → counter runs → 166K ≤ 180K → `dispatch`, envelope `estimator.method: count_tokens`. Walk gate on the head hop: 190,000 > 180,000 → `ROUTING_MISS`; same on every HTTP fallback; the chain lands on `claude-headless` (different transport, cost and timeout class) or exits `CHAIN_EXHAUSTED`. The envelope says 166,000 estimated beside rows saying 190,000 > 180,000.
**Fix:** `_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)` at `:2119` (and in the `message_redacted` text), so pre-flight, I1 and the walk gate agree. Add an e2e row to `test_ceiling_e2e.py` with heuristic > bound ≥ count asserting one dispatch and no `ROUTING_MISS`.
**Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [HIGH-002] Bridgebuilder's default model is an alias its budget table cannot resolve

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` (also `:176`; `head/.claude/skills/bridgebuilder-review/resources/personas/quick.md:2`, `head/.claude/skills/bridgebuilder-review/resources/personas/security.md:2`)
**Issue:** `model: "opus"` replaces the concrete `claude-opus-4-7`. The comment says the alias is "resolved by cheval's alias path" — true for dispatch — but Bridgebuilder's own size decisions key on the model string: `getTokenBudget` looks up `GENERATED_TOKEN_BUDGETS` (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19-52`), which carries only concrete ids. Verified: no `GENERATED_MODEL_ALIASES` (or any alias table) exists anywhere under `pr/head/.claude/skills/bridgebuilder-review/` — resources or `dist/` — and `gen-bb-registry.ts` emits none. The later workspace snapshot of this repository adds exactly that export and an alias step in `budgetId()`, which corroborates the gap at this head.
**Failure scenario:** `getTokenBudget("opus")` → `TOKEN_BUDGETS["default"]` = 100,000 / 4,096 / 0.25. The base default resolved to the 160,000-input row; the head default resolves to 100,000, a 37 % smaller review payload in the PR whose purpose is to size from the catalog. `tiny` (quick persona) has the same problem. The 32,000 `maxOutput` the new `truncation-registry.test.ts` asserts is never reached by the default model. Separately `DEFAULTS.maxInputTokens: 200_000` (`config.ts:176`) exceeds both the probed bound (180,000) and the generated row (160,000); wherever the raw value governs the prepared payload, cheval's gate preempts it with `CONTEXT_TOO_LARGE`.
**Fix:** Emit the yaml `aliases:` block into `truncation.generated.ts` and resolve it in `getTokenBudget` before the lookup (or keep a concrete default and let the registry generator mirror the retarget). Add a test that `getTokenBudget("opus")` equals `getTokenBudget("claude-opus-5")` and `getTokenBudget("tiny")` equals the haiku row. Clamp `maxInputTokens` to `getTokenBudget(model).maxInput` for known ids.
**Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

---

## Medium/Low Priority Issues

### [MED-001] Provider error text becomes a persistent input bound without a plausibility check
- **File:** `head/.claude/adapters/cheval.py:2005` (with `head/.claude/adapters/loa_cheval/routing/ceiling.py:122-123`, `:249-260`; `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:361`, `:503`)
- **Severity:** MEDIUM (confidence: medium) — security / input validation
- **Issue:** The adapter types any 400/413 whose body matches `is_context_limit_message` and fills `input_tokens` / `limit` from `parse_context_limit` of the free-text body. `_calibration_needed_exit` then persists those numbers — or, when the provider states none, cheval's own estimate (`_obs = ... else int(_walk_estimate or 0)`, `:2005`) — via `record_observed`. `observed_for` reduces the store to `min(observed, provider_limit + 1)` and `input_bound` lowers the bound to `observed − 1` with no floor, no ceiling against `context_window`, no consistency check (`input_tokens > limit`), and no expiry. A single body of the shape `prompt is too long: 1 tokens > 1 maximum` (a misbehaving upstream or intercepting proxy), or a 413 byte-size refusal on a text-light payload, sets the bound near zero; every later request to that (provider, model) preempts with `CONTEXT_TOO_LARGE` until the operator runs the paid probe or deletes `.run/ceiling-observed.json`. Confirmed by cross-model review (DISS-C-001); the review's Low on the 413 estimate fallback is folded in here.
- **Fix:** Before lowering, require `FLOOR_MAX_TOKENS ≤ limit ≤ context_window`, `observed ≥ cheval's own estimate` (the provider cannot have seen fewer tokens than were sent), and `input_tokens > limit` for the parsed shape; when the message states nothing, record with `observed_input_tokens: null` (no bound effect), as the 429 path already does; consider a TTL on observed rows.
- **Reference:** CWE-1284 Improper Validation of Specified Quantity in Input — https://cwe.mitre.org/data/definitions/1284.html; CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [MED-002] `_ceiling_unverified` is the head's status, applied to every hop
- **File:** `head/.claude/adapters/cheval.py:1843` (read at `:2256`, `:2297`)
- **Severity:** MEDIUM (confidence: high)
- **Issue:** Assigned once from the head entry's `GateOutcome`, never recomputed in the chain loop, yet it selects `CEILING_UNVERIFIED_LIMIT` vs `PROVIDER_CONTEXT_LIMIT` and the non-walk 429 short-circuit for every fallback hop. Opt-in head dispatches 600K above its probed bound (unverified), fails with a walkable 503; a calibrated fallback's ordinary 429 then exits `RATE_LIMITED` with a `calibration_needed` record for an entry that was never unverified. The converse mis-classes a provider verdict.
- **Fix:** Derive the status per hop from the hop's `CeilingDecision` (`unverified = policy == "derived" and not decision.calibrated and estimate > decision.probed`); keep the head's flag for the envelope only.
- **Reference:** CWE-697 — https://cwe.mitre.org/data/definitions/697.html

### [MED-003] Any 429 above the probed bound ends the call
- **File:** `head/.claude/adapters/cheval.py:2297-2306` (with `head/.claude/adapters/loa_cheval/types.py:225-229`, `anthropic_adapter.py:343`)
- **Severity:** MEDIUM (confidence: high)
- **Issue:** The comment scopes the arm to "the token-limit class", but it fires on any `RateLimitError` while the flag is set; `RateLimitError` at head carries only `provider` and `retry_after`, and the adapter raises it without the 429 body. A plain requests-per-minute 429 on the primary exits `RATE_LIMITED`, writes a `RATE_LIMIT_UNVERIFIED` row keyed to the input size, and never reaches the declared fallback. Opt-in only, hence medium.
- **Fix:** Parse the 429 body ("input tokens per minute" / "tokens per minute") into a `token_limited` flag on `RateLimitError` and gate the short-circuit on it; otherwise fall through to the `PROVIDER_OUTAGE` walk.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-004] The retry shrink can lose the provider's verdict and walk the oversized payload
- **File:** `head/.claude/adapters/loa_cheval/providers/retry.py:494-495` (with `:527-532`, `head/.claude/adapters/cheval.py:2338`)
- **Severity:** MEDIUM (confidence: high)
- **Issue:** `request = replace(request, max_tokens=room)` / `continue` runs inside `for attempt in range(max_retries + 1)` without setting `last_typed_error`. When the `ProviderContextLimitError` arrives on the final iteration (`max_retries: 0`, or after transient failures, or when the global attempt budget trips) the loop exits and `RetriesExhaustedError` is raised with no typed cause; cheval classes the hop `FALLBACK_EXHAUSTED` and walks the same oversized payload to the next voice — the outcome D-1.1b forbids — with no observed-bound row. The shrunk request is never sent. `test_ceiling_retry.py` only exercises `max_retries: 3`.
- **Fix:** Give the single shrink its own attempt outside the retry count (or `raise` instead of `continue` when `attempt == max_retries`) and set `last_typed_error = e`; add a `max_retries: 0` test.
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [MED-005] The long-context threshold ignores cache tokens
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168` (with `:171-172`; `head/.claude/adapters/loa_cheval/metering/ledger.py:162-166`; `anthropic_adapter.py:557-562`)
- **Severity:** MEDIUM (confidence: medium)
- **Issue:** `if threshold is not None and input_tokens > threshold` tests Anthropic `usage.input_tokens`, which excludes `cache_read_input_tokens` / `cache_creation_input_tokens`, while the premium is applied to `cr_cost` / `cw_cost`. A 60K-fresh + 180K-cached request (240K prompt, premium-billed by the provider) is priced at base rates and `long_context` is not set; `cost-report.sh long_context_rows` and the daily budget enforcer under-count.
- **Fix:** Test `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`; state in the catalog comment which total the threshold applies to.
- **Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html

### [MED-006] 64K per Flatline voice re-opens the cycle-124 timeout hazard
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:1027` (with `:129`, `:115`; `head/tests/unit/cycle-124-dispatch-budgets.bats:5-8`)
- **Severity:** MEDIUM (speculative, confidence: low)
- **Issue:** Review, skeptic and score calls on every 128K-declared entry now pass `--max-tokens 64000` where cycle-124 passed 16000 so the per-call timeout never met a 64K generation; `DEFAULT_MODEL_TIMEOUT=120` is what `run_phase1` / `run_inquiry` pass. The scorer emits a small JSON array; on `claude-opus-5` adaptive thinking shares the budget, so the cap mostly lengthens a runaway generation into the timeout. The bats header still states the old rationale.
- **Fix:** Keep the catalog-derived budget but let the mode supply a cap (score ≤ 16K), or scale the phase timeout; fix the bats header.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [LOW-001] Beta-header allowlist accepts a trailing newline
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82` (applied at `:174`)
- **Severity:** LOW (confidence: high)
- **Issue:** `_BETA_HEADER_RE` ends in `$` and is applied with `re.match`; in Python `$` also matches before a trailing newline. Executed: the pattern accepts `"context-1m-2025-08-07\n"` (`fullmatch` rejects it). httpx and urllib refuse header values containing newlines, so the result is an opaque transport exception rather than header injection — but the allowlist is the stated defence and is weaker than documented. Confirmed by cross-model review (DISS-C-003).
- **Fix:** `_BETA_HEADER_RE.fullmatch(item)` or terminate the pattern with `\Z`.
- **Reference:** CWE-113 — https://cwe.mitre.org/data/definitions/113.html

### [LOW-002] Long-context multipliers accept non-finite values
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:290-295` (with `:168-176`)
- **Severity:** LOW (confidence: high)
- **Issue:** `_mult` accepts any positive float. Executed: `input_multiplier: .inf` (valid YAML) parses to `inf`; `calculate_total_cost` then does `int(inp_cost * inf)` → `OverflowError` after the billed call, inside `create_ledger_entry`, so the completed call's cost is never recorded; an absurd finite value inflates the ledger without bound. Confirmed by cross-model review (DISS-C-004).
- **Fix:** Require `math.isfinite(m)` and clamp to a sane range (e.g. 1.0–10.0), else treat as no premium tier, consistent with the malformed-threshold handling.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [LOW-003] `message_redacted` on the calibration exit is recorded unredacted
- **File:** `head/.claude/adapters/cheval.py:2022` (stderr at `:2034-2039`)
- **Severity:** LOW (confidence: medium)
- **Issue:** `"message_redacted": str(_exc)` and the stderr `_error_json` line carry the provider's 400 body verbatim; `cheval.py` at head imports no redaction helper. This is the same class as every existing `models_failed` arm (`:2155`, `:2243`, `:2268`, `:2285`, `:2311`, `:2327`, `:2349`), and the envelope path is redacted field-level by the untouched `loa_cheval/audit/modelinv.py` (`redact_payload_strings`), so it is not introduced here; the stderr line is the only unredacted surface. Anthropic context-limit bodies are fixed-shape and do not echo the prompt; an intercepting proxy could. The test the dissent cites (`test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`) does not exist at this head (verified by grep).
- **Fix:** Pass `str(_exc)` through `loa_cheval.config.redaction.redact_exception` before recording and before the stderr line; keep only the class and parsed numbers on stderr.
- **Reference:** CWE-532 — https://cwe.mitre.org/data/definitions/532.html

### [LOW-004] Context-limit classifier markers are broad
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:157-175`
- **Severity:** LOW (confidence: medium)
- **Issue:** `_CONTEXT_LIMIT_MARKERS` includes "context window", "context length" and "input length"; any 400 whose text mentions the context window for another reason is typed `ProviderContextLimitError`, never walked, and (via MED-001) lowers the observed bound.
- **Fix:** Classify on the two regex shapes plus the 413 `request_too_large` code; keep the marker list as a logged hint only.
- **Reference:** CWE-697 — https://cwe.mitre.org/data/definitions/697.html

### [LOW-005] `estimator.method` says `tiktoken` whenever the module imports
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:1000-1005` (with `:928-937`)
- **Severity:** LOW (confidence: high)
- **Issue:** `estimate_input` sets `method = "tiktoken"` because `import tiktoken` succeeds, independent of whether `estimate_tokens` actually encoded or fell back to chars/3.5 (the cl100k BPE fetch fails offline). The envelope misattributes the number.
- **Fix:** Return the method from `estimate_tokens`.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [LOW-006] Dead conditional in the probe-tool test
- **File:** `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:66-69`
- **Severity:** LOW (confidence: high)
- **Issue:** The third `pytest.raises` block is `<expr> if False else tool.write_catalog(...)`; the first branch is unreachable and obscures the assertion's intent.
- **Fix:** Keep the minimal-fixture call alone.
- **Reference:** CWE-561 — https://cwe.mitre.org/data/definitions/561.html

### [LOW-007] Probe tool leaves a temp file beside the catalog on a failed write
- **File:** `head/tools/ceiling-probe-live.py:173-176`
- **Severity:** LOW (confidence: high)
- **Issue:** `_write_catalog_file` creates the temp file and `os.replace`s it with no try/except; a write failure leaves `.model-config.*.tmp` under `.claude/defaults/`. The adapter-side `record_observed` (`ceiling.py:294-305`) has the unlink-on-failure this writer lacks. Note also that `--write-catalog` is an operator tool that edits a System-Zone file by design; that is accepted here, not counted.
- **Fix:** Wrap write + replace in `try/except BaseException` with `os.unlink(tmp)` before re-raising.
- **Reference:** CWE-459 — https://cwe.mitre.org/data/definitions/459.html

### [LOW-008] Non-Anthropic default output 4,096 → 16,000 against a fixed read timeout
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:171-181`
- **Severity:** LOW (speculative, confidence: low)
- **Issue:** `default_max_tokens` now returns up to 16K for OpenAI/Google/Bedrock hops while only the Anthropic adapter scales its non-streaming read timeout with `max_tokens`; the comment at `:168-170` says such fixture moves "must move deliberately, not by accident". A legitimate long generation on the legacy transport becomes a 504 and a billed retry.
- **Fix:** Scale the OpenAI/Google non-streaming read timeout with `max_tokens` as the Anthropic adapter does, or keep 4,096 on the legacy transport.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

---

## Cross-Model Security Observations

Dissent: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, `metadata.status: reviewed`, `metadata.model: gpt-5.5-pro` (answered by codex-headless), companion `claude-headless` `succeeded` / `independent_voice`, `voices_succeeded 2/2`, `degraded: false`, no `locality.degraded_security_review`. Five findings (3 MEDIUM, 2 LOW), none CRITICAL/HIGH. Caveat: the primary voice's workdir is a later snapshot of this repository than the PR; the test it cites does not exist at head (verified by grep), so that claim is discarded and the code reasoning assessed on its own.

| Dissent | Triage |
|---------|--------|
| DISS-001 (gpt-5.5-pro, MEDIUM) `_calibration_needed_exit` records `str(_exc)` unredacted | Same class as every existing arm; envelope redaction lives in the untouched emitter; cited test absent at head — LOW-003 |
| DISS-C-001 (claude-headless, MEDIUM) parsed provider numbers become a persistent bound with no plausibility check | Confirmed — MED-001 |
| DISS-C-002 (claude-headless, MEDIUM) same as DISS-001 | Merged into LOW-003 |
| DISS-C-003 (claude-headless, LOW) `_BETA_HEADER_RE` `$` + `re.match` accepts a trailing newline | Confirmed by execution — LOW-001 |
| DISS-C-004 (claude-headless, LOW) `_mult` accepts `inf` → `OverflowError` after the billed call | Confirmed by execution — LOW-002 |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-audit.jsonl` has zero rows.

---

## Review demotions confirmed

The review trailer records `excluded: 0` — no speculative high was demoted. `excluded_confirmed: 0`.

---

## Verification performed

- Every hunk of the 65-file diff read; line numbers cited from `pr/head/`.
- Pure head modules executed on a workspace overlay (`/tmp/ovl`): `test_ceiling_policy.py` 20/21 pass — the one failure (`test_observed_store_default_path_is_the_repo_run_dir`) asserts a repo root above the overlay directory and is an environment artifact; `test_long_context_pricing.py` passes. The cheval-importing test modules cannot be collected here because the workspace's untouched modules import `headless_connect_floor`, which the PR-era `types.py` lacks (the checkout is later than the PR); those were reviewed by reading.
- Executed checks: `_BETA_HEADER_RE.match` accepts a trailing newline, `fullmatch` does not; `_long_context_fields` accepts `float('inf')`; PyYAML parses `.inf`.
- Grep: no `GENERATED_MODEL_ALIASES` under `pr/head/.claude/skills/bridgebuilder-review/`; no `token_limited`, `redacts_secret_shapes`, `unverified_status_is_per_hop` or `request_rate_429` anywhere under `pr/head/`.
- Secrets scan over diff additions: only the `sk-ant-test` fixture value and an `api.example.invalid` endpoint in tests.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the retired `claude-3-haiku-20240307` probe id is removed; `_tiny_model_id` derives from config)
- [x] Input validation at trust boundaries — `anthropic-beta` allowlisted (LOW-001 tightens it); `_long_context_fields` rejects malformed thresholds (LOW-002 extends it to multipliers)
- [ ] Untrusted data is not persisted as policy — provider error numbers become a bound without plausibility checks (MED-001)
- [x] No new data path — `count_tokens` and `health_check` send only to the configured provider endpoint with the same headers
- [ ] Error messages — the calibration exit's stderr line carries the raw provider body (LOW-003; same class as existing arms)
- [x] Atomic state writes — `record_observed` temp + `os.replace` + unlink on failure; the probe tool's writer lacks the unlink (LOW-007)
- [x] Tests cover the new security-relevant paths (beta-header allowlist, observed store, policy bounds); gaps named in MED-004 (max_retries 0) and HIGH-002 (alias ids)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 6 |
| Low | 8 |

Excluded (speculative high, low confidence): 0. Review demotions confirmed: 0.

---

## Next Steps

1. Fix HIGH-001 (one estimate for pre-flight, I1 and the walk gate) and HIGH-002 (alias resolution in the Bridgebuilder budget table; clamp `maxInputTokens`).
2. Address MED-001 (plausibility checks before lowering the observed bound), MED-002/MED-003 (per-hop unverified status; token-limited 429 discriminator), MED-004 (shrink outside the retry count), MED-005 (cache tokens in the threshold); decide on MED-006.
3. Apply the lows (fullmatch, finite multipliers, redaction on the calibration exit, narrower classifier, estimator method, test dead code, temp-file cleanup).
4. Run the adapter pytest suite and the Bridgebuilder `npm test` on a clean checkout; add the tests named above.
5. `/implement sprint-1` to fix, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again. No `COMPLETED` marker is written.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":6,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T18:50:00Z"} -->
