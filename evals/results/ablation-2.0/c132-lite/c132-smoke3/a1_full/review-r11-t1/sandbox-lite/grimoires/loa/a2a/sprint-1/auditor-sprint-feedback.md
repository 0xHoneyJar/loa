# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task brief: grimoires/loa/context/task-brief.md)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** pr/head.diff — "feat(cycle-126): full-size adapters, Bridgebuilder and Flatline — every size decision derives from the resolved catalog entry (sprint-247)", 65 files
**Review feedback consumed:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, high 3 / medium 6 / low 5, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Scope and Pre-Flight Record

- **Phase 0 deviation.** The review verdict is CHANGES_REQUIRED, not "All good". The task directive orders the audit regardless ("work autonomously; do not ask questions"), so the audit ran and this deviation is recorded here instead of stopping.
- **Guardrails:** `guardrails-orchestrator.sh --skill auditing-security` → `PROCEED` (injection check returned `ERROR`, fail-open per the include).
- **Integrity pre-check:** `integrity_enforcement` is unset in `.loa.config.yaml` (knob default `warn`); the PR touches 61 System-Zone files and does not touch `.claude/checksums.json` — noted under MED-004, not a halt.
- **Scope analysis:** `security-audit-scope.sh --json` → sources 11, sinks 410 (command_exec 218, file_operations 173), auth files 277, LLM files 274. The audit scope is the 65 files of `pr/head.diff`; every citation is `head/<path>:<line>` with lines from `pr/head/`.
- **Trust assumptions stated.** The provider HTTP response body is treated as semi-trusted (a proxy or gateway may sit in front of it); `.claude/defaults/model-config.yaml` is operator-controlled System Zone; `.run/ceiling-observed.json` is a new local trust input to the pre-flight gate; `pr/head.diff` is the only source for files outside this checkout, so claims about untouched files are flagged `[ASSUMPTION]`.
- **DEGRADED_SECURITY_REVIEW.** The security dissent (`adversarial-audit.json`) completed with `companion_voice.counted_as: sole_voice` — the primary chain `gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro` all `api_failure` (no OpenAI/Google credentials in this sandbox); `primary_voice.status: ceded` to `claude-headless`, which answered as the companion. One voice, Anthropic family only. Its findings are triaged under Cross-Model Security Observations; none change the tally.

---

## Executive Summary

The sprint moves every size decision onto the resolved catalog entry: `loa_cheval/routing/ceiling.py` turns the input bound into a named policy (I1 window fit, I2 calibrated/probed/derived/observed/guard/legacy), the Anthropic adapter types the provider's own "too large" verdict (`ProviderContextLimitError`) and allowlists `anthropic-beta` values with a pinned regex, the output default follows `max_output_tokens` for every provider, `temperature` leaves the wire unless set, the health probe loses its retired snapshot id, and the Bridgebuilder / Flatline tables are regenerated from the same yaml. The security hygiene of the new code is good: no secrets, the beta-header allowlist blocks header injection (CWE-113), `_pos_int` guards every integer read from the catalog and the store, the store writes are atomic, and malformed state fails open as documented.

Three defects block the merge, all on the D-1.1b seam where the new typed error meets the chain walk, and all confirmed independently against the head files: the retry layer's output-budget shrink spends an attempt and can fall out of the loop as a walkable `RetriesExhaustedError` (the oversized payload is re-sent to the next voice and no observation is recorded); the per-hop walk gate compares a fresh heuristic estimate against a bound fitted to the provider's count and refuses requests the pre-flight already approved; and the head entry's `unverified` flag is applied to every fallback hop, turning a transient 429 on a fallback into a terminal exit. Beyond the review's findings, the audit adds one trust-boundary defect of its own: the observed-bound store accepts whatever numbers a provider (or proxy) error message states, with no floor or cross-check against the catalog, so a single spurious or malicious 400 pins a model's bound as low as 0 until an operator recalibrates — and the recalibration command the PR prints edits a System-Zone file covered by `.claude/checksums.json`.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 5 |
| Low | 11 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Retry-layer context shrink consumes an attempt and falls through to a walkable RetriesExhaustedError

