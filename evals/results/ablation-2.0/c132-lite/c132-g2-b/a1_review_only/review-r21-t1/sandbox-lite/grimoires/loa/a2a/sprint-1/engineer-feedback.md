# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`: title and file count only)

---

## Overall Assessment

The change under review is `pr/head.diff` (sprint-257: advisory open-weight voices, `hounfour.locality: local_voices`, Bridgebuilder trusted configuration and exit codes, E2E). Eighty files; the bulk is `adversarial-review.sh` (advisory voices, catalog-priced budget gate, locality plan-time refusals), the cheval Python path (endpoint opt-in rule, `TransportPolicy`, keyless providers, thinking strip, chat `response_format`, MODELINV locality telemetry, price provenance), Bridgebuilder (`loadTrustedConfig`, exit 3 on DEGRADED) and the shell callers.

What is good: the load-time endpoint rule is genuinely one implementation (the cheval module loads `endpoint-validator.py` by path; one case table runs through both entry points), the opt-in host canonicalisation holds up against the usual bypasses (userinfo, trailing dot, obfuscated literals, mapped IPv6, link-local, metadata — exercised here against the head validator), proxy/redirect refusal is enforced in code on all three `http_*` helpers and in curl, the advisory block is kept out of every counted key (ADV-2 pins byte-identity of the normalised envelope and of `verdict-derive --json`), Bridgebuilder reads providers/locality/exit key from the base ref or a repository variable and refuses head-only keyless/insecure declarations, every `entry.sh` caller maps exit 3, and `dist/` matches the `.ts` sources.

What blocks: the request-time half of D-7.2 is wired into `OpenAIAdapter` only, while the loader admits `allow_insecure_endpoint` and `dispatch_group: local` for every non-CLI provider type — an opted-in Anthropic- or Google-type provider loads and then runs on the default transport (proxy env honoured, urllib redirects followed, plain http). And four documents say the health probe refuses hosted hops under `local_voices`; `model-health-probe.sh` never reads `hounfour.locality`. The medium observations are a stale budget comment that now contradicts the gate, a locality label that is never cross-checked against the endpoint despite the "IP-literal or localhost, no DNS" promise, four locality rule copies that disagree on a provider-block `dispatch_group`, and a wrong exit-code row.

Adversarial cross-model review ran (2/2 voices, `gpt-5.5-pro` via `codex-headless` + `claude-headless`, status `reviewed`, no rejected payloads). Its two BLOCKING findings are incorporated below (one as a HIGH, one downgraded with the reason stated).

`reviewer.md` carries no `## AC Verification` section; `pr/REVIEW-INSTRUCTIONS.md` states there is no implementation report in this workspace and waives that pre-flight, so it is not counted — the verdict stands on the code findings.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — request-time locality rules apply to one adapter only

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:156` — `validate_providers` admits `allow_insecure_endpoint` (and `dispatch_group: local`) for every non-CLI provider type, but the `TransportPolicy` it promises is built and passed only by `OpenAIAdapter`; an opted-in `type: anthropic` or `type: google` provider loads, then sends the prompt and its key over plain http through whatever `HTTP_PROXY`/`HTTPS_PROXY` names, and the urllib fallback follows redirects.
**File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143-181` (admission), `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-223` (the only `_transport_policy`), `head/.claude/adapters/loa_cheval/providers/base.py:304` and `:332` (default branch: `httpx.post` with `trust_env` default, `urllib.request.urlopen` with redirects).
**Issue:** `check_endpoint(endpoint, optin, name)` runs for any provider whose `type` is not `*-headless` / `kind: cli`. The module docstring (`endpoint_policy.py:27-29`) and the config example (`.loa.config.yaml.example:1229-1232`) say that for an opted-in or local provider "the adapter ignores proxy environment variables, refuses HTTP redirects and requires every request URL to stay under the declared endpoint path". Only `openai_adapter.py` passes `policy=` to `http_post`/`http_post_stream`; the Anthropic and Google adapters (untouched by this change — live `anthropic_adapter.py:334,486`, `google_adapter.py:370,668`) call the helpers without it, so `base.py` takes the default branch. Under `local_voices`, `hop-locality.py` plans such a hop as local (the label is all it reads) and MODELINV records `hop_locality: local`.
**Why This Matters:** A declared posture ("the prompt does not cross a public network unencrypted", `.loa.config.yaml.example:1227`) is false for a whole class of admitted configurations; the audit trail says local while the bytes go through a proxy. CWE-319 (cleartext transmission), CWE-441 (unintended proxy).
**Required Fix:** Either refuse at load — in `validate_providers`, reject `allow_insecure_endpoint` and `dispatch_group: local` when the provider's `type` is not `openai`/`openai_compat` (named reason, e.g. `ENDPOINT-OPTIN-UNSUPPORTED-TYPE`) — or plumb `policy=` into every adapter's `http_post`/`http_post_stream`/`http_get` call exactly as `OpenAIAdapter._dispatch` does, and add one test per adapter family to `test_endpoint_validator_optin.py` (`test_opted_in_adapter_sends_no_credential_and_uses_the_policy` covers OpenAI only). Fix the docstring to match whichever you choose.
**Reference:** SDD D-7.2 as quoted in the module docstring; dissent DISS-001 / DISS-C-002.

