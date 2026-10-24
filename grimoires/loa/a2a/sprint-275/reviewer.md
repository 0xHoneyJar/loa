# Sprint 275 (cycle-133 Sprint 4) — Implementation Report

**Sprint:** Sprint 4 (final) — hygiene and ship (global 275) · `grimoires/loa/sprint.md` § Sprint 4
**Run:** `run-20261024-ca505ad4` (`/run sprint-plan`), branch `feature/cycle-133-follow-through`, base `f63b4e92a` (the Sprint 274 head) → Sprint 4 head ``f898c739e` (review and audit precede the ship; the merge, record branch, tag and archive commits follow Task 4.5)`
**Who:** the lead (Fable 5.1) for every task; nine read-only Explore batch agents and one second-pass verifier (Opus 5.5) for the sweep, one re-sweep agent for the batch the sample sent back. No model calls by the agents beyond themselves; spend USD 0 in this sprint (cycle total USD 20.88 of the smoke share).

## Status

Tasks 4.1–4.3 landed on the cycle branch: C-13 tooling `7e0123b9a` (+ `14bad657c` integrity manifest, `f48de024e` per-row apply and blocked-by handling, `3deb39cd5` re-run validity), the sweep applied to the tracker (open beads 329 → 155; `a2a/sprint-275/sweep/REPORT.md`), the sweep outcome and the triage DEC rows `c3d873fcf` (DEC-0954 … 0956), release metadata `f898c739e` (CHANGELOG `## [2.0.0-rc.8]`, release notes, version stamps, README). Sprint 273's COMPLETED marker was written in this sprint on the first green Shell Tests run (DEC-0953). Task 4.4: review round 1 CHANGES_REQUIRED (1 high, 2 medium, 4 low) → fixes `9fb44fe10` → round 2 APPROVED; audit (its own dissent envelope, 3 medium + 6 low) → fixes `37547f3a4` (SW-1 … 20) → APPROVED; Task 4.5 (ship) follows both approvals and records G-2, G-3 and FR-14 afterwards.

## AC Verification

