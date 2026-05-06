# ADR-001 — Model-Registry Consolidation (Cycle-099)

| Status | Decided |
| --- | --- |
| Date | 2026-05-06 (cycle-099 finalized in v1.130.0) |
| Deciders | @janitooor, cycle-099 PRD/SDD authors, Flatline Protocol pass #1-#3 reviewers |
| Tags | model-registry, resolver, cross-runtime-parity, codegen, FR-3.9 |
| Supersedes | (none — first ADR) |
| Related | cycle-095 (model currency), cycle-098 (audit envelope) |

## Context

Pre-cycle-099, model selection in Loa was scattered across three layers that could drift independently:

1. **Framework defaults** at `.claude/defaults/model-config.yaml` — the source-of-truth for provider entries, aliases, and per-skill agent bindings.
2. **Operator overrides** at `.loa.config.yaml::aliases` — flat key/value overrides operators applied on top of framework defaults.
3. **Per-adapter associative arrays** — `model-adapter.sh`, `red-team-model-adapter.sh`, `model-resolver.sh`, the bridgebuilder TypeScript runtime overlay (`config.generated.ts`), persona docs (`# model: ...` headers), and the Python cheval `loa_cheval` config loader. Each maintained its own lookup tables.

A change in any one location risked silent drift from the others. Multiple incidents in cycles 086, 091, 095 traced back to this drift surface — for example, a model retired upstream would still resolve in one adapter but not another, producing inconsistent agent behavior across the framework.

