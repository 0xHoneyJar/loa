# Sprint 264 (cycle-131 Sprint 2) — implementation report for the reviewer

**Lead:** Fable 5.1 (main session) · **Implementer:** S2-A (Opus 5.5, worktree `../loa-wt-s2a`, Tasks 2.1/2.2; report `reviewer-a.md`) · **Lead tasks:** 2.3 arm smoke, 2.4 gates + pin + pre-registration, 2.5 batches + scans · **Commits:** `0281ea57` (Tasks 2.1/2.2 + lead integration), `c0d42907` (review r2a), `798d88cf` (audit r2b = the Sprint 264 pin) on `feature/cycle-131-honest-measurement` · **Gates:** review APPROVED (`engineer-feedback.md`, dissent run 1), audit APPROVED (`auditor-sprint-feedback.md`, dissent run 2); third run unused · **Date:** 2026-10-20

## What changed (by file)

| Area | Files | Owner |
|---|---|---|
| Arms | `evals/suites/ablation-2.0.yaml` (+4 arms, `eval_only` header note) | S2-A |
| Validator | `evals/harness/validate-suite.sh` (check 8: toggle vocabulary/type-exact values, rule ids from `took-effect.sh`, `eval_only` boolean, `oracle_open ⇒ eval_only`) | S2-A |
| Pipeline | `evals/harness/pipeline-run.sh` (`eval_only` refusal before any run dir; `--dry-run` sandbox plan line; `LOA_ABLATION_BATCH_CONTEXT`), `evals/harness/run-ablation.sh` (sets the variable on each trial command) | S2-A |
| Suite root | `grimoires/loa/evals/ablation-2.0-c131/` (review-r17, review-r18 from the replication root; bounds REVIEW 50 / AUDIT 40; README; `MANIFEST.sha256` 60316fb8…) | S2-A |
| Report | `evals/harness/ablation-report.py` (eval_only arms excluded from components; efp at two decimals; DEC-0646) | lead |
| Tests | `evals/tests/validate-suite.bats` (+4), `pipeline-run.bats` (+6), `run-ablation.bats` (+1), stub env log; pins AT-13, AR-12, AR-23 | S2-A, lead |
| Records | `grimoires/loa/a2a/sprint-2/self-check-c131.log` (6/6 PASS), `reviewer-a.md` | S2-A |

## AC Verification (sprint.md § Sprint 2, verbatim)

### "PRD FR-5 AC 1–2 (suite validates; toggles implemented and tested; `a1_full_openmount` refused outside an evaluation batch; smoke trial per arm with rules true)"

| AC | Status | Evidence |
|---|---|---|
| suite validates | ✓ Met | `validate-suite.sh` OK on `evals/suites/ablation-2.0.yaml` (18 tasks), both frozen roots and the smoke root; VS-14 … VS-17 |
| toggles implemented and tested | ✓ Met | `bare_model`, `dissent`, `oracle_open` in `lib/sandbox-mount.sh apply_arm_toggles` (Sprint 263) + took-effect rules; dry-run plans per arm in `reviewer-a.md` (A0F BARE on `claude-fable-5-1` effort high; A1R phases `[REVIEW]`; A1N `flatline_protocol.code_review.enabled=false`; A1O `overlay=none(oracle_open)`) |
| `a1_full_openmount` refused outside an evaluation batch | ✓ Met | `pipeline-run.sh` exit 2 `refused: arm 'a1_full_openmount': eval_only arm outside an evaluation batch` before any run dir; `LOA_ABLATION_BATCH_CONTEXT=1` only from `run-ablation.sh` (batch and smoke) — pipeline-run.bats two cases, RAB-c131-5 env log |
| smoke trial per arm with rules true | ✓ Met | batch `smoke-c131-arms-20261020T025808Z` on review-01 (pr-05; DEC-0645), four trials; read in § Arm smoke |

### "PRD FR-6 AC 1–3 (pre-registration refs dated before the first rows with sha256 in MANIFEST; budget B1 ≈ 48, B2 ≈ 220, total ≤ 275; every row's `oracle_exposed_defects` empty except the open-mount arm, took-effect true, dissent fields and models recorded)"

| AC | Status | Evidence |
|---|---|---|
| pre-registration before the first rows, sha256 in MANIFEST | ✓ written | NOTES § Pre-registration — cycle-131 Sprint 264 batches (dated before B1's first row; section sha256 in the DEC row and in each batch's `--pre-registration-ref`) |
| budget | ⚠ amended | B1 ≈ 66, B2 ≈ 228 under an allowance of USD 300 (DEC-0645: the priced-in dissent doubled the per-run cost; R3/R4 cells on pr-17 only; cut order recorded) |
| every row: oracle empty (except open-mount), took-effect true, dissent fields and models | ⏸ Task 2.5 | read in `batch-scans.md` after B1/B2 |

### "One `source_commit` in both MANIFESTs; `copy_source` equals it on every row"

