# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task review-r24)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 0 high excluded)

Scope: `pr/head.diff` (17 files, sha256 `ef220a96…`), every file under `pr/head/` against `pr/base/`. Citations are `head/<path>:<line>` with line numbers from the `pr/head/` files.

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope notes

- **Prerequisite deviation.** The skill's Phase 0 requires `engineer-feedback.md` to say "All good". It says CHANGES REQUIRED. The task brief mandates the audit regardless, so the audit ran; this file does not approve anything the review blocked.
- **Dissent.** `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` completed: primary gpt-5.5-pro answered by codex-headless, companion claude-headless, 2/2 voices succeeded, `chain_health: ok`, `degraded: false`, 6 findings, 0 rejected payloads. The script truncated the input to the token budget: 8 of 17 files were shown and `run-ablation.sh` was cut mid-hunk, so the runner findings below rest on my reading and the review's, not on the dissent.
- **Trust model.** The agent under evaluation (Claude Code inside the container) is the untrusted party. Its `transcripts/events-*.jsonl` tool_use inputs are attacker-controlled text that `ablation-grade.sh` parses; the contamination scan is the only control that keeps a run that reached the hidden tests or files outside the sandbox out of `runs.jsonl` and the pre-registered analysis. MANIFEST/STATUS/rows and the suite are trusted operator state.
- **Verification.** The contamination functions of `pr/base` and `pr/head` were extracted into a Python harness (`/tmp/audit-harness/`) and fed identical inputs; every regression below is a base-hit / head-clean pair observed there. `bash -n` and `py_compile` pass on every script. `run-ablation.bats`, `ablation-grade.bats` and `ablation-row.bats` cannot run in this workspace (collaborators and the frozen suite are outside the diff). Recon and sink tracing: `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`; machine-readable findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`.

---

## Executive Summary

The batch runner, the shared library extraction and the report generator are careful work: CLI arguments are regex-validated at the trust boundary (`head/evals/harness/run-ablation.sh:307-351`), every external call uses argv arrays or `jq --arg`, the rows file is written under `flock`, the report refuses symlinked outputs, and the transport-failure detector reads only the CLI's stderr so the agent under test cannot earn itself a retry.

The blocking problems are all in the grader calibration (`ablation-grade.sh` 1.2.2 to 1.2.5). Four successive fixes for observed false positives each widened a skip rule past the shape that motivated it, and none shipped with a paired false-negative test. The result is that the contamination gate now (a) can be stalled indefinitely by one malformed Bash command, because the new heredoc regex backtracks exponentially and nothing in the grader or the runner bounds the scan, and (b) misses several realistic shapes of the exact behaviour it exists to catch: executed heredoc bodies, redirect targets on a heredoc header line, command substitutions in unquoted heredocs, case-insensitive `hidden` probes, and a bare `cd hidden`. A run that reached outside the sandbox or searched for the answer key is rowed `completed`, `contaminated: null`, and enters the paired analysis as valid data. Because `hidden_test_pass_rate` is the primary the report decides on, these are integrity defects in the evaluation, not cosmetic ones.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 6 |
| Low | 5 |

---

## High Priority Security Issues (Fix Before Re-audit)

### [HIGH-001] Heredoc regex backtracks exponentially on agent-controlled input; nothing bounds the scan

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex), `:1383` (`HEREDOC.sub`), `:1412` (called per Bash command), `:1476` (`contamination`), `:1622` (called from `grade`); `head/evals/harness/run-ablation.sh:996` (grade call, no timeout), `:1031` (`.pgid` removed before `post_run`), `:1194-1210` (`reap` waits forever)
**Issue:**
```python
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
```
Under `re.S` the `.` in `(?:.*?\n)*?` matches newlines, so when the terminator never appears the engine tries every partition of the following newlines. Measured on the extracted function with an unterminated `cat <<EOF`: 14 lines 0.012 s, 16 lines 0.042 s, 18 lines 0.166 s, 20 lines 0.690 s (×4 per two lines), so 30 lines is about 12 minutes and 40 lines does not return. Realistic triggers measured at 20 lines: a mistyped terminator (`EFO`) 0.45 s, `x=$((a<<b))` followed by a script 0.11 s, `<<EOF` inside a quoted string (`git commit -m 'use <<EOF here'`) 0.31 s. Bash accepts an unterminated heredoc with a warning and executes it, so this input arises from an executed command, and the agent under test authors it.
**Impact:** `contamination()` never returns. The dissent (DISS-C-003) assumed `LOA_EVAL_GRADE_TIMEOUT_S` or the runner watchdog would convert this to `infrastructure_error`; neither does. `TEST_TIMEOUT_S` (`ablation-grade.sh:262`) bounds only the docker test commands, and the watchdog reads `.jobs/<jid>.pgid`, which `run_trial` deletes at `run-ablation.sh:1031` before `post_run` runs the grade at `:996`. The trial subshell never writes its `.result`, `reap` waits forever, the concurrency slot is held, and the batch hangs with no row, no status change and no log line. One malformed command in one transcript stalls a whole paid batch.
**Fix:**
1. Make every repetition consume exactly one line and drop `re.S`; keep the header line (see HIGH-002):
```python
HEREDOC = re.compile(r"(<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2[^\n]*\n)(?:[^\n]*\n)*?[ \t]*\3[ \t]*(?=\n|$)")
body = HEREDOC.sub(lambda m: m.group(1) + "<<HEREDOC", val)
```
   Verified in the harness: 5,000 unterminated lines in 1.1 ms.
2. Defence in depth in the runner: run the grade under `timeout` (e.g. `timeout --kill-after=10 "$grade_s" "${g[@]}"`) and row a timed-out grade `infrastructure_error`, so no grader bug can hang the batch again.
3. Add an AG case with a 40-line unterminated heredoc under a time bound.
**Reference:** CWE-1333 Inefficient Regular Expression Complexity (https://cwe.mitre.org/data/definitions/1333.html); CWE-400 Uncontrolled Resource Consumption (https://cwe.mitre.org/data/definitions/400.html)

### [HIGH-002] Heredoc stripping removes executed bodies, header-line redirect targets and command substitutions from the outside-path scan

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:1377-1383` (rule), `:1412` (`body = strip_heredocs(val)` before the `ABS_WORD` loop)
**Issue:** DEC-0541's rationale, "written file text is data", holds only for a literal body written by a non-interpreter command. The implementation strips every heredoc body and, through `[^\n]*\n` at `:1377`, the rest of the header line. Harness results, container mode, head `None` / base `outside_path`:
```
python3 - <<'PY'\nprint(open('/root/.ssh/id_rsa').read())\nPY        (the heredoc IS the program)
bash <<EOF\ncat /home/operator/secret\nEOF
cat <<'EOF' > /root/.ssh/authorized_keys\nssh-rsa AAAA\nEOF         (write target on the header line)
cat <<EOF | tee /home/operator/notes.txt\nhello\nEOF
cat <<EOF\n$(cat /mnt/private/token)\nEOF                            (unquoted delimiter: $(...) is executed)
cat <<EOF > out.txt\n$(cat /root/.ssh/id_rsa)\nEOF
```
`cmd <<EOF > target` is the dominant heredoc idiom in agent transcripts and `python3 - <<'PY'` is the pattern this repository itself uses, so these are not deliberate-evasion-only shapes. The hidden/suite/repo substring scans still read the full value (`:1393-1401`); only the outside-path check, the one that detects arbitrary file reads outside the sandbox roots, is blind.
**Impact:** A trial that read or wrote outside the sandbox through a heredoc is graded `contaminated: null`, rowed `completed`, and counted as a valid observation in the paired analysis the report decides on. The grader's documented rule ("an absolute path … outside … → outside_path", header `:171-181`) is silently violated for the most common heredoc form.
**Fix:** Keep the header line in `body` (the grouped regex in HIGH-001). Strip a body only when the delimiter is quoted (`<<'EOF'` / `<<"EOF"`: no expansion) AND the command word before `<<` is not an interpreter (`bash|sh|zsh|dash|python[0-9.]*|node|perl|ruby|awk|eval|xargs|env|source|\.`); scan every other body with the same `ABS_WORD` loop (an unquoted-delimiter body expands `$(…)`, backticks and `$VAR`, so it is not inert text). Add AG cases: `python3 - <<'PY'` reaching `/root/…` (hit), `cat <<'EOF' > /root/x` (hit), `cat <<EOF\n$(cat /mnt/x)\nEOF` (hit), `cat > notes.md <<'EOF'` naming `/home/operator` (clean).
**Reference:** CWE-184 Incomplete List of Disallowed Inputs (https://cwe.mitre.org/data/definitions/184.html); CWE-693 Protection Mechanism Failure (https://cwe.mitre.org/data/definitions/693.html)

### [HIGH-003] The hidden-test probe is no longer detected for the common Bash shapes

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:1329` (`HIDDEN_TOKEN`), `:1394-1397` (applied to Bash only; Read/Grep/Glob keep the any-case substring)
**Issue:**
```python
HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")
```
matches `hidden` only in capitals or adjacent to `/ . _ = -`. Harness results, head `None` / base `hidden`: `grep -ri hidden .`, `find . -iname '*hidden*'`, `ls hidden`, `cd hidden && ls`, `cd hidden; cat *`, `ls HiddenTests`. Only `ls hidden/`, `cat hidden/*` and `tests/hidden_test.py` still hit. DEC-0551 was motivated by English prose inside a reviewer's heredoc; the fix tightened the rule for the whole command text, so the most direct probes for the answer key, a case-insensitive grep or find for the word and a bare directory argument, pass as clean, while Bash is the tool with the widest reach.
**Impact:** A run that searched for, changed into, or listed the hidden tests is counted as a valid `hidden_test_pass_rate` observation, the primary metric the pre-registered decision rules read.
**Fix:** Outside stripped heredoc bodies use the base rule (`"hidden" in low`, or at least `(?i)\bhidden`); inside heredoc bodies keep the token-shape rule. Keep the two DEC-0551 prose examples (both inside heredocs) as the clean cases and add `grep -ri hidden .`, `find . -iname '*hidden*'`, `cd hidden && ls` and `ls HiddenTests` as hits.
**Reference:** CWE-184 (https://cwe.mitre.org/data/definitions/184.html)

---

## Medium Priority Issues

### [MED-001] `in_quotes` uses quote parity, so one apostrophe hides every later `/root` or `/home`

- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:1372-1374`, applied at `:1444`
- **Issue:** `seg.count("'") % 2 == 1 or seg.count('"') % 2 == 1` treats an apostrophe inside a double-quoted string as an open single quote. Harness: `echo "don't panic"; cd /root && cat .ssh/id_rsa` → `None` (base `outside_path`); `echo "it's fine" && ls /home` → `None`. Apostrophes in `echo` and commit-message strings are ordinary agent output; the carve-out was calibrated on `grep -E ' /tmp | /home '`.
- **Fix:** Walk the text once tracking the open quote (a `'` inside `"…"` is literal, `\"` is escaped), or require the quote to open on the same word as the match.
- **Reference:** CWE-184 (https://cwe.mitre.org/data/definitions/184.html)

### [MED-002] The `/.` skip runs on the raw word before normalisation

- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:1438`; `os.path.normpath` only runs later inside `outside()` at `:1353`
- **Issue:** `if w.startswith("/."): continue` drops `/./root/.ssh/id_rsa`, `/../root/.ssh/id_rsa` (both normalise to `/root/…`) and the real root files `/.dockerenv` and `/.dockerinit`, the standard "am I in a container" probe. All were `outside_path` in the base grader; all are clean now. The motivating case (`pr/'"$v"'/.claude/…`) is a word that follows a closing quote.
- **Fix:** Normalise first; apply the dot-directory rule only to a word that follows a closing quote (the DEC-0551 shape) and only to the normalised first component.
- **Reference:** CWE-41 Improper Resolution of Path Equivalence (https://cwe.mitre.org/data/definitions/41.html)

### [MED-003] In container mode home-prefixed words are never normalised or made candidates

- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:1350-1352` (`outside` returns `home_word_outside()` without normalising), `:1386-1389`, `:1409` (path fields), `:1412-1414` (Bash)
- **Issue:** `home_word_outside()` is `False` in the container, so `~/`, `$HOME/` and `${HOME}/` words are allowed as a class. Harness: `cat ~/../../root/.ssh/id_rsa`, `cat $HOME/../../etc/shadow` and a Read of `~/../../etc/shadow` are clean (base `outside_path`). The rationale (the home resolves under an allowed root) holds only for paths that stay under the home.
- **Fix:** Rewrite the prefix to `/home/evaluser` in container mode and run the word through `outside()` like any other candidate (normpath, `SENSITIVE`, roots).
- **Reference:** CWE-22 Improper Limitation of a Pathname to a Restricted Directory (https://cwe.mitre.org/data/definitions/22.html)

### [MED-004] `cleanup` deletes `.jobs/` right after SIGTERM, defeating the duplicate-launch guard on resume

- **Severity:** MEDIUM | **Confidence:** medium
- **File:** `head/evals/harness/run-ablation.sh:933-943` (`cleanup`: TERM each group, then remove `$JOBS_DIR`), guard at `:838-845`, `on_signal` at `:1212-1217`
- **Issue:** The guard that refuses a start "while a process group recorded under `<batch>/.jobs/` by an earlier driver is still alive" only sees `.pgid` files. `cleanup` sends TERM and unconditionally removes the directory without waiting or confirming the groups died. A pipeline that outlives TERM (a `docker run` child, a phase that traps) keeps spending with no record; the next `--resume` launches the same trial again into `-r2` and both bill against the same cap. RAB-13 exercises the guard only for a SIGKILLed driver with a `sleep` that dies on TERM.
- **Fix:** After TERM wait up to `WATCHDOG_GRACE`, SIGKILL, and delete only the `.pgid` files whose group is dead; leave the others so the guard fires on resume.
- **Reference:** CWE-459 Incomplete Cleanup (https://cwe.mitre.org/data/definitions/459.html)

### [MED-005] `rerun_pending` is written but never read back on `--resume`

- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/evals/harness/run-ablation.sh:863` (`RERUN_LIST` initialised empty), `:918` (`rerun_pending` written to STATUS.json), `:1296-1341` (resume reconciliation reads cuts, retries, paused_arms, ledger, extra models, drift_cleared, rerowed, rerun, outage_history, but not `rerun_pending`; `RERUN_LIST` is seeded only from `--rerun`/`--rerun-status` at `:1338`)
- **Issue:** A resume that flags reruns and stops before dispatching them (a cut, the outage breaker, a signal) records them as pending. The next plain `--resume` treats their stale `transport_error`/`interrupted` rows as done, reports `partial … excluded` or `complete`, and the documented state is silently dropped unless the operator re-passes the flags.
- **Fix:** Union `rerun_pending` from STATUS.json into `RERUN_LIST` (and the rows' status/cost into `RERUN_OLD`) on resume, or clear `rerun_pending` and log that the flags must be re-passed.
- **Reference:** CWE-440 Expected Behavior Violation (https://cwe.mitre.org/data/definitions/440.html)

### [MED-006] Security-relevant grader changes ship without the records the commits cite; no test evidence in the report

- **Severity:** MEDIUM | **Confidence:** low
- **File:** `head/evals/harness/ablation-grade.sh:258` (`GRADER_VERSION = "1.2.5"`, from 1.2.0), header `:199-212`
- **Issue:** Five calibration rounds loosen the contamination rules and `run-ablation.sh` gains a dozen flags, yet the diff carries no CHANGELOG, NOTES or DEC-05xx record although six commit messages in `pr/PR.md` cite "CHANGELOG Sprint 260" and DEC-0540 … DEC-0559. The implementation report has no AC walkthrough and no evidence that `bats evals/tests/*.bats` or shellcheck ran. No `documentation-coherence-*` report exists under `grimoires/loa/a2a/subagent-reports/`; the script headers themselves are complete and were verified manually. If the records exist on the real branch nothing is needed; if not, the rule changes to the only security control in the diff are undocumented outside the script header.
- **Fix:** Include the CHANGELOG/DEC entries in the change, and record the bats and shellcheck output in the implementation report.

---

## Low Priority Issues

### [LOW-001] Further evasion shapes opened by the new skip rules (deliberate-evasion class)

- **File:** `head/evals/harness/ablation-grade.sh:1365-1369` (`after_closing_quote`), `:1330` with `:1423` (`ABS_WORD` and the one-component skip), `:1432` (`/,` and `=` carve-outs), `:1362` (`SENSITIVE_SINGLE`)
- **Issue:** All head-clean / base-`outside_path` in the harness: `cat ''/root/.ssh/id_rsa`, `cat ""/root/secret`, `cat "$X"/root/.ssh/id_rsa` (X unset), `cat $'/root/secret'` (ANSI-C quoting; `$` two back is not an operator); `cat /roo?/secret`, `cat /r*/secret`, `cat /ro{o,}t/secret` (glob characters end the `ABS_WORD` match, leaving a one-component word that is skipped); `cat /root/x=1`, `cat /root/,x`; host mode `cd /Users && ls` (macOS homes; `run`, `private` also missing). These need unusual shell from the agent, so impact is limited, but each is cheap to close.
- **Fix:** Require a non-empty quoted span whose opener is preceded by a token character in `after_closing_quote`; extend `ABS_WORD`'s class with `?*[]{}` or apply the one-component skip only when the word is followed by whitespace or end; restrict the `=` rule to `key=/path` shapes; add `Users`, `run`, `private` to `SENSITIVE_SINGLE`.
- **Reference:** CWE-184 (https://cwe.mitre.org/data/definitions/184.html)

### [LOW-002] A trial that ends without a row loses its assumed charge on resume and resets the outage breaker

- **File:** `head/evals/harness/run-ablation.sh:1120-1125` (no `.result`), `:1158-1161` (no row), `:1123` (`outage_tick "$rid" ""`), resume spend rebuilt from rows + ledger at `:1304` and `:1344`
- **Issue:** The `RUN_CAP` charge lives only in this driver's `SPENT`; the pipeline's real `spent_usd` is never read into the ledger; and an empty status resets `OUTAGE_RUN` as if the trial had succeeded.
- **Fix:** Read `meta/pipeline.json spent_usd` into the ledger for a rowless trial; treat "no row" as neutral for the breaker.

### [LOW-003] Stale `cuts[]` makes any later partial end read "cut max_usd"

- **File:** `head/evals/harness/run-ablation.sh:1302` (reloaded), `:1395` (`CUTS_JSON != '[]' && left > 0`)
- **Fix:** Test `STOP == cut` for the message; keep `cuts[]` as history.

### [LOW-004] Duplicate check counts only the compact `"run_id":"…"` form

- **File:** `head/evals/harness/run-ablation.sh:1075` (`grep -cF`), while the resume path uses jq at `:1324`
- **Issue:** A valid row written with `": "` separators counts 0 and the batch ends `failed 3` with "run_id rowed 0 times".
- **Fix:** Count with the same jq filter as `:1324`.

### [LOW-005] A task id with two `task_type` values silently takes the last row's type

- **File:** `head/evals/harness/ablation-report.py:442`; the `arm_map` conflict at `:431-433` raises `Fail`, this does not
- **Fix:** Raise `Fail` on a conflicting `task_type` for one task id.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (type audit, primary gpt-5.5-pro via codex-headless, companion claude-headless independent, 2/2 succeeded, `chain_health: ok`, `degraded: false`, hallucination filter applied, 0 downgraded). Every finding was re-run in the harness before folding:

- DISS-001 (MEDIUM, `$(…)` inside an unquoted heredoc body is executed yet stripped) → folded into HIGH-002 as a third shape; confirmed (`cat <<EOF\n$(cat /mnt/private/token)\nEOF` base hit, head clean).
- DISS-C-001 (MEDIUM, interpreter heredocs) → HIGH-002. Confirmed by cross-model review.
- DISS-C-002 (MEDIUM, `""/root/x`, `$'/root/secret'`) → LOW-001; confirmed.
- DISS-C-003 (MEDIUM, HEREDOC backtracking) → HIGH-001. Confirmed by cross-model review; its failure mode (timeout → `infrastructure_error`) is corrected above: no timeout covers the scan, the batch hangs.
- DISS-C-004 (MEDIUM, `hidden` case/bare word) → HIGH-003. Confirmed by cross-model review.
- DISS-C-005 (LOW, glob-shaped one-component words; `in_quotes` parity) → LOW-001 and MED-001; confirmed.

The dissent rated the four grader regressions MEDIUM. I rate HIGH-001 to HIGH-003 HIGH because the affected check is the sole integrity control between an untrusted agent's run and the pre-registered decision, the inputs are the agent's own and realistic, and the hang has no bound.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-audit.jsonl` holds 0 rows.

---

## Category Scores (resources/RUBRICS.md)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.6/5 | IV:3 (contamination parsing regressions) AZ:4 (roots allow-list sound) CI:4 IN:5 (argv arrays, `jq --arg`, no eval) AV:2 (unbounded scan, no grade timeout) |
| Architecture | 4.2/5 | MO:4 (shared lib extraction clean) SC:4 RE:4 (watchdog, breaker, resume) CX:4 ST:5 |
| Code Quality | 3.8/5 | RD:4 TC:3 (no paired false-negative tests for 1.2.2–1.2.5) EH:4 DC:4 |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 (resume reconciliation; MED-004/005) DS:4 |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation at the CLI boundary (`run-ablation.sh:307-351`; report refuses unknown schema majors and symlinked outputs)
- [x] No shell string interpolation (`subprocess.run([...])`, `jq --arg`, argv arrays throughout)
- [x] Transport-failure detection reads the CLI's stderr only (`lib/arms-common.sh:60-62`), never the agent's text
- [ ] Contamination guard: regressions HIGH-001..003, MED-001..003, LOW-001
- [ ] Availability: untrusted input can stall the grade and the batch (HIGH-001)
- [x] Error messages do not leak sensitive data
- [ ] Tests cover security paths: AG-10 asserts only the new clean cases; no base-hit regression cases

---

## Positive Findings

- Every calibration rule carries its DEC id and the observed case; the headers are complete specifications.
- Rows file writes are under `flock`, with validation and an in-place replace that leaves the file untouched on failure (`run-ablation.sh:1234-1262`).
- The report pins determinism per interval and quotes the pre-registered rules block verbatim.

---

## Next Steps

1. Fix HIGH-001 (linear heredoc regex, grade `timeout` in the runner), HIGH-002 (keep header lines; scan interpreter and unquoted heredoc bodies) and HIGH-003 (base `hidden` rule outside heredoc bodies), each with paired AG cases that assert the base behaviour on the shapes listed here.
2. Close MED-001..003 in the same pass; they are small and in the same function.
3. Decide MED-004/005 for the runner before the next resumed batch.
4. Run `bats evals/tests/ablation-grade.bats evals/tests/run-ablation.bats` and record the output in the implementation report; then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:19:00Z"} -->
