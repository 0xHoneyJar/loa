# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff` — sprint-257, cycle-129)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)
**Task:** review-r21

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change adds a per-provider insecure-endpoint opt-in with request-time transport rules, keyless local providers, structured output and thinking-trace handling on the OpenAI-compatible chat path, advisory dissent voices, a `hounfour.locality: local_voices` posture across four consumers, a trusted-configuration layer for Bridgebuilder on pull requests, and exit code 3 for a degraded Bridgebuilder consensus. The security engineering is mostly careful: one endpoint rule in `endpoint-validator.py` reused by cheval, the bash wrapper and the probe; the opt-in grammar refuses DNS names, link-local, metadata and ULA addresses; the `TransportPolicy` disables proxy env and refuses redirects on both httpx and urllib; subprocess calls use argv (`execFileSync`, `python3 -I … --`); jq receives data via `--arg`/`--slurpfile`; hop names are regex-validated before they reach any command line; `isSafeRefName` guards `git show`; keyless providers put no placeholder credential on the wire.

The verdict turns on the posture feature. `local_voices` is a confidentiality guarantee, and Bridgebuilder's classifier admits a hop the PR's own classifier refuses: a local model whose `fallback_chain` names a hosted provider is kept, and cheval walks that chain inside the call. One HIGH forces CHANGES_REQUIRED under the one-way rule. Two MEDIUMs: the request-time rules are wired into one adapter family while the loader accepts the opt-in for every provider type, and the trusted-configuration layer protects keyless/insecure/locality/exit keys but not the `endpoint`/`auth` that cheval reads from the (attacker-controlled) head checkout, so the layer's stated threat model is only partly covered. Eight LOWs follow.

Prerequisite note: Phase 0 requires `engineer-feedback.md` to say "All good"; it says CHANGES REQUIRED (1 HIGH). The task brief directs the audit to run regardless, so it ran with that deviation recorded here. `grimoires/loa/known-failures.md` is absent (KF-SURFACE warning); triage proceeded without it. `.loa.config.yaml` has no `integrity_enforcement` key; no System-Zone drift check was possible or needed (the diff is read from `pr/`, nothing under `.claude/` was edited).

Scope limits: findings were confirmed by reading the `pr/head/` files and by reproductions recorded in the review; I did not re-run the pytest or bats suites (the review recorded 123 pytest / 45 bats passing on a hybrid tree), and the Bridgebuilder TypeScript tests could not be run (no `node_modules`; `dist/` hashes were verified against sources by the review).

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 8 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Bridgebuilder's `local_voices` check ignores a local model's `fallback_chain`

