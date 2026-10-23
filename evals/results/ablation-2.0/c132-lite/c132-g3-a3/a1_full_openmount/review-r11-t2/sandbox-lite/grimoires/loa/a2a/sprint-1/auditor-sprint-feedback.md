# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` (cycle-126 sprint-247, "full-size adapters, Bridgebuilder and Flatline — every size decision derives from the resolved catalog entry"; 65 files)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change moves cheval's input bound from a catalog literal to a policy (`loa_cheval/routing/ceiling.py`), adds a provider
context-limit error class that is meant never to be walked, an observed-bound store under `.run/`, a live calibration tool
that writes the catalog, a beta-header allowlist, a models-endpoint health probe, a long-context pricing tier, and
catalog-derived output budgets for Flatline and Bridgebuilder. The security posture of the new surface is reasonable:
the `anthropic-beta` header is allowlisted (CWE-113 prevented), the count endpoint reuses the adapter's own headers and
sends exactly the prompt the request would send, no new credential path or dependency is introduced, the catalog write
is operator-initiated and refuses a partial bisection, and the envelope's `message_redacted` fields still pass through
the emit-time redactor.

Three HIGH defects block the merge; none is an exploitable vulnerability, all three are correctness failures in exactly
the invariants the PR is named for. (1) The per-hop input gate in `cmd_invoke` re-estimates with the raw heuristic
after the pre-flight may have replaced it with the provider's count, so a dispatch the pre-flight accepted is skipped
as `ROUTING_MISS` at every HTTP hop. (2) The retry layer's one-shot output-budget shrink falls through to a walkable
`RetriesExhaustedError` when the provider's verdict arrives on the final attempt (deterministic with
`retry.max_retries: 0` — reproduced below), which is the D-1.1b "never walked" invariant failing. (3) Bridgebuilder's
new alias defaults (`opus`, `tiny`) have no entry in the generated budget tables, so the default review runs with no
per-model input clamp. I confirmed the review's three Changes independently; the two dissent voices (Phase 1C) raised
(2) and the observed-store trust issue but not (1) or (3) — see Cross-Model Observations for why.

