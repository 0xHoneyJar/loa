# Sprint Plan: Performance follow-ups (cycle-137)

**Version:** 1.1
**Date:** 2026-10-28
**Revision:** 1.1 integrates the Flatline sprint review (7 blockers, 40 medium items — dispositions in the Appendix) and PRD 1.1 / SDD 1.1: decision-row classes, one terminal rule for blocking findings, SHA-bound approvals, the ship as a post-audit section, cache trust boundary, verify-chains result protocol, HALT checkpoints, time budget.
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.1, FR-1 … FR-8, G-1 … G-6, § Release predicate R-1 … R-8)
**SDD Reference:** `grimoires/loa/sdd.md` (1.1, C-1 … C-8, § 5.1 … § 5.8, D-1.1, D-2.1 … D-8.1)
**Ledger:** cycle `cycle-137-performance-followups`, sprint globals 281 (local sprint-1) and 282 (local sprint-2)
**Execution:** Sprint 1 is already implemented (the 20 loop commits): the lead writes `a2a/sprint-281/reviewer.md`, then runs `/review-sprint sprint-1` and `/audit-sprint sprint-1` directly (no `/run`, nothing to implement). Sprint 2 runs under `/run sprint-2 --local` (implement → review → audit with the circuit breaker; no push and no PR from run mode); the PR, Bridgebuilder rounds, merge, record, archive and the rc.9 publish are the lead's ship tasks afterwards. Implementers are Opus 5.5 (`global.anthropic.claude-opus-5-5`) in linked worktrees returning `git diff --cached` patches (test patch first, then fix); the lead lands, reviews, audits and ships. CHANGELOG lines are returned as text in the reports and inserted by the lead. Bounded-loop exits (unattended): a patch returned for allowlist or red-test violations more than twice → the lead implements or defers the task with a bead and a DEC row (class S); a dissent voice unreachable after ≤ 3 runs → the lead's own review and the audit still run, the dissent gap is recorded (class S); a `/run sprint-2 --local` circuit-breaker trip → state HALTED, the lead reads the trip reason, fixes forward under the same gates and `/run-resume`s, at most twice, then a real HALT; Bridgebuilder unreachable on `codex-headless` → one retry after ten minutes, then `BRIDGEBUILDER_MODEL=claude-headless`, then degraded (class S only when no blocking finding is open); Bridgebuilder round 2 ends with a blocking finding still open → fix red-first and re-run the audit verify-only once; still open → HALT (class H); spend cap, the one-day window or a HALT-class event → HALT at the nearest safe point with the HALT checkpoint written (below).
**Terminal rule (one, authoritative — PRD R-3):** an unresolved blocking finding (critical or high from review, audit or Bridgebuilder) halts shipping; no waiver exists for it. A non-blocking finding may be deferred only by a `proposed` DEC row naming the finding id, its severity, the final head sha and the acceptance basis; Task 2.9 refuses to open the PR, merge or publish while any blocking finding is open.
**HALT checkpoint (what a HALT writes before stopping):** `.run/sprint-plan-state.json` HALTED with the reason; a NOTES.md entry listing the active worktrees and their heads, patches staged but not landed, commits landed since the last verdict, each gate's status and `reviewed_head`, meter spend, pending release operations (PR open? merged? record pushed? candidate prepared? published?) and the exact safe resume step; implementer agents stopped, their worktrees kept. Ship safe points: HALT may occur before the PR is opened, before ship-1 (merge) and before the rc.9 publish; once ship-1 starts the sequence proceeds to the next stable state (merged + record pushed, or merged + record + archive) or executes the written rollback — never a half-merged state.
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); the lead's tasks are `judgment`; no `operator` task exists — the operator's instruction of 2026-10-28 ("do formal gates and then release when ready and you can also work through the open beads") authorises the whole cycle including the release.
**Decision-row classes:** class S (self-confirmable under that instruction; written `proposed`, confirmed at the close): recording a measured floor and moving FR-6's AC to it; updating a spawn budget with its reason; deferring a Should/Could bead with its reason (the beads were offered as optional work); the D-x.y design choices of the SDD; a dissent voice unreachable after three runs (the lead's review and the audit still run); Bridgebuilder degraded or exhausted with no blocking finding open; a non-blocking finding waived in the terminal-rule format. Class H (halt for the operator — Task 2.9 refuses to open the PR, merge or publish while any unconfirmed class-H row exists, and none is written in this cycle except to record the halt): a blocking finding left open; merging with a required check not `success`; publishing with a digest or `merge_sha` mismatch; accepting a parity divergence beyond the five documented in `a2a/sprint-281/reviewer.md`; any change to `_check_trust_store`, a `br` contract call or a fence's fail-open/fail-closed semantics.
**Spend:** USD 30 cap in the meter's unit (`.run/cost-ledger.jsonl`): Flatline reviews, dissent runs and Bridgebuilder rounds on subscription routes; the Opus 5.5 implementers run as Claude Code agents on the subscription and are not metered in that ledger (their wall time is bounded by the time budget instead); real charges ≈ 0. Meter checkpoints: after the Sprint 1 audit, after the last implementer patch lands (2.7), after the Sprint 2 audit (2.8), before the publish (2.9) — each recorded in the e2e file.
**Time budget (T = the Sprint 1 gates start; one unattended day):** Sprint 1 gates done by T+3 h; implementer patches back by T+6 h; landing and the Sprint 2 report by T+8 h; Sprint 2 review and audit by T+10 h; Bridgebuilder, merge, record by T+13 h; publish, smoke test, archive by T+14 h. Slip order when a latest-start passes: the ship steps slip first (publishing later costs nothing — no operator is needed), bd-09z1i defers first, then bd-wctli, then bd-h5tcn; FR-2, FR-3, FR-5 are not deferred for time.

## Executive Summary

Two sprints. Sprint 1 (global 281) takes the 22-pass optimisation loop — 20 commits already on this branch, each proven byte-identical and Opus-reviewed — through the framework's formal review and audit gates; only gate fixes land. Sprint 2 (global 282) closes the six follow-up beads the loop filed (bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli, bd-09z1i) with the same discipline (profile, golden, one lever, old-vs-new mirror parity, red-first tests), then ships one PR through a Bridgebuilder round, the record branch, the archive and the `v2.0.0-rc.9` release candidate.

## Sprint Overview

| Sprint | Global | Goal | Owners |
|---|---|---|---|
| Sprint 1 | 281 | FR-1: the loop reviewed and audited; G-1, G-3, G-4 evidenced | lead |
| Sprint 2 | 282 | FR-2 … FR-7 implemented and tested; FR-8 shipped; G-2, G-5, G-6 | lead, A, B, C, D |

