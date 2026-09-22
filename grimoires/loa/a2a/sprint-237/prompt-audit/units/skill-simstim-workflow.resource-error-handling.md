# simstim error handling (split from SKILL.md, cycle-124 Sprint 3 prompt audit)

### On Skill/Phase Failure

If any phase fails unexpectedly:

1. Log error to trajectory
2. Present options to user:
   ```
   Phase [X] encountered an error: [message]

   [R]etry - Attempt phase again
   [S]kip - Mark as skipped, continue (may cause issues)
   [A]bort - Save state and exit
   ```

3. Handle choice:
   - **Retry**: Reset phase to in_progress, re-execute
   - **Skip**: Mark phase as "skipped", continue to next
     - Note: Cannot skip Phase 1 (PRD needed for SDD)
     - Note: Cannot skip Phase 3 (SDD needed for Sprint)
   - **Abort**: Mark workflow as "interrupted", save state, exit

### On Flatline Timeout

If Flatline API times out (>120s):
1. Log warning to trajectory
2. Mark flatline phase as "skipped"
3. Continue to next planning phase
4. Inform user: "Flatline review skipped due to timeout"

### On Interrupt (Ctrl+C)

The orchestrator script traps SIGINT:
1. Save current state immediately
2. Mark workflow as "interrupted"
3. Display: "Workflow interrupted. Run /simstim --resume to continue."
