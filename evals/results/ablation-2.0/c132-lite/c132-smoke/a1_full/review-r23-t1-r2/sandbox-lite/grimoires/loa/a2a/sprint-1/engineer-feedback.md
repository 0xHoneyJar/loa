# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, 1,299 lines of bash-wrapped Python), two task seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh` over `lib/seed_tasks.py`), the `source.churn` schema in `validate-suite.sh`, the bd-8o5rx generated-path exclusion in `seed-corpus-from-record.sh` with regenerated `pr-14`/`pr-15` manifests, a `DOCKER_STUB_PATH` hook in the docker stub, and bats suites for all of it.

What is good: the grader's trust model is careful (sandbox never written, `meta/` never read, `safe_rel` on every manifest path, snapshots extracted through a bare scratch repo, ids-only summaries), the seeders stage in a private directory and prove red/green before moving a task into place, the manifest checksums in `SHA256SUMS` match the regenerated files byte for byte, and the test suites are broad.

What blocks the merge: four reproduced defects. The grader cannot grade any run that carries a gate snapshot on Python 3.11.2 (`TarFile.extractall()` has no `filter` argument there; the script declares no minimum version). The bug-fix seeder breaks after its first failed candidate (the staging directory is never cleaned, so the next candidate dies with `File exists`). The seeder's `git apply` fallback silently skips every hunk when the proof tree sits inside a git checkout (this sandbox's `TMPDIR` does), so every clean fix is reported as "not green at reference". And the grader's bats suite hard-wires a personal dotfiles path for the bats binary, so it fails on any other machine. All four were reproduced on this host with throwaway fixtures (evidence inline).

The cross-model dissent (two voices: codex-headless and claude-headless, consensus, nine advisory findings, zero rejected payloads) added four points I verified and adopted as medium observations, notably that dissent-envelope anchors (`path:symbol` plus `anchor_line`) are never turned into citations, so review-catch recall undercounts every finding the dissent produced.

Tests could not be executed as written: the repository tree the bats files run against (`evals/harness/freeze.sh`, `recall-vs-defects.sh`, `lib/sandbox-mount.sh`, the suite file, the smoke tasks) is not part of this workspace. The grader and the seeder library were exercised directly instead.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability — the grader depends on a Python 3.12 API with no version guard

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:714` — `tf.extractall(tree, filter=keep)` raises `TypeError` on any Python before 3.12 (3.11.4+ has the backport; Debian 12's 3.11.2, this host, does not), and `tarfile.data_filter` at line 710 does not exist there either.
**File:** `head/evals/harness/ablation-grade.sh:710-714`
**Issue:** `extract_snapshot` is reached whenever a run has a REVIEW or AUDIT verdict (`gates` non-empty at lines 1110-1113). On this host the grade aborts through the generic handler at line 1290:

```
$ bash ablation-grade.sh run2 bf --suite-root suite --allow-unfrozen --executor host
ablation-grade: internal error: TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'
exit=2            # no grade.json written
```

A run without snapshots grades fine on the same host (`graded bf: hidden 1/2 …`), so the failure is silent until the first gated run. The dissent's DISS-C-002 is the same class: `python3 -P` (line 492, host mode) is a 3.11+ flag; on 3.10 it exits 2 with `Unknown option`, which `run_suite` records as a plausible all-fail grade (`parse_error: true`), not as a tool error.
**Why This Matters:** the grader runs on the operator host's `python3` (line 166), not in the image. Every gated run on a stock Debian 12 or Ubuntu 22.04 host either aborts (3.11.2) or writes a wrong grade (3.10). Nothing in the header, `--help` or the tests names a minimum version.
**Required Fix:** check `sys.version_info` once at startup and raise `GradeError("python >= 3.12 required …")`, or drop the `filter=` dependency (iterate members, apply `safe_rel` + a manual absolute/`..`/symlink-escape check, extract one by one). Document the minimum version in the header. Add a bats case that runs the grader on a run with an `IMPLEMENT.bundle`.

### 2. Seeder — a failed candidate poisons every later candidate

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:598-602` — after `build_bugfix`/`build_refactor` returns `None` (proof failed) the staged `stage/<tid>/` is left on disk and `taken.discard(tid)` releases the id, so the next candidate gets the same `tid` and `os.makedirs(fx)` at line 373 (line 450 for refactor) raises `FileExistsError`, reported as `proof-failed … [Errno 17] File exists`.
**File:** `head/evals/harness/lib/seed_tasks.py:586-602`
**Issue:** reproduced with two fix commits, the newer one a genuine proof failure, the older one the clean SB-1 fix:

