All good

Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)

---

## Overall Assessment

The change under review is sprint-257 of cycle-129 (`pr/head.diff`, 80 files): the per-provider insecure-endpoint opt-in and keyless providers on both validator paths, the request-time TransportPolicy, chat-completions `response_format` with the one-retry fallback, thinking-trace stripping, MODELINV destination/locality telemetry, catalog price provenance and the catalog-priced dissent budget gate, advisory voices, the `hounfour.locality: local_voices` plan-time refusals across the dissent, Flatline, the health probe and Bridgebuilder, Bridgebuilder's trusted-configuration read and its exit-3 DEGRADED contract.

What I verified, not what the report says:

- Read the whole diff. The workspace framework at `.claude/` is byte-identical to `pr/head` for the touched scripts, so untouched callers and helpers could be cross-checked (every helper the new shell code calls exists: `_adv_invoke_hop`, `process_findings`, `_adv_refuse_json`, `_conf_uint`, `_CACHED_TERTIARY_MODEL*`, `is_stage_routing_scorer_enabled`, …).
- Ran the six new Python test files against the head adapters: 123 passed (includes the 127.0.0.1 stub-server E2E through `cheval.cmd_invoke`, the two-path opt-in case table, and the live-catalog provenance invariant).
- Ran the six new bats suites against the head scripts: 45 ok, 1 skipped (`FLL-7` needs a `prd.md` this checkout lacks), 0 failures. These exercise whole runs of `adversarial-review.sh` (advisory voices, the priced budget gate, locality refusals), `flatline-orchestrator.sh`, the Bridgebuilder exit-3 callers and the configured-provider probe against a real 127.0.0.1 stub with a dead proxy in the environment.
- Checked the Bridgebuilder `dist/.build-manifest.json`: all seven touched TypeScript sources match their recorded SHA-256, and the generated `endpoint-validator.generated.ts` source hash equals the head `endpoint-validator.py`.
- Not run: the three TypeScript `node:test` files (`node_modules/zod` is absent here, no `tsc`); their assertions were read and match the code.
- Security read of the new trust boundaries (OWASP A10 SSRF / CWE-918; CWE-601 open redirect): the opt-in admits http only to the one canonical loopback/RFC1918 IP literal or `localhost`, never a DNS name, and the acceptance branch at `endpoint-validator.py` Step 1.5 still runs the userinfo, port and path checks; proxy env is ignored (`trust_env=False` / empty `ProxyHandler`), 3xx is refused on all three transports, and the path-prefix rule rejects a sibling prefix (`/v10`) and traversal. On a pull request Bridgebuilder reads providers, locality and the exit key from the base ref or `BRIDGEBUILDER_TRUSTED_CONFIG`, refuses a head-only keyless/insecure declaration by name, and validates the base ref name before it reaches `git`.

