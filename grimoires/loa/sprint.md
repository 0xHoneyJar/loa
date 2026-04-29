# Sprint Plan — Cycle-095: Model Currency

**Version:** 1.0
**Date:** 2026-04-29
**Author:** Sprint Planner Agent (deep-name + Claude Opus 4.7 1M)
**PRD Reference:** `grimoires/loa/prd.md` (Flatline-iter6-cleared, kaironic stop)
**SDD Reference:** `grimoires/loa/sdd.md` (Flatline-iter2-cleared, kaironic stop)
**Pre-flight intel:** `grimoires/loa/context/model-currency-cycle-preflight.md`

---

## Executive Summary

Cycle-095 promotes OpenAI's gpt-5.5 family to the standard `reviewer` and `reasoning` aliases (cost-safe, non-pro default), introduces `claude-haiku-4-5-20251001` as a new `tiny` tier, and upgrades the `fast-thinker` agent from `gemini-2.5-flash` to a probe-fallback-protected Gemini 3 fast variant. The structural pivot is gpt-5.5's mandatory routing through OpenAI's `/v1/responses` endpoint — driven by a new registry-metadata field `endpoint_family`, NOT name regex, with a Sprint 1 same-commit migration step and a `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT` env-var backstop for operator-defined custom OpenAI entries.

The cycle is split into **three sprints with a 48-hour soak window** between Sprint 2 and Sprint 3:

- **Sprint 1** (independently mergeable, no defaults flip): ships the routing infrastructure (endpoint_family, response normalization for all six §3.1/§5.4 shapes, alias-level kill-switch, golden fixtures, env-var backstop).
- **Sprint 2** (independently mergeable, lands MVP user-facing): flips `reviewer`/`reasoning` to gpt-5.5, adds Haiku 4.5 + `tiny` tier, adds Gemini 3 fast variant + fallback chain, ships FR-5a cost-guardrail primitives (denylist + max_cost_per_session_micro_usd cost-cap with **pre-call atomicity** + `LOA_PREFER_PRO_DRYRUN` env var), regenerates bash maps, updates 8 caller files, locks `gpt-5.3-codex` as immutable self-map.
- **Soak**: 48-hour observation window after Sprint 2 — monitor cost ledger, downstream consumer issues, probe state.
- **Sprint 3** (opt-in convenience, mergeable post-soak): activates the `prefer_pro_models` flag with `tier_groups.mappings:` populated and `tier_groups.override_user_aliases` opt-in for flag-wins-over-pin precedence.

**Total Sprints:** 3
**Sprint Sizing:** Sprint 1 = LARGE (10 tasks); Sprint 2 = LARGE (10 tasks); Sprint 3 = MEDIUM (6 tasks)
**Total Tasks:** 26
**Estimated Completion:** 2026-05-05 (per PRD §Timeline)

### Phase-gated rollout

Each sprint is independently mergeable per PRD HARD constraint. No Sprint-N depends on Sprint-(N+M) being merged first. Each merge gate is its own circuit breaker: Sprint 1 can land alone (operators see no behavior change unless they explicitly migrate); Sprint 2 lands without the pro-flag (cost-safe defaults active); Sprint 3 lands the opt-in pro flag on top of guardrails that already exist.

### Migration ordering invariant (load-bearing)

Sprint 1 commit MUST add `endpoint_family: chat` to every existing OpenAI registry entry **in the same commit** that activates strict validation (PRD FR-1 AC + SDD §3.4 + Flatline iter-3 IMP-003). The `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop is the operator-side safety net for custom user-config entries that haven't been migrated.

**Loa-specific deployment scope** (Flatline sprint-iter1 SKP-003): the migration invariant is enforceable here because Loa's `.claude/` directory ships as a single git commit consumed by downstream submodule users. There is no split between code and config rollout — both move atomically. The "non-atomic deployment" risk pattern from typical CI/CD pipelines (where code can roll out before config catches up) does NOT apply to Loa's distribution model. For downstream consumers running their own custom CI on top, the migration invariant translates to "your `git submodule update` brings both code and config together; if you stage Loa updates non-atomically with your own config, set `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` during the staging window."

### Sprint kickoff: API stability re-probe (Flatline sprint-iter1 SKP-002)

Each sprint kickoff begins with a 5-minute API re-probe to detect provider-side drift since PRD/SDD writing:

```bash
# Re-probe each provider's models endpoint
curl -sS -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models | jq -r '.data[].id' | grep -E "gpt-5\.5"
curl -sS -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models | jq -r '.data[].id' | grep -i haiku
curl -sS "https://generativelanguage.googleapis.com/v1beta/models?key=$GOOGLE_API_KEY" | jq -r '.models[].name' | grep -E "gemini-3"

# Roundtrip probe each target model
for model in gpt-5.5 gpt-5.5-pro claude-haiku-4-5-20251001 gemini-3-flash-preview; do
  echo "=== $model ==="
  # provider-specific minimal call (see grimoires/loa/context/model-currency-cycle-preflight.md for templates)
done
```

If any target model is no longer reachable OR the response shape has changed materially since the SDD §5.4 spec was locked, sprint kickoff blocks pending PRD/SDD revision. Otherwise, proceed.

---

## Sprint Overview

| Sprint | Theme | Size | Key Deliverables | Primary FRs | Dependencies |
|--------|-------|------|------------------|-------------|--------------|
| 1 | Routing infrastructure + response normalization + kill-switch | LARGE (10) | `endpoint_family` field + strict validation + Sprint 1 migration step + `_route_decision` + six-shape `_parse_responses_response` + `aliases-legacy.yaml` + `LOA_FORCE_LEGACY_ALIASES` + `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT` backstop + 7 golden fixtures + Sprint 1 pytests | FR-1 (partial: routing only — defaults stay) | None |
| 2 | Alias flips + new tiers + cost guardrails + immutable self-map + fallback chain + 8 callers + bash regen | LARGE (10) | `reviewer`/`reasoning` → `openai:gpt-5.5`; `gpt-5.3-codex` immutable self-map; `tiny` → Haiku 4.5; Gemini 3 fast w/ `fallback_chain`; `_resolve_active_model` + cooldown + persistence opt-in; FR-5a `tier_groups` block (denylist + cap + dry-run) with **pre-call atomic guard**; 8 caller files; `generated-model-maps.sh` regenerated | FR-2, FR-3, FR-4, FR-5a, FR-6 | Sprint 1 (routing must work) |
| Soak | 48h observation, no code | n/a | Monitor cost ledger, probe state, downstream consumer issues | n/a | Sprint 2 |
| 3 | `prefer_pro_models` activation + `override_user_aliases` opt-in + dry-run full activation | MEDIUM (6) | `tier_groups.mappings:` populated; `apply_tier_groups()` with **user-pin-wins default** + `override_user_aliases` opt-in; `--dryrun` activation; mandatory WARN log; loa-setup SKILL doc update; E2E goal validation | FR-5 | Sprint 2 + soak window clean |

**Critical path**: Sprint 1 → Sprint 2 → Soak → Sprint 3. Sprint 1 is the foundation; Sprint 2 ships MVP; Sprint 3 is opt-in convenience.

---

## Goals (from PRD §Goals & Success Metrics)

| ID | Goal | Measurement | Validation |
|----|------|-------------|-----------|
| G-1 | gpt-5.5 + gpt-5.5-pro callable through cheval Anthropic-style request flow | Round-trip from cheval to OpenAI `/v1/responses` returns valid `CompletionResult` | New pytests in `test_providers.py::TestOpenAIResponsesEndpointRouting` |
| G-2 | `reviewer` AND `reasoning` both resolve to `openai:gpt-5.5` (cost-safe default; pro tier opt-in only) | `model-invoke --validate-bindings` returns `valid: true` with new aliases | bats / pytest assertion |
| G-3 | `tiny` tier alias added pointing at Haiku 4.5 | Registry has the alias entry; round-trip test calls Haiku 4.5 successfully | New pytest |
| G-4 | `fast-thinker` agent binding upgraded to Gemini 3 fast variant | Agent binding YAML updated; probe confirms AVAILABLE; agent invocation succeeds | bats: `validate_bindings_includes_new_agents` + minimal generation probe |
| G-5 | `hounfour.prefer_pro_models: true` retargets all `*-pro`-eligible aliases | Config-load test: with flag set, `reviewer` resolves to `gpt-5.5-pro`, etc. | New pytest in `test_config.py::TestPreferProModels` |
| G-6 | Zero regression for downstream consumers pinning `gpt-5.3-codex` | Backward-compat alias resolves correctly; `update-loa` smoke against fixture project doesn't error | Existing + new pytest, fixture-project smoke |
| G-7 | Probe-gated fail-fast preserved | Setting `probe_required: true` on a synthetic UNAVAILABLE model still triggers adapter fail-fast | Existing `model-health-probe.bats` coverage retained |

---

## Sprint 1: Routing Infrastructure + Response Normalization + Kill-Switch

**Size:** LARGE (10 tasks)
**Duration:** 2.5 days
**Dates:** 2026-04-30 → 2026-05-01
**Mergeable independently:** YES — operators see no behavior change unless they explicitly migrate

### Sprint Goal
Ship the `endpoint_family`-driven OpenAI routing, complete `/v1/responses` six-shape normalizer, alias-level kill-switch primitive, and operator-side env-var backstop — without flipping any user-facing defaults — so Sprint 2's alias flip lands on a known-good runtime.

### Deliverables
- [ ] `ModelConfig` dataclass extended with `endpoint_family: Optional[str] = None` and `metadata: Dict[str, Any] = field(default_factory=dict)` on `CompletionResult` (additive, types.py)
- [ ] `endpoint_family: chat` added to **every existing** OpenAI registry entry in `.claude/defaults/model-config.yaml` (gpt-5.3-codex → `responses`, gpt-5.2 → `chat`, etc.) **in the same commit** as strict validation
- [ ] `endpoint_family: responses` added to gpt-5.5 and gpt-5.5-pro entries (with `probe_required: true` retained — Sprint 2 drops it)
- [ ] Strict validation activated in `loader.py`: missing/unknown `endpoint_family` on OpenAI entries → `InvalidConfigError` (loud, not silent)
- [ ] `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop honored by validator with WARN identifying each affected entry (operator-migration safety net per SDD §3.4)
- [ ] `_route_decision(model_config)` replaces `_is_codex_model` regex check in `openai_adapter.py`
- [ ] `_build_responses_body` rewritten per SDD §5.3 (instructions, max_output_tokens, typed message blocks, tool_call_id → call_id, simple-string optimization)
- [ ] `_parse_responses_response` rewritten per SDD §5.4 (six-shape normalizer) with strict `UnsupportedResponseShapeError` default + `responses_unknown_shape_policy: degrade` opt-in
- [ ] `aliases-legacy.yaml` snapshot file at `.claude/defaults/` capturing pre-cycle-095 alias state
- [ ] `LOA_FORCE_LEGACY_ALIASES=1` env / `hounfour.experimental.force_legacy_aliases: true` config kill-switch wired into `loader.py` post-merge with one-time WARN log
- [ ] Seven golden fixtures at `.claude/adapters/tests/fixtures/openai/`: `responses_multiblock_text.json`, `responses_tool_call.json`, `responses_reasoning_summary.json`, `responses_refusal.json`, `responses_empty.json`, `responses_truncated.json`, `responses_pro_reasoning_tokens.json`
- [ ] Sprint 1 pytests + bats green (per §7.3 Sprint 1 row)

