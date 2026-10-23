All good

Sprint 270 (cycle-132 Sprint 2, Phase 1 batches) is approved for audit.

**Reviewer:** lead (Opus 5.5), with one dissent run on the code (`adversarial-review.json`, run 2; gpt-5.5-pro primary plus the claude-headless companion; status clean, 6 advisory). **Scope:** `c3d21fef..e36da85d` and the Phase 1 artefacts under `evals/results/ablation-2.0/c132-g*`, `grimoires/loa/reports/ablation-2.0/c132-looks/`, `reports/review-catch-c132/`, and `a2a/sprint-270/`.

## What was checked against the acceptance criteria

- **FR-8.** The suite root, the frozen manifest and the self-check are in place. The smoke evidence precedes the first batch row in NOTES. All 140 Phase 1 rows sit at the pin: the make-inputs validator checks `source_commit` on every row in every look. Three looks were taken, each with a timestamp, a DEC row and its outputs committed. The final look reads INCONCLUSIVE by the registered table (z_yes 1.15 against 2.26 at t = 1). I re-derived the reviewer report's per-arm outcome counts from the rows: a1_full 17/28, matched bare 25/28, Fable bare 28/28, review-only 20/28, open mount 23/28. The first draft of that table had three counts wrong; they were corrected before review.
- **FR-4.** The sampler is deterministic, and JS-15 pins sampling identity against a baseline. `result.md` carries n per stratum, agreement, κ with its interval, the confusion table and the corrected figures per arm. The grader stays primary: no look or decision reads the judge.
- **Registration lineage.** Each batch carries the registration that was binding at its launch, and the reads accept the declared `supersedes` chain, which resolves on disk from REGISTRATION-13 back to REGISTRATION.json. Addenda 10–14 keep the pipeline pin. `register-addendum-analysis.sh` refuses unless `.claude/`, the harness (minus the two judge tools), the suites, the fixtures and the suite tasks are byte-identical to the pin; I re-ran that check by hand, and only the two judge tools differ.
- **Contamination.** The hand-reads in `batch-scans.md` cover all 48 invalid units with a mechanism class each. The nine upstream-repository reaches are all bare-agent behaviour and stay excluded in every sensitivity except "all classes re-included".

## Dissent triage (run 2)

All six findings are advisory, and none changes a read of this cycle. I verified the two that could have: every metered row carries a run id, so DISS-C-006's double count cannot occur, and no registration in the chain is unresolved, so DISS-C-001's whitelist path is unused. DISS-C-002, -003 and -004 are hardening. DISS-C-005 is an artefact of the focused diff, which left out `judge-sample.sh`; `judge-sample.bats` passes 24/24 at head. All of them go to bead bd-um8ol.

Run 1 of the dissent left no envelope. Both of its voices ran (cost ledger rows at 09:08:20Z and 09:18:30Z), but the script's main flow exited silently, and its exit-trap reaper reported `wait_for: No record of process 31343`. It is recorded with `--record-fallback failed`, and the record is kept as `adversarial-review-r1-failed.json`. This sprint has used 2 of its 3 dissent runs; the audit gets the third.

## Non-blocking observations (recorded, no change required here)

- The phase drivers lived only in `~/.cache` until e36da85d copied them to `reports/review-catch-c132/scripts/`. Sprint 271's REPRODUCE.md must run from those copies.
- The registered judge estimator removes 1/m of a defect's credit per rejected citation, which makes its per-arm corrected recall incomparable across arms (mean m 4.30 for a1_full against 2.51 for matched bare). The report must state this beside the table. DEC-0800 declares the exploratory defect-level read for Sprint 271.
- Six grader false positives (sed and awk addresses read as paths) and five other benign-by-construction contamination shapes are tracked for grader 1.4 (bd-kddde). None removed a primary cell.
- The session lead model changed from Fable 5.1 to Opus 5.5 on 2026-10-23. Arm and judge models are pinned and unaffected.
- KF-051 (refusal fallback, rec 4) and KF-052 (dead detached runner, rec 3) are now structural, with beads bd-r9abp and bd-yvjew. KF-053 is new.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":6},"excluded":0,"sprint_id":"sprint-270","ts":"2026-10-23T09:41:20Z"} -->
