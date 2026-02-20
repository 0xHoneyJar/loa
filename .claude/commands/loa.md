---
name: loa
description: Guided workflow navigation showing current state and next steps
output: Workflow progress and suggested next command
command_type: wizard
---

# /loa - Guided Workflow Navigator

## Purpose

Show current workflow state, health, progress, and suggest the next command. The **universal entry point** for Loa — the only command you need to remember.

## Invocation

```
/loa              # Show status, health, journey, and suggestion
/loa --help       # Show the 5 Golden Path commands
/loa --help-full  # Show all 43+ commands
/loa --json       # JSON output for scripting
/loa --version    # Only show version info (quick check)
/loa doctor       # Run full health check (delegates to loa-doctor.sh)
```

## Workflow

1. **Detect State**: Run `.claude/scripts/loa-status.sh` and `.claude/scripts/golden-path.sh` to determine workflow state
2. **Trajectory Narrative**: Display project trajectory from `golden_trajectory()` — cycle history, current frontier, open visions (v1.39.0)
3. **Health Summary**: Show one-line system health (from `/loa doctor` quick check)
4. **Journey Bar**: Show golden path progress visualization
5. **Suggest Command**: Present the recommended **golden command** (not truename)
6. **Prompt User**: Ask user to proceed or explore

## Golden Path Integration (v1.30.0)

The `/loa` command now suggests **golden commands** instead of truenames:

| State | Old Suggestion | Golden Suggestion |
|-------|---------------|-------------------|
| `initial` | `/plan-and-analyze` | `/plan` |
| `prd_created` | `/architect` | `/plan` |
| `sdd_created` | `/sprint-plan` | `/plan` |
| `sprint_planned` | `/implement sprint-1` | `/build` |
| `implementing` | `/implement sprint-N` | `/build` |
| `reviewing` | `/review-sprint sprint-N` | `/review` |
| `auditing` | `/audit-sprint sprint-N` | `/review` |
| `complete` | `/deploy-production` | `/ship` |

## Output Format (Enhanced)

```
  Loa — Agent-Driven Development

  ## Trajectory
  This is cycle 14 of the Loa framework. Across 12 prior cycles and 93 sprints
  since 2026-02-11, the codebase has evolved through iterative bridge loops with
  adversarial review, persona-driven identity, and autonomous convergence.

  Current frontier: Environment Design for Agent Flourishing
  Open visions (3): Pluggable credential registry, Context Isolation, ...

  Health: ✓ All systems operational
  State:  Building (implementing sprint-2)

  ┌─────────────────────────────────────────────────────┐
  │  /plan ━━━━━━━ /build ━━●━━━━ /review ─── /ship    │
  │                     ▲                                │
  │                 you are here                         │
  └─────────────────────────────────────────────────────┘

  Progress: [████████████░░░░░░░░] 60%
  Sprint 2 of 3 — 1 complete

  Next: /build
  Continue implementing sprint-2.

  Run /loa --help for all commands.
```

### Health Summary Line

Run a quick health check and display one-line summary:

```bash
# Run golden-path.sh for state detection
source .claude/scripts/golden-path.sh
suggested=$(golden_suggest_command)
journey=$(golden_format_journey)
```

The health line shows:
- `✓ All systems operational` (green) — no issues
- `⚠ 2 warnings — run /loa doctor` (yellow) — non-blocking issues
- `✗ System unhealthy — run /loa doctor` (red) — blocking issues

When warnings or issues are present (yellow or red), append after the health line:
```
Something broken? /feedback reports it directly.
```
Do NOT show this line when health is clean (green).

### Journey Bar

The journey bar shows position in the golden path:

```
/plan ━━━━━●━━━━━ /build ─── /review ─── /ship
      ▲
  you are here
```

Using `golden_format_journey()` from golden-path.sh.

## `/loa --help` Output

```
The Golden Path — 5 commands, full development cycle:

  /loa      Where am I? What's next?
  /plan     Plan your project (requirements → architecture → sprints)
  /build    Build the current sprint
  /review   Review and audit your work
  /ship     Deploy and archive

Power user commands:
  /plan-and-analyze    Create PRD only
  /architect           Design architecture only
  /sprint-plan         Plan sprints only
  /implement sprint-N  Build specific sprint
  /review-sprint N     Review specific sprint
  /audit-sprint N      Security audit specific sprint
  /run sprint-plan     Autonomous mode (overnight)

Ad-hoc:
  /feedback            Report issues or suggestions

Diagnostics:
  /loa doctor          System health check
  /loa doctor --json   CI-friendly health check

Run /loa --help-full for all commands.
```

