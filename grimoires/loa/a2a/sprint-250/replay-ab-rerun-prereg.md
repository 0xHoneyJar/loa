# Task 4.8 (bd-ewrc) — grader 1.1.0 agreement check and pre-registration of the A/B re-run

Fixed 2026-10-05T23:25Z, before any re-run trial. Audit condition (a) for sprint-249.

## Agreement check (condition (a))

`eval-scripts/s4-regrade.py` re-grades every retained Sprint 3 trial (arms 2079e719 before, 41b783a1 after, c9b7bdc0 ablate) with grader 1.1.0 and manifests from the round, and compares each slot with the blind adjudication (`adjudication.json`, 44 graded misses). Full output: `eval-scripts/s4-regrade.out`.

- Graded-vs-adjudicated disagreements: **38 → 11**. Every review case now agrees exactly (review-pr-02/05: 1.000 on all three arms, the same as adjudication).
- **Condition (a) is not met as stated.** The maximum per-case/arm gap is 2, in two places:
  - audit-pr-07, both arms, +2 over-credit. The D21 audits cite `symlink-manifest.sh:258-262` but call the change a hardening, so the location-only grader credits them and the adjudicator does not. This case is outside the re-run set, and the error is the same in both arms.
  - audit-pr-02, before arm, −2. The 51adc68a t3/t4 D06 findings are semantically right but cite `semver-bump.sh:174-191` / `:160-166`. That is `main()`'s argument parsing, not the defect, so no manifest anchor is justified.
- The remaining gaps are 1 or less. They are cited-the-wrong-line misses (D09 `:71` against 66; D14 `:87-89` against 140) and one under-credit (4c816102 t1 D06, adjudicated missed).
- **Reading.** These residuals are location-vs-semantics limits of a location grader, not parser drops. I did not add anchors to absorb them, because that would fit the manifest to the results. The deviation is disclosed for the Sprint 4 review and audit to rule on.

## Pre-registered rule for the re-run

- **Cases.** review-pr-02, review-pr-05, audit-pr-02, audit-pr-03 and audit-pr-05; n = 9 fresh trials per arm.
- **Arms.**
  - before: `main` 2079e719 with grader 1.1.0 and manifests overlaid;
  - after: the Sprint 3 head 2fcd4af8, with the same overlay.
  - Grader and manifests are byte-identical in both arms.
- **Measures, both reported.**
  1. Grader 1.1.0 recall.
  2. Adjudicated recall. A blind Opus 5.5 adjudicator reads only the fixture and the review `.md`, with the arm and run id hidden, and judges every grader-missed slot.
  - A slot counts as **found** if the review raises the defect's consequence as a finding or a flagged observation, even when it is framed as deliberate. This is the Sprint 3 borderline treatment.
  - It counts as **missed** if the review names the change but judges it acceptable or a hardening.
  - Borderline slots are listed by key in the report.
- **Gate.** For each case, the after arm's slots found must be ≥ the before arm's slots found − 1, on **both** measures.
  - If any case loses by more than 1 slot on either measure, or D06 is missed in after while found in before in ≥ 2 trials, ablate the CLAUDE.loa.md trim and the constraints rationale rewrite separately, and revert the implicated change.
- **The AC stays "Waived" until the gate passes** (condition (c)).
- **Condition (b).** `c9b7bdc0` is preserved as `record/cycle-126-ablate-c9b7bdc0`. The Sprint 3 scratch eval scripts are copied under `a2a/sprint-249/eval-scripts/`.
