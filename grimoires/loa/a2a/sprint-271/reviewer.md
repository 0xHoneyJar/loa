# Sprint 271 (cycle-132 Sprint 3) — implementation report for the reviewer

**Cycle:** cycle-132 "the conclusive review-catch answer" · **Branch:** `feature/cycle-132-conclusive-review-catch` · **Sprint range:** `03e12ed0..<HEAD>` · **Lead:** Fable 5.1 (session 04024019; resumed via `/run-resume` after the 2026-10-23T10:07Z host reboot) · **Implementers:** Opus 5.5 (A: label-set re-grades and the reads.py gaps; B: the exploratory defect-level judge sampler; C: the sandbox-lite record and `reproduce.sh`) · **Reproducer:** Opus 5.5 from a fresh clone of the stage-1 record commit.

## Executive Summary

Phases 2 and 3 of the measurement: the registered placebo on the Phase 1 rows and the final read at REGISTRATION-14 (then re-read under analysis addendum 16 / REGISTRATION-15 with the label-set sensitivities and the §5 co-reads), one DEC row per read and for the stopping-rule, placebo and positive-control outcomes (DEC-0801 … DEC-0812), the report assembled byte for byte from the artefacts, the exploratory defect-level judge read, the stage-1 record branch and the independent reproduction, the rc.7 release metadata cut after the proof, and the end-to-end goal validation.

`<fill at close: one-paragraph outcome>`

## AC Verification

