# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff` — sprint-257, cycle-129: advisory open-weight voices, `local_voices` posture, Bridgebuilder trusted configuration and exit codes, E2E)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)

Citations are `head/<path>:<line>` with line numbers in the post-change files (for files not copied under `pr/head/`, derived from the `pr/head.diff` hunk headers). The workspace `.claude/` tree is a later revision than the PR head; every finding below was verified against the head diff, not the workspace.

---

## Overall Assessment

The change is large (80 files, +6686/−301) and mostly well built: one endpoint rule shared by the cheval loader, the bash validator and the probe (`endpoint_policy.py` loads the canonical `endpoint-validator.py` by path, and `test_endpoint_validator_optin.py` runs one 31-case table through both); a real stub-server E2E through `cheval.cmd_invoke` with the MODELINV payload validated against the shipped schema; the advisory-voice envelope proven byte-identical with and without advisory voices (ADV-2); the Bridgebuilder exit-3 contract covered on both shell callers; and the `.build-manifest.json` hash for the new `run-outcome.ts` reproduces from the diff.

Two defects block the merge. First, the `local_voices` posture is **declared, not enforced**: every classifier (`hop-locality.py`, Bridgebuilder `isLocalVoice`, cheval `hop_locality_of` / `_transport_policy`) treats `dispatch_group: local` as the truth and never checks that the provider's endpoint host is loopback, RFC1918 or `localhost`, so a hosted provider relabelled `local` in `.loa.config.yaml` is planned and dispatched to its public endpoint under the posture that promises prompts stay on the host. Second, the Bridgebuilder "trusted configuration" gates only Bridgebuilder's *planning*; the request itself goes through cheval, which loads the checkout's `.loa.config.yaml`, so on a PR-head checkout the head can still redirect a trusted provider's `endpoint` and receive the environment credential — while the skill doc and a code comment now claim the opposite. The cross-model dissent (two voices, both completed) reached the second defect independently (DISS-C-003) and added two medium gaps around the same locality rule.

Process note: the implementation report (`pr/PR.md`) carries no `## AC Verification` walkthrough; under this skill's Phase 4 that alone is an automatic CHANGES_REQUIRED. It is recorded here; the verdict rests on the code findings.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security / Locality posture — `dispatch_group: local` is trusted, never checked against the endpoint

- **HIGH** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116-117` — a hop is classified `local` purely because its model entry or provider block says `dispatch_group: local`; the provider's `endpoint` host is never consulted, so a hosted provider carrying that label is planned under `local_voices` and its prompt leaves the machine.
**File:** `head/.claude/scripts/lib/hop-locality.py:116` (`group = entry.get("dispatch_group") or block.get("dispatch_group")`), `:117` (`if group != "local"`), `:134` (returns `local`, reason `dispatch_group=local`)
**Also:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-730` (`isLocalVoice` — same rule, same gap), `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` (`hop_locality_of` records `hop_locality: local` from the label alone), `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221` (`_transport_policy` puts a `dispatch_group: local` model under the "local" transport rules whatever its endpoint), `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:160-176` (`validate_providers` requires a keyless provider to *declare* `dispatch_group` but never relates `local` to the endpoint host).
**Issue:** Concrete failing input: with `hounfour.locality: local_voices` and this project config
```yaml
hounfour:
  providers:
    openai:
      models:
        gpt-5.5:
          dispatch_group: local
```
`hop-locality.py -- gpt-5.5` prints `gpt-5.5<TAB>openai<TAB>local<TAB>dispatch_group=local`; `adversarial-review.sh` keeps `gpt-5.5` on the primary chain (`_adv_locality_filter`), Flatline's gate passes it, Bridgebuilder keeps it (`applyLocality`), cheval records `hop_locality: local` beside `destination.host: api.openai.com`, and the diff is POSTed to api.openai.com. The module docstring (`:18-19`) promises "Fail closed — a hop is never called local because it could not be read", but it is called local because it was *labelled* so. `dispatch_group` is a billing/routing key the catalog already uses for other values (`openai-gpt`, `azure`), so one stale or copied line defeats FR-8's guarantee silently.
**Why This Matters:** FR-8's whole point is that under `local_voices` no prompt reaches a hosted provider. A posture that can be undone by one declarative line, with no refusal and no warning, is weaker than having no posture, because operators will trust it. D-8.1 is a *locality* rule, not a label rule.
**Required Fix:** Define the local-hop rule once and enforce it everywhere the label is read: a hop is `local` only when its provider is an HTTP provider (not `*-headless` / `kind: cli`) whose `endpoint` host is an IP literal in 127.0.0.0/8, ::1, 10/8, 172.16/12, 192.168/16, or the literal `localhost` — the same acceptance as `check_insecure_optin`. (a) At load, `validate_providers` refuses `dispatch_group: local` on a CLI provider or on an endpoint whose host fails the rule, with a named `ConfigError`. (b) `hop-locality.py` classifies by the rule (reason `endpoint_not_local:<host>` / `cli_provider` / `endpoint_missing`), and `isLocalVoice` reads the declared endpoint the same way. (c) `TransportPolicy` for a local hop refuses by name a request host that fails the rule. Add the negative tests: a `dispatch_group: local` model on `https://api.openai.com/v1` is hosted on every path (bats LOC-*, FLL-*, `trusted-config.test.ts`, a loader pytest).
**Reference:** CWE-284 (Improper Access Control), CWE-807 (Reliance on Untrusted Inputs in a Security Decision)

