# Cycle-108 Sprint Plan — Advisor-Strategy Benchmark + Role→Tier Routing

> **Version**: 1.0 (pre-Flatline)
> **Status**: draft (awaiting `/flatline-review` on sprint-plan — Phase 3b)
> **Cycle**: cycle-108-advisor-strategy
> **Operator**: @janitooor (autonomous /run mode)
> **Created**: 2026-05-13
> **Inputs**:
> - PRD: `grimoires/loa/cycles/cycle-108-advisor-strategy/prd.md` (v1.1, Flatline-amended)
> - SDD: `grimoires/loa/cycles/cycle-108-advisor-strategy/sdd.md` (v1.2, Red Team + Flatline-amended)
> **Output mirror**: `grimoires/loa/sprint.md`

---

## 0. Executive summary

Cycle-108 ships a **role→tier routing substrate**, runs an **empirical advisor-strategy benchmark** over historical Loa sprints, and lands a **rollout decision** (default-on per stratum / opt-in only / shelve) via a mechanical decision-fork from the benchmark data.

Four sprints, sequentially dependent:

| Sprint | Theme | Scope | Tasks | Owner |
|--------|-------|-------|-------|-------|
| **Sprint 1** | Routing substrate | LARGE | 12 tasks (T1.A–T1.L) | autonomous /implement → /review-sprint → /audit-sprint |
| **Sprint 2** | Measurement substrate | LARGE | 12 tasks (T2.A–T2.P, condensed) | autonomous |
| **Sprint 3** | Empirical benchmark | MEDIUM (operator-driven) | 7 tasks (T3.A–T3.G) | operator-signed baselines + autonomous replays |
| **Sprint 4** | Rollout policy + decision-fork | MEDIUM | 8 tasks (T4.A–T4.H) | autonomous with operator decision approval |

**Cross-sprint invariants** (apply to every sprint):

1. Every task has a unique ID, cites the PRD/SDD ref it satisfies, has mechanical AC, names files touched (System Zone writes flagged), declares an effort tier (XS/S/M/L), and declares dependencies.
2. Every sprint goes through the full `/implement → /review-sprint → /audit-sprint` cycle per CLAUDE.md NEVER/ALWAYS rules. The cycle is non-negotiable.
3. Tasks are candidate beads_rust issues. The frontmatter block per task (Appendix B) is `br create`-ingestible.
4. System Zone writes (`.claude/`) are flagged with **🔒 SYSTEM ZONE** and require explicit cycle-level authorization (this cycle has that authorization — cycle-108 is a framework-evolution cycle).

---

## 1. Sprint 1 — Routing substrate

> Goal: ship the role→tier configuration + cheval routing extension + skill-annotation contract + rollback semantics. All measurement work in Sprint 2 depends on this substrate being correct.

**Scope**: LARGE (12 tasks).
**Sprint goal (one sentence)**: Land the role→tier routing substrate (schema, loader, cheval CLI, skill annotations, rollback) such that flipping `advisor_strategy.enabled: true` produces a measurable behavioral change at cheval invocation time, validated by a full-cycle MODELINV trace test.

### 1.1 Deliverables

- [ ] D1.1 — `.claude/data/schemas/advisor-strategy.schema.json` committed with NFR-Sec1 hard-pin on review/audit tiers
- [ ] D1.2 — `load_advisor_strategy()` Python loader in `.claude/adapters/loa_cheval/config/loader.py`
- [ ] D1.3 — `cheval.py` accepts `--role` / `--skill` / `--sprint-kind` flags; backward-compat preserved
- [ ] D1.4 — `loa_cheval/routing/advisor_strategy.py` resolver + `.claude/scripts/lib/advisor-strategy-resolver.sh` thin wrapper
- [ ] D1.5 — MODELINV v1.2 envelope schema bump (additive); writer_version SoT file
- [ ] D1.6 — `validate-skill-capabilities.sh` extended with `role` requirement + heuristic linter + diff-aware role-change rule
- [ ] D1.7 — 35+ SKILL.md files migrated (`role` field added) in ONE atomic commit alongside schema enum seed
- [ ] D1.8 — `.github/workflows/cycle-108-schema-guard.yml` CI workflow
- [ ] D1.9 — `.github/CODEOWNERS` expanded per §20.1
- [ ] D1.10 — Rollback trace-comparison test + golden-pins.json signed by operator
- [ ] D1.11 — `grimoires/loa/runbooks/advisor-strategy-rollback.md` operator-facing rollback guide
- [ ] D1.12 — Symlink-scan + FS-snapshot-diff hook stubs for the Sprint-2 harness

### 1.2 Sprint-level Acceptance Criteria (sprint definition-of-done)

- [ ] AC-S1.1 — `advisor_strategy.enabled: false` produces byte-identical MODELINV traces to pre-cycle-108 behavior across `/implement`, `/review-sprint`, `/audit-sprint`, Flatline, BB, Red Team (full-cycle trace integration test green)
- [ ] AC-S1.2 — `advisor_strategy.enabled: true` with `defaults.implementation: executor` produces MODELINV entries with `payload.tier = "executor"` and `payload.role = "implementation"` for the `/implement` skill
- [ ] AC-S1.3 — Loading a poisoned config (review or audit set to executor in per_skill_overrides) exits with code 78 (EX_CONFIG); 5 negative fixtures all pass
- [ ] AC-S1.4 — All 35+ skills have a valid `role` frontmatter field; CI fails any PR adding a SKILL.md without `role`
- [ ] AC-S1.5 — `cycle-108-schema-guard.yml` workflow passes on a clean PR, fails on a PR that touches SKILL.md `role:` without touching `audited_review_skills`
- [ ] AC-S1.6 — `LOA_ADVISOR_STRATEGY_DISABLE=1` env override takes precedence over config (kill-switch test green)
- [ ] AC-S1.7 — Config-load + role resolution adds ≤5ms (p95 over 1000 calls) — measured by `advisor-strategy-loader-perf.bats`
- [ ] AC-S1.8 — `/review-sprint` + `/audit-sprint` cycle gates green; engineer/auditor feedback files at `grimoires/loa/a2a/auditor-sprint-feedback.md` show APPROVED

### 1.3 Tasks

#### T1.A — Atomic skill-role migration + schema enum seed + CODEOWNERS expansion

> **Satisfies**: SDD §20.1 (ATK-A1 closure), §21.2 (IMP-010 atomic seeding), §13.1 T1.J (CODEOWNERS)
> **Effort**: L
> **Deps**: none (starts Sprint 1)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/skills/*/SKILL.md` (35+ files — add `role` frontmatter field)
> - **🔒 SYSTEM ZONE**: `.claude/data/schemas/advisor-strategy.schema.json` (new file; `audited_review_skills` enum seeded)
> - **🔒 SYSTEM ZONE**: `.claude/scripts/migrate-skill-roles.sh` (new)
> - **🔒 SYSTEM ZONE**: `tools/seed-audited-review-skills.py` (new)
> - `.github/CODEOWNERS` (expanded per §20.1)

**Mechanical AC**:

1. `git log -1 --name-only` on the landing commit shows ALL of the following in the SAME commit: `.claude/skills/*/SKILL.md` files modified, `.claude/data/schemas/advisor-strategy.schema.json` modified, `.github/CODEOWNERS` modified. Test: `bash tests/integration/cycle-108-atomic-commit.bats`.
2. `tools/migrate-skill-roles.sh --dry-run` produces a `migration-plan.md` listing every SKILL.md and its proposed role (one of: planning | review | implementation). Operator-reviewable.
3. `tools/seed-audited-review-skills.py` reads migration-plan.md and emits the `audited_review_skills` enum in the schema. The enum MUST contain at minimum: `review-sprint, audit-sprint, reviewing-code, auditing-security, bridgebuilder-review, flatline-review, red-team, red-teaming, gpt-review, post-pr-validation` (SDD §20.1 explicit allowlist).
4. CODEOWNERS file contains the 4-line block from SDD §20.1 (`.claude/skills/*/SKILL.md @janitooor`, `.github/CODEOWNERS @janitooor`, `.github/workflows/cycle-108-*.yml @janitooor`, `.claude/defaults/model-config.yaml @janitooor`).
5. Negative test: A simulated PR that splits the migration across two commits (SKILL.md in commit A, schema enum in commit B) is rejected by the CI gate (T1.B).
6. `validate-skill-capabilities.sh` (post-T1.D) green against all migrated SKILL.md files.

#### T1.B — `cycle-108-schema-guard.yml` CI workflow

> **Satisfies**: SDD §20.7 (ATK-A17 closure), §21.2 cross-commit rejection
> **Effort**: M
> **Deps**: T1.A (schema file must exist)
> **Files touched**:
> - `.github/workflows/cycle-108-schema-guard.yml` (new)

**Mechanical AC**:

1. Workflow triggers on PRs touching any of: `.claude/data/schemas/advisor-strategy.schema.json`, `.claude/adapters/loa_cheval/config/loader.py`, `.claude/skills/*/SKILL.md`, `.claude/defaults/model-config.yaml`, `.github/CODEOWNERS`.
2. Workflow asserts PR has `@janitooor` as a reviewer; if absent, sets `failure` status check.
3. Workflow queries GH API `/repos/<owner>/<repo>/audit-log` for admin-bypass events in last 24h on the protected file set; on detection, sets `failure` + writes a comment to the PR.
4. Workflow diff-checks: a PR touching SKILL.md `role:` field MUST also touch `audited_review_skills` enum within the same commit. Test fixture PR: a deliberate cross-commit split fails CI.
5. Workflow has required-status-check pinned via branch protection; documented in `grimoires/loa/runbooks/advisor-strategy-rollback.md`.
6. `gh workflow run cycle-108-schema-guard.yml` on a clean PR returns exit 0; on a poisoned PR returns non-zero.

#### T1.C — Schema-pinned `audited_review_skills` enforcement at loader §3.3 step 4

> **Satisfies**: SDD §20.1 (ATK-A1 closure step 2 — loader enforcement); PRD §5 FR-1 IMP-003
> **Effort**: M
> **Deps**: T1.A (schema exists with enum)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/config/loader.py` (new function `load_advisor_strategy()` + step-4 enforcement)
> - `tests/unit/advisor-strategy-loader.bats` (new)
> - `tests/fixtures/advisor-strategy/poisoned-configs/*.yaml` (5 negative fixtures)

