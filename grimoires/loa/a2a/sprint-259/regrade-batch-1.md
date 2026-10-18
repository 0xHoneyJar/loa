# Regrade: cycle-129 review-recall batch 1 under the regenerated record manifests (bd-8o5rx, Task 2.8)

Sprint 259 (cycle-130), implementer F, 2026-10-15. PRD AC-10.1, sprint.md AC-2.7.

## What changed

`evals/harness/seed-corpus-from-record.sh` now keeps generated artefacts out of `fix_regions`
(a `dist/` component; names ending `.map`, `.d.ts`, `.checksum`; `checksums.json`, `REPO-MAP.md`,
`.build-manifest.json`). The eight record manifests were rebuilt with `--build-manifest pr-NN`
from their unchanged labels, then `--freeze` and `--check` (`corpus OK: 842 files match SHA256SUMS`).

| Manifest | defects before | defects after | defect ids | fix_regions before | fix_regions after | excluded paths |
|---|---|---|---|---|---|---|
| pr-11 | 5 | 5 | unchanged | 18 | 18 | 0 |
| pr-12 | 8 | 8 | unchanged | 161 | 161 | 0 |
| pr-13 | 5 | 5 | unchanged | 49 | 49 | 0 |
| pr-14 | 2 | 2 | unchanged | 104 | 95 | 5 |
| pr-15 | 3 | 3 | unchanged | 239 | 207 | 11 |
| pr-16 | 4 | 4 | unchanged | 18 | 18 | 0 |
| pr-17 | 20 | 20 | unchanged | 105 | 105 | 0 |
| pr-18 | 8 | 8 | unchanged | 116 | 116 | 0 |

No `fix_regions` entry of the eight matches the exclusion list afterwards (0 of 769).
Corpus `SHA256SUMS` sha256: `27737553…9b79853` before, `8796b39d…38aceaf3` after; the rows of
batch 1 carry the old value in `corpus_sha256`, so a later batch is distinguishable.

## Batch graded

`evals/results/arms/review-recall/batch-1/` (the only batch; 2026-10-14, source commit 864069f2),
4 arms × 8 fixtures × 3 trials = 96 trials. The batch covers **pr-01 … pr-08 only**: the synthetic
corpus, whose manifests carry no `fix_regions` at all. The regenerated pr-11 … pr-18 manifests are
not read by any trial of this batch, so the refuted share is unchanged by construction, exactly like
recall (graded against labels only).

Method: every trial's stored `review.md` under `artifacts/<task>/trial-<n>/` regraded with
`evals/graders/recall-vs-defects.sh` 1.2.0 twice, `EVAL_MANIFEST_DIR` = the manifests at 4374c446
(before) and the regenerated manifests (after). The results directory was only read; no row was
rewritten. "Row" is the value recorded in `results.jsonl`; "mean" is the mean over trials; "pooled"
is Σ refuted / Σ cited.

| Arm | trials | recall (row mean) | recall before | recall after | refuted share before (mean) | after (mean) | pooled before | pooled after |
|---|---|---|---|---|---|---|---|---|
| baseline | 24 | 1.0 | 1.0 | 1.0 | 0.7658 | 0.7658 | 724/922 | 724/922 |
| no_companion | 24 | 0.9722 | 0.9722 | 0.9722 | 0.7474 | 0.7474 | 774/983 | 774/983 |
| no_karpathy | 24 | 1.0 | 1.0 | 1.0 | 0.7564 | 0.7564 | 715/925 | 715/925 |
| no_rule_files | 24 | 1.0 | 1.0 | 1.0 | 0.7807 | 0.7807 | 818/1032 | 818/1032 |

Per trial, recall and refuted share are identical before and after for all 96 trials, and the
recomputed values match the recorded rows.

## Reading

- Recall is unchanged by construction (labels only) and by measurement (above).
- The refuted share of batch 1 is unchanged because batch 1 never graded a record fixture.
- The exclusion matters for the next batch that grades pr-14 or pr-15: 41 generated regions are gone
  (9 in pr-14, 32 in pr-15), so a finding citing `dist/*.js`, a `.map`, a `.d.ts`, the `.checksum`
  or the `.build-manifest.json` now counts as refuted instead of matched.
