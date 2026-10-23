# sprint-bug-267 Review Feedback (round 1)

**Reviewer:** Fable 5.1 lead (reviewing-code contract; dissent via adversarial-review.sh)
**Date:** 2026-10-21T01:46:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-4439fd/sprint.md (sprint-bug-267)
**Implementation Report:** grimoires/loa/a2a/bug-20261021-4439fd/reviewer.md (implementer B, Opus 5.5)
**Commits under review:** red `06bc53ce` (tests/unit/post-pr-flatline-degraded.bats, PFD-1…7), fix `3ec4e927` on `fix/cycle-132-bugs`
**Dissent:** adversarial-review.json (gpt-5.5-pro; status clean; 3 advisories, 0 blocking; 0 schema-rejected)
**Red-then-green:** `red-test-check.sh --red 06bc53ce --green 3ec4e927 -- bats tests/unit/post-pr-flatline-degraded.bats` → VERIFIED

---

## Overall Assessment

The phase now reads the verdict: the orchestrator runs with `--json`, its stdout lands in `.run/post-pr-flatline-pr.json` by temp-and-move, and only `verdict_quality.status == APPROVED` on an `ok` exit records `completed` + PR-VALIDATED; DEGRADED, FAILED, a missing or unparseable envelope, a timeout and any other exit record `failed` with the degraded summary (phase, status, voices, degraded models, reason) and the `FLATLINE-PR-DEGRADED` marker, and the flow continues to READY_FOR_HITL with a hand-off line that names the degraded review. The ten tests drive the real orchestrator end to end with a stub Flatline; nine fail by assertion at the red commit and all pass at the fix; the eight post-pr suites and two related suites stay green (106 cases). The implementer also found that the real orchestrator exits 6 on a non-APPROVED verdict (so the incident actually reached the `*)` branch, not the `ok` branch as the triage read) and pinned that path (PFD-5b).

Two low-severity points from the dissent are worth a short round because both change what an operator reads in the hand-off.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. A missing orchestrator is reported as "no verdict quality" (dissent DISS-C-002)

- **LOW** (confidence: high) `.claude/scripts/post-pr-orchestrator.sh:486-487, :518` — the "Flatline orchestrator not found" branch sets `flatline_result=0`, falls into `ok)` with no output file and lands in `_flatline_pr_not_green "no_verdict_quality"`. Failing is right (your DECISION stands); the reason string is misleading.
**Required Fix:** give that branch its own reason, `orchestrator_missing`, and a `log_error` naming the expected path; add a PFD case (the stub removed) asserting `reason == orchestrator_missing`, `failed`, the marker, no PR-VALIDATED.

### 2. The single summary slot loses the Flatline summary when Bridgebuilder also degrades (dissent DISS-C-003)

- **LOW** (confidence: medium) `.claude/scripts/post-pr-orchestrator.sh:576-580, :750-758` — the Bridgebuilder phase keeps a Flatline summary at its start, but a DEGRADED Bridgebuilder result overwrites the same path and the hand-off then names only the Bridgebuilder review.
**Required Fix:** when the Bridgebuilder writer finds an existing summary whose `phase` is `flatline_pr`, carry it under `previous` in the new summary (`{state:"DEGRADED", phase:"bridgebuilder_review", …, previous:{…flatline summary…}}`), and `surface_degraded_handoff` names both phases when `previous` is present. Add a PFD case with both stubs degraded (the Bridgebuilder phase can be driven to DEGRADED through its existing test harness pattern; if that is impractical in the time, a static-contract case for the `previous` field and the two-phase hand-off text is acceptable — say which).

---

## Observations (non-blocking)

- DISS-C-001: parsing the whole captured stdout with `jq -er` fails closed if the real orchestrator ever prints a banner on stdout under `--json`. Verified today against two live runs (`prd.json`, `sdd.json`: stdout is exactly one JSON document; progress goes to stderr); fail-closed is the right direction. Accepted.
- The triage's reading that the incident reached the `ok` branch was wrong (exit 6 → `*)` → `skipped`); the fix covers both branches and PFD-5b pins the real one. The triage is corrected in the report, not the code.
- `--skip-flatline` clearing a stale summary and the stale-clear at phase start are good hygiene.

## Rejected dissent payloads
None (0 rows).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"sprint_id":"sprint-bug-267","ts":"2026-10-21T01:46:00Z"} -->
