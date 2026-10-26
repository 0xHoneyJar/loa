# ablation-2.0-v3 — the build suite with variance

Suite v3 reseeds the build side of the Loa 2.0 ablation from Loa's own post-merge fix history, so that the bare arm can fail. The cycle-130 suite (v2, `grimoires/loa/evals/ablation-2.0/`) is saturated on its build side: hidden-test pass 1.000 in a0_bare, a4_no_gates and a1_full over 36 runs each (cycle 130), 1.00 for bare Opus 5.5 on the gen-contrast draw and 0.95–1.00 for every model generation (loa-smol `REPORT.md` §1, §3) — the instrument cannot detect build-side value. The suite file is `evals/suites/ablation-2.0-v3.yaml` (suite_version 3; every arm, model, cap and rule is v2's). The review-catch side is not part of v3.

## Layout

```
grimoires/loa/evals/ablation-2.0-v3/
  MANIFEST.sha256        freeze.sh: one "<sha256>  <relpath>" line per file under tasks/
  README.md              this file
  self-check-image.txt   ablation-grade.sh --self-check base|reference per task in loa-ablation:259 (the hard gate's log)
  tasks/README.md        the calibration: kept and dropped tasks with their numbers
  tasks/<id>/            task.yaml, TASK.md (the brief), REVIEW.md (non-author fairness review), fixture/, hidden/
```

## Provenance

Every task is one fix commit of this repository, reachable from `main` at `3e903cb83`, committed on or after 2026-08-01, whose subject starts `fix`/`bug`, whose code and tests lie under `evals/analysis`, and whose changed tests are pytest files that are red at the parent commit and green with the commit's own change to the sources (`hidden/reference.patch`). `task.yaml` `source` names `fix_commit` and `base_commit`; `source.origin` lists the commit's touched paths that are not part of the task (its documentation under `grimoires/`, its harness-side files under `evals/harness` and `evals/tests`).

Seeder (harness at `6df8c6a3c` on `instrument/build-variance`; `LOA_SEED_BATS` = bats 1.13.0 from the npx cache):

```
evals/harness/seed-bugfix-tasks.sh --since 2026-08-01 --rev 3e903cb83 --select 11 \
  --fixture-scope roots --paths evals/analysis --ignore-paths grimoires,evals/harness,evals/tests \
  --id-prefix bugfix-v3 --suite-version 3 --out <staging>
```

The fixture is the whole `evals/analysis` tree at the parent commit (`--fixture-scope roots`: the tests reach across directories; the sibling rule of the default scope left every Loa candidate red at the reference). The test command names the changed test files (the directory also holds the suite's other tests, and running all of `evals/analysis/c132/tests` exceeds the grader's 120 s per-command deadline). The proof ran on the host under `env -i` and the grader's deadline; `self-check-image.txt` repeats it in the image.

The selecting lead (the branch session) rewrote each `TASK.md` by hand from the commit message and the asserted behaviour, in the v2 briefs' form (what is observed, what is expected, with the exact outcome strings and messages the checks pin), naming no test file, test case, grader path or arm id; `criterion` likewise. `REVIEW.md` is a non-author fairness review by codex gpt-6.1-sol (read-only sandbox) over each task directory; read its verdicts before trusting a task.

| id | fix commit | date | changed tests (under `evals/analysis/c132/tests/`) | sources patched | proof (host) | commit subject |
|---|---|---|---|---|---|---|
| bugfix-v3-01 | 637688ba12ba | 2026-10-23 | test_reads.py, test_registration_chain.py | 2 | red 4 / green 63 | addendum 15 — the row validator accepts only the passed registration or a predecessor found by its bytes; legacy class-9 sensitivity name computes once |
| bugfix-v3-02 | 6ee508330a7d | 2026-10-23 | test_judge_agree.py | 1 | red 1 / green 7 | addendum 14 — judge_agree title from the rows' grader version |
| bugfix-v3-03 | 0d1fe51e494c | 2026-10-22 | test_registration_chain.py (new) | 2 | red 6 / green 9 | addendum 11 — the input validator accepts rows registered under any predecessor in the supersedes chain and reports rows per registration |
| bugfix-v3-04 | 2f023159a0ae | 2026-10-22 | test_reads.py | 1 | red 11 / green 51 | addendum 10 — positive_control() implements §8 verbatim and the look mode reports the §5 co-reads |
| bugfix-v3-05 | 350e52cf2ccd | 2026-10-22 | test_reads.py | 2 | red 3 / green 41 | addendum 9 (part 1) — the sensitivity family gains 'oracle-exposed cells re-included' by form |
| bugfix-v3-06 | 9544948b6413 | 2026-10-22 | test_reads.py | 2 | red 3 / green 39 | addendum 8 (part 2) — the sensitivity family 'contaminated cells re-included, per class' |
| bugfix-v3-07 | 426c6c3d15f6 | 2026-10-21 | test_reads.py | 2 | red 2 / green 37 | addenda 5 and 6 (analysis part) — class-9 grades record repo_named; the sensitivity 'class-9 non-repository egress re-included' |
| bugfix-v3-08 | 42537857306d | 2026-10-21 | test_power.py, test_reads.py | 2 | red 9 / green 51 | Task 1.8 round 3 — the ordered decision table with NEGATIVE |

