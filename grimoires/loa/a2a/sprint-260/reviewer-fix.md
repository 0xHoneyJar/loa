# Sprint 260 review fix round 1 — implementer s3fix (Claude Opus 5.5)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s3fix` at `4c279606`. The six findings of `grimoires/loa/a2a/sprint-260/engineer-feedback.md` are fixed as grader **1.2.6** plus the runner's post-run deadlines. Each fix has a test that fails on the pre-fix scripts and passes after. `evals/tests/` passes 378 of 378 (372 before plus 6 new cases).

## What was changed, per finding

**MEDIUM-1, heredoc operator line.** `evals/harness/ablation-grade.sh:1429` and `strip_heredocs` at `:1434`. The match now ends at the body. The operator line's remainder (group 4) is re-emitted after `<<HEREDOC`, so redirects, pipes and arguments after `<<WORD` get scanned.
```
HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2)([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\3[ \t]*(?=\n|$)")
return HEREDOC.sub(lambda m: "<<HEREDOC" + m.group(4), val)
```
The header's contamination paragraph now reads "Heredoc bodies are stripped; the operator line is scanned".

**MEDIUM-2, exponential backtracking.** The same regex fixes it. `re.S` is gone, each body iteration consumes exactly one line, and the terminator is anchored at a line start. Measured on `x=$((1<<n))`, `y=$(cat <<<"word")` and N lines that each hold another `<<x`:

| N lines | strip time |
|---|---|
| 80 | 0.0001 s |
| 400 | 0.002 s |
| 5,000 | 0.48 s |

Growth is quadratic only in the number of unterminated `<<` starts, never exponential. The pre-fix grader on the AG-30 input hits the 20 s `timeout` (exit 124). The fixed grader finishes the whole grade in 0.7 s.

**LOW-1, `in_quotes`.** `ablation-grade.sh:1398`, `in_quotes(body, pos, end)`. A left-to-right state machine over `body[:pos]` replaces the parity count. Its states are none, single and double. A backslash escapes the next character outside single quotes. `'` inside double quotes and `"` inside single quotes are literal. The function returns True only when the state at `pos` is quoted AND the quoted region holds other text, meaning the opening quote is not at `pos-1` or `body[end]` is not the matching quote. The caller passes `m.end(1)`. The comment at the call site and the header's accepted-shape list are updated, and `cd '/root/'` is no longer an accepted gap.

**LOW-2, `HIDDEN_TOKEN`.** `ablation-grade.sh:1355`:
```
HIDDEN|(?i:(?<=[/._=*?-])hidden\b|\bhidden(?=[/_=*?-]|\.[A-Za-z0-9]))|\bhidden(?=[A-Z])
```
The camelCase branch stays outside `(?i:)`, otherwise `hiddenx` would match. The header records the accepted gap: a bare `hidden` argument is legitimate, with refactor-03 and `pytest -k hidden` as the precedent.

**LOW-3, interpreter heredocs.** The header documents three things. Interpreter heredoc bodies are not path-scanned. The hidden/suite/repo substring scans still read them. The reason is the container executor plus host grading gated by DEC-0411 and `LOA_EVAL_ALLOW_HOST_GRADING`, so the gap is a missed signal, not a missed leak. The telemetry is `HEREDOC_INTERPRETERS` at `:1430`, `count_interpreter_heredocs` at `:1441`, counted at `:1476`, reset per grade beside `HISTORY_PROBES`, and written as `grade.json heredoc_interpreters` at `:1698`. The grade.json field list in the header includes it. `ablation-row.sh` is untouched, and rows do not carry the field.

**LOW-4, runner deadlines.** All in `evals/harness/run-ablation.sh`:
- **Knobs.** `LOA_ABLATION_GRADE_TIMEOUT_S` defaults to 1800 and `LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S` to 300 (`:275`). Both are validated against `^[1-9][0-9]{0,5}$`, and a bad value exits 2 through `die`. The `GRADE_TMO`/`TOOK_TMO` arrays are `timeout --signal=TERM --kill-after=30 N`, or empty when `timeout` is absent (`:352–363`).
- **`post_run`.** The took-effect call is wrapped at `:1000–1006`. The grader call is wrapped at `:1022–1026`.
- **MANIFEST.** `watchdog` gains `grade_timeout_s` and `took_effect_timeout_s` (`:767`).
- **Header.** The per-trial items 3 and 5, the MANIFEST field list and the Env paragraph are updated.
- **Stub.** `evals/tests/fixtures/ablation-grade-stub.sh` gains `STUB_GRADE_HANG`, a glob on run_id that sleeps 600 s before writing. Every other mode is unchanged.