### 2. Security / Trust boundary — "trusted configuration" does not reach the dispatch path, and the docs now say it does

- **HIGH** (confidence: high) `head/.claude/skills/bridgebuilder-review/SKILL.md:118` — states that "the provider, locality and exit keys follow the trusted-source precedence below even when the checkout is a PR head", but every planned voice is dispatched through cheval, which loads the *checkout's* `.loa.config.yaml` (the PR head); a head that leaves `keyless` / `allow_insecure_endpoint` alone and only changes a trusted provider's `endpoint` is neither refused nor noticed, and the environment credential follows the request.
**File:** `head/.claude/skills/bridgebuilder-review/SKILL.md:118`, `:169-184` (the trust table); `head/.claude/skills/bridgebuilder-review/resources/config.ts:440` (comment: "never the head's, so a head cannot point a credential at a provider of its choosing"); `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:224-225` (the voice is dispatched with the env credential once the trusted view admits the provider); `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:114-120` (`check_endpoint` → `validate_declared_endpoint`, which skips the host allowlist: `head/.claude/scripts/lib/endpoint-validator.py:1080-1087`, `:1291-1296`)
**Issue:** `loadTrustedConfig` reads only `hounfour.providers`' `keyless` / `allow_insecure_endpoint` / `auth` / `dispatch_group`, `hounfour.locality` and `exit_on_degraded`; `headOnlyRefused` compares only the keyless and insecure flags. The adapter (`cheval-delegate.ts`) spawns `cheval.py` from `process.cwd()` with the inherited environment, and cheval's loader walks up from cwd to the project root and reads that `.loa.config.yaml`. Scenario on a PR-head checkout with `OPENAI_API_KEY` set: the head's config declares `hounfour.providers.openai.endpoint: "https://collector.example/v1"` — an https public host, which the new load-time gate admits for every provider because the allowlist is deliberately not applied to a declared endpoint. The trusted (base) view declares nothing special for `openai`, so `validateApiKeys` marks it valid, the pipeline dispatches, and cheval POSTs the review prompt with `Authorization: Bearer $OPENAI_API_KEY` to collector.example. No test exercises what cheval reads; `trusted-config.test.ts:373` stubs `generateReview`. The dissent's DISS-C-003 names the same path.
**Why This Matters:** The dispatch path predates this PR, and #1050 was closed on the premise that Bridgebuilder never runs on a PR-head checkout. This PR replaces that premise with an explicit safety claim ("even when the checkout is a PR head") that the mechanism does not deliver; operators reading the skill doc will run it in exactly the setting that leaks a key. A security control documented as broader than it is, is a defect of the control.
**Required Fix:** Either (a) make the claim true — hand the trusted view to cheval for the dispatch (e.g. `LOA_CONFIG_PATH_OVERRIDE` / a `--config` pointing at the trusted config text) or refuse to plan any provider whose head-side `endpoint` / `auth` / `type` differs from the trusted declaration (extend `headOnlyRefused` to those keys); or (b) narrow the claim in `SKILL.md:118`, the table and `config.ts:440`: the trusted view governs Bridgebuilder planning only, cheval reads the checkout, a PR-head checkout remains unsupported. Add a test for whichever contract you choose (an endpoint-redirecting head is refused, or the delegate receives the trusted config).
**Reference:** CWE-522 (Insufficiently Protected Credentials), CWE-1059 (Insufficient Technical Documentation); OWASP ASVS V14.1