### Acceptance Criteria
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestOpenAIResponsesEndpointRouting` passes all six cases (a-f from SDD §7.3 Sprint 1)
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestOpenAIResponsesNormalization` passes — one test per fixture (7 total)
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestUnsupportedResponseShape` proves loud-fail path (default strict)
- [ ] `pytest .claude/adapters/tests/test_pricing_extended.py::TestReasoningTokensBilling` proves cost = `output_tokens × output_per_mtok / 1M` (NOT summed with reasoning_tokens)
- [ ] `tests/integration/cycle095-migration.bats` (NEW): (a) Sprint 1 pre-strict-validation file has all OpenAI entries with `endpoint_family`; (b) `model-invoke --validate-bindings` exits 0 post-migration; (c) exits non-zero if `endpoint_family` deleted on any OpenAI entry; (d) `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env var converts validation FAIL → WARN
- [ ] `tests/integration/model-registry-sync.bats` extended: assert every `providers.openai.models.*` has explicit `endpoint_family`
- [ ] `pytest .claude/adapters/tests/test_config.py::TestForceLegacyAliases` proves `LOA_FORCE_LEGACY_ALIASES=1` resolves to legacy snapshot AND each restored alias routes per its own metadata (gpt-5.3-codex → /v1/responses; NOT a forced endpoint switch)
- [ ] No regression in full `pytest .claude/adapters/tests/` run
- [ ] `flatline-model-validation.bats` 15/15 pass
- [ ] No live API call required for CI gate (live tests opt-in via `pytest -m live`)
- [ ] 0 BLOCKING findings on adversarial review of the Sprint 1 PR

### probe_required semantics (Flatline sprint-iter2 SKP-002 760)

Sprint 2 will remove `probe_required: true` from gpt-5.5 / gpt-5.5-pro registry entries. **This is NOT a relaxation of fail-fast guarantees.** Clarification:

- **Before removal**: `probe_required: true` + UNAVAILABLE → adapter rejects request with `ProviderUnavailableError` AND (since the entry is latent) does not even attempt routing. Latent entries are essentially gated-off.
- **After removal**: `probe_required` is no longer set → entry is treated as a normal model entry. The probe still runs on its cadence and updates `model-health-cache.json`. Adapter STILL respects probe state: AVAILABLE → call; UNAVAILABLE → fail-fast (or fallback if `fallback_chain` set). This matches every other registry entry (e.g., gpt-5.3-codex has no `probe_required` and works correctly).

The probe-gated fail-fast invariant from PRD G-7 is preserved by Task 1.10's `model-health-probe.bats` regression tests (these tests verify UNAVAILABLE → adapter raises, regardless of `probe_required` value).

### Technical Tasks

<!-- Goal annotations: see Appendix C for goal-to-task mapping -->

