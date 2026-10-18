# Sprint 259 (cycle-130) implementer E — Tasks 2.4, 2.5

Worktree `/home/merlin/Documents/thj/code/loa-wt-s2e` at 4374c446. All files are under `grimoires/loa/evals/ablation-2.0/tasks/` (`feature-01…04`, `review-01…04`), plus this report copy. No harness, README, validator, corpus, smoke or shared file was touched.

## What was built

- `tasks/feature-01/` — open bead bd-8o5rx. The fixture is the unchanged `evals/harness/seed-corpus-from-record.sh` from 4374c446, plus `evals/graders/no-secrets.sh`, which seed mode calls. It adds `tests/corpus-helper.bash`, a throwaway corpus builder, and `tests/build-manifest.bats`, five cases of current behaviour. The reference patch adds `GENERATED_NAMES` and `is_generated()` above `build_manifest` (script line 197). It also adds a skip for `fix` rows on generated paths inside the row loop (line 217). Ten changed lines.
- `tasks/feature-02/` — synthetic. The `logq` package is `src/logq/{records,cli}.py`. The reference adds `--since`/`--until`, with `BOUND_RX` and `parse_bound` in `cli.py`. 41 changed lines.
- `tasks/feature-03/` — synthetic. The `confload` package is `src/confload/loader.py`. The reference adds `InterpolationError`, `interpolate()` and the `env=` argument on `loads`/`load`, and exports the class. 54 changed lines.
- `tasks/feature-04/` — synthetic. The `tabular` package is `src/tabular/report.py`. The reference adds `_render_markdown` and its helpers and registers `"markdown"` in `FORMATS`. 36 changed lines.
- `tasks/review-01…04/` — `task.yaml` follows the smoke's shape. `TASK.md` keeps the smoke text verbatim, including the `## Output contract` section, which `diff` confirms is byte-identical. Only the repository phrase changed, and one neutral "The change: …" sentence was added, taken from the PR title.

## Tasks authored

| id | type | source | PR | one-line criterion |
|----|------|--------|----|--------------------|
| feature-01 | feature-build | open-bead bd-8o5rx | — | fix rows on generated artefacts produce no fix region; other fix rows, labels and the summary count unchanged |
| feature-02 | feature-build | synthetic | — | log query CLI gains inclusive ISO-8601 `--since`/`--until` with offsets, whole-day dates and exact usage errors |
| feature-03 | feature-build | synthetic | — | config loader gains `${NAME}` / `${NAME:-default}` / `$$` interpolation, single pass, exact error subclass and messages |
| feature-04 | feature-build | synthetic | — | table renderer gains a Markdown format with min-width-3 columns, alignment rows, pipe and line-break escaping |
| review-01 | review-catch | review-corpus (planted) | pr-05 | review the PR, cite defects by file and line, give a verdict; expected CHANGES_REQUIRED |
| review-02 | review-catch | review-corpus (planted) | pr-08 | same; expected CHANGES_REQUIRED |
| review-03 | review-catch | review-corpus (record) | pr-12 | same; expected CHANGES_REQUIRED |
| review-04 | review-catch | review-corpus (record) | pr-13 | same; expected APPROVED |

### Red/green proofs (host, Python 3.13.5; pytest 9.0.2; bats 1.13.0)

The proof copies the fixture to a fresh `mktemp -d`. It runs `regression_command`, then overlays every `hidden/manifest.json` entry and runs `test_command`. It repeats this after `patch -p1 -s < hidden/reference.patch`. Pytest ran as `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider <args>`. Bats ran as `~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats <args>`.

| task | regression at base | test at base | regression at reference | test at reference |
|------|--------------------|--------------|-------------------------|-------------------|
| feature-01 (`bats tests`) | ok=5 not_ok=0 | ok=6 not_ok=6 | ok=5 not_ok=0 | ok=12 not_ok=0 |
| feature-02 | 6 passed | 9 failed, 6 passed | 6 passed | 15 passed |
| feature-03 | 6 passed | 10 failed, 6 passed | 6 passed | 16 passed |
| feature-04 | 5 passed | 9 failed, 5 passed | 5 passed | 14 passed |

