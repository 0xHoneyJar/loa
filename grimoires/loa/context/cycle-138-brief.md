# cycle-138 brief — hardening follow-ups: the fifteen beads left by cycle-137 and sprint-bug-283

**Operator instruction (verbatim, 2026-10-29):** "please do (1) on my behalf (2) confirmed and then proceed with the next cycle and also (3) is approved" — after the lead's next-steps message that named this cycle as "fix the release robot first (bd-0atxs, as a /bug), harden the older cache (bd-j34zb), then the other 13 follow-up beads". Items (1) and (2) are done (runaway shells killed; DEC-1109 … DEC-1140 confirmed in PR #1312); the `/bug` for the release robot shipped as sprint-bug-283 (PR #1313 → fe52be893). This cycle is the rest.

**Context.** cycle-137 (Sprints 281/282, PR #1309 → a1360dac2, v2.0.0-rc.9) and sprint-bug-283 left fifteen open beads, each filed by a review, audit or Bridgebuilder finding with a severity and an exact code anchor. None is a feature: they are trust-boundary hardening on hooks and libs that run on every tool call, a release-path argv limit, test-coverage gaps the gates found, and two portability verifications. The detailed table (bead, area, origin, suggested sprint) is `grimoires/loa/context/cycle-138-followups.md`.

**Scope — three sprints, no new features:**

1. **Sprint 1 — security and release path:** bd-j34zb (profile-lib `effective-config.json` cache gets the decisions-cache trust boundary and a `mktemp` + `mv -T` writer), bd-qyvju (post-merge release POST / notify bodies off jq argv), bd-hyah6 (loa-status chain summary reports an absent chain file as a third state), bd-20bh1 (zone-write-guard creates `.run/perf-cache` under umask 077).
2. **Sprint 2 — hooks and the KF surface:** bd-yos4s (`KARPATHY_CHECKPOINT_CMD` seam gated or warned), bd-kdzc3 (karpathy trajectory symlink guards), bd-4sikh (KF row cap in the session context), bd-z6gxn (C1 controls in the KF sanitiser), bd-aceil (BWK awk / BSD cut verification and the byte-cap contract — may end as a documented contract if no BWK build is obtainable).
3. **Sprint 3 — tests, guards and one refactor:** bd-7utms (floor descendant clause), bd-y5fy4 (`loa_knob` presence metadata), bd-5v1oa (warm-cache spawn-budget target), bd-rq6gk (CMP-55 reap assertion), bd-3qed8 (`_path_without` skip list), bd-0h7kq (providers dispatch mapping; lowest, deferrable by decision row).

**Ship:** one PR per cycle (DEC-0960 pattern), Bridgebuilder ≤ 2 rounds, merge on green checks on the exact head, record branch, archive. **No release:** the merge prepares an rc.10 candidate that stays unpublished unless the operator asks; promotion rc → 2.0.0 is the operator's call.

**Constraints:** red-first tests; byte-identical old-vs-new output where output exists (mirror parity in real directories, the karpathy hook across the config matrix for bd-j34zb); System Zone writes under the bounded marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); spawn budgets kept (`perf-spawn-budget.bats`); ≤ 3 dissent runs per sprint (the third is the audit's); `br` contract calls untouched; untrusted bodies sanitised at surfacing; no timing-based tests; decisions as class-S rows; NOTES.md (now 46 KiB after the rotation) stays under the guard.

**Non-goals:** new optimisation targets; Flatline, Bridgebuilder or adapter wire-contract changes; quarantining any test; publishing a release.