- [ ] **Task 1.1**: Extend `loa_cheval.types.ModelConfig` with `endpoint_family: Optional[str] = None`; extend `CompletionResult` with `metadata: Dict[str, Any] = field(default_factory=dict)`; add `InvalidConfigError` and `UnsupportedResponseShapeError` exception classes (per SDD §5.6) → **[G-1]**
- [ ] **Task 1.2**: Migrate `.claude/defaults/model-config.yaml` — add explicit `endpoint_family` to every `providers.openai.models.*` entry (gpt-5.5/gpt-5.5-pro: `responses`; gpt-5.3-codex: `responses`; gpt-5.2 and any other existing OpenAI entries: `chat`). **Same commit** as Task 1.3. → **[G-1, G-7]**
- [ ] **Task 1.3**: Activate strict validation in `.claude/adapters/loa_cheval/config/loader.py` — post-merge walk over `providers.openai.models.*`; raise `ConfigError("Missing endpoint_family on openai model X")` if absent or not in `{chat, responses}`. Honor `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var as one-shot backward-compat with WARN per affected entry (SDD §3.4). → **[G-1]**
- [ ] **Task 1.4**: Replace `_is_codex_model` regex check at `openai_adapter.py:32-34` with `_route_decision(model_config, model_id)` per SDD §5.2 — returns `"chat"` or `"responses"` or raises `InvalidConfigError`. → **[G-1]**
- [ ] **Task 1.5**: Replace `_build_responses_body` at `openai_adapter.py:108-126` per SDD §5.3 — handles `system → instructions`, multi-message → `input` typed blocks, `tool_call_id → call_id`, `max_completion_tokens → max_output_tokens`, simple-string optimization for single-user-message-no-tool-results. → **[G-1]**
- [ ] **Task 1.6**: Replace `_parse_responses_response` per SDD §5.4 — six-shape normalizer (multi-block text, tool_call/function_call, reasoning summary, refusal, empty, truncated). Map `output_tokens_details.reasoning_tokens` → `Usage.reasoning_tokens`. Implement strict default + `hounfour.experimental.responses_unknown_shape_policy: degrade` opt-in (§5.4.1). Implement >5% visible-token-divergence WARN (PRD §3.1 edge-case). → **[G-1]**
- [ ] **Task 1.7**: Create `.claude/defaults/aliases-legacy.yaml` snapshot capturing pre-cycle-095 alias state (`reviewer: openai:gpt-5.3-codex`, `reasoning: openai:gpt-5.3-codex`, `fast-thinker → gemini-2.5-flash`, etc.). Snapshot captured at Sprint 1 PR creation time from main branch. → **[G-2, G-4, G-6]**
- [ ] **Task 1.8**: Wire `LOA_FORCE_LEGACY_ALIASES=1` env / `hounfour.experimental.force_legacy_aliases: true` config kill-switch into `loader.py` post-merge step — replace `aliases:` block with `aliases-legacy.yaml` content; emit WARN once per process; short-circuit before tier_groups (PRD FR-1 AC + SDD §1.4.5). Critical: each restored alias still routes per its own `endpoint_family` (NO endpoint-force layer). → **[G-2, G-6]**
- [ ] **Task 1.9**: Ship 7 golden fixtures at `.claude/adapters/tests/fixtures/openai/` per SDD §7.2 (six §5.4 shapes + one gpt-5.5-pro reasoning_tokens-bearing). Each fixture carries known-token `usage` for billing validation. → **[G-1]**
- [ ] **Task 1.10**: Author Sprint 1 pytests per SDD §7.3 Sprint 1 row: `TestOpenAIResponsesEndpointRouting` (6 cases including `LOA_FORCE_LEGACY_ALIASES` regression); `TestOpenAIResponsesNormalization` (7 cases per fixture); `TestUnsupportedResponseShape`; `TestReasoningTokensBilling`; `TestForceLegacyAliases`. NEW bats: `tests/integration/cycle095-migration.bats`. Extend `model-registry-sync.bats`. → **[G-1, G-2, G-6, G-7]**

### Dependencies
- None — first sprint of cycle-095. Probe entries already exist in registry from cycle-093 sprint-4.
- External: OpenAI `/v1/responses` endpoint stability (live-probe-confirmed 2026-04-29T01:15Z).

### Security Considerations
- **Trust boundaries**: No new credential surface. `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT` and `LOA_FORCE_LEGACY_ALIASES` are operator-controlled env vars (same risk profile as existing `LOA_PROBE_LEGACY_BEHAVIOR=1`).
- **External dependencies**: No new pip/npm packages. `httpx`/`urllib` and `pyyaml`/`yq` already present.
- **Sensitive data**: PII filters in trajectory logs unchanged. Probe budget caps preserved (`LOA_PROBE_MAX_COST_CENTS=5`, 30s timeout).
- **System Zone authorization**: `.claude/defaults/model-config.yaml` and `.claude/defaults/aliases-legacy.yaml` writes authorized by this PRD/SDD pair.
- **Defense-in-depth**: Adapter-runtime `InvalidConfigError` is belt-and-suspenders; config-load validation is the primary gate.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Migration ordering inversion (strict validation lands before `endpoint_family` migration) | Low | High | Tasks 1.2 and 1.3 MUST land in same commit (PRD FR-1 AC + SDD §3.4); `cycle095-migration.bats` enforces |
| Operator with custom OpenAI entries hits `ConfigError` post-merge | Medium | High | `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop with WARN; CHANGELOG migration note; `--validate-bindings --suggest-migrations` (deferred to Sprint 2 or follow-up) |
| 7th `/v1/responses` shape arrives in production traffic | Medium | High | `UnsupportedResponseShapeError` is the chosen failure mode (loud > silent); `responses_unknown_shape_policy: degrade` opt-in escape hatch; `TestUnsupportedResponseShape` proves the loud-fail path |
| `aliases-legacy.yaml` drifts from "true pre-cycle-095 state" | Low | Medium | Snapshot captured at Sprint 1 PR creation time from main branch; integration test asserts snapshot ≠ post-Sprint-2 aliases (sanity check) |
| Token-accounting divergence on future OpenAI variants | Low | High | >5% divergence WARN catches drift; unit test asserts WARN fires when fixture intentionally has divergence |

### Success Metrics
- 100% line + branch coverage on new `_route_decision`, `_build_responses_body`, `_parse_responses_response`, `aliases-legacy.yaml` loader (per SDD §7.6)
- 100% golden-fixture coverage of all six §5.4 shapes
- Sprint 1 pytest suite ≤30s wall time (CI gate, no live calls)
- 0 BLOCKING findings on Bridgebuilder + Flatline review of the Sprint 1 PR

---

## Sprint 2: Alias Flips + New Tiers + Cost Guardrails + Immutable Self-Map + Fallback Chain

**Size:** LARGE (10 tasks)
**Duration:** 2.5 days
**Dates:** 2026-05-01 → 2026-05-02
**Mergeable independently:** YES (depends on Sprint 1 routing existing in main)

### Sprint Goal
Flip user-facing defaults to gpt-5.5 (cost-safe non-pro) AND add the new tier aliases (Haiku 4.5 + Gemini 3 fast) AND ship the cost-guardrail primitives (denylist + cap + dry-run) so they exist BEFORE Sprint 3's pro-tier flag — addressing Flatline iter-2 SKP-003's "guardrails-after-the-flip" race.

### Deliverables
- [ ] `aliases.reviewer: openai:gpt-5.5` and `aliases.reasoning: openai:gpt-5.5` (NOT `-pro`) in `.claude/defaults/model-config.yaml`
- [ ] `probe_required: true` removed from gpt-5.5 / gpt-5.5-pro entries
- [ ] `gpt-5.3-codex` immutable self-map in `backward_compat_aliases:` (`"gpt-5.3-codex": "openai:gpt-5.3-codex"` — literal, NOT a retarget to 5.5)
- [ ] One-time INFO log on first resolution of legacy `gpt-5.3-codex` alias
- [ ] `claude-haiku-4-5-20251001` registry entry under `providers.anthropic.models` with capabilities, context_window, token_param, **frozen** pricing (live-fetch ONCE at sprint execution time, then committed)
- [ ] `tiny: anthropic:claude-haiku-4-5-20251001` alias
- [ ] `gemini-3-flash-preview` registry entry (default per SDD OQ-1) under `providers.google.models` with `fallback_chain: ["google:gemini-2.5-flash"]`
- [ ] `gemini-3-flash: google:gemini-3-flash-preview` bare alias
- [ ] `fast-thinker` agent binding updated to use new alias
- [ ] Google adapter `_resolve_active_model` (probe-driven demotion + hysteresis cooldown=300s default + optional `fallback.persist_state` + probe-cache trust boundary)
- [ ] `tier_groups:` block in YAML (structurally, with `mappings:` empty for Sprint 2; populated in Sprint 3)
- [ ] `tier_groups.denylist:` field validation in cheval config loader
- [ ] `tier_groups.max_cost_per_session_micro_usd:` enforcement in `metering/budget.py` with **two-phase atomicity** (pre-call estimate guard raises `CostBudgetExceeded` BEFORE API call; post-call reconciliation logs)
- [ ] `LOA_PREFER_PRO_DRYRUN=1` env / `--dryrun` flag printing remap impact preview (without applying)
- [ ] 8 caller files updated to reference new defaults (PRD §FR-2 AC; pre-flight intel:106-113 list)
- [ ] `.claude/scripts/generated-model-maps.sh` regenerated via `gen-adapter-maps.sh` — extended with `MODEL_ENDPOINT_FAMILY` array
- [ ] `.loa.config.yaml.example` updated with new operator surface (per SDD §4.3)
- [ ] CHANGELOG entry with cost comparison: 5.3-codex baseline vs 5.5 vs 5.5-pro (~5-10× input/output baseline due to reasoning_tokens)

### Acceptance Criteria
- [ ] `model-invoke --validate-bindings` returns `valid: true`
- [ ] `tests/integration/flatline-model-validation.bats` 15/15 pass
- [ ] `pytest .claude/adapters/tests/test_chains.py` passes including: `reviewer`/`reasoning` resolve to `openai:gpt-5.5`; `gpt-5.3-codex` self-map resolves LITERALLY (no silent flip to 5.5); cost-ledger entries reflect 5.3-codex pricing for legacy resolutions
- [ ] `pytest .claude/adapters/tests/test_haiku.py` (NEW) passes including frozen-pricing snapshot test
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestFallbackChain` passes all four cases (primary AVAILABLE; primary UNAVAILABLE → fallback; recovery after cooldown; all UNAVAILABLE → `ProviderUnavailableError`)
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestProbeCacheTrustBoundary` (per SDD §3.5) — wrong owner/mode falls through to UNKNOWN
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestFallbackPersistState` (per SDD §3.5) — opt-in persistence works across simulated restarts
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestTierGroupsCostCap` (NEW, FR-5a) — pre-call estimate exceeds cap → `CostBudgetExceeded` raised BEFORE API call; under cap → ok
- [ ] `pytest .claude/adapters/tests/test_providers.py::TestPreferProDryrun` (NEW, FR-5a) — `LOA_PREFER_PRO_DRYRUN=1` + `validate-bindings` prints expected remap; does NOT actually retarget
- [ ] `tests/integration/cycle095-backwardcompat.bats` (NEW, FR-6) — fixture project at v1.92.0-equivalent legacy pin: alias resolution unchanged for legacy IDs; cost-ledger pricing matches 5.3-codex
- [ ] `test_validate_bindings_includes_new_agents` passes (post-cycle-094)
- [ ] All 8 caller files reference new defaults; bash mirror in sync (drift detection green)
- [ ] Manual 3-model Flatline (Opus + gpt-5.5 + Gemini 3) round-trip succeeds (operator-side smoke)
- [ ] No regression in full `pytest .claude/adapters/tests/` run
- [ ] 0 BLOCKING findings on Bridgebuilder + Flatline review of the Sprint 2 PR

