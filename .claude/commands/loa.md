---
name: loa
description: Guided workflow navigation showing current state and next steps
output: Workflow progress and suggested next command
command_type: wizard
---

# /loa - Guided Workflow Navigator

## Purpose

Show current workflow state, progress, version information, and suggest the next command. Reduces friction for users unfamiliar with the Loa workflow by providing clear guidance on what to do next.

## Invocation

```
/loa              # Show status, version, and suggestion
/loa --json       # JSON output for scripting
/loa --version    # Only show version info (quick check)
```

## Workflow

1. **Detect State**: Run `.claude/scripts/loa-status.sh` to determine current workflow state and version info
2. **Display Progress**: Show visual progress indicator with framework version
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
═══════════════════════════════════════════════════════════════
 Loa Status
═══════════════════════════════════════════════════════════════

Framework Version
  Version: 1.15.0
  Ref:     v1.15.0 (stable release)
  Updated: 2026-01-15
  Source:  https://github.com/0xHoneyJar/loa

───────────────────────────────────────────────────────────────

Workflow State
  State: implementing
  Implementing sprint-2.
  Progress: [████████████░░░░░░░░] 60%
  Current Sprint: sprint-2
  Sprints: 1/3 complete

───────────────────────────────────────────────────────────────

Prompt Enhancement (v1.17.0)
  Today: 5 enhanced, 12 skipped, 0 errors
  Avg latency: 42ms
  Last enhanced: 2 hours ago

───────────────────────────────────────────────────────────────

Invisible Retrospective (v1.19.0)
  Today: 3 detected, 1 extracted, 2 skipped
  Session: 1 learning captured
  Last extraction: 2 hours ago

───────────────────────────────────────────────────────────────
 Suggested: /implement sprint-2
═══════════════════════════════════════════════════════════════

Run suggested command? [Y/n/exit]
```

### Feature Branch Warning

When on a non-stable branch:

```
Framework Version
  Version: 1.15.0
  Ref:     feature/new-thing (feature branch)
  Warning: You're on a non-stable branch
  Tip: Run /update-loa @latest to switch to stable
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

1. **Run loa-status.sh** (includes version info):
   ```bash
   # Full status with version info
   status_json=$(.claude/scripts/loa-status.sh --json)

   # Quick version check only
   version_json=$(.claude/scripts/loa-status.sh --version --json)
   ```

2. **Parse JSON output**:
   - `state`: Current workflow state
   - `current_sprint`: Active sprint ID
   - `progress_percent`: Progress bar value
   - `suggested_command`: What to run next
   - `framework.version`: Current framework version
   - `framework.ref`: Current ref (tag/branch/commit)
   - `framework.ref_type`: Type of ref
   - `framework.warning`: Warning if on non-stable ref
   - `framework.update_available`: True if update is available

3. **Display formatted output** with version info and progress bar

4. **Prompt Enhancement Statistics** (v1.17.0):
   ```bash
   # Parse today's trajectory log for enhancement metrics
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
   # Parse today's retrospective trajectory log for learning metrics
   today=$(date +%Y-%m-%d)
   retro_log="grimoires/loa/a2a/trajectory/retrospective-${today}.jsonl"

   if [[ -f "$retro_log" ]]; then
     detected=$(grep -c '"action":"DETECTED"' "$retro_log" 2>/dev/null || echo 0)
     extracted=$(grep -c '"action":"EXTRACTED"' "$retro_log" 2>/dev/null || echo 0)
     skipped=$(grep -c '"action":"SKIPPED"' "$retro_log" 2>/dev/null || echo 0)
     disabled=$(grep -c '"action":"DISABLED"' "$retro_log" 2>/dev/null || echo 0)

     # Get last extraction timestamp
     last_extracted=$(grep '"action":"EXTRACTED"' "$retro_log" | tail -1 | jq -r '.timestamp' 2>/dev/null)
   fi
   ```

   If no retrospective data exists, show: "Invisible Retrospective: No activity today"

   If feature is disabled in config, show: "Invisible Retrospective: Disabled"

5. **Use AskUserQuestion** for user prompt:
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