**Severity:** HIGH (confidence: medium) — Confirmed by cross-model review (DISS-C-003 names the same chain walk)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:726` (`isLocalVoice`), `:739` (`applyLocality`), applied at `head/.claude/skills/bridgebuilder-review/resources/main.ts:486`
**Issue:** `isLocalVoice` decides from `dispatch_group` alone:
```ts
if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined) return decl.modelGroups[modelId] === "local";
if (decl.dispatchGroup !== undefined) return decl.dispatchGroup === "local";
```
The PR's classifier for the dissent and Flatline states the rule the posture needs — `head/.claude/scripts/lib/hop-locality.py:16`: "every hop on the entry's own `fallback_chain` is local by the same rule — cheval walks that chain inside one call" — and returns `hosted` with `fallback_chain_reaches_hosted:<hop>` at `:133` (pinned by bats LOC-7). Bridgebuilder has no equivalent, and `ProviderDecl` (`core/types.ts`) does not even carry the chain. Every Bridgebuilder voice dispatches through cheval (`cheval-delegate.ts` passes `--model provider:model`), and cheval's `chain_resolver.py:92` appends the primary entry's `fallback_chain` to the walk.
**Scenario:** trusted config `hounfour.locality: local_voices`; provider `lan` with model `qwen` `dispatch_group: local`, `fallback_chain: ["openai:gpt-5.5"]`; multi-model voice `lan/qwen`. `applyLocality` keeps the voice. The local server times out or returns 5xx; cheval falls to `openai:gpt-5.5` and the PR diff plus prompt leave the host. `head/.claude/skills/bridgebuilder-review/SKILL.md:163-166` promises the voice is "dropped … and never rerouted"; `head/README.md:30` promises the posture "refuses every hosted hop by name across the dissent, Flatline, Bridgebuilder and the probe".
**Impact:** Confidentiality posture breach for one of four consumers, invisible to the operator (Bridgebuilder prints no refusal; cheval's MODELINV row records the hosted destination after the fact).
**Fix:** Parse `models.<id>.fallback_chain` into `ProviderDecl` and make `isLocalVoice` recurse over the chain against the trusted declarations plus `GENERATED_MODEL_REGISTRY` (any unresolved or non-local hop ⇒ hosted; depth-bounded like `MAX_DEPTH`), or shell out to `hop-locality.py` with the trusted config text. Add a `trusted-config.test.ts` case mirroring LOC-7 (`qwen-leaky` with a hosted chain is refused by name) and one for an undeclared chain hop.
**Reference:** CWE-200 Exposure of Sensitive Information to an Unauthorized Actor — https://cwe.mitre.org/data/definitions/200.html; OWASP A04:2021 Insecure Design — https://owasp.org/Top10/A04_2021-Insecure_Design/

---

## Medium Priority Security Issues

### [MED-001] Request-time transport rules apply to the OpenAI adapter family only

**Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (review-gate DISS-C-004 earlier today; the audit dissent did not repeat it)
**File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-222` (`_transport_policy`); `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:153-156` (`validate_providers`); `head/.claude/adapters/loa_cheval/providers/base.py:270`, `:378`, `:468` (`policy` optional, default `None`)
**Issue:** `endpoint_policy.py:26-28` promises that "for an opted-in provider, or a model whose `dispatch_group` is `local`, the adapter ignores proxy environment variables, refuses HTTP redirects and requires every request URL to stay under the declared endpoint path". `TransportPolicy` is built in exactly one place:
```python
if getattr(self.config, "allow_insecure_endpoint", None) or getattr(model_config, "dispatch_group", None) == "local":
    return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider)
```
`validate_providers` accepts `allow_insecure_endpoint` for any provider that is not a CLI provider (`_is_cli_provider`), regardless of `type`. `anthropic_adapter.py` and `google_adapter.py` (not in the diff) call `http_post`, `http_post_stream` and `http_get` without `policy`. The review reproduced a `type: anthropic` provider with `endpoint: http://127.0.0.1:9100/v1`, `keyless: true`, `allow_insecure_endpoint: "127.0.0.1"` loading cleanly. `hop-locality.py` is likewise provider-type-agnostic, so such a hop is planned as local under `local_voices` and dispatched with proxy env honoured and the urllib fallback following redirects.
**Fix:** Fail closed at load — refuse the opt-in and `dispatch_group: local` for provider types whose adapter does not implement the policy, with a named reason — or construct the policy in `ProviderAdapter` so every adapter type inherits it (and apply it in `health_check` for `dispatch_group: local` providers, which today get it only with an opt-in, `openai_adapter.py:858`). Add a load test for the refused shape.
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-002] Trusted configuration does not cover the `endpoint`/`auth` that cheval reads from the head checkout

**Severity:** MEDIUM (confidence: medium) — pre-existing exposure; the new mitigation leaves it open. Confirmed by cross-model review (DISS-C-005 raised the omitted allowlist on the Python path)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:669-692` (head-only refusal), `:393-398` (`validateApiKeys`); `head/.claude/scripts/lib/endpoint-validator.py:1291-1297` (`_declared_endpoint` skips the host allowlist); `head/.claude/adapters/loa_cheval/config/loader.py:704`; claim at `head/.claude/skills/bridgebuilder-review/SKILL.md:117-118` and `head/README.md:30`
**Issue:** The layer's own comment names the threat — `config.ts:669`: "on a PR the head checkout is attacker-controlled". The trusted view compares only `keyless` and `allow_insecure_endpoint` declarations (`keylessOnlyInHead || insecureOnlyInHead`) and reads `authEnv`/`dispatch_group` for planning. Dispatch happens in cheval, which loads the checkout's `.loa.config.yaml` (`loader.py:704` → `validate_providers` → `validate_declared_endpoint`, which "skips the host allowlist — an operator-declared https host is the operator's choice"). A head that leaves `openai` keyless-false and non-insecure but sets `providers.openai.endpoint: https://attacker.example/v1` (keeping `auth: "{env:OPENAI_API_KEY}"`) passes every trusted-config check (`openai` is a built-in key-mapped provider, `validateApiKeys` marks it valid), and cheval sends the operator's key as `Bearer` plus the diff to that host. The same holds for swapping `auth` to another allowlisted env var.
**Why MEDIUM, not HIGH:** `SKILL.md:116-117` records that the shipped invocation model has no PR-head checkout, the exposure predates this change (the base loader validated nothing), and the PR narrows it (http and private literals are now refused). It is a defect of the new layer's claim ("reads providers only from trusted configuration"), not a new path.
**Fix:** Either carry the trusted provider block into the cheval call (an override config path or env the delegate passes, so cheval dispatches from the trusted declarations), or refuse a voice whose head `endpoint`/`auth` differ from the trusted declaration (extend `ProviderDecl` with endpoint host and auth template and compare in the head-only loop). On the cheval side, WARN at load when a credentialed (`{env:…}`) provider's https host is outside the canonical allowlist unless the declaration comes from a user/system layer. Reword `SKILL.md:117-118` and `README.md:30` to the keys actually covered until then.
**Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html; CWE-200 — https://cwe.mitre.org/data/definitions/200.html