**Mechanical AC**:

1. `load_advisor_strategy(repo_root)` returns an `AdvisorStrategyConfig` frozen dataclass per SDD §21.1 (or `disabled_legacy()` if absent / LOA_ADVISOR_STRATEGY_DISABLE=1).
2. Loader step-4 iterates `skill_registry`; for any skill where `skill.role == "review"` and `skill_name not in cfg.audited_review_skills`, exits 78 with message `"Unaudited review skill: <name>"`.
3. Five poisoned-config fixtures (all variations of NFR-Sec1 bypass attempts) each cause exit 78. Test: `bats tests/unit/advisor-strategy-loader.bats`.
4. One positive fixture (a clean config) returns a valid `AdvisorStrategyConfig` and exits 0.
5. JSON Schema validation runs BEFORE loader step-4 (schema is the first line of defense; loader is defense-in-depth).
6. Loader perf: p95 over 1000 calls ≤5ms (NFR-P1). Measured by `tests/unit/advisor-strategy-loader-perf.bats`.

#### T1.D — Validator heuristic linter + diff-aware role-change rule

> **Satisfies**: SDD §20.5 (ATK-A13 closure — semantic-vs-declared role lie detection), §20.10 ATK-A2 (diff-aware role-change rule)
> **Effort**: M
> **Deps**: T1.A (SKILL.md files have `role:` fields)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/scripts/validate-skill-capabilities.sh` (extended at line ~146 per SDD §4.2)
> - `tests/unit/skill-capabilities-role-lint.bats` (new)
> - `tests/fixtures/skills/role-lint/*.md` (positive + negative fixtures)

**Mechanical AC**:

1. For any SKILL.md with `role: review` or `role: audit`, validator requires ≥2 review-class keywords in body from: `review, audit, validate, verify, score, consensus, adversarial, inspect, findings, regression`.
2. Failure produces a soft warning unless body contains `# REVIEW-EXEMPT: <rationale>` magic comment.
3. Diff-aware rule: when `role:` changes on an existing SKILL.md (detected via `git diff`), validator requires `# ROLE-CHANGE-AUTHORIZED-BY: <operator> ON <YYYY-MM-DD>` magic comment in the PR description OR co-sign in PR body. Reject `review|audit → implementation` transitions without this co-sign.
4. CI gate runs validator against all skills on every PR; negative fixture (a sham `role: review` skill with no review keywords) fails CI.
5. Skill writing tests: a positive fixture passes; 3 negative fixtures (no keywords, sham role change, missing rationale) all fail.

#### T1.E — Symlink scan + FS-snapshot-diff harness hooks (stubs)

> **Satisfies**: SDD §20.6 (ATK-A14 closure step 3 — Sprint 1 acceptance for FS-snapshot stubs)
> **Effort**: S
> **Deps**: none
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/scripts/lib/harness-fs-guard.sh` (new — stubs `harness_symlink_scan` and `harness_fs_snapshot_pre` / `_post`)
> - `tests/unit/harness-fs-guard.bats` (new)

**Mechanical AC**:

1. `harness_symlink_scan <dir>` runs `find "$dir" -type l` and verifies every symlink's `realpath` resolves INSIDE `$dir`. Returns 0 if all clean; returns 1 + emits BLOCK message naming each outside-pointing symlink and target.
2. `harness_fs_snapshot_pre <out-file>` captures mtimes + sizes for `~`, `/tmp`, `/var/tmp`, `<repo-root>-but-outside-worktree`, `.run/` (excluding `.run/model-invoke.jsonl`).
3. `harness_fs_snapshot_post <pre-file>` re-captures and diffs; emits BLOCK + JSON entry on unexplained mutation.
4. Both functions are CALLABLE from Sprint 2's `tools/advisor-benchmark.sh`; they are stubs in Sprint 1 (no harness yet) but their unit tests run on synthetic inputs.
5. `bats tests/unit/harness-fs-guard.bats` green: positive case (no symlinks), negative case (outside-pointing symlink), positive snapshot diff (no changes), negative snapshot diff (planted mutation).

#### T1.F — `invocation_chain` envelope field + `writer_version` single source of truth

> **Satisfies**: SDD §20.5 step 2 (invocation_chain), §21.4 (IMP-012 writer_version SoT)
> **Effort**: M
> **Deps**: T1.C (loader returns valid config; envelope emitter needs it)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/audit/modelinv.py` (extend envelope emitter)
> - **🔒 SYSTEM ZONE**: `.claude/scripts/audit-envelope.sh` (bash twin)
> - **🔒 SYSTEM ZONE**: `.claude/data/schemas/modelinv-envelope-v1.2.schema.json` (new schema)
> - **🔒 SYSTEM ZONE**: `.claude/data/cycle-108/modelinv-writer-version` (new — contains `1.2`)
> - `tests/integration/modelinv-writer-version-parity.bats` (new)

**Mechanical AC**:

1. `modelinv.py` reads `.claude/data/cycle-108/modelinv-writer-version` at module import; bash twin reads on each emit.
2. Every envelope emitted post-cycle-108 contains `payload.writer_version: "1.2"` and `payload.invocation_chain: [<parent_skill>, <grandparent_skill>, ...]` (top-most caller first).
3. Cross-emitter parity test: bash + Python emit envelopes for the same logical event; `jq -c .payload.writer_version` returns identical strings; `jq -c .payload.invocation_chain` returns identical arrays.
4. Schema v1.2 includes `schema_version: { const: "1.2" }` REQUIRED. Existing v1.1 entries remain readable (loader accepts both).
5. Strip-attack test: rollup tool (Sprint 2) rejects post-cutoff entries lacking `schema_version: "1.2"` with `[STRIP-ATTACK-DETECTED]` BLOCKER (SDD §20.4 step 2). Negative fixture confirms.

#### T1.G — `cycle108-update-golden-pins.sh` atomic signing flow + rollback trace-comparison test

> **Satisfies**: SDD §21.3 (IMP-009 golden-pins operational spec), §13.1 T1.H (FR-7 IMP-010 trace-comparison)
> **Effort**: M
> **Deps**: T1.F (MODELINV v1.2 emitter exists — golden file uses v1.2)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `tools/cycle108-update-golden-pins.sh` (new — compute-sha → sign → emit-envelope → commit, atomically)
> - `tests/fixtures/cycle-108/golden-pins.json` (new — operator-signed)
> - `tests/fixtures/cycle-108/golden-rollback-trace.modelinv` (new — golden MODELINV trace)
> - `tests/fixtures/cycle-108/golden-pins.audit.jsonl` (new — signing audit chain)
> - `tests/integration/rollback-trace-comparison.bats` (new)
> - `.git/hooks/pre-commit` (extend to verify signing key matches operator's id when golden-pins.json changes)

**Mechanical AC**:

1. `tools/cycle108-update-golden-pins.sh` runs as ONE atomic sequence: compute SHA256 of `golden-rollback-trace.modelinv` → `audit_emit_signed` with operator key → write `golden-pins.json` with updated SHA + signed_at → commit. Any step failure aborts the whole sequence (no partial state).
2. `rollback-trace-comparison.bats`: reads `golden-pins.json`, verifies SHA256 of fixture matches pin, runs a full-cycle replay under `advisor_strategy.enabled: false`, compares MODELINV trace to golden. Deviation fails the test.
3. Pre-commit hook verifies signing key in `golden-pins.json::signed_by_key_id` matches operator id in `OPERATORS.md`.
4. Pin includes: `schema_version=1`, `fixture_path`, `sha256`, `signed_by_key_id`, `signed_at` (ISO-8601), `rotation_policy: "operator-triggered; no automatic expiration"`, `last_verified_at`.
5. Rotation test: changing the fixture without re-signing fails the bats test (SHA mismatch).

#### T1.H — cheval CLI: `--role` / `--skill` / `--sprint-kind` flags

> **Satisfies**: PRD §5 FR-2, SDD §13.1 T1.C
> **Effort**: M
> **Deps**: T1.C (loader exists), T1.F (envelope emitter knows new fields)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/cheval.py` (extend `cmd_invoke` at line ~517)
> - `tests/unit/cheval-role-routing.bats` (new)

**Mechanical AC**:

1. `cheval invoke --role implementation --skill implement --sprint-kind glue ...` accepts and parses all three flags; argparse rejects unknown role/sprint-kind values with exit 2.
2. Backward-compat fixture: `cheval invoke <model> ...` (no role flag) behaves identically to pre-cycle-108 — same model resolution, same envelope shape (envelope still has `role` field but value is `"unspecified"` per NFR-O1).
3. When `--role` is supplied AND `advisor_strategy.enabled: true`, cheval resolves via `loa_cheval/routing/advisor_strategy.py::resolve_role_to_model()` (T1.I).
4. MODELINV envelope captured contains the supplied `--role`, `--skill`, `--sprint-kind` in `payload`.
5. `cheval --role implementation` under `enabled: false` ignores role and uses today's resolution path (NFR-Sec3 compliance).

#### T1.I — Resolver: `loa_cheval/routing/advisor_strategy.py` + bash twin

> **Satisfies**: PRD §5 FR-2, SDD §3.5 resolver architecture, §13.1 T1.D (6 parity cases)
> **Effort**: M
> **Deps**: T1.C (loader returns AdvisorStrategyConfig with resolve() method)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/routing/advisor_strategy.py` (new)
> - **🔒 SYSTEM ZONE**: `.claude/scripts/lib/advisor-strategy-resolver.sh` (new — thin exec wrapper)
> - `tests/integration/advisor-strategy-parity.bats` (new)
> - `tests/fixtures/advisor-strategy/canonical-resolved-tier.json` (new — golden output)

**Mechanical AC**:

1. `resolve_role_to_model(role, skill, provider)` returns a `ResolvedTier` dataclass per SDD §21.1.
2. Bash twin `advisor-strategy-resolver.sh` exec's Python resolver; returns JSON via stdout; parsed via `jq` by callers.
3. Six parity cases byte-equal across bash + Python (SDD §13.1 T1.D acceptance):
   - (role=review, skill=review-sprint, provider=anthropic)
   - (role=implementation, skill=implement, provider=anthropic, with per_skill_override)
   - (role=implementation, skill=bug, provider=openai)
   - (role=planning, skill=architect, provider=google, tier_resolution=dynamic)
   - (enabled=false; role=anything) — returns `tier=advisor, tier_source=disabled`
   - (LOA_ADVISOR_STRATEGY_DISABLE=1) — returns `tier_source=kill_switch`
4. NFR-Sec1 runtime check: resolver raises if config attempts to resolve a review-class skill to executor tier (defense-in-depth alongside loader).
5. Within-company fallback-chain semantics preserved within the resolved tier (NFR-R2): if `claude-sonnet-4-6` fails, walks `tier_aliases.executor.anthropic` chain.

#### T1.J — `tier_resolution` mode (static / dynamic) + in-flight kill-switch semantics

> **Satisfies**: PRD §5 FR-9 (IMP-009), FR-7 (IMP-007 in-flight semantics), SDD §3.6, §13.1 T1.G + T1.I
> **Effort**: S
> **Deps**: T1.I (resolver exists)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/routing/advisor_strategy.py` (extend)
> - `.run/sprint-plan-state.json` (extend schema to include `tier_transitions: []`)
> - `tests/integration/in-flight-kill-switch.bats` (new)

**Mechanical AC**:

1. `static` mode (DEFAULT): tier alias resolves to the model ID as of `.loa.config.yaml` commit time. MODELINV envelope `payload.tier_resolution = "static:<config_sha>"`.
2. `dynamic` mode: tier alias re-resolves on every invocation. MODELINV envelope `payload.tier_resolution = "dynamic"`.
3. Switching static → dynamic mid-cycle emits an operator-visible warning to stderr + audit log entry.
4. In-flight kill-switch: setting `LOA_ADVISOR_STRATEGY_DISABLE=1` during a sprint takes effect on the NEXT cheval invocation (per-call re-read), not mid-call. Test simulates: start sprint with enabled=true, midway export env var, next cheval call returns advisor tier.
5. `.run/sprint-plan-state.json` records every tier transition with `{ts, from_tier, to_tier, reason}` in `tier_transitions` array.

#### T1.K — Migration: populate `role` field for 35+ SKILL.md files

> **Satisfies**: PRD §5 FR-3 (IMP-012 multi-role tiebreaker), SDD §4.3, §13.1 T1.F
> **Effort**: M (bundled into T1.A atomic commit; this task captures the audit + multi-role review)
> **Deps**: T1.A (migration script exists; this is the apply + sign-off step)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/skills/*/SKILL.md` (35+ — already touched by T1.A; this task adds `primary_role` to multi-role skills)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/skill-role-migration-review.md` (new — operator-reviewable migration plan + multi-role tiebreaker decisions)