| AC | Status | Evidence |
|---|---|---|
| PRD FR-13 AC 1–2 (the manifests form a complete partition of the frozen inventory; categories sum; opened-during-cycle listed; the sample is verified before any closure applies and a disagreement re-sweeps the batch) | ✓ Met | `.claude/scripts/beads/sweep-apply.sh:1` `--validate` on the nine manifests: VALID, 329 rows form a complete partition of `inventory.jsonl` (sha256 `667765512a5c…`); the five-category table below sums to 329 with the opened-during-cycle column from the frozen `created` dates (38 beads created on or after 2026-10-23); `.claude/scripts/beads/sweep-sample.sh:1` drew 18 of 180 closures (seed 20261023) and the second pass disagreed on one (bd-a4td, batch 03), so batch 03 was re-swept and every closure of that batch re-verified before `--apply` ran (`a2a/sprint-275/sweep/{sample.jsonl,sample-verify.first.jsonl,manifest-03.first-pass.jsonl,manifests/manifest-03.jsonl}`); `tests/unit/sweep-tools.bats:1` SW-1 … SW-9 |
| PRD FR-14 AC 1–2 (rc.8 pre-release with notes and `main` contains the tag; record branch by `record-branch.sh`; archive directory with the merged CHANGELOG section and README) | ✓ Met (rc.8 pre-release with notes; `main` contains the tag; record branch stage 1 built by record-branch.sh; archive directory in the archive PR — e2e.md § G-3) | prepared: `CHANGELOG.md:12` (`## [2.0.0-rc.8] — 2026-10-25 — The follow-through (release candidate)`), `grimoires/loa/reports/release-notes-2.0.0-rc.8.md:1`, `.loa-version.json:2` (`2.0.0-rc.8`), `.claude/loa/CLAUDE.loa.md:1` header, `README.md:9` version and `README.md:76` install pin; the tag on `main`, the record branch (`record-branch.sh --cycle 133 --stage "stage 1"`) and the archive directory are produced by Task 4.5 after this review and the audit approve |
| PRD G-2 (the cycle's own PR reviewed by the Bridgebuilder built on the cycle branch with no `degraded_reason`, summary verdict equal to the consensus block's; if the PR's shape degrades the review, the PR is split per the FR-12 guidance before G-2 is read) | ✗ Not met (G-2: two rounds, both degraded — refusal, then cap-bound coverage and the writer guard; see e2e.md § G-2, the PR triage comment, bead bd-oik13) | the Bridgebuilder round(s) on PR #1292 run with the skill built from the cycle branch (C-1/C-2 landed in Sprint 272: `.claude/skills/bridgebuilder-review/dist/.build-manifest.json:1`); the verdict JSON's `degraded_reason` and summary-vs-consensus equality are read after the round and recorded in `a2a/sprint-275/e2e.md` |
| Review APPROVED, audit APPROVED before the admin merge (Task 4.4; the sweep report, the release metadata and any Bridgebuilder-triggered fix are the sprint's code), ≤ 3 dissent runs | ✓ Met | `grimoires/loa/a2a/sprint-275/engineer-feedback.md:1` (round 2 APPROVED; round 1 in `engineer-feedback-r1.md`), `grimoires/loa/a2a/sprint-275/auditor-sprint-feedback.md:1` (APPROVED); dissent runs 2 of 3 (`adversarial-review.json`, `adversarial-audit.json`); the merge has not happened yet (Task 4.5) |

### Seams under test (sprint.md)

| Seam | Result |
|---|---|
| The 10 % re-verification sample | 18 of 180 closures drawn with seed 20261023; 17 confirmed, 1 disagreement (bd-a4td: the evidence commit implements part of the ask; the remainder makes it kept) → batch 03 re-swept, a fresh Explore re-verified every closure of batch 03 (17 rows): bd-a4td → kept, the two lead-promoted sprint epics (open children) → kept, 14 confirmed (`a2a/sprint-275/sweep/manifest-03.first-pass.jsonl` vs `manifests/manifest-03.jsonl`) |
| The cycle PR through the cycle-branch Bridgebuilder | two rounds run from the cycle-branch dist; verdict UNKNOWN/degraded; 17 findings triaged → 9 beads (e2e.md § G-2) |
| `git branch --contains v2.0.0-rc.8` | pending (Task 4.5) |

## Tasks Completed

| Task | Delivered | Where | Evidence |
|---|---|---|---|
| 4.1 Sweep inventory and batches (lead + Explore) | C-13 tooling (`sweep-inventory.sh`, `sweep-apply.sh`, `sweep-sample.sh`; SW-1 … 9); 329 open beads frozen (Tier 1: 26/26 already closed — bd-kddde closed with the scoped grader 1.4 evidence and its remainder split to bd-mopz7); nine batches of ≤ 40; nine read-only Explore agents returned manifests; `--validate` VALID | `7e0123b9a`, `14bad657c`; `a2a/sprint-275/sweep/{inventory.jsonl,inventory.sha256,INVENTORY.md,batches/,manifests/}` | validator output in `a2a/sprint-275/sweep/VALIDATE.txt` |
| 4.2 Sample, apply, report (lead) | lead triage before the draw (one low-confidence closure demoted; four completed sprint epics/tasks promoted to closed with ledger evidence; Sprint 275's own seven beads marked pulled-in so they are not labelled backlog); seeded 10 % sample re-verified by a second Explore; one disagreement → batch 03 re-swept and fully re-verified; `--apply --sprint 275 --review-by 2027-01-31`: 165 closed as implemented, 9 as obsolete, 147 kept (`backlog-2026-10`, review-by 2027-01-31), 7 pulled-in (`sprint:275`), 1 skipped-blocked (bd-16wg, blocked by the kept bd-de0b); open 329 → 155; three apply runs (the first two surfaced the tool fixes); `applied.jsonl` append-only | `a2a/sprint-275/sweep/{sample.jsonl,sample-verify.first.jsonl,applied.jsonl,REPORT.md}` | the five-category table below |
| 4.3 Release metadata (lead) | CHANGELOG `[Unreleased]` → `## [2.0.0-rc.8] — 2026-10-25 — The follow-through (release candidate)` with the cycle intro and a fresh `[Unreleased]`; `release-notes-2.0.0-rc.8.md` (what shipped per sprint, the deferred FR-10 and Task 3.6, Should Haves as beads, revert paths, KF-056 … KF-061, pins, exit criteria); `update-loa-bump-version.sh --target 2.0.0-rc.8` under the zone marker (header hash preserved); checksums.json + REPO-MAP regenerated; README version line, version and release badges, install `--tag v2.0.0-rc.8`, the rc.8 "What's new" block | `f898c739e`; `CHANGELOG.md`, `grimoires/loa/reports/release-notes-2.0.0-rc.8.md`, `.loa-version.json`, `.claude/loa/CLAUDE.loa.md`, `README.md` | `tools/check-prompt-budget.sh` (CLAUDE.loa.md 9189 B of 9445), gates PASS, `gen-checksums --check` OK |
| 4.4 Sprint close (lead) | this report; DEC rows DEC-0953 (the 273/274 CI overlap), DEC-0954 … DEC-0956 (sweep triage); the ship rows follow Task 4.5; beads closed; spend line | `a2a/sprint-275/` | review and audit files |
| 4.5 Ship (lead) | done — PR #1292 ready with the sprint reports as body; Bridgebuilder rounds 1–2 from the cycle-branch dist (G-2 not met, triaged → nine beads); required checks green on 37547f3a4; admin merge 3e5b9d36; record stage 1 603732b9 (ICE push); rc.8 published through C-3 (tag on the merge, release 422847479, ledger ff 928b3b9e); archive PR follows |
| 4.E2E | G-1 (26/26 Tier 1 closed with commit and test), G-7 (the table and the sample), G-3 and G-2 (after the ship) | `a2a/sprint-275/e2e.md` | see e2e.md |

## The sweep — five-category table

| category | beads | of which opened during cycle-133 | applied | action |
|---|---|---|---|---|
| closed-implemented | 166 | 8 | 165 | `br close --reason "implemented: <evidence>"` |
| closed-obsolete | 9 | 1 | 9 | `br close --reason "obsolete: <evidence>"` |
| kept | 147 | 22 | 147 | label `backlog-2026-10` + status comment, review-by 2027-01-31 |
| pulled-in | 7 | 7 | 7 | label `sprint:275` + comment (the sprint's own beads) |
| **total (the frozen inventory)** | **329** | **38** | 328 | |

skipped-blocked: bd-16wg (blocked by a bead this sweep keeps; left open, no label)


## Judgment calls → DEC rows

- D-2.7 → DEC-0953: Sprint 273 COMPLETED on the first green Shell Tests run (0d51dcf45), the overlap with Sprint 274 commits recorded.
- D-4.2a → DEC-0954: the active sprint's own beads are pulled-in, not backlog; a low-confidence closure demoted before the draw.
- D-4.2b → DEC-0955: the sample disagreement sent batch 03 to a full re-verification (no re-draw); the re-sweep's three demotions accepted (two sprint epics keep open follow-ups).
- D-4.2c → DEC-0956: a bead br refuses as blocked is force-closed only when every blocker closes in the same sweep; blocked by a kept bead → skipped-blocked, left open; epics with open children → kept.
- Lead, no DEC (mechanical): the sweep tooling's two live-run fixes (per-row robustness, re-run validity) with SW-7/SW-10; `checksums.json` regenerated after the sweep scripts were tracked (CI integrity gate on cbd1e4912).

## Spend

| Share | Spent | Of |
|---|---|---|
| smoke (incl. spike) | USD 20.88 | 40 |
| Bridgebuilder rounds | pending (Task 4.5) | 20 |
| dissent runs | USD 0 (subscription routes) | 40 |
