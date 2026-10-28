# Sprint 282 prep (Task 2.0) — external artefacts, anchors, toolchain

**Written:** 2026-10-28 by the lead, before Sprint 281 `COMPLETED` (the worktree creation and the final re-brief happen after it; this file records what does not depend on the Sprint 1 outcome).

## External, unversioned artefacts the plan relies on (sha256)

| sha256 | Path | Used by |
|---|---|---|
| 0b464ff8f263f78612e0069356a0b13252d61f6960bcdbd224941e63563ad0c0 | `~/.cache/loa/cycle-135/ship/ship-1-merge.sh` | Ship S-3 |
| 56ba02434b757f6e07f2e021b3c56223faf292b9b9bf11cb0d3fd04bef0ffe4a | `~/.cache/loa/cycle-135/ship/ship-2-record.sh` | Ship S-4 |
| ca118babc5a7674a53baa5d4adeb4936c4e9aba68a93cf72517f1fe180569a4e | `~/.cache/loa/cycle-135/ship/ship-3-archive.sh` | Ship S-8 |
| 45645a45ac2d2044196eae585c2f5a84c535d050b4a760988b6ed3f348f044f9 | `~/.cache/loa/cycle-135/ship/ship-3b-archive-pr.sh` | Ship S-8 |
| 56ddd39f6c27624f48dd296e391fff13cda14d2a1b339c7cb33026a5cad8d84d | `~/.cache/loa/cycle-135/ship/ship-3c-archive-merge.sh` | Ship S-8 |
| cb4c5a923708820ded9658a205ce859d33034d34521ad53d0494e21e869414d1 | `~/.cache/loa/cycle-135/ship/ship-4-close.sh` | Ship S-8 |
| d764c62ccbc28c1f3f37e444f68c3b6f4bdfcbbf0c4393cb8ebcdbdb84ffcdf1 | `~/.cache/loa/eso-loop/rebaseline.sh` (copy: `a2a/sprint-281/evidence/rebaseline.sh`) | G-3 re-baseline |

The cycle-137 copies of the ship scripts (cycle, branch, PR, `--prev origin/record/cycle-136-bridgebuilder-followups` substituted) are written at Ship S-1 and copied to `a2a/sprint-282/ship/` with their own sha256 in `e2e.md`.

## `profile-lib.sh` sourcers (Task 2.4 must keep their suites green)

| Sourcer | Covering bats |
|---|---|
| `.claude/hooks/loa-kf-surface.sh` | `tests/unit/kf-surface.bats`, `perf-spawn-budget.bats` (a) |
| `.claude/hooks/quality/karpathy-surgical-diff-check.sh` | `tests/unit/karpathy*.bats`, the pass-19 parity harness |
| `.claude/hooks/session-start/loa-decisions-surface.sh` | `tests/unit/loa-decisions-surface.bats` |
| `.claude/hooks/session-start/loa-l6-surface-handoffs.sh` | `tests/unit/*l6*surface*.bats` |
| `.claude/hooks/session-start/loa-l7-surface-soul.sh` | `tests/unit/*l7*surface*.bats` |
| `.claude/scripts/danger-level-enforcer.sh` | `tests/unit/danger-level*.bats` |
| `.claude/scripts/guardrails-orchestrator.sh` | `tests/unit/guardrails*.bats` |
| `.claude/scripts/loa-status.sh` | `tests/unit/loa-status*.bats` |
| the lib's own CLI (`profile-lib.sh knob …`, called from skill preludes) | `tests/unit/profile-lib.bats`, `tests/unit/profile-floor.bats` |

## awk interpreters present on the ship host (Task 2.1 portability check)

| Interpreter | Present | Version |
|---|---|---|
| `mawk` (= `/usr/bin/awk`) | yes | mawk 1.3.4 20250131 |
| `busybox awk` | `/usr/bin/busybox` present; the `awk` applet is exercised by the pass-4/pass-6 reviews — Task 2.1 confirms `busybox awk` runs and names it | — |
| `gawk` | absent (skipped by name) | — |

## Structural anchors verified on e5df3b589 (briefs name functions, not lines)

| Brief | Anchor | Where today |
|---|---|---|
| A | `fieldval(line, label, reA, reB, v)` | `.claude/hooks/loa-kf-surface.sh` ≈ 102; `.claude/scripts/grimoire-index.sh` ≈ 95 (inside `emit_kf`) |
| A | `emit_decisions()`; write-mode `bad`/`total` jq | `grimoire-index.sh` ≈ 216–235; ≈ 322–330 |
| B | `_anthropic_ceiling_json()` (six `yq eval -r` reads) | `.claude/scripts/loa-status.sh` ≈ 848–895 |
| B | `_agy_opt_in_node` (subshell, fd 9), `agy_opted_in`, `agy_gate_warn_once` | `.claude/scripts/lib/agy-gate-lib.sh` ≈ 122–139, 203–206, 300–325 |
| B | `_loa_pl_build`, `_loa_pl_live`, `loa_knob` | `.claude/scripts/lib/profile-lib.sh` ≈ 95–165, 212–224, 226–268 |
| C | `corpus_json()` and the three corpus tests; no `setup_file` yet | `tests/unit/block-destructive-bash.bats` ≈ 1540–1600 |
| C | holder/sleep sites | `tests/unit/adversarial-review-companion.bats` 182, 183, 206, 232, 644, 1253, 1310, 1594, 1613, 1624, 1719, 1741, 1749 |
| D | `_an_audit_chain_summary()` (the `verify-chain` loop) | `.claude/scripts/loa-status.sh` ≈ 408–445 |
| D | `audit_verify_chain()` shell wrapper; `case` dispatch; `--help` | `.claude/scripts/audit-envelope.sh` ≈ 768–795, 1150–1152, 1175 |
| D | `_check_trust_store`, `_trust_store_snapshot`, `audit_verify_chain` (protected) | `.claude/adapters/loa_cheval/audit_envelope.py` ≈ 500–520, 414–470, 580 |

## Live facts recorded for the acceptance criteria

- Shape-C lines for the parsed KF labels today: `grep -cE '^(- )?\*\*(Symptom|Recurrence count|Status) [^*]*\*\*:' grimoires/loa/known-failures.md` → **1** (`**Status (original)**: OPEN …` in KF-008, after the plain `**Status**:` line) — hence D-2.2.
- `git check-ignore .run/perf-cache/x` → `.run/` is ignored (verified by the existing `zone-write-guard` cache).
- Python tests under `tests/unit/` run in CI via `python -m pytest` (`.github/workflows/bats-tests.yml:186`); D's `test_audit_verify_chains.py` goes there.
- `tests/unit/audit-envelope*.bats`: one file today (the PRD's "44" was the test count, not the file count — corrected here).

## Briefs

`a2a/sprint-282/briefs/{COMMON,A,B,C,D}.md` — copies of `~/.cache/loa/cycle-137/briefs/`. Re-brief rule: if a Sprint 281 gate fix touches a file on an implementer's allowlist, the brief gains a line naming the fix commit before the worktree is created.
