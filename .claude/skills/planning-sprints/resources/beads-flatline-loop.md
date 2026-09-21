# Beads Flatline Loop

After creating beads from the sprint plan, optionally run the Flatline Beads Loop to refine the task graph:

```bash
# Check if beads exist and br is available
if command -v br &>/dev/null && [[ $(br list --json 2>/dev/null | jq 'length') -gt 0 ]]; then
    # Run iterative multi-model refinement
    .claude/scripts/beads-flatline-loop.sh --max-iterations 6 --threshold 5
fi
```

This implements the "Check your beads N times, implement once" pattern:
1. Exports current beads to JSON
2. Runs Flatline Protocol review on task graph
3. Applies HIGH_CONSENSUS suggestions
4. Repeats until changes "flatline" (< 5% change for 2 iterations)
5. Syncs final state to git

**When to use:**
- After `/sprint-plan` creates tasks
- Before `/run sprint-plan` begins execution
- When task decomposition seems questionable

**Skip when:**
- Simple projects with <10 tasks
- Time-critical execution needed
- Flatline Protocol is disabled
