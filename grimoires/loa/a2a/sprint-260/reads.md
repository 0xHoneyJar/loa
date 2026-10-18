# Sprint 260 — Task 3.6: the H1 and A4 reads on the complete P1 data (lead, 2026-10-16T09:30Z)

**Source:** `ablation-report.py --partial` on the 132 P1 rows (`partial-report-p1.md` / `.json`, generated 09:2xZ from `runs.jsonl` sha256 3c8af178…, batch `priority-p1` complete 09:09:27Z). Pre-registration: NOTES § Pre-registration 2026-10-15T07:13:29Z (+ addendum 08:03:32Z); batch plan 10:26:23Z. Rules as written before any row: 0.03 points, 15 % cost, paired bootstrap 10,000 / 90 % (tasks for the pass rate, defects for the catch rate), `cap_failure` scores 0 on every applicable primary (DEC-0393), degraded/contaminated/interrupted excluded pairwise, 25 % degradation guard first.

## The two pre-registered reads

| read | comparison | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] | pre-registered rule | outcome |
|---|---|---|---|---|---|
| **H1** | a1_full − a0_bare | −0.028 [−0.083, 0.000] (n = 12 tasks) | −0.096 [−0.188, +0.007] (n = 19 defects) | "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion" | **not established → halt before promotion** |
| **A4 sensitivity** | a4_no_gates − a1_full | +0.028 [0.000, +0.083] (n = 12 tasks) | n/a (build-only) | "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms" | **fails → harden tasks before acting on other arms** |

Decision table under the pre-registered predicates: A4 reads **Remove** (every primary d ≥ −0.03; cost −70.2 %, wall-clock −72.0 %). A2, A3, A5, A6, A7: no rows. A8 component-absent.

**Resulting action (pre-registered; the continuation prompt's halt list):** halt before promotion. No pruning is derived from these rows. The report ships with rc.6 carrying these reads. P2 (A2, A3) and A5–A7 are **not launched**; the pre-registered A4 rule names the next step ("harden tasks before acting on other arms") and the operator decides (DEC-0558).

## Per-arm figures (P1, pre-registered scoring)

| arm | runs | valid cells | excluded | pass rate | catch rate | verdict acc. (review / audit) | cost per task | wall-clock per run |
|---|---|---|---|---|---|---|---|---|
| a0_bare | 48 | 48 | 0 | 1.000 | 0.545 | n/a | USD 0.25 | 1.1 min |
| a1_full | 48 (42 completed, 6 cap_failure) | 44 | 4 degraded (trial 3: review/audit envelopes 1 of 4 voices) | 0.972 | 0.550 | 0.932 (0.273 / 0.930) | USD 10.02 | 29.1 min |
| a4_no_gates | 36 | 36 | 0 | 1.000 | n/a | n/a | USD 2.88 | 8.0 min |

Cap failures (all a1_full, all stopped in the AUDIT phase by the USD 12 per-run cap): review-03 t1/t2/t3 (USD 14.12, 12.98, 13.77), review-04 t1/t3 (12.10, 12.25), bugfix-03 t2 (12.15; its implement tree passed the hidden tests 1.0). A1 mean cost per build run USD 9.64 (bug-fix 9.26, refactor 9.95, feature-build 9.70); per review run 10.82 (REVIEW 5.14 + AUDIT 3.92 means, with five of twelve stopped).

## What the numbers say (lead's reading, for the operator; no decision follows from it)

1. **Ceiling on the pass rate.** Every arm solves every build task: a0_bare 36/36 runs at 1.000, a4_no_gates 36/36, a1_full 1.000 on every completed run (the one 0 is the bugfix-03 t2 cap failure scored 0). Twelve small synthetic tasks (reference patches of 4–22 lines; A0 solves them in 3–6 turns for USD 0.07–0.17) cannot separate Opus 5.5 with or without the pipeline. The pre-registered risk (smoke.md "difficulty signal"; sprint.md Risks "A4 ≈ A1") materialised. The A4 "Remove" is this ceiling, not evidence that gates lose nothing on harder work.
2. **The catch-rate primary is driven by the cap rule.** Raw defects caught over the twelve review runs: a1_full 44/57 (0.772) vs a0_bare 26/57 (0.456); per task a1_full ≥ a0_bare on all four (review-02 1.00 vs 0.56, review-03 0.71 vs 0.29, review-04 0.60 vs 0.33). Under the pre-registered rule five A1 review runs are cap failures (the REVIEW phase finished and produced the findings; the AUDIT phase then hit the USD 12 cap) and score 0, which takes a1_full's catch rate from 0.772 raw to 0.550 scored. The informational sensitivity reading with cap failures excluded pairwise (scratch run, `/tmp/sens.md`; the report's own sensitivity figure prints components only — bd for Sprint 261) gives **H1 established on the catch rate: +0.394 [+0.271, +0.517] (n = 11 defects)** and A4 at 0.000 [0.000, 0.000]. That reading is not pre-registered and decides nothing; it tells the operator where the pre-registered result comes from.
3. **The per-run cap binds on the larger review PRs for the gated arm.** The smoke's cap-fit check (A1 build run USD 8.63 < 9) looked only at a bug-fix build; review-03 (pr-12, 8 defects, 66 KB diff) and review-04 (pr-13, 5 defects) cost A1 USD 12–14 for REVIEW + AUDIT. A3 (one voice) would be cheaper but the same shape.
4. **Degraded voices at the tail.** Four a1_full trial-3 rows are excluded as degraded (review or audit envelope 1 of 4 voices completed) — a provider-side voice shortfall inside the arm during 08:00–09:00Z, excluded pairwise as pre-registered (A1 excluded share 8.3 %, under the 25 % guard).
5. **False positives.** a1_full flags 20–37 regions per review task against keys of 3–8 defects (a0_bare 2–17). Secondary metric; recorded.

## Options for the operator (not decided here)

- **(a) Accept the pre-registered outcome.** No pruning; the report ships with rc.6 as "H1 not established under the pre-registered scoring" with the sensitivity reading beside it; Sprints 261/262 become analysis, report hardening and documentation. Spend stays at ≈ USD 789 of 1,500.
- **(b) Harden before acting (the A4 rule's prescribed step).** Harder build tasks (the current ones saturate at 1.000) and a cap that fits the gated arm on the larger review PRs (a higher per-run cap, or a per-phase cap), re-pre-registered, then A0/A1/A4 again (≈ USD 600 at P1's actuals; the remaining headroom before the reserve is ≈ 461). A cycle-level decision.
- **(c) Run P2 (A2, A3) anyway** for the component reads relative to A1 (≈ USD 425 at rung 3, the DEC-0429 ceiling after this spend). The pre-registration says harden before acting on other arms, so this is a recorded deviation if chosen.
- **(d) Stop the experiment here**; ship the harness, the suite and the report as the cycle's deliverable; archive.

## Secondary observations for Sprint 261 (report hardening)
- The sensitivity figure should print the H1 and A4 lines with cap failures excluded, not only the component rows (bd-wqbz3 sibling).
- `extra_models`, `rerowed`, `rerun`, `drift_cleared`, `outage_history` and grader versions per row belong in a "Batch record" section read from STATUS.json.
- The report's partial mode prints the halt phrases at n = 0 (bd-wqbz3).