The security-relevant findings proper are MEDIUM/LOW: the observed-bound store turns numbers scraped from an HTTP 400/413
body into a durable bound with no plausibility check (an availability concern, CWE-20 / CWE-400, trust boundary = the
configured endpoint), the calibration command surfaced to agents performs a paid live probe and writes a System Zone
file, the `_error_json` stderr line carries the raw provider message, and `http_get` inherits `http_post`'s absence
of a scheme check. Prerequisite note: the review gate's verdict is CHANGES_REQUIRED, not "All good"; the audit was
run on explicit instruction and this report does not substitute for the review's required fixes.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 8 |
| Low | 12 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The walk-loop input gate compares the raw heuristic, not the estimate the pre-flight accepted

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/adapters/cheval.py:2118-2120` (also `:1842` where `_walk_estimate` is set, and `:2090` where the same loop's I1 fit already uses it)
**Issue:** The pre-flight gate may replace the estimate with the provider's `count_tokens` answer — `"_preflight_estimated = _preflight_outcome.estimate.tokens"` / `"_walk_estimate = _preflight_estimated"` (`cheval.py:1841-1842`). The per-hop gate then recomputes it: `"from loa_cheval.providers.base import estimate_tokens"` / `"_estimated = estimate_tokens(messages)"` / `"if _estimated > _input_threshold:"` (`cheval.py:2118-2120`). The hop bound from `_lookup_max_input_tokens` is the same policy value the pre-flight compared against (`ceiling.py:90-133`), so a prompt whose heuristic exceeds the probed bound while its count is under it passes the pre-flight (`ceiling.py:409-414`, counter runs at ≥ 0.9 × bound) and is skipped as `ROUTING_MISS` on every HTTP hop; the call lands on the CLI hop or exits `CHAIN_EXHAUSTED` with an envelope that says `preflight_decision: dispatch`, `estimator.method: count_tokens` next to a `ROUTING_MISS` quoting the heuristic. Two gates in one loop disagree about the same request.
**Failure scenario:** default `probed` policy, head `claude-opus-5` (probed 180,000), heuristic 190,000, count 175,000 → pre-flight dispatches; hop 1 computes 190,000 > 180,000 → skip; every fallback with the same probed value skips the same way.
**Fix:** `_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)` at `:2119`; add an e2e row (default policy, counter → 175,000, heuristic ≈ 190,000) asserting one dispatch and no `ROUTING_MISS`. The existing `test_opt_in_count_endpoint_is_authoritative` runs only under the `derived` opt-in where the bound is 936,000, so it cannot catch this.
**Reference:** CWE-670 Always-Incorrect Control Flow Implementation — https://cwe.mitre.org/data/definitions/670.html

### [HIGH-002] The retry layer's one-shot shrink is lost on the final attempt; the provider's verdict degrades to a walkable error

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:494-495` (fall-through at `:530`)
**Issue:** The context-limit arm does `"request = replace(request, max_tokens=room)"` then `"continue"` (`retry.py:494-495`) without checking that an attempt remains and without setting `last_typed_error`. When `ProviderContextLimitError` arrives on the last pass of `for attempt in range(max_retries + 1)`, the loop ends and `"raise RetriesExhaustedError("` (`retry.py:530`) fires. cheval's `except ProviderContextLimitError` (`cheval.py:2247`) never runs: the same oversized payload is walked to the next voice, no `.run/ceiling-observed.json` row is written, and the operator never sees the calibration command — the outcome D-1.1b forbids and the reference doc promises against (`head/.claude/loa/reference/multi-model-reference.md:75`: "is **never walked**").
**PoC (run on a head overlay):**
```
adapter raises ProviderContextLimitError(input_tokens=190000, limit=200000, max_tokens=64000) on every call
config {"retry": {"max_retries": 0}}:
  WARNING anthropic: provider context limit 200000 at input 190000 with max_tokens 64000 — one retry at max_tokens 10000
  -> RetriesExhaustedError: [cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: unknown
  (the shrunk 10000-token request was never sent; last_error is "unknown")
```
With the default `max_retries: 3` the same path needs three prior 429/503 backoffs on the call; `test_ceiling_retry.py` only runs with `max_retries: 3` (`:25`) and a first-attempt error.
**Fix:** Perform the shrunk retry outside the attempt budget (one extra `adapter.complete()` after the shrink), or set `last_typed_error = e` and `raise` when `attempt == max_retries`; add tests with `max_retries: 0` and with the context error on the final attempt.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-003] Bridgebuilder's alias defaults have no entry in the budget tables

**Severity:** HIGH (confidence: medium)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` and `:176`; `head/.claude/skills/bridgebuilder-review/resources/personas/quick.md:2`, `head/.claude/skills/bridgebuilder-review/resources/personas/security.md:2`
**Issue:** The built-in default becomes `"model: \"opus\""` (`config.ts:172`) with `"maxInputTokens: 200_000"` (`:176`); the personas become `tiny` and `opus`. The generated table is keyed by concrete ids only (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19` onward — no `opus`/`tiny` key) and `scripts/gen-bb-registry.ts` emits no alias map; `core/truncation.ts` is not touched by this PR. The lookup therefore falls through to `TOKEN_BUDGETS["default"]` and the input clamp is skipped for an unknown id, so a default-config review of a large PR prepares up to 200,000 tokens of diff for a model whose cheval probed bound is 180,000 and is pre-empted with CONTEXT_TOO_LARGE where the previous default (`claude-opus-4-7`, 128,000, a known id) was truncated and reviewed. The PR's own tests assert only the string (`__tests__/config.test.ts:161`). Confidence is medium because `truncation.ts` at the PR's base is not in the bundle; the workspace copy carries a `budgetId()` alias resolver annotated "cycle-126 sprint-250 round 2", i.e. a later fix for exactly this gap, which corroborates that the PR's base did a direct key lookup.
**Fix:** Keep concrete ids as the default/persona values, or have `gen-bb-registry.ts` emit the yaml `aliases:` block and resolve it in `getTokenBudget` / `effectiveInputBudget` / `isReasoningClass` (which keys `GENERATED_REASONING[modelId]` by concrete id too, `core/multi-model-pipeline.ts:61`); set the input default at or under the alias target's generated `maxInput` (160,000); add a test that `getTokenBudget("opus")` equals the target's budget.
**Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

---

## Medium/Low Priority Issues

