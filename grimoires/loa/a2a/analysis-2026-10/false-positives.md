# Deliverable 3 — the "false positives", hand-labelled

Universe: every flagged region that matched no planted label in the 24 valid runs (the grader's `false_positives`, merged ±3 windows per file): a0_bare 125 regions over 12 runs, a1_full 385 over 12 runs. Sample: 61 regions, stratified by arm × PR (seed 20261015; a0: 5/6/8/8, a1: 8/8/9/9 for pr-05/08/12/13), packaged **blind** (no arm, no run id): the finding text that cites the region, the head-file context, and the PR's diff hunk when the region lies inside the diff. Two Opus 5.5 labelers worked independently under one codebook; a packaging fault in the first pass (22 bare-arm packets showed the review file's head instead of the citing line) was corrected and those 22 re-labelled by both. Scripts: `fp_sample.py`, `fp_repackage.py`, `fp_kappa.py`; labels in `false-positives-labelled.csv` (lead copy with provenance), `data/fp-labels-{A,B}.csv`, `data/fp-labels-adjudicated.csv`.

## Codebook

- `real` — a genuine defect or material correctness/security/robustness problem in the PR's code or text at the cited location, any severity, and the claim is accurate against the code shown.
- `style` — not a defect: naming, wording, refactor preference, documentation polish, speculative hardening with no failure, a duplicate restatement, an observation.
- `wrong` — the claim is factually incorrect given the code shown.
- `not-a-finding` — the citation at this location is a cross-reference or supporting pointer attached to a finding about a different location, a scope listing, or a verdict line — not an asserted defect here. (Added to the operator's three categories after the first packets showed that the grader counts every `file:line` token in the prose as a flagged region.)

## Agreement

| statistic | agree | n | Cohen's kappa |
|---|---|---|---|
| 4 labels | 56 | 61 | 0.876 |
| 3 labels (not-a-finding folded into style) | 57 | 61 | 0.833 |
| real vs not real | 58 | 61 | 0.871 |

Five disagreements, adjudicated by the lead (shown in full in `false-positives-labelled.csv`, column `final`): P04 real (the envelope's documented triage path is broken for the companion's rows; the full arm's auditor reproduced the same gap), P12 wrong (head line 223 still links `resources/REFERENCE.md`, which the finding denies), P17 and P33 real (the PR's own documentation contradicts what the code writes to the sidecar — a factual error in the PR's text, low severity), P39 not-a-finding (`:1872` is a supporting pointer; the asserted location is `:1911-1915`).

## Labels by arm (final)

| arm | packets | real | style | wrong | not-a-finding |
|---|---|---|---|---|---|
| a0_bare | 27 | 12 (44%) | 9 (33%) | 0 | 6 (22%) |
| a1_full | 34 | 5 (15%) | 9 (26%) | 1 | 19 (56%) |

Reading: **`wrong` is essentially absent in both arms** — the reviewers do not hallucinate defects. The bare arm's stray regions are mostly real unplanted issues (and a third cross-references); the full arm's are mostly cross-reference pointers (its feedback format lists several `file:line` tokens per finding) and style/observation items, with one in six a real unplanted issue.

## Corrected precision

Grader precision = planted defects caught ÷ flagged regions. Corrected precision adds the estimated real unplanted issues (the per-stratum `real` share × the stratum's region count) to the numerator; the interval is a within-stratum bootstrap over the sampled packets (10,000 draws). 'Excluding cross-refs' also removes the estimated `not-a-finding` regions from the denominator, since they are not findings.

| arm | planted caught | flagged | grader precision | est. real unplanted | est. cross-refs | **corrected precision [90 %]** | excluding cross-refs |
|---|---|---|---|---|---|---|---|
| a0_bare | 31 | 165 | 0.188 | 42 | 32 | **0.442 [0.364, 0.512]** | 0.547 |
| a1_full | 46 | 626 | 0.073 | 54 | 210 | **0.160 [0.102, 0.220]** | 0.241 |

Per labeler (no adjudication): A gives a0 0.342 / a1 0.160; B gives a0 0.442 / a1 0.160.

Reading: the shipped precision figures (0.199 vs 0.107) understate both arms by about half and overstate the gap between them in relative terms: corrected, the bare arm is right about **44 %** of the regions it flags and the full arm about **16 %**; excluding the pointer tokens the grader should never have counted, 55 % vs 24 %. The full arm's low precision is real — it writes about three times as many findings per PR and most of the extra ones are observations — but the bare arm's extra findings are more often real bugs the key did not plant.

## Real findings next to a planted site (mislocated planted catches)

Lead check of every `real` region within 40 lines or the same function as a planted anchor, against the planted defect's label:

| packet | arm | file:line | planted site | same issue? |
|---|---|---|---|---|
| P04 | a0_bare | `adversarial-review.sh:1925` | L03 at 1898/1906 | no — the companion sidecar path omission (a different real issue; the full arm's MED-007) |
| P23 | a0_bare | `adversarial-review.sh:468` | L07 (pr-12 d7) at 487 | no — positional id collision (a different real issue) |
| P25 | a1_full | `block-destructive-bash.sh:811` | D13 (pr-05 d1) at 776/807 | pointer — a code block of the credited D13 finding (806–808) with a stray :811 token |
| P26 | a0_bare | `check-no-swallowed-jq.sh:153` | D23 (pr-08 d2) at 139 | no — the marker-rule regression at :153 (a real unplanted regression both arms found; D23 is the heredoc-body hole at :139) |
| P27 | a1_full | `adversarial-review.sh:1910` | L03 (pr-12 d3) at 1898/1906 | pointer — the credited d3 finding's secondary ranges (:1910–1927) |
| P40 | a0_bare | `adversarial-review.sh:1814` | L05 (pr-12 d5) at 1835/1851 | no — `_adv_family_of` array injection (a different real issue) |
| P41 | a0_bare | `check-no-swallowed-jq.sh:153` | D23 at 139 | no — same :153 marker-rule regression |
| P47 | a1_full | `check-no-swallowed-jq.sh:153` | D23 at 139 | no — same :153 regression (full arm) |
| P51 | a0_bare | `verdict-derive.sh:137` | L01 (pr-12 d1) at 131 | **yes** — the heading-only `rejected_summary_check`; bare t3 cited the grep line, 6 lines from the anchor → graded miss |
| P54 | a1_full | `check-no-swallowed-jq.sh:153` | D23 at 139 | no — same :153 regression (full arm) |
| P60 | a0_bare | `agy_headless_adapter.py:157` | D24 (pr-08 d3) at 164 | **yes** — the removed `except ValueError` for embedded NUL; bare t1 cited 157, 7 lines from the anchor → the one bare miss on pr-08 is a mislocation |

Reading: two of the sampled bare-arm 'false positives' are planted defects cited a few lines from the anchor (P51, P60); the transcript reading found the same for pr-12's d1 in all three bare trials, d7 and d3 (`mechanism-pr-12.md` §e). Four packets across both arms describe the same **real, unplanted** regression in `check-no-swallowed-jq.sh:153` that the key does not contain — the corpus key is incomplete there.

## Caveats

- 61 packets over 510 regions; the per-stratum shares carry wide intervals (shown). The a0 pr-05 stratum is the whole population (5 regions).
- Labelers could open the fixture's head/base files for context; they never saw the manifests, labels, run ids or arms.
- The first packaging fault affected only bare-arm packets (one-finding-per-line review files); the re-label changed 7 of the 22 affected labels per labeler on average and moved a0's real share down from the first pass.
- `not-a-finding` was added to the codebook by the lead after seeing the first packets; both labelers used it from the start.

