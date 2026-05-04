# cycle-099-model-registry — Session Resumption Brief

**Last updated**: 2026-05-04 (Sprint 1 ~60% complete: 1A + 1B + 1C SHIPPED; **next: 1D cross-runtime corpus OR 1E hardening primitives**)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read first when resuming cycle-099 work.

## 🚨 TL;DR — Today shipped 4 cycle-099 PRs; Sprint 1 is ~60% done

**Today's wins on main (4 PRs):**
- chore #721 (`9ef33055`) — cycle-099 ledger activation + planning artifacts (mirrors cycle-098 #679 pattern)
- Sprint-1A #722 (`78c59568`) — bridgebuilder codegen foundation (T1.1 + T1.2)
- Sprint-1B #723 (`7140ff1c`) — adapter migrations + drift gate + lockfile (T1.3 + T1.4 + T1.5 + T1.6 + T1.8 + T1.10 partial)
- Sprint-1C #724 (`8b008b9b`) — codegen reproducibility matrix CI + toolchain runbook (T1.7 + T1.9) + latent-drift fix

**Cumulative**: ~95 cycle-099 bats tests on main, 0 regressions. Drift-gate CI active.

### Operator decision needed at session start

> Sprint 1 has 5 unmerged tasks (T1.11/T1.12 cross-runtime corpus; T1.10 remaining bats; T1.13/T1.14/T1.15 cross-cutting hardening). Choose Path A or Path B.

