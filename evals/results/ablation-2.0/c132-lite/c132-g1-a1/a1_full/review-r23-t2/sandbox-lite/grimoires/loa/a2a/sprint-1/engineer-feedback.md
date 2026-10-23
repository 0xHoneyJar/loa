# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`), the bug-fix and refactor task seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `lib/seed_tasks.py`), the bd-8o5rx generated-path exclusion in `seed-corpus-from-record.sh`, the `source.churn` schema in `validate-suite.sh`, the regenerated pr-14/pr-15 key manifests, and six bats suites.

Much of it is careful work: every history path is checked before it touches disk (`safe_path`, `safe_rel`, `tarfile.data_filter`), mount-owned paths are refused by name, the grader never sources or evals anything, grade.json is written atomically, the generated-path rule is correct and tested at both the seeding and `--build-manifest` ends (SC-7, SC-8), the churn schema rejects booleans, and the pr-14/pr-15 checksums in `SHA256SUMS` match the regenerated manifests (verified with `sha256sum -c`).

Three defects block the merge. The hidden-test leak assertions added to `pipeline-run.bats` cannot fail (bare `!` is inert in bats; reproduced on bats 1.13.0). The grader's envelope parser never reads `anchor_line`, so every defect caught only by the adversarial dissent is graded as missed — reproduced against this very review's dissent envelope. And `ablation-grade.bats` hard-codes the author's personal bats path, so the bats-runner tests fail on any host where bats is not in `/usr/bin` (it is `/usr/local/bin/bats` here).

Local test run: the three new suites cannot be executed from the frozen `pr/head/` snapshot (the snapshot drops the executable bit and the suites reach for `evals/graders/no-secrets.sh`, `evals/harness/freeze.sh` and `grimoires/loa/evals/ablation-2.0/smoke/`, none of which is in the PR). The diff itself records mode 100755 for the scripts, so that is a snapshot artefact, not a defect. Reviewed by reading every head file and by targeted reproduction of the mechanics in question.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Testing — the hidden-leak assertions are inert

- **HIGH** (confidence: high) `head/evals/tests/pipeline-run.bats:498` — the `! grep -rqF "$f" …` inside the `for` loop never fails the test: bash skips the ERR trap and `set -e` for a `!`-inverted command, so a hidden-test byte (`sealed-case-7f3a`, `sealed-shape-91c2`, `sealed-patch-c0de`) present in the sandbox, snapshots or transcripts passes silently. Same at `head/evals/tests/pipeline-run.bats:503` (`! git … grep -q -e 'sealed-'`). Only line 504 is effective, and only because it is the last command of the test.
**File:** `head/evals/tests/pipeline-run.bats:498-503`
**Issue:** The new "frozen-suite layout" test is the only check of AC-2.6 / AC-5.5 ("no byte of any hidden/ file reached the sandbox, its git history or the snapshots"), and two of its three assertions are no-ops. Reproduced on bats 1.13.0 with a three-case file: a bare `! grep -q x <<<"x"` mid-test passes; the same line as the last command, or with `|| false`, fails.
**Why This Matters:** A leak of the hidden tests into the agent's sandbox is the one failure that invalidates the whole ablation. A guard that cannot fire is worse than none: it reports the property as verified.
**Required Fix:** Use `run ! grep -rqF "$f" …` (bats ≥1.5) or append `|| false`, as `seed-bugfix.bats:93` and `:109` already do. Apply the same fix to the other new inert negations listed under Observations §4.
**Reference:** bats-core writing-tests: "`! command` does not fail the test; use `run !`". bash(1) `set -e`: "…or if the command's return value is being inverted with !".

