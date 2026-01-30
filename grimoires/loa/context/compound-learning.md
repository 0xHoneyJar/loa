# Compound Learning Feature Context

## Inspiration: Ryan Carson's Pattern

From Ryan Carson's autonomous coding workflow:
- **Batch review**: Review ALL work threads (not just current session) to extract learnings
- **Auto-updating knowledge**: Patterns discovered automatically update AGENTS.md/NOTES.md
- **Cross-session compounding**: Review yesterday's work → apply learnings today
- **Autonomous loop**: Learn → ship → repeat

## Current Loa Capabilities

### What Exists

1. **Continuous Learning Skill** (`.claude/skills/continuous-learning/`)
   - Activates during implementation phases
   - Extracts discoveries from current session
   - Quality gates: Discovery Depth, Reusability, Trigger Clarity, Verification
   - Writes to `skills-pending/` → human approval → `skills/`

2. **Retrospective Command** (`/retrospective`)
   - Manual trigger at session end
   - Scans **current conversation** for discoveries
   - Five-step workflow: Analysis → Quality Gates → Cross-Reference → Extract → Summary
   - Scope options: implementing-tasks, reviewing-code, auditing-security, deploying-infrastructure

3. **Structured Memory Protocol**
   - `grimoires/loa/NOTES.md`: Decisions, blockers, learnings, session continuity
   - `grimoires/loa/a2a/trajectory/*.jsonl`: Audit trail per agent per date
   - Skill lifecycle: pending → active → archived

4. **Skill Audit** (`/skill-audit`)
   - Approve pending skills
   - Prune unused skills
   - Archive deprecated skills

### The Gap

| Feature | Current State | Needed |
|---------|--------------|--------|
| Session Scope | Single session | Multi-session batch |
| Trigger | Manual (`/retrospective`) | Scheduled + autonomous |
| Pattern Detection | Within-session | Cross-session correlation |
| Knowledge Updates | Skills only | Also AGENTS.md/NOTES.md |
| Learning Loop | Extract only | Extract → Apply → Verify |

## Problem Statement

**Agents lose compound learning opportunities** because:
1. Retrospectives only analyze current session, missing cross-session patterns
2. No mechanism to review yesterday's work before starting today's
3. Skills remain isolated; higher-order patterns aren't synthesized into AGENTS.md
4. No autonomous loop: learnings exist but aren't systematically applied

## Proposed Solution: Compound Learning Cycle

### Three New Capabilities

1. **Batch Retrospective** (`/retrospective --batch`)
   - Review trajectory logs across multiple sessions (e.g., last 7 days)
   - Detect recurring patterns, repeated mistakes, convergent solutions
   - Synthesize compound learnings that span sessions

2. **Learning Synthesis Daemon**
   - Periodic (heartbeat/cron-like) review of accumulated learnings
   - Consolidate related skills into AGENTS.md guidance
   - Update NOTES.md with cross-cutting patterns
   - Prune redundant skills, merge similar ones

3. **Apply-and-Verify Loop**
   - Before implementation: Load relevant learnings
   - During implementation: Track if learnings were applied
   - After implementation: Verify learning effectiveness
   - Feedback loop: Learnings that help get reinforced, those that don't get demoted

### Integration Points

```
┌─────────────────────────────────────────────────────────────────┐
│                   Compound Learning Cycle                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌────────┐ │
│  │  /ride   │────▶│/implement│────▶│/retro    │────▶│/synth  │ │
│  │(context) │     │ (apply)  │     │(extract) │     │(consol)│ │
│  └──────────┘     └──────────┘     └──────────┘     └────────┘ │
│       ▲                                                   │     │
│       │           Compound Learning Loop                  │     │
│       └───────────────────────────────────────────────────┘     │
│                                                                  │
│  New Components:                                                 │
│  • /retrospective --batch (multi-session)                       │
│  • /synthesize-learnings (consolidate → AGENTS.md)              │
│  • Learning applicability tracking                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Success Metrics

1. **Skill reuse rate**: % of extracted skills that get matched/applied
2. **Pattern emergence time**: Days from first occurrence to recognized pattern
3. **Mistake reduction**: Repeated errors should decrease over time
4. **Knowledge density**: AGENTS.md guidance increases without bloat
5. **Autonomous loop completion**: % of learn→apply→verify cycles completed

## Technical Considerations

1. **Trajectory storage**: JSONlines format supports querying across sessions
2. **Semantic similarity**: Detect "same problem, different words" across sessions
3. **Staleness handling**: Age-out learnings that aren't reinforced
4. **Zone compliance**: All writes to State Zone (grimoires/loa/)
5. **Human oversight**: Synthesis proposals require approval before AGENTS.md updates

## Prior Art / Research

- **Voyager** (Wang et al., 2023): Open-ended skill library discovery
- **CASCADE** (2024): Meta-skills for compound learning
- **Reflexion** (Shinn et al., 2023): Verbal reinforcement learning
- **SEAgent** (2025): Trial-and-error in software environments
- **Ryan Carson's workflow**: Real-world autonomous coding pattern

## Open Questions

1. How granular should batch review be? (By day? By sprint? By project?)
2. Should AGENTS.md updates be auto-committed or require PR review?
3. How to handle conflicting learnings from different sessions?
4. What's the right decay function for learnings that aren't reinforced?
5. Should the autonomous loop run in background (daemon) or on-demand?
