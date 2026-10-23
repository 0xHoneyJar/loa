# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)
**Scope:** `pr/head.diff` (65 files; cycle-126 sprint-247 — full-size adapters, Bridgebuilder and Flatline sized from the resolved catalog entry). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The PR replaces the single input-ceiling literal with a policy module (`loa_cheval/routing/ceiling.py`) that derives every size decision from the resolved catalog entry, adds a self-correcting observed-bound store (`.run/ceiling-observed.json`) fed by the provider's own context-limit verdicts, an `anthropic-beta` allowlist, a long-context pricing tier, a count-tokens pre-flight and catalog-driven output defaults for every provider, and re-sizes Flatline and Bridgebuilder from the same rows. No secrets, no new network destinations beyond the configured provider endpoint, and the one new data path (`count_tokens`) sends the already context-filtered prompt (`audit_filter_context` runs at `head/.claude/adapters/cheval.py:1672`, before the request object is built). The System-Zone boundary is respected: the only writer into `.claude/` is the operator-invoked probe tool, by design (FR-1.1).

The security posture problem is in the self-correction arm (D-1.1b). Numbers parsed from a provider's HTTP 400/413 body, and a broad marker list that classifies the body as a "size verdict", are written unvalidated into a persistent store that lowers the model's input bound for every later invocation until an operator recalibrates; the same arm ends the chain on any 429, inherits the head hop's "unverified" state on every fallback hop, and the store itself loses rows under the concurrent writers Flatline and the adversarial review always produce. Bridgebuilder's new default model is an alias no budget table knows. These are availability and correctness defects rather than confidentiality ones, but four of them are HIGH and the one-way rule forces CHANGES_REQUIRED.

Dissent: two voices (gpt-5.5-pro primary, claude-headless companion, `counted_as: independent_voice`, `degraded: false`, `locality: null`). Not a degraded security review. Six findings, all triaged below; one (DISS-C-001) is counted as a finding of my own, three confirm review findings, two are downgraded with the reason stated.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 7 |
| Low | 13 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

The review tallied four HIGHs; each is confirmed independently below from the head files and counted as my own.

