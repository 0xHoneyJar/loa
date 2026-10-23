# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task review-r21)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` — sprint-257 (cycle-129): advisory open-weight voices, `local_voices` posture, Bridgebuilder trusted configuration and exit codes, E2E (80 files, +6583/−198)
**Review verdict (Phase 0):** `engineer-feedback.md` reads CHANGES REQUIRED (2 HIGH), not "All good". The task order to run this audit stands; this audit therefore confirms the review's findings independently rather than assuming approval. **Prerequisite deviation recorded.**

**DEGRADED_SECURITY_REVIEW** — the Phase 1C dissent completed with the companion `claude-headless` as `counted_as: sole_voice` (`verdict_quality.status: FAILED`, 1 of 4 planned voices; the OpenAI and Google primaries failed `api_failure` for want of credentials on this host). Its findings are treated as one voice's advisory input, each triaged against the head code below.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change is substantial and most of its security mechanics hold under execution: the one endpoint rule is enforced on both the cheval and bash paths, the request-time transport policy (no proxy environment, no redirects, declared path prefix) is correct for the OpenAI-type adapter and proven against a real loopback stub on both httpx and urllib, Bridgebuilder's trusted-configuration precedence is argv-safe and fail-closed, every jq operand carrying model text travels by `--arg`/`--slurpfile`, and the advisory-voice block is byte-neutral on the counted envelope. The six new pytest files pass on an overlay of the head files (123 passed, reproduced here).

Two defects block merge, both confirmed by independent execution in this audit. First, the `local_voices` posture is enforced by three implementations that read `dispatch_group` differently: the shell planner and Bridgebuilder accept a provider-level declaration, cheval and the MODELINV audit chain read the model entry only, so a provider-level-only declaration is planned local, dispatched hosted and recorded `hop_locality: hosted`. Second, the dissent budget gate now compares the sum of every planned voice against `budget_cents`, which the shipped example still documents as a cap on one call; a dry run of this PR's own diff under the configured 200c is refused at 955c before any dispatch, which is why this audit's dissent had to run with `--budget 1200`. Four MEDIUM findings follow the same theme of a control narrower than its documentation: the insecure-endpoint opt-in is admitted for provider types whose adapters apply no transport policy, the `local` label is never checked against the endpoint it governs, the 400 heuristic lets a server downgrade structured output, and the Bridgebuilder trust contract claims protection on a PR-head checkout that only two flags receive.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 10 |

**Overall Risk Level:** MODERATE (rubric 3.5/5) — the verdict is forced by the HIGH count, not by the score.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Locality: planner, Bridgebuilder and cheval disagree on a provider-level `dispatch_group`