Duration: one unattended day (2026-10-28). Team: the lead plus up to four Opus 5.5 implementers (A shell: C-2 + C-5; B shell: C-3 + C-4; C tests: C-6; D python+shell: C-7). Cadence: implementers return patches; the lead lands them in dependency order and runs the gates.

## Sprint 1: Formal gates on the optimisation loop (global 281)

### Sprint Goal

`/review-sprint` ends `All good` and `/audit-sprint` ends `APPROVED` on the 20 loop commits, with any fix landed red-first and the touched passes' parity harnesses re-run; `COMPLETED` written; ledger sprint 281 completed.

### Deliverables

- `grimoires/loa/a2a/sprint-281/reviewer.md`: the engineer's report — one row per productive pass (target, lever, parity evidence and inputs, covering bats and counts, before/after, review verdict, commit), the two no-change passes with their floors, the final re-baseline table, the full-suite result, and the `## AC Verification` walkthrough of FR-1's criteria (C-1).
- `engineer-feedback.md` (review) and `auditor-sprint-feedback.md` (audit) with `LOA-VERDICT` trailers; fix commits where the gates find anything (each with `checksums.json` + REPO-MAP regenerated).
- `a2a/sprint-281/e2e.md` with the G-1 / G-3 / G-4 evidence.

### Acceptance Criteria

- [x] FR-1 AC rows all green: `reviewer.md` walkthrough complete for passes 1–11, 13, 14, 16–22 and the no-change passes 12 and 15; review `All good`; audit `APPROVED`; `verdict-derive.sh --gate review` and `--gate audit` CONSISTENT; `COMPLETED` written; ledger 281 `completed`.
- [x] Every gate fix commit is red-first where behaviour changes and byte-identical old-vs-new where a loop file's implementation changes; the pass's `~/.cache/loa/eso-loop/pass-K/` harness re-run on the final head; `check-no-raw-sha256sum.sh` and `check-no-swallowed-jq.sh --quiet` clean at every fix commit (the same gate set as Sprint 2).
- [x] Each verdict names `reviewed_head: <sha>`; a code commit after a verdict re-runs that gate before `COMPLETED` (PRD § Constraints, D-1.1).
- [x] A reverted loop pass (Task 1.1 revert path): its later-pass dependencies checked first, its row excluded from the G-3 comparison and named in the DEC row, its mirror harness run old-vs-reverted, the suite re-run.
- [x] Evidence copied to `a2a/sprint-281/evidence/` (per-pass REPORT and VERDICT files, `final-table.tsv`, `baseline/*.json`, `final/*.json`, `rebaseline.sh`, the two TAP files) with the sha256 of each external artefact the plan relies on (`~/.cache/loa/cycle-135/ship/*.sh`, `~/.cache/loa/eso-loop/rebaseline.sh`) recorded in `e2e.md`.
- [x] `tests/unit/perf-spawn-budget.bats` 6/6, `check-loa.sh` passes, `repo-map-gen.sh --validate` passes on the final Sprint 1 head.
- [x] G-3: the re-baseline of `~/.cache/loa/eso-loop/rebaseline.sh` on the final head: no touched row's mean above 110 % of its `final-table.tsv` mean (untouched rows recorded), measured serially on the idle host with no concurrent bats or implementer activity.
- [x] G-4: the full `tests/unit` TAP on the final head fails only the three KF-034 tests of PRD R-4 (exact names), with no new skips; the companion file passes in a serial whole-file run on the idle host.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [x] Task 1.0: Prep and engineer's report (lead) — rotate NOTES.md first if it is within 10 KiB of the 200 KiB guard (`notes-guard.sh rotate`; destination the dated archive the script names); copy the loop evidence to `a2a/sprint-281/evidence/`; then write `a2a/sprint-281/reviewer.md` from `.skill-loop-progress.md` § LOOP 2, the per-pass `REPORT.md` / `review/VERDICT.md` files, `final-table.tsv` and `bats-final/unit.tap`: per pass the parity inputs and comparison, the bats files and counts, the before/after numbers, the verdict and the commit; the no-change passes; the `## AC Verification` section mapping each FR-1 criterion to evidence. → **[G-1]** ⇐ none · kind: judgment
- [x] Task 1.1: Review (lead) — `/review-sprint sprint-1` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs over `main..HEAD`); findings fixed red-first (behaviour) or with a mirror parity proof (implementation), manifests regenerated per commit, the two lint checks clean; `engineer-feedback.md` C-11 grammar, `reviewed_head` named, verdict-derive consistent; a non-fixable finding reverts that single loop commit (dependency check first; dependent later passes reverted together or fixed forward) with a DEC row; CHANGELOG: the loop's block already sits under `[Unreleased]` (pass 22) and each gate fix adds its own line there (lead-inserted), so the rc.9 heading written at the ship covers both sprints. → **[G-1]** ⇐ 1.0 · kind: judgment
- [x] Task 1.2: Audit (lead) — `/audit-sprint sprint-1` → `auditor-sprint-feedback.md` naming `reviewed_head`; fixes as 1.1 (a fix re-runs the audit as a verify-only pass on the new head); `COMPLETED`; ledger sprint 281 `completed` (set `completed` with jq under bash — ledger-lib sets only the status). → **[G-1]** ⇐ 1.1 · kind: judgment
- [x] Task 1.E2E: Sprint 1 goal validation (lead) — `a2a/sprint-281/e2e.md`: G-1 (the two verdicts, the marker), G-3 (re-baseline table within 10 %, guard 6/6), G-4 (full-suite TAP summary; CMP-37 alone). → **[G-1, G-3, G-4]** ⇐ 1.2 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| lead only | any loop file a gate finding names, with `checksums.json` + REPO-MAP regenerated; `a2a/sprint-281/**`; `.skill-loop-progress.md` | the 20 loop commits' history (no squash, no rebase) |

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| Old-vs-new mirror of each loop file in a REAL directory over the pass's fixture matrix | an implementation change that alters bytes, exit code or stderr | hosts with other awk/yq versions (noted UNVERIFIED per pass) | `~/.cache/loa/eso-loop/pass-K/review/` harnesses |
| `tests/unit/perf-spawn-budget.bats` over fixed fixtures | a spawn added to a guarded hot path | spawns on paths without a fixture (karpathy until Sprint 2) | pass 22 |
| The covering bats suites per touched file (repo-map-gen, grimoire-index, kf-surface, run-checkpoint*, compat-*, implement-gate, notes-size-guard, run-state-surface, cache-manager, loa-status*, guard-yield, adapter pytest, karpathy*, push-gate) | a behaviour regression a parity fixture did not cover | — | the loop's per-pass test runs |

