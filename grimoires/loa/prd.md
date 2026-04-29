# Product Requirements Document: Model Currency Cycle (cycle-095)

**Version:** 1.0
**Date:** 2026-04-29
**Author:** PRD Architect (deep-name + Claude Opus 4.7 1M)
**Status:** Draft (awaiting `/architect`)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [Stakeholder Context](#stakeholder-context)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [Technical Considerations](#technical-considerations)
8. [Scope & Prioritization](#scope--prioritization)
9. [Success Criteria](#success-criteria)
10. [Risks & Mitigation](#risks--mitigation)
11. [Timeline & Milestones](#timeline--milestones)
12. [Appendix](#appendix)

---

## Executive Summary

Promote OpenAI's gpt-5.5 to standard `reviewer` AND `reasoning` aliases across the Loa framework (cost-safe default), replacing the current `gpt-5.3-codex` rolling default. The opt-in `hounfour.prefer_pro_models` configuration flag retargets both to `gpt-5.5-pro` for users who want the higher-capability deep-reasoning tier. Add `claude-haiku-4-5-20251001` as a new low-cost tier alias and upgrade the `fast-thinker` agent binding from `gemini-2.5-flash` to a Gemini 3 fast variant.

The migration is structurally non-trivial: gpt-5.5 and gpt-5.5-pro route through OpenAI's `/v1/responses` endpoint (not `/v1/chat/completions`), requiring an adapter routing change in `cheval/providers/openai_adapter.py` that mirrors the codex routing fix from PR #586 / cycle-088. Routing decisions are driven by registry metadata (`endpoint_family: responses|chat`), not name regex, to avoid brittleness on future model variants. Response normalization spec (multi-block content, tool-use, reasoning summary, refusals, empty/partial outputs, and `reasoning_tokens` cost-ledger mapping) is locked in this PRD with golden-fixture coverage.

Backward compatibility for downstream Loa consumers (loa-as-submodule projects) is a HARD constraint with explicit semantics: `gpt-5.3-codex` is an **immutable self-map** (resolves to `openai:gpt-5.3-codex` literally — NOT a retarget alias to gpt-5.5). Pinned configs experience zero quality or cost shift on submodule update; opt-in via the new aliases or `prefer_pro_models` flag is the only path to the new tier.

The cycle is split into three sprints with phase-gated rollout: Sprint 1 lands the adapter routing change without flipping defaults (probe-confirmable in isolation); Sprint 2 flips defaults, adds new tier aliases, AND ships the cost-guardrails (denylist, dry-run, max-cost cap) so they exist before any potential opt-in to pro tier; Sprint 3 adds the `prefer_pro_models` flag itself, building on the Sprint 2 guardrails. Sprints 1 and 2 form the MVP; Sprint 3 is opt-in convenience. An operational alias-level kill-switch (`LOA_FORCE_LEGACY_ALIASES=1` env var or `hounfour.experimental.force_legacy_aliases: true` config) restores pre-cycle-095 alias resolution for incident rollback without a revert PR.

> **Sources**: `grimoires/loa/context/model-currency-cycle-preflight.md` (full pre-flight intel doc, lines 1-130); session 2026-04-28 / 2026-04-29 user confirmations; live API probes captured 2026-04-29T01:15Z.

---

## Problem Statement

### The Problem

Loa's review-and-reasoning workflows currently route through `gpt-5.3-codex` via the `reviewer` and `reasoning` aliases. OpenAI shipped gpt-5.5 and gpt-5.5-pro on 2026-04-23 (six days before this PRD). The Loa model registry already has latent placeholder entries (`probe_required: true`) added in cycle-093 sprint-4 (T2.3, Flatline SKP-002 HIGH) anticipating these models — those entries can now be activated.

Adjacent gaps in the registry's currency:
- **Anthropic Haiku 4.5** (`claude-haiku-4-5-20251001`, released 2025-10-01) is missing from the registry; no `tiny`/cheap-and-fast tier alias exists.
- **Gemini 3 fast variants** (`gemini-3-flash-preview`, `gemini-3.1-flash-lite-preview`) became live, but the `fast-thinker` agent binding still references `gemini-2.5-flash`. Per cycle-093 #574, `gemini-3-flash` was previously pruned because Google v1beta returned `NOT_FOUND` — that condition no longer holds.

> **Sources**: model-currency-cycle-preflight.md:5-50; live API queries against OpenAI/Anthropic/Google `/v1/models` endpoints, 2026-04-29.

### Pain Points

- **Agent quality drift**: Loa users running review/skeptic/dissenter agents on `gpt-5.3-codex` miss the capability uplift in gpt-5.5-pro (deep-reasoning tier returns `reasoning_tokens` in usage metadata — confirmed via probe).
- **Cost-tier rigidity**: No cheap-and-fast tier between `cheap` (Sonnet 4.6) and the larger-context models. Haiku 4.5 fills this gap.
- **Stale fast-thinker**: `fast-thinker` agent on Gemini 2.5-flash misses Gemini 3 fast-variant improvements; the #574 mitigation is now overly conservative.
- **No pro-tier opt-in**: Users wanting to consistently route through `*-pro` models for everything (e.g., compliance-sensitive shops) currently override aliases per-config; no central switch.

### Current State

> Pre-flight: "`reviewer: openai:gpt-5.3-codex` # Primary review model / `reasoning: openai:gpt-5.3-codex` # Reasoning/skeptic model" (model-config.yaml:145-146 prior to this cycle)

Eight files hardcode `gpt-5.3-codex` as the default. Existing latent registry entries for gpt-5.5* are gated by `probe_required: true` and adapter fail-fasts on UNAVAILABLE.

### Desired State

The model registry (SSOT in `.claude/defaults/model-config.yaml`) lists gpt-5.5 / gpt-5.5-pro / claude-haiku-4-5 / a Gemini 3 fast variant as live entries (no `probe_required` gating where confirmed AVAILABLE). Aliases route to the upgraded models. Cheval's OpenAI adapter routes gpt-5.5* to `/v1/responses`. An opt-in `hounfour.prefer_pro_models: true` flag retargets `reviewer` (and any other tiered alias with a `*-pro` variant) to its pro counterpart at config-load time. All eight caller files reference the new defaults via SSOT-derived `generated-model-maps.sh`. Backward-compat aliases for `gpt-5.3-codex` and `gemini-2.5-*` preserved.

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | gpt-5.5 + gpt-5.5-pro callable through cheval Anthropic-style request flow | Round-trip test from cheval to OpenAI `/v1/responses` returns valid `CompletionResult` | New pytests in `.claude/adapters/tests/test_providers.py::TestOpenAIResponsesEndpointRouting` |
| G-2 | `reviewer` AND `reasoning` both resolve to `openai:gpt-5.5` (cost-safe default; pro tier opt-in only) | `model-invoke --validate-bindings` returns `valid: true` with new aliases | bats / pytest assertion |
| G-3 | `tiny` tier alias added pointing at Haiku 4.5 | Registry has the alias entry; round-trip test calls Haiku 4.5 successfully | New pytest |
| G-4 | `fast-thinker` agent binding upgraded to Gemini 3 fast variant | Agent binding YAML updated; probe confirms AVAILABLE; agent invocation succeeds | bats: `validate_bindings_includes_new_agents` + minimal generation probe |
| G-5 | `hounfour.prefer_pro_models: true` retargets all `*-pro`-eligible aliases | Config-load test: with flag set, `reviewer` resolves to `gpt-5.5-pro`, etc. | New pytest in cheval config tests |
| G-6 | Zero regression for downstream consumers pinning `gpt-5.3-codex` | Backward-compat alias resolves correctly; `update-loa` smoke against a fixture project doesn't error | Existing + new pytest, fixture-project smoke |
| G-7 | Probe-gated fail-fast preserved | Setting `probe_required: true` on a synthetic UNAVAILABLE model still triggers adapter fail-fast | Existing model-health-probe.bats coverage retained |

### Key Performance Indicators

| Metric | Current | Target | Validation |
|--------|---------|--------|-----------|
| `flatline-model-validation.bats` pass rate | 15/15 (post-#648) | 15/15 | bats run on each sprint |
| `test_validate_bindings_includes_new_agents` | passing (post-#647) | passing | pytest run |
| Cost-ledger entries for gpt-5.5 calls | n/a (no calls yet) | non-zero, non-NaN, denominated in correct micro-USD | grep post-smoke |
| Pre-merge BUTTERFREEZONE / Bridgebuilder review | n/a | 0 BLOCKING findings per sprint | adversarial-review.json |

### Constraints

- **Backward compatibility (HARD)**: `gpt-5.3-codex`, `claude-opus-4-7`, `gemini-2.5-flash`, etc., must remain valid via `backward_compat_aliases:` and existing alias entries. Existing user `.loa.config.yaml` files MUST resolve identically post-merge.
- **Phase-gated rollout (HARD)**: Each sprint independently mergeable; no Sprint-N depends on Sprint-(N+M) being merged first.
- **Default flag value MUST be `false`** for `hounfour.prefer_pro_models` so opt-in semantics hold.
- **Snapshot pinning policy**: Aliases stay rolling (`gpt-5.5`, not `gpt-5.5-2026-04-23`) per current Loa convention. Pinned snapshots reserved for test fixtures.

> **Sources**: model-currency-cycle-preflight.md:118-127 (stability constraints); session 2026-04-29 user confirmation on snapshot pinning ("stay rolling").

---

## Stakeholder Context

### Primary: Loa framework users (this repo's operators)

**Role**: Engineers who run `/plan`, `/build`, `/review`, `/ship` workflows.
**Goals**: Get capability uplift on the new OpenAI tier without manual `.loa.config.yaml` overrides per project. Maintain backward compatibility for existing in-flight cycles.
**Pain Points**: Stale defaults; no pro-tier-everything switch; no Haiku tier.

### Secondary: Downstream Loa consumers (loa-as-submodule projects)

**Role**: Engineers in projects (like the #642 reporter at `0xHoneyJar/micodex-studio`, formerly pinned at v1.92.0) consuming Loa via git submodule.
**Goals**: Bump submodule pin, get the upgrade automatically, no breakage.
**Pain Points**: Any silent behavior change to `reviewer`/`reasoning` mid-pin would surface as confusing test failures or unexpected API costs in their workflows.

> **Sources**: memory `project_session_20260428_outcomes.md` (downstream submodule consumer flow); session 2026-04-28 on #642 closure pattern.

### Tertiary: Future contributors

**Role**: Engineers adding new providers or models in subsequent cycles.
**Goals**: Clear precedent for how to add a tiered alias system (the `tier_groups` schema introduced in Sprint 3 should generalize).
**Pain Points**: Currently no documented pattern for opt-in tier-wide retargeting.

### Non-stakeholders

- End users of downstream products built atop Loa-using projects — they don't see Loa directly. Migration is invisible to them as long as quality holds.

---

## Functional Requirements

### FR-1: OpenAI adapter routes gpt-5.5* through `/v1/responses` endpoint via registry metadata

**Priority:** Must Have (blocks all other sprints)
**Sprint:** 1

**Description:** The cheval Python OpenAI adapter (`.claude/adapters/loa_cheval/providers/openai_adapter.py`) currently routes all model calls through `/v1/chat/completions`. gpt-5.5 and gpt-5.5-pro (and the entire 5.5 family by extension) reject `/v1/chat/completions` with HTTP 400 `invalid_request_error`. They MUST route through `/v1/responses`. Routing decisions are driven by a new registry metadata field `endpoint_family: responses|chat` on each model entry — explicit-required (validation fails on missing or unknown value), NOT model-name regex (regex is brittle to future model variants). Sprint 1 migration step pre-populates `endpoint_family: chat` on all existing OpenAI entries BEFORE strict validation activates. The codex routing fix from PR #586 (cycle-088) is the precedent for the routing-decision shape; this cycle generalizes it via metadata.

**Acceptance Criteria:**
- [ ] `.claude/defaults/model-config.yaml` adds `endpoint_family: responses` to gpt-5.5 and gpt-5.5-pro entries; existing OpenAI entries (gpt-5.3-codex, gpt-5.2 etc.) get explicit `endpoint_family: chat` for clarity
- [ ] OpenAI adapter reads `endpoint_family` from `model_config`. If absent on a registered OpenAI model entry, `model-invoke --validate-bindings` flags as **misconfigured** (validation FAIL, not silent default) — forces explicit declaration. Backward-compat: a one-time migration step in Sprint 1 adds `endpoint_family: chat` to all existing OpenAI registry entries (gpt-5.3-codex, gpt-5.2, etc.) so post-merge state is fully explicit.
- [ ] Adapter does NOT use name regex for endpoint detection. Endpoint determined by `endpoint_family` value: `chat` → `/v1/chat/completions`, `responses` → `/v1/responses`, unknown value → adapter raises `InvalidConfigError` at request time (never silently default).
- [ ] Request body shape adapted per endpoint family (see Response Contract Matrix in Technical Considerations §3.1):
  - `chat`: existing `messages`, `max_completion_tokens` shape unchanged
  - `responses`: `input` (string OR list of typed message blocks), `max_output_tokens`
- [ ] Response normalization handles ALL six output-shape variants from §3.1 (multi-block text, tool_use, reasoning summary, refusal, empty, partial-truncated)
- [ ] `reasoning_tokens` from `output_tokens_details.reasoning_tokens` mapped to `Usage.reasoning_tokens` field AND included in cost-ledger billing calculation
- [ ] Operational kill-switch operates at the **alias resolution layer** (single design — no contradicting endpoint-force layer): env var `LOA_FORCE_LEGACY_ALIASES=1` OR config `hounfour.experimental.force_legacy_aliases: true` restores pre-cycle-095 alias resolution (`reviewer`/`reasoning` → `openai:gpt-5.3-codex`, `fast-thinker` → `gemini-2.5-flash`, etc.). Each restored alias then routes to its own provider/endpoint per registry metadata (gpt-5.3-codex → /chat/completions, etc.) — there is no endpoint-force layer. Adapter logs WARN once per process when kill-switch is active.
- [ ] New pytests cover: gpt-5.5 routing via metadata to `/v1/responses`, gpt-5.5-pro routing (with `reasoning_tokens` assertion), gpt-5.3-codex routing via metadata to `/v1/chat/completions` UNCHANGED (regression guard), alias-level kill-switch (`LOA_FORCE_LEGACY_ALIASES=1`) makes `reviewer` resolve to `openai:gpt-5.3-codex` (which then routes to /chat/completions per its own metadata — NOT a forced endpoint switch)
- [ ] Golden fixtures for all six response shapes in §3.1
- [ ] Round-trip test against live API succeeds (or, in CI: golden fixture replay)

**Dependencies:** None — independently mergeable. Probe entries already exist in registry.

> **Sources**: model-currency-cycle-preflight.md:33-49 (routing requirement, live probe evidence); PR #586 (cycle-088, codex routing precedent — `feedback_bridgebuilder_codex_routing.md` memory); Flatline cluster 2 (response normalization spec — SKP-001 CRITICAL); Flatline cluster 4 (registry-metadata routing — SKP-003); Flatline cluster 5 (kill-switch — IMP-002).

---

### FR-2: Flip `reviewer` and `reasoning` aliases to gpt-5.5 (cost-safe default)

**Priority:** Must Have
**Sprint:** 2 (depends on FR-1 completion)

**Description:** Update `.claude/defaults/model-config.yaml` aliases section to retarget BOTH `reviewer` and `reasoning` to `openai:gpt-5.5` (the non-pro tier). The pro tier (`gpt-5.5-pro`) is reachable ONLY via the opt-in `prefer_pro_models` flag (FR-5) — this is a deliberate cost-safety choice (Flatline cluster 3 / SKP-002 HIGH 720): gpt-5.5-pro charges for invisible `reasoning_tokens`, and silently flipping `reasoning`-aliased agents (Flatline skeptic, dissenter) to pro could 5-10× per-cycle costs for downstream consumers who pin-bump without realizing. Drop `probe_required: true` from the gpt-5.5 and gpt-5.5-pro registry entries (they're now confirmed live). Preserve `gpt-5.3-codex` as an immutable self-map (NOT a retarget alias).

**Acceptance Criteria:**
- [ ] `reviewer: openai:gpt-5.5` in aliases section
- [ ] `reasoning: openai:gpt-5.5` in aliases section (NOT `-pro`; the pro variant is opt-in via `prefer_pro_models`)
- [ ] `probe_required: true` removed from `providers.openai.models.gpt-5.5` and `gpt-5.5-pro`
- [ ] `gpt-5.3-codex` retained as a registry entry under `providers.openai.models` AND as a self-map in `backward_compat_aliases:` (i.e., `"gpt-5.3-codex": "openai:gpt-5.3-codex"`). This is NOT an alias to gpt-5.5 — pinned configs continue to call the literal old model. Resolution emits a one-time INFO log: "gpt-5.3-codex preserved for back-compat; consider migrating to `reviewer` alias for current default tier."
- [ ] `generated-model-maps.sh` regenerated via `gen-adapter-maps.sh`
- [ ] CHANGELOG entry warns: "If you previously relied on `reviewer`/`reasoning` for high-quality output, the new default is gpt-5.5 (non-pro). Set `hounfour.prefer_pro_models: true` to retarget to gpt-5.5-pro for both reviewer and reasoning, OR pin specific aliases manually."
- [ ] Eight caller files updated to reference new defaults (yq fallback strings, agent bindings, doc samples — full list in pre-flight intel)
- [ ] `model-invoke --validate-bindings` returns `valid: true`
- [ ] `flatline-model-validation.bats` 15/15 pass
- [ ] Cost comparison documented in CHANGELOG: typical Flatline cycle on gpt-5.3-codex (~baseline) vs gpt-5.5 (~Δ%) vs gpt-5.5-pro (~5-10× input/output baseline due to reasoning_tokens)

**Dependencies:** FR-1 (routing must work first or callers will hit HTTP 400).

> **Sources**: model-currency-cycle-preflight.md:106-113 (8-file caller list); Flatline cluster 1 (immutable-self-map decision — SKP-001 CRITICAL 910); Flatline cluster 3 (cost-safe default — SKP-002 HIGH 720); session 2026-04-29 user confirmation on Cluster 3 = Option B.

---

### FR-3: Add `tiny` tier alias for Haiku 4.5

**Priority:** Must Have
**Sprint:** 2

**Description:** Add `claude-haiku-4-5-20251001` as a registry entry under `providers.anthropic.models`. Add a `tiny` (or operator-confirmed name during `/architect`) alias pointing at it. Pricing for Haiku 4.5 to be live-fetched during sprint execution.

**Acceptance Criteria:**
- [ ] `claude-haiku-4-5-20251001` listed under `providers.anthropic.models` with capabilities, context_window, token_param, pricing
- [ ] New alias (proposed: `tiny`) added under `aliases:` pointing at `anthropic:claude-haiku-4-5-20251001`
- [ ] Round-trip pytest call to Haiku 4.5 via cheval succeeds (live or fixture)
- [ ] Pricing reflects Anthropic's published rates: live-fetch ONCE during sprint execution, then **freeze the fetched values into `.claude/defaults/model-config.yaml`** as the committed source-of-truth. Subsequent runs read from YAML (not re-fetched). When provider raises rates, follow-up PR refreshes YAML. Rationale: keeping live-fetch as the runtime path would desynchronize ledger math from committed config (Flatline iter-5 SKP-006).

**Dependencies:** None — Anthropic adapter has no special routing requirements for Haiku 4.5 (probe-confirmed `200 OK` on `/v1/messages`).

> **Sources**: model-currency-cycle-preflight.md:79-88 (probe-confirmed availability); session 2026-04-29 user confirmation on Haiku 4.5 inclusion.

---

### FR-4: Upgrade `fast-thinker` agent binding to Gemini 3 fast variant with automatic fallback

**Priority:** Must Have
**Sprint:** 2

**Description:** Update the `fast-thinker` agent in `.claude/defaults/model-config.yaml:237-240` from `model: gemini-2.5-flash` to a Gemini 3 fast variant. Two probe-confirmed candidates: `gemini-3-flash-preview` (more direct upgrade path) or `gemini-3.1-flash-lite-preview` (newer, lighter). Architecture phase to pick. Because both candidates carry the `-preview` suffix (Google's signal for not-yet-stable models), this FR includes a fallback chain so probe-driven UNAVAILABLE status auto-demotes to a stable model rather than failing the agent invocation.

**Acceptance Criteria:**
- [ ] Chosen variant added to `providers.google.models` with new field `fallback_chain: ["google:gemini-2.5-flash"]` (architecture phase to extend chain if multiple fallbacks justified)
- [ ] Bare alias added under `aliases:` (e.g., `gemini-3-flash: google:gemini-3-flash-preview`)
- [ ] `fast-thinker` agent binding updated to use the alias
- [ ] `gemini-2.5-flash` retained in registry + as alias (backward-compat hard constraint AND serves as fallback target)
- [ ] Adapter implements probe-driven demotion: when primary entry's probe-state transitions to UNAVAILABLE, adapter automatically uses next entry in `fallback_chain` for subsequent calls. WARN-level log on each demotion. Demotion clears when probe returns to AVAILABLE.
- [ ] `model-invoke --validate-bindings` returns `valid: true`
- [ ] Probe round-trip succeeds for the chosen variant
- [ ] New pytest covers fallback-chain demotion: simulate probe UNAVAILABLE on primary, assert adapter routes call to fallback, assert WARN log emitted

**Dependencies:** None.

**Open question for `/architect`:** Pick between `gemini-3-flash-preview` and `gemini-3.1-flash-lite-preview`. Probe data alone is insufficient; need to weigh cost, capability, "preview" stability connotations.

> **Sources**: model-currency-cycle-preflight.md:90-96 (probe results); pre-flight assumption #2 (architecture phase to decide); Flatline cluster 7 (preview-fallback automation — SKP-004 HIGH 735).

---

### FR-5a: Cost-guardrail primitives (foundation for FR-5)

**Priority:** Must Have
**Sprint:** 2 (lands BEFORE any pro-tier flip is possible)

**Description:** Ship the cost-safety primitives in Sprint 2 alongside the alias flip, so they exist BEFORE Sprint 3's `prefer_pro_models` flag becomes operational. This addresses the "guardrails-after-the-flip" race that Flatline iter-2 SKP-003 flagged.

**Acceptance Criteria:**
- [ ] `tier_groups:` block exists in `.claude/defaults/model-config.yaml` (initially empty / structural-only — populated when `prefer_pro_models` is implemented in FR-5)
- [ ] `tier_groups.denylist:` field validation in cheval config loader — accepts list of alias names, validates each is a known alias
- [ ] `tier_groups.max_cost_per_session_micro_usd:` field — when set, cheval per-session cost-ledger sum is checked; on breach, adapter raises `CostBudgetExceeded`. Independent of `prefer_pro_models` (usable today with non-pro defaults)
- [ ] `LOA_PREFER_PRO_DRYRUN=1` env var (or `--dryrun` flag on `model-invoke`) prints the alias remap impact a hypothetical `prefer_pro_models: true` WOULD produce, given current `tier_groups:` config — without enabling
- [ ] Pytests cover: cap enforcement (CostBudgetExceeded raised correctly), denylist validation (warns on unknown alias), dry-run output

**Dependencies:** FR-2 (aliases must exist).

> **Sources**: Flatline iter-2 cluster SKP-003 (guardrail-before-flip ordering — HIGH 745); user request for opt-in pro flag with safety mechanisms.

---

### FR-5: `hounfour.prefer_pro_models` opt-in flag with cost guardrails

**Priority:** Should Have (independent value; mergeable separately)
**Sprint:** 3

**Description:** Add a configuration flag `hounfour.prefer_pro_models: true` that, when set, retargets every alias with a `*-pro` variant to that variant at cheval config-load time. Default: `false` (backward-compat hard constraint). The retargeting is declarative via a new `tier_groups:` block in `model-config.yaml` so future tiers can be added without code changes. **Because pro-tier flips can 5-10× per-call costs (gpt-5.5-pro `reasoning_tokens` charges), the flag carries explicit cost-safety controls**: per-alias denylist, dry-run preview, optional max-cost cap, and a mandatory config-load WARN log.

**Acceptance Criteria:**
- [ ] `tier_groups:` block exists in `.claude/defaults/model-config.yaml` mapping each base alias to its pro variant (per-alias entries; e.g., `reviewer: gpt-5.5-pro`, `reasoning: gpt-5.5-pro`)
- [ ] Cheval config loader (`.claude/adapters/loa_cheval/config/loader.py`) reads `hounfour.prefer_pro_models` flag and walks `tier_groups:` if set, producing a config with retargeted aliases
- [ ] Default `false` keeps current behavior — verified by pytest
- [ ] Per-alias overrides in user `.loa.config.yaml` STILL win over the flag (precedence: user override > `tier_groups.denylist` > flag-driven retargeting > base alias)
- [ ] **Per-alias denylist**: `tier_groups.denylist: [alias1, alias2]` opt-out for specific aliases the user wants to keep on the non-pro tier even with the flag set. Validation: warn if denylist references an alias that has no `*-pro` variant.
- [ ] **Dry-run mode**: `LOA_PREFER_PRO_DRYRUN=1` env var (or `--dryrun` CLI flag on `model-invoke --validate-bindings`) prints the alias remap impact (`reviewer: gpt-5.5 → gpt-5.5-pro`, etc.) without applying. Useful for "what if I turn this on?" inspection.
- [ ] **Optional cost cap**: `tier_groups.max_cost_per_session_micro_usd: <int>` config field. When set, cheval per-session cost-ledger sum is checked against this cap; on breach, adapter raises `CostBudgetExceeded` exception (existing exception type). Cap defaults to unset (no enforcement). Independent of `prefer_pro_models` so users can use cost cap with non-pro defaults too.
- [ ] **Mandatory WARN at config-load** when `prefer_pro_models: true`: emits ONCE per process startup at WARN level: "prefer_pro_models is enabled — N aliases retargeted to pro variants; expected cost impact ~5-10× on reasoning_tokens-charged calls. Use `tier_groups.denylist` to opt specific aliases out, or set `tier_groups.max_cost_per_session_micro_usd` for hard cap."
- [ ] New pytests in `test_config.py::TestPreferProModels` cover: flag default, flag with various tier_groups setups, override precedence, denylist behavior, dry-run output, cost cap enforcement, WARN log emitted
- [ ] Documentation updated (`.claude/skills/loa-setup/SKILL.md` example shows the flag with denylist + cap)

**Dependencies:** FR-2 (the alias targets must exist).

> **Sources**: session 2026-04-28 user request ("i also want a flag which enables people to choose the pro pricer version for everything"); pre-flight assumption #1 (scope of "all `*-pro`-eligible aliases"); Flatline cluster 6 (cost guardrails — IMP-006, SKP-005 HIGH 720).

---

### FR-6: Backward compatibility preservation (immutable-self-map semantics)

**Priority:** Must Have (HARD constraint)
**Sprint:** 2 (alongside FR-2)

**Description:** Existing user configurations and downstream consumer code must not break. **Immutable-self-map semantics** (locked post-Flatline cluster 1): legacy model IDs resolve to themselves (the literal old model), NOT to retargeted newer models. This is a deliberate choice — silent retargeting was identified as CRITICAL risk because pinned configs would shift quality, latency, and cost without operator awareness.

**Concrete contract:**
- `gpt-5.3-codex`: registry entry preserved + `backward_compat_aliases: {"gpt-5.3-codex": "openai:gpt-5.3-codex"}` (self-map). User specifying `reviewer: gpt-5.3-codex` continues to call literal gpt-5.3-codex.
- `claude-opus-4-7`: unchanged (already current default).
- `gemini-2.5-flash`, `gemini-2.5-pro`: registry entries preserved as bare aliases (currently in `aliases:` block per #647).
- Any historical alias retargeting (e.g., `claude-opus-4.5 → claude-opus-4-7`) introduced in prior cycles remains unchanged — those decisions stand.

**Acceptance Criteria:**
- [ ] `backward_compat_aliases:` updated with self-maps for `gpt-5.3-codex` and any other legacy IDs that shouldn't silently retarget
- [ ] All four bash adapter maps (MODEL_PROVIDERS, MODEL_IDS, COST_INPUT, COST_OUTPUT in `generated-model-maps.sh`) regenerated and contain entries for ALL legacy IDs (literal targets, not retargets)
- [ ] New pytest `test_backward_compat.py` verifies: setting `reviewer: gpt-5.3-codex` in user config resolves to `openai:gpt-5.3-codex` LITERALLY (no silent flip to 5.5); cost-ledger entries reflect 5.3-codex pricing, not 5.5
- [ ] One-time INFO log emitted on first resolution of a legacy alias: "Note: <alias-name> preserved for back-compat; consider migrating to `<recommended-alias>` for current default tier."
- [ ] `update-loa` smoke against a fixture project at v1.92.0 pin (or similar legacy state) does not error on alias resolution AND does not silently change quality/cost

> **Sources**: pre-flight intel "Stability constraints" (model-currency-cycle-preflight.md:118-122); memory `project_session_20260428_outcomes.md` on backward-compat-aliases pattern; Flatline cluster 1 (locked immutable-self-map decision — SKP-001 CRITICAL 910).

---

## Non-Functional Requirements

### Performance

- **Probe latency**: New entries' first probe ≤30s per provider call. Subsequent probes hit the cache.
- **Adapter latency overhead**: New `/v1/responses` routing adds ≤5ms per call in the routing-decision branch (no measurable difference to network-bound API call time).
- **Config-load latency**: `prefer_pro_models` flag processing adds ≤10ms to cheval config load (one extra dict walk over `tier_groups:`).

### Reliability

- **Probe-gated fail-fast preserved**: Adapter must fail-fast (raise `ProviderUnavailableError`) when probe state is UNAVAILABLE. No silent fallback to unrelated model.
- **Atomic config writes**: Any registry edit that touches `model-config.yaml` must use the existing tmp+mv atomic write pattern (precedent: `update-loa-bump-version.sh`).
- **No partial-state cycle merges**: Each sprint either lands fully or rolls back; no sprint leaves the registry in an intermediate state where some callers reference new aliases and others reference old.

### Security

- **No new credential surface**: Migration uses existing `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY` env vars. No new secrets introduced.
- **Probe respects budget cap**: `LOA_PROBE_MAX_COST_CENTS=5` (default) and per-call timeout (default 30s) enforced for any new probe wiring.
- **No PII in trajectory logs**: Existing PII filters apply unchanged.

### Observability

- **Cost ledger entries** for gpt-5.5 calls denominated in micro-USD (existing convention from sprint-bug-108) — pricing values match registry. Any cached-input variation tracked in followup.
- **Probe state changes** logged to `grimoires/loa/a2a/trajectory/probe-*.jsonl` with model_id, state transition, latency_ms.
- **Routing-decision logs** at DEBUG level when adapter routes a call to `/v1/responses` vs `/v1/chat/completions` — useful for debugging routing-edge bugs.

### Compliance

- **Snapshot policy**: Stay rolling (per user direction). Pinned snapshots like `gpt-5.5-2026-04-23` reserved for golden test fixtures.
- **Three-zone enforcement**: All registry edits land in `.claude/defaults/` (System Zone) — authorized by cycle-level approval recorded in this PRD.

---

## Technical Considerations

### Architecture Notes

The cheval Python adapter has the routing-decision logic as the natural insertion point. PR #586 added an early-branch in `complete()` that inspected `request.model` against a regex/allowlist for codex routing. **This cycle generalizes that pattern** by making the routing decision driven by a registry-metadata field (`endpoint_family: responses|chat`) on each model entry rather than name regex. Adapter consults `model_config.endpoint_family` and dispatches: `chat` → `/v1/chat/completions`, `responses` → `/v1/responses`. **No silent default**: missing or unknown `endpoint_family` is rejected at validation time (`model-invoke --validate-bindings` flags as misconfigured) and at runtime (adapter raises `InvalidConfigError`). The Sprint 1 migration step ensures all existing OpenAI registry entries carry an explicit `endpoint_family: chat` BEFORE strict validation goes live, so no existing entry breaks.

### §3.1 — Response Contract Matrix (cycle-095, locked in PRD per Flatline SKP-001 CRITICAL)

The `/v1/responses` endpoint returns a **fundamentally different shape** than `/v1/chat/completions`. The adapter MUST normalize all six observed shapes to the existing canonical `CompletionResult` dataclass without lossy data shifts. Sprint 1 ships golden fixtures for each shape.

| Shape | Detect | Normalize to `CompletionResult` |
|-------|--------|--------------------------------|
| **Multi-block text** | `output[]` array contains 1+ `{type: "message", content: [{type: "output_text", text: ...}]}` blocks | Concatenate all `output_text` `text` fields with `\n\n` separator → `result.content` |
| **Tool-use** | `output[]` contains `{type: "tool_call", name, arguments, id}` (or `function_call` per current OpenAI naming) | Convert each tool_call to canonical `tool_calls[]` shape (matches existing `/chat/completions` parsed output): `{id, type: "function", function: {name, arguments}}`. Pre-text content (if any) flows to `result.content`. |
| **Reasoning summary** | `output[]` contains `{type: "reasoning", summary: [{text: ...}]}` (visible-summary block, distinct from invisible `reasoning_tokens` count) | Concatenate summary text → `result.thinking` (existing field). Final `output_text` blocks still flow to `result.content`. |
| **Refusal / safety** | `output[]` contains `{type: "refusal", refusal: <string>}` OR `incomplete_details: {reason: "content_filter"}` at top level | Set `result.content` to refusal text; set `result.metadata["refused"] = true`; do NOT raise — let caller handle |
| **Empty output** | `output[]` is empty array OR all blocks have empty content | `result.content = ""`; emit WARN log with model_id + request hash; do NOT raise — caller may legitimately request 0 tokens |
| **Partial / truncated** | `incomplete_details: {reason: "max_output_tokens"}` (or similar non-`stop` finish) | Normal content extraction, but set `result.metadata["truncated"] = true` and `result.metadata["truncation_reason"] = <reason>`. Useful for caller retries with higher cap. |

**Token accounting** (separate concern from content normalization):
- `usage.input_tokens` → `Usage.input_tokens` (existing)
- `usage.output_tokens` → `Usage.output_tokens` (existing). Per OpenAI documentation for `/v1/responses`, `output_tokens` is the **inclusive total** (visible output tokens + invisible reasoning tokens). It does NOT need to be summed with `reasoning_tokens` — doing so would double-charge.
- `usage.output_tokens_details.reasoning_tokens` → `Usage.reasoning_tokens` (NEW field; defaults to 0 for `/chat/completions` callers and for non-pro `/v1/responses` callers)
- **Cost-ledger billing**: bill on `output_tokens` ONLY (already inclusive). `reasoning_tokens` is observability-only — surfaced in the ledger as a separate field for operator transparency but NOT added to `output_tokens` for billing math. Sprint 1 fixture validates this with a known-cost gpt-5.5-pro round-trip.
- **Edge case**: if a future OpenAI response returns `output_tokens` ≠ visible-tokens-counted-from-output[], we treat OpenAI's `usage.output_tokens` as authoritative (don't recount from text content). Adapter logs WARN if visible output count diverges by >5% — useful for spotting silent contract changes.

### Cheval `Usage` dataclass extension

`Usage` (in `.claude/adapters/loa_cheval/types.py`) adds optional field:
```python
reasoning_tokens: int = 0  # output tokens consumed by invisible reasoning (gpt-5.5-pro etc.)
```
Default 0 preserves back-compat for non-pro callers. Cost-ledger entries for pro-tier calls log this separately for operator transparency.

### Body transformation table

| Field | `/v1/chat/completions` | `/v1/responses` |
|-------|-----------------------|----------------|
| User content | `messages: [{role, content}]` | `input: <string OR list of typed message blocks>` (string for simple chat, list for tool-result threading) |
| Token cap | `max_completion_tokens` | `max_output_tokens` |
| Response | `choices[0].message.content` | `output[]` (see §3.1 above) |
| System prompt | First `messages[]` entry with `role: system` | `instructions` top-level field (string) |
| Tools | `tools: [...]` (existing format) | `tools: [...]` (same shape — no transformation) |

Architecture phase (`/architect`) writes the exact transformation function with concrete code.

### Integrations

| System | Integration Type | Purpose |
|--------|------------------|---------|
| OpenAI `/v1/responses` | HTTP POST | New routing target for gpt-5.5* |
| OpenAI `/v1/chat/completions` | HTTP POST (existing) | Continued use for gpt-5.3-codex etc. |
| Anthropic `/v1/messages` | HTTP POST (existing) | Haiku 4.5 callable via existing path |
| Google `/v1beta/models/{id}:generateContent` | HTTPS POST (existing) | Gemini 3 fast variant callable via existing path |
| `gen-adapter-maps.sh` | Local script | Regenerate `generated-model-maps.sh` from YAML SSOT |

### Dependencies

- `model-health-probe.sh` (existing, sprint-3A keystone) — must classify new entries as AVAILABLE before defaults flip
- `update-loa-bump-version.sh` (existing) — referenced as atomic-write precedent; not directly invoked
- Cheval Python codebase (in-tree at `.claude/adapters/loa_cheval/`) — primary code change locus

### Technical Constraints

- Cheval uses dataclass-based config (`types.py:ModelConfig`) — `params:` field added in #645 is reused for any new wire-protocol gates
- Bash + Python both consume the SSOT YAML — `generated-model-maps.sh` regeneration MUST run as part of Sprint 2 or bash callers will lag
- `tier_groups:` schema must be backwards-additive: existing configs without it still load fine

---

## Scope & Prioritization

### In Scope (MVP — Sprint 1 + Sprint 2)

- FR-1: OpenAI `/v1/responses` routing for gpt-5.5*
- FR-2: `reviewer`/`reasoning` alias flip
- FR-3: Haiku 4.5 + `tiny` tier
- FR-4: `fast-thinker` upgrade to Gemini 3 fast variant
- FR-6: Backward-compat preservation

### In Scope (Future Iteration — Sprint 3)

- FR-5: `prefer_pro_models` opt-in flag

### Explicitly Out of Scope

- **gpt-5.4 / 5.4-pro / 5.4-mini / 5.4-nano migration** — Reason: User scoped to gpt-5.5*; 5.4 family is a separate decision
- **Schema redesign for ledger array fragmentation** (`cycles`/`bugfix_cycles`/`bugfixes`) — Reason: Pre-existing tech debt; separate cleanup cycle
- **Five remaining Shell Tests pre-existing failure clusters** (release-notes, search-orchestrator, self-heal x2, DISCOVERY_TIMEOUT) — Reason: Out of scope per cycle-094 follow-ups; tracked separately
- **`@janitooor → @deep-name` rename auto-edits** in working tree — Reason: Unrelated doc-rename; one-off PR if desired
- **Adding `cached_input_per_mtok` schema field** for cost-ledger 10x-cached-input savings — Reason: Schema expansion; track as enhancement (pre-flight assumption #3)
- **Streaming SSE response handling for `/v1/responses`** — Reason: No current Loa workflow uses streaming; existing adapters are request-response. If future work needs streaming, response normalization spec (§3.1) is forward-additive — new shape rows can be added with golden fixtures. (Flatline iter-2 SKP-004 / IMP-001 — HIGH 770/905)
- **Multimodal input/output blocks** (image, audio attachments via `/v1/responses`) — Reason: Loa workflows are text-only today. Schema can be extended additively when needed.
- **Future OpenAI response object types not in §3.1's six shapes** — Reason: §3.1 covers the observed live-probed shapes. New shapes are added with golden fixture + adapter-test in subsequent PRs (forward-compatible by design — no breaking schema changes). **Adapter behavior on unknown shape**: raise `UnsupportedResponseShapeError` with the offending `output[].type` value in the error message — never silently mishandle. Operators see a clear failure mode rather than wrong-but-plausible output.

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1: Adapter routing | P0 | M | High — blocks everything |
| FR-2: Alias flip | P0 | S | High — primary user-facing change |
| FR-3: Haiku 4.5 + tiny tier | P0 | S | Medium — new capability |
| FR-4: Gemini 3 fast | P0 | S | Medium — quality uplift |
| FR-5: prefer_pro_models flag | P1 | M | Medium — opt-in convenience |
| FR-6: Backward compat | P0 | S | Critical — failure here breaks downstream consumers |

---

## Success Criteria

### Launch Criteria (per-sprint)

**Sprint 1 (FR-1):**
- [ ] All new pytests pass (gpt-5.5/5.5-pro routing + chat-completions regression guard)
- [ ] Adversarial cross-model review: 0 BLOCKING findings
- [ ] No regression in `test_providers.py` (full pytest run green)

**Sprint 2 (FR-2 + FR-3 + FR-4 + FR-6):**
- [ ] `model-invoke --validate-bindings` returns `valid: true`
- [ ] `flatline-model-validation.bats` 15/15 pass
- [ ] `test_validate_bindings_includes_new_agents` passes
- [ ] All 8 caller files updated; `generated-model-maps.sh` regenerated
- [ ] Backward-compat smoke against legacy `gpt-5.3-codex` config: alias resolves
- [ ] Manual 3-model Flatline (Opus + gpt-5.5 + Gemini 3) round-trip succeeds (operator-side)

**Sprint 3 (FR-5):**
- [ ] `prefer_pro_models: true` retargets at config-load (pytest)
- [ ] `prefer_pro_models: false` (default) preserves current behavior (pytest)
- [ ] User override precedence preserved (pytest)
- [ ] Documentation in `loa-setup` SKILL example

### Post-Launch Success (7 days post-merge)

- [ ] Zero rollback PRs filed
- [ ] No issues filed by downstream consumers about alias resolution
- [ ] Cost-ledger entries for gpt-5.5 calls denominated correctly (spot-check)

### Long-term Success (30 days post-merge)

- [ ] At least one downstream consumer has bumped submodule pin and reported clean upgrade
- [ ] No HTTP 400 errors logged from cheval OpenAI adapter on gpt-5.5* calls
- [ ] `prefer_pro_models` flag adoption tracked (if operationally measurable)

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| OpenAI `/v1/responses` contract changes mid-flight | Low | High | Pin pytests to dated snapshot `gpt-5.5-2026-04-23` for fixtures; rolling tag for runtime; alias-level kill-switch (`LOA_FORCE_LEGACY_ALIASES=1`) reverts alias resolution to pre-cycle-095 defaults in seconds without revert PR (NOT an endpoint-force — see FR-1 acceptance criterion) |
| gpt-5.5 quality regression vs 5.3-codex on some workloads | Low | Medium | `gpt-5.3-codex` preserved as immutable self-map — operators on a pin can keep using literal old model; CHANGELOG cost+capability comparison helps inform |
| Cost explosion from `prefer_pro_models` flip | Medium | High | Mandatory WARN at config-load; per-alias denylist; optional `max_cost_per_session_micro_usd` hard cap; dry-run mode shows remap impact before enabling |
| `reasoning_tokens` silent under-billing | Medium | Medium | New `Usage.reasoning_tokens` field; explicit normalization in §3.1; cost-ledger entries log reasoning_tokens separately; Sprint 1 fixture coverage |
| `/v1/responses` parser breaks on edge shape (refusal, empty, tool-use) | Medium | High | §3.1 Response Contract Matrix locks all six shapes in PRD; golden fixtures shipped Sprint 1; adapter normalizes losslessly to existing CompletionResult shape |
| Probe race during Sprint 2 alias flip — flip lands but probe shows UNAVAILABLE | Low | Medium | Sprint 1 confirms probe stability separately; Sprint 2 gates merge on freshly-passing probe; kill-switch as escape hatch |
| Gemini 3 fast variant `-preview` instability | Medium | Low | `fallback_chain: ["google:gemini-2.5-flash"]` declared on the registry entry; probe-driven automatic demotion; WARN log on demote |
| Three-array ledger schema fragmentation worsens | Low | Low | This cycle uses `/run sprint-plan` which writes to `bugfixes` cleanly; no new fragmentation introduced |
| `@deep-name` doc-rename uncommitted dirt re-emerges in working tree | Medium | Low | Selectively stage only this cycle's files (precedent in cycle-094-followups merge process) |
| Downstream consumer (`#642` reporter pattern) breaks on submodule update | Low | High | FR-6 hard constraint with backward-compat tests; immutable-self-map for `gpt-5.3-codex`; manual smoke against fixture project at legacy pin |
| Endpoint-family routing mis-configured (missing or wrong value in registry entry) | Low | High | `model-invoke --validate-bindings` REJECTS missing/unknown `endpoint_family` (validation FAIL, not silent default — Flatline iter-2 SKP-002). Sprint 1 migration step adds explicit `endpoint_family: chat` to all existing OpenAI registry entries BEFORE strict validation goes live (ordering: migrate → validate, NOT vice versa — Flatline iter-3 IMP-003). |

### Assumptions

- `[ASSUMPTION-1]` `prefer_pro_models` flag scope = ALL aliases with a `*-pro` variant declared in `tier_groups:`. Per-alias denylist available for opt-out. (RESOLVED post-Flatline.)
- `[ASSUMPTION-2]` Gemini fast-thinker target = `gemini-3-flash-preview` (architecture phase to validate vs `3.1-flash-lite-preview`). Both options carry `fallback_chain: ["google:gemini-2.5-flash"]` for probe-driven demotion.
- `[ASSUMPTION-3]` `cached_input_per_mtok` schema field is OUT of scope for this cycle. If wrong, schema work added to Sprint 2.
- `[ASSUMPTION-4]` New tier alias for Haiku 4.5 named `tiny` (architecture phase may rename).
- `[ASSUMPTION-5]` `endpoint_family: responses|chat` is sufficient as the registry routing-decision field. If a future provider needs a third family (e.g., a streaming-only variant), schema extends additively.

### Flatline Iteration Closeout (kaironic stop, 6 iters)

PRD passed through 6 Flatline iterations 2026-04-29. Stop signal per `feedback_kaironic_flatline_signals.md` memory: HIGH_CONSENSUS count plateaued ~5; BLOCKER count fluctuated 5-8; iter-6 SKP-001 argued opposite of iter-3/4 (finding rotation); REFRAMEs of same concerns. Real fixes integrated each round (kill-switch redesign, endpoint_family strict validation, reasoning_tokens billing semantics, pricing freeze policy). Residual iter-6 concerns are either **SDD-scope implementation details** (session-cap semantics, fallback request-time vs probe-time, hysteresis/cooldown) or **documented design tensions** (strict-fail on unknown shapes vs graceful fallback — current locks strict with `UnsupportedResponseShapeError`; rationale: better to fail loud than silently mishandle). Iteration outputs preserved at `grimoires/loa/a2a/flatline/prd-review-iter{1,2,3,4,5,6}.json`.

### Decisions Locked Post-Flatline (cycle-095 review, 2026-04-29)

- `gpt-5.3-codex` is an **immutable self-map**, NOT a retarget alias. Pinned configs continue to call literal old model. Resolution emits one-time INFO log suggesting migration. (Flatline cluster 1 / SKP-001 CRITICAL 910)
- `reasoning` alias defaults to `gpt-5.5` (NOT gpt-5.5-pro) — cost-safe default. Pro tier is opt-in via `prefer_pro_models` flag. (Flatline cluster 3 / SKP-002 HIGH 720)
- Routing driven by `endpoint_family` registry-metadata field, not name regex. (Flatline cluster 4 / SKP-003 HIGH 760)
- Operational kill-switch: **alias-level only** rollback via `LOA_FORCE_LEGACY_ALIASES=1` env var or `hounfour.experimental.force_legacy_aliases: true` config restores pre-cycle-095 alias resolution. Each restored alias routes per its own registry metadata (gpt-5.3-codex routes to /chat/completions, etc.). No endpoint-force layer exists in this design. (Flatline cluster 5 / IMP-002)
- Response normalization spec covers six shapes (multi-block text, tool-use, reasoning summary, refusal, empty, partial-truncated) with golden fixtures. (Flatline cluster 2 / SKP-001 CRITICAL 850, SKP-002 CRITICAL 885)
- `prefer_pro_models` flag includes denylist, dry-run mode, optional cost cap, and mandatory WARN log. (Flatline cluster 6 / IMP-006, SKP-005 HIGH 720)
- `-preview` Gemini models include automatic `fallback_chain` for probe-driven demotion. (Flatline cluster 7 / SKP-004 HIGH 735)

### Dependencies on External Factors

- OpenAI `/v1/responses` endpoint remains stable
- Anthropic `claude-haiku-4-5-20251001` snapshot remains live
- Google `/v1beta` keeps returning `gemini-3-flash-preview` (the model that was previously pruned per #574 due to NOT_FOUND)

---

## Timeline & Milestones

Each sprint includes implement → review → audit + adversarial-review-iter cycle. Buffer included for iteration. Sprint exit criteria: 0 BLOCKING findings on adversarial review + all pytests green + manual smoke on cycle-relevant workflow.

| Milestone | Target | Deliverables | Exit Criteria |
|-----------|--------|--------------|---------------|
| PRD approved | 2026-04-29 | This document, Flatline-iter-cleared | 0 BLOCKERs from /flatline-review |
| SDD complete | 2026-04-30 | `grimoires/loa/sdd.md` covering routing fix, tier_groups schema, fallback chain, response normalization details | 0 BLOCKERs from /flatline-review on SDD |
| Sprint plan ready | 2026-04-30 | `grimoires/loa/sprint.md` with task-level breakdown | 0 BLOCKERs from /flatline-review on sprint plan |
| Sprint 1 merged | 2026-05-01 | OpenAI routing via `endpoint_family`, response normalization (§3.1), kill-switch, registry migration step (existing entries get explicit `endpoint_family: chat`), pytests + golden fixtures, 0 defaults flipped | All Sprint 1 ACs met; live + fixture round-trip tests pass; adversarial review on PR clear |
| Sprint 2 merged | 2026-05-02 | Alias flips (reviewer/reasoning → gpt-5.5), Haiku 4.5 + tiny tier, Gemini 3 fast w/ fallback chain, FR-5a cost guardrails (denylist + cap + dry-run), generated maps regenerated, 8 caller files updated, immutable-self-map for gpt-5.3-codex | model-invoke --validate-bindings green; flatline-model-validation 15/15; backward-compat smoke against legacy pin clean; manual 3-model Flatline smoke succeeds |
| Soak period | 2026-05-02 → 2026-05-04 | 48-hour observation window after Sprint 2 — monitor for downstream consumer issues, cost-ledger anomalies, probe state changes | No rollbacks filed; cost-ledger spot-check OK |
| Sprint 3 merged | 2026-05-05 | `prefer_pro_models` flag (builds on Sprint 2 guardrails) | Flag default-off preserves behavior; flag-on retargets correctly with override precedence; WARN log emitted; pytests cover all four guardrail interactions |
| Cycle release tag | 2026-05-05 | v1.108.0 minor release with consolidated CHANGELOG including cost-comparison table | Release notes drafted; downstream consumer migration path documented |

**Schedule risk acknowledgment** (Flatline iter-2 SKP-008): The original 2026-04-29 → 2026-05-02 schedule was compressed. Revised above adds soak period and pushes Sprint 3 to 2026-05-05. Each sprint's PR is independently mergeable — schedule slip on later sprints does not block earlier ones from shipping.

### Rollback Playbook

If incident occurs post-merge, in order of escalating intervention:

1. **Symptom-only investigation** (no code change): Check `grimoires/loa/a2a/trajectory/probe-*.jsonl` for state changes; check cost-ledger entries for anomalies; spot-check `model-invoke --validate-bindings` output.
2. **Alias-level rollback** (no PR): Set `LOA_FORCE_LEGACY_ALIASES=1` env var (or `hounfour.experimental.force_legacy_aliases: true` in user config). Aliases revert to pre-cycle-095 targets. Effect is immediate at next config-load. Verification: `model-invoke --validate-bindings` shows `reviewer → openai:gpt-5.3-codex`.
3. **Per-alias pin** (no PR): User pins specific alias in `.loa.config.yaml` (e.g., `aliases: { reviewer: openai:gpt-5.3-codex }`). Wins over framework defaults via existing precedence. Useful for partial rollback.
4. **Provider-level disable** (no PR): If gpt-5.5* itself is broken, set `tier_groups.denylist: [reviewer, reasoning]` (FR-5a) — keeps everyone on non-pro and routes through any base-tier override.
5. **Revert PR** (last resort): Standard git revert of the merged sprint PR. Requires CI re-run + redeploy.

Each step verifiable in <60s. Steps 1-4 require no merge. Step 5 is the conventional bailout.

---

## Appendix

### A. Pre-flight Intel

Captured at `grimoires/loa/context/model-currency-cycle-preflight.md` — live-probed provider state, exact pricing, routing requirements, scope decisions. Reference document for `/architect` and sprint-planning phases.

### B. Related Memory Notes

- `project_gpt55_migration.md` — original migration plan (predates pre-flight; superseded by this PRD)
- `project_session_20260428_outcomes.md` — context for cycle-094-followups merges that landed yesterday
- `feedback_bridgebuilder_codex_routing.md` — PR #586 codex routing precedent
- `feedback_merge_orchestration.md` — multi-PR ledger merge patterns (relevant to Sprint 2 commit ordering)

### C. Bibliography

**Internal Resources:**
- Pre-flight intel: `grimoires/loa/context/model-currency-cycle-preflight.md`
- Codex routing precedent: PR #586 (cycle-088), commit 84e6472
- Cycle-093 sprint-4 SSOT generator (introduced `generated-model-maps.sh` as derived artifact): T4.2

**External Resources:**
- OpenAI Models API: `https://api.openai.com/v1/models`
- OpenAI Pricing: `https://developers.openai.com/api/docs/pricing`
- Anthropic Messages API: `https://api.anthropic.com/v1/messages`
- Google Gemini API: `https://generativelanguage.googleapis.com/v1beta/models`

### D. Glossary

| Term | Definition |
|------|------------|
| Cheval | Loa's multi-model provider abstraction layer. Vendored in-tree at `.claude/adapters/loa_cheval/`. |
| SSOT | Single source of truth — `.claude/defaults/model-config.yaml` for the model registry. |
| Probe | Health-check call to a provider's `/v1/models` (or equivalent) classifying each registered model as AVAILABLE / UNAVAILABLE / UNKNOWN. Implemented in `.claude/scripts/model-health-probe.sh`. |
| Tier alias | An alias name that conventionally maps to a quality/capability tier (e.g., `reviewer` for default-tier review, `reasoning` for deep-reasoning, `cheap` for budget). |
| `*-pro` variant | A tier-suffixed model providing higher capability at higher cost (e.g., `gpt-5.5-pro` vs `gpt-5.5`). |
| `tier_groups` | New schema block (Sprint 3) mapping base aliases to their pro variants for the `prefer_pro_models` opt-in flag. |
| Backward-compat alias | Entry in `backward_compat_aliases:` that retargets a legacy model ID to a current canonical one (e.g., `claude-opus-4.5 → claude-opus-4-7`). |

---

*Generated by `/plan-and-analyze` 2026-04-29.*
*Pre-flight intel: `grimoires/loa/context/model-currency-cycle-preflight.md`.*
*Next phase: `/architect` to produce SDD covering routing-fix design and `tier_groups:` schema.*
