# /retrospective --batch

Extend the retrospective command to support multi-session batch analysis for cross-session pattern detection.

## Synopsis

```
/retrospective --batch [options]
```

## Description

The `--batch` flag enables multi-session trajectory analysis, detecting patterns that span multiple development sessions. This is part of the Compound Learning System (Goal G-1: Cross-session pattern detection).

Unlike the standard `/retrospective` which analyzes a single session, `--batch` looks across days/weeks to find:
- **Repeated errors** - Same problem occurring multiple times
- **Convergent solutions** - Different problems solved the same way
- **Anti-patterns** - Mistakes made repeatedly before learning
- **Project conventions** - Emerging patterns that should become standards

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--days N` | Analyze last N days | 7 |
| `--sprint N` | Analyze sprint N (overrides --days) | - |
| `--start DATE` | Start date (YYYY-MM-DD) | - |
| `--end DATE` | End date (YYYY-MM-DD) | - |
| `--dry-run` | Show findings without writing | false |
| `--min-confidence N` | Minimum pattern confidence (0-1) | 0.6 |
| `--output FORMAT` | Output format: markdown, json | markdown |
| `--force` | Skip confirmation prompts | false |

## Examples

```bash
# Analyze last 7 days (default)
/retrospective --batch

# Analyze last 14 days
/retrospective --batch --days 14

# Analyze specific sprint
/retrospective --batch --sprint 3

# Preview without writing
/retrospective --batch --dry-run

# Higher confidence threshold
/retrospective --batch --min-confidence 0.8

# JSON output for scripting
/retrospective --batch --output json
```

## Output

### Pattern Presentation

Patterns are presented with confidence levels:

```
## Cross-Session Patterns Found

### HIGH Confidence (80%+)

🔴 **NATS Connection Handling** (repeated_error)
   - Occurred 5 times across 3 sessions
   - Sessions: 2025-01-15, 2025-01-22, 2025-01-29
   - Error: "Connection refused", "Connection timeout"
   - Solution: Durable consumers with reconnection handlers
   - [Extract to Skill?] [View Details]

### MEDIUM Confidence (50-79%)

🟡 **TypeScript Strict Mode** (convergent_solution)
   - Occurred 3 times across 2 sessions
   ...
```

### Actions

After presenting patterns, the command prompts:
- **Y** - Extract all qualified patterns as skills
- **n** - Skip extraction
- **s** - Select specific patterns to extract

## Workflow

1. **COLLECT** - Gather trajectory files for date range
2. **PARSE** - Stream events, extract error/solution pairs
3. **DETECT** - Run pattern detection algorithm (Jaccard similarity)
4. **CLUSTER** - Group similar events into pattern candidates
5. **GATE** - Apply quality gates to each pattern
6. **PRESENT** - Show findings with confidence scores
7. **CONFIRM** - Get user approval (unless --force)
8. **EXTRACT** - Write approved patterns to skills-pending/
9. **LOG** - Write compound-learning trajectory events

## Trajectory Events

The batch retrospective logs these events:
- `compound_review_start` - Analysis begins
- `pattern_detected` - Each pattern found
- `learning_extracted` - Skills extracted
- `compound_review_complete` - Analysis ends

## Configuration

Settings from `.loa.config.yaml`:

```yaml
compound_learning:
  pattern_detection:
    min_occurrences: 2
    max_age_days: 90
  similarity:
    fallback:
      jaccard_threshold: 0.6
```

## Related Commands

- `/retrospective` - Single session analysis
- `/compound` - Full cycle review (includes batch retrospective)
- `/skill-audit` - Manage extracted skills

## Goal Contribution

- **G-1**: Enable cross-session pattern detection ✓
- **G-2**: Reduce repeated investigations (by surfacing patterns)
