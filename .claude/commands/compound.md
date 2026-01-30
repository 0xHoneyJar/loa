# /compound

End-of-cycle learning extraction command that reviews all work from the current development cycle and extracts reusable learnings.

## Synopsis

```
/compound [subcommand] [options]
```

## Description

The `/compound` command orchestrates the complete compound learning cycle:
1. **Review** - Analyze trajectory logs for the current cycle
2. **Detect** - Find cross-session patterns
3. **Extract** - Generate skills from qualified patterns
4. **Consolidate** - Update NOTES.md and ledger

This is the primary command for capturing institutional knowledge at the end of a development cycle.

## Subcommands

### /compound (default)

Run the full compound review cycle.

```bash
/compound                    # Full review with prompts
/compound --dry-run          # Preview without changes
/compound --review-only      # Extract without promotion
/compound --force            # Skip confirmations
```

### /compound status

Show current compound learning status.

```bash
/compound status             # Show status summary
```

Output includes:
- Current cycle information
- Pending extractions count
- Skills in skills-pending/
- Recent patterns detected

### /compound changelog

Generate cycle changelog (standalone).

```bash
/compound changelog                    # Current cycle
/compound changelog --cycle N          # Specific cycle
/compound changelog --output json      # JSON format
```

### /compound archive

Archive cycle artifacts.

```bash
/compound archive                      # Archive current cycle
/compound archive --cycle N            # Archive specific cycle
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Preview without making changes | false |
| `--review-only` | Extract learnings but skip promotion | false |
| `--no-promote` | Skip skill promotion step | false |
| `--no-archive` | Skip archive creation | false |
| `--force` | Skip confirmation prompts | false |
| `--cycle N` | Specify cycle number | current |
| `--days N` | Override date range (days) | from ledger |

## Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    /compound WORKFLOW                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. DETECT CYCLE                                                     │
│     └── Read ledger.json → Get active cycle dates                   │
│                                                                      │
│  2. BATCH RETROSPECTIVE                                              │
│     └── /retrospective --batch --days N                             │
│     └── Pattern detection & clustering                               │
│                                                                      │
│  3. QUALITY GATES                                                    │
│     └── Apply 4-gate filter to patterns                             │
│     └── Filter to qualified patterns only                           │
│                                                                      │
│  4. SKILL EXTRACTION                                                 │
│     └── Generate SKILL.md for each qualified pattern                │
│     └── Write to skills-pending/                                    │
│                                                                      │
│  5. CONSOLIDATION (unless --review-only)                            │
│     └── Update NOTES.md ## Learnings section                        │
│     └── Update ledger with compound_completed_at                    │
│     └── Promote approved skills to skills/                          │
│                                                                      │
│  6. ARCHIVE (unless --no-archive)                                   │
│     └── Create archive/cycle-N/                                     │
│     └── Copy PRD, SDD, trajectory subset                            │
│                                                                      │
│  7. CHANGELOG                                                        │
│     └── Generate CHANGELOG-cycle-N.md                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Examples

### Standard End-of-Cycle Review

```bash
# At the end of a development cycle
/compound

# This will:
# 1. Detect patterns from the cycle
# 2. Extract qualified learnings
# 3. Prompt for skill promotion
# 4. Update ledger and NOTES.md
# 5. Create archive and changelog
```

### Preview Mode

```bash
# See what would be extracted without making changes
/compound --dry-run
```

### Mid-Cycle Check

```bash
# Check for patterns without full promotion
/compound --review-only
```

### Specific Cycle

```bash
# Review a past cycle
/compound --cycle 3
```

## Output Files

| File | Description |
|------|-------------|
| `grimoires/loa/skills-pending/{skill}/SKILL.md` | Extracted skills |
| `grimoires/loa/NOTES.md` | Updated ## Learnings section |
| `grimoires/loa/ledger.json` | Updated with compound_completed_at |
| `grimoires/loa/CHANGELOG-cycle-N.md` | Cycle changelog |
| `grimoires/loa/archive/cycle-N/` | Archived artifacts |
| `grimoires/loa/a2a/compound/patterns.json` | Updated patterns registry |

## Trajectory Events

- `compound_start` - Review begins
- `pattern_detected` - Pattern found
- `learning_extracted` - Skill generated
- `compound_complete` - Review finished

## Configuration

From `.loa.config.yaml`:

```yaml
compound_learning:
  enabled: true
  pattern_detection:
    min_occurrences: 2
    max_age_days: 90
  quality_gates:
    discovery_depth:
      min_score: 5
    reusability:
      min_score: 5
    trigger_clarity:
      min_score: 5
    verification:
      min_score: 3
```

## Related Commands

- `/retrospective --batch` - Multi-session analysis only
- `/skill-audit` - Manage pending skills
- `/learning-report` - View effectiveness metrics

## Goal Contribution

- **G-1**: Cross-session pattern detection ✓
- **G-2**: Reduce repeated investigations ✓
- **G-3**: Automate knowledge consolidation ✓
- **G-4**: Close apply-verify loop (via tracking)
