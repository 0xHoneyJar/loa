# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries pr/PR.md)
**Change under audit:** pr/head.diff (17 files; citations are `head/<path>:<line>` with lines from pr/head/)
**Task:** review-r24

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint adds the ablation batch runner (`run-ablation.sh`), the shared spend/transport library (`lib/arms-common.sh`), the pre-registered report (`ablation-report.py`), the DEC-0545 substitution rule in `ablation-row.sh`, and five calibration rounds of the grader's contamination check (`ablation-grade.sh` 1.2.1 to 1.2.5). The runner and the report are sound: every CLI argument that reaches a path or a process is regex-validated (`run-ablation.sh:310-351`), JSON is built with `jq --arg`/`--argjson` throughout, rows are appended and replaced under `flock` on a sibling lock file, the report refuses symlinked inputs and outputs, and the report test suite passes 22 of 22 on the head tree.

The security problems sit in one place: the grader's contamination classifier, which is the trust boundary between the agent under test and the decision dataset. Each calibration round added a lexical skip rule to silence a false positive, and the rules now suppress true positives on ordinary, non-adversarial command shapes. Three regressions against grader 1.2.0 are confirmed by executing the head `check_value` on the inputs quoted below: the Bash `hidden` scan is now case-sensitive and adjacency-gated; heredoc bodies are stripped even when the heredoc is the program an interpreter runs; and the heredoc regex backtracks exponentially on an unterminated `<<WORD`, so an agent's transcript can stall the grader until the timeout rows the trial `infrastructure_error`. The remaining skips (`/.`, glued quotes, `=`, quote parity) are narrower bypasses. Both independent dissent voices (codex-headless and claude-headless, consensus, 2 of 2) reached the same three highs.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 2 |
| Low | 6 |

**Prerequisite note.** Phase 0 of this skill expects the review's `engineer-feedback.md` to read "All good"; it reads CHANGES_REQUIRED (2 high). The run orchestrator asked for the audit regardless and forbade questions, so the audit ran and this deviation is recorded here rather than acted on.

