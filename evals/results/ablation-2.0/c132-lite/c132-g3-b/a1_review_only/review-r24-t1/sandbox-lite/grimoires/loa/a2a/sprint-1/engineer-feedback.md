# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description; it carries no `## AC Verification` section)

---

## Overall Assessment

The change under review is the sprint-260 batch runner (`evals/harness/run-ablation.sh`, 1,410 lines, new), the pre-registered report (`evals/harness/ablation-report.py`, new), the shared `lib/arms-common.sh` extracted from `run-arms.sh`, the DEC-0545 degraded rule in `ablation-row.sh`, and five grader calibrations (1.2.1 to 1.2.5) in `ablation-grade.sh`, with bats coverage for the runner (20 cases), the report (22 cases) and the grader additions.

The runner is carefully built: pre-flight hard gate, pinned worktree, seeded trial-major plan, transport retry, took-effect pause, drift guard, watchdog on the pipeline process group, spend gating, resume with in-place row replacement, and an outage breaker, each with a test that exercises the stub end to end. The `run-arms.sh` extraction is behaviour-preserving on reading (`spend_charge` and `est_record` reproduce the old inline accounting; no stale `ARM_SUM`/`POOL_SUM` reference remains).

The blocking problems sit in the grader calibration and in the report's primary unit:

- The new heredoc strip (1.2.2) is implemented with a regex that backtracks exponentially on an unterminated `<<WORD` opener (measured: 3 s at 22 lines, doubling per line). The grader runs inside the runner's `post_run`, after the pipeline's `.pgid` is removed, so nothing bounds it: one such transcript stalls the whole batch.
- The same strip removes the rest of the opener line, so `cat <<'EOF' > /home/operator/x` loses its redirect target, and it removes interpreter bodies (`python3 - <<'PY' … open('/home/operator/x') … PY`). Outside reaches through the most common write idiom are no longer contamination hits.
- The hidden-token matcher (1.2.4) is case-sensitive and has no glob-adjacent shape, so `tests/Hidden/`, `find -name '*hidden*'` and `ls hidden*` pass, while the header still promises any-case matching. These are regressions against the base grader.
- The report's pre-registered catch-rate unit is the defect, read from `defects_missed` or `recall.missed`. `ablation-row.sh` emits neither (the grader computes `recall.missed`; the row writer drops it), so every production review-catch row takes the rate fallback, replicating one task-level difference n_defects times and narrowing the bootstrap interval the predicates read.