**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-AZ (authorization of the hop under the posture)
**File:** `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:730`; versus `head/.claude/adapters/cheval.py:541`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221`, `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`
**Issue:** The planner reads `group = entry.get("dispatch_group") or block.get("dispatch_group") or ""` (hop-locality.py:116) and Bridgebuilder's `isLocalVoice` falls through to `if (decl.dispatchGroup !== undefined) return decl.dispatchGroup === "local"` (config.ts:730); its test pins the provider-level case (`trusted-config.test.ts:303-323`, `lan-box` kept). cheval builds `dispatch_group=model_data.get("dispatch_group")` from the model entry only (cheval.py:541); `_transport_policy` tests `allow_insecure_endpoint` or the MODEL's `dispatch_group` (openai_adapter.py:221); `hop_locality_of` returns `"local" if entry.get("dispatch_group") == "local" else "hosted"` (modelinv.py:476). The planner's own docstring (hop-locality.py:15) and `multi-model-reference.md:102` state two different rules.
**Impact:** Under `hounfour.locality: local_voices`, a provider declared `dispatch_group: local` at the block (model entries without their own value; an https DNS endpoint needs no opt-in) is planned local by the dissent, Flatline and Bridgebuilder, refused nowhere, and dispatched by cheval with no `TransportPolicy`: httpx `trust_env=True` honours `HTTPS_PROXY`/`ALL_PROXY`, urllib follows 3xx. The prompt can leave the host under the one posture whose purpose is that it cannot, and the MODELINV row says `hop_locality: hosted`, contradicting the plan and the envelope's `locality.refused` list. The dissent reached the same defect independently (DISS-C-001).
**Fix:** Choose one reading and make all five sites agree. (a) Model-entry only: drop `block.get("dispatch_group")` at hop-locality.py:116 and the provider-level and every-model branches of `isLocalVoice`; correct the docstring at hop-locality.py:15. Or (b) provider-level is canonical: `_build_provider_config` falls back to `prov.get("dispatch_group")` when the entry has none, and `hop_locality_of` does the same. Add a provider-level-only case to `adversarial-review-locality.bats`, `trusted-config.test.ts` and `test_openai_local_hop_e2e.py` asserting the same answer.
**Reference:** CWE-668 Exposure of Resource to Wrong Sphere https://cwe.mitre.org/data/definitions/668.html; CWE-778 Insufficient Logging https://cwe.mitre.org/data/definitions/778.html (the audit chain records the wrong locality).

### [HIGH-002] Budget gate: the sum over every planned voice is compared against a documented per-call budget; the mandatory dissent refuses under shipped defaults

**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-AV (availability of a mandatory security gate)
**File:** `head/.claude/scripts/adversarial-review.sh:4335` (`if [[ $estimated_cost_cents -gt $budget ]]`), `:3866` (`_adv_budget_estimate`), `:4321-4329` (`_bvoices` = primary + companion first hop + each advisory voice); `head/.loa.config.yaml.example:1624` and `:1690` ("Gate on ONE dissent call's pre-dispatch cost estimate")
**Issue:** Reproduced in this audit, not inferred. A dry run of this PR's own diff with this workspace's configured `budget_cents: 200`:
```
[adversarial-review] budget: estimate 955c over 2 planned voice(s) (primary gpt-5.5-pro 718c, companion claude-headless 237c)
ERROR: Estimated cost (955c) exceeds budget (200c)
→ exit 4, {"metadata": {"status": "budget_exceeded", "estimated_cents": 955, "budget_cents": 200, ...}}
```
Two changes compound: catalog prices replace the fixed 10/30 USD per Mtok (intended, BUD-1) and the estimate sums across voices (BUD-4). Neither the example default, its two comments, the README migration notes nor the reference docs changed with the contract. The workspace's own `ADVERSARIAL-REVIEW.md` resource still states "`budget_cents` is a per-voice cap".
**Impact:** Phase 2.5 of `/review-sprint` and Phase 1C of `/audit-sprint` are mandatory when the gates are enabled; `adversarial-review-gate.sh` blocks `COMPLETED` without the envelope. An operator on the shipped config sees the security gate refuse ordinary diffs with no explanation of what changed; this audit itself needed `--budget 1200` to obtain a dissent at all.
**Fix:** Decide the contract and ship it coherently. Either compare per voice (the maximum single-voice estimate, or each voice, against `budget_cents`; keep the sum in `estimate_voices`), or make `budget_cents` a run total and raise the example defaults so the shipped primary plus companion admit what they admitted before, rewrite `.loa.config.yaml.example:1624` and `:1690`, and add a README/CHANGELOG migration line. Name the semantics in the envelope (`budget_semantics: per_voice|total`) and in BUD-4's title.
**Reference:** CWE-693 Protection Mechanism Failure https://cwe.mitre.org/data/definitions/693.html; OWASP A05:2021 Security Misconfiguration https://owasp.org/Top10/A05_2021-Security_Misconfiguration/.

---

## Medium Priority Issues

### [MED-001] Insecure-endpoint opt-in is admitted for provider types whose adapter applies none of the promised request-time rules

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** SEC-CI
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:153-156` (`validate_providers` → `check_endpoint(endpoint, optin, name)` for every non-CLI type); `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-223` (the only `TransportPolicy` constructor) and `:858` (health check); `anthropic_adapter.py:334` and `google_adapter.py` (unchanged, `http_post_stream`/`http_post` with no `policy`)
- **Issue:** Executed through the head loader: `{type: anthropic, endpoint: "http://10.0.0.5:8080", allow_insecure_endpoint: "10.0.0.5"}` loads cleanly (`optin=10.0.0.5`). The example at `.loa.config.yaml.example:1226-1232` promises "for this provider cheval ignores proxy environment variables, refuses redirects and keeps every request under the declared endpoint path"; only `OpenAIAdapter` does so. Confirmed by cross-model review (DISS-C-002).
- **Impact:** A plaintext endpoint on a non-OpenAI provider type runs with proxy variables honoured and, on the urllib fallback, redirects followed with the `x-api-key` header intact — none of the compensating controls the opt-in is conditioned on.
- **Fix:** Refuse `allow_insecure_endpoint` at load unless `type` is `openai` or `openai_compat` (named reason `ENDPOINT-OPTIN-UNSUPPORTED-TYPE`), or build the policy in `ProviderAdapter` so every adapter's `http_*` call receives it.
- **Reference:** CWE-319 https://cwe.mitre.org/data/definitions/319.html; CWE-601 https://cwe.mitre.org/data/definitions/601.html; OWASP A10:2021 https://owasp.org/Top10/A10_2021-Server-Side_Request_Forgery_%28SSRF%29/.

