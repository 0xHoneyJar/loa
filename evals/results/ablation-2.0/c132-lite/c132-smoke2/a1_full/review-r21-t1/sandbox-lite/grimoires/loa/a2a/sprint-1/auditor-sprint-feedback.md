# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Senior review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — "All good", APPROVED, 0 critical / 0 high / 3 medium / 9 low, `excluded: 0`

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Scope: pull request sprint-257 (cycle-129), 80 files — the per-provider insecure-endpoint opt-in (`allow_insecure_endpoint`) and `keyless` providers on the cheval loader and the bash validator, the request-time `TransportPolicy` (no proxy env, no redirects, declared path prefix), chat-completions `response_format` with one unenforced retry, thinking-trace stripping, MODELINV destination/locality telemetry, catalog price provenance and the catalog-priced dissent budget gate, advisory voices, the `hounfour.locality: local_voices` plan-time refusals (dissent, Flatline, probe, Bridgebuilder), Bridgebuilder's trusted-configuration read and its exit-3 DEGRADED contract.

What I did (Phase 1A/1B against the `pr/head/` files, not the description): read every non-generated production change in the diff (cheval adapters, `endpoint_policy.py`, `endpoint-validator.py/.sh`, `hop-locality.py`, `adversarial-review.sh`, `flatline-orchestrator.sh`, `model-health-probe.sh`, `spiral-harness.sh`, Bridgebuilder `config.ts` / `main.ts` / `run-outcome.ts` / `multi-model-pipeline.ts` / `entry.sh`, the session-cap-bb contracts, the example config and README); ran the head `endpoint-validator.py` opt-in and declared-endpoint paths against an edge-case table (loopback/RFC1918/metadata/link-local/ULA/mapped-IPv4/shorthand opt-in values; traversal, `%2e%2e`, `//`, userinfo, `localhost` name, mismatched http host); ran the bash validator with the probe allowlist against an https configured host; cross-checked the three "local" readers (cheval, `hop-locality.py`, Bridgebuilder) and the three locality readers' failure modes; traced the trusted-config read in Bridgebuilder down to the cheval dispatch. The PR's own test suites were executed by the senior review (123 pytest passed; 45 bats ok / 1 skip) and I did not repeat them.

Security read (OWASP A10 SSRF / CWE-918, CWE-601 open redirect, CWE-522 credential exposure): the opt-in is sound — `check_insecure_optin` refuses booleans, DNS names, `127.1` shorthand, `0.0.0.0`, `::ffff:127.0.0.1`, link-local, the metadata addresses and ULA IPv6, and admits only a canonical loopback/RFC1918 literal or `localhost`; http is admitted to that one host only, the acceptance branch still runs the userinfo, port and path checks (traversal, `%2e%2e` and `//` refused); every other declared endpoint keeps https-only and the loopback/private IP block, with the `localhost` name refused once the allowlist backstop is absent. `TransportPolicy` applies `trust_env=False` / an empty `ProxyHandler`, refuses every 3xx on all three transports, and rejects a request URL off the declared origin or path prefix. A keyless provider sends no `Authorization` header at all. Hop names, aliases and the base ref name are validated before they reach `yq`, `jq` or `git`; envelopes travel as files. No secret value is printed anywhere (`describe_provider` returns env-var names only; refusal lines name hosts and aliases).

