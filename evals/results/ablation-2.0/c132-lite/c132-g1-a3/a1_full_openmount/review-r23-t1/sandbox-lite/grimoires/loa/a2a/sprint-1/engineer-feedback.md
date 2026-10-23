# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` (16 files; cited as `head/<path>:<line>` from `pr/head/`)

---

## Overall Assessment

The change adds the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, a 1130-line Python program in a bash heredoc), the two history seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh` over `lib/seed_tasks.py`), the `source.churn` schema key in `validate-suite.sh`, the bd-8o5rx "generated artefacts are never fix regions" rule in `seed-corpus-from-record.sh` with regenerated `pr-14`/`pr-15` manifests, and bats coverage for all of it. What was verified: both manifests parse, no generated path remains in either, and `SHA256SUMS` matches both files byte-for-byte; `seed_tasks.py` and the extracted grader heredoc both `py_compile`; every shell file passes `bash -n`; the wrapper `--help` path works. The design is careful about the trust boundary (no sourcing, argv-only git, safe_rel on every path from history or a manifest, the meta/ boundary test).

Four findings block the merge. (1) The grader's snapshot extraction uses `tarfile.extractall(filter=…)` / `tarfile.data_filter`, which this host's Python 3.11.2 does not have — reproduced: `TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'` — so every run that carries a REVIEW or AUDIT verdict exits 2 "internal error". (2) `hidden_tests` is not a count of hidden tests: it counts every test the task's `test_command` collects in the final tree, including the fixture's visible tests and whatever tests the agent adds (TASK.md tells it to add one), so the headline `hidden_test_pass_rate` is agent-inflatable; the PR's own AG-1 expects `7/7` for a task whose hidden file has 5 cases. (3) The grader never reads the `anchor: "file:symbol"` + `anchor_line` finding shape that Loa's own `adversarial-review.sh` emits (the envelope produced for this very review uses it), so defects caught only by the dissent earn no recall credit. (4) `ablation-grade.bats` hardcodes one operator's dotfiles path for `bats`, so AG-2 and AG-7 fail on any other machine.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability — snapshot extraction crashes on Python < 3.11.4

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:714` — `tf.extractall(tree, filter=keep)` and `tarfile.data_filter` (line 710) exist only on Python 3.12 or the 3.8.17/3.9.17/3.10.12/3.11.4 backports; on 3.11.2 (this host) the call raises `TypeError`, which the top-level handler (line 1290) turns into exit 2 "internal error" for every run that has a review or audit verdict.
**File:** `head/evals/harness/ablation-grade.sh:710-714`
**Issue:** Reproduced here: `python3 --version` → 3.11.2, `hasattr(tarfile, "data_filter")` → False, and `extractall(..., filter=keep)` → `TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'`. `extract_snapshot` is reached whenever `gates` is non-empty (line 1110-1113), i.e. whenever `engineer-feedback.md` or `auditor-sprint-feedback.md` exists, so every gated arm (A1, A2, A3) is ungradeable while ungated arms grade fine — a silent, arm-correlated hole in the ablation. Host mode has the same class of issue: `python3 -P` (line 492) is 3.11+ only; on 3.10 every host-mode suite run exits 2 and parses as 0 passed with `parse_error`. The header guarantees nothing about the grader's own interpreter.
**Why This Matters:** The grader is the measurement instrument; an exit 2 on only the arms that ran a gate biases every per-arm aggregate `ablation-row.sh` builds from `grade.json`.
**Required Fix:** Feature-check at startup — `if not hasattr(tarfile, "data_filter"): raise GradeError("ablation-grade needs Python >= 3.11.4 (tarfile filters)")` — or implement `keep()`'s safety checks by hand (reject absolute names, `..`, links, devices; `safe_rel` already does most of it) and call `extractall(tree, members=…)` without `filter=`. Pick `-P` for host mode only when `sys.version_info >= (3, 11)`. Add a bats case that runs the grader under the oldest supported interpreter or asserts the version message.
**Reference:** Python docs, tarfile "Extraction filters" (added 3.12, backported 3.11.4).

