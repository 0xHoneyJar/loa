# Sprint 259 (local sprint-2) — implementation report (lead)

**Sprint:** sprint-259 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Base:** 4374c446 (Sprint 258 complete) · **Implementers:** D (Opus 5.5, `../loa-wt-s2d`, Tasks 2.1–2.3), E (Opus 5.5, `../loa-wt-s2e`, Tasks 2.4–2.5), F (Opus 5.5, `../loa-wt-s2f`, Tasks 2.6, 2.8); fairness reviewers R1 (E's tasks) and R2 (D's tasks), Opus 5.5, `../loa-wt-s2r{1,2}` · **Lead:** Tasks 2.0 (`survey.md`), 2.7 (dispatch), 2.9 (this report, the freeze, CHANGELOG, REPO-MAP, checksums) · **Reports:** `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md`, `regrade-batch-1.md`, `self-check-image.log`, `survey.md`

## Executive Summary

Sprint 259 freezes the measurement object. Sixteen tasks live under `grimoires/loa/evals/ablation-2.0/tasks/` (four per type), each with an agent-facing brief, hidden grader material and a non-author fairness review; `MANIFEST.sha256` covers 158 files (sha256 `30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba` after the review fix round; `ab1d631f…` before it) and `freeze.sh --check` is green. The grader `ablation-grade.sh` grades inside the ablation image and its `--self-check` passes 36 of 36 (base and reference for every task, noisy for the four review-catch tasks). The candidate survey (Task 2.0) found Loa's post-August history has one small fix commit and no refactor commit confined to `tools/`, `evals/`, `tests/`, so fifteen tasks are synthetic fixtures in the cycle-124 style and one (`feature-01`) is the open bead bd-8o5rx; the seeders ship as tested tools for the day a clean candidate exists (DEC-0500). bd-8o5rx itself is closed in the main tree (Task 2.8): generated paths are out of `fix_regions`, the eight record manifests regenerated, `SHA256SUMS` refrozen, batch 1 regraded (unchanged by construction).

Integration found no defect in the three patches; every suite is green on the integrated tree (`evals/tests/` 316/316, unit 20/20, `floor-snapshot.bats` 6/6). The lead's own corrections were two: the Sprint 258 smoke rows are untouched, and the Task 2.9 freeze turns FZ-6 (red by design while `tasks/` was unfrozen) green.

## Candidate survey (Task 2.0)

See `survey.md`: 186 commits since 2026-08-01 touch `tools/`, `evals/`, `tests/`; one (`b6802e4f`, five files, a Sprint 255 audit round) is a fix commit of six files or fewer with a test, and D's seeder shows its proof fails in isolation (its bats need harness scripts the commit did not touch); zero refactor commits with unchanged tests; open beads under `evals/` or `tools/`: bd-j4lwr (done in Sprint 258; rejected as a feature fixture, DEC-0505) and bd-8o5rx (`feature-01`).

## AC Verification

### AC-2.1
- Criterion: AC-2.1 `freeze.sh --check` exits 0 on the committed suite and 1 after any byte changes under `tasks/`; the manifest hash is in the sprint report (PRD AC-5.1)
- Status: ✓ Met
- Evidence: evals/harness/freeze.sh:1 (manifest over `tasks/` and `smoke/`); `bash evals/harness/freeze.sh --smoke --check` → "OK — 158 files match MANIFEST.sha256 (sha256 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba)"; evals/tests/freeze.bats:1 (FZ-1 … FZ-8: one-byte drift → exit 1, symlink and newline refusal, FZ-6 the committed root); manifest sha256 `30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba` (fix round; `ab1d631f…` at 6be23186)

