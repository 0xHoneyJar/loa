# Reviewer concerns — sprint-1 (PR: sprint-259 tasks, seeders, grader)

1. evals/harness/ablation-grade.sh:713-714 — `tf.extractall(tree, filter=keep)` and `tarfile.data_filter` need Python >= 3.11.4/3.12; on 3.11.2 every snapshot extraction dies with TypeError -> exit 2 (reproduced).
2. evals/harness/ablation-grade.sh:1080 — hidden_tests runs the task's whole test_command (a directory), so agent-authored tests inflate passed/total (reproduced 20/22 with both hidden tests failing).
3. evals/tests/ablation-grade.bats:16 — hardcoded operator path to bats (`$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`); :46 hardcoded /usr/bin/python3.
4. evals/harness/ablation-grade.sh:940,977-983 — ABS_WORD contamination scan flags string literals like '/x' in ordinary Bash commands as outside_path (reproduced).
5. evals/harness/ablation-grade.sh:1086-1098 — base tree gets hidden overlay before regression_command runs; base totals include hidden tests when the regression dir overlaps.
6. evals/harness/lib/seed_tasks.py:225-230 — `git apply` fallback when `patch` is missing silently applies nothing when the staging dir lies inside another git work tree (reproduced).
7. evals/harness/lib/seed_tasks.py:196-198 — pytest counts() reads the last line of stdout+stderr; a trailing stderr line hides the summary.