## `/loa --help-full` Output

Show all commands grouped by category:

```
All Loa Commands

  Core Workflow (Golden Path):
    /loa                     Where am I? What's next?
    /plan                    Plan (requirements → architecture → sprints)
    /build                   Build the current sprint
    /review                  Review and audit your work
    /ship                    Deploy and archive

  Planning (Truenames):
    /plan-and-analyze        Create PRD with context-first discovery
    /architect               Design system architecture → SDD
    /sprint-plan             Create sprint plan with task breakdown

  Implementation:
    /implement sprint-N      Implement specific sprint
    /review-sprint sprint-N  Code review for specific sprint
    /audit-sprint sprint-N   Security audit for specific sprint
    /bug                     Triage and fix a bug (lightweight workflow)
    /deploy-production       Deploy to production

  Autonomous:
    /run sprint-N            Autonomous sprint execution
    /run sprint-plan         Execute all sprints autonomously
    /run --bug "desc"        Autonomous bug fix
    /run-status              Check run progress
    /run-halt                Stop active run
    /run-resume              Resume halted run
    /run-bridge              Iterative excellence loop (bridge)
    /autonomous              Full autonomous workflow
    /simstim                 HITL accelerated workflow

  Analysis:
    /ride                    Analyze existing codebase
    /audit                   Full codebase security audit
    /validate                Validation suite
    /oracle                  Code pattern analysis
    /flatline-review         Multi-model adversarial review

  Framework:
    /mount                   Install Loa on a repo
    /update-loa              Pull framework updates
    /loa doctor              System health check
    /ledger                  Sprint ledger management
    /archive-cycle           Archive development cycle
    /constructs              Browse construct packs

  Learning:
    /compound                Extract learnings from cycles
    /enhance                 Improve prompt quality
    /feedback                Submit DX feedback
    /translate               Executive translations
```

## State Detection

The workflow-state.sh script detects states, and golden-path.sh maps them to golden commands:

| State | Condition | Golden Command |
|-------|-----------|----------------|
| `bug_active` | Active bug fix in `.run/bugs/` | `/build` |
| `initial` | No `prd.md` exists | `/plan` |
| `prd_created` | PRD exists, no SDD | `/plan` |
| `sdd_created` | SDD exists, no sprint plan | `/plan` |
| `sprint_planned` | Sprint plan exists, no work started | `/build` |
| `implementing` | Sprint in progress | `/build` |
| `reviewing` | Awaiting review | `/review` |
| `auditing` | Awaiting security audit | `/review` |
| `complete` | All sprints done | `/ship` |

**Note**: `bug_active` takes priority over all other states. When a bug fix is in progress, `/loa` shows bug status and `/build` routes to the bug's micro-sprint.

## User Prompts (v1.34.0 — Context-Aware Menu)

After displaying status, generate a dynamic menu from the workflow state:

1. Run `golden_menu_options` from `golden-path.sh` to get state-aware options
2. Parse the pipe-delimited output (format: `label|description|action`)
3. Build AskUserQuestion with the parsed options
4. The first option is always the recommended action — append "(Recommended)" to its label
5. The last option is always "View all commands"

### Routing

When the user selects an option, invoke the corresponding action:

| Action Value | How to Handle |
|-------------|---------------|
| `plan` | Invoke the `/plan` skill |
| `build` | Invoke the `/build` skill |
| `review` | Invoke the `/review` skill |
| `ship` | Invoke the `/ship` skill |
| `loa-setup` | Invoke the `/loa setup` skill |
| `loa-doctor` | Run `.claude/scripts/loa-doctor.sh` and display results |
| `archive-cycle` | **Confirm first**: "This will archive the current cycle and prepare for a new one. The archive is recoverable. Continue?" — then invoke `/archive-cycle` |
| `read:PATH` | Read the file at PATH and display its contents |
| `help-full` | Display the `/loa --help-full` output (see below) |

