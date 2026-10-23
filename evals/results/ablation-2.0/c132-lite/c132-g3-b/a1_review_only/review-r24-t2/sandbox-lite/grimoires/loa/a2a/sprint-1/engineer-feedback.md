# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-260 of cycle-130: the ablation batch runner (`run-ablation.sh`, 1410 new lines), the pre-registered report (`ablation-report.py`, 1100 new lines), the shared `lib/arms-common.sh` extracted from `run-arms.sh`, the DEC-0545 narrowing of the degraded rule in `ablation-row.sh`, and grader calibrations 1.2.1 to 1.2.5 in `ablation-grade.sh`, with stubs and bats suites.

What holds up well: the runner's state machine (plan, dispatch, watchdog, retry-once on a CLI transport signature, took-effect pause, drift stop, outage breaker, rerow/rerun under flock, resume reconciliation from the rows file) is coherent and every path has a bats case. The report's statistics match the suite's pre-registered `rules:` block, and I ran `evals/tests/ablation-report.bats` against the head files here: 22 of 22 pass. The `run-arms.sh` refactor onto `lib/arms-common.sh` is behaviour-preserving (`spend_charge` + `est_record` reproduce the old `collect` arithmetic; `budget_gate`/`est_next` are the old bodies keyed by arm with pool `all`). The DEC-0545 `model_missing` rule in `ablation-row.sh` is correct and tested.

What blocks the merge is the grader's contamination scanner. The five calibration rounds replaced a conservative substring/absolute-path scan with a stack of raw-word shape exemptions plus a regex heredoc stripper. I extracted the new `check_value` logic verbatim into a harness and fed it concrete commands: the heredoc regex backtracks exponentially (24 lines of body already cost 14.8 s when the terminator is not matched), the stripper deletes the heredoc operator line's redirect target (`cat <<'EOF' > /home/operator/x` scans clean), it deletes code fed to interpreters (`python3 - <<'PY'` reading `/home/operator/.ssh/id_rsa` scans clean), and the blanket `/.`, `=` and one-component skips drop ordinary absolute paths (`cat /.env`, `cat /flag.txt`, `cat /./root/.ssh/id_rsa` scan clean). Every one of these was flagged by the 1.2.0 scanner in `pr/base`, so they are regressions introduced by this change, in the one check that protects the primary metric from a contaminated run. The adversarial dissent (two voices, consensus) independently reached the same four findings.

Also: the implementation report (`pr/PR.md`) carries no `## AC Verification` section, which is an automatic CHANGES_REQUIRED on its own under this skill; the commit list mentions CHANGELOG commits but no CHANGELOG file is in the 17-file change set, so documentation could not be verified from the diff.