---

## Observations

### 1. Reliability — exit 3 is read as "completed, degraded" without the run JSON that would prove it

- **MEDIUM** (confidence: high) `head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh:78-79` — any exit 3 from the entry script sets `degraded=true`, and `:89-90` then exits 0, even when `$BB_OUT` is empty or not JSON; a failed run is recorded as a completed degraded review in an unattended schedule.
**File:** `dispatcher.sh:78` (`if [[ "$rc" -eq 3 ]]`), `:79`, `:89-90`
**Suggestion:** Treat 3 as completed-degraded only when `$BB_OUT` parses and carries a `verdicts` array (`jq -e '.verdicts | type == "array"'`); otherwise keep `exit "$rc"` and `degraded: false`. Exit-3 producers other than `main.ts` exist in practice: a pre-cycle-129 `entry.sh` pointed to by `LOA_SESSION_CAP_BB_ENTRY` (zod missing → `exit 3`), or any `set -e` failure whose last command returned 3. `head/tests/unit/bb-exit-degraded-callers.bats:18-25` only stubs the happy shape.
**Benefit:** The handoff never records a failure as a completed review; the scheduled cycle keeps its failure signal.

### 2. Functionality — the configured-provider probe cannot probe a configured *hosted* provider

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1469-1475` — `_probe_configured` validates `<endpoint>/models` with `--allowlist loa-providers.json`, so any configured provider whose host is not one of the six built-in hosts (the shipped Azure example, a hosted open-weight API) is always `UNKNOWN / endpoint_refused` (`ENDPOINT-NOT-ALLOWED`), although `--provider <name>` is documented for "a configured hounfour.providers name" (`:21-22`, `head/.claude/loa/reference/scripts-reference.md:73`).
**File:** `model-health-probe.sh:1469` (`_vflags=(--json --allowlist "$PROBE_PROVIDERS_ALLOWLIST")`), `:1475`; the same allowlist is applied again inside `_curl_json` (`:1024-1029`) for the call at `:1508`
**Suggestion:** The cheval path deliberately validates an operator-declared endpoint without the allowlist (`validate_declared_endpoint`); give the probe the same entry point for configured providers (a `--declared-endpoint` flag on `endpoint-validator.py` / `.sh`, or an allowlist generated from the merged config). Add a bats case for an https configured provider. Verified against the shipped allowlist: `https://myres.openai.azure.com/openai/v1/models` → `ENDPOINT-NOT-ALLOWED`.
**Benefit:** The feature works for the example the PR itself ships (Example 3, azure-openai).

### 3. Documentation vs. code — the probe is documented as locality-aware but has no locality logic

- **MEDIUM** (confidence: high) `head/.claude/loa/reference/scripts-reference.md:73` — "refuses a hosted probe under `local_voices`"; `head/.claude/loa/reference/multi-model-reference.md:102` and `head/.loa.config.yaml.example:818` list "the health probe" among the hops planned only on local providers; `head/README.md:30` says the posture "refuses every hosted hop by name across the dissent, Flatline, Bridgebuilder and the probe". `model-health-probe.sh` contains no `locality` read at all: `head/.claude/scripts/model-health-probe.sh:1578` dispatches `_probe_configured` and `:1571-1574` the built-in probes regardless of posture.
**Suggestion:** Either add the gate (read `hounfour.locality` once, refuse built-in and non-local configured providers by name, exit non-zero) with a bats case, or remove the probe from the four documents. The probe only sends `GET /models` with the key (no prompt), so the exposure is small, but a documented refusal that does not exist misleads the operator who audits the posture.
**Benefit:** The posture's documented perimeter matches its real perimeter.

