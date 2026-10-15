# ablation-2.0 task suite (cycle-130)

The frozen task suite for the Loa 2.0 component ablation (PRD FR-5, SDD §3.2). Grader-only material lives under each task's `hidden/` directory and is never copied into a sandbox.

## Layout

```
grimoires/loa/evals/ablation-2.0/
  MANIFEST.sha256        freeze.sh: one "<sha256>  <relpath>" line per file under tasks/ (and smoke/ with --smoke)
  README.md              this file
  tasks/<id>/            the sixteen frozen tasks (Sprint 259)
    task.yaml            schema below; validate-suite.sh checks it
    TASK.md              the brief the agent sees (no grader paths, test names, defect ids or arm ids)
    REVIEW.md            the fairness review by a non-author session (Sprint 259 Task 2.7)
    fixture/             build tasks: the base tree the sandbox starts from
    hidden/              grader-only: manifest.json, tests/…, structural/…, reference.patch
  smoke/<id>/            the two Sprint 258 smoke tasks, same layout, never counted
```

- **Task ids:** `bugfix-01` … `bugfix-04`, `refactor-01` … `refactor-04`, `feature-01` … `feature-04`, `review-01` … `review-04`. An id matches `^[a-z0-9][a-z0-9-]{0,63}$` and equals its directory name.
- **The fixture lives inside the task directory.** `task.yaml` says `fixture: tasks/<id>/fixture`, a path relative to this root, so `freeze.sh` covers the fixture with the rest of the task. The SDD §3.2 example's `fixture: fixtures/<id>` (a sibling `fixtures/` directory) is superseded by this layout (DEC-0436). Review-catch tasks have `fixture: null`; their tree is the frozen corpus fixture named in `review_catch`.
- **A fixture is a plain tree, never a clone.** It never holds `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. It holds no caches (`__pycache__`, `.pytest_cache`) and nothing named `hidden*`. The answer must not be recoverable from history.
- **`hidden/manifest.json`** is `{"files": [{"src", "dest"}]}`. `src` is relative to `hidden/`. `dest` is the path inside the grading tree where the grader overlays the file. A hidden file may overwrite a same-named fixture file, and no `dest` lands on a mount-owned path.

## task.yaml (schema_version 1)

| Field | Meaning |
|-------|---------|
| `id`, `schema_version: 1`, `type` | `type` is one of `feature-build`, `bug-fix`, `refactor`, `review-catch` |
| `source` | `{kind, date, fix_commit?, base_commit?, bead?, origin?, churn?}`; `churn` is `{files, insertions, deletions}` (refactor) |
| `post_cutoff` | `true`: every task comes from code dated 2026-08-01 or later (AC-2.8) |
| `fixture` | `tasks/<id>/fixture` for build types; `null` for review-catch |
| `criterion` | agent-facing behaviour or structure in one sentence; never a path, file name or test name |
| `success_criterion` | grader-facing, one line, mechanical: which hidden file passes how many cases |
| `test_command` | array; first token `python3`, `pytest`, `bats`, `bash`, `node` or `npx`; run from the grading-tree root; `null` for review-catch |
| `regression_command` | array or `null`; green at base; a newly failing case counts as a regression |
| `reference_patch` | `hidden/reference.patch`, a unified diff with `a/` `b/` prefixes applying with `patch -p1` from the fixture root; required for bug-fix and feature-build |
| `grader_protected` | test-infrastructure paths the grader restores from the frozen fixture before it runs anything |
| `structural_check` | refactor: `hidden/structural/<name>_test.py` (or `.bats`), listed in `manifest.json` with a `dest` under `tests/`; `null` otherwise |
| `bounds` | `{max_turns: {}, timeout_min: {}}`; empty maps are the suite's phase defaults; set a phase (for example `IMPLEMENT`) only when a task needs more |
| `review_catch` | `null`, or `{fixture: review-prs/pr-NN, manifest: evals/fixtures/review-prs/manifests/pr-NN.json}` |
| `suite_version` | equals the suite file's `suite_version` |

### `source.kind`

| Kind | Origin | `source.date` |
|------|--------|---------------|
| `loa-history` | a Loa fix or refactor commit (`fix_commit`, `base_commit`), seeded by the tools below | the commit's date |
| `synthetic` | a fixture authored for this suite; `origin` names the defect or smell class | the authoring date |
| `review-corpus` | a frozen review-corpus PR under `evals/fixtures/review-prs/` | the corpus row's date |
| `open-bead` | an open bead at rc.5 whose code lives under `evals/` or `tools/` (`bead`) | the bead's date |

The Sprint 259 candidate survey found one fix commit since 2026-08-01 confined to `tools/` and `evals/` that touched a test, and its proof fails in isolation. It found no refactor commit with unchanged tests. The bug-fix and refactor tasks are therefore synthetic, which is the PRD fallback.

### `grader_protected`

The agent may edit anything in its tree, including the tests. Before grading, the grader restores every `grader_protected` path from the frozen fixture. Every test-infrastructure file the fixture has must be listed: `tests/conftest.py`, `pytest.ini`, `pyproject.toml`, bats helpers, Makefile targets and runner configs. Every listed path must exist in the fixture. For a build task the list also names every file under the fixture's `tests/`, because the fixture suite is the regression check. `validate-suite.sh` checks both rules. Test files the agent adds are not protected, and a hidden test that shares a name with one overwrites it.

## The four types and how each is graded

The grader builds a fresh grading tree for the final tree and for every gate snapshot. It copies the tree, restores `grader_protected`, overlays the `hidden/manifest.json` files, and runs the commands inside the ablation image (SDD D-4.8). The copy keeps only symlinks whose target is relative and stays inside the tree; `grade.json` counts the rest as `symlinks_dropped`. A command is green only when every case passes, its summary parses, it exits 0 and it does not time out. Python runs as `python3 -I -s -m pytest -p no:cacheprovider --rootdir <tree> -q`. Bats runs with `BATS_LIB_PATH` unset.

| Type | Pass rule | Self-check (`ablation-grade.sh --self-check`) |
|------|-----------|-----------------------------------------------|
| bug-fix | `test_command` green with the hidden tests overlaid; `regression_command` (the fixture's own suite) has no newly failing case | base: red; reference patch: green |
| feature-build | as bug-fix | base: red; reference patch: green |
| refactor | the structural check green (it is `hidden_tests`, so the row's `hidden_test_pass_rate` is the structural pass rate) and `test_command` (the fixture's own suite, unchanged) with no newly failing case | base: structural red, suite green; reference: both green; churn recorded |
| review-catch | recall of the corpus defects over the arm-neutral combined findings; false positives deduplicated by region | a findings file citing every key anchor scores recall 1; an empty one scores 0 |

In this suite's bug-fix tasks, the hidden tests overlay under `tests/acceptance/`. `regression_command` runs the fixture suite with `--ignore=tests/acceptance`. In the refactor tasks, the structural check overlays under `tests/structure/`. `test_command` runs the fixture suite with `--ignore=tests/structure`, and the grader runs the structural check at its `dest` with the same runner. For a refactor task the grader reports the structural check as `hidden_tests` and the fixture suite, run at base and at the final tree, as `regressions`; `regression_command` stays null. A gate's verdict on a refactor snapshot is accurate when it approves a tree on which both the structural check and the suite are green, or asks for changes on a tree where either is red.

## Freeze protocol

1. `evals/harness/validate-suite.sh` must report 0 violations. Pass `--allow-partial` only while fewer than four tasks of each type exist.
2. `evals/harness/freeze.sh` writes `MANIFEST.sha256` over every file under `tasks/`: sorted, `LC_ALL=C`, Python hashlib. It runs the validator first and refuses a symlink or a path with a newline. The lead runs the final freeze.
3. `freeze.sh --check` runs before every trial and before every grading. Any byte changed, added or removed under `tasks/` exits 1, and nothing runs or grades on a drifted suite.
4. **`suite_version`:** when a task changes after a smoke, the change, the manifest and `suite_version` move together. The suite file, every `task.yaml` and `MANIFEST.sha256` are updated in one commit, so rows from different versions never pool.
5. **Hardening:** after the first real batch, a task found leaky (the answer is reachable from the agent tree or the brief) or too easy is **replaced, never edited in place**. The replacement gets a new id, the old directory leaves `tasks/`, and `suite_version` bumps.

## Rerun recipe

```
bash evals/harness/validate-suite.sh                  # 0 violations, four tasks per type
bash evals/harness/freeze.sh --check                  # MANIFEST.sha256 matches
bash evals/harness/ablation-grade.sh --self-check …   # every task: base and reference behave as the table says
```

## Tools

- `evals/harness/validate-suite.sh [--root DIR] [--smoke] [--allow-partial] [--suite-file F]` checks the schema, the counts, the allowlist, the manifests, the fixture path rule and leakage.
- `evals/harness/freeze.sh [--root DIR] [--smoke] [--check] [--allow-partial] [--suite-file F]` writes or verifies `MANIFEST.sha256`.
- `evals/harness/seed-bugfix-tasks.sh --since DATE [--select N] --out DIR [--repo DIR] [--paths CSV] [--dry-run]` turns Loa fix commits into candidate bug-fix tasks. The commits must touch a test and stay under the allowed roots. The tool refuses any candidate touching a mount-owned path by name, and proves red at base and green at the reference before writing anything.
- `evals/harness/seed-refactor-tasks.sh` takes the same options and turns refactor commits into candidate refactor tasks. A candidate touches at least two source files and no test file, and its covering tests must be green at both ends. The tool records `source.churn`. The structural check is authored by hand.

Seeded tasks go to a staging root (`--out`), never straight into this suite. The lead selects among them, rewrites the observed behaviour in `TASK.md` and the criterion, and moves the chosen ones in.

## Smoke tasks

- `smoke/smoke-review-01` is a review-catch task on the frozen corpus PR `review-prs/pr-01`. Its `TASK.md` carries the arm-neutral output contract: `review.md`, one `head/<path>:<line> — <description>` per finding, and a final `Verdict:` line.
- `smoke/smoke-build-01` is a bug-fix task from `evals/fixtures/implement-tasks/01`. Its test moved to `hidden/tests/test_slug.py`, with two collapse cases added so it is red at base, and a reference patch makes it green.
