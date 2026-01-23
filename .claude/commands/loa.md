---
name: loa
description: Guided workflow navigation showing current state and next steps
output: Workflow progress and suggested next command
command_type: wizard
---

# /loa - Guided Workflow Navigator

## Purpose

Show current workflow state, progress, and suggest the next command. Reduces friction for users unfamiliar with the Loa workflow by providing clear guidance on what to do next.

## Invocation

```
/loa              # Show status and suggestion
/loa --json       # JSON output for scripting
```

## Workflow

1. **Detect State**: Run `.claude/scripts/workflow-state.sh` to determine current workflow state
2. **Display Progress**: Show visual progress indicator
3. **Suggest Command**: Present the recommended next command
4. **Prompt User**: Ask user to proceed, skip, or exit

## State Detection

The workflow-state.sh script detects:

| State | Condition | Suggested Command |
|-------|-----------|-------------------|
| `initial` | No `prd.md` exists | `/plan-and-analyze` |
| `prd_created` | PRD exists, no SDD | `/architect` |
| `sdd_created` | SDD exists, no sprint plan | `/sprint-plan` |
| `sprint_planned` | Sprint plan exists, no work started | `/implement sprint-1` |
| `implementing` | Sprint in progress | `/implement sprint-N` |
| `reviewing` | Awaiting review | `/review-sprint sprint-N` |
| `auditing` | Awaiting security audit | `/audit-sprint sprint-N` |
| `complete` | All sprints done | `/deploy-production` |

## Output Format

```
═══════════════════════════════════════════════════
 Loa Workflow Status
═══════════════════════════════════════════════════

 State: implementing
 Implementing sprint-2.

 Progress: [████████████░░░░░░░░] 60%

 Current Sprint: sprint-2
 Sprints: 1/3 complete

───────────────────────────────────────────────────
 Suggested: /implement sprint-2
═══════════════════════════════════════════════════

Run suggested command? [Y/n/exit]
```

## User Prompts

After displaying status, prompt the user:

| Input | Action |
|-------|--------|
| `Y` or `y` or Enter | Execute the suggested command |
| `n` or `N` | Show available commands without executing |
| `exit` or `q` | Exit without action |

## Available Commands Display

When user selects `n`, show:

```
Available commands at this stage:

  /implement sprint-2   ← Suggested (continue implementation)
  /review-sprint sprint-1  (review completed sprint)
  /validate             (run validation suite)
  /audit                (full codebase audit)

Type a command or 'exit' to quit:
```

## Implementation Notes

1. **Run workflow-state.sh**:
   ```bash
   state_json=$(.claude/scripts/workflow-state.sh --json)
   ```

2. **Parse JSON output**:
   - `state`: Current workflow state
   - `current_sprint`: Active sprint ID
   - `progress_percent`: Progress bar value
   - `suggested_command`: What to run next

3. **Display formatted output** with progress bar

4. **Use AskUserQuestion** for user prompt:
   ```yaml
   question: "Run suggested command?"
   options:
     - label: "Yes, run it"
       description: "Execute the suggested command now"
     - label: "Show alternatives"
       description: "See other available commands"
   ```

## Error Handling

| Error | Resolution |
|-------|------------|
| workflow-state.sh missing | "Workflow detection unavailable. Try `/help`." |
| Invalid state | "Unable to determine state. Check grimoires/loa/ files." |
| User cancels | Exit gracefully with no action |

## Integration

The `/loa` command integrates with:

- **workflow-chain.yaml**: Uses same state definitions
- **suggest-next-step.sh**: Consistent suggestions
- **All skill commands**: Can be called from `/loa` prompt

## Examples

### First Time User

```
/loa

═══════════════════════════════════════════════════
 Loa Workflow Status
═══════════════════════════════════════════════════

 State: initial
 No PRD found. Ready to start discovery.

 Progress: [░░░░░░░░░░░░░░░░░░░░] 0%

 Sprints: 0/0 complete

───────────────────────────────────────────────────
 Suggested: /plan-and-analyze
═══════════════════════════════════════════════════

This command will gather requirements and create a PRD.
Ready to start? [Y/n/exit]
```

### Mid-Development

```
/loa

═══════════════════════════════════════════════════
 Loa Workflow Status
═══════════════════════════════════════════════════

 State: reviewing
 Review pending for sprint-2.

 Progress: [████████████████░░░░] 80%

 Current Sprint: sprint-2
 Sprints: 2/3 complete

───────────────────────────────────────────────────
 Suggested: /review-sprint sprint-2
═══════════════════════════════════════════════════

Run suggested command? [Y/n/exit]
```

## Configuration

```yaml
# .loa.config.yaml
guided_workflow:
  enabled: true              # Enable /loa command
  auto_execute: false        # Auto-run suggested command (default: prompt)
  show_progress_bar: true    # Display visual progress
  show_alternatives: true    # Show alternative commands on 'n'
```
