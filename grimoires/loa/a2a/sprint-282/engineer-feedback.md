All good

Sprint 282 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 282 Review Feedback (round 3 — final)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-28
**Sprint Reference:** grimoires/loa/sprint.md (1.1, Sprint 2 — global 282, cycle-137)
**Implementation Report:** grimoires/loa/a2a/sprint-282/reviewer.md (+ reports/{a,b,c,d}.md); rounds 1 and 2: `engineer-feedback-r1.md`, `engineer-feedback-r2.md`
**reviewed_head:** 03f910129 — the Sprint 282 landing 980013b87 … 55f82c534, the CHANGELOG block 1564b1977, the sprint-plan ticks 4994ececc, the rc.9 release files 8d63417b0, the SDD 1.2 amendment 2306d7728 (docs-only), the review fixes (round 1 pair 57e38f8c0 → c31b9e03c, round 2 pair c69059546 → c31089280; c31089280 is the last commit touching a System Zone file), the review-rounds docs commit 2832bacce, and the audit's test-only strengthening 03f910129 (round 4 below).

**PR head binding (S-3):** the PR #1309 head 3215c141f = 03f910129 + two `grimoires/`-only commits (e4dacaec9 gate ticks + DEC rows, 3215c141f ledger) — `git diff --stat 03f910129..3215c141f` touches `grimoires/loa/{sprint.md,decisions.yaml,ledger.json}` (116 insertions, 5 deletions) and no file under `.claude/`, `tests/`, `.github/` or the release files; D-1.1 docs-only exemption, verified by the lead before the merge. This verdict therefore binds to the PR head 3215c141f with 03f910129 as the last reviewed code change.

**Round 4 (verify-only, lead):** the audit's dissent asked for AGC-29 and AGC-31 to prove a populated memo before each mutation and to forge the real key with a control (DISS-C-003), and for the FIFO / hard-link cache properties to be pinned (DISS-C-006, refuted by probe). 03f910129 touches `tests/unit/agy-gate-conformance.bats` and `tests/unit/grimoire-index.bats` only — I read the diff (no lib hunk, no fixture outside BATS temp directories, the settle helper reused), ran both files (36/36, 48/48) and re-bound this verdict to it (DEC-1138); the observations and counts below are unchanged.

---

## Overall Assessment

Six beads, seven red/fix pairs and one test-only commit, each landed by the lead from an implementer's patch after the red run failed for exactly the new cases and the fix run went green with manifests regenerated. I read every patch before landing it and re-derived old-vs-new parity on the live tree myself (KF hook, grimoire-index in all modes cold and warm, loa-status human and JSON, run-preflight, the karpathy hook — all identical), re-ran the covering suites (273/273, security pytest 40 passed), and ran `red-test-check.sh` against every red commit on the reviewed head: all ten VERIFIED (nine bats, one pytest). The two new trust surfaces hold: the decisions cache is read and written only inside a uid-owned, non-group-writable directory (tightened when we own it, refused when we do not), validated row by row; `verify-chains` keeps the trust-store check per path through the untouched `_check_trust_store` and fails closed at both layers (a six-schedule store-mutation test equals two oracles). The FR-6 companion-file target was unreachable by test edits and is recorded as the measured floor by a class-S decision row written before this review (DEC-1130), with a negative control per shortened hold.