### 2. Documentation claims a security control the code does not have

- **HIGH** (confidence: high) `head/.claude/loa/reference/scripts-reference.md:73` — "`model-health-probe.sh [--provider <name>]` … refuses a hosted probe under `local_voices`" is not implemented: `model-health-probe.sh` contains no read of `hounfour.locality` (`grep -n locality` on the head file returns nothing), so under `local_voices` the probe still sends the operator's API keys to `api.openai.com`, `googleapis.com` and `api.anthropic.com`.
**File:** `head/.claude/loa/reference/scripts-reference.md:73`; the same claim at `head/README.md:30` ("refuses every hosted hop by name across the dissent, Flatline, Bridgebuilder and the probe"), `head/.loa.config.yaml.example:816-820` ("… Bridgebuilder and the health probe is planned only on a provider whose model entry says `dispatch_group: local`") and `head/.claude/loa/reference/multi-model-reference.md:102` ("the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on…"). Code: `head/.claude/scripts/model-health-probe.sh:1428-1546` (`_probe_configured`, `_probe_one_model`) and `:1756` (`_parse_args`) — no locality branch.
**Issue:** The dissent (`adversarial-review.sh`), Flatline (`flatline_locality_gate`) and Bridgebuilder (`applyLocality`) each got a plan-time gate with tests (LOC-*, FLL-*, trusted-config tests). The probe got the configured-provider path (D-7.5) but not the FR-8 gate, and four documents were written as if it had.
**Why This Matters:** An operator who sets `local_voices` to keep every model-provider contact local, then runs `/loa` or the probe, makes authenticated outbound calls to three hosted vendors — the posture the documents promise is silently absent for one of its four named surfaces. A documented control that does not exist is worse than an undocumented gap.
**Required Fix:** Either implement it — read `hounfour.locality` once in `model-health-probe.sh` (the same `yq … | tag` shape `adversarial-review.sh:238-250` uses), and under `local_voices` skip every provider the classifier does not call local (`python3 -I lib/hop-locality.py …`), logging the same `locality: local_voices refuses hosted hop <m> (<p>)` line, with a bats case beside `model-health-probe-configured-provider.bats` — or remove the probe from all four sentences. Add the probe to LOC-5's "default unchanged" check either way.
**Reference:** `.loa.config.yaml.example:816-820` (the operator-facing contract).

---

## Observations

### 1. Budget gate — the config comment now contradicts the code

- **MEDIUM** (confidence: high) `head/.loa.config.yaml.example:1624-1632` — the `budget_cents` comment still says "Gate on ONE dissent call's pre-dispatch cost estimate … the companion voice and the KF-004 repairs … are further calls it does not count", but `head/.claude/scripts/adversarial-review.sh:4329-4335` now sums the primary, the companion's first hop and every advisory voice (`_adv_budget_estimate`) and compares that sum with `budget_cents`.
**File:** `head/.loa.config.yaml.example:1624-1632` and `:1690`; `head/.claude/scripts/adversarial-review.sh:3866-3900`, `:4322-4340`.
**Suggestion:** Rewrite both comments (and `reviewing-code/resources/ADVERSARIAL-REVIEW.md`, which still says "`budget_cents` is a per-voice cap") to say the estimate sums every planned voice at its catalog price. Say in the CHANGELOG that a budget tuned for one voice may now refuse (exit 4) with two: at the catalog rates printed by `-m loa_cheval.metering.pricing` here, `gpt-5.5-pro` + `claude-headless` on a 1 MB diff is ~2.6× the single-voice fixed-rate estimate.
**Benefit:** Operators reading the example will otherwise debug `budget_exceeded` against a comment that says the companion is free.