### 4. Consistency — a provider-level `dispatch_group: local` is "local" to the planners and "hosted" to cheval

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:541` — `ModelConfig.dispatch_group` is filled from the model entry only, and `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` reads the entry only, while `hop-locality.py:116` and `config.ts:730` also honour the provider block's `dispatch_group`. A provider declared `dispatch_group: local` at provider level (the Bridgebuilder test's `lan-box` shape, `trusted-config.test.ts:293-310`) is planned as local by every planner, yet every MODELINV row for it says `hop_locality: hosted`, and `_transport_policy` (`openai_adapter.py:221`) sees `dispatch_group=None` — it still gets the request-time rules only when the provider also carries `allow_insecure_endpoint` (the opt-in branch), which every loadable loopback/RFC1918 case does.
**Triage of the dissent:** DISS-001 (gpt-5.5-pro) and DISS-C-002 (claude-headless) raise this; DISS-001's exact scenario (`https://127.0.0.1:8443/v1` with no opt-in) does not load at head (`ENDPOINT-IP-BLOCKED`), so the proxy exposure it describes does not occur, but the planner/telemetry contradiction is real → recorded here as MEDIUM, not blocking.
**Suggestion:** Resolve the effective group once at load (`entry.get("dispatch_group") or prov.get("dispatch_group")`) into the model entry, and read it from there in `cheval.py`, `modelinv.py`, `hop-locality.py` and `config.ts`. Fold into Changes Required 1's shared rule.

### 5. Coverage — the opt-in and the local label are admitted on any provider type, but the request-time rules exist only in the OpenAI adapter

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:148-156` — `validate_providers` checks the endpoint rule for every non-CLI provider regardless of `type`, so `type: anthropic` (or `google`) with `allow_insecure_endpoint: "192.168.1.5"` and `endpoint: http://192.168.1.5:8080` loads; the `TransportPolicy` plumbing (`head/.claude/adapters/loa_cheval/providers/base.py:270`, `:378`, `:468`, all `policy=None` by default) is wired only through `OpenAIAdapter._dispatch`, and the Anthropic/Google/Bedrock adapters (untouched by the diff) still call `http_post` / `http_post_stream` without a policy: proxy env honoured, and on the urllib transport redirects followed with the credential attached, while MODELINV may record `hop_locality: local`. Dissent DISS-C-001.
**Suggestion:** Refuse `allow_insecure_endpoint` / `dispatch_group: local` at load on provider types that do not implement the request-time half (`type` not in `openai`, `openai_compat`), with a named reason; or plumb `policy` through the other adapters. Document the supported type in Example 4.

### 6. Structured output — `strict: true` plus a substring heuristic makes the common case a silent downgrade

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:443` — `_build_chat_body` always sends `"strict": True`; servers that implement OpenAI strict mode reject most ordinary schemas (optional properties, missing `additionalProperties: false`) with a 400 that names `response_format`, and `_names_response_format` (`:101-111`) then classifies any such 400 — including a schema-*validation* error — as "schema unsupported": the prompt is paid for twice and the answer comes back unenforced, visible only as `schema_rejected_by_server` in telemetry. Dissent DISS-C-004 (advisory) raised the strict-mode angle.
**Suggestion:** Send `strict: true` only when the schema is strict-compatible (or make it a catalog flag), log the server's message at WARN with the schema name, and narrow the heuristic to `unsupported|not supported|unknown (field|parameter)` alongside the key names.

### 7. Compatibility — a config-wide fail-closed load rule with no CHANGELOG or migration note

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:704` — `validate_providers(merged)` runs on every load; one pre-cycle-129 provider block the new rule refuses (an Ollama entry at `http://localhost:11434/v1` without `allow_insecure_endpoint`, an internal gateway at `https://10.0.0.5/v1`) now aborts every cheval invocation, every Flatline/dissent/Bridgebuilder hop and the probe, until the operator edits the file. The behaviour is correct (fail closed), but the diff touches no `CHANGELOG.md`, and `head/README.md:35` points upgraders at "the CHANGELOG Migration notes" for keys this PR does not add there. Dissent DISS-C-006 (advisory).
**Suggestion:** Add the CHANGELOG entry and a migration note naming the new refusal codes and the one-line opt-in fix; consider naming the offending provider and the fix in the `ConfigError` text (the `EndpointPolicyError` already carries `providers.<name>`).

