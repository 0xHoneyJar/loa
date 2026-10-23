# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

Scope: `pr/head.diff` — PR sprint-257 (cycle-129), 80 files (23 generated `dist/` artefacts), 6,606 insertions / 221 deletions. Citations are `head/<path>:<line>` with line numbers from `pr/head/`. Prerequisite note: the review (`engineer-feedback.md`) ended CHANGES_REQUIRED, so the skill's Phase 0 gate ("All good") is not met; the task instruction orders this audit to run regardless, and it has, with the review's two blocking findings re-verified independently below. `grimoires/loa/known-failures.md` is absent (WARN at session start); `br` is not installed; no documentation-coherence subagent reports exist, so the documentation checks were done by hand (SKILL.md, README, `.loa.config.yaml.example`, the two reference docs, the MODELINV schema).

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint adds four security-relevant mechanisms: a per-provider insecure-endpoint opt-in with a request-time TransportPolicy, the `hounfour.locality: local_voices` confidentiality posture, Bridgebuilder's trusted-configuration source for provider declarations, and keyless/open-weight providers with advisory dissent voices. The endpoint rule itself is sound where it is applied: I ran the head validator against the shipped default endpoints (all admit, including the templated Bedrock host) and an opt-in edge table (host mismatch, userinfo, traversal, metadata, IPv6 ULA, `host:port` opt-ins all refused), the shell operands that reach `jq`/`yq`/`python3` are validated or passed as files, and the PR's six Python suites pass in a head-over-framework tree (123 tests).

Two findings block the merge, both re-verified against the head and both also raised by the review. First, `local_voices` is decided by a label: a provider whose endpoint is `https://api.together.xyz/v1` and whose model carries `dispatch_group: local` is classified `local` by `hop-locality.py`, accepted by `validate_providers`, dispatched by cheval, and recorded as `hop_locality: local` in MODELINV; cheval reads the locality switch for telemetry only and never enforces it, and the label is read from different places by the planners and the transport. Second, Bridgebuilder's trusted configuration governs its planner only; every voice still dispatches through cheval, which loads the checkout's `.loa.config.yaml`, so the new SKILL.md sentence promising trusted precedence "even when the checkout is a PR head" is not delivered.

The cross-model dissent (two voices, `gpt-5.5-pro` + `claude-headless`, 7 findings, none rejected) added one medium of its own: the loader admits `allow_insecure_endpoint` on any HTTP provider type while only the OpenAI adapter applies the TransportPolicy. No critical finding; nothing excluded from the tally.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 6 |
| Low | 11 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The `local_voices` posture is a declaration, not a verified property

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/lib/hop-locality.py:116` (classifier); the same label-only rule at `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` (`hop_locality_of`), `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221` (`_transport_policy`), `head/.claude/skills/bridgebuilder-review/resources/config.ts:726` (`isLocalVoice`); the label read from the model entry only at `head/.claude/adapters/cheval.py:541`; no load-time refusal at `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143` (`validate_providers`).
**Issue:** The classifier's rule is
```python
group = entry.get("dispatch_group") or block.get("dispatch_group") or ""
if group != "local":
    return provider, "hosted", f"dispatch_group={group or 'unset'}"
