# Security analysis working file — sprint-1 audit (pr/head.diff, sprint-264) — 2026-10-21

| # | Kind | Location (head/) | Trust | Status | Note |
|---|------|------------------|-------|--------|------|
| 1 | source | evals/harness/pipeline-run.sh:258 `LOA_ABLATION_BATCH_CONTEXT` env | operator | PARTIAL | literal `1` only; guards a label (`eval_only`) not the capability (`oracle_open`) → MED-001 |
| 2 | source | evals/harness/pipeline-run.sh:242 `--suite-file` → `ARM_DEF.eval_only` | operator | PARTIAL | editable; no per-run provenance → MED-001 / LOW-003 |
| 3 | source | evals/harness/validate-suite.sh:87 `RULE_IDS` from took-effect.sh via sed | in-tree | SAFE | regex `^rule_([a-z_][a-z0-9_]*)()`; passed as argv, no shell re-eval |
| 4 | source | evals/harness/validate-suite.sh:157-180 suite arms (toggles, took_effect, eval_only) | operator | SAFE | type-exact, allowlisted; python3 -I |
| 5 | sink | evals/harness/pipeline-run.sh:341-345 jq config_edits (dry run, stdout only) | — | SAFE | jq data path; duplication only → MED-004 |
| 6 | sink | evals/harness/run-ablation.sh:1300-1301 trial exec with env prefix | — | SAFE | env set on the command only; arm ids regex-gated at :574 |
| 7 | sink | evals/tests/fixtures/ablation-pipeline-stub.sh:55 `>> $STUB_ENV_LOG` | test | N/A | test fixture |
| 8 | sink | evals/tests/pipeline-run.bats:1018 `yq load(strenv(SUITE_SRC))` | test | N/A | test fixture, in-tree path |
| 9 | flow | suite `priority` → run-ablation.sh:570 default plan | — | CONFIRMED | new arms absent → HIGH-001 |
| 10 | flow | components (report.py:1913) → primaries (:653) → compare (:732) → decide (:846) | — | CONFIRMED | pass-rate pair never forms for review-catch-only arms → HIGH-002 |
| 11 | flow | pipeline-run.sh REFUSAL (:244-252) vs eval_only exit (:259) ordering | — | CONFIRMED | eval_only pre-empts applicability refusal → LOW-004 |

Deferred (outside diff / not in workspace): lib/sandbox-mount.sh apply_arm_toggles, took-effect.sh rule bodies, ablation-grade.sh, gen-fixtures.py, grimoires/loa/evals/ablation-2.0 suite root.
