# Sprint Plan — Cycle-099: Model Registry Consolidation + Per-Skill Granularity

**Version:** 1.0
**Date:** 2026-05-04
**Author:** Sprint Planner Agent (deep-name + Claude Opus 4.7 1M)
**PRD Reference:** `grimoires/loa/prd.md` (v1.3 — 3 PRD-level Flatline passes; kaironic plateau at pass #3)
**SDD Reference:** `grimoires/loa/sdd.md` (v1.3 — 3 SDD-level Flatline passes; kaironic stop at pass #3)
**Cycle (proposed for ledger):** `cycle-099-model-registry`
**Predecessor cycle:** `cycle-098-agent-network` (sprint counter ended at global_id=138; cycle-099 reservations 139-142)
**Source issue:** [#710](https://github.com/0xHoneyJar/loa/issues/710) — Refactor: consolidate model registries to single source of truth + add config extension mechanism

---

## Executive Summary

Cycle-099 finishes the registry-consolidation work cycle-095 began. It promotes `.claude/defaults/model-config.yaml` (plus operator-zone `.loa.config.yaml::{model_aliases_extra, skill_models, tier_groups}`) to be the **only authoritative model registry** in the framework, eliminating the 13-location drift surface enumerated in PRD §Problem Statement. Operators get a single edit point ("edit one YAML field, get the latest model in your skill of choice") and per-skill tier-tag granularity ("flatline use max, red team use cheap") that composes with cycle-095's `tier_groups` schema. The legacy bash adapter is retired via a gated 4-sprint sunset path.

The plan structures the work as **4 sprints in PRD-locked order**, **no buffer week** (cycle-098 retrospective: a buffer is only needed when sprint integration touches shared mutable state — cycle-099 sprints layer cleanly: Sprint 1 = codegen + drift gate, Sprint 2 = loader changes + runtime overlay, Sprint 3 = doc/persona/permissions migration + dist regen, Sprint 4 = gated default flip). Each sprint is independently shippable behind feature flags; no sprint depends on the next sprint shipping for safety.

The cycle is **acknowledged to be wider than the PRD's original framing** per SDD §8.0: from PRD's "~110 tests, $110-180, 4-5 weeks" to SDD v1.3's "~160 tests, $200-300, 5-6 weeks". The expansion absorbs SDD-pass-#1+#2+#3 hardening (cross-runtime parity, SSRF surface closure, operator-config robustness, latency methodology, overlay-state corruption handling). Operator confirmed at SDD v1.3 review.

**Total Sprints:** 4 (Sprints 1–4; Sprint 4 is gated at sprint-4 review per FR-4.4)
**Sprint Sizing:** Sprint 1 = LARGE (15 tasks); Sprint 2 = LARGE (16 tasks); Sprint 3 = LARGE (11 tasks); Sprint 4 = SMALL/MEDIUM (7 tasks, gate-decision-shaped)
**Estimated Tests:** ~30 (S1) + ~30 (S2) + ~25 (S3) + ~25 (S4) = ~110 PRD baseline + ~40 SDD-v1.2 + ~10 SDD-v1.3 = **~160 tests**
**Estimated Cost:** ~$30-50 per sprint × 4 sprints + cross-cutting test/property/golden = **$200-300** (operator-acknowledged scope expansion per SDD §8.0)
**Estimated Wall-Clock:** ~5-6 weeks with full quality-gate chain per sprint (cycle-098 pattern: implement → review → audit → bridgebuilder kaironic 2-iter → admin-squash)
**Global Sprint IDs (ledger):** Sprint 1 = 139, Sprint 2 = 140, Sprint 3 = 141, Sprint 4 = 142 (assigned by ledger at registration; cycle-099 not yet registered — chore PR follows the cycle-098 #679 pattern after this sprint plan lands per PRD §Out-of-scope line 499)

### Cycle constraints inherited from PRD/SDD

- **Beads workspace UNHEALTHY (#661):** ledger-only fallback per PRD R-5 + cycle-098 documented pattern. Cycle proceeds with `grimoires/loa/ledger.json` as the sole sprint-tracking source of truth. `git commit --no-verify` per cycle-098 RESUMPTION; consider Sprint 0 beads-recovery only if cumulative friction >4h (operator decision at Sprint 0 boundary, per R-5).
- **Deferred Decisions DD-1..DD-6 are RESOLVED** in SDD §11 Appendix C. No release-blocker remains for Sprint 1 entry. Decision log entries to be archived under `grimoires/loa/cycles/cycle-099-model-registry/decisions/` after the cycle directory is created (chore PR).
- **§10 Open Questions CLOSED** per Flatline SDD pass #1 SKP-001 CRITICAL 910. All 5 cycle-099-scope items resolved before Sprint 2 implementation begins; out-of-scope items confirmed deferred to cycle-100+.
- **Cycle scope acknowledgement** (SDD §8.0): 4 sprints + 5 cross-cutting tasks (T1.11..T1.15) absorbed into Sprint 1; v1.3 deliverables (latency-bats, overlay-state-corruption, multi-file-flock, CDN-CIDR-validator, TS-codegen-parity) allocated across sprints per task table. Operator approved scope at SDD v1.3 review.
- **R10 cheval HTTP/2 bug (#675) workaround active** — cycle-098 already shipped `sprint-bug-131` fix; Flatline reviews on cycle-099 sprint docs use the production retry path. No pre-sprint bugfix dependency for cycle-099.
- **R11 weekly Friday schedule-check ritual is ACTIVE** (routine `trig_01E2ayirT9E93qCx3jcLqkLp`, established cycle-098). Continues across cycle-099. Triggered immediately at Sprint 1 kickoff per cycle-098 SDD pass-#4 SOLO_OPUS recommendation.
- **System Zone changes authorized** for: `.claude/defaults/model-config.yaml` (Sprint 3 schema_version=2 migration, per-model `permissions` block per DD-1); `.claude/defaults/loa.defaults.yaml` (Sprint 1 endpoint allowlists, Sprint 4 flatline_routing flip); `.claude/scripts/gen-*.{sh,ts,py}` (cycle-099 codegen scripts); `.claude/scripts/lib/{model-overlay-hook.py, endpoint-validator.{py,sh,ts}, log-redactor.{py,sh}, model-resolver.py}` (canonical references per SDD §1.5.1 + §1.9.1); `.claude/scripts/loa-migrate-model-config.py` (operator-explicit v1→v2 CLI per T1.14); `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` + generated `truncation.generated.ts` + `config.generated.ts` (Sprint 1); `.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.ts` (Sprint 1, generated); `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (Sprint 2); `.claude/data/personas/*.md` + `.claude/skills/bridgebuilder-review/resources/personas/*.md` (Sprint 3 tier-tag migration); `.claude/protocols/{flatline-protocol.md, gpt-review-integration.md}` (Sprint 3); `.github/workflows/{model-registry-drift,python-runner,bash-runner,bun-runner,cross-runtime-diff}.yml` (Sprint 1). Each authorization derives from cycle-099 PRD/SDD per zone-system rule.
- **De-Scope Triggers active** (cycle-098 pattern):
  - Sprint 1 >2 weeks late → re-baseline (split T1.11/T1.12 cross-runtime golden corpus into a follow-up sprint)
  - Any sprint >2× planned duration → HALT + de-scope review with operator
  - Cross-runtime golden parity test failures >3 across Sprint 1+2 → mandate Sprint 2.5 buffer (consolidation week)
  - Bridgebuilder dist regen (T3.7) breaks downstream submodule consumers (R-1) → activate the staged RC tag (T3.10) and rollback runbook (T3.8); pause Sprint 4 until resolved

---

## Sprint Overview

| Sprint | Theme | Scope | Global ID | Duration (target) | Key Deliverables | Dependencies |
|--------|-------|-------|-----------|-------------------|------------------|--------------|
| 1 | SoT Extension Foundation + Cross-Cutting Hardening | LARGE (15 tasks) | 139 | ~1.5 wk | `gen-bb-registry.ts` + Bun-build wiring (FR-1.1.a); Red Team adapter migrations (FR-1.2, FR-1.3); `model-registry-drift.yml` CI gate (FR-5.1); lockfile + checksum (FR-5.4); reproducibility matrix CI (FR-5.5, NFR-Op-5); golden-corpus + 3 cross-runtime runners + cross-runtime-diff CI (T1.11/T1.12, SDD §7.6); log-redactor module (T1.13, SDD §5.6); `loa migrate-model-config` CLI (T1.14, SDD §3.1.1.1); centralized endpoint validator + CI guard (T1.15, SDD §1.9.1); codegen-toolchain runbook (NFR-Op-5) | None — runs against `main` after cycle-098 #720 merge |
| 2 | Config Extension + Per-Skill Granularity + Runtime Overlay | LARGE (16 tasks) | 140 | ~1.5 wk | JSON Schema published (FR-2.2/DD-5); strict-mode loader extension (FR-2.1, FR-2.6); Python overlay hook (T2.3, FR-1.9, DD-4); `.run/merged-model-aliases.sh` writer (T2.4, FR-1.9, §3.5, §6.6); FR-3.9 6-stage resolver in Python+bash twin (T2.6, §1.5); `tier_groups.mappings` probe-confirmed defaults (T2.7); `prefer_pro_models` overlay with FR-3.4 legacy gate (T2.8); legacy-shape backward compat (T2.9, FR-3.7); permissions baseline + acknowledge flag (T2.10, FR-1.4); endpoint allowlist + URL canonicalization + DNS rebinding defense (T2.11, FR-2.8, NFR-Sec-1, §6.5); `model-invoke --validate-bindings` (T2.12, FR-5.6); `LOA_DEBUG_MODEL_RESOLUTION=1` tracing (T2.13, FR-5.7); operator example block in `.loa.config.yaml.example` (T2.14, FR-2.7); network-fs runbook (T2.16, §6.6) | Sprint 1 (golden corpus + runners + drift gate must be green) |
| 3 | Persona + Docs Migration + Model-Permissions Codegen + Bridgebuilder Dist Regen | LARGE (11 tasks) | 141 | ~1 wk | Persona docs `# model:` → `# tier:` (T3.1/T3.2, FR-1.5); protocol docs operator-config references (T3.3, FR-1.6); DD-1 Option B per-model `permissions` block (T3.4, §3.1.1); `gen-model-permissions.sh` codegen (T3.5, §5.3); `model-permissions.yaml` read-path swap (T3.6, FR-1.4); Bridgebuilder `dist/` regenerated from SoT (T3.7, FR-1.1, SC-4); dist rollback runbook (T3.8, R-1); permissions-removal runbook (T3.9, DD-1); cycle-099-dist-RC1 tag (T3.10, R-1) | Sprints 1+2 (loader supports new fields; codegen scripts in place; cross-runtime resolver canonical) |
| 4 (gated) | Legacy Adapter Sunset (Operator Gate Decision) | SMALL/MEDIUM (7 tasks; outcome forks at T4.4) | 142 | ~1 wk | Mark `model-adapter.sh.legacy` DEPRECATED (T4.1, FR-4.1); flip `hounfour.flatline_routing: true` default (T4.2, FR-4.2); `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning (T4.3, FR-4.3); **Sprint 4 gate review with operator** (T4.4, FR-4.4); IF removal: delete legacy adapter + remove flag + publish removal runbook (T4.5, FR-4.6); IF deprecation continues: extend to cycle-100 in NOTES.md (T4.6); E2E goal validation across G-1..G-5 (T4.7, §7.5) | Sprints 1+2+3 (default flip requires hounfour path proven via Sprint 1+2 cross-runtime gates and Sprint 3 dist regen) |

**Total Sprints:** 4
**Total Tasks (excluding gate review):** 49 task items + 1 gate review = 50 work items
**Total Tests Estimated:** ~160 (per SDD §8.0 acknowledgement)
**Total Cost Estimated:** $200-300 (per SDD §8.0 acknowledgement)

---

## Sprint 1: SoT Extension Foundation + Cross-Cutting Hardening

**Global Sprint ID:** 139 (assigned by ledger when cycle-099 cycle directory + ledger entry are created via chore PR)
**Local Sprint ID:** 1
**Cycle:** `cycle-099-model-registry`
**Duration:** ~1.5 weeks
**Scope:** LARGE (15 tasks — exact PRD/SDD-locked count; size justified by 5 cross-cutting tasks T1.11..T1.15 being absorbed into Sprint 1 per SDD §8.0 cycle-scope acknowledgement)

### Sprint Goal

Codegen pipeline + cross-runtime golden test corpus + drift CI gate are operational, hardening primitives (log-redactor, migration CLI, centralized endpoint validator) are in place, and existing skills (Red Team, default `model-adapter.sh`) source from `generated-model-maps.sh` instead of independent registries. **Acceptance theme (SDD §8 Sprint 1): "Codegen and drift gate work; nothing else changes."**

### Deliverables

- [ ] `gen-bb-registry.ts` codegen script reading `.claude/defaults/model-config.yaml` and emitting `truncation.generated.ts` + `config.generated.ts` in the bridgebuilder-review skill (FR-1.1.a)
- [ ] `bun run build` invokes `gen-bb-registry.ts` before `tsc` in the bridgebuilder-review skill build pipeline (FR-1.1.a)
- [ ] `red-team-model-adapter.sh` migrated to `source generated-model-maps.sh` at init (FR-1.2)
- [ ] `red-team-code-vs-design.sh` `--model opus` literal replaced with `--model "$(resolve_alias opus)"` (FR-1.3)
- [ ] `.github/workflows/model-registry-drift.yml` CI workflow runs `--check` mode of all codegen scripts on every PR; non-zero exit blocks merge (FR-5.1, FR-5.2)
- [ ] `model-config.yaml.checksum` lockfile committed alongside source; `tests/integration/lockfile-checksum.bats` verifies checksum matches SHA256 of source (FR-5.4)
- [ ] Codegen reproducibility matrix CI on `ubuntu-latest` + `macos-latest` produces byte-identical output for the same input (FR-5.5, NFR-Op-5)
- [ ] Default `.claude/scripts/model-adapter.sh` (non-legacy) sources `generated-model-maps.sh`, eliminating its own dictionary (FR-1.7)
- [ ] `grimoires/loa/runbooks/codegen-toolchain.md` published documenting required bash 5.x / bun 1.1.x / jq 1.7+ / python 3.11+ + idna ≥3.6 versions (NFR-Op-5)
- [ ] **Golden-test fixture corpus** at `tests/fixtures/model-resolution/` with the 12 initial scenarios (SDD §7.6.3) covering happy-path tier-tag, explicit-pin, missing-tier-fail-closed, legacy-shape-deprecation, override-conflict, extra-only-model, empty-config, unicode-operator-id, prefer-pro-overlay, extra-vs-override-collision, tiny-tier-anthropic, degraded-mode-readonly
- [ ] **3 cross-runtime golden runners** at `tests/python/golden_resolution.py`, `tests/bash/golden_resolution.bats`, `tests/typescript/golden_resolution.test.ts` consume the fixture corpus identically (T1.11, SDD §7.6, resolves Flatline SDD pass #1 SKP-002 CRITICAL 890)
- [ ] **CI workflows wired**: `.github/workflows/python-runner.yml`, `bash-runner.yml`, `bun-runner.yml` run in parallel; `cross-runtime-diff.yml` job downloads all three artifacts and runs canonical-sort byte-comparison; mismatch fails the build (T1.12, SDD §7.6.2)
- [ ] **Debug Trace + JSON Output Secret Redactor** module at `.claude/scripts/lib/log-redactor.{py,sh}` redacts URL userinfo + 6 query-string secret patterns; cross-runtime parity test verifies identical output (T1.13, SDD §5.6, resolves Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS 860)
- [ ] **`loa migrate-model-config` CLI** at `.claude/scripts/loa-migrate-model-config.py` (operator-explicit v1→v2 migration; preserves YAML structure via `ruamel.yaml`; reports field-level changes; exits 0 success / 78 validation failure; idempotent on v2 input). Pure migration logic in `.claude/scripts/lib/model-config-migrate.py` per SDD §3.1.1.1 contract (T1.14, resolves Flatline SDD pass #2 SKP-001 CRITICAL 910 + IMP-004 HIGH_CONSENSUS 835)
- [ ] **Centralized Endpoint Validator** at `.claude/scripts/lib/endpoint-validator.py` (Python canonical reference) + `endpoint-validator.sh` (bash wrapper invoking Python via `python3 -m endpoint_validator`) + TS port at `.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.ts` (build-time generated via `gen-endpoint-validator-ts.sh` from a Jinja2 template per SDD pass #3 IMP-002 880). Cross-runtime parity tests at `tests/integration/endpoint-validator-cross-runtime.bats`. PR-level CI guard in `model-registry-drift.yml` asserts `urllib.parse` imports only in `endpoint-validator.py`, no direct `curl`/`wget` outside `endpoint-validator.sh`, no direct `fetch(`/`http.request` outside `endpoint-validator.ts` (T1.15, SDD §1.9.1, resolves Flatline SDD pass #2 SKP-006 CRITICAL 870)

### Acceptance Criteria

- [ ] **AC-S1.1** — Running `bun run build` from `.claude/skills/bridgebuilder-review/` produces `truncation.generated.ts` + `config.generated.ts` whose contents match a fresh `gen-bb-registry.ts` invocation byte-for-byte (FR-1.1.a, SC-8 partial)
- [ ] **AC-S1.2** — `red-team-model-adapter.sh` invoking `resolve_alias opus` returns the YAML-aliased canonical model (no internal bash dict consulted) (FR-1.2)
- [ ] **AC-S1.3** — `red-team-code-vs-design.sh` invoked with the framework default resolves `--model "$(resolve_alias opus)"` to the cycle-099 alias chain output (FR-1.3)
- [ ] **AC-S1.4** — `.github/workflows/model-registry-drift.yml` exits non-zero when a hand-edit to `truncation.generated.ts` diverges from a fresh `gen-bb-registry.ts` regen on the same `model-config.yaml` (FR-5.1, FR-5.2, SC-8)
- [ ] **AC-S1.5** — `model-config.yaml.checksum` lockfile contents equal `sha256sum < model-config.yaml`; `tests/integration/lockfile-checksum.bats` PASSES on green main; FAILS when source mutated without checksum update (FR-5.4)
- [ ] **AC-S1.6** — `tests/integration/legacy-adapter-still-works.bats` PASSES — sentinel that nothing in the cycle-098 / cycle-097 / cycle-095 Flatline + Red Team + Bridgebuilder behavior regressed under Sprint 1's changes (SC-6 partial; pre-Sprint-2 sentinel per SDD §7.2)
- [ ] **AC-S1.7** — Codegen matrix CI on `ubuntu-latest` AND `macos-latest` produce byte-identical output for the same input (FR-5.5, NFR-Op-5)
- [ ] **AC-S1.8** — `grimoires/loa/runbooks/codegen-toolchain.md` exists, documents the pinned bash/bun/jq/python/idna versions, and includes operator-facing `loa doctor`-style verification steps (NFR-Op-5)
- [ ] **AC-S1.9** — All 12 initial golden fixtures resolve identically across the 3 runtime runners; `cross-runtime-diff.yml` exits zero only when canonicalized output is byte-equal (T1.11, T1.12, SDD §7.6.2, SDD §7.6.3)
- [ ] **AC-S1.10** — `tests/integration/log-redactor-cross-runtime.bats` PASSES — Python and bash log-redactor produce identical redacted output for the SDD §5.6 test corpus (T1.13)
- [ ] **AC-S1.11** — `loa migrate-model-config` CLI invoked on a v1 fixture produces a valid v2 file (post-migration full v2 schema validation passes); idempotent on a v2 input; exits 78 on validation failure with structured error per SDD §3.1.1.1 (T1.14)
- [ ] **AC-S1.12** — `tests/integration/endpoint-validator-cross-runtime.bats` PASSES — Python canonical reference + bash wrapper + TS port produce identical accept/reject for the SDD §1.9.1 fixture corpus; PR-level CI guard rejects direct `urllib.parse` / `curl` / `wget` / `fetch(` use outside the validator (T1.15)
- [ ] **AC-S1.13** — Sprint 1 quality-gate chain passes: `/implement sprint-1` → `/review-sprint sprint-1` → `/audit-sprint sprint-1` → bridgebuilder kaironic (≤2 iterations per cycle-098 empirical signal) → admin-squash merge

### Technical Tasks

<!-- Each task annotated with PRD goal contributions per Appendix C -->

- [ ] **T1.1** — Create `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` reading `model-config.yaml`, emitting `truncation.generated.ts` + `config.generated.ts`. → **[G-1, G-3, G-4]**
- [ ] **T1.2** — Wire `bun run build` to invoke the generator before `tsc`. → **[G-3, G-4]**
- [ ] **T1.3** — Migrate `.claude/scripts/red-team-model-adapter.sh` to `source generated-model-maps.sh` at init. → **[G-1, G-3]**
- [ ] **T1.4** — Migrate `.claude/scripts/red-team-code-vs-design.sh` `--model opus` literal to `--model "$(resolve_alias opus)"`. → **[G-1, G-3]**
- [ ] **T1.5** — Create `.github/workflows/model-registry-drift.yml` — CI drift gate covering `generated-model-maps.sh`, `dist/truncation.js`, `dist/config.js`, and (Sprint 3) `model-permissions.generated.yaml`. → **[G-3]**
- [ ] **T1.6** — Create `model-config.yaml.checksum` lockfile + `tests/integration/lockfile-checksum.bats` (PR-checked). → **[G-3]**
- [ ] **T1.7** — Add codegen reproducibility matrix CI (`ubuntu-latest` + `macos-latest`); both must produce byte-identical output. → **[G-3]**
- [ ] **T1.8** — Update default `.claude/scripts/model-adapter.sh` (non-`.legacy`) to source `generated-model-maps.sh` (per FR-1.7 verification: cycle-095 vision-011 may already have done part of this — verify against current state and finish migration). → **[G-1, G-3]**
- [ ] **T1.9** — Publish `grimoires/loa/runbooks/codegen-toolchain.md` (NFR-Op-5; pinned bash 5.x / bun 1.1.x / jq 1.7+ / python 3.11+ / idna ≥3.6). → **[G-1]** (operability of the single edit point)
- [ ] **T1.10** — Sprint 1 test deliverables per SDD §7.2: `tests/unit/gen-bb-registry-codegen.bats`, `tests/integration/bridgebuilder-dist-drift.bats`, `tests/integration/legacy-adapter-still-works.bats`, `tests/perf/model-overlay-hook-bench.bats`, `tests/integration/lockfile-checksum.bats`. → **[G-1, G-3]**
- [ ] **T1.11** — Build golden-test fixture corpus (12 initial fixtures per SDD §7.6.3) + 3 cross-runtime runners at `tests/python/golden_resolution.py`, `tests/bash/golden_resolution.bats`, `tests/typescript/golden_resolution.test.ts` (resolves Flatline SDD pass #1 SKP-002 CRITICAL 890). → **[G-1, G-3]**
- [ ] **T1.12** — Wire CI workflows: `.github/workflows/python-runner.yml`, `bash-runner.yml`, `bun-runner.yml`, `cross-runtime-diff.yml`. Mismatch fails build per SDD §7.6.2. → **[G-3]**
- [ ] **T1.13** — Implement Debug Trace + JSON Output Secret Redactor at `.claude/scripts/lib/log-redactor.{py,sh}`; cross-runtime parity test (resolves Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS 860). → **[G-3]** (drift = 0 includes diagnostic output drift)
- [ ] **T1.14** — Implement `loa migrate-model-config` CLI at `.claude/scripts/loa-migrate-model-config.py` (operator-explicit v1→v2 migration); pure migration logic in `.claude/scripts/lib/model-config-migrate.py` per SDD §3.1.1.1 (resolves Flatline SDD pass #2 SKP-001 CRITICAL 910 + IMP-004 HIGH_CONSENSUS 835). → **[G-1]**
- [ ] **T1.15** — Implement Centralized Endpoint Validator: `.claude/scripts/lib/endpoint-validator.{py,sh,ts}` + Jinja2 template + `gen-endpoint-validator-ts.sh` + cross-runtime parity tests + PR-level CI guard (resolves Flatline SDD pass #2 SKP-006 CRITICAL 870). → **[G-3]**

### Dependencies

- **External**: None — runs against `main` after cycle-098 PR #720 merged (already in HEAD: 19d6336f)
- **Cycle-098 carryforwards**: `lib/jcs.sh` library (used by SDD §1.5.1 cross-runtime canonicalization invariants); cheval venv (`.claude/scripts/lib/cheval-venv/`) reused for the model-overlay-hook in Sprint 2 per DD-4 §10.1.4
- **Cycle-095 carryforwards**: existing `gen-adapter-maps.sh`; existing `tier_groups` schema (mappings empty); existing `aliases` namespace; existing `backward_compat_aliases`; existing `prefer_pro_models` flag

### Security Considerations

- **Trust boundaries**: CI runners execute codegen scripts against operator-controlled inputs only via the framework defaults pathway (`.claude/defaults/model-config.yaml`). No operator config reaches Sprint 1 codegen — that's Sprint 2 territory. Sprint 1 hardens primitives (T1.13 redactor, T1.15 endpoint validator) that Sprint 2 will rely on.
- **External dependencies**: Bun (already a Bridgebuilder dependency); Python 3.11+ (cheval); jq 1.7+ (existing tooling); idna ≥3.6 (per R-SDD-5 mitigation, pinned in toolchain runbook). No new runtime dependencies introduced for the framework consumers.
- **Sensitive data**: API keys remain in env vars (NFR-Sec-3 unchanged). The log-redactor (T1.13) ensures debug traces and JSON outputs cannot leak URL userinfo or query-string secrets even if operators enable `LOA_DEBUG_MODEL_RESOLUTION=1` (Sprint 2 flag) on a production agent.

### Risks & Mitigation (Sprint-1-specific from PRD R-1..R-10 + SDD R-SDD-1..R-SDD-8)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R-SDD-7 underspread**: Property test runner generates non-representative configs (Sprint 1 ships golden corpus + Sprint 2 ships property tests; Sprint 1 must seed corpus with edge cases that property generator may miss) | LOW | MEDIUM | Sprint 1 fixture corpus explicitly includes `08-unicode-operator-id`, `10-extra-vs-override-collision`, `12-degraded-mode-readonly` per §7.6.3. Operators reproducing failures pin the seed (deterministic-seeded property generator in DD-6) |
| **R-SDD-5**: Python `idna` library version skew between operator machines and CI | LOW | MEDIUM | T1.9 codegen-toolchain runbook pins `idna ≥3.6`; T1.7 reproducibility matrix CI verifies cross-platform parity |
| **R-8**: `gen-bb-registry.ts` Bun dependency breaks in CI environments without Bun | LOW | LOW | Bun is already a Bridgebuilder dependency; CI containers already include Bun; T1.7 matrix CI verifies on both Linux + macOS runners |
| **R-4**: Drift detection CI false positives (regenerate produces non-deterministic output) | LOW | MEDIUM | Lockfile + reproducibility matrix; T1.6 + T1.7 collectively eliminate non-determinism. Codegen scripts produce sorted, stable output (per FR-5.5 canonical serialization rules) |
| **R-5 Sprint-1 friction**: Beads UNHEALTHY (#661) workaround across 15 tasks adds cumulative time | MEDIUM | MEDIUM | Ledger fallback per cycle-098 pattern; `git commit --no-verify` on each commit; track cumulative friction at sprint mid-point — if >4h, escalate to operator for Sprint 0 beads recovery decision |
| **R-1 deferred**: Bridgebuilder TS dist regeneration breaks downstream (Sprint 1 only generates the `.generated.ts` source files; full `dist/` regen is Sprint 3) | — | — | Sprint 1 does NOT regenerate `dist/`; that work lives in T3.7 with the staged RC tag (T3.10) and rollback runbook (T3.8) per R-1 v1.1 strengthening |

### Success Metrics

- Codegen produces byte-identical output across `ubuntu-latest` + `macos-latest` (FR-5.5 reproducibility) — measured: 0 byte diffs in matrix CI
- CI drift gate exits non-zero on every hand-edited generated artifact — measured: planted-divergence smoke test fails CI as expected
- Cross-runtime golden parity: 12 fixtures × 3 runtimes × resolution_path byte-equality — measured: 0 mismatches in `cross-runtime-diff.yml`
- Sprint 1 cumulative wall-clock: ≤1.5 weeks (within de-scope trigger)
- Sprint 1 cost: ≤$50 (within PRD §Timeline budget)

---

## Sprint 2: Config Extension + Per-Skill Granularity + Runtime Overlay

**Global Sprint ID:** 140 (assigned by ledger)
**Local Sprint ID:** 2
**Cycle:** `cycle-099-model-registry`
**Duration:** ~1.5 weeks
**Scope:** LARGE (16 tasks — exact PRD/SDD-locked count; size justified by 4 of the 6 P0 functional-requirement areas — FR-2, FR-3 majority, FR-1.9, FR-5.6/5.7 — landing in Sprint 2 simultaneously per the SDD §8 acceptance theme: "Operator can extend; tier-tag granularity works; legacy still works.")

### Sprint Goal

Operators can register new models in `.loa.config.yaml::model_aliases_extra`, express per-skill tier-tag granularity in `skill_models`, and observe the FR-3.9 6-stage deterministic resolver via `model-invoke --validate-bindings` and `LOA_DEBUG_MODEL_RESOLUTION=1`. Legacy config shapes continue working with deprecation warnings (one-cycle window). Endpoint allowlist + URL canonicalization + DNS rebinding defense are operational. **Acceptance theme (SDD §8 Sprint 2): "Operator can extend; tier-tag granularity works; legacy still works."**

### Deliverables

- [ ] `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` published — normative JSON Schema for `model_aliases_extra` entries; ajv-validated in TS, jsonschema-validated in Python (DD-5, FR-2.2)
- [ ] Strict-mode loader (cycle-095) extended to accept new top-level fields: `model_aliases_extra`, `model_aliases_override`, `skill_models`, `tier_groups.mappings` (FR-2.1, FR-2.6)
- [ ] `.claude/scripts/lib/model-overlay-hook.py` — Python startup hook reads `model-config.yaml ∪ .loa.config.yaml::model_aliases_extra` and writes `.run/merged-model-aliases.sh` (DD-4, FR-1.9)
- [ ] `.run/merged-model-aliases.sh` writer with atomic-write (`tempfile + rename(2)`) + `flock` exclusive/shared semantics + SHA256 invalidation + monotonic version header + shell-escape via `shlex.quote()` (FR-1.9, SDD §3.5, SDD §6.6)
- [ ] `.claude/scripts/model-adapter.sh` updated to source `.run/merged-model-aliases.sh` with version-mismatch detection (re-read after exclusive-lock acquisition on mismatch) (FR-1.9)
- [ ] FR-3.9 6-stage resolution algorithm — Python canonical reference at `.claude/scripts/lib/model-resolver.py`; bash twin at `.claude/scripts/lib/model-resolver.sh` (sources merged-aliases.sh and applies the same stage ordering); cross-runtime parity verified via Sprint 1 golden corpus runners (FR-3.9, SDD §1.5)
- [ ] `tier_groups.mappings` populated with probe-confirmed defaults (`max` → top-of-provider, `cheap` → budget-tier, `mid` → middle-tier, `tiny` per cycle-095 alias) per SDD §3.1.2 (FR-3.2)
- [ ] `prefer_pro_models` overlay implementation with FR-3.4 legacy-shape gate (`respect_prefer_pro: true` opt-in for legacy shapes during deprecation window) (FR-3.4)
- [ ] Legacy-shape backward compat: `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model` continue resolving with deprecation warning (FR-3.7)
- [ ] Permissions baseline check: operator-added models default to NFR-Sec-5 minimal baseline (`chat` only); `acknowledge_permissions_baseline: true` flag required to opt in (FR-1.4)
- [ ] Endpoint allowlist + URL canonicalization + DNS rebinding defense per SDD §6.5 + §1.9 (T2.11, FR-2.8, NFR-Sec-1)
- [ ] `model-invoke --validate-bindings` CLI per SDD §5.2: `--format json|text`, exit codes 0/1/78 (FR-5.6)
- [ ] `LOA_DEBUG_MODEL_RESOLUTION=1` env-var enables structured `[MODEL-RESOLVE]` stderr logs per FR-5.7 (T2.13)
- [ ] `.loa.config.yaml.example` updated with worked examples for UC-1 (operator adopts new model) and UC-2 (per-skill cost/quality tradeoff) (FR-2.7)
- [ ] `grimoires/loa/runbooks/network-fs-merged-aliases.md` published documenting the SDD §6.6 NFS/SMB advisory-flock hazard mitigation (T2.16)

### Acceptance Criteria

- [ ] **AC-S2.1** — `tests/unit/model-aliases-extra-schema.bats` PASSES — JSON Schema validation rejects malformed entries, missing required fields, duplicate model IDs (FR-2.2, SC-2 partial)
- [ ] **AC-S2.2** — `tests/integration/model-aliases-extra-security.bats` PASSES — NFR-Sec-1.1 SSRF + injection corpus covers: localhost endpoint rejection (`127.0.0.1`, `::1`); IMDS rejection (`169.254.169.254`); RFC 1918 rejection; shell-metachar `api_id` rejection; DNS rebinding rejection at request time; HTTP redirect denial across trust boundaries; permission-escalation rejection (per FR-1.4) (NFR-Sec-1.1, SC-11)
- [ ] **AC-S2.3** — `tests/integration/legacy-config-golden.bats` PASSES — SC-13 4 fixture configs × ~5 assertions verify cycle-098-vintage `.loa.config.yaml` resolves identically before/after cycle-099 migration code lands (SC-13)
- [ ] **AC-S2.4** — `tests/integration/model-resolution-golden.bats` PASSES — SC-9 10+ scenarios × 4 skills (Flatline, Red Team, Bridgebuilder, Adversarial Review) verify (skill, role) → expected `provider:model_id` AND expected `resolution_path` matches FR-3.9 algorithm (SC-9)
- [ ] **AC-S2.5** — `tests/property/model-resolution-properties.bats` PASSES — SC-14 6 invariants from FR-3.9 hold across ~600 random valid configs per CI run; 0 invariant violations across 1000-iteration nightly stress (SC-14)
- [ ] **AC-S2.6** — `tests/integration/url-canonicalization.bats` PASSES — §6.5 corpus (HTTPS-only enforcement; default port enforcement; path normalization rejection of `..`/`./`/repeated slashes; IDN/punycode safe handling)
- [ ] **AC-S2.7** — `tests/integration/merged-aliases-shell-escape.bats` PASSES — §3.5 corpus verifies operator-controlled values escaped via `shlex.quote()` survive bash sourcing without injection
- [ ] **AC-S2.8** — `tests/integration/flock-network-fs-detection.bats` PASSES — §6.6 NFS/SMB detection blocklist refuses without `LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1`
- [ ] **AC-S2.9** — `tests/unit/model-overlay-hook.py.test` PASSES — pytest unit tests for the Python startup hook
- [ ] **AC-S2.10** — `model-invoke --validate-bindings --format json` produces a JSON array of `{skill, role, resolved_provider_id, resolution_path}` tuples per SDD §5.2; exit 0 for clean resolution, exit 78 for schema-invalid `model_aliases_extra`, exit 1 for unresolved bindings (FR-5.6)
- [ ] **AC-S2.11** — `LOA_DEBUG_MODEL_RESOLUTION=1` produces `[MODEL-RESOLVE]` stderr logs with stage-by-stage outcomes per FR-5.7; per-resolution overhead <2ms (FR-5.7)
- [ ] **AC-S2.12** — `tests/integration/overlay-resolution-latency.bats` PASSES on `ubuntu-latest` + `macos-latest` per SDD §7.5.1: p95 ≤50ms (warm cache, 1000-iter post-50-warmup); cold-cache regen budget separately measured at p95 ≤500ms in `overlay-resolution-latency-cold.bats` (NFR-Perf-1)
- [ ] **AC-S2.13** — Operator E2E test (UC-1): fresh-clone repo + sample `.loa.config.yaml` with `model_aliases_extra` entry for hypothetical `gpt-5.7-pro` → `model-invoke --validate-bindings` resolves `flatline_protocol.primary` to `openai:gpt-5.7-pro` (SC-2)
- [ ] **AC-S2.14** — Operator config audit (UC-2): `skill_models: { flatline_protocol: {primary: max, secondary: max, tertiary: max}, red_team: {primary: cheap}, bridgebuilder: {opus_role: max, gpt_role: max, gemini_role: cheap} }` resolves to ≤10 lines (SC-3)
- [ ] **AC-S2.15** — Failure path (FR-3.8 fail-closed): operator binds skill to unmapped tier; agent refuses to start with structured `[BINDING-UNRESOLVED]` error listing all unresolved bindings + 3 remediation paths (SC-10)
- [ ] **AC-S2.16** — Sprint 2 quality-gate chain passes: `/implement sprint-2` → `/review-sprint sprint-2` → `/audit-sprint sprint-2` → bridgebuilder kaironic (≤2 iterations) → admin-squash merge

### Technical Tasks

- [ ] **T2.1** — Define + ship `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` per DD-5; jsonschema-validated in Python; ajv-validated in TS. → **[G-1, G-3]**
- [ ] **T2.2** — Update strict-mode loader (cycle-095) to accept `model_aliases_extra`, `model_aliases_override`, `skill_models`, `tier_groups.mappings`. → **[G-1, G-2]**
- [ ] **T2.3** — Implement Python startup hook `.claude/scripts/lib/model-overlay-hook.py` per DD-4; reuses cheval venv per §10.1.4. → **[G-1]**
- [ ] **T2.4** — Implement `.run/merged-model-aliases.sh` writer with atomic-write (tempfile + `rename(2)` POSIX-atomic) + `flock` exclusive/shared semantics + SHA256 invalidation under shared lock + version header + `shlex.quote()` shell-escape per SDD §3.5 + §6.6. → **[G-1]**
- [ ] **T2.5** — Update `model-adapter.sh` to source `.run/merged-model-aliases.sh` with version-mismatch detection. → **[G-1]**
- [ ] **T2.6** — Implement FR-3.9 6-stage resolution algorithm: Python canonical reference at `.claude/scripts/lib/model-resolver.py`; bash twin at `.claude/scripts/lib/model-resolver.sh`; cross-runtime parity via Sprint 1 golden corpus runners (FR-3.9, §1.5). → **[G-1, G-2]**
- [ ] **T2.7** — Populate `tier_groups.mappings` with probe-confirmed defaults via `model-health-probe.sh` per cycle-095 pattern; per-provider mapping reviewed in Sprint 2 design doc per SDD §3.1.2. → **[G-2]**
- [ ] **T2.8** — Implement `prefer_pro_models` overlay with FR-3.4 legacy-shape gate (`respect_prefer_pro: true` opt-in default false during deprecation window). → **[G-2]**
- [ ] **T2.9** — Implement legacy-shape backward compat: `flatline_protocol.models.{primary,secondary,tertiary}`, `bridgebuilder.multi_model.models[]`, `gpt_review.models.{primary,secondary}`, `adversarial_review.model` resolve via deprecation warning + framework-default fallback per FR-3.7 (the ONE EXCEPTION to FR-3.8 fail-closed semantics, time-bounded to one cycle). → **[G-1]** (registry consolidation requires backward-compat path)
- [ ] **T2.10** — Implement permissions baseline check + `acknowledge_permissions_baseline: true` opt-in per FR-1.4. Reject operator-added models with no baseline AND no acknowledgement flag. → **[G-1]** (operator extension safety)
- [ ] **T2.11** — Implement endpoint allowlist + URL canonicalization (Python `urllib.parse.urlsplit`, HTTPS-only, default-port enforcement, path normalization) + DNS rebinding defense (resolve-and-verify at request time) + HTTP redirect denial across trust boundaries + provider-CDN exemption mechanism per SDD §1.9 + §6.5. → **[G-1, G-3]**
- [ ] **T2.12** — Implement `model-invoke --validate-bindings` per SDD §5.2: input = effective merged config; output `--format json` JSON array of `{skill, role, resolved_provider_id, resolution_path}`; pretty-print `--format text`; `--diff-bindings` flag emits `[BINDING-OVERRIDDEN]` per SDD §1.5.2; exit codes 0/1/78. → **[G-1, G-2]**
- [ ] **T2.13** — Implement `LOA_DEBUG_MODEL_RESOLUTION=1` runtime tracing per FR-5.7; <2ms per-resolution overhead; structured `[MODEL-RESOLVE]` stderr log; integrates Sprint 1 T1.13 log-redactor for secret redaction in trace output. → **[G-2]**
- [ ] **T2.14** — Update `.loa.config.yaml.example` with worked examples (UC-1, UC-2) per FR-2.7. → **[G-2]**
- [ ] **T2.15** — Sprint 2 test deliverables per SDD §7.3: `model-aliases-extra-schema.bats`, `model-aliases-extra-security.bats`, `legacy-config-golden.bats`, `model-resolution-golden.bats`, `model-resolution-properties.bats`, `url-canonicalization.bats`, `merged-aliases-shell-escape.bats`, `flock-network-fs-detection.bats`, `model-overlay-hook.py.test`, `overlay-resolution-latency.bats` (warm + cold variants per SDD §7.5.1). → **[G-1, G-2, G-3]**
- [ ] **T2.16** — Publish `grimoires/loa/runbooks/network-fs-merged-aliases.md` documenting the SDD §6.6 NFS/SMB hazard + LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES opt-in. → **[G-1]** (operability)

### Dependencies

- **Sprint 1**: golden corpus + 3 cross-runtime runners + `cross-runtime-diff.yml` MUST be green; lockfile + drift gate operational; T1.13 log-redactor in place (T2.13 integrates it); T1.14 migration CLI available for operators on cycle-098-vintage configs; T1.15 endpoint validator in place (T2.11 wraps it)
- **Cycle-095**: existing `tier_groups` schema (mappings empty); existing `aliases` namespace; `prefer_pro_models` flag; `backward_compat_aliases`; cheval venv reused for T2.3 per DD-4 §10.1.4
- **Cycle-098**: `lib/jcs.sh` for the §1.5.1 cross-runtime canonicalization invariants

### Security Considerations

- **Trust boundaries**: `.loa.config.yaml` is operator zone; `model_aliases_extra` entries are operator-controlled. Sprint 2 hardens this surface via T2.11 (endpoint allowlist + canonicalization + DNS rebinding) + T2.10 (permissions baseline rejection) + T2.1 (JSON Schema validation) + T2.4 (`shlex.quote()` shell-escape). Defense in depth: schema validation at config load, URL canonicalization at request time, DNS rebinding check at request time, shell-escape at merged-aliases write time.
- **External dependencies**: Python `idna ≥3.6` (per Sprint 1 toolchain pin); `urllib.parse` (stdlib); jsonschema (cheval venv); ajv (Bridgebuilder). No new runtime dependencies.
- **Sensitive data**: Sprint 2 introduces NFR-Sec-5 — `auth` field rejected in `model_aliases_extra` (operator-defined credentials NOT supported in v1; reuses provider's existing credential env var per cycle-095). T2.13 trace output runs through T1.13 log-redactor before stderr write.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R-2**: Operator's existing `.loa.config.yaml` stops working when loader rejects new fields | MEDIUM | MEDIUM | T2.2 strict-mode extension preserves cycle-098 fields; T2.9 legacy-shape backward compat with deprecation warning; T1.14 migration CLI provides operator-explicit upgrade path |
| **R-SDD-1**: Python startup hook adds ~30ms wall-clock to agent startup → frequent feel-slow complaints | LOW | LOW | T2.4 SHA256 short-circuit: skip regen if input SHA matches header; AC-S2.12 latency gate enforces NFR-Perf-1 ≤50ms p95; cold-cache regen ≤500ms p95 measured separately |
| **R-SDD-2**: `model_aliases_override` semantics ambiguous when override target has nested `pricing` block | MEDIUM | MEDIUM | DD-3 locked partial-merge with explicit-fields-win at depth 2 per SDD §3.3; T2.15 `model-aliases-override-merge-semantics.bats` covers depth-2 partial-merge corpus |
| **R-SDD-4**: flock-on-NFS detection has false-positives | LOW | LOW | T2.16 runbook + LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES opt-in covers false-positive case; AC-S2.8 smoke-test on a known-fuse mount |
| **R-SDD-5**: URL canonicalization IDN handling depends on Python `idna` library version | LOW | MEDIUM | Pinned in Sprint 1 toolchain runbook (`idna ≥3.6`); T2.6 cross-runtime parity via golden corpus catches version skew |
| **R-SDD-7**: Property test runner generates non-representative configs | LOW | MEDIUM | T2.15 property generator deterministic-seeded per DD-6; CI logs seed; 1000-iter nightly stress catches state-space gaps; AC-S2.5 enforces 0 invariant violations |
| **R-9**: Operator adds malformed `model_aliases_extra` entry that crashes loader at startup | LOW | LOW | T2.1 JSON Schema validation rejects malformed entries with structured error; loader fails-fast at startup with clear remediation hint |
| **R-6**: tier_groups mapping defaults populated wrong (e.g., `max` resolves to deprecated model) | MEDIUM | MEDIUM | T2.7 explicit probe-confirmation via `model-health-probe.sh`; per-provider mapping reviewed in Sprint 2 design doc; operator override always wins per FR-3.9 stage 1 |
| **R-SDD-8**: Cycle-098 `audit_emit` flock pattern collides with cycle-099 `merged-aliases.sh.lock` | LOW | LOW | Different lock files (`audit-*.lock` vs `merged-model-aliases.sh.lock`); different invocation timing; AC-S2.9 verifies via `lsof -p <pid>` audit |

### Success Metrics

- Operator E2E test (UC-1, UC-2): both succeed end-to-end (SC-2, SC-3)
- All 4 P0 SC criteria related to Sprint 2 satisfied: SC-2, SC-3, SC-7, SC-9, SC-10, SC-11, SC-12, SC-13, SC-14
- FR-3.9 6-stage resolver byte-identical across Python+bash twins per cross-runtime golden corpus
- Property tests: 0 invariant violations across 1000-iter nightly stress
- Latency: p95 ≤50ms warm cache; p95 ≤500ms cold cache (both platforms) (NFR-Perf-1)
- Sprint 2 cumulative wall-clock: ≤1.5 weeks
- Sprint 2 cost: ≤$50

---

## Sprint 3: Persona + Docs Migration + Model-Permissions Codegen + Bridgebuilder Dist Regen

**Global Sprint ID:** 141 (assigned by ledger)
**Local Sprint ID:** 3
**Cycle:** `cycle-099-model-registry`
**Duration:** ~1 week
**Scope:** LARGE (11 tasks — exact PRD/SDD-locked count; size justified by 4 distinct migration domains touching persona docs, protocol docs, model-permissions, and Bridgebuilder dist)

### Sprint Goal

Persona docs, protocol docs, and `model-permissions.yaml` are derived from the SoT via codegen. Bridgebuilder `dist/` is regenerated from SoT + tagged as `cycle-099-dist-RC1` for downstream submodule consumers. The full registry consolidation (registries 1-13 from PRD §Problem Statement) is complete. **Acceptance theme (SDD §8 Sprint 3): "Persona docs derive; model-permissions merged; Bridgebuilder dist regenerated."**

### Deliverables

- [ ] `.claude/data/personas/*.md` migrated from `# model: <model_id>` to `# tier: <tier_tag>` with backward-compat parsing (FR-1.5)
- [ ] `.claude/skills/bridgebuilder-review/resources/personas/*.md` migrated similarly (FR-1.5)
- [ ] `.claude/protocols/flatline-protocol.md` + `gpt-review-integration.md` updated to reference operator config ("configure your top-of-provider in `.loa.config.yaml`") with tier-name examples instead of specific model IDs (FR-1.6)
- [ ] DD-1 Option B per-model `permissions` block in `model-config.yaml` (SDD §3.1.1) — schema_version=2 migration via the Sprint 1 `loa migrate-model-config` CLI
- [ ] `gen-model-permissions.sh` codegen emits `model-permissions.generated.yaml` from SoT (SDD §5.3)
- [ ] `model-permissions.yaml` read-path swap to `model-permissions.generated.yaml`; legacy `model-permissions.yaml` becomes a thin wrapper during cycle-099; **cycle-101 (minimum) deletes** per §3.1.1 SKP-002 HIGH 720 deferral (FR-1.4) (resolves Flatline SDD pass #2 SKP-002 HIGH 760 internal-drift artifact)
- [ ] Bridgebuilder `dist/` regenerated from SoT via `bun run build`; `git diff --quiet dist/` after fresh build (SC-4, FR-1.1)
- [ ] `grimoires/loa/runbooks/bridgebuilder-dist-rollback.md` published documenting the R-1 dist tag pinning + `git submodule update --init --reference <previous-tag>` recovery (R-1)
- [ ] `grimoires/loa/runbooks/model-permissions-removal.md` published documenting the cycle-101-minimum legacy wrapper deletion path (DD-1)
- [ ] Cycle-099-dist-RC1 tag pushed for downstream submodule consumers (R-1, T3.10)

### Acceptance Criteria

- [ ] **AC-S3.1** — `tests/unit/gen-model-permissions.bats` PASSES — DD-1 Option B codegen unit tests (SDD §7.4)
- [ ] **AC-S3.2** — `tests/integration/model-permissions-merge-roundtrip.bats` PASSES — end-to-end SoT → emitted YAML byte-equal (full round-trip from `model-config.yaml::permissions` through `gen-model-permissions.sh` → `model-permissions.generated.yaml` → re-parse identical) (SDD §7.4)
- [ ] **AC-S3.3** — `tests/integration/persona-tier-tag-resolution.bats` PASSES — FR-1.5 backward compat: persona docs parse correctly under both `# model: <id>` (legacy) and `# tier: <tag>` (cycle-099) shapes; tier-tag wins on conflict (FR-1.5)
- [ ] **AC-S3.4** — `tests/integration/bb-runtime-overlay-divergence.bats` PASSES — §1.4.6 SKP-006 corpus: when compiled defaults and runtime overlay disagree on a key, `[BB-OVERLAY-OVERRIDE]` log emitted exactly once per process per overridden key (SDD §1.4.6)
- [ ] **AC-S3.5** — Bridgebuilder `dist/` regenerated from SoT: `git diff --quiet dist/` after a fresh `bun run build` (SC-4)
- [ ] **AC-S3.6** — Drift gate (Sprint 1 T1.5) covers `model-permissions.generated.yaml`: hand-edit produces non-zero CI exit (FR-5.1)
- [ ] **AC-S3.7** — Operator-facing: `grep -r 'claude-opus-[0-9]'` (and similar regex for `gpt-`/`gemini-`/`claude-haiku-`) in `.claude/data/personas/` + `.claude/skills/bridgebuilder-review/resources/personas/` + `.claude/protocols/` finds zero hardcoded model names outside SoT, generated artifacts, and explicit `backward_compat_aliases` (SC-1 full per Sprint 3 acceptance theme)
- [ ] **AC-S3.8** — Cycle-099-dist-RC1 tag pushed to GitHub; downstream submodule consumer test (cycle-098 #642 reporter pattern) verifies `git submodule update --remote` produces no breaking changes to user config format (NFR-Compat-2)
- [ ] **AC-S3.9** — `grimoires/loa/runbooks/bridgebuilder-dist-rollback.md` exists and includes operator-runnable rollback commands (R-1)
- [ ] **AC-S3.10** — `grimoires/loa/runbooks/model-permissions-removal.md` exists and documents the cycle-101-minimum legacy wrapper deletion path (DD-1)
- [ ] **AC-S3.11** — Sprint 3 quality-gate chain passes: `/implement sprint-3` → `/review-sprint sprint-3` → `/audit-sprint sprint-3` → bridgebuilder kaironic (≤2 iterations) → admin-squash merge

### Technical Tasks

- [ ] **T3.1** — Migrate `.claude/data/personas/*.md` from `# model:` to `# tier:` with backward-compat parsing (parsers accept both forms; tier-tag wins if present). → **[G-1, G-2]**
- [ ] **T3.2** — Migrate `.claude/skills/bridgebuilder-review/resources/personas/*.md` similarly. → **[G-1, G-2]**
- [ ] **T3.3** — Update `.claude/protocols/flatline-protocol.md` + `gpt-review-integration.md` to reference operator config with tier-name examples (`max`, `cheap`) instead of specific model IDs. → **[G-1]**
- [ ] **T3.4** — Implement DD-1 Option B: extend `model-config.yaml` with per-model `permissions` block per SDD §3.1.1. Run T1.14 `loa migrate-model-config` CLI to perform schema_version=1→2 migration on the framework SoT. → **[G-1, G-3]**
- [ ] **T3.5** — Implement `gen-model-permissions.sh` emitting `model-permissions.generated.yaml` per SDD §5.3. → **[G-1, G-3, G-4]**
- [ ] **T3.6** — Migrate `model-permissions.yaml` read-path swap: legacy file becomes thin wrapper during cycle-099; `LOA_LEGACY_MODEL_PERMISSIONS=1` enforces one-way sync (model-config.yaml = sole writer; model-permissions.yaml = regenerated derived) per SDD §3.1.1; **cycle-101 (minimum) deletes**. Pre-commit hook + CI guard reject manual edits with `[LEGACY-MODE-DUAL-WRITE]` (resolves Flatline SDD pass #2 SKP-002 HIGH 760). → **[G-3]**
- [ ] **T3.7** — Regenerate Bridgebuilder `dist/` from SoT via `bun run build` (consumes Sprint 1 T1.1 codegen + Sprint 2 T2.6 resolver). → **[G-1, G-3, G-4]**
- [ ] **T3.8** — Publish `grimoires/loa/runbooks/bridgebuilder-dist-rollback.md` per R-1 strengthening; documents version-comment header (`// Generated from model-config.yaml@<sha>`) + dist tag pinning + `git submodule update --init --reference <previous-tag>` recovery. → **[G-1, G-4]** (operability)
- [ ] **T3.9** — Publish `grimoires/loa/runbooks/model-permissions-removal.md` per DD-1; documents the cycle-101-minimum legacy wrapper deletion path. → **[G-3]** (operability)
- [ ] **T3.10** — Tag `cycle-099-dist-RC1` for downstream submodule consumers per R-1; downstream consumers can opt-in to RC for compatibility validation before the cycle-099 default flips. → **[G-4]**
- [ ] **T3.11** — Sprint 3 test deliverables per SDD §7.4: `gen-model-permissions.bats`, `model-permissions-merge-roundtrip.bats`, `persona-tier-tag-resolution.bats`, `bb-runtime-overlay-divergence.bats`. → **[G-1, G-2, G-3, G-4]**

### Dependencies

- **Sprint 1**: `gen-bb-registry.ts` codegen + drift gate operational; `loa migrate-model-config` CLI (T1.14) used in T3.4 to perform schema_version=1→2 migration
- **Sprint 2**: FR-3.9 6-stage resolver operational (Bridgebuilder runtime overlay in T3.7 dist regen depends on it); strict-mode loader supports `skill_models` + `tier_groups.mappings` (persona docs in T3.1/T3.2 reference `tier:` tags that resolve via Sprint 2 logic)
- **Cycle-026**: existing `model-permissions.yaml` 7-dim trust_scopes schema preserved as nested structure within DD-1 Option B per-model permissions block

### Security Considerations

- **Trust boundaries**: Sprint 3 changes happen in System Zone (`.claude/defaults/model-config.yaml`, `.claude/data/personas/`, `.claude/skills/bridgebuilder-review/resources/personas/`, `.claude/protocols/`). Cycle-level approval already exists via PRD/SDD; explicit System Zone modifications listed in cycle constraints above.
- **External dependencies**: Bun for `bun run build` (Sprint 1 dependency); Python venv for `gen-model-permissions.sh` (cheval venv); jq for read-path swap. No new dependencies.
- **Sensitive data**: Model permissions are derived from `model-config.yaml` SoT; no operator-controlled secrets. Pre-commit hook + CI guard prevent accidental hand-edits to the generated artifact.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R-1**: Bridgebuilder TS dist regeneration breaks downstream consumers (PR-strengthened risk) | HIGH | HIGH | T3.10 staged RC tag (`cycle-099-dist-RC1`) before cycle-099 final release; T3.8 rollback runbook; version-comment header (`// Generated from model-config.yaml@<sha>`) for traceability; T3.7 dist regenerated deterministically and verified via T3.11 dist-drift test; downstream consumers opt-in to RC during a compatibility validation window before cycle-099 default flips |
| **R-SDD-3**: DD-1 Option B `model-config.yaml` with per-model `permissions` makes the file ~50% larger | MEDIUM | LOW | T3.4 organizes `permissions` block consistently (sorted dimensions per cycle-026 schema); operators query via `yq '.providers.<p>.models.<id>.permissions'`; cycle-100 considers schema-split if file >40KB |
| **R-SDD-6**: Bridgebuilder runtime overlay (FR-1.1.b) bug silently falls back to compiled defaults, masking operator misconfiguration | MEDIUM | HIGH | §1.4.6 divergence detector emits `[BB-OVERLAY-OVERRIDE]` log; T3.11 `bb-runtime-overlay-divergence.bats` covers the corpus per AC-S3.4 |
| **R-7**: Operator config schema explosion (skill_models + model_aliases_extra + tier_groups + agents legacy + skill-specific legacy) confuses new operators | MEDIUM | MEDIUM | T2.14 (Sprint 2) `.loa.config.yaml.example` worked example covers canonical new shape; legacy shapes documented as deprecation-only per FR-3.7; `loa setup` wizard updates to use new shape (out of scope for cycle-099, surfaced in NOTES.md handoff for operator) |
| **NFR-Compat-2**: Downstream loa-as-submodule projects unaffected by `git submodule update --remote` | — | — | T3.10 RC tag + T3.8 rollback runbook collectively de-risk; AC-S3.8 verifies via cycle-098 #642 reporter pattern smoke test |

### Success Metrics

- All persona docs (`.claude/data/personas/*.md` + `.claude/skills/bridgebuilder-review/resources/personas/*.md`) use `# tier:` instead of `# model:` — measured: `grep -L '^# tier:' .claude/data/personas/*.md` returns empty
- All protocol docs reference operator config — measured: `grep -r 'claude-opus-\|gpt-5\.[0-9]\|gemini-' .claude/protocols/` returns matches only in `backward_compat_aliases` examples or generated artifacts
- `model-permissions.generated.yaml` byte-equal to a fresh `gen-model-permissions.sh` invocation
- Bridgebuilder `dist/` byte-equal to a fresh `bun run build`
- Cycle-099-dist-RC1 tag visible in GitHub releases
- Sprint 3 cumulative wall-clock: ≤1 week
- Sprint 3 cost: ≤$40

---

## Sprint 4 (Gated): Legacy Adapter Sunset (Operator Gate Decision)

**Global Sprint ID:** 142 (assigned by ledger)
**Local Sprint ID:** 4
**Cycle:** `cycle-099-model-registry`
**Duration:** ~1 week
**Scope:** SMALL/MEDIUM (7 tasks — exact PRD/SDD-locked count; outcome forks at T4.4 operator gate review per FR-4.4)

### Sprint Goal

Default flips to `hounfour.flatline_routing: true`; legacy adapter marked DEPRECATED with operator-visible warnings. **Sprint 4 gate review with operator decides full removal in cycle-099 OR continued deprecation through cycle-100 per FR-4.4.** End-to-end goal validation across G-1..G-5 per PRD §Goals. **Acceptance theme (SDD §8 Sprint 4): "Default flipped; deprecation visible; sunset decision made."**

### Deliverables

- [ ] `.claude/scripts/model-adapter.sh.legacy` marked `DEPRECATED` in file header with sunset target cycle (cycle-100 minimum) (FR-4.1)
- [ ] `.claude/defaults/loa.defaults.yaml` flipped: `hounfour.flatline_routing: true` becomes the framework default (FR-4.2)
- [ ] `[LEGACY-MODEL-ADAPTER-DEPRECATED]` operator-visible warning emitted at every Flatline invocation when an operator runs the legacy path (FR-4.3)
- [ ] **Sprint 4 gate review with operator** — full-removal vs continued-deprecation decision; logged in `grimoires/loa/cycles/cycle-099-model-registry/decisions/04-sprint-4-gate-review.md` (FR-4.4)
- [ ] **IF removal chosen** (T4.5 path): `.claude/scripts/model-adapter.sh.legacy` deleted; `hounfour.flatline_routing` feature flag removed from `loa.defaults.yaml` and `.loa.config.yaml.example`; `grimoires/loa/runbooks/legacy-adapter-removal.md` published (FR-4.6)
- [ ] **IF deprecation continues** (T4.6 path): NOTES.md handoff extends deprecation to cycle-100; `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning continues active; full removal scheduled for cycle-100
- [ ] E2E goal validation across G-1..G-5 (T4.7) — see Task 4.E2E below

### Acceptance Criteria

- [ ] **AC-S4.1** — `tests/integration/legacy-adapter-deprecation-warning.bats` PASSES — FR-4.3 visibility test: every Flatline invocation under legacy path emits `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning to operator-visible output (SDD §7.5)
- [ ] **AC-S4.2** — `tests/integration/default-flip-flatline-routing.bats` PASSES — FR-4.2 verification: fresh-clone agent without operator config uses hounfour path (T4.2 default flip) (SDD §7.5)
- [ ] **AC-S4.3** — `tests/integration/sunset-rollback.bats` PASSES — NFR-Op-3 rollback path: `LOA_LEGACY_MODEL_PERMISSIONS=1` env-var or `.loa.config.yaml::hounfour.flatline_routing: false` restores legacy path (SDD §7.5)
- [ ] **AC-S4.4** — Operator confirms gate decision in `grimoires/loa/cycles/cycle-099-model-registry/decisions/04-sprint-4-gate-review.md` (FR-4.4)
- [ ] **AC-S4.5** — IF full-removal: `model-adapter.sh.legacy` returns `404` (file does not exist); `hounfour.flatline_routing` flag removed from `loa.defaults.yaml`; `legacy-adapter-removal.md` runbook exists (FR-4.6)
- [ ] **AC-S4.6** — IF deprecation-continues: NOTES.md handoff entry recorded; `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning continues active; cycle-100 deprecation extension documented in `grimoires/loa/cycles/cycle-099-model-registry/decisions/04-sprint-4-gate-review.md`
- [ ] **AC-S4.7** — E2E goal validation passes per Task 4.E2E (all G-1..G-5 validated)
- [ ] **AC-S4.8** — Sprint 4 quality-gate chain passes: `/implement sprint-4` → `/review-sprint sprint-4` → `/audit-sprint sprint-4` → bridgebuilder kaironic (≤2 iterations) → admin-squash merge

### Technical Tasks

- [ ] **T4.1** — Mark `.claude/scripts/model-adapter.sh.legacy` `DEPRECATED` in file header with sunset target cycle (cycle-100 minimum). → **[G-5]**
- [ ] **T4.2** — Flip `hounfour.flatline_routing: true` default in `.claude/defaults/loa.defaults.yaml`. → **[G-5]**
- [ ] **T4.3** — Implement `[LEGACY-MODEL-ADAPTER-DEPRECATED]` operator-visible warning emitted at every Flatline invocation when an operator runs the legacy path. → **[G-5]**
- [ ] **T4.4** — **Sprint 4 gate review with operator**: full-removal vs continued-deprecation. Decision logged in `grimoires/loa/cycles/cycle-099-model-registry/decisions/04-sprint-4-gate-review.md` per FR-4.4. → **[G-5]**
- [ ] **T4.5** — IF removal chosen at T4.4: delete `.claude/scripts/model-adapter.sh.legacy`; remove `hounfour.flatline_routing` flag from `loa.defaults.yaml` + `.loa.config.yaml.example`; publish `grimoires/loa/runbooks/legacy-adapter-removal.md` per FR-4.6. → **[G-5]**
- [ ] **T4.6** — IF deprecation continues at T4.4: extend deprecation to cycle-100 in NOTES.md handoff; preserve current state with active `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning. → **[G-5]**
- [ ] **T4.7** — Sprint 4 test deliverables per SDD §7.5: `legacy-adapter-deprecation-warning.bats`, `default-flip-flatline-routing.bats`, `sunset-rollback.bats`. Plus the **E2E goal validation** task below (Task 4.E2E). → **[G-1..G-5]**

### Task 4.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4, G-5)

**Description:** Validate that all PRD goals are achieved through the complete cycle-099 implementation. This is the final gate before cycle archival.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| **G-1** | Single edit point for model registration | Time-tracked exercise: framework maintainer adds `claude-opus-4-8` to `.claude/defaults/model-config.yaml`, runs `bash .claude/scripts/gen-adapter-maps.sh`, runs `bun run build` from `.claude/skills/bridgebuilder-review/`, commits source + generated artifacts in single PR. CI drift gate green. | Single PR; ≤30 min wall-clock; CI drift = 0 |
| **G-2** | Per-skill tier-tag granularity from one config block | Operator config audit: `skill_models: { flatline_protocol: {primary: max, secondary: max, tertiary: max}, red_team: {primary: cheap}, bridgebuilder: {opus_role: max, gpt_role: max, gemini_role: cheap} }` written in `.loa.config.yaml`; `model-invoke --validate-bindings --format json` resolves all (skill, role) pairs. | ≤10 lines of operator YAML; clean resolution; SC-3 satisfied |
| **G-3** | Zero drift between registries | Run `.github/workflows/model-registry-drift.yml` on every PR for cycle-099 last 10 PRs; verify all green. Run `grep -r 'claude-opus-[0-9]\|gpt-5\.[0-9]\|gemini-' .claude/data/personas/ .claude/skills/bridgebuilder-review/resources/personas/ .claude/protocols/`. | All drift gates green; grep output shows only `backward_compat_aliases` matches and generated artifacts |
| **G-4** | Bridgebuilder model defaults derive from SoT via build-time codegen | Run `bun run build` from `.claude/skills/bridgebuilder-review/`; verify `git diff --quiet dist/` after fresh build. Tag `cycle-099-dist-RC1` exists. | Clean diff; tag visible in GitHub releases |
| **G-5** | Legacy adapter sunset path with operator opt-in fallback | IF T4.4 chose removal: `model-adapter.sh.legacy` deleted; rollback runbook published. IF T4.4 chose deprecation-continues: `[LEGACY-MODEL-ADAPTER-DEPRECATED]` warning active on every Flatline invocation; cycle-100 sunset scheduled. | Either path: explicit operator-facing decision documented in `decisions/04-sprint-4-gate-review.md` |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence (cite file:line for verification commands; cite PR # for drift gate runs)
- [ ] Integration points verified (data flows end-to-end from `model-config.yaml` SoT through codegen → runtime → resolver → skill consumer)
- [ ] No goal marked as "not achieved" without explicit justification + operator-approved follow-up cycle reference

### Dependencies

- **Sprint 1**: drift gate operational; cross-runtime golden corpus + runners green; `model-adapter.sh` (non-legacy) sources `generated-model-maps.sh`
- **Sprint 2**: FR-3.9 resolver operational; `model-invoke --validate-bindings` available for E2E validation; legacy-shape backward compat in place
- **Sprint 3**: Bridgebuilder `dist/` regenerated + tagged; persona docs migrated; protocol docs migrated; model-permissions codegen operational
- **Operator availability**: T4.4 gate review requires operator (deep-name) in-session decision

### Security Considerations

- **Trust boundaries**: Default flip (T4.2) changes framework-default behavior for all operators. Rollback path (`LOA_LEGACY_MODEL_PERMISSIONS=1` or `hounfour.flatline_routing: false`) preserved per NFR-Op-3.
- **External dependencies**: None new for Sprint 4. All hardening primitives (T1.13 redactor, T1.15 endpoint validator, T2.11 SSRF defense) carried forward.
- **Sensitive data**: No new sensitive-data surface. Legacy-adapter removal (if chosen) eliminates the duplicated 4-array bash dict that cycle-095 vision-011 already partially migrated.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **R-3**: Legacy adapter sunset breaks operators with `hounfour.flatline_routing: false` (the default before Sprint 4) | MEDIUM | MEDIUM | Sprint 4 sunset is gated — operator approves at T4.4 review; deprecation warnings in T4.3 give operators visibility before default flip; rollback path (`LOA_LEGACY_MODEL_PERMISSIONS=1`) preserved per AC-S4.3 |
| **R-2 follow-up**: Schema migration gives operators 1 cycle to migrate `flatline_protocol.models.{primary,...}` legacy shapes (Sprint 2 deprecation warning); cycle-100 expected to flip legacy-shape fail-closed | MEDIUM | MEDIUM | Per FR-3.7 v1.3: legacy-shape unresolved bindings emit deprecation warning + fall back to skill's framework default tier mapping (the ONE EXCEPTION to FR-3.8 fail-closed semantics, time-bounded to one cycle). Operators get telemetry via `model-invoke --validate-bindings` aggregate count. |
| **R-1 carryforward**: Bridgebuilder dist regen breaks downstream submodule consumers | HIGH | HIGH | Mitigated in Sprint 3 via T3.10 RC tag + T3.8 rollback runbook + T3.4 version-comment header |
| **Operator-availability risk**: T4.4 gate review requires synchronous operator decision; if operator unavailable for >24h, Sprint 4 stalls | LOW | MEDIUM | Per FR-4.4 PRD: gate review can default to continued deprecation if operator misses 24h deadline; SOP per Sprint 4 NOTES.md handoff |

### Success Metrics

- All G-1..G-5 PRD goals validated end-to-end per Task 4.E2E
- Sprint 4 gate decision documented in `decisions/04-sprint-4-gate-review.md`
- IF removal: `model-adapter.sh.legacy` returns 404; `hounfour.flatline_routing` flag absent from `loa.defaults.yaml`
- IF deprecation-continues: cycle-100 sunset cycle scheduled in NOTES.md
- Sprint 4 cumulative wall-clock: ≤1 week
- Sprint 4 cost: ≤$40

---

## Risk Register (Cycle-099 Aggregated)

| ID | Risk | Sprint | Probability | Impact | Mitigation | Source |
|----|------|--------|-------------|--------|------------|--------|
| **R-1** | Bridgebuilder TS dist regeneration breaks downstream consumers | 3 (primary), 4 (carryforward) | HIGH | HIGH | RC tag + rollback runbook + version-comment header + staged gate (T3.10, T3.8, T3.4) | PRD R-1 v1.1 strengthening per Flatline IMP-003 HIGH_CONSENSUS 785 |
| **R-2** | Operator's existing `.loa.config.yaml` stops working under strict-mode | 2 | MEDIUM | MEDIUM | One-cycle deprecation path (FR-3.7) + T1.14 migration CLI + T2.9 backward compat | PRD R-2 |
| **R-3** | Legacy adapter sunset breaks operators with `hounfour.flatline_routing: false` | 4 | MEDIUM | MEDIUM | Sprint 4 gated review; T4.3 deprecation warning; rollback path preserved | PRD R-3 |
| **R-4** | Drift detection CI false positives | 1 | LOW | MEDIUM | Lockfile + reproducibility matrix (T1.6, T1.7) | PRD R-4 |
| **R-5** | Beads UNHEALTHY (#661) workaround friction across 4 sprints | All | MEDIUM | MEDIUM | Ledger fallback per cycle-098; `--no-verify` per cycle-098 pattern; Sprint 0 beads-recovery if friction >4h | PRD R-5 |
| **R-6** | tier_groups mapping defaults populated wrong | 2 | MEDIUM | MEDIUM | Probe-confirmed via `model-health-probe.sh` (T2.7) | PRD R-6 |
| **R-7** | Operator config schema explosion confuses new operators | 2-3 | MEDIUM | MEDIUM | T2.14 worked example; legacy shapes deprecation-only | PRD R-7 |
| **R-8** | `gen-bb-registry.ts` Bun dependency breaks in CI | 1 | LOW | LOW | Bun is existing Bridgebuilder dep | PRD R-8 |
| **R-9** | `model_aliases_extra` malformed entry crashes loader | 2 | LOW | LOW | T2.1 JSON Schema validation | PRD R-9 |
| **R-10** | cheval HTTP/2 bug (#675) resurfaces during cycle-099 Flatline reviews | All | LOW | MEDIUM | sprint-bug-131 already shipped in cycle-098; production retry path active | PRD R-10 (mostly closed) |
| **R-SDD-1** | Python startup hook adds ~30ms wall-clock | 2 | LOW | LOW | SHA256 short-circuit; AC-S2.12 latency gate | SDD R-SDD-1 |
| **R-SDD-2** | `model_aliases_override` semantics ambiguous on nested pricing | 2 | MEDIUM | MEDIUM | DD-3 partial-merge spec; AC-S2.16 covers depth-2 | SDD R-SDD-2 |
| **R-SDD-3** | DD-1 Option B per-model `permissions` makes file ~50% larger | 3 | MEDIUM | LOW | T3.4 sorted dimensions; cycle-100 schema-split if >40KB | SDD R-SDD-3 |
| **R-SDD-4** | flock-on-NFS detection false-positives | 2 | LOW | LOW | T2.16 runbook + opt-in flag; AC-S2.8 smoke-test | SDD R-SDD-4 |
| **R-SDD-5** | URL canonicalization IDN handling depends on Python `idna` version | 1-2 | LOW | MEDIUM | T1.9 toolchain pin (`idna ≥3.6`) | SDD R-SDD-5 |
| **R-SDD-6** | Bridgebuilder runtime overlay bug silently falls back | 3 | MEDIUM | HIGH | §1.4.6 divergence detector; AC-S3.4 covers | SDD R-SDD-6 |
| **R-SDD-7** | Property test runner generates non-representative configs | 2 | LOW | MEDIUM | Deterministic-seeded; nightly stress; fallback to Hypothesis | SDD R-SDD-7 |
| **R-SDD-8** | Cycle-098 `audit_emit` flock collides with `merged-aliases.sh.lock` | 2 | LOW | LOW | Different lock files + invocation timing; AC-S2.9 verifies | SDD R-SDD-8 |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Time to add a new framework-default model | ≤30 min wall-clock; single PR | Stopwatch + git-diff scope on probe-confirmed model addition | 1 (codegen ready) → 4 (E2E validated) |
| Time for operator to add a new model not in framework | <5 min via `.loa.config.yaml::model_aliases_extra` | E2E test: fresh-clone repo + sample config; `model-invoke --validate-bindings` resolves operator model | 2 (loader ready) → 4 (E2E validated) |
| Drift between registries | 0 | CI drift gate exits non-zero on PR with hand-edit divergence | 1 (gate operational) → 3 (full coverage) |
| Per-skill tier expressivity | ≤10 lines for "flatline max + red team cheap + bridgebuilder mixed" | Operator config audit; YAML line count | 2 |
| Bridgebuilder default upgrade | Auto-regenerated by `bun run build` | `git diff --quiet dist/` after fresh build | 3 |
| FR-3.9 6-stage resolver byte-identical across runtimes | 0 mismatches in `cross-runtime-diff.yml` | Golden corpus + 3 cross-runtime runners | 1 (corpus + runners) → 2 (resolver implementation) |
| Property test invariants | 0 violations across 1000-iter nightly stress | `model-resolution-properties.bats` | 2 |
| Latency p95 | ≤50ms warm cache, ≤500ms cold cache (Linux + macOS) | `overlay-resolution-latency.bats` (warm + cold) | 2 |
| Security test corpus | 0 SSRF/injection/permission-escalation bypasses | `model-aliases-extra-security.bats` | 2 |
| Cycle cumulative wall-clock | 5-6 weeks (per SDD §8.0) | Sprint-by-sprint tracking | All |
| Cycle cumulative cost | $200-300 (per SDD §8.0) | Sprint-by-sprint cost tracking via cycle-098 metering | All |

---

## Dependencies Map

```
                                  ┌─────────────────────────────────┐
                                  │ Cycle-098 #720 merged (already) │
                                  └────────────────┬────────────────┘
                                                   │
                                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Sprint 1 (LARGE, 15 tasks): SoT Extension Foundation + Cross-Cutting │
│   T1.1-T1.10 (FR-1, FR-5)                                            │
│   T1.11-T1.12 (golden corpus + 3 cross-runtime runners + diff CI)    │
│   T1.13 (log-redactor)                                               │
│   T1.14 (loa migrate-model-config CLI)                               │
│   T1.15 (centralized endpoint validator + CI guard)                  │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Sprint 2 (LARGE, 16 tasks): Config Extension + Per-Skill Granularity │
│   T2.1 (JSON Schema)                                                 │
│   T2.2 (loader extension)                                            │
│   T2.3-T2.5 (Python overlay hook + merged-aliases.sh writer)         │
│   T2.6 (FR-3.9 6-stage resolver: Python canonical + bash twin)       │
│   T2.7-T2.10 (tier_groups + prefer_pro + legacy backcompat + perms)  │
│   T2.11 (endpoint allowlist + URL canonicalization + DNS rebinding)  │
│   T2.12-T2.13 (validate-bindings CLI + LOA_DEBUG tracing)            │
│   T2.14-T2.16 (operator example + tests + network-fs runbook)        │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Sprint 3 (LARGE, 11 tasks): Persona + Docs + Permissions + Dist      │
│   T3.1-T3.3 (persona + protocol docs migration to tier-tag refs)     │
│   T3.4-T3.6 (DD-1 Option B + gen-model-permissions + read-path swap) │
│   T3.7 (Bridgebuilder dist regen from SoT)                           │
│   T3.8-T3.10 (rollback runbook + permissions-removal runbook + RC1)  │
│   T3.11 (test deliverables)                                          │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Sprint 4 (gated, SMALL/MEDIUM, 7 tasks): Legacy Adapter Sunset       │
│   T4.1-T4.3 (deprecate + flip default + warning)                     │
│   T4.4 (operator gate review — outcome forks)                        │
│   T4.5 (full-removal path) OR T4.6 (deprecation-continues path)      │
│   T4.7 (test deliverables + E2E goal validation across G-1..G-5)     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Appendix

### Appendix A — PRD Feature Mapping

| PRD FR | Sprint | Status |
|--------|--------|--------|
| FR-1.1 (Bridgebuilder TS hybrid pattern) | 1 (codegen) + 2 (runtime overlay) + 3 (dist regen) | Planned |
| FR-1.1.1 (endpoint_family lookup) | 1 (T1.15 endpoint validator) + 2 (T2.11 runtime allowlist) | Planned |
| FR-1.2 (Red Team adapter SoT) | 1 (T1.3) | Planned |
| FR-1.3 (red-team-code-vs-design.sh alias) | 1 (T1.4) | Planned |
| FR-1.4 (model-permissions DD-1 Option B + perms baseline) | 2 (T2.10 baseline) + 3 (T3.4-T3.6 codegen) | Planned |
| FR-1.5 (persona tier-tag) | 3 (T3.1-T3.2) | Planned |
| FR-1.6 (protocol docs operator-config refs) | 3 (T3.3) | Planned |
| FR-1.7 (default model-adapter.sh sources generated maps) | 1 (T1.8) | Planned |
| FR-1.8 (only model-config.yaml hand-maintained post-cycle) | 3 (T3.6 read-path swap) | Planned |
| FR-1.9 (runtime config consolidation: Python hook + merged-aliases.sh) | 2 (T2.3, T2.4) | Planned |
| FR-2.1 (model_aliases_extra field placement) | 2 (T2.2) | Planned |
| FR-2.2 (JSON Schema) | 2 (T2.1) | Planned |
| FR-2.3 (model_aliases_override partial-merge per DD-3) | 2 (T2.2 + T2.15) | Planned |
| FR-2.4 (cycle-095 backward_compat_aliases preserved) | All (carryforward; tested AC-S2.3) | Planned |
| FR-2.5 (no hot-reload — restart to apply) | N/A — YAGNI for v1 per PRD §Out-of-scope line 495 | N/A |
| FR-2.6 (extend BOTH models AND aliases) | 2 (T2.2) | Planned |
| FR-2.7 (.loa.config.yaml.example worked example) | 2 (T2.14) | Planned |
| FR-2.8 (provider endpoint allowlist + api_id format normalization) | 1 (T1.15 validator) + 2 (T2.11 runtime check) | Planned |
| FR-3.1 (skill_models field) | 2 (T2.2 + T2.6) | Planned |
| FR-3.2 (tier_groups.mappings defaults) | 2 (T2.7) | Planned |
| FR-3.3 (per-role tier) | 2 (T2.6) | Planned |
| FR-3.4 (prefer_pro_models with FR-3.4 legacy gate) | 2 (T2.8) | Planned |
| FR-3.5 (sensible default tier mapping per skill + startup validation) | 2 (T2.7 + T2.6) | Planned |
| FR-3.6 (mixed mode: tier-tag for some + explicit ID for others) | 2 (T2.6) | Planned |
| FR-3.7 (migration of existing config shapes + legacy-shape exception) | 2 (T2.9) | Planned |
| FR-3.8 (fail-closed tier fallback semantics) | 2 (T2.6) | Planned |
| FR-3.9 (deterministic 6-stage resolution algorithm) | 1 (golden corpus) + 2 (resolver impl in Python+bash twin) | Planned |
| FR-4.1 (legacy adapter DEPRECATED header) | 4 (T4.1) | Gated |
| FR-4.2 (default flip flatline_routing) | 4 (T4.2) | Gated |
| FR-4.3 (deprecation warning) | 4 (T4.3) | Gated |
| FR-4.4 (Sprint 4 gate decision) | 4 (T4.4) | Gated |
| FR-4.5 (backward compat env-var pin) | 4 (T4.5 IF removal) | Gated |
| FR-4.6 (full removal cleanup) | 4 (T4.5) | Gated |
| FR-5.1 (model-registry-drift.yml CI workflow) | 1 (T1.5) | Planned |
| FR-5.2 (CI exit non-zero) | 1 (T1.5) | Planned |
| FR-5.3 (documentation drift grep) | 3 (T3.3 + AC-S3.7) | Planned |
| FR-5.4 (lockfile checksum) | 1 (T1.6) | Planned |
| FR-5.5 (codegen reproducibility matrix CI) | 1 (T1.7) | Planned |
| FR-5.6 (model-invoke --validate-bindings contract) | 2 (T2.12) | Planned |
| FR-5.7 (LOA_DEBUG_MODEL_RESOLUTION runtime tracing) | 2 (T2.13) | Planned |

### Appendix B — SDD Component Mapping

| SDD Section | Sprint | Status |
|-------------|--------|--------|
| §1.1 System Overview (codegen + runtime overlay + resolver pipeline) | 1-3 | Planned |
| §1.4.3 Codegen scripts | 1 (T1.1, T1.5, T1.6, T1.7) + 3 (T3.5) | Planned |
| §1.4.4 model-overlay-hook.py | 2 (T2.3) | Planned |
| §1.4.5 Bridgebuilder runtime overlay (runtime-overlay.ts) | 3 (T3.7) | Planned |
| §1.4.6 Hybrid divergence detector | 3 (AC-S3.4) | Planned |
| §1.5 Data flow: resolution path FR-3.9 | 1 (golden corpus) + 2 (resolver impl) | Planned |
| §1.5.1 Cross-runtime canonicalization standard | 1 (T1.11, T1.12) + 2 (T2.6) | Planned |
| §1.5.2 Build-time vs runtime authority boundaries (`--diff-bindings`) | 2 (T2.12) | Planned |
| §1.9 Security architecture (provider CDN exemptions) | 2 (T2.11) | Planned |
| §1.9.1 Centralized Endpoint Validator | 1 (T1.15) | Planned |
| §3.1.1 Per-model permissions block (DD-1 Option B) | 3 (T3.4) | Planned |
| §3.1.1.1 migrate_v1_to_v2() contract | 1 (T1.14) + 3 (T3.4 invokes) | Planned |
| §3.1.2 tier_groups.mappings populated | 2 (T2.7) | Planned |
| §3.1.3 agents.<skill_name>.default_tier | 2 (T2.7) | Planned |
| §3.3 model_aliases_override semantics | 2 (T2.2 + T2.15) | Planned |
| §3.3.1 Custom-alias vs tier-tag collision | 2 (T2.1 + T2.6) | Planned |
| §3.5 .run/merged-model-aliases.sh writer (atomic-write + flock) | 2 (T2.4) | Planned |
| §5.2 model-invoke --validate-bindings | 2 (T2.12) | Planned |
| §5.3 gen-model-permissions.sh | 3 (T3.5) | Planned |
| §5.6 Debug trace + JSON output secret redactor | 1 (T1.13) | Planned |
| §6.3.1 Lock acquisition contract | 2 (T2.4) | Planned |
| §6.3.2 Degraded read-only fallback (NFR-Op-7 prolonged-degraded monitoring) | 2 (T2.4) | Planned |
| §6.3.3 .run/overlay-state.json corruption handling | 2 (T2.4) | Planned |
| §6.3.4 Multi-file read consistency | 2 (T2.4) | Planned |
| §6.5 URL canonicalization (8-step) | 2 (T2.11) | Planned |
| §6.6 flock-over-NFS detection | 2 (T2.4 + T2.16 runbook) | Planned |
| §7.5.1 Latency measurement methodology | 2 (AC-S2.12) | Planned |
| §7.6 Cross-runtime golden test corpus | 1 (T1.11, T1.12) | Planned |

### Appendix C — PRD Goal Mapping (Goal Traceability)

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| **G-1** | Single edit point for model registration: framework defaults via one `model-config.yaml` entry; operator extensions via one `.loa.config.yaml::model_aliases_extra` entry. No System Zone edits required for operators. | Sprint 1: T1.1, T1.3, T1.4, T1.8, T1.9, T1.10, T1.11, T1.14<br/>Sprint 2: T2.1, T2.2, T2.3, T2.4, T2.5, T2.6, T2.9, T2.10, T2.11, T2.12, T2.15, T2.16<br/>Sprint 3: T3.1, T3.2, T3.3, T3.4, T3.5, T3.7, T3.8, T3.11 | Sprint 4: T4.7 (Task 4.E2E G-1 row) |
| **G-2** | Per-skill tier-tag granularity expressible from one config block, composing with cycle-095's `tier_groups` schema. Operators say "flatline use max, red team use cheap" in plain YAML. | Sprint 2: T2.2, T2.6, T2.7, T2.8, T2.12, T2.13, T2.14, T2.15<br/>Sprint 3: T3.1, T3.2, T3.11 | Sprint 4: T4.7 (Task 4.E2E G-2 row) |
| **G-3** | Zero drift between registries — CI gate fails when generated artifacts diverge from SoT. | Sprint 1: T1.1, T1.2, T1.3, T1.4, T1.5, T1.6, T1.7, T1.10, T1.11, T1.12, T1.13, T1.15<br/>Sprint 2: T2.1, T2.11, T2.12, T2.15<br/>Sprint 3: T3.4, T3.5, T3.6, T3.7, T3.9, T3.11 | Sprint 4: T4.7 (Task 4.E2E G-3 row) |
| **G-4** | Bridgebuilder model defaults derive from SoT via build-time codegen (operators don't need to rebuild TS for new models — framework releases ship updated `dist/`). | Sprint 1: T1.1, T1.2<br/>Sprint 3: T3.5, T3.7, T3.8, T3.10, T3.11 | Sprint 4: T4.7 (Task 4.E2E G-4 row) |
| **G-5** | Legacy adapter sunset path exists with operator opt-in fallback during deprecation window. | Sprint 4: T4.1, T4.2, T4.3, T4.4, T4.5/T4.6, T4.7 | Sprint 4: T4.7 (Task 4.E2E G-5 row — same sprint) |

**Goal Coverage Check:**
- [x] All PRD goals (G-1..G-5) have at least one contributing task
- [x] All goals have a validation task in the final sprint (Sprint 4 Task 4.E2E)
- [x] No orphan tasks — every task contributes to at least one goal (verified by inspection)

**Per-Sprint Goal Contribution:**

- **Sprint 1**: G-1 (foundation: codegen + drift gate + cross-runtime corpus + migration CLI), G-3 (drift gate + lockfile + reproducibility matrix + cross-runtime golden parity), G-4 (codegen for Bridgebuilder TS source files)
- **Sprint 2**: G-1 (loader + overlay + resolver complete), G-2 (skill_models + tier_groups + prefer_pro + validate-bindings), G-3 (schema validation + overlay drift detection)
- **Sprint 3**: G-1 (persona + docs + permissions migration), G-2 (persona tier-tag refs), G-3 (full registry consolidation; all 13 PRD-§Problem-Statement registries derived from SoT), G-4 (Bridgebuilder dist regen + RC1 tag)
- **Sprint 4**: G-5 (legacy adapter deprecation + sunset gate + E2E validation across G-1..G-5)

### Appendix D — Cycle-098 Pattern Reuse

| Cycle-098 pattern | Cycle-099 application |
|-------------------|------------------------|
| Sprint sizing per task count (SMALL/MEDIUM/LARGE) | Applied: S1=15 tasks LARGE; S2=16 tasks LARGE; S3=11 tasks LARGE; S4=7 tasks SMALL/MEDIUM |
| Quality-gate chain per sprint | Applied: implement → review → audit → bridgebuilder kaironic 2-iter → admin-squash |
| Beads UNHEALTHY (#661) ledger fallback | Applied per R-5: ledger-only sprint tracking; `--no-verify` per cycle-098 |
| Sprint counter tracking + global IDs | Applied: 138 (cycle-098 end) → 139-142 (cycle-099 sprints) |
| De-Scope Triggers active across sprint boundaries | Applied: S1 >2 weeks late triggers re-baseline; cross-runtime parity failures >3 triggers Sprint 2.5 buffer |
| R11 Friday weekly schedule-check ritual | Active across cycle-099 (continues from cycle-098) |
| Subagent worktree-isolated delegation for parallel reviews | Available for Sprint 1 (4 distinct workstreams: codegen + cross-runtime + log-redactor + endpoint-validator) |
| Inline implementation for sequential work (per `feedback_inline_vs_subagent_4slice.md`) | Default for Sprint 2 + 3 + 4 (sequential domains; inline saves $40-70 vs subagent dispatch) |
| Kaironic plateau at 2-iter for code PRs | Applied: bridgebuilder review budget per sprint = 2 iterations max before escalation |
| Cycle directory structure under `grimoires/loa/cycles/<cycle-id>/` | Created post-this-sprint-plan via chore PR (per cycle-098 #679 pattern; PRD §Out-of-scope line 499) |

### Appendix E — Cross-Cutting Tasks (T1.11..T1.15) Provenance

Per SDD §8.0 cycle-scope acknowledgement, 5 cross-cutting tasks expand Sprint 1 scope beyond PRD's original 4-sprint framing. Each has primary-source Flatline finding citation:

| Task | Source Finding | SDD Section | Primary Reference |
|------|----------------|-------------|---------------------|
| **T1.11** (golden corpus + 3 cross-runtime runners) | Flatline SDD pass #1 SKP-002 CRITICAL 890 (resolver triplication drift hazard) | §7.6 | Sprint 2.6 cross-runtime parity verification depends on this |
| **T1.12** (CI workflows + cross-runtime-diff gate) | Flatline SDD pass #1 SKP-002 CRITICAL 890 (same as T1.11) | §7.6.2 | PR-level CI guard prevents drift reintroduction |
| **T1.13** (log-redactor module) | Flatline SDD pass #1 IMP-002 HIGH_CONSENSUS 860 (debug-trace + JSON output secret leak vectors) | §5.6 | Used by T2.13 LOA_DEBUG tracing + T2.12 validate-bindings + T2.4 merged-aliases diagnostics |
| **T1.14** (loa migrate-model-config CLI) | Flatline SDD pass #2 SKP-001 CRITICAL 910 (uniform reject v1 + operator-explicit migration) + IMP-004 HIGH_CONSENSUS 835 (migrate_v1_to_v2 concrete spec) | §3.1.1.1 | Operator-explicit, never auto-on-startup |
| **T1.15** (centralized endpoint validator + CI guard) | Flatline SDD pass #2 SKP-006 CRITICAL 870 (three independent URL-validation impls = three drift surfaces) | §1.9.1 | PR-level CI guard prevents reintroduction |

**Operator scope acknowledgement** (SDD §8.0, SDD pass #3 SKP-003 HIGH 790): cycle-099 absorbs these scope expansions (~50 added tests, ~$80-120 added cost, ~1-2 added weeks) at SDD v1.3 review rather than deferring them to cycle-100 cleanup. The expansions address risks the original PRD framing did not see; deferring would push the same work into cycle-100 cleanup at higher cost.

### Appendix F — References

- PRD: `grimoires/loa/prd.md` (v1.3, 2026-05-04)
- SDD: `grimoires/loa/sdd.md` (v1.3, 2026-05-04)
- Cycle-099 (proposed) directory: `grimoires/loa/cycles/cycle-099-model-registry/` — **created post-this-sprint-plan via chore PR** (per cycle-098 #679 pattern, PRD §Out-of-scope line 499)
- Cycle-098 archive: `grimoires/loa/cycles/cycle-098-agent-network/` (PRD/SDD preserved at v1.4/v1.5; Sprint 1-3 + 1.5 + H1 + H2 SHIPPED; Sprint 4-7 deferred)
- Cycle-095 carryforwards: `tier_groups`, `aliases`, `backward_compat_aliases`, `prefer_pro_models`, `gen-adapter-maps.sh`
- Issue #710: https://github.com/0xHoneyJar/loa/issues/710
- Beads UNHEALTHY tracker: https://github.com/0xHoneyJar/loa/issues/661

---

*Generated by Sprint Planner Agent (deep-name + Claude Opus 4.7 1M)*
*Sprint plan iteration count: 1 (initial draft from cycle-099 PRD v1.3 + SDD v1.3 — 100% kaironic-stop convergence at 3 PRD passes + 3 SDD passes; 57 cumulative findings integrated)*