```
(`hop-locality.py:116-118`). Nothing examines the endpoint. Reproduced against the head with the shipped catalog plus this overlay:
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
```
```
$ python3 -I hop-locality.py --catalog model-config.yaml --config overlay.yaml -- hosted-oss:llama-70b
hosted-oss:llama-70b	hosted-oss	local	dispatch_group=local
$ validate_providers(overlay)   # endpoint_policy.py:143
(no error)
```
So `adversarial-review.sh` (`_adv_locality_filter`) and `flatline-orchestrator.sh` (`flatline_locality_gate`) plan the hosted hop, Bridgebuilder's `isLocalVoice` keeps it (it does not consult `fallback_chain`, unlike the Python classifier), cheval dispatches it to the public host under a TransportPolicy meant for loopback, and MODELINV records `hop_locality: local`. Inversely (dissent DISS-C-004, confirmed): a `dispatch_group: local` on the PROVIDER block is honoured by `hop-locality.py:116` and `isLocalVoice`, but `_build_provider_config` reads only `model_data.get("dispatch_group")` (`cheval.py:541`), so `_transport_policy` returns `None` and `hop_locality_of` says `hosted` — a hop planned as local runs with proxy env honoured and redirects followed, and the audit row contradicts the planner. cheval itself never enforces the switch: `grep locality cheval.py` shows only the two telemetry emit sites (`cheval.py:2194`, `:3028`), so under `local_voices` the one process that sends the prompt has no rule of its own (dissent DISS-C-003, substance confirmed).
**Impact:** The posture's stated guarantee (`.loa.config.yaml.example:1227-1233`: the prompt "does not cross a public network") is defeated by one YAML key on any provider, silently, with an audit trail that asserts the opposite. The trigger is a misconfiguration, but the PR title advertises hosted open-weight voices, and the example's comment `dispatch_group: local  # marks the hop local` invites copying the block onto a hosted provider.
**Fix:** Define "local" as a property the loader can check: an HTTP provider (not `*-headless`, not `kind: cli`) whose endpoint host passes `check_insecure_optin` (loopback, RFC1918, `localhost`). Refuse `dispatch_group: local` in `validate_providers` on any provider that fails it. Resolve the label once (entry, else provider block) and apply the same rule in `hop_locality_of`, `_transport_policy`, `hop-locality.py` and `isLocalVoice` (including `fallback_chain`). Under `local_voices`, refuse a hosted hop inside cheval at dispatch time as well as in the planners. Add one negative test per surface (hosted endpoint labelled local; provider-block label through cheval).
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html; CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [HIGH-002] Bridgebuilder's trusted configuration never reaches the process that sends the prompt

