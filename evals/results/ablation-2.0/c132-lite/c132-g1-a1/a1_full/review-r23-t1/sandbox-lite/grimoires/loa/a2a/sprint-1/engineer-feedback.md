# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` (16 files under `evals/`); citations are `head/<path>:<line>` with lines from `pr/head/`.

---

## Overall Assessment

The change adds the cycle-130 ablation grader (`ablation-grade.sh`, 1299 lines), two task seeders over a shared Python engine (`seed_tasks.py`), the generated-path exclusion for fix regions in `seed-corpus-from-record.sh` (with the pr-14/pr-15 manifests and SHA256SUMS regenerated), a `source.churn` schema extension in `validate-suite.sh`, and bats coverage for all of it. The grader's trust-boundary posture is good: no sourcing from variables, `tarfile.data_filter`, path checks on every manifest entry, meta/ never read, ids-only summaries. SHA256SUMS lines match the head manifests byte for byte, every script passes `bash -n` / `py_compile`, and the AG-13 self-greps hold.

The verdict is driven by seven high findings, three of them reproduced by execution here:

- The seeders' staging directory is never cleaned after a failed proof, so one failed candidate makes every later candidate fail with `[Errno 17] File exists` (reproduced for both seeders).
- Without a `patch(1)` binary the seeders fall back to `git apply`, which silently skips every file when the scratch tree sits inside another git work tree (exit 0, "Skipped patch"); the refactor proof then passes against an unpatched tree and a task is written for a behaviour-breaking commit (reproduced: the SR-3 "perf: skip the padding" commit became `refactor-01` with a PASS proof).
- `ablation-grade.bats` hard-codes one developer's `$HOME/.local/dotfiles/...` path as the bats binary.
- Three grader metric defects: refactor `verdict_accuracy` never consults the structural check (two dissent voices concur), the contamination scan flags `"$VAR"/dir` idioms as `outside_path`, and the review-catch reducer ignores the `anchor_line` field live dissent envelopes actually carry.

The implementation report (`reviewer.md`) is the PR description: it describes sixteen tasks under `grimoires/loa/evals/ablation-2.0/tasks/` and a freeze that are not in the diff, and it carries no `## AC Verification` section. Treated as a process observation rather than a counted defect because the sprint definition here is the PR itself.