### [MED-002] The `local` label is never checked against the endpoint it governs

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** SEC-AZ
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143-181` (`validate_providers` requires `dispatch_group` for keyless providers but never relates `local` to the endpoint); `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`
- **Issue:** Executed: a provider `{type: openai_compat, endpoint: "https://llm.example.com/v1", keyless: true, models: {m1: {dispatch_group: local, ...}}}` loads, and `hop-locality.py` prints `lanbox:m1  lanbox  local  dispatch_group=local`. Under `local_voices` that hop is planned, dispatched (the `TransportPolicy` restricts proxies, redirects and path, never the destination) and recorded `hop_locality: local`.
- **Impact:** The posture's single control is a self-declared label. A copied example or a mislabelled hosted provider sends prompts to a public host while every artefact — plan log, envelope, MODELINV — says local.
- **Fix:** At load, warn (or refuse under `local_voices`) when a `dispatch_group: local` model's provider endpoint is not loopback, RFC1918 or the provider's opt-in host; record the endpoint class beside `hop_locality` in MODELINV so the chain can be audited without the config.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision https://cwe.mitre.org/data/definitions/807.html; CWE-778 https://cwe.mitre.org/data/definitions/778.html.

### [MED-003] The 400 heuristic lets any server downgrade structured output and receive the prompt twice

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** SEC-IV
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111` (`_names_response_format`: `return "response_format" in text or "json_schema" in text`), `:191-204` (one retry without the schema), `:441` (`"strict": True` always sent)
- **Issue:** Any HTTP 400 whose body mentions either token is read as "server does not support structured output". OpenAI's strict-mode validation errors ("Invalid schema for response_format ...: 'additionalProperties' is required to be supplied and to be false") match too, and a server controls both status and body. The downgrade is recorded (`schema_rejected_by_server: true`, `schema_enforced: false`) and a WARN is logged; nothing else tells the operator who declared `structured_json` that enforcement was lost. `test_the_heuristic` (`test_openai_chat_schema.py:183-187`) has no strict-mode negative case. Review Observation §1 and dissent DISS-C-004 agree.
- **Impact:** Silent loss of server-side schema enforcement on every hand-written schema that is not strict-clean; a hostile server can force the unenforced path and sees the full prompt twice.
- **Fix:** Match on the error object's `param`/`code` fields rather than the whole body; treat "invalid schema"/"additionalProperties"/"required" phrasings as a schema defect (raise, or retry once with `strict: false`); keep the drop-the-schema retry for "unsupported"/"unknown field" bodies; add the strict-mode message as a negative case.
- **Reference:** CWE-757 Selection of Less-Secure Algorithm During Negotiation https://cwe.mitre.org/data/definitions/757.html; CWE-754 https://cwe.mitre.org/data/definitions/754.html.