### 2. Grading — dissent findings never count toward recall

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:864-867` — `envelope_texts` emits the raw `anchor` string and a `file`/`path` + `line`/`line_start`/`start_line` pair, but the dissent envelopes carry neither: a real finding is `{"anchor": "evals/harness/ablation-grade.sh:envelope_texts", "anchor_line": 864, "anchor_line_end": …}` with `file`, `path` and `line` all absent (this review's own `grimoires/loa/a2a/sprint-1/adversarial-review.json`, every finding). The symbol anchor has no digits, so `citations()` yields nothing; `anchor_line` is never read. Every defect that only the review or audit dissent caught is graded as missed and is absent from `flags`.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** The header promises "each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json" (`ablation-grade.sh:96`), and AG-8 passes only because its hand-written envelopes use `anchor: "lib/x.sh:20"` and `file`+`line`, shapes `adversarial-review.sh` does not produce (its FR-4 contract is `anchor_line`/`anchor_line_end`, `adversarial-review.sh:28`, `:608-617`).
**Why This Matters:** The arm comparison the grader exists for (DEC-0420) is skewed against every arm whose gates run the dissent: their recall is under-counted exactly where the dissent adds value.
**Required Fix:** When `anchor_line` is an int, emit `f"{anchor.split(':', 1)[0]}:{anchor_line}"` (a `-{anchor_line_end}` range when present), keeping the existing `anchor` / `file`+`line` paths; add an AG-8 case whose envelope uses the real FR-4 shape.
**Reference:** `.claude/scripts/adversarial-review.sh:28` ("each finding may carry anchor_line / anchor_line_end (the head-file line, or range…)").

### 3. Fast-gate parity — the grader suite only runs on the author's machine

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is a personal dotfiles path; `ln -s "$BATS_BIN" "$T/bin/bats"` (`:48`) is a dangling symlink everywhere else, and the stub container PATH is `$T/bin:/usr/bin:/bin` (`:51`). On any host whose bats is not in `/usr/bin` (this one: `/usr/local/bin/bats`) the in-"image" `bats --tap tests` is exit 127, `run_suite` falls back to `parse_error: true, passed 0`, and AG-2 (`"2/3"`, `:268`) and AG-7 (`"3/3 false"`, `:352`) fail.
**File:** `head/evals/tests/ablation-grade.bats:16`, `:48`, `:51`
**Issue:** The header even states the design ("`bats` is the operator's bats-core", `:11`). A CI runner or a second reviewer cannot run the grader's test suite green.
**Why This Matters:** `FAST-GATE:` the sprint's self-check cannot be reproduced; a failing-by-construction suite carries the weight of a test failure.
**Required Fix:** `BATS_BIN="${LOA_SEED_BATS:-$(command -v bats)}"` and `skip` when empty; or symlink `$(command -v bats)` and resolve its `libexec` the way bats-core's own wrapper does.

---

## Observations

### 1. Portability of the grader's host interpreter

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:710` — `tarfile.data_filter` and `extractall(…, filter=keep)` (`:714`) exist only on Python ≥3.12 or the 3.11.4 / 3.10.12 / 3.9.17 backports. The grader runs on the host interpreter, which is never checked: on Python 3.11.2 (this host; `'data_filter' in dir(tarfile)` → False) every run that has an IMPLEMENT or FIX1 bundle dies in `extract_snapshot` with `AttributeError`, caught at `:1290` as "internal error" exit 2, and no grade is written.
**Suggestion:** Guard with `getattr(tarfile, "data_filter", None)` and fall back to the explicit member checks `keep` already does (absolute, `..`, link targets), or state the interpreter floor in the header and `die` early.
**Benefit:** A grade refused for an interpreter version looks exactly like a tool failure in a batch.

