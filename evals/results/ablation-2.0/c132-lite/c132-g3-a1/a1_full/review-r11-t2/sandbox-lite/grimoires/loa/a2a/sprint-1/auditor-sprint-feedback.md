# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Task:** review-r11 — `/audit-sprint sprint-1` over the pull request in `pr/` (cycle-126 sprint-247, 65 files)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change makes every size decision a policy over the resolved catalog entry: a new `loa_cheval/routing/ceiling.py` (I1 output-budget shrink, I2 calibrated / probed / derived / observed bound, provider context-limit parsing, an observed-bound store), `cheval.py` pre-flight and chain-walk consumers, a typed `ProviderContextLimitError` that is never walked, a one-shot output-budget shrink in the retry layer, `count_tokens`, an `anthropic-beta` allowlist and a `/v1/models` health probe in the Anthropic adapter, catalog-driven output defaults for every provider, a long-context pricing tier, Flatline and Bridgebuilder sizing from the catalog, and a `--write-catalog` mode on the live ceiling probe.

The security posture of the new surface is mostly sound: the beta-header allowlist is strict and fails closed (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:163`), `count_tokens` sends exactly the prompt the request would send and swallows every failure to the heuristic (`:591`), temperature leaves the wire unless set, and no secrets or credentials were added (sweep of every head `.py/.sh/.ts/.yaml/.bats/.md`: clean). The weak points are in the new **self-correction loop**: integers parsed from a provider error body become durable routing state with no plausibility floor, the exit path records and prints the raw provider text under a field named `message_redacted`, and the observed-bound store is a lockless read-modify-write. None of those is a confirmed exploitable path against the first-party API over TLS, so none is rated above MEDIUM.

What forces the verdict is the five functional defects the review found; I verified each one independently by reading the head files and by running repro checks against the PR code on an overlay (`grimoires/loa/a2a/audits/2026-10-22/test_audit_repro.py`; all seven checks fail against the PR, as they should). Two are on the default path: the chain-walk gate re-judges the chars/3.5 heuristic after the pre-flight replaced it with the provider's count — in my repro the request did not merely fall to the fallback hop, it exhausted the whole chain (exit 12) because both hops share the 180K probed bound; and Bridgebuilder's new default model `opus` is an alias no generated budget table resolves, so the raised 200K default input budget is never clamped. The newer framework revision checked out in this workspace carries regression tests named for three of these defects (`test_request_rate_429_while_unverified_walks_to_the_next_hop`, `test_unverified_status_is_per_hop_not_inherited_from_the_head`, `test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`) and a plausibility floor in `ceiling.py`, none of which exists in this PR — corroboration that they are real, not evidence they are fixed here.

**Verification performed here:** every head `.py` compiles; the PR's 12 Python test files run on a full repo-shaped overlay (workspace framework tree + the PR's files + a shim of nine newer `types.py` symbols the untouched modules import): **163 passed, 1 failed** — the failure (`test_advisor_tier_points_at_opus_5`) is the workspace's newer `.loa.config.yaml` routing the advisor tier to `claude-headless`, not a PR defect. The security dissent ran on `pr/head.diff` with two independent voices (details under Cross-Model Security Observations). `br` is not installed, so no beads comments or labels were recorded. The Phase 0 prerequisite ("engineer-feedback.md says All good") is NOT met — the review verdict is CHANGES_REQUIRED; the task instruction to audit regardless was followed and the deviation is recorded here.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 6 |
| Low | 10 |

Rubric scores (1–5): Security 3 · Architecture 3 · Code Quality 3 · DevOps 4 · Blockchain/Crypto n/a.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

All five are the review's Changes Required 1–5, confirmed independently (code read + repro). They are functional and metering defects in the sprint's core deliverable, not injection-class vulnerabilities; the Reference column names the closest weakness class.

### [HIGH-001] Chain-walk gate discards the provider count and re-judges the heuristic

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/.claude/adapters/cheval.py:2119`
**Issue:** The pre-flight replaces the estimate with `count_tokens` and stores it in `_walk_estimate` (`head/.claude/adapters/cheval.py:1842`), but the per-hop gate recomputes `_estimated = estimate_tokens(messages)` and compares that heuristic to the policy bound. When heuristic > bound ≥ count the head hop is skipped as `ROUTING_MISS`.
**Repro (R1):** prompt the heuristic puts at 184,993 tokens, `count_tokens` → 172,000, uncalibrated `claude-opus-5` (probed 180,000) with fallback `claude-opus-4-8` (same bound). Pre-flight: `preflight_decision: dispatch`, estimator `count_tokens 172000`. Walk: `models_failed = [ROUTING_MISS, ROUTING_MISS]` both saying "estimated 184993 input tokens > 180000 threshold", `dispatched = []`, **exit 12 CHAIN_EXHAUSTED**. The count call was wasted and the request failed outright on the default policy.
**Fix:** compare `_walk_estimate` in the walk gate when it is set (re-estimate only when the gate was disabled at pre-flight); add the `count ≤ bound < heuristic` case to `test_ceiling_e2e.py` (the existing `test_opt_in_count_endpoint_is_authoritative` at `:167` uses count > heuristic and cannot catch this).
**Reference:** CWE-670 Always-Incorrect Control Flow Implementation — https://cwe.mitre.org/data/definitions/670.html

### [HIGH-002] Bridgebuilder's default model is an alias no budget table can clamp

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172`
**Issue:** `model: "opus"` with `maxInputTokens: 200_000` (`:176`). Neither `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts` nor the generator's `renderTruncation` (`head/.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts:277`) emits an alias table (grep for `alias` in both generated files: none), so an unknown id falls to `TOKEN_BUDGETS["default"]` and `effectiveInputBudget` returns the operator budget unclamped. The previous default `claude-opus-4-7` clamped to 160K. 200K tokens at the 0.25 coefficient is 800K chars, which cheval estimates at ≈229K tokens — above the 180K probed bound — so a review that fills the default budget is preempted `CONTEXT_TOO_LARGE` at cheval's gate. The newer framework tree resolves this via a `GENERATED_MODEL_ALIASES` export that this PR does not generate.
**Fix:** emit the catalog `aliases:` block from `gen-bb-registry.ts` and resolve it in `budgetId`, or keep a concrete default id; add `getTokenBudget("opus").maxInput === 160_000` to `truncation-registry.test.ts`.
**Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

### [HIGH-003] `_ceiling_unverified` is a head-entry fact applied to every fallback hop

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/.claude/adapters/cheval.py:2297`
**Issue:** The `RateLimitError` arm (`:2297`) and the `ProviderContextLimitError` classification (`:2256`) read `_ceiling_unverified`, set once from the head's pre-flight (`:1843`) and never recomputed per hop.
**Repro (R3):** `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, head `claude-opus-5` fails `ProviderUnavailableError` (walkable), fallback `claude-opus-4-8` is **calibrated** (`calibrated_at` set, ceiling 700K) and returns 429 → `models_failed = [PROVIDER_OUTAGE, RATE_LIMIT_UNVERIFIED]`, exit 1, and `.run/ceiling-observed.json` gains a row `('claude-opus-4-8', 'RATE_LIMIT_UNVERIFIED')` — a misattributed calibration record for an entry that was never unverified. Conversely an unverified fallback reached from a verified head gets no handling.
**Fix:** compute "above the probed bound" per hop from that hop's entry, budget and `_walk_estimate` (the `input_bound` call already exists in `_lookup_max_input_tokens`) and use the per-hop flag in both arms.
**Reference:** CWE-668 Exposure of Resource to Wrong Sphere (state attributed to the wrong entry) — https://cwe.mitre.org/data/definitions/668.html

### [HIGH-004] The retry layer's output-budget shrink can land on the final iteration and degrade the provider's verdict

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:495`
**Issue:** The shrink path does `continue` inside `for attempt in range(max_retries + 1)` without checking that another iteration exists and without setting `last_typed_error` / `last_error`; after the loop the generic `RetriesExhaustedError` fires (`:530`).
**Repro (R2):** `max_retries: 0`, one shrinkable `input + max_tokens > limit` error → `RetriesExhaustedError("Failed after 1 attempts: unknown")`, `attempts seen=[64000]` — the shrunk request is never sent and the typed class is lost. In cheval the `RetriesExhaustedError` arm then walks the same oversized payload to the next hop, the behaviour D-1.1b forbids, and no observed-bound row is written.
**Fix:** when `attempt >= max_retries` (or the global budget is spent) re-raise the typed error instead of `continue`; otherwise perform the shrink retry outside the attempt budget; set `last_typed_error = e`. Add a `max_retries=0` case to `test_ceiling_retry.py`.
**Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [HIGH-005] Long-context premium threshold ignores cache tokens

**Severity:** HIGH (confidence: medium)
**File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
**Issue:** `if threshold is not None and input_tokens > threshold` decides the premium on `input_tokens` alone, then multiplies `cr_cost` / `cw_cost` (`:171-173`). Anthropic's `usage.input_tokens` excludes `cache_read_input_tokens` / `cache_creation_input_tokens` (the adapter reads them separately, `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:557-562`). The provider's published rule for the one model that currently has a prompt-length premium reads: "A request's prompt length counts all of its input tokens, including cache reads and cache writes" (platform.claude.com/docs/en/about-claude/pricing, fetched 2026-10-22).
**Repro (R4):** 100K fresh + 150K cache-read on a 200K-threshold entry → `long_context_applied=False`, total 525,000 µUSD at base rates.
**Fix:** test `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`; multiply before flooring (`int(cost * m)` on already-floored per-category costs drifts up to 1 µUSD each). See also MED-003 on whether the tier should be billed at all.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

---

## Medium/Low Priority Issues

### [MED-001] Provider error-body integers become durable routing state with no plausibility floor (self-DoS)
- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (DISS-C-001)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:122` (applies `observed − 1` unconditionally); `head/.claude/adapters/cheval.py:2005` (`_obs` falls back to cheval's own estimate); `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:361` (classification by substring before any other 400 handling)
- **Issue:** `parse_context_limit` numbers from an HTTP 400/413 body are appended to `.run/ceiling-observed.json` and `observed_for` reduces to the minimum. The only validation is `> 0`; there is no floor relative to `context_window`, no cap on how far one observation may lower the bound, no expiry. The substring markers (`"context window"`, `"input length"`, `"too many tokens"`, `:157-169`) classify before the billing-class check, and a classified message without numbers still writes a row using the heuristic estimate — so the store mixes provider counts with chars/3.5 estimates.
- **Repro (R5):** one body `prompt is too long: 5 tokens > 1 maximum` → `observed_for` = 2, next call: `input_ceiling {value: 1, basis: observed}`, `[preflight] preempt ... estimated=991 ceiling=1`, **exit 7, nothing dispatched** — every later request to that model is refused until the store is hand-edited. Trust context [ASSUMPTION]: first-party API over TLS makes a hostile body unlikely; the repo's `endpoint` override and proxy support make a buggy or hostile intermediary a realistic source, and a provider message-format change is enough to misparse.
- **Fix:** ignore (and warn once on) observations outside a sane band of the entry's window (e.g. `[0.1 × context_window, context_window]`) in `input_bound`, `observed_for` and the `jq` reducer in `loa-status.sh`; skip the record when the provider gave no number; require a parsed number for the bound-lowering classes.
- **Reference:** CWE-1284 Improper Validation of Specified Quantity in Input — https://cwe.mitre.org/data/definitions/1284.html; CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [MED-002] Raw provider error text recorded under `message_redacted` and printed to stderr JSON
- **Severity:** MEDIUM (confidence: medium) — raised by both voices (DISS-001 rated it HIGH, DISS-C-002 MEDIUM); re-graded here, reasoning below
- **File:** `head/.claude/adapters/cheval.py:2022` (`"message_redacted": str(_exc)`), `:2032` (`_error_json(... f"{_exc} — not walked ...")`)
- **Issue:** `ProviderContextLimitError` carries the provider body verbatim (`f"HTTP {status} context-limit: {_msg}"`, `anthropic_adapter.py:362-365`). The new exit path stores it in `models_failed[].message_redacted` and prints it inside the stderr error JSON that orchestrators and CI capture. The MODELINV emitter redacts payload strings on write (`redact_payload_strings`), so the envelope path is covered; the stderr path is not, and the `sanitize_provider_error_message` helper the retry layer uses for `RetriesExhaustedError` is not applied here.
- **Why not HIGH:** the message class routed here (prompt-too-long / 413) does not echo request content in the first-party API; every pre-existing arm in `cmd_invoke` prints `str(_e)` the same way (`:2157`, `:2245`), so this is a pre-existing pattern extended to a new arm, not a new channel. A credential-shaped echo needs a proxy that rewrites error bodies. Severity is the log-exposure of provider/prompt-derived text; confidence that a secret reaches it is low.
- **Fix:** pass `str(_exc)` through `sanitize_provider_error_message` (or the modelinv redactor) before both the record and the print; add the redaction test the newer tree carries (`test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`).
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [MED-003] The long-context premium is billed from a tier the catalog itself marks `verified: false`, and `verified` is never read
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:282` (`_long_context_fields` ignores `verified`); `head/.claude/defaults/model-config.yaml:406` ("`reference` (verified: false) until the operator confirms it on an invoice")
- **Issue:** The 2.0× / 1.5× tier above 200K is applied to every 5-family request regardless of the `verified` flag the PR adds to say it is unconfirmed. The provider's pricing page fetched today states: "Claude 4.6 and later models (except Claude Haiku 5.5) ... include the full 1M token context window at standard pricing. (A 900k-token request is billed at the same per-token rate as a 9k-token request.)" If that is the rule in force, the ledger **over-reports** every >200K request by 2× on input and 1.5× on output, `cost-budget-enforcer` trips early on exactly the workloads the family was adopted for, and `long_context_rows` in `cost-report.sh` counts phantom premiums. Repro (R6): `_long_context_fields({... "verified": False})` returns a live tier.
- **Fix:** gate the tier on `verified: true` (or drop the block until an invoice confirms it); document the source and date of the rule beside the numbers.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-004] `record_observed` is a lockless read-modify-write
- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (review Observation 1 / DISS-C-007 in the review round)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:279`
- **Issue:** load → append → `mkstemp` + `os.replace` with no lock. Two cheval processes hitting provider limits concurrently (the dissent runs two voices in parallel; Flatline runs several) race and one row is lost — the bound tightens on the second verdict, not the first. Every other ledger in the repo takes `flock` for this reason.
- **Fix:** `fcntl.flock` on a sidecar lock file (opened `O_NOFOLLOW`) around load + write.
- **Reference:** CWE-362 Race Condition — https://cwe.mitre.org/data/definitions/362.html

### [MED-005] Flatline passes an explicit 64K `--max-tokens` to every Anthropic voice, bypassing cheval's transport-aware default
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:1030` (`args+=(--max-tokens ...)`), `:129` (`FLATLINE_VOICE_MAX_TOKENS_CAP=64000`), `:936` (`flatline_voice_max_tokens`)
- **Issue:** An explicit value skips `default_max_tokens`' transport awareness (`_hop_max_tokens` only clamps to `max_output_tokens`), so under `LOA_CHEVAL_DISABLE_STREAMING` the non-streaming call carries 64K (the 16K default existed for that path) and under `LOA_CHEVAL_LEGACY_WIRE` the 4,096 kill-switch default is bypassed. Worst-case output spend per voice call rises 4× (64K × $25/MTok = $1.60 on Opus 5 vs $0.40). `head/tests/unit/cycle-124-dispatch-budgets.bats:8` still states the rationale the tests below it now contradict.
- **Fix:** pass no `--max-tokens` for Anthropic entries whose catalog value exceeds the cap (cheval's default is already `min(64K|16K, max_output_tokens)`), or make the cap transport-aware; refresh the bats header.
- **Reference:** CWE-770 Allocation of Resources Without Limits or Throttling — https://cwe.mitre.org/data/definitions/770.html

### [MED-006] Any 429 while unverified ends the run and writes a store row, with no token-limit discriminator
- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (DISS-C-003a)
- **File:** `head/.claude/adapters/cheval.py:2297`
- **Issue:** `RateLimitError` carries no distinction between a requests-per-minute throttle and an input-tokens-per-minute one, so an ordinary RPM 429 (already backed off by the transport) on a request above the probed bound overrides the declared chain, exits `RATE_LIMITED`, and appends a `RATE_LIMIT_UNVERIFIED` row. The PR's own `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` asserts this, so it is a design decision; the newer framework tree adds `token_limited` to `RateLimitError` and a test that an RPM 429 walks, which is the better reading of D-1.1b.
- **Fix:** take the non-walk path only when the 429 body names a token-rate limit; walk otherwise.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-001] `http_get` follows redirects with the API key, accepts any scheme, reads an unbounded body
- **Severity:** LOW (confidence: medium) — Confirmed by cross-model review (DISS-C-005)
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:342` (urllib path), `:309`
- **Issue:** `urllib.request.urlopen` forwards `x-api-key` across redirects and accepts any opener scheme; `resp.read()` has no size cap. `http_post` has the same lineage (hardening gap, not a new exploit), but `health_check` now sends the live key to `GET {endpoint}/models` on every provider status run. Endpoint is operator config (trusted).
- **Fix:** disable redirects (custom opener / `httpx` `follow_redirects=False` is already the default there), enforce `https`, cap the read.
- **Reference:** CWE-918 SSRF — https://cwe.mitre.org/data/definitions/918.html; CWE-200 — https://cwe.mitre.org/data/definitions/200.html

### [LOW-002] `_mult` accepts `inf` and arbitrarily large multipliers; the ledger write then crashes after the billed call
- **Severity:** LOW (confidence: high — reproduced R6b: `OverflowError: cannot convert float infinity to integer`) — Confirmed by cross-model review (DISS-C-004)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:290`
- **Issue:** `.inf` is valid YAML; `int(cost * inf)` raises inside `create_ledger_entry`, so the row is never written and daily spend is not updated — the "malformed means no premium" promise of `_long_context_fields` is not kept.
- **Fix:** reject non-finite values and bound the multiplier (e.g. `0 < m ≤ 10`).
- **Reference:** CWE-1284 — https://cwe.mitre.org/data/definitions/1284.html

