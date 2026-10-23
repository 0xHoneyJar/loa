# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff (16 files: `evals/harness/ablation-grade.sh` (new, 1299 lines), `evals/harness/lib/seed_tasks.py` (new), `evals/harness/seed-bugfix-tasks.sh` / `seed-refactor-tasks.sh` (new wrappers), `evals/harness/seed-corpus-from-record.sh` (bd-8o5rx generated-path exclusion), `evals/harness/validate-suite.sh` (source.churn), four new/changed bats files, docker-stub, two review-prs manifests + SHA256SUMS)

---

## Overall Assessment

The grader is carefully designed: path validation (`safe_rel`), overlay/protected restore with symlinked-parent replacement, `--network none --read-only` containers, no shell, no `.claude/` sourcing, ids-only grade.json, byte-identical regrades. The seeders are stdlib-only, argv-only git, build-in-staging-then-move, with a red/green proof before anything lands. The `seed-corpus-from-record.sh` generated-path rule matches the regenerated manifests (0 generated fix regions remain in pr-14/pr-15; SHA256SUMS recomputed and verified against the head files). The `validate-suite.sh` churn schema and its VS-11 test are correct.

The change cannot merge as is. Six high findings, all reproduced against the head files in this workspace or the live dissent envelope:

1. The contamination scanner's `outside_path` rule treats any quoted `/word` in a Bash command as a filesystem path, so `grep -rn "/review-sprint"` or `grep "/health"` marks an honest run contaminated.
2. `extract_snapshot` uses the Python 3.12 `tarfile` filter API; on this workspace's Python 3.11.2 every gated run exits 2 with "internal error" and no grade.json.
3. `remove_path`'s chmod pre-pass follows symlinks, so an agent-planted symlink in the sandbox changes the mode of a host directory outside `<run-dir>/grading/` on the next regrade (confirmed: target 0755 → 0700).
4. `envelope_texts` never reads `anchor_line`, the field the dissent envelope actually carries, so adversarial findings never reach `gates-combined.md` (confirmed against the envelope this review produced).
5. `all_pass` ignores the exit status, so an interrupted pytest run with a clean partial summary grades as fully passing.
6. `ablation-grade.bats` hardcodes one developer's `~/.local/dotfiles/.../bats`; on this host (bats in `/usr/local/bin`) AG-2 and AG-7 fail.

