# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, a 1,130-line Python heredoc), the bug-fix and refactor task seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `lib/seed_tasks.py`), the generated-path exclusion in `seed-corpus-from-record.sh` (bd-8o5rx), the `source.churn` key in `validate-suite.sh`, the regenerated pr-14/pr-15 key manifests, and bats coverage for all of it.

What is good: the grader's threat model is thought through (grading trees, protected files, hidden overlay, snapshot extraction from bundles, path-safety on every manifest entry, nothing sourced or eval'd), the seeders prove red/green before anything lands in the suite, and the generated-path rule is applied consistently (I checked every removed `fix_regions` row in pr-14/pr-15 against the new predicate: 41 removed, all generated, none remaining, defects untouched, SHA256SUMS match).

What blocks the merge: four high findings, three of which I reproduced by running the grader from the head tree.

1. Snapshot extraction uses `TarFile.extractall(filter=…)` / `tarfile.data_filter`, which do not exist before Python 3.11.4 / 3.12. On the stock Debian 12 interpreter here (3.11.2) every run that has a REVIEW or AUDIT gate dies with `internal error: TypeError` (exit 2). There is no version guard and no clear message.
2. `hidden_tests` is the result of the whole `test_command` directory, so tests the agent writes (the TASK.md tells it to) inflate passed/total. Reproduced: both hidden tests failing plus 20 agent tests reports `20/22`.
3. `envelope_texts` reads `anchor` as a `path:line` string and `file`+`line`, but the dissent envelope the pipeline copies under `eval/` (produced by `adversarial-review.sh`, the same script I ran in Phase 2.5) carries `anchor: "<path>:<symbol>"` plus `anchor_line`. No citation is ever extracted from a real envelope, so review-catch recall is understated for every arm that runs the dissent. (Raised by the cross-model dissent as DISS-001; verified against this session's envelope.)
4. `evals/tests/ablation-grade.bats` hardcodes an operator-specific bats path (`$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`) where the rest of the suite uses `LOA_EVAL_BATS_BIN`; the bf-sh cases fail on any other machine.

Reproduction notes: the seeded SB-1 scenario produces a task that proves red 2 / green 3 as the test expects; `seed-bugfix.bats` 5/6 and `seed-refactor.bats` 3/4 pass here, the remaining failures are environment (no `patch` binary; `evals/suites/ablation-2.0.yaml` is not part of the PR snapshot). I could not run `ablation-grade.bats`, `seed-corpus.bats` SC-7/SC-8 or `validate-suite.bats` VS-11 here: their setups need the smoke suite, `freeze.sh`, `pipeline-run.sh` and fixtures outside the touched files.

Process notes: `reviewer.md` is the PR description and carries no `## AC Verification` section; the PR title names "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze", but no file under that path and no `MANIFEST.sha256` is in `pr/head.diff`, so neither the tasks nor the freeze could be reviewed. `br` is not installed in this workspace; no beads updates were made.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability — snapshot extraction needs Python ≥ 3.11.4

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:713-714` — `tf.extractall(tree, filter=keep)` raises `TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'` on Python 3.11.2; `keep` (line 710) also calls `tarfile.data_filter`, absent before 3.11.4/3.12. Caught by the generic handler at line 1290 → `internal error`, exit 2.
**File:** `head/evals/harness/ablation-grade.sh:713-714`
**Issue:** Any run where a gate ran (`gates` non-empty at line 1110-1113) reaches `extract_snapshot`; on the Debian 12 stock interpreter the whole grade aborts and no `grade.json` is written. Reproduced here: a run with an IMPLEMENT bundle and a review trailer exits 2 with exactly that message, while a gate-less run grades fine.
**Why This Matters:** The grader is the measurement instrument; an interpreter-version dependency with no guard turns a whole batch into exit-2 rows on a common host, and the message does not say why.
**Required Fix:** Either pin the requirement (check `sys.version_info` / `hasattr(tarfile, "data_filter")` at start and `die` with a clear message), or implement the path check yourself: you already have `safe_rel` and `EXCLUDE_TOP`; add a symlink/hardlink/device member rejection and call `extractall(tree, members=[...])` without `filter`.
**Reference:** Python docs, `tarfile` extraction filters (added 3.12, backported 3.11.4).

### 2. Measurement — agent-authored tests inflate `hidden_tests`

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1080` — `run_suite(final, t.test_command, t.static_cases)` runs the task's whole test directory; `summary()` reports every collected test as a "hidden" test.
**File:** `head/evals/harness/ablation-grade.sh:1080` (same at `:1122` for snapshots, `:1102` for refactor base)
**Issue:** `TASK.md` tells the agent to "add a regression test of your own" (`head/evals/harness/lib/seed_tasks.py:432`). Reproduced: fixture unchanged (both hidden tests fail) plus 20 trivially passing agent tests → `{"passed": 20, "total": 22}`; the honest figure is 0/2. The same denominator feeds `all_pass` → `verdict_accuracy_per_gate` (an agent-added failing test makes a correct APPROVED "inaccurate") and `ablation-row.sh`'s `hidden_test_pass_rate`.
**Why This Matters:** The primary outcome metric is gameable and systematically biased toward arms that write more tests, which is exactly the kind of arm difference the ablation is meant to measure.
**Required Fix:** Grade the overlaid files only: build the argv from `t.overlay` dests (pytest: pass the dest paths instead of the directory; bats: the dest `.bats` files), or at least filter `outcomes` to nodes whose path is an overlay dest and set `total = static_cases`. Keep the directory form for `regression_command` only.

### 3. Review-catch recall — the real dissent envelope schema is never parsed

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:862-867` — `envelope_texts` appends `f["anchor"]` verbatim and a `file:line` string only from `file|path` + `line|line_start|start_line`; the envelope `adversarial-review.sh` writes has `anchor: "<path>:<symbol>"`, `anchor_type`, `anchor_line`, `anchor_line_end` and no `file`/`line` keys.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** `citations()` (line 818) requires `path:<digits>`; `evals/harness/ablation-grade.sh:envelope_texts` yields nothing, so every structured dissent finding contributes zero citations to `gates-combined.md`, and a defect only the dissent caught is counted as missed. AG-8 passes because its fixture envelopes use `{"anchor": "lib/x.sh:20"}` and `{"file", "line"}`, shapes the production writer does not emit. Verified against this session's `grimoires/loa/a2a/sprint-1/adversarial-review.json`. (Dissent DISS-001.)
**Why This Matters:** Recall for the full-pipeline arm (the one with the dissent) is understated relative to the bare arm; this biases the headline review-catch comparison.
**Required Fix:** In `envelope_texts`, when `anchor_line` is an int, derive the path from `anchor.rsplit(":", 1)[0]` (or `file`/`path`) and emit `f"{path}:{anchor_line}"` (and `-{anchor_line_end}` when present); keep the current branches as fallbacks. Change the AG-8 fixture envelopes to the production shape.

### 4. Tests — operator-specific absolute path in the grader test file

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"`; `ln -s "$BATS_BIN" "$T/bin/bats"` at line 48 dangles everywhere else.
**File:** `head/evals/tests/ablation-grade.bats:16` (also `:46` hardcodes `/usr/bin/python3`)
**Issue:** Every case that runs a bats task (AG-2 bf-sh, AG-7 bf-sh) and the TAP assertion at line 353 fails for any operator or CI host without that dotfiles checkout. The rest of the eval suite resolves bats through `LOA_EVAL_BATS_BIN` / `--bats-bin` (`head/evals/tests/pipeline-run.bats:897-901`).
**Why This Matters:** The grader's only tests cannot run outside one machine, which also means the fast gate (`evals/tests/*.bats`) never exercised them in CI.
**Required Fix:** `BATS_BIN="${LOA_EVAL_BATS_BIN:-$(command -v bats)}"` and `skip` when empty; use `command -v python3` for the stand-in.

---

## Observations

### 1. Contamination scan — false positives on ordinary shell words

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:940` — `ABS_WORD` treats any quoted `/x…` token as a path; `check_value` (`:976-983`) then reports `outside_path`. Reproduced: a Bash command containing `re.sub(r'/x', '', s)` marks the run `{"pattern": "outside_path"}`. `sed -e /re/d` with a multi-segment regex, awk programs and python one-liners are the same class. A contaminated flag voids a trial, so a false positive is as costly as a miss.
**Suggestion:** Only treat a word as a path when it exists as a prefix of a known root or has ≥ 2 components and a plausible basename; or scan Bash commands only for the explicit sensitive roots (`/home/*`, `/root`, `/srv`, `/mnt`, `/media`, `/data`) rather than "anything not allowed".
**Benefit:** Fewer voided trials; the scan stays a lower bound on leakage as documented.

### 2. Regression baseline includes the hidden overlay

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1086-1090` — `prepare(t, base_tree)` overlays hidden tests before `regression_command` runs on base. When the regression command targets the same directory (`pytest tests`), `regressions.base` and `regressions.final` totals include the hidden tests (reproduced: base `1/3`, final `1/3`, where the fixture suite is one test). `hidden_tests` likewise includes fixture tests (`1/3` instead of `0/2`).
**Suggestion:** Run `regression_command` on a base tree with protected files restored but without the overlay (or pass only the overlay dests to `test_command`, which also fixes Changes Required §2).
**Benefit:** `regressions.*` and `hidden_tests.*` mean what their names say.

### 3. `all_pass` ignores the exit code and the timeout (dissent DISS-002)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:652-653` — a TAP stream that prints `1..N` and every `ok` and then hangs (or a module whose `atexit` hook blocks after pytest's summary) returns rc 124 and `timed_out: true` yet `all_pass` is true, so an APPROVED gate on that tree is scored accurate.
**Suggestion:** `return res["rc"] == 0 and not res["timed_out"] and …`; apply the same to the self-check acceptance.
**Benefit:** A timed-out or crashed run is never scored as green.

### 4. Grader argv differs from the seeders' proof argv (dissent DISS-C-001)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:492-493` vs `head/evals/harness/lib/seed_tasks.py:204-208` — the grader runs `python3 -I -s -m pytest` (container) / `python3 -P -m pytest` (host), which drop the cwd from `sys.path`; the seeders prove with plain `python3 -m pytest -q <dirs>`. A hidden test that imports a tree-root module without a conftest shim is green in the proof and `ModuleNotFoundError` in the grader. `--self-check reference` would catch it before freezing, but the proof should not be able to pass what the grader fails.
**Suggestion:** Have `seed_tasks.run_tests` build its argv through the same shaping (`-I -s` / `-o pythonpath=.`), or drop `-I`/`-P` in favour of `-E -s`.
**Benefit:** Proof and grade cannot diverge.

### 5. Pytest/TAP terminal parsing is forgeable from the tree under test (dissent DISS-C-002)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:546-594` — `SUMMARY_RX` takes the last matching line of stdout and `OUTCOME_RX` any `PASSED|FAILED … <node>` line; `-rA` also echoes captured stdout of passed tests. Source code under test (not protected) can print `===== 99 passed in 0.01s =====` from an `atexit` hook after pytest's own summary and be scored all-green.
**Suggestion:** Read `--junitxml=/tmp/r.xml` (the tmpfs is already mounted) instead of the terminal; keep the terminal parse as the fallback with `parse_error: true`.
**Benefit:** Scores come from pytest's own record, not from anything that can write to stdout.

### 6. Allowed roots follow the grader's executor, not the agent's (dissent DISS-C-005)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:947-949` — in container mode the transcripts' init cwds are discarded. A run produced by `pipeline-run.sh --executor host` (as AG-18 does) and graded with the default `--executor container` trips `outside_path` on its first absolute `Read` of its own sandbox.
**Suggestion:** Always union `init_cwds`, `<run-dir>/sandbox` and its realpath into the roots; the executor flag should only choose how tests run.
**Benefit:** Host-run debugging trials are not voided for reading their own files.

### 7. `git apply` fallback silently applies nothing inside another work tree

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:225-230` — without a `patch` binary the fallback runs `git apply -p1` with `cwd=tree`; when the staging directory (`tempfile.mkdtemp`, i.e. `$TMPDIR`) lies inside some other git work tree, git resolves paths against that repository, ignores every hunk as "outside the current directory" and exits 0. Reproduced with `TMPDIR` under this repository: the proof then reports `not green at reference (exit 1, 2 failed, 1 passed)` for a correct fix.
**Suggestion:** `git apply --unsafe-paths --directory=<tree>` with `GIT_DIR` unset and `GIT_CEILING_DIRECTORIES=<parent>`, or simply require `patch` (the grader at `:1175` already does).
**Benefit:** A misconfigured host cannot silently reject every candidate.

### 8. Low-severity notes

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1099-1105` — (dissent DISS-C-003) if a refactor's structural dest lies under a `test_command` directory, the structural result is counted in `hidden_tests` and both `suite_green_*` flags, and the documented base self-check ("structural red AND suite green") can never hold. Validate at `load_task` that the structural dest is not under any `test_command` path.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:506-521` — (dissent DISS-C-004) `timeout 120` without `-k` and no `--init`; when the outer `subprocess.run` timeout kills the `docker run` client, a SIGTERM-ignoring test process leaves an orphaned container holding the grading tree mount. Use `timeout -k 10 120`, `--init`, and `docker kill` by `--name` on `TimeoutExpired`.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1280-1281` — the human-readable line prints Python `None` (`verdict_accuracy None`) instead of `null`.
- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198` — pytest `counts()` reads the last line of stdout+stderr concatenated; any trailing stderr line (an interpreter-shutdown warning, a `ResourceWarning`) hides the summary and the proof reports 0 passed. Scan for the summary regex over all lines instead.
- **LOW** (confidence: high) `head/evals/tests/seed-bugfix.bats:183` — SB-6 asserts "not a git repository" with `--repo "$T"`; when `BATS_TEST_TMPDIR` lies inside any git work tree the check passes and the test fails (seen here with `TMPDIR` under the repo). Use a directory with a stray `.git` file or `GIT_CEILING_DIRECTORIES`.
- **LOW** (confidence: high) `head/evals/tests/validate-suite.bats:31-44` — VS-1 now derives both expectations (`n`, `short`) from the suite it validates, so it can no longer fail on a suite that is incomplete; it only checks the counter against `find`. Acceptable while the suite is being filled, but note it in the test name.
- **LOW** (confidence: high) `head/evals/tests/ablation-grade.bats:46` — `/usr/bin/python3` hardcoded in the image stand-in; use `command -v python3`.

### 9. Complexity

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:319-419` and `:1045-1142` — `load_task` (100 lines) and `grade` (97 lines) exceed the 50-line threshold; `grade` nests the build branch four deep. Split `grade` into `grade_build`, `grade_snapshots`, `grade_review_catch`. SIMPLICITY[shrink]: the three candidate-path searches (`load_task` fixture `:337`, manifest `:407`, `resolve_pr_fixture` `:436`) can share one `first_existing(candidates, pred)` helper. net: -40 lines possible.

---

## Cross-Model Dissent (Phase 2.5)

Two voices (gpt-5.5-pro via codex-headless; companion claude-headless), 7 findings, `rejected_count` 0, consensus. Triage:

| ID | Dissent severity | Reviewer disposition |
|----|------------------|----------------------|
| DISS-001 envelope_texts ignores `anchor_line` | BLOCKING | Confirmed against the real envelope → Changes Required §3 |
| DISS-002 all_pass ignores rc / timed_out | BLOCKING | Valid but narrow (TAP streaming or atexit hang) → Observation §3 (MEDIUM) |
| DISS-C-001 `-I`/`-P` vs seeder proof argv | BLOCKING | Valid divergence; `--self-check reference` catches it before freeze → Observation §4 (MEDIUM) |
| DISS-C-002 terminal parse forgeable | ADVISORY | Observation §5 |
| DISS-C-003 structural dest under test_command dir | ADVISORY | Observation §8 (LOW) |
| DISS-C-004 orphaned containers on timeout | ADVISORY | Observation §8 (LOW) |
| DISS-C-005 allowed_roots ignores init cwds | ADVISORY | Observation §6 (MEDIUM) |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Notes |
|------|--------|-------|
| Task 1.1: the change in `pr/head.diff` | Reviewed, changes required | Four high findings above |

---

## Next Steps

1. Fix the four Changes Required items (tarfile portability, overlay-only hidden scoring, envelope `anchor_line` parsing, portable bats resolution).
2. Update the AG-8 fixture envelopes to the production shape and add a case with agent-added tests asserting they are not counted.
3. Re-run `evals/tests/ablation-grade.bats`, `seed-bugfix.bats`, `seed-refactor.bats`, `seed-corpus.bats`, `validate-suite.bats` on a host without the dotfiles checkout, then request re-review.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T05:04:26Z"} -->