**Mechanical AC**:

1. Every skill in `.claude/skills/` has `role: planning | review | implementation` in frontmatter. No skill ships without `role` (CI fails-closed).
2. Skills declared multi-role (≥2 of planning/review/implementation) MUST also declare `primary_role` (advisor-wins-ties tiebreaker rule applies if absent).
3. 6 high-confidence multi-role skills hand-reviewed (per SR-6): `/run-bridge`, `/spiraling`, `/implement` (impl + light planning?), `/bug` (impl + light triage), `/audit` (review-class but standalone), `/post-pr-validation`.
4. Migration review doc lists EVERY skill + its assigned role + (for multi-role) the `primary_role` rationale; operator signs off in PR description.
5. Validator (T1.D) confirms all skills pass post-migration.

#### T1.L — Documentation: `grimoires/loa/runbooks/advisor-strategy-rollback.md`

> **Satisfies**: SDD §13.1 T1.K
> **Effort**: S
> **Deps**: T1.J (kill-switch semantics finalized), T1.G (trace-comparison test green)
> **Files touched**:
> - `grimoires/loa/runbooks/advisor-strategy-rollback.md` (new)

**Mechanical AC**:

1. Doc has sections: "When to roll back", "How to roll back (config flip)", "How to roll back (env var)", "How to roll back (revert PR)", "Verification: confirm advisor tier restored", "Troubleshooting".
2. "Verification" section names exact `jq` command operator runs to confirm MODELINV envelope shows advisor model IDs at all six consumers.
3. Doc cites: PRD §5 FR-7, SDD §7, SDD §20.7 (admin-bypass scan).
4. Pre-merge: operator reads + comments on the runbook draft.

### 1.4 Sprint 1 dependencies + sub-phase sequencing

**Sub-phases** (within Sprint 1, to break the LARGE into reviewable chunks):

- **Phase 1a — Schema + loader foundation**: T1.A (atomic migration) → T1.B (CI gate) → T1.C (loader enforcement) → T1.D (validator linter)
- **Phase 1b — Cheval routing**: T1.F (envelope schema) → T1.H (CLI) → T1.I (resolver) → T1.J (modes)
- **Phase 1c — Operator-facing**: T1.E (harness hooks) → T1.G (golden-pins) → T1.K (skill migration review) → T1.L (runbook)

Order within phase is strict; phases can overlap only after their first task is done.

### 1.5 Sprint 1 risks

| ID | Risk | Mitigation |
|----|------|------------|
| SR1-1 | T1.A atomic commit is massive (35+ SKILL.md + schema + CODEOWNERS in one); operator review burden | Pre-stage migration-plan.md for review BEFORE running the apply step; T1.K captures sign-off explicitly |
| SR1-2 | T1.F envelope schema bump breaks existing v1.1 consumers | Acceptance includes "v1.1 entries still validate"; integration test runs `audit_verify_chain` over mixed v1.1/v1.2 chain |
| SR1-3 | T1.G golden-pins flaky on non-deterministic LLM responses in trace | Trace test uses **recorded-replay** path (per IMP-005 separation); only compares envelope-shape, not LLM-content |

### 1.6 Sprint 1 review + audit gates

- `/review-sprint cycle-108-sprint-1`: validates all 12 tasks against AC; checks `/implement` produced clean code; engineer-feedback at `grimoires/loa/a2a/engineer-sprint-feedback.md`
- `/audit-sprint cycle-108-sprint-1`: validates security (NFR-Sec1 loader enforcement is real; CODEOWNERS coverage complete; no schema bypass paths); audit-feedback at `grimoires/loa/a2a/auditor-sprint-feedback.md`
- **Definition of done**: auditor-sprint-feedback.md contains `APPROVED - LETS FUCKING GO`

---

## 2. Sprint 2 — Measurement substrate

> Goal: ship the benchmark harness, cost-rollup tool, stratifier, and pre-registered baselines machinery. Sprint 3 cannot start until baselines.json is signed.

**Scope**: LARGE (12 tasks, T2.A–T2.P condensed below — some merged).
**Sprint goal**: Land the measurement substrate (harness + rollup + classifier + baselines) such that a single command can produce a fully-stratified benchmark report from `.run/model-invoke.jsonl`, with hash-chain-validated cost data + pre-registered targets that cannot be retrospectively fitted.

### 2.1 Deliverables

- [ ] D2.1 — `tools/advisor-benchmark.sh` worktree-hermetic harness with cost cap + variance protocol + chain-exhaustion classifier
- [ ] D2.2 — `tools/advisor-benchmark-stats.py` paired-bootstrap + pass/fail/inconclusive/untestable classifier
- [ ] D2.3 — `tools/modelinv-rollup.sh` with per-stratum grouping + hash-chain fail-closed + envelope-captured pricing
- [ ] D2.4 — `tools/sprint-kind-classify.py` multi-feature scored classifier + operator override
- [ ] D2.5 — `tools/select-benchmark-sprints.py` deterministic sprint-selection algorithm
- [ ] D2.6 — `tools/compute-baselines.py` over historical MODELINV data
- [ ] D2.7 — `.run/historical-medians.json` computed + CODEOWNERS-protected
- [ ] D2.8 — MODELINV envelope-captured `payload.pricing_snapshot` field
- [ ] D2.9 — `LOA_REPLAY_CONTEXT=1` replay-marker field on envelope + rollup default-exclude
- [ ] D2.10 — `LOA_NETWORK_RESTRICTED=1` enforcement in cheval + shell wrappers
- [ ] D2.11 — MODELINV coverage audit report (≥90% target per [ASSUMPTION-A4])
- [ ] D2.12 — Memory-budget benchmark stats (≤256MB resident for 100-replay aggregation)

### 2.2 Sprint-level Acceptance Criteria

- [ ] AC-S2.1 — `tools/advisor-benchmark.sh --dry-run --sprints sprint-x,sprint-y,sprint-z` emits a cost estimate using envelope-captured pricing + historical-medians.json
- [ ] AC-S2.2 — Benchmark harness REFUSES to run replays if `baselines.json` is missing or hash-mismatched (FR-8 acceptance)
- [ ] AC-S2.3 — Benchmark harness REFUSES to start if estimate exceeds `advisor_strategy.benchmark.max_cost_usd` (default $50; override `--cost-cap-usd N`)
- [ ] AC-S2.4 — Replay produces a manifest at `replay-manifests/<sprint>-<tier>-<idx>.json` with `replay_marker: true` and `LOA_NETWORK_RESTRICTED=1` enforced
- [ ] AC-S2.5 — `tools/modelinv-rollup.sh --per-stratum --last-90-days` produces a valid JSON + Markdown report; emits hash-chain-validation success message
- [ ] AC-S2.6 — Broken-chain fixture causes rollup tool to exit 1 with `[STRIP-ATTACK-DETECTED]` / chain-failure message; NO partial report emitted
- [ ] AC-S2.7 — Coverage audit confirms MODELINV envelope coverage ≥90% of cycle token spend; if <90%, Sprint 2 ships a coverage-improvement subtask before Sprint 3 can start
- [ ] AC-S2.8 — Stats tool processes 100-replay aggregation under `ulimit -v 262144` without OOM (memory-budget AC per §21.5)
- [ ] AC-S2.9 — `/review-sprint` + `/audit-sprint` cycle gates green; auditor-feedback shows APPROVED

