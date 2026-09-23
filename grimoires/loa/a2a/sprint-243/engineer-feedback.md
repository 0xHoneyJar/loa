All good

Sprint 3 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 3 (global 243) Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 3: Run preflight and resume
**Implementation Report:** grimoires/loa/a2a/sprint-243/reviewer.md
**Reviewed commit:** `d6ff411a` · cross-model dissent `adversarial-review.json` (gpt-5.5-pro): `status: clean`, 0 findings, 0 rejected

---

## Overall Assessment

The sprint delivers what FR-3 asked for in the shape the SDD drew: one script owns the eight predicates and the skills' prose shrank onto it (run-mode −389 B), the checkpoint is a locked, atomic, beads-validated hint rather than a second source of truth, and the resume line comes from one producer that the SessionStart hook, `/loa` and `workflow-state.sh` all reuse. I read the three new scripts end to end, replayed the fixtures, and probed the seams the tests do not reach: the exact settings command string runs the surface through `hook-guard.sh` and prints the line (a parse-broken hook fails open with a WARN, as designed); a `RUNNING` state without a timestamp is refused as "in progress (? ago)" rather than mis-aged; the live repository gets `/implement sprint-1` from `workflow-state.sh` because its run is fresh, so the new precedence does not hijack a live run. The report's test-first record is candid about the two fixture faults and the P7 pipefail trap, which is the right kind of record. The re-entry proof uses the real `br`, not a stub.

`reviewer.md` §AC Verification is complete with `file:line` evidence for all four criteria.

Complexity: `run-preflight.sh` is ~300 lines of straight-line predicates with one helper per concern; no function exceeds 40 lines; `p6_read` carries the only nesting (depth 3, early `return`s). Lean for eight predicates. Ship.

**Verdict:** APPROVED

---

## Observations

### 1. Predicate scope edges

- **MEDIUM** (confidence: medium) `.claude/scripts/run-preflight.sh:99-107,120-124` — P1 lets `acceptEdits`/`default` pass on the strength of P2, but `check-permissions.sh` reads only `.claude/settings.json` (`check-permissions.sh:19`); a `deny` in `.claude/settings.local.json` or `~/.claude/settings.json` that overlaps the run's tools would still auto-deny unattended. Scenario: local settings deny `Bash(git push:*)`; preflight passes; the run stalls at its first push. Fix belongs in `check-permissions.sh` (merge the three files, honour `deny`) — file as a follow-up bead; the preflight already names its source file so an operator can see what was inspected.
- **LOW** (confidence: high) `.claude/scripts/run-preflight.sh:186-190` — with both flatline stages disabled the P3 detail reads "every configured voice has a credential or CLI hop ()" (verified); say "no flatline stage enabled" instead. Cosmetic, but the empty parenthesis reads like a bug.

### 2. Portability and timeouts

- **LOW** (confidence: high) `.claude/scripts/run-preflight.sh:84-92`, `.claude/hooks/session-start/loa-run-state-surface.sh:37-45` — ages use GNU `date -d`; on BSD `date` the age prints `?` and staleness never triggers (a stale `RUNNING` is then reported as "in progress", still a FAIL; the surface stays silent for it). Consistent with the rest of the repository's GNU assumption; a `gdate` fallback is the cheap fix when someone owns macOS parity.
- **LOW** (confidence: medium) `.claude/scripts/run-checkpoint.sh:63-68` — `bead_closed` calls `br show` with no timeout; a wedged beads DB (KF-005 class) would hang `read`, and `read` sits on the `/run-resume` path. Wrap in `timeout 10` where available; on timeout treat as "not proven" (discard), which is the safe direction.

### 3. Budget headroom

- **LOW** (confidence: high) `.claude/skills/implementing-tasks/SKILL.md` — 16,372 B of 16,384 after this sprint's write-point clause and trim; any future include growth breaks the budget gate. Trim ≥ 60 B in Sprint 4 if that skill is touched again.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| `run-preflight.bats`: pass+fail per predicate, checklist names predicate and fix, `--json` shape (FR-3 AC 1) | Pass | PF-1…PF-8, PF-J; 14/14 |
| Checkpoint after each task and phase; resume restarts at the recorded task in the integration fixture (FR-3 AC 2) | Pass | write points in `implementing-tasks:213`, `run-mode:106,112`, `sprint-plan-mode.md:29-31`; CK-1…6; RE-2 with real `br` |
| `loa-status.sh` resume line for stale, nothing for clean; `hook-wiring.bats` covers the SessionStart line (FR-3 AC 3) | Pass | RSS-1/2/3/7; `loa-status.sh:717-726`; W10 parity green; hook-guard wrapping probed by hand |
| No new config key (FR-3 AC 4) | Pass | only existing keys read; `.loa.config.yaml.example` untouched |

---

## Security Checklist

- [x] No credential values printed — presence only, asserted by PF-3
- [x] Untrusted state values sanitised (control bytes stripped, 80-char cap) before reaching session context
- [x] Test seams bats-gated (`LOA_PREFLIGHT_HELPERS_DIR`) and negatively tested (PF-S)
- [x] Atomic, locked state writes; a write never replaces the file with unparseable output (CK-4)
- [x] SessionStart hook behind `hook-guard.sh`, exit 0 on every path

---

## Code Quality Summary

**Strengths:** capture-then-parse for health scripts (the P7 trap was caught by a live smoke test, not by a user); yq flavour detection; one surface producer for three consumers; a real-`br` re-entry proof; net-negative skill bytes.

**Areas for Improvement:** P2's inspection scope (above) is inherited from a cycle-old script and should be widened before P1's conditional rule is relied on in mixed settings setups.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"sprint_id":"sprint-243","ts":"2026-09-23T05:05:00Z"} -->
