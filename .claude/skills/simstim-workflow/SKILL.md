# Simstim - HITL Accelerated Development Workflow

<objective>
Orchestrate the complete Loa development cycle (PRD → SDD → Sprint → Implementation)
with integrated Flatline Protocol reviews at each stage. Human drives planning phases
interactively while HIGH_CONSENSUS findings auto-integrate.

"Experience the AI's work while maintaining your own consciousness." — Gibson, Neuromancer
</objective>

<input_guardrails>
- PII filter: enabled
- Injection detection: enabled
- Danger level: moderate (orchestration, not direct execution)
</input_guardrails>

<constraints>
## Plan Mode Prevention

This skill manages its own 8-phase workflow. DO NOT use Claude Code's native Plan Mode.

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

## Constraint Rules

<!-- @constraint-generated: start simstim_constraints | hash:852a0b4eccaea5a8 -->
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

**Why this matters**:
- PR #216 was rolled back because Phase 7 bypassed /run sprint-plan
- Direct implementation skips the review→audit cycle loop
- TaskCreate tasks are invisible to beads and cross-session recovery
</constraints>

<context>
You are executing the /simstim command, a HITL (Human-In-The-Loop) workflow that chains:
1. PRD creation with Flatline review
2. SDD creation with Flatline review
3. Sprint planning with Flatline review
4. Autonomous implementation via /run sprint-plan

This is NOT /autonomous - you interact with the human throughout planning phases.
State is tracked in `.run/simstim-state.json` for resume capability.
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

2. Handle preflight result:
   - Exit code 0: Continue to appropriate phase
   - Exit code 1: Display error, stop
   - Exit code 2: State conflict - ask user: [R]esume / [F]resh / [A]bort
   - Exit code 3: Missing prerequisite - display what's needed

3. If --dry-run: Display planned phases and exit

4. If --abort: Confirm cleanup and exit

5. If --resume: Jump to <resume_support> section

6. Otherwise: Continue to Phase 1 or specified --from phase
</preflight>

---

<phase_1_discovery>
### Phase 1: DISCOVERY [1/8]

Display: `[1/8] DISCOVERY - Creating Product Requirements Document...`

**Update state**: `simstim-orchestrator.sh --update-phase discovery in_progress`

**Guide the user through PRD creation:**

1. Ask about the project/feature they want to build
2. Clarify goals, success metrics, and non-goals
3. Identify users and stakeholders
4. Gather functional requirements
5. Discuss technical constraints
6. Document risks and dependencies

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

1. Run Flatline Protocol:
   ```bash
   result=$(.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --mode hitl --json)
   ```

2. Process results in HITL mode:
   - **HIGH_CONSENSUS** (both models >700): Auto-integrate without prompting
   - **DISPUTED** (delta >300): Present to user with options [Accept/Reject/Skip]
   - **BLOCKER** (skeptic concern >700): Present to user with options [Override with rationale/Reject/Defer]
   - **LOW_VALUE** (both <400): Skip silently

3. For each DISPUTED item, ask user:
   ```
   DISPUTED: [suggestion]
   GPT scored [X], Opus scored [Y]
   [A]ccept / [R]eject / [S]kip?
   ```

4. For each BLOCKER item, ask user:
   ```
   BLOCKER: [concern]
   Severity: [score]
   [O]verride (requires rationale) / [R]eject / [D]efer?
   ```

   **BLOCKER Override Handling:**
   - If Override: REQUIRE user to provide rationale
   - Log override to trajectory:
     ```bash
     .claude/scripts/simstim-orchestrator.sh --log-blocker-override \
         --blocker-id "[id]" \
         --decision "override" \
         --rationale "[user rationale]"
     ```
   - If Reject: Mark blocker as rejected, continue to next
   - If Defer: Add to deferred list in state for post-implementation review

