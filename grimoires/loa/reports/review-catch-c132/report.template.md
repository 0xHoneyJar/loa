# cycle-132 — does the Loa review pipeline catch more real defects per dollar than a bare model, on PRs it has not seen?

**Cycle:** cycle-132 "the conclusive review-catch answer" · **Branch:** `feature/cycle-132-conclusive-review-catch` · **Pipeline under test:** Loa at commit `fbd36a0c` (every Phase 1 row's `source_commit`) · **Binding registration:** `REGISTRATION-15.json` (analysis addendum 16; PREREGISTRATION.md plus addenda 1–16; the pipeline pin unchanged; the full chain with hashes is in `PREREGISTRATION-sha256.txt`) · **Reads taken:** 2026-10-23, Sprint 271, by the lead (Fable 5.1) with `reads-c132.py --final` · **Every table below is copied byte for byte from a generated artefact** by `scripts/report-assemble.py`; `evals/tests/c132-report.bats` fails if a table row appears nowhere in those artefacts.

## ELI5

We asked one question and wrote down, before spending money, how we would answer it: on fourteen real pull requests the pipeline had never reviewed, does Loa's review pipeline (review gate, audit gate, a second model arguing against each) find more real bugs than plain model sessions given the same dollars?

Two blind annotators re-derived the bugs from the fix commits and later incidents, so the answer key was not the pipeline's own past output. Each PR was reviewed twice by the pipeline and twice by a bundle of plain model sessions costing the same money, with the plain sessions' findings pooled. A mechanical grader checked whether a finding pointed at a known bug; a blind judge audited a sample of its verdicts.

The result: the pipeline found about ten points more of the labelled bugs than the same-dollar bundle of plain sessions, and it did so while spending less. But the interval around that ten points runs from about minus nine to plus twenty-nine, so we cannot say the difference is real, and we cannot say it is absent. The pre-registered stopping rule did not fire; the final look reads "inconclusive". Under the older answer key seeded from the original reviews, the plain sessions even came out slightly ahead, so the sign itself depends on which key is used. The pipeline also lost over a quarter of its planned runs to a structural problem: on PRs that modify Loa's own files, the pinned pipeline reads its own already-fixed copies, and those runs were excluded.

Two things came out clearly. Review alone catches fewer bugs than review plus audit. And against plain sessions of the pipeline's own model at the same dollars, the pipeline wins by a wide margin. Nothing shipped by default changes on this cycle's strength.

## The answer

The pipeline (`a1_full`) caught a larger share of the labelled defects than the compute-matched bundle of bare Opus 5.5 sessions (`a0_bare_matched`) on the ten valid PRs, by about ten points of defect-weighted recall, with a 95 % cluster-t interval that includes zero and the registered minimum detectable effect:

{{rows reads.md /^\| (primary|PR-weighted) /}}

{{line reads.md /^Repeated confidence interval/}}

{{line reads.md /^REML LMM/}}
{{line reads.md /^PR-level permutation/}}

**The stopping rule did not fire** at any of the three registered looks, and the final look (information fraction 1) reads **INCONCLUSIVE**: the YES statistic z_yes 1.15 is below the O'Brien–Fleming boundary 2.26 and the NO statistic z_no 0.03 is below its boundary, so neither "the pipeline catches more at the MDE" nor "it does not" is established. **The 25 % guard tripped on the full arm** (eleven of twenty-eight planned cells excluded), so by the registration the read is **inconclusive by degradation**. **The placebo on these rows failed its calibration band** (one in ten shuffled intervals excluded zero against the registered eight percent), so, as pre-specified in §8, the decision rests on the simulation-calibrated group-sequential boundary and the PR-level permutation test (p 0.37) rather than on the bootstrap interval alone. **The sign depends on the key:** under the registered review-derived sensitivity key (nine PRs, fifty-seven defects) the matched bundle reads above the pipeline, with an interval that again covers zero.

## Pre-registered reads (PREREGISTRATION §5)

### Secondary reads

{{line reads.md /^Defects per USD/}}

The matched arm is **dominated**: on the valid pairs the full arm caught seventeen more defects while spending less (USD 276.92 against 330.07; on all spend 358.06 against 443.27), so the registered cost per extra defect has no positive increment to divide by. Since analysis addendum 16 the read carries the registration's own word, `dominated` (DEC-0805), with both increments printed. The session-1 contrasts are unavailable under the c132 validity rules (`no_session1`):

{{tableat reads.md /^\| cost per extra defect \|/}}

{{tableat reads.md /^\| contrast \| read \|/}}

Review alone catches fewer labelled defects than review plus audit (the one registered contrast whose interval excludes zero); the pipeline-independent read (defects with `review_driven = false` or sourced from an incident) has the same sign as the primary on too few PRs to decide; the same-model contrast against bare Fable 5.1 sessions at the same dollars favours the pipeline by a third of the key.

### Co-reads (PREREGISTRATION §5; descriptive, they never enter the decision)

{{rows reads.md /^\| \((a|c)\) /}}

{{tableat reads.md /^\| stratum \| a1_full caught/}}

The pipeline-independent co-read keeps the primary's sign on the defects the production pipeline did not find first; the cost-matched read on the seven pairs within the dollar tolerance is smaller than the primary and its interval covers zero.

### Dollar matching

{{line reads.md /^Dollar matching/}}

{{tableat reads.md /^\| PR \| trial \| cost full/}}

{{line reads.md /^25 % guard/}}

### Missingness (intention-to-run)

{{tableat reads.md /^\| arm \| planned \| rowed/}}

{{tableat reads.md /^\| arm \/ k \|/}}

Bounds with every excluded matched session counted as caught-everything and as missed-everything:

{{rows reads.md /^\| bound: /}}

## Stopping rule (PREREGISTRATION §6)

{{table reads.md "## Looks"}}

Looks 1 and 2 read CONTINUE (look 1 below the minimum-information rule of six valid PRs; look 2 with both conditional powers above the futility floor); look 3 was the final look and reads INCONCLUSIVE by the registered table. No budget stop occurred.

## Sensitivities (PREREGISTRATION §10, registered order; they decide nothing)

{{table reads.md "## Sensitivities"}}

Reading guide. The frozen cycle-131 and v1 keys exist for four of the fourteen fixtures, so after the re-grades (analysis addendum 16) their contrasts read the registered status `too_few_prs` (three PRs with valid pairs); descriptively both keep the primary's sign. **The seeded review-derived key reverses it:** on nine PRs and fifty-seven defects the matched bundle reads above the pipeline (Δ −0.09, interval covering zero). That key was seeded from the original human and pipeline review feedback and holds about a third as many defects as the re-derived v2 key on the same pairs; the primary's positive point estimate is therefore not robust to the choice of key, and the report says so rather than choosing between them after the fact. The judge-corrected sensitivity carries the registered Horvitz–Thompson estimator, which removes 1/m of a defect's credit per rejected citation and so penalises arms with many citations per defect (DEC-0800); it is not an arm comparison. Re-including the oracle-exposed cells (the structural limitation below) moves the estimate up and its interval off zero in the every-form row — that is the read the registration refused to make primary, because exposure is a property of the pinned pipeline on these PRs.

## Placebo (PREREGISTRATION §8)

On the Phase 1 rows, 200 seeded within-PR arm-label shuffles through the primary read:

{{tableat placebo-phase1.md /^\| shuffles \|/}}

{{tableat placebo-phase1.md /^\| unshuffled \|/}}

Verdict **FAIL** on calibration (share excluding zero above the 0.08 band; bias passes), as the Phase 0 placebo on the 63 pre-existing rows also read:

{{tableat ../ablation-2.0/placebo-existing/placebo-existing.md /^\| shuffles \|/}}

The band is not loosened. The pre-specified fallback applies: the primary interval stands beside its placebo-estimated exclusion share, and the decision rests on the group-sequential boundary — whose size the power simulation put at P(YES | Δ = 0) = 0.034 for the complete procedure — and on the PR-level permutation test.

## Positive control (PREREGISTRATION §8, addendum 10)

{{line reads.md /^Positive control/}}

The open mount reads above the closed mount with oracle exposure in nine open runs, so the apparatus distinguishes the two in the expected direction and no read is void. The pre-addendum-10 label (G1 only) is printed beside it as registered.

## Ground truth (Phase 0, Sprint 269)

Two blind Opus 5.5 annotators labelled every fix hunk of `head..fix` and every post-merge incident of the fourteen fixtures; the lead adjudicated disagreements; the merged v2 key is the one every arm was graded against.

{{line ground-truth.md /^\*\*Pooled/}}

{{tableat ground-truth.md /^\| fixture \| hunks \|/}}

Most defects were first found by the production pipeline (defect-weighted review-driven share 0.827), so the labels remain downstream of the thing being measured except for the pipeline-independent subset read above.

## Judge agreement (PREREGISTRATION §9, Sprint 270 Task 2.6)

{{rows judge/result.md /^- (strict|lenient): /}}

The grader's proximity rule credits a citation within three lines of a key anchor; the judge says about one in five such credits describes the labelled defect, in every arm alike. The registered corrected figures (strict, then lenient):

{{table judge/result.md "## Judge-corrected recall and precision per arm (strict"}}

{{table judge/result.md "## Judge-corrected recall and precision per arm (lenient"}}

### Exploratory defect-level read (post hoc; declared in DEC-0800 before its data, sized in DEC-0810)

Forty grader-credited (cell, defect) pairs per arm, drawn with the registered seed; every credited citation of each pair judged blind (593 items, ten sessions, no taint). A pair counts when at least one of its citations describes the defect. This read is not registered and decides nothing; it exists because the registered estimator above removes 1/m of a defect's credit per rejected citation and so penalises the arm with more citations per defect (about four per pair in the full arm against 2.6 in the matched bundle).

{{table judge-defects/result.md "## Per arm (EXPLORATORY / post hoc)"}}

{{table judge-defects/result.md "## a1_full − a0_bare_matched"}}

Read plainly: a quarter to a third of the pairs the grader credits carry at least one citation that a blind judge says describes the defect, in the pipeline and in the matched bundle alike; the difference between them has the primary's sign and an interval three times its width. The open-mount arm describes more of what it is credited with, which is what reading the fixed file should produce.

## Spend (PREREGISTRATION §7)

{{tableat spend.md /^\| item \| USD \|/}}

No batch was stopped by the cap; the arm allowance and every reserve except the judge's were respected (the judge spent USD 43.1 against a reserve of 30; the contingency covered it).

## Honest caveats

1. **The structural limitation.** Nine of the fourteen PRs modify `.claude/`, and the pinned pipeline reads its own fixed copies of those files while reviewing; the registered oracle detector marks such runs exposed and the primary excludes them. Eight full-arm cells fell to it. The re-inclusion sensitivities show what the estimate would be if exposure were ignored; the registration refused to make that the primary, and so does this report.
2. **Degradation.** The full arm kept seventeen of twenty-eight planned cells; the 25 % guard trips and the read is inconclusive by degradation. The matched arm kept twenty-five.
3. **Contamination hand-reads.** Every invalid unit was read by hand (`batch-scans.md`); mechanisms by arm:

{{table batch-scans.md "## Counts"}}

{{tableat batch-scans.md /^\| class \| mechanism \|/}}

4. **Labels downstream of the pipeline.** The v2 key was re-derived from fix commits and incidents, but most of those fixes were prompted by the pipeline's own past reviews (review-driven share 0.827). The pipeline-independent co-read is the honest check and is too small to decide.
5. **Key dependence.** The registered review-derived-key sensitivity reverses the primary's sign (nine PRs, fifty-seven defects, interval covering zero); the frozen c131 and v1 keys keep it on three PRs. Which key one believes decides the sign of the point estimate; no key makes the interval exclude zero in the pipeline's favour at matched dollars.
6. **Placebo calibration.** At ten clusters the cluster-t interval is anti-conservative by about two points; the registration anticipated this and bounded it by the simulated size of the whole procedure.
7. **Judge agreement is low** (κ about 0.2) and the registered correction is biased against arms with many citations per defect (DEC-0800); the exploratory defect-level read puts the describing share at a quarter to a third of credited pairs in every arm, with the arm difference keeping the primary's sign inside a wide interval. The grader stays primary as registered; the semantic question is open.
8. **Corpus ceiling.** N = 14 is every eligible fixture; the power simulation gave P(YES | MDE) 0.82 and P(NO | 0) 0.75 at that N, and a true null ends INCONCLUSIVE in about one study in seven. pr-11 (2026-09-25) is borderline for model exposure and is flagged; the pr-11-out sensitivity is above.
9. **Sixteen addenda** corrected defects exposed by smokes, looks, the judge pilot and the first final read, each registered before the data it governs was read; `PREREGISTRATION-sha256.txt` lists the chain. None changed the primary estimand, the arms, the rule or the cap; addendum 16 supplied the missing label-set and co-read branches of the analysis and the `dominated` label.
10. **Operations.** A host reboot killed the lead session at the start of Sprint 271 (recovered by `/run-resume`); two earlier reboots and one runner kill are recorded in `batches.md`. The Sprint 270 lead ran part of the sprint on Opus 5.5; arm and judge models are pinned in the registration and were unaffected.

## Proof

- **Reproduction** (FR-10): an Opus 5.5 reproducer, from a fresh clone of the record branch into an empty directory, re-grades every recorded run, re-rows, re-reads and re-runs the registered sample live; the record's stage-1 commit is `b15e546e649f98d81378ad3c6261525925b88a1c` (`record/cycle-132-conclusive-review-catch`); the reproducer's report is `reproduction/report.md` beside this file (and `grimoires/loa/a2a/sprint-271/reproduction/report.md` on the record's stage 2), and `REPRODUCE.md` beside this file carries the exact commands and expected hashes.
- **Controls:** the positive control and both placebos above (`placebo-phase1.md`, `placebo-existing/placebo-existing.md`).
- **Judge:** `judge/result.md`, `judge/result.json`, `judge/key-summary.json`; the exploratory defect-level read in `judge-defects/`.
- **Dissent records:** plan-stage Flatline reviews of the PRD, SDD, sprint plan and the pre-registration (`grimoires/loa/a2a/flatline/{prd,sdd,sprint,spec}-flatline-*-final_consensus.json`, `grimoires/loa/a2a/sprint-269/flatline-prereg.json`); the review and audit dissent envelopes of Sprints 269, 270 and 271 (`grimoires/loa/a2a/sprint-26{9,70}/adversarial-{review,audit}.json`, `sprint-270/` copied beside this file, `sprint-271/`); the Bridgebuilder round on the cycle PR.
- **Registration:** `PREREGISTRATION-sha256.txt` (every pre-registration and addendum hash and every REGISTRATION-N.json hash). The reads are bound by REGISTRATION-15 (analysis addendum 16); REGISTRATION-16 (addendum 17) binds the reproduction tooling (`evals/analysis/c132/record_lite.py`, `reproduce.sh`) at the same pipeline pin.
- **Decisions:** DEC-0801 … DEC-0811 (the reads, the stopping-rule outcome, the placebo and positive-control verdicts, the sensitivity re-grades, the exploratory judge read, the record design), each with the alternatives rejected, in `grimoires/loa/decisions.yaml`.

## Files

| file | what |
|---|---|
| `reads.md`, `reads.json` | `reads-c132.py --final` at REGISTRATION-14 (byte-identical across runs; the JSON twin carries every figure) |
| `rows.jsonl` | the 140 Phase 1 rows (groups G1–G3, every registered arm) |
| `power.md` | the power simulation that set N = 14 and the cap |
| `PREREGISTRATION-sha256.txt` | the registration chain |
| `placebo-phase1.md`, `placebo-phase1.json` | the placebo on the Phase 1 rows |
| `judge/` | the blind judge (Task 2.6) |
| `ground-truth.md` | the annotation run (Task 1.6) |
| `spend.md`, `spend.json` | the cycle meter |
| `batches.md`, `batch-scans.md` | the batch record and the contamination hand-reads |
| `scripts/` | the lead's drivers (`batch-c132.sh`, `look.sh`, `final.sh`, `register*.sh`, `run-judge.sh`, `report-assemble.py`) |
| `sprint-270/` | the Sprint 270 gate artefacts (reviewer report, feedback, dissent envelopes) |
| `REPRODUCE.md`, `reproduction/` | the reproduction instructions and the reproducer's report |
| `judge-defects/` | the exploratory defect-level judge read |