Seedable but not included (the suite takes the eight newest): `3c8c26167995` (Task 1.8 round 2; red 4 / green 67) and `ec92795c4754` (Task 1.8 round 1; red 14 / green 77). `debc6b987e4f` (Task 1.5 round 1) failed its proof: 1 of 23 cases red at the reference under the fixture rule.

## Seeding record (`runs/build-variance/driver/seed-*.log` in loa-smol)

- 234 fix/bug commits since 2026-08-01: 152 refused for touching `.claude/` code (the fix lives in the framework the sandbox never carries), 10 outside the roots (CHANGELOG.md), 1 docs only; 57 have code and tests under the evals roots, 26 of them in commits that also add documentation under `grimoires/` (refused by name until `--ignore-paths`).
- Harness-side candidates (`evals/harness` + `evals/tests`, bats): 10 tried, 0 proofs passed. 3 ran past the 120 s grader deadline (pipeline-run.bats, three-file sets); 7 were not green at the reference — their suites read the suite's own smoke fixtures under `grimoires/loa/evals/ablation-2.0/smoke/` (mount-owned, never in a fixture), the review-PR corpus (`evals/fixtures/review-prs`, 41 MB) or `.claude/`. A fixture holding `evals/harness` is also refused by `evals/graders/no-secrets.sh` (`evals/harness/tests/test-graders.sh` carries secret-shaped test strings).
- Four seeder defects stood between the history and a task and are fixed on this branch: a failed proof left its staged directory behind and every later candidate died on EEXIST; fixture files lost their executable bit (every bats-driven candidate 0 passed at the reference); the fixture scope could not reach a library or fixture outside the touched directory; the proof's deadline killed the bats wrapper only, so a timed-out candidate ran its whole suite and left processes behind.

## Why not hosaka seen / ridden (TypeScript)

`seed-bugfix-tasks.sh --since 2026-08-01 --repo /home/merlin/Documents/thj/code/hosaka/{seen,ridden} --dry-run`:

| repo | roots | refused | skipped | candidates |
|---|---|---|---|---|
| seen | default (`tools,evals/harness,…`) | 53 (every one `grimoires/loa/…`: the mount's a2a records travel with the fix) | 45 | 0 |
| seen | `apps,packages,lib,scripts,migrations,contracts,tests`, `--ignore-paths grimoires,.beads` | 0 | 98: 38 "no runnable test file" (`*.test.ts`), 34 outside the roots, 24 no test, 2 no source | 0 |
| ridden | same widened roots and ignore list | 0 | 25: 16 no test, 9 outside the roots | 0 |

Three things block a TypeScript task, in order: (1) `runner_of()` knows pytest and bats only — the 38 seen fixes change `*.test.ts` files (vitest), so they never become candidates; (2) the host proof runs the test command under `env -i` in a plain tree — a vitest run needs the workspace's `node_modules` (pnpm install, network, lockfile) and the package's `tsconfig`/`vitest.config`, which no fixture rule materialises; (3) `loa-ablation:259` has node 20.11 and `npx` but no pnpm, vitest or installed dependencies, and the sandbox has no egress, so the grader could not run them either. ridden's fixes since August carry no tests.

## Calibration

See `tasks/README.md` (written after the bare-arm calibration batch).