### 2. Regression and pass/fail semantics

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1091` — when the base regression run is unparseable, `base_ok = []`, so `newly_failing` is always empty: a `regression_command` that reports through its exit status only (neither pytest nor TAP) can never surface a regression, although `run_suite`'s fallback synthesises ids and a `bad` set for exactly that case. The converse branch (`:1092-1093`) reports every base test as newly failing when only the final run is unparseable, even at rc 0, so `final.passed == final.total` can coexist with a full `newly_failing` list, contradicting the fallback rule at `:86-88`. (Dissent DISS-003, DISS-C-003 — confirmed.)
**Suggestion:** Derive `newly` from the fallback ids when both runs are fallback (`rf["rc"] != 0` → all of `base_ok`, else none) and expose `regressions.parse_error` so consumers can exclude the row.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:652-653` — `all_pass` ignores `rc` and `timed_out`. A suite that prints its complete summary and then hangs (rc 124) or crashes in teardown is green for `verdict_accuracy_per_gate`, `suite_green_*` and the self-checks; conversely nothing cross-checks rc against the parsed line, so agent-authored code imported by the hidden tests (a new root `conftest.py` the fixture lacks is not restored by `prepare`, `:657-674`) can print a forged `N passed in 0.1s` and `os._exit(0)`. (Dissent DISS-002, DISS-C-002 — confirmed as a gap; exploit requires a gaming agent.)
**Suggestion:** Treat `rc != 0` with a clean summary, or `rc == 0` with failures, as `parse_error: true`; require `not timed_out` in `all_pass`; consider removing `conftest.py` / `pytest.ini` / `pyproject.toml` / `setup.cfg` / `tox.ini` not present in the fixture before running.

### 3. Contamination false positives

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:964` — `"hidden" in low` fires on `rg --hidden`, `fd --hidden`, a Grep pattern such as `display: hidden`, or any CSS/HTML edit; `ABS_WORD` (`:977-980`) treats a quoted route string like `grep -rn "/api/users" src/` as a filesystem path, and `/home`, `/root`, `/mnt`, `/srv` are outside the container allow-list (`:949`), so `ls /home` is `outside_path`. The first hit short-circuits (`:1034`), so one benign hit marks the run contaminated and downstream aggregation drops it. The header calls the scan a lower bound on leakage; it is also an unbounded source of false flags. (Dissent DISS-C-001 — confirmed.)
**Suggestion:** Match `hidden` as a path component (`(^|/)hidden(/|$)`) on path fields and path-shaped Bash words; record every hit in a `contamination_hits` list and keep `contaminated` as the first.

### 4. More inert negated assertions

- **MEDIUM** (confidence: high) `head/evals/tests/ablation-grade.bats:501` — `! grep -n 'graded_at\|test_\|slug\|…'` and `:502`, `:505`, `:512`, `:513` are mid-test bare negations: the DEC-0413 "ids only in every summary field" and "no `source`/`eval` in the grader" checks cannot fail (`:463` and `:514` work only as the last command of their tests). Same at `head/evals/tests/seed-corpus.bats:189` (`! grep -qF 'excluded generated path: src/real.sh'`), so SC-7 would not notice a real file being excluded.
**Suggestion:** `run !` or `|| false`, as in finding 1.

### 5. Report and scope

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:452` — the grader hard-depends on `evals/harness/freeze.sh` (also `ablation-grade.bats:521`, `:569`) and the PR title promises "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze", but the diff contains neither a `freeze.sh`, a `MANIFEST.sha256`, nor any task directory; `validate-suite.bats:32-44` (VS-1) now counts the committed `tasks/` that are not in this change. `reviewer.md` is the PR description and has no `## AC Verification` walkthrough, so none of the sprint-259 ACs it cites (AC-2.3, 2.5, 2.6, 2.9, 10.1) can be checked file:line here.
**Suggestion:** Either include the tasks and freeze in the change or state in the report which earlier commit shipped them; add the AC walkthrough.

### 6. Seeder robustness

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:227` — `patch -s -p1 --no-backup-if-mismatch -i` without `--batch`/`-f` and with stdin inherited: a hunk whose file is missing from the fixture makes `patch` prompt "File to patch:" and the seeder blocks on a TTY. The grader passes `--batch --forward` (`ablation-grade.sh:1175`); mirror it.
- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198` — `counts()` reads the last line of stdout+stderr concatenated; a stderr warning printed after pytest's summary makes passed = failed = 0 and the proof fails as "not red at base" / "not green at reference" for a sound commit. Parse stdout, or search the last few lines for the summary pattern as the grader does (`ablation-grade.sh:549-553`).
- **LOW** (confidence: medium) `head/evals/harness/seed-bugfix-tasks.sh:43-44` — the header says refusals and skips "do not count" toward `--select`, but a no-secrets refusal after selection (`seed_tasks.py:588-592`) consumes a slot and is not back-filled from the remaining candidates.