**Severity:** HIGH (confidence: medium)
**File:** `head/.claude/skills/bridgebuilder-review/SKILL.md:117-118` (the claim); `head/.claude/skills/bridgebuilder-review/resources/config.ts:605` (`loadTrustedConfig`), `:672-690` (head read only for keyless/insecure booleans), `:104` (`loadMultiModelConfig` reads the checkout's `.loa.config.yaml`); `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:224-225` (keyless voice handed to the cheval delegate with no key).
**Issue:** `headOnlyRefused` compares two booleans per provider:
```ts
const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
```
(`config.ts:684-685`). A PR head that leaves `keyless`/`allow_insecure_endpoint` as the base declares them but rewrites `endpoint` to `https://attacker.example/v1`, re-points `hounfour.aliases.<voice>`, or widens `secret_env_allowlist`, passes every check; `validate_declared_endpoint` admits any https host (verified: `https://api.together.xyz/v1` → valid), cheval loads the checkout's config and dispatches the review prompt there, with a `{env:VAR}` Bearer credential for a keyed trusted provider. The voice list itself (`bridgebuilder.multi_model.models`) is also read from the checkout (`config.ts:104`). The pre-existing SKILL.md text records the invocation model as "no PR-head checkout" (`:116-117`); the sentence this PR adds (`:117-118`) asserts protection in exactly that case.
**Impact:** The feature's purpose (D-7.5) is that an attacker-controlled head cannot declare its way to a credential or an insecure hop. The control is placed in the planner while the dispatcher reads a different file, and the documentation now promises more than the code holds. Confidence is medium because the shipped scheduled path (`dispatcher.sh --repo`) runs in local mode on a trusted checkout; the exposure is the `--pr`/PR-event path the PR documents.
**Fix:** Either (a) on a pull request compute drift between the head's and the trusted view's `hounfour.providers`, `hounfour.aliases`, `hounfour.locality` and `secret_env_allowlist`, and refuse the multi-model run with a distinct exit code on any difference; or (b) hand the trusted configuration to cheval explicitly (a config path it loads instead of the checkout's). Correct SKILL.md to state exactly what is protected. Add a test where the head changes only `endpoint` of a trusted keyless provider.
**Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html; CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html; OWASP A08:2021 Software and Data Integrity Failures — https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/

---

## Medium/Low Priority Issues

### [MED-001] The request-time half of D-7.2 applies to OpenAI-type providers only
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:153-156`; `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221`
- **Issue:** `validate_providers` admits `allow_insecure_endpoint` on every non-CLI provider type (reproduced: `type: anthropic`, `endpoint: http://10.0.0.6:8080`, opt-in `10.0.0.6` → accepted). Only `OpenAIAdapter._transport_policy` builds a `TransportPolicy`; `anthropic_adapter.py` and `google_adapter.py` (untouched by the PR) call `http_post_stream` with no `policy`, so for such a provider proxy environment variables are honoured and the urllib fallback follows redirects, while the module docstring (`endpoint_policy.py:26-28`) promises the rules for "an opted-in provider". Dissent DISS-C-001, confirmed.
- **Fix:** Refuse `allow_insecure_endpoint` at load unless `type` is `openai`/`openai_compat` (the probe already refuses other types at `model-health-probe.sh:1457-1464`), or apply the policy in every adapter.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html; CWE-319 Cleartext Transmission — https://cwe.mitre.org/data/definitions/319.html

### [MED-002] `trust_env=False` also discards the operator's CA bundle under httpx
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/providers/base.py:300`, `:397`, `:533`
- **Issue:** `httpx.Client(trust_env=False, follow_redirects=False, …)` disables `SSL_CERT_FILE`/`SSL_CERT_DIR` along with proxy discovery; the urllib fallback still honours them through OpenSSL. An https local or opted-in hop with a private-CA certificate fails verification on a host with httpx and succeeds on one without, which nudges operators toward disabling verification.
- **Fix:** Keep redirects and proxies off but pass `verify=ssl.create_default_context()` (which loads the env bundle), or disable proxies via `proxy=None`/`mounts` instead of `trust_env=False`; add a self-signed https stub test.
- **Reference:** CWE-295 Improper Certificate Validation — https://cwe.mitre.org/data/definitions/295.html

### [MED-003] The dispatcher turns any exit 3 into success without proof of a review
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-90`
- **Issue:** `rc == 3` is recorded `degraded: true` and converted to `exit 0` (`:89-90`) without checking that `bb-stdout.json` holds a run JSON; an exit 3 from a shell error inside `entry.sh`, a wrapper, or a mixed-version `dist/` is reported as a completed review. None of the four dispatcher cases in `head/tests/unit/bb-exit-degraded-callers.bats:39-65` covers exit 3 with empty stdout.
- **Fix:** Treat 3 as completed-degraded only when `[[ -s "$BB_OUT" ]] && jq -e '.verdicts | type == "array"' "$BB_OUT"`; otherwise log an ERROR and `exit 3`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-004] The probe refuses configured https providers through its own allowlist
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/model-health-probe.sh:1469-1475`
- **Issue:** `_probe_configured` validates `<endpoint>/models` with `--allowlist "$PROBE_PROVIDERS_ALLOWLIST"` (the full pipeline including the step-8 host allowlist) while the cheval loader admits the same provider through `validate_declared_endpoint` (allowlist skipped). Example 3 (`azure-openai`, `.loa.config.yaml.example:1204-1224`) is reported `UNKNOWN / endpoint_refused`; the header comment at `:852-856` ("exactly as on the cheval path") is not true.
- **Fix:** Add a `--declared-endpoint` mode to `endpoint-validator.py`/`.sh` and use it for configured providers; add an https non-allowlisted bats case.
- **Reference:** OWASP A05:2021 — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [MED-005] Security-relevant contract changes ship without CHANGELOG/migration notes
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/README.md:22`, `:32`; `head/.claude/skills/bridgebuilder-review/SKILL.md:161-162`; `head/.claude/skills/bridgebuilder-review/resources/entry.sh:118-120`
- **Issue:** The README links a CHANGELOG entry and "Migration notes", but `CHANGELOG.md` is not among the touched files, and this sprint changes caller-visible contracts: exit 3 now means DEGRADED and the missing-dependency preflight moved to exit 4, `http://` provider endpoints without an opt-in now fail config load, `pricing_source: stale_catalog` appears in ledger rows, and the budget estimate changed. The documentation audit treats a CHANGELOG omitting security changes as a blocker-class item.
- **Fix:** Add the CHANGELOG entry and migration notes in this PR (exit-code contract, `exit_on_degraded: 0`, the load-time endpoint rule, the budget arithmetic), or state in the PR description where they landed.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-006] No negative tests on the security paths; no self-check record in the report
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/tests/unit/adversarial-review-locality.bats:68` (LOC-1..8), `head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts:110`
- **Issue:** The tests pin the implemented behaviour precisely (I ran the six Python suites: 123 passed), but none covers a hosted-endpoint provider labelled `local`, a provider-block label through cheval, a non-OpenAI type with an opt-in, dispatcher exit 3 with empty stdout, the probe with an https configured host, or a PR head that changes only `endpoint` of a trusted provider. The implementation report (`reviewer.md`) is the PR title and records no formatter, type-check, `bats` or `pytest` run; the bats and TypeScript suites could not be run here (partial tree, no `node_modules`).
- **Fix:** Add one test per gap above; record the self-checks (commands and results) in the report.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [LOW-001] A real credential may travel in cleartext to an opted-in LAN host, as the example recommends
- **Severity:** LOW (confidence: high)
- **File:** `head/.loa.config.yaml.example:1235-1237`; `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:143`
- **Issue:** `validate_providers` admits a keyed provider over `http://` to any RFC1918 host (reproduced: `http://10.0.0.5:8000/v1` with `auth: "{env:OPENAI_API_KEY}"`), and `OpenAIAdapter` then sends `Authorization: Bearer` in cleartext; the example recommends `auth: "{env:LOCAL_LLM_KEY}"` for such servers. Dissent DISS-C-002, confirmed; rated LOW because the pairing is explicit and LAN-scoped.
- **Fix:** WARN at load when an http opt-in provider carries a non-keyless `auth`; steer keyed providers to https or loopback in the example.
- **Reference:** CWE-319 — https://cwe.mitre.org/data/definitions/319.html

