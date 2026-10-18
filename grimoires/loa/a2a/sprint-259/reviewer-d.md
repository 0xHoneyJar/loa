# Sprint 259 implementer D report: Tasks 2.1, 2.2, 2.3

Worktree `/home/merlin/Documents/thj/code/loa-wt-s2d` at `4374c446`. Patch: `~/.cache/loa/cycle-130/patches/s2-d.patch` (stat beside it). No commit, push, stash, docker or model call. `MANIFEST.sha256`, `smoke/`, ledger, decisions, CHANGELOG, REPO-MAP and checksums are untouched.

## Survey
`seed-bugfix-tasks.sh --since 2026-08-01 --dry-run` over the real history finds 1 candidate (`b6802e4f`), with 142 refused (mount paths) and 3 skipped (outside the allowed roots). Materialising it fails the proof: `proof-failed b6802e4f392a: not green at reference (exit 1, 49 failed, 6 passed)`, because its bats tests need harness scripts the commit did not touch. Exit 1, nothing written. `seed-refactor-tasks.sh --since 2026-08-01 --dry-run` finds 0 candidates and 40 refused. This confirms the lead's survey, so all eight tasks are synthetic, per the PRD fallback.

## What was built
- `grimoires/loa/evals/ablation-2.0/README.md` (rewritten) covers:
  - the layout, with fixtures inside `tasks/<id>/fixture/`, superseding the SDD §3.2 `fixtures/<id>` example;
  - the schema table, the `source.kind` vocabulary and the `grader_protected` rule;
  - the four types with their pass and self-check rules, and this suite's `tests/acceptance` and `tests/structure` overlay convention;
  - the freeze, `suite_version` and replace-never-edit hardening protocols, the rerun recipe, and the seeders.
- `evals/harness/validate-suite.sh:20,218-224` accepts `source.churn` as `{files, insertions, deletions}`, non-negative integers. Any other unknown source key is still refused.
- `evals/harness/seed-bugfix-tasks.sh` and `evals/harness/seed-refactor-tasks.sh` are thin wrappers with their full documentation in the header blocks. They `exec python3 -I evals/harness/lib/seed_tasks.py` (new, stdlib only).
  - `classify` (`seed_tasks.py:294`) does the subject match, the by-name mount refusal, the allowed roots and runner detection.
  - `build_bugfix` (`:370`) takes the fixture from the parent (sources, siblings, base tests, infrastructure as `grader_protected`), hidden tests from the commit and the non-test diff as `reference.patch`, then proves red at base and green at reference under `env -i`.
  - `build_refactor` (`:439`) takes the covering tests, proves them green at both ends and records `source.churn`; `structural_check` stays null with a `todo` line.
  - A task moves into place only after its proof and a clean `no-secrets.sh` scan.

## Tasks authored
Proofs used `/tmp/s2d/prove.sh <task>`, a scratch helper. It copies the fixture, overlays the hidden files, and runs every command at base and after `patch -p1`. Results are identical under CPython 3.11.14 and 3.13.

| id | type | source | criterion (short) | base | reference |
|----|------|--------|-------------------|------|-----------|
| bugfix-01 | bug-fix | synthetic: off-by-one at a boundary | the partial last page exists; the pager run has full width; an empty listing works | hidden 8 failed, 5 passed; regression 12 passed | hidden 13 passed; regression 12 passed |
| bugfix-02 | bug-fix | synthetic: stateful cache invalidation | a memoised read reflects load, set and unset, the per-call default, and never another store | hidden 6 failed, 2 passed; regression 5 passed | hidden 8 passed; regression 5 passed |
| bugfix-03 | bug-fix | synthetic: Unicode normalisation | NFKC, full case folding and whitespace collapse are one rule for add, count, merge and remove | hidden 6 failed, 1 passed; regression 6 passed | hidden 7 passed; regression 6 passed |
| bugfix-04 | bug-fix | synthetic: option-precedence order | the first layer giving a value wins, including false, zero and empty | hidden 6 failed, 2 passed; regression 6 passed | hidden 8 passed; regression 6 passed |
| refactor-01 | refactor | synthetic: duplicated validation in three modules | one `validate_record` in `validation`; the readers and the API delegate | structural 8 failed; suite 25 passed | structural 8 passed; suite 25 passed |
| refactor-02 | refactor | synthetic: 69-statement function | split into `parse_lines`, `aggregate` and `render_report`; `build_report` composes; at most 40 statements per function | structural 8 failed; suite 11 passed | structural 8 passed; suite 11 passed |
| refactor-03 | refactor | synthetic: module-level mutable singleton | a frozen `Config` passed as `config` first; no module state, `global` or `configure` | structural 10 failed; suite 10 passed | structural 10 passed; suite 10 passed |
| refactor-04 | refactor | synthetic: string-typed status codes | one `Status` enum; no raw status strings outside it; plain-string equality and JSON unchanged | structural 9 failed; suite 6 passed | structural 9 passed; suite 6 passed |

