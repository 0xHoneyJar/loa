# Implementation report — Sprint 256 implementer E (Task 2.6, FR-6)

Model: Opus 5.5 (global.anthropic.claude-opus-5-5). Worktree: loa-wt-s2b at b6802e4f; nothing was committed.

## Executive Summary
The fail-closed heredoc consumer classifier is implemented in `block-destructive-bash.sh`. It sits behind `destructive_command_guard.heredoc_classifier`, which defaults to true. The knob is documented in the example config, and the hooks reference has a new section on it. `run-corpus.sh` gained `--knob-off`, `--rows` and a per-row p95. **The new corpus B-rows and D-rows (D-6.2) were NOT added.** While I was writing them, a safety classifier stopped my output, so the lead has to decide how to author them. AC-2.8 is therefore only partly met. The SP-1 false-positive line in the hooks reference is unchanged, because no corpus row proves the prose case yet.

## AC Verification
- AC-2.8 "`run-corpus.sh` green with the new rows; no D-row removed; the recorded prose cases allow; every interpreter, wrapper, substitution, same-line-execution and unlisted-consumer D-row blocks; the knob off reproduces today's results; p95 under 80 ms (PRD AC-6.1, AC-6.2)": **PARTIAL**. The existing corpus is green with the knob on and with it off. The knob-off pass is row-for-row identical to the pre-change hook (`--rows` diff). p95 is 45 ms in both modes. The new rows are missing.
- AC-2.12 "After each patch apply the fence corpus and the hook bats were run before the next tool call relied on them, recorded in the report; every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree": **MET for the fence suites** (432 bats, 32 pytest plus 412 subtests, the corpus). The lead's apply-time smoke run is still due.

## Tasks Completed
- The classifier block sits before the bash-version guard in `.claude/hooks/safety/block-destructive-bash.sh`. Its grammar is in the block comment. The main-flow switch is beside the old #1245 scrub, which is kept byte for byte as the knob-off path and the special case.
- `.loa.config.yaml.example`: the `heredoc_classifier: true` key in the `destructive_command_guard:` block.
- `.claude/loa/reference/hooks-reference.md`: the "Heredoc consumer classification (cycle-129 FR-6)" section.
- `tests/fixtures/fence-corpus/run-corpus.sh`: `--knob-off`, `--rows`, and `p95_ms` in the text and JSON output.

## Technical Highlights
Signatures: `_bdb_heredoc_consumer_class <command text>` prints `interpreter|nonexec|none`. `heredoc_nonexec <command text>` exits 0 iff the class is nonexec. Both are available after `BDB_LIB_ONLY=1 source block-destructive-bash.sh`. Library mode applies only when the file is sourced.

## Testing Summary
| Run | benign | dangerous | residual | p95 ms |
|-----|--------|-----------|----------|--------|
| knob on | 78/78 | 100/100 | 0/5 | 45 |
| knob off | 78/78 | 100/100 | 0/5 | 45 |

Host load average was about 3. No quiet-host measurement was taken.

## Known Limitations
- A body written to a plain file by one command and executed by a later command is outside the fence.
- The D-6.2 corpus rows are absent, so the new classes have no corpus coverage yet.
- `guard-yield.sh` looks for `.claude/scripts/lib/heredoc-classifier.sh`, which does not exist, so it still falls back to checking for `<<`.

## Verification Steps
```
bash tests/fixtures/fence-corpus/run-corpus.sh
diff <(bash tests/fixtures/fence-corpus/run-corpus.sh --rows --knob-off) <(bash tests/fixtures/fence-corpus/run-corpus.sh --rows --hook <pre-change hook>)
python3 -m pytest -q tests/unit/test_hook_issue_regressions.py
```

## Assumptions
- [ASSUMPTION decision] Under a quoted delimiter, `$(`, backticks and `<(` in the body are literal and do not force a full scan.
- [ASSUMPTION decision] The exec-shaped flag rule (`-c`, `-e`, `-x` clusters) is applied literally, so `jq -c`, `grep -e` and `wc -c` are full-scanned.
- [ASSUMPTION decision] `br` flags other than exec-shaped ones are accepted, because `br` runs nothing.
- [ASSUMPTION decision] A variable command word in a body also gets a synthetic scan as `rm`, `git` and `kubectl`. This needs no new pattern id.
- [ASSUMPTION decision] Interpreter, executable-target, nested and shebang checks run before the #1245 special case, which tightens that case.
- [ASSUMPTION decision] I did not create the lib shim for `guard-yield.sh`. It would change the GY-3 expectations in a file I do not own.
- [ASSUMPTION fact] No shell-compat scripts exist under `tools/` or `tests/`.
