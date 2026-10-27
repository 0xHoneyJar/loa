# sprint-280 (cycle-136 Sprint 1) — goal validation (Task 1.E2E)

Head at the gates: `be35c3ac6` (review round 2 All good, audit APPROVED); close commit after it. Rows marked *pending* are completed at ship time.

| Goal | Criterion (sprint.md § Success metrics) | Evidence | Status |
|---|---|---|---|
| G-1 | 3 of 3 beads closed with commit and test | bd-akkgq, bd-9tt4b, bd-gyrgq closed at the sprint close with the fix commit, the red commit and the test file in each close reason | met — bd-akkgq, bd-9tt4b, bd-gyrgq closed 2026-10-27 with the fix commit, the red commit and the test file in each close reason (`br show`); follow-ups bd-lkdsx (scaffold hardening ×3 LOW), bd-ae3w2 (coverage pin) |
| G-2 | the scaffold matrix green (legacy WARN, allowlist silent, customised silent, flag fixes one line, negatives byte-identical, yq-less PATH) | `mount-workflow-scaffold.bats` MWS-T13 … T35 green at `90b259222` (41/41 with `cycle-124-live-scaffold.bats`); `red-test-check.sh --red 4e81a0df5 --green 90b259222` VERIFIED; busybox awk cross-check (A § 2) | met |
| G-3 | the shallow-checkout fixtures green with `reviewignore_source: base` and no degrade; the fail-closed cases pinned; the live probe | `paged-fetch-reviewignore.test.ts` (full FR-2 matrix) green at `66c35c9c4`; **live probe met** (`g3-live-probe.sh 1307`, 2026-10-27): `git clone --depth 1 -b feature/cycle-136-bridgebuilder-followups` (shallow: true, head `b2816db`), the built dist's `fetchPRFilesTwoPass` with the real `gh` adapter on PR #1307 → `{reviewignore_source: "base", reviewignore_changed_in_pr: false, degraded: false, degraded_reasons: [], listed: 44, base: 54a8c2824}` and exactly one stderr line `[bridgebuilder] INFO: .reviewignore at base 54a8c2824… read through the contents API (the base commit is not in the clone)`; no model call, nothing posted | met |
| G-4 | `tsc` clean, no intersection casts, `FileContentResult` re-exported, suffix gone, failed-read WARN; FR-5 landed | grep pins in `paged-fetch-coverage.test.ts`; `tsc` clean; 1321/1321 at `81ef8f47d`; FR-5 landed (`63f6d1ae3`, wired `81ef8f47d`) so it counts | met |
| G-5 | every check run green on the final PR head and recorded on the merged head; non-degraded Bridgebuilder verdict with its sha; one implementation PR; record; archive; spend ≤ USD 20 | **one PR (#1307)**; **Bridgebuilder round 1 on `b2816dbc5` (the final head): non-degraded, 2/2 voices, 15 files reviewed, `reviewignore_source: base`, verdict COMMENT, 0 blockers — both MEDIUMs refuted by the shipped code, no round 2** (DEC row BB1); check runs on the final head and the merged head — *pending*; spend: cost-ledger rows price at 0 (subscription routes) | partly met; *pending merge* |

## Local CI mirror (`s-tests.sh all`, started 02:00Z from `9279db32e`, reading the live working tree)

- unit suite: FAIL rc 1 (3404 s) — 7215 ok, 6 not ok: `semver-evidence.bats` 2/3/5 (`git tag v1.0.0 … fatal: no tag message?` — host-local KF-034, recurrence 7; green in CI) and `mount-workflow-scaffold.bats` MWS-T17/T26/T29 — an artefact of landing during the run: the bats file on disk still expected two stderr lines when the round-1 library (`be35c3ac6`, one-line notice) landed mid-suite. At the final head the file pair is consistent: 44/44 (`land.sh a r1 fix`) and `red-test-check.sh --red eb2dac6b9 --green be35c3ac6` VERIFIED. Gotcha recorded: the mirror reads the live tree, so land after it finishes or re-run the touched suites at the final head (done).
- evals PASS (1792 s), scripts PASS, vitest PASS, analysis PASS, gates PASS; pytest rc 1 — the 2 host-local reds (`test_claude_headless_adapter.py` `test_minimal_command`, `test_complete_round_trip`: `CLAUDE_HEADLESS_BIN`, accepted class). Mirror rc 0 overall.

## Ship (appended)

*pending*