### [HIGH-001] The D-1.1b 429 arm ends the chain on every RateLimitError, not the token-limit class

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/adapters/cheval.py:2297`
**Issue:** `except RateLimitError as _e: if _ceiling_unverified: return _calibration_needed_exit(... error_class="RATE_LIMIT_UNVERIFIED" ...)`. The comment at 2298-2301 scopes the arm to "the token-limit class", but `RateLimitError` carries no class — the Anthropic adapter raises it bare on any 429 (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:343`, `:489`) — and the code tests only `_ceiling_unverified`.
**Impact:** Under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, a requests-per-minute 429 (the ordinary shape under load) on a request above the probed bound exits RATE_LIMITED without trying the declared fallback, and appends a RATE_LIMIT_UNVERIFIED row for a 429 that said nothing about size. The operator's chain is the availability contract; this arm voids it. `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` (`head/.claude/adapters/tests/test_ceiling_e2e.py:247`) pins the wrong behaviour for a classless 429.
**Fix:** Classify the 429 in the adapter (`RateLimitError(..., token_limited=True)` when the body says tokens-per-minute / TPM / context-limit) and short-circuit only on `token_limited`; a request-rate 429 walks as it does under the bound. Update the e2e test and add the request-rate case.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-002] `_ceiling_unverified` is computed once from the head entry and applied to every fallback hop

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/adapters/cheval.py:1843` (set), `:2256` and `:2297` (read)
**Issue:** `_ceiling_unverified = _preflight_outcome.unverified` is assigned once in the pre-flight branch and never recomputed inside `for _idx, _entry in enumerate(_chain.entries)`. "Above the probed bound" is a property of a hop's own entry and budget.
**Impact:** A calibrated fallback (or one whose bound exceeds the estimate) that returns a provider verdict is classed `CEILING_UNVERIFIED_LIMIT` instead of `PROVIDER_CONTEXT_LIMIT`, and a plain 429 on it hits HIGH-001; either way the store row and the envelope attribute calibration evidence to the wrong model, and the self-correction lowers the wrong bound.
**Fix:** Compute `_hop_unverified` per hop in the walk loop from `input_bound(_hop_entry, max_tokens=_hop_budget, observed=..., policy=...)` (unverified iff not calibrated and `_walk_estimate > decision.probed`) and consult it at both arms; keep the head's flag on the envelope as the pre-flight record only.
**Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html

### [HIGH-003] `record_observed` has no inter-process lock — concurrent writers lose provider verdicts

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:279-299`
**Issue:** `data = load_observed(path)` (279) → `append` (290) → `mkstemp` + `os.replace(tmp, path)` (294-299). Atomic per writer, not serialised across writers; the docstring promises "append-only history".
**Impact:** Flatline dispatches three voices and the adversarial review two voices concurrently against the same provider with the same payload size, so simultaneous verdicts are the normal case. The review reproduced 4 writers × 25 rows retaining 26-30 of 100. A lost `PROVIDER_CONTEXT_LIMIT` row means the bound is not lowered and the next call repeats the paid failure. (Data-loss handling is on the never-simplify-away floor.)
**Fix:** Hold an exclusive `fcntl.flock` on `<store>.lock` (opened `O_NOFOLLOW`, refused when not a regular file — the pattern at `.claude/adapters/loa_cheval/metering/ledger.py:229-233`) around load → append → replace; keep temp + `os.replace` for lock-free readers. Add an N-writers × M-rows test.
**Reference:** CWE-362 Concurrent Execution using Shared Resource with Improper Synchronization — https://cwe.mitre.org/data/definitions/362.html

