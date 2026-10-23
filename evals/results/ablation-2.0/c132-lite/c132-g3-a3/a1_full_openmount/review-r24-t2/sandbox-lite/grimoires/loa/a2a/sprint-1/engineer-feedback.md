# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries pr/PR.md)
**Change under review:** pr/head.diff (17 files; citations are `head/<path>:<line>` in pr/head/)

---

## Overall Assessment

The batch runner (`run-ablation.sh`), the shared library extraction (`lib/arms-common.sh`), the report generator (`ablation-report.py`) and the `ablation-row.sh` substitution rule are careful work. The resume, rerow, rerun and outage-breaker paths keep spend accounting consistent. The report's predicate order matches the amended suite rules block. `evals/tests/ablation-report.bats` passes 22 of 22 against the head tree.

The blocking problems sit in the grader's contamination check (`ablation-grade.sh` 1.2.1 to 1.2.5). Each calibration round added a skip rule to stop a false positive. Together they now let real probes through, and one regex backtracks exponentially. The grader decides which rows enter the pre-registered analysis, so a contamination miss feeds tainted rows into a decision. A grader stall turns a scored trial into infrastructure_error. Both need fixing before merge.

Two highs are counted below. I verified every finding marked confidence high by running the head `check_value` / `strip_heredocs` code on the inputs quoted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Contamination detection (grader integrity)

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` — In Bash commands, `HIDDEN_TOKEN` now only matches all-caps `HIDDEN` or lowercase `hidden` glued to `/ . _ = -`. Ordinary probes for the hidden tests now grade clean, where 1.2.0 flagged every one of them. Verified on the head code: `grep -ri hidden .`, `find . -iname '*hidden*'` and `ls Hidden/` all return `None` from `check_value`.
**File:** `head/evals/harness/ablation-grade.sh:1329` (used at `:1395`)
**Issue:** DEC-0551 meant to drop English prose in heredoc bodies. The fix instead narrowed the token shape for the whole command. It is case-sensitive, and glob and quote neighbours (`*`, `?`, `'`, `"`) are not in the adjacency classes. The header at `head/evals/harness/ablation-grade.sh:167` still says "any case".
**Why This Matters:** A run that searches for the hidden tests is scored as valid data and enters the pass-rate comparison.
**Required Fix:** Keep the prose exemption scoped to heredoc bodies. Run a case-insensitive `\bhidden\b` scan on `strip_heredocs(val)`, and keep the token-shape scan (made case-insensitive) on the full value. Add AG-10 cases for the three commands above.

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` is compiled with `re.S`, so the body group `(?:.*?\n)*?` can split the same lines many ways. When no terminator line follows a `<<WORD`, the regex backtracks exponentially. Measured on the head regex with an unterminated `cat <<EOF` followed by N plain lines: 16 lines take 0.036 s, 20 take 0.53 s, 22 take 2.1 s, so roughly ×4 per two lines. A long command with a `<<WORD` whose terminator never stands alone on a line will exceed the grade timeout. Examples are a truncated tool input, or a terminator glued to `)` or `;`.
**Why This Matters:** The grade is then killed, and `run-ablation.sh` rows the trial infrastructure_error (`head/evals/harness/run-ablation.sh:996`). That removes a scored cell and pushes the arm toward the degradation guard.
**Required Fix:** Drop `re.S` and make each body chunk exactly one line, for example `(?:[^\n]*\n)*?[ \t]*\2[ \t]*(?=\n|$)`. The match is then linear. Add a test that times an unterminated heredoc of a few hundred lines.

---

## Observations

### 1. Contamination path-word skips (grader 1.2.2 to 1.2.5)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1380` — `strip_heredocs` drops unquoted heredoc bodies too, but the shell still runs command substitutions inside them. Verified: `cat <<EOF` + `$(cat /home/operator/notes.txt)` + `EOF` returns `None`. Only bodies with a quoted delimiter (`<<'EOF'`) are inert data. Scan `$(...)` and backtick spans in unquoted bodies.
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1365` — `after_closing_quote` decides from one preceding character, so an opening quote glued to a token reads as a closing one. Verified: `cat ''/home/operator/notes.txt` returns `None`. `grep -f"/root/x"` takes the same path, because the quote follows `f`. A small quote-state walker would fix this. Treat an empty `''` or `""` before `/` as a separator.
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1438` — The `/.` skip runs before normalisation. `cat /./home/operator/notes.txt` returns `None`, although `outside()` would normalise it to an outside path. Test `os.path.normpath(w)` instead, or limit the skip to the `/.claude/` shape it was written for.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1432` — The comment says "no path component carries =", but filenames can contain `=`. `cat /home/operator/notes=old.txt` returns `None`. Skip `=` only at the start of a component, or only before the first `/`.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1372` — `in_quotes` counts raw quote characters, so an apostrophe inside double-quoted prose flips the parity. Verified: `echo "don't"; ls /mnt` returns `None`. This only affects one-component sensitive words.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1362` — `SENSITIVE_SINGLE` lists Linux data roots only. On a macOS host-mode grade, `ls /Users`, `/Volumes` and `/private` are dropped as command tokens. Add them if host mode on macOS is supported.

### 2. Runner messages

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:805` — The `--rerow` refusal still tells the operator to rerun "by --resume after removing the row". Following that advice hand-edits the tracked rows file. Since DEC-0553 the supported path is `--resume --rerun <id>` or `--rerun-status <status>`, which replaces the row in place under the flock. Point the message there.