Cross-model dissent (Phase 2.5): `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff` refused before dispatch with `status: budget_exceeded` — the configured primary `gpt-5.5-pro` (30 / 180 USD per Mtok) prices this 680 KB diff at 955c (primary 718c, companion `claude-headless` 237c) against `budget_cents: 200`; the catalog-priced gate under review is the very gate that refused. Recorded with `--record-fallback budget_exceeded --since 2026-10-21T13:08:39Z` (`grimoires/loa/a2a/sprint-1/adversarial-review.json`). No model was called; this is a single-model assessment. The gate hook will require a re-run (or `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted) before the sprint's COMPLETED marker.

Process notes: `reviewer.md` is the PR description and carries no `## AC Verification` section; per `pr/REVIEW-INSTRUCTIONS.md` the PR files are the entire input, so that pre-flight rule is not applied to the verdict. No beads (`br` absent). The PR's own acceptance criteria (sprint-257 Tasks 3.1–3.5) are checked below through their tests.

No critical or high finding. The twelve observations below are telemetry/consistency gaps, documentation drift and complexity notes; none produces a wrong verdict, a credential leak or a plan that reaches a hosted provider. Of the medium/low pile, the one worth a follow-up task is the provider-level `dispatch_group` drift (Observation 1): the planners accept a declaration shape that cheval's request-time rules and MODELINV do not.

Over-engineering pass: `_probe_configured` repeats the `/models` 200/401/transient classification of `_probe_openai`; `loadTrustedConfig` is linear precedence logic. `net: -40 lines possible` (share the status classification). Everything else is proportionate to the stated decisions (DEC-0146, DEC-0150, DEC-0165, DEC-0170).

**Verdict:** APPROVED

---

## Observations

### 1. Locality rule drift between the planners and cheval

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` — `hop_locality_of` reads `dispatch_group` from the model entry only, while the planners also honour a provider-level key (`head/.claude/scripts/lib/hop-locality.py:116` `entry.get("dispatch_group") or block.get("dispatch_group")`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:732` "every declared model local"). cheval builds `ModelConfig.dispatch_group` from the model entry only (`head/.claude/adapters/cheval.py:541`), so `_transport_policy` (`head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221`) returns None for such a provider unless it also carries an opt-in.
**File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`
**Suggestion:** Failing input: `providers.lanbox: {type: openai_compat, endpoint: "https://llm.corp.example/v1", auth: "{env:LOA_LAN_KEY}", dispatch_group: local, models: {m1: {…}}}` with `hounfour.locality: local_voices` and `code_review.model: lanbox:m1`. The dissent, Flatline and Bridgebuilder plan `lanbox:m1` as local; cheval sends the request honouring `HTTPS_PROXY` and (urllib) following redirects, and writes `hop_locality: hosted` beside `locality_mode: local_voices`. Either make `hop-locality.py` and `isLocalVoice` model-entry-only (matching the reference text at `head/.claude/loa/reference/multi-model-reference.md:102`, "whose model entry says"), or fold the provider-level key into `ModelConfig.dispatch_group` at `cheval.py:541` and `hop_locality_of`.
**Benefit:** One rule for "local" across plan time, request time and the audit row; the posture's "every hop is dispatched through cheval, which applies the request-time rules to a local hop" holds for every declaration shape the planners accept.

### 2. Documentation: CHANGELOG

- **MEDIUM** (confidence: low) `head/README.md:22` — the Unreleased block links `CHANGELOG.md` for this cycle's entries and migration notes, but the PR carries no `CHANGELOG.md` change for sprint-257 (new `python3 -m loa_cheval.metering.pricing` CLI, `lib/hop-locality.py`, the `advisory_voices` / `locality` / `exit_on_degraded` keys, Bridgebuilder's exit 3/4 contract change). Confidence is low because the entry may already exist from an earlier sprint of the cycle; the repository CHANGELOG is not part of the review input.
**File:** `head/README.md:22`
**Suggestion:** Confirm the CHANGELOG carries sprint-257's additions, in particular the exit-code change operators' wrappers must absorb.
**Benefit:** Operators find the migration note the README promises.

### 3. Complexity

- **MEDIUM** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:605` — `loadTrustedConfig` runs 605–713 (~108 lines) and `_probe_configured` runs `head/.claude/scripts/model-health-probe.sh:1428`–1544 (~116 lines); both exceed the 50-line guideline with no stated reason. SIMPLICITY[shrink]: `_probe_configured` duplicates the `/models` status classification of `_probe_openai` (`listing_miss`, `schema_mismatch`, 401/403, transient); `loadTrustedConfig` could split source selection from the head-only refusal and the two scalar reads. Not blocking: both are linear, commented and match the sibling functions' style in their files.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:605`
**Suggestion:** Extract `selectTrustedSource()` and `refuseHeadOnly()`; share the `/models` classification between the probes.
**Benefit:** Each piece testable alone; the probe classification changes in one place.

### 4. Stale budget comment in the example config

- **LOW** (confidence: high) `head/.loa.config.yaml.example:1624` — the `budget_cents` comment still says the gate prices "ONE dissent call" and that "the companion voice and the KF-004 repairs … are further calls it does not count" (:1626–1627), but `_adv_budget_estimate` now sums the primary, the companion's first hop and every advisory voice at catalog prices (`head/.claude/scripts/adversarial-review.sh:3865`). The same text sits at :1690 for `security_audit`.
**File:** `head/.loa.config.yaml.example:1624`
**Suggestion:** Rewrite the comment to match the new estimate (the `advisory_voices` comment added at :1675–1683 already describes it correctly).
**Benefit:** An operator sizing `budget_cents` from the comment does not get `budget_exceeded` refusals they were told would not happen.

### 5. Keyless rule differs between Bridgebuilder and cheval

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:482` — `literalAuth` treats any non-empty `auth` without `{env:` as keyless (`:491`), while cheval normalises only `auth: "local"` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:51`, "any other literal could be a real key"). A provider with `auth: "sk-…"` is listed as keyless in Bridgebuilder's startup line and skips the env-var check; cheval sends the literal as the Bearer token.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:482`
**Suggestion:** Match cheval: keyless when `keyless: true` or `auth` is exactly `local`.
**Benefit:** The two readers of the same declaration agree on what "keyless" means.