### [HIGH-004] Bridgebuilder's new default model is an alias with no token budget

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` (`model: "opus"`), `:176` (`maxInputTokens: 200_000`); `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19-56` (model ids only); `head/.claude/skills/bridgebuilder-review/resources/personas/quick.md:2` (`tiny`), `security.md:2` (`opus`)
**Issue:** The budget tables are keyed by concrete model id and the PR's `truncation.generated.ts` exports no alias map (no `GENERATED_MODEL_ALIASES` anywhere under `pr/head/`), so `getTokenBudget("opus")` resolves to the `default` row (100K/4096, `truncation.generated.ts:51`) and `effectiveInputBudget(200000, "opus")` returns the raw 200K operator default — above cheval's 180K probed bound for the alias target. Independent confirmation: this snapshot's later `truncation.ts` (sprint-250 round 2) adds exactly the alias resolution the PR lacks, naming this gap.
**Impact:** Under the default configuration a large review is built to 200K and preempted by cheval (CONTEXT_TOO_LARGE, exit 7) where it used to truncate to 160K; a smaller one runs on 100K/4096 instead of 160K/32K. The PR's own goal ("every size decision derives from the resolved catalog entry") fails for the default model, and `truncation-registry.test.ts` checks concrete ids only.
**Fix:** Emit the catalog's `aliases:` block as `GENERATED_MODEL_ALIASES` from `gen-bb-registry.ts` and resolve an alias before the budget lookup; test `getTokenBudget("opus")` equals the target's row and `effectiveInputBudget(200000,"opus")` is clamped.
**Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

---

## Medium/Low Priority Issues

### [MED-001] Provider-stated numbers and a broad marker list poison the persistent input bound (self-inflicted denial of a model)
- **Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (DISS-C-001); traced independently.
- **File:** `head/.claude/adapters/cheval.py:2004-2010` (`_obs = int(observed) ... else int(_walk_estimate or 0)`; `record_observed(... provider_limit=provider_limit)`), `head/.claude/adapters/loa_cheval/routing/ceiling.py:157-169` (markers), `:182-198` (`parse_context_limit`), `:240-261` (`observed_for`), `:122-123` (`observed - 1` becomes the bound); raise sites `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:361-365`, `:503-507`.
- **Issue:** Any HTTP 400/413 whose sanitised text contains one of eleven substrings ("context window", "input length", "maximum context", …) is typed `ProviderContextLimitError`; the numbers the regexes pull from the body are stored as `observed_input_tokens` / `provider_limit` with no plausibility check against the estimate, the catalog `context_window`, or a floor; when the body states no numbers, cheval's own estimate is stored as the observed failure point. `observed_for` then returns the minimum and `input_bound` makes `observed − 1` the bound for every later call to that (provider, model) until `calibrated_at` is set — which needs a paid probe run.
- **Failure scenario:** a 400 that is not a size verdict but mentions "context window" (e.g. a thinking-budget validation error), or a proxy / gateway error page, or an endpoint under `LOA_CHEVAL_ANTHROPIC_BASE_URL`-style redirection answering `"1 tokens > 1 maximum"`, pins the bound at 0-1 and every subsequent invocation of the `opus` target preempts CONTEXT_TOO_LARGE. A single response both ends the call (not walked) and poisons future ones; recovery is a manual store edit or the probe command.
- **Fix:** Accept a provider number only when `limit` is within `[FLOOR, context_window]` and `input_tokens` is within a band of the estimate (e.g. 0.5×–2×); never store the estimate as "observed" for `PROVIDER_CONTEXT_LIMIT`; require a positive classifier (the two regex shapes) before lowering the bound, and treat marker-only matches as walkable 400s. Add a tamper test (`"1 tokens > 1 maximum"` must not change the bound).
- **Reference:** CWE-1284 Improper Validation of Specified Quantity in Input — https://cwe.mitre.org/data/definitions/1284.html; CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [MED-002] Long-context threshold ignores cached prompt tokens — the budget cap under-fires on exactly the most expensive requests
- **Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (DISS-C-003 / review DISS-001).
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:168` (`if threshold is not None and input_tokens > threshold`)
- **Issue:** `cache_read_tokens` / `cache_creation_tokens` are, per `head/.claude/adapters/loa_cheval/metering/ledger.py:133`, "not part of input_tokens". A prompt-cached run of 190K cached + 30K fresh is billed at the premium by the provider and at base rates here; `long_context` is absent from the row, so `cost-report.sh` and the daily-spend enforcer that reads the ledger both under-count. Flatline and Bridgebuilder (cycle-124 cache_control) are this workload.
- **Fix:** Compare `input_tokens + cache_read_tokens + cache_creation_tokens` against the threshold; add a cached-above-threshold test.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-003] `_mult` accepts non-finite multipliers; `.inf` turns a billed completion into API_ERROR and drops the ledger row
- **Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (DISS-C-005).
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:290-295` (`m = float(value) ... return m if m > 0 else 1.0`), `:171` (`int(inp_cost * im)`)
- **Issue:** `float("inf")`, `"1e309"` and `.inf` pass `m > 0`; `int(cost * inf)` raises `OverflowError` inside `calculate_total_cost`, which runs in `budget_hook.post_call` (`head/.claude/adapters/cheval.py:2231`) inside the walk-loop `try`, so the catch-all reports a completed, billed answer as API_ERROR and no ledger row is written. Multipliers in (0, 1) are also accepted and silently discount the premium. The parser's docstring promises "a malformed … block means no premium tier".
- **Fix:** `math.isfinite(m) and m >= 1.0` (and reject bool) in `_mult`; add `.inf` / `nan` / `1e309` / `0.5` cases to `test_long_context_pricing.py`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-004] The retry-layer output shrink is lost on the final attempt and the oversize payload is walked to the next voice
- **Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (review DISS-002 / DISS-C-001).
- **File:** `head/.claude/adapters/loa_cheval/providers/retry.py:472-496`
- **Issue:** `request = replace(request, max_tokens=room); continue` runs inside `for attempt in range(max_retries + 1)` and sets neither `last_typed_error` nor `last_error`. When the context-limit error arrives on the last iteration (always under `retry.max_retries: 0`, otherwise after backoffs consumed the earlier attempts) the loop ends without sending the shrunk request and the post-loop `RetriesExhaustedError` carries the previous transient's text; cheval's `except RetriesExhaustedError` (`head/.claude/adapters/cheval.py:2338`) walks, so the identical payload reaches the next voice, no observation is recorded, and the exit is CHAIN_EXHAUSTED instead of CONTEXT_TOO_LARGE.
- **Fix:** Perform the one-shot shrink outside the attempt counter (or re-raise the `ProviderContextLimitError` when no attempt remains) and set `last_typed_error`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] Non-Anthropic output default rises to 16K while the I1 fit runs only for ceiling-bearing entries — the adapter now refuses prompts that fit before
- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (review DISS-C-002).
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:187-203` (`default_max_tokens`: `base = _NON_ANTHROPIC_DEFAULT_OUTPUT_CAP`), `head/.claude/adapters/cheval.py:2078-2087` (fit gated on `effective_input_ceiling`/`probed_ceiling` in the entry)
- **Issue:** gpt-5.2 (128K window, `max_output_tokens: 16000`, no ceiling fields) jumps from 4096 to 16000 with no I1 shrink; `enforce_context_window` then evaluates `estimate + 16000 ≤ 128000`, so a 115K prompt that dispatched before raises `ContextTooLargeError` and walks, silently (the walk-gate threshold did not change).
- **Fix:** Apply the I1 fit to every hop with a `context_window`, not only ceiling-bearing entries, or keep 4096 for entries without a ceiling.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [MED-006] Gate and adapter disagree on units: the gate accepts on the provider count, the adapter refuses on the chars/3.5 heuristic
- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (review DISS-C-003).
- **File:** `head/.claude/adapters/cheval.py:1840-1842` (`_walk_estimate = _preflight_outcome.estimate.tokens`), `head/.claude/adapters/loa_cheval/providers/base.py:1019` (`enforce_context_window` still calls `estimate_tokens`; unchanged in this diff)
- **Issue:** When the count endpoint runs, the I1 fit grants `max_tokens = context_window − count`, but the adapter's own window check uses the heuristic. Where the heuristic overcounts (English prose ≈ 4 chars/token) a request approved near the window (count 130K + 64K on 200K) is refused by the adapter (heuristic 150K + 64K > 200K) and walked.
- **Fix:** Pass the gate's estimate (or the fitted decision) into the adapter, or let `enforce_context_window` take an override estimate.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [MED-007] Flatline's 64000 voice cap ignores the streaming kill switch
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:129` (`FLATLINE_VOICE_MAX_TOKENS_CAP=64000`), `:936-946`, `:1027`
- **Issue:** Under `LOA_CHEVAL_DISABLE_STREAMING` cheval's own Anthropic default is 16K (`base.py:187-203`) and `_nonstreaming_read_timeout` caps at 600 s (≈ 15K tokens at 25 tok/s); the orchestrator still passes an explicit 64000 clamped only to the catalog's 128K, so a long voice answer hits the read timeout where the cycle-124 16000 literal completed on both transports.
- **Fix:** Cap at the transport default (16000 when the kill switch is set) or pass no `--max-tokens` and let cheval's per-model default decide.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [LOW-001] New calibration exit records `str(_exc)` without the redaction helper (defence in depth)
- **Severity:** LOW (confidence: high) — DISS-001 / DISS-C-002 downgraded: the Anthropic adapter sanitises every provider body via `_extract_error_message` → `sanitize_provider_error_message` (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:791-810`) before raising, and `RateLimitError` is raised with no body (`:343`, `:489`). The test the dissenters name (`test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`) does not exist under `pr/head/`.
- **File:** `head/.claude/adapters/cheval.py:2022` (`"message_redacted": str(_exc)`), `:2032-2037` (stderr `_error_json`)
- **Issue:** Every other `models_failed` writer in the file redacts at the recording site; this one relies on the adapter having done so. A future adapter raising `ProviderContextLimitError` from a raw body would leak.
- **Fix:** Wrap with `sanitize_provider_error_message` at the recording site.
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [LOW-002] `anthropic-beta` allowlist lets Unicode digits and a trailing newline through
- **Severity:** LOW (confidence: high) — Confirmed by cross-model review (DISS-C-004).
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82` (`\d{4}-\d{2}-\d{2}$`), `:174` (`re.match`)
- **Issue:** `\d` matches non-ASCII digits and `$` matches before a trailing `\n`, so `"context-1m-٢٠٢٥-08-07"` and `"context-1m-2025-08-07\n"` pass; both HTTP clients then reject the header value with an untyped exception instead of the promised `ConfigError`. No header injection is possible (the character class excludes CR/LF mid-string and the clients refuse CR/LF).
- **Fix:** `[0-9]` and `re.fullmatch`.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-003] `loa-status.sh` splices the model id into a yq expression and mis-renders `observed`
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/loa-status.sh:806-808` (`".providers.anthropic.models.\"$model\"..."`), `:811-813` (jq `min` over `[.observed_input_tokens, …]`)
- **Issue:** The id comes from the catalog's `aliases.opus` (System Zone, operator-controlled) so the splice is a hardening gap, not an exploit; use `strenv`. The jq `min` yields `null` when a row lacks `observed_input_tokens`, dropping a `provider_limit`-only row, and a `0` row renders `observed -1` while `observed_for` ignores it.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-004] Generated `MODEL_MAX_OUTPUT` interpolates the YAML key unescaped into sourced bash
- **Severity:** LOW (confidence: low) — Confirmed by cross-model review (DISS-C-006); the eight pre-existing arrays in `gen-adapter-maps.sh` use the same raw `[\"\($m.key)\"]` pattern, so this is a repeated hardening gap, not a new class.
- **File:** `head/.claude/scripts/gen-adapter-maps.sh:257-262`
- **Issue:** A key containing `"`, `$(` or a backtick would break out of the string in `generated-model-maps.sh` and execute when `flatline-orchestrator.sh` sources it. The value side is guarded by `select(type == "number")`; the key is not. The catalog is operator-controlled.
- **Fix:** Render keys with `@sh` (or reject keys outside `^[A-Za-z0-9._:-]+$` in the generator).
- **Reference:** CWE-78 — https://cwe.mitre.org/data/definitions/78.html