### [MED-004] The Bridgebuilder trust contract claims protection on a PR-head checkout that only two flags receive

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** SEC-AZ / documentation
- **File:** `head/.claude/skills/bridgebuilder-review/SKILL.md:118` ("the provider, locality and exit keys follow the trusted-source precedence below even when the checkout is a PR head"); `head/.claude/skills/bridgebuilder-review/resources/config.ts:684-686` (only `keylessOnlyInHead` / `insecureOnlyInHead` are refused)
- **Issue:** Every Bridgebuilder voice dispatches through cheval, whose loader reads the working tree's `.loa.config.yaml` — on a PR-head checkout, the head's. `validate_declared_endpoint` admits any https DNS host for a declared provider (by design, `endpoint-validator.py:1080-1086`). The head therefore still controls the `endpoint` (and `aliases`) of a built-in provider such as `openai`, and cheval would send that provider's credential to it. The exposure predates this PR (#1050 records that no PR-head checkout is shipped) and the PR does not open it; the PR's new sentence asserts protection in exactly that scenario, which the mechanism does not provide.
- **Impact:** False assurance in the trust contract: an operator who reads SKILL.md:118 and adopts a PR-head checkout believes provider declarations come from the trusted source only.
- **Fix:** Scope the sentence to what is refused (`keyless` and `allow_insecure_endpoint` declared only in the head), or pass the trusted provider view to cheval (a trusted-config path env var the loader prefers under `--pr`) so endpoints and aliases follow the same precedence.
- **Reference:** CWE-1059 Insufficient Technical Documentation https://cwe.mitre.org/data/definitions/1059.html; CWE-693 https://cwe.mitre.org/data/definitions/693.html.

---

## Low Priority Issues