### 2.3 Tasks

#### T2.A — Benchmark harness skeleton: `tools/advisor-benchmark.sh`

> **Satisfies**: PRD §5 FR-4, SDD §5.1, §5.2 (hermeticity), §13.2 T2.A
> **Effort**: L
> **Deps**: Sprint 1 complete (cheval routing + envelope schema exist)
> **Files touched**:
> - `tools/advisor-benchmark.sh` (new)
> - `tools/advisor-benchmark-lib.sh` (new — shared helpers)
> - `tests/integration/advisor-benchmark-hermeticity.bats` (new)

**Mechanical AC**:

1. Harness creates a worktree at `/tmp/loa-advisor-replay-<sprint>-<tier>-<idx>/` via `git worktree add`.
2. Harness calls `harness_symlink_scan` (from T1.E) on the worktree pre-replay + post-replay; blocks on outside-pointing symlinks.
3. Harness calls `harness_fs_snapshot_pre` + `harness_fs_snapshot_post`; blocks on unexplained mutations.
4. Hermeticity bats test: a replay that attempts to write to `<repo-root>/main` fails with BLOCK; the original repo tree is unmodified after replay.
5. `trap 'cleanup_worktree' EXIT` ensures worktree teardown on every exit path (including SIGINT).
6. Daily cron entry at `.run/cron.d/cleanup-advisor-replays.sh` removes `/tmp/loa-advisor-replay-*` older than 24h.

#### T2.B — Variance protocol + classifier: `tools/advisor-benchmark-stats.py`

> **Satisfies**: PRD §5 FR-4 IMP-004, SDD §5.5, §9, §13.2 T2.B, §21.5 (memory budget)
> **Effort**: M
> **Deps**: T2.A (harness produces replay-result JSONL)
> **Files touched**:
> - `tools/advisor-benchmark-stats.py` (new — paired-bootstrap + classifier + UNTESTABLE outcome)
> - `tests/unit/benchmark-stats-classify.bats` (new)
> - `tests/integration/benchmark-stats-memory.bats` (new — runs under `ulimit -v 262144`)

**Mechanical AC**:

1. Paired bootstrap (n=10000 resamples) over per-sprint score deltas; CIs at 95%.
2. `classify_pair(sprint, tier)` returns PASS / FAIL / INCONCLUSIVE / OPT-IN-ONLY / **UNTESTABLE** (per SDD §20.10 ATK-A5).
3. UNTESTABLE rule: if `INCONCLUSIVE_count / total_replays > 0.25` for any stratum, that stratum is UNTESTABLE; rollout-policy doc decision-fork is amended.
4. Variance flag: if any (sprint, tier) pair shows >2σ across its 3 replays, that pair is flagged for re-run with 2 additional replays. If variance persists, the sprint is dropped from stratum aggregate, recorded separately as "harness-defect candidate".
5. Streaming-mode AC: stats tool reads replay-result JSONL line-by-line (iterator), NOT loading all results into memory. `tests/integration/benchmark-stats-memory.bats` runs the tool under `ulimit -v 262144` (256MB) over a 100-replay synthetic fixture; tool exits 0.

#### T2.C — Replay-semantics separation (fresh-run vs recorded-replay)

> **Satisfies**: PRD §5 FR-4 IMP-005, SDD §5.6, §13.2 T2.C
> **Effort**: S
> **Deps**: T2.A (harness exists)
> **Files touched**:
> - `tools/advisor-benchmark.sh` (extend — `--mode fresh-run | recorded-replay` flag)
> - `tests/integration/replay-semantics-isolation.bats` (new)

**Mechanical AC**:

1. `--mode fresh-run`: harness re-executes the sprint from `git checkout pre-sprint-SHA`; LLM generates everything fresh; emitted to `benchmark-report.md` headline section.
2. `--mode recorded-replay`: harness uses cached prompts + cached responses (deterministic plumbing-test mode); emitted to `benchmark-report.md` "harness-validation" appendix ONLY.
3. Isolation test: a report generation run with mixed-mode replay inputs MUST place recorded-replay results outside the headline section. Test reads generated report, asserts headline section contains only fresh-run results.
4. Sprint-3 acceptance includes `--mode fresh-run` (the only valid mode for the cycle-108 benchmark).

#### T2.D — Cost-cap pre-estimate (IMP-011)

> **Satisfies**: PRD §5 FR-4 IMP-011, NFR-P3, SDD §5.8, §13.2 T2.D
> **Effort**: S
> **Deps**: T2.L (historical-medians.json must exist), T2.J (envelope-captured pricing exists)
> **Files touched**:
> - `tools/advisor-benchmark.sh` (extend with `--cost-cap-usd N` + pre-run estimate)
> - `tests/integration/cost-cap-estimate.bats` (new)

**Mechanical AC**:

1. Harness reads `.run/historical-medians.json` + envelope-captured pricing; computes `sum(median_tokens × price)` over planned replays.
2. If estimate > `advisor_strategy.benchmark.max_cost_usd` (default $50, override `--cost-cap-usd N`), harness aborts BEFORE any replays start; exit code 78; prints estimate breakdown.
3. After all replays complete, harness writes `estimate-vs-actual.json` to the cycle dir; benchmark-report.md includes a section showing estimate vs actual ±%.
4. Test: poisoned-historical-medians fixture (artificially low) inflates estimate after replays; report flags this.

#### T2.E — Chain-exhaustion classifier (IMP-013)

> **Satisfies**: PRD §5 FR-4 IMP-013, SDD §5.7, §13.2 T2.E
> **Effort**: S
> **Deps**: T2.A (replay outcome captured in manifest)
> **Files touched**:
> - `tools/advisor-benchmark-lib.sh` (extend `classify_replay_outcome`)
> - `tests/unit/chain-exhaustion-classify.bats` (new)

**Mechanical AC**:

1. `classify_replay_outcome(manifest)` returns OK / OK-with-fallback / INCONCLUSIVE / EXCLUDED per the FR-4 IMP-013 table.
2. INCONCLUSIVE replays NOT counted in stratum aggregate; reported under "inconclusive runs" section.
3. EXCLUDED replays (operator-aborted) not counted at all.
4. Negative test: a chain-exhaustion fixture (all models in chain returned errors) produces INCONCLUSIVE classification.

#### T2.F — Cost rollup: `tools/modelinv-rollup.sh`

> **Satisfies**: PRD §5 FR-5, SDD §6, §13.2 T2.F
> **Effort**: M
> **Deps**: T1.F (envelope schema v1.2 with new fields)
> **Files touched**:
> - `tools/modelinv-rollup.sh` (new)
> - `tests/integration/modelinv-rollup-grouping.bats` (new)

**Mechanical AC**:

1. Reads `.run/model-invoke.jsonl` (READ-ONLY — does not mutate audit log).
2. Groups by: cycle_id, skill_name, role, tier, final_model_id, **and stratum** (sprint_kind from FR-5 IMP-014).
3. Emits JSON + Markdown; markdown has per-stratum columns showing cost reduction (advisor vs executor).
4. CLI flags: `--per-cycle`, `--per-skill`, `--per-role`, `--per-tier`, `--per-model`, `--per-stratum`, `--last-90-days`, `--last-N-days N`, `--include-replays`.
5. Default mode EXCLUDES replay-marker envelopes (per T2.M).

#### T2.G — Hash-chain fail-closed integrity check (IMP-008)

> **Satisfies**: PRD §5 FR-5 IMP-008, SDD §6.2, §13.2 T2.G
> **Effort**: S
> **Deps**: T2.F (rollup tool exists)
> **Files touched**:
> - `tools/modelinv-rollup.sh` (extend with chain-integrity check)
> - `tests/integration/rollup-hash-chain-fail.bats` (new)

**Mechanical AC**:

1. Rollup tool calls `audit_verify_chain` (from `.claude/scripts/audit-envelope.sh`) BEFORE emitting any output.
2. If chain validation fails, exits 1 with explicit error identifying the failing record's `primitive_id` + line offset. NO partial report emitted.
3. Negative fixture: a broken-chain JSONL file causes exit 1.
4. Recovery via `audit_recover_chain` documented in error message + `grimoires/loa/runbooks/advisor-strategy-rollback.md`.

#### T2.H — Strip-attack detection on MODELINV v1.2 cutoff

> **Satisfies**: SDD §20.4 ATK-A7 closure (writer_version strict cutoff)
> **Effort**: S
> **Deps**: T2.F, T1.F (writer_version SoT exists)
> **Files touched**:
> - `tools/modelinv-rollup.sh` (extend with cutoff detection)
> - `tests/integration/rollup-strip-attack.bats` (new)

**Mechanical AC**:

1. Rollup tool records the cutoff timestamp = `ts_utc` of the first v1.2 entry on file.
2. Entries AFTER cutoff lacking `schema_version: "1.2"` cause `[STRIP-ATTACK-DETECTED]` BLOCKER; rollup aborts (exit 78).
3. Positive fixture: clean v1.2 chain rolls up cleanly.
4. Negative fixture: post-cutoff entry with stripped schema_version triggers BLOCKER.

#### T2.I — Stratifier: `tools/sprint-kind-classify.py` (multi-feature scored)

> **Satisfies**: PRD Appendix A (IMP-006), SDD §6.5, §8, §20.10 ATK-A9 (multi-feature scored), §13.2 T2.I
> **Effort**: M
> **Deps**: none (operates on git metadata)
> **Files touched**:
> - `tools/sprint-kind-classify.py` (new)
> - `tests/unit/sprint-kind-classify.bats` (new)

**Mechanical AC**:

1. Classifier reads sprint metadata (files touched, LOC delta, schema changes) from `git diff <pre-sprint-sha>..<post-sprint-sha>`.
2. Multi-feature scored: each rule emits `(stratum, confidence)`; classifier picks highest confidence. Ties broken by priority `cryptographic > parser > audit-envelope > testing > infrastructure > glue > frontend`.
3. Operator override: `--stratum-override <name> --rationale <text>` requires audit-log entry pinning the override rationale.
4. Strata supported: glue, parser, cryptographic, testing, infrastructure, frontend (PRD Appendix A).
5. Test: 12 historical sprint fixtures classify deterministically; operator override is logged.

