# Grimoires

Home to all grimoire directories for the Loa framework.

## Structure

| Directory | Git Status | Purpose |
|-----------|------------|---------|
| `loa/` | Ignored | Project-specific state (PRD, SDD, notes, trajectories) |
| `pub/` | Tracked | Public documents (research, shareable artifacts) |

## The Grimoire Pattern

Grimoires are project memory stores that persist across sessions. The pattern separates:

1. **Private State** (`loa/`) - Generated during workflow, contains sensitive project details
2. **Public Content** (`pub/`) - Research, documentation, and artifacts meant to be shared

## Usage

```bash
# Private project documents
grimoires/loa/prd.md
grimoires/loa/sdd.md
grimoires/loa/sprint.md
grimoires/loa/NOTES.md

# Public shareable content
grimoires/pub/research/analysis.md
grimoires/pub/docs/guide.md
```

## Adding New Grimoires

Teams can add additional grimoires (e.g., `gtm/` for go-to-market) following the same pattern:

```
grimoires/
├── loa/        # Core framework state
├── pub/        # Public content
└── gtm/        # Go-to-market state (example)
```