Issue [#710](https://github.com/0xHoneyJar/loa/issues/710) flagged this as a tier-1 problem after operator @aussie-loa-evaluator filed a "subscription-auth headless adapter" feature request that exposed how many places needed touching for what should be a simple "add a new model" change.

## Decision

Cycle-099 redraws the boundary so that **`.claude/defaults/model-config.yaml` plus `.loa.config.yaml::{model_aliases_extra, skill_models, tier_groups}` becomes the only authoritative model registry**. All other model-mentioning artifacts become either:

1. **Generated** from the SoT at build time (Bridgebuilder TypeScript runtime overlay → codegen), or
2. **Tier-tag references** that resolve against the SoT at runtime (Red Team bash, persona docs).

A single canonical resolver — `.claude/scripts/lib/model-resolver.py`, implementing the FR-3.9 6-stage algorithm — replaces ad-hoc lookups. Cross-runtime parity is enforced by a CI gate that runs the same resolver in three languages and asserts byte-equal canonical-JSON output.

### Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │  SoT (cycle-099 single authoritative surface) │
                    │                                                │
                    │  .claude/defaults/model-config.yaml            │
                    │  .loa.config.yaml::model_aliases_extra         │
                    │  .loa.config.yaml::skill_models                │
                    │  .loa.config.yaml::tier_groups                 │
                    │  .loa.config.yaml::prefer_pro_models           │
                    └───────────┬──────────────────────────────┬─────┘
                                │                              │
                       ┌────────┴───────┐              ┌───────┴────────┐
                       │  Build time     │              │  Runtime        │
                       │                 │              │                 │
                       │  • TS codegen   │              │  • Python:      │
                       │    (Bridge-     │              │    canonical    │
                       │     builder)    │              │    resolver     │
                       │  • Lockfile     │              │  • Bash:        │
                       │    (drift gate) │              │    runtime      │
                       │                 │              │    overlay      │
                       │                 │              │    .run/merged- │
                       │                 │              │    aliases.sh   │
                       │                 │              │  • TypeScript:  │
                       │                 │              │    codegen-     │
                       │                 │              │    output       │
                       └────────┬────────┘              └────────┬────────┘
                                │                                 │
                                └──────────────┬──────────────────┘
                                               │
                                ┌──────────────┴──────────────┐
                                │  Cross-runtime-diff CI gate   │
                                │  Python ↔ bash ↔ TS           │
                                │  byte-equal canonical JSON    │
                                │  on every PR                  │
                                └───────────────────────────────┘
```

### The 6-stage resolver (FR-3.9)

Operators specify model selection at multiple layers; the resolver disambiguates with deterministic precedence:

| Stage | Source | Action |
|---|---|---|
| **S1** | `skill_models.<skill>.<role>: <provider:model_id>` | Explicit pin — always wins |
| **S2** | `skill_models.<skill>.<role>: <tier-or-alias>` | Tier cascades to S3; alias resolves directly via `framework_aliases ∪ model_aliases_extra` |
| **S3** | `tier_groups.mappings.<tier>.<provider>` | Operator mapping checked first, then framework default |
| **S4** | `<skill>.models.<role>: <alias>` (legacy) | FR-3.7 deprecation-warn fallback |
| **S5** | `framework_defaults.agents.<skill>.{model, default_tier}` | Framework default for the skill |
| **S6** | `prefer_pro_models: true` | POST-resolution overlay; retargets resolved alias to `*-pro` variant if one exists. Per-skill `respect_prefer_pro: true` required for legacy-shape skills (FR-3.4) |

Output: `{provider, model_id, resolution_path: [stage_outcomes]}` on success, `{error: {code, stage_failed, detail}}` on failure. Schema-pinned at `.claude/data/trajectory-schemas/model-resolver-output.schema.json`.

### Cross-runtime canonicalization

The resolver runs in three languages because three runtimes need it:
- **Python** — cheval startup hook + resolver tooling.
- **Bash** — `model-adapter.sh`, `red-team-model-adapter.sh`, etc. (production: source `.run/merged-model-aliases.sh`; test: independent re-implementation in `tests/bash/golden_resolution.sh` for parity verification).
- **TypeScript** — Bridgebuilder runtime overlay (latency-critical hot path; cannot fork Python per call).

Python is the **canonical reference**. Bash and TypeScript are projections:
- Bash production runtime sources `.run/merged-model-aliases.sh` (built by the Python startup hook).
- TypeScript runtime is **build-time generated** from canonical Python via Jinja2 codegen (`emit_model_resolver_ts`). Drift gate enforces `committed.generated.ts == fresh codegen output` + source-content SHA-256 cross-check.

Cross-runtime byte-equality is enforced by a CI gate (`.github/workflows/cross-runtime-diff.yml`) that runs the same fixture corpus through all 3 runners and asserts byte-equal canonical-JSON output.

## Alternatives considered

### A. Three independent reimplementations (status quo, rejected)

Continue letting each runtime maintain its own resolver. Pro: no codegen complexity. Con: drift surface that cycle-099 was specifically created to eliminate. Multiple historical incidents trace to this. **Rejected** as the failure mode the cycle is designed to fix.

### B. Single Python implementation, runtime-shell-out (rejected)

Bash and TS shell out to `python3 -m model_resolver` per resolution. Pro: zero drift by construction. Con: violates FR-3.9 latency budget (<100µs per resolution; subprocess fork is ~10ms). **Rejected** for the Bridgebuilder TS hot path; acceptable for bash where it ships as the production overlay-build step.

### C. Hand-written TS resolver with parity tests (rejected)

Author the TS resolver by hand and rely on cross-runtime fixture tests to catch divergence. Pro: simpler tooling. Con: per-feature edits require manual TS port + risk of subtle JS-vs-Python parser confusion. Sprint-1E.c.1 review caught **2 CRITICAL allowlist bypasses** (URL constructor percent-decoding `%2E` → `.`; Unicode dot equivalents) in a hand-written TS validator that fixture tests had passed — proving fixture-only parity isn't sufficient. **Rejected** in favor of codegen.

### D. Codegen with text-diff drift gate (chosen variant — rejected without hash cross-check)

Codegen TS from Python via Jinja2; drift gate compares committed `.generated.ts` against fresh codegen output via byte-diff. Pro: catches "forgot to regenerate". Con: misses tampered-canonical-with-matching-regen scenarios. **Augmented** with source-content SHA-256 cross-check (forces operator review of any canonical edit).

### E. Codegen + hash cross-check + property tests (CHOSEN)

Codegen produces deterministic TS from canonical Python; drift gate checks byte-diff AND embedded source-hash; **property-based tests** (Sprint 2D.d, deferred) verify cross-runtime output equivalence on ~100 random valid configs per PR + 1000-iter nightly stress. **Adopted**. Property tests close the gap that fixture-only parity left open.

## Trade-offs accepted

### Python availability dependency

The bash overlay-build step and the TS build step both require Python 3.11+ to run the canonical resolver. If Python is unavailable, the Bash and TS production runtimes degrade gracefully (cached overlay file from previous build is sourced; codegen output is committed and shipped without re-build). Build-time CI catches Python failures before they reach operators.

**Cited**: SDD §1.5.1 SKP-002 acknowledgement — *"Cycle-099 explicitly accepts the Python dependency in exchange for elimination of resolver drift across 3 runtimes."*

### Codegen complexity

Adding Jinja2 codegen + drift gate + source-hash cross-check is more infrastructure than hand-writing TS. The complexity is one-time (the codegen pattern is now reused for any future Python-canonical-with-TS-projection module). Sprint-1E.c.1 (endpoint validator) and Sprint-2D.c (model resolver) both use the same emit-module pattern; future TS ports inherit the cost amortization.

### Backward compatibility surface

Cycle-095 alias shape (`aliases:` at config root) is preserved via FR-3.9 stage 4 with deprecation-warn fallback. This means the resolver carries one extra stage forever (until a future cycle deprecates it explicitly). Pre-cycle-095 schema migration tool (`loa-migrate-model-config.py`) helps operators upgrade at their own pace.

### Per-skill `respect_prefer_pro` per FR-3.4

`prefer_pro_models` overlay is automatic for new-shape skills (`skill_models.X.Y`) but per-skill opt-in for legacy-shape skills (`<skill>.models.<role>`). This isolates the overlay surprise to migrated skills only and reduces FR-3.9 algorithm state-space for legacy paths. Cited: SDD pass #2 SKP-002 CRITICAL 885 — algorithm-complexity scope reduction.

## Outcomes (verified at v1.130.0 milestone)

- **17 cycle-099 PRs** shipped between 2026-05-05 and 2026-05-06 (Sprint 1A → 2D.c).
- **All 15 production HTTP caller paths** route through the centralized endpoint validator. Strict CI scanner blocks future raw curl/wget bypasses.
- **3-way cross-runtime parity gate** active on every PR touching the resolver. Catches Python/bash/TS divergence before merge.
- **21/21 framework agents** resolve cleanly via the canonical Python resolver against the production `.claude/defaults/model-config.yaml` (smoke-tested in CI).
- **45 Sprint 2D bats** (16 per-runner contract pins + 27 cross-runtime parity + 2 latency micro-bench) on the resolver test surface.
- **~778 cumulative cycle-099 bats** on main; 0 sentinel regressions.

## Open questions / follow-ups

1. **Sprint 2D.d** (deferred): SC-14 property suite — 6 invariants × ~100 random configs verified continuously. Closes T2.6 entirely.
2. **Sprint 2E** (deferred): `tier_groups.mappings` probe-confirmed defaults + `prefer_pro_models` operator-config wiring (T2.7+T2.8).
3. **`model-adapter.sh.legacy` SSRF migration** (deferred): the legacy-mode adapter path is exempt from sprint-1E SSRF wrapper migration. Sprint 4 sunset will retire this path entirely.
4. **CHANGELOG backfill of v1.110.0 → v1.128.x** (deferred): GitHub Releases carry per-tag detail; the v1.130.0 named release rolls them into a single milestone entry.

## Refs

- [PRD](../../grimoires/loa/cycles/cycle-099-model-registry/prd.md) — requirements
- [SDD](../../grimoires/loa/cycles/cycle-099-model-registry/sdd.md) — system design
- [Sprint plan](../../grimoires/loa/cycles/cycle-099-model-registry/sprint.md)
- [RESUMPTION](../../grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md) — session-resumption brief
- [Migration guide](../migration/v1.130-cycle-099-model-registry.md)
- Issue [#710](https://github.com/0xHoneyJar/loa/issues/710) — problem statement
- PR range [#722](https://github.com/0xHoneyJar/loa/pull/722) → [#741](https://github.com/0xHoneyJar/loa/pull/741) — incremental shipped commits
