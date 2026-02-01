# Cycle-Based Compounding (Design Direction from Jani)

## The Pivot

**From**: Nightly scheduling (cron/launchd)
**To**: End-of-cycle trigger within loa's phase model

## Why This Is Better

1. **No external dependencies** - No cron, launchd, or scheduling setup
2. **Fits loa's existing model** - Just another phase in the workflow
3. **Cycle-scoped learnings** - More coherent than arbitrary day boundaries
4. **Direct handoff** - Learnings from cycle N feed directly into cycle N+1
5. **Natural trigger point** - After audit, before next PRD

## The Extended Phase Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    LOA DEVELOPMENT CYCLE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Phase 1        Phase 2         Phase 3         Phase 4        │
│   /plan-and-     /architect      /sprint-plan    /implement     │
│   analyze                                        (per sprint)   │
│       │              │               │               │          │
│       ▼              ▼               ▼               ▼          │
│   ┌──────┐      ┌──────┐       ┌──────┐       ┌──────┐         │
│   │ PRD  │─────▶│ SDD  │──────▶│Sprint│──────▶│ Code │         │
│   └──────┘      └──────┘       └──────┘       └──────┘         │
│                                                    │            │
│                                                    ▼            │
│   Phase 5        Phase 5.5        Phase 6         NEW!          │
│   /review-       /audit-          /deploy-        /compound     │
│   sprint         sprint           production                    │
│       │              │               │               │          │
│       ▼              ▼               ▼               ▼          │
│   ┌──────┐      ┌──────┐       ┌──────┐       ┌──────┐         │
│   │Review│─────▶│Audit │──────▶│Deploy│──────▶│LEARN │         │
│   └──────┘      └──────┘       └──────┘       └──────┘         │
│                                                    │            │
│                                                    │            │
│   ┌────────────────────────────────────────────────┘            │
│   │                                                             │
│   │  COMPOUND EFFECT: Cycle N learnings → Cycle N+1 context    │
│   │                                                             │
│   ▼                                                             │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    NEXT CYCLE                             │  │
│   │  /plan-and-analyze (with fresh learnings loaded)         │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## /compound Command Actions

| Step | Action | Output |
|------|--------|--------|
| 1 | Review entire cycle's work | Analysis of all sprints, sessions |
| 2 | Batch extract missed learnings | New skills to `skills-pending/` |
| 3 | Update NOTES.md | Cycle-level insights in Learnings section |
| 4 | Promote worthy skills | `skills-pending/` → `skills/` (or flag for review) |
| 5 | Generate cycle summary | Changelog of what was built + learned |
| 6 | Archive cycle artifacts | Move to `grimoires/loa/archive/cycle-N/` |
| 7 | Prepare fresh context | Clean slate for next PRD |

## Trigger Points

**Primary**: After final audit passes, before starting next PRD
```bash
# End of cycle flow
/audit-sprint sprint-N  # Final audit
/compound               # NEW: Extract learnings, prepare for next cycle
/plan-and-analyze       # Next cycle starts with fresh learnings
```

**Optional mid-cycle**: After any sprint if significant learnings accumulated
```bash
/compound --sprint-only  # Just extract from current sprint, don't archive
```

## Comparison: Nightly vs Cycle-Based

| Aspect | Nightly (Ryan Carson) | Cycle-Based (Loa) |
|--------|----------------------|-------------------|
| Trigger | cron/launchd | End of cycle phase |
| Scope | Day's work | Entire cycle (weeks) |
| Dependencies | External scheduler | None (built-in) |
| Granularity | Fine (daily) | Coarse (per cycle) |
| Context | Yesterday → Today | Cycle N → Cycle N+1 |
| Fit | Autonomous agents | Human-in-loop loa |

## Keeping the Compound Effect

The philosophy still applies:
> "Patterns discovered in Cycle 1 inform Cycle 2. Gotchas hit in Cycle 1 are avoided in Cycle 2."

The math changes slightly:
- **Nightly**: Patterns from Monday inform Tuesday
- **Cycle**: Patterns from MVP cycle inform V2 cycle

Both achieve compounding - just at different timescales.

## Coexistence with Inline Extraction

Still two modes, but scoped differently:

| Mode | When | Scope |
|------|------|-------|
| **Inline** (continuous-learning) | During implementation | Single task/session |
| **Batch** (/compound) | End of cycle | Entire cycle |

Batch catches what inline missed across the WHOLE cycle, not just one day.

## Ledger Integration

The Sprint Ledger (`grimoires/loa/ledger.json`) already tracks cycles. `/compound` should:
1. Read current cycle from ledger
2. Archive cycle when complete
3. Create new cycle for next PRD

This is already partially implemented in `/archive-cycle`.

## Extension: /compound Subcommands

```bash
/compound                  # Full cycle compound (default)
/compound --sprint-only    # Just current sprint, no archive
/compound --review-only    # Extract learnings, don't promote skills
/compound --dry-run        # Preview what would happen
/compound changelog        # Generate cycle changelog only
/compound status           # Show what would be extracted
```
