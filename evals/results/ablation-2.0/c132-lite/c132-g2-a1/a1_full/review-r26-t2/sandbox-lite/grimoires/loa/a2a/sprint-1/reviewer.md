# Implementation Report: sprint-1

# feat(cycle-130): sprint-262 — ablation-row.sh 1.2 carries defects_missed (bd-yz1rd) and regressions_final_green (bd-m0hw7)

Sprint 262 (global), 5 file(s) in scope.

Commits in this change:

- feat(cycle-130): sprint-262 — ablation-row.sh 1.2 carries defects_missed (bd-yz1rd) and regressions_final_green (bd-m0hw7)
- feat(cycle-130): sprint-262 — ablation-report.py 1.1.0: suite_version partition, not-testable and not-yet-decidable states, the degradation guard on the H1/A4 lines, the degenerate single-task pair (…
- chore(cycle-130): sprint-261 — run resumed (DEC-0593 option (a)); the 24 priority-v2-p1 rows re-rowed under row writer 1.2 (defects_missed; every other key field identical); KF-048 attempt row; pre-r…
- chore(cycle-130): sprint-261 — DEC-0594 (KF-048 fix design), DEC-0595 (priority-v2-p1b pre-registration); batch priority-v2-p1b launched 2026-10-18T06:17:44Z (a1_full × review-01…03 × 3, --max-usd 38…
- fix(cycle-130): sprint-261 — KF-048 recurrence 2: the per-run codex auth.json keeps a placeholder refresh_token (the codex CLI treats a missing key as logged out and sends no bearer at all)
- chore(cycle-130): sprint-261 — KF-048 recurrence 2 with the attempt rows; DEC-0596 (p1b stopped on the pre-registered condition, corrected credential copy, resumed with --max-usd 376)
- fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283)
- feat(cycle-130): sprint-262 — ablation-report.py 1.2.0 presentation items: sensitivity H1/A4 lines, batch record, per-arm precision and cost per true defect, the budget-matched baseline (all informat…
- chore(cycle-130): sprint-261 — batch priority-v2-p1b complete (9 rows: a1_full × review-01…03 × 3; all completed, none degraded, both dissent voices on every REVIEW and AUDIT envelope; USD 104.26; no…
- chore(cycle-130): sprint-261 — DEC-0597: suite v2 H1 established on twelve valid a1_full cells (+0.263 [+0.158, +0.386]); A4 not testable, no pruning; the cycle continues
- docs(cycle-130): sprint-262 — suite README version table: round-1 v2 (7bc1b538…, 215 files) retired with no rows; the frozen v2 (bde0c22e, ddd200b3…, 282 files, grader 1.2.11) with its task ids and t…
- fix(cycle-130): sprint-261 review r1 — grader 1.2.12 narrows the 1.2.11 basename-collision removal (HIGH-1, MEDIUM-1)
- docs(cycle-130): sprint-262 — suite README task-id line lists the frozen v2 ids (round-1 ids swapped out before any batch row, DEC-0584)
- fix(cycle-130): sprint-261 review r1 — codex pre-flight accepts API-key auth, counts only the trials --resume will launch, and takes LOA_ABLATION_CODEX_HORIZON_S (MEDIUM-2, LOW-1)
- chore(cycle-130): sprint-261 — DEC-0598 (grader 1.2.12 narrowed collision removal)
- fix(cycle-130): sprint-261 review r2 — codex pre-flight horizon bounded below by the longest remaining trial, the STATUS/MANIFEST writers take the pre-flight record by --argjson (no scratch-file depe…
- fix(cycle-130): sprint-261 review r2 — grader 1.2.13: collisions by pytest import name, package-less helper shadowing, fixture python_files (MEDIUM-1, LOW-2, LOW-3)
- chore(cycle-130): sprint-261 — DEC-0599 (grader 1.2.13); sprint-262 — the report's cuts file (A2, A3, A5, A6, A7 Not run (cut) with the batch-plan figures)
- docs(cycle-130): sprint-262 — report.md/report.json generated (report 1.2.0, cuts for A2/A3/A5/A6/A7; suite v2 H1 established, A4 not testable, no pruning; v1 in its own section); CHANGELOG Sprint 26…
- docs(cycle-130): sprint-262 — suite README: the regression-check recipe at the next model bump (run-ablation.sh --source-commit, the hard gate, the report) (AC-5.6, PRD G-6)
- docs(cycle-130): sprint-262 — release-notes-2.0.0-rc.6.md drafted (findings stated plainly; the release body is filled after the candidate publishes)
- fix(cycle-130): sprint-261 audit — a long-lived OPENAI_API_KEY never reaches the agent-writable per-run HOME unless the operator accepts it (LOA_EVAL_CODEX_APIKEY_COPY=1); the credential exposure of…
- chore(cycle-130): sprint-261 COMPLETE — review r3 and audit APPROVED; ledger 261 completed / 262 in_progress; CHANGELOG audit-fix line
- chore(cycle-130): sprint-262 — DEC-0600 (no pruning made)