#### T2.J — Envelope-captured pricing + sprint-selection algorithm + historical-medians

> **Satisfies**: SDD §20.9 ATK-A20 (envelope pricing), §20.2 ATK-A19 (deterministic selection), §20.10 ATK-A6 (historical-medians.json), §13.2 T2.J + T2.K
> **Effort**: M
> **Deps**: T1.F (envelope emitter), T2.F (rollup tool exists for historical-medians input)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/audit/modelinv.py` (extend emitter to capture `payload.pricing_snapshot`)
> - **🔒 SYSTEM ZONE**: `.claude/scripts/audit-envelope.sh` (bash twin)
> - `tools/select-benchmark-sprints.py` (new — deterministic algorithm)
> - `.run/historical-medians.json` (new — computed file)
> - `.github/CODEOWNERS` (extend — `.run/historical-medians.json @janitooor`)
> - `tests/integration/envelope-pricing-capture.bats` (new)
> - `tests/unit/select-benchmark-sprints.bats` (new)

**Mechanical AC**:

1. Every MODELINV envelope post-T2.J emit contains `payload.pricing_snapshot: { input_per_mtok: N, output_per_mtok: M }` captured at invocation time from `.claude/defaults/model-config.yaml`.
2. `tools/modelinv-rollup.sh` reads pricing FROM envelopes, NOT from current model-config (historical pricing changes don't retroactively rewrite cost reports).
3. `tools/select-benchmark-sprints.py`: inputs = stratifier output for last 90 days of merged PRs; min-replays-per-stratum N=3 (default). Selects the largest N such that ALL ≥4 strata have ≥N candidates; picks most-recent N from each stratum.
4. Operator override `--manual-selection <comma-list> --rationale <text>` requires L1-signed audit envelope entry.
5. `.run/historical-medians.json` is generated by `tools/modelinv-rollup.sh --per-stratum --last-90-days`; CODEOWNERS-protected; path-referenced from config.
6. Running-total cost check during benchmark (T2.D extension): after every replay, recompute `cost_so_far + remaining_estimate`; abort if exceeds cap.

#### T2.K — Replay-marker + rollup default-exclude

> **Satisfies**: SDD §20.10 ATK-A15
> **Effort**: XS
> **Deps**: T1.F (envelope emitter), T2.F (rollup tool)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/cheval.py` (read `LOA_REPLAY_CONTEXT=1` env)
> - **🔒 SYSTEM ZONE**: `.claude/adapters/loa_cheval/audit/modelinv.py` (emit `payload.replay_marker: true`)
> - `tools/modelinv-rollup.sh` (default-exclude replay-marked envelopes)
> - `tests/integration/replay-marker.bats` (new)

**Mechanical AC**:

1. Cheval invoked with `LOA_REPLAY_CONTEXT=1` (set by harness) emits envelope with `payload.replay_marker: true`.
2. Rollup tool default mode EXCLUDES replay-marked envelopes (prod queries are clean).
3. `--include-replays` flag opts in; reports separately.
4. Test: harness sets env, runs a single replay; rollup default excludes; `--include-replays` includes.

#### T2.L — Network-restriction env enforcement

> **Satisfies**: SDD §20.10 ATK-A16
> **Effort**: S
> **Deps**: T2.A (harness exists)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/adapters/cheval.py` (check `LOA_NETWORK_RESTRICTED=1`)
> - **🔒 SYSTEM ZONE**: `.claude/scripts/lib/cheval-network-guard.sh` (new — wrapper checks for curl/wget/nc/ftp invocations)
> - `tests/integration/network-restriction.bats` (new)

**Mechanical AC**:

1. Harness sets `LOA_NETWORK_RESTRICTED=1` for the replay process.
2. Cheval + shell wrappers refuse to invoke `curl`, `wget`, `nc`, `ftp` unless target is in the LLM-provider endpoint allowlist (Anthropic, OpenAI, Google).
3. Test: harness-internal `curl http://evil.example` fails with BLOCK message; `curl https://api.anthropic.com/...` succeeds (allowlist hit).
4. Stretch (deferred to Sprint 2 closing if time): container netns with egress-only-to-allowlist documented but not implemented.

#### T2.M — MODELINV coverage audit

> **Satisfies**: [ASSUMPTION-A4] resolution, SDD §13.2 T2.J (renumbered to T2.M in this plan), SR-7
> **Effort**: S
> **Deps**: T2.F (rollup exists)
> **Files touched**:
> - `tools/modelinv-coverage-audit.py` (new)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/coverage-audit.md` (new — report)

**Mechanical AC**:

1. Coverage audit: for each (cycle, skill) pair, compare number of MODELINV envelopes vs git-log-derived count of skill invocations.
2. If coverage <90% overall, Sprint 2 ships a coverage-improvement subtask BEFORE Sprint 3 can start (gate on `coverage-audit.md` status).
3. Report committed; per-skill coverage % visible.
4. Sprint 3 startup script asserts `coverage_pct ≥ 0.90`; otherwise aborts.

### 2.4 Sprint 2 dependencies + sequencing

**Sub-phases**:
- **Phase 2a — Substrate extensions**: T2.J (envelope pricing + writer extensions) → T2.K (replay marker) → T2.L (network restriction)
- **Phase 2b — Rollup + classifier**: T2.F (rollup) → T2.G (hash-chain) → T2.H (strip-attack) → T2.I (stratifier) → T2.M (coverage audit)
- **Phase 2c — Harness**: T2.A (harness skeleton) → T2.B (stats) → T2.C (replay-semantics) → T2.D (cost cap) → T2.E (chain-exhaustion)

T2.J / T2.K / T2.L (Phase 2a) extend Sprint-1 substrate and must land BEFORE Phase 2c so harness can use them.

### 2.5 Sprint 2 risks

| ID | Risk | Mitigation |
|----|------|------------|
| SR2-1 | MODELINV coverage <90% breaks Sprint 3 validity | T2.M coverage audit runs early in Sprint 2; coverage-improvement subtask lands before Sprint 3 |
| SR2-2 | Worktree teardown fails leaving orphan `/tmp` dirs | `trap 'cleanup_worktree' EXIT` + daily cron cleanup (T2.A) |
| SR2-3 | Pre-sprint SHA for replay isn't reproducible (squash merges) | Use `git log --format=%H "$pr_merge_sha^"` fallback per SR-5; warn operator |

### 2.6 Sprint 2 review + audit gates

- `/review-sprint cycle-108-sprint-2` + `/audit-sprint cycle-108-sprint-2`; APPROVED in auditor-feedback before Sprint 3 starts.

---

## 3. Sprint 3 — Empirical benchmark (operator-driven)

> Goal: produce the actual data. Operator signs `baselines.json` + git-tag pin BEFORE any replays. Run ≥36 replays (12 sprints × 3 replays at executor tier). Emit stratified report with 95% CIs.

**Scope**: MEDIUM (7 tasks).
**Sprint goal**: Sign + commit pre-registered baselines, run ≥12 sprints × ≥3 replays at executor tier per stratum, produce a stratified `benchmark-report.md` with 95% bootstrap CIs and per-stratum PASS / FAIL / INCONCLUSIVE / UNTESTABLE classification.

### 3.1 Deliverables

- [ ] D3.1 — `tools/compute-baselines.py` produces `baselines.json` candidates from historical MODELINV data
- [ ] D3.2 — Operator runs `audit_emit_signed` over baselines.json (`baselines.audit.jsonl` committed; chain valid, cross-cycle linked to cycle-107)
- [ ] D3.3 — **OPERATOR ACTION**: `cycle-108-baselines-pin-<sha>` Git tag signed with operator's tag-signing key (separate from L1)
- [ ] D3.4 — Replay-manifests for ≥12 selected sprints generated; operator approves selection
- [ ] D3.5 — ≥36 fresh-run replays executed (12 sprints × 3 replays at executor; baselines from history, not replayed)
- [ ] D3.6 — `benchmark-report.md` committed with paired-bootstrap CIs + per-stratum classification
- [ ] D3.7 — `estimate-vs-actual.json` reconciliation (within ±20% expected; deviations explained)

### 3.2 Sprint-level Acceptance Criteria

- [ ] AC-S3.1 — `baselines.json` committed with `signed_by_key_id` matching operator's id in OPERATORS.md
- [ ] AC-S3.2 — `git tag -v cycle-108-baselines-pin-<sha>` verifies operator's tag-signing key (operator-action required)
- [ ] AC-S3.3 — `baselines.audit.jsonl` chains off cycle-107's last L1 entry's hash (cross-cycle continuity per ATK-A4)
- [ ] AC-S3.4 — Benchmark report has ≥3 fresh-run replays per stratum across ≥4 strata = ≥12 benchmark runs (SC-6 minimum; ≥36 actual replays target)
- [ ] AC-S3.5 — Every report metric tagged with replay-type (fresh-run / recorded-replay); recorded-replay results NOT in headline scorecard
- [ ] AC-S3.6 — Per-stratum classification (PASS / FAIL / INCONCLUSIVE / UNTESTABLE) computed mechanically from SC-1..SC-5 + paired-bootstrap CIs
- [ ] AC-S3.7 — Cost reconciliation within ±20%; deviations explained in report
- [ ] AC-S3.8 — `/review-sprint` + `/audit-sprint` gates green; operator approval recorded in `grimoires/loa/cycles/cycle-108-advisor-strategy/operator-approval.md`

### 3.3 Tasks

#### T3.A — `tools/compute-baselines.py` over historical data + sign + cross-cycle chain

> **Satisfies**: PRD §5 FR-8 (IMP-001), SDD §5.9, §20.3 ATK-A4 (cross-cycle continuity), §13.3 T3.A + T3.B
> **Effort**: M
> **Deps**: Sprint 2 complete (rollup + stratifier exist)
> **Files touched**:
> - `tools/compute-baselines.py` (new)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.json` (new — pre-registered targets)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.audit.jsonl` (new — signing chain)

**Mechanical AC**:

1. `tools/compute-baselines.py --historical strata-historical.json` computes per-stratum advisor-tier baselines for SC-1..SC-5 from last-12 historical sprints across the 4 strata.
2. Executor-tier targets derived as `0.95 × baseline-audit-pass` per PRD §3 SC table.
3. `audit_emit_signed` over the computed file produces `baselines.audit.jsonl`.
4. **Cross-cycle linkage**: pre-commit hook rejects audit-jsonl files that lack `prev_hash` equal to cycle-107's last L1 entry's hash. Test fixture proves rejection.
5. baselines.json includes: per-stratum SC-1..SC-5 baseline + target, git_sha_at_signing, ts_utc, signed_by_key_id.

#### T3.A.OP — **OPERATOR ACTION**: Sign `cycle-108-baselines-pin-<sha>` Git tag

> **Satisfies**: SDD §20.3 ATK-A4 step 2 (out-of-band hash commitment via Git tag); §13.3 T3.A
> **Effort**: XS (operator command — not autonomous)
> **Deps**: T3.A (baselines.json + audit-jsonl exist + committed)
> **Files touched**:
> - Git tag (not a file — `refs/tags/cycle-108-baselines-pin-<sha>`)

**Mechanical AC**:

1. **OPERATOR**: `git tag -s -m "cycle-108 baselines pin" cycle-108-baselines-pin-$(jq -r .git_sha_at_signing baselines.json)`
2. Operator's tag-signing key (separate from L1 signing key) is documented in `OPERATORS.md`.
3. Harness (T3.C below) verifies tag's existence + signature BEFORE any replay.
4. `git tag -v cycle-108-baselines-pin-<sha>` exits 0 (signature verified).
5. **This task is an explicit operator gate** — autonomous /run mode pauses here; operator runs the tag command; autonomous mode resumes after `git tag -v` green.

#### T3.B — Harness acceptance gate: refuse-on-tamper

> **Satisfies**: PRD §5 FR-8 acceptance, SDD §13.3 T3.C
> **Effort**: XS
> **Deps**: T3.A + T3.A.OP (baselines + tag exist)
> **Files touched**:
> - `tools/advisor-benchmark.sh` (extend with baselines verification)
> - `tests/integration/baselines-tamper-detection.bats` (new)

**Mechanical AC**:

1. Harness reads `baselines.json` + verifies `git tag -v cycle-108-baselines-pin-<sha>` exits 0.
2. Harness computes SHA256 of baselines.json; compares to `git_sha_at_signing` field; aborts on mismatch.
3. Negative test: tamper baselines.json after signing; harness aborts with explicit error.
4. Negative test: missing baselines.json causes harness to refuse to start.

#### T3.C — Select replay sprints (operator approves)

> **Satisfies**: PRD §5 FR-4, SDD §20.2 ATK-A19 (deterministic selection), §13.3 T3.D
> **Effort**: S
> **Deps**: T2.J (select-benchmark-sprints.py exists), T2.I (stratifier classifies)
> **Files touched**:
> - `replay-manifests/` (new dir under cycle-108 dir)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/replay-manifests/<sprint>-<tier>-<idx>.json` (≥12 manifests × 3 replays = ≥36 files)
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/operator-approval.md` (new — operator signs off on selection)

**Mechanical AC**:

1. `tools/select-benchmark-sprints.py --last-90-days --min-per-stratum 3` produces a candidate list of ≥12 sprints across ≥4 strata.
2. Each selected sprint has 3 replay manifests at executor tier (advisor baselines come from history per FR-8).
3. Operator reviews `operator-approval.md` listing every selected sprint + its stratum classification; signs off OR uses `--manual-selection` with `--rationale`.
4. Operator override is L1-signed audit envelope entry.

#### T3.D — Execute replays

> **Satisfies**: PRD §5 FR-4, SDD §13.3 T3.E
> **Effort**: L (wall-clock; autonomous)
> **Deps**: T3.B (harness gates exist), T3.C (manifests approved)
> **Files touched**:
> - `replay-manifests/<sprint>-<tier>-<idx>/result.json` (one per replay)
> - `.run/model-invoke.jsonl` (envelopes appended — replay-marked)

**Mechanical AC**:

1. Harness runs ≥36 fresh-run replays under `LOA_REPLAY_CONTEXT=1` + `LOA_NETWORK_RESTRICTED=1`.
2. Wall-clock ≤6 hours (NFR-P2).
3. Cost stays under cap; running-total check fires if approaching.
4. Variance protocol: >2σ pairs flagged + 2 additional replays; if variance persists, sprint dropped + flagged as harness-defect-candidate.
5. Every replay produces a manifest result with: tokens, wall-clock, audit-pass outcome, review-findings density, BB iter count, chain-exhaustion outcome.
6. Replay-marker envelope on every cheval invocation; rollup default-exclude verified.

#### T3.E — Stats + report

> **Satisfies**: PRD §5 FR-4, SDD §9, §13.3 T3.F
> **Effort**: M
> **Deps**: T3.D (replay results exist)
> **Files touched**:
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/benchmark-report.md` (new — the headline deliverable)