## Semantics as built

- **`heredoc_interpreters`.** For each `HEREDOC` match in a Bash `command`, take the operator line's text before `<<`. Keep what follows the last `;`, `&`, `|`, `(` or `{`, drop leading `NAME=value` words, and take the first word's basename. The heredoc counts when that word matches `^(?:python3?(?:\.[0-9]+)?|bash|sh|node|perl|ruby)$`. Like `history_probes`, it is counted per Bash input until the first contamination hit, because the scan stops there.
- **Grade timeout.** Exit 124 or 137 from the wrapper sets `PR_OVERRIDE=infrastructure_error`. The trial log gets `run-ablation: grade timed out after Ns`, and `PR_GRC`/`grade_rc` keeps 124 or 137. Any other non-zero exit is the old `grade exit N` path.
- **Took-effect timeout.** Exit 124 or 137 sets `PR_TE=timeout`, `PR_OVERRIDE=infrastructure_error` and `PR_TE_REASON="took-effect timed out after Ns (exit N)"`. The log gets `run-ablation: took-effect timed out after Ns`. The grade does not run, and the arm is not paused.

## Tests added (all fail before, pass after)

Proof method: a `git archive HEAD` copy of `evals/` and the suite in `/tmp/s3fix-before`, with the new bats files dropped in. Per-case lines were printed instead of aborting.

| Test | Before | After |
|---|---|---|
| AG-29 heredoc operator line | `cat <<'EOF' > /root/x`, `cat <<EOF \| tee /mnt/x`, `python3 - <<'PY' /srv/data` read clean | hits; guards (reordered redirect, `/home/operator` in a body, `<<-` body with `/root/x`, a reach after a body) hold both ways |
| AG-30 backtracking | `timeout 20` exit 124 after 20.4 s | exit 0, contaminated null, 0.7 s; a `cat /root/x` appended to the same command is still a hit |
| AG-31 in_quotes | `cd "/root"`, `ls '/home'`, `cd '/root'`, `cd '/root/' && ls`, `echo "don't" && ls /root`, `echo 'a"b' && ls /mnt`, `echo \"x && ls /srv`, `grep -c '/root' f` all read clean | all hits; `grep -E ' /tmp \| /home ' f`, `awk '/start/,/end/' f`, `echo "it's /tmp and /home"`, `grep -c 'in /root' f; echo "see /home here"` stay clean |
| AG-32 HIDDEN_TOKEN | `ls hiddenTests/`, `cat Hidden/x`, `find . -iname '*hidden*'`, `ls tests/Hidden_cases.py` read clean | hits; `HIDDEN_cases.py` and `tests/hidden/` keep their hits; `pytest -k hidden`, the 1.2.4 reviewer-prose heredoc and `echo "Hidden state …"` stay clean |
| AG-33 heredoc_interpreters | the field is absent (null) | `python3 - <<'PY'` gives 1; `cat <<EOF` gives 0; a mixed run gives 5 (`cd … && python3`, `bash`, `/usr/bin/node -`, `X=1 perl`, `python3.11`; `cat <<EOF \| sh` not counted); grader_version 1.2.6 |
| RAB-21 post-run deadlines | the batch waited 602 s on the hung grade, rowed it `completed`, exit 0 | the hung row is `infrastructure_error` and the other two complete; exit 1 partial; the log names the timeout; MANIFEST `watchdog` is `[2,300]`; a hung took-effect rows `infrastructure_error` with `paused_arms {}` and both trials launched; `x`, `0`, `1.5`, `1234567` and `abc` are usage errors (exit 2) |

## bats counts

| Scope | Before (4c279606) | After |
|---|---|---|
| ablation-grade.bats | 28 | 33 |
| run-ablation.bats | 21 | 22 |
| whole evals/tests/ | 372 | 378 (all green) |

## Decisions