### [LOW-005] Observed-store path accepts any env-supplied path with no regular-file / symlink check, unlike the ledger
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:211-216` (`LOA_CHEVAL_CEILING_OBSERVED_PATH` returned raw), `:292-293` (`os.makedirs` of its parent)
- **Issue:** `resolve_cost_ledger_path` refuses a symlink target and a missing parent (`.claude/adapters/loa_cheval/metering/ledger.py:86`); the new store creates any parent and accepts a symlink. `os.replace` replaces the link rather than following it, so no write-through is possible, but a planted symlink is silently destroyed and the two state files follow different rules.
- **Fix:** Reuse the ledger's resolution rules (canonicalise, refuse symlink / non-regular, require existing parent for the override).
- **Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

### [LOW-006] `--write-catalog` leaves `model-config.yaml` with mode 0600
- **Severity:** LOW (confidence: medium)
- **File:** `head/tools/ceiling-probe-live.py:173-176`
- **Issue:** `tempfile.mkstemp` creates the temp at 0600 and `os.replace` makes that the catalog's mode, dropping the original 0644; on a shared host other accounts (CI runners, a second operator) lose read access to the System-Zone catalog until someone notices. Git does not track the change.
- **Fix:** `shutil.copymode(path, tmp)` (or `os.chmod(tmp, stat.S_IMODE(os.stat(path).st_mode))`) before the replace.
- **Reference:** CWE-732 Incorrect Permission Assignment for Critical Resource — https://cwe.mitre.org/data/definitions/732.html

### [LOW-007] Long-context multipliers applied to already-floored per-category costs
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:171-175`
- **Issue:** `int(inp_cost * im)` multiplies the floored micro cost and the remainders (`inp_rem`, `cr_rem`, …) are not recomputed: 3 tok × 1.25 µUSD × 1.5 bills 4 where the exact floor is 5. Micro-USD scale, but the remainder accounting exists for exactly this and is discarded on the premium path.
- **Fix:** Compute `floor(tokens × rate × multiplier / 1e6)` per category and scale the remainder the same way.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [LOW-008] `"too many tokens"` marker also matches Bedrock's throttle text
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/routing/ceiling.py:159`
- **Issue:** "Too many tokens, please wait before trying again" is a throttle. Only the Anthropic adapter's 400/413 reach the classifier today, so no misfire yet; a throttle marker should outrank a context marker before the classifier is reused by Bedrock. Compounds MED-001.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-009] Estimator reports `method="tiktoken"` whenever the module imports
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:998-1003`
- **Issue:** `estimate_input` sets `method` by import success, not by whether `estimate_tokens` actually used the encoding (an offline `get_encoding` falls back to the heuristic), so the envelope's `estimator.method` can be wrong.
- **Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [LOW-010] The "max_tokens shrunk" notice is hidden behind the warn branch; fallback-hop shrinks print nothing
- **Severity:** LOW (confidence: medium) — Confirmed by cross-model review (review DISS-C-006).
- **File:** `head/.claude/adapters/cheval.py:1888` (`elif _preflight_outcome.shrunk_from is not None`), `:2105-2109`
- **Issue:** A request both warned and shrunk prints only the warn; a fallback-hop shrink writes only the envelope field. An explicit `--max-tokens 64000` can be cut to the 4,096 floor with no stderr line.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-011] Health probe falls back to a message only on exactly 404
- **Severity:** LOW (confidence: low) — Confirmed by cross-model review (review DISS-C-005).
- **File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672-674`
- **Issue:** A proxy answering 403/405/501 for `/models` reports a healthy deployment as down. Minor because the pre-cycle probe targeted a retired id and was worse.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-012] On a CLI hop the calibrate hint names a model `write_catalog` refuses
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/cheval.py:2016`
- **Issue:** The hint is `--model claude-headless`, which `write_catalog` rejects (no block fields), and the observation is recorded against an entry with no HTTP ceiling, so the row can never lower anything.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [LOW-013] Code quality — `cmd_invoke` grows ~250 lines with a 50-line closure over eleven enclosing names
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/cheval.py:1805-1862` (pre-flight branch, four levels deep), `:1994-2037` (`_calibration_needed_exit`), `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:639-659` (`_tiny_model_id`)
- **Issue:** The nesting is where HIGH-002 hid (a flag captured by closure instead of computed per hop). Extract both to module-level helpers taking the state dict; `_tiny_model_id` is a one-line `min()` over priced entries after the haiku check.
- **Reference:** CWE-1121 Excessive McCabe Cyclomatic Complexity — https://cwe.mitre.org/data/definitions/1121.html

---

## Observations

Non-tallied notes (no speculative high/critical was excluded; `excluded: 0`).

- **Process:** `reviewer.md` (= `pr/PR.md`) is a one-line title with no `## AC Verification` walkthrough and no per-FR `file:line` evidence; the review already requires this.
- **Documentation audit:** no `grimoires/loa/a2a/subagent-reports/` exists in this snapshot, so no documentation-coherence report could be checked. Manually verified: `multi-model-reference.md` and the Bridgebuilder `SKILL.md` were updated for the new defaults and the ceiling policy; no secrets or internal URLs in the added doc lines; no CHANGELOG is present in the snapshot, so the per-task entry (including the security-relevant `anthropic-beta` allowlist and the new persistent store) could not be verified. Not a blocker on its own; record it on the fix round.
- **Trust context assumed:** `.claude/defaults/model-config.yaml`, `.loa.config.yaml` and `LOA_CHEVAL_*` env vars are operator-controlled (same trust as the process). Provider HTTP bodies are untrusted network input (MED-001, LOW-001). `pr/` contains no `.reviewignore`; all 65 files were in scope.
- **Scope limit:** Bridgebuilder `dist/*.js` artifacts were checked only for consistency with their `.ts` sources; the bats suites and the live probe were read, not run (the probe spends money and the review already ran the Python and bats suites).