**Path A (Sprint-1D — cross-runtime corpus)**: T1.11 + T1.12. Highest-value remaining piece per SDD §7.6 (strongest determinism guarantee, unblocks Sprint 2's runtime overlay). Estimated ~4-5 hours. Pre-written brief in §"Brief A — Sprint 1D".

**Path B (Sprint-1E — hardening primitives)**: T1.13 (log-redactor) + T1.14 (loa migrate-model-config CLI) + T1.15 (centralized endpoint validator). Three independent primitives that Sprint 2's loader changes will consume. Estimated ~4-5 hours total; can ship as 2 sub-PRs (1E.1: log-redactor + migrate CLI; 1E.2: endpoint validator). Pre-written brief in §"Brief B — Sprint 1E".

Either path is non-blocking — both feed Sprint 2 readiness equally well from the technical side. Path A gives stronger correctness signal (cross-runtime parity test); Path B reduces operator-config blast radius (security primitives).

---

## What's on main (cycle-099 inventory)

### Sprint-1A — codegen foundation (`78c59568`)

| Artifact | Path | Notes |
|---|---|---|
| Bun-compatible codegen | `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` | 549 LOC; reads model-config.yaml via yq subprocess; emits TS |
| Generated truncation | `.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts` | TOKEN_BUDGETS map |
| Generated config registry | `.claude/skills/bridgebuilder-review/resources/config.generated.ts` | MODEL_REGISTRY map |
| Build pipeline | `.claude/skills/bridgebuilder-review/package.json::scripts.build` | `npm run build` invokes codegen before tsc |
| Drift-check entrypoint | `npm run gen-bb-registry:check` (exits 3 on stale) | Consumed by sprint-1B drift-gate |
| 33 bats tests | `tests/unit/gen-bb-registry-codegen.bats` | T1-T12 categories incl. prototype-pollution guard |
| tsx pinned | BB skill `package.json` devDeps | Closes supply-chain via `node_modules/.bin/tsx` |

### Sprint-1B — adapter migrations + drift gate (`7140ff1c`)

| Artifact | Path | Notes |
|---|---|---|
| Resolver lib | `.claude/scripts/lib/model-resolver.sh` | `resolve_alias` / `resolve_provider_id`; override gated behind `LOA_MODEL_RESOLVER_TEST_MODE=1` |
| RT model-adapter migration | `.claude/scripts/red-team-model-adapter.sh` | Sources resolver; prefer-resolver-fallback-to-local |
| RT cvds migration | `.claude/scripts/red-team-code-vs-design.sh` | `--model "$_opus_model_id"` (resolved via resolve_alias) |
| Default adapter migration | `.claude/scripts/model-adapter.sh` | Same pattern; cycle-082 keys preserved |
| Lockfile | `.claude/defaults/model-config.yaml.checksum` | SHA256 hex; verified by drift-gate |
| Drift-gate workflow | `.github/workflows/model-registry-drift.yml` | 3 jobs: lockfile-checksum, bash-codegen-check, ts-codegen-check |
| 6 lockfile tests | `tests/integration/lockfile-checksum.bats` | L1-L5 |
| 25 sentinel tests | `tests/integration/legacy-adapter-still-works.bats` | S1-S6 covering all migrations |

### Sprint-1C — matrix CI + runbook (`8b008b9b`)

| Artifact | Path | Notes |
|---|---|---|
| Matrix CI | `.github/workflows/model-registry-drift.yml::ts-codegen-check` | `[ubuntu-latest, macos-latest]` with platform-aware SHA256-pinned yq |
| Toolchain runbook | `grimoires/loa/runbooks/codegen-toolchain.md` | 168 lines; per-platform install steps; pinned versions |
| Verification script | `tools/check-codegen-toolchain.sh` | `_version_ge` via `sort -V`; CI invokes it on matrix runners |
| Bash codegen drift fix | `.claude/scripts/generated-model-maps.sh` | +5 lines for `claude-sonnet-4-5-20250929` (sprint-1A latent regression) |

---

## Brief A — Sprint 1D (cross-runtime golden corpus, T1.11 + T1.12)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief A". Then ship Sprint 1D.

Sprint-1D scope (T1.11 + T1.12 per cycle-099 sprint.md §1):
  - 12 golden fixture files at tests/fixtures/model-resolution/ covering
    SDD §7.6.3 scenarios: happy-path tier-tag, explicit-pin, missing-tier-
    fail-closed, legacy-shape-deprecation, override-conflict, extra-only-
    model, empty-config, unicode-operator-id, prefer-pro-overlay, extra-vs-
    override-collision, tiny-tier-anthropic, degraded-mode-readonly
  - 3 cross-runtime runners that consume the fixture corpus identically:
      tests/python/golden_resolution.py
      tests/bash/golden_resolution.bats
      tests/typescript/golden_resolution.test.ts
  - 4 CI workflows:
      .github/workflows/python-runner.yml
      .github/workflows/bash-runner.yml
      .github/workflows/bun-runner.yml
      .github/workflows/cross-runtime-diff.yml
    The cross-runtime-diff job downloads all three runners' artifacts and
    asserts byte-equality. Mismatch fails the build (SDD §7.6.2).

Caveat — the FR-3.9 6-stage resolver is sprint-2 scope. The 1D runners
should test what CURRENTLY exists (the codegen-derived MODEL_PROVIDERS /
MODEL_IDS lookup and the new generated-model-maps.sh / config.generated.ts
output) — i.e., the SUBSET of FR-3.9 behavior that's already implemented.
Sprint 2 will extend the corpus + runners as the full resolver lands.

Continue Path: cut feat/cycle-099-sprint-1d from main (8b008b9b+).

Tooling already in place from sprint-1C:
  - bats v1.10+ (existing repo dependency)
  - Python 3.13 (cheval venv per .claude/scripts/lib/cheval-venv/)
  - tsx via BB skill node_modules (npx --no-install tsx works after npm ci)
  - pyyaml (cheval requirement) — for the python runner
  - yq pinned v4.52.4 with darwin-arm64 SHA256

Quality-gate chain (sprint-1A/1B/1C precedent):
  1. Implement test-first: write golden_resolution.bats first as the canonical
     reference, then port to python and TS verifying byte-equal output
  2. Subagent review (general-purpose) + audit (paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>
  4. Admin-squash after kaironic plateau (typical: 2 iterations for code PRs)

Slice if needed:
  - 1D.a: 12 fixtures + bats runner + bash-runner.yml (smallest, fastest gate)
  - 1D.b: python runner + python-runner.yml
  - 1D.c: TS runner + bun-runner.yml + cross-runtime-diff.yml

Refs: SDD §7.6.3 (fixture corpus); Flatline SDD pass #1 SKP-002 CRITICAL 890
(this is the resolution).
```

---

## Brief B — Sprint 1E (hardening primitives, T1.13 + T1.14 + T1.15)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief B". Then ship Sprint 1E.

Sprint-1E scope (T1.13 + T1.14 + T1.15 per cycle-099 sprint.md §1):

  T1.13 — Log-redactor module (SDD §5.6, IMP-002 HIGH_CONSENSUS 860):
    .claude/scripts/lib/log-redactor.py — Python canonical
    .claude/scripts/lib/log-redactor.sh — bash twin
    Function: redact(text) — masks URL userinfo + 6 query-string secret
    patterns (key=, token=, secret=, password=, api_key=, auth=).
    Cross-runtime parity test at tests/integration/log-redactor.bats.

  T1.14 — Operator migration CLI (SDD §3.1.1.1):
    .claude/scripts/loa-migrate-model-config.py — operator-explicit v1→v2
    Pure migration logic in .claude/scripts/lib/model-config-migrate.py
    Preserves YAML structure via ruamel.yaml; reports field-level changes;
    exits 0 success / 78 validation failure; idempotent on v2 input.

  T1.15 — Centralized endpoint validator (SDD §1.9.1, SKP-006 CRITICAL 870):
    .claude/scripts/lib/endpoint-validator.py — Python canonical
    .claude/scripts/lib/endpoint-validator.sh — bash wrapper (Python via subprocess)
    .claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.ts — generated TS
    Validators: scheme allowlist, port allowlist, host allowlist, DNS
    rebinding defense (resolve + lock IP), URL canonicalization
    Cross-runtime parity test at tests/integration/endpoint-validator-cross-runtime.bats
    PR-level CI guard: model-registry-drift.yml asserts urllib.parse imports
    only in endpoint-validator.py, no direct curl/wget outside endpoint-validator.sh,
    no direct fetch(/http.request outside endpoint-validator.ts.

Slice into 2 sub-PRs (each ~2 hours):
  - 1E.a: T1.13 (log-redactor) + T1.14 (migration CLI) — both Python+bash with parity
  - 1E.b: T1.15 (endpoint validator) — three-language with TS codegen

Continue Path: cut feat/cycle-099-sprint-1e from main (8b008b9b+).

Tooling already in place:
  - cheval venv with pyyaml + idna (latter ships with Python 3.11+)
  - For T1.14 ruamel.yaml: pip install in cheval venv on first sub-PR
  - bats v1.10+, jq, yq pinned (cycle-099 sprint-1C runbook)

Quality-gate chain (same as 1A/1B/1C):
  1. Implement test-first
  2. Subagent review + audit in parallel
  3. Bridgebuilder kaironic INLINE (~2 iters for code PRs)
  4. Admin-squash after plateau

Refs: SDD §5.6 (log-redactor) + §3.1.1.1 (migration CLI) + §1.9.1 (endpoint
validator); Flatline SDD pass #1 IMP-002 + pass #2 SKP-001 + pass #2 SKP-006.
```

---

## Open backlog at session-end (2026-05-04)

### Sprint 1 remaining

- **T1.10 unfinished bats**: bridgebuilder-dist-drift.bats + perf-bench.bats. Sprint-1A landed gen-bb-registry-codegen.bats; sprint-1B landed legacy-adapter-still-works.bats. Two more deliverables per SDD §7.2 still owed. **Defer to sprint-1D bundle** (small, can ride alongside the cross-runtime work).

### Sprint 1 deferred to sprint-1D follow-ups

- **macos arm64 hardcoding** (BB iter-1 F3 + iter-2 F5): pin to `macos-14` instead of `macos-latest` for deterministic arch.
- **yq upstream checksums URL** (BB iter-2 F2): cross-reference https://github.com/mikefarah/yq/releases/download/v4.52.4/checksums in the workflow comment for audit ergonomics.
- **Composite action for yq install** (BB iter-2 F8): three workflows currently duplicate the install step. Repository-local action could DRY this up.
- **`local alias=` shadows builtin** (sprint-1B review H1): cosmetic; rename to `_alias`.
- **Workflow_dispatch trigger for drift gate** (sprint-1C review process): catches "drift introduced before the gate landed" race.

### Sprint 2+ scope (downstream of Sprint 1 completion)

- Sprint 2 — Config extension (`model_aliases_extra`) + per-skill granularity (`skill_models`) + runtime overlay (`.run/merged-model-aliases.sh`)
- Sprint 3 — Personas + docs migration + DD-1 Option B model-permissions codegen + bridgebuilder dist regen
- Sprint 4 (gated at T4.4) — Legacy adapter sunset

### Beads

UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)) unchanged across all 4 PRs today. `--no-verify` policy active per cycle-099 sprint plan §`--no-verify` Safety Policy. Each PR commit message carries the `[NO-VERIFY-RATIONALE: ...]` audit-trail tag.