### [MED-001] Observed-bound store accepts unvalidated numbers from a provider error body and makes them a durable bound
- **Severity:** MEDIUM (confidence: medium) — availability
- **File:** `head/.claude/adapters/cheval.py:2005-2010` (record), `head/.claude/adapters/loa_cheval/routing/ceiling.py:122-123` (lowers the bound), `:240-261` (`observed_for`), `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:361` and `:503` (classification + regex parse)
- **Issue:** `"_obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)"` (`cheval.py:2005`) is recorded with `provider_limit` as-is; `observed_for` takes `min(observed, provider_limit + 1)` and `input_bound` applies `observed − 1` to every uncalibrated request for that entry (`ceiling.py:122`). There is no floor, no relation to `context_window` or `probed_ceiling`, and no requirement that the refused request was itself above the bound. One HTTP 400/413 body of the shape `prompt is too long: 5 tokens > 4 maximum` from whatever answers the configured `endpoint` (a gateway, a misbehaving proxy) records a bound of 4, and every later call to that (provider, model) is pre-empted at the pre-flight until an operator runs the paid probe. When the body carries no numbers (a 413 `request_too_large` on request bytes, not tokens), `_obs` falls back to the text-only estimate and lowers the bound to that request's size. The store is read on every hop (`_lookup_max_input_tokens` → `_observed_for`). Trust boundary: the configured endpoint; the catalog-shipped `api.anthropic.com` is trusted, so the realistic trigger is a proxy/gateway or a false positive of the broad `_CONTEXT_LIMIT_MARKERS` (`ceiling.py:157-169`, e.g. "context window", "input length").
- **Fix:** Only lower the bound when the refused request's own estimate was at or above the recorded value; require `provider_limit >= FLOOR_MAX_TOKENS` and `<= context_window`; treat a no-numbers 413 as non-recordable; consider N consistent observations before lowering below `probed_ceiling`.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [MED-002] `_ceiling_unverified` is the head entry's flag but gates every hop, and every 429
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/adapters/cheval.py:1843`, `:2256`, `:2297`
- **Issue:** `"_ceiling_unverified = _preflight_outcome.unverified"` (`:1843`) is computed once for the head entry and consulted on every hop's `ProviderContextLimitError` arm (`:2256`) and `RateLimitError` arm (`:2297`). Under the `derived` opt-in a 429 on a fallback hop — even a calibrated one, even an ordinary requests-per-minute 429 that says nothing about the payload (`RateLimitError` carries no token-limit marker, `types.py:225-229`) — ends the call as `RATE_LIMIT_UNVERIFIED` and appends a calibration row against that fallback entry instead of walking.
- **Fix:** Recompute the unverified zone per hop (that hop's `probed` vs the estimate, and its own calibration), or clear the flag on leaving the head entry; distinguish token-limit 429 bodies from RPM ones before refusing to walk.
- **Reference:** CWE-670 — https://cwe.mitre.org/data/definitions/670.html

### [MED-003] Observed store: unlocked read-modify-write; unbounded append read on every hop
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:278-299`
- **Issue:** `load_observed` → append → `os.replace` is atomic per write but not as a sequence; Flatline runs its voices as parallel cheval processes, so two verdicts within the same window drop a row. The store is append-only with no expiry or compaction and is loaded and parsed in full on every hop and at the pre-flight. (The dissent's symlink point is not a defect: `os.replace` replaces a planted link rather than writing through it; `load_observed` only reads.)
- **Fix:** Take the per-user flock the ledger writers use around read-append-replace; cap or compact the store (keep the min per entry).
- **Reference:** CWE-362 Race Condition — https://cwe.mitre.org/data/definitions/362.html

### [MED-004] `/loa` prints `ceiling: observed -1` from a zero-token observation row
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/loa-status.sh:811-814`
- **Issue:** The jq reduction takes `min` of `observed_input_tokens` with no positivity check; cheval writes `observed_input_tokens: 0` when the message carries no numbers and the estimate is unset (`cheval.py:2005`). `obs=0` passes `"[[ \"$obs\" =~ ^[0-9]+$ ]]"` (`:814`), so the status line reads `observed -1`. The Python reducer (`ceiling.py:252`) skips non-positive values, so the two readers disagree.
- **Fix:** `select(.observed_input_tokens > 0)` in the jq, and do not append a row with a zero observation.

### [MED-005] Flatline: every call kind gets a 64K output budget on 128K entries
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:936-946`, `:1027`
- **Issue:** `flatline_voice_max_tokens` returns `min(declared, 64000)` for any mode; `score` (a small JSON array) and review/skeptic alike pass `--max-tokens 64000` for `claude-opus-5`. The cycle-124 rationale this removes ("the 600 s per-call timeout never meets a 64K-output generation") is deleted without touching the timeout, and on adaptive-thinking Opus the budget is shared with thinking: a runaway generation now runs to the timeout and drops the voice where 16K bounded it.
- **Fix:** Keep the per-voice cap but let the mode lower it (`score` has no use for 64K), or document the timeout interaction.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [MED-006] Health probe: any non-404 on `/models` is now "unhealthy"
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672`
- **Issue:** `"if status != 404: return False"`. A gateway that does not serve `GET /v1/models` and answers 403/405/501, or a transport 503/504 envelope from `http_get`, is reported unhealthy without the one-token message fallback, so the breaker/status surfaces a false negative for proxied endpoints.
- **Fix:** Fall back to the message probe on any non-2xx other than an authentication error.

### [MED-007] Long-context threshold ignores cache tokens
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
- **Issue:** `"if threshold is not None and input_tokens > threshold:"` tests uncached input only, then multiplies `cr_cost`/`cw_cost` by the input multiplier (it knows cache traffic is input-side). A request of 1,000 uncached + 250,000 cache-read tokens is billed at the base tier and `long_context` is not set on the ledger row, so `cost-report.sh` undercounts exactly the cache-heavy workloads most likely to exceed 200K. Confidence medium because the catalog marks the tier `verified: false`.
- **Fix:** Test `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`; pin in `test_long_context_pricing.py`.

### [MED-008] The surfaced calibration command performs a paid live probe and writes the System Zone
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:205`, `head/.claude/adapters/cheval.py:2016`, `:2032`, `head/tools/ceiling-probe-live.py:189`, `:92-93`
- **Issue:** `"PROBE_COMMAND = \"python3 tools/ceiling-probe-live.py --model {model} --write-catalog\""` is printed on stderr, in the `_error_json` line and in the envelope on every provider verdict. `--write-catalog` defaults to `.claude/defaults/model-config.yaml` (`ceiling-probe-live.py:92-93`, `:189`), a System Zone file agents must never edit, and the run spends up to `--budget-usd 1.5` by default on a real account. The strings carry no "operator only" marker, so an autonomous agent that follows cheval's stderr in run mode will execute a paid probe and a System Zone write, which `integrity_enforcement` may then flag as drift. The tool itself is sound (refuses a partial bisection without `--allow-partial`, validates `--tier`, never guesses a block).
- **Fix:** Mark the surfaced command operator-only (or surface the dry `--output` form and let the operator add `--write-catalog`); document the System Zone write in the zone rules or route it through an override path.
- **Reference:** OWASP ASI (Agentic) excessive agency class; CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html

### [LOW-001] Raw provider message on the stderr error line
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/cheval.py:2022`, `:2032`
- **Issue:** `"\"message_redacted\": str(_exc)"` (`:2022`) and the stderr `_error_json` text `"f\"{_exc} — not walked: ...\""` (`:2032`) carry the provider body verbatim. The envelope field is redacted at emit (`loa_cheval/audit/modelinv.py:213-223` lists `message_redacted` among `_REDACT_FIELDS`), so the exposure is the stderr line only, which the orchestrators capture into trajectory logs. Both dissent voices rated this MEDIUM (DISS-001, DISS-C-002); I rate it LOW because the Anthropic context-limit body is a fixed-shape message with numbers and the pattern matches every existing arm — only the catch-all arm (`:2404-2413`) redacts at the write site. Also the `_calib` dict embeds the absolute store path (`:2016`).
- **Fix:** Route the stderr message through the shared redactor (as the catch-all arm does) and record the store path relative to the project root.
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [LOW-002] Beta-header allowlist regex anchors with `$`, which admits a trailing newline
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82`, `:174`
- **Issue:** `"_BETA_HEADER_RE = re.compile(r\"^[a-z0-9]+(-[a-z0-9]+)*-\\d{4}-\\d{2}-\\d{2}$\")"` with `re.match` accepts `"context-1m-2025-08-07\n"` (verified: `match` → True, `fullmatch` → False). A YAML block scalar in `params.beta_headers` would pass the allowlist and reach `headers["anthropic-beta"]`; Python's `http.client` then rejects the value (`ValueError: Invalid header value`, verified), so the result is an untyped crash rather than header injection — but the allowlist does not do what its comment says.
- **Fix:** Use `fullmatch` (or `\Z`).
- **Reference:** CWE-113 HTTP Response/Request Splitting — https://cwe.mitre.org/data/definitions/113.html (near-miss)

### [LOW-003] Long-context multipliers accept `inf` and values below 1.0
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:290-295`
- **Issue:** `"return m if m > 0 else 1.0"` admits `.inf`/`1e400` (verified: `_mult(inf) → inf`; `int(cost * inf)` raises `OverflowError` after the call was billed, dropping the ledger row) and multipliers under 1.0 (silent under-billing). Catalog is operator-controlled, so this is a typo-hardening item (dissent DISS-C-005).
- **Fix:** Require `math.isfinite(m) and m >= 1.0`; otherwise log and fall back to no premium.

### [LOW-004] `http_get` sends the API key to any configured endpoint with no scheme check or body cap
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:309-355`, `:342`
- **Issue:** `"with urllib.request.urlopen(req, timeout=connect_timeout + read_timeout) as resp:"` takes the catalog `endpoint` verbatim; urllib honours `file://`/`ftp://`, and `resp.read()` is unbounded. Same posture as the existing `http_post` (no scheme check there either), so hardening, not a new exposure (dissent DISS-C-006).
- **Fix:** Assert `https` (http only for explicit localhost) in one shared place; cap the probe body.
- **Reference:** CWE-918 Server-Side Request Forgery — https://cwe.mitre.org/data/definitions/918.html

### [LOW-005] Atomic writes leave the catalog and the store with mode 0600
- **Severity:** LOW (confidence: high)
- **File:** `head/tools/ceiling-probe-live.py:173-176`, `head/.claude/adapters/loa_cheval/routing/ceiling.py:294-299`
- **Issue:** `tempfile.mkstemp` creates 0600 and `os.replace` keeps that mode, so `model-config.yaml` (normally 0644, read by `yq` in `loa-status.sh` and by the Bridgebuilder generator) and `.run/ceiling-observed.json` lose group/world read after the first write. Harmless on single-user hosts; breaks shared mounts and CI readers running as another user.
- **Fix:** `os.chmod(tmp, stat of the original or 0o644)` before `os.replace`.
- **Reference:** CWE-732 Incorrect Permission Assignment — https://cwe.mitre.org/data/definitions/732.html

### [LOW-006] Observations never expire and the store has no reset path
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:240-261`
- **Issue:** `observed_for` ignores `ts`; a bound lowered once (e.g. a 200K limit while an account lacked the 1M beta) persists after the account changes until the operator runs the paid probe or hand-deletes the file; no `--reset` exists and `/loa` names only the probe.
- **Fix:** Age out rows (the catalog already has `stale_after_days`) or add a reset verb.

### [LOW-007] Estimator parity comment does not hold on hosts with tiktoken
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/scripts/lib-multipass.sh:94-95`
- **Issue:** The comment says the Anthropic pass uses "the same `chars / 3.5` bound cheval applies", but `estimate_tokens` prefers cl100k when tiktoken is installed and `estimate_input` labels it `method: tiktoken` (`head/.claude/adapters/loa_cheval/providers/base.py:988-1002`); the two estimators diverge on exactly those hosts.
- **Fix:** Make `estimate_tokens` provider-aware or correct the comment.

### [LOW-008] Dead branch in `fit_max_tokens`
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:144-145`
- **Issue:** `room >= requested` ⇔ `estimate + requested <= context_window`, which the first branch (`:139`) already returned on; unreachable. SIMPLICITY[delete].

### [LOW-009] Long-context tier declared only on the 5-family
- **Severity:** LOW (confidence: low)
- **File:** `head/.claude/defaults/model-config.yaml:541` (claude-opus-4-8, 1M window), `:744` (claude-sonnet-4-6, 1M window); locked in by `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:320`
- **Issue:** If the published premium applies to these 1M-window ids too, >200K requests are under-billed by 2×.
- **Fix:** State applicability in the yaml comment or add the block.

### [LOW-010] Test hygiene
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:66-69`; `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:295-296`
- **Issue:** A `… if False else …` expression leaves the first `write_catalog` call dead inside a `pytest.raises`; the `assert A == … or derived.basis in ("calibrated", "i1")` is near-tautological for the shipped entries and does not pin the derived value.

### [LOW-011] `cmd_invoke` complexity
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/cheval.py:1805-1862`, `:1994-2037`
- **Issue:** ~250 new lines in one function (nested closure with `nonlocal`, a 60-line pre-flight branch). SIMPLICITY[shrink]: extract the pre-flight gate into a helper returning `(decision, outcome)`. The policy module itself is lean.

### [LOW-012] Implementation report and documentation-coherence evidence missing
- **Severity:** LOW (confidence: high) — process
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md` (= `pr/PR.md`)
- **Issue:** The report is the PR title plus "65 file(s) in scope": no AC verification, no test or fast-gate output, and no `documentation-coherence-task-*.md` report exists (`grimoires/loa/a2a/subagent-reports/` is absent). Manually verified instead: `multi-model-reference.md:63-88` and `bridgebuilder-review/SKILL.md:98` describe the new behaviour accurately except for the "never walked" promise that HIGH-002 breaks; the security-relevant additions (beta allowlist, count endpoint, catalog write) are commented at the code; no secrets or internal URLs in docs.

---

## Exclusions and Scope Notes

Nothing excluded: no high-severity finding was demoted as speculative/low-confidence (`excluded: 0`). The review trailer's `excluded` is 0 and I confirm that count (`excluded_confirmed: 0`).

- [ASSUMPTION] Trust context: cheval runs on an operator's host against the configured provider endpoint; `.run/` and `.claude/defaults/` are writable by the same user. `.reviewignore` is absent in this workspace, so the whole PR surface was in scope.
- The workspace tree is a later revision than `pr/head` (its `cheval.py` already carries a per-hop `token_limited` 429 check and its `truncation.ts` an alias resolver). Only the `pr/head` files were audited; the tree was used solely to assemble a runnable overlay.
- Unable to assess: `core/truncation.ts` at the PR's base (not in the bundle — hence the medium confidence on the Bridgebuilder alias finding); the Bridgebuilder `dist/` build (no node toolchain here; the review checked the generated tables against the yaml).

---

## Cross-Model Observations

Phase 1C ran `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`: primary
`gpt-5.5-pro` (status `reviewed`, answered by `codex-headless`), companion `claude-headless` (`succeeded`,
`counted_as: independent_voice`); `degraded: false`, `verdict_quality.consensus_outcome: consensus`, 2/2 voices. Seven
findings (2 MEDIUM primary/companion, 1 MEDIUM, 4 LOW). Not a degraded security review. Disposition:

- DISS-001 (gpt-5.5-pro) / DISS-C-002 (claude-headless), raw provider text in `message_redacted` and stderr → LOW-001 (downgraded; envelope field is redacted at emit, stderr only).
- DISS-C-001, unvalidated numbers become a durable bound; store path guards → MED-001 (accepted) and MED-003 (symlink part rejected on the merits: `os.replace` does not write through a link).
- DISS-C-003, `_ceiling_unverified` head-only and every 429 → MED-002 (accepted).
- DISS-C-004, retry shrink lost on the final attempt → HIGH-002 (upgraded: reproduced deterministically with `max_retries: 0`; it is the D-1.1b invariant).
- DISS-C-005, `inf`/sub-1.0 multipliers → LOW-003. DISS-C-006, `http_get` scheme/body → LOW-004.
- Caution on the companion's evidence: it cites tests `test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`, `test_unverified_status_is_per_hop_not_inherited_from_the_head` and a `token_limited` attribute as "disagreeing with the code". None of these exists in `pr/head` (grep over `pr/head/.claude/adapters/`); they exist only in the later workspace tree. The code-level observations stand on my own reading; the test-disagreement claims were discarded.
- Neither voice raised HIGH-001 (the hop gate heuristic) or HIGH-003 (alias budgets); both stand on the review's and my independent reading.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-audit.jsonl` holds no rows (companion sidecar: null).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the retired snapshot id is gone from the probe; `_PRICE_IN` in the tool is a price table, not a credential; the store holds counts only)
- [x] Input validation on all new entry points — beta-header allowlist is anchored (`fullmatch` gap: LOW-002); `_long_context_fields` rejects malformed blocks (`inf` gap: LOW-003); env knobs parsed defensively; provider error numbers NOT validated before becoming a bound (MED-001)
- [x] Authentication required where needed — `count_tokens` and `health_check` reuse the adapter's own headers; no new credential path
- [x] No SQL/XSS injection vulnerabilities (n/a); no shell interpolation of untrusted data (bash assoc-array keys are not arithmetic-evaluated; yq query interpolates the catalog's own alias)
- [ ] Error handling doesn't leak info — the stderr `_error_json` line carries the raw provider message and an absolute path (LOW-001)
- [ ] Tests cover security paths — the no-numbers 413 path, the zero-retry shrink path, the alias budget lookup and the default-policy count rescue are untested (HIGH-001/002/003, MED-001)

---

## Rubric Scores

| Dimension | Score | Justification |
|-----------|-------|---------------|
| SEC-IV Input Validation | 3 | Allowlists where present; provider-body numbers unvalidated (MED-001), `$` anchor (LOW-002), `inf` (LOW-003) |
| SEC-AZ Authorization | 4 | No new credential path; surfaced System Zone write for agents (MED-008) |
| SEC-CI Confidentiality/Integrity | 4 | Emit-time redaction intact; stderr raw (LOW-001); 0600 modes (LOW-005) |
| SEC-IN Injection Prevention | 5 | Header allowlist; no shell/yq injection from untrusted data |
| SEC-AV Availability/Resilience | 2 | Durable per-entry DoS from one error body (MED-001); verdict walked on final attempt (HIGH-002); fallback hops refused (MED-002) |
| ARCH-MO / ARCH-CX | 4 / 3 | `ceiling.py` is a clean pure module; `cmd_invoke` grows by ~250 lines (LOW-011) |
| CQ (readability/tests) | 3 | Well-commented; the three HIGH paths have no test; two dead/tautological test spots (LOW-010) |
| DevOps | 3 | Generated maps/tables regenerated and consistent; no fast-gate evidence in the report; catalog mode change (LOW-005) |
| Blockchain/Crypto | n/a | |

---

## Verification performed

- Head overlay (65 head files over the workspace adapters tree with the tree's superset `types.py` and `scripts/lib`): `pytest` on `test_ceiling_policy.py test_ceiling_retry.py test_ceiling_e2e.py test_ceiling_probe_write_catalog.py test_long_context_pricing.py test_count_tokens_fallback.py test_full_size_adapter_defaults.py test_anthropic_catalog_floor.py` → 88 passed, 2 failed; both failures (`test_advisor_loader_resolves_the_review_role_to_opus_5`, `test_advisor_tier_points_at_opus_5`) are pre-existing tests reading the live `.loa.config.yaml`, absent from the overlay — not PR defects.
- HIGH-002 reproduced on the overlay (PoC above). LOW-002 and LOW-003 verified with `python3 -I` one-liners (regex `match` vs `fullmatch`; `_mult(inf)`; `http.client` rejects the newline).
- `security-audit-scope.sh --json` over `pr/head`: 0 web sources, 26 sinks (14 command-exec, 11 file-op, 1 query), 24 auth-touching files, 23 LLM files. Working file: `grimoires/loa/a2a/audits/2026-10-23/SECURITY_ANALYSIS_TODO.md`; structured findings: `grimoires/loa/a2a/audits/2026-10-23/findings.jsonl`.
- Beads: `br` is not installed in this workspace; the beads workflow was skipped.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (`cheval.py:2119` reads `_walk_estimate`), HIGH-002 (shrunk retry outside the attempt budget or typed re-raise on the last attempt), HIGH-003 (concrete default ids or an alias map in the budget lookup); add the four missing tests named above.
2. Address MED-001/MED-002/MED-003 while in the same files (validate before recording; per-hop unverified; flock the store).
3. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with `## AC Verification` and fast-gate evidence; re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":8,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T04:12:00Z"} -->