### 2. Grading integrity — `hidden_tests` counts visible and agent-added tests

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1080` — `run_suite(final, t.test_command, t.static_cases)` runs the task's directory-wide `test_command` and reports its whole result as `hidden_tests`; the fixture's visible tests and any test file the agent adds under the same directory are counted as hidden passes.
**File:** `head/evals/harness/ablation-grade.sh:1080-1081` (also `:593`, `:637`)
**Issue:** The static case count (line 637) is only a floor. For `bf-py` the hidden file has 5 cases, yet AG-1 (`head/evals/tests/ablation-grade.bats:243`) asserts `7/7` because `tests/test_existing.py` is swept in. The seeded TASK.md says "add a regression test of your own" (`head/evals/harness/lib/seed_tasks.py:432`). Concrete scenario: the agent fixes nothing, adds `tests/test_mine.py` with 20 trivially passing cases → `hidden_tests` 22/27 (0.81) instead of 0/5; `all_pass` is still false, but `hidden_test_pass_rate` (the metric AG-18 derives, line 391) rises with every test the agent writes, and an agent that adds one failing test makes a correct fix look partial. Across arms this rewards verbosity, not correctness.
**Why This Matters:** `hidden_test_pass_rate` is the primary build-task metric of the ablation (PRD FR-6). A metric the graded agent can move without touching the hidden tests is not a hidden-test metric.
**Required Fix:** Score only nodes whose file is an overlay destination: after `parse_pytest`/`parse_tap`, keep `order`/`bad` entries whose path (pytest node prefix, or the bats file) is in `{dest for _s, dest, _f in t.overlay}` excluding `t.structural`, and set `total = max(len(kept), t.static_cases)`. Alternatively run `test_command` with the overlay dest paths appended instead of the directory. Report the whole-suite result separately (e.g. `suite_tests`) if it is wanted. Update AG-1 to expect `5/5`.

### 3. Recall — Loa's own dissent envelope shape yields no citations

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:864` — `envelope_texts` only reads a numeric `anchor` string or `file|path` + `line|line_start|start_line`; the finding shape `adversarial-review.sh` actually writes — `anchor: "<file>:<symbol>"`, `anchor_type: "function"`, `anchor_line: N` — produces a citation `citations()` cannot parse (no digits after the colon) and no `file`/`line` pair, so the finding contributes nothing to `gates-combined.md`.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** Verified against the envelope this review produced (`grimoires/loa/a2a/sprint-1/adversarial-review.json`): every finding is `{"anchor": "evals/harness/ablation-grade.sh:envelope_texts", "anchor_line": 864, …}` — none has `file`, `path`, `line`, `line_start` or `start_line`. AG-8 (`head/evals/tests/ablation-grade.bats:402-403`) tests two shapes the real script does not emit. Result: in review-catch tasks, a defect caught only by the cross-model dissent is scored as missed, which systematically undercounts the arms that run the dissent (exactly the arms the ablation compares).
**Why This Matters:** DEC-0420 makes `gates-combined.md` the arm-neutral reduction; dropping one arm's findings source breaks neutrality.
**Required Fix:** In `envelope_texts`, when `anchor` matches `^(?P<file>[^:]+):(?P<sym>[A-Za-z_]\w*)$` and `anchor_line` is an int, emit `f"{file}:{anchor_line}"` (and `-{anchor_line_end}` when present); also accept `anchor_line` as a line key alongside `line`. Add a fixture in AG-8 copied from a real envelope.

### 4. Tests — bats path hardcoded to one operator's home

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is symlinked into the stub image PATH at line 48; on any machine without that exact path the link dangles, `bats` execs 127 inside the stub, `run_suite` records `parse_error` 0/3, and AG-2 (`:268-269`) and AG-7 (`:352-353`) fail.
**File:** `head/evals/tests/ablation-grade.bats:16` (and `:48`)
**Issue:** The file header even says "`bats` is the operator's bats-core". A test that passes only on the author's workstation gives the sprint no CI evidence for the bats/TAP grading path (AC-2.6), and will red every other contributor's run of `evals/tests/`.
**Why This Matters:** Fast-gate parity: the test suite must run where the fast gate runs.
**Required Fix:** `BATS_BIN="${LOA_TEST_BATS:-$(command -v bats || true)}"`; `skip "bats not on PATH"` in the two tests that need it when empty. The same applies to `/usr/bin/python3` at line 46 (see Observations).

---

## Observations