---

## Cross-Model Security Observations

Two voices, `verdict_quality.voices_succeeded: 2/2`, `consensus_outcome: consensus`, `degraded: false`. Primary gpt-5.5-pro answered via `codex-headless`; companion `claude-headless`, `counted_as: independent_voice`. Not a DEGRADED_SECURITY_REVIEW.

| Dissent | Triage |
|---------|--------|
| DISS-001 (MEDIUM, redact at calibration exit) | Downgraded → LOW-001: adapter sanitises upstream; the cited test does not exist in `pr/head/`. |
| DISS-C-001 (MEDIUM, provider numbers poison the bound) | Real → MED-001, counted as my own (traced independently before the envelope arrived). |
| DISS-C-002 (MEDIUM, secret shapes in envelope) | Duplicate of DISS-001 → LOW-001. |
| DISS-C-003 (MEDIUM, cache tokens vs threshold under-fires the budget cap) | Real → MED-002, Confirmed by cross-model review. |
| DISS-C-004 (LOW, beta regex `$`) | Real → LOW-002. |
| DISS-C-005 (LOW, `.inf` multiplier) | Real; damage is a lost ledger row and a billed call reported as API_ERROR → MED-003. |
| DISS-C-006 (LOW, unescaped key in generated bash) | Real hardening gap, pre-existing pattern → LOW-004. |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and `adversarial-rejected-audit.jsonl` is 0 bytes.