Three rounds. Round 1 (`engineer-feedback-r1.md`, CHANGES_REQUIRED) took the whole code diff to the cross-model dissent: one BLOCKING finding, the agy opt-in memo keeping a revoked `true` across a same-size rewrite within one whole-second `stat` tick — fixed red-first (AGC-33 → `_agy_opt_in_node_memo` reads uncached while the file's mtime is the current second), DEC-1132. Round 2 (`engineer-feedback-r2.md`, CHANGES_REQUIRED) took the fix diff alone to the dissent (2/2 voices): the rule ignored ctime (a chmod within the second could keep a now world-writable config memoised as on) and the new test's aged stamp was recomputed per `stat` call (flaky across a clock tick), plus four advisories — all fixed red-first (AGC-34, AGC-35; AGC-33 frozen; AGC-28 aged with the hit pinned; AGC-36 pins each key component; ctime + a one-second margin; `builtin printf %(%s)T` before `date`, never `EPOCHSECONDS`), DEC-1133. Round 3 is my own re-check of that pair without a third dissent run (the sprint's third run is the audit's, on the full diff of this head — DEC-1134): `red-test-check.sh` VERIFIED for both pairs, `agy-gate-conformance.bats` 36/36 and `loa-status-providers.bats` 17/17, parity for `loa-status` (human/stderr/rc/JSON) and `run-preflight` (human/stderr/rc/--json) identical old 747b5db0d vs new, the live config still read once for two calls, manifests regenerated under the marker, `check-loa.sh` All checks passed. The full `tests/unit` suite on 8d63417b0: 7309 planned, 7306 ok, 3 not ok = exactly the KF-034 allowed-failure list, 135 skipped — the two skips not on the Sprint 281 head are this sprint's own host-conditional awk tests (DEC-1135); the run on c31089280 is in progress and goes to `e2e.md`.

**Verdict:** APPROVED

---

## Observations

### 1. Spawn-budget coverage of the cache hit path

- **MEDIUM** (confidence: medium) `tests/unit/perf-spawn-budget.bats:140-169` — the grimoire-index target measures a cache MISS only (its fixture `.run` is fresh every run), so the warm-path spawn count — the production hot path once the cache exists — has no budget. Failure: when a later edit adds a spawn to `_gi_dec_read` or the hit branch of `emit_decisions` then the guard passes while every real `grimoire-index` run pays it.
**File:** `tests/unit/perf-spawn-budget.bats:140-169`
**Suggestion:** a second trace of the same fixture after the first (warm) with its own measured budget, in the file's style → bead bd-5v1oa.
**Benefit:** the guard watches the path the loop optimised, not only the one-off miss.

### 2. Implementer B's report never arrived

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-282/reports/b.md:1-6` — B delivered six patches and fixtures, went idle and ignored two requests to write its report; `reports/b.md` is the lead's reconstruction. Failure: when B's own same-session hyperfine table and config-matrix parity run are needed then only the lead's measurement (−104 ms) and parity (loa-status, run-preflight, karpathy) and the VERIFIED red-test-checks for 2.3a/2.3b/2.4 stand in, so the acceptance rests on lead evidence for those two items.
**Suggestion:** none for this sprint; the brief's "write REPORT.md with a Bash heredoc" line (A, C, D complied) goes into the COMMON brief for the next cycle.

### 3. Sentinel strings in `loa_knob`

- **LOW** (confidence: medium) `.claude/scripts/lib/profile-lib.sh:248-256` — `__LOA_PL_ABSENT__` joins the pre-existing `__LOA_PL_MISS__` / `__LOA_PL_STALE__` sentinels returned through `jq -r`. Failure: when a config value is literally equal to a sentinel string then `loa_knob` reads it as the sentinel and prints the fallback instead of the value — the same pre-existing class as the other two, so not a regression; a JSON-tagged result would remove the class.

### 4. A framework script now changes a directory mode

- **LOW** (confidence: high) `.claude/scripts/grimoire-index.sh:263-271` — a uid-owned `.run` or `.run/perf-cache` with a group/other write bit is tightened (`chmod go-w`) on the first index run (DEC-1126, SDD 1.2). Failure: when a group member relied on writing into the user's `.run` then that permission is gone after the next `grimoire-index` run; the live checkout's `.run/perf-cache` went 775 → 755 during the re-baseline. Documented in the CHANGELOG and the release notes; bd-20bh1 fixes the creator (zone-write-guard) so the tightening becomes a no-op on fresh mounts.

### 5. Test-only residuals recorded by the implementer

- **LOW** (confidence: high) `tests/unit/adversarial-review-companion.bats:1681` — CMP-55 keeps its 300 s hold because no break of the hold or the reaper fails it (the test never asserts a reap happened). Failure: when the reaper regresses on the path CMP-55 exercises then CMP-55 still passes and only CMP-14, CMP-30 and CMP-48 can turn red. Bead bd-rq6gk (assert the reap attempt; raise the sleeper margin). `--jobs` behaviour of the new `setup_file` is UNVERIFIED live (GNU parallel absent) — the bats 1.13.0 source reasoning is recorded (DEC-1131).

### 6. The agy conformance file waits for its fixtures to settle

- **LOW** (confidence: high) `tests/unit/agy-gate-conformance.bats:660-665` — `_agc_settle` waits until the clock is two seconds past a real fixture's ctime because a touch or chmod stamps ctime now and the lib never memoises a file within one second of the clock. Failure: when the suite runs on a slow or loaded host then AGC-27 and AGC-28 add up to about six seconds of wall time between them, against a file that ran in under two seconds before this sprint; the frozen-stamp shim tests (AGC-33 … AGC-36) carry the deterministic key coverage at no wait.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty in both envelopes (`adversarial-review-r1.json`, `adversarial-review.json` = round 2) and the sidecars `adversarial-rejected-review-r1.jsonl` and `adversarial-rejected-review.jsonl` have zero rows; round 3 ran no dissent (DEC-1134).

---

## Cross-Model Observations

Round 1: `adversarial-review.sh --type review --sprint-id sprint-282 --diff-file <code-only diff 747b5db0d...8d63417b0, 156 KB> --context-file reviewer-concerns.md --budget 900`; primary gpt-5.5-pro via codex-headless answered, companion claude-headless FAILED (`timeout` after 910 s while the host ran the full unit suite and eight red-test-check worktrees — KF-037 class, a dropped voice, non-blocking for a review); one BLOCKING finding → fixed. Round 2: `--diff-file <code-only diff 8d63417b0..c31b9e03c, 5.3 KB> --context-file reviewer-concerns-r2.md --budget 200`; `verdict_quality` 2/2 voices (codex-headless gpt-5.5-pro, claude-headless), consensus, chain_health ok, confidence floor high; six findings (primary 1 BLOCKING, companion 1 BLOCKING + 4 ADVISORY) → all fixed or adopted; one primary finding used the deprecated `failure_mode` key (alias of `failure_scenario`, removed in 2.1.0) and was accepted via the alias. Cost 0 in both runs (subscription routes). Round 3: no run — the sprint's third dissent is the audit's (DEC-1134).

---

## Acceptance Criteria Check

### Sprint 2 (global 282) — sprint.md 1.1 § Acceptance Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-2 AC rows all green | Pass | 9 red cases → green (980013b87 → 2944f4b55); live file identical in the implementer's and the lead's mirrors; drift guard; mawk + busybox byte-identical; BWK UNVERIFIED (bd-aceil); red-test-check VERIFIED |
| FR-3 AC rows all green | Pass (lead evidence) | LSP-9a pins one yq on the live config; lead hyperfine −104 ms; lead parity loa-status + run-preflight identical (re-run after both review fixes); AGC-27 … AGC-36 memo oracles incl. the whole-second shim (same-second rewrite, chmod within the second, one-second-old stamp, per-component key misses); red-test-check VERIFIED ×4 (2.3a, 2.3b, r1, r2) |
| FR-4 AC rows all green | Pass | PL-20 … PL-25 green; karpathy spawn-budget target; lead parity of the hook over three payloads incl. the state dir; the full pass-19 matrix UNVERIFIED-BY-IMPLEMENTER; red-test-check VERIFIED |
| FR-5 AC rows all green | Pass with two recorded readings | 46 cases incl. every hostile condition; warm 310 ms (≤ 650), cold +24 ms paired (≤ +40); live warm 826 → 196 ms; "mid-run rewrite caches nothing" read as key-consistent cache (DEC-1125); group-writable uid-owned dir tightened, not ignored (DEC-1126); budgets with reasons; red-test-check VERIFIED ×2 |
| FR-6 AC rows green or the floor row | Pass via DEC-1130 | TAP set identical ×7; negative control per shortened hold; corpus once with status capture; floor 667 s median recorded before the review; CMP-55 exempted (DEC-1131, bd-rq6gk) |
| FR-7 AC rows all green ((a) implemented) | Pass | 18/18 bats, 15/15 pytest; six mutation schedules equal two oracles; 140/141 artefacts identical (the one is the intended `--help` addition); −1.15 s on r5; python3 5 → 1; protected functions have no hunk (diff checked again at this head: docstring line, `Sequence` import, `__all__` entry, the new function); red-test-check VERIFIED ×2 (bats, pytest) |
| Red commits fail only their own cases; fix commits green; Task 2.5 single commit; manifests regenerated; lint/check-loa/validate/budget green at every fix commit and the final head | Pass | `red-test-check.sh` VERIFIED for all ten red commits (`~/.cache/loa/cycle-137/logs/rtc-282*.log`, `rtc-282-r1fix.json`, `rtc-282-r2fix.json`); every fix run green; manifests regenerated under the marker with `check-loa.sh` All checks passed each time (incl. c31b9e03c and c31089280); the release-files commit passed check-loa, semver (next 2.0.0-rc.9), README sync and the prompt budget |
| `reviewer.md` before the review; verdicts with `reviewed_head` = the merged head (ship files committed) | Pass | this file names c31089280; the release files are in 8d63417b0; the audit names the same head |
| Full `tests/unit` TAP under R-4 + whole-head parity gate | Parity gate Pass; full TAP → `e2e.md` | five entry points identical old 747b5db0d vs new, re-run after each review fix for the two agy callers; 8d63417b0: 7306 ok / 3 not ok (the KF-034 list) / 135 skipped (two new host-conditional skips, DEC-1135); the run on c31089280 (`~/.cache/loa/cycle-137/logs/unit-c31089280.tap`) is compared by skip NAME and recorded in `e2e.md` before the audit closes the sprint |
| Live KF shape-C count and D-2.2 | Pass | 1 line (KF-008); shape C scoped inside `fieldval` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (every patch read before landing; the only token-shaped strings are pre-existing fixture probes)
- [x] Input validation and sanitisation present — the decisions-cache reader validates header, count, fields and alphabet before serving a row; the KF `san()`/`SAN_AWK` twins unchanged in effect; `verify-chains` records validated by index with a fail-closed default; every stat-derived number regex-gated before arithmetic
- [x] Trust boundaries explicit and tested — uid-owned non-group-writable directories (tightened when owned, refused otherwise; stat and chmod shims cover the foreign and untightenable cases); `_check_trust_store` untouched and exercised per path under a store-mutation schedule; the agy consent flag re-read on any content, permission or path change and within one second of any stamp
- [x] No new eval, no `source` of data, no `bash -c` with interpolated data (the companion shim's `bash -c '… sleep "$1"'` passes the knob as an argument, not text)
- [x] Dependencies unchanged (jq ≥ 1.6 for `$ARGS`, already required elsewhere; CI's pytest list gains the new file)
- [x] Error messages unchanged on every degraded path except the two intended readings recorded by DEC-1124 and DEC-1128
- [x] Memo variables reset at load and never seeded from the environment (agy); the clock is a builtin, not an inheritable variable; the test knob is an unexported shell variable

---

## Code Quality Summary

**Strengths:**
- Every change is a fast path with a verbatim fallback or a validated cache; every red commit fails for exactly its cases (red-test-check VERIFIED ×10).
- Implementer reports (A, C, D) record their judgment calls, deviations and UNVERIFIED items explicitly; the lead turned each into a decision row before the gate.
- The guard tests pin the properties that matter (one yq, no yq on the warm karpathy path, one python3, cache hit by trace, each memo key component on its own).

**Areas for Improvement:**
- The spawn-budget guard should also watch the cache hit path (Observation 1).
- Complexity: `emit_decisions` grew by five helpers (~110 lines in total, each ≤ 30 lines); `audit_verify_chains` wrapper ~55 lines; `_agy_opt_in_node_memo` ~40 lines incl. comment; nesting ≤ 3; no duplicate blocks. Over-engineering pass: `Lean already. Ship.`

---

## Next Steps

1. `/audit-sprint sprint-2` on 03f910129 (the sprint's third dissent run ran on the full code diff 747b5db0d..c31089280; the test-only strengthening it asked for is 03f910129).
2. On `APPROVED`: `COMPLETED`, ledger 282 `completed`, `e2e.md` part 1 (incl. the final-head full-suite TAP compared by skip name and the idle-host re-baseline), then the Ship section.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":5},"excluded":0,"sprint_id":"sprint-282","ts":"2026-10-28T07:40:00Z"} -->
