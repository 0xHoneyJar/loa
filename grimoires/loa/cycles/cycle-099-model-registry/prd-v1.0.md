# Product Requirements Document: Model Registry Consolidation + Per-Skill Granularity

**Version:** 1.0 (initial draft; awaiting Flatline pass + operator approval)
**Date:** 2026-05-04
**Author:** PRD Architect (deep-name + Claude Opus 4.7 1M)
**Status:** Draft — interview complete, 4 locked decisions, ready for `/architect` after operator review.
**Cycle (proposed):** `cycle-099-model-registry` *(actual ID assigned by ledger when `/sprint-plan` runs)*

**Source issue:**
- [#710](https://github.com/0xHoneyJar/loa/issues/710) — Refactor: consolidate model registries to single source of truth + add config extension mechanism

**Operator-approved scope decisions** (interview, 2026-05-04):

| Decision | Locked value |
|----------|--------------|
| Cycle scope | Narrow — `#710` only (no cycle-098 follow-ups) |
| Migration ordering | Phased — Sprint 1 SoT → Sprint 2 extension+granularity → Sprint 3 BB-TS codegen → Sprint 4 (optional) sunset |
| Per-skill granularity shape | Tier-tag per skill (composes with cycle-095 `tier_groups`) |
| Bridgebuilder TS migration | Build-time codegen (`gen-bb-registry.ts`) |

**Replaces**: cycle-098 PRD (now archived at `grimoires/loa/cycles/cycle-098-agent-network/prd.md`).

**Predecessor cycle**: `cycle-095-model-currency` shipped the YAML registry as SoT for the hounfour/cheval (Python) path. This PRD finishes that consolidation by extending SoT coverage to the remaining consumers (Bridgebuilder TS, Red Team adapter, model-permissions, personas, docs) and adding the operator-facing extension mechanism + per-skill granularity layer that #710 + the operator's follow-up comment ask for.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

---

## Executive Summary

Loa's model selection logic is fragmented across **5+ independent registries** that drift independently and require coordinated multi-file edits to keep in sync. Cycle-095 began consolidating this by promoting `.claude/defaults/model-config.yaml` to be the source of truth for the hounfour/cheval (Python) execution path. Cycle-099 finishes the job: extends SoT coverage to all remaining consumers (Bridgebuilder TypeScript, Red Team bash adapter, `model-permissions.yaml`, persona docs, protocol docs), adds an operator-facing config extension mechanism (`model_aliases_extra`), introduces per-skill tier-tag granularity composing with cycle-095's `tier_groups`, and sunsets the legacy bash adapter.

Operator outcome: "edit one YAML field in `.loa.config.yaml`, get the latest model in your skill of choice." No System Zone edits, no Loa release wait, no multi-file PR.

**Estimated cycle**: 4 sprints (~4-5 weeks), modest scope per sprint, full quality-gate chain per cycle-098 pattern.

---

## Problem Statement

### Current state (citation-grounded)

> From #710 issue body: "Model selection across the Loa framework is hardcoded in **at least five separate registries** — a legacy bash adapter, a 'hounfour' generated map, two skill-internal TypeScript registries, and a Red Team-specific bash adapter."

Concrete inventory verified against current codebase:

| # | Location | Role | SoT-derived today? |
|---|----------|------|---------------------|
| 1 | `.claude/scripts/model-adapter.sh.legacy` | Default Flatline + dissent gates (when `hounfour.flatline_routing: false`, the **default**) | ❌ Independent 4-array bash dict |
| 2 | `.claude/scripts/generated-model-maps.sh` | hounfour/cheval path (when `flatline_routing: true`) | ✅ Generated from YAML SoT (cycle-095) |
| 3 | `.claude/defaults/model-config.yaml` | YAML SoT for the generator above | n/a — source |
| 4 | `.claude/scripts/red-team-model-adapter.sh` | `/red-team` skill | ❌ Independent bash dict |
| 5 | `.claude/scripts/red-team-code-vs-design.sh` | Red Team gate | ❌ Hardcoded `--model opus` flag |
| 6 | `.claude/skills/bridgebuilder-review/resources/config.ts` | Bridgebuilder default | ❌ Hardcoded `claude-opus-4-7` |
| 7 | `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | Bridgebuilder context budgets | ❌ Hardcoded map; only 3 entries (2 already stale: `4-6`, `gpt-5.2`) |
| 8 | `.claude/skills/bridgebuilder-review/resources/adapters/openai.ts` | Bridgebuilder OpenAI endpoint routing | ❌ String-match `"codex"` — heuristic, not derived |
| 9 | `.claude/skills/bridgebuilder-review/resources/personas/*.md` | Bridgebuilder persona-aware model selection | ❌ Per-persona model name in markdown |
| 10 | `.claude/data/model-permissions.yaml` | Permission system | ❌ Independent model-name listing |
| 11 | `.claude/data/personas/alternative-model.md` | Panel persona docs | ❌ Per-persona model refs |
| 12 | `.claude/protocols/flatline-protocol.md` | Documentation | ❌ Hardcoded model names in examples |
| 13 | `.claude/protocols/gpt-review-integration.md` | Documentation | ❌ Hardcodes `gpt-5.3-codex` |

> From [CODE:`grimoires/loa/reality/decisions.md:86-87`]: "Modifications to `.claude/scripts/model-adapter.sh` MUST update all 4 associative arrays (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`) **atomically**; backward compat aliases must exist in ALL four maps"

This codified constraint is precisely the friction #710 names. The constraint exists because the adapter is hand-maintained, not derived.

### Two parallel runtime systems, gated by feature flag

> From #710 issue body: "There are effectively **two model-resolution systems** in Loa:
> 1. **Legacy (default)** — `model-adapter.sh.legacy` with the small dict. Used when `hounfour.flatline_routing` is unset/false.
> 2. **Hounfour (newer)** — `model-invoke` → `cheval.py` reading `generated-model-maps.sh`. Used when `hounfour.flatline_routing: true`."

The legacy registry is significantly behind the hounfour one. Operators on the default path can't use models that exist in `generated-model-maps.sh` (e.g., `gpt-5.5`, `gpt-5.5-pro`, `gemini-3.1-pro-preview`, `claude-haiku-4-5`) without flipping a flag whose discoverability is poor.

### Operator-facing problem (cited from #710 comment)

> "as an operator i want to trivially be able to choose which models will be used for either:
> - ALL (e.g. flatline, red team, bridgebuilder etc)
> - or in a more granular way (e.g. flatline use all the most powerful models, for red team cheaper, for bridge buidler max for opus and codex but cheaper for gemini)
>
> all of this should be possible from a single location e.g. the loa config and trivial for anyone to get their claude to help set up"

Today's `.loa.config.yaml` exposes per-skill model selection, but the **shape is inconsistent across skills** (verified against current `.loa.config.yaml`):
- `flatline_protocol.models.{primary,secondary,tertiary}` (3-position)
- `bridgebuilder.multi_model.models[]` (array of `{provider, model_id, role}` objects)
- `gpt_review.models.{primary,secondary}` (2-position)
- `adversarial_review.model` (single string)
- `spiral.executor_model` / `spiral.advisor_model` (cycle-072 advisor pattern)

Each skill invented its own schema. There's no operator-facing "tier" abstraction that unifies them.

### Brownfield codebase grounding

> Codebase grounding via `/ride --enriched` (2026-05-04) confirmed:
> - GAP-003-4d6f [P1]: README.md:32 says "GPT-5.3-codex"; README.md:191 says "GPT-5.2"; `.loa.config.yaml.example` says "GPT-5.3-codex" — confirming live drift across docs.
> - [CODE:`grimoires/loa/reality/structure.md:11`]: cheval Python adapter at `.claude/adapters/` is the multi-provider runtime substrate.
> - [CODE:`grimoires/loa/reality/terminology.md:108`]: Flatline canonically defined as "Multi-model adversarial review (Opus + GPT)" — confirms multi-model isn't optional, it's structural.

> Sources: #710 issue body + comment, [CODE:`reality/decisions.md:86-87`], [CODE:`reality/terminology.md:108`], [CODE:`.claude/defaults/model-config.yaml:1-460`], [CODE:`.loa.config.yaml`], `gaps.md:GAP-003-4d6f`, Phase 0 synthesis (interview, 2026-05-04).

---

## Goals & Success Metrics

### Goals

| ID | Goal |
|----|------|
| **G-1** | Single edit point for model registration: framework defaults via one `model-config.yaml` entry; operator extensions via one `.loa.config.yaml::model_aliases_extra` entry. No System Zone edits required for operators. |
| **G-2** | Per-skill tier-tag granularity expressible from one config block, composing with cycle-095's `tier_groups` schema. Operators say "flatline use max, red team use cheap" in plain YAML. |
| **G-3** | Zero drift between registries — CI gate fails when generated artifacts diverge from SoT. |
| **G-4** | Bridgebuilder model defaults derive from SoT via build-time codegen (operators don't need to rebuild TS for new models — framework releases ship updated `dist/`). |
| **G-5** | Legacy adapter sunset path exists with operator opt-in fallback during deprecation window. |

### Success metrics (SMART)

| Metric | Baseline (today) | Target | Measurement |
|--------|------------------|--------|-------------|
| Time to add a new framework-default model | 5+ files, 4-array atomic edits, Loa release cycle | 1 line in `model-config.yaml` + `gen-adapter-maps.sh` + `gen-bb-registry.ts` regen, single PR | Stopwatch + git-diff scope on a probe-confirmed model addition during Sprint 2 |
| Time for operator to add a model not yet in framework | Impossible without forking / System Zone edit | <5 min: 1 entry in `.loa.config.yaml::model_aliases_extra` | E2E test: fresh-clone operator adds hypothetical `gpt-5.7-pro` via config alone; resolves at runtime |
| Drift between registries | Visible (truncation.ts has 2 stale entries vs SoT) | 0 (CI gate enforces) | CI check exits non-zero on divergence; PR cannot merge |
| Per-skill tier expressivity | Inconsistent shape across 5+ skills | One `skill_models` block, ≤10 lines for "flatline max + red team cheap + bridgebuilder mixed" | Operator config audit: count YAML lines for the example above |
| Bridgebuilder default upgrade | Manual TS edit + rebuild + Loa release | Auto-regenerated by `bun run build` reading SoT YAML | Sprint 3 acceptance: adding a model to YAML + rebuilding regenerates `dist/truncation.js` and `dist/config.js` |

> Sources: #710 acceptance criteria, operator interview confirmation (2026-05-04), cycle-098 sprint pattern (test-first quality-gate chain).

---

## User Personas & Use Cases

### Personas

| ID | Persona | Goal |
|----|---------|------|
| **P1 (Primary)** | **Operator** running Loa in their own repo | Use newer/different models without forking the framework or editing System Zone code |
| **P2 (Secondary)** | **Framework maintainer** (deep-name + Loa contributors) | One-step model-config.yaml updates that propagate to all consumers; CI catches drift |
| **P3 (Tertiary)** | **Agent runtime** (cheval, bash adapters, BB skill) | Deterministic model resolution from operator config + framework defaults; clear failure modes |

### Use cases

**UC-1 — Operator adopts a newly-released GPT model the day it ships**
> Provider releases `gpt-5.7-pro` on Tuesday. Operator wants to use it for Flatline by Wednesday morning. Adds 3 lines to `.loa.config.yaml::model_aliases_extra` (provider, api_id, capabilities) + 1 line to `skill_models.flatline_protocol.primary: max` (or directly references the new model). Restarts agent. Done. No PR upstream.

**UC-2 — Operator wants per-skill cost/quality tradeoff**
> Operator wants Flatline maxed out (paying for top-tier review) but Red Team cheap (it's an unguided exploration, doesn't need top-tier reasoning). Adds:
> ```yaml
> skill_models:
>   flatline_protocol: { primary: max, secondary: max, tertiary: max }
>   red_team: { primary: cheap }
> ```
> Done. Tier resolution happens at runtime startup.

**UC-3 — Framework maintainer ships Loa release with new tier-of-Anthropic model**
> Anthropic releases Opus 4.8. Maintainer adds 1 entry to `model-config.yaml` (provider, capabilities, pricing), updates `aliases.opus: anthropic:claude-opus-4-8`, runs `gen-adapter-maps.sh` + `gen-bb-registry.ts`, commits source + generated artifacts in a single PR. CI verifies drift = 0. Ships.

**UC-4 — Operator pins a legacy model for backward compatibility**
> Operator's pipeline depends on `gpt-5.3-codex` exact behavior. Operator adds explicit `skill_models.bridgebuilder.gpt_role: gpt-5.3-codex` (bypassing the `max` tier). Backward compat aliases in cycle-095 ensure literal model IDs continue resolving.

**UC-5 — Framework maintainer sunsets the legacy adapter**
> Sprint 4 gate decision (operator at gate). If chosen: flip default to `hounfour.flatline_routing: true`, mark `model-adapter.sh.legacy` deprecated with operator-visible warning, schedule full removal for follow-up cycle. If not chosen: continue deprecation indefinitely with warnings active.

> Sources: #710 issue body + comment, Phase 4 functional-requirement decomposition, operator interview confirmation (2026-05-04).

---

## Functional Requirements

### FR-1 — Single Source of Truth Extension (P0)

`.claude/defaults/model-config.yaml` becomes the registry for all consumers. Cycle-095 covered the hounfour/cheval path; cycle-099 covers the rest.

| AC | Acceptance criterion |
|----|----------------------|
| **FR-1.1** | Bridgebuilder TypeScript registries (`config.ts` default model, `core/truncation.ts` truncation map, `adapters/openai.ts` endpoint routing) are generated at build time from `model-config.yaml` via a new `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` script. The generated TS files are committed alongside source (mirrors `generated-model-maps.sh` pattern). `bun run build` invokes the generator. |
| **FR-1.2** | Red Team bash adapter (`red-team-model-adapter.sh`) reads from `generated-model-maps.sh` (sourced in shell) — eliminating the independent associative array. |
| **FR-1.3** | `red-team-code-vs-design.sh` resolves `--model opus` via the SoT's alias chain (no hardcoded `opus` literal — uses the `opus` alias defined in YAML). |
| **FR-1.4** | `.claude/data/model-permissions.yaml` is either (a) derived from `model-config.yaml` via codegen, or (b) merged into `model-config.yaml` as a `permissions` field per model. **Operator decision deferred to `/architect`.** v1.0 PRD recommendation: merge into `model-config.yaml` since permissions are a per-model attribute. |
| **FR-1.5** | Persona docs (both `.claude/data/personas/*.md` and `.claude/skills/bridgebuilder-review/resources/personas/*.md`) replace hardcoded model names with tier-tag references (e.g., `# tier: max` instead of `# model: claude-opus-4-7`). Backward compat: parsers accept both forms; tier-tag wins if present. |
| **FR-1.6** | Protocol docs (`.claude/protocols/flatline-protocol.md`, `gpt-review-integration.md`) replace hardcoded model names with operator-config references ("configure your top-of-provider in `.loa.config.yaml`"). Examples reference tier names (`max`, `cheap`), not specific model IDs. |
| **FR-1.7** | `.claude/scripts/model-adapter.sh` (the *non*-`.legacy` shipped variant) sources `generated-model-maps.sh` at init, eliminating its own dictionary. (Note: cycle-095's `vision-011 activation` bug-fix already converted this script to runtime-swap to `generated-model-maps.sh` at runtime — verify against current state in Sprint 1.) |
| **FR-1.8** | After all migrations land, the only hand-maintained model registry in the codebase is `.claude/defaults/model-config.yaml`. |

### FR-2 — Config Extension Mechanism (P0)

Operators register new models without System Zone edits. Mirrors the existing `protected_classes_extra` pattern from cycle-098 Sprint 1B.

| AC | Acceptance criterion |
|----|----------------------|
| **FR-2.1** | New `.loa.config.yaml` field `model_aliases_extra` (top-level or nested under `models:`, decision in `/architect`) accepts an array of model definitions matching the YAML schema for `providers.<provider>.models.<id>` entries. |
| **FR-2.2** | Schema validation at config load time. Reject: malformed entries, missing required fields, duplicate model IDs (collide with framework defaults). Structured error with offending line + remediation hint. |
| **FR-2.3** | Merge order: framework defaults (`model-config.yaml`) ∪ operator extras (`model_aliases_extra`). On duplicate ID: error (do not silently override; operator must rename or explicitly opt into override via a separate `model_aliases_override` field — decision in `/architect`). |
| **FR-2.4** | Backward-compat aliases from cycle-095 (legacy model IDs, e.g., `claude-opus-4.x` → `claude-opus-4-7`) preserved without operator action. |
| **FR-2.5** | Hot-reload **NOT** required for v1 (YAGNI). Config loaded at runtime startup; restart-to-apply is acceptable. |
| **FR-2.6** | Operators can extend BOTH `models` and `aliases` — i.e., they can define a new model AND give it a friendly tier-tag in one config block. |
| **FR-2.7** | `.loa.config.yaml.example` documents the `model_aliases_extra` field with a worked example. |

### FR-3 — Per-Skill Tier-Tag Granularity (P0)

Operators express which tier each skill should use via a single config block. Composes with cycle-095's `tier_groups` schema (mappings empty as of cycle-095 Sprint 2).

| AC | Acceptance criterion |
|----|----------------------|
| **FR-3.1** | New `.loa.config.yaml` field `skill_models` (top-level or under `agents:`, decision in `/architect`). Schema: `{<skill_name>: {<role>: <tier_or_model_ref>}}`. Example: `skill_models: { flatline_protocol: {primary: max, secondary: max, tertiary: max}, red_team: {primary: cheap}, bridgebuilder: {opus_role: max, gpt_role: max, gemini_role: cheap}, adversarial_review: {primary: max} }` |
| **FR-3.2** | Tier-tag → concrete model resolution via `tier_groups.mappings` (cycle-095 Sprint 2 schema). Cycle-099 Sprint 2 populates default mappings: `max` → top-of-provider per provider; `cheap` → budget-tier per provider; `mid` → middle-tier. Operator can override `tier_groups.mappings` in `.loa.config.yaml`. |
| **FR-3.3** | Per-role tier (when a skill has multiple roles, e.g., bridgebuilder's opus/gpt/gemini reviewer roles). Each role independently tier-taggable. |
| **FR-3.4** | Composes with cycle-095's `prefer_pro_models` flag — `prefer_pro_models: true` retargets the `max` tier to the pro variant per provider (e.g., `gpt-5.5` → `gpt-5.5-pro`). |
| **FR-3.5** | Each skill ships with sensible default tier mapping in `model-config.yaml::agents.<skill_name>` so that no operator config is required for default behavior. The `skill_models` block is purely override. |
| **FR-3.6** | Mixed mode supported: an operator can specify a tier-tag for some roles AND an explicit model ID for others (e.g., `bridgebuilder.opus_role: max, bridgebuilder.gpt_role: gpt-5.3-codex`). Resolution: tier-tags resolve via `tier_groups`; explicit IDs resolve directly via `aliases` + `models`. |
| **FR-3.7** | Migration of existing config shapes: `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model` continue to work via deprecation aliases (one cycle's deprecation window). New `skill_models` is the canonical shape going forward. |

### FR-4 — Sunset Legacy Adapter (P1, gated)

| AC | Acceptance criterion |
|----|----------------------|
| **FR-4.1** | `.claude/scripts/model-adapter.sh.legacy` marked `DEPRECATED` in file header with sunset target cycle. |
| **FR-4.2** | Default flip: `hounfour.flatline_routing: true` becomes the framework default in `.claude/defaults/loa.defaults.yaml` (currently `false`). Operators with custom config get migration warning at startup. |
| **FR-4.3** | One-cycle deprecation window: when an operator runs the legacy path (explicitly opts in OR has stale config), agent emits operator-visible `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning at every Flatline invocation. |
| **FR-4.4** | **Sprint 4 gate decision** (operator at gate review): full removal in cycle-099 OR continued deprecation through cycle-100. Decision logged in `grimoires/loa/cycles/cycle-099-model-registry/decisions/`. |
| **FR-4.5** | Backward compat for operators currently pinning legacy via env var or feature flag preserved. Removal documented in release notes. |
| **FR-4.6** | If full removal chosen: `model-adapter.sh.legacy` deleted; `hounfour.flatline_routing` feature flag removed from `loa.defaults.yaml` and `.loa.config.yaml.example`; migration runbook published at `grimoires/loa/runbooks/legacy-adapter-removal.md`. |

### FR-5 — Drift Detection (cross-cutting, P0)

| AC | Acceptance criterion |
|----|----------------------|
| **FR-5.1** | New CI workflow `.github/workflows/model-registry-drift.yml` runs on every PR. Compares: (a) `generated-model-maps.sh` against `model-config.yaml` (regenerate + diff); (b) Bridgebuilder generated TS (`dist/truncation.js`, `dist/config.js`) against source YAML (regenerate + diff); (c) `model-permissions.yaml` against `model-config.yaml` (per FR-1.4 decision). |
| **FR-5.2** | Failure mode: CI exits non-zero with structured diff output. PR cannot merge until generated artifacts match SoT. |
| **FR-5.3** | Documentation drift: `grep`-based check for hardcoded model names in `.claude/protocols/*.md`. Warning (not block) on hit; PR description must acknowledge. |
| **FR-5.4** | Lockfile approach: `model-config.yaml.checksum` committed alongside source. CI verifies generated artifacts' hash matches the lockfile. |

> Sources: #710 acceptance criteria, operator interview confirmation (2026-05-04), cycle-095 SoT pattern from `model-config.yaml`, cycle-098 `protected_classes_extra` pattern reference.

---

## Non-Functional Requirements

### NFR-Performance

| ID | Requirement |
|----|-------------|
| **NFR-Perf-1** | Model resolution overhead at runtime startup: <50ms p95 (target: indistinguishable from cycle-095 baseline; YAML already parsed for hounfour). |
| **NFR-Perf-2** | Build-time codegen for Bridgebuilder TS adds <10s to CI build time. |
| **NFR-Perf-3** | CI drift gate adds <30s to PR check time. |

### NFR-Security

| ID | Requirement |
|----|-------------|
| **NFR-Sec-1** | `model_aliases_extra` schema validated at load time. Rejects: shell metacharacters in `api_id`, malformed URLs in `endpoint`, unknown provider types. |
| **NFR-Sec-2** | Same trust model as `protected_classes_extra` (cycle-098 Sprint 1B): operator zone, not System Zone. Validation happens before any HTTP call. |
| **NFR-Sec-3** | No new secrets surface introduced — model resolution doesn't handle API keys (those remain in environment variables per cycle-095). |
| **NFR-Sec-4** | If `model_aliases_extra` adds a new provider type (not in framework defaults), reject with structured error directing to upstream PR (provider plugin contract is System Zone, not operator-extensible in v1). |

### NFR-Compatibility

| ID | Requirement |
|----|-------------|
| **NFR-Compat-1** | All `backward_compat_aliases` from cycle-095 (`claude-opus-4.x` → `4-7`, `gpt-5.2-codex` → `gpt-5.3-codex`, etc.) preserved without operator action. |
| **NFR-Compat-2** | Downstream loa-as-submodule projects (e.g., #642 reporter pattern) unaffected: `git submodule update --remote` produces no breaking changes to user config format. |
| **NFR-Compat-3** | Existing operator `.loa.config.yaml` files continue working unchanged through cycle-099. Deprecation warnings for legacy shapes (`flatline_protocol.models.{primary,...}`) but no breaking changes within the cycle. |
| **NFR-Compat-4** | Bridgebuilder existing `dist/` consumers (operators who depend on the compiled artifacts) get a regenerated `dist/` in cycle-099 that matches the new SoT-derived defaults. No breaking API changes to the skill's external interface. |

### NFR-Operability

| ID | Requirement |
|----|-------------|
| **NFR-Op-1** | Drift detection CI runs in GitHub Actions with clear error messages — operator sees exactly which file diverged and which line. |
| **NFR-Op-2** | All failure modes fail-closed (operator-visible) not fail-silent. Specifically: invalid `model_aliases_extra` → refuse to load + structured error; legacy adapter active → visible warning; codegen failure → CI fails. |
| **NFR-Op-3** | Sprint 4 sunset (if approved) ships with migration runbook + rollback path. Rollback = restore `hounfour.flatline_routing: false` default + un-deprecate the legacy adapter. |
| **NFR-Op-4** | All sprints ship with operator-facing release notes (cycle-098 `release-notes-sprint*.md` pattern). |

> Sources: cycle-098 NFR pattern (PRD v1.3), `protected_classes_extra` security model from cycle-098 Sprint 1B, cycle-095 backward_compat preservation from `model-config.yaml:282-313`.

---

## User Experience

### Operator path: "I want to use a newer model"

1. Open `.loa.config.yaml`
2. Add (if model not yet in framework):
    ```yaml
    model_aliases_extra:
      - id: gpt-5.7-pro
        provider: openai
        api_id: gpt-5.7-pro
        endpoint_family: responses
        capabilities: [chat, tools, function_calling, code]
        context_window: 256000
        pricing:
          input_per_mtok: 40000000   # $40/Mtok
          output_per_mtok: 200000000 # $200/Mtok
    ```
3. Add (per-skill granularity):
    ```yaml
    skill_models:
      flatline_protocol:
        primary: max     # resolves via tier_groups.mappings to gpt-5.7-pro if mapped, else falls back
    ```
4. Optionally override the `max` tier mapping:
    ```yaml
    tier_groups:
      mappings:
        max:
          openai: gpt-5.7-pro
    ```
5. Restart Loa
6. Verify: `model-invoke --validate-bindings` confirms `flatline_protocol.primary` resolves to `openai:gpt-5.7-pro`

### Framework maintainer path: "Anthropic shipped Opus 4.8"

1. Edit `.claude/defaults/model-config.yaml`:
    ```yaml
    providers:
      anthropic:
        models:
          claude-opus-4-8:
            capabilities: [chat, tools, function_calling, thinking_traces]
            context_window: 200000
            token_param: max_tokens
            params: { temperature_supported: false }
            pricing:
              input_per_mtok: 5000000
              output_per_mtok: 25000000
    aliases:
      opus: anthropic:claude-opus-4-8   # retarget alias
    backward_compat_aliases:
      claude-opus-4.7: anthropic:claude-opus-4-8   # add legacy pin
    ```
2. Run `bash .claude/scripts/gen-adapter-maps.sh` — regenerates `generated-model-maps.sh`
3. Run `bun run build` from `.claude/skills/bridgebuilder-review/` — regenerates `dist/`
4. Commit source + generated artifacts + lockfile in single PR
5. CI verifies drift = 0
6. Ship

> Sources: #710 acceptance criteria, operator interview confirmation (2026-05-04), `model-config.yaml:251-281` aliases pattern.

---

## Technical Considerations

### TypeScript codegen for Bridgebuilder (FR-1.1)

Bun script reads `model-config.yaml` at build time, emits TS literal map for `truncation.ts` defaults and `config.ts` default-model. The skill ships with a pre-compiled `dist/` per current pattern; cycle-099 adds the codegen step before compilation.

```typescript
// .claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts
import { parse } from 'yaml';
import { readFileSync, writeFileSync } from 'fs';

const config = parse(readFileSync('.claude/defaults/model-config.yaml', 'utf8'));
const truncationMap = computeTruncationMap(config);
const defaultModel = config.aliases.opus;  // resolves alias chain

writeFileSync('resources/core/truncation.generated.ts', renderTruncation(truncationMap));
writeFileSync('resources/config.generated.ts', renderConfig(defaultModel));
```

`bun run build` invokes `gen-bb-registry.ts` before `tsc`. CI verifies `dist/*.js` matches a fresh build (drift gate).

### Red Team adapter migration (FR-1.2)

`red-team-model-adapter.sh` currently maintains its own associative array. Migration: source `generated-model-maps.sh` at init, drop the local arrays. The `red-team-code-vs-design.sh`'s `--model opus` literal becomes `--model "$(resolve_alias opus)"` which resolves to the alias-mapped model.

### model-permissions.yaml strategy (FR-1.4)

Two options for `/architect` to decide:

**Option A — Codegen from SoT**: `model-permissions.yaml` becomes a generated artifact. New script `gen-model-permissions.sh` reads each model's permissions from `model-config.yaml::providers.<p>.models.<id>.permissions` and writes `model-permissions.yaml`. Drift gate enforces match.

**Option B — Merge into SoT**: permissions become a per-model field in `model-config.yaml` directly. `model-permissions.yaml` becomes a thin compatibility wrapper that lists `<model_id>: <permissions_block>`. Eventually deleted in cycle-100.

PRD recommendation: **Option B** — permissions are a per-model attribute and merging them into the SoT eliminates an entire registry. Operator decision at `/architect`.

### Persona docs migration (FR-1.5)

Markdown frontmatter currently uses `# model: <id>`. New convention: `# tier: <tier>` resolves at runtime via the same tier-resolution path skills use. Backward compat: parsers accept both forms; `# tier:` wins if present.

### Operator-config schema expansion impact

Adding `model_aliases_extra` and `skill_models` to `.loa.config.yaml` schema. Loader rejects unknown top-level fields today (per cycle-095 SDD §1.4.5 strict-mode), so loader code MUST be updated to accept the new fields. Schema validation happens at load — invalid entries reject the entire load (fail-closed).

### Backward-compat for legacy skill_models shapes

Existing `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model` continue working. Loader reads both shapes; `skill_models` block (if present) wins. Deprecation warning emitted on legacy-shape detection.

> Sources: cycle-095 `model-config.yaml`, cycle-095 SDD §1.4.5 strict-mode loader, Bridgebuilder skill structure observed in `/ride` reality.

---

## Scope & Prioritization

### In scope (cycle-099)

| Priority | Item |
|----------|------|
| P0 | FR-1 Single Source of Truth Extension (Sprints 1, 2, 3) |
| P0 | FR-2 Config Extension Mechanism (`model_aliases_extra`) (Sprint 2) |
| P0 | FR-3 Per-Skill Tier-Tag Granularity (`skill_models`) (Sprint 2) |
| P0 | FR-5 Drift Detection CI gate (Sprint 1) |
| P1 | FR-4 Legacy Adapter Sunset — gated at Sprint 4 review (Sprint 4 if approved) |

### Out of scope (deferred)

| Item | Rationale |
|------|-----------|
| **Cycle-098 follow-ups** (L4 graduated-trust, L5/L6/L7 primitives) | Different problem domain — agent trust tiers, not model tiers. Belongs in a separate cycle. |
| **Beads DB recovery (#661)** | Operations work, not model-registry-shaped. Handle as `/bug` between cycles or as a Sprint 0 chore. |
| **Bridgebuilder iter-2 polish (#714, #719)** | T3 cosmetic backlog; not cycle-shaped. |
| **Hot-reload of model config** | YAGNI for v1 — restart-to-apply is acceptable. Could be follow-up cycle if operator demand emerges. |
| **Provider plugin contract for `model_aliases_extra`** | New providers (beyond OpenAI/Anthropic/Google/Bedrock) require System Zone code. Operator extension limited to existing provider types in v1. |
| **Multi-tenant model billing isolation** | Not in #710 scope; separate concern. |
| **Schema redesign of `model-config.yaml`** | Adding fields, not redesigning. Existing schema absorbs the changes. |
| **Ledger.json activation** | Chore PR after PRD lands (matches cycle-098 #679 pattern). |
| **Renaming `model-config.yaml`** | Stable identifier, no value in renaming. |

> Sources: operator interview decision (2026-05-04, scope = narrow), conflation-risk callout from operator during interview.

---

## Success Criteria

Cycle-099 is shipped when:

| ID | Criterion | Verification |
|----|-----------|--------------|
| **SC-1** | All non-legacy registries derive from `model-config.yaml` | CI drift gate passes; `grep -r 'claude-opus-[0-9]'` or similar finds zero hardcoded model names outside SoT, generated artifacts, and explicit backward-compat aliases |
| **SC-2** | Operator can register a model in `.loa.config.yaml::model_aliases_extra` and reference it from `skill_models` | E2E test: fresh-clone repo + sample operator config + `model-invoke --validate-bindings` resolves operator model |
| **SC-3** | `skill_models` block expresses Flatline-max / Red-Team-cheap / Bridgebuilder-mixed in ≤10 lines | Operator config audit during Sprint 2 acceptance |
| **SC-4** | Bridgebuilder `dist/` defaults regenerated from SoT via `bun run build` | Sprint 3 acceptance: `git diff --quiet dist/` after fresh build |
| **SC-5** | If FR-4 approved at Sprint 4 gate: `hounfour.flatline_routing: true` is default; legacy adapter marked deprecated; migration runbook published | Sprint 4 acceptance gate review |
| **SC-6** | No regressions in existing Flatline / Red Team / Bridgebuilder runs | Existing test suite (480+ from cycle-098) + new Sprint tests pass |
| **SC-7** | Backward compat preserved: existing operator configs work without changes | Migration test: cycle-098-vintage `.loa.config.yaml` resolves correctly |
| **SC-8** | Drift between registries = 0 | CI drift gate green on every PR |

> Sources: G-1..G-5 with measurement criteria, cycle-098 success-criteria pattern.

---

## Risks & Mitigation

| ID | Risk | Severity | Mitigation |
|----|------|----------|------------|
| **R-1** | Bridgebuilder TS dist regeneration breaks existing skill consumers (downstream Loa-mounted projects pin `dist/`) | HIGH | Generate `dist/` deterministically in PR; CI verifies dist matches source; ship cycle-099 release notes flagging the regen for downstream operators; backward-compat at API surface (only defaults change, not interfaces) |
| **R-2** | Operator's existing `.loa.config.yaml` stops working when loader strict-mode rejects new fields | MEDIUM | One-cycle deprecation path: loader accepts both old and new shapes; operator-visible warning on legacy shape; new shape wins on conflict; full schema migration in cycle-100 |
| **R-3** | Legacy adapter sunset breaks operators with `hounfour.flatline_routing: false` (the default today) | MEDIUM | Sprint 4 sunset is gated — operator approves at Sprint 4 review; flip the default in Sprint 4, deprecate but don't delete in cycle-099; full removal scheduled for cycle-100 |
| **R-4** | Drift detection CI false positives (regenerate produces non-deterministic output) | LOW | Lockfile approach with checksum verification; codegen scripts produce sorted, stable output; CI runs codegen + diff, not just diff |
| **R-5** | Beads UNHEALTHY (#661) workaround friction across 4 sprints | MEDIUM | Ledger fallback documented (per cycle-098 protocol); `--no-verify` for commits per cycle-098 pattern; consider Sprint 0 beads recovery if friction > 4h cumulative across cycle-099 — operator decision at Sprint 0 boundary |
| **R-6** | tier_groups mapping defaults populated wrong (e.g., `max` resolves to a deprecated model) | MEDIUM | Sprint 2 default mappings explicitly probe-confirmed via `model-health-probe.sh` (cycle-095 pattern); per-provider mapping reviewed in Sprint 2 design doc; operator override always wins |
| **R-7** | Operator config schema explosion (skill_models + model_aliases_extra + tier_groups + agents legacy + skill-specific legacy) confuses new operators | MEDIUM | `.loa.config.yaml.example` provides a worked example showing the canonical (new) shape; legacy shapes documented as deprecation-only; `loa setup` wizard updates to use new shape |
| **R-8** | Bridgebuilder `gen-bb-registry.ts` introduces a build-time dependency that breaks in CI environments without Bun | LOW | Bun is already a Bridgebuilder dependency (current `bun run build` pattern); CI containers already include Bun; no new dependency surface |
| **R-9** | `model_aliases_extra` security: operator adds malformed entry that crashes loader at startup | LOW | Schema validation rejects malformed entries with structured error; loader fails-fast at startup with clear remediation |
| **R-10** | cheval HTTP/2 bug (#675) mid-cycle resurfaces during Flatline review of cycle-099 PRDs/SDDs | MEDIUM | Already mitigated in cycle-098 via direct curl fallback; same workaround applies; cheval bug fix is its own follow-up |

> Sources: cycle-098 risk-assessment pattern, R-5 from cycle-098 RESUMPTION beads workaround, R-10 from cycle-098 SDD v1.5 cheval reference.

---

## Timeline & Milestones

Phased migration ordering (operator-locked at interview).

| Sprint | Scope | Estimated tests | Estimated cost | Risk |
|--------|-------|-----------------|----------------|------|
| **Sprint 1** | SoT extension foundation: Bridgebuilder TS codegen script (`gen-bb-registry.ts`); Red Team bash adapter migration to `generated-model-maps.sh`; `red-team-code-vs-design.sh` alias resolution; Drift detection CI gate (FR-5); Lockfile approach for generated artifacts | ~30 | ~$30-50 | LOW |
| **Sprint 2** | Config extension + per-skill granularity: `model_aliases_extra` schema + loader (FR-2); `skill_models` config block (FR-3.1); `tier_groups.mappings` populated for max/cheap/mid (FR-3.2); Per-role tier resolution (FR-3.3); `prefer_pro_models` composition (FR-3.4); Backward-compat aliases for legacy `models.{primary,...}` shapes (FR-3.7) | ~30 | ~$30-50 | MEDIUM (loader changes) |
| **Sprint 3** | Persona + docs migration + model-permissions: Persona docs use tier-tag (FR-1.5); Protocol docs reference operator config (FR-1.6); `model-permissions.yaml` derived from SoT (FR-1.4); Bridgebuilder `dist/` regenerated from SoT | ~25 | ~$25-40 | MEDIUM (Bridgebuilder dist) |
| **Sprint 4 (gated)** | Legacy adapter sunset: Mark `model-adapter.sh.legacy` deprecated (FR-4.1); Default flip: `hounfour.flatline_routing: true` (FR-4.2); Deprecation warnings active (FR-4.3); Sprint 4 gate review: full removal vs continued deprecation (FR-4.4); Migration runbook + release notes (NFR-Op-3) | ~25 | ~$25-40 | MEDIUM (default flip) |

**Total estimated**: ~110 tests, ~$110-180 cost, ~4-5 weeks wall-clock with full quality-gate chain per sprint (cycle-098 pattern: implement → review → audit → bridgebuilder kaironic 2-iter → admin-squash).

**Buffer**: Sprint 3.5 buffer week available for cross-sprint integration testing if Sprint 1-3 reveal shared-state interactions (e.g., Bridgebuilder dist regen + persona migration timing).

> Sources: cycle-098 sprint-cost actuals (~$25-50 per sprint with 4-slice + full quality gate), Sprint counter at 138 (cycle-099 reservations would be 139-142 or 139-143 with buffer).

---

## Appendix

### Appendix A — Full registry inventory (verified against current codebase)

See "Problem Statement" §1 for the table of 13 locations. Cross-referenced against [CODE:`grimoires/loa/reality/structure.md:11`] cheval adapter and [CODE:`grimoires/loa/reality/api-surface.md`] for current state.

### Appendix B — Cycle-095 baseline references

| What cycle-095 shipped | Where | Cycle-099 leverages |
|------------------------|-------|---------------------|
| YAML-as-SoT for hounfour path | [CODE:`.claude/defaults/model-config.yaml`] | Extend to all consumers |
| Provider registry + aliases + agents | [CODE:`model-config.yaml:7-381`] | Add `model_aliases_extra` as operator-extension layer |
| `tier_groups` schema (mappings empty) | [CODE:`model-config.yaml:402-413`] | Populate mappings in Sprint 2 |
| `prefer_pro_models` flag | cycle-095 Sprint 3 (closed) | Compose with `skill_models.X.tier: max` |
| `backward_compat_aliases` | [CODE:`model-config.yaml:282-313`] | Preserve unchanged |
| `gen-adapter-maps.sh` generator | cycle-095 Sprint 2 | Add `gen-bb-registry.ts` companion |
| Probe-gated rollout | cycle-095 Sprint 1 | Reuse for default tier mapping verification |

### Appendix C — Decision log

| Date | Decision | Source | Rationale |
|------|----------|--------|-----------|
| 2026-05-04 | Cycle-099 scope = narrow (#710 only); cycle-098 follow-ups deferred | Operator interview | Conflation risk between agent-tier (L4) and model-tier (cycle-099); narrow scope ships faster |
| 2026-05-04 | Migration ordering = phased (Sprint 1 SoT → 2 extension+granularity → 3 BB-TS codegen → 4 sunset) | Operator interview | Independently shippable per sprint; lower integration risk |
| 2026-05-04 | Per-skill granularity = tier-tag per skill (composes with `tier_groups`) | Operator interview | Simpler than direct-model-per-role; composes with cycle-095 |
| 2026-05-04 | Bridgebuilder TS migration = build-time codegen | Operator interview | Preserves current ship pattern; simpler than runtime YAML reads |
| 2026-05-04 | model-permissions.yaml strategy: Option B (merge into SoT) recommended; `/architect` decides | PRD recommendation | Permissions are a per-model attribute; merging eliminates a registry |
| 2026-05-04 | Legacy adapter sunset gated at Sprint 4 review | PRD framing | Operator opts in to full removal vs deprecation-window |

### Appendix D — Glossary

| Term | Definition |
|------|------------|
| **SoT** | Source of Truth — the single authoritative registry. In cycle-099, `model-config.yaml`. |
| **Tier** | Operator-facing abstraction: `max`, `cheap`, `mid`. Resolves via `tier_groups.mappings` to a concrete model per provider. |
| **Tier-tag** | Tier reference at the operator-config level (e.g., `flatline_protocol.primary: max`). |
| **Tier-group** | The cycle-095 schema in `model-config.yaml::tier_groups` that maps tier names to model IDs. |
| **Hounfour path** | The cheval (Python) execution path. Activated by `hounfour.flatline_routing: true`. Today: not the default. |
| **Legacy adapter** | `model-adapter.sh.legacy` — the bash dict-based resolver used when `hounfour.flatline_routing: false` (today's default). |
| **cheval** | The multi-provider Python adapter at `.claude/adapters/cheval.py`. Routes requests to OpenAI, Anthropic, Google, Bedrock. |
| **Bridgebuilder dist** | Pre-compiled TypeScript output at `.claude/skills/bridgebuilder-review/dist/`. Today's pattern: maintainer commits dist alongside source. |
| **Codegen** | Build-time generation of artifacts (bash maps, TS literals, lockfile checksums) from SoT YAML. |
| **Drift gate** | CI check that fails when generated artifacts diverge from SoT. |
| **Backward compat aliases** | Legacy model IDs in `model-config.yaml::backward_compat_aliases` that resolve to current canonical models. |

### Appendix E — Sources cited

| Source | Use |
|--------|-----|
| [#710](https://github.com/0xHoneyJar/loa/issues/710) issue body | Problem statement, registry audit, FR-1/2/3 acceptance criteria |
| [#710](https://github.com/0xHoneyJar/loa/issues/710#issuecomment-4367754767) operator comment | Per-skill granularity scope (FR-3) |
| [CODE:`grimoires/loa/reality/decisions.md:86-87`] | Existing 4-array atomic-edit constraint — pain point being solved |
| [CODE:`grimoires/loa/reality/terminology.md:106-108`] | Bridgebuilder + Flatline canonical multi-model definitions |
| [CODE:`grimoires/loa/reality/structure.md:11`] | cheval adapter at `.claude/adapters/` confirmed as Python multi-provider substrate |
| [CODE:`.claude/defaults/model-config.yaml:1-460`] | Cycle-095 SoT baseline — providers, aliases, agents, tier_groups, backward_compat |
| [CODE:`.loa.config.yaml`] | Current per-skill config shapes (inconsistent across skills) |
| `grimoires/loa/context/model-currency-cycle-preflight.md` (102 lines) | Cycle-095 live API state capture |
| `grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md` Brief A | Cycle-099 brief, scope, locked patterns |
| `grimoires/loa/gaps.md:GAP-003-4d6f` | Doc drift confirmation |
| Phase 0 synthesis (interview, 2026-05-04) | Pre-interview context map |
| Phase 1-7 confirmations (interview, 2026-05-04) | 4 locked decisions on scope, ordering, granularity, Bridgebuilder TS |

---

*This PRD is the cycle-099 charter. Operator approves scope, then `/architect` produces SDD, then `/sprint-plan` produces sprint plan, then `/run sprint-1` begins implementation. Cycle-098's PRD/SDD are preserved at `grimoires/loa/cycles/cycle-098-agent-network/`. Ledger activation (transition `active_cycle` to `cycle-099-model-registry`) is a separate chore step after PRD approval, matching the cycle-098 #679 pattern.*
