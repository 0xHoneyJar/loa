# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22T22:06:38Z
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: the cycle-130 batch runner (`run-ablation.sh`, 1,410 lines), the pre-registered report (`ablation-report.py`), the shared `lib/arms-common.sh` extracted from `run-arms.sh`, the DEC-0545 drift/degraded narrowing in `ablation-row.sh`, and five grader calibration rounds (1.2.1 to 1.2.5) in `ablation-grade.sh`'s contamination scan, plus three new bats suites and fixtures.

The runner and the report are well built. Spend accounting reconciles (spent = rows + ledger, verified against RAB-5/RAB-19 arithmetic), the rerun/rerow/clear-drift paths keep the rows file byte-identical on every refusal, the lock and process-group handling are sound, and the report's statistics match the pre-registered rules block (task unit for pass rate, defect unit for catch rate, percentile bootstrap, degradation guard first). The `run-arms.sh` refactor onto `lib/arms-common.sh` is behaviour-preserving: `est_record "$arm" all` and `budget_gate "$a" "$n"` reproduce the removed per-arm/pooled means, and no reference to the removed `ARM_SUM`/`POOL_SUM` symbols remains.

The grader calibration is where the change introduces defects. Each of the five rounds removes a false-positive class seen in the P1 batch, but three of the new exemptions are broader than their stated rule and reopen contamination paths the 1.2.0 scan caught: the `HEREDOC` regex is exponential on an unterminated heredoc (verified: 24 body lines take 11.5 s, each 4 lines multiply by about 16), it also strips the redirect target on the heredoc's own header line (`cat <<EOF > /root/.ssh/authorized_keys` is clean), and the Bash `hidden` token rule misses the plain discovery commands (`grep -rn hidden .`, `find . -name '*hidden*'`) and mixed case (`Hidden/`) that the 1.2.0 substring check caught. The contamination scan is the integrity guard for every row this runner produces, so these block.

Tests: the bats suites could not be run in this workspace (only the 17 touched files are present; `pipeline-run.sh`, `freeze.sh`, `took-effect.sh`, `docker-stub.sh` and the frozen suite are absent). The assertions were read and checked by hand against the planted fixtures (gen-fixtures.py numbers reproduce the AR-1..AR-22 expectations). The implementation report (PR.md) carries no `## AC Verification` section and no test-run evidence.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader: the heredoc regex is exponential on an unterminated heredoc

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` is compiled with `re.S`, so `.` in `(?:.*?\n)*?` matches newlines and the inner `.*?\n` and outer `*?` are ambiguous over the same newline boundaries; when no terminator line matches, the engine tries every composition of the remaining lines.
**File:** `head/evals/harness/ablation-grade.sh:1377` (applied at `:1383` and `:1412`)
**Issue:** Measured on the committed pattern: 16 body lines 0.05 s, 20 lines 0.67 s, 24 lines 11.5 s; the growth is about 16x per 4 lines, so a 30-line unterminated heredoc runs for minutes and 40 lines never finishes. Triggers in real transcripts: a truncated agent command, a terminator written as `EOF;` or `EOF)`, or a here-string `cat <<< word` followed by more lines (the pattern accepts `<<` + space + identifier as a header).
**Why This Matters:** `strip_heredocs` runs inside `contamination()` for every Bash tool_use value of every phase. One such command stalls the grade; `run-ablation.sh` then rows the trial `infrastructure_error` on the grade timeout with no diagnostic, and the trial's spend is lost.
**Required Fix:** Drop `re.S` and make each iteration consume exactly one line so the pattern is unambiguous, e.g. `r"(?<!<)<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\2[ \t]*(?=\n|$)"`; reject `<<<` with the lookbehind. Add an AG-10 case with a 60-line unterminated heredoc asserting the grade finishes.
**Reference:** CWE-1333 (Inefficient Regular Expression Complexity)

### 2. Grader: the heredoc header's redirect target is stripped with the body

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1383` — `HEREDOC.sub("<<HEREDOC", val)` replaces the whole match, and the match includes `[^\n]*\n` after the delimiter, i.e. the rest of the header line; the path scan at `:1415` never sees a redirect written there.
**File:** `head/evals/harness/ablation-grade.sh:1383` (pattern at `:1377`)
**Issue:** Verified: `cat <<EOF > /root/.ssh/authorized_keys\nkey\nEOF\n` becomes `cat <<HEREDOC\n` and `ABS_WORD` yields no candidate. The header comment and DEC-0541 say only heredoc *bodies* are data; the redirect target is a path the agent reached.
**Why This Matters:** `cmd <<EOF > /abs/path` is the common idiom for writing a file. A write outside the sandbox through it (also `>> ~/.bashrc` in host mode) grades as not contaminated.
**Required Fix:** Capture the header remainder as a group and re-emit it (`HEREDOC.sub(r"<<HEREDOC\3", val)` with group 3 = `([^\n]*\n)`). Add an AG-10 case: `cat <<EOF > /root/x\nhi\nEOF` must yield `outside_path`.