### [LOW-001] Two readings of a keyless literal
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:482` (`literalAuth`: any `auth` string without `{env:`) vs `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50` (`KEYLESS_AUTH_LITERALS = frozenset({"local"})`) — **Confidence:** high
- **Issue:** `auth: "sk-…"` in trusted config is keyless to Bridgebuilder and a Bearer credential to cheval.
- **Fix:** Share the literal set.

### [LOW-002] Empty endpoint audited as a CLI hop
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:445` — **Confidence:** high
- **Issue:** `destination_for` returns `{host: cli-subprocess, scheme: cli}` for any provider with no `endpoint`, not only `*-headless`/`kind: cli`.
- **Fix:** Return `unknown`/`unknown` for a non-CLI provider.

### [LOW-003] `price_source` schema admits traversal the test refuses
- **File:** `head/.claude/schemas/model-config.schema.json:142` (`^(https://\S+|docs/\S+)$`) vs `test_catalog_pricing_provenance.py:139` — **Confidence:** high
- **Fix:** Add `(?!.*\.\.)` or name the test as the authority.

### [LOW-004] Startup line names a working-tree source that was not read
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:617` — **Confidence:** medium
- **Issue:** `source = "working-tree"` is set before `readWorkingTree` may return `undefined`.
- **Fix:** `source = "none"` when `text` is undefined.

### [LOW-005] `localhost` opt-in contradicts the "never resolved through DNS" claim
- **File:** `head/.claude/scripts/lib/endpoint-validator.py:1047`; `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:6` — **Confidence:** low
- **Issue:** `localhost` is resolved by the OS resolver (`/etc/hosts`, search domains); the IP-literal claim is true, the `localhost` claim is not.
- **Fix:** Drop `localhost` from the opt-in or correct the sentence.
- **Reference:** CWE-350 https://cwe.mitre.org/data/definitions/350.html.

### [LOW-006] Unterminated `<think>` empties content with no marker
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_streaming.py:75` — **Confidence:** medium
- **Issue:** The whole remainder becomes `thinking`; qualification sees an empty answer indistinguishable from a malformed one (tested as intended).
- **Fix:** Record `thinking_truncated: true` so the repair loop can tell them apart.

### [LOW-007] Reference documents a probe locality refusal that does not exist, and exit codes the classifier does not return
- **File:** `head/.claude/loa/reference/scripts-reference.md:73` ("refuses a hosted probe under `local_voices`") and `:74` ("0 local; 1 hosted or unresolved; 2 usage"); `head/.loa.config.yaml.example:818` ("Bridgebuilder and the health probe is planned only on a provider whose model entry says `dispatch_group: local`") — **Confidence:** high
- **Issue:** `head/.claude/scripts/model-health-probe.sh` contains no locality code (grep: no match). Executed `hop-locality.py` with an unresolved hop and two hosted hops: exit 0 with three TSV rows; `main()` always returns 0.
- **Impact:** A documented security control that is absent; an exit-code contract a caller could wrongly rely on.
- **Fix:** Implement the probe refusal or remove the two claims; correct the row to "always 0; column 3 carries the verdict".
- **Reference:** CWE-1059 https://cwe.mitre.org/data/definitions/1059.html.

### [LOW-008] `describe-provider` and the probe log print the resolved endpoint
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:200` (`"endpoint": prov.get("endpoint") or ""`); `head/.claude/scripts/model-health-probe.sh:1505` (`log_info "probing configured provider $provider at $url…"`) — **Confidence:** medium
- **Issue:** Executed: the head loader resolves a templated endpoint (`https://{env:AUDIT_HOST}/v1`) to a plain `str` before `validate_providers`. The helper, documented as never carrying a secret value, emits that string verbatim; an operator who templates a gateway token into the endpoint path has it printed and logged. Dissent DISS-C-005.
- **Fix:** Emit scheme, host and port from `split_url` (or the raw template) instead of the resolved endpoint.
- **Reference:** CWE-532 https://cwe.mitre.org/data/definitions/532.html.

### [LOW-009] `--provider <configured name>` can never probe a hosted custom provider
- **File:** `head/.claude/scripts/model-health-probe.sh:1475` (validation against `lib/allowlists/loa-providers.json`), header `:21-22` — **Confidence:** high
- **Issue:** Executed: `https://myco.openai.azure.com/openai/v1/models` through the probe's allowlist → `ENDPOINT-NOT-ALLOWED`. Only an opted-in loopback/RFC1918 provider is probeable; the header promises any configured `hounfour.providers` name. Fail-closed, so a functional defect, not an exposure.
- **Fix:** Validate a configured provider with `validate_declared_endpoint` semantics, or document the limit.

### [LOW-010] `health_check` and `_transport_policy` decide "policy applies" differently
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:858` vs `:221` — **Confidence:** high
- **Issue:** The health check applies the policy only for an opted-in provider; completions also apply it for a `dispatch_group: local` model. A local-labelled https provider without an opt-in is health-checked with proxies honoured.
- **Fix:** Apply the policy in `health_check` when any declared model is `local`, or document the difference.

---

## Observations

- **Review demotions:** the review trailer records `excluded: 0`; nothing to confirm. `excluded_confirmed: 0`.
- **Not introduced by this PR (cross-model, DISS-C-003):** the urllib fallback for HOSTED providers keeps `urllib.request.urlopen` (`head/.claude/adapters/loa_cheval/providers/base.py:332`, `:414`, `:620`), whose default handler follows 3xx and re-sends the `Authorization` header; httpx does not follow redirects by default, so the two transports diverge for hosted hops. Pre-existing behaviour; the PR is where the safe opener was added and deliberately scoped to the policy path. Suggest using `_policy_urllib_opener()` unconditionally (redirects are already refused on the httpx path).
- **Advisory voices (D-7.4):** `_adv_advisory_walk` runs `process_findings`, including the repair loop, in one backgrounded subshell per advisory voice (`adversarial-review.sh:3915-3985`). Globals are per-subshell, CLI serialisation is a cross-process flock, ledger writers hold their own flock, sidecars are disabled (`LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1`), and the block is assembled from files. No shared-state race found; the one wall clock and the `_adv_reap_advisory` on every exit path are correct. Advisory findings remain untrusted model text and are surfaced only under `advisory_voices[]`, as the skill texts now say.
- **Bridgebuilder exit 3:** all in-tree callers of `entry.sh` were updated (`spiral-harness.sh:697-712`, `dispatcher.sh:75-91`); `session-cap-fanout.sh` only generates YAML naming the dispatcher. `entry.sh` moves its missing-dependency exit to 4. No caller still reads 3 as a failure.
- **Opt-in branch of the validator (Step 1.5, `endpoint-validator.py:1146-1176`):** userinfo, port, path and control bytes are checked for the opted-in host; IDN and the IP-literal block tables are not needed for an IP literal or `localhost`. Non-canonical spellings (`127.1`, `0x7f000001`, `[::ffff:127.0.0.1]`) do not equal the canonical opt-in host and are refused — fail-closed.
- **`TransportPolicy.check_url`** (`base.py:128-142`): string-based traversal check; the request URL is adapter-built (`f"{endpoint}/chat/completions"`), so no attacker-controlled path reaches it. Not a finding.
- **Repro notes for the fixer:** the budget-gate dry run (second blocking finding) is `bash .claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-N --diff-file pr/head.diff --dry-run --json` under the shipped `budget_cents`; the opt-in and local-label loads (first two medium findings) are three-line `hounfour.providers` blocks fed to `load_config(project_root=…)`.

## Cross-Model Security Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `status: reviewed`, `metadata.model: gemini-3.1-pro` (configured primary; the three HTTP primaries `api_failure`, the primary chain ceded `claude-headless` to the companion), `companion_voice.counted_as: sole_voice`, `verdict_quality.status: FAILED` (1/4). Run with `--diff-file pr/head.diff --budget 1200` (see the second blocking finding for why the configured 200c refuses). Five findings, none CRITICAL/HIGH, each triaged:

- **DISS-C-001** (MEDIUM, `cheval.py:541`) — real; confirmed, and it is the first blocking finding above (locality) on the proxy/redirect scenario. Its references to `endpoint_policy.py` symbols `_local_labels`, `hop_is_local`, `validate_local_fallbacks` name code absent from `pr/head` (grep finds none; they belong to this workspace's newer framework files the model was shown as context) and are discounted.
- **DISS-C-002** (MEDIUM, `validate_providers`) — real; confirmed by execution (first medium finding, opt-in on non-OpenAI types).
- **DISS-C-003** (MEDIUM, `base.py:332`) — accurate but pre-existing; recorded under Observations, not tallied as this PR's defect.
- **DISS-C-004** (LOW, `_names_response_format`) — real; folded into the third medium finding, the 400 heuristic (the review had already rated it MEDIUM).
- **DISS-C-005** (LOW, `describe_provider`) — real; confirmed by execution that the endpoint is resolved to a string at load (eighth low finding).

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` stands beside the envelope.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this evaluation workspace (no `/implement` phase ran); documentation coherence was verified manually against the head files. Findings: `scripts-reference.md:73-74` and `.loa.config.yaml.example:818` describe a probe control and exit codes that do not exist (LOW-007); `.loa.config.yaml.example:1624`/`:1690` describe the previous budget contract (HIGH-002); `SKILL.md:118` overstates the trusted-config control (MED-004); `hop-locality.py:15` and `multi-model-reference.md:102` state two rules for `local` (HIGH-001). The README "What's new" block, the Bridgebuilder exit-code table and the two skill texts ("read `advisory_voices[].findings` as advisory input") match the code. No secrets or internal URLs in docs or comments. Security-relevant changes (opt-in rule, transport policy, keyless, trusted config) carry security documentation.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.4/5 | IV:4 AZ:3 CI:3 IN:5 AV:2 |
| Architecture | 3.6/5 | MO:3 SC:4 RE:4 CX:3 ST:4 |
| Code Quality | 3.8/5 | RD:4 TC:4 EH:4 TS:4 DC:3 |
| DevOps | 3.6/5 | AU:4 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | not applicable |
| **Overall** | **3.5/5** | security weighted highest |

Machine-parseable findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`. Working file: `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (probe and loader print env var NAMES; `describe_provider` carries no auth value — but see LOW-008 for the resolved endpoint)
- [x] Input validation at trust boundaries (opt-in host validated on both paths; `isSafeRefName`; `_CONFIGURED_NAME_RE`; `auth_env` regex before indirect expansion; advisory alias regex; price regex)
- [ ] Authorization/posture consistent — **no**: HIGH-001, MED-002, LOW-010
- [x] No injection vectors (jq via `--arg`/`--argjson`/`--slurpfile`; `execFileSync` argv arrays; yq splices only the gate's own config key)
- [x] Error handling does not leak sensitive data (allowlisted/truncated provider lines; budget refusal names aliases only)
- [x] Tests cover security paths (123 pytest on the overlay: redirect refused, proxy env ignored, path prefix, origin match, keyless sends no credential, cross-provider isolation; bats suites per the review's run)
- [ ] Dependencies/transport consistent across adapters — **no**: MED-001
- [x] `idna` made optional with a fail-closed refusal; no new runtime dependency

### Evidence gathered by execution in this audit

| Check | Result |
|-------|--------|
| `pytest` — 6 new test files, head overlay (`.run/audit-ov`) | 123 passed |
| `adversarial-review.sh --dry-run` on `pr/head.diff`, configured 200c | exit 4, `budget_exceeded`, 955c (718c + 237c) |
| `adversarial-review.sh --type audit … --budget 1200` | envelope written, sole voice, 5 findings |
| head loader: `type: anthropic` + `http://10.0.0.5:8080` + opt-in | loads (MED-001) |
| head loader: `dispatch_group: local` on `https://llm.example.com/v1` | loads; classifier says `local` (MED-002) |
| head loader: templated endpoint `https://{env:…}/v1` | loads, resolved to `str` (LOW-008; no regression) |
| validator with the probe allowlist: Azure https URL | `ENDPOINT-NOT-ALLOWED` (LOW-009) |
| `hop-locality.py` with unresolved + hosted hops | exit 0 (LOW-007) |
| `grep locality model-health-probe.sh` (head) | no match (LOW-007) |

### Not verified here

- Bridgebuilder TypeScript tests and `dist/` parity with `.build-manifest.json` (no `node_modules`, no network).
- `emit_endpoint_validator_ts --check` (no `jinja2`).
- bats suites were not re-run in this audit; the review's run (all pass on an executable filesystem) is the reference.

---

## Next Steps

1. Resolve the `dispatch_group` reading across `hop-locality.py`, `config.ts`, `cheval.py`, `openai_adapter.py` and `modelinv.py`; add the provider-level-only case to each suite (HIGH-001).
2. Decide the `budget_cents` contract, align the example comments and defaults, add the migration line (HIGH-002).
3. Refuse or police the opt-in for non-OpenAI provider types; cross-check `local` against the endpoint; narrow the 400 heuristic; scope the SKILL.md trust sentence (MED-001..004).
4. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:12:00Z"} -->
