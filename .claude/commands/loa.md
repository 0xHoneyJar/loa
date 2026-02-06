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
2. **Health Summary**: Show one-line system health (from `/loa doctor` quick check)
3. **Journey Bar**: Show golden path progress visualization
4. **Suggest Command**: Present the recommended **golden command** (not truename)
5. **Prompt User**: Ask user to proceed or explore

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
    /deploy-production       Deploy to production

  Autonomous:
    /run sprint-N            Autonomous sprint execution
    /run sprint-plan         Execute all sprints autonomously
    /run-status              Check run progress
    /run-halt                Stop active run
    /run-resume              Resume halted run
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
| `initial` | No `prd.md` exists | `/plan` |
| `prd_created` | PRD exists, no SDD | `/plan` |
| `sdd_created` | SDD exists, no sprint plan | `/plan` |
| `sprint_planned` | Sprint plan exists, no work started | `/build` |
| `implementing` | Sprint in progress | `/build` |
| `reviewing` | Awaiting review | `/review` |
| `auditing` | Awaiting security audit | `/review` |
| `complete` | All sprints done | `/ship` |

## User Prompts

After displaying status, prompt the user using AskUserQuestion:

```yaml
question: "What would you like to do?"
options:
  - label: "Run suggested"
    description: "Execute /build (continue implementing sprint-2)"
  - label: "Show all commands"
    description: "See all available commands"
  - label: "Run doctor"
    description: "Full system health check"
```

## Implementation Notes

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
```