**Mechanical AC**:

1. `tools/advisor-benchmark-stats.py --replay-results replay-manifests/ --baselines baselines.json` emits `benchmark-report.md`.
2. Report sections: Executive summary, Per-stratum classification table (PASS/FAIL/INCONCLUSIVE/UNTESTABLE/OPT-IN-ONLY), CIs at 95% paired-bootstrap, Per-stratum cost reduction, Replay-type breakdown (fresh-run only in headline; recorded-replay in appendix), Sources.
3. Cost reconciliation section: estimate-vs-actual within ±20%; deviations explained.
4. Mechanical decision-input section: surfaces the inputs for Sprint-4 decision-fork (per-stratum outcomes + per-stratum FAIL count).
5. Report is reproducible from `.run/model-invoke.jsonl` + git-SHAs alone (NFR-O2).

#### T3.F — Operator approval recorded

> **Satisfies**: PRD §10 cycle-level acceptance (operator reviews benchmark report)
> **Effort**: XS (operator action)
> **Deps**: T3.E
> **Files touched**:
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/operator-approval.md` (extend with benchmark sign-off)

**Mechanical AC**:

1. Operator reviews benchmark-report.md.
2. Records approval (or change-request) in operator-approval.md.
3. Sprint 4 cannot start until operator-approval.md shows "BENCHMARK APPROVED".

### 3.4 Sprint 3 risks

| ID | Risk | Mitigation |
|----|------|------------|
| SR3-1 | Operator unavailable to sign tag — Sprint 3 blocked | Operator-action is well-defined; tag-signing command + key id documented in OPERATORS.md; autonomous mode pauses cleanly at T3.A.OP |
| SR3-2 | Wall-clock >6h on replay run | Cost-cap should auto-abort; partial results still usable; report flags missing strata |
| SR3-3 | Variance protocol drops too many sprints — stratum becomes UNTESTABLE | T2.B UNTESTABLE outcome is explicit; rollout-policy doc Sprint-4 handles this case |

### 3.5 Sprint 3 review + audit gates

- `/review-sprint cycle-108-sprint-3` + `/audit-sprint cycle-108-sprint-3`; APPROVED required.
- Plus operator approval on benchmark-report.md before Sprint 4 starts.

---

## 4. Sprint 4 — Rollout policy + decision-fork

> Goal: derive rollout decision from Sprint 3 data mechanically. Decision-fork (a / b / c) determined by per-stratum classification. Ship migration guide + post-rollout watch hooks.

**Scope**: MEDIUM (8 tasks).
**Sprint goal**: Land the rollout-policy doc + decision-fork outcome + `.loa.config.yaml.example` defaults + migration guide + post-rollout watch hooks. Make the cycle's framework-level commitment concrete and reversible.

### 4.1 Deliverables

- [ ] D4.1 — `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md` with explicit (a)/(b)/(c) decision-fork outcome
- [ ] D4.2 — `.loa.config.yaml.example` updated with documented defaults per decision-fork
- [ ] D4.3 — `grimoires/loa/runbooks/advisor-strategy-migration.md` operator-facing migration guide
- [ ] D4.4 — `feedback_advisor_benchmark.md` auto-memory updated with cycle-108 datapoints (replaces spiral-harness-only data)
- [ ] D4.5 — `grimoires/loa/known-failures.md` updated with any new KF-NNN entries from benchmark observations
- [ ] D4.6 — 30-day post-rollout watch hook (post-merge orchestrator extension)
- [ ] D4.7 — Post-merge admin-bypass scan extension
- [ ] D4.8 — Per-skill daily token quota + alert

### 4.2 Sprint-level Acceptance Criteria

- [ ] AC-S4.1 — `rollout-policy.md` cites specific data points from `benchmark-report.md` for every per-stratum recommendation
- [ ] AC-S4.2 — Decision-fork outcome (a / b / c per PRD §7 Sprint 4) is documented mechanically — derived from baselines.json + benchmark-report.md, not discretionary
- [ ] AC-S4.3 — Per-stratum FAIL veto codified: if ANY stratum FAILs, decision (a) "default-on" is unavailable; operator can opt into (b)
- [ ] AC-S4.4 — `.loa.config.yaml.example` defaults reflect the decision (e.g., `enabled: false` if outcome is (b) or (c))
- [ ] AC-S4.5 — 30-day post-rollout watch hook: if production cycle under executor tier produces audit failures within 30 days, auto-revert `advisor_strategy.enabled` to false via post-merge hook
- [ ] AC-S4.6 — Admin-bypass scan: post-merge orchestrator scans merged-commit metadata for branch-protection-bypass on protected files; if detected, opens automatic revert PR + escalates to operator
- [ ] AC-S4.7 — Per-skill daily token quota: MODELINV rollup alerts when any single skill exceeds `daily_token_budget_default` (operator-configurable)
- [ ] AC-S4.8 — `/review-sprint` + `/audit-sprint` gates green

### 4.3 Tasks

#### T4.A — `rollout-policy.md` with explicit decision-fork

> **Satisfies**: PRD §5 FR-6, §7 Sprint 4 decision-fork, SDD §13.4 T4.A + T4.B, §20.2 per-stratum FAIL veto
> **Effort**: M
> **Deps**: Sprint 3 complete + operator approval on benchmark-report.md
> **Files touched**:
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md` (new)