### [LOW-002] `localhost` is resolved at request time; the comments say it never is
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/lib/endpoint-validator.py:1047`, `:1054`; `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:6`
- **Issue:** The opt-in admits `localhost` under the claim that an insecure endpoint "is never resolved, so it cannot be rebound"; httpx/urllib resolve it through the OS resolver and `TransportPolicy.check_url` never checks the resolved address.
- **Fix:** Restrict the opt-in to IP literals, or resolve `localhost` in `check_url` and require loopback (fail closed); correct both comments.
- **Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [LOW-003] A declared endpoint may carry a token in its query string, which tooling then prints
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/scripts/lib/endpoint-validator.py:1080` (`validate_declared_endpoint`); `head/.claude/scripts/model-health-probe.sh:1505`
- **Issue:** Verified with the head validator: `https://api.example.com/v1?api_key=SECRET` and the opted-in http form are admitted (userinfo is refused with "credentials must travel via env vars, not URLs"; the query string is not). `describe-provider` prints the endpoint verbatim and the probe logs `probing configured provider … at $url`, both documented as never printing a secret. Dissent DISS-C-007, partially confirmed (the CLI-provider path is not printed).
- **Fix:** Refuse a non-empty query or fragment in a declared endpoint (`ENDPOINT-QUERY-PRESENT`).
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html; CWE-598 — https://cwe.mitre.org/data/definitions/598.html

### [LOW-004] The schema-rejection heuristic is server-controlled and re-sends the prompt
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:101-111`, `:203`
- **Issue:** Any HTTP 400 whose body mentions `response_format` or `json_schema` drops the strict schema and re-sends the full prompt once, so a server can switch enforcement off at will and double the spend; an operator's invalid schema ("Invalid schema for response_format") is masked. `schema_rejected_by_server` keeps telemetry truthful. Dissent DISS-C-006, confirmed.
- **Fix:** Match `error.param`/`code` for an unsupported parameter only; do not retry when the message says the schema itself is invalid.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-005] MODELINV records an unknown provider as a CLI subprocess
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:444`
- **Issue:** `destination_for` returns `{host: cli-subprocess, scheme: cli}` whenever `not endpoint`, which includes a provider absent from `hounfour.providers` or an HTTP provider with a missing endpoint; the tamper-evident chain then makes a positive claim nothing verified. Dissent DISS-C-005, confirmed.
- **Fix:** Return the CLI sentinel only for `*-headless` types or `kind: cli` entries; otherwise `unknown`/`unknown`.
- **Reference:** CWE-223 Omission of Security-relevant Information — https://cwe.mitre.org/data/definitions/223.html

