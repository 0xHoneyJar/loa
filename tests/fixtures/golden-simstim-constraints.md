## Plan Mode Prevention

This skill manages its own 8-phase workflow. DO NOT use Claude Code's native Plan Mode.

**CRITICAL RULES**:
1. NEVER call `EnterPlanMode` — simstim phases ARE the plan
2. NEVER jump to implementation after any user confirmation
3. Each phase MUST complete sequentially: 0→1→2→3→4→5→6→6.5→7→8
4. User approvals within phases are for THAT PHASE ONLY
5. Only Phase 7 (IMPLEMENTATION) involves writing application code

**Why this matters**:
- Plan Mode collapses the workflow into "plan → implement"
- This skips DISCOVERY (no PRD), ARCHITECTURE (no SDD), and PLANNING (no sprint)
- Quality artifacts are never created
- Users report confusion (#192)

**Correct behavior**:
- User says: `/simstim I want to build authentication`
- You respond: `[1/8] DISCOVERY - Let me ask you some questions...`
- NOT: Enter Plan Mode and write a plan

**If you feel the urge to plan**: You're already IN a planning workflow. Follow the phases.

## Implementation Phase Enforcement

6. Phase 7 MUST invoke `/run sprint-plan` — NEVER implement code directly
7. If `/run sprint-plan` fails or is unavailable, HALT and inform the user — do NOT fall back to direct implementation
8. Use `br` commands for task lifecycle, NOT `TaskCreate`/`TaskUpdate`
9. If sprint plan exists but no beads tasks are created, create them FIRST using `br create` before invoking `/run`

**Why this matters**:
- PR #216 was rolled back because Phase 7 bypassed /run sprint-plan
- Direct implementation skips the review→audit cycle loop
- TaskCreate tasks are invisible to beads and cross-session recovery