### Technical Tasks

- [ ] **Task 2.1**: Update `.claude/defaults/model-config.yaml` aliases section: `reviewer: openai:gpt-5.5`, `reasoning: openai:gpt-5.5` (NOT pro). Drop `probe_required: true` from gpt-5.5 / gpt-5.5-pro entries. → **[G-1, G-2]**
- [ ] **Task 2.2**: Add immutable-self-map: `backward_compat_aliases: {"gpt-5.3-codex": "openai:gpt-5.3-codex"}`. Implement one-time INFO log emission on first resolution per process per alias (per SDD §6.3). → **[G-2, G-6]**
- [ ] **Task 2.3**: Add `claude-haiku-4-5-20251001` to `providers.anthropic.models` with capabilities `[chat, tools, function_calling]`, `context_window: 200000`, `token_param: max_tokens`. Live-fetch pricing ONCE during sprint execution, then **freeze** values into YAML as committed source-of-truth (PRD FR-3 AC + SDD §5.7). Add `tiny: anthropic:claude-haiku-4-5-20251001` alias. → **[G-3]**
- [ ] **Task 2.4**: Add `gemini-3-flash-preview` to `providers.google.models` (default per SDD OQ-1; live-fetch + freeze pricing) with `fallback_chain: ["google:gemini-2.5-flash"]`. Add `gemini-3-flash: google:gemini-3-flash-preview` bare alias. Update `fast-thinker` agent binding. Retain `gemini-2.5-flash` registry entry as bare alias (backward-compat + fallback target). → **[G-4, G-7]**
- [ ] **Task 2.5**: Implement Google adapter `_resolve_active_model` per SDD §5.8 — probe-driven demotion + hysteresis (`fallback.cooldown_seconds: 300` default) + optional `fallback.persist_state: true` (with `flock` for multi-process safety) + probe-cache trust boundary (file owner UID match + mode 0600 — per SDD §3.5 + iter-1 SKP-003 HIGH 770). WARN-once-per-(primary,fallback)-per-process on demotion; INFO-once on recovery; ERROR on cache trust check fail. → **[G-4, G-7]**
- [ ] **Task 2.6**: Implement `tier_groups:` schema block (PRD FR-5a + SDD §3.6) — structurally with `mappings:` EMPTY, `denylist: []`, `max_cost_per_session_micro_usd: null`. Add `denylist` validation: each entry must be a known alias (unknown → WARN, not error). → **[G-5]**
- [ ] **Task 2.7**: Implement `tier_groups.max_cost_per_session_micro_usd:` enforcement in `.claude/adapters/loa_cheval/metering/budget.py` per SDD §1.4.4 — **two-phase atomicity**: (a) pre-call `check_session_cap_pre()` computes `prospective_cost = current_total + (input_tokens × input_per_mtok + max_output_tokens × output_per_mtok)` worst-case; raises `CostBudgetExceeded` BEFORE API call if breached; (b) post-call `check_session_cap_post()` is observability-only. `threading.Lock` serializes the cap-check window. → **[G-5]**
- [ ] **Task 2.8**: Implement `LOA_PREFER_PRO_DRYRUN=1` env / `--dryrun` flag on `model-invoke --validate-bindings` per FR-5a. Prints alias remap preview given current `tier_groups:` config WITHOUT enabling. Even with empty `mappings:` in Sprint 2, dry-run shape works (prints "no remaps configured"). → **[G-5]**
- [ ] **Task 2.9**: Update 8 caller files to reference new defaults. Source list: `grimoires/loa/context/model-currency-cycle-preflight.md:106-113`. Includes yq fallback strings, agent bindings, doc samples. Each caller's reference must use SSOT-derived value, not hardcoded model ID. → **[G-2]**
- [ ] **Task 2.10**: Run `gen-adapter-maps.sh` to regenerate `.claude/scripts/generated-model-maps.sh` — extended with `MODEL_ENDPOINT_FAMILY` associative array (per SDD §1.4.6). Update `.loa.config.yaml.example` with new operator surface (denylist, cap, dryrun, kill-switch examples per SDD §4.3). Author CHANGELOG entry with cost-comparison table per PRD FR-2 AC. NEW bats `cycle095-backwardcompat.bats` (FR-6 fixture project at legacy pin); extend `model-registry-sync.bats`. NEW pytests: `test_haiku.py` (Haiku 4.5 round-trip + pricing freeze); `TestFallbackChain`, `TestProbeCacheTrustBoundary`, `TestFallbackPersistState`, `TestTierGroupsCostCap`, `TestPreferProDryrun` in `test_providers.py`. → **[G-3, G-4, G-6, G-7]**

### Dependencies
- **Sprint 1**: routing must work or callers will hit HTTP 400 (PRD FR-2 dependency).
- **External**: Anthropic `claude-haiku-4-5-20251001` snapshot remains live; Google `/v1beta` keeps returning `gemini-3-flash-preview`. Both probe-confirmed 2026-04-29.

### Security Considerations
- **Trust boundaries**: Probe cache (`.run/model-health-cache.json`) gains explicit ownership/mode trust check (defense against attacker writing the file to manipulate routing — SDD iter-1 SKP-003 HIGH 770). On mismatch, treat cache as missing (probe state UNKNOWN, no fallback) and emit ERROR log.
- **External dependencies**: No new pip/npm packages.
- **Sensitive data**: Pricing values frozen into YAML (System Zone) at sprint execution time; live-fetch happens once, never at runtime — desync between live API price and committed config is operator-action territory (follow-up PR).
- **System Zone authorization**: `.claude/defaults/model-config.yaml`, `.claude/scripts/generated-model-maps.sh` (regenerated), `.claude/adapters/loa_cheval/providers/google_adapter.py`, `.claude/adapters/loa_cheval/metering/budget.py`, `.claude/adapters/loa_cheval/routing/tier_groups.py`, `.loa.config.yaml.example` writes authorized by this PRD/SDD pair.
- **Pricing freshness cadence** (Flatline sprint-iter2 SKP-004 710): pricing values in `.claude/defaults/model-config.yaml` are frozen once (live-fetched at sprint execution time per FR-3 AC). The frozen values can drift if OpenAI/Anthropic/Google change rates. Mitigation: a quarterly or release-bound refresh task (`task pricing-refresh` or equivalent) re-runs the live fetch and emits a diff for operator review. Documented in Sprint 2 deliverables. Sprint 3's mandatory WARN log on `prefer_pro_models` activation reminds operators to verify cost expectations against current pricing. The frozen-pricing snapshot date is documented in CHANGELOG so operators can audit staleness.
- **Cost-cap atomicity** — explicit semantics (Flatline sprint-iter1 SKP-004 CRITICAL 895):
  - **Hard guarantee within a single Loa process**: pre-call estimate uses `max_output_tokens` ceiling; `threading.Lock` serializes the cap-check window. Cap is never exceeded by more than one call's worst-case overshoot.
  - **Soft semantics across multiple Loa processes** (parallel `/run`, CI workers, etc.): each process tracks its own session cap independently. Operators wanting cross-process consistency must use a shared ledger file via `flock` AND a coordinated `trace_id`. CHANGELOG calls this out explicitly: "If you run multiple Loa processes concurrently against a shared budget, each process's cap is independent — sum their caps OR coordinate trace_id manually for true cross-process enforcement."
  - **Documented in CHANGELOG + `loa-setup` SKILL example**: Sprint 2 deliverable. Quoted operator guidance: "max_cost_per_session_micro_usd is a per-process hard guard, not a distributed lock. Multi-process workflows require explicit operator coordination."

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cost cap soft-cap nature surprises operators (multi-process, shared ledger) | Medium | Medium | SDD §1.4.4 documents soft-cap nature explicitly; `threading.Lock` serializes single-process; multi-process is operator-action territory (`flock` on shared ledger documented) |
| Fallback chain hysteresis cooldown=300s wrong for some operators | Low | Low | Cooldown is config-overridable (`fallback.cooldown_seconds`); documentation includes tuning guidance |
| Probe-cache trust check fails in container env (UID mismatch from rootless container) | Medium | Low | Falls through to UNKNOWN behavior (no fallback fires); ERROR log surfaces it; documented as accepted limitation |
| 8 caller files list incomplete (more references hardcode `gpt-5.3-codex`) | Medium | Medium | Cross-reference grep `gpt-5.3-codex` across entire `.claude/` and `grimoires/` trees during Task 2.9; bash regen drift detection (`gen-adapter-maps.sh --check`) catches |
| Pricing freeze drifts from Anthropic/Google live rates | Low | Low | Live-fetch happens at sprint execution; YAML commit is the source-of-truth; rate change is operator-action (follow-up PR) |
| Backward-compat smoke against legacy pin reveals additional regressions | Low | Medium | Sprint 2 launch criterion includes the smoke test; failures gate the merge |
| Schedule slip into soak window | Low | Low | Each sprint is independently mergeable per PRD HARD constraint; soak window can absorb 1 day slip without breaking Sprint 3 |

