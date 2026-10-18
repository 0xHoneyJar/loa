# Sprint 259 — Task 2.0 candidate survey (lead, 2026-10-15T04:10Z)

Scope: Loa history since 2026-08-01 (`git log --since=2026-08-01 --name-only`), commits confined to `tools/`, `evals/harness/`, `evals/graders/`, `evals/fixtures/`, `tests/unit/`, `evals/tests/` (the roots a build fixture may contain: no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/`, AC-2.9), plus the open beads at rc.5 whose code lives under `evals/` or `tools/`.

## Fix commits with a test (bug-fix candidates)

| Filter | Count |
|---|---|
| commits since 2026-08-01 touching `tools/`, `evals/`, `tests/` at all | 186 |
| confined to the allowed roots, ≤ 6 files, subject `fix`/`bug`, touching a test file | 1 |
| confined to the allowed roots, > 6 files, subject `fix`/`bug`, touching a test file | 0 |

The one candidate is `b6802e4f` (2026-10-14, Sprint 255 audit round r255-2: `execute-agent.sh`, `run-arms.sh`, `seed-corpus-from-record.sh`, `arm-toggles.bats`, `floor-snapshot.bats`) — five files, several unrelated changes, tests that need most of `evals/` to run. Not a clean "one fix, one test" shape. Every other fix since August is a multi-file sprint round whose non-test files sit under `.claude/`.

## Refactor commits with unchanged tests (refactor candidates)

Zero commits since 2026-08-01 with subject `refactor|chore|style|perf`, ≥ 2 source files under the allowed roots and no test change.

## Open beads at rc.5 under `evals/` or `tools/` (feature-build candidates)

- `bd-j4lwr` — `run-arms.sh --max-usd` / `--screen`: implemented in Sprint 258 (base `run-arms.sh` at `252501b4`, reference = the Sprint 258 diff). Its fixture needs the review-prs corpus (`SHA256SUMS` verification before each trial), the stub executor and the suite files: likely too large for a self-contained fixture; E decides by `du -sh`.
- `bd-8o5rx` — generated paths out of `fix_regions` in `seed-corpus-from-record.sh`: F implements it in the main tree (Task 2.8); E may author it as a feature task with a tiny corpus fixture and its own reference patch.
- `bd-yzzb9` — excluded (code under `.claude/adapters/`).
- No other open bead names `evals/` or `tools/`.

## Decision (DEC-0500)

The PRD's risk row applies: synthetic fixtures in the cycle-124 style are the source for the bug-fix, refactor and most feature-build tasks (planted defect classes, structural smells, missing features; authored 2026-10-15, `post_cutoff: true`, never a clone). `seed-bugfix-tasks.sh` and `seed-refactor-tasks.sh` ship as tested tools and the survey is rerun when a clean candidate appears. Review-catch tasks come from the frozen `review-prs` corpus (two planted, two record). Fixtures live inside `tasks/<id>/fixture/` so `freeze.sh` covers them (DEC-0499).

## Dispatch

- D (`../loa-wt-s2d`): Tasks 2.1, 2.2, 2.3 — README/validator, the seeders, `bugfix-01…04`, `refactor-01…04`.
- E (`../loa-wt-s2e`): Tasks 2.4, 2.5 — `feature-01…04`, `review-01…04`.
- F (`../loa-wt-s2f`): Tasks 2.6, 2.8 — `ablation-grade.sh` + bats + `pipeline-run.bats` extension; bd-8o5rx manifests, `SHA256SUMS`, batch-1 regrade.
- Lead: 2.0 (this file), 2.7 (fairness reviews after D/E land), 2.9 (self-check 16/16 inside the image, freeze, CHANGELOG, REPO-MAP, checksums).