| AC | Status | Evidence |
|---|---|---|
| one pin | ✓ `798d88cf` | the audit-round r2b commit, recorded in the NOTES pre-registration and passed as `--source-commit` to every batch; every row's `copy_source` checked in the scans |

## Deviations and decisions

1. Budget re-derived (DEC-0645); arm smoke on pr-05 instead of pr-17/pr-12 (cheaper; checks rules, not catch).
2. Report components exclude eval_only arms (DEC-0646).
3. The implementer ran an unfiltered `pkill -f bats-exec` while stopping its own run (reported by itself); no lead run was affected (the lead's r1c run had finished). Brief rule for future sprints: process control only on PIDs you own.

## Arm smoke (Task 2.3) — batch `smoke-c131-arms-20261020T025808Z`, complete 2026-10-20T03:32:14Z

Pin `0281ea57`, review-01 (pr-05), one trial per new arm, concurrency 2, USD 21.77 (estimate 32). Columns: arm, status, degraded, reason, overlay, oracle_open, catch_pm3, oracle-exposed, dissent-absent gates, review voices, audit voices, phases, USD.

```
a1_no_dissent      completed  true   REVIEW:  refusal  fallback  head  false  1.0  0    review  -/-           2/2    REVIEW+AUDIT  7.191
a0_bare_fable      completed  false  -        false    1.0       0     -      -/-  -/-  BARE    0.834                              
a1_full_openmount  completed  false  -        none     true      1.0   0      -    2/2  2/2     REVIEW+AUDIT  8.826                
a1_review_only     completed  false  -        head     false     1.0   0      -    2/2  -/-     REVIEW        4.921                
```

- **Took-effect:** every rule true on every arm (`a0_bare_fable`: no_dot_claude, no_system_prompt, no_audit_rows, bare_model_fable [Fable 5.1, effort high], integrity_clean; `a1_review_only`: review_only_phases, oracle_closed, integrity_clean; `a1_no_dissent`: all_phases_present, no_review_dissent_envelope [no review envelope, code_review.enabled false, audit voices 2], oracle_closed, integrity_clean; `a1_full_openmount`: all_phases_present, oracle_open_recorded [mount_overlay=none, oracle_open=true], integrity_clean).
- **Batch-entry gates:** numeric-anchor share 10/10 (`a1_review_only` review), 9/9 (`a1_full_openmount` review), 4/4 (`a1_no_dissent` audit) — all ≥ 0.80; both voices at every dissent-enabled review gate; `budget_scale: diff` (effective 200 c on the 5 KB diff).
- **Open mount:** `oracle_exposed_defects` [] on this trial (the reviewer did not peek; peeking is stochastic — cycle-130 saw it in 1 of 12 original runs), the arm's evidence and rules are correct.
- **Finding (KF-051):** the `a1_no_dissent` REVIEW phase carried a refusal fallback — Fable 5.1 refused the session (category `cyber`) and the pipeline continued on Opus 5.5 (Fable 3,228 vs Opus 14,682 output tokens); the row reads `degraded: true` ("REVIEW: refusal fallback"). First such event in 44 review-catch rows (0 of 36 cycle-130, 0 of 8 Sprint 263 smoke). The Sprint 264 pre-registration excludes fallback rows from the model contrast (R5) and counts them degraded elsewhere; the cell is not retried (that would select on the refusal).
- FR-5 AC 2 → ✓ Met (every rule true per arm); the arms enter the batches.

## Batches (Task 2.5) — at pin `798d88cf`

| batch | cells | rowed | completed | contaminated | cuts | USD | notes |
|---|---|---|---|---|---|---|---|
| `c131-b1-oracle-ab` | a1_full_openmount × r17 × 3 | 3 | 3 | 0 | 0 | 57.62 | all three open-mount runs peeked (7/15/3 defects exposed); pm3 0.8/0.85/0.6 |
| `c131-b2-control-prices-a` | a0_bare, a0_bare_fable, a1_full × r17, r18 × 3 | 18 | 16 | 2 (a0_bare r18 t1: real curl probe; a1_full r18 t1: $HOME/tmp scratch repo → S3) | 0 | 152.03 | REVIEW phases 19–48 min inside the bounds; no refusal fallback |
| `c131-b2-control-prices-b` | a1_review_only, a1_no_dissent × r17 × 3 | 6 | 5 | 1 (a1_no_dissent t3: outside_path in the AUDIT phase, see NOTES) | 1 at the 80 cap, resumed with 90 under DEC-0649 | 82.87 | review_only pm3 0.65 × 3 (USD 10.8–11.7); no_dissent 0.75, 0.75, (0.6 contaminated) |

Scans per row (pin, took-effect, degraded, oracle, voices/budget/anchors, fallbacks, catch, cost): `batch-scans.md`. FR-6 AC 3: every closed-mount row's `oracle_exposed_defects` is empty; every row's took-effect rules are true (`status` would be `infrastructure_error` otherwise); dissent fields and per-phase models recorded; `copy_source == source_commit == 798d88cf` on every row.
