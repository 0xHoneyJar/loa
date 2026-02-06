## Plan Mode Prevention

This skill manages its own multi-phase autonomous workflow. DO NOT use Claude Code's native Plan Mode.

**CRITICAL RULES**:
1. NEVER call `EnterPlanMode` — autonomous phases ARE the plan
2. NEVER jump to implementation after any approval
3. Each phase MUST complete before proceeding
4. This skill orchestrates OTHER skills — each has its own workflow

**Why this matters**:
- Plan Mode would bypass quality gates
- PRD/SDD/Sprint artifacts would not be created
- Multi-model Flatline reviews would be skipped

**Correct behavior**: Execute phases sequentially with full quality gate compliance.

## Implementation Enforcement

5. Implementation phases MUST use `/run sprint-plan` or `/run sprint-N` — NEVER implement directly
6. Do NOT use `/implement` without `/run` — `/run` provides the review→audit cycle
7. Use `br` commands for task lifecycle, NOT `TaskCreate`/`TaskUpdate`
8. If sprint plan exists but no beads tasks created, create them FIRST
