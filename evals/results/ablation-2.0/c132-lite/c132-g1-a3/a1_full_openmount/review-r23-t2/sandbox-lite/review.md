head/evals/harness/ablation-grade.sh:976 — contamination `outside_path` treats any quoted `/word` in a Bash command as a path (`grep "/review-sprint"`, `grep "/health"`, `echo "run /plan"` → contaminated); honest runs are flagged
head/evals/harness/ablation-grade.sh:710 — `tarfile.extractall(filter=…)` / `tarfile.data_filter` need Python ≥ 3.11.4; on Python 3.11.2 every run with a gate verdict and a snapshot bundle dies with "internal error" exit 2 and no grade.json
head/evals/harness/ablation-grade.sh:242 — `remove_path` chmod pre-pass follows symlinks: an agent-planted `evil -> ../../..` in the sandbox is copied into grading/final and the next regrade chmods the host target to 0700 (writes outside `<run-dir>/grading/`)
head/evals/harness/ablation-grade.sh:862 — `envelope_texts` never reads `anchor_line`; real dissent envelopes carry `anchor` (path:symbol) + `anchor_line` only, so adversarial findings never reach gates-combined.md and recall is under-counted
head/evals/harness/ablation-grade.sh:653 — `all_pass` ignores `rc` and `timed_out`; an interrupted pytest run (rc 2) with a clean partial summary grades as fully passing and marks a wrong APPROVED accurate
head/evals/tests/ablation-grade.bats:16 — `BATS_BIN` hardcoded to one developer's `~/.local/dotfiles/...`; where bats is not in /usr/bin or /bin (here /usr/local/bin) the stub's bats dangles and AG-2 / AG-7 fail
head/evals/harness/ablation-grade.sh:964 — `"hidden" in low` is a substring match over every scanned field (`hidden_size`, a Grep pattern `Hidden`) → false contamination
head/evals/harness/ablation-grade.sh:482 — hidden pytest run loads agent-added conftest.py / ini at unprotected paths and the parser trusts terminal output (a `pytest_sessionfinish` hook can print a fake summary)
head/evals/harness/ablation-grade.sh:508 — `timeout 120` without `-k`; on the outer TimeoutExpired only the docker CLI is killed and the container keeps running with the grading tree mounted rw
head/evals/harness/ablation-grade.sh:1222 — `--self-check base` passes on `passed < total` alone, so a parse_error run (nothing executed) reports PASS
head/evals/harness/ablation-grade.sh:1102 — refactor hidden run also collects the structural check when its dest lies under the test command's path, making a correct task red at base; nothing validates the constraint
head/evals/harness/ablation-grade.sh:1045 — `grade()` ~100 lines and `load_task()` (319) ~103 lines over the 50-line threshold; split per task type
head/evals/harness/lib/seed_tasks.py:196 — proof counts parse the last line of stdout+stderr; any trailing stderr line yields 0 passed/failed and a spurious proof failure
head/evals/harness/lib/seed_tasks.py:227 — `patch` without `--batch --forward` prompts on inherited stdin for an already-applied hunk
head/evals/harness/ablation-grade.sh:796 — citation regex matches version tokens (`1.2.3:4`) and counts them as stray false-positive regions
head/evals/harness/ablation-grade.sh:1057 — `gate_verdict` "none" leaks into `verdict.value` (header documents APPROVED | CHANGES_REQUIRED | null) and an audit file without a trailer masks the review verdict
head/evals/harness/ablation-grade.sh:1053 — `fresh_dir(grading)` wipes the previous grading tree before `docker_ready()` can refuse
head/evals/tests/validate-suite.bats:33 — VS-1 derives its expected counts from the same tree the validator reads; no fixed expectation remains
head/evals/tests/ablation-grade.bats:46 — `/usr/bin/python3` hardcoded in the image stand-in
Verdict: CHANGES_REQUIRED
