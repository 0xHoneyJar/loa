# Reviewer concerns (Phase 2, sprint-1 / PR sprint-261 suite v2 + per-type run caps)

1. evals/harness/ablation-grade.sh remove_colliding (1.2.11): `reserved` includes EVERY fixture .py under tests/ or test/ (helpers.py, _oracle_x.py), not only pytest-collected test modules, and the walk covers the whole tree (src/ included). An agent-added src/helpers.py with a fixture tests/helpers.py would be deleted before grading -> correct solution graded as failing. Also packages with __init__.py do not collide under prepend mode but are still removed.
2. run-ablation.sh codex pre-flight: horizon = now + 2 x sum(watchdog_s)/concurrency where watchdog_s is already 2x phase sum; on --resume the whole plan counts; is write_manifest re-run on resume (overwriting codex_preflight)? Is $WORK/plan-only.json built on resume?
3. run-ablation.sh suite_kind_cap dies inside $( ) — does die write REFUSED.txt or only stderr; `|| exit 2` path.
4. arms-common.sh budget_gate: is the new <reserve-per-trial> used in the wait condition as well as CUT_JSON?
5. pipeline-run.sh make_home: python rewrites auth.json; error path rm -f + WARN; refresh_token absent key left absent.
6. Tests: RAB-8 "charged the run cap" assertion value after 12->15; pipeline-run.bats setup for $T/home/.codex, $T/dlog/run-1.argv/mounts; validate-suite.bats $SUITE var; seed-*.bats pass --suite-version to seed scripts not in this PR.
7. run-ablation.bats RAB-1 comment says A0 BARE stays 70 min but asserts 9600 s (80 min) — stale comment.