### [LOW-003] `ceiling-probe-live.py --write-catalog` rewrites the System-Zone catalog with a 0600 temp file and leaks the temp on error; its price map is a literal
- **Severity:** LOW (confidence: high)
- **File:** `head/tools/ceiling-probe-live.py:173-176` (`mkstemp` → `os.replace` with no cleanup on exception, no mode preservation), `:42` (`_PRICE_IN` hard-coded per model)
- **Issue:** `mkstemp` creates 0600; `os.replace` makes `.claude/defaults/model-config.yaml` unreadable to other users/CI after one operator run. An exception between `mkstemp` and `os.replace` leaves `.model-config.*.tmp` beside the catalog (`ceiling.py:300-305` does this correctly). The budget cap derives from a literal map although the catalog carries the prices — the sprint's own principle. `write_catalog` also leaves `probed_ceiling` stale (cosmetic once `calibrated_at` is set).
- **Fix:** `os.chmod(tmp, stat.S_IMODE(os.stat(path).st_mode))` before replace; `try/except → unlink`; read `input_per_mtok` from the catalog entry.
- **Reference:** CWE-732 Incorrect Permission Assignment — https://cwe.mitre.org/data/definitions/732.html; CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [LOW-004] `loa-status.sh` interpolates the alias target into a `yq` path expression
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/loa-status.sh:806` (`".providers.anthropic.models.\"$model\".effective_input_ceiling"`), `:804`
- **Issue:** `$model` comes from the catalog's `aliases.opus` (System Zone, trusted), but an id containing `"` or `)` would break or redirect the expression; the `jq` side correctly uses `--arg`. Observations of `0` also reach the `min` and print `observed -1` (see MED-001).
- **Fix:** pass the id with `--arg m` / `env(m)` in yq as well; filter `observed_input_tokens > 0`.
- **Reference:** CWE-94 — https://cwe.mitre.org/data/definitions/94.html