**Mechanical AC**:

1. Doc captures: thresholds for "safe to default" (SC-1..SC-3 PASS on ≥3 sprints in a stratum), "operator opt-in only" (meets ≥2 of SC-1..SC-3), "DO NOT USE" (fails ≥1 of SC-1..SC-3), and **per-stratum FAIL veto** (any stratum FAIL → decision (a) blocked).
2. Per-sprint-kind recommended defaults derived from benchmark-report.md (cited inline with `[ref: benchmark-report.md §X]`).
3. "What to do on regression" section: triage flowchart for operator if production cycle X under executor tier produces audit failures.
4. **Decision-fork outcome explicitly recorded** (one of):
   - **(a) Default-on-for-passing-strata**: Sprint 3 produced ≥1 PASS stratum AND zero FAIL strata. Ship `advisor_strategy.enabled: true` as default with per-stratum opt-out for non-PASS strata.
   - **(b) Opt-in only**: Sprint 3 produced mixed outcomes (some PASS, some FAIL/INCONCLUSIVE/UNTESTABLE). Ship `enabled: false` default; rollout-policy captures per-stratum guidance.
   - **(c) Shelve**: Sprint 3 produced ALL FAIL or majority INCONCLUSIVE/UNTESTABLE. Ship FR-1..FR-9 substrate (behind default-off flag) + benchmark report + DO-NOT-ADOPT recommendation with full data trail. Re-evaluate in 6 months.
5. Net-negative branch (PRD §5 FR-6) explicitly handled in doc.

#### T4.B — 30-day post-rollout watch hook

> **Satisfies**: SDD §20.2 step 3 (post-rollout 30-day watch), §13.4 T4.B
> **Effort**: S
> **Deps**: T4.A (decision known)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/hooks/post-merge/cycle-108-rollout-watch.sh` (new)
> - `grimoires/loa/runbooks/advisor-strategy-migration.md` (mention the watch hook)

**Mechanical AC**:

1. Hook runs on post-merge to main; queries `.run/model-invoke.jsonl` for executor-tier audit failures within 30 days of rollout.
2. If executor-tier audit failure detected, auto-revert `advisor_strategy.enabled: true` → `false` in `.loa.config.yaml` via PR; escalate to operator with explicit issue.
3. Watch window expires after 30 days from rollout-commit-SHA; hook becomes no-op after.
4. Test: simulate audit failure within window; hook auto-creates revert PR.

#### T4.C — Post-merge admin-bypass scan

> **Satisfies**: SDD §20.7 ATK-A17 step 2 (post-merge orchestrator extension), §13.4 T4.C
> **Effort**: S
> **Deps**: T1.B (schema-guard workflow exists)
> **Files touched**:
> - **🔒 SYSTEM ZONE**: `.claude/scripts/post-merge-orchestrator.sh` (extend with admin-bypass scan)
> - `tests/integration/post-merge-admin-bypass.bats` (new)

**Mechanical AC**:

1. Post-merge orchestrator scans merged-commit metadata via GH API for branch-protection-bypass events on protected files (schema, loader, SKILL.md, model-config.yaml, CODEOWNERS, workflows).
2. If detected, opens automatic revert PR + escalates to operator via Slack/email alert.
3. Test: simulate admin-bypass; scan detects; revert PR opened.

#### T4.D — Per-skill daily token quota + alert

> **Satisfies**: SDD §20.5 step 3 (per-skill daily token quota), §13.4 T4.D
> **Effort**: S
> **Deps**: T2.F (rollup tool exists)
> **Files touched**:
> - `tools/modelinv-rollup.sh` (extend with `--per-skill-daily-quota` flag + alert)
> - `.loa.config.yaml.example` (add `advisor_strategy.daily_token_budget_default` field)
> - `tests/integration/per-skill-quota-alert.bats` (new)

**Mechanical AC**:

1. Rollup tool computes per-skill daily token spend; compares to `daily_token_budget_default` (operator-configurable in `.loa.config.yaml`).
2. If any skill exceeds quota, emits alert (stderr + audit-log entry).
3. Test: synthetic data exceeding quota triggers alert; under quota does not.

#### T4.E — Per-stratum FAIL veto codified in rollout-policy doc

> **Satisfies**: SDD §20.2 step 2 (per-stratum FAIL veto), §13.4 T4.E
> **Effort**: XS (doc-only)
> **Deps**: T4.A
> **Files touched**:
> - `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md` (this is a sub-AC of T4.A; called out separately for traceability)

**Mechanical AC**:

1. rollout-policy.md has a dedicated "Per-stratum FAIL veto" section.
2. Section states: "If ANY stratum FAILs at executor tier (per SC-1..SC-3), decision (a) 'default-on' is unavailable regardless of aggregate. Operator can opt into (b) per-stratum."
3. Section cites SDD §20.2 + benchmark-report.md.

#### T4.F — `.loa.config.yaml.example` updated

> **Satisfies**: PRD §10 cycle-level AC, SDD §13.4 T4.C (re-numbered to T4.F in this plan)
> **Effort**: XS
> **Deps**: T4.A (decision known)
> **Files touched**:
> - `.loa.config.yaml.example` (extend with `advisor_strategy:` section)

**Mechanical AC**:

1. New section added per PRD §5 FR-1 schema.
2. Defaults reflect decision-fork outcome (e.g., `enabled: false` if (b) or (c)).
3. Comments explain each field (`tier_resolution`, `defaults`, `tier_aliases`, `per_skill_overrides`, `audited_review_skills`, `benchmark.max_cost_usd`, `daily_token_budget_default`).

#### T4.G — Migration guide

> **Satisfies**: SDD §13.4 T4.D
> **Effort**: S
> **Deps**: T4.A, T4.F
> **Files touched**:
> - `grimoires/loa/runbooks/advisor-strategy-migration.md` (new)

**Mechanical AC**:

1. Guide has sections: "Pre-migration checklist", "How to enable advisor_strategy", "Per-stratum operator decisions", "How to roll back", "Monitoring after rollout (30-day watch)", "Troubleshooting".
2. Cites rollout-policy.md decision-fork outcome.
3. Includes operator commands for enabling, rolling back, querying MODELINV rollup.

#### T4.H — Auto-memory + known-failures updates

> **Satisfies**: PRD §10 cycle-level AC, SDD §13.4 T4.E + T4.F
> **Effort**: S
> **Deps**: Sprint 3 benchmark-report.md exists
> **Files touched**:
> - `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/feedback_advisor_benchmark.md` (extend with cycle-108 datapoints)
> - `grimoires/loa/known-failures.md` (append KF-NNN entries for any failure classes observed during benchmark)

**Mechanical AC**:

1. `feedback_advisor_benchmark.md` updated to include cycle-108 benchmark data (replacing or supplementing spiral-harness-only data).
2. Any new failure class observed during Sprint 3 replays gets a KF-NNN entry per CLAUDE.md context-intake discipline.
3. known-failures.md remains append-only.

### 4.4 Sprint 4 decision-fork (encoded in plan; outcome resolved by Sprint 3 data)

The decision is mechanical:

```
IF (every stratum is PASS) AND (zero FAIL strata):
    OUTCOME = (a) default-on-for-passing-strata
ELIF (at least one PASS stratum) AND (at least one FAIL or INCONCLUSIVE or UNTESTABLE):
    OUTCOME = (b) opt-in-only
ELSE:  # all FAIL or majority INCONCLUSIVE/UNTESTABLE
    OUTCOME = (c) shelve
```

T4.A captures the outcome; T4.F encodes it in `.loa.config.yaml.example` defaults; T4.G documents the operator pathway.

**Per-stratum FAIL veto (SDD §20.2)**: even if aggregate passes, ANY stratum FAILing blocks (a). This is encoded in the IF clause above.

### 4.5 Sprint 4 risks

| ID | Risk | Mitigation |
|----|------|------------|
| SR4-1 | Decision-fork outcome politically contested | Mechanical derivation from data; operator approval recorded but the rule is the rule |
| SR4-2 | Migration guide misses an operator step | Operator reviews + signs off in PR description |
| SR4-3 | 30-day watch hook flaky in production | Hook is idempotent + read-only on detection (auto-revert PR is just a PR, operator still approves) |

### 4.6 Sprint 4 review + audit gates

- `/review-sprint cycle-108-sprint-4` + `/audit-sprint cycle-108-sprint-4`; APPROVED required.
- Cycle-level acceptance (PRD §10): all checkboxes flipped; post-PR Bridgebuilder loop closed; `/run-bridge` excellence loop ran post-merge.

---

## 5. Cross-sprint dependencies

```
Sprint 1 (substrate) ──→ Sprint 2 (measurement) ──→ Sprint 3 (benchmark) ──→ Sprint 4 (rollout)
       │                       │                          │                       │
       │  T1.A atomic          │  T2.J extends            │  T3.A.OP operator     │  T4.A reads
       │  T1.F envelope v1.2   │   T1.F emitter           │   tag signing         │   benchmark-report.md
       │  T1.G golden-pins     │  T2.A harness needs      │  T3.B reads baselines │  T4.B/C extend
       │   signed by operator  │   T1.E hooks             │   from T3.A           │   post-merge
       │                       │  T2.D needs T2.L+T2.J    │  T3.D needs T2.A      │