### 2. Locality — the `local` label is never checked against the endpoint

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116` — locality is derived from the `dispatch_group` label alone; nothing in `validate_providers` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143-181`) requires a `dispatch_group: local` model's provider endpoint to be the opt-in host or any IP-literal/localhost, although the comment at `head/.claude/scripts/adversarial-review.sh:4266` and the docstring at `head/.claude/scripts/lib/hop-locality.py:21-22` promise "IP-literal or localhost endpoint, no DNS" for a local hop.
**File:** `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143-181`.
**Suggestion:** In `validate_providers`, when any model of a provider is `dispatch_group: local`, require the provider's endpoint host to be an IP literal or `localhost` (reuse `check_insecure_optin` on `split_url(endpoint)[1]`), refusing with a named code; or drop the "no DNS" sentence from both places. A project overlay that sets `providers.openai.models.gpt-5.5.dispatch_group: local` currently plans and records `api.openai.com` as a local hop (verified against the head classifier: `blockbox:silent-model` on `https://llm.example.com` → `local`).
**Benefit:** The posture becomes checkable instead of label-trusting; a typo in a project overlay cannot turn a hosted vendor into a "local" voice.

### 3. Locality — four rule copies, two semantics

- **MEDIUM** (confidence: medium) `head/.claude/scripts/lib/hop-locality.py:116` — `entry.get("dispatch_group") or block.get("dispatch_group")` and `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733` accept a provider-block `dispatch_group: local`; `head/.claude/adapters/cheval.py:541` and `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` read the model entry only. The planner and Bridgebuilder call such a hop local, cheval would build `ModelConfig.dispatch_group=None` (no `TransportPolicy`, MODELINV `hop_locality: hosted`).
**File:** as cited; docs disagree too — `head/.claude/loa/reference/scripts-reference.md:74` says "model entry or provider", `head/.loa.config.yaml.example:818` says "model entry".
**Suggestion:** Dissent DISS-C-001 rated this BLOCKING; downgraded here because `loader._validate_model_auth_metadata` (`head/.claude/adapters/loa_cheval/config/loader.py:1017-1030`) refuses any model entry without its own `dispatch_group`, so a block-level-only provider never loads in cheval — the run fails at dispatch, late but closed. Still: pick one rule (model entry only is what the loader enforces), make `hop-locality.py`, `isLocalVoice` and the two docs say it, and have `modelinv.hop_locality_of` and `_transport_policy` share one helper so the audit field and the transport decision cannot drift (DISS-C-003).
**Benefit:** One rule, one place; the "ONE implementation" promise the endpoint rule keeps is kept for locality too.

### 4. Reference — wrong exit-code contract

- **MEDIUM** (confidence: high) `head/.claude/loa/reference/scripts-reference.md:74` — documents `lib/hop-locality.py` as "0 local; 1 hosted or unresolved; 2 usage"; the script prints one TSV row per hop and always exits 0 (`head/.claude/scripts/lib/hop-locality.py:154-163`; verified: hosted and unresolved hops, and an unreadable config, all exit 0). A caller following the row would treat every hop as local.
**Suggestion:** "0 with one `<hop>\t<provider>\t<local|hosted>\t<reason>` row per hop (config failures are rows with `config_unreadable`); 2 usage".

### 5. Advisory voices — the promotion refusal misses the default companion chain

- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4296` — the "cannot be counted" check compares advisory aliases only with `CONF_COMPANION_CHAIN_ANTHROPIC`/`_OPENAI` (operator-configured chains); with no `companion_chain` block the default chain (`claude-headless` on a keyless host) is not consulted, so `advisory_voices: [claude-headless]` runs the same model as the counted companion and again as advisory — the exact double-count D-7.4 refuses when the chain is spelled out (ADV-5).
**Suggestion:** Compare against `_companion_chain "$(_companion_family …)"` (the resolved chain) rather than the raw config keys.

### 6. Flatline — locality falls open to `hosted` when the config cannot be read

- **LOW** (confidence: high) `head/.claude/scripts/flatline-orchestrator.sh:707` — `flatline_locality_mode` echoes `hosted` when `$CONFIG_FILE` is missing or `yq` is absent; `adversarial-review.sh:238-250` treats an unreadable value as `invalid` and refuses. A `local_voices` operator whose config path is wrong gets hosted dispatch without a word.
**Suggestion:** Return `invalid:unreadable` on the missing-file/missing-yq branch under the same `case` the dissent uses.

### 7. OpenAI adapter — `health_check` applies the policy on opt-in only

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:858` — `health_check` builds a `TransportPolicy` only when `allow_insecure_endpoint` is set; `_transport_policy` (`:217-223`) also applies it for `dispatch_group: local`. An https local model with no opt-in probes through the proxy env that `complete()` ignores.
**Suggestion:** Call the same `_transport_policy` helper (needs a model; probe the first `dispatch_group: local` model, or pass the policy in).

### 8. Thinking strip — an unterminated `<think>` is a successful empty answer

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/openai_streaming.py:75-77` — a leading `<think>` with no `</think>` moves the whole body to `thinking` and returns `content == ""` with no error (verified: `'<think>unterminated reasoning' -> ('', …, True)`). A reasoning model that hits `max_tokens` inside its trace reads as a clean empty response; the caller's empty-content handling, not a typed truncation, decides what happens.
**Suggestion:** Surface `finish_reason == "length"` + stripped-to-empty as the existing "thinking spent the budget" flag so the repair/fallback chain names the cause.

### 9. Schema rejection — substring heuristic retries on the operator's own error

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111` — any HTTP 400 whose body mentions `response_format` or `json_schema` triggers the one retry without the schema, including hosted OpenAI's 400 for an invalid strict schema (which names `response_format`); the misconfiguration degrades to an unenforced voice with only a telemetry bit.
**Suggestion:** Narrow to the compat servers' "unknown/unsupported parameter" phrasing, or log the 400 body head at WARN so the operator sees why enforcement was dropped.

### 10. Budget gate — a malformed project config looks like "no catalog price"

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/metering/pricing.py:591` + `head/.claude/scripts/adversarial-review.sh:3875` — a YAML error in `.loa.config.yaml` makes the CLI exit 2 (`cannot read the catalog`, stderr discarded by the caller), `rows=""`, and every voice falls back to 10/30 with "no catalog price for <alias>" — a misleading reason for a `budget_exceeded`.
**Suggestion:** Distinguish "CLI failed" (one WARN naming the exit code) from "alias not priced" in `_adv_budget_estimate`.

### 11. SURGICAL — unrelated prose edits in two skill files

- **LOW** (confidence: high) `head/.claude/skills/reviewing-code/SKILL.md:211` (dropped "(paths only)"), `:246`, `:254`, `:262`, and `head/.claude/skills/auditing-security/SKILL.md:159` ("(do this first)" removed), `:177`, `:238`, `:246` — wording trims with no relation to advisory voices beyond the one-line `advisory_voices[].findings` sentence each file needed (ADV-8).
**Suggestion:** Keep the two needed sentences; move the trims to the prompt-budget work they belong to, or say in the PR why they ride along.

### 12. Complexity

- **LOW** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1428` — `_probe_configured` is 117 lines (describe → validate URL → auth → curl → classify); `head/.claude/skills/bridgebuilder-review/resources/config.ts:542` — `loadTrustedConfig` is 108 lines (mode/source resolution, parse, head-only refusal, locality, exit key). Both are linear and commented, nesting ≤ 3, no duplicate blocks; `_adv_advisory_block` (58 lines) is one jq program with a shell frame.
**Suggestion:** Split `_probe_configured` at the auth decision and `loadTrustedConfig` at "resolve source text" / "derive view"; `SIMPLICITY[shrink]` only. The new code is otherwise lean — one classifier, one pricing CLI, no new dependency. `net: -40 lines possible`.

### 13. Documentation and report

