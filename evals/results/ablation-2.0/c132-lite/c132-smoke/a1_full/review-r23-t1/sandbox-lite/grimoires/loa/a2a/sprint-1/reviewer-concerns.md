# Reviewer concerns — sprint-1 (PR: sprint-259 seeders, grader, generated-path rule)

Scope: pr/head.diff; cite as head/<path>:<line>.

1. head/evals/harness/lib/seed_tasks.py:225-230 — apply_patch falls back to `git apply -p1` when `patch` is absent.
   From a subdirectory of ANY git work tree (e.g. TMPDIR under a checkout; reproduced with TMPDIR=/workspace/.eval/tmp),
   git apply resolves paths against the repo root, prints "Skipped patch" and exits 0. The seeder then reports
   "not green at reference" and writes nothing (exit 1) — a false proof failure.
2. head/evals/harness/lib/seed_tasks.py:570-602 — `selected = cands[:select]`; a candidate skipped post-selection
   ("no test at the parent names a touched file", secret refusal) consumes a slot; header says skips don't count.
   Reproduced: --select 1 with the newest candidate uncovered → written 0 although an older candidate qualifies.
3. head/evals/harness/ablation-grade.sh:713-714 — tarfile.extractall(filter=) needs Python ≥3.12 (or the 3.11.4+/3.10.12+ backport);
   on Python 3.11.2 (this host) hasattr(tarfile, "data_filter") is False → TypeError → "internal error" exit 2 for any run with snapshots.
4. head/evals/tests/ablation-grade.bats:16 — BATS_BIN hard-codes one operator's $HOME path (diff-so-fancy/test/bats); the stub PATH
   ($T/bin:/usr/bin:/bin) omits /usr/local/bin, so bf-sh tests fail on any other machine.
5. head/evals/harness/ablation-grade.sh:624-636 — a command without a parseable summary that exits 0 is credited passed=total
   (parse_error true); an agent-authored root conftest.py / pytest plugin can produce that. The seeder protects only infra files that
   EXIST at the parent (seed_tasks.py:158-177, 384), so an agent can add a root conftest.py / pytest.ini unprotected.
6. head/evals/harness/ablation-grade.sh:296 — copy_tree uses shutil.copyfile on every regular file; an unreadable (mode 000) file the agent
   leaves in the sandbox raises PermissionError → internal error exit 2 (agent-controllable grading abort).
7. head/evals/harness/lib/seed_tasks.py:51-54 — _git_env keeps HOME but does not set GIT_CONFIG_GLOBAL=/dev/null (the grader does);
   user gitconfig (log.showSignature, etc.) can alter parsed `git log` output.
8. head/evals/harness/ablation-grade.sh:1057-1063 — verdict.value can be the string "none" (file present, no trailer) instead of null,
   and review.md's Verdict is then not consulted.
9. head/evals/tests/validate-suite.bats:31-45 (VS-1) — assumes a type with != 4 tasks produces exactly one counts line (a type with >4 may not).
10. PR description claims sixteen task directories under grimoires/loa/evals/ablation-2.0/tasks/ and "the freeze"; none are in the diff.
