# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff` — sprint-257, cycle-129)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)

---

## Overall Assessment

The change is large (80 files) and, on the whole, carefully built: the per-provider insecure-endpoint opt-in is implemented once in the canonical validator and reused by the cheval loader, the bash wrapper and the health probe; the `TransportPolicy` request-time rules (no proxy env, no redirects, declared path prefix) are tested against a real 127.0.0.1 stub on both the httpx and urllib transports; advisory voices are kept byte-for-byte out of the counted envelope; the `local_voices` posture refuses hosted hops by name in the dissent and Flatline through one fail-closed classifier; Bridgebuilder reads provider declarations from trusted configuration only. The new tests are substantive and I ran them: 123 Python tests pass, 45 bats tests pass (one skipped for a missing `prd.md`). Two bats failures seen on a first run were caused by the sandbox's `/tmp` being mounted `noexec`, not by the PR, and pass from an executable path. The Bridgebuilder TypeScript tests could not be run here (no `node_modules`); `dist/.build-manifest.json` hashes match the head sources for every changed `.ts` file.

The verdict turns on one gap in the posture feature: the PR defines "local" three different ways across its four consumers, and the Bridgebuilder definition admits a hop the PR's own classifier refuses. Under `hounfour.locality: local_voices` Bridgebuilder keeps a voice whose local model carries a hosted `fallback_chain`; cheval walks that chain inside the call, so the PR content can reach a hosted provider under a posture whose stated contract is "refuses every hosted hop by name". The dissent and Flatline do not have this hole because `hop-locality.py` classifies such an entry as hosted. One `HIGH` finding forces `CHANGES_REQUIRED` under the one-way rule.

Also noted: the request-time `TransportPolicy` is wired only into the OpenAI adapter while the load-time opt-in is accepted for any provider type (MEDIUM); two LOW consistency gaps; and the implementation report (`pr/PR.md`) carries no `## AC Verification` walkthrough. Per `pr/REVIEW-INSTRUCTIONS.md` the PR files are the entire input and pre-flight steps that need sprint artifacts are skipped, so the missing walkthrough is recorded as an observation rather than applied as the automatic rule; the verdict here is driven by the code findings.

Testing caveat: the only runnable tree available was the workspace framework (a newer revision than the PR base) with every `pr/head/` file overlaid. All test results above are from that hybrid tree; every finding below was confirmed by reading the `pr/head/` files or by a reproduction against them, not inferred from test output alone.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security posture — Bridgebuilder's locality check diverges from the PR's own classifier

- **HIGH** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733` — `isLocalVoice` decides locality from `dispatch_group` alone and never looks at the model entry's `fallback_chain`; under `local_voices` a voice whose local model falls back to a hosted hop is kept by `applyLocality` (line 739) and cheval walks the chain to the hosted provider when the local server fails.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:726-733` (and `applyLocality`, line 739)
**Issue:** The PR's classifier for the dissent and Flatline, `head/.claude/scripts/lib/hop-locality.py:16` and `:133`, states the rule: "every hop on the entry's own `fallback_chain` is local by the same rule — cheval walks that chain inside one call", and returns `hosted` with reason `fallback_chain_reaches_hosted:<hop>` otherwise (pinned by bats LOC-7). Bridgebuilder's `isLocalVoice` has no equivalent: trusted config `hounfour.locality: local_voices`, provider `lan` with model `qwen` `dispatch_group: local`, `fallback_chain: ["openai:gpt-5.5"]`, multi-model voice `lan/qwen` → `applyLocality` keeps the voice; when the local server is down, cheval (which every voice dispatches through, `multi-model-pipeline.ts:225`) walks to `openai:gpt-5.5` and the PR diff leaves the host. `head/.claude/skills/bridgebuilder-review/SKILL.md:181` promises that under `local_voices` "every voice whose provider is not `dispatch_group: local` in the trusted config is dropped … and never rerouted"; the README and `multi-model-reference.md` promise the same across "the dissent, Flatline, Bridgebuilder and the probe".
**Why This Matters:** `local_voices` is a confidentiality posture (FR-8). The dissent and Flatline honour the fallback-chain rule; Bridgebuilder does not, so the guarantee holds for three of four consumers and the operator has no way to know which. The same function also admits two shapes cheval's loader rejects outright (see Observation 2), so Bridgebuilder's notion of "local" is neither cheval's nor hop-locality.py's.
**Required Fix:** Give Bridgebuilder the same classification as the shell callers: either (a) have `loadTrustedConfig` parse `models.<id>.fallback_chain` into `ProviderDecl` and make `isLocalVoice` recurse over the chain against the trusted declarations plus the generated registry (hosted when any hop is not local, `MAX_DEPTH`-bounded, unresolved = hosted), or (b) shell out to `hop-locality.py` with the trusted config text. Add a `trusted-config.test.ts` case mirroring bats LOC-7 (`qwen-leaky` with `fallback_chain: ["openai:gpt-5.5"]` is refused with a named reason) and a test that an undeclared fallback hop is treated as hosted.
**Reference:** SDD D-8.1 (plan-time refusal, never rerouted); CWE-200 (exposure of sensitive information to an unauthorized actor) for the posture breach.