### Success Metrics
- `flatline-model-validation.bats` 15/15
- 100% line + branch coverage on `_resolve_active_model`, `tier_groups` validator, `check_session_cap_pre`/`_post`
- `model-invoke --validate-bindings` exits 0 with new aliases
- All 8 caller files traced via grep to use SSOT references; 0 hardcoded `gpt-5.3-codex` strings outside backward-compat machinery
- 0 BLOCKING findings on Bridgebuilder + Flatline review of the Sprint 2 PR
- Manual 3-model Flatline smoke succeeds (operator-side)

---

## Soak: 48-Hour Observation Window (PRD §Timeline 2026-05-02 → 2026-05-04)

**Size:** N/A (no code change)
**Duration:** 48 hours
**Dates:** 2026-05-02 (Sprint 2 merge) → 2026-05-04 (Sprint 3 start)

### Soak Goal
Allow downstream consumer pin-bumps and routine framework usage to surface unexpected issues with the Sprint 2 changes (alias flip, immutable self-map, fallback chain, cost guardrails) BEFORE adding the pro-tier opt-in flag in Sprint 3.

### Decision Authority (Flatline IMP-002)

**Decider**: @deep-name (project maintainer per CLAUDE.md). Default to maintainer when only one person; if multiple maintainers in scope, name a single soak-decider per-cycle in the Sprint 2 merge commit message.

**Response time**: triage signal → decision within 4 business hours. If decider is unavailable (PTO, unreachable), Sprint 3 start defers automatically — no implicit "silence is consent" rollover.

**Escalation path** (issue severity tiers):
- **Sev-1** (any data corruption, cost-ledger NaN, downstream consumer breakage): immediate triage; consider immediate kill-switch + rollback PR
- **Sev-2** (probe instability, fallback thrashing, log noise but no incorrect output): triage within 4h; mitigate but don't necessarily block Sprint 3
- **Sev-3** (cosmetic, doc, minor): track in NOTES.md, address in cleanup PR

### Observation Targets — Quantitative Gates (Flatline IMP-001)

| Target | Metric | Pass threshold | Source |
|---|---|---|---|
| Cost-ledger sanity | `jq` over `grimoires/loa/a2a/cost-ledger.jsonl` for 48h window — count entries with `cost_micro_usd <= 0` OR `cost_micro_usd > 100_000_000` (>$100/call sanity) | 0 anomalies | manual run at soak end |
| `reasoning_tokens` correctness | For each pro-tier call (if any): `tokens_reasoning <= tokens_out` (subset invariant) | 100% of pro-tier entries | jq filter |
| Probe state churn | Probe state transitions per model in `grimoires/loa/a2a/trajectory/probe-*.jsonl` | ≤ 5 transitions per model per 48h (more = thrash) | grep + count |
| Adapter HTTP 400s on gpt-5.5* | grep adapter logs for HTTP 400 with model startswith gpt-5.5 | 0 | grep |
| Adapter HTTP 4xx on /v1/responses (excl 429) | grep | 0 (or each instance investigated for shape-handling gap) | grep |
| Kill-switch invocations | grep for `LOA_FORCE_LEGACY_ALIASES` activation logs | 0 (any activation = soak-blocking issue, investigate before Sprint 3) | grep |
| Downstream consumer issues filed | `gh issue list --search "label:cycle-095"` for new entries since Sprint 2 merge | 0 | gh CLI |
| Existing test suite drift | `bats tests/unit/flatline-model-validation.bats` + `tests/unit/mount-version-resolver.bats` + `pytest .claude/adapters/tests/` (full run) | 100% pass on main HEAD | CI run |
| `model-invoke --validate-bindings` | Run on a fresh `.loa.config.yaml` clone | `valid: true` | CLI |

Soak-end checklist (decider runs at T+48h):
1. Pull latest main
2. Run each metric query above
3. If all pass: green-light Sprint 3 in Sprint 3's PR description, link to soak-evidence file
4. If any fail: file `/bug` with cluster of evidence; Sprint 3 start defers until cleared

Evidence preserved at `grimoires/loa/a2a/cycle-095/soak-evidence-{date}.md` (manually authored by decider).

### Soak Exit Criteria
- [ ] All quantitative observation targets pass (above table)
- [ ] Decider explicitly signs off in Sprint 3 PR description
- [ ] If issues surface: triage via `/bug`; soak window does NOT silently extend — explicit re-evaluation gate
- [ ] If kill-switch (`LOA_FORCE_LEGACY_ALIASES=1`) needed at any point: any activation = soak-blocking issue, investigate root cause, do NOT proceed to Sprint 3 until cleared

---

## Sprint 3: prefer_pro_models Activation + override_user_aliases Opt-In + Dry-Run Full Activation

**Size:** MEDIUM (6 tasks)
**Duration:** 1 day
**Dates:** 2026-05-04 → 2026-05-05
**Mergeable independently:** YES (depends on Sprint 2 alias targets + FR-5a guardrails existing in main)

### Sprint Goal
Activate the `hounfour.prefer_pro_models: true` opt-in flag with full retargeting via populated `tier_groups.mappings:`, with **user-pin-wins precedence by default** + opt-in `override_user_aliases: true` for operators who want flag-wins-over-pin behavior — building entirely on top of Sprint 2's already-shipped guardrails (denylist, cost cap, dry-run primitive).

### Deliverables
- [ ] `tier_groups.mappings:` populated in `.claude/defaults/model-config.yaml` with `reviewer: gpt-5.5-pro` and `reasoning: gpt-5.5-pro`
- [ ] `.claude/adapters/loa_cheval/routing/tier_groups.py` (NEW) implementing `apply_tier_groups()` per SDD §5.9 with **user-pin-wins default** precedence (SDD iter-2 SKP-005 fix)
- [ ] `tier_groups.override_user_aliases: false` (default) honored — explicit user `aliases:` pins WIN over flag-driven retargeting unless override is set
- [ ] `tier_groups.override_user_aliases: true` opt-in — flag wins over user pins (denylist still wins over override)
- [ ] `apply_tier_groups()` wired into `loader.py` post-merge AFTER kill-switch short-circuit (per SDD §1.4.5)
- [ ] `--dryrun` mode on `model-invoke --validate-bindings` fully activated — prints all alias resolutions per the SDD §5.10 precedence examples table
- [ ] Mandatory WARN log emitted ONCE per process when `prefer_pro_models: true` activates: "prefer_pro_models is enabled — N aliases retargeted to pro variants; expected cost impact ~5-10× on reasoning_tokens-charged calls. Use tier_groups.denylist to opt specific aliases out, or set tier_groups.max_cost_per_session_micro_usd for hard cap."
- [ ] `.claude/skills/loa-setup/SKILL.md` example shows the flag with denylist + cap configuration
- [ ] CHANGELOG entry on cost impact and opt-in semantics

