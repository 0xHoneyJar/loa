# Sprint 265 (cycle-131 Sprint 3) — implementation report for the reviewer

**Lead:** Fable 5.1 (main session; a documents-and-reads sprint, no implementer) · **Commits:** `ba3937ca` (reads, addendum, CHANGELOG, rows, ledger) on `feature/cycle-131-honest-measurement`; pin of the measured rows `798d88cf` · **Date:** 2026-10-20

## Deliverables

| Deliverable (sprint.md § Sprint 3) | Where | Status |
|---|---|---|
| `analysis.md` §10 "cycle-131 addendum" (ELI5 first; re-grade table with three rules; oracle A/B; control reading; two prices with the rules quoted; adjudication; spend); `report.md` untouched | `grimoires/loa/reports/ablation-2.0/analysis.md` §10.0–10.8; `report.md` unchanged (`git diff origin/main -- grimoires/loa/reports/ablation-2.0/report.md` empty) | ✓ |
| DEC rows per read; the seven `cycle-131-candidate` beads closed or re-labelled; KF attempts rows | DEC-0651 (R1), DEC-0654 (R5), DEC-0652 (R3), DEC-0653 (R4); beads bd-mlg9s, bd-5rmmf, bd-zv4og, bd-9lfns, bd-1ohfe closed with outcomes, bd-pacqf and bd-ba54i labelled `cycle-131-outcome-inconclusive` with notes; KF-049 attempt row (closed for the mounted arm), KF-046 recurrence 10 + attempt, KF-050/KF-051 new; KF-041 recurrences recorded at planning | ✓ |
| CHANGELOG `[Unreleased]` and release notes for the harness changes and the `budget_scale` knob | `CHANGELOG.md` `[Unreleased]` (Sprints 263, 264/265 entries; Known failures) | ✓ |
| PR merged on green CI; `record/cycle-131-honest-measurement` built and pushed; `evals/tests/` and `tests/unit/` green at the close | Task 3.3 — after this sprint's gates | pending |

## AC Verification (sprint.md § Sprint 3, verbatim)

### "Each read's outcome text matches its pre-registration verbatim; the decision statistic is the one Task 1.10's DEC named"

| Read | Pre-registered branches (DEC-0648) | Outcome written (DEC) | Match |
|---|---|---|---|
| R1 | inflated / no measurable inflation / investigate (+ insufficient when cells < 4) | "insufficient" (as written) / "investigate" (trial level) — DEC-0651 | ✓ verbatim |
| R5 | the model explains the lift / the gates earn their cost / between (both intervals reported) | "between (both intervals reported)" — DEC-0654 | ✓ verbatim |
| R3 | propose audit-gate opt-in / keep / inconclusive (+ insufficient) | "insufficient" / "inconclusive" — DEC-0652 | ✓ verbatim |
| R4 | propose dissent opt-in / keep / investigate / inconclusive (+ insufficient) | "insufficient" — DEC-0653 | ✓ verbatim |
| statistic | `recall_pm3` (DEC-0638) | `defect_catch_rate_pm3` on every read | ✓ |

### "PRD FR-7 AC 1–2 (validators pass; CHANGELOG lists FR-1 … FR-5 — the lead writes each sprint's entries at integration; no shipped default changed — the diff against `main` shows only the optional knob with its `fixed` default and the additive anchor fields)"

| Check | Evidence |
|---|---|
| validators | `validate-artifact.sh --type prd|sdd|sprint|decisions` pass (sprint.md one pre-existing WARN on a `kind: judgment` wording at line 77) |
| CHANGELOG lists FR-1 … FR-5 | `[Unreleased]`: closed mount (FR-1), grader 1.3.0 + row/report (FR-2/FR-3), `--allow-partial` (FR-3), dissent anchors + `budget_scale` (FR-4), multi-site labels (FR-2), four arms + suite root (FR-5), the measurement (FR-6/FR-7) |
| no shipped default changed | `a2a/sprint-3/e2e.md` G-6: `.loa.config.yaml`, every `SKILL.md`, `settings.json` unchanged vs `origin/main`; suite `priority` unchanged; `.claude/` changes limited to the authorized files; example config gains `budget_scale: fixed`, `budget_cents_max: 600` |

### "Task 3.E2E documents evidence for G-1 … G-6"

`grimoires/loa/a2a/sprint-3/e2e.md` — written before the PR; G-1 ✓ (24/24 closed rows unexposed; the control arm exposed 7/15/3), G-2 ✓ (36/36 regression; adjudication κ 1.0, 2/7 → `recall_pm3`), G-3 ✓ (anchor share ≥ 0.90 per gate, both voices on every dissent-enabled gate), G-4 ✓ (6 bare-Fable rows; R5 named), G-5 ✓ (refs dated before the rows; R3/R4 named branches), G-6 ✓.

## Honest notes for the reviewer

1. Two of four main reads are "insufficient" because the pre-registration's `min_valid_cells 4` cannot be met by its own 3-trial single-PR cells (DEC-0650); the trial-level sensitivity is reported beside, and the addendum says which branch each read reaches under each threshold without choosing.
2. R4 is insufficient under every reading: the third no-dissent cell was contaminated by a scratch-directory reproduction outside the path shapes S3 declared; S3 was not widened after the fact.
3. The reads script (`a2a/sprint-3/reads-c131.py`) is lead-written analysis code under a2a (record branch), not harness code; its mechanics were checked on the Sprint 263 smoke rows and on the batch rows as they landed (zero-row and partial-row runs), and its validity filters follow DEC-0648 and the S3 declaration literally.
