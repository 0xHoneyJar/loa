# Software Design Document: Model Registry Consolidation + Per-Skill Granularity

**Version:** 1.1 (Flatline pass #1 integration: 3 HIGH_CONSENSUS + 6 BLOCKERS resolved at 100% model agreement)
**Date:** 2026-05-04
**Author:** Architecture Designer (Claude Opus 4.7 1M)
**Status:** Draft — Flatline pass #1 integrated; ready for `/sprint-plan` after operator review (pass #2 optional convergence verification).
**Cycle:** `cycle-099-model-registry`
**PRD Reference:** `grimoires/loa/cycles/cycle-099-model-registry/prd.md` (v1.3, kaironic plateau at pass #3)
**Source issue:** [#710](https://github.com/0xHoneyJar/loa/issues/710)

> **v1.0 → v1.1 changes** (Flatline pass #1, `grimoires/loa/a2a/flatline/cycle-099-sdd-review.json`, Opus + GPT-5.3-codex + Gemini-3.1-pro-preview, 100% model agreement):
> - **SKP-001 (CRITICAL 910) integrated** — §10 Open Questions closed: tiny-tier uses cycle-095's `tiny` alias; endpoint_family is operator-set per entry (no overrideable framework default); permissions optional with NFR-Sec-5 minimal baseline default.
> - **SKP-002 (CRITICAL 890) integrated** — §7.X Cross-Runtime Golden Test Corpus; all 3 runtimes (Python/Bash/TS) consume identical fixture corpus in CI matrix.
> - **SKP-003 (HIGH 770) integrated** — §6.5 URL canonicalization simplified: 9-step → 8-step; Levenshtein homoglyph defense REMOVED in favor of strict normalized-host-matching against allowlist.
> - **SKP-004 (HIGH 740) integrated** — §6.3/§6.6: degraded read-only fallback default; `LOA_OVERLAY_STRICT=1` opt-in for fail-closed; stale-lock recovery via `kill -0` PID check; new NFR-Op-6 documents degraded mode contract.
> - **SKP-002 (HIGH 720) integrated** — §3.1.1: `schema_version: 2` top-level field; `migrate_v1_to_v2()` auto-upgrade; permissions wrapper deletion deferred from cycle-100 to cycle-101 MINIMUM.
> - **SKP-005 (HIGH 710) integrated** — §3.1.1 rollback path: `LOA_LEGACY_MODEL_PERMISSIONS=1` triggers one-way sync; pre-commit hook + CI guard reject manual model-permissions.yaml edits; `[LEGACY-MODE-DUAL-WRITE]` structured error.
> - **IMP-001 (HIGH_CONSENSUS 865) integrated** — §6.3: lock acquisition order (shared first; upgrade if write needed); timeouts (5s shared, 30s exclusive); env-var configurable via `LOA_OVERLAY_LOCK_TIMEOUT_*_MS`.
> - **IMP-002 (HIGH_CONSENSUS 860) integrated** — New §5.X (or NFR-Sec-X): Debug Trace + JSON Output Secret Redactor; URL userinfo + query-string secret patterns; applied to FR-5.7 + FR-5.6 + FR-1.9 generated diagnostics.
> - **IMP-004 (HIGH_CONSENSUS 765) integrated** — §3.1.X + JSON Schema: `model_aliases_extra` ADDS new IDs (`oneOf` rejects framework-default collisions); `model_aliases_override` MODIFIES existing IDs (requires framework-default ID); mutually exclusive at entry level.

> **What this SDD adds beyond the PRD**
>
> The PRD v1.3 reached kaironic plateau with 6 deferred decisions (DD-1..DD-6) and 4 SDD-shape operational refinements (SKP-003..SKP-006) explicitly handed to `/architect`. This SDD resolves all of them with rationale, citations, and concrete schemas. Where the PRD said "decide between A and B", this SDD says "B, here is the schema, here is the migration step, here is the test fixture path". Where the PRD said "URL canonicalization is SDD-shape", this SDD specifies the exact parser, the exact rejection rules, and the test corpus.
>
> The SDD also introduces:
> - A **stage-numbered resolver state machine** (Mermaid `stateDiagram-v2`) reifying FR-3.9
> - A **codegen pipeline** (Mermaid `flowchart`) showing build-time + runtime overlay touch points
> - A **merged-aliases.sh shape spec** with shell-escape rules (resolves SKP-004)
> - A **flock-over-NFS hardening table** (resolves SKP-005)
> - A **Bridgebuilder hybrid divergence detection contract** (resolves SKP-006)
> - **DD-1 Option B merger schema** showing how cycle-026 7-dim trust_scopes coexist with model-config.yaml capabilities
>
> Sprint plan (`/sprint-plan` next phase) will consume this SDD plus the PRD to produce 4 sprint briefs. SDD does NOT lock model-permissions.yaml deletion — it specifies the merge-but-thin-wrapper path so Sprint 3 has a concrete migration target while preserving rollback.

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Data Model: model-config.yaml + model_aliases_extra + skill_models](#3-data-model-model-configyaml--model_aliases_extra--skill_models)
4. [Operator UX: `.loa.config.yaml` Schema Surface](#4-operator-ux-loaconfigyaml-schema-surface)
5. [API & CLI Specifications](#5-api--cli-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases (Sprint Decomposition Hints)](#8-development-phases-sprint-decomposition-hints)
9. [Known Risks and Mitigation (SDD-level additions)](#9-known-risks-and-mitigation-sdd-level-additions)
10. [Resolved Open Questions](#10-resolved-open-questions-sprint-2-release-blockers--closed-by-flatline-sdd-pass-1-skp-001-critical-910)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 System Overview

Cycle-099 is a **registry-consolidation + operator-extension** cycle. There is no new runtime service, no new HTTP surface, no new database. The deliverable is a redrawn boundary: `.claude/defaults/model-config.yaml` plus `.loa.config.yaml::{model_aliases_extra, skill_models, tier_groups}` becomes the **only authoritative model registry** in the framework. All other model-mentioning artifacts (Bridgebuilder TS, Red Team bash, persona docs, protocol docs, model-permissions.yaml) become either (a) generated artifacts derived from the SoT or (b) tier-tag references that resolve against the SoT at runtime.

> From PRD §Executive Summary: "Cycle-099 finishes the job [cycle-095 began]: extends SoT coverage to all remaining consumers (Bridgebuilder TypeScript, Red Team bash adapter, `model-permissions.yaml`, persona docs, protocol docs), adds an operator-facing config extension mechanism (`model_aliases_extra`), introduces per-skill tier-tag granularity composing with cycle-095's `tier_groups`, and sunsets the legacy bash adapter." (`prd.md:82`)

The architecture is a **codegen-and-runtime-overlay pipeline** with a deterministic precedence resolver. Three operating modes coexist:

1. **Build-time codegen** — at framework release, `gen-adapter-maps.sh` (existing, cycle-095) and new `gen-bb-registry.ts` and new `gen-model-permissions.sh` (DD-1 Option B keeps the .yaml emitted as a compat artifact during cycle-099) read `model-config.yaml` and emit committed artifacts (`generated-model-maps.sh`, `dist/truncation.generated.ts`, `dist/config.generated.ts`, `model-permissions.generated.yaml`).
2. **Runtime startup hook** — at Loa startup, a Python helper (DD-4 resolution) reads `model-config.yaml` ∪ `.loa.config.yaml::model_aliases_extra` and writes `.run/merged-model-aliases.sh` (mode 0600) for bash adapters to source.
3. **Per-resolution tracing** — when an agent asks "what model should `flatline_protocol.primary` use?", a 6-stage deterministic resolver (FR-3.9) walks operator config → operator tier-mappings → framework tier-mappings → legacy shape → framework default → `prefer_pro_models` overlay. Each stage emits structured tracing under `LOA_DEBUG_MODEL_RESOLUTION=1`.

### 1.2 Architectural Pattern

**Pattern:** Codegen-derived single-source-of-truth + runtime overlay + deterministic precedence resolver.

This is NOT a microservices/event-driven/serverless decision — there is no service surface to make. The pattern decision is **where the truth lives** (one YAML file under cycle-095 + cycle-099 schema extensions) and **how it propagates** (build-time codegen for shipped artifacts; runtime overlay for operator-added entries; deterministic resolver for the per-call lookup).

**Justification:**

| Alternative considered | Why rejected |
|------------------------|--------------|
| Pure runtime YAML reads (no codegen) | Forces every framework consumer to import a YAML parser. The Bridgebuilder TS skill ships compiled JS — adding a runtime YAML parser inflates dist size and adds a dependency the skill currently doesn't need. PRD `prd.md:51-52` rejected this for Bridgebuilder. |
| Pure build-time codegen (no runtime overlay) | Operator-added models in `model_aliases_extra` would be invisible to the Bridgebuilder dist that shipped *before* the operator added the model. PRD Flatline pass #1 SKP-001 CRITICAL (950) caught this gap; the hybrid pattern was the integration. (`prd.md:33` v0→v1.1 changes) |
| New runtime service (model-resolver-daemon) | YAGNI. PRD `prd.md:246` explicitly rejects hot-reload as v1 scope. Restart-to-apply is acceptable; a daemon adds operational surface without solving an actual operator problem. |
| `model-permissions.yaml` stays a separate hand-maintained file (DD-1 Option C) | Re-introduces drift surface. PRD `prd.md:108` lists model-permissions.yaml as registry #10 of 13. Cycle-099 G-3 ("zero drift") forbids this. |

**Pattern shape** (cycle-098 §1.2 callback): the same "build-time generated artifacts + runtime extension + deterministic precedence" pattern that L1-L7 audit primitives use. Cycle-099 reuses the structure, swapping audit-envelope for model-resolution.

### 1.3 Component Diagram

```mermaid
flowchart TB
  subgraph SoT[Source of Truth]
    YAML[".claude/defaults/model-config.yaml<br/>(extended Sprint 3 with .permissions per-model<br/>per DD-1 Option B)"]
  end

  subgraph OperatorZone[Operator Zone — .loa.config.yaml]
    EXTRA[model_aliases_extra<br/>skill_models<br/>tier_groups.mappings overrides]
  end

  subgraph BuildTime[Build-Time Codegen]
    GEN_SH[gen-adapter-maps.sh<br/>cycle-095 existing]
    GEN_TS[gen-bb-registry.ts<br/>cycle-099 Sprint 1 new]
    GEN_PERM[gen-model-permissions.sh<br/>cycle-099 Sprint 3 new<br/>DD-1 Option B]
  end

  subgraph CommittedArtifacts[Committed Generated Artifacts]
    MAPS_SH["generated-model-maps.sh<br/>(bash arrays)"]
    TRUNC_TS["dist/truncation.generated.ts<br/>+ dist/config.generated.ts"]
    PERM_YAML["model-permissions.generated.yaml<br/>(thin wrapper)"]
    LOCKFILE["model-config.yaml.checksum<br/>(SHA256 lockfile)"]
  end

  subgraph Runtime[Runtime — agent startup]
    HOOK[".claude/scripts/lib/model-overlay-hook.py<br/>cycle-099 Sprint 2 new (DD-4 Python)"]
    MERGED[".run/merged-model-aliases.sh<br/>mode 0600, atomic-write,<br/>flock-guarded, version+SHA256 header"]
  end

  subgraph Resolvers[Per-Resolution Path — FR-3.9]
    BASH_ADAPTER["model-adapter.sh<br/>(sources merged.sh)"]
    BB_OVERLAY["bridgebuilder runtime-overlay.ts<br/>(merges compiled + extra)"]
    CHEVAL["cheval.py<br/>(reads merged config)"]
  end

  subgraph Consumers[Skills + Skills-internal Consumers]
    FL[Flatline]
    RT[Red Team]
    BB[Bridgebuilder]
    AR[Adversarial Review]
    GR[gpt-review]
  end

  YAML --> GEN_SH --> MAPS_SH
  YAML --> GEN_TS --> TRUNC_TS
  YAML --> GEN_PERM --> PERM_YAML
  YAML --> LOCKFILE

  YAML --> HOOK
  EXTRA --> HOOK
  HOOK --> MERGED

  MAPS_SH --> BASH_ADAPTER
  MERGED --> BASH_ADAPTER
  TRUNC_TS --> BB_OVERLAY
  EXTRA --> BB_OVERLAY
  YAML --> CHEVAL
  EXTRA --> CHEVAL

  BASH_ADAPTER --> RT
  BASH_ADAPTER --> FL
  BB_OVERLAY --> BB
  CHEVAL --> FL
  CHEVAL --> AR
  CHEVAL --> GR
```

### 1.4 System Components

#### 1.4.1 SoT: `.claude/defaults/model-config.yaml`

- **Purpose:** Authoritative registry for providers, models, aliases, backward-compat aliases, agents, tier_groups.
- **Responsibilities (cycle-099 additions):**
  - Holds per-model `permissions` field (DD-1 Option B; cycle-026 7-dim `trust_scopes` schema preserved as nested map under `.permissions.trust_scopes`).
  - Holds populated `tier_groups.mappings` for `max`, `cheap`, `mid`, `tiny` (Sprint 2 task — replaces cycle-095's empty mapping).
  - Holds per-skill default tier mapping under existing `agents.<skill_name>` (extended to declare `default_tier` instead of bare `model:` for skills migrated to tier-shape).
- **Interfaces:** Read-only YAML; consumed by all four codegen scripts + Python startup hook + cheval runtime + Bridgebuilder runtime overlay.
- **Dependencies:** None upstream. Hand-maintained by framework maintainer.

#### 1.4.2 Operator extension: `.loa.config.yaml::{model_aliases_extra, skill_models, tier_groups}`

- **Purpose:** Operator-facing zero-System-Zone-edit extension surface.
- **Responsibilities:**
  - `model_aliases_extra: { schema_version, entries: [ModelExtra] }` — top-level (DD-2) schema-versioned object whose `entries` list mirrors SoT `providers.<p>.models.<id>` shape, plus reuse of provider's existing credential env var (NFR-Sec-5).
  - `skill_models: Map[skill_name, Map[role_name, tier_or_model_ref]]` — per-skill per-role tier or explicit model spec.
  - `tier_groups.mappings: Map[tier_name, Map[provider, model_ref]]` — operator overrides of framework default tier mapping.
- **Interfaces:** Schema-validated at config load via JSON Schema at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (DD-5). Strict-mode loader rejects unknown top-level fields; cycle-099 adds these three to the allowlist.
- **Dependencies:** Cycle-095's strict-mode loader; cycle-098's `protected_classes_extra` precedent for the operator-extension pattern.

#### 1.4.3 Codegen scripts

- **`gen-adapter-maps.sh`** (cycle-095, existing) — emits 4 bash arrays. Cycle-099 Sprint 1 adds support for `endpoint_family` consumption (currently unused at the bash layer) so Sprint 2's runtime hook has parity with the build-time generator.
- **`gen-bb-registry.ts`** (cycle-099 Sprint 1, new) — Bun script. Reads `model-config.yaml`, emits `truncation.generated.ts` + `config.generated.ts` under `resources/core/` and `resources/`.
- **`gen-model-permissions.sh`** (cycle-099 Sprint 3, new — DD-1 Option B path) — emits `model-permissions.generated.yaml` as a thin compatibility wrapper for any tooling still reading the standalone file. Sprint 3 starts the deletion clock; cycle-100 deletes the wrapper.

#### 1.4.4 Runtime overlay hook: `model-overlay-hook.py`

- **Purpose:** Read merged config (SoT ∪ operator extras), write `.run/merged-model-aliases.sh` for bash consumers.
- **Implementation language:** Python (DD-4 fallback default). Cheval is already Python; this hook lives at `.claude/scripts/lib/model-overlay-hook.py` and reuses cheval's PyYAML import.
- **Concurrency:** flock-exclusive on `.run/merged-model-aliases.sh.lock` for write; flock-shared for reader verification of version mismatch (FR-1.9).
- **Atomic write:** writing to `${TMPDIR:-/tmp}` is forbidden (cross-filesystem `rename(2)` is non-atomic) — write to `.run/merged-model-aliases.sh.tmp.<pid>.<random>` in the same directory as the final file, then `os.rename()` to final path.
- **Permission:** `chmod 0600` on the temp file BEFORE `rename()` (avoids a brief world-readable window).
- **Failure modes:** see §6.3.

#### 1.4.5 Bridgebuilder runtime overlay: `runtime-overlay.ts`

- **Purpose:** Merge compiled (codegen) defaults with `.loa.config.yaml::model_aliases_extra` at Bridgebuilder skill init.
- **Truncation computation for operator-added models:** see §3.4.
- **Divergence detection (resolves SKP-006):** see §1.4.6.

#### 1.4.6 Hybrid divergence detector (resolves PRD SKP-006)

> From PRD `prd.md:632`: "SKP-006 (hybrid BB TS-runtime/runtime-overlay divergence) — These are operational refinements appropriate for SDD-level architecture review."

The hybrid pattern (compiled-defaults + runtime-overlay) introduces a **dual-source consistency hazard**: the compiled `truncation.generated.ts` and the runtime-computed `effective.truncation` could diverge if a model exists in both `model-config.yaml` (compiled default) AND `model_aliases_extra` (operator override) but with conflicting `context_window` / `truncation_coefficient`. PRD FR-3.9 step 1 says explicit operator override wins absolutely; but the COMPILED truncation table has no operator-override awareness.

**SDD specification:**
- `runtime-overlay.ts` builds the effective table by SHALLOW-COPYING compiled defaults, then APPLYING operator overrides per-key (per FR-2.3). The compiled table is treated as immutable input.
- After overlay, a **divergence audit** runs: for every key K where `COMPILED[K]` exists AND `OPERATOR_EXTRA[K]` exists with a different shape, emit a structured `[BB-OVERLAY-OVERRIDE]` log line at INFO level with `compiled_value`, `effective_value`, and the `resolution_path` (always "stage-1-pin" for this case). This is a one-time-per-process emission per overridden key — not per resolution.
- Test contract: `tests/integration/bb-runtime-overlay-divergence.bats` constructs a fixture where `gpt-5.5` exists in compiled defaults with `context_window: 400000` and operator overrides it to `300000`. Test asserts (a) effective table reports `300000`; (b) `[BB-OVERLAY-OVERRIDE]` log line emitted; (c) no second emission on subsequent resolutions of the same key.

### 1.5 Data Flow: Resolution Path (FR-3.9 reified)

```mermaid
stateDiagram-v2
  [*] --> S1
  state "S1: explicit provider:model_id in skill_models" as S1
  state "S2: tier-tag in skill_models, lookup operator tier_groups.mappings" as S2
  state "S3: tier-tag in skill_models, lookup framework tier_groups.mappings" as S3
  state "S4: legacy shape (flatline_protocol.models.X / etc)" as S4
  state "S5: framework default agents.skill_name.{model,default_tier}" as S5
  state "S6: prefer_pro_models overlay (gated for legacy by respect_prefer_pro)" as S6
  state "RESOLVED: provider:model_id" as RESOLVED
  state "FAIL_CLOSED: refuse to start" as FAIL_CLOSED
  state "DEPRECATION_WARN_FALLBACK: emit warning + use S5 default" as DEPRECATION_WARN_FALLBACK

  S1 --> RESOLVED: explicit pin matched
  S1 --> S2: no explicit pin

  S2 --> S6: operator mapping resolved (then check S6 overlay)
  S2 --> S3: no operator mapping for (tier, provider)

  S3 --> S6: framework mapping resolved (then check S6 overlay)
  S3 --> FAIL_CLOSED: no framework mapping AND new shape (FR-3.8)
  S3 --> S4: no framework mapping AND legacy shape allowed

  S4 --> RESOLVED: legacy alias matched (emit FR-3.7 deprecation warning)
  S4 --> DEPRECATION_WARN_FALLBACK: legacy unresolved (FR-3.7 cycle-099 exception only)

  S5 --> S6: framework default present (then check S6 overlay)
  S5 --> FAIL_CLOSED: no framework default for skill

  DEPRECATION_WARN_FALLBACK --> S5

  S6 --> RESOLVED: prefer_pro_models off OR overlay applied OR not applicable
```

**State legend (corresponds to FR-3.9 stages 1-6):**
- **S1** (FR-3.9 step 1) — explicit pin always wins
- **S2** (FR-3.9 step 2) — operator-set tier mapping
- **S3** (FR-3.9 step 3) — framework default tier mapping
- **S4** (FR-3.9 step 4) — legacy shape, deprecation-warn path
- **S5** (FR-3.9 step 5) — framework `agents.<skill>` default
- **S6** (FR-3.9 step 6) — `prefer_pro_models` overlay (POST-resolution, may retarget the resolved ID to its `*-pro` variant)

**Conflict resolution (PRD FR-3.9):**
- (1) and (4) both present → (1) wins. No silent tiebreaker.
- Two same-priority mechanisms (e.g., explicit pin AND tier-tag in same `skill_models.<skill>.<role>` block) → schema-level rejection at load time, not runtime.

### 1.6 External Integrations

| Service | Purpose | API | Notes |
|---------|---------|-----|-------|
| OpenAI API | Chat completions, code generation | REST `https://api.openai.com/v1` | Endpoint allowlist enforced (FR-2.8); `api_id` format `^[a-zA-Z0-9._-]+$` |
| Anthropic API | Chat, thinking traces | REST `https://api.anthropic.com` | Same allowlist + format constraints |
| Google Generative AI | Chat, deep research | REST `https://generativelanguage.googleapis.com/v1beta` | Wildcard `*.googleapis.com` permitted; subdomain hijack hardening per §1.9 |
| AWS Bedrock | Claude via Bedrock | REST `bedrock-runtime.{region}.amazonaws.com` | Region tokenized in allowlist; FR-2.8 enforces whole-host match per region |
| Cheval (loa_cheval Python adapter) | Multi-provider routing | Python module | Reads `model-config.yaml` + `model_aliases_extra` |

### 1.7 Deployment Architecture

Cycle-099 is purely framework-side. Deployment = git push to operator's repo; Loa picks up changes on next agent startup. There is no service deployment, no infrastructure cost, no operational telemetry beyond the existing Loa hooks.

The ONLY new deployment artifact is the **Bridgebuilder dist tag** (PRD R-1 risk mitigation): each cycle-099 release publishes a git tag `cycle-099-dist-v<N>` so downstream submodule consumers can pin a specific dist generation for compatibility validation before flipping defaults. Sprint 3 produces an RC tag (`@loa/bridgebuilder-dist@cycle099-rc1`) before the cycle-099 final release.

### 1.8 Scalability Strategy

Resolution-time complexity:
- **FR-3.9 algorithm** is O(1) per (skill, role) lookup — direct map indexing through six in-memory tables.
- **Startup hook** runs once per agent invocation; no streaming, no incremental update.
- **Framework size**: ~50 framework-default models, expected operator-added models ≤20 in practice. Total resolution table size ≤70 entries; fits in any cache.

Per-resolution overhead under tracing (FR-5.7) is <2ms (logging-only). Per-resolution overhead without tracing is <100µs (six map lookups + one optional overlay check).

Performance budget verification: NFR-Perf-1 says "<50ms p95 startup overhead". The Python hook reads two YAMLs (~30KB each) + writes ~10KB bash file under flock. Realistic measurement target: 15ms median, 35ms p95 on `ubuntu-latest`. Sprint 1 ships a microbenchmark in `tests/perf/model-overlay-hook-bench.bats`.

### 1.9 Security Architecture

**Threat model** (extends PRD NFR-Sec-1):

| Threat | Surface | Mitigation |
|--------|---------|------------|
| SSRF via operator-supplied `endpoint` | `model_aliases_extra.<id>.endpoint` | Provider allowlist (FR-2.8); localhost / IMDS / RFC 1918 blocked; HTTPS-only; default-port enforcement |
| DNS rebinding | Resolved IP at request time differs from load time | Re-resolve at request time (FR-2.8 implementation); reject IP-rebound to blocked range with `[ENDPOINT-DNS-REBOUND]` |
| HTTP redirect across trust boundary | Provider returns 302 to attacker-controlled host | Reject same-host-only; structured `[ENDPOINT-REDIRECT-DENIED]` |
| Command injection via `api_id` | Operator embeds shell metacharacters | `api_id` format `^[a-zA-Z0-9._-]+$` enforced at JSON Schema layer |
| Permission elevation | Operator declares `permissions: high` | FR-1.4 baseline rejection + `acknowledge_permissions_baseline: true` opt-in |
| Credential surface expansion | Operator-defined `auth` field | NFR-Sec-5 v1: `auth` field rejected; only existing provider env vars used |
| Plaintext at rest in `.run/merged-model-aliases.sh` | World-readable file leaks tokens (no — this file holds NO secrets, only model IDs + endpoints + pricing) | mode 0600 BEFORE rename; secrets remain in env vars only |
| Path traversal via `id` | Operator embeds `../` in model id | Schema rejects |
| URL canonicalization edge cases (resolves SKP-003) | IPv6 literals, IDN/punycode, port specs | See §6.5 detailed rules |
| Shell-escape safety in `.run/merged-model-aliases.sh` (resolves SKP-004) | Operator id contains shell metachar; bash sourcing executes attacker code | See §3.5 quoting rules |
| flock semantics over network filesystems (resolves SKP-005) | NFS/SMB flock is advisory + may be lost during failover | Detect filesystem type; refuse to write merged.sh on non-local fs unless `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` (operator must opt in with eyes open) |

The security architecture is **defense-in-depth at four points**: (1) JSON Schema rejection at config-load (NFR-Sec-1); (2) startup hook validation (FR-1.9 fail-closed); (3) per-request DNS re-verification (NFR-Sec-1 v1.2); (4) shell-escape audit at `.run/merged-model-aliases.sh` write time (§3.5 + §7.4 NFR-Sec-1.1 corpus).

---

## 2. Software Stack

Cycle-099 introduces no new framework dependencies beyond what Loa already ships. Every component below is already required by some existing skill.

### 2.1 Build-time Toolchain (cycle-099 reuses existing)

| Category | Technology | Version | Justification |
|----------|------------|---------|---------------|
| YAML loader (cycle-095) | yq (Mike Farah) | ≥ v4.40 | Already required by `gen-adapter-maps.sh`. Cycle-099 reuses for codegen reproducibility (FR-5.5). |
| Bash | GNU Bash | ≥ 5.0 | Existing requirement. Pinned via `.tool-versions`. |
| Bun (Bridgebuilder) | bun | 1.1.x (specific minor pinned) | Already a Bridgebuilder dependency. Cycle-099 adds `gen-bb-registry.ts` under same toolchain. |
| TypeScript | tsc via Bun | 5.9.x | Same. |
| Python | CPython | ≥ 3.11 | Already required by cheval. Cycle-099 adds `model-overlay-hook.py` under same runtime. |
| YAML library (Python) | PyYAML | ≥ 6.0 | Already required by cheval. |
| JSON Schema validator | ajv (TS) and jsonschema (Python) | ajv 8.x; jsonschema ≥ 4.21 | ajv for build-time TS validation; jsonschema for Python startup hook (DD-5 follows DD-4). |
| `jq` | jq | ≥ 1.7 | Already required by `gen-adapter-maps.sh`. |
| `flock` (Linux) | util-linux | ≥ 2.36 | Already required by event-bus.sh + cycle-098 audit_emit pattern. macOS uses `brew install util-linux`. |

### 2.2 Test Runners

| Category | Technology | Version | Justification |
|----------|------------|---------|---------------|
| Bats (shell tests) | bats-core | ≥ 1.10 | Already used; cycle-099 ships `tests/property/`, `tests/integration/legacy-config-golden.bats`, etc. |
| Bats helpers | bats-assert + bats-support | latest | Already vendored. |
| Bash property generator | Custom (DD-6 fallback default) | n/a | Sprint 2 ships ~150-line bash helper at `tests/property/lib/property-gen.bash` that emits N random valid configs. Sufficient for FR-3.9's deterministic invariants per cycle-098 SKP-002 mitigation pattern. **0 new dependencies**. |
| Node test (Bridgebuilder) | tsx --test | latest | Already used; cycle-099 adds `bb-runtime-overlay-divergence.bats` (bash) + `runtime-overlay.test.ts` (Node). |
| Python test (Sprint 2 hook) | pytest | ≥ 8 | Already required by cheval test suite. |

### 2.3 CI/CD

| Category | Technology | Purpose |
|----------|------------|---------|
| GitHub Actions | `model-registry-drift.yml` (new Sprint 1) | Runs codegen + diff vs committed artifacts. Exit non-zero on divergence. |
| GitHub Actions matrix | `ubuntu-latest` + `macos-latest` | NFR-Op-5 reproducibility check; codegen must produce byte-identical output across both. |
| Existing CI | `bedrock-contract-smoke.yml` | Already running cycle-098 audit-envelope tests; cycle-099 adds nothing here. |

### 2.4 No New Application Code Stack

Cycle-099 does NOT introduce: a frontend framework, a backend service framework, a database, a cache provider, a queue, a CDN, a container runtime, an orchestrator, or any cloud-vendor service. The PRD §"Out of Scope" line 497 ("Multi-tenant model billing isolation — Not in #710 scope; separate concern") confirms this scope is purely framework-internal. Application-stack questions in the SDD template (§4 UI Design, etc.) are **adapted below to framework-internal equivalents** (CLI/operator UX surface; framework-internal data shape).

---

## 3. Data Model: model-config.yaml + model_aliases_extra + skill_models

### 3.1 SoT shape (cycle-099 additions to cycle-095 shape)

The cycle-095 `model-config.yaml` schema already exists. Cycle-099 adds:

#### 3.1.1 Per-model `permissions` field (DD-1 Option B integration)

> **DD-1 resolution: Option B** (merge permissions into `model-config.yaml`). Rationale: (a) PRD recommendation; (b) eliminates a registry per G-3 zero-drift; (c) `model-permissions.yaml` cycle-026 7-dim `trust_scopes` schema is RICHER than cycle-095 model schema — it adds `data_access`, `financial`, `delegation`, `model_selection`, `governance`, `external_communication`, `context_access` per-model, which are **per-model attributes** not provider attributes (unlike `endpoint` and `auth`). Per-model placement is correct.

The new shape per `providers.<provider>.models.<id>`:

```yaml
providers:
  openai:
    models:
      gpt-5.5-pro:
        capabilities: [chat, tools, function_calling, code]
        context_window: 400000
        token_param: max_completion_tokens
        endpoint_family: responses
        pricing:
          input_per_mtok: 30000000
          output_per_mtok: 180000000
        # cycle-099 NEW FIELD — DD-1 Option B
        permissions:
          trust_level: medium
          trust_scopes:
            data_access: none
            financial: none
            delegation: none
            model_selection: none
            governance: none
            external_communication: none
            context_access:
              architecture: full
              business_logic: redacted
              security: none
              lore: full
          execution_mode: remote_model
          capabilities:
            file_read: false
            file_write: false
            command_execution: false
            network_access: false
          notes: >
            Used for Flatline Protocol adversarial review and Bridgebuilder.
```

**Schema versioning (resolves Flatline SDD pass #1 SKP-002 HIGH 720):**

`model-config.yaml` gains a top-level `schema_version: 2` field at the cycle-099 boundary (cycle-095 used implicit version 1). The merged schema now has two evolution vectors (cycle-026 permissions + cycle-095 model attrs); explicit versioning enables atomic migration when either evolves.

```yaml
# .claude/defaults/model-config.yaml
schema_version: 2                          # cycle-099 NEW — bumps from implicit 1
providers:
  openai:
    models:
      gpt-5.5-pro:
        # ... per-model fields including permissions block (DD-1 Option B)
```

- **Loader behavior** (cheval Python loader and Bridgebuilder TS loader):
  - `schema_version: 2` → load directly.
  - `schema_version: 1` (or absent) → invoke `migrate_v1_to_v2()` (Python loader only; TS loader rejects v1 with deprecation pointer to Python migration). The migration auto-promotes old shape to new; emits one-time stderr WARN `[CONFIG-SCHEMA-V1-DEPRECATED] migrating in-memory; persist via 'loa doctor model --migrate'`.
  - `schema_version: 3+` (future) → reject with `[CONFIG-SCHEMA-VERSION-UNSUPPORTED]` (exit 78). Forward-incompatibility is fail-closed.
- **`migrate_v1_to_v2()` contract** (`.claude/scripts/lib/model-overlay-hook.py`): pure function; takes parsed v1 dict, returns parsed v2 dict; no I/O; idempotent (calling with v2 input is a no-op). Unit test: `tests/unit/migrate-v1-to-v2.py.test`.

**Migration path (Sprint 3):**
1. `gen-model-permissions.sh` reads SoT `providers.<p>.models.<id>.permissions` and emits `model-permissions.generated.yaml` matching the cycle-026 `model_permissions:` top-level shape (key = `<provider>:<model_id>`, value = the permissions block).
2. The standalone `model-permissions.yaml` becomes a generated artifact during cycle-099 (operator/tooling reads still work).
3. **Wrapper deletion deferred from cycle-100 to cycle-101 MINIMUM** (resolves Flatline SDD pass #1 SKP-002 HIGH 720). Rationale: provides ≥1 cycle of stable migration before one-way-door deletion; allows rollback via `LOA_LEGACY_MODEL_PERMISSIONS=1` to remain valid for at least one full cycle. Migration runbook at `grimoires/loa/runbooks/model-permissions-removal.md` (Sprint 3 deliverable) reflects the cycle-101 schedule.

**Rollback path (resolves Flatline SDD pass #1 SKP-005 HIGH 710):** when `LOA_LEGACY_MODEL_PERMISSIONS=1` is set (operator opts back into separate hand-maintained `model-permissions.yaml`), the system enforces **one-way sync semantics** — `model-config.yaml` is the SOLE writer; `model-permissions.yaml` is regenerated derived. Direct operator edits to `model-permissions.yaml` are rejected:

| Guard | Mechanism | Error |
|-------|-----------|-------|
| Pre-commit hook | `.claude/hooks/legacy-mode-dual-write.sh` checks if `model-permissions.yaml` was modified manually when `LOA_LEGACY_MODEL_PERMISSIONS=1` is set in environment | `[LEGACY-MODE-DUAL-WRITE]` exit 1 |
| CI guard | `.github/workflows/legacy-mode-drift.yml` regenerates `model-permissions.yaml` from `model-config.yaml`; diff fails the PR | `[LEGACY-MODE-DUAL-WRITE]` PR check fail |
| Reverse-sync NOT supported | `model-permissions.yaml` → `model-config.yaml` propagation is forbidden in legacy mode | rejected at load with same code |

**One-way semantics**: `model-config.yaml` CAN be edited; `model-permissions.yaml` is regenerated each commit; reverse-sync NOT supported in legacy mode. Drift alarm catches any manual edit to the derived file. Documented in `grimoires/loa/runbooks/model-permissions-removal.md` "Rollback section". This closes the cycle-099 G-3 (zero-drift) regression that vanilla rollback would have introduced (PRD pass #2 SKP-005 HIGH 710).

#### 3.1.2 `tier_groups.mappings` populated (Sprint 2)

Cycle-095 ships `tier_groups.mappings: {}` (empty). Cycle-099 Sprint 2 populates:

```yaml
tier_groups:
  mappings:
    max:
      anthropic: opus              # → claude-opus-4-7 (resolves via aliases)
      openai: gpt-5.5-pro          # top-of-OpenAI per probe-confirmation
      google: gemini-3.1-pro       # → gemini-3.1-pro-preview
    cheap:
      anthropic: cheap             # → claude-sonnet-4-6
      openai: gpt-5.3-codex        # cost-safe codex tier
      google: gemini-3-flash       # → gemini-3-flash-preview
    mid:
      anthropic: cheap             # same as cheap during cycle-099 (sonnet is the mid choice)
      openai: gpt-5.5
      google: gemini-2.5-pro
    tiny:
      anthropic: tiny              # → claude-haiku-4-5-20251001
      openai: gpt-5.3-codex        # no smaller OpenAI in registry (open question §10)
      google: gemini-3-flash
  denylist: []                     # operator opt-out (unchanged)
  max_cost_per_session_micro_usd: null
```

**Probe verification (Sprint 2 task):** every default mapping above is verified via `model-health-probe.sh` (cycle-095 pattern). PR cannot land if any default mapping resolves to UNAVAILABLE.

#### 3.1.3 `agents.<skill_name>.default_tier` (Sprint 2)

Cycle-095's `agents` entries declare `model:` directly. Cycle-099 extends to declare `default_tier:` (preferred for new skills; `model:` retained for back-compat).

```yaml
agents:
  flatline-reviewer:
    default_tier: cheap            # cycle-099 NEW (preferred)
    # model: reviewer              # cycle-095 LEGACY (retained, but unused if default_tier present)
    temperature: 0.3
  red-team-attacker:               # cycle-099 NEW skill binding
    default_tier: cheap
    temperature: 0.4
  bridgebuilder-opus-reviewer:     # cycle-099 NEW skill binding
    default_tier: max
  bridgebuilder-gpt-reviewer:
    default_tier: max
  bridgebuilder-gemini-reviewer:
    default_tier: cheap
```

**FR-3.9 stage 5 lookup** uses `default_tier` if present; falls back to `model:` if not.

### 3.2 `model_aliases_extra` JSON Schema (DD-2 + DD-5 resolution)

> **DD-2 resolution:** top-level (mirrors `protected_classes_extra` from cycle-098 Sprint 1B).
> **DD-5 resolution:** schema at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (path locked); validator language Python (jsonschema 4.21+) per DD-4 fallback. ajv-TS validator at `.claude/skills/bridgebuilder-review/resources/core/runtime-overlay.ts` for the Bridgebuilder side.

Schema (excerpt; full file at `.claude/data/trajectory-schemas/model-aliases-extra.schema.json`):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "loa://schemas/model-aliases-extra/v1.0.0",
  "title": "Operator-defined model aliases (cycle-099 model_aliases_extra)",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version"],
  "properties": {
    "schema_version": {
      "const": "1.0.0",
      "description": "Bumped on breaking schema changes."
    },
    "entries": {
      "type": "array",
      "items": { "$ref": "#/$defs/ModelExtra" }
    }
  },
  "$defs": {
    "ModelExtra": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "provider", "api_id", "capabilities", "context_window", "pricing"],
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[a-zA-Z0-9._-]+$",
          "minLength": 2,
          "maxLength": 64,
          "description": "FR-2.8 normalization. Rejects shell metacharacters, path separators, nullbytes."
        },
        "provider": {
          "type": "string",
          "enum": ["openai", "anthropic", "google", "bedrock"],
          "description": "NFR-Sec-4: new provider types require System Zone change."
        },
        "api_id": {
          "type": "string",
          "pattern": "^[a-zA-Z0-9._-]+$",
          "minLength": 1,
          "maxLength": 128
        },
        "endpoint_family": {
          "type": "string",
          "enum": ["chat", "responses", "messages", "converse"]
        },
        "endpoint": {
          "type": "string",
          "format": "uri",
          "description": "OPTIONAL — defaults to provider's framework default. If supplied, must match provider's allowed_endpoints in loa.defaults.yaml."
        },
        "capabilities": {
          "type": "array",
          "minItems": 1,
          "items": { "enum": ["chat", "tools", "function_calling", "code", "thinking_traces", "deep_research"] }
        },
        "context_window": {
          "type": "integer",
          "minimum": 1024,
          "maximum": 10000000
        },
        "token_param": {
          "type": "string",
          "enum": ["max_tokens", "max_completion_tokens"]
        },
        "pricing": {
          "type": "object",
          "additionalProperties": false,
          "required": ["input_per_mtok", "output_per_mtok"],
          "properties": {
            "input_per_mtok": { "type": "integer", "minimum": 0 },
            "output_per_mtok": { "type": "integer", "minimum": 0 }
          }
        },
        "context": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "max_input": { "type": "integer", "minimum": 1024 },
            "truncation_coefficient": { "type": "number", "minimum": 0.05, "maximum": 0.95 }
          }
        },
        "permissions": {
          "$ref": "loa://schemas/model-permissions-baseline/v1.0.0",
          "description": "OPTIONAL. If absent, FR-1.4 minimal-baseline applies. If present, validated against framework provider baseline."
        },
        "acknowledge_permissions_baseline": {
          "type": "boolean",
          "description": "FR-1.4: explicit operator opt-in to minimal-only permissions for this entry."
        },
        "auth": false
      },
      "allOf": [
        {
          "if": { "not": { "required": ["permissions"] } },
          "then": { "required": ["acknowledge_permissions_baseline"] }
        }
      ]
    }
  }
}
```

**Notes on the schema:**
- `auth: false` at the property level forbids operator-supplied credentials (NFR-Sec-5).
- The `allOf` clause forces operators with no `permissions` block to set `acknowledge_permissions_baseline: true` (FR-1.4 v1.2 hardening).
- `endpoint` is OPTIONAL — most operators inherit the provider's framework default endpoint and don't supply this field.

### 3.3 `model_aliases_override` shape (DD-3 resolution)

> **DD-3 resolution:** **partial-merge override** (PRD fallback default). Rationale: (a) PRD §"Deferred Decisions" `prd.md:510` already locked this fallback if no consensus; (b) full override (replace-the-entire-block) creates a hidden trap where forgetting one field silently inherits provider default, which is worse than partial-merge with explicit-fields-win; (c) silent override REJECTED per IMP-001.

Schema:

```yaml
# .loa.config.yaml
model_aliases_override:
  - id: gpt-5.3-codex                  # MUST exist in framework defaults
    pricing:
      input_per_mtok: 1500000          # operator's contracted rate
      output_per_mtok: 13000000
    # capabilities, context_window, token_param: INHERITED from framework default
```

**Semantics:**
- `id` MUST match an existing framework default (per `providers.<p>.models.<id>`). If `id` is unknown, reject at load with `[OVERRIDE-UNKNOWN-MODEL]`.
- Only specified fields override; unspecified fields inherit from the framework default. Field-level merge depth: 2 (e.g., overriding only `pricing.input_per_mtok` keeps `pricing.output_per_mtok` from framework default).
- Conflict reporting: at load time, emit one structured INFO log per overridden model: `[OVERRIDE-APPLIED] id=<id> fields=[pricing.input_per_mtok, pricing.output_per_mtok]`.
- `model_aliases_override` and `model_aliases_extra` are TWO DIFFERENT fields with TWO DIFFERENT semantics. `extra` adds new entries; `override` modifies existing. Operator that wants both adds both blocks.
- `endpoint` MAY be overridden via `model_aliases_override` (rare — operator routing through enterprise proxy) but the override target MUST still pass FR-2.8 endpoint allowlist. If it fails, reject at load.
- `permissions` MAY NOT be overridden via `model_aliases_override` for any framework-default model — that's a System Zone concern (FR-1.4). Reject at load with `[OVERRIDE-PERMISSIONS-FORBIDDEN]`.

**Explicit precedence — `model_aliases_extra` vs `model_aliases_override` (resolves Flatline SDD pass #1 IMP-004 HIGH_CONSENSUS 765):**

The two fields have **mutually exclusive entry-level semantics**, enforced at the JSON Schema layer:

| Field | Semantic | Schema-level enforcement | Rejection |
|-------|----------|--------------------------|-----------|
| `model_aliases_extra` | ADDS a new model ID (must NOT collide with framework defaults) | `oneOf` clause: if entry's `id` matches any framework-default ID, reject | `[MODEL-EXTRA-COLLIDES-WITH-DEFAULT]` |
| `model_aliases_override` | MODIFIES an existing framework-default model (must collide; "override" is meaningless on a non-existent ID) | Schema requires `id` to match a framework-default ID; otherwise reject | `[OVERRIDE-UNKNOWN-MODEL]` |

**Mutually exclusive at the entry level** — operator CANNOT put the same ID in both fields. Cross-field validation rejects with `[MODEL-EXTRA-OVERRIDE-CONFLICT]`. The validator constructs the framework-default ID set once at startup (from `providers.*.models.*` keys), then for every entry in `model_aliases_extra` and `model_aliases_override` checks the membership constraint. Operators wanting BOTH "modify pricing on framework default X" AND "add new model Y" use BOTH blocks, with X only in `override` and Y only in `extra`.

**JSON Schema clause (excerpt; full schema in §3.2):**
```json
"model_aliases_extra.entries[]": {
  "allOf": [
    {
      "not": {
        "properties": {
          "id": { "enum": ["<framework_default_id_1>", "<framework_default_id_2>", "..."] }
        }
      }
    }
  ]
},
"model_aliases_override.entries[]": {
  "properties": {
    "id": { "enum": ["<framework_default_id_1>", "<framework_default_id_2>", "..."] }
  }
}
```

The `enum` values are populated at validator-init time from the parsed framework-default registry (the schema is dynamic-context, not a static JSON file — generated from `model-config.yaml` parsed structure before validation). Test corpus at `tests/integration/extra-vs-override-precedence.bats` constructs three failure modes: (1) `extra` ID collides with framework default; (2) `override` ID is not in framework defaults; (3) same ID in both — all three exit 78 with the appropriate structured code.

This closes the operator-mistake surface where placing an ID in the wrong field would silently produce different semantics than intended (DD-3 originally said `extra` and `override` were two-different-fields-two-different-semantics; this Flatline integration makes the schema enforce it rather than relying on operator discipline).

### 3.4 Truncation computation for operator-added models

The Bridgebuilder runtime overlay needs a truncation coefficient for every model in scope. Compiled defaults (from `model-config.yaml` codegen) cover framework-default models; operator-added models need a runtime computation.

**Formula:**
```typescript
function computeTruncationFromContext(extra: ModelExtra): TruncationEntry {
  const ctx_window = extra.context_window;
  const max_input = extra.context?.max_input ?? Math.floor(ctx_window * 0.75);
  const truncation_coefficient = extra.context?.truncation_coefficient ?? 0.20;
  return {
    max_input,
    truncation_coefficient,
    // safety margin for response: assume 25% of context_window for output
    output_budget: Math.floor(ctx_window * 0.25),
  };
}
```

**Justification of defaults:**
- 0.75 max_input ratio: matches the cycle-076 Bridgebuilder convention of reserving 25% of context for output.
- 0.20 truncation coefficient default: matches `claude-opus-4-7` framework default observed in `truncation.ts`. Not optimal for all models but produces sane behavior pre-tuning.
- Operators can override BOTH via `model_aliases_extra.<id>.context.{max_input, truncation_coefficient}`.

### 3.5 `.run/merged-model-aliases.sh` shape (resolves SKP-004)

> From PRD `prd.md:632`: "SKP-004 (shell-escape safety in `.run/merged-model-aliases.sh`)"

The runtime hook writes a bash file consumed by `model-adapter.sh` and Red Team scripts via `source`. Naive variable interpolation could allow operator-supplied model IDs to inject shell code — even though the JSON Schema constrains `id` and `api_id` to `^[a-zA-Z0-9._-]+$`, defense-in-depth requires the bash file ALSO assume hostile input.

**File contents shape:**
```bash
# Generated by .claude/scripts/lib/model-overlay-hook.py at <ISO8601>
# version=42
# source-sha256=<sha256-of-merged-yaml>
# DO NOT EDIT — regenerate via `loa-overlay-hook regen`

declare -gA LOA_MODEL_PROVIDERS=(
  [opus]="anthropic"
  [reviewer]="openai"
  [reasoning]="openai"
  # ... operator-added entries appended below
  [my-custom-model]="openai"
)

declare -gA LOA_MODEL_IDS=(
  [opus]="claude-opus-4-7"
  [reviewer]="gpt-5.5"
  [reasoning]="gpt-5.5"
  [my-custom-model]="gpt-5.7-pro"
)

declare -gA LOA_MODEL_ENDPOINT_FAMILIES=(
  [opus]="messages"
  [reviewer]="responses"
  [my-custom-model]="responses"
)

declare -gA LOA_MODEL_COST_INPUT_PER_MTOK=(
  [opus]="5000000"
  [reviewer]="5000000"
  [my-custom-model]="40000000"
)

declare -gA LOA_MODEL_COST_OUTPUT_PER_MTOK=(
  [opus]="25000000"
  [reviewer]="30000000"
  [my-custom-model]="200000000"
)

# Resolution-trace fingerprint (FR-5.7 enabled when LOA_DEBUG_MODEL_RESOLUTION=1)
LOA_OVERLAY_FINGERPRINT="<sha256-truncated-to-12>"
```

**Shell-escape rules (SDD-level enforcement):**
1. The Python writer NEVER interpolates operator strings into `.sh` content via f-strings or `+`. It uses `shlex.quote()` per value and asserts post-quoting that the result is a single-quoted bash literal containing only `[a-zA-Z0-9._-]` plus the surrounding quote chars.
2. Keys (alias names) are validated by JSON Schema BEFORE writer touches them. If a key contains anything outside `^[a-zA-Z0-9._-]+$`, abort with `[MERGED-ALIASES-WRITE-FAILED]`.
3. Values for COST fields MUST match `^[0-9]+$`. Schema enforces `integer minimum: 0`; writer asserts the type matches before formatting.
4. Numerical values are emitted UNQUOTED per bash array literal convention; non-numerical values are emitted in DOUBLE quotes, where bash recognizes `[a-zA-Z0-9._-]` as no-expansion characters. Empty values forbidden.
5. The writer emits a final `_LOA_OVERLAY_VALIDATE_ASSERTS` line invoking the validator on every entry; if any value contains `$`, `` ` ``, `\`, `\n`, `\r`, abort.
6. Test corpus at `tests/integration/merged-aliases-shell-escape.bats` constructs a fixture where the schema-bypassing reaches the writer (simulated via a debug flag) — writer rejects, asserts non-zero exit. Probe values: `; rm -rf`, `$(touch /tmp/pwned)`, `\` `\n`, ` `, `'`, `"`. **All probes MUST exit 1 with structured error** before any disk write.

### 3.6 Per-skill `skill_models` data shape

```yaml
# .loa.config.yaml — top-level
skill_models:
  flatline_protocol:
    primary: max
    secondary: max
    tertiary: max
  red_team:
    primary: cheap
  bridgebuilder:
    opus_role: max
    gpt_role: max
    gemini_role: cheap
  adversarial_review:
    primary: max
  gpt_review:
    primary: gpt-5.5-pro             # explicit pin (FR-3.9 stage 1)
    secondary: cheap                 # tier (stage 2/3)
```

**Validation (FR-3.5 + FR-3.8):**
- For each `<skill>.<role>` entry, resolution at load-time MUST produce a concrete `provider:model_id`. If unresolvable, refuse to start.
- Mixed mode (FR-3.6): per-role independence is structural — `bridgebuilder.opus_role: max` and `bridgebuilder.gpt_role: max` are independent decisions.

### 3.7 Migration of existing config shapes (FR-3.7)

Existing `.loa.config.yaml` shapes (from cycle-098-vintage configs):

| Legacy shape | Effective new shape |
|--------------|---------------------|
| `flatline_protocol.models.{primary, secondary, tertiary}: <model_ref>` | Continue working with deprecation warning; resolve via FR-3.9 stage 4. |
| `bridgebuilder.multi_model.models[].{provider, model_id, role}` | Continue working; resolve via FR-3.9 stage 4. Per-array-element fail-closed in stage 4 unless cycle-099 deprecation exception (FR-3.7). |
| `gpt_review.models.{primary, secondary}: <model_ref>` | Continue working with deprecation warning. |
| `adversarial_review.model: <model_ref>` | Continue working with deprecation warning. |
| `spiral.executor_model` / `spiral.advisor_model` | Out of cycle-099 scope; continue working unchanged. |

**Deprecation telemetry:** every legacy resolution emits `[LEGACY-SHAPE-RESOLVED]` to stderr (one INFO log per process per (skill, role) tuple). `model-invoke --validate-bindings` aggregates count for visibility.

---

## 4. Operator UX: `.loa.config.yaml` Schema Surface

(SDD template's §4 UI Design adapted to framework-internal operator UX.)

### 4.1 Configuration Surface Overview

The operator's primary edit surface is `.loa.config.yaml`. Cycle-099 adds three top-level fields and one nested override:

| Field | Path | Required | Cycle-099 sprint |
|-------|------|----------|------------------|
| `model_aliases_extra` | top-level | Optional | Sprint 2 |
| `model_aliases_override` | top-level | Optional | Sprint 2 |
| `skill_models` | top-level | Optional | Sprint 2 |
| `tier_groups.mappings` | nested | Optional (inherits framework) | Sprint 2 |
| `legacy_shapes_fail_closed` | top-level | Optional, default false | Sprint 2 (cycle-100 default flip) |

### 4.2 Worked operator examples

#### 4.2.1 UC-1 — adopt newly-released model (PRD use case)

```yaml
# .loa.config.yaml
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: gpt-5.7-pro
      provider: openai
      api_id: gpt-5.7-pro
      endpoint_family: responses
      capabilities: [chat, tools, function_calling, code]
      context_window: 256000
      pricing:
        input_per_mtok: 40000000
        output_per_mtok: 200000000
      acknowledge_permissions_baseline: true   # explicit minimal-only opt-in

skill_models:
  flatline_protocol:
    primary: gpt-5.7-pro              # explicit pin (FR-3.9 stage 1)
```

#### 4.2.2 UC-2 — per-skill cost/quality tradeoff (PRD use case)

```yaml
skill_models:
  flatline_protocol:
    primary: max
    secondary: max
    tertiary: max
  red_team:
    primary: cheap
```

This is the **canonical 5-line operator config** PRD §"Goals" Goal G-2 names ("≤10 lines for 'flatline max + red team cheap + bridgebuilder mixed'"). Bridgebuilder mixed adds 4 more lines:

```yaml
  bridgebuilder:
    opus_role: max
    gpt_role: max
    gemini_role: cheap
```

Total: 9 lines. SC-3 verified.

### 4.3 Page (file) structure (operator-config tour)

```
.loa.config.yaml
|-- existing fields (cycle-095 and earlier)
|   |-- hounfour.flatline_routing
|   |-- flatline_protocol.models.{primary,secondary,tertiary}     # legacy shape
|   |-- bridgebuilder.multi_model.models[]                        # legacy shape
|   `-- ...
|-- model_aliases_extra                                          # NEW Sprint 2
|-- model_aliases_override                                       # NEW Sprint 2
|-- skill_models                                                 # NEW Sprint 2
`-- tier_groups.mappings                                         # NEW Sprint 2 (extends cycle-095 schema)
```

### 4.4 Component architecture (config loader internals)

```mermaid
flowchart TD
  A["Read .loa.config.yaml"] --> B["Strict-mode loader<br/>cycle-095 SDD §1.4.5"]
  B --> C{"Top-level fields<br/>recognized?"}
  C -->|No| F1["FAIL_CLOSED<br/>[CONFIG-UNKNOWN-FIELD]"]
  C -->|Yes| D["JSON Schema validate<br/>model_aliases_extra"]
  D --> E{"Schema valid?"}
  E -->|No| F2["FAIL_CLOSED<br/>[MODEL-EXTRA-INVALID]"]
  E -->|Yes| G["NFR-Sec-1 endpoint allowlist check"]
  G --> H{"Allowed?"}
  H -->|No| F3["FAIL_CLOSED<br/>[ENDPOINT-NOT-ALLOWED]"]
  H -->|Yes| I["Permission baseline check (FR-1.4)"]
  I --> J{"Acknowledged or system-zone?"}
  J -->|No| F4["FAIL_CLOSED<br/>[PERMISSIONS-NOT-ACKNOWLEDGED]"]
  J -->|Yes| K["Merge with framework SoT"]
  K --> L["Validate skill_models bindings"]
  L --> M{"All resolve?"}
  M -->|No| F5["FAIL_CLOSED<br/>[BINDING-UNRESOLVED]"]
  M -->|Yes| N["Write .run/merged-model-aliases.sh"]
  N --> O["Agent runtime ready"]
```

### 4.5 Responsive Design (cross-platform)

Cycle-099 doesn't have a UI but it does have **cross-platform behavior** (Linux + macOS):

| Concern | Linux | macOS |
|---------|-------|-------|
| `flock` (FR-1.9) | util-linux native | requires `brew install util-linux` (existing requirement from cycle-098) |
| `rename(2)` atomic | yes (same filesystem) | yes (same filesystem) |
| `os.rename()` Python | atomic on same filesystem | atomic on same filesystem |
| File mode 0600 | works | works |
| Codegen reproducibility (FR-5.5) | required | required |
| flock over network filesystems | NFS: advisory; can be lost on failover | SMB: advisory; can be lost on disconnect |

### 4.6 Accessibility (operator clarity)

- Every error message has a `code` and `remediation_url` pointing to `grimoires/loa/runbooks/<error-code>.md`.
- `model-invoke --validate-bindings --verbose` produces a human-readable resolution trace (mirrors AWS CLI `--debug` pattern).
- `LOA_DEBUG_MODEL_RESOLUTION=1` env var enables per-resolution stderr trace per FR-5.7.

### 4.7 State management (config caching)

Config is read ONCE at agent startup. There is no in-process re-read; mutations require restart (FR-2.5 YAGNI rejection of hot-reload). The cache is the merged config in-memory for the agent lifetime.

`.run/merged-model-aliases.sh` is the file-system cache of the merged config for shell consumers. It is rewritten by the startup hook on every agent invocation (modulo SHA256-equal short-circuit; see §6.3).

---

## 5. API & CLI Specifications

### 5.1 Design Principles

- **CLI-first**: all operator interaction is via `model-invoke`, `gen-adapter-maps.sh`, and `loa doctor` (cycle-095 idiom).
- **Exit codes**: `0` success, `1` operational error, `2` usage error, `3` drift detected, `78` config error (`EX_CONFIG`).
- **Output formats**: default human-readable; `--format json` for machine consumption; structured stderr for diagnostics.

### 5.2 `model-invoke --validate-bindings` (FR-5.6 contract)

#### Request

```bash
model-invoke --validate-bindings [--format json|text] [--verbose] [--config <path>]
```

#### Behavior

- Reads effective merged config (framework defaults + `model_aliases_extra` + `skill_models` + `tier_groups.mappings`).
- For each `(skill, role)` pair declared in framework `agents.<skill_name>` AND/OR operator `skill_models`, runs the FR-3.9 6-stage resolver.
- Emits one record per pair.
- Makes ZERO API calls (dry-run).

#### Response (default JSON format)

```json
{
  "schema_version": "1.0.0",
  "command": "validate-bindings",
  "exit_code": 0,
  "summary": {
    "total_bindings": 24,
    "resolved": 24,
    "unresolved": 0,
    "legacy_shape_warnings": 3
  },
  "bindings": [
    {
      "skill": "flatline_protocol",
      "role": "primary",
      "resolved_provider": "openai",
      "resolved_model_id": "gpt-5.5-pro",
      "resolution_path": [
        {"stage": 1, "outcome": "miss", "label": "stage1_pin_check"},
        {"stage": 2, "outcome": "miss", "label": "stage2_tier_lookup_operator"},
        {"stage": 3, "outcome": "hit", "label": "stage3_tier_lookup_default"},
        {"stage": 6, "outcome": "applied", "label": "stage6_prefer_pro_overlay", "details": {"retargeted_from": "gpt-5.5"}}
      ],
      "tracing_fingerprint": "abc123def456"
    }
  ]
}
```

#### Exit codes

| Code | Meaning |
|------|---------|
| `0` | All bindings resolve cleanly |
| `1` | At least one unresolved binding (FR-3.8 violation) |
| `78` | Config error (`EX_CONFIG`): schema-invalid `model_aliases_extra`, unknown override target, etc. |
| `2` | Usage error (e.g., unknown `--format` value) |

### 5.3 Codegen scripts CLI

#### `gen-adapter-maps.sh` (cycle-095, extended)

```bash
gen-adapter-maps.sh                  # write generated-model-maps.sh
gen-adapter-maps.sh --check          # exit 3 if stale
gen-adapter-maps.sh --dry-run        # emit to stdout
gen-adapter-maps.sh --output <path>  # custom output
gen-adapter-maps.sh --reproducible   # NFR-Op-5: byte-stable output for CI matrix
```

#### `gen-bb-registry.ts` (cycle-099 Sprint 1, NEW)

```bash
bun run gen-bb-registry              # via Bridgebuilder package.json scripts
bun run gen-bb-registry --check      # exit 3 if stale
bun run gen-bb-registry --output-dir <path>
```

Default output: `.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts` + `.claude/skills/bridgebuilder-review/resources/config.generated.ts`.

#### `gen-model-permissions.sh` (cycle-099 Sprint 3, NEW — DD-1 Option B)

```bash
gen-model-permissions.sh             # emit model-permissions.generated.yaml
gen-model-permissions.sh --check     # exit 3 if stale vs SoT
```

Default output: `.claude/data/model-permissions.generated.yaml` (new). The standalone `model-permissions.yaml` becomes a generated artifact during cycle-099; deletion scheduled for cycle-100.

### 5.4 Startup hook CLI: `model-overlay-hook` (cycle-099 Sprint 2, NEW)

```bash
# Default: regenerate .run/merged-model-aliases.sh if stale
.claude/scripts/lib/model-overlay-hook.py

# Force regen (bypass SHA256 short-circuit)
.claude/scripts/lib/model-overlay-hook.py --force

# Validate without writing
.claude/scripts/lib/model-overlay-hook.py --check  # exit 0/3

# Verbose trace
.claude/scripts/lib/model-overlay-hook.py --verbose
```

The hook is invoked:
1. By `model-adapter.sh` at first sourced lookup if `.run/merged-model-aliases.sh` is missing.
2. By the `loa doctor` command (NFR-Op-5 verification).
3. By Sprint 1 CI to verify drift = 0.

### 5.5 No HTTP API

Cycle-099 introduces no HTTP endpoints. Provider HTTP calls are made by `cheval.py` (existing) and Bridgebuilder TS adapters (existing); cycle-099 modifies *which model* they call but not *how* they call it.

### 5.6 Debug Trace + JSON Output Secret Redactor (resolves Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS 860)

The Flatline review identified a critical security/operability gap: debug traces (FR-5.7 `[MODEL-RESOLVE]` stderr output) and JSON outputs (FR-5.6 `model-invoke --validate-bindings` resolution_path field) are common leak vectors for secrets — particularly URL `userinfo` (everything between `://` and `@`) and query strings carrying `key=`, `token=`, `secret=`, `password=`, `api_key=`, `auth=` parameters. Operator-added endpoints CAN contain credentials in URL form even though NFR-Sec-5 forbids `auth` field, because the `endpoint` URL itself is the carrier.

**v1.1 introduces a mandatory redaction module** applied to every diagnostic surface that may emit URLs or operator config values:

#### 5.6.1 Module locations

- **Python**: `.claude/scripts/lib/log-redactor.py` — used by `model-overlay-hook.py`, FR-5.6 `model-invoke --validate-bindings` (Python implementation), and FR-5.7 stderr emission.
- **Bash**: `.claude/scripts/lib/log-redactor.sh` — used by FR-1.9 generated bash file's diagnostic comments, by `model-adapter.sh` debug paths, and by any `[MODEL-RESOLVE]` emission from bash callers.

Both modules expose a single function: `redact(text: str) -> str` (Python) / `_redact "$text"` (bash) producing a redacted string with structural identity preserved (so log-grep operators can still find the URL pattern, just with secrets masked).

#### 5.6.2 Redaction patterns

| Pattern | Detection | Replacement |
|---------|-----------|-------------|
| URL `userinfo` | `://[^/@]*@` (everything between `://` and `@`) | `://[REDACTED]@` |
| Query param `key=<v>` | `[?&]key=[^&]*` | `[?&]key=[REDACTED]` (preserve separator) |
| Query param `token=<v>` | `[?&]token=[^&]*` | `[?&]token=[REDACTED]` |
| Query param `secret=<v>` | `[?&]secret=[^&]*` | `[?&]secret=[REDACTED]` |
| Query param `password=<v>` | `[?&]password=[^&]*` | `[?&]password=[REDACTED]` |
| Query param `api_key=<v>` | `[?&]api_key=[^&]*` | `[?&]api_key=[REDACTED]` |
| Query param `auth=<v>` | `[?&]auth=[^&]*` | `[?&]auth=[REDACTED]` |

The Python module uses `re.sub` with a single combined regex per pattern class; bash uses `sed` with the same patterns translated to BRE. Both modules are **case-insensitive** for the parameter name match (`Token=`, `TOKEN=`, etc. all redact).

#### 5.6.3 Application surface

The redactor is invoked at every diagnostic emission surface:

| Surface | Caller | When |
|---------|--------|------|
| FR-5.7 `[MODEL-RESOLVE]` stderr | Python loader, bash adapter | Per resolution under `LOA_DEBUG_MODEL_RESOLUTION=1` |
| FR-5.6 `model-invoke --validate-bindings` JSON | Python loader (writes JSON to stdout) | `resolution_path[].details.endpoint` and any field carrying URL |
| FR-1.9 generated bash file's diagnostic comments | Python writer | `# Generated by ...` header, `LOA_OVERLAY_FINGERPRINT` (already non-URL but defensive) |
| `[OVERLAY-DEGRADED-READONLY]` WARN | Python startup hook | `reason=<...>` field never includes URLs but defense-in-depth |
| `[ENDPOINT-NOT-ALLOWED]` ERROR | Python loader | Error detail field `field=<URL>` redacted |
| Trajectory log emission (cycle-098 audit envelope) | All callers | When emitting endpoint-bearing fields |

**NFR-Sec-3 invariant preservation**: cycle-098 v1.0 NFR-Sec-3 stated "no new secrets surface introduced". Cycle-099 v1.0 was consistent with that under the assumption that operator-added endpoints contain no credentials. v1.1 hardens the assumption: even if an operator violates the schema and somehow sneaks a credential into the URL, the diagnostic surface will not echo it.

#### 5.6.4 Test coverage

`tests/integration/log-redactor.bats` (Sprint 2 deliverable) covers:
- URL userinfo: `https://user:pass@api.example.com/v1` → `https://[REDACTED]@api.example.com/v1`
- Multiple query params: `?key=abc&token=def&foo=bar` → `?key=[REDACTED]&token=[REDACTED]&foo=bar` (foo unchanged)
- Multiline (URLs in markdown-like contexts): redacts each line independently
- Encoded chars: `?token=abc%20def` → `?token=[REDACTED]` (treated as one value)
- Empty values: `?token=&key=foo` → `?token=[REDACTED]&key=[REDACTED]`
- Case-insensitive: `?Token=abc` → `?Token=[REDACTED]`
- No URL present: plain text passes through unchanged
- Mixed: `[MODEL-RESOLVE] skill=flatline endpoint=https://user:pass@api.example.com/v1?api_key=secret` → fully redacted

**Cross-runtime parity**: `tests/integration/log-redactor.bats` runs both Python and Bash redactors against the same input fixtures and asserts byte-equal output. A divergence indicates one runtime missing a pattern.

**Cite**: this implementation preserves NFR-Sec-3 ("No new secrets surface introduced") under the operator-added-endpoint case where the URL itself carries credentials. The redactor does not REMOVE the secrets surface (operator can still misconfigure); it ensures the secret never appears in diagnostic output.

---

## 6. Error Handling Strategy

### 6.1 Error Categories

| Category | Code prefix | Example |
|----------|-------------|---------|
| Config validation | `[MODEL-EXTRA-*]` | `[MODEL-EXTRA-INVALID]`, `[MODEL-EXTRA-DUPLICATE]` |
| Permission validation | `[PERMISSIONS-*]` | `[PERMISSIONS-NOT-ACKNOWLEDGED]`, `[PERMISSIONS-FORBIDDEN]` |
| Endpoint validation | `[ENDPOINT-*]` | `[ENDPOINT-NOT-ALLOWED]`, `[ENDPOINT-DNS-REBOUND]`, `[ENDPOINT-REDIRECT-DENIED]` |
| Resolution | `[BINDING-*]` | `[BINDING-UNRESOLVED]`, `[LEGACY-SHAPE-RESOLVED]` |
| Codegen drift | `[DRIFT-*]` | `[DRIFT-DETECTED]`, `[DRIFT-LOCKFILE-MISMATCH]` |
| Runtime hook | `[MERGED-ALIASES-*]` | `[MERGED-ALIASES-CORRUPT]`, `[MERGED-ALIASES-WRITE-FAILED]` |
| Override | `[OVERRIDE-*]` | `[OVERRIDE-UNKNOWN-MODEL]`, `[OVERRIDE-PERMISSIONS-FORBIDDEN]` |
| Resolution debug | `[MODEL-RESOLVE]` | FR-5.7 stderr trace |
| Hybrid divergence | `[BB-OVERLAY-OVERRIDE]` | §1.4.6 |

### 6.2 Error Response Format

All errors emitted via stderr in the structured shape:

```
[ERROR-CODE] field=<offending field> remediation=<URL or runbook path>
  detail: <human-readable single-line explanation>
  code: <short error code per §6.1>
```

Example:
```
[MODEL-EXTRA-INVALID] field=entries[0].api_id remediation=grimoires/loa/runbooks/model-extra-invalid.md
  detail: api_id 'gpt;rm -rf' contains shell metacharacter ';' (rejected by ^[a-zA-Z0-9._-]+$)
  code: MODEL-EXTRA-INVALID-API-ID-FORMAT
```

For machine consumption, `--format json` wraps the error in:
```json
{
  "schema_version": "1.0.0",
  "command": "validate-bindings",
  "exit_code": 78,
  "errors": [
    {
      "code": "MODEL-EXTRA-INVALID-API-ID-FORMAT",
      "field": "model_aliases_extra.entries[0].api_id",
      "detail": "...",
      "remediation": "..."
    }
  ]
}
```

### 6.3 Failure Modes for FR-1.9 Runtime Hook

#### 6.3.1 Lock acquisition contract (resolves Flatline SDD pass #1 IMP-001 HIGH_CONSENSUS 865)

The startup hook acquires `.run/merged-model-aliases.sh.lock` per the following sequence (per IMP-001 lock/timeout specification):

1. **Acquisition order**: ALWAYS acquire **shared lock first** (read-only verification of existing merged file). Upgrade to **exclusive lock** only if write is needed (file missing, SHA256 mismatch, version mismatch). POSIX `flock(2)` supports atomic shared-to-exclusive upgrade.
2. **Timeout values** (configurable via env var):
   - **Shared lock**: 5 seconds (`LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS=5000` default).
   - **Exclusive lock**: 30 seconds (`LOA_OVERLAY_LOCK_TIMEOUT_EXCLUSIVE_MS=30000` default).
   - **Shared-to-exclusive upgrade**: 30 seconds (uses the exclusive timeout).
3. **Multi-agent startup race**: each agent's startup hook attempts shared lock first; if the merged file exists and is valid (header SHA256 matches input SHA256), no upgrade is needed. If file generation/regeneration is needed, upgrade to exclusive lock for the regen window only, then drop to shared.
4. **Stale-lock recovery (resolves Flatline SDD pass #1 SKP-004 HIGH 740)**: before treating a lock-acquisition timeout as a failure, the hook reads the lockfile holder PID (recorded in lockfile header) and runs `kill -0 <pid>`. If the holder is dead (kill -0 returns ESRCH), break-and-retry **once** with full timeout. If retry also fails, fall through to the failure-mode behavior below.
5. **Failure routes to degraded fallback by default** (see §6.3.2); strict mode (`LOA_OVERLAY_STRICT=1`) routes to fail-closed (`[MERGED-ALIASES-LOCK-TIMEOUT]` exit).

**Configurability rationale**: shared lock 5s is short because reader verification is fast (read header, compare SHA256, release); making this longer than 5s indicates a runaway holder. Exclusive lock 30s is generous because the regen sequence (read two YAMLs, run JSON Schema validation, render bash file, fsync, rename) realistically completes in <5s but can spike on slow filesystems. Operators on enterprise CI may extend via env vars without a code change.

#### 6.3.2 Degraded read-only fallback (resolves Flatline SDD pass #1 SKP-004 HIGH 740)

The original SDD v1.0 specified fail-closed semantics on lock timeout. The Flatline review found this risks turning environmental quirks (network FS hiccups, container restarts mid-acquisition, slow filesystems) into total system unavailability. The v1.1 contract introduces a **degraded read-only fallback** as the default behavior, with a strict-mode opt-in for ops/CI environments that want fail-closed.

**Default behavior** (`LOA_OVERLAY_STRICT=0`, the default): on lock acquisition failure after timeout (and after stale-lock recovery has been attempted), if `.run/merged-model-aliases.sh` exists and its `source-sha256=` header matches the SHA256 of `model-config.yaml ∪ .loa.config.yaml::model_aliases_extra`, the hook continues in **degraded read-only mode**:
  - Source the existing merged file as-is (no regen).
  - Emit one-time stderr WARN per process: `[OVERLAY-DEGRADED-READONLY] reason=<lock-timeout|stale-lock-unrecoverable> file=.run/merged-model-aliases.sh source_sha=<sha8>`.
  - Set process env var `LOA_OVERLAY_DEGRADED=1` for downstream consumers (`model-invoke --validate-bindings --report-degraded-mode` exposes via JSON).
  - **No writes attempted** during degraded mode (read-only contract).
  - Degraded duration logged in trajectory.

**Strict mode** (`LOA_OVERLAY_STRICT=1`, opt-in): on lock acquisition failure, refuse to start. This is the cycle-099 v1.0 behavior, retained as opt-in for ops/CI environments where any degradation is unacceptable.

**Last-known-good condition**: degraded fallback only proceeds if (a) the merged file exists, (b) its `source-sha256=` header matches a fresh hash of the input (i.e., the cached file IS the up-to-date answer — the only thing missing is the lock proof), AND (c) bash syntax check on the file passes. If any of these fail, even default mode escalates to fail-closed with `[MERGED-ALIASES-CORRUPT]` or `[MERGED-ALIASES-STALE-AND-LOCKED]`.

**NFR-Op-6 (NEW — degraded mode contract)**: degraded reads are read-only (no writes attempted); structured WARN emitted; degraded duration logged. Operator can verify via `model-invoke --validate-bindings --report-degraded-mode` (JSON output includes `"degraded_mode": true|false, "degraded_reason": "..."` field). CI/ops dashboards SHOULD alert when `LOA_OVERLAY_DEGRADED=1` is observed in production traffic.

#### 6.3.3 Failure mode table (updated)

| Trigger | Code | Behavior (default) | Behavior (`LOA_OVERLAY_STRICT=1`) |
|---------|------|--------------------|-----------------------------------|
| `.run/merged-model-aliases.sh` absent | `[MERGED-ALIASES-MISSING]` | Regenerate via startup hook (acquires exclusive lock) | Same |
| Bash syntax check fails on regen output | `[MERGED-ALIASES-CORRUPT]` | Refuse to start (fail-closed in BOTH modes) | Same |
| Write permission failure / disk full | `[MERGED-ALIASES-WRITE-FAILED]` | Refuse to start | Same |
| SHA256 mismatch (stale per FR-1.9) | `[MERGED-ALIASES-STALE]` | Regenerate under exclusive flock | Same |
| flock shared lock timeout (>5s default) | `[MERGED-ALIASES-LOCK-TIMEOUT-SHARED]` | Stale-lock recovery via `kill -0`; if holder dead, break-and-retry once. On retry failure: degraded read-only fallback (§6.3.2) | Refuse to start |
| flock exclusive lock timeout (>30s default) | `[MERGED-ALIASES-LOCK-TIMEOUT-EXCLUSIVE]` | Stale-lock recovery via `kill -0`; if holder dead, break-and-retry once. On retry failure: degraded read-only fallback IF cached file is last-known-good; ELSE refuse | Refuse to start |
| Stale lock unrecoverable (holder alive but unresponsive) | `[MERGED-ALIASES-STALE-LOCK]` | Degraded read-only fallback IF cached file is last-known-good; ELSE refuse | Refuse to start |
| Network-fs detected without opt-in | `[MERGED-ALIASES-NETWORK-FS]` | Refuse to start; operator must `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` (resolves SKP-005) | Same |
| Schema-invalid `model_aliases_extra` (caught at load before hook write) | `[MODEL-EXTRA-INVALID]` | Refuse to start | Same |
| Cached file last-known-good check fails (SHA mismatch with current input) | `[MERGED-ALIASES-STALE-AND-LOCKED]` | Refuse to start (degradation rejected — cache is wrong, not just stale) | Same |

### 6.4 Logging Strategy

- **Log levels**: ERROR (fail-closed events), WARN (deprecation, non-fatal divergence), INFO (resolution trace), DEBUG (FR-5.7 per-resolution detail).
- **Format**: structured per §6.2 above for ERROR/WARN; FR-5.7 format `[MODEL-RESOLVE] skill=X role=Y input=Z resolved=A:B resolution_path=[...]` for DEBUG.
- **Sink**: stderr for all levels. No log files. Loa's existing trajectory logs (`grimoires/loa/a2a/trajectory/`) capture skill-level reasoning; cycle-099 doesn't add a new log sink.
- **Correlation**: `tracing_fingerprint` (12-char SHA256 prefix of resolution_path) for cross-log correlation when an operator reports a resolution surprise.

### 6.5 URL Canonicalization Rules (resolves SKP-003 + Flatline SDD pass #1 SKP-003 HIGH 770)

> From PRD `prd.md:632`: "SKP-003 (URL canonicalization edge cases — IPv6/IDN/punycode/port specs)"
>
> **v1.1 simplification** (Flatline SDD pass #1 SKP-003 HIGH 770): the original 9-step pipeline included a Levenshtein-distance-<2 punycode-lookalike check. The Flatline review found this brittle (false-positive risk on legitimate operator-added domains; bypass risk via single-character substitutions outside the distance metric; complex to implement correctly). It is **REMOVED** in favor of strict normalized-host-matching against the allowlist. Pipeline reduced from 9 steps to 8.

Endpoint URLs from `model_aliases_extra.<id>.endpoint` and `model_aliases_override.<id>.endpoint` are canonicalized at config-load time using a **strict canonicalization pipeline**:

| Step | Rule | Rejection code |
|------|------|----------------|
| 1 | Parse via Python `urllib.parse.urlsplit()` (DD-4 Python). Reject if `urlsplit()` raises. | `[ENDPOINT-PARSE-FAILED]` |
| 2 | `scheme` MUST be `https`. Reject `http`, `ws`, custom schemes. | `[ENDPOINT-INSECURE-SCHEME]` |
| 3 | `netloc` MUST be present. Reject empty (relative URL). | `[ENDPOINT-RELATIVE]` |
| 4 | If hostname contains `:` (IPv6 literal): MUST be RFC 3986 bracketed-form `[::1]`. Strip brackets for IP-range check; check against blocked IPv6 ranges (`::1`, `fe80::/10`, `fc00::/7`, etc.). | `[ENDPOINT-IPV6-BLOCKED]` |
| 5 | **(v1.1 simplified)** IDN encoding via Python `idna` library (≥ 3.6, RFC 5891) when hostname contains non-ASCII OR `xn--` prefix. After encoding, the resulting ASCII hostname is matched verbatim against the provider's `allowed_endpoints` list. **No similarity matching, no Levenshtein, no punycode-lookalike heuristic.** Per Flatline SDD pass #1 SKP-003 HIGH 770 — Levenshtein-based homoglyph defense rejected as brittle and overly complex; strict allowlist matching is sufficient given that providers' canonical hostnames are well-known and operator additions go through cycle-level approval. | `[ENDPOINT-IDN-NOT-ALLOWED]` |
| 6 | `port` rules: if absent, infer 443 for HTTPS. If present, MUST equal 443 for OpenAI/Anthropic/Google; allowlist per-provider for Bedrock (some regional endpoints use non-default ports). Reject non-default ports unless explicitly permitted in `loa.defaults.yaml::providers.<p>.allowed_endpoints[].ports`. | `[ENDPOINT-PORT-NOT-ALLOWED]` |
| 7 | `path` normalization: reject `..`, `./`, repeated slashes, percent-encoded path-traversal (`%2e%2e/`), Unicode normalization tricks (right-to-left override). | `[ENDPOINT-PATH-INVALID]` |
| 8 | Final check: rebuild canonical URL; the canonical form MUST match the schema-validated allowlist host pattern exactly. Match is on the IDNA-normalized + lowercased hostname. | `[ENDPOINT-NOT-ALLOWED]` |

**Removed step (v1.0 step 6)**: punycode Levenshtein-distance-<2 check was REMOVED in v1.1. Rationale (Flatline SDD pass #1 SKP-003 HIGH 770): "Custom URL canonicalization and anti-lookalike logic is overly complex and brittle (IDN, punycode, Levenshtein checks), likely to produce bypasses or false positives. Security controls that are hard to implement correctly often fail open or break valid endpoints. Either outcome is severe: SSRF exposure or operator lockout." The remediation strategy: rely on the strict allowlist matching in step 8 — every legitimate operator-added endpoint MUST match an entry in `providers.<p>.allowed_endpoints[]`, which is itself reviewed at cycle-level approval. Lookalike domains never reach the validator because they cannot be added to the allowlist without explicit framework-maintainer review.

**Rejection code update**: the `[ENDPOINT-PUNYCODE-LOOKALIKE]` code is REMOVED from the registry. The 8 remaining codes are: `[ENDPOINT-PARSE-FAILED]`, `[ENDPOINT-INSECURE-SCHEME]`, `[ENDPOINT-RELATIVE]`, `[ENDPOINT-IPV6-BLOCKED]`, `[ENDPOINT-IDN-NOT-ALLOWED]`, `[ENDPOINT-PORT-NOT-ALLOWED]`, `[ENDPOINT-PATH-INVALID]`, `[ENDPOINT-NOT-ALLOWED]`.

**Test corpus** (`tests/integration/url-canonicalization.bats`): probes for every step above, including IPv6 literal `https://[::1]/v1`, IDN homograph `https://googⅬe.com/v1` (Cyrillic L — REJECTED at step 5 because IDN-encoded form does not appear in any provider's allowed_endpoints list), punycode `xn--ggle-vqa.com` (REJECTED at step 5 same reason), port `:8080`, path traversal `https://api.openai.com/../v1`, RTL override. The fixture for "lookalike rejection" no longer asserts a specific Levenshtein-distance behavior — it asserts that the encoded hostname does not match any allowlist entry.

### 6.6 flock-over-NFS hardening (resolves SKP-005)

> From PRD `prd.md:632`: "SKP-005 (flock semantics over network filesystems — NFS/SMB caveats)"

`flock` is **advisory** on POSIX local filesystems and **best-effort** on NFS / SMB / CIFS. Operators running Loa on a network-mounted filesystem (e.g., shared CI runner with NFS-mounted workspace) face a real risk: `flock` either silently no-ops or throws `EBADF`/`EOPNOTSUPP`.

**SDD specification:**

1. The Python startup hook detects `.run/merged-model-aliases.sh.lock`'s filesystem type via `os.statvfs(...)` (`f_basetype` on Solaris) or via reading `/proc/mounts` (Linux) or via `df -T` (cross-platform fallback).
2. If filesystem type is in the blocklist `{nfs, nfs3, nfs4, cifs, smbfs, smb3, fuse.sshfs, fuse.s3fs, autofs, davfs}`, refuse to write merged.sh and exit with `[MERGED-ALIASES-NETWORK-FS]`.
3. Operator can override with `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` env var. The override emits one WARN log per process: `[MERGED-ALIASES-NETWORK-FS-OVERRIDE] flock semantics may be lost on NFS failover`.
4. The override does NOT disable flock; flock still attempts. But the operator has acknowledged the failure mode.

**Test corpus** (`tests/integration/flock-network-fs-detection.bats`): mock `/proc/mounts` with NFS entry; verify hook refuses; verify `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1` permits with WARN log.

**Operator runbook**: `grimoires/loa/runbooks/network-fs-merged-aliases.md` (Sprint 2 deliverable) explains the flock-on-NFS hazard, lists alternative deployment patterns (local-fs `.run/`, RAM-disk overlay), and documents the override.

---

## 7. Testing Strategy

### 7.1 Testing Pyramid (cycle-099 contributions)

| Level | Coverage Target | Tools | Cycle-099 additions (estimate) |
|-------|-----------------|-------|--------------------------------|
| Unit (codegen scripts) | Per-fn test | bats | ~30 (gen-bb-registry, gen-model-permissions, model-overlay-hook) |
| Unit (schema) | All ModelExtra branches | jsonschema (Python) + ajv (TS) | ~20 |
| Unit (resolution) | Each FR-3.9 stage | bats | ~25 |
| Integration | Cross-component | bats + tsx --test | ~40 (legacy-config-golden, security corpus, divergence detector, flock-network-fs, url-canonicalization, shell-escape) |
| Property | FR-3.9 invariants | bats + custom property generator (DD-6) | ~6 invariants × ~100 random configs = ~600 cases per CI run; 1000-iter stress in nightly |
| E2E | Operator UC validation | bats (fresh-clone simulation) | ~5 (UC-1, UC-2, UC-3, UC-4, UC-5 from PRD) |

**Total cycle-099 new tests: ~110 + property suite + 1000-iter nightly.**

### 7.2 Sprint 1 test deliverables

- `tests/unit/gen-bb-registry-codegen.bats` — codegen script unit tests (~12 cases)
- `tests/integration/bridgebuilder-dist-drift.bats` — CI gate verification
- `tests/integration/legacy-adapter-still-works.bats` — sentinel that nothing broke pre-Sprint 2
- `tests/perf/model-overlay-hook-bench.bats` — NFR-Perf-1 microbenchmark
- `tests/integration/lockfile-checksum.bats` — FR-5.4 lockfile mechanism

### 7.3 Sprint 2 test deliverables

- `tests/unit/model-aliases-extra-schema.bats` — JSON Schema validation unit tests
- `tests/integration/model-aliases-extra-security.bats` — NFR-Sec-1.1 SSRF + injection corpus
- `tests/integration/legacy-config-golden.bats` — SC-13 (4 fixture configs × ~5 assertions)
- `tests/integration/model-resolution-golden.bats` — SC-9 (10+ scenarios × 4 skills)
- `tests/property/model-resolution-properties.bats` — SC-14 (6 invariants)
- `tests/integration/url-canonicalization.bats` — §6.5 corpus
- `tests/integration/merged-aliases-shell-escape.bats` — §3.5 corpus
- `tests/integration/flock-network-fs-detection.bats` — §6.6
- `tests/unit/model-overlay-hook.py.test` — Python hook unit tests via pytest

### 7.4 Sprint 3 test deliverables

- `tests/unit/gen-model-permissions.bats` — DD-1 Option B codegen unit tests
- `tests/integration/model-permissions-merge-roundtrip.bats` — end-to-end SoT → emitted YAML byte-equal
- `tests/integration/persona-tier-tag-resolution.bats` — FR-1.5 backward compat (both `# model:` and `# tier:` work)
- `tests/integration/bb-runtime-overlay-divergence.bats` — §1.4.6 SKP-006 corpus

### 7.5 Sprint 4 test deliverables (gated)

- `tests/integration/legacy-adapter-deprecation-warning.bats` — FR-4.3 visibility test
- `tests/integration/default-flip-flatline-routing.bats` — FR-4.2 verification
- `tests/integration/sunset-rollback.bats` — NFR-Op-3 rollback path

### 7.6 Cross-Runtime Golden Test Corpus (resolves Flatline SDD pass #1 SKP-002 CRITICAL 890)

The FR-3.9 6-stage resolver is duplicated across **three runtimes**: the Python loader at §1.4.4 (cheval + `model-overlay-hook.py`), the Bash overlay generator at §1.4.5 (`.run/merged-model-aliases.sh` consumers), and the Bridgebuilder TypeScript runtime overlay at §1.5. The Flatline review identified this triplication as a **CRITICAL drift hazard** — any small precedence mismatch can route different skills to different models under the same config, causing inconsistent behavior, hard-to-debug incidents, and trust loss.

**Mitigation**: a shared **golden-test fixture corpus** that all three runtimes consume identically. CI matrix verifies byte-identical resolution output across all three runtimes for every fixture.

#### 7.6.1 Fixture schema

`tests/fixtures/model-resolution/<scenario>.yaml` — each fixture is a self-contained scenario with two top-level keys:

```yaml
# tests/fixtures/model-resolution/01-happy-path-tier-tag.yaml
description: "Operator declares skill_models.flatline_protocol.primary: max; resolves to opus"

input:                                  # the EFFECTIVE merged config (post FR-2.x merge)
  schema_version: 2
  framework_defaults:                   # mock framework SoT subset
    providers:
      anthropic:
        models:
          claude-opus-4-7:
            capabilities: [chat, tools]
            context_window: 200000
            pricing: { input_per_mtok: 5000000, output_per_mtok: 25000000 }
    aliases:
      opus: { provider: anthropic, model_id: claude-opus-4-7 }
      max: { provider: anthropic, model_id: claude-opus-4-7 }    # tier expansion
    tier_groups:
      mappings:
        max: { anthropic: opus }
    agents:
      flatline-reviewer: { default_tier: cheap }
  operator_config:                      # mock .loa.config.yaml subset
    skill_models:
      flatline_protocol:
        primary: max

expected:                               # expected resolution per skill/role per runtime
  resolutions:
    - skill: flatline_protocol
      role: primary
      resolved_provider: anthropic
      resolved_model_id: claude-opus-4-7
      resolution_path:
        - { stage: 1, outcome: hit, label: stage1_pin_check }    # "max" treated as pin? Or tier? Documented in fixture
  cross_runtime_byte_identical: true
```

The `expected.resolutions` array is consumed identically by:
- `tests/python/golden_resolution.py` — feeds fixture into the Python loader's resolver and asserts every field of every resolution matches.
- `tests/bash/golden_resolution.bats` — feeds fixture into the bash resolver (sourced from `.run/merged-model-aliases.sh` mocked from input) and asserts.
- `tests/typescript/golden_resolution.test.ts` — feeds fixture into the Bridgebuilder TS runtime overlay and asserts.

**Byte-identical assertion**: not just "same model_id" — the FULL `resolution_path` array (stage outcomes + labels) MUST be identical. This catches subtle differences like "Python returned at stage 3 hit; Bash returned at stage 5 hit because it has a different default in agents lookup". `cross_runtime_byte_identical: true` is a fixture-level assertion that ALL three runtimes' canonicalized output is byte-equal.

#### 7.6.2 CI matrix

Three GitHub Actions workflows run in parallel, each consuming the same fixture corpus:

| Workflow file | Runtime | Test runner |
|---------------|---------|-------------|
| `.github/workflows/python-runner.yml` (NEW Sprint 1) | Python 3.11 (cheval venv) | pytest |
| `.github/workflows/bash-runner.yml` (NEW Sprint 1) | bash 5.0 + bats-core | bats |
| `.github/workflows/bun-runner.yml` (NEW Sprint 1) | Bun 1.1.x (Bridgebuilder TS toolchain) | tsx --test |

A **mismatch fails the build**: each workflow uploads a `<runtime>-resolution-output.json` artifact; a downstream `cross-runtime-diff.yml` job downloads all three artifacts and runs `jq -S` canonical sort + byte-comparison. Any divergence → exit non-zero on the matrix → PR cannot land.

Existing `model-registry-drift.yml` is augmented to include the three runtime jobs; the cross-runtime diff is the gate.

#### 7.6.3 Initial fixture corpus (12+ scenarios)

Sprint 1 ships the following fixtures; Sprint 2/3 add as new edge cases surface:

| # | File | Scenario |
|---|------|----------|
| 1 | `01-happy-path-tier-tag.yaml` | tier-tag in skill_models resolves cleanly (FR-3.9 stage 2 hit) |
| 2 | `02-explicit-pin-wins.yaml` | explicit provider:model_id pin in skill_models takes precedence (FR-3.9 stage 1) |
| 3 | `03-missing-tier-fail-closed.yaml` | tier-tag with no mapping for (tier, provider) → fail-closed (FR-3.8) |
| 4 | `04-legacy-shape-deprecation.yaml` | flatline_protocol.models.primary legacy shape → resolves with deprecation warning (FR-3.7) |
| 5 | `05-override-conflict.yaml` | model_aliases_override targets unknown ID → reject (`[OVERRIDE-UNKNOWN-MODEL]`) |
| 6 | `06-extra-only-model.yaml` | operator-added model in model_aliases_extra resolves identically across runtimes |
| 7 | `07-empty-config.yaml` | minimal `.loa.config.yaml` (no operator overrides) → all defaults resolve |
| 8 | `08-unicode-operator-id.yaml` | operator-added model with id containing only `[a-zA-Z0-9._-]+` (schema-allowed unicode boundary) |
| 9 | `09-prefer-pro-overlay.yaml` | FR-3.9 stage 6 retargets resolved model to its `*-pro` variant |
| 10 | `10-extra-vs-override-collision.yaml` | same ID in both `extra` and `override` → reject (`[MODEL-EXTRA-OVERRIDE-CONFLICT]`) — IMP-004 enforcement |
| 11 | `11-tiny-tier-anthropic.yaml` | `tiny: anthropic:claude-haiku-4-5-20251001` (cycle-095 alias) — verifies SKP-001 resolution |
| 12 | `12-degraded-mode-readonly.yaml` | startup hook degraded mode (lock timeout) — uses cached merged file; resolves via cached mappings |

**Sprint 1 task added**: T1.X — "Build golden-test fixture corpus (12 initial fixtures) + 3 cross-runtime runners (Python/Bash/TS) + cross-runtime-diff CI gate. Fixtures consumed identically; mismatch fails build."

**Cross-reference**: this corpus is the implementation of FR-3.9 acceptance criterion SC-9 ("10+ scenarios × 4 skills"); v1.0 specified the count but not the cross-runtime-byte-identical assertion. v1.1 promotes this to mandatory.

### 7.7 CI/CD integration

- **PR check**: `model-registry-drift.yml` (Sprint 1) runs all four codegen scripts in `--check` mode; non-zero exit blocks merge.
- **Matrix CI**: `ubuntu-latest` + `macos-latest` for codegen reproducibility.
- **Property test cadence**: ~600 cases on every PR check; 1000-iter stress nightly via `cron: '0 6 * * *'`.
- **Lockfile gate**: `tests/integration/lockfile-checksum.bats` runs in PR check, verifies `model-config.yaml.checksum` matches SHA256 of source; CI fails if checksum is stale.

---

## 8. Development Phases (Sprint Decomposition Hints)

`/sprint-plan` will produce final sprint briefs. The PRD already locked phasing (`prd.md:23-28`); SDD adds task-level detail.

### Sprint 1 — SoT Extension Foundation (estimated ~30 tests, ~$30-50)

**Acceptance theme**: "Codegen and drift gate work; nothing else changes."

- [ ] T1.1 — Create `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` reading `model-config.yaml`, emitting `truncation.generated.ts` + `config.generated.ts`. (FR-1.1.a)
- [ ] T1.2 — Wire `bun run build` to invoke the generator before `tsc`. (FR-1.1.a)
- [ ] T1.3 — Migrate `red-team-model-adapter.sh` to `source generated-model-maps.sh` at init. (FR-1.2)
- [ ] T1.4 — Migrate `red-team-code-vs-design.sh` `--model opus` literal to `--model "$(resolve_alias opus)"`. (FR-1.3)
- [ ] T1.5 — Create `.github/workflows/model-registry-drift.yml` — CI drift gate for all generated artifacts. (FR-5.1, FR-5.2)
- [ ] T1.6 — Create `model-config.yaml.checksum` lockfile + `tests/integration/lockfile-checksum.bats`. (FR-5.4)
- [ ] T1.7 — Add codegen reproducibility matrix CI (Linux + macOS). (FR-5.5, NFR-Op-5)
- [ ] T1.8 — Update `model-adapter.sh` (non-`.legacy`) to source `generated-model-maps.sh`. (FR-1.7)
- [ ] T1.9 — Publish `grimoires/loa/runbooks/codegen-toolchain.md` (NFR-Op-5).
- [ ] T1.10 — Test deliverables per §7.2.
- [ ] T1.11 — **Build golden-test fixture corpus + 3 cross-runtime runners (Python/Bash/TS)**. Initial 12 fixtures per §7.6.3; runners at `tests/python/golden_resolution.py`, `tests/bash/golden_resolution.bats`, `tests/typescript/golden_resolution.test.ts`. (resolves Flatline SDD pass #1 SKP-002 CRITICAL 890)
- [ ] T1.12 — Wire CI workflows: `.github/workflows/python-runner.yml`, `bash-runner.yml`, `bun-runner.yml`, `cross-runtime-diff.yml`. Mismatch fails build. (§7.6.2)
- [ ] T1.13 — Implement Debug Trace + JSON Output Secret Redactor at `.claude/scripts/lib/log-redactor.{py,sh}`. Cross-runtime parity test. (§5.6, resolves Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS 860)

**Acceptance criteria**: SC-1 (partial — only registries 1, 2, 4, 5 covered), SC-8 (drift gate green), Flatline SDD pass #1 SKP-002 CRITICAL 890 mitigation in CI matrix.

### Sprint 2 — Config Extension + Per-Skill Granularity (estimated ~30 tests, ~$30-50)

**Acceptance theme**: "Operator can extend; tier-tag granularity works; legacy still works."

- [ ] T2.1 — Define + ship `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (DD-5). (FR-2.2)
- [ ] T2.2 — Update strict-mode loader to accept `model_aliases_extra`, `model_aliases_override`, `skill_models`, `tier_groups.mappings`. (FR-2.1, FR-2.6)
- [ ] T2.3 — Implement Python startup hook `.claude/scripts/lib/model-overlay-hook.py` (DD-4). (FR-1.9)
- [ ] T2.4 — Implement `.run/merged-model-aliases.sh` writer with atomic-write + flock + SHA256 + version + shell-escape. (FR-1.9, §3.5, §6.6)
- [ ] T2.5 — Update `model-adapter.sh` to source the merged file with version-mismatch detection.
- [ ] T2.6 — Implement FR-3.9 6-stage resolution algorithm (Python + bash twin). (FR-3.9, §1.5)
- [ ] T2.7 — Populate `tier_groups.mappings` with probe-confirmed defaults. (FR-3.2, §3.1.2)
- [ ] T2.8 — Implement `prefer_pro_models` overlay with FR-3.4 legacy-shape gate. (FR-3.4)
- [ ] T2.9 — Implement legacy-shape backward compat with deprecation warning. (FR-3.7)
- [ ] T2.10 — Implement permissions baseline check + `acknowledge_permissions_baseline` opt-in. (FR-1.4)
- [ ] T2.11 — Implement endpoint allowlist + URL canonicalization + DNS rebinding defense. (FR-2.8, NFR-Sec-1, §6.5)
- [ ] T2.12 — Implement `model-invoke --validate-bindings` per §5.2. (FR-5.6)
- [ ] T2.13 — Implement `LOA_DEBUG_MODEL_RESOLUTION=1` per FR-5.7.
- [ ] T2.14 — Update `.loa.config.yaml.example` with worked examples (UC-1, UC-2). (FR-2.7)
- [ ] T2.15 — Test deliverables per §7.3.
- [ ] T2.16 — Publish `grimoires/loa/runbooks/network-fs-merged-aliases.md`. (§6.6)

**Acceptance criteria**: SC-2, SC-3, SC-7, SC-9, SC-10, SC-11, SC-12, SC-13, SC-14.

### Sprint 3 — Persona + Docs Migration + Model-Permissions (estimated ~25 tests, ~$25-40)

**Acceptance theme**: "Persona docs derive; model-permissions merged; Bridgebuilder dist regenerated."

- [ ] T3.1 — Migrate `.claude/data/personas/*.md` from `# model:` to `# tier:` with backward-compat parsing. (FR-1.5)
- [ ] T3.2 — Migrate `.claude/skills/bridgebuilder-review/resources/personas/*.md` similarly. (FR-1.5)
- [ ] T3.3 — Update `.claude/protocols/flatline-protocol.md` + `gpt-review-integration.md` to reference operator config. (FR-1.6)
- [ ] T3.4 — Implement DD-1 Option B: extend `model-config.yaml` with per-model `permissions` block. (§3.1.1)
- [ ] T3.5 — Implement `gen-model-permissions.sh` emitting `model-permissions.generated.yaml`. (§5.3)
- [ ] T3.6 — Migrate `model-permissions.yaml` → `model-permissions.generated.yaml` (read-path swap; cycle-100 deletes). (FR-1.4)
- [ ] T3.7 — Regenerate Bridgebuilder `dist/` from SoT via `bun run build`. (FR-1.1, SC-4)
- [ ] T3.8 — Publish `grimoires/loa/runbooks/bridgebuilder-dist-rollback.md`. (R-1)
- [ ] T3.9 — Publish `grimoires/loa/runbooks/model-permissions-removal.md`. (DD-1)
- [ ] T3.10 — Tag cycle-099-dist-RC1 for downstream submodule consumers. (R-1)
- [ ] T3.11 — Test deliverables per §7.4.

**Acceptance criteria**: SC-1 (full — all 13 registries covered), SC-4, SC-6, SC-12.

### Sprint 4 (gated) — Legacy Adapter Sunset (estimated ~25 tests, ~$25-40)

**Acceptance theme**: "Default flipped; deprecation visible; sunset decision made."

- [ ] T4.1 — Mark `.claude/scripts/model-adapter.sh.legacy` `DEPRECATED` in file header. (FR-4.1)
- [ ] T4.2 — Flip `hounfour.flatline_routing: true` default in `.claude/defaults/loa.defaults.yaml`. (FR-4.2)
- [ ] T4.3 — Implement `[LEGACY-MODEL-ADAPTER-DEPRECATED]` operator-visible warning. (FR-4.3)
- [ ] T4.4 — Sprint 4 gate review with operator: full-removal vs continued-deprecation. (FR-4.4)
- [ ] T4.5 — IF removal chosen: delete `model-adapter.sh.legacy`, remove feature flag, publish `legacy-adapter-removal.md`. (FR-4.6)
- [ ] T4.6 — IF deprecation continues: extend deprecation to cycle-100 in NOTES.md handoff.
- [ ] T4.7 — Test deliverables per §7.5.

**Acceptance criteria**: SC-5.

---

## 9. Known Risks and Mitigation (SDD-level additions)

PRD Risks R-1..R-10 carried forward. SDD adds:

| ID | Risk | Probability | Impact | Mitigation |
|----|------|-------------|--------|------------|
| **R-SDD-1** | Python startup hook adds ~30ms wall-clock to agent startup → frequent feel-slow complaints | LOW | LOW | Cache `.run/merged-model-aliases.sh` SHA256 short-circuit (skip regen if input SHA matches header). NFR-Perf-1 budget is 50ms p95; we have ~20ms headroom even after Python import. |
| **R-SDD-2** | `model_aliases_override` semantics ambiguous when override target has nested `pricing` block — operator expects partial-merge but gets replace | MEDIUM | MEDIUM | DD-3 locked partial-merge with explicit-fields-win at depth 2. SDD §3.3 documents. Sprint 2 ships `tests/integration/model-aliases-override-merge-semantics.bats` covering depth-2 partial-merge. |
| **R-SDD-3** | DD-1 Option B `model-config.yaml` with per-model `permissions` makes the file ~50% larger → harder to read in PRs | MEDIUM | LOW | Sprint 3 organizes `permissions` block consistently (sorted dimensions per cycle-026 schema); operators use `yq '.providers.<p>.models.<id>.permissions'` for queries. Cycle-100 considers schema-split if file >40KB. |
| **R-SDD-4** | flock-on-NFS detection has false-positives (some `fuse.*` filesystems are local but masquerade as network — e.g., `fuse.fakeroot`) | LOW | LOW | §6.6 detection blocklist is conservative; opt-in flag covers false-positive case. Detection is `f_basetype` PLUS `/proc/mounts` cross-check. |
| **R-SDD-5** | URL canonicalization in §6.5 step 5 IDN handling depends on Python `idna` library version; older versions reject some valid IDN domains | LOW | MEDIUM | Pin `idna >= 3.6` in cycle-099 toolchain `.tool-versions`. Sprint 1 codegen-toolchain runbook documents. |
| **R-SDD-6** | Bridgebuilder runtime overlay TS code path (FR-1.1.b) bug in production silently falls back to compiled defaults, masking operator misconfiguration | MEDIUM | HIGH | §1.4.6 divergence detector + `[BB-OVERLAY-OVERRIDE]` log emission. Sprint 3 `tests/integration/bb-runtime-overlay-divergence.bats` covers. |
| **R-SDD-7** | Property test runner (DD-6 bash + custom generator) generates non-representative configs (insufficient state-space coverage) | LOW | MEDIUM | Property generator is deterministic-seeded; CI logs seed. Operators reproducing failures pin the seed. 1000-iter nightly stress catches state-space gaps. If property generator proves insufficient by Sprint 3, swap to Hypothesis (Python) — small refactor. |
| **R-SDD-8** | Cycle-098 `audit_emit` flock pattern collides with cycle-099 `merged-aliases.sh.lock` (same `.run/` directory, similar name) | LOW | LOW | Different lock files (`audit-*.lock` vs `merged-model-aliases.sh.lock`); different invocation timing (audit-emit per event vs merged-aliases per startup). Sprint 2 verification: `lsof -p <pid>` audit during agent startup. |

---

## 10. Resolved Open Questions (Sprint 2 release blockers — closed by Flatline SDD pass #1 SKP-001 CRITICAL 910)

> **Flatline SDD pass #1 SKP-001 (CRITICAL 910)** identified the v1.0 §10 Open Questions as a **release blocker for Sprint 2 implementation**: leaving these open means resolver determinism, schema compatibility, and security posture remain underspecified, risking late-Sprint-2 / late-Sprint-3 rework across codegen, runtime hooks, tests, and docs. Per the Flatline recommendation: "Freeze these decisions before Sprint 2 implementation starts, publish final ADRs, and update schema + acceptance criteria to remove ambiguity."
>
> **All cycle-099-scope items are RESOLVED** below. Out-of-scope items (relevant to v2 / cycle-100+) are listed separately. **No Sprint 2 deliverable begins implementation until §10 is closed (this constraint is enforced at sprint-plan time).**

### 10.1 Resolved (cycle-099 scope)

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 10.1.1 | tiny-tier semantics for OpenAI (no smaller option than gpt-5.3-codex) | Use cycle-095's existing `tiny: anthropic:claude-haiku-4-5-20251001` alias (already declared in `.claude/defaults/model-config.yaml::aliases:`). For OpenAI, the v1 mapping uses `gpt-5.3-codex` per the existing `tier_groups.mappings.tiny.openai` default — operators preferring fail-closed semantics for OpenAI tiny can declare `tier_groups.mappings.tiny.openai: null` (fail-closed on resolution). **No new tier added.** | The cycle-095 `tiny` alias is already a stable contract; introducing a new tier would expand the resolution surface without operator demand. The `null` opt-out path covers the fail-closed case for operators who want it. |
| 10.1.2 | Should `model_aliases_override` allow overriding `endpoint_family`? | **NO.** `endpoint_family` is set per-entry by operators in their `model_aliases_extra` entries (where they own the model definition). Framework defaults are FROZEN at compile time and not overrideable via `model_aliases_override`. The JSON Schema for `model_aliases_override.entries[]` does NOT include `endpoint_family` in its allowed properties. | Operators wanting to change endpoint_family for a framework default would be replacing the model contract, not overriding pricing/endpoint — that's a System Zone concern (cycle-level approval to add a new entry to framework defaults). For OpenAI provider entries in `model_aliases_extra`, the schema REQUIRES `endpoint_family` (per cycle-095 Sprint 1) — no implicit default. |
| 10.1.3 | Should DD-1 Option B `permissions` block be REQUIRED for every model in `model_aliases_extra`, or remain OPTIONAL with FR-1.4 minimal-baseline fallback? | **OPTIONAL** in `model_aliases_extra`. If absent, the operator-added model defaults to NFR-Sec-5 minimal baseline (`chat` capability only, all other trust_scopes set to `none`, all `capabilities.*` set to `false`). Acknowledgement flag `acknowledge_permissions_baseline: true` REQUIRED when omitted (per FR-1.4 v1.2 strengthening). | Required-for-every-model would force operators to write 20+ lines per model to add a single new model — defeats the cycle-099 G-2 "≤10 lines for canonical operator config". OPTIONAL with a minimal-by-default + explicit acknowledgement preserves NFR-Sec safety. |
| 10.1.4 | `model-overlay-hook.py` venv vs system Python | **Reuse cheval venv** (`.claude/scripts/lib/cheval-venv/`) at `.claude/scripts/lib/model-overlay-hook.py`. Same Python interpreter; same PyYAML version; same jsonschema version. NO separate venv. NO system-Python path. | Cheval venv already exists; sharing avoids dependency duplication and drift between cheval's YAML behavior and the hook's. Reproducibility (NFR-Op-5) is easier with one venv. The startup hook invocation uses the venv's `python3` interpreter explicitly. |
| 10.1.5 | `loa doctor model` subcommand combining all validation checks | **Sprint 2 stretch goal — NOT a release blocker.** If Sprint 2 ships with `model-invoke --validate-bindings` (FR-5.6) covering the most-needed check, the standalone `loa doctor model` becomes a thin wrapper that calls validate-bindings + lockfile-check + flock-fs-check. Sprint 2 ships if budget permits; otherwise deferred to cycle-100 follow-up. | The validation checks already exist as discrete tools; `loa doctor model` is a convenience aggregator. Operators can compose the existing tools manually if needed. Not on the critical path for cycle-099 acceptance. |

### 10.2 Out of cycle-099 scope (deferred to follow-up)

| Question | Deferred to | Rationale |
|----------|-------------|-----------|
| Should DD-1 Option B `permissions` block become REQUIRED for every model in `model-config.yaml` (System Zone) post-Sprint 3? | cycle-100 (or later) | Migration is multi-step: cycle-099 ships permissions block as new field (Sprint 3); cycle-100 evaluates whether to require it for all framework defaults; cycle-101+ may require it of operator extras. Forcing the schema flip in cycle-099 risks breaking the migration. |
| Hot-reload of `model-config.yaml` without agent restart | post-cycle-101 (or never) | YAGNI — PRD `prd.md:246` rejected for v1 scope. Restart-to-apply is acceptable. |
| v2 schema_version migration framework (when cycle-026 trust_scopes evolves to 8th dimension) | post-cycle-101 | The schema_version mechanism in §3.1.1 (resolves Flatline pass #1 SKP-002 HIGH 720) is the migration entry point; the next-schema-version is defined when the next breaking change is needed. |
| Per-invocation cost forecasts at resolution time (DISPUTED IMP-004 from PRD pass #3) | cycle-100 (operator's discretion) | DISPUTED at PRD pass #3 (avg 645, delta 330) — no consensus. SDD does not implement; operator may revisit. |
| Multi-tenant model billing isolation | out of #710 scope | PRD §"Out of Scope" line 497 explicitly rejects. |

**Sprint 2 release blocker status: CLOSED** — all 10.1 items resolved; 10.2 items confirmed out-of-scope. Sprint 2 implementation may begin once SDD v1.1 is operator-approved.

---

## 11. Appendix

### A. Glossary (cycle-099 SDD additions to PRD glossary)

| Term | Definition |
|------|------------|
| **Compiled defaults** | TS literal maps emitted by `gen-bb-registry.ts` at framework build time. Shipped in `dist/`. |
| **Runtime overlay** | TS module at Bridgebuilder skill init that merges compiled defaults with `.loa.config.yaml::model_aliases_extra`. |
| **Divergence detection** | §1.4.6 emission of `[BB-OVERLAY-OVERRIDE]` when compiled and runtime tables disagree on a key. |
| **Merged-aliases.sh** | `.run/merged-model-aliases.sh` — bash file written by Python startup hook, sourced by bash adapters. |
| **Resolution path** | The ordered sequence of FR-3.9 stage outcomes (`hit`/`miss`/`applied`) that produced a (skill, role) → `provider:model_id` resolution. |
| **Tracing fingerprint** | 12-char SHA256 prefix of resolution_path serialization, for cross-log correlation. |
| **Lockfile** (cycle-099 sense) | `model-config.yaml.checksum` — SHA256 of source YAML. CI verifies generated artifacts match a fresh codegen against this checksum. NOT the same as flock `*.lock` files. |
| **Strict-mode loader** | cycle-095 `.loa.config.yaml` loader that rejects unknown top-level fields. Cycle-099 adds new fields to its allowlist. |

### B. References

- PRD: `grimoires/loa/cycles/cycle-099-model-registry/prd.md` (v1.3, 2026-05-04)
- Flatline SDD pass #1 review JSON: `grimoires/loa/a2a/flatline/cycle-099-sdd-review.json` (2026-05-04)
- Issue #710: https://github.com/0xHoneyJar/loa/issues/710
- Cycle-095 PRD/SDD: `grimoires/loa/cycles/cycle-095-model-currency/`
- Cycle-098 SDD pattern (Sprint 1B `protected_classes_extra`): `grimoires/loa/cycles/cycle-098-agent-network/sdd.md`
- Cycle-026 model_permissions schema: `.claude/data/model-permissions.yaml:1-23` header
- RFC 8785 JCS (used by cycle-098 audit envelope): https://datatracker.ietf.org/doc/html/rfc8785
- RFC 3986 URI Generic Syntax (used by §6.5 canonicalization): https://datatracker.ietf.org/doc/html/rfc3986
- RFC 5891 IDN encoding (used by §6.5 step 5 simplified canonicalization): https://datatracker.ietf.org/doc/html/rfc5891
- Python `urllib.parse` docs: https://docs.python.org/3/library/urllib.parse.html
- Python `idna` library (≥ 3.6): https://pypi.org/project/idna/
- POSIX `flock(2)` semantics: https://man7.org/linux/man-pages/man2/flock.2.html
- POSIX `kill(2)` (used by §6.3.1 stale-lock PID check via `kill -0`): https://man7.org/linux/man-pages/man2/kill.2.html

### C. Decision Log (Resolution of PRD Deferred Decisions, SDD-Shape Findings, and Flatline SDD Pass #1 Findings)

| Date / Source | Decision | Source / Finding ID | Rationale |
|---------------|----------|---------------------|-----------|
| 2026-05-04 (PRD-driven) | DD-1 model-permissions strategy: **Option B** (merge into model-config.yaml). 7-dim trust_scopes preserved as nested structure. | PRD DD-1 | §3.1.1, §5.3, §8 Sprint 3 — eliminates a registry per G-3 zero-drift; cycle-026 schema is per-model attribute not provider. Wrapper deletion deferred to cycle-101 MIN per Flatline pass #1 SKP-002 HIGH 720. |
| 2026-05-04 (PRD-driven) | DD-2 model_aliases_extra placement: **Top-level** (mirrors `protected_classes_extra` cycle-098 pattern). | PRD DD-2 | §3.2, §4.1 — operator-extension parity with existing pattern. |
| 2026-05-04 (PRD-driven) | DD-3 model_aliases_override semantics: **Partial-merge override** at depth 2; explicit-fields-win; silent override REJECTED; `permissions` override forbidden. | PRD DD-3 | §3.3 — full override creates hidden trap when forgetting one field; partial-merge with explicit-fields-win is least-surprising. v1.1 strengthens with mutually-exclusive entry-level enforcement (Flatline IMP-004 HIGH_CONSENSUS 765). |
| 2026-05-04 (PRD-driven) | DD-4 startup hook language: **Python** (cheval is already Python; reuses PyYAML; jsonschema 4.21+). | PRD DD-4 | §1.4.4, §2.1 — venv reuse confirmed in §10.1.4. |
| 2026-05-04 (PRD-driven) | DD-5 JSON Schema location + validator language: `.claude/data/trajectory-schemas/model-aliases-extra.schema.json`; Python validator (matches DD-4); ajv-TS for Bridgebuilder side. | PRD DD-5 | §3.2 — same schema authoritative for both runtimes. |
| 2026-05-04 (PRD-driven) | DD-6 Property test runner: **bats + simple bash property generator** at `tests/property/lib/property-gen.bash` (~150 lines). 0 new dependencies. | PRD DD-6 | §2.2, §7.1 — same pattern as cycle-098 SKP-002 mitigation. |
| 2026-05-04 (PRD-driven) | SKP-003 URL canonicalization: original 9-step canonicalization pipeline. | PRD SKP-003 (SDD-shape) | §6.5 v1.0 — strict canonicalization pipeline. v1.1 simplified to 8 steps per Flatline pass #1 SKP-003 HIGH 770. |
| 2026-05-04 (PRD-driven) | SKP-004 shell-escape safety in merged-aliases.sh: shlex.quote() per value; key/value validation pre-emit; abort on shell metachar. | PRD SKP-004 (SDD-shape) | §3.5 — defense-in-depth at writer layer in addition to schema layer. |
| 2026-05-04 (PRD-driven) | SKP-005 flock-over-NFS hardening: filesystem-type detection blocklist; refuse on NFS/SMB/etc unless `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1`. | PRD SKP-005 (SDD-shape) | §6.6, §1.9 — NFS/SMB advisory-flock hazard mitigation. |
| 2026-05-04 (PRD-driven) | SKP-006 hybrid BB TS-runtime/runtime-overlay divergence: shallow-copy compiled + per-key operator overlay; one-time-per-process `[BB-OVERLAY-OVERRIDE]` emission per overridden key. | PRD SKP-006 (SDD-shape) | §1.4.6 — hybrid pattern divergence detector. |
| 2026-05-04 (SDD pass #1) | §10 Open Questions CLOSED — all 5 cycle-099-scope questions resolved before Sprint 2 implementation. | Flatline SDD pass #1 SKP-001 CRITICAL (910) | §10 — release blocker per Flatline review; resolution prevents late-Sprint-2 rework across codegen, runtime hooks, tests, docs. Resolutions: tiny-tier reuses cycle-095 alias; endpoint_family operator-set per entry; permissions OPTIONAL with NFR-Sec-5 minimal baseline + acknowledge flag; cheval venv reused; loa-doctor-model is stretch goal. |
| 2026-05-04 (SDD pass #1) | Cross-Runtime Golden Test Corpus added — Python, Bash, TS runtimes consume identical fixture set in CI matrix; mismatch fails build. | Flatline SDD pass #1 SKP-002 CRITICAL (890) | §7.6 — resolver-triplication drift hazard; 12 initial fixtures cover happy paths + edge cases (legacy shape, override conflict, extra-only model, empty config, unicode operator-added id, prefer_pro overlay, extra-vs-override collision, tiny-tier resolution, degraded mode). |
| 2026-05-04 (SDD pass #1) | URL canonicalization simplified: 9-step → 8-step; Levenshtein-based punycode-lookalike defense REMOVED in favor of strict normalized-host-matching against allowlist. | Flatline SDD pass #1 SKP-003 HIGH (770) | §6.5 — Levenshtein heuristic too brittle (false-positive risk on legit operator domains; bypass risk via single-char substitutions outside metric); strict allowlist sufficient given cycle-level approval gate. |
| 2026-05-04 (SDD pass #1) | Degraded read-only fallback default; `LOA_OVERLAY_STRICT=1` opt-in for fail-closed; stale-lock recovery via `kill -0` PID check; new NFR-Op-6 documents degraded mode contract. | Flatline SDD pass #1 SKP-004 HIGH (740) | §6.3.2 — fail-closed-on-lock-timeout risks turning environmental quirks (NFS hiccups, container restarts) into total outage. Default degraded with last-known-good fallback; strict mode preserved for ops/CI. |
| 2026-05-04 (SDD pass #1) | `schema_version: 2` top-level field added to `model-config.yaml`; `migrate_v1_to_v2()` auto-upgrade for old configs; permissions wrapper deletion deferred from cycle-100 to **cycle-101 MINIMUM**. | Flatline SDD pass #1 SKP-002 HIGH (720) | §3.1.1 — merged schema has two evolution vectors (cycle-026 permissions + cycle-095 model attrs); explicit versioning enables atomic migration. Cycle-101 minimum allows ≥1 cycle of stable migration before one-way-door deletion. |
| 2026-05-04 (SDD pass #1) | Legacy mode rollback (`LOA_LEGACY_MODEL_PERMISSIONS=1`) enforces one-way sync: `model-config.yaml` is sole writer; `model-permissions.yaml` regenerated derived. Pre-commit hook + CI guard reject manual edits with `[LEGACY-MODE-DUAL-WRITE]`. | Flatline SDD pass #1 SKP-005 HIGH (710) | §3.1.1 — vanilla rollback would re-introduce drift surface (G-3 regression). One-way semantics preserve cycle-099 zero-drift goal even in rollback mode. |
| 2026-05-04 (SDD pass #1) | Lock acquisition contract specified: shared-lock-first-then-upgrade; 5s shared timeout, 30s exclusive timeout (configurable via env vars); stale-lock recovery via `kill -0`. | Flatline SDD pass #1 IMP-001 HIGH_CONSENSUS (865) | §6.3.1 — multi-agent startup race specification; deterministic acquisition order prevents nondeterministic startup failures. |
| 2026-05-04 (SDD pass #1) | Debug Trace + JSON Output Secret Redactor module added at `.claude/scripts/lib/log-redactor.{py,sh}`; URL userinfo + 6 query-string secret patterns; applied to FR-5.7 + FR-5.6 + FR-1.9 generated diagnostics. | Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS (860) | §5.6 — debug traces and JSON outputs are common leak vectors; URL userinfo + query strings are realistic secret carriers. Preserves NFR-Sec-3 ("no new secrets surface introduced") even under operator-misconfiguration. |
| 2026-05-04 (SDD pass #1) | `model_aliases_extra` ADDS new IDs (`oneOf` rejects framework-default collisions); `model_aliases_override` MODIFIES existing IDs (requires framework-default ID); mutually exclusive at entry level. | Flatline SDD pass #1 IMP-004 HIGH_CONSENSUS (765) | §3.3 + JSON Schema — DD-3 originally said "two-different-fields-two-different-semantics" by convention; v1.1 enforces at the schema layer to remove ambiguity and operator-mistake surface. |

### D. Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-05-04 | Initial SDD draft. Resolves DD-1..DD-6 and SDD-shape SKP-003..SKP-006 from PRD v1.3 deferred items. Ready for SDD-level Flatline review (cycle-098 pattern: 2-4 passes). | Architecture Designer |
| 1.1 | 2026-05-04 | **Flatline SDD pass #1 integrated** (`cycle-099-sdd-review.json`, Opus + GPT-5.3-codex + Gemini-3.1-pro-preview, **100% model agreement**, 3 HIGH_CONSENSUS + 6 BLOCKERS): SKP-001 CRITICAL 910 (§10 closed), SKP-002 CRITICAL 890 (§7.6 cross-runtime corpus), SKP-003 HIGH 770 (§6.5 simplified to 8 steps), SKP-004 HIGH 740 (§6.3 degraded fallback), SKP-002 HIGH 720 (§3.1.1 schema_version + cycle-101 deferral), SKP-005 HIGH 710 (§3.1.1 one-way sync), IMP-001 HIGH_CONSENSUS 865 (§6.3.1 lock spec), IMP-002 HIGH_CONSENSUS 860 (§5.6 redactor), IMP-004 HIGH_CONSENSUS 765 (§3.3 mutual-exclusion). Status: ready for `/sprint-plan` after operator review (pass #2 optional). | Architecture Designer |

### E. Sources Cited

- Flatline SDD pass #1: `grimoires/loa/a2a/flatline/cycle-099-sdd-review.json` (2026-05-04, 100% model agreement, 3 HIGH_CONSENSUS + 6 BLOCKERS, kaironic stop after pass #1)
- PRD v1.3: `grimoires/loa/cycles/cycle-099-model-registry/prd.md` (2026-05-04, kaironic plateau at pass #3)
- v1.0 backup: `grimoires/loa/cycles/cycle-099-model-registry/sdd-v1.0.md`

---

*Generated by Architecture Designer Agent. Cycle-099 model-registry consolidation. Operator priority: URGENT. v1.1 integrates Flatline pass #1 at 100% model agreement.*