| AC | Status | Evidence |
|---|---|---|
| FR-9 AC 1: `reports/review-catch-c132/{report.md, reads.md, reads.json, rows.jsonl, power.md, PREREGISTRATION-sha256.txt}` tracked; `reads.md` byte-identical across two runs | `<status>` | commit `cb71ecbf` (+ the re-read commit); two consecutive `final.sh final` runs: final.md `b52e2a71…`, final.json `af68131a…` identical (NOTES 2026-10-23T11:25Z) `<update after re-read>` |
| FR-9 AC 2: every figure in `report.md` reproduced by `reads-c132.py` (no hand-typed numbers; a bats case diffs the report's tables against `reads.md`) | `<status>` | `report.template.md` + `scripts/report-assemble.py` (directives copy rows verbatim); `evals/tests/c132-report.bats` 3/3 |
| FR-9 AC 3: DEC rows for the primary read, each secondary read, the stopping-rule outcome and the placebo/positive-control verdicts | ✓ Met | DEC-0801 (primary), 0802 (stopping rule), 0803 (review-only), 0804 (matched-Fable), 0805 (cost reads), 0806 (pipeline-independent), 0807 (placebo), 0808 (positive control); process rows 0809–0812 |
| FR-10 AC 1: `REPRODUCE.md` lists exact commands, expected hashes and the sample; the reproducer's report shows every hash equal and the rerun grades inside the recorded arm range (or the discrepancy named) | `<status>` | `<fill: REPRODUCE.md, a2a/sprint-271/reproduction/report.md, DEC-0812 rerun outcome>` |
| FR-10 AC 2: `report.md` § Proof links the reproduction report, the positive control, the placebos, the judge result and the dissent records by path | `<status>` | `report.md` § Proof |
| G-7: allowlisted diff vs `main` of `.loa.config.yaml`, skill frontmatter and shipped suite arms empty; rc.7 cut only after FR-9 and FR-10 | `<status>` | `e2e.md` G-7 row; `<fill: CHANGELOG commit>` |
| Review APPROVED, audit APPROVED, Bridgebuilder round triaged, CI green, merged, record branch pushed, cycle archived through the fixed `archive-cycle.sh` | `<status>` | `<fill at ship>` |

## Tasks Completed

| Task | Delivered | Where | Evidence |
|---|---|---|---|
| 3.1 final reads (lead) | placebo on the Phase 1 rows (FAIL calibration 0.100 vs 0.08; §8 fallback) and the final read at REGISTRATION-14, re-taken under REGISTRATION-15 with every registered figure identical; primary +0.0971 [−0.0936, 0.2879], INCONCLUSIVE, a1_full guard tripped; byte-identical across runs | `reports/review-catch-c132/reads.{md,json}`, `reports/ablation-2.0/c132-final/` | DEC-0801 … DEC-0808, DEC-0814; bead bd-759du closed |
| 3.2 report (lead) | `<fill>` | `reports/review-catch-c132/report.md` (+ template, assembler), `analysis.md` §11 | bats 3/3 |
| 3.3a stage-1 record branch | `<fill>` | `record/cycle-132-conclusive-review-catch` | `<sha>` |
| 3.3b reproduction | `<fill>` | `REPRODUCE.md`, `evals/analysis/c132/{record_lite.py,reproduce.sh}`, `a2a/sprint-271/reproduction/report.md` | `<hash table>` |
| 3.4 controls (lead) | placebo FAIL on calibration (bias passes) with the registered fallback stated; positive control PASS (+0.0417, 90 % [−0.0335, 0.1169], 11 pairs, 9 exposed open runs); both embedded in `report.md` from the artefacts | `placebo-phase1.{md,json}`; `reads.md` § Positive control | DEC-0807, DEC-0808; bead bd-04fey closed |
| 3.5 release metadata | `<fill>` | CHANGELOG, `reports/release-notes-2.0.0-rc.7.md`, `.loa-version.json`, README pin | `<commit>` |
| 3.6 ship | `<fill>` | PR, review, audit, Bridgebuilder, merge, stage 2, archive | `<fill>` |
| 3.E2E | `<fill>` | `a2a/sprint-271/e2e.md` | G-1 … G-7 |

## Technical Highlights

- **Analysis addendum 16** (implementer A, `s3-a.patch`, +1,104/−12): `regrade_labels.py` re-grades hard-link copies of every cell (never a recorded dir) under alternate suite roots whose `review_catch.manifest` points at the label set's key and which are re-frozen with `freeze.sh` (every grade `suite_frozen true`), sessions first then `--union`, writing `c132-sensitivity-grades/<label>/…/grade.json` + `INDEX.json` + a seeded `--check` (18 files byte-identical); reads.py gains `review_derived_labels` (§10 item 2; `review/` for pr-19…28, `c131/` for the four older fixtures as the seeder documents) and emits the §5 co-reads in `--final`; stats.py prints `dominated` / `dominated_by_cost` instead of a negative ratio with status `ok`. Results: c131 and v1 read `too_few_prs` (3 PRs; descriptive 0.667 vs 0.583 and 0.583 vs 0.417), the review-derived key reverses the sign (Δ −0.0877, 95 % [−0.3033, 0.1279], 9 PRs, 57 defects) — stated in the report's answer, sensitivities guide, ELI5 and caveat 5.
- **Exploratory defect-level judge read** (implementer B, `s3-b.patch`, +1,093; DEC-0800/0810/0813): `judge_defects.py sample` draws 40 credited (cell, defect) pairs per arm from the Task 2.6 universe with the registered seed and writes one blind packet per credited citation (593; judge-sample.sh's packet format and provenance scan; byte-identical to the dry run); `aggregate` reads the session labels and reports per-arm describing shares with PR-cluster intervals, defect-level corrected recall, the arm difference and per-PR counts. 10 blind Opus 5.5 sessions, 593/593 labels, no taint, USD 7.85.
- **Record and reproduction tooling** (implementer C's `record_lite.py`, completed and verified by the lead; addendum 17 → REGISTRATION-16; DEC-0811): the grader needs `sandbox/review.md`, the sandbox's `grimoires/loa/a2a/sprint-1/*.md`, the sandbox copies of the key defect files and `pr/` (copied to `grading/pr`); the record keeps exactly that lite set per run directory with a sha manifest of every sandbox file, and the reproducer rebuilds `sandbox/` from the tracked fixture plus the lite files. Acceptance: 28/28 reconstructed units re-grade byte-identically across every arm (DEC-0811); the dress rehearsal over all twelve group batches reproduced 433/433 session, 84/84 cell and 56/56 union grades, 140/140 rows and every read byte for byte; seven run directories the runner never graded are listed, not counted. `reproduce.sh` adds the environment checks and the DEC-0812 live rerun; `REPRODUCE.md` carries the commands and expected hashes.
- The grader rewrites `<run-dir>/grading/` beneath whatever run directory it is given, even with `--out` (NOTES 2026-10-23T11:25Z): every re-grade in this sprint runs on hard-link copies; the one lead probe that touched a recorded cell regenerated byte-identical files.

## Testing Summary

- `evals/tests/c132-report.bats`: 3/3 (every numeric table row verbatim from an artefact; reads.md byte-identical to the final read; ELI5 ≤ 300 words).
- `python3 -m pytest evals/analysis/c132/tests -q`: 152 → 176 after A and B → 182 with `test_record_lite.py`.
- `regrade_labels.py --check`: PASS, 18 files byte-identical over 3 seeded cells across the three label sets (`c132-sensitivity-grades/CHECK.json`); the final read itself byte-identical across two runs.
- `record_lite.py build --check`: 28/28 byte-identical (8 cells, 19 sessions, 1 union; `~/.cache/loa/cycle-132/lite-lead-probe2/build.log`); the dress-rehearsal report `~/.cache/loa/cycle-132/repro-rehearsal/report.md`.

## Known Limitations

- **The answer is inconclusive by design and by degradation.** The registered stopping rule did not fire at the final look; the full arm's 25 % guard tripped (11 of 28 cells excluded, eight to oracle exposure of the pinned pipeline on PRs that modify `.claude/`). The report says so plainly; nothing shipped changes (G-7).
- **Key dependence.** The registered review-derived-key sensitivity reverses the primary's sign on nine PRs and fifty-seven defects; the frozen c131 and v1 keys read `too_few_prs`. The report states it in the answer, the sensitivities guide, the ELI5 and caveat 5 rather than choosing a key after the fact.
- **Placebo calibration** fails on these rows as on the Phase 0 rows (0.100 vs 0.08); the registered §8 fallback applies and is stated in one sentence.
- **Judge agreement is low** (κ 0.20) and the registered Horvitz–Thompson correction is biased against arms with many citations per defect; the exploratory defect-level read (DEC-0813) is arm-symmetric and decides nothing.
- **Seven recorded run directories carry no grade** (interrupted by the 2026-10-22 host reboots or superseded before grading); the reproduction lists them and excludes them from every count.
- **The live rerun** reproduces three cells of one PR (DEC-0812, about USD 50), not a batch; it confirms the apparatus, not the statistics.

## Verification Steps

```
python3 -I grimoires/loa/reports/review-catch-c132/scripts/report-assemble.py && ~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/c132-report.bats
bash grimoires/loa/reports/review-catch-c132/scripts/final.sh final   # twice; compare sha256 of c132-final/final.{md,json}
python3 -m pytest evals/analysis/c132/tests -q
```

## Deviations, stated

1. **Two analysis addenda in one sprint** (16 → REGISTRATION-15 for the reads; 17 → REGISTRATION-16 for the reproduction tooling), each registered before the data it governs was read, each at the unchanged pipeline pin. Addendum 16 was registered before implementer C's tooling landed so that the registered re-read and the report were not blocked on tooling that touches no read (DEC-0814). The register script names the file after the addendum; both files were renamed (N−1) to keep the lineage dense, with `registration.py verify` passing on the renamed files.
2. **Implementer C stalled** (no file change or reply for 85 minutes after delivering a complete `record_lite.py`); the lead stopped it and completed `reproduce.sh`, the tests, REPRODUCE.md and addendum 17 itself, after verifying the module (28/28 byte-identical, DEC-0811 acceptance) and fixing one classification (units the record never graded are skipped and listed, not counted as differences).
3. **A lead grader probe touched a recorded run directory's `grading/` subtree** (`c132-g1-a1/a1_full/review-r14-t1`): `ablation-grade.sh` regenerates `grading/gates-combined.md` and `grading/pr` beneath whatever run directory it is given, even with `--out`. Two further runs produced byte-identical files and the pipeline at HEAD is byte-identical to the pin, so the record's content is unchanged (mtimes only); every later re-grade ran on hard-link copies (NOTES 2026-10-23T11:25Z).
4. **NOTES rotation kept the oldest sections** (`notes-guard.sh rotate` retains the first ~70 KB); the Sprint 270/271 tail was restored by hand from the archive and the gotcha recorded.
5. **The exploratory judge read** (DEC-0800, declared pre-data; sized DEC-0810; result DEC-0813) spent USD 7.85 from the contingency; the judge reserve was already exceeded in Sprint 270.
6. **Run interrupted by a host reboot** at the start of the sprint (10:07Z); resumed via `/run-resume` with the state corrected RUNNING → INTERRUPTED → RUNNING; no task had started.