- **LOW** (confidence: high) `head/README.md:22` — the "Unreleased" bullet links to `CHANGELOG.md`, but no CHANGELOG entry is part of this change (the sprint touches 80 files, none of them the CHANGELOG), and `reviewer.md` has no `## AC Verification` walkthrough (waived by `pr/REVIEW-INSTRUCTIONS.md` for this workspace).
**Suggestion:** Add the sprint-257 CHANGELOG rows (Bridgebuilder exit 3 / entry.sh exit 4 and the budget-gate change are operator-visible) and an AC walkthrough citing `file:line` per FR-7/FR-8 criterion.

---

## Cross-Model Observations

Adversarial review envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — `status: reviewed`, `voices_planned: 2`, `voices_succeeded: 2` (`codex-headless`, `claude-headless`), `companion_voice.counted_as: independent_voice`, `rejected_count: 0`, hallucination filter applied (0 downgraded).

| Dissent id | Severity | Triage |
|------------|----------|--------|
| DISS-001 (`base.py:http_post` default branch for non-OpenAI providers) | BLOCKING | Confirmed — Changes Required §1 |
| DISS-C-001 (`cheval.py:541` reads model-level `dispatch_group` only) | BLOCKING | Confirmed as an inconsistency, downgraded to Observation §3: the loader refuses a model entry without `dispatch_group`, so the block-level-only case never dispatches |
| DISS-C-002 (`validate_providers` admits opt-in for every type) | ADVISORY | Same defect as DISS-001 — folded into §1 |
| DISS-C-003 (`modelinv.hop_locality_of` is a second rule copy) | ADVISORY | Observation §3 |
| DISS-C-004 (`stale_catalog` and ledger readers) | ADVISORY | Not a defect: `cost-report.sh:424-438` and `cost-budget-enforcer-lib.sh:1228` count only `unknown`/absent as unpriced; `rollup.py:121` was updated. `reprice.py:116` still stamps `config` on re-priced rows (cosmetic) |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` is zero bytes.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required §1 and §2 above |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" | Pass | 2 high, 4 medium, 9 low, each with `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED — see trailer |
| Advisory voices never counted (ADV-1..9) | Pass | Block isolated; `verdict-derive.sh` reads top-level `findings`/`metadata` only |
| `local_voices` refuses hosted hops across the dissent, Flatline, Bridgebuilder **and the probe** | Fail | Probe has no gate — Changes Required §2 |
| Request-time rules for an opted-in / local hop (D-7.2) | Fail | OpenAI adapter only — Changes Required §1 |
| Bridgebuilder trusted config + exit 3 / entry.sh exit 4 | Pass | `config.ts`, `run-outcome.ts`, all four shell callers, `dist/` in sync |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (keyless path sends no header; probe never prints a key)
- [x] Input validation and sanitization present at the opt-in / endpoint boundary (verified against the head validator with bypass-shaped URLs)
- [ ] Authentication/authorization correct — see Changes Required §1 (transport policy not applied for non-OpenAI adapters)
- [x] No SQL/XSS injection vulnerabilities (n/a); jq operands are validated scalars, hop names regex-bounded
- [x] Dependencies secure (no new dependency; `idna` made lazy and fail-closed)
- [x] Error messages don't leak sensitive data (advisory `error` cut to 200 chars, control bytes stripped)

---

## Code Quality Summary

**Strengths:**
- One endpoint rule, loaded by path, with a case table run through both entry points.
- Advisory voices isolated by construction and pinned by a byte-identity test (ADV-2).
- Fail-closed classifier; `hosted` default is the rollback.
- Every exit-3 caller tested with a stub `entry.sh`; `entry.sh` moved its preflight to exit 4.

**Areas for Improvement:**
- Enforce the same rule at load that the docs promise at request time (§1, Observations §2, §3).
- Documentation that names a control must point at code that has it (§2, Observations §1, §4).

---

## Next Steps

1. Address Changes Required §1 and §2.
2. Decide on Observations §1–§4 (doc/code reconciliation); the rest are at your discretion.
3. Run the bats suites (`adversarial-review-*.bats`, `flatline-locality.bats`, `bb-exit-degraded-callers.bats`, `model-health-probe-configured-provider.bats`) and the adapter pytest set; add the per-adapter policy test and the probe locality case.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC walkthrough and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T15:03:01Z"} -->