Scope note: the PR title promises "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze"; the diff contains no file under `grimoires/` and no MANIFEST.sha256, so that part of the sprint could not be reviewed here (see Observation 4).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Contamination scan — false positives on ordinary Bash strings

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:976-983` — every quoted absolute-looking word in a Bash command is a path candidate; anything outside the allowed roots is `outside_path`, so an honest run is graded `contaminated`.
**File:** `head/evals/harness/ablation-grade.sh:940` (ABS_WORD), `:976-983` (candidate loop), `:978` (the one-component exemption requires a trailing slash)
**Issue:** Reproduced with the head file's own `check_value`: `grep -rn "/review-sprint" pr/head/.claude` → `outside_path`; `grep -n '/implement' pr/head.diff` → `outside_path`; `echo "run /plan then /build"` → `outside_path`; `grep -rn "/health" src`, `grep -n "/api/v1/users" app.py`, `sed -i 's|/old/path|/new/path|' cfg`, and a heredoc containing `{"path": "/api/v1"}` all → `outside_path`. The review-catch PRs are Loa changes full of `/plan`, `/implement`, `/review-sprint`; a reviewer grepping for a command name is marked contaminated.
**Why This Matters:** `contaminated` is a run-level verdict (D-4.7/DEC-0493) joined into runs.jsonl; a false positive discards or taints an honest run, and the header (`:118-125`) describes the scan as a lower bound on leakage, not as something that over-reports.
**Required Fix:** Treat a Bash word as a path only when its first component is a real top-level directory of the execution root (`os.listdir("/")` of the image, or the fixed set the roots already name) or when the word has at least two components and exists in the tree; drop the trailing-slash requirement in the one-component exemption (`/word` alone is a slash-command or a route, not a path); add the reproduced inputs to AG-11 as clean cases.

### 2. Python floor — snapshot extraction crashes on Python < 3.11.4

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:705-714` — `tarfile.data_filter`, `tarfile.FilterError` and `extractall(filter=…)` exist only on 3.12+ (and the 3.8.17/3.9.17/3.10.12/3.11.4 backports); on this workspace's `/usr/bin/python3` (3.11.2) the call raises `TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'`, caught by the generic handler at `:1290` → "internal error", exit 2, no grade.json.
**File:** `head/evals/harness/ablation-grade.sh:710-714`; also `:492` (`python3 -P` is 3.11+ for host mode)
**Issue:** Reproduced here: `python3 -c "import tarfile; print(hasattr(tarfile,'data_filter'))"` → `False`; `extractall(..., filter=…)` → TypeError. `extract_snapshot` runs for every run with a REVIEW/AUDIT verdict and an IMPLEMENT/FIX1 bundle (`:1115-1120`), i.e. every gated arm, so exactly the runs that carry the per-gate verdict-accuracy metric fail, and a run without snapshots grades fine — hard to diagnose. The dissent's DISS-C-006 reached the same conclusion independently.
**Why This Matters:** The grader is the measurement instrument of the ablation; it must either run on the operator's interpreter or refuse clearly. An opaque exit 2 on half the runs is neither.
**Required Fix:** Either declare the floor once (`sys.version_info >= (3, 12)` check → a clear `GradeError` naming it, header line) or guard: `if hasattr(tarfile, "data_filter"): extractall(filter=keep) else:` walk members, apply `safe_rel` + reject non-regular/non-dir/non-symlink members and absolute/escaping link targets, and extract one by one. Apply the same floor statement to `-P` (`:492`), or drop `-P` on hosts below 3.11.

### 3. `remove_path` follows symlinks when chmod-ing — writes outside the run directory

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:239-244` — the chmod pre-pass walks with `followlinks=False` (symlinked directories are still listed in `ds`) and calls `os.chmod(…, 0o700)` on each, which follows the link, so a symlink to a directory inside the tree being removed changes the mode of its target anywhere on the host.
**File:** `head/evals/harness/ablation-grade.sh:239-244`; reached via `fresh_dir(grading)` `:1040-1041`, `put_file` `:305-306`, `prepare` `:672`
**Issue:** `copy_tree` deliberately preserves sandbox symlinks into `grading/final` (`:282-283`, `:293-294`), so an agent that leaves `evil -> ../../..` or `evil -> /home/<user>/some-dir` in its sandbox gets it copied; the next grade of the same run dir (ablation-row re-run, or `--self-check noisy`, which grades twice) calls `fresh_dir(grading)` → `remove_path` → chmod on the target. Reproduced with the head file's `remove_path`: a sibling directory at 0755 became 0700 while the tree was removed. `shutil.rmtree` itself is symlink-safe; only the pre-pass is not. Dissent DISS-C-001 (companion voice) raised this.
**Why This Matters:** The header contract (`:38-40`) is "writes only `<run-dir>/grading/` and the `--out` file" and the sandbox is explicitly tamperable. A world-readable shared directory losing group/other access, or a read-only suite root gaining write bits, is a host side effect driven by agent content. CWE-59 (improper link resolution before file access).
**Required Fix:** Skip links in the pre-pass: `if not os.path.islink(path): os.chmod(path, 0o700)`; or use `os.chmod(..., follow_symlinks=False)` where supported and otherwise skip; or drop the pre-pass and use `shutil.rmtree(p, onexc=…)` that chmods only the failing non-link entry. Add a test with a symlinked directory in the sandbox and assert the target's mode is unchanged after two grades.

### 4. Review-catch envelope reduction drops the dissent's findings

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:859-867` — `envelope_texts` emits `anchor` (a `path:symbol` string) and `file:line` only when a finding carries `file`/`path` with `line`/`line_start`/`start_line`; the envelope schema (cycle-131 FR-4) carries `anchor` + `anchor_line` + `anchor_line_end`, so no `path:line` is produced and `citations()` finds nothing.
**File:** `head/evals/harness/ablation-grade.sh:862-867`; header promise at `:96-97`
**Issue:** The envelope this very review produced has finding keys `anchor, anchor_line, anchor_line_end, …` and no `file`/`line`. Fed to the head file's `envelope_texts`, `{"anchor":"lib/x.sh:handle","anchor_line":42}` yields `['lib/x.sh:handle']` and zero citations. AG-8 passes only because its fixture envelopes use `anchor: "lib/x.sh:20"` (a numeric anchor, `:402`) and `file`+`line` (`:403`) — shapes the real producer does not write. Dissent DISS-001 raised this.
**Why This Matters:** DEC-0420's arm-neutral reduction is supposed to include the dissent's findings; dropping them lowers `defects_caught`/recall for exactly the arms whose gates run the dissent, biasing the ablation against them.
**Required Fix:** When `anchor_line` is an int, split `anchor` on the first `:` (path before it; `anchor_type`-aware) and emit `f"{path}:{anchor_line}"` (or `path:anchor_line-anchor_line_end`); keep the existing fallbacks. Change AG-8's envelope fixtures to the real shape (`anchor` as `path:symbol`, `anchor_line`), so the test fails on the current code.

### 5. `all_pass` ignores the exit status and the timeout flag

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:652-653` — `passed >= total and not bad and not parse_error` is true for a suite whose process exited non-zero (or timed out) as long as a parseable summary was printed, so an interrupted run counts as fully passing.
**File:** `head/evals/harness/ablation-grade.sh:652-653`; consumers `:1105`, `:1129`, `:1216`, `:1224`
**Issue:** Reproduced with the head file's `parse_pytest` on `PASSED tests/t.py::test_a[1] / !!! KeyboardInterrupt !!! / 1 passed in 0.05s` with rc=2: `all_pass` → True. Code under test (agent-controlled) that raises `KeyboardInterrupt` after the first parametrized case stops pytest with a clean partial summary; the static-count floor (`count_cases`, `:429-430`) counts `def test` functions, not parametrized cases, so the floor does not catch it. Dissent DISS-002 raised this.
**Why This Matters:** `verdict_accuracy_per_gate` and the reference self-check (`:1224`) are computed from `all_pass`; a false "all pass" marks a wrong APPROVED as accurate.
**Required Fix:** `all_pass` must also require `res["rc"] == 0 and not res["timed_out"]`; record `rc` in `hidden_tests`. Add a test with a suite that exits non-zero after a clean partial summary.