**Severity:** HIGH · **Confidence:** high · Confirmed by cross-model review (review Changes Required #1)
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:495` (arm `retry.py:472-496`; loop `retry.py:354`; post-loop raise `retry.py:530`)
**Issue:** The `except ProviderContextLimitError` arm replaces the request and `continue`s inside `for attempt in range(max_retries + 1):`:
```python
                request = replace(request, max_tokens=room)
                continue
```
On the final iteration (or with `retry.max_retries: 0`, i.e. `range(1)`) the loop ends, `last_typed_error` is still `None`, and line 530 raises a generic `RetriesExhaustedError(... last_error=sanitize_provider_error_message(None) ...)`. cheval's `RetriesExhaustedError` arm walks the chain, so the identical payload is sent to the next voice — the exact behaviour D-1.1b forbids ("the provider's own size verdict ends the call — it is never walked", `head/.claude/adapters/cheval.py:1999`) — and `_calibration_needed_exit` never runs, so no row lands in `.run/ceiling-observed.json` and no `calibration_needed` envelope is emitted.
**Impact:** Every fallback voice re-receives an oversized prompt (each one a billed provider call for Anthropic hops that bill the input before refusing), the call ends `CHAIN_EXHAUSTED` with no size message, and the self-correction loop that the whole sprint is built around records nothing. `test_ceiling_retry.py` runs with `max_retries: 3` and never exhausts; `test_ceiling_e2e.py:116` patches `invoke_with_retry` wholesale, so the seam is untested end to end.
**Fix:** Do not charge the shrink to the attempt budget (an explicit extra iteration, or `if attempt == max_retries: raise` before the `continue`), and set `last_typed_error = e` in every path so a fall-through still carries the typed cause. Add `test_ceiling_retry.py` cases with `max_retries: 0` and with the shrink arriving after prior 429s, asserting `ProviderContextLimitError` propagates.
**Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [HIGH-002] Walk gate compares the heuristic estimate against a bound fitted to the provider's count

**Severity:** HIGH · **Confidence:** high · Confirmed by cross-model review (review Changes Required #2)
**File:** `head/.claude/adapters/cheval.py:2119` (fit `cheval.py:2089-2104`; threshold `cheval.py:2112-2116`)
**Issue:** The pre-flight may replace `_walk_estimate` with the provider's count (`cheval.py:1842`). The walk loop fits the hop budget from that count (`_fit_max_tokens(... estimate=_walk_estimate ...)`), then asks `_lookup_max_input_tokens(..., max_tokens=_hop_budget)`, whose I1 clamp returns `context_window − _hop_budget` — a bound that equals the counted size after a shrink. The gate then re-estimates with the heuristic:
```python
                    from loa_cheval.providers.base import estimate_tokens
                    _estimated = estimate_tokens(messages)
```
Worked path under the default policy, verified arithmetically against `ceiling.py:136-146` and `ceiling.py:90-133`: 200K entry, `--max-tokens 128000`, count 100K, heuristic 114K → pre-flight shrinks to 86K, bound 114K (`i1`), count replaces the estimate, dispatch; walk: `_hop_budget` 128K → fit against 100K → 100K; `_lookup_max_input_tokens(max_tokens=100K)` → min(180K, 200K − 100K) = 100K; heuristic 114K > 100K → `ROUTING_MISS` for every Anthropic hop → `CHAIN_EXHAUSTED`. Any prompt whose count is below the heuristic (English prose) hits this whenever the count is near the window.
**Impact:** A request the pre-flight and the provider's own count approved is refused by cheval with a routing-miss message, not a size message; under the opt-in it refuses exactly the certified-near-the-window inputs the feature exists to allow. `test_170k_on_a_200k_entry_shrinks_the_output_budget_instead_of_failing` misses it because `MagicMock().count_tokens(...)` returns a `MagicMock`, which `_pos_int` rejects, so both estimates coincide.
**Fix:** Compare `_walk_estimate` (the authoritative post-pre-flight estimate) in the walk gate instead of calling `estimate_tokens(messages)` again, or fit the gate bound from the unfitted budget. Add an e2e case whose adapter `count_tokens` returns an int below the heuristic and asserts dispatch.
**Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [HIGH-003] The head entry's `unverified` flag is applied to every fallback hop

**Severity:** HIGH · **Confidence:** medium · Confirmed by cross-model review (review Changes Required #3; dissent DISS-C-003)
**File:** `head/.claude/adapters/cheval.py:2297` (set once `cheval.py:1843`; also `cheval.py:2256`)
**Issue:** `_ceiling_unverified = _preflight_outcome.unverified` is computed from the head entry's `GateOutcome` and never recomputed in the `for _idx, _entry in enumerate(_chain.entries)` loop, yet both D-1.1b arms consult it per hop:
```python
            except RateLimitError as _e:
                if _ceiling_unverified:
                    ...
                    return _calibration_needed_exit(
                        _entry, _entry_target, _e, error_class="RATE_LIMIT_UNVERIFIED",
```
After a walkable head failure (503, timeout), a plain 429 on a fallback hop — possibly calibrated, possibly another provider — ends the invocation `RATE_LIMITED` and appends a `RATE_LIMIT_UNVERIFIED` row for the fallback model. The adapter raises a bare `RateLimitError(self.provider)` for any 429, so the arm cannot tell a token-per-minute limit from a request-rate limit either. The `ProviderContextLimitError` arm at line 2256 inherits the same flag and labels a verdict on a calibrated fallback `CEILING_UNVERIFIED_LIMIT`.
**Impact:** The fallback chain exists to absorb a 429; under the opt-in it now terminates on the first fallback 429, and the operator is told to recalibrate a model that never ran above its probed bound. `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` covers the head hop only.
**Fix:** Compute the flag per hop (true only for `_idx == 0`, or by comparing `_walk_estimate` against the hop entry's own `input_bound(...).probed`) and use that per-hop value in both arms. Add an e2e case: head 503 → fallback 429 → the walk continues and no calibration row is written.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

---

## Medium/Low Priority Issues

### [MED-001] Observed-bound store accepts unvalidated provider numbers — one spurious 400 pins a model until recalibration

- **Severity:** MEDIUM · **Confidence:** high (mechanism) / medium (trigger) · Confirmed by cross-model review (DISS-C-002); absorbs review Observation #1
- **File:** `head/.claude/adapters/cheval.py:2005`, `head/.claude/adapters/loa_cheval/routing/ceiling.py:122`, `head/.claude/adapters/loa_cheval/routing/ceiling.py:157-169`
- **Issue:** `_calibration_needed_exit` writes whatever the provider message stated, or the heuristic when it stated nothing:
  ```python
          _obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)
  ```
  `record_observed` stores it, `observed_for` reduces to the smallest value, and `input_bound` applies `observed − 1` with no floor and no comparison to `probed_ceiling` / `context_window` (`ceiling.py:122-123`). The trigger is any 400/413 whose body matches a marker in `_CONTEXT_LIMIT_MARKERS` — including the broad `"context window"`, `"context length"`, `"input length"` (`ceiling.py:163-166`) — or a 413 from a proxy's body-size limit. A body such as `prompt is too long: 1 tokens > 1 maximum` (a hostile or buggy gateway, a TLS-terminating corporate proxy, or a local writer of `.run/ceiling-observed.json`) yields bound 0, and the e2e test `test_provider_limit_under_the_probed_bound_is_the_catalogs_error_and_still_not_walked` shows that a stated limit of 120000 silently overrides the catalog's 180000 with no sanity check. Because the error is deliberately non-walkable, the fallback chain does not help, and the store is append-only with no expiry.
- **Impact:** Persistent, self-inflicted denial of service for one model across every caller in the repo (Flatline voices, Bridgebuilder, dissent) until an operator runs the probe (which spends real money — MED-004) or edits the store. Trust boundary: the provider response body is now a write path into pre-flight policy.
- **Fix:** Lower the bound only when the provider stated `input_tokens` or `limit` AND the value is plausible (e.g. within [0.5×, 1.5×] of `_walk_estimate` and ≤ `context_window`); record the rest with a non-lowering class; treat 413 separately from the prompt-too-long 400; give observations a TTL or a `--reset-observed` operator path.
- **Reference:** CWE-1284 Improper Validation of Specified Quantity in Input — https://cwe.mitre.org/data/definitions/1284.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [MED-002] Long-context premium threshold ignores cache traffic that the multipliers are then applied to

- **Severity:** MEDIUM · **Confidence:** medium (review Observation #2)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
- **Issue:** `if threshold is not None and input_tokens > threshold:` tests uncached input only, while the block then multiplies `cr_cost` and `cw_cost` as well. The provider's published rule keys on the total prompt (uncached + cache read + cache creation), so a prompt-caching-heavy request above 200K total is billed base rate and `long_context_rows` undercounts.
- **Impact:** Ledger and invoice disagree; the budget enforcer under-sees spend on exactly the 1M-window calls this cycle enables.
- **Fix:** Compare `input_tokens + cache_read_tokens + cache_write_tokens > threshold` and say so in the `PricingEntry` comment; pin with a `test_long_context_pricing.py` case.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-003] Flatline voices get a 64K output budget against an unchanged 600 s timeout; stage routing sizes the budget from a model cheval may not pick

- **Severity:** MEDIUM · **Confidence:** medium (review Observation #4)
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:1027` (cap `flatline-orchestrator.sh:129`; routing `flatline-orchestrator.sh:1003-1012`)
- **Issue:** `per_call_max_tokens="$(flatline_voice_max_tokens "$model_override")"` runs on both argv branches; under score stage routing line 1004 omits `--model`, so the budget belongs to `model_override` while cheval's role gate picks the tier. Separately, `FLATLINE_VOICE_MAX_TOKENS_CAP=64000` lands on every Anthropic voice (the generated `MODEL_MAX_OUTPUT` carries 128000 for all eight) while the per-call timeout is unchanged, reversing the rationale the PR leaves standing in `head/tests/unit/cycle-124-dispatch-budgets.bats:5-8` ("the 600 s Flatline ... timeouts never meet a 64K generation").
- **Impact:** A runaway generation now outlives its timeout and the voice is lost after spending up to 64K output tokens per call (several dollars per voice on Opus-class pricing), multiplied by the voices and phases of a Flatline run.
- **Fix:** Skip `--max-tokens` under stage routing (let cheval's per-model default apply); lower the cap to what the review/skeptic documents need or raise the per-call timeout, and update the bats header.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [MED-004] The operator-facing calibration command edits a System-Zone file covered by the integrity manifest

- **Severity:** MEDIUM · **Confidence:** medium
- **File:** `head/tools/ceiling-probe-live.py:189` (default `_DEFAULT_CATALOG` `ceiling-probe-live.py:92-93`; write `ceiling-probe-live.py:167-176`); command surfaced at `head/.claude/adapters/loa_cheval/routing/ceiling.py:205`, `head/.claude/scripts/loa-status.sh:819`, `head/.claude/adapters/cheval.py:2029`
- **Issue:** `PROBE_COMMAND = "python3 tools/ceiling-probe-live.py --model {model} --write-catalog"` is printed on every provider verdict, in every `calibration_needed` envelope and in `/loa` output. `--write-catalog` with no path rewrites `.claude/defaults/model-config.yaml` in place — a System-Zone file that `.claude/checksums.json:665` pins by sha256. The Three-Zone rule is "Never edit `.claude/` — use `.claude/overrides/` or `.loa.config.yaml`". Following the printed remediation therefore (a) drifts the integrity manifest (a HALT for every skill under `integrity_enforcement: strict`, a warning otherwise), (b) is overwritten by the next framework mount/update, losing the measured calibration, and (c) requires `ANTHROPIC_API_KEY` and spends up to `--budget-usd 1.5` of real provider traffic as the recovery path for MED-001.
- **Impact:** Operators are steered into an integrity-drift / zone violation as the documented fix; the measurement does not survive an update.
- **Fix:** Point the write at an overlay (`.claude/overrides/` or a `.run/`-side calibration file the ceiling policy reads after the catalog), or regenerate `checksums.json` as part of `--write-catalog`; say so in `multi-model-reference.md`.
- **Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

### [MED-005] No CHANGELOG entry and no AC Verification walkthrough for a change with security-relevant surface

- **Severity:** MEDIUM · **Confidence:** high (review Observation #6)
- **File:** `head/.claude/loa/reference/multi-model-reference.md:63` (the only prose updated); `pr/PR.md`
- **Issue:** None of the 65 touched files is a CHANGELOG, and the implementation report is a two-line title with no `## AC Verification` mapping FR-1.1 … FR-1.9 to `file:line` evidence. The change adds a new header on the wire (`anthropic-beta`, `anthropic_adapter.py:300`), a new outbound request class (`count_tokens`, `anthropic_adapter.py:591`, which posts the full prompt to a second endpoint), a new local trust input to the pre-flight gate (`.run/ceiling-observed.json`), and a tool that rewrites the catalog — all security-relevant per this skill's Documentation Audit blocker list ("a CHANGELOG omitting security changes"). No `documentation-coherence-task-*.md` report exists under `grimoires/loa/a2a/subagent-reports/` (directory absent) and none was manually verified.
- **Impact:** Reviewers, the audit gate and downstream operators cannot trace the new wire/trust surface to its requirement; the integrity and zone implications of MED-004 are undocumented.
- **Fix:** Add the CHANGELOG entry (naming the beta header allowlist, the count endpoint, the observed store and the catalog writer) and an AC table with one row per FR and the test that pins it.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] `http_get` urllib fallback follows redirects and forwards `x-api-key`

- **Severity:** LOW · **Confidence:** medium · Confirmed by cross-model review (DISS-C-005)
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:342`
- **Issue:** `urllib.request.urlopen(req, ...)` follows 3xx by default and `HTTPRedirectHandler` re-sends the original headers (only `Content-*` are dropped) to the new location; the httpx branch does not follow redirects, so behaviour depends on the installed client. The URL is the operator-configured endpoint plus `/models?limit=1`, so the precondition is a redirecting proxy or compromised endpoint. Parity note: the pre-existing `http_post` at `base.py:272` has the same shape, so the exposure is not new in kind — but the health probe is now the first request made against every configured provider.
- **Fix:** Install an opener whose `redirect_request` returns `None`, or compare `resp.geturl()` host to the request host and treat a mismatch as `503`.
- **Reference:** CWE-200 Exposure of Sensitive Information — https://cwe.mitre.org/data/definitions/200.html

### [LOW-002] Beta-header allowlist regex `$` admits a trailing newline

- **Severity:** LOW · **Confidence:** high · Confirmed by cross-model review (DISS-C-004)
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82`
- **Issue:** `re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$")` with `.match` accepts `"context-1m-2025-08-07\n"` (`$` matches before a trailing newline). http.client and httpx both reject a header value containing `\n`, so this is not exploitable for header injection today; the allowlist is simply weaker than the comment at `anthropic_adapter.py:77-81` documents and relies on the transport.
- **Fix:** Use `\Z` or `re.fullmatch`.
- **Reference:** CWE-113 Improper Neutralization of CRLF Sequences in HTTP Headers — https://cwe.mitre.org/data/definitions/113.html

### [LOW-003] `_mult` accepts `inf` / `1e400` multipliers → `OverflowError` at ledger time

- **Severity:** LOW · **Confidence:** medium · Confirmed by cross-model review (DISS-C-006)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:292-295`
- **Issue:** `m = float(value)` … `return m if m > 0 else 1.0` accepts YAML `.inf` or `"1e400"`; `int(inp_cost * im)` at `pricing.py:171` then raises `OverflowError` inside `create_ledger_entry`, after the billed call completed. `[ASSUMPTION]` whether cheval wraps the ledger write is not visible in the diff; the catalog is operator-controlled, so this is a robustness, not an attack, finding.
- **Fix:** Reject non-finite values (`math.isfinite`) and cap the multiplier (e.g. ≤ 10).
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-004] Observed store is read-modify-write without a lock and grows without bound

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:279-299`
- **Issue:** `record_observed` loads the file, appends, and `os.replace`s a temp — atomic per writer but not serialized across writers. Flatline dispatches voices in parallel; two concurrent provider verdicts lose one row (the losing writer's observation vanishes, so its bound is not lowered). The store is append-only "history" with no cap or compaction, and `load_observed` silently discards a malformed file (so a corrupted store loses all history on the next write).
- **Fix:** `fcntl.flock` around load→write (the repo already has a lock helper for the trajectory logs), and cap or compact rows per (provider, model).
- **Reference:** CWE-362 Concurrent Execution using Shared Resource with Improper Synchronization — https://cwe.mitre.org/data/definitions/362.html ; CWE-770 — https://cwe.mitre.org/data/definitions/770.html

### [LOW-005] Unreachable branch in `fit_max_tokens`

- **Severity:** LOW · **Confidence:** high (review minor #1)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:144`
- **Issue:** `if 0 < requested < FLOOR_MAX_TOKENS and room >= requested:` — `room >= requested` ⇔ `estimate + requested <= context_window`, which the first branch (line 139) already returned on. Dead code; −2 lines.
- **Reference:** CWE-561 Dead Code — https://cwe.mitre.org/data/definitions/561.html

### [LOW-006] I1 fit is not re-run after the count replaces the estimate

- **Severity:** LOW · **Confidence:** medium (review minor #2)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:410-414`
- **Issue:** The fit at line 387 uses the heuristic; after `counted` replaces it (line 412) `counted + max_tokens` may exceed `context_window` by the heuristic's error, so the provider 400s and the retry shrink (HIGH-001) pays for it.
- **Fix:** Re-run `fit_max_tokens` with the counted estimate before the comparison.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [LOW-007] `/loa` ceiling jq discards every observation when one row has a null `observed_input_tokens`

- **Severity:** LOW · **Confidence:** medium (review minor #3)
- **File:** `head/.claude/scripts/loa-status.sh:813`
- **Issue:** `[.observed_input_tokens, (if .provider_limit then .provider_limit + 1 else empty end)] | min` yields `null` for a null field; the outer `min` then returns `null` for the model and the status line reports `probed` while cheval (whose `observed_for` skips nulls via `_pos_int`) enforces `observed`. The two consumers disagree on the same store.
- **Fix:** `select(. != null)` before both `min`s.
- **Reference:** CWE-697 — https://cwe.mitre.org/data/definitions/697.html

### [LOW-008] Multipass estimator is ceil(chars/3.5) while cheval's is floor; the comment claims parity

- **Severity:** LOW · **Confidence:** high (review minor #4)
- **File:** `head/.claude/scripts/lib-multipass.sh:106`
- **Issue:** `echo $(( (char_count * 2 + 6) / 7 ))` is a ceiling; `estimate_tokens` is `int(len / 3.5)` (floor). Off-by-one at chunk boundaries contradicts "the same `chars / 3.5` bound cheval applies" (line 96).
- **Fix:** `$(( char_count * 2 / 7 ))` or fix the comment.

### [LOW-009] Catalog/store temp files keep 0600 and the probe's temp is not unlinked on failure

- **Severity:** LOW · **Confidence:** medium (review minor #5)
- **File:** `head/tools/ceiling-probe-live.py:173-176`; `head/.claude/adapters/loa_cheval/routing/ceiling.py:294`
- **Issue:** `tempfile.mkstemp` creates 0600; `os.replace` gives the group-readable shipped catalog (and the store) that mode. A failed `fh.write` in the probe leaves `.model-config.*.tmp` beside the catalog (the store path at `ceiling.py:300-305` does unlink).
- **Fix:** `os.chmod(tmp, os.stat(path).st_mode & 0o777)` before replace; wrap the probe write in the same try/unlink.
- **Reference:** CWE-732 Incorrect Permission Assignment — https://cwe.mitre.org/data/definitions/732.html ; CWE-404 — https://cwe.mitre.org/data/definitions/404.html

### [LOW-010] `MODEL_MAX_OUTPUT` generator interpolates the catalog key unescaped into bash

- **Severity:** LOW · **Confidence:** high · Confirmed by cross-model review (DISS-C-007)
- **File:** `head/.claude/scripts/gen-adapter-maps.sh:261`
- **Issue:** `"    [\"\($m.key)\"]=\"\($m.value.max_output_tokens)\""` emits the yaml model key verbatim into a `declare -A` literal that `flatline-orchestrator.sh` sources. The value is type-checked (`type == "number"`), the key is not. This follows the pre-existing pattern of every other map in the file (lines 165, 189, 225, 242), so the exposure is not new, but the generator gains one more unescaped sink; the catalog is System Zone, so the trust assumption is "operator-controlled".
- **Fix:** Validate keys against `^[A-Za-z0-9._:-]+$` once at the top of the generator and `error(...)` otherwise, as the `dispatch_group` branch already does for values.
- **Reference:** CWE-78 OS Command Injection — https://cwe.mitre.org/data/definitions/78.html

### [LOW-011] Bridgebuilder `maxInputTokens: 200_000` exceeds every generated Anthropic `maxInput`

- **Severity:** LOW · **Confidence:** low (review Observation #3, re-rated)
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:176` (default `model: "opus"` at line 172)
- **Issue:** `maxInputTokens: 200_000` while `truncation.generated.ts` carries `maxInput: 160000` for every Anthropic row (ceiling − 20K headroom). The review's alias concern (`model: "opus"` not keyed in the generated tables) is weakened by this checkout's `truncation.ts:693-694`, where `getTokenBudget` resolves through `GENERATED_MODEL_ALIASES` first — `[ASSUMPTION]` the PR head's `truncation.ts` (outside the diff) matches. The mismatch between the config default and the generated budget remains.
- **Fix:** Derive the default from the generated row for the resolved alias, or add a config test that `maxInputTokens ≤ getTokenBudget(DEFAULTS.model).maxInput`.

---

## Observations (not tallied)

- **Review Observation #5 (temperature default reaches adapters outside the diff) — not reproduced.** In this checkout, `grep request\.temperature` over `loa_cheval/providers` finds only the cursor headless adapter's docstring, which states the field is ignored; the four adapters in the diff all route through `wire_temperature`. `[ASSUMPTION]` the PR head tree matches this checkout for the untouched adapters (`.claude/` here differs from `pr/base/` in version, so this is not confirmed). Not counted.
- **`count_tokens` posts the full prompt to a second endpoint** (`anthropic_adapter.py:591-619`) using the same headers and beta flags. Same host, same key, same payload — no new trust boundary, but it is a new outbound request class that the CHANGELOG (MED-005) should name, and it runs before the gate approves the payload, so an oversized prompt is sent once more than before (the count endpoint is free of token charges).
- **`estimate_input` non-ASCII share** (`base.py:995`) iterates bytes in a Python generator; ~0.3 s on a 1M-token prompt. Acceptable; `raw.count` arithmetic would be O(n) in C.
- **`_messages_text_and_tools`** (`base.py:960-980`) counts only text blocks; image/document blocks contribute 0 tokens to the estimate and no `high` uncertainty, so a media-heavy prompt is systematically underestimated and lands on the provider's verdict, i.e. the retry-shrink seam described in the first blocking finding above.

---

## Cross-Model Security Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `status: reviewed`, `final_model: claude-headless`, `companion_voice.counted_as: sole_voice` (primary `gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro` all `api_failure`; `primary_voice.status: ceded`), `hallucination_filter.downgraded: 0`, `rejected_count: 0`. **DEGRADED_SECURITY_REVIEW** (one voice, one family). Seven findings, none CRITICAL/HIGH, so none enters the tally as the dissenter's own; each was checked against the head files:

| Dissent id | Severity | Claim | Triage |
|---|---|---|---|
| DISS-C-001 | MEDIUM | `_calibration_needed_exit` stores `str(_exc)` as `message_redacted` and prints it via `_error_json` | Not a new defect: identical to every pre-existing `models_failed` arm (e.g. `cheval.py:2244-2246`) and the MODELINV layer redacts at emit (`redact_payload_strings`, which `test_ceiling_e2e.py:118` patches to identity). Noted; not counted. |
| DISS-C-002 | MEDIUM | Store populated from unvalidated provider numbers → persistent self-DoS | **Confirmed by cross-model review** — counted as MED-001 (audit's own finding, independently reached). |
| DISS-C-003 | LOW | `_ceiling_unverified` head-only, 429 class not distinguished | **Confirmed by cross-model review** — counted as HIGH-003 (the audit rates the chain-contract break higher than the dissenter did). |
| DISS-C-004 | LOW | `$` in `_BETA_HEADER_RE` admits a trailing newline | Confirmed — LOW-002. |
| DISS-C-005 | LOW | `http_get` urllib follows redirects with `x-api-key` | Confirmed — LOW-001 (parity with `http_post`). |
| DISS-C-006 | LOW | `_mult` accepts `inf` → `OverflowError` at ledger time | Confirmed — LOW-003. |
| DISS-C-007 | LOW | `MODEL_MAX_OUTPUT` key unescaped in generated bash | Confirmed — LOW-010 (pre-existing pattern). |

Review demotions to confirm: the review trailer's `excluded` is 0, so `excluded_confirmed` is 0.

---

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` file exists beside the envelope.

---

## Rubric Scores

| Dimension | Score (1–5) | Justification |
|---|---|---|
| Security | 3 | No secrets, pinned allowlist, guarded integer reads, atomic writes; but a provider-controlled write path into gate policy with no plausibility check (MED-001), a redirect-forwarded key in the new probe (LOW-001), and the three D-1.1b seams that re-send oversized payloads or terminate the chain. |
| Architecture | 3 | The policy module is clean and every basis is named; per-hop state (`_ceiling_unverified`, `_walk_estimate`, the re-estimate) is computed once for the head and reused, which is the root of all three highs. The documented remediation writes into the System Zone (MED-004). |
| Code Quality | 4 | 18 policy unit tests, byte-consistent generated artefacts, kill switches pinned; `cmd_invoke` grows ~170 lines inside an already very long function; one unreachable branch. |
| DevOps | 3 | Health probe fixed, generated maps regenerated, manifest consistent; but the Flatline budget/timeout inversion (MED-003), no CHANGELOG, no AC walkthrough, no docs-coherence report (MED-005). |
| Blockchain/Crypto | N/A | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the probe reads `ANTHROPIC_API_KEY` from env; `_tiny_model_id` removes the retired literal)
- [x] Input validation on all new endpoints — beta headers allowlisted (`anthropic_adapter.py:82`, LOW-002 tightens it); `_pos_int` on every catalog/store integer
- [ ] Input validation on the new trust input — `.run/ceiling-observed.json` and the provider message numbers are consumed without plausibility checks (MED-001)
- [x] Authentication required where needed — `count_tokens`, `health_check` reuse `_headers()`; the key is never logged
- [ ] Credential never leaves the configured host — urllib redirect path forwards `x-api-key` (LOW-001, pre-existing pattern)
- [x] No SQL/XSS injection (n/a); generated-bash sink inherits the existing pattern (LOW-010)
- [x] Error handling doesn't leak info beyond the pre-existing pattern (MODELINV redaction at emit)
- [ ] Tests cover security paths — the three D-1.1b seams are untested end to end (`invoke_with_retry` patched wholesale; `MagicMock().count_tokens` never returns an int)
- [ ] CHANGELOG / documentation for security-relevant changes (MED-005)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 5 |
| Low | 11 |

Excluded (speculative, low-confidence high/critical): 0. Review demotions confirmed (`excluded_confirmed`): 0.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001, HIGH-002 and HIGH-003 (retry shrink outside the attempt budget with the typed cause preserved; walk gate on `_walk_estimate`; per-hop `unverified`) and add the three e2e cases named above with a real `count_tokens` int and an unpatched `invoke_with_retry`.
2. Add a plausibility floor before any observation lowers a bound (MED-001) and move the calibration write out of the System Zone or regenerate the checksum (MED-004).
3. Fix the long-context threshold (MED-002), the Flatline budget/timeout inversion (MED-003), and add the CHANGELOG entry plus the AC Verification table (MED-005).
4. Address the LOW items opportunistically; LOW-002, LOW-004 and LOW-007 are one-line fixes.
5. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again; re-run the dissent on a host with a second provider family so the security review is not degraded.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:05:00Z"} -->