### [LOW-005] Under `LOA_CHEVAL_LEGACY_WIRE`, thinking-model entries log "temperature 0.7 dropped" on every call
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:245` (`wire_temperature(None)` returns 0.7 under the kill switch, `base.py:177`; the old `!= 0.7` guard is gone)
- **Fix:** log only when `request.temperature is not None`.
- **Reference:** CWE-779 Logging of Excessive Data — https://cwe.mitre.org/data/definitions/779.html

### [LOW-006] `"too many tokens"` marker also matches throttle text
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:159`
- **Issue:** "Too many tokens, please wait before trying again" is a throttle shape; only the `status in (400, 413)` gate (`anthropic_adapter.py:361`, `:503`) keeps it from becoming a terminal, bound-lowering `CONTEXT_TOO_LARGE`. A proxy mapping 429 → 400 crosses it.
- **Fix:** check throttle markers first, or require a parsed number for the bound-lowering classes (ties to MED-001).
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [LOW-007] `health_check` returns `False` for any non-200/non-404 answer from `GET /models`
- **Severity:** LOW (confidence: low)
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672`
- **Issue:** Proxies fronting only the Messages API commonly answer 401/403/405/501 for unknown routes; the previous one-token probe would have passed there.
- **Fix:** fall through to the tiny-model probe on 404, 405, 501 as well.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-008] Test gaps and stale test text
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/tests/test_ceiling_e2e.py:167` (count > heuristic only — misses HIGH-001); `head/.claude/adapters/tests/test_ceiling_retry.py` (no `max_retries=0` case — misses HIGH-004); `head/tests/unit/flatline-call-model-schema.bats:48` greps the removed `FLATLINE_(REVIEW|SCORE)_MAX_TOKENS` (dead); `head/tests/unit/cycle-124-dispatch-budgets.bats:8` header contradicts the tests below it
- **Fix:** add the four cases named in HIGH-001/003/004 and MED-001 (the repro file in `audits/2026-10-22/` is a starting point); drop the dead grep; refresh the header.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-009] `_multipass_is_anthropic` is a hand-maintained regex duplicating the catalog aliases
- **Severity:** LOW (confidence: low)
- **File:** `head/.claude/scripts/lib-multipass.sh:98`
- **Issue:** `opus|sonnet|haiku|fable|tiny$|cheap$` will drift from `aliases:`; `generated-model-maps.sh` already carries alias → provider.
- **Fix:** look the alias up in `MODEL_IDS` / the provider map instead.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-010] Process and documentation: title-only implementation report; no CHANGELOG touched; no documentation-coherence reports
- **Severity:** LOW (confidence: high)
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md` (= `pr/PR.md`: one title line, no AC verification, no self-check record)
- **Issue:** The PR adds a new outbound call (`count_tokens`), a new header path (`anthropic-beta`), a new health-probe route, a new state file (`.run/ceiling-observed.json`) and a tool that rewrites a System-Zone file, none of which is listed in a changelog in the diff. `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` does not exist. Manually verified instead: `head/.claude/loa/reference/multi-model-reference.md:63-88` documents the policy, the three env knobs, the beta allowlist, the probe and the envelope fields coherently with the code; `bridgebuilder-review/SKILL.md:98` documents the new default. Whether the repository keeps a CHANGELOG at all is not assessable from the PR files (scope limit).
- **Fix:** supply the AC walkthrough and self-check on resubmission; add a changelog entry naming the new network calls and state file.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

---

## Cross-Model Security Observations

Security dissent: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — type `audit`, primary `gpt-5.5-pro` (`status: reviewed`, `degraded: false`), companion `claude-headless` (`status: succeeded`, `independent: true`, `counted_as: independent_voice`), `verdict_quality: 2/2 voices succeeded, chain_health ok`; 6 findings, 0 advisory voices, `metadata.locality` absent (no `degraded_security_review`). Not a degraded review. Invocation: `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`, diff only, no `--context-file`.

| Dissent | Severity (voice) | Triage |
|---------|------------------|--------|
| DISS-001 raw provider text in calibration exit | HIGH | Folded as MED-002 (re-graded: pre-existing arm pattern, non-echoing message class, envelope path redacted; residual is stderr). Counted in the tally at MEDIUM. |
| DISS-C-001 error-body integers become durable routing state | MEDIUM | Confirmed → MED-001 (reproduced R5) |
| DISS-C-002 `message_redacted` holds unredacted text | MEDIUM | Confirmed → MED-002 |
| DISS-C-003 (a) RPM 429 ends the run (b) unverified flag not per hop | MEDIUM | (a) → MED-006; (b) confirmed → HIGH-003 (reproduced R3) |
| DISS-C-004 `_mult` accepts inf | LOW | Confirmed → LOW-002 (reproduced R6b) |
| DISS-C-005 `http_get` redirects / scheme / unbounded body | LOW | Confirmed → LOW-001 |

Both voices cite tests "at HEAD" (`test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`, `test_request_rate_429_while_unverified_walks_to_the_next_hop`, `test_unverified_status_is_per_hop_not_inherited_from_the_head`). Those tests are **not in the PR**; they exist in the newer framework tree checked out in this workspace, i.e. they are later regression tests for these defects. They corroborate the findings; they do not change what the PR ships.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the listed sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-audit.jsonl` is zero bytes; `companion_voice.rejected_sidecar` is null.