### Dependencies

- Internal: 1.0 → 1.1 → 1.2 → 1.E2E. External: the host toolchain (bash 5, jq 1.7, mikefarah yq 4.44, Python 3.13, bats 1.13 via npx, hyperfine 2.0) and the unversioned artefacts Task 1.0 verifies and fingerprints (`~/.cache/loa/eso-loop/**`, `~/.cache/loa/cycle-135/ship/*.sh`).

### Security Considerations

- The loop touched four fences (implement-gate, notes-size-guard, karpathy, run-mode-stop-guard) and one trust surface (kf-surface): the review re-reads their fail-open / fail-closed paths and the sanitisers; any widening is a blocking finding.
- The audit confirms no new eval/source of untrusted data, atomic-write semantics on the new `.run/perf-cache`-style paths (none added in the loop), and that the lazy provider imports change no credential handling.

### Risks & Mitigation

- Risk: the formal review finds a parity gap the per-pass reviews missed → fix red-first and re-run the pass harness; a non-fixable one reverts that single commit (one pass = one commit).
- Risk: dissent voices unreachable (KF-037/KF-041 shapes) → ≤ 3 runs, then lead-only gate recorded in a DEC row.
- Risk: the review's own bats runs load the host and CMP-37 fails → run the file alone and record it.

### Success Metrics

- G-1: review `All good`, audit `APPROVED`, `COMPLETED` present.
- G-3: re-baseline within 10 %; guard 6/6.
- G-4: full suite green modulo KF-034.

> Sources: prd.md § FR-1, § Goals; sdd.md § 1.4 C-1, § 7; `.skill-loop-progress.md` § LOOP 2

---

## Sprint 2: The six follow-up beads and the ship (global 282)

### Sprint Goal

Close bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli and bd-09z1i with red-first tests (bd-wctli: TAP-set parity plus the negative control) and byte-identical outputs where output exists, each landed or deferred under PRD R-2; the Sprint 2 engineer's report; review `All good` and audit `APPROVED` on the final head with the ship files already committed; `COMPLETED`. The ship itself (PR, Bridgebuilder, merge, record, publish, archive) is the post-audit § Ship section below — outside the gated sprint, as in cycles 135/136.

### Deliverables

