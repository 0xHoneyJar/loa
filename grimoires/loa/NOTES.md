# NOTES.md - Compound Learning Development

## Current Focus

| Field | Value |
|-------|-------|
| Active Task | Sprint 1 - Foundation & Directory Setup |
| Status | ✅ **COMPLETED** |
| Blocked By | None |
| Next Action | `/implement` Sprint 2 - Trajectory Reader |

## Session Log

| Timestamp | Event | Details |
|-----------|-------|---------|
| 2025-01-30 | Session Start | Compound learning PRD discovery |
| 2025-01-30 | Context Created | `context/compound-learning.md` with feature analysis |
| 2025-01-30 | PRD v1 Completed | Full PRD at `grimoires/loa/prd.md` |
| 2025-01-30 | Ryan Carson Pattern | Added `context/ryan-carson-pattern.md` with concrete implementation |
| 2025-01-30 | PRD v2 Updated | Added two-phase architecture, FR-7/8/9, UC-3 nightly cycle |
| 2025-01-30 | Philosophy Added | `context/compound-effect-philosophy.md` - core insight + coexistence model |
| 2025-01-30 | PRD v3 | Added compound effect example, two-mode coexistence, extension ideas |
| 2025-01-30 | **DESIGN PIVOT** | Jani: Cycle-based instead of nightly scheduling |
| 2025-01-30 | Context Added | `context/cycle-based-compounding.md` with new architecture |
| 2025-01-30 | PRD v4 Final | Restructured for end-of-cycle `/compound` command |
| 2025-01-30 | SDD Completed | Full SDD at `grimoires/loa/sdd.md` (44KB) - architecture designed |
| 2025-01-30 | Sprint Plan Created | Full sprint plan at `grimoires/loa/sprint.md` - 16 sprints, 4 phases |
| 2025-01-30 | Ledger Created | `grimoires/loa/ledger.json` initialized for cycle-001 |
| 2025-01-30 | **Sprint 1 COMPLETE** | All 7 tasks implemented: dir structure, schemas, config, helper script |

## Decision Log

| Date | Decision | Rationale | Source |
|------|----------|-----------|--------|
| 2025-01-30 | ~~Two-phase nightly architecture~~ | ~~Order matters: learnings must update FIRST~~ | ~~ryan-carson-pattern.md~~ |
| 2025-01-30 | **PIVOT: End-of-cycle triggering** | Fits loa's phase model, no external deps | Jani design direction |
| 2025-01-30 | Single `/compound` command | Replaces compound-review + compound-ship separation | cycle-based-compounding.md |
| 2025-01-30 | ~~External scheduling (cron/launchd)~~ | ~~Keep scheduler outside loa~~ | ~~superseded~~ |
| 2025-01-30 | Cycle-scoped learnings | More coherent than day boundaries | cycle-based-compounding.md |
| 2025-01-30 | Sprint Ledger integration | Use existing cycle tracking | PRD FR-1 |
| 2025-01-30 | Two-mode coexistence (inline + batch) | Inline catches obvious wins; batch catches everything else | compound-effect-philosophy.md |
| 2025-01-30 | Keyword-based pattern detection for MVP | Avoids external API dependency; embeddings later | PRD Technical Considerations |
| 2025-01-30 | Human approval required for AGENTS.md | Maintains human oversight for critical files | PRD FR-5 |
| 2025-01-30 | Jaccard similarity (threshold 0.6) | Simple, offline, deterministic for MVP | SDD Algorithm Design |
| 2025-01-30 | New dir: `grimoires/loa/a2a/compound/` | Isolates compound state in State Zone | SDD Data Architecture |
| 2025-01-30 | 4-phase dev plan (8 weeks) | MVP batch retro → compound cycle → feedback → synthesis | SDD Development Phases |

## Blockers

- [ ] None currently

## Technical Debt

- [ ] Semantic similarity is keyword-based initially; may need embedding upgrade for better matching
- [ ] Morning context loading should be < 5s; may need optimization if skill library grows large

## Goal Status

| Goal ID | Goal | Status |
|---------|------|--------|
| G-1 | Enable cross-session pattern detection | 📐 Designed |
| G-2 | Reduce repeated investigations | 📐 Designed |
| G-3 | Automate knowledge consolidation | 📐 Designed |
| G-4 | Close the apply-verify loop | 📐 Designed |

## Learnings

- Loa's trajectory JSONL format is well-suited for batch analysis
- Existing continuous-learning skill provides solid foundation
- Zone compliance already enforces State Zone writes
- Jaccard similarity is sufficient for MVP pattern matching

## Architecture Summary (from SDD)

### Key Components
1. **Batch Retrospective Engine**: Extends `/retrospective --batch` for multi-session analysis
2. **Cross-Session Pattern Detector**: Keyword extraction + Jaccard clustering
3. **Learning Application Tracker**: `learning_applied` events in trajectory
4. **Effectiveness Feedback Loop**: Score learnings 0-100, prune ineffective
5. **Learning Synthesis Engine**: Cluster skills → propose AGENTS.md updates
6. **Morning Context Loader**: Top 5 relevant learnings at session start

### Data Files (new)
- `grimoires/loa/a2a/compound/patterns.json` - detected patterns
- `grimoires/loa/a2a/compound/learnings.json` - effectiveness tracking
- `grimoires/loa/a2a/compound/synthesis-queue.json` - AGENTS.md proposals
- `grimoires/loa/a2a/compound/review-markers/` - phase completion markers

### Commands (new/extended)
- `/retrospective --batch` - multi-session pattern analysis
- `/compound-review` - Phase 1: extract learnings
- `/compound-ship` - Phase 2: implement with learnings
- `/compound` - orchestrate both phases
- `/synthesize-learnings` - manual synthesis trigger

## Open Questions (from SDD)

1. **Scheduling**: External cron/launchd vs. minimal built-in scheduling?
2. **Embedding upgrade**: When to invest in embedding-based similarity?
3. **AGENTS.md sections**: Which sections for synthesis? All or specific?
4. **Pruning threshold**: Effectiveness < 20% after 3+ applications?
5. **Multi-project patterns**: Cross-project or project-scoped?

## Session Continuity

**Last State**: Sprint plan completed with 16 sprints across 4 phases (~8 weeks).

**Recovery Anchor**: 
- PRD at `grimoires/loa/prd.md` (40KB)
- SDD at `grimoires/loa/sdd.md` (69KB)
- Sprint Plan at `grimoires/loa/sprint.md` (49KB)
- Ledger at `grimoires/loa/ledger.json`
- Context at `grimoires/loa/context/compound-learning.md`
- Branch: `compound-learning`

**Sprint Plan Summary**:
- **Phase 1 (Sprints 1-4)**: Foundation - Directory setup, trajectory reader, pattern detection, clustering
- **Phase 2 (Sprints 5-9)**: Commands - Batch retrospective, quality gates, /compound command, changelog
- **Phase 3 (Sprints 10-12)**: Feedback Loop - Application tracking, effectiveness scoring, lifecycle
- **Phase 4 (Sprints 13-16)**: Synthesis - Skill clustering, AGENTS.md proposals, context loading, visualization

**Next Session Should**:
1. Run `/implement` for Sprint 1: Foundation & Directory Setup
2. Start with Task 1.1: Create compound directory structure
3. Work through Sprint 1 tasks (Est: 2.5 days, ~8-10 hours)
