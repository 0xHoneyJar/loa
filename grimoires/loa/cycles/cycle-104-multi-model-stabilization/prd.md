# Cycle-104 PRD — Multi-Model Stabilization

**Status**: APPROVED — ready for `/architect`
**Drafted**: 2026-05-12 (post cycle-103 archive `f6d9a763`)
**Approved**: 2026-05-12 via `/plan-and-analyze` (operator @janitooor)
**Author**: Claude Opus 4.7 (1M context) — cycle-104 kickoff session
**Predecessor**: cycle-103-provider-unification (PR #846, merged `7fc875ff`, archived `f6d9a763`)
**Issues**: [#847](https://github.com/0xHoneyJar/loa/issues/847) (main scope), [#848](https://github.com/0xHoneyJar/loa/issues/848) (foundational dependency)
**Sprint count**: 3 (~10-12 days)

---

## How to pick this up in a fresh context window

If you're starting cold on this cycle, read these files first **in order** before doing anything else:

1. **`grimoires/loa/known-failures.md`** (Read-FIRST per `CLAUDE.md`) — KF-003, KF-008 (recurrence-4 close-out), KF-001 (architectural precedent) are load-bearing.
2. **GitHub issues**: [#847](https://github.com/0xHoneyJar/loa/issues/847) (8 ACs, 10 tasks, full proposed architecture) and [#848](https://github.com/0xHoneyJar/loa/issues/848) (`archive-cycle.sh` framework bug — Sprint 1 foundational).
3. **`grimoires/loa/cycles/cycle-103-provider-unification/prd.md`** — substrate this cycle builds on. The cheval Python `httpx` substrate is the unified provider boundary; cycle-104 extends it with within-company fallback chains, headless opt-in, and BB internal dispatcher migration.
4. **`.claude/defaults/model-config.yaml`** — every primary model entry, existing `fallback_chain` examples (e.g., `gemini-3-flash-preview: ["google:gemini-2.5-flash"]` at L_~existing).
5. **`.claude/adapters/loa_cheval/providers/`** — `claude_headless_adapter.py`, `codex_headless_adapter.py`, `gemini_headless_adapter.py` (shipped cycle-099 PR #727 by contributor zksoju; this cycle wires them into routing).
6. **`.loa.config.yaml`** lines 245-257 (current cycle-102 T1B.4 swap — `flatline_protocol.code_review.model: claude-opus-4-7`; reverted to `gpt-5.5-pro` per AC-5).
7. **This file** — cycle-104 scope, 3-sprint plan skeleton, AC mapping.

> Sources: cycle-103 PRD §"How to pick this up" template (`grimoires/loa/cycles/cycle-103-provider-unification/prd.md:11-19`).

---

## 0. Cycle relationship & decisions locked

Cycle-104 follows cycle-103 immediately. Cycle-103 unified the **substrate** (every Loa consumer now flows through cheval `httpx`); cycle-104 hardens the **routing** that runs on top of that substrate.

> From #847 §"Why This Sequencing": "Cycle-103 had to ship first because three parallel adapter implementations (BB Node, Flatline bash, Red Team bash) would have meant doing this work three times. With cycle-103's substrate unification: one place (`cheval.py` + `model-config.yaml`) where chain composition, headless routing, and operator preference get wired up once and propagate everywhere."

Cycle-104 does **three things**:

1. **Unblock framework archival hygiene** (#848). `archive-cycle.sh` targets the pre-per-cycle-subdir layout, producing empty archives for cycles 098+. Also fix BB `dist/` build hygiene so future BB TypeScript changes can't silently ship source-only (cycle-103 near-miss).
2. **Restore cross-company consensus diversity + add operator-opt-in headless** (#847). Within-company fallback chains absorb KF-003-class failures without escaping company boundary. Revert `flatline_protocol.code_review.model` to `gpt-5.5-pro` (the T1B.4 cross-company swap becomes unnecessary). Add `hounfour.headless.mode: prefer-api | prefer-cli | api-only | cli-only` for operators with working local CLIs.
3. **Close KF-008 recurrence-4** by routing BB's internal multi-model parallel dispatcher (`multi-model:google` and siblings) through cheval, just like the review adapter already does. This is the remaining Node-fetch path BB still owns post-cycle-103.

> From `grimoires/loa/known-failures.md` (KF-008 recurrence-4 note): "Architectural closure holds for BB *internal* model dispatcher's Node-fetch path which still hits this — cycle-104 candidate: route BB's multi-model parallel dispatcher through cheval as well."

**Decisions locked at draft time**:

- Cycle-104 is a stabilization-and-hardening cycle, not a feature cycle. Goal: every quality gate's multi-model implementation flows through cheval, with within-company retry chains, with an operator-flippable CLI-only mode.
- Cycle-104 does NOT add new model providers, new agents, or new orchestration patterns. It tightens the routing layer above the cheval substrate.
- **Sprint 1 is foundational** — #848 closure unblocks cycle archival hygiene for every future cycle. Cheap and fast. Clears the path.
- **Sprint 2 is the main event** — #847's 8 ACs / 10 tasks. The fallback-chain + headless-mode + code_review-revert package together.
- **Sprint 3 is the boundary close-out** — BB internal dispatcher → cheval. Closes KF-008 recurrence-4 gap. After Sprint 3, BB owns zero direct provider HTTP code.

> Sources: operator recommendation 2026-05-12 (cycle-103 closure session), issue #847 §"Implementation Plan" (T1-T10), KF-008 recurrence-4 attempts table.

---

## 1. Problem & vision

### 1.1 The problem

After cycle-103, the Loa quality-gate stack has a unified provider substrate (cheval Python `httpx`) but the **routing layer above** still carries three structural defects:

| # | Defect | Source |
|---|--------|--------|
| D1 | **Cross-company swap collapses consensus diversity.** `flatline_protocol.code_review.model: claude-opus-4-7` (`.loa.config.yaml:251`) puts Anthropic in 2 of 3 BB voices. Anthropic outage → 2 of 3 voices vanish. Same architecture → less genuine cross-validation. | `.loa.config.yaml:251`, `.loa.config.yaml:257`; cycle-102 Sprint 1B T1B.4 commit history |
| D2 | **Within-company fallback under-populated.** `fallback_chain` field exists in `model-config.yaml` (used today for `gemini-3-flash-preview: ["google:gemini-2.5-flash"]`) but most primary models have no within-company chain. When the primary fails (rate limit / empty content / overloaded), the only escape is cross-company. | `.claude/defaults/model-config.yaml` (single example); #847 §"Proposed Architecture" |
| D3 | **Headless adapters exist but aren't routed-to.** Cycle-099 PR #727 (contributor zksoju) shipped `codex_headless_adapter.py`, `gemini_headless_adapter.py`, `claude_headless_adapter.py`. They bypass HTTP entirely (spawn local CLI, feed via stdin/stdout — no API keys, no network, no rate limits). The routing layer doesn't surface them as alternatives. | `.claude/adapters/loa_cheval/providers/{claude,codex,gemini}_headless_adapter.py`; #847 §"Gap 2" |
| D4 | **Framework archival hygiene is broken** for cycle 098+ layouts. `archive-cycle.sh:94-111` copies from `${GRIMOIRE_DIR}` root, but per-cycle subdirs at `grimoires/loa/cycles/cycle-NNN-name/` are now canonical. Workaround in active use: skip the script, flip ledger status directly. | `.claude/scripts/archive-cycle.sh:94-111`; #848 §"Reproduction"; cycle-103 closure commit `f6d9a763` |
| D5 | **BB internal multi-model dispatcher still uses Node fetch** even after cycle-103's review-adapter unification. KF-008 closed for the review path, re-fires on the parallel-dispatch path at request_size=539089B (recurrence-4). | KF-008 attempts table row 4; cycle-103 PR #846 BB cycle-3 run `bridgebuilder-...20260511T1316Z` |

### 1.2 The thesis

**The substrate is one place. The routing on top of it should be one place too.**

Within-company fallback chains in `model-config.yaml` give every primary model a structurally-graceful degradation path that never crosses company boundaries. Operator-opt-in headless mode lets the same chain composition adapt to different operator contexts (budget-constrained → `prefer-cli`; CI / production → `prefer-api`; offline / zero-budget → `cli-only`). And BB's last Node-fetch path goes through the same cheval pipe as everything else.

After cycle-104, every quality-gate multi-model implementation in Loa flows through cheval, with within-company retry chains, with an operator-flippable CLI-only mode. **That's the stable flagship state.**

> Sources: operator recommendation 2026-05-12 (end-state articulation); #847 §"Proposed Architecture" §"Per-alias within-company fallback chains" + §"Operator-opt-in headless preference".

### 1.3 Axioms (inherits cycle-103 → cycle-102 vision-019)

1. **Fail loud**: every silent-degradation surface gets a typed error. Chain walks are recorded in `MODELINV/model.invoke.complete.models_failed[]`. (AC-2)
2. **Audit observed state, not configured state**: the resolved chain order, the routes actually taken, the operator-mode in effect — all written to audit. (AC-2, AC-3)
3. **Substrate as answer**: routing-layer fixes ship once in `model-config.yaml` + `cheval` and propagate to every consumer automatically. (#847 §"Why This Sequencing")
4. **Never escape company boundary for retry** — only at consensus aggregation. (#847 §"Gap 1"; AC-1)

---

## 2. Goals & success metrics

### 2.1 Cycle goals

| # | Goal | Measurable outcome |
|---|------|---------------------|
| G1 | Restore 3-company BB consensus diversity | `flatline_protocol.code_review.model: gpt-5.5-pro` restored; BB multi-model invocation log shows Anthropic + OpenAI + Google in the primary slots (AC-5) |
| G2 | Within-company chains absorb KF-003 without cross-company escape | Empirical replay: gpt-5.5-pro chain handles 30K-80K input via fallback to gpt-5.3-codex when primary returns empty (AC-7) |
| G3 | Operator-opt-in headless mode lands | `hounfour.headless.mode` + `LOA_HEADLESS_MODE` env var supported; bats test pins chain reordering under `prefer-cli` (AC-3) |
| G4 | `cli-only` mode runs Loa end-to-end without `*_API_KEY` env vars | Fresh-machine e2e test against zero-budget op-mode passes; audit envelope records `transport: cli` consistently (AC-8) |
| G5 | KF-008 recurrence-4 closed | BB internal multi-model dispatcher routes through cheval; CI drift gate from cycle-103 T1.7 extended to cover the parallel-dispatch path; KF-008 status → `RESOLVED-architectural-complete` |
| G6 | Framework archival hygiene fixed | `archive-cycle.sh --cycle 104 --dry-run` correctly enumerates cycle-104 artifacts from per-cycle subdir; `--retention N` honored; cycle-104 archive is the first proper archive run after the fix |
| G7 | BB dist build hygiene | BB TypeScript changes can't silently ship source-only; pre-commit / CI gate enforces `dist/` regeneration; near-miss from cycle-103 cannot recur |

### 2.2 Cycle non-goals

- **Not a new-feature cycle.** No new model providers, no new quality gates, no new orchestration topologies.
- **Not retrying KF-003/KF-008 fixes that recurrence-≥3 closed.** The structural fixes from cycle-103 stand; cycle-104 extends them to the routing layer.
- **Not breaking changes.** Backward compat: operators who do nothing keep `prefer-api` semantics (same behavior as today); the new `fallback_chain` entries are additive to `model-config.yaml`.

> Sources: #847 §"Acceptance Criteria" (AC-1 through AC-8); #848 §"Proposed fix" + §"Also worth addressing".

---

## 3. Users & stakeholders

| Persona | Role | Cares about |
|---------|------|-------------|
| **Operator @janitooor** (primary) | Loa user running BB / Flatline / Red Team locally | Diversity of consensus; ability to use local CLIs when API budget tight; clean cycle archives; multi-model failure modes that don't silently degrade |
| **Future cycle authors** | Subsequent cycle developers | `archive-cycle.sh` actually archives the work; framework boundary stays clean (no more T1B.4-style cross-company swaps as workarounds) |
| **Downstream Loa adopters** | Users of `0xHoneyJar/loa` consuming framework defaults | `prefer-api` default unchanged; new `prefer-cli` / `cli-only` modes available opt-in; `model-config.yaml` `fallback_chain` extensions are additive |
| **External contributors** (e.g., zksoju for headless adapters PR #727) | Land features whose routing is then wired up by core | Headless adapters from cycle-099 finally have a route to them; capability matrix doc gives clear opt-in surface |

> Sources: project memory (`feedback_operator_collaboration_pattern.md`), cycle-099 PR #727 contributor history.

---

## 4. Functional requirements (per sprint)

### Sprint 1 (Foundational): `archive-cycle.sh` fix + BB dist build hygiene

> **Issue**: [#848](https://github.com/0xHoneyJar/loa/issues/848). Plus BB dist build hygiene (cycle-103 near-miss).
>
> **Rationale**: Without dist clean-step, all future BB TypeScript changes risk shipping source-only and not actually running. Without the archive-cycle fix, every cycle going forward needs the manual ledger-flip workaround. Cheap, fast — clears the path.

| FR | Description | Acceptance |
|----|-------------|------------|
| **FR-S1.1** | `archive-cycle.sh` resolves cycle dir from ledger lookup before copying artifacts. Per-cycle subdirs at `grimoires/loa/cycles/cycle-NNN-name/{prd.md, sdd.md, sprint.md, handoffs/, a2a/}` are the source of truth. | `archive-cycle.sh --cycle 104 --dry-run` enumerates the cycle's prd/sdd/sprint/handoffs/a2a paths correctly; `--retention N` honors N (currently hardcoded 5-archive deletion list does not). |
| **FR-S1.2** | `--retention N` flag actually respects the configured count. Today the deletion list is fixed at 5 specific archives regardless of `N`. | bats test: `--retention 50` does NOT delete the same 5 archives that `--retention 5` does; `--retention 0` keeps all archives. |
| **FR-S1.3** | Copy `handoffs/` subdir (modern equivalent of legacy `a2a/compound/`). Preserve `a2a/` subdir copy for backward compat (cycles ≤097 use it). | Cycle-103 archive (re-run after fix) contains both `handoffs/` and the cycle-103 sub-artifacts. |
| **FR-S1.4** | BB `dist/` regen enforced at pre-commit + CI. Any PR touching `bridgebuilder-review/resources/**.ts` MUST also include the regenerated `dist/**` artifacts. | Pre-commit hook (or `.github/workflows/`) gate fails the PR if `dist/` is stale relative to `src/`. Bats test pins the gate's reject behavior on a contrived `dist/`-out-of-sync fixture. |
| **FR-S1.5** | Operator runbook update: `grimoires/loa/runbooks/cycle-archive.md` (NEW) documenting `archive-cycle.sh --cycle N` semantics, per-cycle subdir layout assumption, and recovery procedure if the script fails (the cycle-103 ledger-flip workaround as documented escape hatch). | Runbook exists, linked from `CLAUDE.md` or `PROCESS.md` (whichever is canonical at land time). |

> Sources: #848 §"Problem" + §"Proposed fix" + §"Also worth addressing"; operator recommendation 2026-05-12 ("BB dist build hygiene") referencing the cycle-103 near-miss.

### Sprint 2 (Main event): Within-company fallback chains + headless opt-in

> **Issue**: [#847](https://github.com/0xHoneyJar/loa/issues/847). 8 ACs, 10 tasks (T1-T10).
>
> **Rationale**: Restore 3-company consensus diversity; give operators `prefer-cli` / `cli-only` modes. Direct multi-model stabilization.

| FR | Description | Acceptance |
|----|-------------|------------|
| **FR-S2.1** | Every primary model in `model-config.yaml` gets an explicit `fallback_chain` ending in a within-company headless adapter (where one exists) or in the smallest within-company model. **No cross-company entries** in any `fallback_chain`. | AC-1 (`grep -A5 "fallback_chain"` of `model-config.yaml` shows every primary covered; no chain entry references a different company prefix). |
| **FR-S2.2** | Headless adapter aliases added to `model-config.yaml` (`anthropic:claude-headless`, `openai:codex-headless`, `google:gemini-headless`) with capability matrix declaring which features each supports (large context / tool use / structured JSON output). | AC-4 (aliases resolvable via existing alias-resolution test corpus from cycle-099 sprint-1D; capability matrix file landed at `grimoires/loa/runbooks/headless-capability-matrix.md`). |
| **FR-S2.3** | `cheval` routing walks `fallback_chain` on transient / rate-limit / overloaded / empty-content errors per cycle-103 T3.1 dispatch table. Walked chain recorded in `MODELINV/model.invoke.complete.models_failed[]`. | AC-2 (bats integration test: simulate primary-empty-content → asserts chain walked, asserts audit envelope `models_failed[]` populated in order). |
| **FR-S2.4** | `hounfour.headless.mode: prefer-api \| prefer-cli \| api-only \| cli-only` config + `LOA_HEADLESS_MODE` env var. `prefer-cli` reorders chain (CLI first, HTTP after); `cli-only` removes HTTP entries entirely. | AC-3 (bats test captures resolved chain via routing tracer under each of 4 modes). |
| **FR-S2.5** | `adversarial-review.sh` cross-company fallback (`flatline_protocol.models.{secondary, tertiary}`) repurposed: ONLY fires when within-company chain is exhausted, AND only to drop the voice from consensus aggregation — NOT to substitute another company's model in the same slot. | AC-1 + AC-2 (the cross-company default fallback is no longer invoked on within-company-recoverable failures; voice-drop on full chain exhaustion is recorded as `consensus.voice_dropped` event). |
| **FR-S2.6** | **Revert `.loa.config.yaml::flatline_protocol.code_review.model` from `claude-opus-4-7` back to `gpt-5.5-pro`.** Same for `security_audit.model`. The cycle-102 T1B.4 cross-company swap becomes unnecessary now that within-company chains handle KF-003. | AC-5 (`grep "code_review" .loa.config.yaml` shows `gpt-5.5-pro`; BB multi-model invocation log shows Anthropic + OpenAI + Google as the 3 primary slots). |
| **FR-S2.7** | Capability gate: each headless adapter declares feature support. Capability mismatch → router skips-and-continues (does NOT fail), recorded in `models_failed[].reason = "capability_mismatch"`. | AC-4 (bats test: request requiring `large_context` (>1M tokens) against `codex-headless` (which lacks large-context support) → router skips, no fail, audit records reason). |
| **FR-S2.8** | Empirical replay (gated `LOA_RUN_LIVE_TESTS=1`) verifying within-company chain closes KF-003 (gpt-5.5-pro empty-content at 27K+ input) by falling back to `gpt-5.3-codex` — without leaving OpenAI. | AC-7 (test fixture: synthetic 30K-80K-input adversarial-review prompt; primary returns empty; fallback walks to codex; audit shows OpenAI-only chain walk). |
| **FR-S2.9** | `cli-only` mode runs Loa end-to-end against a fresh machine with NO `*_API_KEY` env vars set. Every consumer routes via headless; audit envelope records `transport: cli` consistently. | AC-8 (e2e test or operator-runbook-validated procedure; doubles as the offline / zero-budget operator path). |
| **FR-S2.10** | Operator runbook: `grimoires/loa/runbooks/headless-mode.md` covering CLI installation pre-reqs (`codex`, `gemini`, `claude` binaries), capability tradeoffs, when to use which mode, debugging CLI-vs-HTTP discrepancies. | AC-6 (runbook lands at the path; linked from `.loa.config.yaml.example` near the new `hounfour.headless.mode` key). |

> Sources: #847 §"Proposed Architecture" + §"Implementation Plan" (T1-T10 map 1:1 to FR-S2.1-FR-S2.10); #847 §"Acceptance Criteria" (AC-1 through AC-8).

### Sprint 3 (Boundary close-out): BB internal multi-model dispatcher → cheval

> **Issue**: implicit in KF-008 recurrence-4 note + operator recommendation 2026-05-12. May warrant a fresh issue filed during Sprint 3 kickoff for tracker hygiene.
>
> **Rationale**: Cycle-103 closed BB's *review adapter* via cheval delegate. BB's *internal multi-model parallel dispatcher* (`multi-model:google` siblings) still uses Node fetch and re-hits KF-008 at >300KB request bodies. Closes the KF-008 recurrence-4 gap.

| FR | Description | Acceptance |
|----|-------------|------------|
| **FR-S3.1** | BB's internal multi-model parallel dispatcher (the path that produces `multi-model:google`, `multi-model:openai`, `multi-model:anthropic` consensus calls) routes through `python3 cheval.py` instead of Node `fetch`. | All BB consensus invocations in audit show `transport: cheval` (or whatever the canonical token is from cycle-103); zero `fetch failed` errors at request_size ≥300KB on synthetic large-PR replay. |
| **FR-S3.2** | Cycle-103 T1.7 CI drift gate (`no Node-side direct fetch`) extended to cover the parallel-dispatch path. Any PR reintroducing direct Node fetch in `.claude/skills/bridgebuilder-review/resources/**` fails the gate. | bats / GHA test pinning the extended drift gate; positive control + negative control. |
| **FR-S3.3** | Empirical replay closes KF-008 recurrence-4 at the observed body sizes (297KB / 302KB / 317KB / 539KB). | KF-008 status → `RESOLVED-architectural-complete` with closing-evidence ref (commit SHA / PR # of the Sprint 3 land). |
| **FR-S3.4** | BB owns zero direct provider HTTP code after Sprint 3. Verified by inventory grep of `.claude/skills/bridgebuilder-review/resources/**/*.{ts,js}` for `fetch(` / `https.request(` / `undici` imports. | Inventory grep returns zero matches outside test fixtures / type definitions. |

> Sources: KF-008 attempts table row 4 ("cycle-104 candidate: route BB's multi-model parallel dispatcher through cheval as well"); cycle-103 T1.7 drift gate spec (`grimoires/loa/cycles/cycle-103-provider-unification/sdd.md`).

---

## 5. Technical & non-functional requirements

### 5.1 Performance

- **Within-company chain latency budget**: chain-walk should add ≤ 1 retry round-trip per primary failure. No additional p95 latency expected for the happy path (primary success).
- **CLI adapter cold-start**: `prefer-cli` mode acceptable to add ≤ 2s subprocess-spawn overhead per invocation (vs HTTP). Operators who choose `prefer-cli` accept this tradeoff for budget reasons.
- **Audit emit overhead**: `models_failed[]` array growth bounded by chain depth (≤ 5 entries per primary chain in current configs).

### 5.2 Security

- **No `*_API_KEY` exposure under `cli-only` mode**: bats/e2e test asserts no `Authorization: Bearer ...` header / no `*_API_KEY` env var read in the entire run (AC-8).
- **Headless adapter trust boundary**: local CLI binaries (`codex`, `gemini`, `claude`) are pre-existing operator-installed tools. The router does NOT install or update them. Capability matrix documents which features depend on which CLI version (per `grimoires/loa/runbooks/headless-capability-matrix.md`).
- **Audit-chain integrity**: `models_failed[]` writes go through the same `audit_emit` path (lib/audit-envelope) as today — no schema bypass, no signed-payload escape. Schema version bump if `models_failed[].reason = "capability_mismatch"` is a new enum value.

### 5.3 Backward compatibility

- **Default behavior unchanged**: operators who don't set `hounfour.headless.mode` get `prefer-api` (today's behavior).
- **`fallback_chain` additions are additive**: existing operators whose `model-config.yaml` is unchanged see no behavioral diff until the framework defaults propagate (next mount-loa or explicit update-loa).
- **`flatline_protocol.code_review.model` revert is a config change** in `.loa.config.yaml` (not `.claude/defaults/`); operators who have customized this key keep their override. Default ships `gpt-5.5-pro`.

### 5.4 Observability

- Every chain walk produces a single `MODELINV/model.invoke.complete` envelope with `models_failed[]` populated in order. Existing operators reading audit can grep for chain depth without code changes.
- `hounfour.headless.mode` recorded in the envelope (`config_observed.headless_mode`) so audit shows the operator-mode in effect at invocation time (axiom 2 from §1.3).

### 5.5 Constraints

- **`bash -n` is structural-only**: per project memory `feedback_bash_n_is_structural_not_semantic`, content-shape gates are required where command-substitution patterns are forbidden in caller config. Sprint 2 should reuse the cycle-099 Sprint 2C `_loa_overlay_validate_shape` pattern for any new caller-supplied YAML/text reading paths.
- **JCS canonicalization**: any new audit payloads (e.g., `models_failed[].reason` with structured detail) must canonicalize via `lib/jcs.sh` — never substitute `jq -S -c` (cycle-098 invariant).

---

## 6. Scope & prioritization

### 6.1 In scope (MVP — what cycle-104 lands)

- ✅ Sprint 1: archive-cycle.sh fix + BB dist build hygiene (FR-S1.1 through FR-S1.5)
- ✅ Sprint 2: within-company fallback chains + headless opt-in + code_review revert (FR-S2.1 through FR-S2.10)
- ✅ Sprint 3: BB internal multi-model dispatcher → cheval (FR-S3.1 through FR-S3.4)

### 6.2 Out of scope (explicit)

- **No new provider companies** (xAI, Mistral, Cohere). Within-company chains assume the existing Anthropic / OpenAI / Google triad.
- **No prompt-dialect translation between companies** (SKP-002 from cycle-102 sprint-Flatline). Within-company chains assume same dialect family; cross-company fallback would need translation, which is its own design problem deferred to a later cycle.
- **No reorganization of the cheval substrate itself.** Cheval is the answer cycle-103 produced; cycle-104 builds on it.
- **No changes to consensus aggregation math.** Voice-dropping (when full chain exhausts) is the only aggregation-layer change; weighting / quorum logic untouched.
- **No multi-machine / distributed routing.** Headless adapters spawn local CLIs only; no remote-CLI orchestration.

### 6.3 Deferred / future cycles

- **Cross-company dialect translation** for hard primary-down failover (SKP-002 from cycle-102 sprint-Flatline). Currently when within-company chain exhausts, voice is dropped from consensus. A future cycle could add prompt-dialect translation to permit cross-company substitution.
- **xAI / Mistral / Cohere as 4th-company option** if the operator's quality bar warrants 4-way diversity (current 3-way is sufficient for cycle-104's stability goals).
- **`prefer-cli` for cost-tier-by-task-type routing** (e.g., "use headless for cheap tasks, API for expensive tasks"). Cycle-104 ships per-session mode toggle; per-task routing is a future enhancement.

> Sources: #847 §"Acceptance Criteria" + §"Why This Sequencing"; cycle-102 sprint-Flatline SKP-002 (cross-provider dialect translation); operator recommendation 2026-05-12.

---

## 7. Risks & dependencies

### 7.1 Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|-----------|--------|------------|
| R1 | **Within-company chain still doesn't close KF-003** in field conditions (gpt-5.5-pro empty-content recurs in gpt-5.3-codex too) | Medium | High — would invalidate AC-7 + force re-opening the cycle-102 T1B.4 cross-company swap | AC-7 empirical replay (FR-S2.8) gates Sprint 2 closure on demonstrated recovery; if codex-too returns empty, fallback chain ends at `openai:codex-headless` (CLI bypasses the empty-content bug entirely) |
| R2 | **Headless CLI capability gap larger than expected** (codex-headless missing tool-use, gemini-headless missing structured output) — routes through capability gate but operator sees frequent skip events | Medium | Medium — UX wart; not a correctness bug | Capability matrix doc (FR-S2.10) sets expectations; `LOA_HEADLESS_VERBOSE=1` env var surfaces skip events at runtime for operator debugging |
| R3 | **`cli-only` mode reveals cheval has hidden HTTP fallback** for telemetry / metering / version-check that bypasses the routing layer | Low | Medium — would break AC-8 zero-API-key claim | Sprint 2 AC-8 e2e test runs against fresh-machine with `strace`/equivalent to verify zero HTTPS connections; failure here gates Sprint 2 closure |
| R4 | **BB internal dispatcher migration breaks consensus aggregation math** (response shapes differ between cheval-routed vs Node-fetch-routed) | Medium | High — would break BB output | Sprint 3 lands behind feature flag with side-by-side run option; bats / golden-test pins consensus output unchanged for fixed input |
| R5 | **`archive-cycle.sh` retention bug fix breaks downstream tooling** (CI, dashboards) that depended on the old 5-archive deletion list | Low | Low — that list was fixed-hardcoded; nothing should depend on it | FR-S1.2 ships with migration note; if any external tool depends on the old behavior, the bats-pinned test surfaces it pre-merge |
| R6 | **BB `dist/` build hygiene gate produces false positives** (legitimate dist changes flagged as stale) | Medium | Low — pre-commit / CI annoyance | FR-S1.4 gate uses content-hash comparison (not timestamp); test corpus includes "dist matches src" positive controls |

### 7.2 Dependencies

| ID | Dependency | Status |
|----|------------|--------|
| DEP-1 | Cycle-103 cheval substrate landed | ✅ MET — PR #846 merged `7fc875ff` (2026-05-12) |
| DEP-2 | Headless adapters present in `.claude/adapters/loa_cheval/providers/` | ✅ MET — cycle-099 PR #727 (zksoju) |
| DEP-3 | `fallback_chain` field schema in `model-config.yaml` exists | ✅ MET — `gemini-3-flash-preview` uses it today |
| DEP-4 | Cycle-103 T1.7 CI drift gate ("no Node-side direct fetch") | ✅ MET — extending it in Sprint 3 |
| DEP-5 | Cycle-099 alias-resolution test corpus (12 fixture YAMLs + 3 byte-equal runners) for adding new headless aliases | ✅ MET — `tests/fixtures/model-resolution/` |
| DEP-6 | Operator has working `codex` / `gemini` / `claude` CLIs installed (for Sprint 2 AC-8) | ⚠️ Op-side prerequisite. Captured in `headless-mode.md` runbook (FR-S2.10) |
| DEP-7 | Sprint 1 land BEFORE Sprint 2 closes, so cycle-104 archive itself benefits from the fix | Sequencing — Sprint 1 first |

### 7.3 Known sequencing constraints

- **Sprint 1 must merge before Sprint 2 closes.** Sprint 1 fixes `archive-cycle.sh`; cycle-104 needs that fix to archive itself cleanly. Sprint 2 + Sprint 3 can land in either order after Sprint 1.
- **Sprint 2 FR-S2.6 (code_review revert) requires FR-S2.1 (chains populated) to be in effect.** Reverting code_review back to `gpt-5.5-pro` only works once the within-company chain exists to absorb KF-003.
- **Sprint 3 builds on Sprint 2's chain mechanics** insofar as BB's parallel dispatcher will also benefit from `fallback_chain` (each parallel branch can independently walk its company chain).

---

## 8. Cycle-level acceptance summary

Cycle-104 ships when:

- [ ] **Sprint 1 ACs met**: FR-S1.1 through FR-S1.5 (archive-cycle.sh fix; BB dist hygiene; runbook)
- [ ] **Sprint 2 ACs met**: #847 AC-1 through AC-8 (10 tasks; within-company chains; headless opt-in; code_review revert; e2e zero-API-key)
- [ ] **Sprint 3 ACs met**: FR-S3.1 through FR-S3.4 (BB internal dispatcher → cheval; KF-008 recurrence-4 closed)
- [ ] **Cumulative**: every Loa quality gate's multi-model implementation flows through cheval; within-company retry chains exist for every primary; operator-flippable CLI-only mode works end-to-end
- [ ] **Audit trail**: `MODELINV/model.invoke.complete` envelopes record `models_failed[]` chain walks and `config_observed.headless_mode` consistently across BB + Flatline + Red Team
- [ ] **Known-failures ledger updated**: KF-003 closure note (within-company chain absorbs); KF-008 → `RESOLVED-architectural-complete`; new entries (if any) filed
- [ ] **Operator can run `cli-only` mode** offline against a fresh machine — Loa works end-to-end with zero API keys (the offline / zero-budget operator path)

> Sources: #847 §"Acceptance Criteria"; KF-008 closure evidence framework (KF-008 attempts table); operator recommendation 2026-05-12 ("stable flagship state").

---

## 9. Lore connection (optional context)

This cycle pattern-matches **the bridge speaks back** axiom from cycle-102 vision-019 / cycle-100 sprint-3 closures. Cycle-103 made the substrate one thing. Cycle-104 makes the routing on top one thing. After cycle-104, the bridge speaks back consistently regardless of which provider's voice the operator is hearing — the failure modes are uniform, the audit shape is uniform, the operator's escape hatches (`prefer-cli`, `cli-only`, voice-drop) are uniform.

The kaironic time pattern here is the same one cycle-103 surfaced: **substrate as answer**. Two cycles ago, the answer to KF-001 was "fix Happy Eyeballs in BB Node fetch". One cycle ago, the answer was "stop having BB own a Node fetch path at all — route through the unified substrate". This cycle, the answer is "stop having the substrate's routing be implicit — make it operator-readable and operator-flippable, and close the last Node-fetch parallel-dispatch path BB still owns".

The pattern: each cycle's answer becomes the next cycle's substrate. The operator's question "is this actually working?" gets a more structural answer each time. Cycle-104's structural answer is: every chain walk is named, every fallback is enumerated, every operator-mode is observed-and-audited, no Node fetch survives.

> Sources: `feedback_bb_plateau_via_reframe.md` (REFRAME-as-plateau signal pattern); cycle-103 PRD §1.2 ("Cheval is the substrate. BB and Flatline are consumers, not parallel implementations.").

---

## Sources index

This PRD traces to:

- **GitHub issues**: [#847](https://github.com/0xHoneyJar/loa/issues/847), [#848](https://github.com/0xHoneyJar/loa/issues/848), [#845](https://github.com/0xHoneyJar/loa/issues/845) (KF-008 upstream)
- **Known-failures ledger**: `grimoires/loa/known-failures.md` KF-001 (architectural precedent), KF-003 (gpt-5.5-pro empty-content), KF-008 (recurrence-4 closure target)
- **Predecessor cycle**: `grimoires/loa/cycles/cycle-103-provider-unification/prd.md` (substrate); cycle-102-model-stability sprint-1B T1B.4 (the swap to revert)
- **Config**: `.loa.config.yaml:245-257` (current cycle-102 code_review/security_audit overrides); `.claude/defaults/model-config.yaml` (fallback_chain examples)
- **Adapters**: `.claude/adapters/loa_cheval/providers/{claude,codex,gemini}_headless_adapter.py` (cycle-099 PR #727)
- **Operator recommendation**: 2026-05-12 cycle-103 closure session (3-sprint scope + end-state articulation)
- **Project memory**: `feedback_bash_n_is_structural_not_semantic.md`, `feedback_bb_plateau_via_reframe.md`, `feedback_operator_collaboration_pattern.md`, `feedback_autonomous_run_mode.md`

🤖 Drafted in-session during cycle-104 kickoff, 2026-05-12