---

## Observations

### 1. Request-time rules apply to one adapter type only

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/config/endpoint_policy.py:26` — the module promises "for an opted-in provider, or a model whose `dispatch_group` is `local`, the adapter ignores proxy environment variables, refuses HTTP redirects and requires every request URL to stay under the declared endpoint path", but `TransportPolicy` is constructed only by `OpenAIAdapter._transport_policy` (`head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-223`); `validate_providers` (`endpoint_policy.py:143-156`) accepts `allow_insecure_endpoint` for any non-CLI provider type.
**File:** `head/.claude/adapters/loa_cheval/providers/openai_adapter.py:217-223`; `head/.claude/adapters/loa_cheval/providers/base.py:270,378,468` (the `policy` keyword is optional and defaults to None)
**Suggestion:** Reproduced: a `type: anthropic` provider with `endpoint: http://127.0.0.1:9100/v1`, `keyless: true`, `allow_insecure_endpoint: "127.0.0.1"` loads cleanly, and the Anthropic and Google adapters call `http_post`/`http_post_stream`/`http_get` without `policy`, so proxy env vars are honoured and the urllib fallback follows redirects for that provider. Either refuse the opt-in and `dispatch_group: local` at load for provider types whose adapter does not implement the policy (fail closed, with a named reason), or move policy construction into `ProviderAdapter` so every adapter type gets it. Add a load test for the refused shape.
**Benefit:** The documented request-time guarantee becomes true for every provider the loader admits, not only `openai`/`openai_compat`.

### 2. Three definitions of "local" for one hop

- **LOW** (confidence: high) `head/.claude/scripts/lib/hop-locality.py:116` — the planner (and Bridgebuilder, `config.ts:730-732`) treats a provider-level `dispatch_group: local`, or "every declared model is local", as local, while cheval's loader requires `dispatch_group` on every model entry (`head/.claude/adapters/loa_cheval/config/loader.py:643`, `_validate_model_auth_metadata`: reproduced `CONFIG-INVALID … missing required 'dispatch_group'`), reads only the model-level key into `ModelConfig` (`head/.claude/adapters/cheval.py:541`) and records `hop_locality` from the model entry alone (`head/.claude/adapters/loa_cheval/audit/modelinv.py:473-476`).
**File:** `head/.claude/scripts/lib/hop-locality.py:116`; `head/.claude/skills/bridgebuilder-review/resources/config.ts:730-732`; `trusted-config.test.ts:359` pins the "every declared model is local" rule for a provider with no models at all
**Suggestion:** A provider-level `dispatch_group` plans a hop cheval then refuses at load, so nothing leaks, but the planners' docstring ("that model entry, or its provider block", `hop-locality.py:15`) describes a config shape the dispatcher never accepts. Drop the provider-block rule from both classifiers (model-level only, matching cheval and D-8.0), or make cheval honour the provider-level key everywhere (loader, `ModelConfig`, `hop_locality_of`, `_transport_policy`). One rule, one place.
**Benefit:** One answer to "is this hop local" across plan time, dispatch and MODELINV.

### 3. The probe applies a different endpoint rule than cheval to configured providers

- **LOW** (confidence: medium) `head/.claude/scripts/model-health-probe.sh:1469` — `_probe_configured` validates the configured provider's `/models` URL with the host-allowlist pipeline (`--allowlist "$PROBE_PROVIDERS_ALLOWLIST"`), while cheval admits an operator-declared https host through `validate_declared_endpoint` (no allowlist). A hosted open-weight API such as `https://api.example-inference.com/v1` loads in cheval but is answered `UNKNOWN / endpoint_refused` by the probe.
**File:** `head/.claude/scripts/model-health-probe.sh:1469`
**Suggestion:** The docs say the probe goes "through the endpoint rule" as cheval does. Either pass a declared-endpoint mode to the validator CLI for configured providers, or say in the probe's `--help` and `scripts-reference.md` that configured https providers must also be on the probe allowlist. Not silent (the reason is named), hence LOW.
**Benefit:** The probe answers for every provider cheval will dispatch to.

