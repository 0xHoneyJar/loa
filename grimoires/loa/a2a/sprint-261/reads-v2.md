# Sprint 261 — Task 4.9: the H1 and A4 reads on suite v2 (lead, 2026-10-17T21:10Z)

**Source:** batch `priority-v2-p1` (a0_bare and a1_full on review-01 … review-04 × 3 trials; 24 rows, `suite_version` 2, manifest `ddd200b3…`; launched 2026-10-17T18:41:24Z, complete 20:48:53Z, USD 142.49, no cap failure, no retry, no drift, no outage, no contamination). Pre-registration: NOTES § "Re-pre-registration — cycle-130 ablation, suite v2 batch priority-v2-p1 — 2026-10-17T18:40:55Z" (DEC-0591). Computed with `ablation-report.py --partial` on the v2 rows alone (the script in the tree pools suite versions; Sprint 262's partition fixes that), `/tmp/v2reads/`.

## What happened inside the batch

Nine of the twelve a1_full rows are `degraded`: "review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed". The OpenAI dissent voice (codex-headless on the operator's ChatGPT plan) failed in every container with `401 refresh_token_reused`: the host credential's access token expired on 2026-10-16T06:51Z, and the first container to refresh consumed the shared refresh token inside its private per-run copy, so every later container and the host itself lost the voice (KF-048). The same cause explains P1's four degraded trial-3 rows on 16 Oct and every a1_full calibration run of 17 Oct. The other three a1_full rows (review-04) carry no dissent at all (`budget_exceeded`: the in-sandbox dissent budget gate refuses the pr-13 diff), which the row writer does not flag. The companion voice (claude-headless) answered on every degraded run. a0_bare does not use the dissent and is unaffected.

## The reads

| read | comparison | pre-registered (degraded excluded pairwise) | sensitivity, degraded included (decides nothing) |
|---|---|---|---|
| **H1** on `defect_catch_rate` | a1_full − a0_bare | **inconclusive by degradation**: a1_full's excluded share is 9 / 12 = 0.75 > 0.25 (DEC-0393); the one remaining task (review-04, 5 defects) gives +0.133 [+0.133, +0.133], a zero-variance interval (rows carry no per-defect ids, so every defect takes the row's rate) — an artefact, not evidence | **+0.298 [+0.208, +0.392]** (19 defects, MDE 0.170); task level +0.207 [+0.056, +0.438] (4 tasks) |
| H1 on `hidden_test_pass_rate` | a1_full − a0_bare | not testable on suite v2: no build task met the pre-registered hardness bar (DEC-0590) | — |
| **A4 sensitivity** | a4_no_gates − a1_full | not testable on suite v2: no admissible build task (DEC-0591) → **no pruning of A4** | — |

The script in the tree prints "H1: established" for the pre-registered column; it applies the 25 % guard only to component decisions and does not detect the degenerate interval. Both are report defects (sent to implementer H2 for Sprint 262 Task 5.2). Read under the pre-registered rules as written, H1 is **not established** on suite v2.

Per-arm figures (all 24 rows):

| arm | runs | catch rate (task-mean) | false positives per task (review-01 … 04) | cost per run | wall-clock per run |
|---|---|---|---|---|---|
| a0_bare | 12 | 0.668 | 1.7 / 4.0 / 14.7 / 21.3 | USD 0.70 | 2.8 min |
| a1_full | 12 (9 degraded) | 0.875 | 14.0 / 28.7 / 43.3 / 39.3 | USD 11.17 | 27.2 min |

Per task (defects caught over three trials): review-01 (3 defects) a1 9/9 vs a0 9/9; review-02 (3) a1 9/9 vs a0 8/9; review-03 (8) a1 20/24 vs a0 6/24; review-04 (5) a1 10/15 vs a0 8/15.

## Resulting action

**H1 is not established on suite v2 under the pre-registered rules → halt before promotion; the operator decides** (the operator's halt condition). No pruning follows. The run is HALTED; PR #1283 stays `[INCOMPLETE]`.

The reading behind the halt is narrow and repairable: the comparison was emptied by an infrastructure credential failure, not by the arms. Every number available says the gated pipeline catches more defects than the bare agent on the larger review PRs, at about 16 times the cost and 10 times the wall-clock, with two to seven times the false positives; but those A1 runs had one dissent voice instead of two.

## Options for the operator

- **(a) Re-authenticate Codex and rerun the degraded cells (recommended).** You run `! codex login` in this session. The lead then lands the harness fix (the per-run HOME gets an access-token-only copy, so a container can never consume the host's refresh token again; the batch preflight refuses a run when the access token would expire before the batch ends), re-rows every run directory with per-defect ids (bd-yz1rd), and reruns the nine degraded a1_full cells as a supplementary batch (about USD 95, about 1.5 hours). The pre-registered H1 read is then taken on twelve valid a1_full cells. Spend would reach about USD 1,150 of 1,500.
- **(b) Accept the v2 read as inconclusive.** The report ships with rc.6 stating H1 not established (inconclusive by degradation) beside the sensitivity figure, and no pruning. Spend stays at about USD 1,051.
- **(c) Rerun the nine cells with the companion voice only, as a recorded deviation.** This tests "A1 with one voice" against A0, which is not the pre-registered arm.
- **(d) Stop the experiment here** and ship the harness, the suite and the report as the cycle's deliverable.

Spend at the halt: USD 1,050.84 (`spend.sh` 1,029.14 + the P1 first-attempt ledger 21.70); headroom 449.

---

# After the supplementary batch (lead, 2026-10-18T08:40Z) — the pre-registered H1 read on twelve valid a1_full cells

**Source:** batch `priority-v2-p1b` (a1_full on review-01, review-02, review-03 × trials 1–3 — the nine cells KF-048 degraded; pre-registered addendum NOTES § "Re-pre-registration addendum — cycle-130 ablation, supplementary batch priority-v2-p1b — 2026-10-18T06:07:55Z", DEC-0595; launched 06:17:44Z, stopped 06:30:18Z on the pre-registered condition after three REVIEW phases (the OpenAI voice failed again — a different cause, KF-048 recurrence 2: the codex CLI treats a missing `refresh_token` key as logged out; fix `00ce0a5a`, DEC-0596), resumed 06:37:31Z with `--max-usd 376`, complete 08:24:54Z; **9 rows, all `completed`, none degraded, both dissent voices on every REVIEW and AUDIT envelope but one (below); USD 104.26 + 12.88 for the three interrupted REVIEW phases; no cap failure, retry, drift, outage or contamination**). The 24 `priority-v2-p1` rows were re-rowed under row writer 1.2 beforehand (`defects_missed`; every other key field identical). Computed with `ablation-report.py` 1.2.0 (`c031144f` + `044ce03d`: the suite_version partition, read states, degenerate check, sensitivity lines, precision, budget-matched) on the tracked `runs.jsonl` (165 rows) with `--partial`, output `/tmp/reads-p1b/`; the nine degraded rows are excluded as "duplicate cell; superseded by priority-v2-p1b-…" and do not count toward the degradation share (AR-21).

## The reads

| read | comparison | pre-registered (degraded excluded pairwise; 25 % guard first; degenerate check) | note |
|---|---|---|---|
| **H1** on `defect_catch_rate` | a1_full − a0_bare | **established: +0.263 [+0.158, +0.386]** (19 defects, paired bootstrap 10,000 at 90 %; a1_full excluded share 0 / 12; not degenerate: four tasks, per-defect ids from `defects_missed`); MDE 0.218 at this n — the interval excludes zero and the point estimate is far above the 0.03 threshold; the MDE is reported, not applied (the power rule governs component decisions) | per task a1 vs a0 defects caught over three trials: review-01 9/9 vs 9/9; review-02 9/9 vs 8/9; review-03 **18/24 vs 6/24**; review-04 10/15 vs 8/15 |
| H1 on `hidden_test_pass_rate` | a1_full − a0_bare | not testable on suite_version 2 — no admissible task (DEC-0590) | H1 is decided on the catch rate alone |
| **A4 sensitivity** | a4_no_gates − a1_full | not testable on suite_version 2 — no admissible build task (DEC-0591) → **no pruning of A4** | — |

Per-arm figures (valid cells, suite_version 2):

| arm | runs (valid cells) | catch rate (task-mean) | false positives per task (review-01 … 04) | precision (true defects ÷ flagged regions) | cost per run | USD per true defect | wall-clock per run |
|---|---|---|---|---|---|---|---|
| a0_bare | 12 (12) | 0.668 | 1.7 / 4.0 / 14.7 / 21.3 | 0.199 (31 / 156) | USD 0.70 | 0.27 | 2.8 min |
| a1_full | 21 rowed, 12 valid (9 superseded) | 0.854 | 23.7 / 23.0 / 42.3 / 39.3 | 0.107 (46 / 431) | USD 11.64 | 3.04 | 28.8 min |

Informational figures (decide nothing):
- **Sensitivity (degraded rows included, cap failures excluded):** H1 established, +0.263 [+0.158, +0.386] — identical, because every a1 cell now holds a valid superseding row.
- **Budget-matched baseline** (the union of a0_bare's three trials per task against a1_full's per-trial catch): a0 union 0.744 vs a1 0.854 → +0.110 (review-01 1.000 vs 1.000; review-02 1.000 vs 1.000; review-03 0.375 vs 0.750; review-04 0.600 vs 0.667); three a0 trials cost USD 2.11 against USD 11.64 for one a1 trial. Reading: three bare passes close less than half of the gap on the large PR and none of it on the small ones.
- **A disclosure the row writer cannot make (bead bd-ocovl):** four valid a1_full cells ran a gate with **no dissent envelope at all** — review-04's three rows (both gates `budget_exceeded`: the framework's own dissent budget gate estimated 366 c > its 200 c budget on the pr-13 diff, as in `priority-v2-p1`) and the `priority-v2-p1b` review-03 trial-1 REVIEW gate (the dissent run was killed by `adversarial-review.sh`'s own 420 s wall-clock cap; its AUDIT gate had both voices). Row writer 1.2 derives `degraded` from `verdict_quality.voices_succeeded` only, so these rows read `completed`, not degraded; both shapes are the pinned framework's own behaviour (its budget gate, its wall-clock cap), not an infrastructure failure, so the pre-registered definition is read as written. **Strict-reading sensitivity (those four rows treated as degraded):** a1_full excluded share 4 / 12 = 0.333 > 0.25 → the guard would read "inconclusive by degradation"; the remaining pairs give +0.274 [+0.107, +0.464] (14 defects); with the four rows simply dropped, +0.274 [+0.107, +0.464]. The direction of the effect does not change under any of the three readings; the pre-registered read is the conservative one on the point estimate (the four rows are a1's weakest).
- Suite version 1 (batch `priority-p1`, its own section, never pooled): H1 not established (pass rate −0.028 [−0.083, 0.000], catch rate −0.096 [−0.188, +0.007]); A4 fails — unchanged from `a2a/sprint-260/reads.md`.

## Resulting action

**H1 is established on suite v2 under the pre-registered rules → the cycle continues to Sprint 262 (report, docs, rc.6).** No pruning follows from this cycle: the A4 sensitivity is not testable on v2 (no build task met the hardness bar) and the pre-registered reading for that case is "no pruning of A4" (DEC-0559, DEC-0591); A2, A3, A5, A6, A7 are `Not run (cut)`. Task 5.4 records "no pruning made".

What the numbers say, plainly: on review PRs the gated pipeline (two review gates, each with a two-voice dissent) catches more seeded defects than one bare Opus pass — the lift is concentrated on the large PR (review-03: 18 of 24 against 6 of 24) and absent on the two small ones — at about 17 × the cost, 10 × the wall-clock, two to fourteen times the false positives per task, and half the precision per flagged region. Three bare passes for a fifth of the cost close less than half the gap on the large PR. On fair, fully specified build tasks the bare agent saturates (DEC-0590), so no build-side benefit was measurable at this scale.

Spend after the batch: USD 1,167.98 of 1,500 (`spend.sh` over every rows file 1,133.40 + the P1 first-attempt ledger 21.70 + the p1b interrupted-phase ledger 12.88); headroom 332.02.
