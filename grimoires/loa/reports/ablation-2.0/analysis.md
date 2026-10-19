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

## Files

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