### 6. Undeclared model on an all-local provider

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:732` — a model id not declared under a provider whose declared models are all local counts as local (`isLocalVoice("local-vllm", "unlisted-alias") === true`, as the test pins), whereas `hop-locality.py` returns `model_not_declared → hosted` for the same hop (`:112–113`). Bridgebuilder plans a voice the dissent and Flatline would refuse; cheval then fails to resolve it and the run is DEGRADED.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:732`
**Suggestion:** Return false for a model id the provider does not declare, unless the provider-level key says local (see Observation 1 for which rule to keep).
**Benefit:** One answer per hop across the three planners.

### 7. Declared endpoints skip hostname syntax

- **LOW** (confidence: high) `head/.claude/scripts/lib/endpoint-validator.py:1291` — the `_declared_endpoint` branch returns valid after the IDN step without a hostname-syntax check, so a host containing `{` and `}` passes (verified: `validate_declared_endpoint("https://bedrock-runtime.{region}.amazonaws.com")` → valid). The shipped bedrock default relies on this; an operator typo such as `https://api.openai.com /v1` is refused only at connect time.
**File:** `head/.claude/scripts/lib/endpoint-validator.py:1291`
**Suggestion:** Apply an RFC 1123 label check and allow the single `{region}` placeholder explicitly.
**Benefit:** A malformed declared host is refused at load with a named reason, like every other declared-endpoint error.

### 8. Over-broad 400 heuristic

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101` — `_names_response_format` matches any HTTP 400 whose body mentions `json_schema`, including a server that supports `response_format` but rejects this schema's content (OpenAI strict mode: "Invalid schema for response_format … additionalProperties must be false"). The adapter then retries without the schema and the run proceeds unenforced with `schema_rejected_by_server: true`, so a schema bug reads as a server capability gap. Accepted by SDD §6 as the heuristic; recorded here so the telemetry is read with that in mind.
**File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101`
**Suggestion:** Distinguish "unsupported" from "invalid schema" when the body says `Invalid schema`, and surface the latter as an error instead of retrying.
**Benefit:** A broken wire schema is caught in CI rather than silently downgrading enforcement.

### 9. Probe runs the loader once per model

- **LOW** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1576` — `_probe_one_model` calls `_configured_providers` (a full cheval `load_config` in a Python process) for every model of a configured provider, although `_parse_args` (`:1793`) already resolved the set once; `--provider local` with N models runs the loader N+1 times.
**File:** `head/.claude/scripts/model-health-probe.sh:1576`
**Suggestion:** Cache the configured-provider list in a variable after `_parse_args`.
**Benefit:** Probe latency scales with HTTP calls, not loader processes.

### 10. Missing trajectory row on schema mismatch

- **LOW** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1519` — the configured-provider probe sets `PROBE_ERROR_CLASS="schema_mismatch"` without the `_emit_trajectory "schema_mismatch"` row the openai (`:1142`) and google (`:1205`) probes emit.
**File:** `head/.claude/scripts/model-health-probe.sh:1519`
**Suggestion:** Emit the same row with the configured provider's name.
**Benefit:** Contract drift on a local server is visible in the trajectory like it is for the hosted ones.

### 11. Destination telemetry for an endpoint-less HTTP provider

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:444` — `destination_for` records `{host: cli-subprocess, scheme: cli}` whenever `endpoint` is empty, including a non-CLI provider type with a missing endpoint; the row then claims a CLI hop that never existed.
**File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:444`
**Suggestion:** Reserve the CLI shape for `*-headless` types and `kind: cli`; record `unknown` for an empty endpoint.
**Benefit:** `destination` stays truthful for FR-7 AC-7.5.

### 12. The posture switch fails open in two readers

- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:664` — when `yq` is missing or fails, the trusted view is empty, `source` becomes `none` and `locality` stays `hosted` with only a warning; `head/.claude/scripts/flatline-orchestrator.sh:707` likewise returns `hosted` when `yq` is absent. `head/.claude/scripts/adversarial-review.sh:239`–249 instead treats an unreadable value as `invalid` and refuses the run. A host without `yq` runs Bridgebuilder and Flatline hosted under an operator's `local_voices` posture.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:664`
**Suggestion:** Treat an unreadable config as `invalid` for the locality key in all three readers (the dissent's behaviour).
**Benefit:** "A posture typo never runs hosted silently" (the `loadTrustedConfig` docstring) extends to an unreadable posture.

---

## Rejected dissent payloads

None. The dissent did not run: `adversarial-review.sh` refused before dispatch with `status: budget_exceeded` (955c estimated over the 200c budget for a 680 KB diff), recorded as the round's fallback envelope; `rejected_summary` is empty and no sidecar was written.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| — | — | Task 1.1 (the change in `pr/head.diff`) is complete; no PR task is incomplete. |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (sprint.md success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict")

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect reported with file and line | Pass | Twelve observations above, each `head/<path>:<line>`; mirrored in `review.md` |
| Merge verdict given | Pass | APPROVED — zero critical/high |

### The PR's own criteria (sprint-257, cycle-129), checked through the code and its tests

| Criterion | Status | Notes |
|-----------|--------|-------|
| 3.1 / AC-3.1 — insecure-endpoint opt-in on both validator paths, keyless providers, probe `--provider <name>` | Pass | `test_endpoint_validator_optin.py` (31-case table through `endpoint-validator.py` and `endpoint_policy.check_endpoint`, stub-server redirect/proxy/path tests on httpx and urllib), `test_config_examples_load.py` (13 refusals, 8 acceptances, cross-provider isolation), `model-health-probe-configured-provider.bats` (6 ok, incl. live 127.0.0.1 stub with dead proxy) |
| 3.2 / AC-3.2 — chat `response_format`, 400 retry, thinking strip, `streaming_recovery` plumbing, E2E through `cmd_invoke` | Pass | `test_openai_chat_schema.py`, `test_openai_thinking_strip.py`, `test_openai_local_hop_e2e.py` (MODELINV rows validated against the shipped payload schema) |
| 3.3 / AC-7.3, AC-7.5 — advisory voices never counted; catalog-priced budget gate; price provenance | Pass | `adversarial-review-advisory.bats` (9 ok, byte-identical envelope and `verdict-derive --json` with/without advisory voices), `adversarial-review-budget.bats` (6 ok), `test_catalog_pricing_provenance.py` |
| 3.4 / D-7.5, D-7.7 — Bridgebuilder trusted config, `completed/planned`, exit 3 on DEGRADED, callers | Pass (TS tests read, not executed) | `bb-exit-degraded-callers.bats` (9 ok); `trusted-config.test.ts`, `run-outcome.test.ts`, `progress.test.ts` read against the code; dist manifest hashes match the sources |
| 3.5 / AC-8.1–8.3 — `local_voices` plan-time refusals across the dissent and Flatline | Pass | `adversarial-review-locality.bats` (8 ok), `flatline-locality.bats` (6 ok, 1 skip for a missing `prd.md`) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (fixture keys only in tests; `describe_provider` prints env-var names, never values)
- [x] Input validation and sanitization present (opt-in host canonicalised and range-checked; alias and hop names validated before reaching `yq`/`jq`; base ref name validated before `git`)
- [x] Authentication/authorization correct (keyless sends no `Authorization`; head-only keyless/insecure declarations refused on a PR; `{env:VAR}` still bound by `secret_env_allowlist`)
- [x] No SQL/XSS injection vulnerabilities (n/a; jq operands passed as `--arg`, envelopes as files)
- [x] Dependencies secure (no new dependency; `idna` import made lazy and fail-closed)
- [x] Error messages don't leak sensitive data (refusal lines name hosts and aliases, never key values; advisory `error` cut to 200 printable chars)

---

## Code Quality Summary

**Strengths:**
- One canonical endpoint rule (`endpoint-validator.py`) reached from cheval, the bash wrapper and the probe, with a single case table proving both paths agree.
- The advisory block and the locality refusals are additive: the tests prove the counted envelope and `verdict-derive` output are byte-identical with and without them.
- Fail-closed defaults where it matters: the locality classifier calls anything unreadable hosted; a head-only provider declaration is refused by name; the pricing CLI never invents a price.
- Request-time rules tested against a real local stub on both transports, including the no-policy control that proves the proxy environment was actually live.

**Areas for Improvement:**
- Three readers of "local" (cheval, `hop-locality.py`, Bridgebuilder) with three slightly different rules (Observations 1, 6) and two different fail-open postures (Observation 12).
- Documentation drift inside the same file the PR edits (Observation 4).

---

## Next Steps

1. Open a follow-up task for Observation 1 (one locality rule across plan time, request time and MODELINV).
2. Re-run the cross-model dissent with a budget or primary the gate admits (the recorded fallback does not open `adversarial-review-gate.sh`), then `/audit-sprint sprint-1`.
3. Fix the example-config comment (Observation 4) alongside any CHANGELOG entry (Observation 2).

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:12:00Z"} -->
