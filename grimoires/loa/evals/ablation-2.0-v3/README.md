# ablation-2.0-v3 — the build suite with variance

Suite v3 reseeds the build side of the Loa 2.0 ablation from Loa's own post-merge fix history, so that the bare arm can fail. The cycle-130 suite (v2, `grimoires/loa/evals/ablation-2.0/`) is saturated on its build side: hidden-test pass 1.000 in a0_bare, a4_no_gates and a1_full over 36 runs each (cycle 130), 1.00 for bare Opus 5.5 on the gen-contrast draw and 0.95–1.00 for every model generation (loa-smol `REPORT.md` §1, §3) — the instrument cannot detect build-side value. The suite file is `evals/suites/ablation-2.0-v3.yaml` (suite_version 3; every arm, model, cap and rule is v2's). The review-catch side is not part of v3.

## Layout

```
grimoires/loa/evals/ablation-2.0-v3/
  MANIFEST.sha256        freeze.sh: one "<sha256>  <relpath>" line per file under tasks/
  README.md              this file
  self-check-image.txt   ablation-grade.sh --self-check base|reference per task in loa-ablation:259 (the hard gate's log)
  tasks/README.md        the calibration: kept and dropped tasks with their numbers
  tasks/<id>/            the four kept tasks (bugfix-v3-05 … 08): task.yaml, TASK.md (the brief), REVIEW.md (non-author fairness review), fixture/, hidden/
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

| id | fix commit | date | changed tests (under `evals/analysis/c132/tests/`) | sources patched | proof (host) | commit subject | calibration |
|---|---|---|---|---|---|---|---|
| bugfix-v3-01 | 637688ba12ba | 2026-10-23 | test_reads.py, test_registration_chain.py | 2 | red 4 / green 63 | addendum 15 — the row validator accepts only the passed registration or a predecessor found by its bytes; legacy class-9 sensitivity name computes once | dropped (1.000) |
| bugfix-v3-02 | 6ee508330a7d | 2026-10-23 | test_judge_agree.py | 1 | red 1 / green 7 | addendum 14 — judge_agree title from the rows' grader version | dropped (1.000) |
| bugfix-v3-03 | 0d1fe51e494c | 2026-10-22 | test_registration_chain.py (new) | 2 | red 6 / green 9 | addendum 11 — the input validator accepts rows registered under any predecessor in the supersedes chain and reports rows per registration | dropped (1.000) |
| bugfix-v3-04 | 2f023159a0ae | 2026-10-22 | test_reads.py | 1 | red 11 / green 51 | addendum 10 — positive_control() implements §8 verbatim and the look mode reports the §5 co-reads | dropped (1.000) |
| bugfix-v3-05 | 350e52cf2ccd | 2026-10-22 | test_reads.py | 2 | red 3 / green 41 | addendum 9 (part 1) — the sensitivity family gains 'oracle-exposed cells re-included' by form | kept (0.976) |
| bugfix-v3-06 | 9544948b6413 | 2026-10-22 | test_reads.py | 2 | red 3 / green 39 | addendum 8 (part 2) — the sensitivity family 'contaminated cells re-included, per class' | kept (0.974) |
| bugfix-v3-07 | 426c6c3d15f6 | 2026-10-21 | test_reads.py | 2 | red 2 / green 37 | addenda 5 and 6 (analysis part) — class-9 grades record repo_named; the sensitivity 'class-9 non-repository egress re-included' | kept (0.973) |
| bugfix-v3-08 | 42537857306d | 2026-10-21 | test_power.py, test_reads.py | 2 | red 9 / green 51 | Task 1.8 round 3 — the ordered decision table with NEGATIVE | kept (0.980) |

Seedable but not included (the suite takes the eight newest): `3c8c26167995` (Task 1.8 round 2; red 4 / green 67) and `ec92795c4754` (Task 1.8 round 1; red 14 / green 77). `debc6b987e4f` (Task 1.5 round 1) failed its proof: 1 of 23 cases red at the reference under the fixture rule.

## Seeding record (`runs/build-variance/driver/seed-*.log` in loa-smol)

- 234 fix/bug commits since 2026-08-01: 152 refused for touching `.claude/` code (the fix lives in the framework the sandbox never carries), 10 outside the roots (CHANGELOG.md), 1 docs only; 57 have code and tests under the evals roots, 26 of them in commits that also add documentation under `grimoires/` (refused by name until `--ignore-paths`).
- Harness-side candidates (`evals/harness` + `evals/tests`, bats): 10 tried, 0 proofs passed. 3 ran past the 120 s grader deadline (pipeline-run.bats, three-file sets); 7 were not green at the reference — their suites read the suite's own smoke fixtures under `grimoires/loa/evals/ablation-2.0/smoke/` (mount-owned, never in a fixture), the review-PR corpus (`evals/fixtures/review-prs`, 41 MB) or `.claude/`. A fixture holding `evals/harness` is also refused by `evals/graders/no-secrets.sh` (`evals/harness/tests/test-graders.sh` carries secret-shaped test strings).
- Four seeder defects stood between the history and a task and are fixed on this branch (the calibration then found two harness faults, see Calibration): a failed proof left its staged directory behind and every later candidate died on EEXIST; fixture files lost their executable bit (every bats-driven candidate 0 passed at the reference); the fixture scope could not reach a library or fixture outside the touched directory; the proof's deadline killed the bats wrapper only, so a timed-out candidate ran its whole suite and left processes behind.

## Why not hosaka seen / ridden (TypeScript)

`seed-bugfix-tasks.sh --since 2026-08-01 --repo /home/merlin/Documents/thj/code/hosaka/{seen,ridden} --dry-run`:

| repo | roots | refused | skipped | candidates |
|---|---|---|---|---|
| seen | default (`tools,evals/harness,…`) | 53 (every one `grimoires/loa/…`: the mount's a2a records travel with the fix) | 45 | 0 |
| seen | `apps,packages,lib,scripts,migrations,contracts,tests`, `--ignore-paths grimoires,.beads` | 0 | 98: 38 "no runnable test file" (`*.test.ts`), 34 outside the roots, 24 no test, 2 no source | 0 |
| ridden | same widened roots and ignore list | 0 | 25: 16 no test, 9 outside the roots | 0 |

Three things block a TypeScript task, in order: (1) `runner_of()` knows pytest and bats only — the 38 seen fixes change `*.test.ts` files (vitest), so they never become candidates; (2) the host proof runs the test command under `env -i` in a plain tree — a vitest run needs the workspace's `node_modules` (pnpm install, network, lockfile) and the package's `tsconfig`/`vitest.config`, which no fixture rule materialises; (3) `loa-ablation:259` has node 20.11 and `npx` but no pnpm, vitest or installed dependencies, and the sandbox has no egress, so the grader could not run them either. ridden's fixes since August carry no tests.

## Fairness reviews (non-author)

Each kept task's `REVIEW.md` is the review of codex gpt-6.1-sol (subscription; read-only sandbox; prompt `runs/build-variance/driver/review-prompt.md` in loa-smol) over a copy of the task directory, run while the calibration batch ran and moved in afterwards. Codex's sandbox (bubblewrap) failed intermittently on this host ("No permissions to create new namespace"); a review that could not read the files was discarded and rerun (the discarded ones are under `runs/build-variance/driver/reviews-blocked/`). Verdicts:

| task | verdict | sections 1–4 | what the reviewer found |
|---|---|---|---|
| bugfix-v3-01 | FAIL | PASS, FAIL, PASS, FAIL | the brief said every non-sha256 `supersedes` is an input error while a retained case expects a non-string `supersedes` to end the chain (the bare arm passed the task regardless; dropped, brief left as it ran) |
| bugfix-v3-02 | PASS | all PASS | — |
| bugfix-v3-03 | PASS | all PASS | — |
| bugfix-v3-04 | PASS | all PASS | — |
| bugfix-v3-05 | PASS | all PASS | the checks do not assert that validity reasons carry the form (the brief asked for it); the bare arm then broke a retained case by writing the form into the reason — the brief now says the reason stays `oracle_exposed` and the form is recorded beside it. The calibration ran with the earlier wording |
| bugfix-v3-06 | PASS | all PASS | — |
| bugfix-v3-07 | PASS | all PASS | — |
| bugfix-v3-08 | FAIL | FAIL, PASS, PASS, PASS | section 1: the brief "describes the patch as well as the symptom" — it states the new first argument of `decide`, the result keys and the Markdown column. Kept as written: the checks call `decide(delta, …)` positionally and read those exact keys, so a brief without them would fail an agent for its guesswork, not its fix; the v2 briefs state their contracts the same way |

Earlier passes of the reviews (before `grader_protected` listed the test directory's infrastructure) failed section 3 on every task: `_path.py`, `synth.py` and `tests/fixtures/` were unprotected. The seeder now protects every non-test file in and below a test's directory.

## Calibration (bare arm only)

Batch `bv-o55b` (loa-smol `runs/build-variance/bv-o55b/`; rows in `runs/build-variance/runs.jsonl`; metered under `repair-build-bv-o55b-…` in `.run/cost-ledger.jsonl`): arm a0_bare — Opus 5.5 (`global.anthropic.claude-opus-5-5`, the suite default BARE model, effort high, 170 turns / 70 min), one trial per task, egress blocked (`lib/egress-proxy.sh`, self-check all PASS), image `loa-ablation:259`, pin `fbd36a0c9880` (a0_bare mounts nothing from it), cap USD 15, one container at a time. The suite's MANIFEST.sha256 at the batch's pre-flight was `2ef9f39e73d4a4df75561f16a152687c6495ca95c3ef8c8d6fcbbe9e43b0ccdd` (REVIEW.md placeholders, the briefs of 01 and 05 before their fixes). Rows graded by `ablation-grade.sh --suite-file evals/suites/ablation-2.0-v3.yaml` (`--resume --rerow`, see below).

| task | hidden passed/total | pass rate | cost USD | wall min | the case the bare arm failed |
|---|---|---|---|---|---|
| bugfix-v3-01 | 63/63 | 1.000 | 0.40 | 3.5 | — |
| bugfix-v3-02 | 7/7 | 1.000 | 0.15 | 0.7 | — |
| bugfix-v3-03 | 9/9 | 1.000 | 0.33 | 1.8 | — |
| bugfix-v3-04 | 51/51 | 1.000 | 0.76 | 10.6 | — |
| bugfix-v3-05 | 40/41 | 0.976 | 0.52 | 3.5 | a retained case: the validity reason must stay `oracle_exposed`; the agent wrote `oracle_exposed:unknown` into the reason — the brief's "validity reasons carry the form" invited it; the brief is corrected |
| bugfix-v3-06 | 38/39 | 0.974 | 0.45 | 3.5 | the family's per-group counts included a contaminated cell with a second invalidity (oracle-exposed); the base code and the brief count only cells whose only invalidity is the contamination |
| bugfix-v3-07 | 36/37 | 0.973 | 0.57 | 3.0 | the sensitivity did not bring the non-repository egress pair back (`n_pairs` 14, not 15) |
| bugfix-v3-08 | 50/51 | 0.980 | 0.45 | 3.3 | `PARTITION_LEGEND` was turned into a tuple of pairs; the existing check reads it as text (`"NEGATIVE" in PARTITION_LEGEND`) |

The bare arm's runs were short (0.7–10.6 min, USD 0.15–0.76, 2.3–15.7 k output tokens; USD 3.63 for the eight): it edits, runs the named test files against their base versions, sees green and stops; the hidden cases it misses are the ones the base files do not yet hold.

Two infrastructure faults sat between the batch and these numbers, both fixed on this branch: pipeline-run.sh refused every v3 trial before its first phase ("arm id appears in the sandbox: evals/analysis/c132/power.py" — the fixtures are Loa's own ablation analysis, which names every arm; batch `bv-o55`, 1 refused trial, USD 0; fixture-native ids are now exempt), and ablation-grade.sh had no `--suite-file`, so its freeze check read suite_version 3 as a drift and every completed `bv-o55b` trial was rowed infrastructure_error (regraded in place with `--resume --rerow` once the grader took the flag; no model call repeated). The runner itself died once during the batch — its script was edited while it ran — and was resumed; one trial (bugfix-v3-04) ran under the resume.

**Kept (the bare arm failed at least one hidden test): bugfix-v3-05, -06, -07, -08. Dropped (1.000): bugfix-v3-01, -02, -03, -04** — removed from `tasks/` (they stay in git history at `ce4d077be`; their reviews are under loa-smol `runs/build-variance/driver/reviews-dropped/`). `tasks/README.md` holds the same table. One trial per task: a 1.000 here is one pass, not a pass rate; a kept task's miss was one case of 37–51 (0.973–0.980). Re-calibration is owed for bugfix-v3-05 (its brief changed after the run) and, before any multi-arm batch, for the whole suite at three trials per task.

The suite as frozen after the calibration: MANIFEST.sha256 `173b25a47b9e9c8d1098b1965acd4f21b99d1de8206db1db94b56459d413f590` (138 files, four tasks, the codex reviews in place); `self-check-image.txt` is the in-image self-check of that freeze (8 PASS lines; the hard gate wants 2 × 4).

### The next difficulty lever

The seeded candidates themselves say where the difficulty is. The four misses are each one case the base test file does not yet hold — a retained reason string, a count rule, a re-inclusion the agent did not complete, a public constant's type — and the four passes are the tasks whose changed tests are new files or whose base tests already circled the change (`bugfix-v3-03`: a new test file whose every case the brief states; `bugfix-v3-02`: one case). In order of expected effect: (1) fixes whose commit changed three or more test files or added cases to several existing ones (`3c8c26167995`: test_reads + test_stats, 4 red cases; `ec92795c4754`: test_power + test_reads + test_stats, 14 red cases — both seedable, both left out of this draw of eight); (2) fixes spanning two subsystems where the hidden check covers both (`426c6c3d15f6` is such a commit but its harness half had to be left out of the task); (3) a brief that states the symptom only — the reviewer of bugfix-v3-08 holds that the briefs here "describe the patch as well as the symptom"; a symptom-only brief with the same hidden checks would fail more agents, at the price of the fairness argument the v2 briefs made; (4) fixes whose CI run was red at the parent (the history since August has none under `evals/analysis`: every analysis fix landed with its tests in one commit, so red-at-base is the test's own addition, never a broken build).