Seeder bats runs in this environment: SB-3, SB-4, SB-5, SR-2, SR-4 pass; SB-1, SB-2, SR-1, SR-3 fail here because the host has no `patch(1)` (which exposes high finding 3) and because `/tmp` is noexec and the bats temp dir lies inside a git repository (environment, noted under Observations). The grader bats suite needs fixtures outside this diff (smoke tasks, `freeze.sh`, `recall-vs-defects.sh`) and was reviewed by reading only.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Seeder: a failed proof poisons every later candidate (staging collision)

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:373` — after a candidate fails its proof the staging directory `stage/<tid>` is left behind while `taken.discard(tid)` frees the id; the next candidate gets the same id and `os.makedirs(fx)` raises `FileExistsError`, reported as a proof failure.
**File:** `head/evals/harness/lib/seed_tasks.py:373` (bugfix), `head/evals/harness/lib/seed_tasks.py:450` (refactor), `head/evals/harness/lib/seed_tasks.py:598-602` (failure path without cleanup)
**Issue:** `main()` only removes `stage` at the very end (`shutil.rmtree(stage)` at :617). A `proof-failed`, `skip` or `secret` return leaves `stage/bugfix-01/` on disk; `next_id` (:332-339) checks `taken` and `tasks_dir`, not `stage`, so it hands out `bugfix-01` again.
**Why This Matters:** Reproduced here with two candidates in each mode. Newest-first order means one bad fix commit at the top of the window yields `written 0` for the whole run:
```
proof-failed be02fb4d67b8: not red at base (exit 0, 0 failed, 3 passed)
proof-failed 9666b206e19f: [Errno 17] File exists: '.../seed-stage.4f02gpoo/bugfix-01/fixture'
seed-bugfix: 2 candidate(s), 0 refused, 0 skipped; selected 2, written 0, proof failed 2
```
The bats tests never select two candidates where the first fails (SB-4 and SR-3 use a single candidate), so this is uncovered.
**Required Fix:** On every non-success return in the loop (:588-602) `shutil.rmtree(os.path.join(stage, tid), ignore_errors=True)` before `taken.discard(tid)`; or stage each candidate in its own `mkdtemp`. Add a two-candidate test where the newest fails and the older one must still be written.

### 2. Seeder: `git apply` fallback silently applies nothing, so the proof is vacuous

- **HIGH** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:229` — when `patch` is not on PATH the fallback runs `git apply -p1 <patch>` with `cwd=tree`; a git-style patch applied from a directory inside another repository (any `TMPDIR` under a checkout, e.g. this harness's own `.eval/tmp`) is skipped with "Skipped patch '<file>'." and exit 0, so `apply_patch` returns True with the tree unchanged.
**File:** `head/evals/harness/lib/seed_tasks.py:225-230`; the wrappers' tool checks at `head/evals/harness/seed-bugfix-tasks.sh:75` and `head/evals/harness/seed-refactor-tasks.sh:142` require only `git` and `python3`.
**Issue:** The refactor proof (`:473-481`) is "green at base AND green at reference"; with an unpatched reference tree that is trivially true. Reproduced with the SR-3 scenario (the `perf: skip the padding` commit, which breaks `test_left`):
```
proof refactor-01 004bb7d39c9b: green at base (2 passed) / green at reference (2 passed)
wrote .../s2/tasks/refactor-01
```
and the written `hidden/reference.patch` was never shown to apply. For bugfix tasks the same condition turns every candidate into `not green at reference`, which at least fails loudly.
**Why This Matters:** A seeded task with an unverified reference patch and a vacuous proof enters the frozen suite; `ablation-grade.sh --self-check reference` later fails on it (it uses `patch` directly), but only if someone runs it before the freeze.
**Required Fix:** Require `patch` in both wrappers' tool loops, or make the fallback safe: run `git apply` with `GIT_CEILING_DIRECTORIES=$(dirname tree)` (or `--directory`/`--unsafe-paths` as appropriate) and treat "Skipped patch" or an unchanged tree as failure. Independently assert after applying that at least one fixture file changed.

### 3. Grader tests: a hard-coded personal path for the bats binary

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is one developer's dotfiles checkout; `ln -s "$BATS_BIN" "$T/bin/bats"` (`:48`) creates a dangling symlink on every other machine.
**File:** `head/evals/tests/ablation-grade.bats:16`, `head/evals/tests/ablation-grade.bats:48`
**Issue:** The docker stub runs the graded command with `PATH=$T/bin:/usr/bin:/bin`; the bats-TAP paths of AG-2 (bf-sh, expects `2/3` with `failed_names t1`) and AG-7 (expects `3/3 false` and `timeout 120 bats --tap tests`) exec a dangling symlink, get rc 127, and fall into the `parse_error` branch. Both tests fail on CI and on every reviewer's machine.
**Required Fix:** `BATS_BIN="$(command -v bats)"` with `skip` when absent, as the header already promises ("`bats` is the operator's bats-core").

### 4. Seeder: refactor tasks leave the regression oracle editable by the agent

- **HIGH** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:457` — for a refactor task the covering tests are copied into the fixture (`:455-456`) but only conftest/helper files become `grader_protected`; `hidden/manifest.json` is written empty (`:464`), so nothing restores the covering tests at grading time.
**File:** `head/evals/harness/lib/seed_tasks.py:455-457`, `head/evals/harness/lib/seed_tasks.py:464`; locked in by `head/evals/tests/seed-refactor.bats:92` (`grader_protected == [conftest.py]`).
**Issue:** `test_command` is the covering suite and the grader's `suite_green_final` (`ablation-grade.sh:1105`) runs it on the final tree after restoring only `grader_protected` paths. An agent that edits `tools/fmt/tests/test_fmt.py` to `assert True` (or deletes the assertions) grades "suite green" although TASK.md says "the existing suite must stay green without edits". The bugfix seeder avoids this by overlaying the tests from `hidden/`; the refactor seeder does neither. The `todo` line (`:613-614`) tells the lead to author the structural check, not to protect the suite.
**Why This Matters:** `grader_protected` exists exactly for this threat (AG-2 tests "a helper that fakes the fix"). Four of the sixteen suite tasks would carry a tamperable oracle.
**Required Fix:** List every covering test under `grader_protected` (or overlay them from `hidden/tests/` like the bugfix seeder) and update SR-1 accordingly.

### 5. Grader: refactor `verdict_accuracy` ignores the structural check

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1122` — snapshot trees are graded with `run_suite(tree, t.test_command, t.static_cases)` only; `structural_command(t)` runs on `final` alone (`:1100-1101`), so for refactor tasks `all_pass(snap_res[...])` (`:1129-1130`) is the covering suite, which the seeder proves green at base.
**File:** `head/evals/harness/ablation-grade.sh:1122`, `head/evals/harness/ablation-grade.sh:1129-1130`
**Issue:** An IMPLEMENT snapshot where the agent changed nothing is `all_pass` → a REVIEW gate saying `CHANGES_REQUIRED` (correct: the refactor was not done) is scored `false`, `APPROVED` is scored `true`. `t.static_cases` excludes the structural file (`:397`), so nothing pulls it in. Both dissent voices flagged this independently (DISS-002, DISS-C-002 blocking).
**Why This Matters:** `verdict_accuracy` / `verdict_accuracy_per_gate` is the FR-6 metric; for one of four task types it is inverted and biased toward APPROVED across arms.
**Required Fix:** For refactor tasks, grade each snapshot with both `test_command` and `structural_command(t)` and define gate accuracy as "structural green and suite green"; record `structural` per snapshot in `snapshot_tests`. Update the header (`:107-109`) to match.

### 6. Grader: contamination scan flags `"$VAR"/dir` as an outside path

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:940` — `ABS_WORD`'s lookbehind set includes `"` and `'`, so in `cd "$PWD"/tests && pytest` the token `/tests` is taken as an absolute path; it is under none of the allowed roots, so `check_value` (`:976-983`) returns `outside_path` and the whole run is marked contaminated.
**File:** `head/evals/harness/ablation-grade.sh:940`, `head/evals/harness/ablation-grade.sh:976-983`
**Issue:** Verified with the shipped regex: `cd "$PWD"/tests && python3 -m pytest -q` → candidate `/tests` → CONTAMINATED; `bats '$ROOT'/tests` → CONTAMINATED. The `^/[^/]+/$` escape (`:978`) only covers a one-component word with a trailing slash. Quoted-variable path prefixes are routine agent shell. (Dissent DISS-C-001, blocking.)
**Why This Matters:** `contaminated` is a first-class grade field; false positives discount valid runs and do so unequally across arms (the arms differ in how much shell the agent writes), which corrupts the comparison the suite exists for.
**Required Fix:** Do not treat a `/` that directly follows a closing quote (`"`/`'`) or `)`/`}` as the start of an absolute path, e.g. exclude words whose preceding character is a quote when the character before that is not whitespace, or tokenise with `shlex` and test only whole words that start with `/`. Add AG-11 cases for `"$PWD"/x`, `'$T'/x`, `$(cmd)/x`, `${X}/x`.

### 7. Grader: the review-catch reducer ignores `anchor_line`, so dissent findings earn no recall

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:862-867` — `envelope_texts` emits the `anchor` string and a `file|path` + `line|line_start|start_line` pair; real envelopes carry `anchor: "head/<path>:<symbol>"` plus an integer `anchor_line` (and `anchor_line_end`), neither of which this reads.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** Checked against the envelope the dissent wrote for this very review: finding keys are `anchor, anchor_line, anchor_status, anchor_type, …`, e.g. `("head/evals/harness/ablation-grade.sh:envelope_texts", 865)`. `citations()` needs `:digits`, so the symbolic anchor yields nothing and `anchor_line` is never consulted. `adversarial-review.sh:28` and `:608-617` document `anchor_line` as the numeric anchor (cycle-131 FR-4). AG-8 passes only because it fabricates envelopes with numeric anchors and `file`+`line` keys the writer never emits. (Dissent DISS-001.)
**Why This Matters:** DEC-0420's arm-neutral reduction is supposed to credit the dissent's catches; with live envelopes it credits none, under-counting recall precisely for the arms that run the adversarial gates.
**Required Fix:** In `envelope_texts`, when `anchor_line` is an int emit `f"{path_of(anchor)}:{anchor_line}"` (range with `anchor_line_end`), where the path is the anchor text up to its last `:`; keep the existing keys as fallbacks. Make AG-8 use the writer's real shape.

---

## Observations

Medium and low findings; not counted in the trailer.

### 1. Seeder: `--select` semantics differ from the headers

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:570` — `selected = cands[:a.select]` is fixed before build time, but a candidate can still be skipped (no covering test, `:593-597`) or refused (secret pattern, `:588-592`) inside the loop; those outcomes consume a slot and nothing replaces them.
**Suggestion:** The headers promise otherwise (`head/evals/harness/seed-bugfix-tasks.sh:43-44` "refusals and skips do not count"; `head/evals/harness/seed-refactor-tasks.sh:115-116` "a commit without a covering test is skipped and does not count"). Either iterate over `cands` until `written + failed == select`, or fix the headers.
**Benefit:** `--select 4` reliably yields four tasks, or says why not.

### 2. Grader: Python version floor is undeclared

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:710-714` — `tarfile.data_filter` / `extractall(filter=)` exist from Python 3.11.4 / 3.12; on this host's 3.11.2 (`'data_filter' in dir(tarfile)` → False) every snapshot extraction raises and the whole grade exits 2 "internal error". Host mode additionally runs `python3 -P` (`:492`), a 3.11+ flag; on 3.10 the interpreter exits 2 and the grade is written as all-red with only `parse_error: true` as a hint (dissent DISS-C-006).
**Suggestion:** Check `sys.version_info` and `hasattr(tarfile, "data_filter")` at start and `die` with a clear message; state the floor in the header.

### 3. Grader: regression detection drops the baseline when its output is unparseable

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1091` — `base_ok = [...] if not rb["parse_error"] else []`; for a `bash`/`node` regression command (allowed by `validate-suite.sh`) that exits 0 at base and non-zero at final, the synthetic `#1` case is never in `base_ok`, so `newly_failing` stays empty despite the regression. (Dissent DISS-003.)
**Suggestion:** When the base run is `parse_error` with rc 0, treat its synthetic cases as passing; the header (`:85-88`) already defines that fallback.

### 4. Grader: test timeout cannot kill a SIGTERM-ignoring process

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:508` — the in-container watchdog is `timeout 120 <cmd>` without `-k`; a test process that traps TERM (agent-authored code is in scope) runs on, the outer `subprocess.run(timeout=180)` (`:517-518`) kills only the `docker run` client, and the unnamed `--rm` container stays alive. (Dissent DISS-C-003.)
**Suggestion:** `timeout -k 10 120`, give the container a `--name` derived from the run dir, and `docker kill` it on `TimeoutExpired`.

### 5. Grader: the hidden overlay on the base tree distorts regressions and self-check

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1087` — `prepare(t, base_tree)` writes the hidden tests into the base tree before `regression_command` runs; when the regression target directory covers the hidden dest (e.g. `pytest tests` with hidden tests under `tests/`), hidden cases are double-counted in `regressions.base/final` and `--self-check base` can never pass because `suite_green` (`:1219`) sees them failing at base by design. (Dissent DISS-C-004.)
**Suggestion:** Run `regression_command` on trees that carry only the `grader_protected` restore, not the overlay; or document the authoring rule that regression targets must not overlap hidden dests and enforce it in `validate-suite.sh`.

### 6. Grader: TAP results keyed by description collapse duplicate names

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:617-621` — `names[n]` is the description; `ids_of` (`:642-644`) builds `pos` from `order`, so two bats tests with the same description (legal, and common across files when a directory is run) share one key: `failed_names` and `newly_failing` lose entries and `t<k>` can point at the wrong position. (Dissent DISS-C-005.)
**Suggestion:** Key TAP results by test number and map to `t<n>` directly.

### 7. Seeder: pytest counts read only the last line of stdout+stderr

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198` — `tail = output.strip().splitlines()[-1]` on `stdout + stderr`; any trailing stderr line (an interpreter warning) hides the summary and the proof reads `0 failed, 0 passed`, failing a good candidate.
**Suggestion:** Search lines in reverse for the summary regex as `ablation-grade.sh:549-553` does.

### 8. Process: the implementation report does not describe this diff

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md` — the report is the PR description; it names sixteen tasks under `grimoires/loa/evals/ablation-2.0/tasks/` and a freeze (`MANIFEST.sha256`) that the diff does not contain, and it has no `## AC Verification` walkthrough. Several bats tests (AG-14, AG-16, AG-18, VS-1) depend on those absent artefacts and on fixtures outside the diff.
**Suggestion:** Either include the tasks/freeze in the PR or split the description; add an AC Verification table with `file:line` evidence.

### 9. Low: `patch` hard dependency in the grader's self-check

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1175` — `subprocess.run(["patch", ...])` with no tool check; a missing binary raises `FileNotFoundError`, caught as "internal error" (exit 2) with no hint. Inconsistent with the seeder's fallback.
**Suggestion:** Check `shutil.which("patch")` in `main()` for `--self-check reference` and `die` with a clear message.

### 10. Low: verdict readers skip the symlink check used elsewhere

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:766` and `head/evals/harness/ablation-grade.sh:783` — `gate_verdict` / `review_md_verdict` open sandbox files with `isfile` only, while `combined_findings` (`:877`, `:881`) also refuses symlinks; a sandbox `engineer-feedback.md -> /etc/passwd` is read (only for a trailer, so low).
**Suggestion:** Add `and not os.path.islink(path)` for symmetry with DEC-0413.

### 11. Low: seeder tests assume properties of the temp directory and host

- **LOW** (confidence: high) `head/evals/tests/seed-bugfix.bats:183` — `--repo "$T"` is expected to be "not a git repository", which fails whenever `BATS_TEST_TMPDIR` lies inside a checkout (it did here); `head/evals/tests/seed-refactor.bats:97` calls `patch` directly without a `skip` guard.
**Suggestion:** Use a directory created with `git init` then `.git` removed, or `/dev/null`-style paths; `command -v patch || skip`.

### 12. SIMPLICITY[shrink]: the citation parser is duplicated

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:794-801` — the "recall-vs-defects.sh 1.1.2 parser" is re-implemented here (`CITE`, `ONE`, `TRAILER`, `URL`), so the two can drift silently.
**Suggestion:** Expose the parser from the grader script (or a shared `lib/`) and call it from both; `net: -40 lines possible`.

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` beside the envelope has no rows.

## Cross-Model Observations

Two voices answered (`gpt-5.5-pro` via `codex-headless`, companion `claude-headless`; consensus, 2/2 succeeded). Triage of the nine findings:

- DISS-001 (anchor_line ignored) → confirmed against the live envelope schema; counted as Changes Required 7.
- DISS-002 and DISS-C-002 (refactor verdict accuracy) → confirmed; counted as Changes Required 5.
- DISS-003 (regression baseline dropped on parse_error) → confirmed; Observation 3.
- DISS-C-001 (ABS_WORD false positives) → reproduced with the shipped regex; counted as Changes Required 6.
- DISS-C-003 (timeout without -k) → plausible; Observation 4.
- DISS-C-004 (overlay on base tree) → confirmed by reading `prepare()` call order; Observation 5.
- DISS-C-005 (TAP duplicate names) → confirmed; Observation 6.
- DISS-C-006 (`python3 -P` floor) → confirmed; folded into Observation 2.

The dissent saw 5 of 16 files after budget truncation (`validate-suite.sh` cut mid-hunk); the seeder findings above are from direct review and execution.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | Every file in `pr/head/` read; seeders executed against synthetic repositories |
| Report each defect with file and line | Pass | Seven high findings and twelve observations above, each with `head/<path>:<line>` |
| Give a merge verdict | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (a hard-coded personal path, see Changes Required 3)
- [x] Input validation at trust boundaries (`safe_rel`, `safe_path`, manifest checks, `tarfile.data_filter`)
- [ ] Grader oracle integrity for refactor tasks (Changes Required 4)
- [x] No shell interpolation of untrusted strings; no `source`/`eval` from variables
- [x] Dependencies: stdlib only; `yq`, `git`, `docker`, `patch` as external tools (undeclared floors, Observations 2 and 9)
- [x] Error messages carry ids only; `grade.json` holds no paths or excerpts

---

## Code Quality Summary

**Strengths:**
- Clear header contracts for every script; the code matches them in nearly every checked clause.
- Argument-vector subprocess calls throughout; the trust boundary (no `.claude/` sourcing, `-I` interpreters) is kept.
- Thoughtful test design (AG-12 byte-identical grade without meta/, AG-13 self-greps, SC-7/SC-8 generated-path rule).

**Areas for Improvement:**
- Failure paths in the seeder loop are untested beyond a single candidate.
- Test fixtures fabricate shapes the real writers never produce (AG-8 envelopes).
- Environment assumptions (bats path, `patch`, Python ≥3.11.4, tmpdir outside a repo) are implicit.

---

## Next Steps

1. Fix the seven Changes Required items; add the regression tests named in each.
2. Re-run `evals/tests/seed-bugfix.bats`, `seed-refactor.bats` and `ablation-grade.bats` on a machine without the author's dotfiles.
3. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section that matches the diff.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":7,"medium":8,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:45:00Z"} -->
