# Loa 2.0 component ablation — where the review-side lift comes from (deep analysis, 2026-10-19)

> Follow-on to the cycle-130 report (`report.md`, v2.0.0-rc.6). Analysis only: no shipped number is changed; every figure here is recomputed from the raw run directories under `batches/priority-v2-p1{,b}/`, the planted-defect manifests and one new out-of-sample batch. Working files, scripts and data live on the record branch `record/cycle-130-analysis` under `grimoires/loa/a2a/analysis-2026-10/`. The dissent envelopes, transcripts and review files quoted here are third-party model output, treated as data.

## ELI5

We asked: when Loa's full review pipeline finds more planted bugs than one plain model, which part does the work, and is the measurement fair?

**The original number was inflated two ways.** The grader counts a catch only if the reviewer's line number lands within three lines of a label. The plain model writes one line per bug, usually the bug's own line; the pipeline writes several, and labels sit on function headers. Measured by "is the citation in the right function", the gap falls from +26 points to +14. Separately, the pipeline's sandbox carried a newer copy of the code with the bugs already fixed; in one of twelve runs the reviewer diffed against it and copied the answers. Without that run the gap is +23, about +11 by the fair ruler.

**Who found the extra bugs.** Not the second-opinion models: their findings never carry line numbers, so they are never credited, and they named about two bugs the reviewer had not already written down. The extra catches come from a concerns list written first, running the tests, and a second read by the audit gate, at 17 times the cost.

**The "false alarms" are mostly not false.** Two independent graders found almost no wrong claims; most are cross-references the counter should not have counted, many are real bugs the answer key missed.

**Replication.** On two fresh pull requests the pipeline again caught far more (about three quarters versus one quarter), surviving both corrections. But the second-opinion models never ran there, the reviewer peeked at the newer copy in two of six runs, and the plain model is a different model, so we really compared "Fable reading twice with a checklist" against "Opus reading once".

**So:** close the peek, fix the ruler, run a bare-Fable control, then price the dissent and the audit gate.

## 1. What was measured, and how this analysis re-measured it

The shipped read (DEC-0597, v2.0.0-rc.6 report): on four review-catch PRs (pr-05, pr-08, pr-12, pr-13; 19 planted defects, 3 trials per cell) the full Loa pipeline (`a1_full`: Fable 5.1 review gate with a two-voice dissent, then a Fable audit gate with its own dissent) beat one bare Opus 5.5 session (`a0_bare`) on `defect_catch_rate` by **+0.263 [+0.158, +0.386]** at 17 × the cost. This analysis started from the 24 valid run directories, not from the report: every agent-written file and dissent envelope was re-graded with the grader's own citation rule (exec'd from `ablation-grade.sh`, identical to every `grade.json`), every catch was timed against the dissent's launch and return in the transcripts, every gate's cost was split into the Fable session and the voices' ledger rows, and two Opus readers read the pr-12 and pr-13 transcripts end to end.

## 2. Contingency (deliverable 1 — `contingency.md`)

57 paired defect-trials: caught by both 31, **full only 15, bare only 0**, neither 11. Exact McNemar on the discordant pairs p = 6 × 10⁻⁵ (optimistic: trials of one defect and defects of one PR are not independent). The pre-registered defect-level bootstrap reproduces +0.263 (upper bound +0.386; the lower bound sits on a discreteness jump, +0.140 or +0.158). The honest uncertainty with four PRs is the **cluster bootstrap by PR: +0.263 [+0.056, +0.437]** — only 33 distinct resample values; the lower end is where pr-12 drops out (leave-pr-12-out: +0.091). Per PR the lift is 0 on the two ~130-line PRs (bare already at 9/9 and 8/9), **+12 of 24 on pr-12**, +2 of 15 on pr-13.

## 3. Where the lift comes from (deliverable 2 — `attribution.md`)