### 4. Report and documentation

- **LOW** (confidence: high) `head/README.md:22` — the implementation report (`pr/PR.md`, one line plus a file count) carries no `## AC Verification` walkthrough, no assumptions, and no record of the formatter/type-check self-checks (FAST-GATE: `tsc --noEmit` for the Bridgebuilder sources is not evidenced; the `dist/` hashes do match the sources). The README's "Unreleased — earned guards and open voices" block points at `CHANGELOG.md`, which is not in the diff and could not be checked here.
**Suggestion:** On re-submission include the AC walkthrough with `file:line` + symbol per criterion, the test commands run (the six pytest files, the seven bats files, `npm test` for the skill) and the CHANGELOG entry or a pointer to the commit that carries it.
**Benefit:** Lets the next reviewer verify rather than re-derive.

### 5. Complexity

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-health-probe.sh:1428` — `SIMPLICITY[shrink]`: `_probe_configured` is ~110 lines with four early-return state blocks that repeat the same five assignments; `loadTrustedConfig` (`head/.claude/skills/bridgebuilder-review/resources/config.ts:605`) is ~100 lines and `_adv_advisory_block` (`head/.claude/scripts/adversarial-review.sh:3972`) ~60 lines with a 30-line embedded jq program. All three exceed the 50-line threshold without a justification comment.
**Suggestion:** In the probe, a `_probe_unknown <reason> <class>` helper removes ~20 lines; in `config.ts`, split the PR-mode source resolution (settings → base ref → main) into its own function; in the shell, move the jq program to a `.jq` file beside the schemas. `net: -60 lines possible`.
**Benefit:** Each unit becomes readable in one screen and testable on its own.

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and the named sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` has zero rows (both voices' payloads validated without repair).

---

## Cross-Model Observations

Adversarial review ran on `pr/head.diff` (`grimoires/loa/a2a/sprint-1/adversarial-review.json`): primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless`, two independent voices, verdict quality APPROVED, 7 findings. Each was verified against the head files:

- **DISS-001 (BLOCKING, primary)** — "a `dispatch_group: local` provider with an https loopback endpoint and no opt-in gets no TransportPolicy". Refuted: a model-level `dispatch_group: local` does produce a policy (`openai_adapter.py:221`), and a provider-level-only key never loads (cheval requires the model-level key, Observation 2). An https loopback or RFC1918 literal without an opt-in is refused at load (`ENDPOINT-IP-BLOCKED`, pinned by `test_config_examples_load.py`). Not counted.
- **DISS-002 (BLOCKING, primary)** — "the loader does not stop a local model's `fallback_chain` from reaching a hosted provider". Partly confirmed: cheval's loader indeed does not, and the dissent/Flatline planners compensate with `hop-locality.py`; Bridgebuilder does not. Counted as Changes Required 1.
- **DISS-C-001 (ADVISORY, companion)** — provider-level `dispatch_group` diverges between the planner and cheval. Confirmed as a consistency gap, but cheval fails closed at load; counted as Observation 2 (LOW), not as the leak the voice described.
- **DISS-C-002 (ADVISORY)** — `cost-report.sh` would count `stale_catalog` rows as unpriced. Refuted: that script classifies unpriced as `pricing_source == "unknown"` only and buckets by `pricing_resolution`; the budget enforcer likewise keys on `unknown`.
- **DISS-C-003 (ADVISORY)** — the final MODELINV emit derives the hop from `models_failed[-1].model`, which "is very likely a bare id". Refuted: `_entry_target = _entry.canonical` (`provider:model`), and the e2e test's all-hops-failed case asserts `destination.provider == "local"`.
- **DISS-C-004 (ADVISORY)** — TransportPolicy only on OpenAI adapters. Confirmed and reproduced; counted as Observation 1 (MEDIUM).
- **DISS-C-005 (ADVISORY)** — a templated `{region}` catalog endpoint would fail every load. Refuted: `validate_declared_endpoint("https://bedrock-runtime.{region}.amazonaws.com")` returns valid and the default catalog loads (`test_hosted_defaults_still_load_unchanged`).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Per-provider insecure-endpoint opt-in: one rule, both paths agree (D-7.2) | Pass | `test_endpoint_validator_optin.py` runs one 30-case table through the validator and `endpoint_policy.check_endpoint`; both agree on code and verdict |
| Request-time rules: no proxy, no redirect, path prefix | Partial | True for `openai`/`openai_compat` on httpx and urllib (stub-server tests); not applied by other adapter types the loader admits (Observation 1) |
| Keyless local provider, no credential on the wire | Pass | `test_opted_in_adapter_sends_no_credential_and_uses_the_policy`, e2e stub asserts no `Authorization` header |
| `response_format` json_schema on chat, honest `schema_enforced`, one retry on a naming 400 | Pass | `test_openai_chat_schema.py` (streaming and non-streaming) |
| Thinking traces: `reasoning_content` and leading `<think>` to `thinking`, `thinking_stripped` recorded | Pass | `test_openai_thinking_strip.py`; tracker `on_progress` keeps the first-token deadline alive without feeding content |
| Over-window prompt refused by name, never truncated | Pass | e2e asserts nothing sent and `failure_class: context_window_refused` |
| MODELINV destination / locality telemetry, schema updated | Pass | payload schema extended additively; e2e validates every captured row against it |
| Price provenance, `stale_catalog`, pricing CLI | Pass | `test_catalog_pricing_provenance.py`; rollup counts stale as priced; bats BUD-1..6 |
| Advisory voices: findings only under `advisory_voices[]`, envelope byte-identical otherwise | Pass | bats ADV-1..9 (ADV-2 passes from an executable path) |
| `local_voices` refuses hosted hops by name — dissent, Flatline | Pass | bats LOC-1..8, FLL-1..7; `hop-locality.py` fail-closed incl. fallback chains |
| `local_voices` — Bridgebuilder | Fail | `isLocalVoice` ignores `fallback_chain` (Changes Required 1); provider-level rule cheval rejects (Observation 2) |
| `local_voices` — health probe | Pass | hosted probe refusal is in the shell path; configured-provider probe through the validator with the provider's opt-in |
| Bridgebuilder trusted config (base ref / repository variable, head-only refusals) | Pass (by reading) | `trusted-config.test.ts` covers precedence, head-only refusal, unsafe ref names; TS tests not executable here |
| Bridgebuilder exit 3 on DEGRADED, `completed/planned` banner, callers treat 3 as completed | Pass | `run-outcome.ts` pure functions; bats `bb-exit-degraded-callers` for dispatcher.sh and spiral-harness; `entry.sh` preflight moved to exit 4 |
| Config examples load (`@example-begin` blocks) | Pass | `test_config_examples_load.py` loads all four marked examples with the real loader |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (fixture keys are `fixture-not-a-key`; the pricing and endpoint CLIs never print a secret)
- [x] Input validation at trust boundaries — opt-in host grammar, hop-name regexes in yq/jq paths, `isSafeRefName` before `git show`, `_CONFIGURED_NAME_RE` in the probe
- [ ] Authorization boundaries consistent — the request-time TransportPolicy covers one adapter family (Observation 1); the `local_voices` posture has a Bridgebuilder gap (Changes Required 1)
- [x] No injection paths found — jq receives data via `--arg`/`--slurpfile`/files; the yq expressions splice only the gate's own config key
- [x] Dependencies — `idna` made lazy and fail-closed; `zod` unchanged
- [x] Error messages do not leak sensitive data — refusals name hosts and codes, never key values

---

## Code Quality Summary

**Strengths:**
- One implementation of the endpoint rule reused by three callers, with a cross-path parity test.
- Fail-closed defaults throughout: missing validator → ConfigError; unreadable config → every hop hosted; malformed budget → 0 cents.
- Honest telemetry (`schema_enforced` derived from the body actually sent; `thinking_stripped`; `destination`).
- Advisory voices isolated by construction and proven byte-identical by test.

**Areas for Improvement:**
- "Local" is defined in three places with three rules (Changes Required 1, Observation 2).
- The TransportPolicy is a base-layer facility wired from one adapter (Observation 1).
- Several new functions exceed the 50-line threshold (Observation 5).
- The implementation report gives the reviewer nothing to verify against (Observation 4).

---

## Next Steps

1. Close Changes Required 1: make Bridgebuilder's locality classification match `hop-locality.py` (fallback chains, unresolved = hosted) and pin it with a test mirroring LOC-7.
2. Decide Observation 1 (refuse the opt-in for adapter types without the policy, or implement the policy in the base adapter) and Observation 2 (one rule for provider-level `dispatch_group`).
3. Re-run the six pytest files, the seven bats files and `npm test` for the skill; record the commands and results in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC Verification walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":3},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:38:00Z"} -->
