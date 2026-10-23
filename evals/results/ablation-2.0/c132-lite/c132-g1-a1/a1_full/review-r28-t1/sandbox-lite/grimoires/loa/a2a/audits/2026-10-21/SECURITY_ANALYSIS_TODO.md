# Security analysis working file — sprint-1 (review-r28), 2026-10-21

Scope: pr/head.diff (11 files: 5 harness/suite, 6 tests). Workspace holds only the touched files; lib/sandbox-mount.sh,
took-effect.sh, the suite root and fixtures are absent, so bats suites were not executed.

## Sources (untrusted → trusted)

| # | Source | file:line | Trust | Status | Note |
|---|--------|-----------|-------|--------|------|
| S1 | `--suite-file` (any path) → `ARM_DEF`, `SUITE_TOGGLES`, `eval_only` | head/evals/harness/pipeline-run.sh:243-258 | operator-controlled | SAFE | parsed with jq; values compared as strings; `--arg` everywhere |
| S2 | `LOA_ABLATION_BATCH_CONTEXT` env | head/evals/harness/pipeline-run.sh:259 | self-attested (any shell) | PARTIAL | misuse guard, not a boundary; see M-001 / L-006 |
| S3 | `$ARM` argv → refusal message | head/evals/harness/pipeline-run.sh:260 | operator | SAFE | echo to stderr only; run-ablation validates `^[a-z][a-z0-9_]{0,63}$` (:575) |
| S4 | took-effect.sh → `RULE_IDS` (sed) → python argv | head/evals/harness/validate-suite.sh:85-88,122 | in-tree sibling | SAFE | fixed regex, `python3 -I`, into a set |
| S5 | suite arms → TOGGLE_VALUES / took_effect / eval_only checks | head/evals/harness/validate-suite.sh:157-180 | suite author | SAFE | type-exact comparisons; every violation listed |
| S6 | suite arms → `components`, `primaries()` | head/evals/harness/ablation-report.py:653-658, 1913 | suite author | CONFIRMED (quality) | review-catch-only arms → dead decision path (H-001) |

## Sinks

| # | Sink | file:line | Status | Note |
|---|------|-----------|--------|------|
| K1 | run directory creation | head/evals/harness/pipeline-run.sh:356 | SAFE | eval_only refusal at :259-262 precedes it; dry run at :318-350 also precedes it |
| K2 | agent launch env (host + container) | head/evals/harness/pipeline-run.sh:833-868, 897 | SAFE | allowlist `envkv` + `ENV_SHIM` (:797); `LOA_ABLATION_BATCH_CONTEXT` not in the allowlist, not emitted by ARM_ENV_FILE → never reaches the agent (dissent DISS-C-002 dismissed) |
| K3 | trial launch | head/evals/harness/run-ablation.sh:1300-1301 | SAFE | single launch site; env set on the command only |
| K4 | sandbox .loa.config.yaml edits (dry-run description) | head/evals/harness/pipeline-run.sh:341-345 | PARTIAL | hand-copied mapping; drift risk (L-001) |
| K5 | report decisions table / expected-FP line | head/evals/harness/ablation-report.py:1913, 1927-1932, 2003 | CONFIRMED (quality) | H-001, M-002, M-003, L-005 |

## Second-order flows

- Open-mount rows (a1_full_openmount) → `list_reason` admits them to cells (:1108-1123); not a component, not in detail_arms (:2003); `oracle_reason` never excludes oracle_open rows (:583-591, pre-existing). Bounded: never decided, only the sensitivity count sees them. L-005.
- Ad hoc rows produced with the env var set outside a batch have no manifest → listed, never celled (`list_reason` "no manifest for batch"). Bounds DISS-C-001 to LOW.

Deferred: none. All entries traced.