### [LOW-006] Bridgebuilder and cheval disagree on what a literal `auth` means
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:482`; `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50`
- **Issue:** Any literal `auth` without `{env:` is keyless in Bridgebuilder (`literalAuth`); cheval normalises only `"local"` and sends any other literal as a Bearer token.
- **Fix:** Match cheval: keyless iff `keyless: true` or `auth` equals `local`.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [LOW-007] Advisory voices are still cut at the per-call timeout
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/adversarial-review.sh:3920`; `head/.loa.config.yaml.example:1257`
- **Issue:** `_adv_advisory_walk` invokes each advisory hop with `$timeout` (`timeout_seconds`, default 60); `advisory_timeout_seconds` only bounds the group. The example's CPU server (`first_token_deadline_s: 120`) is killed before its own first-token deadline.
- **Fix:** Use `min(advisory_timeout_seconds, per-hop deadline)` or document that `timeout_seconds` bounds each advisory call.
- **Reference:** CWE-400 Uncontrolled Resource Consumption (availability) — https://cwe.mitre.org/data/definitions/400.html

### [LOW-008] The example's budget contract contradicts the code
- **Severity:** LOW (confidence: high)
- **File:** `head/.loa.config.yaml.example:1624-1627`, `:1690`; `head/.claude/scripts/adversarial-review.sh:4320-4341`
- **Issue:** The comments still say the gate prices "ONE dissent call" and that the companion is a call it does not count, while the gate now sums the primary, the companion's first hop and every advisory voice at catalog price.
- **Fix:** Rewrite both `budget_cents` comments to the summed contract and state the default-config consequence.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-009] Graceful key mode now exits 3 on every run with an unset key
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:490`; `head/.claude/skills/bridgebuilder-review/resources/core/run-outcome.ts:46`; `head/.claude/skills/bridgebuilder-review/resources/main.ts:750`
- **Issue:** A voice whose key is unset under `api_key_mode: graceful` is planned but never runs, so the run is DEGRADED and exits 3; CI steps treating non-zero as failure break. Deliberate (pinned by `run-outcome.test.ts:52-61`) but undocumented for upgraders; `exit_on_degraded: 0` is the rollback.
- **Fix:** Cover in the migration notes (MED-005).
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-010] Three new functions well over the 50-line ceiling
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/scripts/model-health-probe.sh:1428` (`_probe_configured`, 118 lines); `head/.claude/skills/bridgebuilder-review/resources/config.ts:605` (`loadTrustedConfig`, 110 lines); `head/.claude/scripts/adversarial-review.sh:3972` (`_adv_advisory_block`, ~70 lines with an embedded jq program)
- **Fix:** Split into describe/validate/auth helpers (reusing `_probe_openai`'s status switch); `selectTrustedSource`/`refuseHeadOnly`/`readPosture`; a named jq filter.
- **Reference:** Clean Code, Functions (ARCH-CX rubric)

### [LOW-011] Prompt trims outside the sprint's scope
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/skills/reviewing-code/SKILL.md:246`, `:253`, `:211`; `head/.claude/skills/auditing-security/SKILL.md:159`, `:238`, `:246`
- **Issue:** Worked examples and clarifying phrases in the reviewer's and auditor's own instructions are removed in a sprint about advisory voices; only the one-line "Read `advisory_voices[].findings` as advisory input" belongs here.
- **Fix:** Land budget trims in their own commit with the `check-prompt-budget.sh` result.
- **Reference:** Karpathy principle 3 (surgical changes)

---

## Observations

No finding was marked speculative/low-confidence for exclusion; the tally above counts every finding. The review's trailer excluded 0 findings, so there was nothing to confirm (`excluded_confirmed: 0`).

Verified safe (not findings): shell operands reaching `jq`/`yq` are validated (`_adv_conf_advisory_voices` regex, `_conf_uint`, locality enum) or travel as files; hop names reach `hop-locality.py` after `--`; `isSafeRefName` guards the git ref and all git/gh/yq calls use `execFileSync` without a shell; the probe's `${!auth_env}` indirect expansion is behind the loader's `secret_env_allowlist` and a `[A-Za-z_][A-Za-z0-9_]*` name regex; `endpoint_validator__guarded_curl` runs an opted-in call with `--proto =http,https --max-redirs 0 --noproxy '*'`; the advisory walkers are reaped on every exit path; `emit_model_invoke_complete` validates the new enums; the shipped default envelope loads unchanged (`test_hosted_defaults_still_load_unchanged`, re-run here).

---

## Cross-Model Security Observations

Phase 1C ran `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` (no context file). Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`: `metadata.status: clean`, `metadata.model: gpt-5.5-pro`, companion `claude-headless` succeeded (`counted_as: independent_voice`), `voices_planned: 2 / succeeded: 2`, 7 findings (4 MEDIUM, 3 LOW), hallucination filter applied with 0 downgrades, `metadata.locality: null`. Not a degraded review. Some anchors name symbols (`hop_is_local`, `_local_labels`) that do not exist in the head — the dissent escalated context from this workspace's newer framework copy — so each was checked by hand against `pr/head/`:

- DISS-C-001 (MEDIUM, `endpoint_policy.py:validate_providers`) — confirmed; MED-001.
- DISS-C-002 (MEDIUM, `openai_adapter.py:complete`) — confirmed; recorded as LOW-001 (explicit, LAN-scoped configuration).
- DISS-C-003 (MEDIUM, `loader.py:load_config`) — the named loader function does not exist in the head; the substance (cheval reads `locality` for telemetry only, no dispatch-time enforcement) is confirmed and folded into HIGH-001's fix.
- DISS-C-004 (MEDIUM, `cheval.py:_build_provider_config`) — confirmed; folded into HIGH-001 (provider-block label).
- DISS-C-005 (LOW, `modelinv.py:destination_for`) — confirmed; LOW-005.
- DISS-C-006 (LOW, `openai_adapter.py:_names_response_format`) — confirmed; LOW-004.
- DISS-C-007 (LOW, `endpoint_policy.py:describe_provider`) — partially confirmed (query strings admitted and printed; CLI-provider endpoints are not printed); LOW-003.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| Security | 3 | Sound endpoint rule and fail-closed defaults; the posture and trusted-config controls do not hold (HIGH-001, HIGH-002, MED-001) |
| Architecture | 3 | One rule ("what is local") implemented four times in three languages with three readings; planner and dispatcher read different configs |
| Code Quality | 4 | Precise tests for the implemented behaviour (123 Python tests pass); negative cases missing; three oversized functions |
| DevOps | 3 | Exit-code contract change with a lenient dispatcher and no migration notes; probe allowlist mismatch |
| Blockchain/Crypto | n/a | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixture keys in tests only; `describe_provider` returns the env var name, never the value)
- [x] Input validation on all new entry points (hop names, aliases, locality value, exit codes, `--provider` names validated before `jq`/`yq`/`python3`; envelopes as files)
- [ ] Authentication/authorization correct where needed — the locality posture and the trusted-config boundary do not hold (HIGH-001, HIGH-002); the TransportPolicy covers one adapter (MED-001)
- [x] No SQL/XSS injection vulnerabilities (not applicable; shell and jq injection surfaces reviewed)
- [x] Error handling doesn't leak info (probe reasons capped; MODELINV messages redacted) — except an endpoint query string (LOW-003)
- [ ] Tests cover security paths — the implemented paths yes, the failure modes no (MED-006)

---

## Next Steps

**CHANGES_REQUIRED:**
1. Address HIGH-001 and HIGH-002: one checkable definition of "local" enforced at load, plan, dispatch and record time; close or honestly document the Bridgebuilder → cheval configuration gap and correct SKILL.md.
2. Address the mediums: restrict the opt-in to adapters that apply the TransportPolicy, keep the CA bundle under httpx, guard the dispatcher's exit-3 conversion, give the probe a declared-endpoint validator mode, add the CHANGELOG/migration notes, add the negative tests and record the self-checks.
3. Run `/implement sprint-1` to fix issues, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":6,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:20:00Z"} -->