```
proof-failed 0797b806dde5: not red at base (exit 1, 0 failed, 0 passed)
proof-failed d14099157d2e: [Errno 17] File exists: '/tmp/seed-stage.ho6vw307/bugfix-01/fixture'
seed-bugfix: 2 candidate(s), 0 refused, 0 skipped; selected 2, written 0, proof failed 2
```

The same happens after a `"skip"` or `"secret"` return (lines 588-597): the directory stays, the id is reused. The bats suites never place a failing candidate before a passing one (SB-4 and SR-3 each have exactly one selected candidate), so the gap is uncovered.
**Why This Matters:** `--select 4` over real history will routinely hit a proof failure first (the header itself says "a failed proof does" count); from that point on the seeder materialises nothing and misreports healthy commits as proof failures with an `OSError` message.
**Required Fix:** remove `os.path.join(stage, tid)` (`shutil.rmtree(..., ignore_errors=True)`) in every non-written branch before `continue`, or stage each candidate in its own `tempfile.mkdtemp(dir=stage)`. Add a test with a failing candidate followed by a clean one.

### 3. Seeder — the `git apply` fallback silently applies nothing inside a repository

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:229` — without GNU `patch` on `PATH` the proof uses `git apply -p1 <patch>` with `cwd=tree`; when `tree` lies inside any git working tree, `git apply` resolves patch paths against that repository's root, prints `Skipped patch '…'` and exits 0, so `apply_patch` returns `True` on an unpatched tree.
**File:** `head/evals/harness/lib/seed_tasks.py:225-230` (the proof trees come from `tempfile.mkdtemp` at lines 400 and 467, i.e. `$TMPDIR`)
**Issue:** this sandbox has no `patch` and `TMPDIR=/workspace/.eval/tmp` (inside the checkout). The clean SB-1 fixture then fails its proof with a misleading reason, and the direct reproduction shows why:

```
proof-failed d14099157d2e: not green at reference (exit 1, 2 failed, 1 passed)