---

## Rubric Scores

| Dimension | Score (1-5) | Justification |
|-----------|-------------|---------------|
| Security | 3 | No secret, injection or boundary defect; one untrusted-input → persistent-state availability path (MED-001) and defence-in-depth gaps (LOW-001/002/005). |
| Architecture | 3 | The policy module is clean and well-named; the walk-loop integration captures head state by closure (HIGH-002) and the alias layer was missed (HIGH-004). |
| Code Quality | 3 | Strong unit coverage of the policy; the e2e tests pin two wrong behaviours (HIGH-001) and no concurrency test (HIGH-003). |
| DevOps | 3 | Generated maps and dist rebuilt consistently; mode and lock handling on the two new state writers lag the ledger's hardening. |
| Blockchain/Crypto | N/A | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new trust boundaries (provider error numbers: MED-001)
- [x] Authentication required where needed (count_tokens / health reuse the provider headers)
- [x] No shell / header injection path reachable from untrusted input (LOW-002, LOW-004 are hardening)
- [x] Error handling doesn't leak info (sanitised upstream; LOW-001 defence in depth)
- [ ] Tests cover security paths (no tamper test for the store; no multi-writer test)

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 … HIGH-004 (classify the 429, per-hop unverified, flock the store, alias → budget).
2. Fix MED-001 (plausibility-check provider numbers; positive classifier before lowering the bound) alongside HIGH-003 — same file, same test.
3. Address MED-002 … MED-007 and the LOWs as the fix round allows; add the `## AC Verification` walkthrough to the implementation report.
4. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":13},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T02:59:00Z"} -->
