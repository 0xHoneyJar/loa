# Reviewer concerns — sprint-1 (PR: sprint-261 suite v2 + per-type run caps + KF-048)

Scope: pr/head.diff (evals/harness/ablation-grade.sh, lib/arms-common.sh, pipeline-run.sh, run-ablation.sh, suites/ablation-2.0.yaml, tests/*.bats, tests/fixtures/ablation-pipeline-stub.sh).

## Candidate findings (please attack or confirm)

1. ablation-grade.sh remove_colliding (1.2.11), lines 1079-1098: the `reserved` set takes EVERY `.py` basename under the fixture's tests/ or test/ (except __init__.py, conftest.py), not just pytest-collected test modules (test_*.py / *_test.py). The grader's own header names fixture helpers (`from helpers import …`, `import _oracle_x`). An agent that adds `src/<pkg>/helpers.py` (not in the fixture, not an overlay dest) has it unlinked before the hidden suite runs, so a correct solution is graded as failing. Severity HIGH?
2. remove_colliding: `reserved` from the overlay only includes FILE dests (`owned` excludes dirs); a hidden overlay declared as a directory (put_file supports copy_tree) contributes no basenames, so collisions with those test modules are not caught — the import-mismatch abort the fix targets still happens.
3. COLLIDING[0] is accumulated across every prepare() call in one grade (final, base, implement, fix1 snapshots), so grade.json colliding_tests_removed over-counts the same agent file up to 3-4x.
4. run-ablation.sh line 806: required_until = now + 2 × Σ watchdog_s / concurrency, but watchdog_s is already 2 × phase-sum. For a full A0–A4 batch (~240 trials) this is weeks, beyond any codex access-token lifetime (~10 days observed) — large batches are permanently refused regardless of token freshness.
5. run-ablation.sh line 785: the KF-048 pre-flight is skipped only for --smoke. With --executor host, pipeline-run.sh does not call make_home (host HOME with the real refresh token is used), so the codex CLI can refresh; the pre-flight falsely refuses host-mode batches.
6. seed-bugfix.bats / seed-refactor.bats now pass `--suite-version` to the seed scripts, which are not in this diff; if the flag does not exist the tests fail.
7. ablation-pipeline-stub.sh line 143 still writes rows with suite_version 1 while the suite is at 2.
8. pipeline-run.bats line 973: `! grep -q 'codex/auth.json' run-1.mounts` is vacuous (auth.json is never a mount).
9. RAB-5 title still says "a cap failure charges run_cap" (now the kind's cap).
10. suite_kind_cap: `.[$k] // ""` treats a `false`/`null` entry as absent and silently falls back, contradicting "a present entry that is not an amount is a usage error".

## Areas I believe are correct (please double-check)
- --types jq fix (`.type as $t | … | index($t)`), WANT_TYPES expansion of `build`.
- spend_charge/budget_gate new optional params; RESERVE_CAP = max cap over plan kinds; --resume reads caps from MANIFEST and ignores --run-cap.
- make_home placeholder refresh token: 0600, keeps other keys, host file untouched, failure → rm + WARN.
- Pre-flight JSON decode with base64url padding; no token material printed.
