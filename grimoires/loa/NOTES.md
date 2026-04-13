# Loa Project Notes

## Session Continuity — 2026-04-13 (cycles 052-054)

### Current state
- **cycle-052** (PR #463) — MERGED: Multi-model Bridgebuilder pipeline + Pass-2 enrichment
- **sprint-bug-104** (PR #465) — MERGED: A1+A2+A3 follow-ups (stdin, warn, docblock)
- **cycle-053** (PR #466) — MERGED: Amendment 1 post-PR loop + kaironic convergence
- **cycle-054** (PR #468) — OPEN: Enable Bridgebuilder on this repo (Option A rollout)

### How to restore context
See **Issue #467** — holds full roadmap, proposal doc references, and session trajectory.

Key entry points:
- `grimoires/loa/proposals/close-bridgebuilder-loop.md` (design rationale)
- `grimoires/loa/proposals/amendment-1-sprint-plan.md` (sprint breakdown)
- `.claude/loa/reference/run-bridge-reference.md` (post-PR integration + kaironic pattern)
- `.run/bridge-triage-convergence.json` (if exists — latest convergence state)
- `grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl` (per-decision audit trail)

### Open work (see #467 for full detail)
- **Option A** — Enable + observe (PR #468 in flight)
- **Option B** — Amendment 2: auto-dispatch `.run/bridge-pending-bugs.jsonl` via `/bug`
- **Option C** — Wire A4 (cross-repo) + A5 (lore loading) from Issue #464
- **Option D** — Amendment 3: pattern aggregation across PRs

### Recent HITL design decisions (locked)
1. Autonomous mode acts on BLOCKERs with mandatory logged reasoning (schema: minLength 10)
2. False positives acceptable during experimental phase
3. Depth 5 inherit from `/run-bridge`
4. No cost gating yet — collect data first
5. Production monitoring: manual + scheduled supported

---

# cycle-040 Notes

## Rollback Plan (Multi-Model Adversarial Review Upgrade)

### Full Rollback

Single-commit revert restores all previous defaults:

```bash
git revert <commit-hash>
```

### Partial Rollback — Disable Tertiary Only

```yaml
# .loa.config.yaml — remove or comment out:
hounfour:
  # flatline_tertiary_model: gemini-2.5-pro
```

Flatline reverts to 2-model mode (Opus + GPT-5.3-codex). No code changes needed.

### Partial Rollback — Revert Secondary to GPT-5.2

```yaml
# .loa.config.yaml
flatline_protocol:
  models:
    secondary: gpt-5.2

red_team:
  models:
    attacker_secondary: gpt-5.2
    defender_secondary: gpt-5.2
```

Also revert in:
- `.claude/defaults/model-config.yaml`: `reviewer` and `reasoning` aliases back to `openai:gpt-5.2`
- `.claude/scripts/gpt-review-api.sh`: `DEFAULT_MODELS` prd/sdd/sprint back to `gpt-5.2`
- `.claude/scripts/flatline-orchestrator.sh`: `get_model_secondary()` default back to `gpt-5.2`

## Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-26 | Cache: result stored [key: integrit...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: clear-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: clear-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: stats-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: stats-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: test-sec...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: test-key...] | Source: cache |
| 2026-02-26 | Cache: PASS [key: test-key...] | Source: cache |
| 2026-02-26 | Cache: PASS [key: test-key...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: integrit...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: clear-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: clear-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: stats-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: stats-te...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: test-sec...] | Source: cache |
| 2026-02-26 | Cache: result stored [key: test-key...] | Source: cache |
| 2026-02-26 | Cache: PASS [key: test-key...] | Source: cache |
| 2026-02-26 | Cache: PASS [key: test-key...] | Source: cache |
## Blockers

None.
