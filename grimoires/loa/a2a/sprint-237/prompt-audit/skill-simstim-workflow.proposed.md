---
name: simstim
description: "HITL-accelerated development: orchestrates PRD -> SDD -> Sprint -> Run with integrated Flatline reviews, the human driving planning decisions while HIGH_CONSENSUS findings auto-integrate. Use when the operator wants to steer planning but automate execution. (Contrast: run-mode and autonomous-agent are unattended.)"
role: implementation
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: true
  user_interaction: true
  agent_spawn: true
  task_management: true
cost-profile: unbounded
---

# Simstim - HITL Accelerated Development Workflow

<objective>
Orchestrate the complete Loa development cycle (PRD → SDD → Sprint → Implementation)
with integrated Flatline Protocol reviews at each stage. Human drives planning phases
interactively while HIGH_CONSENSUS findings auto-integrate.

"Experience the AI's work while maintaining your own consciousness." — Gibson, Neuromancer
</objective>

## Cost

**Estimated per invocation**: $25–$65/full cycle (see [Cost Matrix](../../../docs/CONFIG_REFERENCE.md#cost-matrix))
**External providers called**: Claude Opus 4.7 (primary), GPT-5.3-codex (cross-review), Gemini 2.5 Pro (tertiary)
**To cap spend**: Set `hounfour.metering.budget.daily_micro_usd` in `.loa.config.yaml`. Budget enforcement is active when `hounfour.metering.enabled: true`.
**If cost is a concern**: Run `/loa setup` — the wizard will guide you to a budget-appropriate configuration.

_Pricing verified: 2026-04-15. Prices change — recheck before large commitments._

<input_guardrails>
- PII filter: enabled
- Injection detection: enabled
- Danger level: moderate (orchestration, not direct execution)
</input_guardrails>

<constraints>
## Plan Mode Prevention

This skill manages its own 8-phase workflow — do not use Claude Code's native Plan Mode for it. Plan Mode collapses the workflow into "plan → implement", skipping DISCOVERY (no PRD), ARCHITECTURE (no SDD), and PLANNING (no sprint), so the artifacts this skill exists to produce are never created. When the user invokes `/simstim`, respond with the phase display (e.g. `[1/8] DISCOVERY - ...`) and proceed through the phases below.

## Constraint Rules

<!-- @constraint-generated: start simstim_constraints | hash:fa9331a75525a8d5 -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
1. NEVER call `EnterPlanMode` — simstim phases ARE the plan
2. NEVER jump to implementation after any user confirmation
3. Each phase MUST complete sequentially: 0→1→2→3→3.5→4→4.5→5→6→6.5→7→8
4. User approvals within phases are for THAT PHASE ONLY
5. Only Phase 7 (IMPLEMENTATION) involves writing application code
6. Phase 7 MUST invoke `/run sprint-plan` — NEVER implement code directly
7. If `/run sprint-plan` fails or is unavailable, HALT and inform the user — do NOT fall back to direct implementation
8. Use `br` commands for task lifecycle, NOT `TaskCreate`/`TaskUpdate`
9. If sprint plan exists but no beads tasks created, create them FIRST
<!-- @constraint-generated: end simstim_constraints -->

Rule 6: direct implementation skips the review→audit cycle `/run` wraps around `/implement`. Rule 8: `TaskCreate` tasks are invisible to beads and cross-session recovery.
</constraints>

<context>
You are executing the /simstim command: the PRD → SDD → Sprint → Implementation cycle above, run as HITL (Human-In-The-Loop) rather than /autonomous — you interact with the human throughout the planning phases. State is tracked in `.run/simstim-state.json` for resume capability.
</context>

---

## Workflow Execution

<preflight>
### Phase 0: PREFLIGHT [0/8]

Display: `[0/8] PREFLIGHT - Validating configuration...`

1. Check configuration:
   ```bash
   result=$(.claude/scripts/simstim-orchestrator.sh --preflight ${DRY_RUN:+--dry-run} ${FROM:+--from "$FROM"} ${RESUME:+--resume} ${ABORT:+--abort})
   ```

2. **Flatline Readiness Validation** (stateless, ~100ms, no API calls) — run fresh per cycle, not cached from a previous session, since provider keys can change between sessions:
   ```bash
   flatline_result=$(.claude/scripts/flatline-readiness.sh --json)
   flatline_exit=$?
   ```
   Handle exit codes:
   - **0 (READY)**: All configured providers have API keys — continue normally.
   - **1 (DISABLED)**: `flatline_protocol.enabled: false`. Display: `"Flatline Protocol is disabled — review phases will be skipped."`
   - **2 (NO_API_KEYS)**: Zero provider keys present. Display the warning plus the `recommendations` array from the JSON output.
   - **3 (DEGRADED)**: Some but not all provider keys present — a warning, not a block; Flatline may use fewer models than configured. Display: `"Flatline running in degraded mode — some providers unavailable."` plus `recommendations`.

3. Handle preflight result:
   - Exit code 0: Continue to appropriate phase
   - Exit code 1: Display error, stop
   - Exit code 2: State conflict - ask user: [R]esume / [F]resh / [A]bort
   - Exit code 3: Missing prerequisite - display what's needed

4. If --dry-run: Display planned phases and exit

5. If --abort: Confirm cleanup and exit

6. If --resume: see `resources/resume-support.md`

7. Otherwise: Continue to Phase 1 or specified --from phase

8. **Compute total phases** for progress display. Base phases: 8. Check config gates to count enabled sub-phases:
   - `simstim.bridgebuilder_design_review: true` → +1 (Phase 3.5)
   - `red_team.enabled: true` AND `red_team.simstim.auto_trigger: true` → +1 (Phase 4.5)
   - beads installed AND `simstim.flatline.beads_loop: true` → +1 (Phase 6.5)

   Store computed `total_phases` in simstim state:
   ```bash
   .claude/scripts/simstim-state.sh update total_phases "$total_phases"
   ```

   Use `[N/$total_phases]` in every subsequent phase display instead of the hardcoded `[N/8]`.
</preflight>

---

<phase_1_discovery>
### Phase 1: DISCOVERY [1/8]

Display: `[1/8] DISCOVERY - Creating Product Requirements Document...`

**Update state**: `simstim-orchestrator.sh --update-phase discovery in_progress`

Guide the user through PRD creation: the project or feature, goals and success metrics, non-goals, users and stakeholders, functional requirements, technical constraints, and risks and dependencies.

**Create PRD at `grimoires/loa/prd.md`** following standard PRD structure.

**Artifact completion detection:**
- File exists: `test -f grimoires/loa/prd.md`
- Size check: File > 500 bytes
- Header validation: Contains "Product Requirements Document" or "PRD"

Once complete:
```bash
.claude/scripts/simstim-orchestrator.sh --update-phase discovery completed
.claude/scripts/simstim-state.sh add-artifact prd grimoires/loa/prd.md
```

Proceed to Phase 2.
</phase_1_discovery>

---

<phase_2_flatline_prd>
### Phase 2: FLATLINE PRD REVIEW [2/8]

Display: `[2/8] FLATLINE PRD - Multi-model adversarial review...`

**Update state**: `simstim-orchestrator.sh --update-phase flatline_prd in_progress`

Run the shared Flatline HITL review procedure (→ `resources/flatline-hitl-review.md`) against `grimoires/loa/prd.md` with `--phase prd`. Phases 4 and 6 run the identical procedure against the SDD and sprint plan.

Proceed to Phase 3.
</phase_2_flatline_prd>

---

<phase_3_architecture>
### Phase 3: ARCHITECTURE [3/8]

Display: `[3/8] ARCHITECTURE - Creating Software Design Document...`

**Update state**: `simstim-orchestrator.sh --update-phase architecture in_progress`

Guide the user through SDD creation: review the PRD requirements, design the system architecture (components, data flow), select the technology stack with justification, design data models and schemas, define API contracts, plan the security architecture, and consider scalability and performance.

**Create SDD at `grimoires/loa/sdd.md`** following standard SDD structure.

**Artifact completion detection:**
- File exists: `test -f grimoires/loa/sdd.md`
- Size check: File > 500 bytes
- Header validation: Contains "Software Design Document" or "SDD"

Once complete:
```bash
.claude/scripts/simstim-orchestrator.sh --update-phase architecture completed
.claude/scripts/simstim-state.sh add-artifact sdd grimoires/loa/sdd.md
```

Proceed to Phase 3.5 (if enabled) or Phase 4.
</phase_3_architecture>

---

<phase_3_5_bridgebuilder_sdd>
### Phase 3.5: BRIDGEBUILDER SDD (Design Review) [3.5/8]

Runs ONLY when BOTH `bridgebuilder_design_review.enabled` AND `simstim.bridgebuilder_design_review` are true (default off; if the flags disagree, warn and skip). Advisory, never blocking: any failure logs to trajectory, marks the phase `skipped`, and continues to Phase 4. Full procedure: → `resources/phase-3.5-bridgebuilder-sdd.md`.

</phase_3_5_bridgebuilder_sdd>

---

<phase_4_flatline_sdd>
### Phase 4: FLATLINE SDD REVIEW [4/8]

Display: `[4/8] FLATLINE SDD - Multi-model adversarial review...`

**Update state**: `simstim-orchestrator.sh --update-phase flatline_sdd in_progress`

Same procedure as Phase 2 (→ `resources/flatline-hitl-review.md`), against `grimoires/loa/sdd.md` with `--phase sdd`.

Proceed to Phase 4.5 (if enabled) or Phase 5.
</phase_4_flatline_sdd>

---

<phase_4_5_red_team_sdd>
### Phase 4.5: RED TEAM SDD (Optional) [4.5/8]

Runs when `red_team.enabled: true` AND `red_team.simstim.auto_trigger: true` (default off). Full procedure: → `resources/phase-4.5-red-team-sdd.md`. On disabled: skip to Phase 5.

</phase_4_5_red_team_sdd>

---

<phase_5_planning>
### Phase 5: PLANNING [5/8]

Display: `[5/8] PLANNING - Creating Sprint Plan...`

**Update state**: `simstim-orchestrator.sh --update-phase planning in_progress`

Guide the user through sprint planning: review the PRD and SDD, break the work into sprints, define tasks with acceptance criteria, estimate complexity and effort, identify dependencies between tasks, and set verification criteria per sprint.

**Create sprint plan at `grimoires/loa/sprint.md`** following standard format.

**Artifact completion detection:**
- File exists: `test -f grimoires/loa/sprint.md`
- Size check: File > 500 bytes
- Header validation: Contains "Sprint Plan"

Once complete:
```bash
.claude/scripts/simstim-orchestrator.sh --update-phase planning completed
.claude/scripts/simstim-state.sh add-artifact sprint grimoires/loa/sprint.md
```

Proceed to Phase 6.
</phase_5_planning>

---

<phase_6_flatline_sprint>
### Phase 6: FLATLINE SPRINT REVIEW [6/8]

Display: `[6/8] FLATLINE SPRINT - Multi-model adversarial review...`

**Update state**: `simstim-orchestrator.sh --update-phase flatline_sprint in_progress`

Same procedure as Phase 2 (→ `resources/flatline-hitl-review.md`), against `grimoires/loa/sprint.md` with `--phase sprint`.

Proceed to Phase 7.
</phase_6_flatline_sprint>

---

<phase_7_implementation>
### Phase 7: IMPLEMENTATION [7/8]

Display: `[7/8] IMPLEMENTATION - Handing off to autonomous execution...`

**Update state**: `simstim-orchestrator.sh --update-phase implementation in_progress`

### Pre-Implementation Verification

Before invoking `/run sprint-plan`, verify:

1. **Sprint plan exists**: `grimoires/loa/sprint.md` is present and was generated this cycle
2. **Beads tasks created**: If beads is HEALTHY, sprint tasks exist in beads (`br list` shows tasks)
3. **No stale feedback**: Check `auditor-sprint-feedback.md` and `engineer-feedback.md` — address any findings first
4. **Feature branch**: Not on `main` or other protected branch

If any check fails, report the issue to the user instead of proceeding — this phase invokes `/run sprint-plan` only, never `/implement` directly (rule 6 above).

**Handoff to /run sprint-plan** (delegates to the run-mode skill for autonomous implementation):

1. Inform user:
   ```
   Ready to begin autonomous implementation.
   This will execute all sprints and create a draft PR.

   Continue? [Y/n]
   ```

2. **Set plan_id reference**:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --set-expected-plan-id
   ```
   Stores the expected plan_id for state correlation after run-mode completes.

3. Invoke /run sprint-plan:
   - Run-mode takes over the conversation
   - Creates its own state at `.run/sprint-plan-state.json`
   - Implements all sprints autonomously
   - Creates draft PR when complete

4. **Sync run-mode state**:
   ```bash
   sync_result=$(.claude/scripts/simstim-orchestrator.sh --sync-run-mode)
   ```
   Synchronizes run-mode completion state back to simstim state atomically.

   **Check sync result**:
   - If `synced: true`: State successfully synchronized
   - If `synced: false, reason: plan_id_mismatch`: Stale run-mode state detected, do NOT proceed
   - If `synced: false, reason: stale_timestamp`: Run-mode state too old, do NOT proceed
   - If `synced: false, reason: no_run_mode_state`: Run-mode didn't complete, check manually

5. Check synchronized state:
   - If simstim state = "COMPLETED": Implementation complete (no post-PR validation)
   - If simstim state = "AWAITING_HITL": Post-PR validation complete, proceed to Phase 8
   - If simstim state = "HALTED": Mark as "incomplete", inform user of `/run-resume`
   - If simstim state = "SYNC_FAILED": Sync failed after max attempts, use `--force-phase` to bypass

6. Update simstim state (if sync didn't already):
   ```bash
   .claude/scripts/simstim-orchestrator.sh --update-phase implementation [completed|incomplete]
   ```

**Recovery: Force Phase.** If sync fails repeatedly (after 3 attempts), the escape hatch bypasses validation — use only after manually verifying implementation is actually complete:
```bash
.claude/scripts/simstim-orchestrator.sh --force-phase complete --yes
```

Proceed to Phase 7.5 (if post-PR validation ran) or Phase 8.
</phase_7_implementation>

---

<phase_7_5_post_pr_validation>
### Phase 7.5: POST-PR VALIDATION [7.5/8]

Runs when `post_pr_validation.enabled: true`. Full procedure (orchestrator invocation, exit-code table, HITL prompts): → `resources/phase-7.5-post-pr-validation.md`. On disabled: skip to Phase 8.

</phase_7_5_post_pr_validation>

---

<phase_complete>
### Phase 8: COMPLETE [8/8]

Display: `[8/8] COMPLETE - Workflow finished!`

1. Generate Flatline summary:
   ```
   Flatline Summary:
   - PRD: [N] integrated, [M] disputed, [K] blockers
   - SDD: [N] integrated, [M] disputed, [K] blockers
   - Sprint: [N] integrated, [M] disputed, [K] blockers
   Total: [X] integrated, [Y] disputed, [Z] blockers
   ```

2. Display PR URL from run-mode (if available)

3. Update final state:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --complete
   ```

4. Display completion message:
   ```
   Simstim workflow complete!

   Artifacts created:
   - grimoires/loa/prd.md
   - grimoires/loa/sdd.md
   - grimoires/loa/sprint.md

   PR: [URL]

   Use /simstim --abort to clean up state file.
   ```
</phase_complete>

---

## Error Handling

See `resources/error-handling.md` for the phase-failure retry/skip/abort prompt, Flatline timeout handling (>120s), and SIGINT/interrupt behavior.

---

## Resume Support

See `resources/resume-support.md` when the user passes `--resume` — state validation, artifact-drift handling, and the resume-phase jump table live there. `.run/simstim-state.json` is the cross-session source of truth: all progress, artifact checksums, and Flatline metrics live there, so a fresh session resumes from it, not from conversation context.

---

## Flags Reference

| Flag | Description | Mutual Exclusivity |
|------|-------------|-------------------|
| `--from <phase>` | Start from specific phase (plan-and-analyze, architect, sprint-plan, run) | Cannot use with --resume |
| `--resume` | Continue from interruption | Cannot use with --from |
| `--abort` | Clean up state and exit | Takes precedence over others |
| `--dry-run` | Show planned phases without executing | Can combine with any |

---

## Configuration

Requires in `.loa.config.yaml`:
```yaml
simstim:
  enabled: true
```

Full configuration reference: See SDD Section 8.3

## Provenance

Removed from rule text: #192, PR #216 (Plan Mode Prevention), cycle-048/cycle-045 (Preflight), cycle-047 (Red Team rollout note, now in `resources/phase-4.5-red-team-sdd.md`), v1.28.0/v1.25.0 (Phase 7/7.5 tags).
