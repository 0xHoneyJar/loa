# Annotation run — cycle-132 Task 1.6 (Sprint 269)

Two blind annotators (Opus 5.5, `blind-session.sh`, packets from `annotation-packets.sh`, no run directories denied — DEC-0716) labelled every fix hunk and post-merge incident of the 14 candidate fixtures (DEC-0715). The lead adjudicated every disagreement by the rules of DEC-0717 (anchors = union of in-hunk sites; one wrong behaviour per group; the same flaw on another code path is a member site, a helper, wiring or compiled copy is a follow-on; documentation text is `docs`; a malformed record is rerun blind, never edited), with the reason on every record (`<fx>/decisions.json` → `<fx>/adjudication.json`). Merged v2 labels: `evals/fixtures/review-prs/labels/pr-NN.tsv` + `manifests/pr-NN.json` (label_set v2, approved_by lead 2026-10-21); the seeded review-derived set is preserved at `labels/review/` + `manifests/review/`; SHA256SUMS frozen (1,804 files).

| fixture | hunks | κ verdict | κ severity | localization | grouping Jaccard | items | adjudicated | share | v2 defects | incident-confirmed | review-driven share | review key confirmed | reruns | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pr-27 | 28 | 1.000 | 1.000 | 1.000 | 0.973 | 31 | 6 | 0.194 | 13 | 1 | 0.769 | 5/7 | 0 | 0.880 |
| pr-28 | 9 | 1.000 | 1.000 | 1.000 | 1.000 | 11 | 1 | 0.091 | 3 | 0 | 1.000 | 2/2 | 0 | 0.320 |
| pr-23 | 66 | 0.938 | 0.861 | 1.000 | 0.792 | 77 | 27 | 0.351 | 13 | 1 | 0.615 | 1/1 | 1 | 2.880 |
| pr-14 | 95 | 0.970 | 0.620 | 1.000 | 0.922 | 121 | 13 | 0.107 | 17 | 0 | 1.000 | 2/2 | 0 | 3.740 |
| pr-15 | 227 | 0.930 | 0.762 | 0.971 | 0.525 | 239 | 99 | 0.414 | 45 | 0 | 0.867 | 3/3 | 0 | 6.340 |
| pr-25 | 29 | 0.838 | -0.200 | 1.000 | 0.372 | 39 | 12 | 0.308 | 4 | 0 | 1.000 | 0/1 | 0 | 0.990 |
| pr-16 | 18 | 0.880 | 1.000 | 1.000 | 0.300 | 26 | 11 | 0.423 | 6 | 0 | 0.667 | 3/4 | 0 | 0.590 |
| pr-26 | 54 | 0.551 | 0.630 | 1.000 | 0.846 | 56 | 23 | 0.411 | 9 | 0 | 0.778 | 0/0 | 0 | 1.510 |
| pr-21 | 105 | 0.843 | 1.000 | 0.941 | 0.606 | 108 | 70 | 0.648 | 16 | 0 | 0.938 | 1/2 | 0 | 2.410 |
| pr-19 | 20 | 1.000 | 0.231 | 0.933 | 1.000 | 30 | 7 | 0.233 | 15 | 0 | 0.867 | 9/11 | 0 | 1.100 |
| pr-24 | 31 | 0.784 | 0.210 | 1.000 | 0.963 | 39 | 11 | 0.282 | 9 | 1 | 0.778 | 4/4 | 0 | 1.250 |
| pr-20 | 56 | 0.629 | 1.000 | 1.000 | 1.000 | 57 | 13 | 0.228 | 10 | 0 | 0.300 | 1/4 | 0 | 1.020 |
| pr-22 | 79 | 0.886 | 0.576 | 1.000 | 0.614 | 88 | 44 | 0.500 | 20 | 2 | 0.900 | 9/11 | 0 | 2.230 |
| pr-11 | 18 | 0.780 | 0.000 | 1.000 | 1.000 | 33 | 7 | 0.212 | 5 | 0 | 1.000 | 4/5 | 0 | 0.720 |

**Pooled (14 fixtures):** hunk-verdict κ 0.8776 (n 835); incident κ 0.8846 (n 120); items 955, adjudicated 344 (share 0.360); v2 defects 185 (incident-confirmed 5); defect-weighted review-driven share 0.827; blind-session spend USD 26.00 (rows in `evals/results/ablation-2.0/c132-phase0/rows.jsonl`).

- Every fixture confirmed ≥ 2 defects, so the candidate set of DEC-0715 is the corpus (N = 14, DEC-0718).
- Verdict agreement is high (κ ≥ 0.84 on 12 fixtures; pr-26 0.55 and pr-24 0.78 where annotator B read the same correction applied at several sites as follow-ons — resolved by the member-site rule). Severity agreement varies (κ −0.20 … 1.0; lowest where a fixture has few defects, so one disagreement moves it); grouping disputes are mostly namespace differences (the dominant-correspondence map in `dispute-dump.py`).
- One malformed record (pr-23, role A: a follow-on without a group) → role A rerun blind; the first output is kept at `pr-23/A-invalid-1/`.
- The review-derived keys are mostly inside the v2 keys (confirmed column), and the pipeline-independent set (review_driven = false or label_source incident) is 32 of 185 defects.

Per-fixture detail: `<fx>/merge/result.md`, `<fx>/merge/kappa.json`, `<fx>/merge/adjudication.md`, `<fx>/adjudication.json`; pooled: `pooled/kappa.json`.