### 1. Seeder selection contract

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:570` — `selected = cands[:a.select]` is fixed before any task is built, so a build-time `skip` (no covering test, mixed runners, lines 593-597) or `secret` refusal (588-592) consumes a selection slot and is never backfilled; with `--select 4` and the newest refactor candidate lacking a covering test, three tasks are written and exit is 0.
**File:** `head/evals/harness/lib/seed_tasks.py:570`
**Suggestion:** Iterate over `cands` until `written + failed == a.select` (or the list is exhausted). Both wrapper headers promise this: "refusals and skips do not count" (`head/evals/harness/seed-bugfix-tasks.sh:43-44`), "a commit without a covering test is skipped and does not count" (`head/evals/harness/seed-refactor-tasks.sh:37-38`).
**Benefit:** The documented `--select N` means N tasks or a non-zero exit.

### 2. Grader correctness edges

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1087` — `prepare(t, base_tree)` overlays the hidden tests before `regression_command` runs on `base` and `final` (lines 1089-1090). A regression command that sweeps a directory receiving hidden tests (e.g. `pytest tests` with dest `tests/test_x.py`) counts hidden cases in `regressions.base/final`; at base they fail by design, so `--self-check base` (line 1219, `suite_green` from `r["final"]`) FAILs a correct task and pushes authors to `regression_command: null` (as both seeders already write). Run the regression suite on copies taken before the overlay, or restore only `grader_protected` for that run. (Dissent DISS-C-004, confirmed.)
- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:653` — `all_pass` ignores `rc` and `timed_out`; a suite that prints its passing summary and is then killed by `timeout 120` (rc 124, `timed_out: true`) still marks an APPROVED verdict accurate (line 1129-1130) and a refactor suite green (line 1105). Require `rc == 0 and not timed_out` in `all_pass`. (Dissent DISS-002; triaged down from blocking: the scenario needs a post-summary hang, and `hidden_tests.timed_out` is still recorded for consumers.)
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:242` — `remove_path` chmods every entry of `ds` from `os.walk(followlinks=False)`, which still lists symlinks to directories, and `os.chmod` follows the link. `copy_tree` preserves the agent's symlinks verbatim (lines 283, 294), so a re-grade (`fresh_dir(grading)`, line 1041) or a protected-directory restore (`put_file` → `remove_path`) chmods the symlink *target* to 0700 — any directory the grader user owns, including `<run-dir>/transcripts` via a relative `../transcripts` link from the sandbox. Owner access survives (so no data loss, hence not blocking), but the header's "writes only grading/ and --out" (DEC-0413) is violated. Skip `os.path.islink(...)` entries before `chmod`. (Dissent DISS-C-001, confirmed; triaged to medium.)
- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:492` — the grader strips the cwd from `sys.path` (`-I -s` in the image, `-P` on the host) while the seeders prove tasks with plain `python3 -m pytest` (cwd importable, `head/evals/harness/lib/seed_tasks.py:206-208`). A seeded task whose tests import by cwd (no conftest chain) passes its proof and collects 0/N under the grader in every arm. Either share the shaped argv with the seeder's proof or make `--self-check reference` a hard pre-freeze step in `freeze.sh`. (Dissent DISS-C-002, confirmed.)
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1119` — a gate whose feedback file exists but whose snapshot cannot be extracted (missing bundle, non-hex or absent `index.json` entry, or the Python issue above once guarded) hits `continue` and leaves `verdict_accuracy_per_gate[gate]` null, which the header (lines 110-111) reserves for "a gate that did not run". Separately `verdict.value` can be the literal `"none"` (line 1057-1060) where the header promises APPROVED/CHANGES_REQUIRED/null. Record a reason (e.g. `snapshot_missing: [label]`) and map `"none"` to null in `verdict`. (Dissent DISS-C-005 overlaps.)
- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:964` — `"hidden" in low` flags any tool input containing the substring: `rg --hidden`, `find . -name '.hidden*'`, `ls --hide`, a Grep `pattern` of `hidden` all mark the run `contaminated` with pattern `hidden`. The scan is documented as a lower bound, but these are false positives that will appear in ordinary runs. Match a path component (`(^|/)hidden(/|$)`) and the `-i` word form, and exclude the `--hidden` flag.

### 3. Scope and report

- **MEDIUM** (confidence: medium) `head/evals/harness/validate-suite.sh:1` — the PR title and `reviewer.md` claim "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze", yet `pr/head.diff` contains no file under `grimoires/` and no `MANIFEST.sha256`; VS-1 (`head/evals/tests/validate-suite.bats:31-44`) now derives its expected counts from whatever is committed under that path, so the test cannot fail on a wrong task count. The tasks and freeze cannot be reviewed from this change; the report also has no `## AC Verification` section (automatic CHANGES_REQUIRED per the review skill). Either include the task tree in the PR or state explicitly that it lands separately and keep VS-1 asserting a fixed `16`.

