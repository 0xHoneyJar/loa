# simstim resume support (split from SKILL.md, cycle-124 Sprint 3 prompt audit)

### Resuming from Interruption

When `--resume` flag is provided:

**Step 1: Validate State File Exists**
```bash
if [[ ! -f .run/simstim-state.json ]]; then
    error "No state file found. Cannot resume."
    error "Use /simstim to start a new workflow."
    exit 1
fi
```

**Step 2: Check Schema Version**
```bash
.claude/scripts/simstim-state.sh check-version
```
If version mismatch, migration is attempted automatically.

**Step 3: Load State and Determine Resume Point**
```bash
# Get current state
state=$(.claude/scripts/simstim-state.sh get state)
phase=$(.claude/scripts/simstim-state.sh get phase)

# Find first incomplete phase
incomplete_phase=$(jq -r '.phases | to_entries | map(select(.value == "in_progress" or .value == "pending")) | .[0].key // "complete"' .run/simstim-state.json)
```

**Step 4: Validate Artifact Checksums**
```bash
drift=$(.claude/scripts/simstim-state.sh validate-artifacts)
valid=$(echo "$drift" | jq -r '.valid')
```

**Step 5: Handle Artifact Drift**
If drift detected (`valid == false`), present options to user:

For each modified artifact:
```
⚠️ Artifact drift detected:

[artifact_name] (path/to/file.md)
  Expected: sha256:abc123...
  Actual:   sha256:def456...

This file was modified since the last session.

[R]e-review with Flatline - Run Flatline Protocol again on this artifact
[C]ontinue - Keep changes, skip re-review (may miss quality issues)
[A]bort - Stop workflow, keep current state
```

User choices:
- **Re-review**: Roll back to the Flatline review phase for that artifact
- **Continue**: Update stored checksum, proceed from current phase
- **Abort**: Exit immediately, state preserved

**Step 6: Display Resume Summary**
```
════════════════════════════════════════════════════════════
     Resuming Simstim Workflow
════════════════════════════════════════════════════════════

Simstim ID: simstim-20260203-abc123
Started: 2026-02-03T10:00:00Z
Last Activity: 2026-02-03T11:30:00Z

Completed Phases:
  ✓ PREFLIGHT
  ✓ DISCOVERY (PRD created)
  ✓ FLATLINE PRD (3 integrated, 1 disputed)
  ✓ ARCHITECTURE (SDD created)

Resuming from: FLATLINE SDD

════════════════════════════════════════════════════════════
```

**Step 7: Jump to Resume Phase**
Based on `incomplete_phase`, jump to the appropriate phase section:
- `discovery` → Phase 1
- `flatline_prd` → Phase 2
- `architecture` → Phase 3
- `bridgebuilder_sdd` → Phase 3.5
- `flatline_sdd` → Phase 4
- `planning` → Phase 5
- `flatline_sprint` → Phase 6
- `implementation` → Phase 7
- `complete` → Phase 8 (already done)

### Session Restart Handling

If Claude session times out and user returns to a new session:

1. **State file is the source of truth**
   - `.run/simstim-state.json` persists across sessions
   - Contains all progress, artifact checksums, Flatline metrics

2. **SKILL.md is loaded fresh**
   - New session has no context of previous work
   - Must read state file to restore context

3. **User invokes `/simstim --resume`**
   - Preflight validates state file exists
   - Schema version checked (migrate if needed)
   - Artifact drift validated
   - Workflow resumes from saved phase

4. **Artifacts contain all work**
   - `grimoires/loa/prd.md` - PRD content
   - `grimoires/loa/sdd.md` - SDD content
   - `grimoires/loa/sprint.md` - Sprint plan

5. **Flatline metrics preserved**
   - State file records integrated/disputed/blocker counts
   - Blocker override decisions with rationale preserved

### Handling 'incomplete' Status

When run-mode encounters a circuit breaker scenario (max cycles, timeout, etc.):

```bash
.claude/scripts/simstim-state.sh update-phase implementation incomplete
```

On resume:
1. Check if implementation phase is `incomplete`
2. Inform user: "Previous implementation attempt incomplete. Continuing..."
3. Invoke `/run-resume` instead of fresh `/run sprint-plan`

### Handling State Sync Issues

When state sync fails (plan_id mismatch, stale timestamp, etc.):

**Automatic Detection on Resume:**
The preflight phase automatically detects when implementation completed but simstim state wasn't updated (e.g., due to context compaction). It validates:
- Plan ID correlation between simstim and run-mode state
- Timestamp staleness (rejects state older than 24 hours)
- Run-mode terminal state (JACKED_OUT, READY_FOR_HITL, HALTED)

**SYNC_FAILED State:**
After 3 failed sync attempts, simstim enters SYNC_FAILED state. Recovery options:

1. **Investigate**: Check `.run/sprint-plan-state.json` manually
2. **Force bypass**: use the escape hatch after manually verifying implementation is complete:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --force-phase complete --yes
   ```

**AWAITING_HITL State:**
When run-mode returns READY_FOR_HITL (post-PR validation requested human review):
1. Simstim state is set to AWAITING_HITL
2. Phase 8 displays PR URL and prompts for HITL review
3. After review, workflow completes normally