### 3. Grader: the Bash `hidden` token rule misses discovery commands and mixed case

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` — `HIDDEN_TOKEN` counts `hidden` in Bash text only as `HIDDEN` or when glued to `/ . _ = -`; the 1.2.0 check at `:1397` was a case-insensitive substring match on every tool.
**File:** `head/evals/harness/ablation-grade.sh:1329` (applied at `:1395`)
**Issue:** Verified against the committed regex: `grep -rn hidden .`, `find . -name '*hidden*'`, `ls | grep -i hidden` and `cat /workspace/Hidden/tests.json` all return no match; the base grader flagged every one of them. The motivating false positive (DEC-0551) was prose inside a reviewer's heredoc, but `strip_heredocs` already exists for exactly that and is not used by this check, so the token rule overshoots and exempts the commands the scan exists to catch. AG-10 in `head/evals/tests/ablation-grade.bats:459` still only exercises `tests/HIDDEN_cases.py`; no test pins the discovery commands.
**Why This Matters:** An agent that greps or finds for the hidden tests is scored clean; contaminated runs inflate `hidden_test_pass_rate` in the arm they land in, and the ablation's decisions read them.
**Required Fix:** For Bash, run the plain `"hidden" in strip_heredocs(val).lower()` check on the command text (bodies removed) and apply `HIDDEN_TOKEN` only to the stripped bodies if a prose exemption is still wanted. Add AG-10 rows for `grep -rn hidden .`, `find . -name '*hidden*'` and `cat Hidden/x` → `hidden`, and keep the heredoc-prose row clean.

---

## Observations

### 1. Grader: quote-parity heuristic flips on an apostrophe

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1372` — `in_quotes` counts raw `'` and `"` independently with no nesting or escape awareness; `echo "it's"; ls /root` makes `in_quotes` true for `/root` (verified) and `:1444` skips the sensitive single-component word.
**File:** `head/evals/harness/ablation-grade.sh:1372`
**Suggestion:** Walk the body once tracking shell quoting state (outside / single / double with backslash) and record quoted spans; test membership of `m.start(1)`. Or drop the heuristic and accept the `grep ' /tmp | /home '` false positive the comment already calls marginal.
**Benefit:** `ls /root` and `ls /home` are reported whatever the preceding text contained.

### 2. Grader: any `=` in a path word exempts it

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1432` — `"=" in w` discards a multi-component absolute path when any component carries `=` (`cat /home/operator/notes=secret.txt` is a candidate for `ABS_WORD` and then skipped). `=` is legal in file names.
**File:** `head/evals/harness/ablation-grade.sh:1432`
**Suggestion:** Treat `=` as the regex / key=value marker only in the first component (`^/[^/]*=`), where the sed `s=/x=/y=` and `KEY=/value` shapes put it.
**Benefit:** Outside paths with `=` in a later component stay candidates.

### 3. Grader: the one-component whitelist of five names

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1423` — any one-component word not in `{root, home, mnt, media, srv}` is a command token: `ls /secrets`, `ls /data`, `ls /boot`, `ls /run` (and `/Users` in host mode) are skipped before `outside()` sees them.
**File:** `head/evals/harness/ablation-grade.sh:1362` and `:1423`
**Suggestion:** Invert the rule: skip only a word shaped like a Loa slash command (`^/[a-z][a-z0-9-]*$`) that is not the argument of a filesystem command (`ls cd cat find stat du tree`), or a `/x/` delimiter after `s y = ~ '`; let `outside()` decide the rest.
**Benefit:** Listing a top-level directory outside the allowed roots is reported again.