Cross-model dissent (two voices, gpt-5.5-pro primary via codex-headless and claude-headless companion, both succeeded, no rejected payloads) raised nine findings; I reproduced each one named below with a concrete input before counting it. Advisory voices were read as input, never counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Availability: the heredoc regex stalls the grader and, through it, the batch

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` is compiled with `re.S`, so `(?:.*?\n)*?` lets each `.*?\n` span any number of lines; when the terminator `\2` never appears the engine tries every partition of the k newlines (2^(k-1) attempts). Measured with the regex as written: 12 lines 0.002 s, 18 lines 0.12 s, 20 lines 0.47 s, 22 lines 3.0 s; 30 lines is minutes, 40 is days.
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex), `:1412` (`body = strip_heredocs(val)` on every Bash tool_use), `head/evals/harness/run-ablation.sh:1031` (the `.pgid` the watchdog reads is removed before `post_run` at `:1054`), `head/evals/harness/ablation-grade.sh:262` (`LOA_EVAL_GRADE_TIMEOUT_S` wraps test subprocesses only).
**Issue:** The opener also matches non-heredoc text: a here-string `<<<'X'` (the regex re-anchors at the second `<`), a C/Python shift `a << n`, a Markdown `<<name>>`, or a heredoc whose terminator is not alone on a line. Any Bash command with such a token plus roughly thirty newlines makes `check_value` run for minutes to hours. (Confirmed by dissent DISS-C-002.)
**Why This Matters:** `grade()` calls `check_value` on every tool_use of every transcript. The runner invokes the grader in `post_run`, inside the trial job, after the pipeline process group has already exited and its `.pgid` file is gone, so `watchdog_tick` (`:1169`) never fires for it. The trial job never writes its `.result`, `reap 1` loops forever, the concurrency slot is burned, and the batch never finishes or fails. For the P1-sized batches this is a silent multi-hour stall with spend committed.
**Required Fix:** Replace the regex with a linear scan: find `<<[-]?\s*(['"]?)(WORD)\1` with `re.search`, then locate the terminator with a per-line loop (`for i, line in enumerate(lines[start:]): if line.strip() == word`), and leave the text untouched when no terminator exists. Add a test with an unterminated opener over 40 lines that must grade in under a second. Independently, give `post_run` a deadline in the runner (wrap the took-effect, grade and row calls in `timeout`, or record a `.pgid` for the post-run subshell so `watchdog_tick` covers it) and row the trial `infrastructure_error` when it expires.
**Reference:** CWE-1333 (Inefficient Regular Expression Complexity).

### 2. Contamination false negatives introduced by the heredoc strip

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377-1382` — `[^\n]*\n` after the delimiter consumes the rest of the opener line and `strip_heredocs` replaces the whole match with `<<HEREDOC`, so `cat <<'EOF' > /home/operator/notes.txt` becomes `cat <<HEREDOC` and the outside path is never a candidate; the stripped body also hides `python3 - <<'PY' … open('/home/operator/notes.txt') … PY`.
**File:** `head/evals/harness/ablation-grade.sh:1377-1382`, applied at `:1412`.
**Issue:** Reproduced with the regex as written: `cat <<'EOF' > /home/operator/notes.txt\nhello\nEOF` → `cat <<HEREDOC`; `cat <<EOF | tee /root/.bashrc\nx\nEOF\n` → `cat <<HEREDOC\n`; the interpreter case yields zero path words after the strip against one before. In the base grader all three were `outside_path` hits. DEC-0541 intended to exempt written prose, not the redirect target on the opener line or a script fed to an interpreter. (Dissent DISS-C-001 raised the opener-line case independently.)
**Why This Matters:** Writing a file through a heredoc redirect is the most common shell idiom an agent uses; an agent that writes or reads outside the sandbox through it stays in the scored set, inflating that arm's primary. The hidden/suite/repo scans still read the body (as the comment says), but the outside-path scan does not.
**Required Fix:** Strip only the body: keep the opener line intact (match from the newline after the opener to the terminator line) and keep the body when the heredoc feeds an interpreter (`python3 -`, `bash`, `sh`, `node`, `perl`, `ruby`, or any command word other than `cat`/`tee`/a bare redirect). Add true-positive tests for `cat <<'EOF' > /home/operator/x` and `python3 - <<'PY' … open('/home/operator/x')` beside the false-positive ones at `head/evals/tests/ablation-grade.bats:499-507`.
**Reference:** CWE-693 (Protection Mechanism Failure).

### 3. The hidden-token matcher is case-sensitive and misses glob-adjacent probes

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` — `HIDDEN_TOKEN` has no `re.I`; only the all-caps alternative is case-independent in effect, and neither alternative accepts `*` or a quote next to the word, so `cat tests/Hidden/cases.json`, `find . -name '*hidden*'` and `ls hidden*` are not hits in a Bash command while the base grader (`"hidden" in low`) caught all three.
**File:** `head/evals/harness/ablation-grade.sh:1329` (regex), `:1397-1399` (the Bash branch), `:166` (header still reads "`hidden` (any case …)").
**Issue:** Reproduced: the three commands above return no match under `HIDDEN_TOKEN` and a match under the base substring check; `ls tests/hidden/` matches both. A glob search for the hidden tree is exactly the probe the contamination check exists to catch, and it is a command token, not the prose DEC-0551 set out to exempt. (Dissent DISS-001 and DISS-C-003.)
**Why This Matters:** A run that enumerates the hidden tests and then passes them is scored as a clean completion. The header documents behaviour the code no longer has.
**Required Fix:** Compile with `re.I` (drop the separate `HIDDEN` alternative) and add `*`, `?`, `'`, `"` to the adjacency classes: `(?i)(?<=[/._=*?'"-])hidden\b|\bhidden(?=[/_=*?'"-]|\.[A-Za-z0-9])`. Keep the prose exemption by requiring the adjacency. Add the three inputs above as true-positive tests next to `head/evals/tests/ablation-grade.bats:519-528`, and fix the header sentence at `:166`.
**Reference:** CWE-178 (Improper Handling of Case Sensitivity).

### 4. Statistics: the report's per-defect unit is dead in production

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:477-483` — `defect_vector` reads `defects_missed`, then `recall.missed`, else returns `[defect_catch_rate] * n`; `ablation-row.sh` writes `defects_seeded`, `defects_caught`, `defect_catch_rate` and `flags` (`head/evals/harness/ablation-row.sh:372-377`) and never `defects_missed` or `recall`, although the grader computes `recall.missed` (`head/evals/harness/ablation-grade.sh:1319`). Every production review-catch row therefore takes the rate branch.
**File:** `head/evals/harness/ablation-report.py:477-483`, `:546` (the replicated values enter `res["diffs"]`), `head/evals/harness/ablation-row.sh:372-377`.
**Issue:** With the rate branch, a task with n defects contributes n identical differences, so the bootstrap at `:184-190` resamples k copies of one value per task. The interval of the mean over 4 tasks × 8 copies is roughly sqrt(8) narrower than over the 4 task-level differences. The predicates at `:579-603` read `lo` and `hi`, so an arm can cross into `investigate` or `keep` on an interval the data does not support. The header (`:69-74`) documents the fallback as the exception for "aggregate rows"; in this PR it is the only path a real row can take. `AR-7` tests the ids path on planted fixtures that set `defects_missed` directly (`head/evals/tests/fixtures/ablation-report/gen-fixtures.py:77-78`), so nothing in the suite notices.
**Why This Matters:** The report is the pre-registered analysis the operator decides on (DEC-0558/0559 were taken on P1 reads). Pseudo-replication understates uncertainty on every review-catch comparison.
**Required Fix:** Propagate `missed` in `ablation-row.sh` (`defects_missed: ($rc.missed // null)` beside `defects_caught`, with a `--validate` rule that it is a list of `d<K>` strings when present) and make the report treat a rate-only row as one task-level difference (n = 1) rather than n copies, or refuse to use the defect unit when any paired row lacks ids. Add a `--validate` fixture row from the real grader output to AR-20.
**Reference:** Pseudo-replication (Hurlbert 1984); SDD §5.12 "catch-rate unit the defect".

---

## Observations

### 1. Grader calibration: further exemptions that pre-empt the path check

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1438` — `w.startswith("/.")` runs on the raw word before `outside()` applies `os.path.normpath`, so `cat /./root/x`, `ls /../home/operator` and `/.//root/x` are skipped although they normalise to `/root/x` and `/home/operator`. (Dissent DISS-C-007 confirms.)
**File:** `head/evals/harness/ablation-grade.sh:1438`
**Suggestion:** Test the first component only: `re.match(r"^/\.[^/.]", w)` (a dot-name that is not `.` or `..`), or normalise first and skip when the normalised first component starts with a dot.
**Benefit:** Keeps the `/.claude/…` exemption without opening `/./` and `/../` spellings.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1432` — `"=" in w` drops any word carrying `=`; `/home/operator/a=b` is skipped. Rare in practice, but the comment's premise ("no path component carries =") is false on Linux.
**File:** `head/evals/harness/ablation-grade.sh:1432`
**Suggestion:** Limit the `=` exemption to words where `=` precedes the first `/` of a second component, or to words following a sed/awk program (`s`, `y`, a quote).
**Benefit:** Narrows the exemption to the regex and key=value shapes that caused the false positives.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1365-1369` — `after_closing_quote` skips any `/x/y` glued to a closing quote whatever precedes it. `cat "$HOME"/private/credentials` matches neither `HOME_WORD` (`:1332`, requires `$HOME/` contiguous) nor, now, `ABS_WORD`, so in host mode a home reach is silent; a prefixed Python literal `f"/root/x"` or `r"/root/x"` puts a letter at pos-2 and is skipped in both modes. Reproduced. (Dissent DISS-002, DISS-C-004.)
**File:** `head/evals/harness/ablation-grade.sh:1365-1369`, `:1442`
**Suggestion:** Only skip when the quoted token is itself a path-like or variable expansion (`"$D"`, `'"$v"'`): check that the quote at pos-1 closes a run that began with `"$` or `'$`, or extend `HOME_WORD` to accept `"$HOME"/` and `"${HOME}"/`.
**Benefit:** Keeps the DEC-0557 exemption for the mutation-test idiom while leaving `$HOME` and string-literal paths visible.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1372-1374` — `in_quotes` is raw quote parity over the whole prefix; an apostrophe inside an earlier double-quoted string flips it. `git commit -m "don't break" && ls /root` sees one `'` before `/root`, so the sensitive one-component word is skipped at `:1444`. Reproduced. (Dissent DISS-C-005.)
**File:** `head/evals/harness/ablation-grade.sh:1372-1374`
**Suggestion:** Walk the prefix with a small state machine (single quote / double quote / none, honouring `\"`) instead of counting; or restrict the check to the current simple command (split on `;`, `&&`, `||`, `|`).
**Benefit:** Commit messages and echo text with apostrophes are routine in agent commands; `ls /root` and `ls /home` are the probes AG-10 asserts.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1362`, `:1423` — `SENSITIVE_SINGLE` whitelists five Linux roots; `ls /Users`, `ls /data`, `ls /export` were outside hits before 1.2.1 and are silent now. Host grading on macOS makes `/Users` the home root. (Dissent DISS-C-006.)
**File:** `head/evals/harness/ablation-grade.sh:1362`
**Suggestion:** Invert the rule: treat a one-component word as a command token only when it is not an existing directory under the allowed-root model (e.g. keep a short list of known slash commands and flag-like tokens), or add `Users`, `private`, `data`, `export`, `run` to the set.
**Benefit:** Closes the single-component gap without re-flagging `/review-sprint`.

- **MEDIUM** (confidence: high) `head/evals/tests/ablation-grade.bats:483-546` — every new calibration block asserts the false positive it fixes, and only three assert that a true positive beside it still fires (`:514-516`, `:526-528`, `:535-537`, `:543-546`). None covers the regressions in Changes Required 2 and 3 or the exemptions above, which is how five false negatives shipped in one grader bump.
**File:** `head/evals/tests/ablation-grade.bats:483-546`
**Suggestion:** For every exemption added to `check_value`, add the adjacent true positive (mixed-case `Hidden`, `'*hidden*'`, `cat <<'EOF' > /home/operator/x`, `/./root/x`, `"don't" && ls /root`, `"$HOME"/x` in host mode) in the same test block.
**Benefit:** Turns each DEC into a pair of assertions so the next calibration cannot widen the gap unnoticed.

### 2. Runner robustness

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:1067-1081` — `append_and_validate` appends the row, then runs `ablation-row.sh --validate` over the whole rows file. A pre-existing bad row (another batch's, or one written by an older schema) fails the validation of this batch's first append; `STOP=invalid` ends the batch with exit 3 after the row is already in the file.
**File:** `head/evals/harness/run-ablation.sh:1067-1081`
**Suggestion:** Validate the new row alone (`--validate "$rowf"`) before appending, and run the whole-file validation once at start-up (refuse with the offending line) rather than per append.
**Benefit:** A foreign bad row is reported before spend, and the batch never ends with a row appended and a `failed` state.

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:1031`, `:1054`, `:1169` — the watchdog (DEC-0429) reads `.pgid` files, and `run_trial` removes the trial's `.pgid` at `:1031` before `post_run` at `:1054`. took-effect, the drift guard, the grader (a docker run in container mode) and `ablation-row.sh` therefore run with no deadline. Changes Required 1 is one way to hit this; a hung docker daemon is another.
**File:** `head/evals/harness/run-ablation.sh:1031-1054`
**Suggestion:** Record a `.pgid` (or a separate `.postpid` with its own deadline, e.g. 2 × `LOA_EVAL_GRADE_TIMEOUT_S` + a margin) for the post-run phase and let `watchdog_tick` row the trial `infrastructure_error` when it expires.
**Benefit:** The batch's liveness no longer depends on every collaborator returning.

### 3. Low

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:996` — `post_run` rows any non-zero grader exit as `infrastructure_error`; the header (`:149`) and RAB-5 say exit 2. The grader's exit 1 is the self-check FAIL mode only today, so this is harmless until a graded-but-failing exit code is introduced.
**Suggestion:** Match on `PR_GRC -eq 2` for infrastructure_error and log any other non-zero as a grader bug.

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:543-547` — `drift_check` compares CLI versions only when the manifest's `cli_version` is a semver and falls back to the image digest only when no transcript carries a version. With `cli_version: unknown` (the `docker run … claude --version` probe failed) and transcripts that do carry versions, neither check runs.
**Suggestion:** When `want` is not a semver, always compare image digests.

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:372-385` — on `--resume`, `--arms`, `--tasks`, `--types`, `--suite-root`, `--suite-file`, `--executor` and `--image` given on the command line are silently replaced by the manifest's values (RAB-6 passes `--arms a1_full --batch p1 --resume --clear-arm …` and gets the manifest's arms).
**Suggestion:** Warn, or refuse, when a resumed invocation carries one of these options with a value that differs from the manifest.

- **LOW** (confidence: medium) `pr/PR.md` — the commit list names CHANGELOG entries, DEC-0540 … DEC-0559 records and `evals/tests/run-arms.bats` as the golden check for the `run-arms.sh` extraction, but none of these files is in the 17-file diff. Documentation verification could not be completed from the PR as presented; the behaviour-preservation claim for `run-arms.sh` rests on reading the diff, not on the test.
**Suggestion:** Include the CHANGELOG hunk and confirm `run-arms.bats` ran green at head in the implementation report.

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1118-1166`, `:1008-1064`, `:969-1006` — `collect`, `run_trial` and `post_run` approach or exceed 50 lines, and `write_manifest` (`:703`) carries 25 `--arg` bindings. The header documents the design well, so this is noted, not blocked; `Lean already. Ship.` does not apply to a 1,410-line runner, but no single deletion is obviously safe either. `net: -0 lines possible` without a design change.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (status `reviewed`, primary gpt-5.5-pro answered by codex-headless, companion claude-headless, 2/2 voices, `verdict_quality.status: APPROVED` on the aggregate, `rejected_summary: []`, sidecar empty). Findings DISS-001, DISS-002, DISS-C-001, DISS-C-002, DISS-C-003 (blocking) and DISS-C-004 … DISS-C-007 (advisory) were each reproduced against the head code before being folded into the entries above; none was counted on the dissenter's word alone. The dissenter saw a truncated diff (8 of 17 files; `run-ablation.sh` cut mid-hunk), so its silence on the runner and the report carries no weight.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The four Changes Required above; `reviewer.md` has no `## AC Verification` walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Grader calibration 1.2.1 to 1.2.5 removes the P1 false positives without new false negatives | Fail | Changes Required 1 to 3; Observations 1 |
| run-ablation.sh plans, dispatches, retries, guards, resumes and reruns as the header states | Pass with observations | RAB-1 to RAB-20 read and matched to the code; Observations 2 |
| ablation-report.py applies the pre-registered rules on the defect unit | Fail | Changes Required 4 |
| lib/arms-common.sh extraction leaves run-arms.sh behaviour unchanged | Pass (by reading) | run-arms.bats not in the diff |
| ablation-row.sh DEC-0545 degraded rule: substitution degrades, extra model is telemetry | Pass | `head/evals/harness/ablation-row.sh:316-325`; ablation-row.bats 145-157 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries (argument regexes, `python3 -I`, literal `source` path, jq `--arg`)
- [ ] Contamination detection intact — regressions in Changes Required 1 to 3 (CWE-1333, CWE-693, CWE-178)
- [x] No shell injection: collaborators are invoked with arrays, never `eval`
- [x] Error messages do not leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The runner's header is a complete contract and the bats suite exercises every documented path against stubs, including signal handling, process groups and resume reconciliation.
- Row replacement under `flock` with a validated temp file and `mv` is the right shape for the shared tracked rows file.
- `is_pipeline_transport_failure` classifies on CLI stderr and result events only, never on the agent's words, with a test for the adversarial case.

**Areas for Improvement:**
- Grader calibrations add exemptions without their true-positive twins; each DEC should ship both assertions.
- A regex over multi-line transcript text needs a complexity bound; prefer line-wise scans.
- The report should refuse, or degrade visibly, when a producer does not emit the field its primary unit depends on.

---

## Next Steps

1. Fix Changes Required 1 to 4 (grader heredoc strip and hidden token, report defect unit via the row writer).
2. Add the true-positive tests listed under Observations 1 and the unterminated-heredoc timing test.
3. Re-grade the P1 rows affected by 1.2.2 to 1.2.5 (`--rerow`) once the grader is fixed, since contamination may have been missed.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":8,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T05:50:00Z"} -->