**Fallback**: If a skill invocation is denied or fails, display the equivalent command as a copyable code block so the user can invoke it manually. Example: "Run `/plan` to continue."

### Example Menu (implementing state)

```yaml
question: "What would you like to do?"
options:
  - label: "Build sprint-2 (Recommended)"
    description: "Continue implementing the current sprint"
  - label: "Review sprint-1"
    description: "Code review and security audit"
  - label: "Check system health"
    description: "Run full diagnostic check"
  - label: "View all commands"
    description: "See all available Loa commands"
```

## Implementation Notes

0. **Generate trajectory narrative** (v1.39.0 — before all other output):
   ```bash
   source .claude/scripts/golden-path.sh
   trajectory=$(golden_trajectory)
   # Display trajectory output as the opening section
   # If empty, skip silently (graceful degradation)
   ```
   The trajectory provides continuity of purpose — agents and humans see where the project
   has been, what it has learned, and what it is becoming. Displayed once per session,
   before the health summary.

   Config toggle: `golden_path.show_trajectory: true` (default: true)
   To disable: set `golden_path.show_trajectory: false` in `.loa.config.yaml`

1. **Run loa-status.sh** for version and state info:
   ```bash
   status_json=$(.claude/scripts/loa-status.sh --json)
   ```

2. **Run golden-path.sh** for golden command resolution:
   ```bash
   source .claude/scripts/golden-path.sh
   suggested=$(golden_suggest_command)
   journey=$(golden_format_journey)
   phase=$(golden_detect_plan_phase)
   sprint=$(golden_detect_sprint)
   ```