---

## Low Priority Issues

### [LOW-001] Three definitions of "local" for one hop
- **Confidence:** high — Confirmed by cross-model review (DISS-C-004)
- **File:** `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:730-732`; `head/.claude/adapters/loa_cheval/audit/modelinv.py:473-475`; `head/.claude/adapters/cheval.py:541`
- **Issue:** The planners accept a provider-level `dispatch_group: local` (or "every declared model is local"); cheval's loader requires the key on every model entry (`_validate_model_auth_metadata`, reproduced `CONFIG-INVALID` in the review), `ModelConfig.dispatch_group` and `hop_locality_of` read the model entry only. A provider-level-only hop is planned local, refused by cheval at load (nothing leaks), and would be recorded `hosted` in MODELINV — the artifact meant to prove locality after the fact.
- **Fix:** One rule in one place: drop the provider-block rule from both planners (model-level only, matching D-8.0), or make cheval honour it in the loader, `ModelConfig`, `hop_locality_of` and `_transport_policy`.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-002] A credentialed provider may opt into plaintext http; nothing couples the opt-in to `keyless`
- **Confidence:** medium — Cross-model review DISS-C-001
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:151-156`; `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:172-173`
- **Issue:** `validate_providers` never relates `allow_insecure_endpoint` to `keyless`; `complete()` attaches `Authorization: Bearer <key>` unless keyless. A provider with `endpoint: http://192.168.1.20:8080/v1`, `allow_insecure_endpoint: "192.168.1.20"` and `auth: "{env:OPENAI_API_KEY}"` loads and sends a hosted vendor's key in cleartext on the LAN. The example (`head/.loa.config.yaml.example:1235-1237`) invites a keyed local server, so the shape is expected; the silence is not.
- **Fix:** WARN at load (naming the env var) when an http-opted-in provider is not keyless; consider refusing non-local-named env vars on such a provider.
- **Reference:** CWE-319 Cleartext Transmission of Sensitive Information — https://cwe.mitre.org/data/definitions/319.html