- C-2: shape-C field regex and H2 `cur` reset in both KF parsers; `kf-surface.bats` and `grimoire-index.bats` cases (A).
- C-5: `grimoire-index.sh` content-keyed decisions cache under `.run/perf-cache/`, `LOA_GRIMOIRE_INDEX_NO_CACHE=1`, one write-mode jq for `bad` + `total`; bats cases (A).
- C-3: `_anthropic_ceiling_json` six-line yq protocol with fallback; `_agy_opt_in_node_memo` in `agy-gate-lib.sh`; bats cases (B).
- C-4: `profiles.yaml` `cached_keys` + cache-builder support + `loa_knob` absent-source fast path; `profile-lib.bats` cases; karpathy target added to `perf-spawn-budget.bats` (B).
- C-6: `block-destructive-bash.bats` corpus-once `setup_file`; `adversarial-review-companion.bats` bounded waits; TAP-set parity evidence (C).
- C-7: `audit-envelope.sh verify-chains` + the Python batch entry; `loa-status.sh` switched to one call; bats and the security suite green (D).
- CHANGELOG `[Unreleased]` lines per bead (lead inserts the implementers' texts); then, before the final gate pass, the rc.9 heading, the README pin and `.loa-version.json` (so the reviewed head is the merged head — PRD R-1/R-3).
- `a2a/sprint-282/reviewer.md`: the Sprint 2 engineer's report (FR-2 … FR-7 AC walkthrough, measurements with host/command/run count, parity evidence, deferrals with their DEC rows, final commit shas) — written before Task 2.8.
- `a2a/sprint-282/prep.md` (external artefacts verified with sha256; the `profile-lib.sh` sourcers and their bats files; awk interpreters present) and `a2a/sprint-282/briefs/` (the four implementer briefs as given).

### Acceptance Criteria

- [ ] FR-2 AC rows all green (shape C parsed in both parsers, shape B still parsed, `## KF-abc:` resets, live file byte-identical for the hook stdout and `--tsv/--json/write`).
- [ ] FR-3 AC rows all green (mirror parity on live/--json/--help/bogus/no-yq and the config matrix for `loa-status.sh` and `run-preflight.sh`; `yq` count 1 in `_anthropic_ceiling_json` on the six-line success path with the live config — the fallback intentionally performs today's reads; ≥ 40 ms measured on `bash .claude/scripts/loa-status.sh` (human mode, from the project root) under the measurement protocol; agy memo bats incl. same-size rewrite, `mv`, deletion, path switch).
- [ ] FR-4 AC rows all green (warm cache resolves `diff_lines_per_task` without `yq`; override / profile default / hard default identical to the live path; `loa_profile` output unchanged; karpathy state files identical across the pass-19 matrix; new spawn-budget target).
- [ ] FR-5 AC rows all green (cold/warm parity on all modes; invalidation on content change; truncated / altered / wrong-key / wrong-count / symlinked / read-only / foreign-owned or group-writable cache dir ignored with no write; `NO_CACHE=1` disables read and write; yq-absent host never reads; concurrent writers; mid-run source rewrite caches nothing; warm ≤ 650 ms and cold ≤ old + 40 ms; budget updated with reason).
- [ ] FR-6 AC rows green or the measured floor recorded by a class-S DEC row written before Task 2.8 (pass/fail/skip set identical per test name; negative control per affected test; corpus run once with `setup_file` status captured; companion serial wall time ≤ 300 s or the floor, median of three `bats -T` runs).
- [ ] FR-7 AC rows all green ((a) implemented per sdd.md § 5.7: exactly one validated JSON record per requested path, in argument order; a missing, duplicate or malformed record or a process failure marks the affected paths FAILED (fail-closed) in the wrapper and in `loa-status.sh`; per-path results equal per-call results on live and fixture chains and under the store-mutation schedule (revoke, tamper, delete) with independently stated expected outcomes — every path verified under an INVALID store FAILs with `[TRUST-STORE-INVALID]` and `loa-status.sh` shows the same invalid count old and new; `test_audit_trust_policy.py` green; the 44 audit-envelope bats files green; ≥ 100 ms on a 5-chain fixture root) or (b) deferred by a class-S DEC row written before Task 2.8 with the bead relabelled `deferred-cycle-137`.
- [ ] Each red commit fails only its own new cases (`red-test-check.sh`); each fix commit green; Task 2.5 lands as one commit exempt from the red/fix pair (its evidence is the TAP set, the `bats -T` tables and the negative control); `checksums.json` and REPO-MAP regenerated in every System Zone commit; `check-no-raw-sha256sum.sh`, `check-no-swallowed-jq.sh --quiet`, `check-loa.sh`, `repo-map-gen.sh --validate`, `perf-spawn-budget.bats` green at every fix commit and the final head.
- [ ] `a2a/sprint-282/reviewer.md` written before the review; review `All good` and audit `APPROVED` with `reviewed_head` equal to the head that the PR will merge (ship files already committed); `verdict-derive.sh` CONSISTENT; `COMPLETED`; ledger sprint 282 `completed`.
- [ ] Full `tests/unit` TAP on the final head under PRD R-4 (only the three named KF-034 tests, no new skips) and the whole-head parity gate of sdd.md § 7 (old mirror from the Sprint 1 final head vs new mirror from the Sprint 2 final head over every touched entry point).
- [ ] Live KF file: for the parsed labels (`Symptom`, `Recurrence count`, `Status`) exactly one shape-C line exists today — `**Status (original)**: OPEN …` in KF-008, AFTER that entry's plain `**Status**:` line (grep recorded in `prep.md`); shape C is therefore scoped to `Symptom` and `Recurrence count` (D-2.2: the live qualified `Status` forms — `Status (original)`, `Original Status`, `Historical status (…)` — are historical annotations that must never win), `Status` keeps shapes A/B, a decoy fixture `**Status (original)**:` after `**Status**:` asserts no change, and FR-2's byte-identical criterion stands; if the grep count changes before landing, the criterion becomes "differs only by the enumerated newly recognised fields, diff attached".

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [x] Task 2.0: Sprint prep (lead) — after Sprint 1 `COMPLETED`: verify and fingerprint the external artefacts (`~/.cache/loa/cycle-135/ship/*.sh`, `~/.cache/loa/eso-loop/rebaseline.sh` and the pass harnesses) into `a2a/sprint-282/prep.md`, together with the list of `profile-lib.sh` sourcers and their bats files and the awk interpreters present (`mawk`, `busybox`, `gawk`); verify the structural anchors each brief cites (the `verify-chain` loop inside the chain-status function of `loa-status.sh`, `_anthropic_ceiling_json`, `fieldval` in both parsers) and replace line numbers by function names in the briefs; write the implementer briefs under `~/.cache/loa/cycle-137/briefs/` and copy them to `a2a/sprint-282/briefs/` (one per implementer: allowlist, SDD section, fixtures, parity recipe with REAL-directory mirrors, red-first rule or its test-only substitute, measurement protocol, no live push config, no deletions under the System Zone, zsh word-split note, the HALT and STOP conditions); create the four worktrees from the Sprint 1 final head; re-brief rule: if a Sprint 1 gate fix touched a file on an implementer's allowlist, that brief names the fix commit. → **[G-2]** ⇐ none · kind: judgment
- [x] Task 2.1: KF shape-C regex and H2 reset (A, System Zone) — `loa-kf-surface.sh` and `grimoire-index.sh` `fieldval`: add shape C (`^(- )?\*\*LABEL( [^*]*)?\*\*: ?`) for the `Symptom` and `Recurrence count` labels only — `Status` keeps shapes A/B (D-2.2; the live `**Status (original)**:` in KF-008 must never win) — and reset `cur` on every `^## ` line (sdd § 5.1); `kf-surface.bats` and `grimoire-index.bats` red-first cases: shape C parsed, shape B still parsed, `**Symptomatic**:` not a field, `## KF-abc:` resets, `## Index` fields ignored; live-file parity (hook stdout; `--tsv/--json/write`) byte-identical; `## KF-abc:` resets silently (no stderr); drift test asserting the two `fieldval` bodies and heading rules are identical; both programs run under every awk present on the host (mawk, busybox awk, `gawk --posix`; absent ones skipped by name in the report). → **[G-2]** ⇐ 2.0 · kind: mechanical
- [x] Task 2.2: grimoire-index decisions cache and one write-mode jq (A, System Zone) — sdd § 3 and § 5.5: key `v1:<sha256_portable of the decisions.yaml snapshot>:<yq major.minor>:<jq major.minor>:<row count>` as the first line of `.run/perf-cache/grimoire-index-decisions.v1.tsv`; trust boundary before any read or write: `.run` and `.run/perf-cache` are real directories (not symlinks), owned by the current uid, not group- or world-writable — otherwise the cache is neither read nor written; reader = one awk validating header, row count, 9 fields per row and the sanitiser alphabet, printing rows only when everything validated; hit → print; miss → today's pipeline over the same snapshot, then the writer (umask 077, `mkdir -p` + `-L` re-check, exclusive `mktemp "$cache.XXXXXX"`, `-L` re-check on the cache path immediately before `mv -f -T`/`mv -f`, temp removed on failure, never fatal, never under CI); `LOA_GRIMOIRE_INDEX_NO_CACHE=1` disables read and write; the unparsable-ledger NOTE path caches nothing; the `v1:` prefix constant sits next to the `s` filter with a bats case pinning their coupling; write-mode `bad` and `total` from one root-preserving jq (sdd § 5.5) tested on a valid and an invalid index; bats red-first (hit skips yq by trace, miss rebuilds, content change invalidates, truncated/altered/wrong-key/wrong-count/symlinked dir/symlinked file/pre-existing temp symlink/read-only/group-writable dir → no read no write, NO_CACHE, CI env, yq-absent host, two concurrent writers, source rewritten mid-run → no cache written); cold/warm parity on all four modes; `perf-spawn-budget.bats` grimoire-index budget updated with the reason in the same commit. → **[G-2]** ⇐ 2.1 · kind: mechanical
- [x] Task 2.3: loa-status six-line yq and the agy node memo (B, System Zone) — sdd § 5.2 and § 5.3: one `yq eval -r` emitting alias + five fields, accepted only as exactly six lines, else today's reads verbatim; `_agy_opt_in_node_memo` (parent-shell wrapper, result in `_AGY_NODE_MEMO_VAL`, never `$(...)`) keyed by `<cfg>|dev:ino:size:mtime:ctime` with nanosecond precision where `stat` supports it (GNU `%.9Y`/`%.9Z`, else seconds — recorded UNVERIFIED on a 1 s filesystem), `stat` failure → no memo; used by `agy_opted_in` and `agy_gate_warn_once`; two commits (ceiling read; memo); bats red-first (`loa-status-providers.bats`: fast path taken on the live config by trace, six-line fixtures — malformed YAML, map for scalar, embedded newline, null, false, empty final field, all absent, yq failure; `agy-gate-conformance.bats`: memo hit, miss after a same-length `true`→`false` rewrite within the same second, after `mv`, after deletion, after a path switch, `$(...)` caller correct); mirror parity over live/--json/--help/bogus/no-yq and the config matrix (alias absent; model without ceiling fields; opt_in true/false/"true"/absent) for `loa-status.sh` AND `run-preflight.sh`; hyperfine ≥ 40 ms on `bash .claude/scripts/loa-status.sh` under the protocol; `yq` count 1 in the function's trace on the success path. → **[G-2]** ⇐ 2.0 · kind: mechanical
- [x] Task 2.4: profile-lib `cached_keys` (B, System Zone) — sdd § 5.4: `profiles.yaml` top-level `cached_keys: [karpathy_principles.diff_lines_per_task]`; the cache builder records `{value, source: explicit|absent, profile_value: null}` for listed non-profile keys; `profile_keys` and `overrides` unchanged; `loa_knob` warm-cache `absent` → fallback without `yq`; classification mirrors `_loa_pl_live` exactly (same yq expression; fixtures null, "", false, 0, map, multi-line); bats red-first in `profile-lib.bats` (absent → fallback without yq by trace, explicit wins, stale id → live, older cache without the entry → live, `loa_profile` output byte-identical, cache JSON differs only by the new knob entry); every validator of `profiles.yaml` accepts the new top-level key (`check-loa.sh`, yamllint, profile-lib's key enumeration) and the bats files of every `profile-lib.sh` sourcer (listed in `prep.md`) stay green; karpathy hook state files identical across the pass-19 matrix (`~/.cache/loa/eso-loop/pass-19/` harness); `perf-spawn-budget.bats` gains a karpathy target (fixed fixture + warm cache) measured and budgeted in the same commit. → **[G-2]** ⇐ 2.3 · kind: mechanical
- [x] Task 2.5: Test-suite runtime (C, tests only; one commit, exempt from the red/fix pair) — sdd § 5.6: `block-destructive-bash.bats` `setup_file` runs the corpus once into `$BATS_FILE_TMPDIR` capturing status, stdout and stderr without failing (`|| true`); each corpus test asserts the status and JSON validity first; `corpus_json()` reads the file (the runtime test reads `runtime_ms` of that run); `adversarial-review-companion.bats`: `bats -T` serial profile first (median of three), then shorten only fixed sleeps no test waits on and keep every hold ≥ 2× the longest wait on it (`CMP_STUB_HOLD_S`, default 300, read only by the in-file shim and the test bodies), listing the affected tests and their bounds by name; no assertion, expected value or skip condition changes; negative control per affected test (break the asserted behaviour → fails; restore → passes); TAP pass/fail/skip set per test name identical before and after (serial); CMP-37 untouched; report the measured floor; if the companion file stays above 300 s, the report names the floor and the lead records the class-S DEC row adjusting FR-6 before Task 2.8. → **[G-2]** ⇐ 2.0 · kind: mechanical
- [x] Task 2.6: `verify-chains` (D, System Zone) — sdd § 5.7: `audit-envelope.sh verify-chains <path>…` → one Python process, `audit_verify_chain` per path in its own try/except, one JSON record per input path in argument order `{i, path, ok, error}`, exit 0 / 1 / 2 (usage or import); the shell wrapper parses by index with one jq and is fail-closed: exactly one validated record per requested path, otherwise (missing, duplicate, malformed, non-1 non-zero exit, unparsable output) every unrecorded path is FAILED; `_check_trust_store`, `_trust_store_snapshot` and `audit_verify_chain` bodies untouched; the `verify-chain` loop inside the chain-status function of `loa-status.sh` (the lead verifies the anchor at briefing) keeps its `[[ -f ]]` pre-filter and makes one call, reproducing today's `valid` count by index; bats red-first: valid/tampered/broken-link/missing/empty chains per path, paths with spaces and colons, duplicate paths, zero args → exit 2, a truncated record set → fail-closed, read-only chain tree with sha256 before/after, a tampered trust store → every path FAILs with `[TRUST-STORE-INVALID]` and `loa-status.sh` shows the same invalid count old and new, single `verify-chain` unchanged; pytest in `tests/unit/`: batch records equal fresh per-call results under a store-mutation schedule between paths (replace with a revoking store; tamper; delete) via a test hook that does not touch the protected functions; `pytest tests/security/test_audit_trust_policy.py` green; the 44 audit-envelope bats files green; hyperfine on a 5-chain fixture root ≥ 100 ms; loa-status mirror parity. If any of this needs a change to `_check_trust_store`, STOP and return the measurement for a class-S DEC-row deferral. → **[G-2]** ⇐ 2.3 · kind: mechanical
- [x] Task 2.7: Landing and the Sprint 2 report (lead) — land in this order: A (2.1 red, 2.1 fix, 2.2 red, 2.2 fix), then B (2.3 as two red/fix pairs, 2.4 red/fix — B's `perf-spawn-budget.bats` karpathy target lands after A's budget line; the lead resolves the shared file), then C (2.5, one commit), then D (D's worktree is reset onto B's landed 2.3 fix before D edits `loa-status.sh`; 2.6 red/fix); every commit under the marker with `checksums.json` and REPO-MAP regenerated; `red-test-check.sh` per red commit; the implementers' CHANGELOG texts inserted; `perf-spawn-budget.bats` budgets updated where a task says so; `rebaseline.sh` re-run serially on the idle host and the table recorded; the whole-head parity gate (sdd § 7) run; class-S DEC rows for every judgment call (D-1.1, D-2.1 … D-8.1, the implementers', any deferral) written before 2.8; beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli closed PROVISIONALLY ("landed on feature branch <sha>, pending merge" — updated at ship-4 with the merged sha), bd-09z1i likewise or relabelled `deferred-cycle-137`; then the ship files (rc.9 CHANGELOG heading with the rc.8 version markers, README pin, `.loa-version.json`) committed; then `a2a/sprint-282/reviewer.md` written (FR-2 … FR-7 walkthrough, measurements with host/command/run count, parity evidence, deferrals, final shas). Bead rollback reverts the fix commit AND its red commit together. → **[G-2]** ⇐ 2.2, 2.4, 2.5, 2.6, Sprint 1 `COMPLETED` · kind: judgment
- [ ] Task 2.8: Review and audit (lead) — `/review-sprint sprint-2` (≤ 3 dissent runs, code-only diffs since the Sprint 1 head), `engineer-feedback.md` (C-11 grammar, `reviewed_head`, verdict-derive consistent); fixes red-first with the touched task's parity harness re-run; `/audit-sprint sprint-2` → `auditor-sprint-feedback.md` with `reviewed_head` equal to the head the PR will merge; `COMPLETED`; ledger sprint 282 `completed`; meter checkpoint. → **[G-2]** ⇐ 2.7 · kind: judgment
- [ ] Task 2.E2E: Sprint 2 goal validation (lead) — `a2a/sprint-282/e2e.md` part 1 (written at `COMPLETED`): G-2 (six beads with commit + test, or the deferral row), the measurement tables with host/command/run count, the whole-head parity gate result, the full-suite TAP under R-4, the meter checkpoints. Part 2 is appended by the § Ship section. → **[G-2]** ⇐ 2.8 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh`, `tests/unit/kf-surface.bats`, `tests/unit/grimoire-index.bats`, `tests/unit/perf-spawn-budget.bats` (the grimoire-index budget line and comment only) | `CHANGELOG.md` (text returned in the report), `checksums.json`, REPO-MAP (lead regenerates), any other hook or script |
| B | `.claude/scripts/loa-status.sh` (`_anthropic_ceiling_json` only), `.claude/scripts/lib/agy-gate-lib.sh`, `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml`, `tests/unit/loa-status-providers.bats`, `tests/unit/agy-gate-conformance.bats`, `tests/unit/profile-lib.bats`, `tests/unit/perf-spawn-budget.bats` (the new karpathy target only) | `CHANGELOG.md`, manifests, the karpathy hook itself, any other `loa-status.sh` function |
| C | `tests/unit/block-destructive-bash.bats`, `tests/unit/adversarial-review-companion.bats` | anything under `.claude/`, any other test file, `tests/fixtures/**` |
| D | `.claude/scripts/audit-envelope.sh`, `.claude/adapters/loa_cheval/audit_envelope.py` (a new batch entry point only — `_check_trust_store`, `_trust_store_snapshot`, `audit_verify_chain` bodies untouched), `.claude/scripts/loa-status.sh` (the `verify-chain` loop inside the chain-status function only — the lead names the function in the brief), `tests/unit/audit-envelope*.bats` (new cases only), one new `tests/unit/test_audit_verify_chains.py` | `CHANGELOG.md`, manifests, `audit-signing-helper.py`, `tests/security/**`, any chain file under `.run/` or `grimoires/` |

A patch outside its allowlist is returned, not landed. Implementers make no live model or GitHub calls, never run anything with the live push configuration, never write under `.run/` of the main checkout, and never commit, push or stash in their worktrees. Parity mirrors live under paths without `.claude` in them or with the file under test in a REAL directory.

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `fieldval` over fixtures of the three field shapes, a `**Symptomatic**:` decoy, `## KF-abc:` and `## Index` sections, plus the live file | a shape parsed differently between the two parsers; a field attached to the wrong entry | field shapes nobody writes (e.g. `__Label__:`) | pass-6 reviewer fixtures fx_e/fx_all |
| `_anthropic_ceiling_json` six-line protocol vs the per-field reads on the config matrix (alias absent, ceiling fields absent, multi-line value) | a value shift or a dropped field; a multi-line value swallowed | yq versions other than mikefarah 4.44 (UNVERIFIED) | pass 18's three-line protocol |
| `_agy_opt_in_node_memo` with a rewritten config between calls and a `$(...)` caller | a stale node after a rewrite; a memo leak across configs | a config rewritten with identical dev/ino/size/mtime within one second | pass 14's memo |
| `loa_knob` on a warm cache for an absent cached key, an explicit value, a stale id | a wrong fallback; a profile-keys change; an `overrides` change | profile-lib callers outside the hook set (10 callers — the cache builder test covers `loa_profile`) | `profile-lib.bats` |
| decisions cache hit / miss / invalidation / corrupt / symlink / read-only / NO_CACHE, cold and warm, all four modes | stale rows; a cache write that is fatal; a cache followed through a symlink | concurrent writers (last writer wins; both outputs are correct) | zone-write-guard's perf-cache |
| TAP pass/fail/skip set per test name for the two test files, serial, before vs after | a changed verdict; a dropped test | wall-time on CI runners (recorded, not asserted) | pass 21 |
| `verify-chains` per-path results vs `verify-chain` per-call results on live and fixture chains, with a tampered trust store | a per-path divergence; a trust decision changed by batching | hosts without the signing helper (same refusal as today) | `test_audit_trust_policy.py` |

### Dependencies

- Internal: Sprint 1 `COMPLETED` → 2.0 (worktrees from the Sprint 1 final head) → 2.1 → 2.2 (A, same file area); 2.0 → 2.3 → 2.4 (B) and 2.3 → 2.6 (D's worktree reset onto B's landed 2.3 fix); 2.0 → 2.5 (C, independent); 2.7 after 2.2, 2.4, 2.5, 2.6 and Sprint 1 `COMPLETED`; 2.8 after 2.7; 2.E2E after 2.8; the § Ship section after 2.E2E.
- External: host toolchain (bash 5, jq 1.7, mikefarah yq 4.44, Python 3.13 with the repo `.venv` for pytest, bats 1.13 via npx, hyperfine 2.0, the awk interpreters present on the host — mawk, busybox, gawk — for the portability check, `gh` 2.x authenticated for the ship, `codex` CLI logged in for `BRIDGEBUILDER_MODEL=codex-headless` with the fallback chain in the header).

### Security Considerations

- The KF parsers surface untrusted text: the change widens which lines are recognised as fields, never what is done with them — sanitisation (`san()`, the jq `s` filter) is unchanged; every awk present on the host runs the regexes (Task 2.1 names the ones tested).
- Caches: trust boundary enforced before any read or write (real, uid-owned, non-group/world-writable `.run` and `.run/perf-cache`; otherwise neither read nor written); content-keyed with row count; payload validated row by row against the sanitiser alphabet; exclusive temp files; symlink checks re-done immediately before the rename; never fatal; never under CI; a forged cache is served only to whoever could already write the source file (the pass-6 trust argument of the 2026-07 loop) and then only if it validates.
- `verify-chains` keeps `_check_trust_store` and its subprocess-over-snapshot defence untouched; chains are read-only inputs; the security suite is a gate.
- The agy memo keys on file identity so a rewritten config is re-read; the subshell reader keeps its fd-9 open-once check.
- Implementers never touch the live push config, credentials, `.run/` of the main checkout or the `br` contract calls; secret scan before every push.

### Risks & Mitigation

- Risk: shape C over-matches → space-after-label requirement; decoy fixtures.
- Risk: the six-line protocol swallows a newline → line-count gate and fallback; multi-line fixture.
- Risk: `cached_keys` changes visible profile output → `profile_keys`/`overrides` computed from profile keys only; `loa_profile` output pinned byte-identical.
- Risk: the companion file's floor is the script runtime → measured first; the AC moves to the floor by DEC row rather than forcing structural test changes.
- Risk: `verify-chains` alters a trust decision → untouched gate function; security suite; per-path vs per-call parity; else deferral.
- Risk: a Bridgebuilder round degrades (KF-010/KF-062) → prefix excludes for generated and planning files; ≤ 2 rounds; recorded.
- Risk: rc.9 publish (KF-034, KF-063) → rc.8 recipe; non-shallow clone; digest approval; ancestry check before announcing.
- Rollback: a bead reverts as its fix commit plus its red commit together (a red test alone would be red on `main`); a reverted loop pass is checked for later-pass dependencies and re-verified with its mirror harness; the whole cycle reverts as the single merge commit with manifests regenerated; the published release follows the written rollback in § Ship (release withdrawn, tag kept, version pins return with the revert, record branch and archive stay as history with a note, beads reopened).

### Success Metrics

- G-2: 6 of 6 beads closed (or 5 + one deferral row) with commit and test.
- G-5 and G-6 are measured by the § Ship section.

> Sources: prd.md § FR-2 … FR-7, § Goals, § Release predicate; sdd.md § 3, § 5.1 … § 5.7, § 6, § 7, § 9, § 11.D

---

## Ship (post-audit; outside the gated sprint — cycles 135/136 precedent; PRD FR-8 and R-3 … R-8; sdd.md § 5.8)

Runs only after Sprint 282 `COMPLETED` and only while no class-H row and no blocking finding is open. Its rows are checked separately:

- [ ] S-1 Pre-PR: secret scan on the final head; CI mirror (full unit suite) from the final head under R-4; the PR body lists both sprints, beads, DEC rows, each gate's verdict with its `reviewed_head`, the measurement protocol (host, command lines, run counts) and the Bridgebuilder outcome per head sha; PR opened from `feature/cycle-137-performance` (title names the behaviour changes and classifies `cycle`).
- [ ] S-2 Bridgebuilder: ≤ 2 rounds (`BRIDGEBUILDER_MODEL=codex-headless`, generated and planning files excluded; fallback chain per the header). A blocking finding is fixed red-first on the branch, the touched task's parity harness is re-run, and `/audit-sprint sprint-2` re-runs as a verify-only pass naming the new `reviewed_head`; the CI mirror and secret scan re-run on that head. Round 2 ending with a blocking finding open → HALT (class H). Non-blocking findings are fixed or waived in the terminal-rule format.
- [ ] S-3 Merge gate (R-3): every check run on the exact PR head has completed with conclusion `success`, or `neutral`/`skipped` only for a path-filtered workflow that did not run; any `failure`, `cancelled`, `timed_out` or `action_required` blocks; the six required checks — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — are `success`; `reviewed_head` of both verdicts equals the PR head; merge via the cycle-135 `ship-1` recipe; then `git diff --quiet <PR head> <merge commit>` (identical trees).
- [ ] S-4 Record: `ship-2` (`record-branch.sh --cycle 137 --prev origin/record/cycle-136-bridgebuilder-followups`, `--accept-scan` only for the `audit-key-password-assignment` NOTES hit); stage 1 pushed; the ship scripts copied to `a2a/sprint-282/ship/` with sha256 in `e2e.md`.
- [ ] S-5 Main CI (R-5): the push-to-main `BATS Tests` and `CI` runs on the merge commit are `success` before any publish step.
- [ ] S-6 Publish summary (R-6, R-7): the pipeline's prepared candidate fetched from a non-shallow clone; `a2a/sprint-282/publish-summary.md` records the intended release sha (= the merge commit), the candidate's `merge_sha` (must equal it), the printed digest and the lead-recomputed digest (`sha256_portable` over the fetched bytes; must be equal), the tag `v2.0.0-rc.9`, the CHANGELOG heading, the beads' states, every class-S row written, and R-1 … R-5 ticked with evidence links.
- [ ] S-7 Publish (R-8): `post-merge-orchestrator.sh --publish <candidate> --approve-sha256 <digest>` from the non-shallow clone; then verify `git rev-parse v2.0.0-rc.9^{commit}` equals the intended release sha, `git ls-remote --tags origin v2.0.0-rc.9` matches the local tag object, `git merge-base --is-ancestor v2.0.0-rc.9 origin/main`, the release page exists with its target commit equal to the peeled tag and every listed asset digest equal to what the candidate recorded; install smoke test from a scratch directory (`git clone --depth 1 --branch v2.0.0-rc.9` → `check-loa.sh` and the kf-surface hook succeed). Any mismatch → the written rollback (S-9), never a silent retry.
- [ ] S-8 Archive and close: `ship-3*` (`archive-cycle.sh --cycle 137 --retention 50`, housekeeping merge classified `housekeeping`); `ship-4` (JACKED_OUT, parked `.run/*.cycle-137.jacked-out.json`, `main`); beads' provisional close reasons updated with the merged sha; ledger cycle archived; `e2e.md` part 2: G-5 (check runs on the merged head; Bridgebuilder summary; record and archive shas), G-6 (tag + release URL; ancestry and identity checks; smoke test), spend.
- [ ] S-9 Rollback (written here before S-7 runs): revert the merge commit on `main` with manifests regenerated (version pins return with it); mark the GitHub release as a withdrawn pre-release and leave the tag; the record branch and archive stay as history with a note; reopen the beads; a DEC row records the withdrawal and the cause.

> Sources: prd.md § FR-8, § Release predicate, § Authorization; sdd.md § 5.8, § 6; `~/.cache/loa/cycle-135/ship/*.sh`

---

## Appendix

### Goals (from prd.md § Goals & Success Metrics)

| Goal | Criterion | Evidence |
|---|---|---|
| G-1 | Review `All good` and audit `APPROVED` on the loop | `a2a/sprint-281/{engineer-feedback,auditor-sprint-feedback}.md`, `COMPLETED` |
| G-2 | Six beads closed (or one deferred by DEC row) | `br show` close reasons naming commit + test; `a2a/sprint-282/e2e.md` |
| G-3 | Gains hold; guard green | `rebaseline.sh` table: no touched row above 110 % of its final-table mean; `perf-spawn-budget.bats` 6/6 (7/7 after Task 2.4) |
| G-4 | Full suite green modulo the three named KF-034 tests | the TAP summary on the final heads under R-4 |
| G-5 | PR, Bridgebuilder, merge, record, archive | § Ship S-1 … S-5, S-8 |
| G-6 | `v2.0.0-rc.9` published | § Ship S-6, S-7 |

### Flatline sprint review dispositions

Review: `flatline-orchestrator.sh --doc grimoires/loa/sprint.md --phase sprint --budget 300` on sprint plan 1.0 (commit b49e6310d): 7 blockers, 40 medium items (`~/.cache/loa/cycle-137/logs/flatline-sprint.out`).

| # | Finding (location) | Disposition in 1.1 |
|---|---|---|
| B1 | one validated result per path; fail-closed batch (Task 2.6) | Task 2.6 and the FR-7 AC row: JSON records by index, exactly one per path, missing/duplicate/malformed/process failure → FAILED in the wrapper and in `loa-status.sh` |
| B2 | DEC-row classes; which halt (header) | Header § Decision-row classes: class S (self-confirmable under the operator's instruction) and class H (halt); Task 2.9 → § Ship refuses while a class-H row or blocking finding is open |
| B3 | one terminal rule for blocking findings | Header § Terminal rule; § Ship S-2; waiver format for non-blocking findings |
| B4 | release sha, peeled tag, remote identity, asset digests | § Ship S-6, S-7 |
| B5, B6 | cache temp safety; cache trust boundary | Task 2.2 (uid-owned, non-group/world-writable real directories; `mktemp`; `-L` re-checks; row validation; fixtures); Security Considerations |
| B7, M1 | approvals bound to SHAs; gates re-run after shipping changes | `reviewed_head` in Sprint 1 and 2 ACs and Tasks 1.1, 1.2, 2.8; § Ship S-2 (verify-only audit, parity harness, CI mirror and secret scan re-run on the new head); S-3 compares `reviewed_head` with the PR head |
| M2 | KF-034 exact names | Sprint 1 G-4 AC and Sprint 2 full-suite AC cite PRD R-4 |
| M3 | non-tautological trust-store check | Task 2.6: every path under an INVALID store FAILs with `[TRUST-STORE-INVALID]`; `loa-status.sh` invalid count equal old and new |
| M4 | Sprint 2 engineer report | Deliverable `a2a/sprint-282/reviewer.md`, written in Task 2.7 before 2.8 |
| M5 | check-run semantics | § Ship S-3 (conclusions; PR head vs merge commit; S-5 for main) |
| M6, M35 | HALT checkpoint; ship safe points | Header § HALT checkpoint |
| M7, M18 | Bridgebuilder completion rule; unreachable exit | Header bounded-loop exits (retry, model fallback, degraded only with no blocking finding; round 2 open blocking → HALT); § Ship S-2; external dependency added |
| M8, M39 | bead rollback = red + fix; loop-pass revert consequences | Risks → Rollback; Sprint 1 AC (revert row excluded from G-3, harness re-run) |
| M9 | release rollback | § Ship S-9 |
| M10, M11 | cache trust boundary; source change mid-run | Task 2.2 (snapshot; fixtures) |
| M12, M31 | same-second rewrite; ns mtime | Task 2.3 (`%.9Y`/`%.9Z` + ctime; same-second fixture; 1 s filesystems UNVERIFIED) |
| M13, M14 | batch protocol; mutation fixture | Task 2.6 |
| M15, M38 | measurement protocol; inconclusive handling | PRD § NFR Performance referenced in Tasks 2.3, 2.7 and Sprint 1 G-3 (serial, idle host); inconclusive → repeat with 30 runs, else "not met" recorded |
| M16, M29 | ship outside the gated sprint; split AC rows | § Ship section S-1 … S-9; Sprint 2 AC trimmed to the gated work |
| M17 | circuit-breaker exit | Header bounded-loop exits |
| M19 | key captures the pipeline | Task 2.2: `v1:` prefix adjacent to the `s` filter with a bats coupling case (SDD D-5.1) |
| M20 | implementer spend metering | Header § Spend (not metered; bounded by the time budget; meter checkpoints) |
| M21, M32 | external artefacts verified; briefs preserved | Task 1.0 (sha256 in e2e), Task 2.0 (`prep.md`, `a2a/sprint-282/briefs/`) |
| M22 | bead closure provisional until merge | Task 2.7; § Ship S-8 |
| M23 | time budget and slip order | Header § Time budget |
| M24 | gate set aligned across sprints | Sprint 1 AC adds the two lint checks |
| M25 | mawk in the toolchain | Task 2.1 and dependencies: every awk present on the host, absent ones named |
| M26 | `profiles.yaml` validators and profile-lib callers | Task 2.4; `prep.md` lists the sourcers and bats files |
| M27 | 2.7 after Sprint 1 COMPLETED; worktrees from its head; re-brief rule | Dependencies; Task 2.0 |
| M28 | CHANGELOG handling for Sprint 1 | Task 1.1 |
| M30 | yq count on the success path; command measured | FR-3 AC row; Task 2.3 |
| M33 | shared-file landing mechanics | Task 2.7 landing order; D's worktree reset onto B's fix |
| M34 | live KF shape-C count | Sprint 2 AC: 0 today (grep recorded), criterion stands with the fallback wording |
| M36 | structural anchor for the loa-status loop | Task 2.0 verifies anchors; Task 2.6 and D's allowlist name the function, not lines |
| M37 | Task 2.5 single commit, exempt from red/fix | Task 2.5; Sprint 2 AC |
| M40 | checks on the merge commit; CI mirror and secret scan after the last fix | § Ship S-2, S-5 |
| Declined | — | none |

> Sources: `~/.cache/loa/cycle-137/logs/flatline-sprint.out`; prd.md 1.1 Appendix C; sdd.md 1.1 § 11.F