### 6. Test suite depends on one developer's dotfiles path

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"`; `make_bin` symlinks it into the stub image PATH (`:48`, PATH at `:51` is `$T/bin:/usr/bin:/bin`), so wherever bats is not under `/usr/bin` or `/bin` the link dangles and the stub's `bats --tap tests` is rc 127.
**File:** `head/evals/tests/ablation-grade.bats:16`, `:48`, `:51`
**Issue:** On this host bats is `/usr/local/bin/bats` (the bats-core default) and the dotfiles path does not exist; AG-2's bf-sh assertions (`:268-269`, `2/3`, `t1`) and AG-7's (`:352`, `3/3 false`) then fail because the run is a parse-error with 0 passed. The seeders solve the same problem with `LOA_SEED_BATS` (`seed-bugfix-tasks.sh:51`).
**Why This Matters:** This file is the only evidence that the grader's TAP path works; a suite that passes only on the author's machine is not evidence, and the eval CI runs these bats files.
**Required Fix:** `BATS_BIN="${LOA_SEED_BATS:-$(command -v bats)}"` and `skip "bats not on PATH"` when empty; the same for `/usr/bin/python3` at `:46` (`command -v python3`).

---

## Observations

### 1. Contamination and grading semantics (non-blocking)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:964` — `"hidden" in low` is a substring test over every scanned field: `grep -rn hidden_size model.py` → `hidden`, a Grep pattern `Hidden` → `hidden`. DEC-0493 names the pattern, but the review-prs fixtures and this PR's own harness text contain the word in ordinary places; a reviewer grepping the PR for it is marked contaminated. Use a word-boundary match and restrict to path-shaped fields; say the FP risk in the header.
- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:482-493`, `:546-594` — (dissent DISS-C-002) pytest runs inside the graded tree with `--rootdir /workspace`, so a conftest.py / ini / `pytest_plugins` the agent added at an unprotected path is loaded, and the parser trusts terminal output (a `pytest_sessionfinish` hook printing `999 passed in 0.1s` plus `os._exit(0)` grades 999/999). `grader_protected` is the only defence and depends on the author guessing every path. Consider `--noconftest` plus `-c <protected ini or /dev/null>` and `-p no:…` for the hidden run (protected conftest re-injected via `-p`/`PYTHONPATH`), or at least `rc == 0` gating (Change 5) and a note in the header that output is trusted.
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:506-521` — (dissent DISS-C-003) `timeout 120` is used without `-k`, and on the outer `TimeoutExpired` Python kills only the direct child: in container mode the docker CLI, not the container, which keeps running with the grading tree bind-mounted rw; in host mode `env`/`timeout` dies and the orphaned pytest keeps writing into `grading/<label>` while later steps and the `finally` cleanup run. Use `timeout -k 10 120`, `--name` + `docker kill` on TimeoutExpired, or `--stop-timeout`.
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1214`, `:1222` — (dissent DISS-C-005) `--self-check base` passes on `passed < total` alone; with `parse_error: true` (pytest missing in the image, `-P` unsupported, a mount path with `:`) `passed=0 < total` → PASS with nothing executed. Require `not parse_error` (and rc semantics) in the base branch for build and refactor.
- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1099-1105` — for refactor tasks the hidden run (`run_suite(final, t.test_command)`) also collects the structural check whenever its manifest `dest` lies under the test command's path (e.g. `tests/structural/test_x.py` with `pytest tests`), making `hidden_tests` red at base by design and `suite_green_base` false, so a correctly authored task fails `--self-check base`. Nothing validates the constraint; the seeder's `todo` line (`head/evals/harness/lib/seed_tasks.py:613`) tells authors where the source goes but not where the dest may land. Validate in `validate-suite.sh` or state it in both headers.

