# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (17 files): the new batch runner `evals/harness/run-ablation.sh`, the shared spend/transport library `evals/harness/lib/arms-common.sh` (extracted from `run-arms.sh`), the new report generator `evals/harness/ablation-report.py`, the DEC-0545 degraded rule in `ablation-row.sh`, the suite predicate reorder, and grader 1.2.1 to 1.2.5 (the contamination-scanner calibration in `ablation-grade.sh`), with tests and fixtures.

What is good: the runner's resume, rerun, rerow and spend accounting are internally consistent (ledger + rows = spent holds on every path I traced, including DEC-0553 in-place replacement under flock); the library extraction from `run-arms.sh` is behaviour-preserving (`est_record`/`est_next` keyed by arm with pool `all` reproduce the old per-arm and pooled means; `spend_charge` reproduces the assumed-cap branch); the report generator's predicate order, pairwise exclusion, defect-unit bootstrap and MDE handling match the header and the suite, and its 22 bats tests pass here (`bats evals/tests/ablation-report.bats` on a copy of `pr/head`: 22/22 ok).

What blocks the merge: the grader 1.2.2 to 1.2.5 calibration of the contamination scanner (the integrity control that decides whether a run's row is valid) introduces four regressions I reproduced against the head code with the scanner functions extracted verbatim (`head/evals/harness/ablation-grade.sh:1324-1456`): an exponential-backtracking regex that can hang a trial job and therefore the whole batch, and three false-negative classes where the base grader (1.2.0) flagged an outside reach and the head grader returns clean. Every one has a concrete input below. The DEC records justify narrowing prose-only hits; they do not cover executed heredoc bodies, escaped quotes, mixed case or glob-adjacent tokens, and in one case the header's own text (`:167`, "any case") contradicts the regex.

Pre-flight notes: per `pr/REVIEW-INSTRUCTIONS.md` there is no sprint plan, beads database or PRD/SDD in this workspace; `reviewer.md` is the PR description and carries no `## AC Verification` section (recorded under Observations, not applied as the automatic rule since the brief says to skip steps that need those artifacts). The CHANGELOG and grimoires record commits named in `pr/PR.md` are outside the 17-file diff and could not be verified. `shellcheck` is not installed here; `bash -n` and `py_compile` pass on every script.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Availability — grader regex can hang a trial job and the batch

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` is `<<-?\s*(['"]?)(\w+)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)` compiled with `re.S`; because `.` also matches `\n`, `(?:.*?\n)*?` is an ambiguous nested quantifier and backtracks exponentially when no terminator line exists.
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex), `:1383` (`HEREDOC.sub` in `strip_heredocs`), `:1412` (called for every Bash `command`)
**Issue:** Measured with the head functions extracted verbatim: a command `cat <<EOF > notes.md` followed by N lines and no `EOF` line takes 0.08 s at N=16, 0.99 s at N=20, 3.9 s at N=22, 15.4 s at N=24 (×4 per two lines; N=36 is about two hours). Realistic shapes: a multi-line `python3 -c`/`awk` program containing a bit shift such as `x<<n` (the opener needs only `<<` + an identifier), a `$(cat <<EOF … EOF)` whose terminator line is `EOF)`, or a transcript line truncated before the terminator. The scan runs in-process in `contamination()`; `TEST_TIMEOUT_S` (`:262`) only bounds the test subprocesses.
**Why This Matters:** `run-ablation.sh` removes the watchdog's `.pgid` file right after the pipeline exits (`head/evals/harness/run-ablation.sh:1031`), before `post_run` calls the grader (`:996`). Nothing bounds the grade, so the trial job never writes its `.result`, `reap` never collects it, and the driver's final `reap 1` (`:1382`) loops forever with the batch lock held. One pathological Bash tool_use stops a USD-budgeted batch until an operator notices.
**Required Fix:** Replace the regex with a linear procedural scan (find `<<[-]?['"]?WORD`, then walk `val.splitlines()` for the first line whose stripped text equals WORD; if none, leave the command unstripped). Independently, keep the watchdog alive through `post_run` (write the `.pgid` after `wait` with the grader's pid, or wrap the grade/took-effect/row calls in `timeout`) so a hung collaborator rows `infrastructure_error` instead of hanging the batch.
**Reference:** CWE-1333 (Inefficient Regular Expression Complexity)

### 2. Contamination detector false negatives (regressions from grader 1.2.0)

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1412` — `strip_heredocs` is applied to every Bash command before the path scan, so an outside absolute path inside a heredoc that an interpreter executes (`python3 - <<'PY' … open('/home/operator/notes') … PY`, `bash <<EOF cat /home/operator/notes EOF`) is never a candidate; the opener's `[^\n]*` (`:1377`) also swallows a redirection target on the same line (`cat <<EOF > /home/operator/out.txt`). Both return `None` on head and `outside_path` on base.
**File:** `head/evals/harness/ablation-grade.sh:1412`, `:1377`
**Issue:** DEC-0541's rationale ("written file text is data, not a path the agent reached") holds for `cat > f <<EOF`, not for `python3 -`, `bash`, `sh`, `node -`, `sqlite3 <<SQL`, which is the most common way a model runs multi-line code in one Bash call. The redirect-target case is a write outside the sandbox hidden by the same substitution.
**Why This Matters:** A run that read or wrote outside the sandbox is counted as a valid row; the ablation decision for that arm is built on it.
**Required Fix:** Strip a heredoc body only when its consumer is a writer (`cat`/`tee`/`printf` with `>`/`>>` or `--out`-style targets); otherwise scan the body. Never remove the remainder of the opener line (replace only the body, from the newline after the opener to the terminator).

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1368-1369` — `after_closing_quote` treats any character other than whitespace or `=(<>|;&,` before the quote as evidence of a glued closing quote, so `bash -c "cat \"/home/operator/notes\""`, `python3 -c "print(open(\"/home/operator/notes\").read())"`, `python3 -c 'print(open(f"/home/operator/{n}").read())'` (and `r"…"`, `b"…"`, `$'…'`) all skip the path. Head returns `None`; base returned `outside_path`.
**File:** `head/evals/harness/ablation-grade.sh:1368-1369`, called at `:1442`
**Issue:** The character before the quote is `\`, `f`, `r`, `b` or `$`, none of which closes a token. Escaped quotes inside a `-c "…"` program and f-string paths are routine in model-written one-liners.
**Why This Matters:** Same as above: a reach outside the sandbox is graded clean.
**Required Fix:** Return `False` when `before` is `\` or `$`, or when the quote at `pos-1` is an opening quote by parity (an even count of that unescaped quote character in `body[:pos-1]`); only a quote that closes an open string of the same kind can be "glued" to a preceding token.

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` — `HIDDEN_TOKEN` matches only all-caps `HIDDEN` or lowercase `hidden` adjacent to `/ . _ = -`; `ls Hidden_tests/` and `find / -name '*hidden*'` return `None` on head, while base's case-insensitive substring check flagged both, and the header at `:167` still promises "any case".
**File:** `head/evals/harness/ablation-grade.sh:1329`, used at `:1395`; header `:167`
**Issue:** Mixed case and glob adjacency are the shapes of a hidden-test probe, not of reviewer prose (the DEC-0551 false positive the change targets).
**Why This Matters:** A probe for the hidden tests is the contamination class the scanner was built for; the row is counted valid.
**Required Fix:** Compile with `re.I` and add `*?[]` to both adjacency classes (`(?<=[/._=*?\[-])hidden\b|\bhidden(?=[/_=*?\]-]|\.[A-Za-z0-9])`); keep bare prose `hidden` unflagged as DEC-0551 intends; add the two inputs above to AG-10.

---

## Observations

### 1. Scanner heuristics (non-blocking, same component)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1374` — `in_quotes` counts every `'` and `"` in the whole command; `echo "it's"; cd /root && cat .ssh/id_rsa` returns `None` on head (base: `outside_path`) because one apostrophe in earlier prose flips the parity for the later single-component word.
**Suggestion:** Count parity only over the current simple command (text after the last unquoted `;`, `&&`, `||`, `|`) and ignore `'` inside a `"…"` string.
**Benefit:** Closes a bypass the comment at `:1439-1441` does not list as accepted.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1438` — `w.startswith("/.")` is tested before `os.path.normpath`, so `/./home/operator/notes` and `/../root/x` are discarded as "root dot-directory" words; head returns `None`.
**Suggestion:** Normalise first; skip only when the first component is a dot-directory other than `.`/`..`.
**Benefit:** Removes a trivial normalisation bypass.

- **MEDIUM** (confidence: low) `head/evals/harness/ablation-row.sh:319` — `model_missing` requires `model_requested` to be a non-empty string; a phase record with `model_requested` null and a non-empty `models_used` naming another model is no longer degraded (base's key-by-key compare flagged it). `run-ablation.sh`'s `drift_check` falls back to the manifest model in this case (`head/evals/harness/run-ablation.sh:519`); the row does not.
**Suggestion:** Fall back to `MANIFEST phase_models[name]` (the `--manifest` is already passed) before giving up.
**Benefit:** Keeps the row's `degraded` consistent with the runner's drift guard.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1432` — `"=" in w` discards any absolute word whose component carries `=` (`cat /home/operator/x=y` returns `None`); the documented intent (sed-range remnants, `key=value`) is already covered by the `/,` and lookbehind rules.
**Suggestion:** Restrict to words whose first component contains `=`, or to words preceded by a regex delimiter.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1404` — `HISTORY_PROBES` is incremented only after the hidden/suite/repo checks did not return, and `contamination()` returns on the first hit (`:1500`), so probes after a hit and `git log --all -- tests/hidden` are not counted. Telemetry only.

### 2. Runner robustness

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:309` — the tool pre-flight checks `git jq yq python3 awk` only; `setsid` (`:1025`) and `flock` (`:1070`, `:1241`) fall back silently, which drops process-group termination (the watchdog then signals only the pipeline's pid) and the rows-file lock that the header and `.gitignore` describe. Either pre-flight them or log the degraded mode in `MANIFEST.json`.

### 3. Process

- **LOW** (confidence: high) `pr/PR.md:1` — the implementation report (the PR description) has no `## AC Verification` walkthrough, and the CHANGELOG / NOTES / DEC-record commits it lists are not in the 17-file diff; neither could be verified from this workspace. Not applied as the automatic CHANGES_REQUIRED rule per `pr/REVIEW-INSTRUCTIONS.md`.

### Complexity

`run-ablation.sh` is 1,410 lines; `run_trial` (`:1008-1064`) and the resume reconciliation block (`:1299-1352`) exceed 50 lines but each is one linear state machine with the DEC it implements cited inline, which I accept as justification. `SIMPLICITY[shrink]`: the three near-identical `is_paused` skip lines in the dispatch loop (`:1367`, `:1370`, `:1375`) could be one helper; net: -6 lines possible. Otherwise lean for what it does.

---

## Cross-Model Observations

Adversarial review (Phase 2.5): `grimoires/loa/a2a/sprint-1/adversarial-review.json`, two voices (primary `gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`), status `reviewed`, 11 findings. Disposition after reproducing each against the head scanner:

- DISS-C-001 (interpreter-fed heredoc bodies) — confirmed; adopted into Changes Required §2 first entry.
- DISS-001 (opener line's redirect target stripped) — confirmed; folded into the same entry.
- DISS-C-002 (`HIDDEN_TOKEN` misses mixed case and glob adjacency) — confirmed; Changes Required §2 fourth entry.
- DISS-C-004 (f-string/raw prefixes, `$'…'`) — confirmed; folded into the `after_closing_quote` entry.
- DISS-C-003 (`/./`, `/../` before normpath) — confirmed; Observations MEDIUM.
- DISS-003 (`=` in word), DISS-C-006 (`HISTORY_PROBES` undercount), DISS-C-007 (`model_missing` with null `model_requested`), DISS-C-008 (flock/setsid not pre-flighted) — accepted as Observations.
- DISS-C-005 (claims `<<<` here-strings also trigger the backtracking) — verified false: `HEREDOC.search("cat <<< word\n…")` does not match (the third `<` is not an identifier character). Not counted. The bit-shift (`x<<y`) part of the same finding is correct and is in §1.
- DISS-002 (`/.` skips valid dot-component paths) — duplicate of DISS-C-003.

## Rejected dissent payloads

- none: `metadata.rejected_summary` is `[]` and the listed sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` is empty (0 bytes).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| report each defect it introduces with the file and line it sits on | Pass | Four high and seven lower findings above, each with `head/<path>:<line>` and a reproduced input |
| give a merge verdict | Pass | CHANGES_REQUIRED (4 high, 0 critical) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the new files carry none; test fixtures use planted hashes)
- [ ] Input validation and sanitization present — the contamination scanner's new exemptions widen what passes unflagged (Changes Required §2)
- [x] Authentication/authorization correct (n/a: local harness)
- [x] No SQL/XSS injection vulnerabilities (jq/python programs take data via `--arg`/argv, not string splicing)
- [x] Dependencies secure (stdlib python, jq, yq, bash)
- [x] Error messages don't leak sensitive data
- [ ] Denial of service — `HEREDOC` regex (Changes Required §1, CWE-1333)

---

## Code Quality Summary

**Strengths:**
- Rows file mutations (append, in-place replace) are flock-guarded, validated on a temp copy, then `mv`'d; refusals leave the file byte-identical and the tests assert it (`RAB-18`, `RAB-19`).
- Spend accounting is reconstructed from rows on resume and the tests pin `spent = rows + ledger` (`RAB-19:600`).
- `ablation-report.py` compares on 9-decimal rounded values, seeds one generator per interval, and refuses symlinked outputs; AR-1 to AR-22 pass.
- `lib/arms-common.sh` is a faithful extraction: every removed `run-arms.sh` block maps to one library function with the same arithmetic.

**Areas for Improvement:**
- The grader's path scanner has grown five layers of regex heuristics on top of `ABS_WORD`; each calibration DEC fixed a false positive and opened a false negative. A small tokenizer (shlex-style with heredoc awareness) would replace `after_closing_quote`, `in_quotes`, the `/,`/`=`/`/.` skips and `strip_heredocs` with one pass and would be testable against the AG-10 corpus directly.
- Keep the watchdog armed through the post-run chain.

---

## Next Steps

1. Fix the four Changes Required entries in `ablation-grade.sh` (and the watchdog gap in `run-ablation.sh`), bumping the grader version; add the reproduced inputs above to `AG-10` as regression cases.
2. Re-run `evals/tests/ablation-grade.bats` and `evals/tests/run-ablation.bats`; attach an `## AC Verification` section to the implementation report.
3. Resubmit for `/review-sprint sprint-1`.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":3,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T18:40:00Z"} -->