### 4. Simplicity and structure

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:166` — `SIMPLICITY[shrink]`: 1130 lines of Python live inside a bash heredoc, so nothing lints or `py_compile`s it in CI (the review had to extract it by hand), and `grade()` (lines 1045-1142, ~98 lines) and `load_task()` (lines 319-419, ~100 lines) exceed the 50-line ceiling. `seed_tasks.py` already shows the pattern: move the body to `evals/harness/lib/ablation_grade.py`, keep the `.sh` as the thin `exec python3 -I` wrapper, and split `grade()` into `grade_build`/`grade_review_catch`. `net: -0 lines possible` in logic; the gain is testability, not size.

### 5. Low

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196` — `counts()` reads the last line of `stdout + stderr`; any stderr emitted after the pytest summary (plugin warnings, a `ResourceWarning`) yields 0/0 and a spurious `proof-failed … not red at base` (exit 1). Scan lines in reverse for the summary as the grader does (`SUMMARY_RX`).
- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:52` — `_git_env` keeps the user's global git config active (`GIT_CONFIG_NOSYSTEM` only); `log.showSignature=true` or a global `diff.external` changes the `%x1e`-delimited `git log` output (line 86) and the patch bytes. The grader's `git_env` (`head/evals/harness/ablation-grade.sh:678-679`) already sets `GIT_CONFIG_GLOBAL=/dev/null`; mirror it.
- **LOW** (confidence: high) `head/evals/tests/ablation-grade.bats:46` — the python3 stand-in execs `/usr/bin/python3`; hosts whose `python3` is elsewhere (pyenv, Homebrew, `/usr/local/bin`) fail every container-path test. Use `$(command -v python3)` captured in `make_bin`.
- **LOW** (confidence: medium) `head/evals/harness/seed-bugfix-tasks.sh:78` (and `seed-refactor-tasks.sh:67`) — the `no-secrets.sh` path is passed unconditionally; if it is absent, `secrets_clean` (`head/evals/harness/lib/seed_tasks.py:505-506`) gets rc 127 and every built task is reported as `refused … a secret pattern in the materialised task`. Check the file exists in the wrapper's missing-tool loop and exit 2 with its name.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1222` — `--self-check base` passes when the test command cannot run at all (`parse_error`, passed 0 < total ≥ 1); the header promises "PASS when at least one hidden test fails". Require `not h["parse_error"] and not h["timed_out"]`, and show `parse_error` in the evidence string. (Dissent DISS-C-003, confirmed.)

---

## Cross-Model Observations

Two voices answered (primary `gpt-5.5-pro` via `codex-headless`, companion `claude-headless`; `verdict_quality.consensus_outcome: consensus`, 2/2 succeeded). Triage of the eight findings: DISS-001 confirmed and counted (Changes Required §3); DISS-002 confirmed, triaged to medium (Observations §2); DISS-C-001 confirmed, triaged to medium (Observations §2); DISS-C-002, DISS-C-003, DISS-C-004 confirmed as observations; DISS-C-005 overlaps the silent-null observation; DISS-C-006 confirms Changes Required §1, which this review had already reproduced and holds at high.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` has zero rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" | Pass | Every finding above cites `head/<path>:<line>` from `pr/head/`. |
| "give a merge verdict" | Pass | CHANGES_REQUIRED (four high findings). |
| `reviewer.md` carries `## AC Verification` | Fail | The report is the PR description only; no AC walkthrough. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the `BATS_BIN` path is a personal path, not a secret)
- [x] Input validation at trust boundaries: `safe_rel`/`safe_path` on every history and manifest path; argv-only `git`, `yq`, `patch`; no `source`/`eval` (AG-13)
- [ ] Write boundary: `remove_path` chmods through agent-controlled symlinks (Observations §2)
- [x] No shell injection: `subprocess.run` with lists throughout; docker argv built as a list
- [x] Error messages leak no hidden-test names or excerpts (AG-12 asserts ids only)
- [x] Dependencies: stdlib only; `tarfile` filter use is the right intent, wrong floor (Changes Required §1)

---

## Code Quality Summary

**Strengths:**
- The meta/ and sandbox-envelope trust boundary is explicit, documented and tested (AG-8, AG-12, AG-13).
- Task building in a private stage directory, moved into place only after the proof and no-secrets scan, is the right shape for the seeders.
- `generated_path` and its two tests (SC-7, SC-8) are small and exactly scoped; the manifests and checksums are consistent.
- Deterministic `grade.json` (no timestamps or scratch paths) and a byte-identity test for it.

**Areas for Improvement:**
- The grader guarantees behaviour only inside the Sprint 258 image but runs on the host interpreter; state and check the host requirement.
- Metric names must mean what they say (`hidden_tests`); the ablation is only as good as its instrument.
- Tests must not depend on one workstation's filesystem.

---

## Next Steps

1. Fix the four Changes Required items (interpreter floor, hidden-test scoping, envelope anchor parsing, bats path) and add the regression cases named in each.
2. Decide the medium observations in `grimoires/loa/NOTES.md` (regression-before-overlay and `--select` backfill are cheap and worth taking now).
3. Add an `## AC Verification` section to `grimoires/loa/a2a/sprint-1/reviewer.md` and either include the sixteen tasks and `MANIFEST.sha256` in the change or say where they land.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":9,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:08:00Z"} -->