**No dissent envelope carries a numeric line anchor.** All 24 envelopes anchor findings on function names, hunk headers or code lines, so under the grader's rule the dissent contributes 0 credited citations in every run: every catch is text the Fable reviewer or auditor wrote. Timing the 15 lift catches against the dissent's return: 5 were cited before it returned, 5 fell on gates where no voice ran at all (pr-13's budget gate refused the dissent on every trial; pr-12 t1's review dissent was killed by the 420 s cap), 2 came only from the audit gate, 2 were first cited after a voice had named the enclosing function, 1 after a dissent that named nothing. The transcript reader's causal count for the dissent on pr-12 is ≈ 2 defect-trials of 24. Cost: USD 11.64 per full run, of which the dissent voices are 17 % (USD 1.99) and the audit gate 49 % (USD 5.70).

## 4. The frontier (deliverable 4 — `frontier.md`)

Task-mean catch rate against USD per PR: bare ×1 0.668 @ 0.70; bare ×2/×3 union 0.744 @ 1.41/2.11; full without the audit gate (reconstructed from the review gate's files) 0.799 @ 5.93; full 0.854 @ 11.64; two full runs' union 0.925 @ 23.28. Nothing cheaper than the full pipeline reaches 0.80 in this data; the review gate alone keeps 94 % of full's catch at 51 % of its cost; removing the dissent's cost changes catch not at all (it is never credited) and saves USD 2 of 11.64.

## 5. Two measurement artefacts (`sensitivities.md`)

**The ±3-line window.** Bare writes one `head/<path>:<line>` per finding; the full arm's feedback files carry ranges and several `:N` pointers per finding; manifest anchors sit on function headers or fix-region lines. Bare described pr-12's d1 in all three trials at `verdict-derive.sh:137` (anchor 131), d7 at `:502` (anchor 487), d3 at `:1914` (anchors 1898/1906) — all graded misses — while six of its credits and five of full's are different findings that happen to sit on an anchor line. Re-graded with "±3 or any cited line inside the anchor's function": bare 42/57, full 50/57, **gap +0.140** (task-mean +0.096) instead of +0.263.

**The mounted-framework oracle (KF-049, new).** Every full-arm sandbox mounts the pinned Loa tree, a later version that already contains every fix; bare mounts nothing. At every planted site of all seven corpus PRs the mounted copy differs from the PR head. In one of twelve runs (pr-13 trial 2) the reviewer diffed the PR head against it "for hints of post-review fixes", saw the fixes for d1–d4, and cited them afterwards; the audit inherited them through a memory note. That one run is pr-13's entire lift. Excluding it pairwise: **+0.228 [+0.105, +0.351]**; zeroing it: +0.175 [+0.035, +0.316]. Both corrections together leave ≈ +0.115 pooled, all of it on pr-12.

## 6. Mechanism (deliverable 5 — `mechanism.md`)

On pr-12 what remains after the artefacts is bought by (i) the skill's concerns pass — the reviewer writes a numbered list of concerns before anything else, and most catches are already in it; (ii) reproductions — 18 test executions and 7 harness probes per review gate against 1 and 0.3 for bare, which could not run the PR's bats because `pr/` holds no libraries (execution raised confidence; the reader finds it did not drive discovery); (iii) the second reader (two defect-trials from the auditor); (iv) the dissent (≈ two). The model differs too (Fable reads in full, Opus in bare) and is not separable here. Nobody caught d8 (a test stub's vocabulary; needs a schema outside `pr/` and its anchors are 16+ lines from the real site). The lift is not a function of diff size: zero where bare saturates, concentrated where high/medium logic bugs sit in a long bash script (pr-12), absent or leaked where the defects are low-severity prose (pr-13). Every planted site is inside a diff hunk.

## 7. The "false positives", hand-labelled (deliverable 3 — `false-positives.md`)

61 stray regions (stratified by arm × PR, blind to arm), two independent Opus labelers, one codebook with four labels (real / style / wrong / not-a-finding): kappa 0.88 (4-way), 0.87 on real-vs-not; five disagreements adjudicated by the lead. **`wrong` is essentially absent** (0 of 61 after adjudication, 1 before): neither arm hallucinates defects. Bare's stray regions are 44 % real unplanted issues and a third cross-reference tokens; full's are 54 % cross-reference tokens (its feedback format lists several `file:line` pointers per finding) and 16 % real issues. Corrected precision: **bare 0.19 → 0.44 [0.36, 0.51]; full 0.07 → 0.16 [0.10, 0.22]**; with the pointer tokens the grader should never have counted removed from the denominator, 0.55 vs 0.24. Two sampled bare "false positives" are planted defects cited a few lines from the anchor (pr-12 d1 at `:137`, pr-08 d3 at `:157`), and four packets across both arms describe the same real regression in `check-no-swallowed-jq.sh:153` that the key does not contain.

## 8. Out-of-sample replication on pr-17 and pr-18 (deliverable 6 — `replication.md`)

Batch `replication-01` (pre-registered in NOTES 2026-10-19T02:49:20Z, DEC-0602/0603): two review-catch PRs no analysis or arm had touched — pr-17 (20 labelled defects, 4,437-line diff) and pr-18 (8 defects, 2,194 lines) — same arms, pin, caps and rule. Valid cells 4 of 6; excluded share a0 0.00, a1 0.33.

**Pre-registered read:** on the 4 valid cells a1_full − a0_bare on `defect_catch_rate` = +0.524 [+0.393, +0.643] over 28 defects; the 25 % guard → the formal verdict is **inconclusive by degradation** under the rule as written (the arm's excluded share exceeds 0.25; both excluded rows are grader-scan false positives on the PR's own repository name, KF-046 recurrence 9, read by hand). Per PR (valid cells): review-r17 bare 13/60 vs full 45/60; review-r18 bare 0/8 vs full 4/8.

**Sensitivities (all exclude zero; decide nothing):** the two contaminated rows hand-read and included → **+0.452 [+0.310, +0.595]** (review-r17 bare 13/60 vs full 45/60; review-r18 bare 7/24 vs full 13/24); oracle-exposed cells (review-r17-t1, review-r18-t1) excluded → +0.393 [+0.214, +0.571]; every catch that followed a head-versus-later-copy diff set to zero → +0.333 [+0.190, +0.476]; same-function window bare 33 vs full 60 of 84 (+0.321). Original for comparison: +0.263 [+0.158, +0.386].

Dissent: `budget_exceeded` at every review gate (pr-18 estimates 214 c against the 200 c cap) and at four of six audit gates — the full arm here is Fable review + Fable audit with no second voice at the review gate. Oracle (KF-049): used in two of six runs (`review-r17 t1`: nine planted sites in the printed diffs, all nine cited afterwards, seven of them missed by bare; `review-r18 t1`: one). Cost per run a0 USD 1.43 / a1 USD 13.37; wall 5.6 / 34.3 min; precision a0 0.180 / a1 0.113; batch spend USD 88.81.

Reading: the lift reappears on PRs nobody looked at, larger than the original, and survives both corrections; the pre-registered gate was tripped by the measurement apparatus, not by the arms. What the replication cannot do is separate the model from the pipeline — the comparison is Fable twice with the skill's checklist against Opus once — and it confirms the oracle channel is habitual.

## 9. Loa changes, ranked by expected catch-rate per dollar

Catch per dollar on suite v2 (task-mean catch ÷ USD per PR): bare ×1 0.95; bare ×3 union 0.35; full without the audit gate 0.135; full without the dissent's cost 0.089; full 0.073. The first two changes are measurement fixes: they cost nothing to catch and decide what every later number means, so they come first; the next two are the pipeline changes with the best catch-per-dollar; the last is the control arm that the whole question still lacks. Each is written as "change X because measurement Y, testable by Z", with the A/B that would prove it wrong. None is applied here; each is a `cycle-131-candidate` bead.

1. **Mount the review-catch sandbox's framework at the PR's base commit, or strip every PR-touched path from the mount** — because at every planted site of all seven corpus PRs the mounted `ba11b860` copy differs from `pr/head`, and the reviewer diffed the two and then cited the exposed fixes in one of twelve original runs and two of six replication runs (nine of fifteen catches in `review-r17 t1`; KF-049) — testable by rerunning the three pr-13 and three pr-17 full trials with the mount pinned (≈ USD 85): the change is wrong if the catch does not fall on the previously exposed cells. Expected effect on catch: none when the reviewer did not peek; the number becomes an honest one.
2. **Grade with multi-site labels and a same-function rule, or require range citations from every arm** — because bare described pr-12's d1, d3 and d7 and pr-13's d5 at the bug line while the anchors sit on function headers or fix-region lines, and re-grading at "±3 or same function" halves the original gap (+0.263 → +0.140; replication +0.452 → +0.321) — testable at USD 0 by re-grading the 36 existing runs under the new rule plus a 20-packet two-labeler adjudication of the credits it adds (kappa reported): the change is wrong if the added credits are mostly unrelated findings.
3. **Run the audit gate on review PRs only when the review gate approves (or above a diff-size threshold)** — because the audit gate is 49 % of a full run (USD 5.70 of 11.64) and removing its citations costs 0.055 of task-mean catch (0.854 → 0.799; two of 46 catches were audit-first), lifting catch per dollar from 0.073 to 0.135 — testable by an `a1_review_only` arm on the four v2 PRs × 3 trials (≈ USD 70): wrong if catch drops by more than 0.10 or the review-gate verdict accuracy falls below the audit's.
4. **Make the dissent cite lines and size its budget to the diff, or drop it from review-catch gates** — because no envelope in 36 runs carries a numeric anchor (0 credited citations), its causal contribution on pr-12 is ≈ 2 defect-trials of 24, it costs 17 % of a full run where it runs, and its 200 c budget gate refused every review gate on pr-13, pr-17 and pr-18 (so the shipped "two-voice" pipeline ran with no second voice on three of six PRs) — testable by `a3_one_voice` and a no-dissent arm on pr-12 × 3 (≈ USD 45) and by counting numeric anchors after an anchor-format change: wrong if the no-dissent arm loses more than 0.08 catch on pr-12.
5. **Add a bare-Fable control arm (`a0_bare` with Fable 5.1 instead of Opus 5.5)** — because the dissent never ran at the review gate on three of six PRs, so the measured lift is "Fable twice with the skill's checklist" against "Opus once", and the model is the largest unexplained term (`mechanism.md` §1) — testable by 12 bare-Fable runs on pr-12 and pr-17 (≈ USD 30 at bare prices): if bare-Fable reaches the pipeline's catch, the pipeline's own contribution is the second read and the checklist, not the gates; if it stays at Opus's level, the gates earn their cost.

Not recommended yet: routing small PRs to two bare passes (bare saturates on the two ~130-line PRs and two passes reach 0.744 at 12 % of full's cost) — true in this data but on two PRs with three defects each; add two small corpus PRs before acting on it.

## 10. cycle-131 addendum — honest review-catch measurement (2026-10-19/20)

### ELI5

In cycle-130 we said the full Loa review pipeline catches far more planted bugs than one bare model call, at about seventeen times the cost. Three things could have been fooling that number: the pipeline's sandbox contained the already-fixed code (a peek), the grader's ruler was loose in a way that favoured one side, and the full pipeline ran on a different model (Fable) than the bare arm (Opus). This cycle closed the peek, re-measured with a stricter ruler, and ran the bare arm on Fable too. Result: the peek was real but small on the PR where we could measure it (the open mount lifted the catch by roughly 0.07, within noise); the looser "same-function" ruler we had proposed turned out to credit the wrong finding five times out of seven, so we did not adopt it; and the model is not the explanation — a bare Fable session catches *fewer* planted bugs than a bare Opus session (0.23 vs 0.39), while the full pipeline on Fable catches 0.68. The pipeline's gates, not the model, carry the lift. We could not price the audit gate or the dissent at this sample: three trials on one PR leave both reads inconclusive or insufficient, and the pre-registered cell threshold we wrote was stricter than the design could meet — reported as written, with the intended threshold beside it. Spend: about USD 443 of the 500 cap.

### 10.1 What changed since §9 (the five changes, built and gated)

| Change (from §9) | Built as | Gate evidence |
|---|---|---|
| Close the peek (R1, KF-049) | the closed mount: every answer-bearing `.claude/` path overlaid with the PR's own version before any phase, pre-launch check, `oracle_closed` took-effect rule, grader oracle detector (diff + read forms) | smoke 7/7 `oracle_closed OK`; batches: `oracle_exposed_defects` empty on every closed-mount row; the open-mount control arm peeked in 3 of 3 B1 runs (7/15/3 defects exposed) |
| Fix the ruler (R2) | grader 1.3.0 with three results (`recall_pm3_v1` on the frozen v1 labels, `recall_pm3` on curated multi-site labels, `recall` = ±3 or same enclosing definition); regression 36/36; blind two-labeler adjudication | the same-scope rule was **not adopted**: 2 of 7 same-scope credits were the labelled defect (kappa 1.0) → `recall_pm3` is the decision statistic (DEC-0638) |
| Bare-Fable control (R5) | arm `a0_bare_fable` | 6 rows, see 10.3 |
| Price the audit gate (R3) | arm `a1_review_only` | 3 rows, see 10.4 |
| Price the dissent (R4) | `anchor_line` in every voice's findings + `budget_scale: diff` (eval config); arm `a1_no_dissent` | anchor share ≥ 0.94 everywhere; both voices ran on every dissent-enabled gate (nothing refused at the diff-scaled budget); 3 rows, see 10.4 |

### 10.2 The re-grade (36 cycle-130 runs, three rules)

36 cycle-130 review-catch runs re-graded under grader 1.3.0 (regression `recall_pm3_v1 == stored recall` on 36/36): the stored `recall` was the ±3 rule on the original labels; `recall_pm3` is ±3 on the curated multi-site labels; `recall` is ±3 or same enclosing definition (not adopted). Rows: `grimoires/loa/reports/ablation-2.0/regrade-c131/rows.jsonl`; detail per run in `a2a/sprint-1/regrade-c131.md`.

| cells | `recall_pm3_v1` (stored ruler) | `recall_pm3` (curated labels) | `recall` (same-scope, not adopted) |
|---|---|---|---|
| p1/p1b a0_bare × review-01..04 (12) | mean 0.625 | mean 0.727 | mean 0.829 |
| p1/p1b a1_full × review-01..04 (12) | mean 0.829 | mean 0.927 | mean 0.969 |
| replication a0_bare × r17, r18 (6) | 0.263 | 0.371 | 0.400 |
| replication a1_full × r17, r18 (6) | 0.646 | 0.771 | 0.796 |

The curated labels raise both arms (they credit the human finding's cited lines); the same-scope rule raises them further but the adjudication showed those extra credits are mostly other findings in the same function. The detector flagged 3 oracle-exposed runs by the diff form (review-04 t2, r17 t1, r18 t1) and 2 more diffs the analysis had missed (r17 t2, t3), plus incidental later-copy reads on 7 runs; the union is the exclusion set (DEC-0632).

### 10.3 The oracle A/B (R1) and the model control (R5)

**R1 — did the open mount inflate the catch?** `a1_full_openmount` (the pin's framework copy mounted as in cycle-130) vs `a1_full` (closed mount) on pr-17, 3 trials each: open 0.750 vs closed 0.683, Δ = +0.067, 90 % [−0.017, +0.150]. The detector shows the open mount was used in every open run (7, 15 and 3 of 20 defects exposed). Pre-registered branch: under the written `min_valid_cells 4` → **insufficient**; at the trial level → **investigate** (not above +0.05, not inside ±0.05). The peek is real, bounded on this PR, and not the size of cycle-130's lift (DEC-0651).

**R5 — does the model explain the lift?** `a0_bare_fable` (one Fable 5.1 session, the bare prompt, no mount) vs `a1_full` and vs `a0_bare` (Opus 5.5) on pr-17 and pr-18, 28 defects:

| contrast | A | B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A vs B |
|---|---|---|---|---|---|---|
| bare-Fable − full | 0.226 | 0.685 | −0.458 | [−0.601, −0.316] | [−0.563, −0.417] | 4.28 vs 19.94 |
| bare-Fable − bare-Opus | 0.226 | 0.393 | −0.167 | [−0.310, −0.018] | [−0.250, −0.133] | 4.28 vs 1.40 |

Pre-registered branch: **between (both intervals reported)** — neither contrast is within ±0.05. Reading: a bare Fable session catches fewer planted defects than a bare Opus session; the gated pipeline on Fable catches three times as many as bare Fable. The lift is the pipeline's, not the model's (DEC-0654). Same branch under every sensitivity.

### 10.4 The two prices (R3 audit gate, R4 dissent)

**R3 — what does the audit gate buy?** `a1_review_only` vs `a1_full` on pr-17: 0.650 vs 0.683, Δ = −0.033, 90 % [−0.133, +0.067]; cost USD 11.42 vs 21.50 per run (ratio 0.53). Branch: **insufficient** as written (3 cells); trial level **inconclusive** — the interval straddles the ±0.05 opt-in band and does not fall below −0.10. The audit gate costs 47 % of the run for a catch contribution this sample cannot resolve (DEC-0652). No shipped-default change is proposed.

**R4 — what does the dissent buy?** `a1_no_dissent` vs `a1_full` on pr-17: only 2 of 3 no-dissent cells are valid (the third read `contaminated`: a reproduction under `/home/evaluser/audit-scratch`, a scratch directory outside the shapes S3 declared); **insufficient** under every read. Descriptively the two cells read 0.75 and 0.75 vs 0.683 (Δ +0.067 [−0.05, +0.19]). What this cycle did prove about the dissent: with `budget_scale: diff` it runs on the large PRs that cycle-130 refused at 200 c (effective 406 c on pr-17, 257 c on pr-18), both voices completed on every dissent-enabled gate in 27 of 27 rows, and ≥ 0.90 of its findings now carry a numeric `anchor_line` the grader can credit — the measurement is now possible; the price is not yet measured (DEC-0653).

### 10.5 Adjudication (Task 1.10)

Two independent Opus 5.5 labelers, 17 blind packets (all 7 same-scope-only credits + 10 of 40 anchor-expansion-only credits, stratified by arm × PR, seed 20261015), agreement 1.000 / Cohen's κ 1.000. Group (a): 2 of 7 same-scope credits describe the labelled defect (0.286, Wilson 95 % [0.082, 0.641]) — below the pre-registered 80 % bar → the rule is not adopted. Group (b): 6 of 10 anchor-expansion credits (0.600 [0.313, 0.832]) — reported, decides nothing; a caveat on the curated anchors. Record: `a2a/sprint-1/adjudication/result.md`.

### 10.6 Spend

| item | USD |
|---|---|
| Sprint 263 smoke (7 PRs) + pr-17 re-smoke | 91.45 + 22.46 |
| Sprint 264 arm smoke (pr-05) | 21.77 |
| B1 `c131-b1-oracle-ab` | 57.62 |
| B2a `c131-b2-control-prices-a` | 152.03 |
| B2b `c131-b2-control-prices-b` (incl. the resumed cell) | 82.87 |
| dissent runs (5), Flatline planning runs, adjudication labelers | ≈ 15 |
| **cycle-131 total** | **≈ 443 of the USD 500 cap** (batch allowance 300: spent 292.52) |

Per-run cost of `a1_full` under the closed mount with the dissent actually running: USD 17–24 on pr-17/pr-18 (about double cycle-130's), because the diff-scaled dissent now runs where the fixed 200 c budget used to refuse it.

### 10.7 Honest caveats

- The pre-registration carried `min_valid_cells 4` while planning 3 trials per arm on one PR for R1, R3 and R4; under the rule as written those three main reads are "insufficient" by construction. The hashed text was not edited; the trial-level sensitivity (min 3) is reported beside each (DEC-0650). Which branch a reader takes is stated, not chosen for them.
- Two B2a rows were `contaminated`: a bare run fetched the upstream `CLAUDE.loa.md` (a real probe; excluded everywhere) and a full-pipeline audit built a scratch repository under `$HOME/tmp` to reproduce a claim (re-included only in sensitivity S3, declared before the reads).
- pr-12 cannot run under the closed mount (import skew, KF-050) and stays re-grade-only; pr-17 needed task bounds of 50/40 min and a USD 30 run cap once the dissent actually ran (DEC-0640); a Fable review session refused once and fell back to Opus (KF-051; such rows are excluded from the model read).
- The priced-in dissent roughly doubled the cost of a full run (USD 10–22 per PR); the batch allowance was re-derived to USD 300 (DEC-0645) and B2b's last cell was resumed within it (DEC-0649).
- All reads are on two PRs (pr-17: 20 defects; pr-18: 8) at 3 trials per cell; the intervals are wide, and this is a measurement of this corpus, not of Loa in general.

### 10.8 Recommendations, re-ranked

| # | change (as a testable Loa change) | status after this cycle |
|---|---|---|
| 1 | **Close the peek**: keep the closed mount as the default for every review-catch evaluation (built; `oracle_closed` true on 24/24 closed rows). | **done** — shipped as harness behaviour; the open mount survives only as the eval-only control arm |
| 2 | **Fix the ruler**: adopt the ±3-or-same-function rule. | **withdrawn** — adjudication 2/7; `recall_pm3` on curated multi-site labels is the ruler; the curated labels themselves carry a 6/10 caveat |
| 3 | **Bare-Fable control**: run it before attributing any lift to the pipeline. | **done, answered** — the model does not explain the lift (R5 between: bare-Fable below bare-Opus) |
| 4 | **Price the audit gate** (opt-in on review-only PRs if catch within ±0.05 and cost ≤ 60 %). | **inconclusive at 3 trials** — Δ −0.033 [−0.133, +0.067], cost 0.53; needs ≥ 6 trials on ≥ 2 PRs (≈ USD 200) to resolve |
| 5 | **Price the dissent** (anchors + diff-scaled budget; opt-in if within ±0.08). | **anchors and budget shipped as optional knobs** (defaults unchanged); the price read is insufficient (2 valid cells) — re-run with the S3 path shapes declared up front |

No shipped default changed in this cycle (G-6): `budget_scale` ships `fixed`, `anchor_line` is an additive optional field; the suite's shipped arms are untouched (the four cycle-131 arms sit outside `priority`).

## 11. cycle-132 — the conclusive review-catch answer (2026-10-21/23)

The cycle-132 measurement (fourteen unseen record fixtures, re-derived ground truth with two blind annotators, a hashed pre-registration with a group-sequential stopping rule, four arms plus the open-mount positive control, a blind judge on a stratified sample, and an independent reproduction from a fresh clone) is reported in full at `grimoires/loa/reports/review-catch-c132/report.md`, with the reads beside it (`reads.md`, `reads.json`), the rows, the power simulation, the registration hashes, the judge result, the placebo and positive-control results, the contamination hand-reads and the spend meter. The answer in one sentence, the stopping-rule outcome and every caveat live there; this document is not updated further.

## Files

- cycle-131: `grimoires/loa/reports/ablation-2.0/c131-rows.jsonl` (27 batch rows), `c131-reads.md` (the formal reads), `regrade-c131/rows.jsonl` (36 re-graded cycle-130 runs); record branch `record/cycle-131-honest-measurement` for `a2a/sprint-1…3/` (adjudication packets and labels, smoke and batch scans, dissent envelopes, NOTES).

| deliverable | file (record branch, `grimoires/loa/a2a/analysis-2026-10/`) |
|---|---|
| 1 contingency | `contingency.md`, `contingency.json`, `scripts/contingency.py` |
| 2 attribution | `attribution.md`, `attribution.json`, `scripts/attribution.py` |
| 3 false positives | `false-positives.md`, `false-positives-labelled.csv`, `data/fp-packets-blind.md`, `data/fp-labels-{A,B,adjudicated}.csv`, `scripts/fp_sample.py`, `scripts/fp_repackage.py`, `scripts/fp_kappa.py` |
| 4 frontier | `frontier.md`, `frontier.json`, `scripts/frontier.py` |
| 5 mechanism | `mechanism.md`, `mechanism-pr-12.md`, `mechanism-pr-13.md`, `data/mechanism-stats.md`, `scripts/mechanism_stats.py` |
| sensitivities | `sensitivities.md`, `scripts/window_sensitivity.py`, `scripts/oracle_scan.py`, `data/oracle-scan.json` (KF-049) |
| 6 replication | `replication.md`, `replication-authoring.md`, `replication-driver-diff.md`, `self-check-replication.log`, `data/replication-read.json`, `scripts/replication_read.py`; suite `grimoires/loa/evals/ablation-2.0-replication/`; rows `evals/results/ablation-2.0/runs.jsonl` (batch `replication-01`) |
| extraction | `scripts/common.py` (exec's the grader's citation rule), `scripts/extract.py`, `data/runs.json` |