### AC-2.2
- Criterion: AC-2.2 Every `task.yaml` names a one-line mechanical `success_criterion`, an allowlisted `test_command`, `post_cutoff: true` with the commit date, and its `type`; the four types have four tasks each (PRD AC-5.2)
- Status: ✓ Met
- Evidence: evals/harness/validate-suite.sh:1 (schema, allowlist, four-by-four counts); `bash evals/harness/validate-suite.sh` → "OK — 16 task(s) valid" and `--smoke` → 18; grimoires/loa/evals/ablation-2.0/tasks/bugfix-01/task.yaml:1 … review-04/task.yaml:1 (sixteen files; `source.date` ≥ 2026-08-01 and `post_cutoff: true` on all sixteen, checked by a yq loop: 0 of 16 bad)

### AC-2.3
- Criterion: AC-2.3 `ablation-grade.sh --self-check` passes 16/16: hidden tests fail at base and pass at the reference patch for bug-fix and feature-build tasks; each refactor task's structural assertion is red at base and green at the reference while the unchanged suite is green at both, churn recorded; review-catch known-good (a findings file citing every key anchor) scores recall 1.0, known-bad (an empty findings file) 0.0, and a known-noisy file (every head line flagged) scores a false-positive count above the known-good file's (PRD AC-5.3, AC-6.4; DEC-0432)
- Status: ✓ Met
- Evidence: evals/harness/ablation-grade.sh:1203 (`self_check`); `self-check-image.log` (36 lines, every one PASS, run with `--executor container --image loa-ablation:258`: e.g. `base bugfix-01: PASS hidden 17/25, fixture suite 12/12`, `reference bugfix-01: PASS hidden 25/25`, `base refactor-03: PASS structural 0/10, suite green`, `reference refactor-03: PASS structural 10/10`, `base review-03: PASS recall 0.0 (0/8)`, `reference review-03: PASS recall 1.0 (8/8)`, `noisy review-03: PASS … false_positives 25 vs reference 0`); churn in each refactor `task.yaml` `source.churn` (refactor-01 4/35/68, refactor-02 1/76/38, refactor-03 3/38/37, refactor-04 4/42/25)