### [LOW-003] Schema-rejection heuristic is a substring scan the server controls
- **Confidence:** medium — Cross-model review DISS-C-002
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111` (`_names_response_format`), `:190-204` (retry)
- **Issue:** Any HTTP 400 whose body contains `response_format` or `json_schema` (any field, any case — including an echoed prompt, and this very diff contains both strings) triggers one retry without the schema. A server can thereby run every structured call unenforced and receive the prompt twice. The destination is unchanged and `schema_rejected_by_server` / `schema_enforced=false` are recorded, so damage is limited to a silent downgrade of the output contract.
- **Fix:** Match the structured error (`error.param == "response_format"`, `error.code` naming an unsupported parameter) rather than the whole body; surface the downgrade to the caller, not only MODELINV.
- **Reference:** CWE-757 Selection of Less-Secure Algorithm During Negotiation — https://cwe.mitre.org/data/definitions/757.html

### [LOW-004] Adapter-side endpoint re-check runs only when an opt-in is present
- **Confidence:** medium — Cross-model review DISS-C-006
- **File:** `head/.claude/adapters/cheval.py:551-555`
- **Issue:** `_build_provider_config` re-checks the endpoint only `if _optin_raw is not None`; a hand-built or stale config with an `http://` or loopback endpoint and no opt-in reaches `ProviderConfig` unchecked, and a lone opt-in with no endpoint is not validated. `load_config` is the real gate (`loader.py:704`), so this is a defence-in-depth gap.
- **Fix:** Call `check_endpoint(endpoint, _optin_raw, provider_name)` unconditionally for non-CLI providers with an endpoint; validate a lone opt-in via `canonical_optin_host`.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-005] `describe-provider` and the probe print the interpolated endpoint verbatim
- **Confidence:** medium — Cross-model review DISS-C-007
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:200` (`"endpoint": prov.get("endpoint")`), `:224` (`str(exc)` on load failure); `head/.claude/scripts/model-health-probe.sh:1505` (`log_info "probing configured provider $provider at $url…"`)
- **Issue:** `interpolate_config` is eager for every string except `providers.*.auth` (`interpolation.py:40`), so an endpoint template embedding `{env:GATEWAY_TOKEN}` is resolved and printed to stdout/logs by the helper the docstring says "never carries a secret"; a load failure prints the raw exception text.
- **Fix:** Emit scheme/host/port via `split_url` (as `destination_for` does) and route load errors through `redact_config`.
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [LOW-006] The probe applies the host allowlist to configured providers cheval admits without it
- **Confidence:** medium
- **File:** `head/.claude/scripts/model-health-probe.sh:1469`
- **Issue:** `_probe_configured` validates `<endpoint>/models` with `--allowlist "$PROBE_PROVIDERS_ALLOWLIST"`, while cheval admits an operator-declared https host through `validate_declared_endpoint` (`endpoint-validator.py:1080`). A hosted open-weight API loads in cheval and is answered `UNKNOWN / endpoint_refused` by the probe. The reason is named, so not silent.
- **Fix:** Pass a declared-endpoint mode to the validator CLI for configured providers, or document in `--help` and `scripts-reference.md` that configured https providers must also be on the probe allowlist.

### [LOW-007] Three new functions exceed the 50-line threshold without justification
- **Confidence:** high
- **File:** `head/.claude/scripts/model-health-probe.sh:1428` (`_probe_configured`, ~110 lines, four repeated early-return blocks); `head/.claude/skills/bridgebuilder-review/resources/config.ts:605` (`loadTrustedConfig`, ~105 lines); `head/.claude/scripts/adversarial-review.sh:3972` (`_adv_advisory_block`, ~65 lines with a 30-line embedded jq program)
- **Fix:** A `_probe_unknown <reason> <class>` helper; split the PR-mode source resolution out of `loadTrustedConfig`; move the jq program to a `.jq` file beside the schemas.

### [LOW-008] Implementation report and CHANGELOG evidence
- **Confidence:** high
- **File:** `head/README.md:22` (points at `CHANGELOG.md`, not in the diff); `pr/PR.md` (two lines)
- **Issue:** The implementation report carries no `## AC Verification` walkthrough, no assumptions and no record of the test or type-check runs; the CHANGELOG entry that should log the security-relevant changes (endpoint opt-in, trusted configuration, exit-code semantics) is not in the change set, so the documentation-audit check "CHANGELOG omitting security changes" cannot be passed; no documentation-coherence subagent reports exist for this sprint (`grimoires/loa/a2a/subagent-reports/` absent).
- **Fix:** On re-submission include the AC walkthrough with `file:line` + symbol per criterion, the test commands run, and the CHANGELOG entry (or its commit).

---

## Observations

None excluded from the tally (`excluded: 0`). The review's trailer excluded nothing, so `excluded_confirmed: 0`.

Positive observations worth keeping:
- `check_insecure_optin` (`endpoint-validator.py:1033`) refuses booleans, DNS names, link-local, cloud-metadata and ULA addresses; step 1.5 still enforces no-userinfo and the path validator for the opted-in host; IPv4-mapped IPv6 and shorthand literals do not match an IPv4 opt-in.
- `TransportPolicy` (`base.py:118-163`) is applied consistently to `http_post`, `http_get` and `http_post_stream` on both transports; the urllib opener drops the proxy handler and the redirect handler.
- `endpoint_validator__guarded_curl` (`endpoint-validator.sh:406-411`) runs curl with `--proto =http,https --max-redirs 0 --noproxy '*'` only after the validator admits the URL.
- Advisory voices are isolated by construction (`_adv_advisory_block`, `:3972`) and the counted envelope is proven byte-identical (bats ADV-2).
- Exit code 3 is handled consistently by `dispatcher.sh:78-91`, `spiral-harness.sh:697-712` and `entry.sh:120` (preflight moved to 4).

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `metadata.rejected_sidecars` is `[]`; the companion's sidecar `adversarial-rejected-audit-companion.jsonl` has zero rows (both voices validated without repair).

---

## Cross-Model Security Observations