2b. **Check for active bug fix** (v1.32.0 — Issue #278):
   ```bash
   source .claude/scripts/golden-path.sh
   if active_bug=$(golden_detect_active_bug 2>/dev/null); then
     bug_state=$(jq -r '.state' ".run/bugs/${active_bug}/state.json")
     bug_title=$(jq -r '.bug_title' ".run/bugs/${active_bug}/state.json")
     bug_sprint=$(jq -r '.sprint_id' ".run/bugs/${active_bug}/state.json")
     # Display: "Active Bug Fix: {active_bug} — {bug_title} ({bug_state})"
     # Suggested command: /build (routes to bug micro-sprint)
   fi
   ```
   If an active bug is detected, display it prominently before the journey bar.

2c. **Check for active bridge loop** (v1.34.0 — Issue #292):
   ```bash
   source .claude/scripts/golden-path.sh
   bridge_state=$(golden_detect_bridge_state)
   if [[ "$bridge_state" != "none" && "$bridge_state" != "JACKED_OUT" ]]; then
     bridge_progress=$(golden_bridge_progress)
     # Display: "$bridge_progress"
   fi
   ```
   If a bridge is active, display its progress after bug detection but before the journey bar.

2d. **Lore context for naming** (v1.34.0):
   When displaying command names or framework concepts, reference the Lore Knowledge Base
   (`.claude/data/lore/`) for naming context. For example, if a user asks "why is it called
   a bridge?" or "what does 'jacked out' mean?", load the relevant glossary entry from
   `.claude/data/lore/mibera/glossary.yaml` and use the `short` field for inline explanation.

3. **Health summary** (quick check):
   ```bash
   # If loa-doctor.sh exists (from PR #218), run quick check
   if [[ -x .claude/scripts/loa-doctor.sh ]]; then
     health_json=$(.claude/scripts/loa-doctor.sh --json --quick 2>/dev/null)
     health_status=$(echo "$health_json" | jq -r '.status')
     health_warnings=$(echo "$health_json" | jq '.warnings // 0')
     health_issues=$(echo "$health_json" | jq '.issues // 0')
   fi
   ```

4. **Prompt Enhancement Statistics** (v1.17.0):
   ```bash
   today=$(date +%Y-%m-%d)
   log_file="grimoires/loa/a2a/trajectory/prompt-enhancement-${today}.jsonl"

   if [[ -f "$log_file" ]]; then
     enhanced=$(grep -c '"action":"ENHANCED"' "$log_file" 2>/dev/null || echo 0)
     skipped=$(grep -c '"action":"SKIP"' "$log_file" 2>/dev/null || echo 0)
     errors=$(grep -c '"action":"ERROR"' "$log_file" 2>/dev/null || echo 0)
     avg_latency=$(jq -s 'map(.latency_ms // 0) | add / length | floor' "$log_file" 2>/dev/null || echo "N/A")
   fi
   ```

   If no trajectory data exists, show: "Prompt Enhancement: No activity today"

5. **Invisible Retrospective Statistics** (v1.19.0):
   ```bash
   today=$(date +%Y-%m-%d)
   retro_log="grimoires/loa/a2a/trajectory/retrospective-${today}.jsonl"

   if [[ -f "$retro_log" ]]; then
     detected=$(grep -c '"action":"DETECTED"' "$retro_log" 2>/dev/null || echo 0)
     extracted=$(grep -c '"action":"EXTRACTED"' "$retro_log" 2>/dev/null || echo 0)
     skipped=$(grep -c '"action":"SKIPPED"' "$retro_log" 2>/dev/null || echo 0)
   fi
   ```

## Error Handling

| Error | Resolution |
|-------|------------|
| workflow-state.sh missing | "Workflow detection unavailable. Try `/help`." |
| golden-path.sh missing | Fall back to truename suggestions |
| Invalid state | "Unable to determine state. Check grimoires/loa/ files." |
| User cancels | Exit gracefully with no action |

## Integration

The `/loa` command integrates with:

- **golden-path.sh**: Golden command resolution, journey bar, state detection
- **loa-status.sh**: Version info, workflow state
- **loa-doctor.sh**: Health summary (if available from PR #218)
- **workflow-chain.yaml**: State definitions
- **All skill commands**: Can be called from `/loa` prompt

## Examples

### First Time User

```
/loa

  Loa — Agent-Driven Development

  Health: ✓ All systems operational
  State:  Ready to start

  ┌─────────────────────────────────────────────────────┐
  │  /plan ●━━━━━━ /build ─── /review ─── /ship        │
  │     ▲                                                │
  │ you are here                                         │
  └─────────────────────────────────────────────────────┘

  No PRD found. Ready to start planning.

  Something unexpected? /feedback reports it directly.

  Next: /plan
  Gather requirements and plan your project.
```

### Mid-Development

```
/loa

  Loa — Agent-Driven Development

  Health: ⚠ 1 warning — run /loa doctor
  State:  Building (implementing sprint-2)

  ┌─────────────────────────────────────────────────────┐
  │  /plan ━━━━━━━ /build ━━●━━━━ /review ─── /ship    │
  │                     ▲                                │
  │                 you are here                         │
  └─────────────────────────────────────────────────────┘

  Progress: [████████████░░░░░░░░] 60%
  Sprint 2 of 3 — 1 complete

  Next: /build
  Continue implementing sprint-2.
```

### Active Bug Fix

```
/loa

  Loa — Agent-Driven Development

  Health: ✓ All systems operational
  State:  Bug Fix in Progress

  Active Bug Fix: 20260211-a3f2b1
    Title: Login fails with + in email
    State: IMPLEMENTING
    Sprint: sprint-bug-3

  ┌─────────────────────────────────────────────────────┐
  │  /plan ━━━━━━━ /build ━━●━━━━ /review ─── /ship    │
  │                     ▲                                │
  │                 you are here                         │
  └─────────────────────────────────────────────────────┘

  Next: /build
  Continue bug fix implementation (sprint-bug-3).
```

### All Done

```
/loa

  Loa — Agent-Driven Development

  Health: ✓ All systems operational
  State:  Ready to ship

  ┌─────────────────────────────────────────────────────┐
  │  /plan ━━━━━━━ /build ━━━━━━━ /review ━━━━━ /ship ●│
  │                                                  ▲   │
  │                                          you are here│
  └─────────────────────────────────────────────────────┘

  All 3 sprints reviewed and audited.

  Next: /ship
  Deploy to production and archive the cycle.
```

## Configuration

```yaml
# .loa.config.yaml
guided_workflow:
  enabled: true              # Enable /loa command
  auto_execute: false        # Auto-run suggested command (default: prompt)
  show_progress_bar: true    # Display visual progress
  show_alternatives: true    # Show alternative commands on 'n'
  golden_path: true          # Use golden command suggestions (default: true)

golden_path:
  show_trajectory: true      # Display trajectory narrative in /loa (v1.39.0)
```
