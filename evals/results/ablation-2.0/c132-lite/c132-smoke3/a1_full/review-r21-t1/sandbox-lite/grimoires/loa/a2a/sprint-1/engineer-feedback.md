# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` — sprint-257: advisory open-weight voices, `local_voices` posture, Bridgebuilder trusted configuration and exit codes, E2E (80 files, +6583/−198)

---

## Overall Assessment

This is a large, carefully built change and most of it holds up under execution, not just reading. I ran the six new Python test files against an overlay of the head files (123 passed) and the six new bats suites (all pass once run from an executable filesystem; this sandbox's `/tmp` is mounted `noexec`, which is why two cases first failed with "Permission denied" on `verdict-derive.sh` and the voice-drop classifier). The endpoint opt-in rule is implemented once and agreed on by both paths, the request-time transport policy is tested against a real stub server on both httpx and urllib, the Bridgebuilder trusted-config precedence is tested against a real git repository, and the advisory-voice block is proven byte-neutral on the counted envelope.

Two findings block merge:

1. The `local_voices` posture is enforced by three implementations that disagree on what "local" means. The shell planner (`hop-locality.py`) and Bridgebuilder accept a provider-level `dispatch_group: local`; cheval's request-time `TransportPolicy` and the MODELINV `hop_locality` field read only the model entry. A provider declared local at the provider block is planned as local, dispatched without the no-proxy/no-redirect rules, and recorded `hop_locality: hosted`. The cross-model dissent found the same defect independently (DISS-C-001, DISS-C-002).
2. The dissent budget gate now sums every planned voice against `budget_cents`, which the shipped example still documents as a cap on ONE dissent call. Running this PR's own diff through the gate with the configured 200c was refused at 955c (primary 718c + companion 237c). With the shipped `gpt-5.5-pro` price a diff of roughly 150 KB is now refused where the previous formula admitted roughly 580 KB. The contract changed without the default, the comment, or a migration note changing with it.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Locality: planner, Bridgebuilder and cheval disagree on provider-level `dispatch_group`

- **HIGH** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116` — `group = entry.get("dispatch_group") or block.get("dispatch_group")` classifies a hop as local when only the PROVIDER block says `dispatch_group: local`; cheval never reads that key at provider level, so the hop is dispatched as hosted.
**File:** `head/.claude/scripts/lib/hop-locality.py:116` (planner), `head/.claude/skills/bridgebuilder-review/resources/config.ts:730` (`isLocalVoice`: `if (decl.dispatchGroup !== undefined) return decl.dispatchGroup === "local"`), versus `head/.claude/adapters/cheval.py:541` (`dispatch_group=model_data.get("dispatch_group")` — model entry only), `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:221` (`_transport_policy` tests `allow_insecure_endpoint` or the MODEL's `dispatch_group`), `head/.claude/adapters/loa_cheval/audit/modelinv.py:476` (`hop_locality_of` reads `entry.get("dispatch_group")` only).
**Issue:** The planner's own docstring at `head/.claude/scripts/lib/hop-locality.py:15` says "that model entry, or its provider block, says `dispatch_group: local` (the canonical key, D-8.0)". The multi-model reference at `head/.claude/loa/reference/multi-model-reference.md:102` says "providers whose model entry says `dispatch_group: local`". Bridgebuilder's test even pins the provider-level reading (`trusted-config.test.ts`, `lan-box` with provider-level `dispatch_group: local` is kept). cheval disagrees with both planners.
**Why This Matters:** Concrete scenario: `hounfour.locality: local_voices`, provider `lan-box: {type: openai_compat, endpoint: "https://llm.internal/v1", dispatch_group: local, models: {m: {...}}}` (an https DNS endpoint is admitted by `validate_declared_endpoint`, no opt-in needed). `adversarial-review.sh` and Flatline plan `lan-box:m` as local and refuse every hosted hop by name. cheval then builds no `TransportPolicy` (`openai_adapter.py:221` is false on both terms), so the request runs on the default transport: httpx `trust_env=True` honours `HTTPS_PROXY`/`ALL_PROXY`, urllib follows 3xx. The prompt can leave the host through a proxy or a redirect under the one posture whose purpose is that it cannot, and the MODELINV row for the call says `hop_locality: hosted`, contradicting the plan and the envelope's `locality.refused` list. Anyone auditing locality from the chain gets the wrong answer in both directions.
**Required Fix:** Pick one reading and make all three agree. Either (a) model-entry only: `hop-locality.py` drops `block.get("dispatch_group")`, `isLocalVoice` drops the provider-level and "every declared model" branches, docstring at line 15 corrected; or (b) provider-level is canonical: cheval's `_build_provider_config` falls back to `prov.get("dispatch_group")` when the model entry has none, and `hop_locality_of` does the same. Add one test per implementation with a provider-level-only declaration asserting the same answer (the e2e test `test_openai_local_hop_e2e.py` is the natural place for cheval; `adversarial-review-locality.bats` LOC-7 for the planner).
**Reference:** SDD D-8.0 / D-8.1 as quoted in the PR's own comments ("the canonical key"); CWE-668 (exposure of resource to wrong sphere) for the proxy/redirect leak under a locality guarantee.

### 2. Budget gate: the sum of every planned voice is compared against a per-call budget

- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4335` — `if [[ $estimated_cost_cents -gt $budget ]]` now compares the SUM over primary + companion + advisory voices (`_adv_budget_estimate`, line 3866; `_bvoices` built at lines 4321–4329) against `budget_cents`, which the shipped example still describes as "Gate on ONE dissent call's pre-dispatch cost estimate" (`head/.loa.config.yaml.example:1624` and `:1690`).
**File:** `head/.claude/scripts/adversarial-review.sh:4321-4335`; `head/.loa.config.yaml.example:1624`, `head/.loa.config.yaml.example:1690`
**Issue:** Observed, not inferred. Running the Phase 2.5 dissent on this PR's own diff with this workspace's configured `budget_cents: 200`:
```
[adversarial-review] budget: estimate 955c over 2 planned voice(s) (primary gpt-5.5-pro 718c, companion claude-headless 237c)
ERROR: Estimated cost (955c) exceeds budget (200c)
```
(exit 4, `status: budget_exceeded`). The same diff under the pre-PR formula estimates 233c for one voice. More generally, with the catalog price of `gpt-5.5-pro` ($30/$180 per Mtok, via the new `pricing --alias` CLI) a single primary voice estimates 139c at 100 KB, 242c at 200 KB and 447c at 400 KB; the previous fixed formula gave 40c, 74c and 143c. Under the shipped 200c default a review of a 200 KB diff is now refused where it previously ran. Two changes compound: real catalog prices (which the PR intends and tests, BUD-1) and summation across voices (BUD-4). Neither the default `budget_cents`, the example's comment, the README migration notes nor the reference docs were updated, so an operator on the shipped config sees the dissent refuse with no explanation of what changed.
**Why This Matters:** Phase 2.5 is mandatory when `flatline_protocol.code_review.enabled: true`; a refused dissent leaves `adversarial-review-gate.sh` blocking `COMPLETED` until the operator diagnoses the budget and edits config. Security audits go through the same gate (`security_audit.budget_cents: 150` in the example, line 1690, with the same "ONE dissent call" comment).
**Required Fix:** Decide the contract and ship it coherently. Either keep `budget_cents` per voice (compare the maximum single-voice estimate, or each voice, against it — the sum is still reported in `estimate_voices`), or make it a run total and (a) raise the example defaults so the shipped `gpt-5.5-pro` + companion still admit the diff sizes they admitted before, (b) rewrite the comments at `.loa.config.yaml.example:1624` and `:1690`, (c) add a README/CHANGELOG migration line. Whatever the choice, `BUD-4` should assert the chosen semantics explicitly in its name and the envelope's `budget_cents` field should say which it is (`per_voice` vs `total`).
**Reference:** The example's own definition of the key, lines 1624 and 1690.

---

## Observations

### 1. Structured output

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:111` — `_names_response_format` returns true for ANY 400 body containing `response_format` or `json_schema`. OpenAI's strict-mode validation errors read "Invalid schema for response_format ...: 'additionalProperties' is required to be supplied and to be false" when the SCHEMA is wrong, not the feature. Such a server fully supports `response_format`, yet the adapter retries without it, records `schema_rejected_by_server: true` and the unenforced answer goes to the tolerant parser. Since `_build_chat_body` always sends `strict: true` (line 441), every hand-written schema that is not strict-clean on a `structured_json` chat entry takes this path, and the operator's only signal is a WARN and a telemetry flag. The dissent raised the same point (DISS-C-006).
**Suggestion:** Narrow the heuristic: treat "invalid schema" / "additionalProperties" / "required" phrasings as a schema defect to surface (raise, or retry with `strict: false` once) and keep the drop-the-schema retry for "unsupported" / "unknown field" / "extra fields" bodies. Add the OpenAI strict-mode message as a negative case in `test_openai_chat_schema.py::test_the_heuristic`.
**Benefit:** Operators who declared `structured_json` get the enforcement they asked for, or a visible failure, instead of silent degradation.

### 2. Smaller inconsistencies and telemetry edges

- **LOW** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:482` — `literalAuth` treats ANY `auth` string without `{env:` as keyless, while cheval's `KEYLESS_AUTH_LITERALS` at `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:50` normalises only the literal `"local"`. A provider with `auth: "sk-…"` in trusted config is "keyless" to Bridgebuilder and a Bearer credential to cheval. Harmless today (cheval still authenticates), but the two D-8.0 readings should be the same string set.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:444` — `destination_for` records `{host: cli-subprocess, scheme: cli}` for any provider with no `endpoint`, not only `*-headless` / `kind: cli` providers. An HTTP provider whose endpoint failed to interpolate is reported as a CLI hop in the audit chain.
- **LOW** (confidence: high) `head/.claude/schemas/model-config.schema.json:142` — the `price_source` pattern `^(https://\S+|docs/\S+)$` admits `docs/../secrets.md`, which `test_catalog_pricing_provenance.py` explicitly refuses. Add `(?!.*\.\.)` or document that the test is the authority.
- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:617` — in local mode `source = "working-tree"` is set before `readWorkingTree` returns `undefined`, so the startup line reports "Trusted config: working-tree" when no `.loa.config.yaml` exists. Set `source = "none"` when `text` is undefined.
- **LOW** (confidence: low) `head/.claude/scripts/lib/endpoint-validator.py:1047` — the opt-in admits `localhost`, and the module docstring at `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:6` says an insecure endpoint "is never resolved through DNS". `localhost` IS resolved by the OS resolver (`/etc/hosts`, `search` domains). The IP-literal claim is true; the `localhost` claim is not. Either drop `localhost` from the opt-in or correct the sentence.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/openai_streaming.py:75` — an unterminated leading `<think>` turns the entire remaining content into `thinking` and leaves `content` empty (tested as intended, `unterminated` case). A model that emits `<think>` as the first token and never closes it (budget exhausted) yields an empty answer that the qualification step then treats as malformed rather than as truncated reasoning. Consider recording `thinking_truncated: true` so the repair loop can tell the two apart.

### 3. Verification I could not complete here

- The Bridgebuilder TypeScript tests (`trusted-config.test.ts`, `run-outcome.test.ts`, `progress.test.ts`) were not run: the skill's `node_modules` are not present in this sandbox and `npm ci` needs the network. The `dist/` output does contain `loadTrustedConfig`, `exitOnDegraded` and `process.exitCode`, consistent with the sources, but byte-level parity with `.build-manifest.json` is unverified.
- `emit_endpoint_validator_ts --check` (the generated-TS drift gate) could not run: `jinja2` is not installed. The generated file changed only in its source hash line, which is consistent with a generator that embeds the hash and the allowlist tables, but unverified.
- `flatline-locality.bats` FLL-7 skipped (no `grimoires/loa/prd.md` in this checkout).

### 4. Complexity and process

- `_adv_advisory_block` (`head/.claude/scripts/adversarial-review.sh:3985-4034`) and `_adv_run_advisory_voices` are each over 50 lines with a large embedded jq program; `loadTrustedConfig` (`config.ts:606-700`) is about 95 lines. Each is justified by its single responsibility and the "files, never argv" rule, and I found no duplication to remove. Over-engineering pass: nothing to delete beyond function length. `net: -0 lines possible`.
- `reviewer.md` carries no `## AC Verification` walkthrough; in this evaluation the implementation report is the PR description by construction, so this is noted, not counted.

---

## Cross-Model Observations

Phase 2.5 ran twice. The first attempt was refused by the gate under review (see Changes Required §2; the refusal record is reproduced there). The second ran with `--budget 1200`, the diff-scaled ceiling this workspace's config declares (`budget_cents_max: 1200`), as the operator's stated intent. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — `status: reviewed`, the three OpenAI/Google primary hops failed for want of credentials (`api_failure`), the Anthropic companion `claude-headless` answered and is `counted_as: sole_voice`; `verdict_quality.status: FAILED` (1 of 4 planned voices). Treated as advisory input per the skill. Triage of its seven findings:

- DISS-C-001 (BLOCKING, `openai_adapter.py:_transport_policy`) — real; same root cause as Changes Required §1. The part of its text naming a `TransportPolicy.local` field refers to a symbol that does not exist in `pr/head` (it exists in this workspace's newer framework files the dissent was shown as escalated context) and is discounted.
- DISS-C-002 (BLOCKING, `modelinv.py:hop_locality_of`) — real; folded into Changes Required §1.
- DISS-C-003 (BLOCKING, `loader.py` dead `validate_local_fallbacks`) — not a defect of this PR: no such symbol exists in `pr/head` (`grep` of `endpoint_policy.py`, `loader.py`, `base.py` finds none); the dissent itself conditioned the finding on this check. The underlying leak (a local entry whose `fallback_chain` reaches a hosted alias) is handled at plan time by `hop-locality.py` (`fallback_chain_reaches_hosted`, LOC-7 passes).
- DISS-C-004 (BLOCKING, `cheval.py` bare model ids defeat `hop_telemetry`) — refuted: `_entry_target = _entry.canonical` (`cheval.py:2306`) is `provider:model`, and `test_openai_local_hop_e2e.py` asserts `destination` on both the success and the `context_window_refused` paths (passing).
- DISS-C-005 (ADVISORY, exit-7 emit dereferences `_preflight_head`) — not new: the same kwargs already read `_preflight_head.canonical` and `.provider` before this PR (`cheval.py:2160-2170`); the PR adds no new None path.
- DISS-C-006 (ADVISORY, 400 heuristic) — real; recorded as Observation §1.
- DISS-C-007 (ADVISORY, `{region}` endpoints refused at load) — refuted by execution: `check_endpoint("https://bedrock-runtime.{region}.amazonaws.com", None)` is accepted, and `test_hosted_defaults_still_load_unchanged` passes against the shipped catalog (line 964 carries that template).

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `rejected_sidecars` is empty, and no `adversarial-rejected-review*.jsonl` sidecar stands beside the envelope.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Reviewed, changes required | The two HIGH items above |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect reported with the file and line it sits on | Pass | Every finding above cites `head/<path>:<line>` |
| Merge verdict given | Pass | CHANGES_REQUIRED (2 HIGH) |

### Evidence gathered by execution

| Check | Result |
|-------|--------|
| `pytest` — 6 new test files, overlay of head on this framework | 123 passed |
| `bats` — `bb-exit-degraded-callers`, `model-health-probe-configured-provider`, `adversarial-review-budget`, `adversarial-review-locality` | all pass |
| `bats` — `flatline-locality`, `adversarial-review-advisory` | all pass when run from an executable filesystem (FLL-7 skipped: no prd.md); the first run's two failures were `noexec /tmp` |
| `adversarial-review.sh` on `pr/head.diff`, configured 200c | refused: 955c (`budget_exceeded`) |
| `adversarial-review.sh` on `pr/head.diff`, 1200c | completed, sole voice |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the probe and the loader print env var NAMES only; `describe_provider` never carries a value)
- [x] Input validation at trust boundaries present (opt-in host is validated on both paths; `isSafeRefName` guards the git ref; `_CONFIGURED_NAME_RE` guards the provider name; `auth_env` regex guards the indirect expansion)
- [x] Authentication/authorization correct — with the caveat in Changes Required §1 (the locality guarantee does not reach a provider-level declaration)
- [x] No injection vectors found (jq operands are `--arg`/`--argjson`/`--slurpfile`; `yq` programs splice only the gate's own config key)
- [x] Dependencies: `idna` made optional with a fail-closed refusal; no new runtime dependency
- [x] Error messages do not leak sensitive data (provider lines are allowlisted/truncated; the budget refusal names aliases only)

---

## Code Quality Summary

**Strengths:**
- One endpoint rule, loaded by path into cheval, with a single case table run through both entry points (`test_endpoint_validator_optin.py`), and request-time rules proven against a real 127.0.0.1 server on both transports including the proxy-env control.
- Bridgebuilder's trusted-config precedence is a clean seam-injected design with a real-git test; the head-only refusal is explicit and named.
- The advisory block's byte-neutrality is asserted on the normalised envelope AND on `verdict-derive --json` output (ADV-2), which is exactly the right invariant.
- Fail-closed defaults throughout (`hop-locality.py` unreadable config → hosted; validator missing → `ConfigError`; malformed budget → 0c).

**Areas for Improvement:**
- Three implementations of "is this hop local" with two readings of the key (Changes Required §1).
- A documented contract (`budget_cents`) changed in code without its documentation, default or migration note (Changes Required §2).
- The example config gained 100 lines of prose; the two stale "ONE dissent call" comments show the risk of comment-as-spec.

---

## Next Steps

1. Resolve the `dispatch_group` reading across `hop-locality.py`, `config.ts` and cheval; add the provider-level-only case to each test suite.
2. Decide the `budget_cents` contract (per voice or run total), align `.loa.config.yaml.example:1624`/`:1690`, defaults and README migration notes; make BUD-4 name the semantics.
3. Consider narrowing `_names_response_format` for strict-mode schema errors.
4. Run the Bridgebuilder TS tests and the codegen drift check in an environment with `node_modules` and `jinja2`.
5. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:55:00Z"} -->