### Verification notes

- `bats evals/tests/ablation-report.bats` passed 22 of 22 on a copy of pr/head/evals.
- `evals/tests/run-ablation.bats` and `ablation-grade.bats` were not run. They need collaborators that the frozen PR tree does not hold: freeze.sh, took-effect.sh, pipeline-run.sh, the frozen suite root and docker-stub.sh. I read their assertions instead.
- `bash -n` passes on `run-ablation.sh`. `py_compile` passes on both Python files. shellcheck is not installed here.
- Complexity: `run-ablation.sh` has functions over 50 lines (`post_run`, `run_trial`, `collect`). They are linear stage sequences with early returns, and their headers justify them. Not blocking. Lean already. Ship, once the grader items above are fixed.

---

## Cross-Model Observations

Two-voice dissent ran: codex-headless and claude-headless, consensus, 2 of 2 voices, `status: reviewed`. Its findings map onto the entries above:

- DISS-003 and DISS-C-001 (hidden token) are counted as the first HIGH.
- DISS-C-003 (heredoc backtracking) is counted as the second HIGH. I confirmed it by measurement.
- DISS-001 (heredoc command substitution), DISS-002 and DISS-C-004 (quote heuristics), and DISS-C-002 (`/.` skip) are recorded under Observations as MEDIUM or LOW. They need deliberately unusual command shapes, and the agents under test are not adversarial.
- DISS-C-005 (macOS roots) is recorded as LOW.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, and `adversarial-rejected-review.jsonl` is zero bytes.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md, Success Criteria) | Reviewed | Defects are listed above with head/ citations. Merge verdict: CHANGES_REQUIRED |

The implementation report has no `## AC Verification` section, because it is the PR description. Per the skill, that alone would force CHANGES_REQUIRED. The two counted highs are the substantive reason.

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation: the contamination classifier, the trust boundary between agent output and the analysis, has the gaps above
- [x] Run ids, batch names and arm ids are validated by regex before use in paths (`run-ablation.sh` argument block)
- [x] The report refuses symlinked inputs and outputs
- [x] Error messages do not leak sensitive data (grade excerpts avoid echoing the outside path)

## Next Steps

1. Fix the two HIGH items in `ablation-grade.sh`, and add AG-10 cases plus a timing case for each.
2. Consider the MEDIUM path-skip items in the same pass. Bump GRADER_VERSION.
3. Re-run `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:55:27Z"} -->
