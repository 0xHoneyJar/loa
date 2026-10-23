# Security analysis working file — /audit-sprint sprint-1 (review-r28), 2026-10-21

Scope: pr/head.diff (11 files under evals/). security-audit-scope.sh over pr/head: sources 0, sinks 2 (command_exec 1, file_operations 1), auth_files 1, llm_files 1.

| # | Item | file:line | Trust | Status |
|---|------|-----------|-------|--------|
| 1 | Source: suite file arm def → `ARM_DEF`, `SUITE_TOGGLES`, `eval_only` | head/evals/harness/pipeline-run.sh:242-258 | in-tree / operator (`--suite-file`) | PARTIAL — refusal keys on declared `eval_only`, not `toggles.oracle_open` (MED-001) |
| 2 | Source: env `LOA_ABLATION_BATCH_CONTEXT` | head/evals/harness/pipeline-run.sh:259 | operator shell | SAFE as documented soft guard (LOW-005); exact-value check |
| 3 | Sink: dry-run jq over `SUITE_TOGGLES` → stdout only | head/evals/harness/pipeline-run.sh:341-345 | in-tree | SAFE (no exec/file); duplication finding MED-004 |
| 4 | Sink: `RULE_IDS` sed-scrape of took-effect.sh → python3 -I argv | head/evals/harness/validate-suite.sh:87, 122 | in-tree script | SAFE (single argv, -I); regex brittleness LOW-002 |
| 5 | Source: `took_effect`, `toggles`, `eval_only` YAML values → `bad()` messages | head/evals/harness/validate-suite.sh:157-180 | in-tree | SAFE (json.dumps, type-exact) |
| 6 | Sink: `LOA_ABLATION_BATCH_CONTEXT=1 setsid "${cmd[@]}"` | head/evals/harness/run-ablation.sh:1300-1301 | runner | SAFE (command-prefix assignment, no export) |
| 7 | Sink: stub `STUB_ENV_LOG` append | head/evals/tests/fixtures/ablation-pipeline-stub.sh:55 | test only | N/A |
| 8 | Report: `eval_only is not True` vs jq `-r == true` typing | head/evals/harness/ablation-report.py:1913 vs pipeline-run.sh:258 | in-tree | PARTIAL (LOW-004) |
| 9 | Run dir creation ordering vs refusal | head/evals/harness/pipeline-run.sh:258-262 vs :356 | — | SAFE (nothing created before refusal; grep mktemp/mkdir < 258 empty) |
| 10 | `--help` / `usage()` sed ranges vs header length | pipeline-run.sh:193 (rule at 157); validate-suite.sh:68 (rule at 57) | — | SAFE |
| 11 | Decision reachability for review-catch-only components | head/evals/harness/ablation-report.py:653-658, 731-733, 846-877, 922 | — | CONFIRMED (HIGH-001) |
| 12 | Repo state outside the diff: took-effect.sh rule_<id>() for 5 new ids; grimoires/loa/evals/ablation-2.0 suite root | VS-14/VS-16, RAB-c131-5 | — | Unable to assess (not in pr/); recorded as scope limit |