### 2. Complexity (SIMPLICITY)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1045-1142`, `:319-419` — SIMPLICITY[shrink]: `grade()` is ~100 lines (verdict extraction, tree build, churn, regression, structural, snapshot, accuracy and review-catch branches interleaved) and `load_task()` ~103 lines; `parse_pytest` 54, `main` 59. Over the 50-line threshold without justification. Split `grade()` into `grade_build()`, `grade_review_catch()`, `gate_accuracy()`; `load_task()` into `load_overlay()` / `load_review_catch()`. Lean otherwise; net: 0 lines, readability only.

### 3. Seeders (LOW)

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198`, `:213` — the pytest proof parses the LAST line of `stdout + stderr`; any trailing stderr line (a plugin warning, `PytestCacheWarning`) becomes the tail and yields 0 passed / 0 failed → a spurious `not red at base` / `not green at reference`. Scan for the last line matching a summary regex, as the grader does (`ablation-grade.sh:549-553`).
- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:227` — `patch -s -p1 … -i` without `--batch --forward`: an already-applied or reversed hunk makes `patch` prompt on inherited stdin and the seeder hangs in a terminal. Mirror the grader (`ablation-grade.sh:1175`).

### 4. Scope and report

- **MEDIUM** (confidence: high) `pr/PR.md:1-3` vs the file list — the description claims sixteen frozen tasks under `grimoires/loa/evals/ablation-2.0/tasks/` and "the freeze"; the change holds no `grimoires/` file and no `MANIFEST.sha256`. The task content (synthetic planted defects, structural checks, TASK.md leak-scans) and the freeze are therefore unreviewed here, and the report carries no `## AC Verification` walkthrough. If the tasks travel in another change, say so in the description; otherwise they are missing from this one.

### 5. Minor

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:794-798` — the inherited 1.1.2 citation regex matches version-like tokens: `version 1.2.3:4` → citation `('1.2.3', 4)` (reproduced), counted by `false_positives()` as a stray region. Shared with recall-vs-defects.sh; note it as a known FP source.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:764-779`, `:1057-1060` — (dissent DISS-C-004) `gate_verdict` returns the string `"none"` for a trailer-less file, so `verdict.value` can be `"none"` and an audit file without a trailer masks a valid review verdict; the header (`:106-107`) documents only `APPROVED | CHANGES_REQUIRED | null`. Map `"none"` to `null` in `verdict`, or document the third value.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1053` vs `:1074` — `fresh_dir(grading)` wipes the previous grading tree before `docker_ready()`; a missing image leaves the run dir without its prior grading output. Check docker first.
- **LOW** (confidence: medium) `head/evals/tests/validate-suite.bats:32-44` — VS-1 now derives `n` and `short` from the same tree the validator reads, so it cannot catch a validator that miscounts the same way; adaptive by design, but a fixed-expectation case on a synthetic suite is the stronger test (VS-2 covers part).
- **LOW** (confidence: high) `head/evals/tests/ablation-grade.bats:46` — `/usr/bin/python3` hardcoded in the image stand-in; `command -v python3`.

### Verified clean

- `head/evals/fixtures/review-prs/SHA256SUMS` matches the head manifests (sha256 recomputed); 0 generated-path fix regions remain in pr-14/pr-15; defect labels untouched.
- `head/evals/harness/seed-corpus-from-record.sh:202-213`, `:235-236`, `:709-713` — the exclusion fires only on `fix` rows / fix hunks, prints each path once, and SC-7/SC-8 assert both the manifest and the stderr lines.
- `head/evals/harness/validate-suite.sh:218-224` — churn schema rejects bools, negatives, missing keys and non-mappings; VS-11 covers each.
- `head/evals/tests/fixtures/docker-stub.sh:76-79` — PATH injection only when no `-e PATH` was given.
- All shell files pass `bash -n`; `seed_tasks.py` and the grader heredoc compile.

---

## Adversarial dissent (Phase 2.5)

`adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff` → `status: reviewed`, primary gpt-5.5-pro, companion claude-headless `succeeded`, `counted_as: independent_voice`. Eight findings: DISS-001, DISS-002, DISS-C-001 (BLOCKING) are confirmed and counted above as Changes 4, 5, 3; DISS-C-006 (ADVISORY) duplicates Change 2; DISS-C-002/003/004/005 (ADVISORY) are confirmed and recorded under Observations. The dissent's input was truncated (5 of 16 files fit the token budget; `validate-suite.sh` partially), so the seeders and tests were reviewed by this voice alone.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds 0 rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Changes required | Six high findings above; the sixteen frozen tasks and MANIFEST.sha256 named in the description are not in the change |

---

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":6,"medium":7,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:25:00Z"} -->