The pytest proofs were also rerun under CPython 3.11.14, the image's minor version, through `uv run --offline --no-project --python <uv cpython-3.11.14> --with pytest python -m pytest -q -p no:cacheprovider tests`. The counts were identical: 9 failed/15 passed, 10 failed/16 passed, 9 failed/14 passed. `git apply --check` of every reference patch passes on a fixture copy.

## Tests added

- feature-01: `hidden/tests/generated-exclusion.bats`, seven cases covering dist at any depth, map and d.ts files, the four exact names at any depth, kept regions with id/lines/order/source, lookalikes kept, review/audit labels on generated files kept, and the summary count. Six fail at base and all pass at the reference. The lookalike case passes at base by design: it guards against an over-broad filter.
- feature-02: `hidden/tests/test_time_window.py`, nine cases, all red at base and green at the reference.
- feature-03: `hidden/tests/test_interpolation.py`, ten cases, all red at base and green at the reference. The new class is resolved at test time, so a missing class fails each case instead of aborting collection.
- feature-04: `hidden/tests/test_markdown.py`, nine cases, all red at base and green at the reference.
- Fixture suites, green at both base and reference: `tests/build-manifest.bats` (5), `tests/test_cli.py` (6), `tests/test_loader.py` (6) and `tests/test_text.py` (5).

## Checks

- `bash evals/harness/validate-suite.sh --allow-partial` reports `OK — 8 task(s) valid` (rc 0). With `--smoke`, it reports 10 tasks valid.
- `bash evals/graders/no-secrets.sh <fixture>` passes on all four fixtures.
- No `__pycache__` or `.pytest_cache` exists under `tasks/`. The only `hidden*` names are the four `hidden/` directories.
- Sizes: feature-01 108K (the script is 42 KB), feature-02 68K, feature-03 64K, feature-04 64K, each review task 12K.

## bats counts

At 4374c446 the suite has 284 cases. After this patch, `evals/tests/*.bats` run serially gives 282 of 284; the two failures are #106 FZ-6 and #275 VS-1. These two cases pin the Sprint 258 empty-`tasks/` state and fail by construction once any task exists:
- `validate-suite.bats` VS-1 greps `OK — 2 task(s) valid` and expects four `counts:` lines without `--allow-partial`;
- `freeze.bats` FZ-6 runs `freeze.sh --smoke --allow-partial --check` against the committed `MANIFEST.sha256`, which was frozen over smoke only.
Neither is mine to edit. Both resolve when the lead runs the Task 2.9 freeze and updates VS-1 to the sixteen-task state.

## DECISION: bullets