### AC-2.4
- Criterion: AC-2.4 Every task has a `REVIEW.md` from a session other than its author answering the three checks (no solution leak, red-then-green run, criterion mechanical) (PRD AC-5.4)
- Status: ✓ Met
- Evidence: grimoires/loa/evals/ablation-2.0/tasks/bugfix-01/REVIEW.md:1 … review-04/REVIEW.md:1 (sixteen files; R1 — a session that authored nothing — reviewed E's eight, R2 D's eight; every verdict PASS with the reviewer's own pytest/bats tails pasted under "## 2. Red then green"); DEC-0513 (L23)

### AC-2.5
- Criterion: AC-2.5 `ablation-grade.bats`: grading runs in a fresh grading tree, never in the sandbox; agent-edited `conftest.py`, `pytest.ini`, bats helpers and Makefile targets are replaced by the frozen reference; a deleted test dir is restored; a same-named file is overwritten by the hidden copy; per-gate verdict accuracy against each gate's snapshot incl. `null` when no gate ran; the arm-neutral combined findings file reduces the four gate outputs; a transcript naming a path outside the sandbox, `hidden`, the suite path or `git log --all` yields `contaminated`; `grade.json` summary fields carry ids only (PRD AC-6.1, AC-6.2)
- Status: ✓ Met
- Evidence: evals/tests/ablation-grade.bats:1 (AG-1 fresh tree and unchanged sandbox digest, AG-2 protected files replaced, AG-3 deleted `tests/` restored, AG-4 same-named overwrite, AG-6 per-gate accuracy incl. null, AG-8 gates-combined reduction and the sandbox envelope ignored, AG-10 ten contamination inputs incl. WebFetch/WebSearch, AG-12 `meta/`-removed byte-identical grade.json and ids only, AG-18 a pipeline-run.sh run graded and rowed); evals/harness/ablation-grade.sh:657 (`prepare`), :1010 (`contamination`)

### AC-2.6
- Criterion: AC-2.6 No hidden path appears under any sandbox created for a task (`pipeline-run.bats` case extended to the frozen suite layout) (PRD AC-5.5)
- Status: ✓ Met
- Evidence: evals/tests/pipeline-run.bats:1 ("frozen-suite layout": `tasks/bf-02/{task.yaml,fixture,hidden}`; the sandbox, snapshots, transcripts and every commit hold no hidden path or byte); evals/harness/pipeline-run.sh:1 (leak guards, Sprint 258)

### AC-2.7
- Criterion: AC-2.7 `seed-corpus.bats` pins the generated-path exclusion; the eight regenerated manifests carry no generated `fix_regions`; `SHA256SUMS` refrozen; the regraded batch-1 refuted shares are in the sprint report with recall unchanged (PRD AC-10.1)
- Status: ✓ Met
- Evidence: evals/harness/seed-corpus-from-record.sh:205 (`generated_path`), :236 (`--build-manifest` skip), :710 (seed skip); evals/tests/seed-corpus.bats:1 (SC-7 seven generated shapes excluded, one real path kept, each exclusion printed; SC-8 seeding); evals/fixtures/review-prs/manifests/pr-14.json:1 (104 → 95 regions), pr-15.json:1 (239 → 207), the other six byte-identical, every defect id unchanged, 0 generated paths among 769 regions; evals/fixtures/review-prs/SHA256SUMS:1 (`--check` → "corpus OK: 842 files"); `regrade-batch-1.md` (batch 1 graded pr-01 … pr-08 only, which have no `fix_regions`: recall and refuted share unchanged for all 96 trials — baseline 1.0 / 0.7658, no_companion 0.9722 / 0.7474, no_karpathy 1.0 / 0.7564, no_rule_files 1.0 / 0.7807)

### AC-2.8
- Criterion: AC-2.8 All sixteen tasks come from code dated 2026-08-01 or later; the dates are in `task.yaml` (PRD FR-5; DEC-0432)
- Status: ✓ Met
- Evidence: grimoires/loa/evals/ablation-2.0/tasks/bugfix-01/task.yaml:4 … (`source.date`: synthetic tasks 2026-10-15; `feature-01` 2026-10-15 (bd-8o5rx, no fix commit yet); review-01/02 2026-09-20 (the planted fixtures' commit 72bdb7d2), review-03 2026-09-25, review-04 2026-10-05; `post_cutoff: true` on all sixteen); the planted PRs revert fixes from 2026-05-14 … 2026-08-09, recorded as a ceiling risk (DEC-0509, DEC-0507)

### AC-2.9
- Criterion: AC-2.9 No build task's fixture, tests or reference patch touches `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/`; the seeders refuse such a candidate by name; every `task.yaml` lists `grader_protected`; every review-catch `TASK.md` carries the output contract; the README states the freeze and `suite_version` protocol (PRD AC-5.6, DEC-0404)
- Status: ✓ Met
- Evidence: evals/harness/validate-suite.sh:1 (fixture path rule and reference-patch path rule on every build task, 0 violations); evals/harness/lib/seed_tasks.py:294 (`classify`: by-name mount refusal), evals/tests/seed-bugfix.bats:1 (SB-2 `.claude/x.sh` refused by name), evals/tests/seed-refactor.bats:1 (SR-2 `grimoires/` refused); every build `task.yaml` lists `grader_protected` (`tests/conftest.py` and the fixture test files; `feature-01` also `evals/graders/no-secrets.sh`); grimoires/loa/evals/ablation-2.0/tasks/review-01/TASK.md:14 … review-04 (the `## Output contract` section byte-identical to the smoke's); grimoires/loa/evals/ablation-2.0/README.md:1 (freeze, `suite_version`, replace-never-edit hardening, rerun recipe)

### AC-2.10
- Criterion: AC-2.10 Every existing suite green on the final tree; `floor-snapshot.bats` green
- Status: ✓ Met
- Evidence: `bats evals/tests/` → 316/316 (284 at 4374c446; D +11, F +21: AG-1 … AG-18, SC-7, SC-8, the pipeline-run frozen-suite case; VS-1 rewritten by D to derive its expectations from the tree); `bats tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope}.bats` → 20/20; `bats tests/unit/floor-snapshot.bats` → 6/6; `tools/gen-checksums.sh --check` OK (no `.claude/` change), `tools/check-manifest-paths.sh` 1,973/0/0, `evals/fixtures/sync-fixtures.sh --check` "All fixtures current", `evals/graders/no-secrets.sh grimoires/loa/evals/ablation-2.0/tasks` pass

## Lead decisions

DEC-0499 (fixtures inside `tasks/<id>/fixture/`, L21), DEC-0500 (synthetic fallback after the survey, L20), DEC-0507 (keep the planted pair; the report separates planted and record recall, L22), DEC-0513 (two non-author fairness sessions, L23); implementer decisions DEC-0501 … DEC-0504 (D-1 … D-4), DEC-0505, DEC-0506, DEC-0508 … DEC-0510 (E-1 … E-5), DEC-0511, DEC-0512, DEC-0514 … DEC-0518 (F-1 … F-7). Every row `proposed` for `/decisions confirm --cycle cycle-130 --all`.

## Toolchain and spend

Host: Claude Code 2.1.300, python 3.13; image `loa-ablation:258` id `4e37cb5f…` (CLI 2.1.299, python 3.11, pytest 9.0.2, bats 1.13.0). The implementers and fairness reviewers ran no model calls and no docker; the lead ran the image self-check (36 docker runs) and no model call. Cycle spend after Sprint 258: USD 97.89 of 1,500 (no new spend in Sprint 259 before the review round).

## Feedback Addressed — review round 1

Round 1 (`engineer-feedback-r1.md`, dissent `adversarial-review-r1.json`: codex primary with three findings, companion timed out, KF-037 rec 10) returned CHANGES_REQUIRED with one high, three medium and two low findings. One Opus 5.5 implementer fixed all six in `../loa-wt-s2fix` (report `reviewer-fix.md`); the lead applied the patch, reran the image self-check (36/36 PASS on the re-frozen suite), updated the CHANGELOG and recorded DEC-0519 … DEC-0522.

| Finding | Fix | Test (fails on 6be23186, passes now) |
|---|---|---|
| HIGH-1 symlink-following chmod and symlink copying (DISS-001) | `remove_path` chmods only real directories (lstat); `copy_tree` drops absolute or escaping links (lexical check, then a realpath pass until stable) and counts `symlinks_dropped`; the snapshot tar filter rejects escaping symlink members | `ablation-grade.bats` AG-19 (probe mode unchanged across two gradings; three escaping links absent, in-tree links kept; bundle variant) |
| MEDIUM-1 refactor primary read the fixture suite | grader 1.1.0: refactor `hidden_tests` = the structural check, `test_command` = the regression check at base and final; snapshot accuracy needs structural and suite green; README and header updated | AG-7 (rewritten), AG-20 (grade then row: `hidden_test_pass_rate` is the structural rate; an untouched tree scores 0) |
| MEDIUM-2 D's tasks protected only `conftest.py` | every file under `fixture/tests/` listed on the eight tasks; `validate-suite.sh` enforces the rule for build types | `validate-suite.bats` VS-12 (missing top-level, nested and symlinked files listed; review-catch exempt) |
| MEDIUM-3 passing summary overrode a failing exit (DISS-002) | `all_pass` requires rc 0 and no timeout; `hidden_tests` and `regressions.base/final` carry `rc`, `timed_out`; the self-check and per-gate accuracy follow | AG-21 (`1..1 ok 1` then exit 1 is not green; the self-check reference FAILs) |
| LOW-1 bugfix-02 discarded-store case probabilistic | confirmed address reuse through weakref + `gc.collect()`, bounded at 500, stop after three reuses; `success_criterion` reads 6 failed deterministically | ten consecutive base runs red on CPython 3.11/3.12/3.13 (report); image self-check base 7/13 |
| LOW-2 unparseable regression commands (DISS-003) | `regressions()` derives `newly_failing` from exit statuses when a side is unparseable and sets `parse_error` | AG-22 (bash command, exit 0 at base and 1 at final → every fallback id) |

The suite was re-frozen: 158 files, sha256 `30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba` (nine entries changed: eight `task.yaml`, one hidden test). `evals/tests/` 321/321 (5 new cases), image self-check 36/36, `validate-suite.sh --smoke` 18 valid, trust-boundary scan clean.

## Feedback Addressed — audit round 1 (fix commit `05830914`)

Round 1 (`auditor-sprint-feedback-r1.md`, dissent `adversarial-audit.json`: two voices, codex 1 MEDIUM, claude 5 MEDIUM + 1 LOW) returned CHANGES_REQUIRED with one high, three medium and two low findings, all in the grader's handling of the agent's tree. One Opus 5.5 implementer fixed all six in `../loa-wt-s2afix` (report `reviewer-afix.md`, grader 1.2.0); the lead applied the patch, reran the image self-check (36/36 PASS with the hardened container flags), updated the CHANGELOG and recorded DEC-0525 … DEC-0527.

| Finding | Fix | Test (fails on 75d84262, passes now) |
|---|---|---|
| HIGH-A1 agent-left harness files loaded while grading | `remove_harness` before every run: `conftest.py` (any depth), `pytest.ini`, `.pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `setup_suite.bash`, `*helper*.bash/.sh`, `.bash` under `tests/`/`test/` removed unless byte-identical to the fixture's copy or a hidden overlay dest; `harness_files_removed`; pytest `-o addopts=` | AG-23 (root and `tests/acceptance/` conftest hookwrappers, `pyproject.toml` addopts, bats `setup_suite.bash`; fixture copies survive) |
| MEDIUM-A1 container without deadline, limits, cleanup; unbounded stdout | `timeout --signal=TERM --kill-after=10`, `--init`, `--name ablgrade-…`, `--pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges`, client deadline with `killpg` + `docker kill`/`rm -f`, 4 MiB output cap (`output_truncated`) | AG-24 (argv, hung client killed and removed by name), AG-25 (10 MiB output truncated, row writes), AG-1/AG-7 updated |
| MEDIUM-A2 node paths from stdout opened on the host | `node_text`: grader-owned copy first, else `safe_rel` + `is_within` + `read_regular` (`O_NOFOLLOW`, `O_NONBLOCK`, `S_ISREG`, 1 MiB) | AG-26 (`/dev/zero`, `../../etc/passwd`, a FIFO) |
| MEDIUM-A3 unbounded copies and reads; readers followed symlinks | 16 MiB copy cap incl. snapshot tar members (`oversized_files_skipped`); churn never reads oversized files; feedback, review.md and envelopes read ≤ 2 MiB, symlink-free, inside the sandbox | AG-27 (20 MiB sparse file skipped; symlinked feedback → `none`) |
| LOW-A1 host executor without opt-in | `host_gate`: exit 2 unless `LOA_EVAL_ALLOW_HOST_GRADING=1`, WARNING when allowed | AG-28 |
| LOW-A2 contamination exempted credential stores | no `~` root exempt; `~/`, `$HOME/`, `${HOME}/` always outside; `/proc/*/environ|cmdline|maps|mem`, `/var/run` flagged; `/x/` regex skip only after `s y = ~ '` | AG-10, AG-11 extended (nine new rows) |

`evals/tests/` 328/328 (6 new cases), image self-check 36/36 under the hardened container (`--cap-drop ALL`, `--init`, limits proven against the real image), `freeze.sh --smoke --check` OK (158 files, `30e1f2ad…`; the suite is unchanged), trust-boundary scan clean.