### 4. Grader: an opening quote after `[`, `{` or `:` reads as a closing quote

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1365` — `after_closing_quote` accepts any quote whose preceding character is not whitespace or one of `=(<>|;&,`; `python3 -c "for p in ['/root/.ssh/id_rsa']: ..."` has `[` before the `'`, so `/root/.ssh/id_rsa` is skipped at `:1442` (verified).
**File:** `head/evals/harness/ablation-grade.sh:1365`
**Suggestion:** Require the quoted segment to end in `$NAME"`, `${...}"`, `)"` or a segment containing `/` (the DEC-0557 shapes), or at minimum add `[ { :` to the delimiter set.
**Benefit:** Absolute paths inside Python list literals or f-strings in a `-c` one-liner stay candidates.

### 5. Grader: command substitution inside an unquoted heredoc body is stripped

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1380` — an unquoted heredoc body executes `$(…)`; `cat <<EOF\n$(cat /root/secret.txt)\nEOF` reads the outside file, but the only outside path sits in the stripped body.
**File:** `head/evals/harness/ablation-grade.sh:1380`
**Suggestion:** Keep bodies of unquoted delimiters (`<<EOF`, not `<<'EOF'`) in the scan, or scan them for `$(` / backtick spans only.
**Benefit:** Reads executed through a heredoc are judged like any other command text.

### 6. Runner: the row is appended before it is validated

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:1071` — `cat "$rowf" >> "$ROWS"` precedes `--validate`; an invalid row stays in the tracked `runs.jsonl` with the batch marked `failed`, and a later `--resume` (`:1342`) reads it as done.
**File:** `head/evals/harness/run-ablation.sh:1071`
**Suggestion:** Validate the row file on its own (or the concatenation into a temp beside the rows file, as `replace_row_try` does) and append only on success; record the rejected row under `<batch>/rejected/` for the operator.
**Benefit:** The tracked rows file never carries a row the validator refused.

### 7. Implementation report: no AC Verification, tests not evidenced

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the report is the PR description: a commit list with no `## AC Verification` walkthrough and no record of the three bats suites running (the skill treats a missing AC Verification as automatic CHANGES_REQUIRED). The suites also cannot run in this frozen workspace, so their green state is unverified here.
**File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1`
**Suggestion:** Add the AC walkthrough with `file:line` evidence per criterion and the bats run output (`run-ablation.bats`, `ablation-report.bats`, `ablation-grade.bats`) to the report.
**Benefit:** The review can confirm the acceptance criteria from evidence rather than from the diff alone.

### 8. Runner: counters advance after a failed in-place replacement

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1155` — when `replace_row_try` fails (`STOP=invalid` at `:1150`) the run is still added to `DONE_LIST` and `account_row` (`:1156`) counts a row that is not in the file.
**File:** `head/evals/harness/run-ablation.sh:1155`
**Suggestion:** Skip the done/account step when `STOP=invalid` was just set.
**Benefit:** STATUS.json per_arm and spend match the rows file even on the failure path.

### 9. Report: the table header hardcodes the 90 % interval

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:813` — "[90 % CI]" appears in the Decisions and Sensitivity headers (`:941`) while `--level` is configurable and marked in the header line at `:807`.
**File:** `head/evals/harness/ablation-report.py:813`
**Suggestion:** Format the header from `args.level`.
**Benefit:** A report at another level does not mislabel its intervals.

### 10. Runner: a batch whose trials all end `cap_failure` exits 3

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:1398` — `total_completed -eq 0` reads `failed: no trial completed` although every row is valid and scorable (cap_failure scores 0 by the rules); the header's exit-code text says "no trial completed without a cut".
**File:** `head/evals/harness/run-ablation.sh:1398`
**Suggestion:** Count `cap_failure` rows as scored for this check, or name the cap failures in the message.
**Benefit:** The exit code distinguishes an infrastructure failure from an expensive but valid batch.

### 11. Report: trials present in only one arm are paired by task mean over different trial sets

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:501` — `drop` removes a trial only when a cell exists and is invalid; a trial the control never ran stays in the arm's mean, so the per-task difference averages unequal trial sets.
**File:** `head/evals/harness/ablation-report.py:501`
**Suggestion:** Document the choice in the Method section, or drop trials absent on either side when `trials.build` is the planned count.
**Benefit:** The pairing rule is explicit for readers of the pre-registration.

### 12. Documentation: the CHANGELOG hunks are not in the diff

- **LOW** (confidence: high) `pr/PR.md:12` — two commits in the description are CHANGELOG entries for Sprint 260, but `CHANGELOG.md` is not among the 17 files in `pr/head.diff`, so the per-task entry cannot be verified here.
**File:** `pr/PR.md:12`
**Suggestion:** Include the CHANGELOG hunk in the reviewed change, or state in the report why it is out of scope.
**Benefit:** The documentation gate can be checked from the same artefact as the code.

---

## Cross-Model Observations

Two voices answered (gpt-5.5-pro via codex-headless; companion claude-headless), `rejected_summary` empty, `verdict_quality.status` APPROVED with 2/2 voices. Triage of the eleven payloads:

- DISS-001 / DISS-C-003 (hidden token misses discovery commands and mixed case): confirmed by running the regex; counted as Changes Required 3.
- DISS-C-001 (HEREDOC exponential backtracking): confirmed by timing (24 lines 11.5 s); counted as Changes Required 1.
- DISS-C-002 (redirect target stripped with the heredoc header): confirmed; counted as Changes Required 2.
- DISS-004 / DISS-C-004 (in_quotes parity): confirmed; Observation 1.
- DISS-003 / DISS-C-006 (`=` exemption): confirmed; Observation 2.
- DISS-C-005 (one-component whitelist): confirmed; Observation 3.
- DISS-C-007 (after_closing_quote after `[`): confirmed by running the helper; Observation 4.
- DISS-002 (command substitution inside an unquoted heredoc): true by construction; Observation 5.

## Rejected dissent payloads

- none: `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` holds no rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The three grader defects above; the AC Verification walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each introduced defect reported with file and line | Pass | Twelve findings above, three blocking, all cited as `head/<path>:<line>` |
| Merge verdict | Pass | CHANGES_REQUIRED (three HIGH findings in the contamination scan) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries (`--batch`, `--arms`, `--tasks`, `--rerow`/`--rerun` ids, `--image`, env knobs are regex-validated; the row and manifest readers reject unknown schema majors; symlink refusal on `--out`/`--json` and MANIFEST.json)
- [ ] Contamination scan regressions (Changes Required 1 to 3; CWE-1333 for the regex)
- [x] No shell injection: collaborators are invoked as argv arrays; `source ./lib/arms-common.sh` is a literal path
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Spend accounting reconciles across resume, retry, rerow and rerun (`spent = rows + ledger`), and every refusal path leaves the rows file byte-identical.
- The report pins its numbers (planted fixtures reproduce AR-1..AR-22), one RNG per interval, 9-decimal predicate rounding, and quotes the pre-registered rules block verbatim.
- Process-group handling (setsid per trial, `.jobs/*.pgid`, SIGTERM then SIGKILL, refusal while an orphaned group lives) is careful.
- `run-arms.sh` keeps behaviour through the `lib/arms-common.sh` extraction; no dangling symbol.

**Areas for Improvement:**
- The grader's five calibration rounds are each a narrow exemption added to one 60-line function; a small shell-word tokenizer (quoting state, heredoc headers kept, bodies dropped) would replace four heuristics and remove the regressions.
- SIMPLICITY[shrink]: `check_value` is now over 60 lines with six `continue` exemptions in a row; lift the word classification into a `classify_word(body, m)` helper with one test table.
- `run-ablation.sh` at 1,410 lines mixes pre-flight, planning, dispatch and reconciliation; the `--rerow`/`--rerun` resume reconciliation would read better as its own sourced file.

Complexity pass: net: -40 lines possible (word classifier replaces the exemption chain; `append_and_validate` and `replace_row_try` share one validate-then-commit helper).

---

## Next Steps

1. Fix the three grader defects (heredoc regex, header remainder, hidden token rule) and add the AG-10 rows named above.
2. Address the medium observations in the grader's word classification, or record the accepted gaps in a DEC entry.
3. Add the AC Verification walkthrough and the bats run evidence to `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T22:06:38Z"} -->