---

## Review demotions (`excluded`)

The review trailer counts `excluded: 0`; nothing to confirm. `excluded_confirmed: 0`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (sweep clean; `ANTHROPIC_API_KEY` read from env only, `tools/ceiling-probe-live.py:195`)
- [x] Input validation at the new trust boundary — partial: `beta_headers` allowlisted (fail-closed); provider error-body numbers NOT bounded (MED-001); `long_context` multipliers NOT bounded (LOW-002)
- [x] Authentication unchanged; `x-api-key` now also sent to `/v1/models` and `/messages/count_tokens` on the configured endpoint only
- [x] No SQL/XSS surface; shell: `flatline_voice_max_tokens` validates digits before `(( ))`; `loa-status.sh` yq interpolation noted (LOW-004)
- [ ] Error handling doesn't leak info — raw provider text to stderr JSON under `message_redacted` (MED-002)
- [ ] Tests cover security paths — the PR's tests pass (163/163 attributable) but miss the count-vs-heuristic walk, the final-attempt shrink, the per-hop flag and the store floor (LOW-008)

---

## Documentation Audit

No `documentation-coherence-task-*.md` / `-sprint-*.md` reports exist for this sprint. Manual verification: `multi-model-reference.md` and `bridgebuilder-review/SKILL.md` were updated and agree with the code (see LOW-010). Security-relevant changes (new outbound calls, new header, new state file, System-Zone-writing tool) have no changelog entry in the diff.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 … HIGH-005 (the review's Changes Required 1–5), each with the regression case named above.
2. Add the plausibility floor and the redaction on the calibration exit (MED-001, MED-002); decide the `verified` gate on the premium tier (MED-003); lock the store (MED-004).
3. Run `/implement sprint-1` to apply, then `/review-sprint sprint-1` and re-run `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":6,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T20:05:00Z"} -->