### 8. Config semantics — `auth: "local"` silently overrides an explicit `keyless: false`

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:140` — `normalise_keyless` sets `prov["keyless"] = True` whenever `auth` is the literal `local`, even when the operator wrote `keyless: false` beside it; the contradiction should be refused by name rather than resolved silently.
**Suggestion:** `if prov.get("keyless") is False: raise ConfigError("... keyless: false contradicts auth: \"local\"")`.

### 9. Robustness — the probe helper CLI reports only `ConfigError`

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:223` — `_main` catches `ConfigError` only; a `yaml.YAMLError`, `ValueError` or `KeyError` from the loader prints a traceback and exits 1, and `model-health-probe.sh`'s `_configured_providers` (`head/.claude/scripts/model-health-probe.sh:880-882`) then greps `"error"` from stderr and shows nothing useful before the enum error.
**Suggestion:** Catch `Exception` in `_main`, emit the one JSON line (`{"error":"config_load_failed","detail":...}`) and exit 78 for every load failure.

### 10. Divergence — Bridgebuilder treats any literal `auth` as keyless; cheval normalises only `"local"`

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:482`, `:491` — `literalAuth` is any non-empty `auth` without `{env:`, so `auth: "sk-…"` makes the provider keyless in Bridgebuilder's view, while `KEYLESS_AUTH_LITERALS` (`head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50`) accepts only `local` ("any other literal could be a real key"). `head/.claude/skills/bridgebuilder-review/resources/core/types.ts:63` documents the Bridgebuilder rule as D-8.0, which it is not.
**Suggestion:** Match cheval: keyless iff `keyless: true` or `auth` is exactly `local`; warn on any other literal.

### 11. Consistency — `health_check` applies the transport policy only for the opt-in, not for a `local` model

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:858` — `health_check` builds a `TransportPolicy` only when `allow_insecure_endpoint` is set, while `_transport_policy` (`:221`) also applies it for `dispatch_group: local`; an https local provider without the opt-in is probed with proxies honoured and redirects followed.
**Suggestion:** Reuse the provider-level part of `_transport_policy` in `health_check`.

### 12. Arithmetic — the catalog-priced budget estimate can overflow and pass the gate

- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:3893` — `tokens * _bv_in` with a 12-digit rate (the regex at `:3885` admits up to `10^12`) and a few-million-token diff exceeds 2^63; bash wraps negative, `estimated_cost_cents` goes negative and `-gt $budget` is false, so the gate admits the run. Unrealistic prices, but the gate is the one place a wrong price must fail closed.
**Suggestion:** Divide before multiplying (`tokens / 10000 * _bv_in / 1000000`) or compute in the python helper already invoked for prices; refuse a negative or non-numeric estimate.

### 13. Non-blocking echo of Observation 1 in the harness

- **LOW** (confidence: high) `head/.claude/scripts/spiral-harness.sh:700-704` — `_bb_surface_exit` prints "completed DEGRADED (exit 3)" for any exit 3, run JSON or not; here it only mislabels the WARN (the gate was non-blocking before), but the same `verdicts`-array check as Observation 1 would keep the two callers' contracts identical, which `bb-exit-degraded-callers.bats` otherwise asserts.

### 14. Interpreter isolation — `-I` for the policy CLI, `PYTHONSAFEPATH` for the pricing CLI

- **LOW** (confidence: low) `head/.claude/scripts/model-health-probe.sh:863` — `_endpoint_policy_cli` runs `python3 -I`, which also drops the user site-packages; on a host where PyYAML is user-installed, every configured-provider probe is `UNKNOWN` ("configured providers unavailable"), while `head/.claude/scripts/adversarial-review.sh:3875` runs the pricing CLI under `PYTHONSAFEPATH=1 PYTHONPATH=…` and works. Pick one isolation mode for both cheval CLIs.

### 15. Reviewer-facing docs — the envelope grew fields the triage protocol does not know

- **LOW** (confidence: high) `head/.claude/skills/reviewing-code/SKILL.md:232` and `head/.claude/skills/auditing-security/SKILL.md:184` add one sentence each, but `resources/ADVERSARIAL-REVIEW.md` (the byte-identical block both skills carry, CMP-138) is untouched: `companion_voice.reason: locality_refused`, `metadata.locality{mode,refused,note}`, `metadata.estimate_voices` and the `advisory_voices[]` entry shape (`status`, `counted_as`, `duplicate_of`, `rejected_summary`) are undocumented for the reviewer who must triage the envelope.
**Suggestion:** Extend the shared block in both copies in the same commit.

### 16. Test gap tied to Changes Required 1

- **LOW** (confidence: high) `head/tests/unit/adversarial-review-locality.bats:19-42` and `head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts:34-45`, `:293-310` — every locality fixture pairs `dispatch_group: local` with a `127.0.0.1` endpoint (or no endpoint at all); no case gives the label to a public endpoint, so the trust-not-enforce defect is invisible to the suite.

---

## Cross-Model Observations

Phase 2.5 ran `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --context-file grimoires/loa/a2a/sprint-1/reviewer-concerns.md --json`: status `reviewed`, primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless` succeeded and counted as an independent voice (`voices_planned: 2`, `voices_succeeded: 2`), `rejected_count: 0`, `repaired_count: 0`. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`. Note: the dissent read context files from the workspace tree, which is a later revision than the head; each finding was re-verified against the head diff.

| Finding | Voice | Triage |
|---------|-------|--------|
| DISS-001 (BLOCKING) provider-level `dispatch_group: local` bypasses `_transport_policy` | gpt-5.5-pro | Partially valid → Observation 4 (MEDIUM). The named scenario (`https://127.0.0.1:8443/v1`, no opt-in) is refused at load (`ENDPOINT-IP-BLOCKED`); the planner/cheval inconsistency is real. |
| DISS-C-001 (BLOCKING) opt-in / local label admitted for any provider type; request-time rules only in `OpenAIAdapter` | claude-headless | Valid → Observation 5 (MEDIUM). |
| DISS-C-002 (BLOCKING) `_build_provider_config` reads `dispatch_group` from the model entry only | claude-headless | Valid → merged into Observation 4 (MEDIUM). |
| DISS-C-003 (BLOCKING) public https host admitted for every provider; on a PR-head checkout the Bearer token goes to an attacker host | claude-headless | Valid → corroborates Changes Required 2 (HIGH). |
| DISS-C-004 (ADVISORY) `strict: True` + substring heuristic → silent unenforced downgrade | claude-headless | Valid → Observation 6 (MEDIUM). |
| DISS-C-005 (ADVISORY) `stale_catalog` enum breaks readers testing `pricing_source == "config"` | claude-headless | Not a defect: the only other readers are `reprice.py` (reprices `unknown`/absent-without-cost only) and `cost-report.sh` (unpriced = `unknown`/absent; buckets by `pricing_resolution`, which stale rows carry); `rollup.py` was updated in the diff. |
| DISS-C-006 (ADVISORY) config-wide fail-closed load rule is a breaking change without migration | claude-headless | Valid as documentation/compat → Observation 7 (MEDIUM). |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows (the companion produced no sidecar).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | FR-8 local posture enforced by endpoint host (Changes Required 1); trusted-configuration claim made true or narrowed (Changes Required 2); `## AC Verification` walkthrough in the implementation report; CHANGELOG / migration note |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-7 open-weight / local provider declared with one endpoint rule (D-7.2) | Pass | `endpoint_policy.py` ↔ `endpoint-validator.py` one implementation; 31-case table on both paths; request-time rules tested on httpx and urllib — for the OpenAI adapter only (Obs. 5) |
| FR-7 chat `response_format`, thinking strip, named context refusal (D-7.3) | Pass (with Obs. 6) | `test_openai_chat_schema.py`, `test_openai_thinking_strip.py`, `test_openai_local_hop_e2e.py` |
| FR-7 advisory voices never touch the verdict (D-7.4) | Pass | ADV-2 byte-identical envelope and verdict-derive output; sidecar disabled for advisory walkers |
| FR-7 catalog-priced budget gate + provenance (D-7.6) | Pass | BUD-1…6, `test_catalog_pricing_provenance.py`; overflow edge noted (Obs. 12) |
| FR-7 configured-provider probe (D-7.5) | Fail | Only loopback/RFC1918 opt-in hosts pass the allowlist (Obs. 2); no locality gate though documented (Obs. 3) |
| FR-7 Bridgebuilder trusted configuration (D-7.5, DEC-0170) | Fail | Planning-only; dispatch reads the checkout; claim overstated (Changes Required 2) |
| FR-7 Bridgebuilder `completed/planned` and exit 3 (D-7.7, DEC-0150) | Pass (with Obs. 1) | `run-outcome.ts` pure functions tested; callers covered; JSON-less exit 3 masked in the dispatcher |
| FR-8 `local_voices` refuses every hosted hop by name (D-8.1, DEC-0146) | Fail | Refusal keyed on a declarative label, not the endpoint (Changes Required 1, Obs. 4) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (fixtures use `fixture-not-a-key`; redaction masks provider key shapes)
- [x] Input validation at trust boundaries — endpoint rule, opt-in host string, advisory alias regex, ref-name check for `git show`
- [ ] Authorization / trust boundary correct — **No**: locality trusts a label (CR 1); trusted config does not govern dispatch (CR 2); request-time rules missing on non-OpenAI adapters (Obs. 5)
- [x] No injection vectors — jq operands are small validated scalars; `isSafeRefName` guards the git ref; argv never carries envelopes
- [x] Dependencies — no new runtime dependency (idna made lazy, fail-closed)
- [x] Error messages don't leak sensitive data — refusals name hosts/aliases only; `describe_provider` never prints a secret

---

## Code Quality Summary

**Strengths:**
- One canonical endpoint rule, loaded by path, with the bash and Python paths proven to agree on every refusal code.
- Honest telemetry: `schema_enforced` derived from the body actually sent; `thinking_stripped`, `destination`, `hop_locality` validated against the shipped payload schema in the E2E.
- Advisory voices are structurally quarantined (own workdir, sidecar disabled, `advisory_voices[]` only) and the quarantine is tested byte-for-byte.
- Pure, testable `run-outcome.ts`; `main.ts` wiring pinned by source assertions.

**Areas for Improvement:**
- Security properties are asserted in four places (classifier, Bridgebuilder, cheval loader, cheval telemetry) from the same untrusted label — centralise the local-hop rule and test the negative case.
- Several documents describe behaviour the code does not have (probe locality, PR-head trust); keep claims to what the tests prove.
- `adversarial-review.sh` keeps growing by in-function comment essays; the new budget/advisory/locality blocks (~240 lines) would read better as a sourced lib with its own bats file.

SIMPLICITY: Lean enough for its scope; the budget gate's bash arithmetic is the one place the python helper already invoked for prices would remove both the overflow edge and ~25 lines of sed/awk. net: -25 lines possible.

---

## Next Steps

1. Address Changes Required 1 and 2 (enforce the local-hop rule everywhere the label is read; make the trusted-config claim true or narrow it).
2. Fix the dispatcher's JSON-less exit-3 handling, the probe's allowlist/locality gaps, the provider-type coverage of the request-time rules, and add the CHANGELOG/migration note.
3. Run `pytest .claude/adapters/tests`, `bats tests/unit`, and `npm test` in `bridgebuilder-review`; rebuild `dist/` and the manifest.
4. Add a `## AC Verification` section to the implementation report and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":7,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T17:35:00Z"} -->