**Scope limits.** The dissent prompt was truncated to the token budget: 8 of 17 files were sent and `run-ablation.sh` was cut mid-hunk (the run's stderr log). The envelope is not marked degraded, both voices completed, and the files the voices did not see (`run-ablation.sh` tail, `lib/arms-common.sh`, `ablation-report.py`, the tests and fixtures) were read in full by this auditor. `evals/tests/run-ablation.bats` and `ablation-grade.bats` were not executed: they need `freeze.sh`, `took-effect.sh`, `pipeline-run.sh`, the frozen suite root and the docker stub, none of which the frozen PR tree holds; their assertions were read instead. `shellcheck` and `br` are not installed here.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The Bash `hidden` scan is case-sensitive and adjacency-gated, so ordinary probes for the hidden tests grade clean

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1329` (used at `:1395`; header still says "any case" at `:167`)
**Issue:** Grader 1.2.0 flagged `"hidden" in val.lower()` for every tool. Grader 1.2.4 replaces that for Bash with

```python
HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")
```

which matches only all-caps `HIDDEN` or lowercase `hidden` glued to `/ . _ = -`. Quote, glob and space neighbours are not in the adjacency classes, and `Hidden` in any mixed case never matches. Executed on the head code (`A.executor = "container"`): `grep -ri hidden .`, `find . -iname '*hidden*'`, `ls Hidden/`, `ls hidden`, `cat Hidden_x` and `find / -iname 'hidden*'` all return `None`; grader 1.2.0 returned `"hidden"` for each. DEC-0551's stated intent was to exempt English prose inside a reviewer's heredoc; the fix instead narrowed the token shape for the whole command.
**Impact:** A run that enumerates or reads the hidden test directory through Bash is scored as valid data and enters the pass-rate comparison the pre-registered analysis decides on. Bash is the richest tool channel, and these are the natural, non-adversarial spellings.
**Fix:** Keep the prose exemption scoped to heredoc bodies: run a case-insensitive `\bhidden\b` scan on `strip_heredocs(val)` and keep the token-shape scan, made case-insensitive, on the full value. Add AG-10 cases for the six commands above. Update the header at `:167`.
**Reference:** CWE-178 Improper Handling of Case Sensitivity https://cwe.mitre.org/data/definitions/178.html ; CWE-693 Protection Mechanism Failure https://cwe.mitre.org/data/definitions/693.html
**Cross-model:** Confirmed by cross-model review (DISS-C-003, claude-headless, HIGH).

### [HIGH-002] `strip_heredocs` removes heredoc bodies that the shell executes, hiding every outside path they contain

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1380-1383` (applied at `:1412`)
**Issue:** The docstring's premise is "file text being written is data, not a path the agent reached". That is true only for a heredoc that lands in a file through `cat >`. When the heredoc is the standard input of an interpreter, or its delimiter is unquoted, the body runs in the sandbox. Executed on the head code, each of the following returns `None`, where grader 1.2.0 returned `"outside_path"`:

```
python3 - <<'EOF'
print(open('/home/operator/notes.txt').read())
EOF
```
```
bash <<EOF
cat /root/.ssh/id_rsa
EOF
```
```
cat <<EOF
$(cat /home/operator/notes.txt)
EOF
```
```
cat > /tmp/s.sh <<'EOF'
cat /home/operator/notes.txt
EOF
bash /tmp/s.sh
```

`python3 - <<'PY'` is the idiom this very grader and `run-ablation.sh` use for inline scripts, so it is a shape the agents under test emit routinely.
**Impact:** The outside-path check is the only control that catches arbitrary reads outside the sandbox roots (the `hidden`/suite/repo substring scans still read the full value, but only for those three strings). Any interpreter-driven read is now invisible to contamination grading.
**Fix:** Strip only bodies that are inert data: a quoted delimiter (`<<'EOF'`, `<<"EOF"`) whose command is a writer (`cat`, `tee`, redirection to a file). For an interpreter command (`python3 -`, `bash`, `sh -s`, `node -`, `perl -`), or any unquoted delimiter, scan the body with the path-word loop (at least `$(...)` and backtick spans for the unquoted case). Add AG-10 cases for the four commands above.
**Reference:** CWE-693 Protection Mechanism Failure https://cwe.mitre.org/data/definitions/693.html ; OWASP A04:2021 Insecure Design https://owasp.org/Top10/A04_2021-Insecure_Design/
**Cross-model:** Confirmed by cross-model review (DISS-C-001 HIGH, claude-headless; DISS-002 MEDIUM, gpt-5.5-pro). The review counted the `$(...)` case as MEDIUM; the interpreter case widens it to the common shape, hence HIGH here.

### [HIGH-003] The `HEREDOC` regex backtracks exponentially on an unterminated heredoc, stalling the grade

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1377`
**Issue:**

```python
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
```

Under `re.S` the `.` in `(?:.*?\n)*?` also matches newlines, so a body of N lines can be split into chunks in 2^N ways. When no terminator line follows, every split is tried. Measured on the head regex with `cat <<EOF` followed by N plain lines: 12 lines 0.003 s, 16 lines 0.046 s, 18 lines 0.121 s, 20 lines 0.469 s; the review measured 2.1 s at 22. Roughly ×4 per two lines, so a few dozen lines exceed any `LOA_EVAL_GRADE_TIMEOUT_S`. Triggers are a truncated tool input, a terminator glued to `)` or `;`, or `<<WORD` inside a quoted string.
**Impact:** The input is the agent's own Bash command text from `transcripts/events-*.jsonl`. A stalled grade is killed, `run-ablation.sh` rows the trial `infrastructure_error` (`head/evals/harness/run-ablation.sh:996-997`), the cell leaves the analysis and the arm moves toward the degradation guard. An agent escapes grading of a run by emitting one malformed heredoc.
**Fix:** Drop `re.S` and make each body chunk exactly one line, for example `(?:[^\n]*\n)*?[ \t]*\2[ \t]*(?=\n|$)`; the match is then linear. Add a timing test with an unterminated heredoc of a few hundred lines.
**Reference:** CWE-1333 Inefficient Regular Expression Complexity https://cwe.mitre.org/data/definitions/1333.html ; CWE-400 Uncontrolled Resource Consumption https://cwe.mitre.org/data/definitions/400.html
**Cross-model:** Confirmed by cross-model review (DISS-C-005, claude-headless, MEDIUM).

---

## Medium/Low Priority Issues

### [MED-001] `after_closing_quote` reads any glued quote as a closing one, so `''/`, `""/` and `$'...'` hide an absolute path
- **File:** `head/evals/harness/ablation-grade.sh:1365-1369` (used at `:1442`)
- **Severity:** MEDIUM (confidence: high)
- **Issue:** The function decides from one preceding character. An opening quote glued to the path is read as a closing one. Executed on the head code: `cat ''/home/operator/notes.txt`, `cat ""/home/operator/notes.txt`, `cat $'/home/operator/notes.txt'` and `grep -f"/root/x" y` return `None`; grader 1.2.0 flagged the first. The `$'...'` form is new to 1.2.5: `$` is not in the separator list, so the ANSI-C quote counts as closing.
- **Fix:** Walk quote state instead of reading one character; treat an empty `''`/`""` before `/` as a separator and `$'` / `$"` as an opening quote.
- **Reference:** CWE-20 Improper Input Validation https://cwe.mitre.org/data/definitions/20.html
- **Cross-model:** Confirmed by cross-model review (DISS-C-002, claude-headless).