5. Update state with metrics:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --update-flatline-metrics prd [integrated] [disputed] [blockers]
   .claude/scripts/simstim-orchestrator.sh --update-phase flatline_prd completed
   ```

**Skip if Flatline unavailable:** Log warning, continue to Phase 3.

Proceed to Phase 3.
</phase_2_flatline_prd>

---

<phase_3_architecture>
### Phase 3: ARCHITECTURE [3/8]

Display: `[3/8] ARCHITECTURE - Creating Software Design Document...`

**Update state**: `simstim-orchestrator.sh --update-phase architecture in_progress`

**Guide the user through SDD creation:**

1. Review PRD requirements
2. Design system architecture (components, data flow)
3. Select technology stack with justification
4. Design data models and schemas
5. Define API contracts
6. Plan security architecture
7. Consider scalability and performance

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

Display: `[3.5/8] BRIDGEBUILDER SDD - Architectural design review...`

**Trigger conditions** (ALL must be true):
- `bridgebuilder_design_review.enabled: true` in `.loa.config.yaml`
- `simstim.bridgebuilder_design_review: true` in `.loa.config.yaml`
- SDD exists (`test -f grimoires/loa/sdd.md`)

If only one config flag is set, skip with warning:
"bridgebuilder_design_review.enabled and simstim.bridgebuilder_design_review disagree — design review will not run. Set both to true to enable."

**Skip conditions** (any triggers skip):
- Either config flag is false (default)
- User chooses to skip when prompted
- SDD does not exist

**When triggered:**

1. **Update state**: `simstim-orchestrator.sh --update-phase bridgebuilder_sdd in_progress`

2. **Load persona**: Read persona from path configured in
   `bridgebuilder_design_review.persona_path` (default: `.claude/data/bridgebuilder-persona.md`)

3. **Load lore** (if `bridgebuilder_design_review.lore_enabled: true`):
   Load lore entries using the same mechanism as Run Bridge Phase 3.1 step 3:
   read categories from `yq '.run_bridge.lore.categories[]' .loa.config.yaml`,
   then load matching entries from `grimoires/loa/lore/patterns.yaml` and
   `grimoires/loa/lore/visions.yaml`. Falls back gracefully to empty string
   if lore files do not exist.

   **Trajectory log** (after lore load):
   Log categories loaded, number of lore entries found, and whether fallback
   was used (e.g., "Lore loaded: 2 categories, 5 entries" or
   "Lore: no files found, proceeding without lore context").

4. **Read artifacts**:
   - SDD: `grimoires/loa/sdd.md` (full document; if >5K tokens, summarize per Run Bridge truncation strategy)
   - PRD: `grimoires/loa/prd.md` (for requirement traceability)
   - Discovery notes (optional, budget: 3K tokens total): Load
     `grimoires/loa/a2a/flatline/prd-review.json` (structured, predictable size)
     and the most recently modified file from `grimoires/loa/context/`. If total
     discovery notes exceed 3K tokens, truncate context/ content first (preserve
     flatline results). Skip silently if neither exists. These enable tracing the
     full problem → requirements → design reasoning chain.

5. **Generate review**: Using the Bridgebuilder persona and
   `.claude/data/design-review-prompt.md` template, evaluate the SDD against 6 dimensions:
   - Architectural Soundness
   - Requirement Coverage (PRD → SDD mapping)
   - Scale Alignment
   - Risk Identification
   - Frame Questioning (REFRAME)
   - Pattern Recognition (ecosystem lore)

   Produce dual-stream output:
   - **Stream 1**: Structured findings JSON inside `<!-- bridge-findings-start/end -->` markers
   - **Stream 2**: Insights prose (architectural meditations, FAANG parallels)

   Target completion within 120 seconds. If taking significantly longer,
   truncate insights prose and preserve findings JSON.

6. **Save review**:
   ```bash
   mkdir -p .run/bridge-reviews
   ```
   Write to `.run/bridge-reviews/design-review-{cycle}.md` with 0600 permissions.

7. **Parse findings**:
   ```bash
   .claude/scripts/bridge-findings-parser.sh \
     --input .run/bridge-reviews/design-review-{cycle}.md \
     --output .run/bridge-reviews/design-review-{cycle}.json
   ```

8. **HITL interaction** for each finding by severity:

   **REFRAME findings** (always presented):
   ```
   REFRAME: [title]
   [description]

   This questions the design framing, not the implementation.
   [A]ccept minor (modify SDD section)
   [A]ccept major (return to Architecture phase)
   [R]eject (log rationale)
   [D]efer (capture as vision)
   ```

   - Accept minor: Agent modifies the relevant SDD section in-place
   - Accept major: Mark SDD artifact as `needs_rework`, set
     `simstim-orchestrator.sh --update-phase architecture in_progress`,
     preserve REFRAME context to `.run/bridge-reviews/reframe-context.md`,
     return to Phase 3. **Circuit breaker**: Track rework count in
     `bridgebuilder_sdd.rework_count` (max 2). After 2 cycles,
     REFRAME findings are presented as accept-minor-only or auto-defer.
   - Reject: Log rationale to trajectory
   - Defer: Reclassify finding as VISION (preserving `original_severity: "REFRAME"`
     in metadata) and capture as vision entry in Step 9. This semantic transition
     reflects the state change: an active design question becomes a preserved
     insight for later exploration.

   **CRITICAL findings** (mandatory acknowledgment):
   ```
   CRITICAL: [title]
   [description]
   Design cannot satisfy a P0 requirement as specified.

   [A]ccept (modify SDD) / [R]eturn to Architecture / [R]eject (with rationale)
   ```
   No Defer option — CRITICAL findings demand a decision, not deferral.

   **HIGH/MEDIUM findings**:
   ```
   [severity]: [title]
   [description]
   Suggested change: [suggestion]

   [A]ccept (modify SDD) / [R]eject / [D]efer
   ```

   **SPECULATION findings**:
   ```
   SPECULATION: [title]
   [description]

   Architectural alternative to consider.
   [A]ccept (incorporate into SDD) / [D]efer (capture as vision)
   ```

   **LOW findings** (informational, no action required):
   ```
   LOW: [title]
   [description]
   Minor suggestion — displayed for awareness.
   ```

   **PRAISE findings**: Display to user (no action needed)

   **VISION findings**: Auto-capture to vision registry (no user interaction)

9. **Vision capture** (if any VISION/SPECULATION findings — including
   deferred REFRAMEs reclassified as VISION in Step 8 — and
   `bridgebuilder_design_review.vision_capture: true`):
   ```bash
   .claude/scripts/bridge-vision-capture.sh \
     --findings .run/bridge-reviews/design-review-{cycle}.json \
     --bridge-id "design-review-{simstim_id}" \
     --iteration 1 \
     --output-dir grimoires/loa/visions
   ```
   Note: `--pr` is omitted (optional argument). `--bridge-id` uses a
   design-review-prefixed identifier for provenance tracking.

   **Trajectory log** (after vision capture):
   Log event name (`design_review_vision_capture`), number of vision entries
   created, bridge-id, and findings count by severity.

10. **Update artifact checksum** (if SDD was modified):
    ```bash
    .claude/scripts/simstim-state.sh add-artifact sdd grimoires/loa/sdd.md
    ```

11. **Complete phase**:
    ```bash
    .claude/scripts/simstim-orchestrator.sh --update-phase bridgebuilder_sdd completed
    ```

**If skipped** (config disabled or mismatch):
- Log skip reason to state file
- Continue to Phase 4

**If Phase 3.5 fails** (review generation error, parse failure, etc.):
- Log error to trajectory with stack context
- Mark phase as `skipped` (not `failed`) to avoid blocking
- Display warning: "Design review failed: [reason]. Continuing to Phase 4."
- Continue to Phase 4 — design review is advisory, not blocking

Proceed to Phase 4.
</phase_3_5_bridgebuilder_sdd>

---

<phase_4_flatline_sdd>
### Phase 4: FLATLINE SDD REVIEW [4/8]

Display: `[4/8] FLATLINE SDD - Multi-model adversarial review...`

**Update state**: `simstim-orchestrator.sh --update-phase flatline_sdd in_progress`

Follow same HITL process as Phase 2, but for SDD:
```bash
result=$(.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --mode hitl --json)
```

Process HIGH_CONSENSUS, DISPUTED, BLOCKER items as in Phase 2.

Update state:
```bash
.claude/scripts/simstim-orchestrator.sh --update-flatline-metrics sdd [integrated] [disputed] [blockers]
.claude/scripts/simstim-orchestrator.sh --update-phase flatline_sdd completed
```

Proceed to Phase 4.5 (if enabled) or Phase 5.
</phase_4_flatline_sdd>

---

<phase_4_5_red_team_sdd>
### Phase 4.5: RED TEAM SDD (Optional) [4.5/8]

Display: `[4.5/8] RED TEAM SDD - Generative adversarial security design...`

**Trigger conditions** (ALL must be true):
- `red_team.simstim.auto_trigger: true` in `.loa.config.yaml`
- `red_team.enabled: true` in `.loa.config.yaml`
- SDD exists and was reviewed by Flatline (Phase 4 complete)

**Skip conditions** (any triggers skip):
- `red_team.simstim.auto_trigger: false` (default)
- User chooses to skip when prompted
- SDD does not exist

**When triggered:**

1. Prompt user: "Run red team analysis on the SDD? [Y/n]"
2. If yes, invoke:
   ```bash
   .claude/scripts/flatline-orchestrator.sh \
     --doc grimoires/loa/sdd.md \
     --phase sdd \
     --mode red-team \
     --execution-mode standard \
     --json
   ```
3. Present attack summary:
   - CONFIRMED_ATTACK: Show details, require acknowledgment for severity >800
   - THEORETICAL: Show count
   - CREATIVE_ONLY: Show count
   - DEFENDED: Show count
4. Confirmed attacks generate additional sprint tasks:
   - Each CONFIRMED_ATTACK with severity >700 becomes a sprint task
   - Task description includes attack name, vector, and counter-design
   - Tasks are added to the sprint plan in Phase 5
5. Update state: `simstim-orchestrator.sh --update-phase red_team_sdd completed`

**If skipped:**
- Log skip reason to state file
- Continue to Phase 5

Proceed to Phase 5.
</phase_4_5_red_team_sdd>

---

<phase_5_planning>
### Phase 5: PLANNING [5/8]

Display: `[5/8] PLANNING - Creating Sprint Plan...`

**Update state**: `simstim-orchestrator.sh --update-phase planning in_progress`

**Guide the user through sprint planning:**

1. Review PRD and SDD
2. Break down work into sprints
3. Define tasks with acceptance criteria
4. Estimate complexity and effort
5. Identify dependencies between tasks
6. Set verification criteria per sprint

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

Follow same HITL process as Phase 2, but for sprint plan:
```bash
result=$(.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sprint.md --phase sprint --mode hitl --json)
```

Process HIGH_CONSENSUS, DISPUTED, BLOCKER items as in Phase 2.

Update state:
```bash
.claude/scripts/simstim-orchestrator.sh --update-flatline-metrics sprint [integrated] [disputed] [blockers]
.claude/scripts/simstim-orchestrator.sh --update-phase flatline_sprint completed
```

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

If any check fails, report the issue to the user instead of proceeding.

**CRITICAL**: Do NOT implement directly. Do NOT use `/implement` without `/run`. The `/run` command wraps `/implement` with the review→audit cycle and circuit breaker.

**Handoff to /run sprint-plan:**

This phase delegates to the run-mode skill for autonomous implementation.

1. Inform user:
   ```
   Ready to begin autonomous implementation.
   This will execute all sprints and create a draft PR.

   Continue? [Y/n]
   ```

2. **Set plan_id reference** (v1.28.0):
   ```bash
   .claude/scripts/simstim-orchestrator.sh --set-expected-plan-id
   ```
   This stores the expected plan_id for state correlation after run-mode completes.

3. Invoke /run sprint-plan:
   - Run-mode takes over the conversation
   - Creates its own state at `.run/sprint-plan-state.json`
   - Implements all sprints autonomously
   - Creates draft PR when complete

4. **Sync run-mode state** (v1.28.0):
   ```bash
   sync_result=$(.claude/scripts/simstim-orchestrator.sh --sync-run-mode)
   ```
   This synchronizes run-mode completion state back to simstim state atomically.

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

**Recovery: Force Phase** (v1.28.0):

If sync fails repeatedly (after 3 attempts), use the escape hatch:
```bash
.claude/scripts/simstim-orchestrator.sh --force-phase complete --yes
```
⚠️ WARNING: This bypasses validation. Only use as last resort when you've verified implementation is actually complete.

Proceed to Phase 7.5 (if post-PR validation ran) or Phase 8.
</phase_7_implementation>

---

<phase_7_5_post_pr_validation>
### Phase 7.5: POST-PR VALIDATION [7.5/8] (v1.25.0)

Display: `[7.5/8] POST-PR VALIDATION - Fresh-eyes review...`

**This phase runs automatically via post-pr-orchestrator.sh when `post_pr_validation.enabled: true`.**

The post-PR validation loop includes:

1. **POST_PR_AUDIT**: Consolidated audit on PR changes
   - Auto-fixable issues enter fix loop (max 5 iterations)
   - Circuit breaker: same finding 3x = escalate
   - Creates `.PR-AUDITED` marker

2. **CONTEXT_CLEAR**: Checkpoint and fresh context
   - Saves checkpoint to NOTES.md Session Continuity
   - Logs to trajectory JSONL
   - Displays instructions:
     ```
     To continue with fresh-eyes E2E testing:
       1. Run: /clear
       2. Run: /simstim --resume
     ```

3. **E2E_TESTING**: Fresh-eyes testing
   - Runs build and tests with clean context
   - Fix loop for failures (max 3 iterations)
   - Circuit breaker: same failure 2x = escalate
   - Creates `.PR-E2E-PASSED` marker

4. **FLATLINE_PR** (optional): Multi-model PR review
   - Runs if `flatline_review.enabled: true`
   - Cost: ~$1.50
   - Uses HITL mode (blockers prompt user, not auto-halt)
   - Creates `.PR-VALIDATED` marker

**Resume from context clear:**

When user runs `/simstim --resume` after context clear:

```bash
# Check post-PR state
current_phase=$(post-pr-state.sh get state)
if [[ "$current_phase" == "CONTEXT_CLEAR" ]]; then
  # Continue from E2E_TESTING
  post-pr-orchestrator.sh --resume --pr-url "$PR_URL"