Security dissent ran on `pr/head.diff`: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. Primary `gpt-5.5-pro` (answered by `codex-headless`, status `clean`, 0 findings); companion `claude-headless` succeeded, `counted_as: independent_voice`; `voices_planned: 2`, `voices_succeeded: 2`, verdict quality APPROVED; `metadata.locality: null`, `degraded: false`. Not a degraded security review. No `advisory_voices` block (none configured). Each companion finding was verified against the head files:

- **DISS-C-001 (MEDIUM)** opt-in independent of keyless → confirmed; tallied as LOW-002 (operator-chosen, loopback/RFC1918 only, but silent).
- **DISS-C-002 (MEDIUM)** substring schema-rejection heuristic → confirmed; tallied as LOW-003 (same destination, recorded).
- **DISS-C-003 (MEDIUM)** `validate_local_fallbacks` never called → the named function does not exist in the head; the PR enforces fallback-chain locality at plan time in `hop-locality.py`, not at load. The chain-walk concern is real and is where Bridgebuilder fails: counted under HIGH-001. cheval's own loader having no such check is a defence-in-depth gap folded into HIGH-001's fix.
- **DISS-C-004 (MEDIUM)** `hop_locality_of` ignores the provider-block label → confirmed as a consistency gap; tallied as LOW-001 (cheval refuses the provider-level-only shape at load, so nothing leaks).
- **DISS-C-005 (MEDIUM)** any public https host admitted for a credentialed provider from project config → confirmed, pre-existing on the Python path; tallied as MED-002 together with the trusted-config scope gap.
- **DISS-C-006 (LOW)** adapter re-check only with an opt-in → confirmed; LOW-004.
- **DISS-C-007 (LOW)** `describe-provider` prints the interpolated endpoint → confirmed (`interpolation.py:40` lazy for `auth` only); LOW-005.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixture keys are `fixture-not-a-key`; pricing/endpoint CLIs print no secret values — but see LOW-005 for interpolated endpoints)
- [x] Input validation at trust boundaries — opt-in host grammar, hop-name regexes before yq/jq/argv, `isSafeRefName` before `git show`, `_CONFIGURED_NAME_RE` and `_ENV_AUTH` in the probe path
- [ ] Authorization / confidentiality boundaries consistent — HIGH-001 (Bridgebuilder locality), MED-001 (policy on one adapter family), MED-002 (trusted config vs cheval's head read)
- [x] No injection paths found — `execFileSync` argv, `python3 -I … --`, jq `--arg`/`--slurpfile`, yq via stdin; no `eval`, no string-built shell
- [x] Error handling doesn't leak info — refusals name hosts and codes, never key values (LOW-005 is the one exception, config-dependent)
- [x] Tests cover security paths — stub-server tests for proxy/redirect/no-credential (`test_openai_local_hop_e2e.py`), 30-case opt-in parity table, bats LOC-1..8 / FLL-1..7 / ADV-1..9; TS tests present but not executable here

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | Allowlist grammar for the opt-in; LOW-003 heuristic is the gap |
| SEC-AZ Authorization / trust boundaries | 3 | MED-002: trusted layer covers planning, not dispatch |
| SEC-CI Confidentiality | 3 | HIGH-001 posture breach; MED-001 partial transport rules; LOW-002 |
| SEC-IN Injection | 5 | argv everywhere, data via jq args/files |
| SEC-AV Availability | 4 | Advisory wall clock, reapers, budget gate priced per voice |
| Architecture | 3 | LOW-001 three definitions of local |
| Code Quality | 3 | LOW-007 long functions; LOW-008 report evidence |
| DevOps | 4 | Exit-code contract consistent; LOW-006 probe/cheval rule mismatch |

Working file: `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`. Structured findings: `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001: give Bridgebuilder the fallback-chain rule (recurse or delegate to `hop-locality.py`), pin it with a test mirroring LOC-7.
2. Decide MED-001 (refuse the opt-in / `dispatch_group: local` for adapter types without the policy, or implement it in `ProviderAdapter`) and MED-002 (carry trusted declarations into the cheval call or compare head endpoint/auth; at minimum narrow the README/SKILL.md claim).
3. Address the LOWs as convenient; LOW-002 and LOW-005 are one-line WARN/redaction changes.
4. Re-run the pytest, bats and `npm test` suites; record the commands, the AC walkthrough and the CHANGELOG entry in `reviewer.md`.
5. `/review-sprint sprint-1`, then `/audit-sprint sprint-1` to verify.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:58:00Z"} -->