### Acceptance Criteria
- [ ] `pytest .claude/adapters/tests/test_config.py::TestPreferProModels` (NEW) passes all six cases: (a) flag default false: behavior unchanged; (b) flag true + tier_groups.mappings: aliases retarget; (c) override precedence with `override_user_aliases: false` (default) → user pin WINS; (d) override precedence with `override_user_aliases: true` → flag WINS; (e) denylist: alias listed in denylist NOT retargeted (denylist wins over override); (f) WARN log emitted once per process; dry-run preview output matches §5.10 examples table
- [ ] `tests/integration/cycle095-prefer-pro-e2e.bats` (NEW): with flag on + no user pin, `model-invoke reviewing-code` resolves to `gpt-5.5-pro`; ledger entry uses pro pricing
- [ ] `model-invoke --validate-bindings --dryrun` prints all five precedence rows from SDD §5.10 examples table when given matching synthetic configs
- [ ] All four guardrail interactions tested: denylist + override + flag + cap
- [ ] No regression in Sprint 2 tests; full `pytest .claude/adapters/tests/` run green
- [ ] 0 BLOCKING findings on Bridgebuilder + Flatline review of the Sprint 3 PR
- [ ] E2E goal validation task (Task 3.E2E) passes for all seven PRD goals

### Technical Tasks

- [ ] **Task 3.1**: Populate `tier_groups.mappings:` in `.claude/defaults/model-config.yaml` with `reviewer: gpt-5.5-pro` and `reasoning: gpt-5.5-pro` (per SDD §3.2). → **[G-5]**
- [ ] **Task 3.2**: Implement `.claude/adapters/loa_cheval/routing/tier_groups.py::apply_tier_groups()` per SDD §5.9 — pure config transformation. Critical precedence (SDD §5.10 + iter-2 SKP-005 fix): walk `mappings:`; SKIP if base in denylist; SKIP if base in user-overrides AND `override_user_aliases: false` (default). Implement `_detect_user_alias_overrides()` helper. Populate `validate_tier_groups()` per §3.6 (mappings keys validated, denylist alias-existence WARN, cost-cap type check). → **[G-5]**
- [ ] **Task 3.3**: Wire `apply_tier_groups()` into `.claude/adapters/loa_cheval/config/loader.py` post-merge — AFTER `force_legacy_aliases` short-circuit per SDD §1.4.5. Emit mandatory WARN once per process when retargeting fires (≥1 mapping applied, NOT counting skipped denylist/user-override). → **[G-5]**
- [ ] **Task 3.4**: Activate full `--dryrun` mode on `model-invoke --validate-bindings` per SDD §4.2 — prints all alias resolutions including the precedence-decision lineage ("base → mapping → denylist-skip / user-pin-skip / FINAL"). Does NOT mutate config. Builds on Sprint 2 FR-5a primitive. → **[G-5]**
- [ ] **Task 3.5**: Update `.claude/skills/loa-setup/SKILL.md` example with the flag, denylist, and cost cap. Update `.loa.config.yaml.example` with `tier_groups.mappings:` populated section commented out as opt-in example. Author CHANGELOG entry on cost impact and opt-in semantics. → **[G-5]**
- [ ] **Task 3.6**: Author Sprint 3 pytests per SDD §7.3 Sprint 3 row: `test_config.py::TestPreferProModels` (six cases including precedence + denylist + WARN + dry-run); NEW bats `tests/integration/cycle095-prefer-pro-e2e.bats`. **Plus explicit kill-switch precedence test cases (Flatline sprint-iter1 IMP-006 800):** `TestKillSwitchPrecedence` covers (a) `LOA_FORCE_LEGACY_ALIASES=1` + `prefer_pro_models: true` → kill-switch wins, aliases revert to legacy targets (NOT retargeted to pro); (b) `LOA_FORCE_LEGACY_ALIASES=1` + user pin + `prefer_pro_models: true` → kill-switch still wins (legacy snapshot used regardless of user-config or flag); (c) confirms loader short-circuit ordering per SDD §1.4.5. → **[G-5, G-6]**

### Task 3.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1 through G-7)

**Description:**
Validate that all PRD goals are achieved through the complete cycle-095 implementation (Sprint 1 + Sprint 2 + Sprint 3). This is the final gate before cycle archive.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | gpt-5.5 + gpt-5.5-pro callable through cheval | Run `pytest -m live test_providers.py::TestOpenAIResponsesEndpointRouting` (or fixture replay if no key); inspect ledger entry for round-trip | `CompletionResult` returned; ledger entry has correct micro-USD cost; `reasoning_tokens` populated for pro call |
| G-2 | `reviewer` AND `reasoning` resolve to `openai:gpt-5.5` (cost-safe default) | `model-invoke --validate-bindings`; inspect resolved alias targets | `reviewer → openai:gpt-5.5`; `reasoning → openai:gpt-5.5`; `valid: true` |
| G-3 | `tiny` tier alias points at Haiku 4.5; round-trip works | `pytest test_haiku.py`; `model-invoke --validate-bindings` shows alias | `tiny → anthropic:claude-haiku-4-5-20251001`; round-trip ledger entry has Haiku 4.5 pricing |
| G-4 | `fast-thinker` agent binding upgraded; probe AVAILABLE | `pytest TestFallbackChain`; `model-invoke --validate-bindings`; minimal Gemini 3 generation probe | `fast-thinker → google:gemini-3-flash-preview`; fallback chain populated; generation probe returns 200 OK |
| G-5 | `prefer_pro_models: true` retargets aliases | `pytest TestPreferProModels`; `model-invoke --validate-bindings --dryrun` with synthetic flag-on config | `reviewer → gpt-5.5-pro`; `reasoning → gpt-5.5-pro`; WARN log emitted once; user pin wins by default; denylist + override_user_aliases + cap interact correctly |
| G-6 | Zero regression for `gpt-5.3-codex` pin | `pytest test_chains.py` self-map case; `tests/integration/cycle095-backwardcompat.bats`; `update-loa` smoke against fixture project at legacy pin | Legacy alias resolves LITERALLY; cost-ledger uses 5.3-codex pricing; `update-loa` smoke clean |
| G-7 | Probe-gated fail-fast preserved | Synthetic UNAVAILABLE probe state on a model with `probe_required: true`; adapter call should raise `ProviderUnavailableError` | Adapter fails fast; existing `model-health-probe.bats` tests green |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence (ledger entry, pytest output, bats output)
- [ ] Integration points verified end-to-end (alias → adapter routing → API call → ledger write → CompletionResult)
- [ ] No goal marked as "not achieved" without explicit justification
- [ ] Rollback playbook (PRD §Rollback Playbook) executable in <60s for steps 1-4 (verifiable via dry-run of each step)

### Dependencies
- **Sprint 2**: alias targets must exist (`gpt-5.5-pro` is the retarget destination; FR-5a guardrails in place).
- **Soak window clean**: no rollback signals from Sprint 2 cost ledger or probe state.

### Security Considerations
- **Trust boundaries**: `prefer_pro_models` flag is operator-controlled config. No new credential surface.
- **Override precedence (SDD iter-2 SKP-005 fix)**: User pin-wins-by-default protects operators from silent retargeting of their own pins; `override_user_aliases: true` is the explicit opt-in for the inverted behavior.
- **Cost amplification awareness**: Mandatory WARN at config-load is the user-facing surface for the 5-10× cost impact. Combined with Sprint 2's `max_cost_per_session_micro_usd` cap, operators have both observability and a hard guard.
- **System Zone authorization**: `.claude/defaults/model-config.yaml` (mappings populated), `.claude/adapters/loa_cheval/routing/tier_groups.py`, `.claude/adapters/loa_cheval/config/loader.py`, `.claude/skills/loa-setup/SKILL.md`, `.loa.config.yaml.example` writes authorized by this PRD/SDD pair.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Tier-groups override precedence subtlety surprises operators (custom alias overwritten by mappings) | Medium | Medium | User-pin-wins is the DEFAULT (revised post-iter-2 SKP-005); `override_user_aliases: true` is opt-in; `--dryrun` mode surfaces remap with full precedence-decision lineage |
| `prefer_pro_models` triggers cost-cap exception mid-session and breaks downstream workflow | Medium | Medium | `BudgetExceededError` documented in PRD §Constraints as the safety net; downstream callers already handle it; CHANGELOG includes calibration guidance |
| Operator enables flag without setting cost cap, hits surprise cost spike | Medium | High | Mandatory WARN log on activation directs operator to denylist + cap; documentation example shows recommended pattern; soak-window pre-deployment ensures Sprint 2 guardrails are battle-tested before flag activates |
| Soak window surfaces issue requiring Sprint 2 fix | Low | Medium | Sprint 3 start is gated on clean soak observation; `/bug` triage path is the standard recovery |

