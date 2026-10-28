# Sprint 282 Review Feedback (round 2)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-28
**Sprint Reference:** grimoires/loa/sprint.md (1.1, Sprint 2 — global 282, cycle-137)
**Implementation Report:** grimoires/loa/a2a/sprint-282/reviewer.md (+ reports/{a,b,c,d}.md); round 1: `engineer-feedback-r1.md`
**reviewed_head:** c31b9e03c (the round-1 fix pair 57e38f8c0 → c31b9e03c on top of the round-1 head 2306d7728)

---

## Overall Assessment

Round 1 required one change: the agy opt-in memo could keep a revoked `true` when a same-size rewrite happened within one whole-second `stat` tick. The fix pair landed red-first (AGC-33 → `_agy_opt_in_node_memo` never memoises a file whose mtime second is the current second), `red-test-check.sh` VERIFIED it, the covering suites are 50/50, parity for `loa-status` and `run-preflight` old-vs-new is identical and the live config is still read once per shell. Round 2 took the fix diff alone to the cross-model dissent (two voices, 2/2 succeeded) and both voices found something real in the pair itself: the rule covers mtime but not ctime, although ctime is a key component with the same whole-second precision (a permission change within the current second can leave a now world-writable config cached as on — the untrusted-config rule says it must read off); and the new test's part 2 recomputes its aged stamp per `stat` call, so a clock tick between its two reads fails it — a flaky gate test. Both are one-line fixes with deterministic red tests, and the four advisories (a one-second margin for coarse-clock stamp lag, the clock source order, a comment sentence, AGC-28's weakened assertion) are cheap enough to land in the same fix round. The rest of the sprint is unchanged since round 1 and is not re-litigated here.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Correctness — the current-second rule ignores ctime

- **MEDIUM** (confidence: high) `.claude/scripts/lib/agy-gate-lib.sh:236-243` — the round-1 rule extracts the mtime second only; ctime (the 5th key field, whole seconds on the BSD branch) is not compared with the clock. Failure: when an aged `agy_opt_in: true` config is chmod'ed to 0600 and read in second S and then chmod'ed to 0666 in the same second, then every later `agy_opted_in` in that shell returns the cached true although others can now write the file and the untrusted-config rule should read it off (DISS-001, primary voice).
**File:** `.claude/scripts/lib/agy-gate-lib.sh:236-243`
**Issue:** the key's identity has two time components and the guard checks one of them.
**Why This Matters:** the permission rule (r251-5 U1) exists so that a config others can write never opts the run in; the memo must not outlive a permission change any more than a content change. Precondition is narrow (two permission changes within one second while a planner runs in the same shell), hence MEDIUM, but it is a hole in exactly the rule the round-1 fix claimed.
**Required Fix:** extract the ctime second as well and read uncached when either mtime or ctime is at or after the clock; red test first with the whole-second shim printing an aged mtime and a current ctime, chmod 0600 → read → chmod 0666 → the second call must read off, two node reads.
**Reference:** CWE-367; DEC-1132.

### 2. Test reliability — AGC-33 part 2 is flaky by construction

- **MEDIUM** (confidence: high) `tests/unit/agy-gate-conformance.bats:719-724` — the aged stamp is computed inside the shim at every `stat` call (`now - SHIM_AGE`), so the two `agy_opted_in` calls can see two different whole seconds. Failure: when the wall clock ticks between the two reads then the memo key changes and the test fails with "node reads for an aged file: 2 (expected 1)", a per-run failure probability roughly equal to the gap length in seconds on a loaded CI runner (DISS-C-001, companion voice).
**Required Fix:** freeze the stamp once in the test (export it before the two calls; the shim prints the exported value for both time fields), so the key is deterministic whatever the clock does.

---

## Observations

### 1. Coarse-clock stamp lag (adopt in the fix round)

- **LOW** (confidence: medium) `.claude/scripts/lib/agy-gate-lib.sh:241` — the comparison is `mtime >= now` with the fine clock; file stamps come from the kernel's coarse clock. Failure: when a write lands in the first milliseconds of second S+1 while the coarse clock still reads S then the file looks aged at once and a same-size rewrite stamped S within the lag is served from the memo (DISS-C-002). A one-second margin (`>= now - 1`) closes it for one extra second of uncached reads after a write.

### 2. Clock source order (adopt in the fix round)

- **LOW** (confidence: high) `.claude/scripts/lib/agy-gate-lib.sh:237-240` — `EPOCHSECONDS` is tried first; on bash < 5 it is a plain variable and an exported stale or future value would be believed. Failure: when a bash 4 host inherits a future `EPOCHSECONDS` from its environment then every file looks aged and the whole-second window reopens (DISS-C-003). `builtin printf '%(%s)T' -1` (bash 4.2+, a builtin) first, then `date +%s`, removes the ambient variable from the rule.

