# Reviewer concerns — sprint-1 (PR: sprint-259 tasks, seeders, grader)

Scope: pr/head.diff. Cite as head/<path>:<line>.

1. head/evals/harness/ablation-grade.sh:710-714 — `tarfile.data_filter` and `extractall(filter=)` need Python >= 3.12 (or 3.11.4+ backport); no version guard. On Debian 12's Python 3.11.2 (this host) `tarfile.data_filter` is absent: snapshot grading raises AttributeError -> "internal error" exit 2 for any run with a REVIEW/AUDIT verdict.
2. head/evals/tests/ablation-grade.bats:16 — BATS_BIN hard-wired to `$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`, a personal dotfiles path; on any other host the `$T/bin/bats` symlink dangles and the bats-based cases (AG-2 second half, AG-7) fail.
3. head/evals/harness/ablation-grade.sh:1126-1130 — refactor verdict accuracy judges the gate's snapshot by the suite only (all_pass of test_command), never the structural check, so an APPROVED review of an un-refactored tree (suite still green) is scored accurate.
4. pr/PR.md claims sixteen frozen-suite tasks and a freeze manifest; neither appears in head.diff.
5. head/evals/harness/lib/seed_tasks.py:196-198 — pytest counts read the LAST line of stdout+stderr; any stderr output after the summary (warnings) yields 0/0 and a spurious proof failure.
6. head/evals/harness/lib/seed_tasks.py:342-362 — covering_tests matches a touched module's stem as a bare word (e.g. `left`, `util`) across every test file under the roots; common words pull unrelated tests into the fixture and the test command.
7. head/evals/harness/lib/seed_tasks.py:227 — `patch` without --batch/--forward can prompt on a tty.
8. head/evals/harness/ablation-grade.sh:617-621 — TAP results keyed by description: duplicate bats test names collide, failed ids/positions wrong.
9. head/evals/harness/lib/seed_tasks.py:502-506 — any non-zero exit of no-secrets.sh (missing script, tool error) is reported as "a secret pattern in the materialised task".
10. head/evals/harness/lib/seed_tasks.py:570,579-602 — in-build skips (no covering test) and secret refusals consume a --select slot; fewer than N tasks are materialised although later candidates qualify.
11. head/evals/harness/ablation-grade.sh:964-965 — any Bash command containing the substring "hidden" is contamination (e.g. `ls -a` output unaffected, but `grep hidden`, `.hidden` dirs); documented as lower bound but produces false positives.
12. head/evals/harness/seed-corpus-from-record.sh:233-236 — missing-file error for a generated path is raised before the exclusion check.