fi
```

**Final states:**
- `READY_FOR_HITL`: All validations passed, PR ready for human review
- `HALTED`: Validation failed, check `halt_reason` field

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

<error_handling>
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
</error_handling>

---

## Resume Support

<resume_support>
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

### Handling State Sync Issues (v1.28.0)

When state sync fails (plan_id mismatch, stale timestamp, etc.):

**Automatic Detection on Resume:**
The preflight phase automatically detects when implementation completed but simstim state wasn't updated (e.g., due to context compaction). It validates:
- Plan ID correlation between simstim and run-mode state
- Timestamp staleness (rejects state older than 24 hours)
- Run-mode terminal state (JACKED_OUT, READY_FOR_HITL, HALTED)

**SYNC_FAILED State:**
After 3 failed sync attempts, simstim enters SYNC_FAILED state. Recovery options:

1. **Investigate**: Check `.run/sprint-plan-state.json` manually
2. **Force bypass**: Use escape hatch if implementation is verified complete:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --force-phase complete --yes
   ```
   ⚠️ WARNING: Only use after manually verifying implementation is complete

**AWAITING_HITL State:**
When run-mode returns READY_FOR_HITL (post-PR validation requested human review):
1. Simstim state is set to AWAITING_HITL
2. Phase 8 displays PR URL and prompts for HITL review
3. After review, workflow completes normally
</resume_support>

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