$ cd /workspace/.eval/tmp/tmp.X/ref && git apply -v -p1 ref.patch
Skipped patch 'tools/mathx/rounding.py'.
rc=0
```

With `TMPDIR=/tmp` the identical command writes `bugfix-01` and prints `proof bugfix-01 …: red 2 failed / green 3 passed`.
**Why This Matters:** any host without `patch` (slim CI images, this evaluation sandbox) plus a temp dir under a checkout (a very common CI layout) makes both seeders refuse every candidate with exit 1 and a wrong diagnosis. The grader's own `synth_run` (line 1175) hard-requires `patch`, so the two tools already disagree on the dependency.
**Required Fix:** either require `patch` (check it in the wrapper's tool loop at `seed-bugfix-tasks.sh:75` / `seed-refactor-tasks.sh:64` and drop the fallback), or make the fallback safe: `git init -q` a throwaway repository in `tree` before `git apply` (so paths resolve against the tree), and in both paths verify that at least one patched file actually changed, treating `Skipped patch` as failure.

### 4. Tests — the grader suite hard-wires a personal dotfiles path for bats

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is one developer's dotfiles checkout; line 48 symlinks it into the stub image's `PATH`. On any other machine (this host included: the directory does not exist) the symlink dangles and every bats-based case fails (`AG-2` second half, `AG-7` `bf-sh`, and any task whose `test_command` is `bats`).
**File:** `head/evals/tests/ablation-grade.bats:16`, `:48`
**Issue:** the header (lines 9-11) promises "`bats` is the operator's bats-core", but the code pins a path rather than resolving the operator's binary.
**Why This Matters:** the suite is the only check on the grader's TAP path and on the bats-shaped container argv (`timeout 120 bats --tap tests`, asserted at line 353). As committed it cannot pass in CI or for the other implementers, so the TAP path is effectively untested.
**Required Fix:** `BATS_BIN="$(command -v bats)"` (bats is already running the file, so `$BATS_ROOT/bin/bats` or `command -v bats` is always available), and `skip` the bats-shaped cases if resolution fails.

---

## Observations

Non-blocking. Medium and low findings, including the dissent's advisory findings that survived verification (marked "dissent").

### 1. Seeder proof parsing and candidate selection

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:196-198` — `counts()` reads the LAST line of `stdout + stderr` (line 213). Any stderr line emitted after pytest's summary (a `pytest_sessionfinish` hook, a plugin warning) yields 0/0 and a spurious proof failure. Reproduced with a two-line conftest hook: `proof-failed …: not red at base (exit 1, 0 failed, 0 passed)`.
**Suggestion:** parse stdout only and locate the summary line by regex over all lines (the grader's `SUMMARY_RX` at `ablation-grade.sh:528` already does this); better, share the parser.

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:350` — `covering_tests` treats a touched module's stem as a bare word anywhere in any test file under the roots. Stems such as `left`, `util`, `config` match prose and comments; the matched test is pulled into the fixture and `test_command` without its own siblings, so the proof fails at base. Reproduced: an unrelated `tools/other/tests/test_other.py` containing the comment "nothing left-pads here" turned the SR-1 refactor into `proof-failed …: suite not green at base (exit 2, 1 failed, 0 passed)`; without that file the same commit seeds cleanly.
**Suggestion:** match import statements or path fragments (`from left import`, `import left`, `left.py`, `tools/fmt/left`) rather than bare words, and prefer tests whose directory shares an ancestor with the touched source.

- **LOW** (confidence: high) `head/evals/harness/lib/seed_tasks.py:570` — `selected = cands[:a.select]` is fixed before building, so a `"skip"` (no covering test) or `"secret"` refusal inside `build_refactor` consumes a `--select` slot; `seed-refactor-tasks.sh:37-38` says such a commit "does not count". Fewer than N tasks are written although later candidates qualify.

- **LOW** (confidence: high) `head/evals/harness/lib/seed_tasks.py:502-506` — any non-zero exit of the no-secrets scanner (script missing, `bash` error, exit 127) is reported as `refused …: a secret pattern in the materialised task`. Fail-closed is right; the message is wrong. Distinguish exit 1 (hit) from other codes (tool error → exit 2).

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:25` — `^(fix|bug)` also matches subjects starting `fixture…`/`fixed-point…`/`bugbear…`; the refactor set matches every `chore(release): …`. Anchor on the conventional-commit type: `^(fix|bug)(\(|!|:)`.

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:51-54` — `_git_env` keeps `HOME` and sets only `GIT_CONFIG_NOSYSTEM`, so the user's `~/.gitconfig` applies to every parsed call: `log.showSignature=true` injects `gpg:` lines into the `%x1e`-separated log stream, `diff.context`/`diff.algorithm` reshape `reference.patch`. Add `GIT_CONFIG_GLOBAL=/dev/null` as the grader does (`ablation-grade.sh:679`).

### 2. Grader semantics

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1126-1130` — for refactor tasks `verdict_accuracy_per_gate` judges the gate's snapshot with `all_pass(test_command)` only; the structural check (lines 1099-1106) is never consulted. A review that APPROVES an untouched tree (suite green, structural red) is scored accurate, while the self-check (lines 1209-1216) defines refactor success as structural green AND suite green. Align the two: a refactor snapshot "passes" when the structural check and the suite both pass.

- **MEDIUM** (confidence: high, dissent DISS-001) `head/evals/harness/ablation-grade.sh:862-867` — `envelope_texts` forwards each finding's `anchor` and reads `line`/`line_start`/`start_line`, but the dissent envelopes written by `adversarial-review.sh` carry `anchor` as `path:symbol` and the line in `anchor_line`/`anchor_line_end` (verified on the envelope this review produced: `{"anchor":"…/ablation-grade.sh:envelope_texts","anchor_line":864}`). `citations()` cannot parse `path:symbol` (checked: zero matches), and `anchor_line` is never read, so dissent findings contribute no citation and review-catch recall undercounts every arm with dissent. Header line 96 claims otherwise.
**Suggestion:** read `anchor_line`/`anchor_line_end`, take the file component of `anchor` (everything before the last `:`), emit `file:line[-end]`.

- **MEDIUM** (confidence: medium, dissent DISS-C-001) `head/evals/harness/ablation-grade.sh:492-493` — the shaped argv (`-I -s` in the image, `-P` on the host) removes the cwd entry that plain `python3 -m pytest` prepends to `sys.path`, while both seeders prove with plain `python3 -m pytest` (`seed_tasks.py:201-208`). A test importing a repo-root package without a conftest `sys.path` insert passes the proof and fails under the grader for every arm, including the reference patch. Either prove with the grader's shaped argv or keep the tree on `sys.path` (`-e PYTHONPATH=/workspace`).

- **MEDIUM** (confidence: medium, dissent DISS-C-003) `head/evals/harness/ablation-grade.sh:517-524` — `exec_in_tree` returns the docker client's own failures (125 daemon/mount, 126, 127 e.g. no `timeout` in the image) as a test result; `run_suite` then records `passed 0, total = static, parse_error: true`, a plausible all-fail grade joined into `runs.jsonl`, where the header promises exit 2 for "a tool failure". `docker_ready()` checks the image exists, not that the mount/user/`timeout` combination works. Treat rc in {125,126,127} with no parseable summary as `GradeError`, or smoke-run `timeout 1 true` in `docker_ready()`.

- **MEDIUM** (confidence: high, dissent DISS-C-005) `head/evals/harness/ablation-grade.sh:296` — `copy_tree` handles FIFOs, sockets and symlinks but not an unreadable regular file; `shutil.copyfile` raises `PermissionError`, uncaught, and the grade aborts. Reproduced: one `chmod 000` file in the sandbox → `ablation-grade: internal error: PermissionError … exit=2`, no `grade.json`. The graded agent controls the sandbox, so a single mode-000 residue (common in permission tests) denies the run its grade. Catch `OSError` per file (skip and count), or `chmod u+r` first.

- **LOW** (confidence: medium, dissent DISS-002) `head/evals/harness/ablation-grade.sh:653` — `all_pass` ignores `rc` and `timed_out` once a summary parsed; a runner that reports `1..1 / ok 1` and then exits non-zero (teardown failure, timeout after the plan) is "fully passing".

- **LOW** (confidence: medium, dissent DISS-C-006) `head/evals/harness/ablation-grade.sh:561-571` — `OUTCOME_RX` runs over every output line, and `-rA` prints captured output sections; a captured line beginning `FAILED …`/`ERROR …` becomes an outcome, and an `ERROR word` without `::` is treated as a collection error, decrementing `total` at line 589. Restrict the scan to the `short test summary info` section.

- **LOW** (confidence: medium, dissent DISS-C-004) `head/evals/harness/ablation-grade.sh:520-521` — on the outer `subprocess` timeout only the `docker run` client dies; the container keeps the grading tree bind-mounted rw until its inner `timeout` fires or forever if it ignored SIGTERM. Pass `--name` and `docker kill` it on `TimeoutExpired`.

- **LOW** (confidence: medium, dissent DISS-C-007) `head/evals/harness/ablation-grade.sh:948-954` — the contamination root set follows the grader's `--executor`, not how the run executed; grading a host-executed run in (default) container mode whitelists all of `/home/evaluser`, so reads of sibling run dirs or the run's own `eval/` envelopes are never `outside_path`. Derive the model from the transcripts' init cwd instead.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:617-621` — TAP results are keyed by description; two bats tests with the same description collide in `names`/`bad`, so `failed_names` and positions are wrong for that file. Key by test number and map to the description only for display.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:964-965` — `"hidden" in low` flags any Bash command containing the substring (`ls -a .hidden_cache`, `grep -i hidden docs/`). Documented as a lower bound, but these are false positives, not misses; consider a word boundary plus the known hidden paths.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1175` — `--self-check reference` calls `patch` directly; with no `patch` binary the `FileNotFoundError` surfaces as `internal error`, not as a usage message, and `patch` is listed nowhere as a dependency (the seeder falls back, see Changes Required 3).

### 3. seed-corpus and the implementation report

- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:232-236` — the `head/<file> missing` error (line 232) is raised before the generated-path exclusion (line 235), so a `fix` row for a generated artefact that is not in `head/` fails the manifest build although the row would be dropped anyway. Move the exclusion above the file check.

- **MEDIUM** (confidence: high) `pr/PR.md` vs `pr/head.diff` — the title and the first commit claim "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze"; the diff contains neither a task directory nor a `MANIFEST.sha256`, and `reviewer.md` carries no `## AC Verification` section. `head/evals/tests/validate-suite.bats:32-45` (VS-1) now reads the committed suite's `tasks/*/task.yaml`, so its expectations depend on files this change does not deliver. Either the tasks and the freeze belong in this PR, or the description and VS-1 must stop referring to them.

---

## Rejected dissent payloads

None. The envelope `adversarial-review.json` carries `rejected_summary: []`, `rejected_count: 0`, and its sidecar `adversarial-rejected-review.jsonl` holds no rows. Two voices succeeded (codex-headless for the gpt-5.5-pro chain, claude-headless as companion); all nine findings were ADVISORY and are triaged above (five adopted as MEDIUM, four as LOW; DISS-C-002 folded into Changes Required 1).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" (sprint.md) | Done | 4 high, 8 medium, 12 low findings above, each with `head/<path>:<line>` |
| "give a merge verdict" (sprint.md) | Done | CHANGES_REQUIRED |
| Grader grades a run with gate snapshots (header lines 54-57) | Fail | Reproduced `TypeError` on Python 3.11.2 (Changes Required 1) |
| Seeder materialises up to `--select` candidates (header `seed-bugfix-tasks.sh:43-44`) | Fail | Second candidate after a failure dies with `File exists` (Changes Required 2) |
| Seeder proof "red at base, green with the reference patch" (header `seed-bugfix-tasks.sh:30-31`) | Fail | `git apply` fallback skips hunks silently (Changes Required 3) |
| `evals/tests/ablation-grade.bats` exercises the TAP path | Fail | personal `BATS_BIN` path (Changes Required 4) |
| `SHA256SUMS` matches regenerated manifests | Pass | both `pr-14.json` and `pr-15.json` verified byte for byte |
| `source.churn` validated as `{files, insertions, deletions}` non-negative ints | Pass | `validate-suite.sh:218-224`, VS-11 |
| Generated paths never fix regions, printed once each | Pass (static) | `generated_path`/`note_excluded`, SC-7/SC-8; ordering nit in Observations |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (a hard-coded personal path, Changes Required 4, but no secret)
- [x] Input validation at trust boundaries: `safe_rel`/`safe_path` on every manifest and history path, symlinks refused from history, bundle extraction through a scratch bare repo, run-dir path refused with `:`/`,`
- [x] No code sourced or eval'd from variables (AG-13 pins this)
- [x] Container runs `--network none --read-only --user uid:gid` with one rw mount
- [ ] Error paths: agent-controlled sandbox content (a mode-000 file) aborts the grade (Observation 2); docker client failures become grades (Observation 2)
- [x] Error messages leak no hidden-test names or excerpts (ids only; AG-12)

---

## Code Quality Summary

**Strengths:**
- Clear header contracts on every script; the grader's read/write boundary is spelled out and mostly honoured.
- Deterministic `grade.json` (no timestamps, no scratch paths), atomic write.
- The seeders stage privately, prove before publishing, and run the proof under `env -i`.

**Areas for Improvement:**
- Two independent summary parsers (`counts()` in the seeder, `parse_pytest`/`parse_tap` in the grader) with different robustness; share one.
- Undeclared host dependencies: Python 3.12 API, `patch`, `yq`, `timeout` inside the image.
- `SIMPLICITY[shrink]`: `grade()` is 97 lines and `load_task()` 100 lines with nesting over three in places (lines 1073-1131, 319-419); split the build and review-catch branches into functions. Lean otherwise; `net: -0 lines possible` beyond that split.
- `FAST-GATE:` no formatter or lint run is recorded in the report; `bash -n` and `py_compile` pass on every script here, but the bats suites could not be run against this workspace.

---

## Next Steps

1. Fix the four Changes Required (version guard or filter-free extraction; stage cleanup per candidate; `patch` requirement or a safe `git apply`; resolve `bats` from `PATH`).
2. Add the two missing regression cases: a failing candidate followed by a passing one in `seed-bugfix.bats`/`seed-refactor.bats`; a gated run with an `IMPLEMENT.bundle` in `ablation-grade.bats` on the CI Python.
3. Decide where the sixteen tasks and the freeze live, and make `PR.md` / VS-1 agree with the diff.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":8,"low":12},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T09:56:00Z"} -->
