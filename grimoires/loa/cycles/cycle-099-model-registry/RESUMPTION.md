# cycle-099-model-registry — Session Resumption Brief

**Last updated**: 2026-05-05 (Sprint 1 ~75% complete: 1A + 1B + 1C + 1E.a SHIPPED; **next: 1D cross-runtime corpus OR 1E.b endpoint validator**)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read first when resuming cycle-099 work.

## 🚨 TL;DR — Sprint 1 is ~75% done; 5 cycle-099 PRs on main

**On main (5 PRs):**
- chore #721 (`9ef33055`) — cycle-099 ledger activation + planning artifacts (mirrors cycle-098 #679 pattern)
- Sprint-1A #722 (`78c59568`) — bridgebuilder codegen foundation (T1.1 + T1.2)
- Sprint-1B #723 (`7140ff1c`) — adapter migrations + drift gate + lockfile (T1.3 + T1.4 + T1.5 + T1.6 + T1.8 + T1.10 partial)
- Sprint-1C #724 (`8b008b9b`) — codegen reproducibility matrix CI + toolchain runbook (T1.7 + T1.9) + latent-drift fix
- **Sprint-1E.a #728 (`cd1c2438`)** — log-redactor (T1.13) + migrate-model-config CLI (T1.14)

**Cumulative**: ~169 cycle-099 bats tests on main (95 prior + 74 from 1E.a), 0 regressions. Drift-gate CI active. Strict v2 schema with `additionalProperties:false` at every level.

### Operator decision needed at session start

> Sprint 1 has 3 unmerged task surfaces (T1.11/T1.12 cross-runtime corpus; T1.10 remaining bats — bridgebuilder-dist-drift.bats + perf-bench.bats; T1.15 endpoint validator). Choose Path A or Path B.

