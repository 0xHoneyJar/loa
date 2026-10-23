# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

Scope reviewed: `pr/head.diff` — 80 files, 6583 insertions / 198 deletions; 30 of the files are generated `dist/` output and source maps. Citations are `head/<path>:<line>` with line numbers from `pr/head/`. No PRD/SDD/integration-context exists in this workspace; `grimoires/loa/known-failures.md` is absent (surfaced as a WARN at session start); `br` is not installed, so the beads steps were skipped.

---

## Overall Assessment

The sprint delivers four things: advisory open-weight voices for the dissent script, the `hounfour.locality: local_voices` posture across the dissent, Flatline, Bridgebuilder and the health probe, Bridgebuilder's trusted-configuration source plus the DEGRADED exit code, and an end-to-end local-hop test. The engineering is careful in the places it looks: every shell operand that reaches `jq`/`yq` is validated or passed as a file, the endpoint opt-in reuses the one canonical validator on both the bash and cheval paths, the TransportPolicy disables proxies and redirects on both the httpx and urllib paths, and the default hosted envelope is left byte-identical (I ran the head validator against the shipped default endpoints, including the templated `bedrock` host — all admit).

Two findings block the merge. First, the `local_voices` posture is satisfied by a label: `dispatch_group: local` on any model or provider block makes a hop "local" with no check that its endpoint is actually a loopback/RFC1918/localhost HTTP endpoint. I reproduced this with the head's own classifier against a declared provider whose endpoint is `https://api.together.xyz/v1`. The config example sells the posture with a threat model ("the prompt does not cross a public network"), and the label does not hold it; the dissent's BLOCKING finding adds that the label is not even read consistently — a provider-block label is honoured by the planners but ignored by cheval's transport and MODELINV. Second, Bridgebuilder's trusted configuration only governs Bridgebuilder's planning; every voice still dispatches through cheval, which reads the checkout's `.loa.config.yaml`. The SKILL.md added in this PR claims the trusted precedence holds "even when the checkout is a PR head", which the code does not deliver.

The implementation report (`reviewer.md` = the PR title line) carries no `## AC Verification` walkthrough, no stated assumptions and no record of which self-checks ran; by the skill's rule that alone is an automatic CHANGES_REQUIRED, independent of the findings above.

Seven medium and seven low observations follow; none of them is counted in the verdict.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security posture — locality is a declaration, not a property

- **HIGH** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116` — under `hounfour.locality: local_voices` a hop is planned as `local` whenever its model entry or provider block says `dispatch_group: local`; the endpoint host is never examined, so a hosted provider labelled `local` is dispatched to and the posture's guarantee does not hold.
**File:** `head/.claude/scripts/lib/hop-locality.py:116-134` (classify); the same label-only rule in `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` (`hop_locality_of`, the MODELINV record), `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221` (`_transport_policy`) and `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733` (`isLocalVoice`); the label is read from different places at `head/.claude/adapters/cheval.py:541` (model entry only).
**Issue:** The classifier's rule is "`dispatch_group: local` on the entry or its provider block, and every fallback hop local by the same rule" (`hop-locality.py:11-17`). Reproduced with the head script against the shipped catalog plus this overlay:
```yaml
hounfour:
  locality: local_voices
  providers:
    hosted-oss:
      type: openai_compat
      endpoint: "https://api.together.xyz/v1"
      auth: "{env:LOA_TOGETHER_KEY}"
      models:
        llama-70b: {dispatch_group: local, context_window: 131072}
    openai:
      models:
        gpt-5.5: {dispatch_group: local, fallback_chain: []}