### 3. Comment completeness (adopt in the fix round)

- **LOW** (confidence: high) `.claude/scripts/lib/agy-gate-lib.sh:231-235` — the residual recorded in DEC-1132 (a filesystem server clock running behind the host stamps a fresh write as already past) is not in the function comment. Failure: when an operator on such a filesystem reads the comment's promise then they expect a same-size revocation to be seen within the lag, which it is not (DISS-C-004).

### 4. AGC-28's first half now passes for the wrong reason (adopt in the fix round)

- **LOW** (confidence: high) `tests/unit/agy-gate-conformance.bats:675-684` — the three stamps `t`, `t+1`, `t+2` are all at or after the clock, so every call reads uncached and the "three reads" assertion no longer pins three key misses. Failure: when a regression drops mtime from the key then AGC-28's first half still passes because no call was ever served from the memo (DISS-C-005). Age the base stamp by 60 s and add a fourth call without a re-touch asserting the count stays at three.

### 5. Carried from round 1, unchanged

- **MEDIUM** (confidence: medium) `tests/unit/perf-spawn-budget.bats:140-169` — the grimoire-index target measures a cache MISS only. Failure: when a later edit adds a spawn to `_gi_dec_read` or the hit branch of `emit_decisions` then the guard passes while every real warm run pays it. Bead bd-5v1oa.
- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-282/reports/b.md:1-6` — implementer B's report is the lead's reconstruction. Failure: when B's own hyperfine table and config-matrix parity are needed then only the lead's measurement and parity and the VERIFIED red-test-checks stand in.
- **LOW** (confidence: medium) `.claude/scripts/lib/profile-lib.sh:248-256` — `__LOA_PL_ABSENT__` joins the pre-existing sentinel class. Failure: when a config value literally equals a sentinel then `loa_knob` prints the fallback instead of the value; pre-existing class, not a regression.
- **LOW** (confidence: high) `.claude/scripts/grimoire-index.sh:263-271` — a uid-owned group-writable `.run` or `.run/perf-cache` is tightened with `chmod go-w` on the first index run (DEC-1126). Failure: when a group member relied on writing into the user's `.run` then that permission is gone after the next run; documented in the CHANGELOG and release notes; bd-20bh1.
- **LOW** (confidence: high) `tests/unit/adversarial-review-companion.bats:1681` — CMP-55 keeps its 300 s hold (bd-rq6gk); `setup_file` under `--jobs` UNVERIFIED live (DEC-1131). Failure: when the reaper regresses on the path CMP-55 exercises then CMP-55 still passes and only CMP-14, CMP-30 and CMP-48 can turn red.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty for this run and the named sidecar `adversarial-rejected-review.jsonl` gained no rows.

---

## Cross-Model Observations

`adversarial-review.sh --type review --sprint-id sprint-282 --diff-file <code-only diff 8d63417b0..c31b9e03c over agy-gate-lib.sh and agy-gate-conformance.bats, 5.3 KB> --context-file reviewer-concerns-r2.md --budget 200 --json` (run 2 of the sprint's ≤ 3). Envelope: status `reviewed`; `verdict_quality` 2/2 voices (codex-headless gpt-5.5-pro, claude-headless), consensus, chain_health ok, confidence floor high; cost 0. Six findings: primary 1 BLOCKING (→ Change 1, triaged CONFIRMED, graded MEDIUM for its narrow precondition); companion 1 BLOCKING (→ Change 2, CONFIRMED — the per-call stamp is visibly non-deterministic) and 4 ADVISORY (→ Observations 1–4, all adopted). One primary finding named only the deprecated `failure_mode` key (alias of `failure_scenario`, removed in 2.1.0) — accepted via the alias. Round 1's companion timeout (KF-037 class) did not recur: the host was lighter (one unit suite instead of a suite plus eight red-test-check worktrees).

---

## Acceptance Criteria Check

Deferred to round 3 (every row other than the FR-3 memo row is evidenced in `reviewer.md` § AC Verification; the FR-3 row is re-checked on the fixed head).

---

## Next Steps

1. Test-only commit: AGC-34 (ctime window, red), AGC-35 (one-second-old stamp inside the margin, red), AGC-33 part 2 frozen stamp, AGC-28 aged base + fourth-call hit; then the lib fix (ctime second, one-second margin, `builtin printf` first then `date`, comment sentence); `agy-gate-conformance.bats` + `loa-status-providers.bats`, the loa-status / run-preflight parity, manifests under the marker, `red-test-check.sh`.
2. `/review-sprint sprint-2` round 3 on the new head by the lead without a third dissent run (runs 1 and 2 are spent on the review; run 3 is the audit's and will see the final head) — recorded as a class-S decision.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":8},"excluded":0,"sprint_id":"sprint-282","ts":"2026-10-28T06:20:00Z"} -->