### [MED-002] The `/.` skip runs before normalisation, so `/./home/...` is never checked against the roots
- **File:** `head/evals/harness/ablation-grade.sh:1438`
- **Severity:** MEDIUM (confidence: high)
- **Issue:** `if w.startswith("/."): continue` was written for `/.claude/<file>` after a quote. It also drops `/./root/.ssh/id_rsa`, `/./home/operator/notes.txt` and `R=/./root; cat $R/.ssh/id_rsa`, which the kernel resolves to the undotted path and which `outside()` would have normalised and flagged. Executed on the head code: all three return `None`; grader 1.2.0 flagged the middle one. Validate-before-canonicalise is the textbook ordering fault.
- **Fix:** Test `os.path.normpath(w)` (or `w.startswith("/.") and not w.startswith("/./")`), or limit the skip to the `/.claude/` shape it was written for.
- **Reference:** CWE-180 Incorrect Behavior Order: Validate Before Canonicalize https://cwe.mitre.org/data/definitions/180.html
- **Cross-model:** Confirmed by cross-model review (DISS-001 gpt-5.5-pro; DISS-C-002 claude-headless).

### [LOW-001] Any word carrying `=` is skipped, but filenames may contain `=`
- **File:** `head/evals/harness/ablation-grade.sh:1432`
- **Severity:** LOW (confidence: high)
- **Issue:** The comment says "no path component carries =". `cat /home/operator/notes=old.txt` returns `None` on the head code (flagged by 1.2.0). `cat x=/home/operator/notes.txt` is still flagged because the match starts after `=`.
- **Fix:** Skip `=` only before the first `/` or at the start of a component.
- **Reference:** CWE-184 Incomplete List of Disallowed Inputs https://cwe.mitre.org/data/definitions/184.html

### [LOW-002] `in_quotes` counts raw quote characters, so an apostrophe inside double quotes flips the parity
- **File:** `head/evals/harness/ablation-grade.sh:1372-1374` (used at `:1444`)
- **Severity:** LOW (confidence: high)
- **Issue:** `echo "don't"; ls /mnt` returns `None` on the head code. Only one-component sensitive words (`/root /home /mnt /media /srv`) take this branch, which bounds the damage. Commit messages and echo text with apostrophes are common.
- **Fix:** Track quote state (ignore `'` inside `"..."` and vice versa, honour backslash escapes).
- **Reference:** CWE-20 https://cwe.mitre.org/data/definitions/20.html
- **Cross-model:** Confirmed by cross-model review (DISS-C-004, claude-headless, MEDIUM; downgraded here because the branch is reached only for the five single-component roots).