- DECISION: bd-j4lwr (`run-arms.sh --max-usd/--screen`) is not used as a feature task. Its fixture would need `.loa.config.yaml`, a mount-owned path the path rule refuses. It would also need the 22 MB `review-prs` corpus, whose `SHA256SUMS` it verifies per trial, plus `sandbox.sh`, `execute-agent.sh`, `grade.sh` and a git source commit to cut a worktree from. Its Sprint 258 diff is 172 lines in `run-arms.sh` alone, over the 120-line reference ceiling.
- DECISION: feature-01 is the only real-history feature task, with source `open-bead bd-8o5rx` dated 2026-10-15, the authoring date. The bead has no fix commit yet. The reference is my own minimal exclusion and is independent of implementer F's Task 2.8 patch.
- DECISION: the feature-01 generated-path rule comes from the bead text: a `dist` directory component at any depth, a name ending `.map` or `.d.ts`, or an exact name `.checksum`, `checksums.json`, `REPO-MAP.md` or `.build-manifest.json`. Only `fix` rows are filtered, because recall is graded against labels, which the bead says are unaffected. Generated rows are skipped before the head-file check.
- DECISION: the feature-01 fixture keeps the script at its real path, `evals/harness/seed-corpus-from-record.sh`, so `REPO_ROOT` resolves inside the tree. The tests pass `--corpus` to a temporary directory. `no-secrets.sh` is included so seed mode is runnable, though no test exercises seed mode.
- DECISION: three synthetic feature tasks were authored, all dated 2026-10-15: the log-query time window, config interpolation and the Markdown table. Priority lanes were not chosen.
- DECISION: the feature-01 `test_command` is `["bats", "tests"]`, which runs the fixture suite and the overlaid file together, matching the pytest tasks' `tests` convention. `regression_command` is the fixture's own suite file.
- DECISION: `grader_protected` lists every fixture test file, not only the helpers. The regression suite is restored before grading, so an agent edit cannot weaken it. feature-01 also protects `evals/graders/no-secrets.sh`.
- DECISION: feature bounds are `{max_turns: {IMPLEMENT: 60}, timeout_min: {IMPLEMENT: 25}}`, per the brief. Review bounds are empty maps, the suite defaults, as in the smoke.
- DECISION: host pytest proofs run without `-I`. pytest lives only in the user site, which `-I` disables (`No module named pytest`). `PYTHONDONTWRITEBYTECODE=1` and `-p no:cacheprovider` keep the fixtures free of caches.
- DECISION: the review-catch choice is pr-05 and pr-08 (planted) and pr-12 and pr-13 (record).
- DECISION: pr-05 key: 3 defects, D13 critical, D14 high, D15 medium. Expected verdict CHANGES_REQUIRED.
- DECISION: pr-08 key: 3 defects, D22 high, D23 medium, D24 medium. Expected verdict CHANGES_REQUIRED. It was chosen as the planted PR with a single high defect.
- DECISION: pr-12 key: 8 defects, L01–L03 high, L04–L06 medium, L07–L08 low. Expected verdict CHANGES_REQUIRED. It is the smallest record diff (66 KB, 15 files) that carries high defects.
- DECISION: pr-13 key: 5 defects, L01 low, L02 medium, L03–L05 low. It is the PR with no high or critical defect, so the expected verdict under DEC-0420 is APPROVED. pr-13 was preferred over pr-14, pr-15 and pr-16 for the larger key, with at least 3 defects.
- DECISION: review `source.date` is the corpus row's commit date for the record PRs: pr-12 at 6c887887 is 2026-09-25, and pr-13 at 41b783a1 is 2026-10-05. The planted PRs use 2026-09-20, the date of commit 72bdb7d2, which authored the planted PR fixtures. The corpus rows' own commits for pr-05/pr-08 are 2026-05-14 … 2026-08-09, the fix commits the planted defects revert, and most predate the 2026-08-01 cutoff.
- DECISION: the review `TASK.md` replaces the smoke's "a repository of shell scripts" with a phrase accurate to the PR. pr-05 and pr-08 say "shell and Python scripts"; pr-12 and pr-13 say "shell scripts, tests and documentation". Each adds "The change: …", paraphrased from the PR title only, never the description.

## Could not do / limitations

- AC-2.8 risk for review-01/02: the planted defects revert code from commits dated 2026-05-14 to 2026-08-09, before the cutoff. A model may have seen the fixed code, even though the planted PR itself dates from 2026-09-20. The lead should decide whether to swap in a record PR. pr-11, pr-17 and pr-18 carry high defects, but their diffs are 125–383 KB.
- No proof ran inside `loa-ablation:258`, because Docker is lead-only. The host runs used bats 1.13.0, plus pytest 9.0.2 on Python 3.13 and 3.11.
- feature-01 has one hidden case green at base by design, the lookalike guard. All other feature hidden cases are red at base.

## Handoff notes for the lead

- Freeze after the fairness review. VS-1 and FZ-6 need the Task 2.9 freeze and VS-1 update; they are expected red until then.
- The feature-01 fixture embeds the 4374c446 copy of the seed script. If F's Task 2.8 patch lands first, the fixture stays at 4374c446 on purpose: the base must lack the feature.
- Images: `bats`, `jq` and `python3` on PATH are required for feature-01. The tests call `jq`.
