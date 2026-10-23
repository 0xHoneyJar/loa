# Reviewer concerns — sprint-1 (PR: sprint-261 suite v2 + per-type run caps + KF-048 + grader 1.2.11)

Phase 2 notes for the adversarial dissent. Cite as head/<path>:<line>.

1. head/evals/harness/ablation-grade.sh:1081-1097 remove_colliding: the reserved basename set is
   every .py under a fixture tests/ dir (helpers.py, utils.py, …, not only collected test modules)
   plus every overlay .py basename including __init__.py; the walk removes matches ANYWHERE in the
   tree (src/ packages too). An agent that adds src/<pkg>/helpers.py while the fixture has
   tests/helpers.py loses the file before test_command runs -> ImportError -> correct solution
   graded as failing. Same for an overlay shipping tests/__init__.py: every new __init__.py the
   agent created is deleted.
2. head/evals/harness/ablation-grade.sh:1079-1081: directory overlays (owned_dirs) contribute no
   basenames to reserved, so the pytest "import file mismatch" abort 1.2.11 targets survives for
   suites whose hidden tests are overlaid as a directory.
3. head/evals/harness/run-ablation.sh:806: required_until sums watchdog_s over the WHOLE plan,
   including a0_bare trials that never use codex, and on --resume over already-rowed trials; for
   a full suite v2 batch this is days, likely beyond the access token lifetime -> every full batch
   and every late resume refused.
4. head/evals/harness/run-ablation.sh:500-504: a per-kind entry of false/null falls to the single
   cap silently, contrary to the "present but malformed is refused" comment.
5. head/evals/tests/run-ablation.bats:95-97: stale comment ("A0 BARE stays 70 min") contradicts
   the 80-min assertion beside it.
6. Tests depend on suite tasks (grimoires/loa/evals/ablation-2.0/tasks/*-v2-*) and on seed-*.sh
   --suite-version support, none of which is in this diff — unverifiable here.
7. head/evals/harness/pipeline-run.sh:623-645 make_home: credential copy looks correct (0600,
   placeholder refresh token, host untouched, rm on failure); check for anything missed.
