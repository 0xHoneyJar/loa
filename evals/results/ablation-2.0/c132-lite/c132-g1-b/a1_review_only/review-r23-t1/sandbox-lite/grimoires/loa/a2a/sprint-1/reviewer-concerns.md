# Reviewer concerns — sprint-1 (PR: sprint-259 tasks and seeders, ablation grader)

Scope: pr/head.diff (16 files: evals/harness/ablation-grade.sh, evals/harness/lib/seed_tasks.py,
seed-bugfix-tasks.sh, seed-refactor-tasks.sh, seed-corpus-from-record.sh, validate-suite.sh,
evals/tests/*.bats, docker-stub.sh, review-prs manifests pr-14/pr-15 + SHA256SUMS).

Concerns to dissent on:
1. evals/tests/ablation-grade.bats:16 — BATS_BIN is a hard-coded path under one developer's $HOME
   (.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats); line 48 symlinks it as the image bats,
   so every bats-based grading test (AG-2 bf-sh, AG-7 bf-sh) fails on any other host / CI.
2. ablation-grade.sh:940,976-980 — ABS_WORD treats sed/awk address ranges in Bash commands as
   absolute paths (`sed -n '/^a/,/^b/p'` → `/^b/p`... `/bar/p`), yielding a spurious `outside_path`
   contamination verdict on legitimate agent commands.
3. seed_tasks.py:570 — `selected = cands[:a.select]` fixes the selection before building; a candidate
   that turns out `skip` (no covering test) or `secret` consumes a slot and is not replaced, contrary to
   the wrapper headers ("refusals and skips do not count").
4. seed_tasks.py:196-198 — pytest counts are read from the last line of stdout+stderr concatenated;
   any stderr output after the summary breaks the proof.
5. ablation-grade.sh — agent-added root conftest.py / pytest.ini / pyproject.toml are not neutralised
   unless listed in grader_protected; pytest still loads them with --rootdir.
6. PR.md promises sixteen tasks under grimoires/loa/evals/ablation-2.0/tasks/ and "the freeze"; the
   diff contains neither (no task dirs, no MANIFEST.sha256).
7. ablation-grade.bats:46 — /usr/bin/python3 hard-coded in the image stand-in.
8. seed_tasks.py:52 — git env keeps HOME without GIT_CONFIG_GLOBAL=/dev/null; user gitconfig
   (log.showSignature, diff.*) can alter parsed output.