### [LOW-003] `SENSITIVE_SINGLE` lists Linux data roots only
- **File:** `head/evals/harness/ablation-grade.sh:1362`
- **Severity:** LOW (confidence: medium)
- **Issue:** On a macOS host-mode grade, bare `/Volumes` or `/Users` is dropped as a command token (`ls /Volumes` returns `None` in host mode). Two-component words such as `/Users/op` are still flagged, which narrows the review's version of this finding.
- **Fix:** Add `Users`, `Volumes`, `private` if host mode on macOS is supported; otherwise document the Linux-only assumption.
- **Reference:** CWE-184 https://cwe.mitre.org/data/definitions/184.html

### [LOW-004] The `--rerow` refusal points the operator at hand-editing the tracked rows file
- **File:** `head/evals/harness/run-ablation.sh:805`
- **Severity:** LOW (confidence: high)
- **Issue:** The message says the trial "is a rerun (--resume after removing the row)". Following it hand-edits `runs.jsonl`. Since DEC-0553 the supported path is `--resume --rerun <id>` or `--rerun-status <status>`, which replaces the row in place under the flock (`:1236-1270`).
- **Fix:** Point the message at `--rerun`/`--rerun-status`.
- **Reference:** CWE-1059 Insufficient Technical Documentation https://cwe.mitre.org/data/definitions/1059.html

### [LOW-005] `append_and_validate` appends first and validates second, so a rejected row stays in the tracked file
- **File:** `head/evals/harness/run-ablation.sh:1071-1081`
- **Severity:** LOW (confidence: medium)
- **Issue:** The row is `cat`-appended to `$ROWS` and only then `ablation-row.sh --validate` runs over the whole file. On failure (or a duplicate run_id, `:1079`) the batch ends `failed` but the offending line remains in `runs.jsonl`, the tracked decision dataset. `replace_row_try` (`:1236-1270`) does this correctly: temp file, validate, `mv`. The resume path refuses a duplicate (`:1324-1325`) but does not re-validate schema, so a schema-invalid row would be read as done on `--resume` and by `ablation-report.py`.
- **Fix:** Build `$ROWS.append.$$` with the new row, validate that, then `mv` under the same flock, as `replace_row_try` does.
- **Reference:** CWE-703 Improper Check or Handling of Exceptional Conditions https://cwe.mitre.org/data/definitions/703.html

### [LOW-006] A `drift_check` crash in `post_run` fails open
- **File:** `head/evals/harness/run-ablation.sh:983-985`
- **Severity:** LOW (confidence: medium)
- **Issue:** `dout="$(drift_check ... || true)"`; an empty first line becomes `PR_DRIFT=null`, so a guard that threw (unreadable MANIFEST, unexpected `phase_models` shape) reads as "no drift" and the trial is graded. The `--clear-drift` path (`:786-788`) handles the same failure closed. The provenance guard is DEC-0407's control.
- **Fix:** Treat an empty or non-JSON `dout` as `infrastructure_error` with a logged reason, as a took-effect failure is.
- **Reference:** CWE-636 Not Failing Securely https://cwe.mitre.org/data/definitions/636.html

---

## Observations

No high finding is demoted here as speculative; `excluded` is 0. The review's trailer records `excluded: 0`, so there is nothing to confirm and `excluded_confirmed` is 0.

- `head/evals/harness/ablation-grade.sh:1417` — the pre-existing `//` skip (`cat //home/operator/x` returns `None`) is not introduced by this change; noted for the same fix pass since `//root` resolves on Linux.
- `head/evals/harness/run-ablation.sh:829-833` — stale-lock takeover (`rm -rf "$LOCK"; mkdir "$LOCK"`) has a two-driver race window when both see a dead pid; operator-only CLI, not tallied.
- `head/evals/harness/run-ablation.sh:365` — the smoke guard compares the rows path literally; `--rows` through `..` or a symlink to the tracked file would pass. Operator footgun, not tallied.
- `head/evals/harness/ablation-report.py:857,919` — `reason` and row ids are rendered into Markdown without `md_cell` in two places; rows come from `ablation-row.sh`, whose `--validate` checks the arm grammar and enums but not run_id/task_id shape. Report is read by the lead, not tallied.

---

## Cross-Model Security Observations

