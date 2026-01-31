# Context Editing Protocol

## Purpose

Define policies for automatic context compaction in long-running agentic workflows. Based on Anthropic's context editing feature which achieved **84% token reduction** in 100-turn evaluations.

**Key insight**: Context editing automatically clears stale tool calls and results when approaching token limits, enabling agents to complete workflows that would otherwise fail due to context exhaustion.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Loa Layer                            │
│  Defines: WHAT to compact, WHEN to trigger, priorities      │
├─────────────────────────────────────────────────────────────┤
│                      Runtime Layer                          │
│  Executes: Token counting, API calls, actual compaction     │
│  (Claude Code, Clawdbot, or custom runtime)                 │
├─────────────────────────────────────────────────────────────┤
│                        API Layer                            │
│  Anthropic: context-management-2025-06-27 beta header       │
└─────────────────────────────────────────────────────────────┘
```

## Compaction Triggers

### Threshold-Based

```yaml
# Trigger when context reaches 80% of limit
compact_threshold_percent: 80

# Example: 200K context window
# Trigger compaction at 160K tokens
```

### Phase-Based

```yaml
# Clear after these phases complete
clear_after_phases:
  - initialization    # Phase 1 complete
  - implementation    # Phase 5 complete
  - testing           # Phase 6 complete
```

### Attention Budget

```yaml
# Existing attention budget thresholds (PR #83)
attention_budget:
  single_search: 2000     # Per-operation limit
  accumulated: 5000       # Accumulated limit
  session_total: 15000    # Session hard limit
```

## Clearing Priority

Items are cleared in priority order (lowest priority first):

| Priority | Target | Description |
|----------|--------|-------------|
| 1 (lowest) | `stale_tool_results` | Old tool outputs no longer needed |
| 2 | `completed_phase_details` | Verbose logs from finished phases |
| 3 | `superseded_file_reads` | Files re-read with newer content |
| 4 | `intermediate_outputs` | Temporary computation results |
| 5 | `verbose_debug` | Debug logs and tracing |

## Preservation Rules

### Always Preserve (NEVER clear)

```yaml
preserve_artifacts:
  - trajectory_events         # Audit trail for decisions
  - quality_gate_results      # Gate pass/fail decisions
  - decision_records          # Architecture decisions
  - notes_session_continuity  # Recovery anchor
  - active_beads              # Current task state
```

### Why These Are Preserved

1. **trajectory_events**: Required for trajectory evaluation, debugging, and compliance
2. **quality_gate_results**: Evidence of passing gates (security, review)
3. **decision_records**: Architecture rationale survives context compaction
4. **notes_session_continuity**: Enables session recovery after /clear
5. **active_beads**: Current task context needed for continuity

## Runtime Integration

### Signal Protocol

```yaml
runtime_signals:
  # Signal FROM runtime TO Loa when context approaches limit
  context_near_limit: "CONTEXT_NEAR_LIMIT"

  # Signal FROM Loa TO runtime when compaction complete
  compaction_complete: "COMPACTION_COMPLETE"

  # Threshold that triggers the signal
  signal_threshold_percent: 80
```

### Runtime Implementation Notes

For runtime implementers (Claude Code, Clawdbot):

1. **Track token usage** per tool result
2. **Signal CONTEXT_NEAR_LIMIT** when threshold reached
3. **Invoke compaction protocol** based on Loa's configuration
4. **Clear items** in priority order until under threshold
5. **Signal COMPACTION_COMPLETE** when done

### Anthropic API Integration

```bash
# Enable context editing via beta header
# NOTE: The date (2025-06-27) is the API version identifier, not a future date.
# This is the official Anthropic beta header string.
curl https://api.anthropic.com/v1/messages \
  -H "anthropic-beta: context-management-2025-06-27" \
  ...
```

## Interaction with Other Protocols

### Lossless Ledger Protocol

Context editing respects the "Clear, Don't Compact" paradigm:
- Synthesize critical information to NOTES.md BEFORE clearing
- Never clear without first externalizing important data

### Structured Memory Protocol

Memory files (`grimoires/loa/memory/`) are OUTSIDE context:
- They are not subject to context editing
- They persist across sessions
- They can be queried to restore context after compaction

### Attention Budget (PR #83)

Context editing extends attention budgets:
- Attention budgets define per-skill thresholds
- Context editing provides automatic enforcement
- Both work together for token management

## Configuration

```yaml
# .loa.config.yaml
context_editing:
  enabled: true
  compact_threshold_percent: 80
  preserve_recent_turns: 5

  clear_targets:
    - stale_tool_results
    - completed_phase_details
    - superseded_file_reads
    - intermediate_outputs
    - verbose_debug

  clear_after_phases:
    - initialization
    - implementation
    - testing

  preserve_artifacts:
    - trajectory_events
    - quality_gate_results
    - decision_records
    - notes_session_continuity
    - active_beads
```

## Per-Skill Configuration

Skills can declare clearing behavior in SKILL.md frontmatter:

```yaml
---
name: implementing-tasks
context_editing:
  # Clear after specific phases within this skill
  clear_after_phases: [setup, coding]

  # Additional artifacts this skill needs preserved
  preserve_artifacts:
    - test_results
    - coverage_data
---
```

## Performance Expectations

Based on Anthropic benchmarks:

| Metric | Value | Source |
|--------|-------|--------|
| Token reduction | 84% | 100-turn web search evaluation |
| Improvement (editing alone) | 29% | Agentic search tasks |
| Improvement (with memory) | 39% | Combined with memory tool |

## Debugging

### Check Context Status

```bash
# Runtime should expose context metrics
# Example (hypothetical Claude Code command):
/context-status

# Output:
# Context: 142,000 / 200,000 tokens (71%)
# Preserved: 45,000 tokens
# Clearable: 97,000 tokens
# Status: NORMAL
```

### Force Compaction

```bash
# Manual compaction trigger (for testing)
/compact --reason "manual test"
```

## Related

- Configuration: `.loa.config.yaml` (context_editing section)
- Attention Budgets: `.claude/protocols/attention-budget.md`
- Lossless Ledger: `.claude/protocols/lossless-ledger.md`
- Memory Protocol: `.claude/protocols/memory.md`

## Sources

- [Anthropic Context Management](https://claude.com/blog/context-management)
- [Context Editing Documentation](https://platform.claude.com/docs/en/build-with-claude/context-window-management)