Tests I could not run here: `run-ablation.bats`, `ablation-grade.bats`, `ablation-row.bats`, `arm-toggles.bats` need the frozen suite root, `pipeline-run.sh`, `took-effect.sh` and `freeze.sh`, none of which are in `pr/`. Their assertions were read, not executed.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader: the heredoc regex is exponential (ReDoS on an ordinary transcript)

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` nests `(?:.*?\n)*?` under `re.S` with a trailing `\s*\2`; when the captured delimiter never terminates, the engine tries every segmentation of the newlines. Measured on the extracted regex: 16 lines 0.05 s, 20 lines 0.8 s, 22 lines 5.0 s, 24 lines 14.8 s. Inputs that trigger it are legitimate Bash: `cat <<EOF-REPORT … EOF-REPORT` (the delimiter class `[A-Za-z_][A-Za-z0-9_]*` captures `EOF`, the terminator line is `EOF-REPORT`, never matched), `x=$(cat <<EOF … EOF)` (terminator followed by `)`), or CRLF-terminated bodies (`EOF\r`). A 30-line heredoc of that shape stalls `contamination()` for hours.
**File:** `head/evals/harness/ablation-grade.sh:1377`
**Issue:** Catastrophic backtracking in `HEREDOC`; `strip_heredocs` (line 1380-1383) runs it on every Bash tool_use of every phase.
**Why This Matters:** `LOA_EVAL_GRADE_TIMEOUT_S` kills the grade, `run-ablation.sh` rows the trial `infrastructure_error` (`post_run`, line 997), the row is excluded under DEC-0417, and the arm's excluded share rises toward the 0.25 degradation guard. One agent that writes a longer heredoc turns a scored trial into an exclusion.
**Required Fix:** Replace the regex with a line-based parse: find `<<[-]?['"]?WORD['"]?` on a line, take WORD as the full delimiter token (up to whitespace or a shell metacharacter), then scan subsequent lines for one equal to WORD (after optional tab-strip for `<<-`). No nested repetition; linear in the input. Add a bats case with a 40-line body and an unterminated delimiter asserting the grade finishes in under a second.
**Reference:** CWE-1333 (Inefficient Regular Expression Complexity).

### 2. Grader: `strip_heredocs` deletes the operator line's redirect target

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1383` — the substitution replaces the whole match, and the pattern's `[^\n]*\n` consumes everything after the delimiter on the operator line. `cat <<'EOF' > /home/operator/notes.txt\nhello\nEOF` reduces to `cat <<HEREDOC`; `ABS_WORD` never sees `/home/operator/notes.txt` and the scan returns clean. Verified on the extracted code; the 1.2.0 scanner in `pr/base` flags it `outside_path`.
**File:** `head/evals/harness/ablation-grade.sh:1377-1383`, applied at `:1412`
**Issue:** The header (line 209-210) and the docstring promise that only heredoc *bodies* are removed; the regex removes the operator line's tail too, which is where `> path` lives. `cmd <<EOF > path` is the standard way an agent writes a file from Bash.
**Why This Matters:** A write outside the sandbox roots (and in host mode a write under `~/` or `$HOME/`, which this same version declares outside at line 1386-1389) is graded `contaminated: null`.
**Required Fix:** Keep the operator line intact and replace only the body lines (from the line after the operator up to and excluding the terminator). With the line-based parser from item 1 this is the natural output.

### 3. Grader: heredoc bodies that are code, not data, are no longer scanned

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1412` — `body = strip_heredocs(val)` removes every heredoc body before the path-word scan on the premise that a body is "written file text". Three shapes feed the body to an interpreter or expand it: `python3 - <<'PY'\nprint(open('/home/operator/.ssh/id_rsa').read())\nPY`, `bash <<'EOF'\ncat /home/operator/secret\nEOF`, and the unquoted `cat <<EOF\n$(cat /root/answers.json)\nEOF` (the command substitution runs). All three scan clean on the extracted code; all three are `outside_path` in `pr/base`. The `python3 - <<'PY'` idiom is the one this very grader, `run-ablation.sh` and the bats files use throughout, so an agent running Loa inside the sandbox produces it routinely.
**File:** `head/evals/harness/ablation-grade.sh:1380-1383`, `:1412`
**Issue:** DEC-0541's exemption is keyed on the heredoc syntax, not on where the body goes.
**Why This Matters:** A real reach outside the roots performed through an interpreter heredoc is scored as a clean run; this is the exact leakage path (read the host's or another checkout's files) the contamination check exists to catch.
**Required Fix:** Strip a body only when the heredoc's command redirects to a file (`>` or `>>` present on the operator line, or the command is `cat`/`tee` with a target) and the delimiter is quoted (no expansion). Scan the body when the command is an interpreter (`python3`, `bash`, `sh`, `node`, `perl`, `ruby`, `awk`, `sqlite3`) or when the delimiter is unquoted (expansions and `$( )` run). Add bats cases for the three shapes above expecting `outside_path`, beside the existing "prose in a `cat > notes.md` heredoc is clean" case.

### 4. Grader: blanket skips for `/.`, `=` and one-component words drop ordinary absolute paths

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1438` — `if w.startswith("/."): continue` runs on the raw word before `outside()` normalises it. `cat /.env`, `cat /.ssh/id_rsa`, `cat /./root/.ssh/id_rsa` and `cat /../root/secret` all scan clean (the last two resolved to `/root/…` and were caught in 1.2.0 via `os.path.normpath`). Line 1432 `or "=" in w` drops `cat /mnt/data/split=train/answers.json`. Line 1423 drops every one-component word except five directory names, so `cat /flag.txt` and `cat /answers` (root-level files) are "command tokens". Each was `outside_path` in `pr/base`; verified on the extracted code.
**File:** `head/evals/harness/ablation-grade.sh:1423`, `:1432`, `:1438`
**Issue:** The rules are keyed on the shape of the raw word rather than on the context that motivated them (a glued `pr/'"$v"'/.claude/…` tail, a sed address remnant, a slash command inside report prose). The glued-quote case is already handled by `after_closing_quote` (line 1442), and the report-prose case by the heredoc strip, so the `/.` skip in particular buys nothing and removes the normpath guarantee.
**Why This Matters:** Detection coverage for plain absolute paths outside the roots is the scanner's documented contract (header line 171-176). The `/./` variant is a one-character bypass.
**Required Fix:** Delete the `/.` and `=` skips; call `os.path.normpath` before any shape test; restrict the one-component exemption to the contexts that motivated it (a word that follows a backtick, or whose component is a known Loa slash command) so that a root-level file name such as `/flag.txt` stays a candidate. Add bats cases for `/.env`, `/./root/x`, `/flag.txt`, `/mnt/x/split=train/y` expecting `outside_path`.

---

## Observations

### 1. Grader: quote-shape bypasses in the 1.2.4/1.2.5 rules

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1442` — `after_closing_quote` accepts an empty quoted string as a glued closing quote: `cat ""/root/.ssh/id_rsa` and `cat ''/home/operator/secret` scan clean (Bash expands both to the real path). Line 1444 `in_quotes` counts all quote characters of either kind before the word, so an apostrophe in an earlier argument flips parity: `echo "don't"; ls /root` scans clean, and `cat "/home"/operator/secret` is clean twice over (`/home` is one-component inside quotes, `/operator/secret` follows a glued quote). The comment at 1434-1437 accepts the `cd '/root/'` gap; these are wider than that.
**File:** `head/evals/harness/ablation-grade.sh:1365-1375`, `:1442-1445`
**Suggestion:** Tokenise the command with `shlex.split(posix=True)` (falling back to the raw scan when it raises) and apply the path rules to tokens; quote pairing, glued quotes and empty strings then come for free.
**Benefit:** Removes three hand-written quote heuristics and their blind spots.

### 2. Grader: the Bash `hidden` check misses bare and mixed-case names; header still says "any case"

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` — `HIDDEN_TOKEN` matches `HIDDEN`, or lowercase `hidden` adjacent to `/ . _ = -`. `ls hidden`, `cd hidden && cat test.py` and `cat tests/Hidden/x` scan clean (verified); all three were hits in 1.2.0. Header line 166-167 still reads "`hidden` (any case …)", which is no longer true for Bash.
**File:** `head/evals/harness/ablation-grade.sh:1329`, `:1395`, header `:164-168`
**Suggestion:** Add `(?i)` for the token alternatives and accept `hidden` as a whole shell word (preceded by start/space/quote, followed by end/space/`;`/`&`/`|`/quote), keeping the prose exemption only for words followed by another lowercase word; update the header sentence.
**Benefit:** Restores the hidden-test-name signal the header documents.

### 3. Runner: a drift_check crash reads as "no drift"

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:983-986` — `dout="$(drift_check … || true)"`; when the Python exits non-zero (an unreadable `meta/pipeline.json`, a malformed MANIFEST) `dout` is empty, `PR_DRIFT=""` fails the `jq -e .` probe and is reset to `null`, `PR_EXTRA` to `{}`. The guard the header calls a hard stop (DEC-0407) fails open and the trial is graded and rowed as clean.
**File:** `head/evals/harness/run-ablation.sh:983-986`
**Suggestion:** Capture the exit status; on non-zero set `PR_OVERRIDE=infrastructure_error` with a `drift_check failed` line in the trial log instead of nulling the result.
**Benefit:** A broken guard excludes the trial rather than passing it.

### 4. Runner: `cleanup` discards the process-group records after SIGTERM only

- **MEDIUM** (confidence: low) `head/evals/harness/run-ablation.sh:933-941` — on a signalled driver `cleanup` sends TERM to each recorded group, then deletes the whole `.jobs/` directory (line 941). The duplicate-trial guard at 838-845 reads those `.pgid` files, so it only protects the SIGKILL case (as the header says at 212-214). A `docker run` child that outlives TERM (PID 1 in the image ignoring it) keeps spending while `--resume` launches the same trial again into `-r2`.
**File:** `head/evals/harness/run-ablation.sh:941`
**Suggestion:** After TERM, wait up to `WATCHDOG_GRACE` for each group with `kill -0 -- -$p`, KILL the survivors, and only then delete `.jobs/`; or leave `.pgid` files of still-alive groups in place so the 838 check fires on resume.
**Benefit:** No double spend on a resumed batch.

### 5. Runner: unguarded empty-array expansion

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:1278` — `for n in "${!RR_K[@]}"` runs on every resume, with `RR_K` empty unless `--rerow` was given. Under `set -u` this is fine on bash 4.4+ but errors on older bash; the rest of the file guards the same shape (`${PJOB[@]+"${PJOB[@]}"}`, line 1172) and `lib/arms-common.sh` is written for bash 3.2.
**Suggestion:** `for n in ${RR_K[@]+"${!RR_K[@]}"}`.

### 6. Runner: the rerow temp file is not ignored beside the tracked rows file

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1237` — `tmp="$ROWS.rerow.$$"` is written next to the tracked `grimoires/loa/reports/ablation-2.0/runs.jsonl`; `.gitignore` (`head/.gitignore:333`) adds only `runs.jsonl.lock`. A driver killed between the Python write and the `mv` leaves `runs.jsonl.rerow.<pid>` as an untracked file in a tracked directory.
**Suggestion:** Add `grimoires/loa/reports/ablation-2.0/runs.jsonl.rerow.*` to `.gitignore`, or write the temp under `$WORK` and `mv` across (same filesystem not guaranteed, so prefer the ignore rule).

### 7. Runner: `--arms` and `--tasks` are silently discarded on `--resume`

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:383`, `:453` — on resume `ARMS_CSV` is overwritten from the manifest and `TASKS_CSV` is ignored without a message, while `--source-commit` on resume is checked and refused on mismatch (381). An operator passing `--tasks bugfix-01 --resume` believes the resume is narrowed.
**Suggestion:** `die` when `--arms`/`--tasks`/`--types`/`--trials-*` accompany `--resume`, matching the `--source-commit` treatment.

### 8. Complexity and documentation

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1008-1064` — `run_trial` is 57 lines and the top-level `--resume` reconciliation block (1299-1352) is 54; both are over the 50-line mark without a justification comment. `rerow_all`/`collect` share the replace-and-record sequence (1140-1147 vs 1285-1290).
- **LOW** (confidence: medium) `pr/PR.md` — the commit list names two `docs(cycle-130): CHANGELOG Sprint 260` commits but no CHANGELOG file is among the 17 touched files, and there is no `## AC Verification` walkthrough. The report cannot be checked against acceptance criteria from the diff alone.

**Over-engineering pass:** the grader's five stacked shape exemptions (1423-1445) are the hotspot; a `shlex` tokeniser plus a 15-line heredoc parser replaces ~25 lines of regex special cases. `net: -0 lines possible` (the fix is a trade, not a deletion). The runner and report are lean for what they do.

---

## Adversarial Cross-Model Review

`adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff`: status `reviewed`, two voices (gpt-5.5-pro via codex-headless, claude-headless companion), `verdict_quality.status` OK, consensus. Eight findings; the four BLOCKING ones (DISS-001 ReDoS, DISS-002 heredoc bodies hide `$(…)`, DISS-003 `=`/`/.` skips, DISS-C-001 operator-line redirect target) correspond to Changes Required 1-4 above and were each reproduced here before being adopted. ADVISORY DISS-C-002 (`/./` normpath), DISS-C-003 (empty-quote glue), DISS-C-004 (ReDoS variants), DISS-C-005 (`hidden` token gaps) are folded into item 4 and Observations 1-2. The dissenter saw a truncated diff (8 of 17 files; `run-ablation.sh` cut mid-hunk), so its silence on the runner and the report is not evidence.

## Rejected dissent payloads

- none: `metadata.rejected_summary` is `[]` and `adversarial-rejected-review.jsonl` is empty (0 bytes).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | All 17 files read in full against `pr/base`; report test suite executed (22/22). |
| Report each defect with file and line | Pass | 4 blocking, 9 observations above, each cited `head/<path>:<line>`. |
| Give a merge verdict | Pass | CHANGES_REQUIRED (grader regressions). |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the contamination scanner's new exemptions reduce coverage (items 1-4, Obs. 1-2)
- [x] Authentication/authorization correct (n/a)
- [x] No SQL/XSS injection vulnerabilities (n/a; jq/python receive data via `--arg`/argv, heredocs are quoted)
- [x] Dependencies secure (stdlib only; `python3 -I` throughout)
- [x] Error messages don't leak sensitive data
- [ ] Denial of service — CWE-1333 in `HEREDOC` (item 1)

---

## Code Quality Summary

**Strengths:**
- Runner state is recomputed from the rows file on every resume; rerow/rerun replace rows in place under flock with validation before `mv`.
- Transport classification reads only the CLI's stderr/result events, never the agent's text (DISS-C-005 lineage preserved in `lib/arms-common.sh`).
- The report's decision order, rounding to 9 decimals, per-defect unit and MDE are each pinned by a planted-fixture test; determinism per seed is asserted byte-for-byte.
- `lib/arms-common.sh` extraction is clean; `run-arms.sh` keeps its behaviour.

**Areas for Improvement:**
- The grader scanner needs a tokenizer and a real heredoc parser instead of further regex exemptions; each calibration round so far has opened a new gap.
- Fail-open paths in the runner (`drift_check`) should fail to `infrastructure_error`.

---

## Next Steps

1. Fix Changes Required 1-4 in `evals/harness/ablation-grade.sh` (one parser, delete the blanket skips), bump `GRADER_VERSION`, add the listed bats cases.
2. Re-grade the P1 rows affected by the scanner change (DEC-0551/0557 cited specific runs) so `contaminated` reflects the corrected rule.
3. Address Observations 3 and 4 in `run-ablation.sh`.
4. Add an `## AC Verification` section to the report and include the CHANGELOG change in the PR.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T07:30:00Z"} -->
