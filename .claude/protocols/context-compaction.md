# Context Compaction Protocol

> **Version**: 1.0 (v0.11.0 Claude Platform Integration)
> **Integration**: Client-side compaction with Lossless Ledger Protocol

## Purpose

Define rules and behavior for client-side context compaction in Claude Code. Ensures critical information survives compaction while allowing removal of redundant or processed content.

## Preservation Categories

### ALWAYS Preserved

These items must survive any compaction event:

| Item | Rationale |
|------|-----------|
| `NOTES.md` Session Continuity | Recovery anchor for new sessions |
| `NOTES.md` Decision Log | Audit trail, reasoning persistence |
| Trajectory entries | External files, already lossless |
| Active bead references | Task continuity |
| Sprint context | Current work state |
| **Run mode state** (v1.27.0) | `.run/sprint-plan-state.json` - autonomous execution continuity |

### Run Mode State Recovery (v1.27.0)

**CRITICAL**: After compaction, ALWAYS check for active run mode:

```bash
if [[ -f .run/sprint-plan-state.json ]]; then
  state=$(jq -r '.state' .run/sprint-plan-state.json)
  if [[ "$state" == "RUNNING" ]]; then
    # Resume autonomous execution - DO NOT prompt for confirmation
    current=$(jq -r '.sprints.current' .run/sprint-plan-state.json)
    # Continue sprint loop from $current
  fi
fi
```

If `state=RUNNING`, the agent MUST resume autonomous sprint execution without user confirmation. This enables overnight/unattended runs to survive context compaction.

### COMPACTABLE

These items can be summarized or removed after use:

| Item | When Compactable | Replacement |
|------|------------------|-------------|
| Tool results | After processing | Summary/path reference |
| Thinking blocks | After trajectory logging | Trajectory entry reference |
| Verbose debug output | After problem resolution | Brief status |
| Redundant file reads | After first extraction | Path + line refs |
| Intermediate outputs | After final synthesis | Result only |

## Compaction Triggers

### Automatic Triggers

1. **Token Threshold**: When context approaches limit (~190k tokens)
2. **Session End**: Before natural session termination
3. **Phase Transition**: Between major workflow phases

### Manual Triggers

1. `/compact` command - User-initiated compaction
2. `/clear` command - Full reset (uses recovery protocol)
3. `context-manager.sh compact` - Pre-check what would be compacted

## Compaction Workflow

```
COMPACTION SEQUENCE:

1. Pre-Check Phase
   ├── Verify NOTES.md Session Continuity exists
   ├── Verify Decision Log updated
   ├── Verify trajectory logged (if thinking occurred)
   └── Verify active beads referenced

2. Preservation Phase
   ├── Lock preserved items
   ├── Mark for compaction
   └── Validate no critical loss

3. Compaction Phase
   ├── Summarize tool results
   ├── Replace thinking blocks with refs
   ├── Remove redundant reads
   └── Compress intermediate outputs

4. Verification Phase
   ├── Confirm preserved items intact
   ├── Validate recovery possible
   └── Log compaction event
```

## Integration with Lossless Ledger

### Truth Hierarchy Alignment

Compaction respects the Lossless Ledger truth hierarchy:

```
1. CODE         → Never in context, always re-readable
2. BEADS        → External ledger, refs preserved
3. NOTES.md     → Critical sections preserved
4. TRAJECTORY   → External files, refs preserved
5. CONTEXT      → Compactable (this is what we're managing)
```

### Recovery Guarantee

Post-compaction, the following recovery sequence must succeed:

```bash
# Level 1 Recovery (~100 tokens)
context-manager.sh recover 1

# Level 2 Recovery (~500 tokens)
context-manager.sh recover 2

# Level 3 Recovery (~2000 tokens)
context-manager.sh recover 3
```

## Configuration

```yaml
# .loa.config.yaml
context_management:
  client_compaction: true          # Enable/disable compaction
  preserve_notes_md: true          # Always preserve NOTES.md
  simplified_checkpoint: true      # Use 3-step checkpoint
  auto_trajectory_log: true        # Auto-log thinking blocks

  # Preservation rules (customizable)
  preservation_rules:
    always_preserve:
      - notes_session_continuity
      - notes_decision_log
      - trajectory_entries
      - active_beads
    compactable:
      - tool_results
      - thinking_blocks
      - verbose_debug
      - redundant_file_reads
      - intermediate_outputs
```

## Commands

### Pre-Check

```bash
# Show what would be compacted
context-manager.sh compact --dry-run
```

### Preservation Rules

```bash
# Show current rules
context-manager.sh rules

# JSON output for automation
context-manager.sh rules --json
```

### Verify Preservation

```bash
# Check critical sections exist
context-manager.sh preserve

# Check specific section
context-manager.sh preserve session_continuity
```

## Error Handling

### Missing Critical Sections

If a critical section is missing before compaction:

1. **Warn** - Alert user to missing section
2. **Block** - In strict mode, prevent compaction
3. **Create** - Offer to initialize missing section

### Recovery Failure

If recovery fails after compaction:

1. Log failure to trajectory
2. Trigger Level 3 recovery (full context)
3. Flag potential data loss for review

## Metrics

Track compaction efficiency:

| Metric | Target |
|--------|--------|
| Pre-compaction size | Baseline |
| Post-compaction size | <50% of pre |
| Recovery success rate | 100% |
| Critical section preservation | 100% |

## Related Protocols

- `session-continuity.md` - Recovery procedures
- `synthesis-checkpoint.md` - Checkpoint process
- `jit-retrieval.md` - Lightweight identifiers
- `attention-budget.md` - Token thresholds