---

## Patterns established this session (worth remembering)

1. **Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel** caught real bugs across all three sprints. Paranoid cypherpunk specifically caught: `__proto__` prototype-shadowing (1A), `LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE` ungated arbitrary-bash-source (1B), unverified macOS yq SHA256 (1C). General-purpose specifically caught: silent regression of `claude-sonnet-4-5-20250929` (1A), brittle source-line regex pin (1B), advisory-only version-comparison-script (1C).

2. **Bridgebuilder kaironic 2-iter convergence** held empirically. Each PR plateaued in 2 iterations.

3. **The vacuous-green-via-fixture-syntax-error pattern** (BB iter-1 F1 on PR #723): a security-test fixture with a bash syntax error means the negative assertion passes for the wrong reason (file fails to parse before the attack code runs). **Fix template**: add a positive-control sentinel that proves the payload WOULD fire if the gate were absent.

4. **The drift-gate-cannot-catch-its-own-introducing-PR race** (sprint-1A → 1B → 1C surfacing): SDD R-5 in the wild. Sprint-1C remediated retroactively via gen-adapter-maps regen. Sprint-1D follow-up should add `workflow_dispatch` post-merge gate.

5. **Inline implementation pattern with subagent quality gates** continues to outperform `/run` autopilot for sliced sub-sprints. Sprint 1A/1B/1C/(future)1D/1E all use the inline-then-subagent-review-then-BB-kaironic-then-admin-squash flow.

6. **Conversation-budget discipline**: today's session shipped 4 PRs (~3-5 hours each in normal time; compressed to 1 long session). Future sessions should slice sprints further (1A/1B/1C-style) before starting, not mid-session.