The bug-fix reference patches change these line counts: bugfix-01 4, bugfix-02 22, bugfix-03 6, bugfix-04 7. All are at most 40.

Refactor churn, from each reference patch:

| task | files | insertions | deletions |
|------|-------|------------|-----------|
| refactor-01 | 4 | 35 | 68 |
| refactor-02 | 1 | 76 | 38 |
| refactor-03 | 3 | 38 | 37 |
| refactor-04 | 4 | 42 | 25 |

Fixtures are 84 to 148 source lines, text only, and pass `no-secrets.sh`. Every reference patch applies with `patch -p1` and `git apply`. `validate-suite.sh --smoke --allow-partial` reports `OK — 10 task(s) valid`.

## Tests added
- **VS-11** (`validate-suite.bats`) covers churn: a valid mapping passes, and a missing key, a negative count or a non-mapping is listed. Any other unknown source key is still refused. Before the change, the base validator listed `source.churn is not a known key` for all four refactor tasks. After it, the case is green.
- **VS-1** is rewritten. It expected an empty `tasks/` (2 tasks, 4 count lines) and went red once tasks existed. It now derives the task count and the short types from the committed tree, so it is green with my eight tasks and stays green with E's tasks or the full sixteen.
- **SB-1 to SB-6** (`seed-bugfix.bats`, new). SB-1: a clean fix gives every field, a parent fixture, `red 2 failed / green 3 passed` and a valid suite. SB-2: a `.claude/x.sh` fix is refused by name, nothing written. SB-3: dry-run writes nothing. SB-4: a test green at the parent gives `proof-failed`, exit 1. SB-5: outside-roots and no-test commits are skipped; a mount root in `--paths` is exit 2. SB-6: usage.
- **SR-1 to SR-4** (`seed-refactor.bats`, new). SR-1: churn in `task.yaml` and the printed line match `git diff --numstat`; both ends green; the only violations are the structural check to author. SR-2: a test-touching commit is skipped with the reason, one source is skipped, `grimoires/` is refused. SR-3: dry-run, and a broken refactor gives `proof-failed`, exit 1. SR-4: no covering test, and usage.
- **Mutation checks:** a mount check returning False turns SB-2, SB-3 and SB-5 red. A churn sum that drops a row, with the test-file skip removed, turns SR-1 and SR-2 red.

## bats counts
| Run | Passed | Total |
|-----|--------|-------|
| Before, at `4374c446` | 284 | 284 |
| After | 294 | 295 |

The new cases are VS-11, six SB cases and four SR cases. The one red after the change is **FZ-6**, which runs `freeze.sh --smoke --allow-partial --check` against the committed root. It is red by design until the lead's freeze, because `tasks/` now holds files the committed manifest does not list. On a copy of the suite root, `freeze.sh --smoke --allow-partial` followed by `--check` exits 0: `97 files match … (sha256 460cf5df…)`. RA-8 failed once in a full run under load. It passed alone and in the next full run, so it is a timing flake unrelated to this patch.