Two-voice dissent ran on `--diff-file pr/head.diff`: primary gpt-5.5-pro answered by codex-headless, companion claude-headless, `status: reviewed`, `degraded: false`, `consensus_outcome: consensus`, 2 of 2 voices, `confidence_floor: high`. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. Mapping:

- DISS-C-003 (hidden token) → HIGH-001.
- DISS-C-001 and DISS-002 (heredoc bodies) → HIGH-002.
- DISS-C-005 (heredoc backtracking) → HIGH-003.
- DISS-C-002 and DISS-001 (`/.`, glued quotes, `=`) → MED-001, MED-002, LOW-001.
- DISS-C-004 (quote parity) → LOW-002.
- DISS-C-006 (LOW, `git log --all`/`git reflog` downgraded to telemetry) — noted, not tallied: DEC-0540 records the decision and `history_probes` keeps the count in every grade (`ablation-grade.sh:1404,1623`). [ASSUMPTION] The "fresh git init at base" invariant is enforced by `pipeline-run.sh`, which is outside the PR tree and was not verified here; if host mode ever reuses a repo with history, revisit.
- DISS-C-007 (LOW, partial model substitution no longer degrades a phase) — noted, not tallied: this is the pre-registered DEC-0545 rule (`ablation-row.sh:316-321`), and the extra models are kept as telemetry in the trial result and `STATUS.json extra_models` (`run-ablation.sh:987-991,1099-1102`), so the data to revisit the rule survives.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `adversarial-rejected-audit.jsonl` is zero bytes.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 3 | Runner args and JSON are validated; the grader's agent-output classifier has the gaps above |
| SEC-AV Availability | 3 | Watchdog, outage breaker and budget gate are good; one agent-controlled regex is exponential |
| SEC-CI Confidentiality/Integrity | 4 | Rows under flock, symlink refusals, pinned pristine worktree; append-then-validate gap |
| SEC-IN Injection | 5 | No eval, no string-built shell or SQL; `jq --arg` everywhere; `python3 -I` |
| ARCH-MO Modularity | 4 | `lib/arms-common.sh` extraction without behaviour change; two runners share one spend model |
| CQ-TC Test Coverage | 4 | 22/22 report tests pass; runner and grader suites read but not runnable here |
| CQ-EH Error Handling | 4 | Refusals write `REFUSED.txt`; one fail-open in `drift_check` |
| DevOps | 4 | Lock file ignored in `.gitignore`; batch `.gitignore` keeps run dirs out |

---

## Documentation Audit

No `documentation-coherence-*.md` reports exist under `grimoires/loa/a2a/subagent-reports/`; verified manually. Each script's header documents the new behaviour (`run-ablation.sh:1-228`, `arms-common.sh:1-51`, `ablation-report.py:1-105`, `ablation-row.sh:22-32`). One contradiction is a finding: `ablation-grade.sh:167` still says `hidden` is matched in "any case" (HIGH-001). The PR commits name CHANGELOG entries for Sprint 260, but `CHANGELOG.md` is not among the 17 files in the frozen tree, so that claim could not be checked. No secrets, credentials or internal URLs appear in the diff.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new trust boundaries (the contamination classifier: HIGH-001, HIGH-002, MED-001, MED-002)
- [x] Run ids, batch names, arm ids, image refs and numeric knobs are regex-validated before use in paths or commands
- [x] No shell or SQL built from strings; `jq --arg`, `python3 -I`, arrays for argv
- [ ] Error handling fails closed (LOW-005, LOW-006)
- [x] Error messages do not leak sensitive data
- [x] Resource limits: watchdog, outage breaker, budget gate (one exponential regex: HIGH-003)
- [ ] Tests cover the security paths (no AG-10 case for the shapes in HIGH-001/002/003)

---

## Next Steps

1. Fix HIGH-001, HIGH-002, HIGH-003 in `ablation-grade.sh`, bump `GRADER_VERSION`, add AG-10 cases for every command quoted above plus a timing case.
2. Take MED-001 and MED-002 in the same pass (one quote-state walker covers MED-001 and LOW-002).
3. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*
<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":2,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T04:06:00Z"} -->