No critical or high finding. Fourteen findings follow: two of my own (a functional gap in the configured-provider probe and an overstated trust claim around Bridgebuilder's trusted configuration) and the senior review's twelve observations, each independently confirmed against the head files (one re-rated upward, one downward). None produces a wrong verdict, a credential leak in the shipped invocation model, or a hosted hop under `local_voices` from a declaration cheval accepts as local.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 5 |
| Low | 9 |

**Cross-model dissent:** `DEGRADED_SECURITY_REVIEW` — the security dissenter did not run (see "Security Dissenter" below). This is a single-model audit.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] The configured-provider probe runs the probe host allowlist, so a declared https provider is refused

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/model-health-probe.sh:1469` (and `:1024`)
- **Issue:** `_probe_configured` validates `<endpoint>/models` with `endpoint_validator__check --json --allowlist "$PROBE_PROVIDERS_ALLOWLIST"` (`:1469`–`1475`), and `_curl_json` passes the same `--allowlist` to `endpoint_validator__guarded_curl` (`:1024`). That is the bash `validate()` pipeline WITH the Step-8 host allowlist (`lib/allowlists/loa-providers.json`: only `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com` and three bedrock hosts), not the `validate_declared_endpoint` rule the cheval loader applies to the same declaration. Only an opted-in loopback/RFC1918 host (Step 1.5 bypasses the allowlist for that one host) can be probed. Verified: `python3 -I endpoint-validator.py --allowlist lib/allowlists/loa-providers.json --json https://llm.corp.example/v1/models` → `ENDPOINT-NOT-ALLOWED`, exit 78. So `model-health-probe.sh --provider azure-openai` for the PR's own Example 3 (`head/.loa.config.yaml.example:1206`, `https://myorg.openai.azure.com`) and any hosted open-weight API return `UNKNOWN` / `endpoint_refused`, while the header (`:21`–`22`), `scripts-reference.md:117` and `multi-model-reference.md:104` say the probe accepts any configured `hounfour.providers` name. The bats suite covers only the opted-in `127.0.0.1` case.
- **Impact:** Functional, fail-closed — nothing is sent. An operator reads a "refused" probe as a broken provider and may loosen `LOA_PROBE_PROVIDERS_ALLOWLIST` to make it pass, which would also widen the probes of the four built-in providers.
- **Fix:** For a configured provider, validate with the declared-endpoint rule (add a `--declared-endpoint` flag to `endpoint-validator.py` / the bash wrapper that calls `validate_declared_endpoint`, or pass a per-provider allowlist built from the provider's own host), and add a bats case for an https configured host. Document the limitation until then.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-002] Bridgebuilder's trusted configuration gates the plan, but cheval dispatches from the working-tree config

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/skills/bridgebuilder-review/SKILL.md:118` (code: `head/.claude/skills/bridgebuilder-review/resources/config.ts:605`, `:672`; `head/.claude/adapters/loa_cheval/config/loader.py:110`)
- **Issue:** `loadTrustedConfig` (`config.ts:605`) reads `hounfour.providers`, `hounfour.locality` and `exit_on_degraded` from the base ref or `BRIDGEBUILDER_TRUSTED_CONFIG` on a pull request, and reads the head checkout "only to refuse" keyless / `allow_insecure_endpoint` declarations the trusted source lacks (`:672`–`690`). But the voices it then plans are dispatched through `cheval.py` resolved from `process.cwd()` (workspace `adapters/cheval-delegate.ts:117`), and the cheval loader reads `.loa.config.yaml` from the working tree (`loader.py:110`) — on a PR-head checkout that is the head's `hounfour.providers`: `endpoint`, `auth`, `models`. The head-only refusal compares only the two flags, so a head that keeps a trusted provider's `keyless`/opt-in flags unchanged and rewrites its `endpoint` (the new `validate_declared_endpoint` admits any https host, `endpoint-validator.py:1291`) is planned as trusted and dispatched to the head's host; for a provider with `auth: "{env:VAR}"` the Bearer credential travels with it. Quote: "Since cycle-129 the provider, locality and exit keys follow the trusted-source precedence below even when the checkout is a PR head." (`SKILL.md:117`–`118`) — true of Bridgebuilder's plan, not of the dispatch.
- **Impact:** Credential and prompt exfiltration to an attacker-chosen https host, but only in an invocation model the skill says it does not ship (#1050: "no PR-head checkout", `SKILL.md:117`), and the exposure predates this PR (the base loader validated no endpoint at all; this PR adds the first check on that path). Not a regression; the new sentence overstates coverage. [ASSUMPTION] the GitHub Action that runs Bridgebuilder on `pull_request` does not check out the head; if it does, this is HIGH.
- **Fix:** Either state the boundary in `SKILL.md` ("the trusted config governs the plan; cheval still reads the checkout's `.loa.config.yaml`, so Bridgebuilder must run from a trusted checkout"), or pass the trusted provider view to cheval (a `--config` / `LOA_CHEVAL_CONFIG` path written from `TrustedConfig`), or extend the head-only refusal to a changed `endpoint` / `auth` of a trusted-declared provider.
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html ; OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [MED-003] Provider-level `dispatch_group: local` is honoured by the planners, not by cheval's request-time rules or MODELINV

- **Severity:** MEDIUM (confidence: high) — confirms senior review Observation 1
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`
- **Issue:** `hop_locality_of` reads `dispatch_group` from the model entry only (`modelinv.py:476`: `return "local" if entry.get("dispatch_group") == "local" else "hosted"`), and `ModelConfig.dispatch_group` is built from the model entry only (`head/.claude/adapters/cheval.py:541`), so `_transport_policy` (`head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217`) returns `None` for a provider that declares the key at provider level without an opt-in. The planners accept that shape: `head/.claude/scripts/lib/hop-locality.py:116` (`entry.get("dispatch_group") or block.get("dispatch_group")`) and `head/.claude/skills/bridgebuilder-review/resources/config.ts:726`–`732`.
- **Impact:** Under `local_voices`, `providers.lanbox: {endpoint: "https://llm.corp.example/v1", auth: "{env:LOA_LAN_KEY}", dispatch_group: local, models: {m1: {...}}}` is planned as local by the dissent, Flatline and Bridgebuilder, while cheval sends the request honouring `HTTPS_PROXY`, following redirects (urllib), and records `hop_locality: hosted` beside `locality_mode: local_voices`. The posture's "every hop is dispatched through cheval, which applies the request-time rules to a local hop" does not hold for that declaration.
- **Fix:** One rule. Either make `hop-locality.py` and `isLocalVoice` model-entry-only (matching `head/.claude/loa/reference/multi-model-reference.md:102`, "whose model entry says"), or fold the provider-level key into `ModelConfig.dispatch_group` at `cheval.py:541` and into `hop_locality_of`.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [MED-004] The `local_voices` posture fails open in two of three shell/TS readers

- **Severity:** MEDIUM (confidence: medium) — senior review Observation 12, re-rated from LOW: a silently violated privacy posture is the audit's concern
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:663`
- **Issue:** When `yq` is missing or fails, `loadTrustedConfig` pushes a warning, sets `source = "none"` (`config.ts:663`–`664`) and `locality` stays `hosted` (`:694`); `flatline_locality_mode` returns `hosted` when `yq` is absent (`head/.claude/scripts/flatline-orchestrator.sh:707`). `adversarial-review.sh:239`–`248` instead classifies an unreadable value as `invalid` and refuses the run. The `loadTrustedConfig` docstring promises "a posture typo never runs hosted silently" (`config.ts:600`) — an unreadable posture does.
- **Impact:** A host without `yq` runs Bridgebuilder and Flatline against hosted providers under an operator's `local_voices` posture, with only a stderr warning.
- **Fix:** Treat an unreadable config as `invalid` for the locality key in all three readers (the dissent's behaviour); Bridgebuilder should throw as it does for an invalid value.
- **Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html

### [MED-005] Documentation: CHANGELOG entry not in the PR

- **Severity:** MEDIUM (confidence: low) — confirms senior review Observation 2
- **File:** `head/README.md:22`
- **Issue:** The Unreleased block links `CHANGELOG.md` for cycle-129's entries and migration notes, but the PR carries no `CHANGELOG.md` change for sprint-257: the `python3 -m loa_cheval.metering.pricing` CLI, `lib/hop-locality.py`, the `advisory_voices` / `locality` / `exit_on_degraded` keys, the Bridgebuilder exit 3/4 contract change (a behaviour change operators' wrappers must absorb) and the new endpoint rule on the cheval path (a security change). Confidence is low because the entry may already exist from an earlier sprint of the cycle; the CHANGELOG is not part of this workspace.
- **Fix:** Confirm the CHANGELOG carries sprint-257's additions, in particular the exit-code change and the endpoint rule.
- **Reference:** documentation audit, "a CHANGELOG omitting security changes".

### [LOW-001] Bridgebuilder and cheval disagree on what "keyless" means

- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:482`
- **Issue:** `literalAuth` treats any non-empty `auth` without `{env:` as keyless (`:482`, `:491`); cheval normalises only `auth: "local"` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50`, "any other literal could be a real key"). A provider with `auth: "sk-…"` is listed as keyless in Bridgebuilder's startup line and skips the env-var check, while cheval sends the literal as the Bearer token. (Confirms review Observation 5.)
- **Fix:** Keyless when `keyless: true` or `auth` is exactly `local`.

### [LOW-002] An undeclared model id on an all-local provider is local for Bridgebuilder, hosted for the planners

- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:732`
- **Issue:** `isLocalVoice` returns true for a model id the provider does not declare when every declared model is local (`:732`); `hop-locality.py:115` returns `model_not_declared → hosted`. Bridgebuilder plans a voice the dissent and Flatline refuse; cheval then fails to resolve it and the run is DEGRADED. (Confirms review Observation 6.)
- **Fix:** Return false for an undeclared model id unless the provider-level key says local (see MED-003 for which rule to keep).

### [LOW-003] A declared endpoint skips hostname syntax

- **File:** `head/.claude/scripts/lib/endpoint-validator.py:1291`
- **Issue:** The `_declared_endpoint` branch returns valid after the IDN step with no hostname-syntax check. Verified on the head module: `validate_declared_endpoint("https://bedrock-runtime.{region}.amazonaws.com")` → valid; `validate_declared_endpoint("https://api.openai.com /v1")` (space in the authority) → valid. A malformed declared host is refused only at connect time. (Confirms review Observation 7.)
- **Fix:** Apply an RFC 1123 label check and allow the single `{region}` placeholder explicitly.

### [LOW-004] The HTTP 400 heuristic also matches a schema-content rejection

- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101`
- **Issue:** `_names_response_format` (`:101`–`111`) matches any HTTP 400 whose body mentions `response_format` or `json_schema`, including a server that supports `response_format` but rejects this schema's content (OpenAI strict mode: "Invalid schema for response_format … additionalProperties must be false"). The adapter retries without the schema and proceeds unenforced with `schema_rejected_by_server: true`, so a wire-schema bug reads as a server capability gap. Accepted by SDD §6 as the heuristic. (Confirms review Observation 8.)
- **Fix:** Surface a body that says `Invalid schema` as an error instead of retrying.

### [LOW-005] Stale `budget_cents` comment in the example config

- **File:** `head/.loa.config.yaml.example:1624`
- **Issue:** The comment still says the gate prices "ONE dissent call" and that the companion and the repairs "are further calls it does not count" (`:1624`–`1628`; same at `:1690`–`1693`), while `_adv_budget_estimate` (`head/.claude/scripts/adversarial-review.sh:3866`) now sums the primary, the companion's first hop and every advisory voice at catalog prices — the very estimate that refused this sprint's dissent at 955c against 200c. (Confirms review Observation 4.)
- **Fix:** Rewrite the two comments to match the new estimate (the `advisory_voices` comment at `:1675`–`1683` already does).

### [LOW-006] The probe runs the cheval loader once per model

- **File:** `head/.claude/scripts/model-health-probe.sh:1576`
- **Issue:** `_probe_one_model` calls `_configured_providers` (a full `load_config` in a Python process) for every model of a configured provider although `_parse_args` (`:1793`) already resolved the set; `--provider local` with N models runs the loader N+1 times. (Confirms review Observation 9.)
- **Fix:** Cache the configured-provider list after `_parse_args`.

### [LOW-007] Missing trajectory row on a configured provider's schema mismatch

- **File:** `head/.claude/scripts/model-health-probe.sh:1519`
- **Issue:** `_probe_configured` sets `PROBE_ERROR_CLASS="schema_mismatch"` (`:1519`) without the `_emit_trajectory "schema_mismatch"` row the openai (`:1142`), google (`:1205`) and anthropic (`:1292`) probes emit. (Confirms review Observation 10.)
- **Fix:** Emit the same row with the configured provider's name.

### [LOW-008] Destination telemetry claims a CLI hop for an endpoint-less HTTP provider

- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:444`
- **Issue:** `destination_for` records `{host: cli-subprocess, scheme: cli}` whenever `endpoint` is empty (`:444`), including a non-CLI provider type with a missing endpoint; the MODELINV row then claims a CLI hop that never existed (FR-7 AC-7.5 asks for truthful destination). (Confirms review Observation 11.)
- **Fix:** Reserve the CLI shape for `*-headless` types and `kind: cli`; record `unknown` for an empty endpoint.

### [LOW-009] Two functions over the 50-line guideline

- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:605`
- **Issue:** `loadTrustedConfig` runs `:605`–`713` (~108 lines) and `_probe_configured` runs `head/.claude/scripts/model-health-probe.sh:1428`–`1544` (~116 lines); `_probe_configured` repeats the `/models` 200/401/transient classification of `_probe_openai`. Both are linear and commented; I rate this LOW (code quality), where the senior review rated it MEDIUM (Observation 3).
- **Fix:** Extract source selection and the head-only refusal from `loadTrustedConfig`; share the `/models` classification between the probes.

---

## Observations

None excluded. The senior review's trailer carries `excluded: 0`; there is no demoted HIGH to confirm (`excluded_confirmed: 0`).

Not a finding, recorded for the reader: `flatline_protocol.*.budget_scale: diff` sits in this workspace's `.loa.config.yaml` but neither the base nor the head `adversarial-review.sh` reads it (pre-existing, not introduced here). The advisory voices' concurrent `process_findings` runs were checked for shared state: the reject sidecar is disabled per walker (`adversarial-review.sh:3918`), repair temp files are `mktemp` per call, and the only a2a write is the opt-in `LOA_ADVERSARIAL_DEBUG=1` capture, named per model and timestamp — no clobber path found (senior review concern 4 closed).

---

## Security Dissenter (Phase 1C)

`bash .claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` refused before dispatch with `status: budget_exceeded` — the configured primary `gpt-5.5-pro` (30 / 180 USD per Mtok) prices the 680 KB `pr/head.diff` at 955c (primary 718c, companion `claude-headless` 237c) against `security_audit.budget_cents: 200`; no model was called. Recorded with `--record-fallback budget_exceeded --reason … --since 2026-10-21T13:17:32Z` as `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. A fallback record names no `metadata.model`, so `adversarial-review-gate.sh` will not open the `COMPLETED` marker: re-run the dissent with a budget or primary the gate admits (or `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted in sprint notes) before marking the sprint complete. The `COMPLETED` marker was therefore NOT written by this audit.

`DEGRADED_SECURITY_REVIEW`: single-model audit; no cross-model security observations.

## Rejected dissent payloads

None. The dissent did not run (`budget_exceeded` before dispatch); `rejected_summary` is empty and no sidecar was written.

---

## Documentation Audit

No `documentation-coherence-*` subagent reports exist in this workspace (there is no PRD/SDD for this eval cycle); documentation was verified manually against the code: `multi-model-reference.md:102`–`104`, `scripts-reference.md:116`–`119`, the Bridgebuilder `SKILL.md` exit-code and trusted-config tables, the example config comments, and the README Unreleased block. Red flags found: the probe claim (MED-001), the trusted-config claim (MED-002), the stale budget comment (LOW-005), and the unverifiable CHANGELOG (MED-005). No secrets or internal URLs in docs or comments.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixture keys only in tests; `describe_provider` prints env-var names, never values)
- [x] Input validation on all new trust boundaries (opt-in host canonicalised and range-checked; hop names, aliases and base ref validated before `yq`/`jq`/`git`; `python3 -I` for the classifier and pricing CLI)
- [x] Authentication required where needed (keyless sends no `Authorization`; head-only keyless/insecure declarations refused on a PR; `{env:VAR}` still bound by `secret_env_allowlist`) — with the plan/dispatch boundary noted in MED-002
- [x] No SQL/XSS injection vulnerabilities (n/a; jq operands as `--arg`, envelopes as files)
- [x] Error handling doesn't leak info (refusal lines name hosts and aliases; advisory `error` cut to 200 printable chars; cheval error summaries allowlisted)
- [x] Tests cover security paths (opt-in case table on both validator paths; stub-server redirect/proxy/path tests on httpx and urllib; head-only refusal and base-ref validation in `trusted-config.test.ts`) — gap: no probe test for an https configured host (MED-001)

---

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| Security | 4 | Opt-in and transport rules are fail-closed and tested; MED-002 and MED-004 are posture/claim gaps, not exploitable in the shipped model |
| Architecture | 3 | One canonical endpoint rule, but three readers of "local" with three rules (MED-003, LOW-001, LOW-002) |
| Code Quality | 4 | Clear comments and decision references; two long functions (LOW-009); telemetry gaps (LOW-007, LOW-008) |
| DevOps | 3 | Probe feature works only for opted-in hosts (MED-001); CHANGELOG not in PR (MED-005); exit-code contract documented and callers updated |
| Blockchain/Crypto | n/a | — |

---

## Next Steps

**APPROVED:**
1. Re-run the security dissent with an admitted budget or primary so the `COMPLETED` gate can open; then write the marker.
2. Open follow-up tasks for MED-001 (probe allowlist vs declared-endpoint rule), MED-002 (state or close the plan/dispatch trust boundary) and MED-003 (one locality rule); fix MED-004 alongside MED-003.
3. Fix the example-config comments (LOW-005) with the CHANGELOG entry (MED-005).

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":5,"low":9},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:26:00Z"} -->
