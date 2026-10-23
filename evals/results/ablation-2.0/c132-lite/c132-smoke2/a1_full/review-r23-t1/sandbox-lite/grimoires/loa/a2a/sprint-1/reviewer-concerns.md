# Reviewer concerns — sprint-1 (PR: sprint-259 grader, seeders, freeze, bd-8o5rx)

Scope: pr/head.diff. New: evals/harness/ablation-grade.sh (bash exec → python3 -I heredoc),
evals/harness/lib/seed_tasks.py, seed-bugfix-tasks.sh, seed-refactor-tasks.sh, tests
(ablation-grade.bats, seed-bugfix.bats, seed-refactor.bats). Modified: seed-corpus-from-record.sh
(generated paths never fix regions), validate-suite.sh (source.churn), docker-stub.sh
(DOCKER_STUB_PATH), pipeline-run.bats, seed-corpus.bats, validate-suite.bats, pr-14/pr-15
manifests + SHA256SUMS.

Concerns to probe:

1. evals/tests/ablation-grade.bats:16 — BATS_BIN is an operator-specific absolute path
   ($HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats); the stub `bats` symlink dangles
   on any other machine, so AG-2 (bf-sh half) and AG-7 fail outside the author's laptop.
2. evals/tests/ablation-grade.bats:46 — hard-coded /usr/bin/python3 in the image stand-in.
3. evals/harness/lib/seed_tasks.py:196-198 — pytest proof counts read only the LAST line of
   stdout+stderr; any stderr noise after the summary makes the proof read 0 passed / 0 failed and
   the candidate fails spuriously.
4. evals/harness/lib/seed_tasks.py:225-230 — `patch` without --batch/--forward can prompt on
   /dev/tty (reversed/already-applied patch) and hang an interactive seeding run; the grader uses
   --batch --forward.
5. evals/harness/lib/seed_tasks.py:158-177 / 384 / 457 — grader_protected is only the infra
   files that EXIST at the parent; a fixture with no conftest.py / pytest.ini leaves the agent free
   to add one that neutralises the hidden tests (grading does not remove files the fixture lacks
   unless listed; validate-suite.sh:279 forbids listing non-fixture paths).
6. evals/harness/ablation-grade.sh:964 — contamination `hidden` substring on Grep pattern / Bash
   command flags legitimate searches (this very PR's diff is full of `hidden/`), marking clean
   review-catch runs contaminated.
7. evals/harness/ablation-grade.sh:597-621 — TAP ids keyed by description; duplicate bats
   descriptions collapse to one position.
8. evals/harness/ablation-grade.sh:588-589 — a test that FAILED and then ERRORed in teardown is
   counted twice in total.
9. evals/harness/seed-corpus-from-record.sh:232-236 — the generated-path exclusion runs after the
   `head/<file> missing` check, so a generated path outside the fixture scope errors instead of being
   excluded.
10. evals/tests/validate-suite.bats:31-44 — VS-1 now derives its expectations from the committed
    suite (self-referential); a type with MORE than four tasks is counted as `short`.