**Path A (Sprint-1D — cross-runtime corpus)**: T1.11 + T1.12. Highest-value remaining piece per SDD §7.6 (strongest determinism guarantee, unblocks Sprint 2's runtime overlay). Estimated ~4-5 hours. Pre-written brief in §"Brief A — Sprint 1D".

**Path B (Sprint-1E.b — endpoint validator)**: T1.15 (centralized endpoint validator: scheme/port/host allowlist + DNS rebinding lock; py + bash + TS three-language port). Sprint-1E.a already shipped (T1.13 + T1.14); 1E.b is the remaining 1E primitive. Estimated ~2-3 hours. Pre-written brief in §"Brief B — Sprint 1E.b".

Either path is non-blocking — both feed Sprint 2 readiness equally well from the technical side. Path A gives stronger correctness signal (cross-runtime parity test); Path B reduces operator-config blast radius (the last security primitive).

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

### Sprint-1E.a — hardening primitives (`cd1c2438`)

| Artifact | Path | Notes |
|---|---|---|
| Log-redactor (Python canonical) | `.claude/scripts/lib/log-redactor.py` | Stdlib-only; URL userinfo + 6 query-param secret patterns; case-insensitive name match with case preservation |
| Log-redactor (bash twin) | `.claude/scripts/lib/log-redactor.sh` | POSIX BRE; explicit `[Aa]`-style case classes; sed line-by-line; cross-runtime byte-identical |
| Migrate CLI driver | `.claude/scripts/loa-migrate-model-config.py` | argparse + ruamel.yaml + jsonschema; O_NOFOLLOW + 0o600 output; distinct error codes (MIGRATION-PRODUCED vs CONFIG-V2-INVALID) |
| Migrate lib (pure) | `.claude/scripts/lib/model-config-migrate.py` | `migrate_v1_to_v2()` + `detect_schema_version()`; deepcopy-safe; field-level report list |
| v2 JSON Schema | `.claude/data/schemas/model-config-v2.schema.json` | Strict `additionalProperties:false` at root + providers + modelEntry + agentBinding + permissionsBlock; agentBinding forbids tier-tag in `model:` field |
| 37 log-redactor tests | `tests/integration/log-redactor-cross-runtime.bats` | T1-T12 SDD §5.6.4 corpus + T8.4 caller-contract pin |
| 37 migrate tests | `tests/integration/migrate-model-config.bats` | M1-M18 incl. M13 security (symlink, mode, !!python/object), M14 tier_groups edges, M15 pure-function, M16 distinct error codes, M18 strict-mode |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-tests.yml` | ruamel.yaml + jsonschema pinned; runs both bats + production smoke against `.claude/defaults/model-config.yaml` + cycle-026 perms |

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

## Brief B — Sprint 1E.b (endpoint validator, T1.15)

Sprint-1E.a already SHIPPED (T1.13 + T1.14, PR #728 cd1c2438). T1.15 remains.

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief B". Then ship Sprint 1E.b.

Sprint-1E.b scope (T1.15 per cycle-099 sprint.md §1):

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

  Optionally fold in T1.10 leftover bats (bridgebuilder-dist-drift.bats +
  perf-bench.bats) — small, ride alongside the validator.

Continue Path: cut feat/cycle-099-sprint-1e-b from main (cd1c2438+).

Reference patterns from Sprint-1E.a (#728):
  - .claude/scripts/lib/log-redactor.{py,sh} — Python canonical + bash twin pattern
  - tests/integration/log-redactor-cross-runtime.bats — parity helper `_assert_redacts_to`
  - .claude/scripts/loa-migrate-model-config.py — argparse + O_NOFOLLOW + 0o600 pattern
  - .claude/data/schemas/model-config-v2.schema.json — strict additionalProperties:false
  - .github/workflows/cycle099-sprint-1e-tests.yml — Python deps install pattern
                                                     (ruamel.yaml + jsonschema pinned)

Tooling already in place:
  - .venv has ruamel.yaml==0.18.17 + jsonschema==4.26.0 (sprint-1E.a installed)
  - For T1.15: idna ships with Python 3.11+; no new pip needed for Python
    canonical. TS port may need additional Bun deps (review BB skill package.json).
  - bats v1.10+, jq, yq pinned (cycle-099 sprint-1C runbook)

Quality-gate chain (same as 1A/1B/1C/1E.a):
  1. Implement test-first (bats parity test before code)
  2. Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh
     (typical 2-iter convergence for code PRs)
  4. Admin-squash after plateau

Sprint-1E.a remediation lessons worth carrying forward:
  - Use `<<'EOF'` quoted heredocs + os.environ for path passing in bats tests
    (closes shell-injection-into-Python-source surface; helper `_python_assert`
     in tests/integration/migrate-model-config.bats is the template)
  - `_assert_redacts_to "$input" "$expected"` is the right shape for parity
    tests (catches vacuous-green where one runtime relaxes silently)
  - `additionalProperties: false` at every schema level + enumerate the full
    field surface from production yaml (operator-injected fields go to a
    namespaced `_unknown_v1_fields` instead of passing validation)
  - Mode 0600 + O_NOFOLLOW on operator-output writes (review C-H2 + C-L1)
  - Distinct error codes for "we made it bad" (MIGRATION-PRODUCED-INVALID-V2)
    vs "you gave us bad" (CONFIG-V2-INVALID); /distinguishes operator-side
    config corruption from migrator bugs
  - Smoke-test against production yaml in CI catches schema-vs-reality drift
    (sprint-1E.a discovered compliance_profile null + api_format dict edge
    cases via this gate)

Refs: SDD §1.9.1 (endpoint validator); Flatline SDD pass #2 SKP-006 CRITICAL 870.
```

---

## Open backlog at session-end (2026-05-05)

### Sprint 1 remaining

- **T1.10 unfinished bats**: bridgebuilder-dist-drift.bats + perf-bench.bats. Sprint-1A landed gen-bb-registry-codegen.bats; sprint-1B landed legacy-adapter-still-works.bats. Two more deliverables per SDD §7.2 still owed. **Defer to sprint-1D OR sprint-1E.b bundle** (small, can ride alongside).

### Sprint 1 deferred to follow-ups

- **macos arm64 hardcoding** (BB iter-1 F3 + iter-2 F5 from sprint-1C): pin to `macos-14` instead of `macos-latest` for deterministic arch.
- **yq upstream checksums URL** (BB iter-2 F2 from sprint-1C): cross-reference https://github.com/mikefarah/yq/releases/download/v4.52.4/checksums in the workflow comment for audit ergonomics.
- **Composite action for yq install** (BB iter-2 F8 from sprint-1C): three workflows currently duplicate the install step. Repository-local action could DRY this up.
- **`local alias=` shadows builtin** (sprint-1B review H1): cosmetic; rename to `_alias`.
- **Workflow_dispatch trigger for drift gate** (sprint-1C review process): catches "drift introduced before the gate landed" race.
- **Sprint-1E.a leftovers** (BB iter-2, all LOW or recycled, deferred):
  - F4: T8.2/T8.3 caller-contract docs discoverability — log-redactor module docstring already documents the URL-only scope; consider README/operator-doc snippet
  - F5: M13.3 umask defense-in-depth — Python `os.O_CREAT, mode=0o600` ALREADY enforces; the test pins it via the bash-side `stat`. Could add a parallel test that explicitly inspects Python's `os.stat()` result.
  - F6: pip-install-without-hashes — matches existing repo convention (jcs-conformance.yml, bedrock-contract-smoke.yml); deferred as repo-wide hardening cycle
  - F7: T1.2 mixed `_redact_both` + `_assert_parity` — uniformly migrate remaining sites to `_assert_redacts_to`
  - F8: smoke-test partial-write defense — add a `[ -s /tmp/migrated.yaml ]` size check after the migrate call
  - F12: M11.1 brittleness — replace `grep -E '^[a-z_]+:'` with a parser-based first-key check via ruamel.yaml

### Sprint 2+ scope (downstream of Sprint 1 completion)

- Sprint 2 — Config extension (`model_aliases_extra`) + per-skill granularity (`skill_models`) + runtime overlay (`.run/merged-model-aliases.sh`)
- Sprint 3 — Personas + docs migration + DD-1 Option B model-permissions codegen + bridgebuilder dist regen
- Sprint 4 (gated at T4.4) — Legacy adapter sunset

### Beads

UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)) unchanged across all 5 PRs (#721/#722/#723/#724/#728). `--no-verify` policy active per cycle-099 sprint plan §`--no-verify` Safety Policy. Each PR commit message carries the `[NO-VERIFY-RATIONALE: ...]` audit-trail tag.

---

## Patterns established this session (worth remembering)

1. **Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel** caught real bugs across all four sub-sprints. Paranoid cypherpunk specifically caught: `__proto__` prototype-shadowing (1A), `LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE` ungated arbitrary-bash-source (1B), unverified macOS yq SHA256 (1C), `additionalProperties` schema gap + symlink-clobber on output write (1E.a). General-purpose specifically caught: silent regression of `claude-sonnet-4-5-20250929` (1A), brittle source-line regex pin (1B), advisory-only version-comparison-script (1C), input-dict mutation in "pure" function + tier_groups absent/partial-fill gaps + tautological assertion (1E.a).

2. **Bridgebuilder kaironic 2-iter convergence** held empirically. Each PR plateaued in 2 iterations including 1E.a.

3. **The vacuous-green-via-fixture-syntax-error pattern** (BB iter-1 F1 on PR #723): a security-test fixture with a bash syntax error means the negative assertion passes for the wrong reason (file fails to parse before the attack code runs). **Fix template**: add a positive-control sentinel that proves the payload WOULD fire if the gate were absent.

4. **The drift-gate-cannot-catch-its-own-introducing-PR race** (sprint-1A → 1B → 1C surfacing): SDD R-5 in the wild. Sprint-1C remediated retroactively via gen-adapter-maps regen. Sprint-1D follow-up should add `workflow_dispatch` post-merge gate.

5. **Inline implementation pattern with subagent quality gates** continues to outperform `/run` autopilot for sliced sub-sprints. Sprint 1A/1B/1C/1E.a all used the inline-then-subagent-review-then-BB-kaironic-then-admin-squash flow.

6. **Conversation-budget discipline**: future sessions should slice sprints further before starting. 1E.a was sliced cleanly from 1E.b at session start, so the remaining endpoint validator can ship as a small follow-up rather than getting bundled in mid-session.

7. **Production-yaml smoke-test in CI catches schema-vs-reality drift** (sprint-1E.a): the strict v2 schema initially rejected legitimate cycle-095 production fields (compliance_profile null, api_format dict for Bedrock per-capability mapping). Without the dedicated CI step that runs the migrator against `.claude/defaults/model-config.yaml`, this would have surfaced only when an operator hit it in the field. **Fix template**: every schema-tightening PR must include a smoke-test step that runs against the most-permissive real-world fixture available.

8. **Heredoc shell-injection-into-Python-source surface** (sprint-1E.a BB iter-1 F2): bats tests using `"$PYTHON" - <<EOF` (unquoted) interpolate every `$VAR` into the embedded Python source. If any path contains a quote, `$`, or `\`, the embedded code can break or be injected. **Fix template**: helper function `_python_assert` that exports paths via env vars + uses quoted heredoc `<<'EOF'`, with the embedded Python reading via `os.environ["PATH_VAR"]`. See `tests/integration/migrate-model-config.bats` for the canonical pattern.
