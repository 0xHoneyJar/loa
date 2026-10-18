APPROVED - LET'S FUCKING GO

# Sprint 262 security audit — round 1 (cycle-130 Sprint 5) — APPROVED

**Auditor:** Paranoid Security Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T12:29:50Z)
**Scope:** the Sprint 262 diff `4434d450..dad13df1` (report 1.0 → 1.2.2, row writer 1.2, their bats and fixtures, CHANGELOG, the suite README, report.md, cuts.json, the rc.6 notes; 2,941 lines) plus the audit fix `56ce0b8f` (row writer 1.3, report 1.2.3); the review verdict `engineer-feedback.md` (round 3 APPROVED; rounds 1–2 archived).
**Dissent:** `adversarial-audit.json` (run 3 of 3, `--type audit`): two voices (`codex-headless`, `claude-headless`; 2 of 2), status `clean`, four findings (1 MEDIUM, 3 LOW) — all four accepted and fixed in `56ce0b8f` (one sub-claim refuted below, with evidence).
**Local checks:** `ablation-report.bats` 47/47 and `ablation-row.bats` 37/37 on `56ce0b8f`; `evals/tests/` 438/438 on `dad13df1` and 447 cases on `56ce0b8f` (the run completes at the close); `ablation-row.sh --validate` 165 tracked rows valid under 1.3; the shipped report regenerated under 1.2.3 is identical to the 1.2.2 output on every key but the generator string (every real id list already satisfies the new rules; every real cost is finite; every arm and task id is inside the grammar).

## Findings

### MEDIUM-1 (DISS-C-001, input validation) — `defects_missed` ids were unconstrained: FIXED
Row writer 1.3 shares one jq rule set between the writer and `--validate` (prepended from a bash variable; no `eval`, no `source`): on a review-catch row a non-null list must satisfy the `^d[1-9][0-9]*$` grammar, uniqueness, at most `defects_seeded` ids, ids within `d1 … d<defects_seeded>`, and `defects_seeded − |ids| == defects_caught` when both are numbers; `--validate` names the violated rule and the line, and the writer turns an inconsistent grade list into `null` with nothing else changed (cases 34–37). Report 1.2.3's `defect_vector()` returns the row's rate (never the id vector) on an inconsistent list (AR-43). The pre-registered H1 vector on the shipped rows is unchanged (every real list passes).

### LOW-1 (DISS-C-002, info-disclosure) — exception text copied verbatim into the published report: FIXED
`stage_note()` writes `str(x)` to stderr once and renders only the class and a fixed stage phrase naming the batch (`Not rendered (ValueError while reading the batch record of ver-v2)`); AR-41 pins the sanitized text, AR-47 proves the full text appears only on stderr.

### LOW-2 (DISS-C-003, input validation) — unguarded numeric conversions: FIXED
`is_num()` / `num_of()` / `usd_of()` guard every cost and wall-clock read (a finite non-bool number, else 0 with one stderr note per row and key); the JSON twin is serialised with `allow_nan=False` and a non-finite value exits 2 naming the key before either file is written (AR-44, AR-45).

### LOW-3 (DISS-C-004, input validation) — arm and task grammar before filesystem access: FIXED (one sub-claim refuted)
`ARM_GRAMMAR` and `TASK_GRAMMAR` are checked before any path is built; a failing row counts `n/a` with the note "N row(s) with an arm or task_id outside the grammar"; `contained()` resolves the candidate with `realpath`, refuses a symlinked component and anything outside the batch's manifest directory (AR-46: a canary outside the tree is never read; a symlinked `meta/` refused). **Refuted sub-claim:** `GRADE_DIR` was already matched with `fullmatch` in `run_dir_of()` (its only use) since 1.2.1, so `rc-01-t1-r2.bak` never attributed; the finding's "unanchored" reading was stale — recorded, no change needed there.

## Residuals (bead bd-… filed at the close: see § Beads of `reviewer.md`)
`batches[].status_file` and `provenance.manifests[].manifest` carry filesystem paths (pre-existing, the lead's own paths, absolute only when `--manifests` is absolute); a NaN primary passes `_classify`'s `isinstance` check and fails loudly only with `--json`. Neither affects the shipped report.

## Security posture of the sprint diff (verified)
Python stdlib only; no `eval`; symlinks never followed in the manifests tree; nothing written but `--out` and `--json`; no secret, path or file content reaches the published report through an exception; the row writer's schema gate now rejects a row whose per-defect ids contradict its counts, so the pre-registered defect-level interval cannot be built from inconsistent data; the docs (README, CHANGELOG, release notes) name no credential or private path.

## Verdict

APPROVED — Sprint 262 is complete. Residuals carried as the follow-up bead above and bd-ocovl, bd-85o9e, bd-lfrkn, bd-w0ofw from Sprint 261.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"sprint_id":"sprint-262","ts":"2026-10-18T12:29:50Z"} -->