### 7. Grader robustness

- **LOW** (confidence: low) `head/evals/harness/ablation-grade.sh:517-521` — on `TimeoutExpired` only the `docker run` client is killed; the container keeps its rw bind mount into `grading/<label>` and the next `fresh_dir(grading)` (`:1053`) can race its writes. Name the container and `docker kill` it on timeout. (Dissent DISS-C-004 — plausible, unreproduced.)
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:213` — `yq` is required (`load_yaml`) but never checked; a missing binary is reported as "internal error: FileNotFoundError" rather than a usage error at startup, unlike docker (`docker_ready`, `:471`).

### 8. Complexity and style

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1045-1142` — `grade()` is 98 lines with the build / review-catch branches, regressions, refactor structural and snapshot accuracy inlined; `load_task()` (`:319-419`) is 100 lines. SIMPLICITY[shrink]: split per concern (`grade_build`, `grade_snapshots`, `grade_review_catch`) so each check is testable alone. `head/evals/harness/seed-corpus-from-record.sh:53` is a 113-column header line (two sentences merged). Over-engineering pass otherwise clean — net: -0 lines possible (split, don't delete).

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`, status `reviewed`, primary gpt-5.5-pro, companion claude-headless (`independent_voice`), 7 findings.

| Finding | Triage |
|---------|--------|
| DISS-001 (BLOCKING) envelope_texts ignores anchor_line | Confirmed against the real envelope shape → Changes Required §2 |
| DISS-002 (BLOCKING) all_pass ignores rc / timed_out | Confirmed gap, hang-after-summary is uncommon → Observations §2 (MEDIUM) |
| DISS-003 (BLOCKING) unparseable regression base → newly_failing always [] | Confirmed → Observations §2 (MEDIUM) |
| DISS-C-001 contamination false positives | Confirmed → Observations §3 (MEDIUM) |
| DISS-C-002 forged summary / no rc cross-check | Confirmed gap, needs a gaming agent → folded into Observations §2 |
| DISS-C-003 final-run parse_error → all base tests newly failing | Confirmed → folded into Observations §2 |
| DISS-C-004 orphaned container on client timeout | Plausible, unreproduced → Observations §7 (LOW) |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` has 0 rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md) | Done | 3 blocking defects, 11 observations, each cited `head/<path>:<line>`; verdict below |
| Sprint-259 ACs named by the PR (AC-2.3, 2.5, 2.6, 2.9, 10.1) | Not verifiable | No `## AC Verification` in reviewer.md; the tasks/freeze the title names are not in the diff (Observations §5) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (SHA256SUMS verified; no-secrets scan is invoked by both seeders)
- [x] Input validation at trust boundaries: `safe_path`/`safe_rel`, mount-owned refusal, `data_filter`, symlink handling in `copy_tree`/`prepare`
- [x] No `source`/`eval` of variable content in the grader; argument-vector subprocess calls throughout
- [ ] Hidden-test leak guard effective — NO (Changes Required §1)
- [ ] Gaming resistance of pass/fail parsing — gap (Observations §2)
- [x] Error messages carry ids only in grade.json (by inspection; the test for it is inert, Observations §4)

---

## Code Quality Summary

**Strengths:**
- Path safety and trust-boundary discipline in both the seeders and the grader.
- Atomic `grade.json` write; byte-identical regrade by design (no timestamps or scratch paths).
- Generated-path exclusion (bd-8o5rx) correct at both ends with matching tests; `source.churn` schema strict.

**Areas for Improvement:**
- Negative assertions in bats must use `run !` or `|| false`.
- Test infrastructure must not depend on one operator's machine.
- Parse-fallback semantics should be the same for hidden tests, regressions and gate accuracy.

---

## Next Steps

1. Fix the three blocking items (inert leak assertions, `anchor_line` in `envelope_texts`, portable `BATS_BIN`).
2. Address the inert negations in Observations §4 in the same pass.
3. Add an `## AC Verification` section to the report, and either include the tasks/freeze or name the commit that shipped them.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:46:16Z"} -->
