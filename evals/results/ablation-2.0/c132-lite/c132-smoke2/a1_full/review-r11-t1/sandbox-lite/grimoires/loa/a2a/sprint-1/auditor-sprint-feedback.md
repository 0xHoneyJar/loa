# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries the PR title only; `pr/PR.md` is the report per sprint.md)
**Review Gate:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — CHANGES_REQUIRED (high 3, medium 5, low 10, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

Scope: `pr/head.diff` (cycle-126 sprint-247, 65 files) — the `routing/ceiling.py` input-bound policy, the non-walkable `ProviderContextLimitError` with its observed-bound store and `--write-catalog` probe writer, catalog-driven output defaults and wire temperature for every adapter, Anthropic `beta_headers` / `count_tokens` / models-endpoint health probe, the long-context pricing tier, Flatline per-voice budgets from the generated maps, and Bridgebuilder generated reasoning flags and 32K budgets.

**Prerequisite deviation.** `/audit-sprint` normally requires the review gate to read "All good". The review ended CHANGES_REQUIRED; the task directed the audit to run regardless, so this report audits the change as submitted and does not write a `COMPLETED` marker. `pr/REVIEW-INSTRUCTIONS.md` says there is no PRD/SDD here, so the SDD decision ids below are quoted from the PR's own code comments and `multi-model-reference.md`. The known-failures surface was unreadable this session (`grimoires/loa/known-failures.md` missing); triage ran without it.

**Method.** I read every non-generated hunk, rebuilt the head tree as a `/tmp` overlay (the workspace's untouched modules have drifted past the PR base) and ran the PR's adapter-level suites there: 56 tests pass (`test_ceiling_policy`, `test_ceiling_retry`, `test_long_context_pricing`, `test_ceiling_probe_write_catalog`, `test_estimator_uncertainty`, `test_count_tokens_fallback`, `test_full_size_adapter_defaults`). The cheval-importing e2e suites cannot be collected against the drifted package and were audited by reading. I reproduced the retry-layer defect by execution against the head module, and verified the beta-header allowlist, the jq reducer and the long-context multiplier parser with standalone checks. Trust boundaries traced: provider HTTP error bodies → `ProviderContextLimitError` → `.run/ceiling-observed.json` and the MODELINV envelope; catalog yaml → `anthropic-beta` header; env redirects → state files; the probe tool → the System-Zone catalog.

**Posture.** No secrets, no new dependencies, no injection into jq/yaml/shell; the catalog parsers fail closed on malformed shapes. The security-relevant defects are in the new provider-verdict path: it bypasses the retry layer's message sanitizer on its way to stderr, accepts any number a provider or proxy states as the new persistent input bound, and classifies every hop by the head entry's unverified flag. The three HIGH findings from the review are confirmed independently (one by execution) and tallied here as my own.

**Security Dissenter (Phase 1C).** `adversarial-audit.json`: `status: reviewed`, primary chain gpt-5.5-pro → gpt-5.5 → gemini-3.1-pro all `api_failure` (no credentials), `claude-headless` answered as the companion, `counted_as: sole_voice`, `voices_succeeded 1/4`, `confidence_floor: low`, `rejected_summary: []`, no sidecar. One voice only ⇒ **DEGRADED_SECURITY_REVIEW** (reason: `sole_voice` — the primary chain never answered). Seven findings, triaged in §Cross-Model Security Observations.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 7 |
| Low | 12 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Retry layer drops the one-shot shrink on the final attempt and the typed verdict becomes walkable

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:495`
**Issue:** The `except ProviderContextLimitError` arm (472–496) shrinks `request.max_tokens` and `continue`s at :495, relying on a further loop iteration to send the shrunk request. When the verdict lands on the last permitted attempt (`attempt == max_retries`) the loop simply ends: `last_typed_error` is never set, `last_error` is whatever the previous arm left, and :530 raises `RetriesExhaustedError`. Reproduced against the head module with the `_Adapter` shape of `test_ceiling_retry.py`:

```
A max_retries=3, limit on attempt 1:        seen=[64000, 10000] -> returned, metadata={'max_tokens_shrunk': {...}}
B max_retries=0, limit on attempt 1:        seen=[64000]        -> RetriesExhaustedError: Failed after 1 attempts: unknown
C max_retries=3, 3x503 then limit on att 4: seen=[64000]        -> RetriesExhaustedError: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE ...
```

**Impact:** cheval's `except ProviderContextLimitError` arm (`cheval.py:2247`) never fires; the walk arm sends the same oversize payload to every fallback hop (repeated provider 400s, cost, latency), no `.run/ceiling-observed.json` row is written, the exit is `CHAIN_EXHAUSTED` with cause "unknown", and the invariant the PR documents in `multi-model-reference.md` ("the provider's own size verdict … is never walked to the next voice") is violated exactly in the configuration operators use to turn retries off. `test_ceiling_retry.py` runs only with `max_retries: 3` and a first-attempt verdict; `test_ceiling_e2e.py:116` patches `invoke_with_retry` away, so no suite reaches this path.
**Fix:** Send the shrunk request outside the attempt budget, or re-raise the typed error when no attempt remains:

```python
            request = replace(request, max_tokens=room)
            last_typed_error = e
            if attempt < max_retries:
                continue
            raise  # typed: cheval records the bound and exits CONTEXT_TOO_LARGE, never walks
```

Add `max_retries: 0` and "verdict on the last attempt" cases to `test_ceiling_retry.py`, and one e2e case that does not patch `invoke_with_retry`.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ; SDD D-1.1b as quoted in `head/.claude/loa/reference/multi-model-reference.md`.

### [HIGH-002] Per-hop walk gate re-decides with the heuristic after the pre-flight accepted the provider's count

**Severity:** HIGH (confidence: medium — confirmed by reading)
**File:** `head/.claude/adapters/cheval.py:2119`
**Issue:** Two estimates of the same prompt flow through `cmd_invoke`. `_walk_estimate` (:1842) is the pre-flight estimate after the D-1.4 count replaced it; the per-hop I1 fit (:2090) and `_lookup_max_input_tokens(..., max_tokens=_hop_budget)` (:2112) derive the hop's bound from it. The comparison at :2119–2120 then uses a fresh `estimate_tokens(messages)` — the heuristic — against that bound. Under the default `probed` policy any prompt the heuristic places above 180K while the provider's count places it below is `ROUTING_MISS`ed at the head hop although the pre-flight dispatched it; under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` the I1 bound equals the count by construction (`cw − (cw − count)`), so `heuristic > count` is the whole test. The fallback hops share the same probed bound and the same heuristic, so the request lands on the CLI hop or exits `CHAIN_EXHAUSTED`.
**Impact:** D-1.4 made the count authoritative near the bound so the heuristic's error (cl100k vs Claude's tokenizer, code-heavy prompts) does not decide the call; the gate re-introduces it one step later, and the only e2e count test (`test_ceiling_e2e.py:167`) uses a count *above* the heuristic, so the overestimating direction is untested.
**Fix:** `_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)` at :2119, plus an e2e case where the counter returns a value below the heuristic near the bound and the head hop dispatches.
**Reference:** CWE-1288 Improper Validation of Consistency within Input — https://cwe.mitre.org/data/definitions/1288.html ; `routing/ceiling.py` docstring ("the provider's count is authoritative").

### [HIGH-003] Bridgebuilder's new default model is an alias that no budget table in the head tree resolves

**Severity:** HIGH (confidence: medium)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172`
**Issue:** `model: "opus"` is a cheval alias. `GENERATED_TOKEN_BUDGETS` (`truncation.generated.ts:19–52`) keys concrete ids only, the head tree exports no alias map (grep of `pr/head/.claude/skills/bridgebuilder-review/` for `GENERATED_MODEL_ALIASES`/`budgetId`: none; `dist/core/truncation.generated.js` was rebuilt without one), so `getTokenBudget("opus")` falls to the `default` row (`truncation.generated.ts:51`: 100000 / 4096) instead of the 5-family row this PR generates (`:27`: 160000 / 32000). The built artefact ships the alias (`dist/config.js:141`). `config.test.ts:161` asserts the literal and nothing downstream of it.
**Impact:** The sprint's Bridgebuilder deliverable — 32K output and 160K input budgets from the catalog — never applies when `BRIDGEBUILDER_MODEL` is unset. With the raised `maxInputTokens: 200_000` default the default configuration either under-budgets (100K) or over-sends (200K against cheval's 180K probed bound), depending on which path `reviewer.ts` takes. (The workspace's later revision of `truncation.ts` resolves aliases through a generated map, which is consistent with this gap having been closed after the PR.)
**Fix:** Keep a concrete default (`claude-opus-5`, the alias target) or emit `GENERATED_MODEL_ALIASES` from `gen-bb-registry.ts` (the yaml `aliases:` block) and resolve it in `getTokenBudget` before the `default` fallback; add `getTokenBudget("opus").maxOutput === 32_000`.
**Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html ; SDD D-1.5 as quoted in `config.ts:168`.

---

## Medium/Low Priority Issues

### Medium

### [MED-001] Observed-bound store accepts any provider-stated number as the persistent input bound
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/cheval.py:2005` (store write), `head/.claude/adapters/loa_cheval/routing/ceiling.py:240–261` (reducer)
- **Issue:** `_calibration_needed_exit` writes `observed_input_tokens` / `provider_limit` parsed from the provider's error text straight into `.run/ceiling-observed.json`; `observed_for` takes the minimum with no plausibility floor, and `input_bound` (:122) caps the bound at `observed − 1` until calibration. A single malformed or hostile 400 of the matched class — `is_context_limit_message` fires on broad substrings such as "context window" or "input length" — e.g. `prompt is too long: 5 tokens > 1 maximum` from an intermediary proxy sets the bound to 1 token and every request to that (provider, model) is preempted locally (exit 7) until an operator runs the probe tool or deletes the store. When the message states no numbers (:2005, `_walk_estimate` None under `LOA_CHEVAL_DISABLE_INPUT_GATE=1`), a row with `observed_input_tokens: 0` is still appended. Confirmed by cross-model review (DISS-C-002, DISS-C-005 of the review round).
- **Fix:** Clamp observations to a plausibility band (e.g. ignore `observed < FLOOR_MAX_TOKENS` or below a fraction of `probed_ceiling`), skip the row when there is no positive observation, and require both a context-class status and a numeric shape before lowering the bound.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html ; CWE-400 Uncontrolled Resource Consumption (self-inflicted denial) — https://cwe.mitre.org/data/definitions/400.html

### [MED-002] `_ceiling_unverified` is computed once from the head entry and applied to every hop and every 429
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/adapters/cheval.py:2297` (429 arm), `:2256` (class), `:1843` (flag set)
- **Issue:** The flag is set from the head entry's pre-flight (:1843) and never recomputed. A plain requests-per-minute 429 on a *fallback* hop (or on the head) ends the invocation as `RATE_LIMIT_UNVERIFIED` (exit 1) and writes a calibration row instead of walking; a `ProviderContextLimitError` on a calibrated fallback is classed `CEILING_UNVERIFIED_LIMIT` although that hop's bound was verified. Confirmed by cross-model review (DISS-C-007). The workspace's later revision of `test_ceiling_e2e.py` carries `test_request_rate_429_while_unverified_walks_to_the_next_hop` and `test_unverified_status_is_per_hop_not_inherited_from_the_head`, which assert the opposite behaviour — the head's tests do not contain them.
- **Fix:** Recompute the unverified flag per hop from that hop's `input_bound` decision (`not calibrated and estimate > probed`) and apply the 429 short-circuit only to a token-limit 429 (message class), never to a request-rate 429.
- **Reference:** CWE-703 Improper Check or Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/703.html

### [MED-003] Provider verdict text reaches stderr and `models_failed[].message_redacted` without passing the sanitizer
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/cheval.py:2022` (recorded), `:2031–2036` (stderr JSON)
- **Issue:** `ProviderContextLimitError` propagates straight through `invoke_with_retry` (`except ChevalError: raise`), so unlike the `RetriesExhaustedError` path it never passes `sanitize_provider_error_message` (retry.py:532). `_calibration_needed_exit` then records `str(_exc)` as `message_redacted` and prints it inside `_error_json` to stderr. The MODELINV emitter does redact `message_redacted` at write time (`audit/modelinv.py:215`, `assert_no_secret_shapes_remain` :881), so the audit chain is protected; the operator stderr/log line is not. A provider or proxy that echoes request fragments or a key-shaped token in a 400 body lands verbatim in operator logs. Confirmed by cross-model review (DISS-C-001); the workspace's later `test_calibration_exit_redacts_secret_shapes_in_the_recorded_message` asserts the secret reaches neither the envelope nor stderr.
- **Fix:** Pass `str(_exc)` through `sanitize_provider_error_message` (or `redact_payload_strings`) before :2022 and :2031.
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [MED-004] Long-context premium ignores cache tokens
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168`
- **Issue:** `if threshold is not None and input_tokens > threshold` — Anthropic's `usage.input_tokens` excludes `cache_read_input_tokens` / `cache_creation_input_tokens` (the adapter maps them separately, `anthropic_adapter.py:557–562`) while the provider applies the tier to the request's total prompt. A 150K uncached + 100K cached prompt is billed premium by the provider and base rate here; `long_context_rows` under-counts exactly the cached long prompts Flatline/Bridgebuilder send, and the daily budget enforcer admits more spend than configured. Confirmed by cross-model review (DISS-C-006).
- **Fix:** Compare `input_tokens + cache_read_tokens + cache_creation_tokens` against the threshold.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-005] Bridgebuilder default input budget exceeds every bound the catalog gives the target
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:176`
- **Issue:** `maxInputTokens: 200_000` is above the generated 160K `maxInput` for the 5-family and above cheval's 180K probed input bound for the `opus` target; a review prepared to the default is preempted by cheval's pre-flight (exit 7, `CONTEXT_TOO_LARGE`) unless something clamps it, and with HIGH-003 the alias is not `known`, so the clamp in `truncation.ts` does not apply.
- **Fix:** Default to the generated row's `maxInput` or clamp the operator budget to `getTokenBudget(model).maxInput` before preparing the payload.
- **Reference:** CWE-1188 — https://cwe.mitre.org/data/definitions/1188.html

### [MED-006] Flatline output budget moves 16K → 64K while the 600 s per-call timeout stays
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:129` (cap), `:1027` (applied)
- **Issue:** cycle-124 introduced the 16000 literal so "the 600 s per-call timeout never meets a 64K-output generation" (the comment this PR deletes). `flatline_voice_max_tokens` now yields 64000 for every Anthropic 5-family voice (`MODEL_MAX_OUTPUT` 128000 capped at `FLATLINE_VOICE_MAX_TOKENS_CAP`), and `_nonstreaming_read_timeout(120, 64000)` saturates at its 600 s cap — the invariant is silently reversed.
- **Fix:** Cap at a value the timeout absorbs (32000, the Bridgebuilder cap) or raise the per-call timeout alongside, and record the decision in the KF-037/KF-038 comment in `.loa.config.yaml`.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [MED-007] 1M-window 4.x entries carry no long-context pricing tier
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/.claude/defaults/model-config.yaml:527` (claude-opus-4-8; also `:574` opus-4-7, `:637` opus-4-6, `:737` sonnet-4-6)
- **Issue:** These entries declare `context_window: 1000000` but no `pricing.long_context`, while the 5-family does (`:408`, `:465`, `:522`, `:732`). A 600K request to them is ledgered at base rate, and `test_long_context_pricing.py::test_entries_outside_the_five_family_carry_no_long_context_tier` locks the gap in.
- **Fix:** Add the tier (`verified: false`) to every 1M-window entry, or document why the 4.x family is excluded.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### Low

### [LOW-001] Beta-header allowlist admits a trailing newline
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82` (pattern), `:174` (`re.match`)
- **Issue:** `_BETA_HEADER_RE` ends in `$` and is applied with `re.match`; in Python `$` matches before a trailing `\n`, so `"context-1m-2025-08-07\n"` passes the allowlist (verified: `match` → True, `fullmatch` → False). Both HTTP clients reject the illegal header value (`http.client` raises `ValueError: Invalid header value`), so no header injection results, but the operator typo surfaces as a transport failure that walks the chain instead of the `ConfigError` the allowlist promises.
- **Fix:** Use `_BETA_HEADER_RE.fullmatch(item)` or `\Z`.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-002] `http_get` urllib path follows redirects with the API key attached
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:342`
- **Issue:** `urllib.request.urlopen` follows 3xx and re-sends the original headers, including `x-api-key`, to the redirect target (cross-host included); the httpx branch does not follow redirects, so behaviour differs by installed client. `health_check` now issues this GET with the live key on every probe. Same pattern as the pre-existing `http_post` fallback; new code path. (DISS-C-004.)
- **Fix:** Build an opener without `HTTPRedirectHandler` for the probe, or treat 3xx as "not served".
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html

### [LOW-003] Long-context multiplier parser accepts `inf` and sub-1.0 values
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:295`
- **Issue:** `_mult` returns any `m > 0`: a YAML `.inf` multiplier passes and `int(inp_cost * inf)` at :171 raises `OverflowError` inside `calculate_total_cost`, after the billed call, aborting ledger creation (row and daily spend lost); multipliers below 1.0 silently under-bill the premium tier. (DISS-C-005.)
- **Fix:** Require `1.0 <= m < some sane cap` and `math.isfinite(m)`; otherwise treat the block as absent with a warning.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-004] `loa-status.sh` jq reducer renders `observed -1` on a zero row and hides the bound on a null row
- **File:** `head/.claude/scripts/loa-status.sh:813`
- **Issue:** `min` runs over `observed_input_tokens` without filtering non-positive or null values (verified: a row with `observed_input_tokens: 0` yields `0` → "observed -1"; a row with `observed_input_tokens: null, provider_limit: 200000` yields `null`, so the `provider_limit + 1` candidate is lost). The Python reducer (`observed_for`) skips both.
- **Fix:** `[.observed_input_tokens | select(. != null and . > 0)]` before the inner `min`.

### [LOW-005] `estimate_input` reports `method: "tiktoken"` whenever the import succeeds
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:1000`
- **Issue:** `estimate_tokens` (:929–933) falls back to the heuristic when `get_encoding("cl100k_base")` fails (offline hosts), but the envelope still says `tiktoken`.
- **Fix:** Derive the method from the branch `estimate_tokens` actually took.

### [LOW-006] Unreachable branch in `fit_max_tokens`
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:144`
- **Issue:** Reaching :144 requires `estimate + requested > cw`, i.e. `room < requested`, so `room >= requested` is never true. `SIMPLICITY[delete]`.

### [LOW-007] `health_check` reports down for any `/models` status other than 200/404
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672`
- **Issue:** A gateway that fronts `/messages` but answers 401/403/405 on `/models` is reported unhealthy. Net better than the retired-id probe it replaces. (Review; DISS-C-008 of the review round.)

### [LOW-008] Only the Anthropic HTTP adapter raises the typed size verdict
- **File:** `head/.claude/adapters/loa_cheval/providers/bedrock_adapter.py:227`
- **Issue:** Bedrock (`ValidationException: input is too long`), OpenAI (`context_length_exceeded`) and Google size verdicts still walk the chain with the same payload — a scope gap against the PR title, not a regression.

### [LOW-009] Near-tautological assertion
- **File:** `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:296`
- **Issue:** `assert derived.value == min(...) or derived.basis in ("calibrated", "i1")` — the second disjunct absorbs most real failures. Split by calibration state.

### [LOW-010] Dead expression wrapped around the real assertion
- **File:** `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:68`
- **Issue:** `… if False else tool.write_catalog(...)` — keep the single `pytest.raises` on the synthetic two-line catalog.

### [LOW-011] e2e suite patches the retry layer away
- **File:** `head/.claude/adapters/tests/test_ceiling_e2e.py:116`
- **Issue:** `patch("loa_cheval.providers.retry.invoke_with_retry", ...)` keeps the retry layer out of every e2e case — the reason HIGH-001 was not caught. One unpatched case with a stub adapter closes the seam.

### [LOW-012] Probe tool leaves its temp file behind on a failed write
- **File:** `head/tools/ceiling-probe-live.py:173`
- **Issue:** `_write_catalog_file` has no cleanup around `os.fdopen`/`os.replace`; `record_observed` in `ceiling.py` unlinks its temp file on failure.

---

## Cross-Model Security Observations

Security Dissenter envelope `adversarial-audit.json` (`--type audit --diff-file pr/head.diff`): primary chain exhausted for want of credentials; companion `claude-headless` answered (`counted_as: sole_voice`) ⇒ **DEGRADED_SECURITY_REVIEW**. Seven findings, all `voice: claude-headless`:

| Id | Dissent severity | Triage |
|----|------------------|--------|
| DISS-C-001 unredacted provider text in `message_redacted` / stderr | MEDIUM | Confirmed with a correction: the MODELINV emitter redacts the field at write time; the stderr line is the unsanitized surface → MED-003 |
| DISS-C-002 observed store takes unbounded provider numbers as the ceiling | MEDIUM | Confirmed by reading `observed_for` / `input_bound` → MED-001 |
| DISS-C-003 store write without symlink guards | LOW | Not a defect: `record_observed` writes via `mkstemp` + `os.replace`, which replaces a planted symlink rather than following it; the path is the same operator-env trust as `LOA_COST_LEDGER_PATH` |
| DISS-C-004 urllib `http_get` follows redirects with `x-api-key` | LOW | Confirmed (pre-existing pattern in `http_post`, new code path) → LOW-002 |
| DISS-C-005 `_mult` accepts `inf` / sub-1.0 | LOW | Confirmed → LOW-003 |
| DISS-C-006 threshold ignores cache tokens | LOW | Confirmed; raised to MEDIUM for the budget-enforcer impact → MED-004 |
| DISS-C-007 `_ceiling_unverified` head-only, every 429 short-circuits | LOW | Confirmed; raised to MEDIUM (fallback disabled by a transient 429) → MED-002 |

The dissent cites three test names as "head tests this diff does not implement"; they exist only in the workspace's later revision of `test_ceiling_e2e.py` (lines 260, 283, 309), not in `pr/head/`. They corroborate MED-002 and MED-003 as behaviours corrected after this PR.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Review-Gate Cross-Check

The review trailer counts `excluded: 0`, so there are no demoted highs to confirm (`excluded_confirmed: 0`). Its three HIGH findings are re-verified above as HIGH-001 (by execution), HIGH-002 and HIGH-003 (by reading the head tree and built artefacts). Its five MEDIUMs are carried (MED-002, MED-004 … MED-007); its LOW on `cheval.py:2005` is folded into MED-001; the remaining LOWs are re-verified at their cited lines. New in this audit: MED-001 (plausibility clamp), MED-003 (sanitizer bypass), LOW-001 (allowlist `$`), LOW-002, LOW-003, and the null-row half of LOW-004.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — the retired `claude-3-haiku-20240307` probe id is removed; `tools/ceiling-probe-live.py` reads `ANTHROPIC_API_KEY` from the environment only
- [x] Input validation at trust boundaries — `params.beta_headers` allowlisted (LOW-001 tightens it), `_long_context_fields` / `_pos_int` reject malformed catalog shapes (LOW-003 tightens multipliers), `load_observed` fails open by design on a malformed state file; **gap:** provider-stated numbers become a persistent bound without a plausibility clamp (MED-001)
- [x] Authentication unchanged — `_headers()` factors the existing `x-api-key` path; `count_tokens` sends the same prompt to the same host
- [x] No injection — `loa-status.sh` passes values to jq via `--arg`/`--argjson`; `write_catalog` edits lines by exact match with validated scalars (`tier` from `_TIERS`, `itpm` int); `gen-adapter-maps.sh` emits bash from yaml keys with the pre-existing quoting pattern
- [ ] Error handling doesn't leak info — the new typed-verdict path prints the provider's message unsanitized to stderr (MED-003); the MODELINV envelope is redacted at emit
- [x] Dependencies — none added (`tiktoken`, `httpx` remain optional)
- [ ] Tests cover security paths — the retry last-attempt path, the heuristic/count disagreement and the per-hop unverified flag are untested (HIGH-001, HIGH-002, MED-002); the e2e suite patches the retry layer out (LOW-011)
- [x] System-Zone integrity — the probe tool's `--write-catalog` rewrites `.claude/defaults/model-config.yaml` by design; `preflight.sh` verifies file counts only, so the rewrite does not trip the integrity gate

---

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| Security | 3 | No secret/injection defects; new provider-verdict path bypasses the sanitizer (MED-003), accepts unbounded provider numbers as policy (MED-001), credential on redirect (LOW-002) |
| Architecture | 4 | `routing/ceiling.py` is a clean pure policy module with named bases; `cmd_invoke` grows ~150 lines and carries two estimates of one prompt (HIGH-002) |
| Code Quality | 3 | Control flow that depends on "there is a next iteration" (HIGH-001); unreachable branch, dead test expressions, tautological assertion |
| DevOps | 3 | Generated maps/registry regenerate cleanly; Flatline timeout invariant reversed silently (MED-006); dist shipped with an unresolvable default (HIGH-003) |
| Blockchain/Crypto | n/a | — |

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` reports exist (the PR is a frozen snapshot; `pr/REVIEW-INSTRUCTIONS.md` says to skip steps that need them). Manually verified: `head/.claude/loa/reference/multi-model-reference.md` documents the ceiling policy, the non-walkable verdict and the probe command; the Bridgebuilder `SKILL.md` budget table is updated; the new env knobs (`LOA_CHEVAL_UNCALIBRATED_CEILING`, `LOA_CHEVAL_LEGACY_CEILING`, `LOA_CHEVAL_MAX_INPUT_TOKENS`, `LOA_CHEVAL_CEILING_OBSERVED_PATH`) are documented in the module docstring. No CHANGELOG entry is part of the frozen diff (cannot verify whether the repository keeps one). The security-relevant contract that is documented but not met is the "never walked" invariant (HIGH-001).

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (send or re-raise the shrunk request when no attempt remains), HIGH-002 (reuse `_walk_estimate` at the walk gate), HIGH-003 (concrete default or generated alias map) with the named regression tests.
2. Decide MED-001 … MED-007 as explicit policy: plausibility clamp on observations, per-hop unverified flag with a token-limit-only 429 short-circuit, sanitizer on the verdict path, cache tokens in the premium threshold, 200K default vs the catalog bound, 64K vs the 600 s timeout, 4.x long-context tier.
3. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again; the dissent should be re-run with a second voice available (this round was `sole_voice`).

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:16:00Z"} -->