```
```
$ python3 -I hop-locality.py --catalog model-config.yaml --config overlay.yaml -- hosted-oss:llama-70b gpt-5.5
hosted-oss:llama-70b	hosted-oss	local	dispatch_group=local
gpt-5.5	openai	local	dispatch_group=local
```
Both hosted hops are `local`; `adversarial-review.sh` and `flatline-orchestrator.sh` would plan them, Bridgebuilder's `isLocalVoice` keeps them (it does not even consult `fallback_chain`, unlike the Python classifier), cheval's TransportPolicy is applied to a public host, and MODELINV records `hop_locality: local`. A CLI provider block labelled `local` (e.g. `anthropic-headless: {dispatch_group: local}`) is likewise admitted by `isLocalVoice`. Nothing at load time (`endpoint_policy.validate_providers`) refuses the label on a provider that cannot honour it.
The dissent (DISS-C-001, confirmed against the head) adds the inverse failure: a label on the PROVIDER block is honoured by `hop-locality.py:116` and `isLocalVoice`, but `_build_provider_config` reads only `model_data.get("dispatch_group")` (`cheval.py:541`), so `_transport_policy` returns None and `hop_locality_of` says `hosted` — a hop planned and admitted as local runs without the D-7.2 request-time rules (proxy env honoured, redirects followed, no path check) and the audit row contradicts the planner.
**Why This Matters:** `local_voices` is the sprint's confidentiality posture; `.loa.config.yaml.example:1227-1233` describes its threat model as the prompt never crossing a public network. A posture that a single YAML key on any provider defeats, with no refusal and a MODELINV row that says `local`, is worse than no posture: the audit trail asserts something false. The rule is applied in four places (bash planner, Python telemetry, Python transport, TypeScript planner) with three different readings (fallback chains considered or not; provider-block label honoured or not).
**Required Fix:** Define "local" as a property the provider can be checked for: an HTTP provider (not `*-headless`, not `kind: cli`) whose declared endpoint host passes the validator's `check_insecure_optin` host acceptance (loopback, RFC1918 or `localhost`). Refuse `dispatch_group: local` at load (`endpoint_policy.validate_providers`) on any provider that fails it; resolve the label once (entry, else provider block) and apply the same rule in `hop_locality_of`, `_transport_policy` (and check the request host at request time), `hop-locality.py` and `isLocalVoice` (including `fallback_chain`, as the Python classifier already does). Add one test per surface with a hosted-endpoint provider labelled `local` and one with a provider-block label. Keep one implementation where the languages allow (cheval + MODELINV + loader share `endpoint_policy`; the bash and TS planners mirror its host rule).
**Reference:** CWE-693 (Protection Mechanism Failure); CWE-807 (Reliance on Untrusted Inputs in a Security Decision); OWASP A05:2021 Security Misconfiguration.

### 2. Security — the trusted configuration never reaches the process that sends the prompt

- **HIGH** (confidence: medium) `head/.claude/skills/bridgebuilder-review/SKILL.md:117` — on a PR-head checkout Bridgebuilder reads providers/locality/exit from the base branch, but each voice is dispatched by cheval, which loads the checkout's `.loa.config.yaml`; a head that keeps a trusted provider's `keyless`/opt-in flags but changes its `endpoint`, `aliases` or `secret_env_allowlist` is admitted and the prompt (and a `{env:VAR}` credential) go where the head says.
**File:** `head/.claude/skills/bridgebuilder-review/SKILL.md:117-118` (the claim); `head/.claude/skills/bridgebuilder-review/resources/config.ts:602-605` and `:678-700` (`loadTrustedConfig` reads the head only for keyless/insecure declarations the trusted source lacks); `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:220-235` (the voice is created with no key and handed to the cheval delegate).
**Issue:** `headOnlyRefused` compares only two booleans per provider (`keylessOnlyInHead`, `insecureOnlyInHead`). A PR head that leaves `local-vllm: {keyless: true, allow_insecure_endpoint: "127.0.0.1"}` identical to the base but rewrites `endpoint` to `https://attacker.example/v1` (an operator-declared https endpoint skips the host allowlist in `validate_declared_endpoint`, `endpoint-validator.py:1289-1296`), or re-points `hounfour.aliases.<voice>` at a different provider, passes every check here; cheval then loads the checkout config and dispatches the review prompt there. For a trusted provider with `auth: "{env:X}"`, the Bearer credential travels with it. The pre-existing SKILL.md text records this invocation model as "no PR-head checkout" (`:116-117`); the sentence this PR adds (`:117-118`) asserts protection in exactly that case.
**Why This Matters:** The feature's stated purpose (D-7.5) is that an attacker-controlled head cannot declare its way to a credential or an insecure hop. The control is placed in Bridgebuilder's planner while the dispatch path reads a different file; the documentation now promises more than the code holds. Confidence is medium because the shipped scheduled invocation (`dispatcher.sh --repo`) runs in local mode on a trusted checkout; the exposure is the PR-event/`--pr` path the PR documents.
**Required Fix:** Either (a) on a pull request compute drift between the head's and the trusted view's `hounfour.providers`, `hounfour.aliases`, `hounfour.locality` and the secret allowlists and refuse the multi-model run on any difference with a distinct exit code, or (b) hand the trusted configuration to cheval explicitly (a config path cheval loads instead of the checkout's) so the dispatch reads what Bridgebuilder trusted. Correct SKILL.md to state exactly what is protected. Add a test where the head changes only `endpoint` of a trusted keyless provider.
**Reference:** CWE-693 (Protection Mechanism Failure); CWE-829 (Inclusion of Functionality from Untrusted Control Sphere); OWASP A08:2021 Software and Data Integrity Failures.

---

## Observations

### 1. Callers — an exit 3 with nothing to show for it becomes success

- **MEDIUM** (confidence: high) `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78` — `rc == 3` is recorded as `degraded: true` and converted to `exit 0` (`:89-90`) without checking that `bb-stdout.json` holds a run JSON; an exit 3 from any other source (a shell error inside `entry.sh`, a wrapper, a mixed-version `dist/`) is reported as a completed review.
**File:** `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-90`
**Suggestion:** Treat 3 as completed-degraded only when `[[ -s "$BB_OUT" ]] && jq -e '.verdicts | type == "array"' "$BB_OUT"`; otherwise log an ERROR and `exit 3`. `_bb_surface_exit` in `spiral-harness.sh:697-711` already tolerates an empty file (it was `|| true` before), so only the dispatcher's exit conversion needs the guard. Add a bats case with exit 3 and empty stdout (none of the four dispatcher cases in `bb-exit-degraded-callers.bats:39-65` covers it).
**Benefit:** The scheduled contract keeps its pre-cycle-129 property that a non-zero Bridgebuilder exit without a review is a failure.

### 2. Health probe — configured https providers are refused by the probe's own allowlist

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1469` — `_probe_configured` validates `<endpoint>/models` with `--allowlist "$PROBE_PROVIDERS_ALLOWLIST"` (`:1469-1475`), i.e. the full `validate()` pipeline including step-8 host allowlisting, while the cheval loader admits the same provider through `validate_declared_endpoint` (allowlist skipped). A configured https provider on any host not in `lib/allowlists/loa-providers.json` — Example 3 (`azure-openai`, `.loa.config.yaml.example:1204-1224`) — is reported `UNKNOWN / endpoint_refused` and never probed.
**File:** `head/.claude/scripts/model-health-probe.sh:1469-1475`
**Suggestion:** Add a `--declared-endpoint` mode to `endpoint-validator.py`/`.sh` that calls `validate_declared_endpoint`, and use it for configured providers (the built-in four keep the allowlist). The header comment at `:852-856` ("apply exactly as on the cheval path") then becomes true. The bats file covers only the 127.0.0.1 opt-in and load-time refusals; add an https non-allowlisted case.
**Benefit:** `--provider <name>` works for the hosted open-weight APIs the PR title advertises, not only loopback servers.

### 3. Budget gate — the example's contract contradicts the code

- **MEDIUM** (confidence: high) `head/.loa.config.yaml.example:1624` — the `budget_cents` comment still says the gate prices "ONE dissent call" and that "the companion voice … are further calls it does not count", while `head/.claude/scripts/adversarial-review.sh:4329-4335` now sums the primary, the companion's first hop and every advisory voice; the FR-7 paragraph a few lines below (`:1675-1683`) says the opposite of `:1624-1627`.
**File:** `head/.loa.config.yaml.example:1624-1627`; `head/.claude/scripts/adversarial-review.sh:4320-4341`
**Suggestion:** Rewrite the `budget_cents` comment to the summed contract and state the default-config consequence: with `gpt-5.3-codex` (1.75/14 USD per Mtok in the catalog) and no Anthropic key the companion is `claude-headless` (10/50), so a 150c budget now refuses diffs above ~350 KB where it admitted up to ~430 KB before; with an Anthropic key (`opus`, 4/20) the new estimate is lower than the old fixed rate. Mention this in the CHANGELOG migration notes or raise the shipped default.
**Benefit:** Operators reading the example get the gate's real arithmetic; a mid-size diff that starts exiting 4 after the upgrade is explained.

### 4. Documentation — the CHANGELOG this PR points at is not in this PR

- **MEDIUM** (confidence: medium) `head/README.md:22` — the new README block links a CHANGELOG "Unreleased — earned guards and open voices" entry and `:32` tells users to "see the CHANGELOG Migration notes", but `CHANGELOG.md` is not among the 80 touched files, and this sprint changes caller-visible contracts: Bridgebuilder exit 3 now means DEGRADED and the missing-dependency preflight moved to exit 4 (`head/.claude/skills/bridgebuilder-review/SKILL.md:161-162`, `resources/entry.sh:118-120`), `pricing_source: stale_catalog` appears in ledger rows, the dissent budget estimate changed (observation 3), and `http://` provider endpoints without an opt-in now fail config load.
**File:** `head/README.md:22-32`
**Suggestion:** Add the CHANGELOG entry and migration notes in this PR (the skill's documentation check wants one per task), covering the exit-code contract, `exit_on_degraded: 0`, the load-time endpoint rule and the budget arithmetic. If the entry already landed in an earlier sprint of cycle-129, say so in the PR description so a reviewer can verify it.
**Benefit:** The upgrade path this README promises exists where it says it does.

### 5. FAST-GATE: no record of the fast gate in the report

- **MEDIUM** (confidence: medium) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR title; it names no formatter check, type check, shellcheck, `pytest` or `bats` run. The rebuilt `dist/` (`head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json`) implies `tsc` ran, but nothing shows the six new Python test files, the seven new bats files or the three TypeScript tests passing, and this workspace holds only touched files so I could not run them.
**Suggestion:** Record the self-checks (commands and results) in the report. The tests I read assert the implemented behaviour precisely (ADV-1…9, BUD-1…6, LOC-1…8, FLL-1…7, the probe, dispatcher and trusted-config suites, the local-hop E2E); the gaps are the cases named above (hosted provider labelled local; provider-block label; probe with an https configured provider; dispatcher exit 3 with empty stdout).

### 6. SIMPLICITY[shrink]: three functions well over the 50-line ceiling

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1428` — `_probe_configured` runs 118 lines (`:1428-1545`): config read, five early-return classifications, URL validation, auth selection, the curl and a four-way status switch that duplicates `_probe_openai`'s 200/401/403/other handling. `head/.claude/skills/bridgebuilder-review/resources/config.ts:605` — `loadTrustedConfig` runs 110 lines (`:605-714`) mixing source selection, parsing, head-refusal, locality and exit-code validation. `head/.claude/scripts/adversarial-review.sh:3972` — `_adv_advisory_block` runs ~70 lines with a 25-line embedded jq program.
**Suggestion:** Split `_probe_configured` into describe/validate/auth helpers and reuse the existing OpenAI status switch; split `loadTrustedConfig` into `selectTrustedSource`, `refuseHeadOnly`, `readPosture`; move the advisory jq program to a named filter string. net: -60 lines possible.

### 7. Transport — `trust_env=False` also drops the operator's CA bundle under httpx

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/base.py:300` — for a policy hop the httpx client is built with `trust_env=False` (also `:397`, `:533`). In httpx that switch disables proxy discovery and `SSL_CERT_FILE`/`SSL_CERT_DIR` alike, while the urllib fallback still honours them through OpenSSL. An https local or opted-in hop presenting a private-CA certificate that the operator trusts via `SSL_CERT_FILE` fails TLS verification on a host with httpx installed and succeeds on one without. (Dissent DISS-C-005, confirmed against the head.)
**Suggestion:** Keep redirects and proxies off but pass an explicit `verify=ssl.create_default_context()` (which loads `SSL_CERT_FILE`/`SSL_CERT_DIR`), or disable proxies via `mounts`/`proxy=None` instead of `trust_env=False`, at the three sites; add a test with a self-signed local https stub.

### 8. Bridgebuilder vs cheval disagree on what a literal `auth` means

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:482` — any literal `auth` value without `{env:` is treated as keyless (`literalAuth`), while cheval normalises only the literal `"local"` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50`, `:139`) and treats any other literal as a real key. A trusted `auth: "sk-…"` provider therefore needs no env var in Bridgebuilder but is sent as a Bearer token by cheval; harmless today, but the D-8.0 doc on `ProviderDecl.keyless` (`core/types.ts:63`) states the broader rule as canonical.
**Suggestion:** Match cheval: keyless iff `keyless: true` or `auth` equals `local` (case-insensitive, trimmed).

### 9. `localhost` opt-in is resolved by the system resolver

- **LOW** (confidence: medium) `head/.claude/scripts/lib/endpoint-validator.py:1047` — `check_insecure_optin` admits `localhost` under the claim that an insecure endpoint "is never resolved, so it cannot be rebound" (`:1054`; repeated at `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:6`). An IP literal is not resolved; `localhost` is, by the OS resolver (`/etc/hosts`, nsswitch) at request time, and nothing in `TransportPolicy.check_url` (`providers/base.py:131-146`) verifies it resolves to loopback.
**Suggestion:** Either drop `localhost` from the opt-in (IP literals only) or resolve it in `TransportPolicy.check_url` and require every address to be loopback (fail closed on resolver error). Correct the two comments.

### 10. Advisory voices are still cut at the per-call timeout

- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:3920` — `_adv_advisory_walk` invokes each advisory hop with `$timeout` (`flatline_protocol.<gate>.timeout_seconds`, default 60 at `.loa.config.yaml.example:1623`); `advisory_timeout_seconds` (default 600) is only an outer bound on the group. The use case the example gives — a CPU server with `first_token_deadline_s: 120` (`:1253`) — is killed at 60 s before its own first-token deadline.
**Suggestion:** Either give advisory hops `min(advisory_timeout_seconds, per-hop deadline from the model's streaming_recovery)` or document that `timeout_seconds` still bounds each advisory call.

### 11. SURGICAL: prose trims outside the sprint's scope

- **LOW** (confidence: high) `head/.claude/skills/reviewing-code/SKILL.md:246` — this PR removes the worked example `("implemented in src/", "done")`, "(nothing after it)" after the trailer rule (`:253`), "(paths only)" (`:211`) and the matching phrases in `auditing-security/SKILL.md` (`:159`, `:238`, `:246`). These are prompt-budget trims unrelated to advisory voices; only the one-line "Read `advisory_voices[].findings` as advisory input" belongs to the sprint.
**Suggestion:** Land budget trims in their own commit with the `check-prompt-budget.sh` result, so the review of this sprint's behaviour is not mixed with edits to the reviewer's own instructions.

### 12. Graceful key mode now exits 3 on every run with an unset key

- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:490` — `voicesPlanned` is every configured voice minus the agy not-planned ones; a voice whose API key is unset under `api_key_mode: graceful` is planned but never runs, so `summarizeVoices` (`core/run-outcome.ts:25-48`) marks the run DEGRADED and `main.ts:750` exits 3. Any CI step that treats non-zero as failure now fails on a configuration that was explicitly "graceful" before. `exit_on_degraded: 0` is the rollback; `run-outcome.test.ts:52-61` pins the behaviour, so this is a deliberate contract change that needs the migration note (observation 4).

### 13. MODELINV records an unknown provider as a CLI subprocess

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:444` — `destination_for` returns `{host: cli-subprocess, scheme: cli}` whenever `not endpoint`, which includes a provider absent from `hounfour.providers` (`prov == {}`) or an HTTP provider with a missing endpoint. The audit row then makes a positive claim ("a local CLI") about a hop nothing verified. (Dissent DISS-C-004, confirmed against the head.)
**Suggestion:** Return the CLI sentinel only for `*-headless` types or `kind: cli` entries; for an unknown provider or missing endpoint return the `unknown`/`unknown` pair already used for an unparseable endpoint.

### 14. The schema-rejection heuristic also swallows an invalid schema

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101` — `_names_response_format` fires on any HTTP 400 whose body mentions `response_format` or `json_schema`, which includes hosted OpenAI's "Invalid schema for response_format …" for an operator's broken schema (and a 400 that echoes a prompt containing `json_schema`). The adapter then drops the schema, re-sends once and returns an unenforced answer with a WARNING; `schema_rejected_by_server: true` is recorded, so telemetry stays truthful, but the operator's error is masked and the hop's wall clock doubles inside the same `timeout_seconds`. (Dissent DISS-C-007, confirmed against the head.)
**Suggestion:** Match on the error's `param`/`code` (`error.param in ("response_format", "text.format")` with an "unsupported"/"unknown parameter" message) rather than substring presence, and do not retry when the message says the schema itself is invalid.

---

## Cross-Model Observations

Phase 2.5 ran `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --context-file reviewer-concerns.md --json`. Envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`: `metadata.status: clean`, `metadata.model: gpt-5.5-pro`, companion `claude-headless` succeeded (`counted_as: independent_voice`), 7 findings (1 BLOCKING, 6 ADVISORY), hallucination filter applied with 0 downgrades. Each was re-verified against `pr/head/` (the dissent escalated context from this workspace's newer framework copy, so anchors were checked by hand):

- DISS-C-001 (BLOCKING, `cheval.py:541`) — confirmed in the head: a provider-block `dispatch_group: local` is honoured by the planners but not by `_build_provider_config`, `_transport_policy` or `hop_locality_of`. Folded into Changes Required 1 (it forces CHANGES_REQUIRED on its own).
- DISS-C-002 (ADVISORY, `cheval.py:2195`) — not reproducible: `_preflight_head` is assigned unconditionally from `_chain.entries[0]` at `cheval.py:2020` before the emit site.
- DISS-C-003 (ADVISORY, `cheval.py:3032`) — not reproducible: `_modelinv_state["final_model_id"]` is set to `_entry_target`, the canonical `provider:model` hop (`cheval.py:2804`), and the E2E test asserts the destination on the success path.
- DISS-C-004 (ADVISORY, `modelinv.py:444`) — confirmed; observation 13.
- DISS-C-005 (ADVISORY, `base.py:301`) — confirmed at three sites; observation 7.
- DISS-C-006 (ADVISORY, `ledger.py:170`) — not reproducible in the readers checked: `rollup.py` was updated in this PR and `cost-report.sh:426-438` classifies by `unknown`/absent and `pricing_resolution` (which the ledger still sets for `stale_catalog`), so stale rows stay priced. Worth a grep when new ledger consumers land.
- DISS-C-007 (ADVISORY, `openai_adapter.py:101`) — confirmed; observation 14.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-review*.jsonl` sidecar exists beside the envelope.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required 1 and 2 above; the report has no `## AC Verification` section, no stated assumptions and no self-check record |

---

## Acceptance Criteria Check

`sprint.md` names one task and the PR title's four deliverables; there is no per-AC list, so the PR title's claims are checked.

### Task 1.1: sprint-257 — advisory open-weight voices, local_voices posture, Bridgebuilder trusted configuration and exit codes, E2E

| Criterion | Status | Notes |
|-----------|--------|-------|
| Advisory voices run after the counted voices; findings only under `advisory_voices[]`; the counted envelope unchanged | Pass | `head/.claude/scripts/adversarial-review.sh:3914-4030`, `:4855-4873`; ADV-1…9 assert it; sidecar disabled for advisory walkers (`:3918`) so `verdict-derive.sh` counts none |
| Budget gate prices every planned voice at catalog price | Pass (doc Fail) | `:3866-3912`, `:4320-4341`; the example's `budget_cents` comment contradicts it (observation 3) |
| `hounfour.locality: local_voices` refuses hosted hops by name in dissent, Flatline, Bridgebuilder, probe | Fail | Refusal mechanics work (LOC-1…8, FLL-1…7, `applyLocality`), but "local" is a label with no endpoint check and three readings of the label — Changes Required 1 |
| Endpoint opt-in: one validator for cheval, bash and probe; http only to the opted-in loopback/RFC1918 host; redirects/proxy refused | Pass | `endpoint-validator.py:1017-1177`, `endpoint_policy.py`, `base.py:117-162`; verified the shipped defaults still admit; `localhost` caveat (observation 9); CA-bundle caveat (observation 7) |
| Keyless providers send no credential; `auth: "local"` normalised | Pass | `openai_adapter.py:169-173`, `endpoint_policy.py:126-141`, `loader.py:645-648` |
| Chat path sends `response_format` json_schema when `structured_json`; 400 retried once without it; telemetry truthful | Pass (heuristic caveat) | `openai_adapter.py:433-446`, `:188-210`; tests `test_openai_chat_schema.py`; observation 14 |
| Thinking traces stripped/recorded on streaming and non-streaming paths | Pass | `openai_streaming.py:48-97`, `:209-220`; `test_openai_thinking_strip.py` |
| MODELINV carries destination / locality_mode / hop_locality / thinking_stripped / schema_rejected_by_server; schema updated | Pass (semantic Fail) | `modelinv.py:423-498`, schema `model-invoke-complete.payload.schema.json:815-840`; `hop_locality` records the label (Changes Required 1); unknown provider recorded as CLI (observation 13) |
| Bridgebuilder reads providers/locality/exit from trusted config; head-only keyless/insecure refused | Partial | Planner-side only; cheval reads the checkout (Changes Required 2) |
| Bridgebuilder exits 3 on DEGRADED after writing JSON; callers surface a WARN; `entry.sh` preflight exits 4 | Pass (dispatcher caveat) | `main.ts:740-750`, `run-outcome.ts`, `spiral-harness.sh:697-711`, `entry.sh:118-120`; dispatcher converts an unproven exit 3 to 0 (observation 1) |
| Health probe `--provider <configured>` | Partial | Works for opted-in loopback hosts; https configured hosts refused by the probe allowlist (observation 2) |
| E2E local hop test | Pass | `test_openai_local_hop_e2e.py` stands up a 127.0.0.1 server and asserts headers, body, MODELINV row and schema validity |
| Catalog price provenance | Pass | `pricing.py:316-375`, `test_catalog_pricing_provenance.py`; no open-weight entry ships |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (fixture keys in tests only; `describe_provider` returns the env var name, never the value)
- [x] Input validation and sanitization present at the shell boundaries (hop names, aliases, locality value, exit codes validated before `jq`/`yq`; envelopes travel as files)
- [ ] Authentication/authorization correct — the locality posture and the trusted-config boundary do not hold (Changes Required 1, 2)
- [x] No SQL/XSS injection vulnerabilities (not applicable; shell injection surfaces reviewed)
- [x] Dependencies secure (no new dependency; `idna` import made lazy with a fail-closed fallback)
- [x] Error messages don't leak sensitive data (opt-in refusals quote the host; probe reasons are capped; MODELINV messages redacted)

---

## Code Quality Summary

**Strengths:**
- One canonical endpoint rule reused by three callers, with a case table run through both entry points (`test_endpoint_validator_optin.py`).
- The advisory block is assembled from files, never argv, and its sidecar is disabled so the existing verdict tooling needs no change; ADV-2 proves the counted envelope is byte-identical.
- Fail-closed defaults throughout: unreadable classifier → hosted; invalid locality → refused with the value named; missing validator module → ConfigError.
- The TransportPolicy covers httpx and urllib, streaming and non-streaming, with tests that use a real local server and a dead proxy.

**Areas for Improvement:**
- The same rule ("what is local") implemented four times in three languages, with three readings.
- A security control (trusted config) placed on the planner while the dispatcher reads a different file.
- Long functions in new shell and TypeScript code; a stale budget comment left beside the new one.
- The implementation report is a title line: no AC walkthrough, no assumptions, no self-check record.

---

## Next Steps

1. Address Changes Required 1 and 2 (one local-hop rule enforced at load, plan, request and record time; close or honestly document the Bridgebuilder/cheval configuration gap).
2. Fix the dispatcher exit-3 guard, the probe allowlist mode and the httpx CA-bundle regression; reconcile the budget comment; add the CHANGELOG/migration entry.
3. Add the missing tests named under observation 5; record formatter, type-check, `pytest` and `bats` results.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough (`file:line` + symbol per criterion).
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":7,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:00:00Z"} -->