### Success Metrics
- 100% line + branch coverage on `tier_groups.py` (`apply_tier_groups`, `validate_tier_groups`, `_detect_user_alias_overrides`)
- 100% of SDD §5.10 precedence-table examples covered in pytest
- E2E goal validation: 7/7 goals validated with documented evidence
- 0 BLOCKING findings on Bridgebuilder + Flatline review of the Sprint 3 PR
- v1.108.0 minor release tag created with consolidated CHANGELOG (per PRD §Timeline)

---

### Flatline Iteration Closeout (kaironic stop, 2 sprint-plan iters)

Sprint plan passed through 2 Flatline iterations 2026-04-29. Real fixes integrated:

- **iter-1 BLOCKERs (5)**: Quantitative soak exit gates + decision authority (§Soak), cost-cap multi-process semantics clarification (§Sprint 2 Risks), kill-switch precedence test cases added to Task 3.6, sprint-kickoff API re-probe (§Migration), Loa-specific atomic-deployment scope (§Migration).
- **iter-2 BLOCKERs (6)**: probe_required semantics clarification (§Sprint 1), pricing-freshness cadence (§Sprint 2 Risks). Other 4 are REFRAMEs of design tensions already resolved in PRD/SDD.

Stop signal per `feedback_kaironic_flatline_signals.md`: HIGH_CONSENSUS plateau (4→3); BLOCKER count flat (5→6 with rotation); iter-2 SKP-005 reframes the same strict-vs-degrade tension covered in PRD/SDD with `degrade` opt-in already shipped. Residual concerns are accepted operational realities (multi-process cost-cap requires operator coordination; frozen-pricing carries documented refresh expectation; timeline slip handled by independent-mergeability of each sprint). Iteration outputs preserved at `grimoires/loa/a2a/flatline/sprint-review-iter{1,2}.json`.

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R-1 | OpenAI `/v1/responses` contract changes mid-flight | 1-2 | Low | High | Pin pytests to dated snapshot `gpt-5.5-2026-04-23` for fixtures; rolling tag for runtime; alias-level kill-switch as escape hatch | Implementer |
| R-2 | Migration ordering inversion (validation before migration) | 1 | Low | High | Tasks 1.2 + 1.3 same commit; `cycle095-migration.bats` enforces; documented in PRD §Risks endpoint-family-mis-config | Implementer |
| R-3 | Operator with custom OpenAI entries hits `ConfigError` post-merge | 1 | Medium | High | `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop; CHANGELOG migration note; `--validate-bindings --suggest-migrations` | Implementer |
| R-4 | gpt-5.5 quality regression vs 5.3-codex on some workloads | 2 | Low | Medium | `gpt-5.3-codex` immutable self-map preserved; CHANGELOG cost+capability comparison helps inform | Implementer |
| R-5 | Cost explosion from `prefer_pro_models` flip | 3 | Medium | High | Mandatory WARN at config-load; per-alias denylist; optional `max_cost_per_session_micro_usd` hard cap (Sprint 2 ships); dry-run mode shows remap impact before enabling | Implementer |
| R-6 | `reasoning_tokens` silent under-billing | 1 | Medium | Medium | `Usage.reasoning_tokens` field; explicit normalization §5.4; cost-ledger logs reasoning_tokens separately; Sprint 1 fixture coverage validates billing math | Implementer |
| R-7 | `/v1/responses` parser breaks on edge shape (refusal, empty, tool-use) | 1 | Medium | High | §5.4 Response Contract Matrix locks all six shapes; golden fixtures Sprint 1; `UnsupportedResponseShapeError` for 7th shape; `responses_unknown_shape_policy: degrade` opt-in escape hatch | Implementer |
| R-8 | Probe race during Sprint 2 alias flip | 2 | Low | Medium | Sprint 1 confirms probe stability separately; Sprint 2 gates merge on freshly-passing probe; kill-switch as escape hatch | Implementer |
| R-9 | Gemini 3 fast variant `-preview` instability | 2 | Medium | Low | `fallback_chain: ["google:gemini-2.5-flash"]` declared; probe-driven automatic demotion; WARN log on demote | Implementer |
| R-10 | Three-array ledger schema fragmentation | 1-3 | Low | Low | This cycle uses `/run sprint-plan` cleanly; no new fragmentation introduced | Implementer |
| R-11 | `@deep-name` doc-rename uncommitted dirt re-emerges | 1-3 | Medium | Low | Selectively stage only this cycle's files (precedent: cycle-094-followups merge process) | Implementer |
| R-12 | Downstream consumer breaks on submodule update | 2 | Low | High | FR-6 hard constraint with backward-compat tests; immutable-self-map for `gpt-5.3-codex`; manual smoke against fixture project at legacy pin | Implementer |
| R-13 | Endpoint-family routing mis-configured | 1 | Low | High | `model-invoke --validate-bindings` REJECTS missing/unknown `endpoint_family` (validation FAIL, not silent default); Sprint 1 migration step adds explicit `endpoint_family: chat` to all existing OpenAI registry entries IN SAME COMMIT as strict validation | Implementer |
| R-14 | Probe cache trust boundary fails in container env | 2 | Medium | Low | Falls through to UNKNOWN behavior (no fallback fires); ERROR log surfaces it; documented as accepted limitation (SDD iter-1 SKP-003) | Implementer |
| R-15 | Tier-groups precedence subtlety surprises operators | 3 | Medium | Medium | User-pin-wins by default (revised post-iter-2 SKP-005); `override_user_aliases: true` is opt-in; `--dryrun` surfaces full precedence lineage | Implementer |
| R-16 | Soak window surfaces issue requiring Sprint 2 fix | 2-3 | Low | Medium | Sprint 3 start is gated on clean soak observation; `/bug` triage path | Operator |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| `flatline-model-validation.bats` pass rate | 15/15 | bats run | 1, 2 |
| `test_validate_bindings_includes_new_agents` | passing | pytest run | 2 |
| Cost-ledger entries for gpt-5.5 calls | non-zero, non-NaN, micro-USD | grep post-smoke | 2, 3 |
| Pre-merge BUTTERFREEZONE / Bridgebuilder review | 0 BLOCKING findings per sprint | adversarial-review.json | 1, 2, 3 |
| New cheval modules coverage | 100% line + 100% branch | `pytest --cov` | 1, 2, 3 |
| Six §5.4 shapes coverage | 100% golden-fixture coverage | pytest | 1 |
| 8 caller files updated | 100% reference SSOT | grep audit | 2 |
| Zero rollback PRs filed | 0 | git log | 7 days post-merge |
| Manual 3-model Flatline smoke | succeeds | operator-side run | 2 |
| E2E goal validation | 7/7 goals validated | Task 3.E2E | 3 |
| v1.108.0 release tag created | 1 tag | post-merge orchestrator | 3 |

---

## Dependencies Map

```
Sprint 1 ─────────▶ Sprint 2 ─────────▶ Soak (48h) ─────────▶ Sprint 3
   │                   │                       │                  │
   │ Routing infra     │ Alias flips +         │ Observation      │ prefer_pro_models
   │ + kill-switch     │ tiers + guardrails    │ window           │ activation
   │ + golden fixtures │ + 8 callers + bash    │ (no code)        │ + override opt-in
   │                   │                       │                  │
   └─ FR-1 (partial)   └─ FR-2/3/4/5a/6        └─ Cost ledger     └─ FR-5
                                                  Probe state
                                                  Downstream pin