## Decisions
- DECISION: The survey found one fix commit (`b6802e4f`), whose proof fails in isolation, and zero refactor commits. All eight tasks are `source.kind: synthetic`, dated `2026-10-15`, per the PRD fallback (sprint.md § Risks).
- DECISION: `source.churn` is added to the validator's known source keys, with the shape `{files, insertions, deletions}` of non-negative integers. The refactor tasks and the refactor seeder need it, and VS-11 pins it.
- DECISION: Bug-fix hidden tests overlay at `tests/acceptance/<file>`. `test_command` is `python3 -m pytest -q tests` (fixture plus hidden). `regression_command` is the same with `--ignore=tests/acceptance`, so the regression check is the fixture suite whether or not the overlay is present.
- DECISION: The refactor structural checks overlay at `tests/structure/<name>_test.py`. `test_command` is the fixture suite with `--ignore=tests/structure`, green at both ends. `regression_command` is null, because the brief makes `test_command` the regression check. The grader runs the structural check at its `dest`.
- DECISION: The seeders share one Python engine in a new file, `evals/harness/lib/seed_tasks.py`, run as `python3 -I`. The two `.sh` files only exec it, so no harness script sources code and there is no `eval`.
- DECISION: The seeder proof runs under `env -i PATH HOME=<fresh tmp> LC_ALL=C` plus `PYTHONUSERBASE=<host user base>` and `PYTHONDONTWRITEBYTECODE=1`. The Sprint 258 smoke showed this host has pytest only in the user site. The image has no user site, so the extra variable is harmless there. `LOA_SEED_BATS` names a bats binary when bats is not on PATH.
- DECISION: The seeders also copy the other non-test files in each touched source file's directory into the fixture, because a refactor's tests import untouched siblings. Without them every realistic proof fails.
- DECISION: A seeded `TASK.md` carries the subject, sanitised of paths, file names, test names and the grader word, plus the failure count and the test command. It never carries test names; the brief overrides SDD §5.14's "subject plus the test names", because `validate-suite.sh` refuses hidden stems. The lead rewrites the observed behaviour before selection.
- DECISION: The refactor seeder writes `structural_check: null` and `manifest.json {"files": []}`, then prints a `todo` line. The structural assertion is hand-authored, per the brief, so a seeded refactor task fails validation until it exists, on purpose.
- DECISION: Seeded ids are the next free `bugfix-NN` or `refactor-NN` under `--out`. Seeding is meant for a staging root, never the frozen suite.
- DECISION: bugfix-02's latent id-reuse defect is part of the task. The fixture memo keys on `id(store)`, and a discarded store's id is reused. The reference fixes it with a `WeakKeyDictionary`. The hidden discarded-store case is red at base on CPython; it relies on id reuse and is not counted in the five deterministic reds.
- DECISION: VS-1 is rewritten to derive its expectations from the committed tree instead of pinning the Sprint 258 empty `tasks/`.

## Could not do / limitations
- FZ-6 stays red until the lead runs the freeze. I may not write `MANIFEST.sha256`.
- No proof ran inside `loa-ablation:258` (no docker); host CPython 3.11.14 covers the version gap.
- The real candidate `b6802e4f` cannot be used: its tests need much of `evals/harness/` beyond the five touched files.

## Handoff notes for the lead
- E's patch touches only `tasks/feature-*` and `tasks/review-*`, so apply order is free. VS-1 adapts to E's tasks.
- After applying, run the freeze to turn FZ-6 green: `freeze.sh --smoke --allow-partial`, or the final freeze without `--allow-partial`. Then put the manifest hash in the sprint report.
- F's grader must honour the `--ignore=tests/acceptance` and `--ignore=tests/structure` arguments in the commands. It runs the structural check from the manifest `dest` under the tree root, where `tests/conftest.py` puts `src` on `sys.path`.
- CHANGELOG and REPO-MAP need entries for the seeders, `lib/seed_tasks.py`, the churn key and the bats files.
- `grimoires/loa/a2a/` is git-ignored, so the `reviewer-d.md` copy sits in the worktree but not in the patch.
