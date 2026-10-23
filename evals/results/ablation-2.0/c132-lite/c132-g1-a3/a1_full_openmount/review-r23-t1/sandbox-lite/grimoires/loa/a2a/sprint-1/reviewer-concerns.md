# Reviewer concerns — sprint-1 (review-r23), Phase 2 notes

1. head/evals/harness/ablation-grade.sh:710-714 — tarfile.data_filter / extractall(filter=) need Python >= 3.11.4; TypeError on 3.11.2 (reproduced) -> every gated run exits 2.
2. head/evals/harness/ablation-grade.sh:1080 (+593, 637) — hidden_tests counts every collected test (fixture visible tests, agent-added tests); AG-1 expects 7/7 with 5 hidden cases.
3. head/evals/tests/ablation-grade.bats:16,48 — BATS_BIN hardcoded to one operator's dotfiles path; AG-2/AG-7 fail elsewhere.
4. head/evals/harness/lib/seed_tasks.py:570,588-597 — --select slots consumed by build-time skips/refusals, not backfilled (contradicts wrapper headers).
5. head/evals/harness/ablation-grade.sh:964 — substring "hidden" flags rg --hidden etc.
6. head/evals/harness/ablation-grade.sh:1119-1120 — unextractable snapshot leaves per-gate accuracy null silently.
7. head/evals/harness/lib/seed_tasks.py:196 — counts() reads last line of stdout+stderr.
8. head/evals/harness/lib/seed_tasks.py:52 — global git config not neutralised.
9. PR description claims 16 tasks under grimoires/ + freeze; not in diff. reviewer.md lacks AC Verification.