```

**Critical path**: Sprint 1 → Sprint 2 → Soak → Sprint 3. Each sprint independently mergeable per PRD HARD constraint; no Sprint-N depends on Sprint-(N+M) being merged.

**Inter-sprint contract surfaces**:
- Sprint 1 → Sprint 2: `endpoint_family` field exists; routing works for all OpenAI models; kill-switch operational; aliases-legacy.yaml snapshot available.
- Sprint 2 → Sprint 3: `gpt-5.5-pro` registry entry + alias targets exist; `tier_groups:` block structurally present; FR-5a guardrails (denylist, cap, dryrun primitive) operational.
- Soak → Sprint 3: Cost ledger clean; probe state stable; no kill-switch invocations.

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature (FR-X) | Sprint | Tasks | Status |
|--------------------|--------|-------|--------|
| FR-1: OpenAI adapter routes via `endpoint_family` | Sprint 1 | 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10 | Planned |
| FR-2: Flip `reviewer`/`reasoning` to gpt-5.5 | Sprint 2 | 2.1, 2.9, 2.10 | Planned |
| FR-3: `tiny` tier alias for Haiku 4.5 | Sprint 2 | 2.3 | Planned |
| FR-4: `fast-thinker` to Gemini 3 fast w/ fallback | Sprint 2 | 2.4, 2.5 | Planned |
| FR-5a: Cost-guardrail primitives (foundation) | Sprint 2 | 2.6, 2.7, 2.8 | Planned |
| FR-5: `prefer_pro_models` flag activation | Sprint 3 | 3.1, 3.2, 3.3, 3.4, 3.5, 3.6 | Planned |
| FR-6: Backward-compat (immutable self-map) | Sprint 2 | 2.2, 2.10 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Tasks | Status |
|---------------|--------|-------|--------|
| §1.4.1 OpenAI Adapter (modified) | Sprint 1 | 1.4, 1.5, 1.6 | Planned |
| §1.4.2 Google Adapter (modified) | Sprint 2 | 2.5 | Planned |
| §1.4.3 Tier Groups Module (NEW) | Sprint 3 | 3.2, 3.3 | Planned |
| §1.4.4 Cost-Cap Enforcer (modified) | Sprint 2 | 2.7 | Planned |
| §1.4.5 Loader (modified) | Sprint 1 + 3 | 1.3, 1.8, 3.3 | Planned |
| §1.4.6 Generated bash maps (regenerated) | Sprint 2 | 2.10 | Planned |
| §1.4.7 model-invoke CLI (modified) | Sprint 2 + 3 | 2.8, 3.4 | Planned |
| §3.2 Registry schema (extended) | Sprint 1 + 2 + 3 | 1.2, 2.1-2.4, 2.6, 3.1 | Planned |
| §3.4 endpoint_family validation | Sprint 1 | 1.3 | Planned |
| §3.5 fallback_chain field | Sprint 2 | 2.4, 2.5 | Planned |
| §3.6 tier_groups validation | Sprint 2 + 3 | 2.6, 3.2 | Planned |
| §5.2 _route_decision | Sprint 1 | 1.4 | Planned |
| §5.3 Body transformation | Sprint 1 | 1.5 | Planned |
| §5.4 Six-shape normalizer | Sprint 1 | 1.6 | Planned |
| §5.5 Cost-ledger billing semantics | Sprint 1 | 1.6, 1.10 | Planned |
| §5.8 Google adapter fallback | Sprint 2 | 2.5 | Planned |
| §5.9 apply_tier_groups | Sprint 3 | 3.2 | Planned |
| §5.10 Override precedence | Sprint 3 | 3.2, 3.4 | Planned |
| §6 Error handling (new exception classes) | Sprint 1 | 1.1, 1.6 | Planned |
| §7 Testing strategy (golden fixtures + tests) | All sprints | 1.9, 1.10, 2.10, 3.6 | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| **G-1** | gpt-5.5 + gpt-5.5-pro callable through cheval Anthropic-style request flow | Sprint 1: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.9, 1.10 + Sprint 2: 2.1 | Sprint 3: Task 3.E2E |
| **G-2** | `reviewer` AND `reasoning` resolve to `openai:gpt-5.5` (cost-safe default) | Sprint 1: 1.7, 1.8, 1.10 + Sprint 2: 2.1, 2.2, 2.9 | Sprint 3: Task 3.E2E |
| **G-3** | `tiny` tier alias added pointing at Haiku 4.5 | Sprint 2: 2.3, 2.10 | Sprint 3: Task 3.E2E |
| **G-4** | `fast-thinker` agent binding upgraded to Gemini 3 fast variant | Sprint 2: 2.4, 2.5, 2.10 | Sprint 3: Task 3.E2E |
| **G-5** | `hounfour.prefer_pro_models: true` retargets all `*-pro`-eligible aliases | Sprint 2: 2.6, 2.7, 2.8 + Sprint 3: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6 | Sprint 3: Task 3.E2E |
| **G-6** | Zero regression for downstream consumers pinning `gpt-5.3-codex` | Sprint 1: 1.7, 1.8, 1.10 + Sprint 2: 2.2, 2.10 | Sprint 3: Task 3.E2E |
| **G-7** | Probe-gated fail-fast preserved | Sprint 1: 1.2, 1.10 + Sprint 2: 2.4, 2.5, 2.10 | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All 7 PRD goals have at least one contributing task
- [x] All 7 goals have validation in Task 3.E2E (final sprint)
- [x] No orphan tasks — every task in Sprints 1, 2, 3 contributes to ≥1 goal

**Per-Sprint Goal Contribution:**

- Sprint 1: G-1 (foundation: routing infra), G-2 (kill-switch + legacy snapshot), G-6 (kill-switch + legacy snapshot), G-7 (migration step preserves existing probe-gated entries)
- Sprint 2: G-1 (defaults flip), G-2 (alias flip + 8 callers), G-3 (Haiku 4.5 + tiny tier complete), G-4 (Gemini 3 fast complete), G-5 (FR-5a guardrail primitives), G-6 (immutable self-map complete), G-7 (fallback chain hardens probe-gated semantics)
- Sprint 3: G-5 (full activation: mappings populated + apply_tier_groups + dry-run + WARN); E2E validation of G-1 through G-7

### D. Operator-Facing Artifacts (cycle-095 surface)

Per SDD §4.1 — these are the new operator-facing surfaces shipped by this cycle:

| Surface | Where | Sprint |
|---------|-------|--------|
| `endpoint_family` field | `.claude/defaults/model-config.yaml`, optionally `.loa.config.yaml` | 1 |
| `aliases-legacy.yaml` snapshot | `.claude/defaults/aliases-legacy.yaml` | 1 |
| `LOA_FORCE_LEGACY_ALIASES=1` env | shell environment | 1 |
| `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env (operator backstop) | shell environment | 1 |
| `hounfour.experimental.force_legacy_aliases: true` | `.loa.config.yaml` | 1 |
| `hounfour.experimental.responses_unknown_shape_policy: degrade` | `.loa.config.yaml` | 1 |
| `reviewer: openai:gpt-5.5` (default flip) | `.claude/defaults/model-config.yaml` | 2 |
| `tiny` alias | `.claude/defaults/model-config.yaml` | 2 |
| `gemini-3-flash` alias | `.claude/defaults/model-config.yaml` | 2 |
| `tier_groups:` block (empty/structural) | `.claude/defaults/model-config.yaml` | 2 |
| `tier_groups.denylist:` | `.loa.config.yaml` | 2 |
| `tier_groups.max_cost_per_session_micro_usd:` | `.loa.config.yaml` | 2 |
| `LOA_PREFER_PRO_DRYRUN=1` env (preview only) | shell environment | 2 |
| `fallback.cooldown_seconds:` (config) | `.loa.config.yaml` | 2 |
| `fallback.persist_state: true` (opt-in) | `.loa.config.yaml` | 2 |
| `tier_groups.mappings:` populated | `.claude/defaults/model-config.yaml` | 3 |
| `hounfour.prefer_pro_models: true` activation | `.loa.config.yaml` | 3 |
| `tier_groups.override_user_aliases: true` opt-in | `.loa.config.yaml` | 3 |
| `model-invoke --validate-bindings --dryrun` (full) | CLI | 3 |

### E. Rollback Playbook (mirrors PRD §Rollback Playbook)

If incident occurs post-merge, in order of escalating intervention:

1. **Symptom-only investigation** (no code change): Check `grimoires/loa/a2a/trajectory/probe-*.jsonl`, cost-ledger entries, `model-invoke --validate-bindings`
2. **Alias-level rollback** (no PR): Set `LOA_FORCE_LEGACY_ALIASES=1` env var (or `hounfour.experimental.force_legacy_aliases: true`)
3. **Per-alias pin** (no PR): User pins `aliases: { reviewer: openai:gpt-5.3-codex }` in `.loa.config.yaml`
4. **Provider-level disable** (no PR): `tier_groups.denylist: [reviewer, reasoning]` (Sprint 2+)
5. **Endpoint-family operator backstop** (no PR): `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` for custom OpenAI entries
6. **Revert PR** (last resort): Standard `git revert` of the merged sprint PR

Each step verifiable in <60s. Steps 1-5 require no merge.

---

*Generated by Sprint Planner Agent (deep-name + Claude Opus 4.7 1M) 2026-04-29.*
*PRD: `grimoires/loa/prd.md` (Flatline-iter6-cleared, kaironic stop).*
*SDD: `grimoires/loa/sdd.md` (Flatline-iter2-cleared, kaironic stop).*
*Pre-flight intel: `grimoires/loa/context/model-currency-cycle-preflight.md`.*
*Next phase: `/flatline-review` on this sprint plan, then `/run sprint-plan` to begin implementation (Sprint 1 first).*
