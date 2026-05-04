# Product Requirements Document: Model Registry Consolidation + Per-Skill Granularity

**Version:** 1.3 (Flatline pass #3 kaironic plateau: 2 PRD-level themes integrated; 4 SDD-shape operational refinements deferred to `/architect`)
**Date:** 2026-05-04
**Author:** PRD Architect (deep-name + Claude Opus 4.7 1M)
**Status:** Draft — 3 PRD-level Flatline passes complete (kaironic stop at pass #3: 90% agreement, finding-rotation at finer grain, first DISPUTED item appearing). Ready for `/architect`.
**Cycle (proposed):** `cycle-099-model-registry` *(actual ID assigned by ledger when `/sprint-plan` runs)*

**Source issue:**
- [#710](https://github.com/0xHoneyJar/loa/issues/710) — Refactor: consolidate model registries to single source of truth + add config extension mechanism

> **v1.2 → v1.3 changes** (Flatline pass #3, `grimoires/loa/a2a/flatline/cycle-099-prd-review-v12.json`, Opus + GPT-5.3-codex + Gemini-3.1-pro-preview, **90% model agreement, 1 DISPUTED, 6 BLOCKERS, 4 HIGH_CONSENSUS — kaironic plateau signal**):
> - **Kaironic stop declared** per cycle-098 PRD v1.4 → v1.5 pattern: finding-rotation at finer grain (IPv6/IDN/punycode URL canonicalization, shell-escape safety, flock over network filesystems, BB hybrid divergence detection — all NEW themes that are increasingly specific operational refinements appropriate for SDD-level), DISPUTED item emerging (IMP-004 GPT 480 vs Gemini 880 delta 330), agreement decreasing.
> - **2 PRD-level themes integrated**:
>   - **IMP-001 (HIGH 865) credential contract for operator-added providers** — New NFR-Sec-5: v1 scope clarified — operator-added models in `model_aliases_extra` REUSE the provider's existing credential env var (per cycle-095); no new credential surface introduced. Operator wanting different credentials per operator-added model: not supported in v1; must use System Zone registration (cycle-level approval). FR-2.8 endpoint allowlist + NFR-Sec-1 SSRF defenses already prevent operator from routing to a different provider via spoofed endpoint.
>   - **IMP-005 (HIGH 845) fail-closed vs legacy compat conflict** — FR-3.7 strengthened: during cycle-099 deprecation window, legacy shape unresolved bindings emit deprecation warning AND fall back to skill's framework default tier mapping (FR-3.5). This is the **ONE EXCEPTION** to FR-3.8 fail-closed semantics, explicitly time-bounded to one cycle. New `skill_models` shape always fail-closed. Cycle-100 (or operator setting `legacy_shapes_fail_closed: true` for early opt-in) makes legacy bindings also fail-closed.
> - **4 SDD-shape operational refinements deferred to `/architect` SDD review** (per kaironic plateau — appropriate level): SKP-003 (URL canonicalization edge cases: IPv6 literals, IDN/punycode, port specs); SKP-004 (shell-escape safety in `.run/merged-model-aliases.sh`); SKP-005 (flock semantics over network filesystems — NFS/SMB caveats); SKP-006 (hybrid BB TS-runtime vs runtime-overlay divergence detection). These will surface in SDD-level Flatline reviews and integrate as architecture-level mitigations rather than PRD-level scope.
> - **DISPUTED item recorded but NOT integrated**: IMP-004 (avg 645, delta 330) — per-invocation cost forecasts at resolution time. GPT 480 (low value, complex) vs Gemini 880 (high operator-safety value). Decision: defer to operator's discretion at SDD; cycle-098 disputed-rotation pattern says "rotation is signal, not action."
>
> **v1.1 → v1.2 changes** (Flatline pass #2, `grimoires/loa/a2a/flatline/cycle-099-prd-review-v11.json`, Opus + GPT-5.3-codex + Gemini-3.1-pro-preview, 100% model agreement, 9 BLOCKERS → 5 BLOCKERS = 4 closed by v1.1):
> - **SKP-001 (CRITICAL 910) integrated** — Deferred Decisions table strengthened with **owner**, **deadline**, **fallback-if-no-consensus** columns for DD-1..DD-5. 48-72h ceiling per decision; missed deadline triggers fallback choice.
> - **SKP-002 (CRITICAL 885) integrated** — FR-3.4 + FR-3.9 strengthened: legacy `prefer_pro_models` overlay gated behind explicit `respect_prefer_pro: true` opt-in for legacy-shape skills (default false during deprecation window) — isolates overlay surprise to migrated skills. **NEW: property-based tests** for FR-3.9 precedence invariants per cycle-098 SKP-002 pattern. Algorithm complexity preserved (6 stages); state-space reduced by gating.
> - **SKP-003 (HIGH 770) integrated** — FR-1.9 strengthened: atomic write (temp + `rename(2)`), `flock` shared/exclusive locks, monotonic version header in `.run/merged-model-aliases.sh` first line.
> - **SKP-004 (HIGH 755) integrated** — NFR-Sec-1 + FR-2.8 strengthened: canonical URL parser (HTTPS only, default port enforced, path normalized); DNS-resolved IP re-verified at request time (defeats DNS rebinding); HTTP redirects crossing trust boundaries denied; TLS verification mandatory; no operator `verify=false` override.
> - **SKP-005 (HIGH 730) integrated** — FR-1.4 strengthened: operator-added models default to **minimal permissions baseline** (`chat` only). Higher permissions require System Zone `model-config.yaml` registration (cycle-level approval) OR explicit operator-acknowledged baseline (`acknowledge_permissions_baseline: true`).
> - **IMP-001 (HIGH_CONSENSUS 890) integrated** — DD-3 row in Deferred Decisions table strengthened: explicit `model_aliases_override` field design specification required from `/architect`; partial vs full override semantics documented; silent override rejected.
> - **IMP-002 (HIGH_CONSENSUS 820) integrated** — New FR-5.7: runtime resolution tracing via `LOA_DEBUG_MODEL_RESOLUTION=1` env var; structured `[MODEL-RESOLVE]` stderr log per resolution showing stage-by-stage path. `model-invoke --validate-bindings --verbose` enables it for dry-run.
> - **IMP-003 (HIGH_CONSENSUS 835) integrated** — FR-1.9 strengthened: explicit fail-closed semantics for file-missing (regenerate), parse-error (refuse to start), permission failure (refuse to start), stale (regenerate via SHA256 hash mismatch).
> - **IMP-004 (HIGH_CONSENSUS 735) integrated** — FR-1.9 strengthened: SHA256-based invalidation (NOT mtime — under concurrent writes mtime can lie); invalidation check under shared `flock`; regeneration under exclusive `flock`. Race-condition mitigation explicit.
> - **IMP-006 (HIGH_CONSENSUS 845) integrated** — New SC-13: legacy compatibility golden tests at `tests/integration/legacy-config-golden.bats` covering all 4 existing config shapes; cycle-098-vintage `.loa.config.yaml` fixtures resolve identically before/after migration.
>
> **v0 → v1.1 changes** (Flatline pass #1, `grimoires/loa/a2a/flatline/cycle-099-prd-review.json`, Opus + GPT-5.3-codex + Gemini-3.1-pro-preview, 100% model agreement):
> - **SKP-001 (CRITICAL 950) integrated** — Decision 4 revised from "build-time codegen" to **hybrid (build-time codegen for defaults + runtime YAML overlay for operator-added entries)**. Bridgebuilder reads `.loa.config.yaml::model_aliases_extra` at startup and merges with compiled defaults. Closes runtime/build-time visibility gap.
> - **SKP-003 (CRITICAL 910 + HIGH 750) integrated** — NFR-Sec-1 strengthened: provider-specific endpoint allowlist; localhost / 169.254.169.254 / RFC 1918 IPs blocked unless `allow_local_endpoints` System Zone flag set; api_id format normalization (`^[a-zA-Z0-9._-]+$`); SSRF + command-injection security test corpus (NFR-Sec-1.1). New FR-2.8 enforces endpoint allowlist per provider.
> - **SKP-004 (CRITICAL 860 + HIGH 720) integrated** — FR-3.5 strengthened: startup validation refuses launch on unresolved (skill, role, tier) bindings. New FR-3.8 makes fail-closed semantics explicit. FR-1.4 adds permissions-elevation rejection (operator can't elevate via `model_aliases_extra`).
> - **SKP-002 BASH-YAML (HIGH 780) integrated** — New FR-1.9: startup hook (Python/Node) writes merged config to `.run/merged-model-aliases.sh` (mode 0600); bash adapters source this file. No bash YAML parsing.
> - **SKP-002 PRECEDENCE (HIGH 780) integrated** — New FR-3.9: deterministic 6-stage resolution algorithm with explicit precedence + tiebreakers + conflict errors. Golden tests per skill in SC-9.
> - **SKP-001 DEFERRED-DECISIONS (HIGH 760) integrated** — New "Deferred Decisions to Resolve Before Sprint 1" subsection. FR-1.4 / FR-2.1 / FR-2.3 marked release blockers for /architect SDD.
> - **SKP-005 REPRODUCIBILITY (HIGH 720) integrated** — New NFR-Op-5: codegen reproducibility (pinned toolchain, canonical serialization, matrix CI). New FR-5.5 enforces in CI.
> - **IMP-001 PRECEDENCE (avg 875) integrated** — covered by FR-3.9.
> - **IMP-002 FALLBACK (avg 835) integrated** — covered by FR-3.8.
> - **IMP-003 ROLLBACK (avg 785) integrated** — R-1 strengthened: dist regeneration rollback path + version-comment header (`// Generated from model-config.yaml@<sha>`) + dist tag for downstream submodule pinning.
> - **IMP-004 SCHEMA-ARTIFACT (avg 815) integrated** — FR-2.2 strengthened: normative JSON Schema at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (ajv-validated).
> - **IMP-005 CLI-CONTRACT (avg 735) integrated** — New FR-5.6: `model-invoke --validate-bindings` contract spec (input, output schema, exit codes).
> - **Postmortem of Flatline pass #1 itself**: 2 attempts failed in 3 distinct ways, all caused by the very registry fragmentation cycle-099 solves. Captured at `grimoires/loa/cycles/cycle-099-model-registry/decisions/02-flatline-prd-review-failure-postmortem-2026-05-04.md` as primary-source evidence for the cycle.

**Operator-approved scope decisions** (interview 2026-05-04 + Flatline integration):

| Decision | Locked value |
|----------|--------------|
| Cycle scope | Narrow — `#710` only (no cycle-098 follow-ups) |
| Migration ordering | Phased — Sprint 1 SoT → Sprint 2 extension+granularity → Sprint 3 BB-TS codegen → Sprint 4 (optional) sunset |
| Per-skill granularity shape | Tier-tag per skill (composes with cycle-095 `tier_groups`) |
| Bridgebuilder TS migration | **Hybrid (v1.1 reframe)** — build-time codegen for defaults + runtime YAML overlay for operator-added entries. Per Flatline SKP-001 CRITICAL (950). |

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
| **FR-1.1** | Bridgebuilder TypeScript registries follow a **hybrid pattern** (revised v1.1 per Flatline SKP-001 CRITICAL): (a) **Build-time codegen** of compiled defaults — `gen-bb-registry.ts` reads `model-config.yaml`, emits `truncation.generated.ts` (truncation map keyed by model_id) and `config.generated.ts` (default-model alias resolution). Generated files committed alongside source; `bun run build` invokes generator. (b) **Runtime overlay** at Bridgebuilder startup — reads `.loa.config.yaml::model_aliases_extra` + `.loa.config.yaml::skill_models` and merges into the compiled tables. Operator-added models become visible to Bridgebuilder without rebuilding. Resolution order: operator override > runtime overlay > compiled default. Truncation entries for operator-added models computed at startup using a generic context-window-based formula (see Technical Considerations §"Hybrid Bridgebuilder pattern"); operators may override per-model truncation by populating `model_aliases_extra.<id>.context.truncation_coefficient`. |
| **FR-1.1.1** | Endpoint routing in `adapters/openai.ts`: replace `string-match "codex"` heuristic with explicit `endpoint_family` field lookup. `/v1/responses` vs `/v1/chat/completions` decision sources from compiled defaults (build-time) AND runtime overlay (operator-added models declare `endpoint_family` in `model_aliases_extra`). |
| **FR-1.2** | Red Team bash adapter (`red-team-model-adapter.sh`) reads from `generated-model-maps.sh` (sourced in shell) — eliminating the independent associative array. |
| **FR-1.3** | `red-team-code-vs-design.sh` resolves `--model opus` via the SoT's alias chain (no hardcoded `opus` literal — uses the `opus` alias defined in YAML). |
| **FR-1.4** | `.claude/data/model-permissions.yaml` is either (a) derived from `model-config.yaml` via codegen, or (b) merged into `model-config.yaml` as a `permissions` field per model. **`/architect` MUST resolve before Sprint 1 implementation begins** (release blocker per Flatline SKP-001 deferred-decision finding). v1.0 PRD recommendation: merge into `model-config.yaml` since permissions are a per-model attribute. **Permissions-elevation rejection** (per Flatline SKP-004 CRITICAL): if `model_aliases_extra` includes a `permissions` field, validate against framework-default provider baseline; reject operator entries that declare permissions higher than the baseline. Permission elevation requires System Zone change (and cycle-level approval per zone-system rule). **Baseline for new operator-added models with no framework baseline entry** (per v1.2 Flatline SKP-005 HIGH 730): default to **minimal permissions baseline** (`chat` only — no `tools`, no `function_calling`, no `code`, no `thinking_traces`). If operator wants higher permissions for an operator-added model, two paths: (a) add the model to System Zone `model-config.yaml::providers.<p>.models.<id>.permissions` (cycle-level approval, NOT operator-extensible); OR (b) explicitly opt into the minimal baseline by setting `model_aliases_extra.<id>.acknowledge_permissions_baseline: true` (explicit operator acknowledgement that the operator-added model gets minimal-only permissions). Validation rejects operator-added models with no baseline entry AND no `acknowledge_permissions_baseline: true` flag. |
| **FR-1.5** | Persona docs (both `.claude/data/personas/*.md` and `.claude/skills/bridgebuilder-review/resources/personas/*.md`) replace hardcoded model names with tier-tag references (e.g., `# tier: max` instead of `# model: claude-opus-4-7`). Backward compat: parsers accept both forms; tier-tag wins if present. |
| **FR-1.6** | Protocol docs (`.claude/protocols/flatline-protocol.md`, `gpt-review-integration.md`) replace hardcoded model names with operator-config references ("configure your top-of-provider in `.loa.config.yaml`"). Examples reference tier names (`max`, `cheap`), not specific model IDs. |
| **FR-1.7** | `.claude/scripts/model-adapter.sh` (the *non*-`.legacy` shipped variant) sources `generated-model-maps.sh` at init, eliminating its own dictionary. (Note: cycle-095's `vision-011 activation` bug-fix already converted this script to runtime-swap to `generated-model-maps.sh` at runtime — verify against current state in Sprint 1.) |
| **FR-1.8** | After all migrations land, the only hand-maintained model registry in the codebase is `.claude/defaults/model-config.yaml`. |
| **FR-1.9** | **Runtime config consolidation** (per Flatline SKP-002 HIGH bash-YAML-parsing finding): a startup hook (Python or Node, decision DD-4) reads merged config (`model-config.yaml` ∪ `.loa.config.yaml::model_aliases_extra`) and writes `.run/merged-model-aliases.sh` with mode `0600`. Bash adapters (Red Team, model-adapter.sh, etc.) `source` this file at init — they do NOT parse YAML at runtime. **Atomic write semantics** (per v1.2 Flatline SKP-003 HIGH 770): write to temp file with random suffix in same directory, then `rename(2)` to final path (POSIX-atomic on same filesystem). **Concurrency control**: writers acquire `flock` exclusive lock on `.run/merged-model-aliases.sh.lock`; readers acquire shared lock; lock file is permanent and 0-byte. **Version header**: first line of `.run/merged-model-aliases.sh` is `# version=<monotonic_counter>` AND second line is `# source-sha256=<hash-of-merged-input-yaml>`; readers verify version match before sourcing — version mismatch triggers re-read after lock acquisition. **Invalidation** (per v1.2 Flatline IMP-004 HIGH_CONSENSUS 735): SHA256-based (NOT mtime alone — under concurrent writes mtime can be inconsistent); invalidation check happens under shared `flock` lock; regeneration under exclusive lock. **Failure modes** (per v1.2 Flatline IMP-003 HIGH_CONSENSUS 835): (a) file-missing → regenerate via startup hook; (b) parse-error / bash syntax check fails → refuse to start (fail-closed, `[MERGED-ALIASES-CORRUPT]` structured error); (c) write permission failure / disk full → refuse to start (fail-closed, `[MERGED-ALIASES-WRITE-FAILED]`); (d) stale per SHA256 → regenerate. Pattern mirrors cycle-095's `gen-adapter-maps.sh` (build-time) + adds runtime equivalent. |

### FR-2 — Config Extension Mechanism (P0)

Operators register new models without System Zone edits. Mirrors the existing `protected_classes_extra` pattern from cycle-098 Sprint 1B.

| AC | Acceptance criterion |
|----|----------------------|
| **FR-2.1** | New `.loa.config.yaml` field `model_aliases_extra` (top-level or nested under `models:`, **`/architect` MUST resolve placement before Sprint 1**, release blocker per Flatline SKP-001 deferred-decision finding) accepts an array of model definitions matching the YAML schema for `providers.<provider>.models.<id>` entries. |
| **FR-2.2** | Schema validation at config load time using **normative JSON Schema published at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json`** (per Flatline IMP-004 HIGH_CONSENSUS, ajv-validated). Reject: malformed entries, missing required fields, duplicate model IDs (collide with framework defaults). Structured error includes offending line + remediation hint. Schema versioned via `schema_version` field; breaking changes bump major version. |
| **FR-2.3** | Merge order: framework defaults (`model-config.yaml`) ∪ operator extras (`model_aliases_extra`). On duplicate ID: error (do not silently override; operator must rename or explicitly opt into override via a separate `model_aliases_override` field — **`/architect` MUST resolve override-semantics design before Sprint 1**, release blocker per Flatline SKP-001 deferred-decision finding). |
| **FR-2.4** | Backward-compat aliases from cycle-095 (legacy model IDs, e.g., `claude-opus-4.x` → `claude-opus-4-7`) preserved without operator action. |
| **FR-2.5** | Hot-reload **NOT** required for v1 (YAGNI). Config loaded at runtime startup; restart-to-apply is acceptable. |
| **FR-2.6** | Operators can extend BOTH `models` and `aliases` — i.e., they can define a new model AND give it a friendly tier-tag in one config block. |
| **FR-2.7** | `.loa.config.yaml.example` documents the `model_aliases_extra` field with a worked example. |
| **FR-2.8** | **Provider-specific endpoint allowlist** (per Flatline SKP-003 CRITICAL 910 + HIGH 750): each provider has a framework-defined list of permitted endpoint hostnames in `.claude/defaults/loa.defaults.yaml::providers.<p>.allowed_endpoints` (e.g., `openai: [api.openai.com]`, `anthropic: [api.anthropic.com]`, `google: [generativelanguage.googleapis.com, *.googleapis.com]`, `bedrock: [bedrock-runtime.{region}.amazonaws.com]`). Operator `model_aliases_extra` entries whose `endpoint` does NOT match the provider's allowlist are rejected at load time UNLESS `allow_local_endpoints: true` is explicitly set in System Zone defaults (cycle-level authorization, NOT operator-extensible). Localhost variants (`localhost`, `127.0.0.0/8`, `::1`), AWS IMDS (`169.254.169.254`), and RFC 1918 private IPs (`10/8`, `172.16/12`, `192.168/16`) are blocked even when `allow_local_endpoints: true` UNLESS additionally `allow_internal_endpoints: true` is set. `api_id` format normalization: must match `^[a-zA-Z0-9._-]+$` — shell metacharacters and path separators rejected with structured error. |

### FR-3 — Per-Skill Tier-Tag Granularity (P0)

Operators express which tier each skill should use via a single config block. Composes with cycle-095's `tier_groups` schema (mappings empty as of cycle-095 Sprint 2).

| AC | Acceptance criterion |
|----|----------------------|
| **FR-3.1** | New `.loa.config.yaml` field `skill_models` (top-level or under `agents:`, decision in `/architect`). Schema: `{<skill_name>: {<role>: <tier_or_model_ref>}}`. Example: `skill_models: { flatline_protocol: {primary: max, secondary: max, tertiary: max}, red_team: {primary: cheap}, bridgebuilder: {opus_role: max, gpt_role: max, gemini_role: cheap}, adversarial_review: {primary: max} }` |
| **FR-3.2** | Tier-tag → concrete model resolution via `tier_groups.mappings` (cycle-095 Sprint 2 schema). Cycle-099 Sprint 2 populates default mappings: `max` → top-of-provider per provider; `cheap` → budget-tier per provider; `mid` → middle-tier. Operator can override `tier_groups.mappings` in `.loa.config.yaml`. |
| **FR-3.3** | Per-role tier (when a skill has multiple roles, e.g., bridgebuilder's opus/gpt/gemini reviewer roles). Each role independently tier-taggable. |
| **FR-3.4** | Composes with cycle-095's `prefer_pro_models` flag — `prefer_pro_models: true` retargets the `max` tier to the pro variant per provider (e.g., `gpt-5.5` → `gpt-5.5-pro`). **Legacy-shape isolation** (per v1.2 Flatline SKP-002 CRITICAL 885 — algorithm-complexity scope reduction): for skills using new `skill_models` shape, `prefer_pro_models` overlay applies automatically. For skills still using legacy `flatline_protocol.models.<role>` / `bridgebuilder.multi_model.models[]` / `gpt_review.models.<role>` / `adversarial_review.model` shape, `prefer_pro_models` overlay is **opt-in** via per-skill `respect_prefer_pro: true` (default `false` during deprecation window). This isolates the overlay surprise to migrated skills only and reduces FR-3.9 algorithm state-space for legacy paths. |
| **FR-3.5** | Each skill ships with sensible default tier mapping in `model-config.yaml::agents.<skill_name>` so that no operator config is required for default behavior. The `skill_models` block is purely override. **Startup validation** (per Flatline SKP-004 CRITICAL 860): every (skill, role) pair in the effective merged config MUST resolve to a concrete `provider:model_id`. If any (skill, role) maps to a tier without a tier_groups mapping for the resolved provider, OR maps to a model_id absent from both framework defaults and `model_aliases_extra`, the agent **refuses to start** with structured error listing all unresolved bindings. No silent fallback. |
| **FR-3.6** | Mixed mode supported: an operator can specify a tier-tag for some roles AND an explicit model ID for others (e.g., `bridgebuilder.opus_role: max, bridgebuilder.gpt_role: gpt-5.3-codex`). Resolution: tier-tags resolve via `tier_groups`; explicit IDs resolve directly via `aliases` + `models`. |
| **FR-3.7** | Migration of existing config shapes: `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model` continue to work via deprecation aliases (one cycle's deprecation window). New `skill_models` is the canonical shape going forward. **Legacy-shape fail-closed exception** (per v1.3 Flatline IMP-005 HIGH 845 — fail-closed vs legacy compat conflict resolution): during the cycle-099 deprecation window, legacy-shape unresolved bindings (e.g., a legacy `flatline_protocol.models.secondary` referencing a model not in any registry) emit a deprecation warning `[LEGACY-SHAPE-UNRESOLVED] skill=X role=Y — recommend migration to skill_models`. Resolution falls back to the skill's **framework default tier mapping** per FR-3.5 (i.e., the cycle-095 `agents.<skill_name>` tier resolves via `tier_groups.mappings`). This is the **ONE EXCEPTION** to FR-3.8 fail-closed semantics, explicitly time-bounded to one cycle. New `skill_models` shape **always fail-closed** (no exception). Cycle-100 (or operators opting in early via `legacy_shapes_fail_closed: true`) makes legacy bindings also fail-closed — the deprecation window ends. Operators on legacy shapes during cycle-099 receive deprecation-warning telemetry on every resolution; aggregate count surfaces in `model-invoke --validate-bindings`. |
| **FR-3.8** | **Fail-closed tier fallback semantics** (per Flatline SKP-004 CRITICAL + HIGH): when `tier_groups.mappings` lacks the required tier for a provider OR the required provider for a tier-tagged binding, refuse to start. Diagnostic: `[BINDING-UNRESOLVED] skill=flatline_protocol role=primary tier=max provider=openai (no max mapping for openai in tier_groups)`. Operator remediation paths (printed in error message): (1) populate `tier_groups.mappings` to map the missing tier; (2) pin an explicit `provider:model_id` in `skill_models`; (3) drop the binding and accept the framework default for the skill. The agent NEVER starts with unresolved bindings — explicit operator action required. |
| **FR-3.9** | **Deterministic resolution algorithm** (per Flatline SKP-002 HIGH precedence + IMP-001 HIGH_CONSENSUS 875): when multiple resolution mechanisms could apply to the same (skill, role) pair, precedence is applied in this fixed order: (1) explicit `provider:model_id` in `.loa.config.yaml::skill_models.<skill>.<role>` wins absolutely; (2) tier-tag in `skill_models` resolves via operator-set `tier_groups.mappings` if present; (3) tier-tag resolves via framework-default `tier_groups.mappings` from `model-config.yaml`; (4) legacy shape (`flatline_protocol.models.<role>`, `bridgebuilder.multi_model.models[]`, etc.) resolves directly via `aliases` + `models` namespaces with deprecation warning emitted; (5) framework default for skill in `model-config.yaml::agents.<skill_name>`; (6) `prefer_pro_models: true` overlay applied AFTER step 1-5 (retargets resolved `*-pro` variants per provider; **gated per FR-3.4 for legacy shapes**). Conflict between (1) and (4) → (1) wins (no silent tiebreaker). Two same-priority mechanisms produce error. **Property-based test coverage** (per v1.2 Flatline SKP-002 CRITICAL 885 mitigation; cycle-098 SKP-002 invariant pattern): Sprint 2 ships property-based tests at `tests/property/model-resolution-properties.bats` verifying invariants: (i) "if (1) and (4) both present, (1) wins"; (ii) "two same-priority mechanisms always produce error, never silent tiebreaker"; (iii) "prefer_pro overlay always applied last (step 6)"; (iv) "deprecation warning emitted ⟺ stage (4) was the resolution path"; (v) "operator-extra-tier resolves before framework-default-tier when both define same provider mapping"; (vi) "unmapped tier produces FR-3.8 fail-closed error, never silent fallback to (5)". Test runner: `bats` + simple property-generator (random valid configs across the 6-stage state-space, run resolution, assert invariants). |

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
| **FR-5.5** | **Codegen reproducibility** (per Flatline SKP-005 HIGH 720): `gen-adapter-maps.sh`, `gen-bb-registry.ts`, `gen-model-permissions.sh` (per FR-1.4 Option A), and the FR-1.9 startup hook MUST produce byte-identical output for the same input across Linux + macOS. Pinning: bash `>= 5.x`, bun `1.1.x` (specific minor pinned in `.tool-versions` or equivalent), jq `>= 1.7`, python `>= 3.11`. Canonical serialization rules: keys sorted alphabetically, trailing newline normalized to LF, no trailing whitespace, integer scalars unquoted. CI matrix runs codegen on `ubuntu-latest` + `macos-latest`; byte-for-byte mismatch fails the build. |
| **FR-5.6** | **`model-invoke --validate-bindings` contract** (per Flatline IMP-005 HIGH_CONSENSUS 735): input = effective merged config (framework defaults + `model_aliases_extra` + `skill_models` + `tier_groups`); output (default `--format json`) = JSON array of `{skill, role, resolved_provider_id, resolution_path}` tuples where `resolution_path` enumerates which step of the FR-3.9 algorithm produced the resolution; pretty-print mode `--format text` for operator readability. Exit codes: `0` = all bindings resolve cleanly; `78` = config error (`EX_CONFIG`, e.g., schema-invalid `model_aliases_extra`); `1` = at least one unresolved binding (FR-3.8 violation). Behavior is dry-run (no API calls). |
| **FR-5.7** | **Runtime resolution tracing** (per v1.2 Flatline IMP-002 HIGH_CONSENSUS 820): when `LOA_DEBUG_MODEL_RESOLUTION=1` is set in the agent's environment, every model resolution emits a structured log entry to stderr in the format: `[MODEL-RESOLVE] skill=<X> role=<Y> input='<operator-or-default-spec>' resolved='<provider:model_id>' resolution_path=[stage1_pin_check:miss, stage2_tier_lookup_operator:miss, stage3_tier_lookup_default:hit, stage6_prefer_pro_overlay:applied]`. Each stage in the path identifies which FR-3.9 algorithm stage matched, with `:hit`, `:miss`, `:applied`, `:skipped`, or `:error` outcome. `model-invoke --validate-bindings --verbose` automatically enables tracing for the dry-run resolution. Per-resolution overhead under tracing: <2ms (logging-only; no behavior change). Default: tracing OFF — production hot path unaffected. |

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
| **NFR-Sec-1** | **`model_aliases_extra` SSRF + injection hardening** (strengthened in v1.1 per Flatline SKP-003 CRITICAL 910 + HIGH 750; further strengthened in v1.2 per Flatline SKP-004 HIGH 755): schema validated at load time via the JSON Schema in FR-2.2. Rejects (with structured error citing the violating field + remediation): (a) shell metacharacters / path separators / nullbytes in `api_id` (must match `^[a-zA-Z0-9._-]+$` per FR-2.8); (b) `endpoint` URLs whose hostname does NOT match the provider's allowlist in `.claude/defaults/loa.defaults.yaml::providers.<p>.allowed_endpoints` (per FR-2.8) — UNLESS `allow_local_endpoints: true` is set in System Zone defaults; (c) `endpoint` URLs resolving to localhost / `127.0.0.0/8` / `::1` / AWS IMDS `169.254.169.254` / RFC 1918 ranges, even with `allow_local_endpoints: true`, UNLESS additionally `allow_internal_endpoints: true` is explicitly set; (d) unknown provider `type` (provider plugin contract is System Zone, not operator-extensible in v1, per NFR-Sec-4); (e) `params` fields containing executable values (function references, eval strings, raw shell commands). **URL canonicalization** (per v1.2 Flatline SKP-004): use Python `urllib.parse.urlsplit` (or Node `URL` constructor — pick per DD-4) for parsing; require `scheme == 'https'` (no HTTP, no custom schemes); enforce default port (`443`) — operator-supplied custom ports rejected unless explicitly allowlisted per provider; normalize path (no `..` / `./` / repeated slashes). **DNS rebinding defense**: at REQUEST time (not just config load), resolve hostname; if resolved IP falls into blocked ranges per (c), reject the request and emit `[ENDPOINT-DNS-REBOUND]` audit log. **Redirect denial**: HTTP redirect responses crossing trust boundaries (different hostname OR different IP range than the originally-resolved-and-verified IP) are rejected; only same-host redirects honored. **TLS verification** mandatory; no operator `verify=false` override permitted for `model_aliases_extra` endpoints. |
| **NFR-Sec-1.1** | **Security test corpus** (new in v1.1 per Flatline SKP-003 CRITICAL): Sprint 2 ships an integration test suite at `tests/integration/model-aliases-extra-security.bats` covering: SSRF probes via `endpoint` (localhost, IMDS, internal IPs); command injection via `api_id` (shell metacharacters, command substitution, env-var expansion); path traversal via field values (`../`, `~/`, absolute paths); permission escalation via `permissions` field (per FR-1.4); schema-invalid entries crashing loader (vs failing-closed); duplicate ID handling. Each probe produces a deterministic structured error; exit codes match FR-5.6. |
| **NFR-Sec-2** | Same trust model as `protected_classes_extra` (cycle-098 Sprint 1B): operator zone, not System Zone. Validation happens before any HTTP call. |
| **NFR-Sec-3** | No new secrets surface introduced — model resolution doesn't handle API keys (those remain in environment variables per cycle-095). |
| **NFR-Sec-4** | If `model_aliases_extra` adds a new provider type (not in framework defaults), reject with structured error directing to upstream PR (provider plugin contract is System Zone, not operator-extensible in v1). |
| **NFR-Sec-5** | **Credential contract for operator-added models** (per v1.3 Flatline IMP-001 HIGH 865): v1 scope — operator-added models in `model_aliases_extra` MUST reuse the provider's existing credential env var (per cycle-095: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `AWS_BEARER_TOKEN_BEDROCK`). The `auth` field in `model_aliases_extra` entries is rejected at load time (operator-defined credentials NOT supported in v1). Combined with FR-2.8 endpoint allowlist + NFR-Sec-1 SSRF defenses, this prevents operators from routing requests to a different-trust-domain provider via custom credentials. Operators wanting different credentials per operator-added model must use System Zone registration (`.claude/defaults/model-config.yaml::providers.<p>.models.<id>` with explicit `auth` field; cycle-level approval). Documented in `.loa.config.yaml.example` operator-facing comment block. v2 follow-up (out of scope for cycle-099): per-operator-model credential namespace (`OPENAI_API_KEY_<model_id>` pattern) — defer to operator demand. |

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
| **NFR-Op-5** | **Codegen reproducibility operability** (per Flatline SKP-005 HIGH 720, paired with FR-5.5): toolchain pinning surfaced at the operability boundary — Sprint 1 publishes `grimoires/loa/runbooks/codegen-toolchain.md` documenting required `bash`, `bun`, `jq`, `python` versions; `loa doctor` (or equivalent) verifies versions on operator install. CI matrix produces a published `dist-checksum.txt` per release; downstream submodule consumers can verify their pinned dist matches the released hash. Reproducibility failure mode: if codegen on operator's machine differs from the released hash, drift gate fails the operator's local PR with structured error directing to the runbook. |

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

### Hybrid Bridgebuilder pattern (FR-1.1, revised v1.1 per Flatline SKP-001)

The hybrid pattern combines **build-time codegen** (for compiled defaults that ship with the framework release) with a **runtime overlay** (for operator-added entries from `model_aliases_extra`).

**Build-time path** (unchanged from v1.0): a Bun script reads `model-config.yaml` at build time, emits TS literal maps for `truncation.generated.ts` and `config.generated.ts`. Generated TS files are committed alongside source (mirrors the `generated-model-maps.sh` pattern). `bun run build` invokes the generator before `tsc`. CI verifies `dist/*.js` matches a fresh build (drift gate).

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

**Runtime overlay path** (new in v1.1): at Bridgebuilder skill init, a small loader reads `.loa.config.yaml::model_aliases_extra` and `.loa.config.yaml::skill_models`, merges them with the compiled tables, and computes truncation entries for any operator-added model:

```typescript
// .claude/skills/bridgebuilder-review/resources/core/runtime-overlay.ts
import { TRUNCATION_DEFAULTS } from './truncation.generated';
import { DEFAULT_MODEL } from '../config.generated';
import { parseLoaConfig } from './config-loader';

export function buildEffectiveTruncation(): TruncationMap {
  const userConfig = parseLoaConfig();
  const effective = new Map(TRUNCATION_DEFAULTS);
  for (const extra of userConfig.model_aliases_extra ?? []) {
    if (effective.has(extra.id)) continue;  // operator-override resolution per FR-3.9 step 1
    effective.set(extra.id, computeTruncationFromContext(extra.context));
  }
  return effective;
}
```

**Truncation computation for operator-added models**: `computeTruncationFromContext()` uses a generic formula based on `context.max_input` + `context.truncation_coefficient` (default `0.20`). Operators may pin per-model truncation by populating `model_aliases_extra.<id>.context.truncation_coefficient` explicitly.

**Resolution order at runtime**: operator override (`skill_models.bridgebuilder.<role>: <provider:id>`) > runtime overlay (`model_aliases_extra` entries) > compiled default (`truncation.generated.ts` + `config.generated.ts`). Mirrors FR-3.9 algorithm.

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

### Deferred decisions to resolve before Sprint 1 (release blockers)

Per Flatline SKP-001 HIGH 760 — `/architect` MUST resolve all of these in the cycle-099 SDD before Sprint 1 implementation begins. Treat as Sprint 1 release blockers; Sprint 1 cannot enter `/run` until each decision is documented in `grimoires/loa/cycles/cycle-099-model-registry/decisions/`.

| ID | Decision | Owner | Deadline | Fallback (if no consensus by deadline) | Sources |
|----|----------|-------|----------|----------------------------------------|---------|
| **DD-1** | `model-permissions.yaml` strategy: Option A (codegen from SoT) vs Option B (merge into `model-config.yaml`). PRD recommendation: B. | deep-name (operator) | `/architect` SDD merge — 48h post-PRD-approval | Default to **Option B** per PRD recommendation; `/architect` adds rationale | FR-1.4, Technical Considerations |
| **DD-2** | `model_aliases_extra` schema field placement: top-level vs nested under `models:` | deep-name (operator) | `/architect` SDD merge — 48h post-PRD-approval | Default to **top-level** (mirrors `protected_classes_extra` pattern from cycle-098 Sprint 1B) | FR-2.1 |
| **DD-3** | `model_aliases_override` field design (override semantics): allowed fields, nesting depth, conflict reporting | deep-name (operator) | `/architect` SDD merge — 72h post-PRD-approval (more design surface) | Default to **partial-merge override** (operator override merges with framework default at field level; explicit fields override; missing fields inherit from default); silent override REJECTED in all cases per IMP-001 | FR-2.3 |
| **DD-4** | FR-1.9 startup hook implementation language: Python vs Node | deep-name (operator) | `/architect` SDD merge — 48h post-PRD-approval | Default to **Python** (cheval is already Python; mirrors loa_cheval extension) | FR-1.9 |
| **DD-5** | FR-2.2 JSON Schema location + ajv adapter language (matches the language chosen for DD-4) | deep-name (operator) | `/architect` SDD merge — same as DD-4 | Schema at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json`; validator language follows DD-4 | FR-2.2 |
|   |   |   |   |   |   |
| **DD-6** *(new v1.2)* | Property-based test runner (FR-3.9): `bats` + simple property generator vs port-fast (Hedgehog/Hypothesis-style) external tool | `/architect` author | Sprint 2 design — 48h post-SDD-merge | Default to **bats + simple bash property generator** (sufficient for deterministic stage-by-stage assertion; 0 new dependencies) | FR-3.9 |

> Sources: operator interview decision (2026-05-04, scope = narrow), conflation-risk callout from operator during interview, **Flatline SKP-001 HIGH (760) — deferred-decisions-as-spec-gaps**.

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
| **SC-9** | **Deterministic resolution algorithm** (FR-3.9) produces consistent output across configs | Golden tests at `tests/integration/model-resolution-golden.bats` cover 10+ scenario configs per skill (Flatline, Red Team, Bridgebuilder, Adversarial Review): each scenario asserts (skill, role) → expected `provider:model_id` AND expected `resolution_path` matches the FR-3.9 algorithm. Per Flatline SKP-002 + IMP-001. |
| **SC-10** | **Failure paths produce structured errors not silent fallback** (FR-3.8) | E2E test: operator binds skill to unmapped tier; system refuses to start with structured error listing unresolved bindings. Per Flatline SKP-004. |
| **SC-11** | **Security test corpus passes** (NFR-Sec-1.1) | `tests/integration/model-aliases-extra-security.bats` covers SSRF + injection + permission-escalation probes; all tests pass. Per Flatline SKP-003 + SKP-004 permissions. |
| **SC-12** | **Bridgebuilder runtime sees operator-added models** (FR-1.1 hybrid) | E2E test: operator adds `gpt-5.7-pro` to `model_aliases_extra`, sets `skill_models.bridgebuilder.gpt_role: gpt-5.7-pro`, restarts; Bridgebuilder logs show operator model in effective config. Per Flatline SKP-001. |
| **SC-13** | **Legacy compatibility golden tests** (per v1.2 Flatline IMP-006 HIGH_CONSENSUS 845) | Golden tests at `tests/integration/legacy-config-golden.bats` cover all 4 existing config shapes: `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model`. Each shape has a representative cycle-098-vintage `.loa.config.yaml` fixture in `tests/fixtures/legacy-configs/`; `model-invoke --validate-bindings` produces the same `provider:model_id` resolution before and after cycle-099 migration code lands. Adds 4+ fixture configs and ~20 assertions. |
| **SC-14** | **Property-based test invariants pass** (per v1.2 Flatline SKP-002) | `tests/property/model-resolution-properties.bats` runs random valid configs through resolution algorithm; all 6 invariants from FR-3.9 hold. ~100 random scenarios per CI run; 0 invariant violations across 1000-iteration stress-test. |

> Sources: G-1..G-5 with measurement criteria, cycle-098 success-criteria pattern.

---

## Risks & Mitigation

| ID | Risk | Severity | Mitigation |
|----|------|----------|------------|
| **R-1** | Bridgebuilder TS dist regeneration breaks existing skill consumers (downstream Loa-mounted projects pin `dist/`) | HIGH | **Strengthened v1.1 per Flatline IMP-003 HIGH_CONSENSUS 785**: (a) Generate `dist/` deterministically in PR; CI verifies dist matches source. (b) **Rollback path**: every cycle-099 release publishes a git tag `cycle-099-dist-v<N>` so downstream submodule consumers can pin a specific dist generation; rollback runbook at `grimoires/loa/runbooks/bridgebuilder-dist-rollback.md` documents `git submodule update --init --reference <previous-tag>` recovery. (c) **Version-comment header**: every generated `dist/` file emits `// Generated from model-config.yaml@<sha>` as the first line for traceability. (d) **Staged gate**: cycle-099 sprint-3 publishes a release-candidate dist as a separate npm-style artifact tag (`@loa/bridgebuilder-dist@cycle099-rc1`) before the cycle-099 final release; downstream consumers can opt-in to the RC for compatibility validation before the cycle-099 default flips. (e) Backward-compat at API surface preserved (only defaults change, not interfaces). |
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
| 2026-05-04 (revised) | Bridgebuilder TS migration = **hybrid (build-time codegen for defaults + runtime YAML overlay for operator-added entries)** | Flatline pass #1 SKP-001 CRITICAL (950) | Build-time alone leaves operator-added models invisible to Bridgebuilder; hybrid closes the gap while preserving compiled-defaults ship pattern |
| 2026-05-04 | NFR-Sec-1 strengthened with provider-specific endpoint allowlist + SSRF blocks + api_id format normalization + security test corpus (NFR-Sec-1.1) | Flatline pass #1 SKP-003 CRITICAL (910) + HIGH (750) | Operator-extensible model definitions create SSRF + injection surface; layered defenses required |
| 2026-05-04 | FR-3.5 strengthened: startup validation refuses launch on unresolved bindings; FR-3.8 added: fail-closed semantics; FR-1.4 adds permissions-elevation rejection | Flatline pass #1 SKP-004 CRITICAL (860) + HIGH (720) | Tier mapping fallback was undefined ("else falls back" without spec); silent fallback masks misconfiguration |
| 2026-05-04 | FR-1.9 added: runtime config consolidation via Python/Node startup hook (decision DD-4); bash adapters source `.run/merged-model-aliases.sh` | Flatline pass #1 SKP-002 HIGH (780) — bash YAML parsing | Bash YAML parsing is fragile; cleaner to dump merged config once at startup |
| 2026-05-04 | FR-3.9 added: deterministic 6-stage resolution algorithm with explicit precedence + conflict errors; SC-9 golden tests | Flatline pass #1 SKP-002 HIGH (780) + IMP-001 (875) — resolution precedence | Multiple overlapping resolution mechanisms (skill_models, aliases, backward_compat, tier_groups, prefer_pro_models, legacy shapes) without deterministic precedence creates inconsistent runtime behavior |
| 2026-05-04 | FR-1.4 / FR-2.1 / FR-2.3 marked release blockers; new "Deferred Decisions" section listing DD-1..DD-5 | Flatline pass #1 SKP-001 HIGH (760) — deferred-decisions-as-spec-gaps | Implementation cannot start cleanly with unresolved spec questions |
| 2026-05-04 | NFR-Op-5 + FR-5.5 added: codegen reproducibility (pinned toolchain + canonical serialization + matrix CI Linux/macOS) | Flatline pass #1 SKP-005 HIGH (720) | Cross-language codegen across Bash/Python/Bun assumes determinism but didn't specify it |
| 2026-05-04 | R-1 strengthened: rollback runbook + version-comment header + dist tag for downstream pinning | Flatline pass #1 IMP-003 HIGH_CONSENSUS (785) | dist regen is a real compatibility hazard; staged rollout reduces blast radius |
| 2026-05-04 | FR-2.2 strengthened: normative JSON Schema published at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (ajv-validated) | Flatline pass #1 IMP-004 HIGH_CONSENSUS (815) | Schema validation needs an exact artifact, not prose |
| 2026-05-04 | FR-5.6 added: `model-invoke --validate-bindings` contract spec (input, output JSON shape, exit codes) | Flatline pass #1 IMP-005 HIGH_CONSENSUS (735) | CLI is referenced in success criteria; needs explicit contract |
| 2026-05-04 (pass #2) | Deferred Decisions table strengthened with Owner / Deadline / Fallback columns; DD-6 added for FR-3.9 property-test runner | Flatline pass #2 SKP-001 CRITICAL (910) — deferred decisions need explicit accountability | Bare deadline isn't enough; missed deadlines need explicit fallback choice to prevent decision-stalling |
| 2026-05-04 (pass #2) | FR-3.4 strengthened: `prefer_pro_models` overlay for legacy shapes is opt-in via `respect_prefer_pro: true` (default false during deprecation window) | Flatline pass #2 SKP-002 CRITICAL (885) — algorithm complexity reframe | Reduces FR-3.9 algorithm state-space for legacy paths without forcing migration |
| 2026-05-04 (pass #2) | FR-3.9 strengthened: property-based tests at `tests/property/model-resolution-properties.bats` covering 6 invariants | Flatline pass #2 SKP-002 CRITICAL (885) | Property-based tests verify algorithm correctness without forcing scope reduction |
| 2026-05-04 (pass #2) | FR-1.9 strengthened: atomic write (`temp + rename(2)`), `flock` shared/exclusive locks, monotonic version header, SHA256-based invalidation under shared lock + exclusive lock for regen, file-missing/parse-error/permission-failure/stale failure modes | Flatline pass #2 SKP-003 HIGH (770) + IMP-003 (835) + IMP-004 (735) | Concurrency / race conditions / startup edge cases were underspecified |
| 2026-05-04 (pass #2) | NFR-Sec-1 strengthened: URL canonicalization (`urlsplit`-style), HTTPS-only + default port enforcement, DNS rebinding defense (resolve-and-verify at request time), redirect denial across trust boundaries, mandatory TLS verification | Flatline pass #2 SKP-004 HIGH (755) | Endpoint allowlist alone bypassed by DNS rebinding / HTTP→HTTPS redirects / canonicalization gaps |
| 2026-05-04 (pass #2) | FR-1.4 strengthened: minimal permissions baseline for operator-added models; explicit System Zone path OR `acknowledge_permissions_baseline: true` flag required | Flatline pass #2 SKP-005 HIGH (730) | Operator-added models without baseline entries had undefined permissions; rejection rule was incomplete |
| 2026-05-04 (pass #2) | DD-3 row in Deferred Decisions strengthened with `model_aliases_override` semantics specification (partial-merge default, explicit fields override, silent override always rejected) | Flatline pass #2 IMP-001 HIGH_CONSENSUS (890) | Override/merge semantics are core to correctness; left undefined creates divergent implementations |
| 2026-05-04 (pass #2) | FR-5.7 added: runtime resolution tracing via `LOA_DEBUG_MODEL_RESOLUTION=1` env var; structured `[MODEL-RESOLVE]` stderr log per resolution | Flatline pass #2 IMP-002 HIGH_CONSENSUS (820) | Pre-flight validation (FR-5.6) is insufficient for runtime debugging in a precedence resolver |
| 2026-05-04 (pass #2) | SC-13 added: legacy compatibility golden tests at `tests/integration/legacy-config-golden.bats` covering all 4 existing config shapes | Flatline pass #2 IMP-006 HIGH_CONSENSUS (845) | PRD promises legacy support; golden tests prevent silent regression |
| 2026-05-04 (pass #2) | SC-14 added: property-based test invariants pass | Flatline pass #2 SKP-002 mitigation | Companion to FR-3.9 property test addition |
| 2026-05-04 (pass #3) | **Kaironic stop declared** at PRD pass #3 (90% agreement, DISPUTED appearing, finding-rotation at finer grain) | Flatline pass #3 plateau analysis | Per cycle-098 PRD v1.4→v1.5 pattern; remaining BLOCKERs are SDD-shape operational refinements |
| 2026-05-04 (pass #3) | NFR-Sec-5 added: credential contract for operator-added models (reuse provider env var; `auth` field rejected; v2 namespacing deferred) | Flatline pass #3 IMP-001 HIGH (865) | Operator-added models implied a credential surface; PRD didn't address; v1 scope clarified to existing-provider env vars only |
| 2026-05-04 (pass #3) | FR-3.7 strengthened: legacy-shape fail-closed exception (deprecation warning + framework-default tier mapping fallback) during cycle-099 window only; new shape always fail-closed | Flatline pass #3 IMP-005 HIGH (845) | Real spec conflict between FR-3.8 fail-closed and SC-7 legacy-compat-no-changes; explicit time-bounded exception resolves the tension |
| 2026-05-04 (pass #3) | 4 SDD-shape findings explicitly deferred to `/architect`: SKP-003 (URL canonicalization edge cases — IPv6/IDN/punycode/port specs), SKP-004 (shell-escape safety in `.run/merged-model-aliases.sh`), SKP-005 (flock semantics over network filesystems), SKP-006 (hybrid BB TS-runtime/runtime-overlay divergence) | Flatline pass #3 BLOCKERs analysis | These are operational refinements appropriate for SDD-level architecture review, not PRD-level scope; will surface in SDD Flatline reviews |
| 2026-05-04 (pass #3) | DISPUTED item recorded but NOT integrated: IMP-004 per-invocation cost forecasts at resolution time (avg 645, delta 330) | Flatline pass #3 disputed-rotation pattern | Cycle-098 disputed-rotation precedent: rotation is signal, not action; defer to operator at SDD if cost-observability emerges as a felt need |
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
| `grimoires/loa/a2a/flatline/cycle-099-prd-review.json` | Flatline pass #1 output: 5 HIGH_CONSENSUS + 9 BLOCKERS, 100% model agreement (Opus + GPT-5.3-codex + Gemini-3.1-pro-preview) |
| `grimoires/loa/a2a/flatline/cycle-099-prd-review-v11.json` | Flatline pass #2 output: 5 HIGH_CONSENSUS + 5 BLOCKERS, 100% model agreement; 4 BLOCKERS closed by v1.1 integration (convergence in progress) |
| `grimoires/loa/a2a/flatline/cycle-099-prd-review-v12.json` | Flatline pass #3 output: 4 HIGH_CONSENSUS + 6 BLOCKERS + 1 DISPUTED, 90% model agreement — kaironic plateau signal (finding-rotation at finer grain, agreement decreasing, DISPUTED emerging). 2 PRD-level themes integrated to v1.3; 4 SDD-shape operational refinements deferred to `/architect`. |
| `grimoires/loa/cycles/cycle-099-model-registry/decisions/02-flatline-prd-review-failure-postmortem-2026-05-04.md` | Flatline-on-cycle-099-PRD failure modes; primary-source evidence for the cycle (the PRD review was failing because of the very registry fragmentation cycle-099 solves) |

---

*This PRD is the cycle-099 charter. Operator approves scope, then `/architect` produces SDD, then `/sprint-plan` produces sprint plan, then `/run sprint-1` begins implementation. Cycle-098's PRD/SDD are preserved at `grimoires/loa/cycles/cycle-098-agent-network/`. Ledger activation (transition `active_cycle` to `cycle-099-model-registry`) is a separate chore step after PRD approval, matching the cycle-098 #679 pattern.*
