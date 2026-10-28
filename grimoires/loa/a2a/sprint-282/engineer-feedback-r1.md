# Sprint 282 Review Feedback (round 1)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-28
**Sprint Reference:** grimoires/loa/sprint.md (1.1, Sprint 2 — global 282, cycle-137)
**Implementation Report:** grimoires/loa/a2a/sprint-282/reviewer.md (+ reports/{a,b,c,d}.md)
**reviewed_head:** 2306d7728 (code head 8d63417b0; the SDD 1.2 amendment after it is docs-only)

---

## Overall Assessment

Six beads, seven red/fix pairs and one test-only commit; every red commit VERIFIED by `red-test-check.sh` against the reviewed head (seven bats runs, one pytest run); lead parity on the live tree identical for the KF hook, grimoire-index (all modes, cold and warm), loa-status, run-preflight and the karpathy hook; covering suites 273/273 and the security pytest green. One finding from the cross-model dissent is real and blocking for a supported platform: the agy opt-in memo's BSD `stat` branch keys on whole-second mtime/ctime, so a same-size in-place rewrite of `agy_opt_in` within the same second — on macOS, or on any filesystem with one-second timestamps under the GNU branch — leaves a stale `true` in the shell for the rest of the process. Implementer B documented the window; the SDD's own risk row said the memo must "keep the 'config cannot change mid-run' assumption honest", and the Flatline sprint review (M12/M31) asked for exactly this case. It is a one-function fix with a deterministic red test (a whole-second `stat` shim), so it lands in this sprint before round 2.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Correctness — stale agy opt-in under whole-second file identity

- **HIGH** (confidence: high) `.claude/scripts/lib/agy-gate-lib.sh:227-240` — `_agy_opt_in_node_memo` memoises on `<cfg>|dev:ino:size:mtime:ctime|PATH`; the BSD `stat -f '%d:%i:%z:%m:%c'` branch (and the GNU branch on a one-second-granularity filesystem) yields whole seconds, so a same-length in-place rewrite within the same second keeps every key component. Failure: when a planner caches `agy_opt_in: true ` and the operator rewrites it to `agy_opt_in: false` in the same second, every later `agy_opted_in` call in that shell returns true — the agy route stays planned after the opt-in was revoked, violating the rule that only the current explicit boolean true enables it (DISS-001, primary voice).
**File:** `.claude/scripts/lib/agy-gate-lib.sh:227-240`
**Issue:** the identity key has no sub-second component on BSD stat, and the memo trusts it anyway.
**Why This Matters:** the agy route sends the prompt on the CLI's argv (readable by local users); a stale opt-in is a consent violation, not a performance bug. macOS is a supported host (bash 3.2 / BSD stat), so the window is real there.
**Required Fix:** do not memoise while the file's mtime second equals the current second (`$EPOCHSECONDS`, else `printf '%(%s)T' -1`, else `date +%s`): a file modified in the current second is re-read every time until the clock moves on, which closes the window whatever the stat precision (a rewrite in a later second changes mtime and misses as today). Red test first in `tests/unit/agy-gate-conformance.bats` with a `stat` shim that prints whole seconds equal to the current second: `true` → same-length `false` rewrite → `agy_opted_in` must return false; and a shim printing an older second must still memoise (one read for two calls), so the fix does not disable the memo.
**Reference:** CWE-367 (time-of-check/time-of-use), the SDD § 9 memo risk row, DEC-1127.

---

## Observations

### 1. Spawn-budget coverage of the cache hit path

- **MEDIUM** (confidence: medium) `tests/unit/perf-spawn-budget.bats:140-169` — the grimoire-index target measures a cache MISS only (its fixture `.run` is fresh every run), so the warm-path spawn count — the production hot path once the cache exists — has no budget. Failure: a later edit that adds a spawn to `_gi_dec_read` or the hit branch of `emit_decisions` passes the guard while every real `grimoire-index` run pays it. Bead bd-5v1oa.

### 2. Implementer B's report never arrived

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-282/reports/b.md:1-6` — B delivered six patches and fixtures, went idle and ignored two requests to write its report; `reports/b.md` is the lead's reconstruction. Failure: B's own same-session hyperfine table and config-matrix parity run are UNVERIFIED-BY-IMPLEMENTER; the lead's measurement (−104 ms) and parity (loa-status, run-preflight, karpathy) and the VERIFIED red-test-checks stand in.

### 3. Sentinel strings in `loa_knob`

- **LOW** (confidence: medium) `.claude/scripts/lib/profile-lib.sh:248-256` — `__LOA_PL_ABSENT__` joins the pre-existing `__LOA_PL_MISS__` / `__LOA_PL_STALE__` sentinels returned through `jq -r`. Failure: when a config value is literally the sentinel string then `loa_knob` reads it as an absent knob and prints the fallback instead of the value; the same pre-existing class as the other two sentinels, not a regression.

### 4. A framework script now changes a directory mode

- **LOW** (confidence: high) `.claude/scripts/grimoire-index.sh:263` — a uid-owned `.run` or `.run/perf-cache` with a group/other write bit is tightened (`chmod go-w`) on the first index run (DEC-1126, SDD 1.2). Failure: when a group member relied on writing into the user's `.run` then that write permission is gone after the next `grimoire-index` run; documented in the CHANGELOG and the release notes, and bd-20bh1 fixes the creator so fresh mounts never need the tightening.

### 5. Test-only residuals

- **LOW** (confidence: high) `tests/unit/adversarial-review-companion.bats:1681` — CMP-55 keeps its 300 s hold because no break fails it (bd-rq6gk); `setup_file` under `--jobs` UNVERIFIED live (GNU parallel absent; DEC-1131). Failure: when the reaper regresses on the path CMP-55 exercises then CMP-55 still passes and only CMP-14, CMP-30 and CMP-48 can turn red, so that path has one fewer sentinel.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Cross-Model Observations

`adversarial-review.sh --type review --sprint-id sprint-282 --diff-file <code-only diff 747b5db0d...8d63417b0 over .claude/{adapters,data,hooks,scripts} .github tests CHANGELOG.md, 156 KB> --context-file reviewer-concerns.md --budget 900`. Envelope: status `reviewed`, primary gpt-5.5-pro answered via codex-headless; companion claude-headless FAILED (`timeout`: `claude -p` timed out after 910 s while the host ran the full unit suite and eight red-test-check worktrees) — a dropped voice, non-blocking for a review (`verdict_quality.status` DEGRADED with one voice); `cost_usd` 0. One finding, BLOCKING → the HIGH above; triaged CONFIRMED (B's own report documented the whole-second window; the fix is bounded).

---

## Acceptance Criteria Check

Deferred to round 2 (every row other than the FR-3 memo row is already evidenced in `reviewer.md` § AC Verification and will be re-checked on the fixed head).

---

## Next Steps

1. Red test + fix for the same-second memo window (lead, red-first), manifests regenerated, `agy-gate-conformance.bats` and the loa-status/run-preflight parity re-run.
2. `/review-sprint sprint-2` round 2 on the new head (dissent on the fix diff; ≤ 3 runs per sprint — this was run 1).

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":4},"excluded":0,"sprint_id":"sprint-282","ts":"2026-10-28T05:50:00Z"} -->
