# Loa 2.0.0-rc.8 — The follow-through (release candidate)

**Date:** 2026-10-25 · **Cycle:** cycle-133 "the follow-through" (sprints 272–275) · **Branch:** `feature/cycle-133-follow-through` → `main` · **Previous:** 2.0.0-rc.7 (`CHANGELOG.md` § [2.0.0-rc.7]) (the conclusive review-catch answer) · **Full entries:** `CHANGELOG.md` § [2.0.0-rc.8]

rc.8 is the follow-through on rc.7: every cycle-132 carry-over, every framework defect that cycle exposed, Loa reviewing Loa, one finding contract, external corpus seeding and a tracker that tells the truth. It stays a **pre-release**: the 2.0 line soaks with real users and `2.0.0` is promoted on the rc.1 exit criteria.

## What shipped

**Sprint 272 — the framework's own defects (C-1 … C-5).** Bridgebuilder reads every pull request pinned to one head (paged, SHA-pinned fetch with a coverage record; KF-054) and its enriched consensus is the consensus (writer-role allowlist, verdict table; KF-055); release publication tags the merge commit and proves the tag reachable from `main` before it announces (schema 2 candidates, the lease, the deferral path; KF-034); `record-branch.sh` builds the public record branch as a framework script with the C-4 credential scan; framework ergonomics (NOTES rotation by kind, pre-compact liveness, dec-write length, security-audit scope, ledger validation); CI and test health (analysis pytest in CI, dated quarantine with expiry, ten unit tests un-quarantined).

**Sprint 273 — harness and reproduction hardening (C-6 … C-9).** One session library with fail-closed metering and a descriptor shim that reaches the limit; reproduction attests the worktree and the analysis tree against the registration; grader 1.4.0 with the two benign shapes recorded and a per-arm refusal policy; the egress block (a tinyproxy sidecar with netfilter, a registry-generated allowlist, denials attributed per run) and the restartable batch supervisor (linger precondition, systemd-run or setsid, hang detection, retry classes); the intermediate pipeline version recorded.

**Sprint 274 — the product (C-10 … C-12).** The Task 3.0 spike established the Claude Code 2.1.299 scope facts with a canary per surface item (design a′ confirmed, DEC-0908). The `home-scope` mount mode (the pinned framework under the sandbox HOME, redirected through `LOA_FRAMEWORK_ROOT` and `LOA_PROJECT_ROOT`; the PR's `.claude/` as data at the root; took-effect clauses (e)–(g); a negative control) **landed but is not claimed** — see Deferred. One finding contract: `finding.schema.json` v1 with 47 vectors run by four agreeing validators, the `Failure:` clause grammar and blocking tally in `verdict-derive.sh` (now fail-closed on an unclosed fence), alias normalisation in the dissent, grader 1.5 `--judge-verdicts`, `reads.py --judge-defects` under registration v2. External corpus seeding: `seed-corpus-from-external.sh` with three public dry-runs, the shared `corpus-seed` and `secret-classes` libraries, registration v2 `looks_seen`, the measurement-cycle guidance. The egress gap found by CI (a sandbox could reach the host's bridge gateway, KF-058) is fixed with a guard namespace per blocked sandbox; the dissent under home-scope (KF-061) is fixed; the floor amendment mechanism records the one planned change to a floor file (DEC-0946).

**Sprint 275 — hygiene and ship (C-13, C-14).** The beads sweep tooling (frozen inventory, Explore batch manifests, partition and evidence validation, the seeded 10 % re-verification, an append-only apply log) and the sweep itself: 329 open beads frozen, nine read-only Explore batches, a validated complete partition, a seeded 10 % second pass (17 of 18 confirmed; the one disagreement sent its batch to a full re-verification), then 165 closed as implemented and 9 as obsolete with evidence, 147 kept under `backlog-2026-10` with a review-by date, 7 pulled into the sprint, 1 left open as blocked — 329 → 155 open, every mutation in `applied.jsonl`. This release's metadata, record branch and publication through the fixed path.

## Deferred

- **FR-10 — Loa reviews Loa without reading its own installed files.** Both smoke launches at the recorded pins failed clause (f): a Loa reviewer consults its installed Loa in HOME as the reference for a Loa PR (it compared the HOME copy with `pr/base`, read it, and the auditor executed the installed version of a changed script). The mount isolates the workspace root; it cannot hide the install from the reviewer that runs it, and clause (f) detects this reliably (two of two). Recorded as KF-060 (recurrence 2) and DEC-0950; the path forward is external fixtures (C-12), where the framework is not the subject, or a base-version framework — the operator's decision (bead bd-ivmtk). Home-scope stays available to measure exposure, never as an isolation claim. Spend USD 20.88 of the USD 40 smoke share.
- **Task 3.6 — the session-library drift test** stays (the deletion was conditional on a green smoke; bead bd-nzblj).
- **Should Haves carried as beads:** the dissent wire still asks for `failure_mode` (bd-ci4g9, removal in 2.1.0); the a7 arm under home-scope and a live dissent check (bd-yv0d4); egress and clause (f) evidence lines (bd-yt1k1); grader 1.5 judge-row hardening (bd-afz2p); floor-amendment strengthening (bd-znx6q); seeder defense in depth and PEM redaction line counts (bd-868s1); sandbox `--cap-drop ALL` (bd-vlgk1); grader contamination shapes 3–6 (bd-mopz7).

## Revert paths

Every CHANGELOG entry in the rc.8 section names its revert path; in short: each sprint's hunks revert independently (C-1/C-2 → the previous Bridgebuilder dist; C-3 → the schema-1 publish; C-6 → inline metering copies; C-9 → the launchers rejoin the network directly and KF-058 reopens; C-10 → pinned-root is the only mode; C-11 → the templates lose the clause and `verdict-derive.sh` stops scanning bullets; C-12 → the seeders regain their inline Python and classes; the floor amendment → delete the row and re-pin `FLOOR_SHA256`). The sweep's closures are reversible one by one with `br reopen` from `applied.jsonl`.

## Known failures recorded this cycle

KF-056 (new-cycle DEC rows), KF-057 (npx bats absent in CI → `$BATS_ROOT/bin/bats`), KF-058 (fixed: host gateway reachable from an `--internal` network), KF-059 (shallow CI checkout vs history-resolving tests), KF-060 (open: home-scope exposes review-time files a PR changes — structural), KF-061 (fixed: dissent under home-scope). KF-037 recurrence 12 (companion claude-headless unavailable on a host dissent run).

## Pins

- Measurement pin: `7d2119477` (tree `e98fcee86b74`; first pin `32a8d79cf`), `loa-ablation:259` (Claude Code 2.1.299, `sha256:61e88d02…`), `loa-egress-proxy:259` with the guard label (`sha256:95c4c379…`). `evals/harness/README.md` § Pipeline version.
- Decisions: DEC-0819 … DEC-0952 (plus the sweep and release rows that follow). Known failures: `grimoires/loa/known-failures.md`.

## Exit criteria for 2.0.0

Unchanged from the rc.1 notes: soak with real users, no open HIGH in the audit ledger, the cycle-132 record reproducible, and the review-catch answer standing.