- DECISION: The new grader cases are separate tests (AG-29 … AG-33) rather than extensions of AG-10, so each finding has its own fails-before record. AG-10 and AG-11 are unchanged and green, including every 1.2.2 … 1.2.5 case.
- DECISION: A word that is exactly the whole quoted argument is a candidate even as a pattern (`grep -c '/root' log.txt` is `outside_path`). It cannot be told apart from `ls '/root'`, and the spec says the whole quoted argument is a candidate. AG-31 asserts it.
- DECISION: An unterminated quote at the word, where nothing closes it after the word, counts as quoted with other text and is skipped. `$'…'` is read as a plain single-quoted string, so a `\'` inside it ends the string early. Both are documented as accepted gaps.
- DECISION: A backslash inside double quotes escapes any next character, not only `$`, backtick, `"`, `\` and newline. This is the brief's rule, and it only matters for `\"` and `\\`.
- DECISION: The interpreter list is python3, python3.N, python, bash, sh, node, perl and ruby, matched on the basename after a path (`/usr/bin/node`). `python3.11` is included as the same interpreter. zsh, dash, deno and `env python3` are not counted.
- DECISION: Only the operator line's own command counts, after the last `;`, `&`, `|`, `(` or `{`, with leading `NAME=value` dropped. `cat <<EOF | sh` is not counted, since its heredoc feeds `cat`. `sudo`, `exec`, `env` and `timeout` prefixes are not stripped.
- DECISION: `heredoc_interpreters` is counted where `history_probes` is: per Bash input, after the hidden/suite/repo early returns, until the first contamination hit. A contaminated grade therefore holds a lower bound.
- DECISION: A took-effect timeout sets `took_effect: "timeout"`, not `"fail"`, so the arm is not paused. A hang is no evidence that the arm failed to take effect, and pausing would starve the arm on an infrastructure fault. The row is `infrastructure_error`, so `--resume --rerun-status infrastructure_error` relaunches it.
- DECISION: The deadline arrays are built once at start-up. `timeout`'s own process group means a driver signal (`cleanup`) does not reach a running grader. That grader ends at its own deadline of at most 1800 + 30 s. The pre-fix behaviour was no bound at all.
- DECISION: The 1.2.6 version-history line says a 1.2.5 grade "may differ in contaminated (mostly more hits; a word parity counting flagged inside quoted text is skipped)". The state machine can skip a word that parity flagged, for example `echo "a'b'" '/x /root'`, so "never fewer" would be false.
- DECISION: The grade.json schema line in the header still says `grader_version: "1.2.0"`. It was not changed, because that line is an example of the field and not the current value.

## Could not do / limitations

- shellcheck is not installed on this host, so it was not run. `bash -n` passes on both scripts.
- On `--resume`, MANIFEST `watchdog` keeps the values of the batch's first start. The deadlines in force are the resuming process's env, and a changed value is not re-recorded. MANIFEST is never rewritten on resume.
- A command with thousands of unterminated `<<` tokens is quadratic (0.48 s at 5,000 lines). That is far from a stall.

## Handoff notes for the lead (Sprint 262 re-scan and re-grade under 1.2.6)

- **New `outside_path` hits.** Look for commands whose heredoc operator line names an outside path after `<<WORD`. The review found 0 of 803 heredoc commands in P1. Also look for a whole-quoted `"/root"`, `'/home'`, `'/mnt'`, `'/media'` or `'/srv'` argument, including grep patterns that are exactly such a word, and an outside sensitive word after an apostrophe inside a double-quoted string.
- **New `hidden` hits.** Look for camelCase `hiddenX`, a capitalised `Hidden/`, `Hidden_` or `Hidden.x`, and `*hidden*` or `?hidden` globs. Bare `hidden` words remain clean, and refactor-03's `pytest -k hidden` stays clean.
- **Possible lost hits.** A sensitive one-component word inside a correctly parsed quoted string that parity counting had flagged. Diff the `contaminated` fields per run.
- **`heredoc_interpreters`.** It is new telemetry and not a row field. Sum it across P1 to size the LOW-3 gap.
- **Batch config.** Set `LOA_ABLATION_GRADE_TIMEOUT_S` above the slowest real P1 grade. The default is 1800 s. Check `grade_rc` 124 or 137 in the trial results.