```

Strict ordering: Sprint N+1 cannot start `/implement` until Sprint N's `/audit-sprint` shows APPROVED.

---

## 6. Risk register (cycle-level — mirrors PRD §8 + SDD §14)

PRD R-1..R-11 inherited. SDD SR-1..SR-7 inherited. Sprint-specific risks captured in §1.5, §2.5, §3.4, §4.5.

Key cycle-level risks to track in NOTES.md as we proceed:

- **R-9** (benchmark cost burn): T2.D cost cap; tracked across replays
- **R-10** (Opus voice degradation recurs): voice-drop semantics in cheval handle it; track recurrence in known-failures.md
- **R-11** (recorded-replay leak): T2.C two-mode separation; report-format gate

---

## 7. Success metrics (cycle-level — mirrors PRD §3 SC table)

Cycle is complete + successful when:

| ID | Metric | Target | Source |
|----|--------|--------|--------|
| SC-1 | Audit-sprint pass rate at executor tier vs advisor baseline | ≥95% relative | benchmark-report.md |
| SC-2 | Review-sprint findings density delta | ≤ +20% relative | benchmark-report.md |
| SC-3 | BB iteration count to plateau | ≤ +1 avg | benchmark-report.md |
| SC-4 | Cost per sprint reduction (advisor still on review/audit) | ≥40% | benchmark-report.md per-stratum |
| SC-5 | Wall-clock per sprint | ≤ +30% slower | benchmark-report.md |
| SC-6 | Stratification coverage | ≥4 sprint kinds × ≥3 replays = ≥12 runs | replay-manifests/ |

Plus **cycle-level acceptance** (PRD §10): all 12 checkboxes flipped.

---

## 8. Quality-gate inheritance per CLAUDE.md

Every sprint MUST go through:

1. `/implement sprint-N` — writes code per task ACs (NEVER write code outside /implement)
2. `/review-sprint sprint-N` — validates against acceptance criteria (engineer feedback at `grimoires/loa/a2a/engineer-sprint-feedback.md`)
3. `/audit-sprint sprint-N` — security audit (auditor feedback at `grimoires/loa/a2a/auditor-sprint-feedback.md`)

Cycle-level:
- `/flatline-review` on sprint-plan (Phase 3b — next)
- `/run sprint-plan` orchestrates Sprint 1 → 4 (Phase 4)
- `/run-bridge` post-merge iterative Bridgebuilder excellence loop (Phase 5)

NEVER rules from CLAUDE.md applied:
- NEVER write code outside /implement
- NEVER skip /review-sprint or /audit-sprint
- NEVER skip from sprint plan to implementation without /run sprint-plan
- ALWAYS use /run sprint-plan for autonomous execution

---

## Appendix A: Beads-ingestible task index

| Task ID | Title | Sprint | Effort | Deps |
|---------|-------|--------|--------|------|
| T1.A | Atomic skill-role migration + schema enum seed + CODEOWNERS | 1 | L | — |
| T1.B | cycle-108-schema-guard.yml CI workflow | 1 | M | T1.A |
| T1.C | audited_review_skills enforcement at loader §3.3 step 4 | 1 | M | T1.A |
| T1.D | Validator heuristic linter + diff-aware role-change rule | 1 | M | T1.A |
| T1.E | Symlink scan + FS-snapshot-diff harness hooks (stubs) | 1 | S | — |
| T1.F | invocation_chain envelope field + writer_version SoT | 1 | M | T1.C |
| T1.G | cycle108-update-golden-pins.sh + trace-comparison test | 1 | M | T1.F |
| T1.H | cheval --role/--skill/--sprint-kind flags | 1 | M | T1.C, T1.F |
| T1.I | Resolver: advisor_strategy.py + bash twin | 1 | M | T1.C |
| T1.J | tier_resolution mode + in-flight kill-switch | 1 | S | T1.I |
| T1.K | Migration: populate role for 35+ SKILL.md (multi-role review) | 1 | M | T1.A |
| T1.L | Documentation: advisor-strategy-rollback.md | 1 | S | T1.J, T1.G |
| T2.A | Benchmark harness skeleton | 2 | L | Sprint 1 done |
| T2.B | Variance protocol + classifier + memory budget | 2 | M | T2.A |
| T2.C | Replay-semantics separation | 2 | S | T2.A |
| T2.D | Cost-cap pre-estimate | 2 | S | T2.J, T2.L (=T2.J historical-medians) |
| T2.E | Chain-exhaustion classifier | 2 | S | T2.A |
| T2.F | Cost rollup: modelinv-rollup.sh | 2 | M | T1.F |
| T2.G | Hash-chain fail-closed integrity check | 2 | S | T2.F |
| T2.H | Strip-attack detection on MODELINV v1.2 cutoff | 2 | S | T2.F, T1.F |
| T2.I | Stratifier: multi-feature scored classifier | 2 | M | — |
| T2.J | Envelope-captured pricing + selection algo + historical-medians | 2 | M | T1.F, T2.F |
| T2.K | Replay-marker + rollup default-exclude | 2 | XS | T1.F, T2.F |
| T2.L | Network-restriction env enforcement | 2 | S | T2.A |
| T2.M | MODELINV coverage audit | 2 | S | T2.F |
| T3.A | compute-baselines.py + sign + cross-cycle chain | 3 | M | Sprint 2 done |
| T3.A.OP | OPERATOR: sign cycle-108-baselines-pin-<sha> tag | 3 | XS | T3.A |
| T3.B | Harness acceptance gate: refuse-on-tamper | 3 | XS | T3.A.OP |
| T3.C | Select replay sprints (operator approves) | 3 | S | T2.J, T2.I |
| T3.D | Execute replays (≥36) | 3 | L | T3.B, T3.C |
| T3.E | Stats + benchmark-report.md | 3 | M | T3.D |
| T3.F | Operator approval recorded | 3 | XS | T3.E |
| T4.A | rollout-policy.md with explicit decision-fork | 4 | M | Sprint 3 done |
| T4.B | 30-day post-rollout watch hook | 4 | S | T4.A |
| T4.C | Post-merge admin-bypass scan extension | 4 | S | T1.B |
| T4.D | Per-skill daily token quota + alert | 4 | S | T2.F |
| T4.E | Per-stratum FAIL veto codified | 4 | XS | T4.A |
| T4.F | .loa.config.yaml.example updated | 4 | XS | T4.A |
| T4.G | Migration guide | 4 | S | T4.A, T4.F |
| T4.H | Auto-memory + known-failures updates | 4 | S | T3.E |

---

## Appendix B: Beads YAML-frontmatter blocks (sample for `br create` ingestion)

```yaml
# Sample for T1.A — others follow same pattern
---
id: cycle-108-T1.A
title: "T1.A: Atomic skill-role migration + schema enum seed + CODEOWNERS expansion"
type: task
priority: 0  # P0 — sprint blocker
sprint: cycle-108-sprint-1
external_ref: cycle-108-T1.A
labels:
  - cycle:108
  - sprint:1
  - effort:L
  - zone:system
  - red-team-amendment:ATK-A1
  - flatline-amendment:IMP-010
satisfies:
  - "SDD §20.1 (ATK-A1 closure)"
  - "SDD §21.2 (IMP-010 atomic seeding)"
  - "SDD §13.1 T1.J (CODEOWNERS)"
files_touched:
  - ".claude/skills/*/SKILL.md (35+ files)"
  - ".claude/data/schemas/advisor-strategy.schema.json (new)"
  - ".claude/scripts/migrate-skill-roles.sh (new)"
  - "tools/seed-audited-review-skills.py (new)"
  - ".github/CODEOWNERS (extend)"
acceptance_criteria:
  - "Single atomic commit shows all 3 file classes modified"
  - "tools/migrate-skill-roles.sh --dry-run produces migration-plan.md"
  - "audited_review_skills enum contains the SDD §20.1 explicit allowlist"
  - "CODEOWNERS contains the 4-line block from §20.1"
  - "validate-skill-capabilities.sh green against migrated files"
dependencies: []
---
```

Each task in §1.3, §2.3, §3.3, §4.3 has equivalent YAML — generated at sprint-plan parse time by helper scripts (`.claude/scripts/beads/create-sprint-task.sh`).

---

## Appendix C: Goal traceability (PRD G-1..G-4 → tasks)

| Goal | Description | Contributing tasks |
|------|-------------|--------------------|
| **G-1** | Validate or refute advisor-strategy hypothesis empirically | T2.A, T2.B, T2.C, T2.D, T2.E, T2.I, T3.A, T3.B, T3.C, T3.D, T3.E, T3.F |
| **G-2** | Ship operator-controlled role→tier routing | T1.A, T1.B, T1.C, T1.D, T1.F, T1.H, T1.I, T1.J, T1.K, T1.L, T4.F, T4.G |
| **G-3** | Make MODELINV cost data actionable | T1.F, T2.F, T2.G, T2.H, T2.J, T2.K, T2.M, T4.D |
| **G-4** | Catalogue failure modes by sprint kind | T2.I, T3.E, T4.A, T4.E, T4.H (known-failures.md updates) |

**E2E validation task**: T3.E (`benchmark-report.md`) is the load-bearing E2E validator — it produces the data that drives G-1 directly and G-2/G-3/G-4 indirectly via the rollout decision in T4.A.

No goal lacks contributing tasks. No warning emitted.

---

## Appendix D: Sources

| Section | Source |
|---------|--------|
| Sprint 1–4 task decomposition | PRD §7, SDD §13 (§13.1–13.4) |
| Sprint 1 amendments | SDD §20.1, §20.5, §20.6, §20.7, §20.8 (Red Team); §21.1, §21.2, §21.3, §21.4 (Flatline) |
| Sprint 2 amendments | SDD §20.4, §20.9, §20.10 (Red Team); §21.5 (Flatline memory budget) |
| Sprint 3 amendments | SDD §20.2, §20.3 (Red Team) |
| Sprint 4 amendments | SDD §20.2, §20.7, §20.10 (Red Team) |
| Quality-gate inheritance | `.claude/loa/CLAUDE.loa.md` (NEVER/ALWAYS rules) |
| Beads workflow | `.claude/protocols/beads-integration.md`; CLAUDE.md task-tracking hierarchy |
| Cycle-level acceptance | PRD §10 |

---

> **Next gate**: `/flatline-review` on this sprint-plan (Phase 3b). If Flatline produces a re-emission of IMP-008's content (per SDD §21.6 gap), it gets integrated as sprint-plan v1.1. Then `/run sprint-plan` orchestrates Sprint 1 → 4 autonomously.
