# Product Requirements Document: Compound Learning System

**Version:** 1.0
**Date:** 2025-01-30
**Author:** PRD Architect Agent
**Status:** Draft

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

---

## Executive Summary

> **"Stop prompting. Start compounding."**

The Compound Learning System extends Loa's existing Continuous Learning Skill to enable cross-session pattern detection, batch retrospectives, and autonomous knowledge consolidation. Inspired by Ryan Carson's autonomous coding workflow pattern, this feature closes the loop between learning and application.

**The Core Insight**: The agent gets smarter every cycle because it reviews all work before starting the next PRD. Patterns discovered in Cycle 1 inform Cycle 2. Gotchas hit during MVP development are avoided during V2.

**Design Direction**: Instead of external scheduling (cron/launchd), compound review triggers at the **end of each PRD cycle** as a new phase in loa's workflow:

```
PRD → Architect → Sprint Plan → Implement → Review → Audit → COMPOUND → (next PRD)
```

Currently, Loa agents extract skills from debugging discoveries within a single session via the continuous-learning skill (inline extraction). However, the most valuable patterns often emerge across multiple sessions and sprints. The Compound Learning System adds **batch extraction** at cycle boundaries that catches what inline extraction misses.

**The Two-Mode Model**:
- **Inline** (existing): Real-time extraction during implementation
- **Batch** (new): End-of-cycle review catches everything missed across ALL sprints

> Source: compound-learning.md, cycle-based-compounding.md

This enhancement positions Loa as the first AI development framework with true longitudinal learning—agents that genuinely get better at a codebase over time, with learnings from Cycle N feeding directly into Cycle N+1.

---

## Problem Statement

### The Problem

**Agents lose compound learning opportunities** because retrospectives are session-scoped, learnings remain isolated as individual skills, and there's no mechanism to detect patterns that only emerge across multiple work sessions.

> Source: compound-learning.md:42-46

### User Pain Points

1. **Repeated investigations**: Agents re-discover the same solutions across sessions because cross-session patterns aren't detected
2. **Manual synthesis burden**: Developers must manually notice when multiple skills should consolidate into AGENTS.md guidance
3. **Skill sprawl**: Individual skills accumulate without higher-order pattern recognition
4. **Lost momentum**: Starting a new session means starting fresh, rather than building on yesterday's work

### Current State

- `/retrospective` analyzes only the current conversation
- Skills are extracted individually without cross-referencing other sessions
- NOTES.md captures session continuity but doesn't synthesize patterns
- AGENTS.md requires manual human updates
- No feedback loop to verify if learnings actually help

### Desired State

- Batch retrospectives analyze trajectory logs across days/sprints
- Recurring patterns automatically surface as candidates for AGENTS.md updates
- Sessions begin with a "morning review" that applies yesterday's learnings
- Learnings that prove helpful get reinforced; those that don't get demoted
- The autonomous loop: Learn → Apply → Verify → Reinforce

### The Compound Effect (Concrete Example)

**Before Compound Learning:**
```
Monday:    Hit NATS reconnection bug, spend 2 hours debugging
Tuesday:   Hit same bug AGAIN, spend 1.5 hours
Wednesday: Hit same bug AGAIN, finally document it
Thursday:  Hit same bug... wait, where's that doc?
Total: 5+ hours lost on one bug
```

**After Compound Learning:**
```
Monday:       Hit NATS reconnection bug, spend 2 hours debugging
Monday night: Batch review extracts pattern, updates AGENTS.md
Tuesday:      Agent reads AGENTS.md, knows about bug, AVOIDS it
Wednesday:    Zero time wasted on NATS bugs
Thursday:     Agent ships features instead of re-debugging
Total: 2 hours, then done FOREVER
```

> Source: compound-effect-philosophy.md

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Enable cross-session pattern detection | % of patterns spanning 2+ sessions identified | Trajectory analysis showing multi-session skill origins |
| G-2 | Reduce repeated investigations | # of re-discovered solutions decreases over time | Compare session-1 vs session-N investigation counts |
| G-3 | Automate knowledge consolidation | AGENTS.md updates generated from skill synthesis | Count of auto-generated AGENTS.md proposals |
| G-4 | Close the apply-verify loop | % of learnings that get applied and verified | Track learning application events in trajectory |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Skill reuse rate | Unknown (not tracked) | >30% skills matched within 30 days | Sprint 3 | G-2 |
| Cross-session patterns detected | 0 | 5+ per project | Sprint 2 | G-1 |
| AGENTS.md update proposals | 0/month | 2+/month | Sprint 3 | G-3 |
| Learning apply-verify completion | 0% | >50% | Sprint 4 | G-4 |

### Constraints

- Must maintain Zone compliance (all writes to State Zone)
- Human approval required for AGENTS.md modifications
- Must not significantly increase session startup time (<5s overhead)
- Must work with existing trajectory JSONL format

---

## User Personas & Use Cases

### Primary Persona: Senior Developer (Alex)

**Demographics:**
- Role: Tech Lead using Loa for a 6-month project
- Technical Proficiency: Expert
- Goals: Ship features faster by not repeating past mistakes

**Behaviors:**
- Uses Loa daily across multiple sprints
- Runs `/retrospective` occasionally at session end
- Notices patterns manually but rarely documents them

**Pain Points:**
- Sees agents re-investigate issues they solved last week
- Skills accumulate but aren't synthesized into guidance
- No way to see "what did we learn this sprint?"

### Secondary Persona: AI Agent (Loa Implementing-Tasks)

**Demographics:**
- Role: Implementation agent executing sprint tasks
- Technical Proficiency: Depends on skill library
- Goals: Complete tasks correctly the first time

**Behaviors:**
- Loads skills matching current task context
- Discovers solutions through debugging
- Extracts learnings via continuous learning skill

**Pain Points:**
- Cannot access learnings from previous sessions
- Doesn't know if a similar problem was solved before
- No feedback on whether past learnings were helpful

### Use Cases

#### UC-1: Batch Retrospective After Sprint
**Actor:** Senior Developer (Alex)
**Preconditions:** Sprint completed, multiple sessions with trajectory logs exist
**Flow:**
1. Developer runs `/retrospective --batch --days 14`
2. System analyzes trajectory logs from past 14 days
3. System identifies recurring patterns, repeated solutions, convergent approaches
4. System presents compound learning candidates with quality assessment
5. Developer approves/rejects candidates
6. Approved candidates become skills or AGENTS.md proposals

**Postconditions:** New compound learnings extracted, skill library enriched
**Acceptance Criteria:**
- [ ] Can specify time range for batch analysis
- [ ] Presents cross-session patterns with evidence
- [ ] Logs all decisions to trajectory

#### UC-2: Morning Learning Review
**Actor:** Loa Implementing-Tasks Agent
**Preconditions:** Previous session(s) exist with extracted learnings
**Flow:**
1. Session starts with implementation task
2. System loads recent learnings relevant to task context
3. System presents "Before you begin..." summary of applicable learnings
4. Agent applies learnings during implementation
5. System tracks which learnings were referenced

**Postconditions:** Agent starts informed, application tracked for feedback loop
**Acceptance Criteria:**
- [ ] Relevant learnings auto-loaded at session start
- [ ] Application events logged to trajectory
- [ ] Overhead < 5 seconds

#### UC-3: End-of-Cycle Compound Review
**Actor:** Developer (or autonomous via `/run` completion)
**Preconditions:** Development cycle complete (all sprints implemented, reviewed, audited)
**Flow:**
1. Developer runs `/compound` after final audit passes
2. System scans all trajectory logs from current cycle
3. System identifies patterns missed by inline extraction
4. System presents batch learning candidates with quality assessment
5. Developer approves/rejects candidates
6. System promotes approved skills from `skills-pending/` to `skills/`
7. System updates NOTES.md with cycle-level insights
8. System generates cycle changelog
9. System archives cycle artifacts
10. System prepares fresh context for next PRD

**Postconditions:** Cycle complete, learnings extracted, ready for next cycle
**Acceptance Criteria:**
- [ ] All trajectory logs from cycle are analyzed
- [ ] Duplicates with inline-extracted skills are detected and handled
- [ ] Cycle changelog is comprehensive and useful
- [ ] Next `/plan-and-analyze` can load these learnings

> Source: cycle-based-compounding.md (Jani's design direction)

#### UC-4: Learning Synthesis to AGENTS.md
**Actor:** System (Learning Synthesis Daemon)
**Preconditions:** 3+ related skills exist in active state
**Flow:**
1. System detects cluster of related skills (semantic similarity)
2. System drafts consolidated guidance for AGENTS.md
3. System presents proposal to human with supporting evidence
4. Human approves/modifies/rejects proposal
5. If approved, system updates AGENTS.md (or creates PR)

**Postconditions:** Higher-order pattern codified in AGENTS.md
**Acceptance Criteria:**
- [ ] Human approval required before any AGENTS.md modification
- [ ] Proposal includes citations to source skills
- [ ] Original skills archived (not deleted) if fully subsumed

---

## Functional Requirements

### FR-1: Compound Command (`/compound`)
**Priority:** Must Have
**Description:** New end-of-cycle command that reviews all work from the current development cycle, extracts learnings missed by inline extraction, and prepares fresh context for the next PRD. This is the final phase before starting a new cycle.

**Acceptance Criteria:**
- [ ] Reviews entire cycle's work (all sprints, all sessions from ledger)
- [ ] Scans `grimoires/loa/a2a/trajectory/*.jsonl` for cycle's session IDs
- [ ] Applies quality gates (Discovery Depth, Reusability, Trigger Clarity, Verification)
- [ ] Batch extracts learnings missed by inline continuous-learning
- [ ] Updates `NOTES.md` with cycle-level insights
- [ ] Promotes worthy `skills-pending/` → `skills/` (or flags for review)
- [ ] Generates cycle summary/changelog
- [ ] Archives cycle artifacts to `grimoires/loa/archive/cycle-N/`
- [ ] Prepares fresh context for next PRD
- [ ] Integrates with Sprint Ledger (`ledger.json`) for cycle tracking

**Subcommands:**
- `/compound` - Full cycle compound (default)
- `/compound --sprint-only` - Just current sprint, no archive
- `/compound --review-only` - Extract learnings, don't promote skills
- `/compound --dry-run` - Preview what would happen
- `/compound changelog` - Generate cycle changelog only
- `/compound status` - Show what would be extracted

**Dependencies:** Existing trajectory JSONL infrastructure, Sprint Ledger

> Source: cycle-based-compounding.md (Jani's design direction)

### FR-1b: Batch Retrospective Mode (`/retrospective --batch`)
**Priority:** Should Have
**Description:** Extend `/retrospective` to support multi-session batch analysis for ad-hoc reviews (mid-cycle or historical).

**Acceptance Criteria:**
- [ ] `--batch` flag enables multi-session analysis
- [ ] `--sprint N` analyzes all sessions within sprint N
- [ ] `--cycle N` analyzes all sessions within cycle N
- [ ] Detects: recurring errors, repeated solutions, convergent approaches
- [ ] Uses semantic similarity to match "same problem, different words"
- [ ] Presents findings with confidence scores and evidence
- [ ] Writes compound skills to `skills-pending/` with multi-session provenance

**Dependencies:** FR-1 (shares pattern detection logic)

### FR-2: Cross-Session Pattern Detector
**Priority:** Must Have
**Description:** Core algorithm that identifies patterns spanning multiple sessions by analyzing trajectory logs.

**Acceptance Criteria:**
- [ ] Identifies repeated error→solution pairs across sessions
- [ ] Detects converging approaches (multiple paths to same solution)
- [ ] Finds anti-patterns (repeated mistakes before finding fix)
- [ ] Calculates pattern confidence based on occurrence frequency
- [ ] Supports filtering by agent type, date range, sprint
- [ ] Outputs structured pattern report

**Dependencies:** Semantic similarity implementation (could use embeddings or keyword overlap)

### FR-3: Learning Application Tracking
**Priority:** Should Have
**Description:** Track when extracted learnings are applied during implementation, enabling the verify feedback loop.

**Acceptance Criteria:**
- [ ] Log `learning_applied` events to trajectory
- [ ] Include skill ID, task context, application type
- [ ] Support explicit application ("per skill X...") and implicit detection
- [ ] Query API: "which learnings were applied in session Y?"
- [ ] Integrate with `/implement` phase for automatic tracking

**Dependencies:** FR-1 (skills must exist to be applied)

### FR-4: Learning Effectiveness Feedback Loop
**Priority:** Should Have
**Description:** Verify whether applied learnings actually helped, using outcome signals.

**Acceptance Criteria:**
- [ ] Define "helped" signals: task completed faster, fewer errors, no revert
- [ ] Log `learning_verified` events with effectiveness rating
- [ ] Learnings that consistently help: increase retrieval priority
- [ ] Learnings that don't help: flag for review, eventual pruning
- [ ] Monthly report: "Top 5 most helpful learnings this month"

**Dependencies:** FR-3 (must track application to verify)

### FR-5: Learning Synthesis Engine
**Priority:** Should Have
**Description:** Consolidate related skills into higher-order patterns, proposing AGENTS.md updates.

**Acceptance Criteria:**
- [ ] Cluster related skills by semantic similarity
- [ ] Draft consolidated guidance from skill cluster
- [ ] Present proposal with: draft text, source citations, confidence
- [ ] Human approval workflow (approve/modify/reject)
- [ ] If approved: update AGENTS.md, archive source skills (optional)
- [ ] Command: `/synthesize-learnings` for manual trigger
- [ ] Periodic auto-trigger (configurable, default: weekly)

**Dependencies:** FR-2 (pattern detection), semantic similarity

### FR-6: Morning Context Loading
**Priority:** Nice to Have
**Description:** At session start, automatically load relevant learnings for the day's work.

**Acceptance Criteria:**
- [ ] Detect task context from PRD, sprint, or user prompt
- [ ] Query skill library for matching learnings
- [ ] Present "Before you begin..." summary (max 5 learnings)
- [ ] Allow dismissal if not relevant
- [ ] Configurable: enabled/disabled, max learnings shown
- [ ] Overhead < 5 seconds

**Dependencies:** Skill retrieval mechanism

### FR-7: Learning Context Loading for Next Cycle
**Priority:** Should Have
**Description:** When starting a new PRD cycle, automatically load learnings from the previous cycle to inform the new work.

**Acceptance Criteria:**
- [ ] `/plan-and-analyze` detects if previous cycle had learnings
- [ ] Loads relevant skills and NOTES.md insights into context
- [ ] Presents "Learnings from last cycle" summary before PRD discovery
- [ ] Allows dismissal if not relevant to new cycle's scope
- [ ] Configurable: enabled/disabled, max learnings shown
- [ ] Overhead < 5 seconds

**Dependencies:** FR-1 (learnings must be extracted first)

> Source: cycle-based-compounding.md (Cycle N → Cycle N+1 handoff)

### FR-8: Cycle Changelog Generation
**Priority:** Should Have
**Description:** Generate a comprehensive changelog summarizing what was built, learned, and improved during the cycle.

**Acceptance Criteria:**
- [ ] Lists all features/tasks completed
- [ ] Lists skills extracted (inline + batch)
- [ ] Lists NOTES.md insights added
- [ ] Lists PRs created and merged
- [ ] Output formats: Markdown, JSON
- [ ] Auto-generated during `/compound`, also available standalone
- [ ] Useful for stakeholder updates and retrospectives

**Dependencies:** Sprint Ledger, trajectory logs

### FR-9: Cycle Archive Management
**Priority:** Nice to Have
**Description:** Archive cycle artifacts for historical reference while keeping active workspace clean.

**Acceptance Criteria:**
- [ ] Archives to `grimoires/loa/archive/cycle-N/`
- [ ] Preserves: PRD, SDD, sprint plans, trajectory logs, skills extracted
- [ ] Configurable retention policy (keep last N cycles)
- [ ] `/compound --no-archive` to skip archiving
- [ ] `/compound archive --cycle N` to archive specific past cycle

**Dependencies:** FR-1

---

## Non-Functional Requirements

### Performance
- Batch retrospective for 30 days of logs: < 2 minutes
- Morning context loading: < 5 seconds
- Pattern detection query: < 10 seconds

### Scalability
- Support projects with 1000+ skill files
- Support trajectory logs spanning 6+ months
- Graceful degradation if logs exceed memory limits (streaming analysis)

### Security
- Learnings never leave the local machine (no cloud sync)
- Skill files may contain sensitive project info—no external transmission
- Audit trail in trajectory is append-only

### Reliability
- Partial trajectory corruption should not break analysis
- Missing days should not fail batch retrospective
- Graceful handling of malformed skill files

### Compliance
- Zone compliance: all writes to State Zone (`grimoires/loa/`)
- Human oversight: AGENTS.md updates require approval
- Audit trail: all decisions logged to trajectory

---

## User Experience

### Key User Flows

#### Flow 1: End-of-Sprint Batch Retrospective
```
Developer: /retrospective --batch --sprint 3
→ System: Analyzing 14 sessions, 847 trajectory events...
→ System: Found 3 compound patterns:
         1. [HIGH] NATS reconnection handling (seen 5 times)
         2. [MED] TypeScript strict mode gotchas (seen 3 times)
         3. [LOW] Docker compose networking (seen 2 times)
→ Developer: Approve #1, #2. Reject #3.
→ System: Created skills, logged to trajectory.
```

#### Flow 2: Morning Learning Brief
```
Agent: Starting implementation of sprint-4-task-2 (auth service)
→ System: 📚 Before you begin...
         - [SKILL] NATS JetStream consumer durability pattern
         - [SKILL] JWT validation edge cases
         Apply these? [Y/n]
→ Agent: Y
→ System: Learnings loaded. Tracking application.
```

#### Flow 3: End-of-Cycle Compound Review
```
Developer: /audit-sprint sprint-3  (final sprint)
→ System: ✓ Audit passed. Cycle complete.
→ System: 💡 Tip: Run /compound to extract learnings before next cycle.

Developer: /compound
→ System: 📚 Analyzing cycle "MVP Development"...
→ System: Scanning 3 sprints, 12 sessions, 2,847 trajectory events...
→ System: 
→ System: INLINE EXTRACTION (already captured):
→ System:   • 5 skills in skills-pending/
→ System:   • 3 skills already promoted to skills/
→ System: 
→ System: BATCH EXTRACTION (newly discovered):
→ System:   1. [HIGH] NATS reconnection handling (seen 5× across sprints)
→ System:   2. [MED] TypeScript strict mode gotchas (seen 3×)
→ System:   3. [LOW] Docker compose networking (seen 2×)
→ System: 
→ System: Approve batch extractions? [Y/n/select]
Developer: Y

→ System: ✓ 3 skills extracted to skills-pending/
→ System: ✓ NOTES.md updated with cycle insights
→ System: ✓ Changelog generated: grimoires/loa/CHANGELOG-cycle-1.md
→ System: ✓ Cycle archived to archive/cycle-001/
→ System: 🎉 Ready for next cycle!

Developer: /plan-and-analyze  (next cycle)
→ System: 📚 Loading learnings from previous cycle...
→ System: Found 8 relevant skills. Applying to context.
→ System: Starting PRD discovery...
```

#### Flow 4: Weekly Synthesis Proposal
```
System: 🧠 Learning Synthesis Proposal
        3 related skills detected:
        - nats-reconnection-handling
        - nats-jetstream-durability
        - nats-consumer-patterns
        
        Proposed AGENTS.md addition:
        "When using NATS, always configure durable consumers
         with explicit reconnection handlers. See skills/nats-*"
        
        [Approve] [Modify] [Reject]
```

### Interaction Patterns
- Batch operations show progress indicators
- Proposals are non-blocking (can be dismissed)
- All commands support `--dry-run` for preview
- Confidence levels clearly communicated (HIGH/MED/LOW)

### Accessibility Requirements
- CLI output must be screen-reader compatible
- No reliance on color alone for status indication
- Progress updates at regular intervals (not just spinners)

---

## Technical Considerations

### Architecture Notes

**End-of-Cycle Compound Phase** (Loa's Extended Phase Model):

```
┌─────────────────────────────────────────────────────────────────┐
│                    LOA DEVELOPMENT CYCLE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   EXISTING PHASES                                                │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                                                           │  │
│   │  /plan-and   /architect   /sprint-    /implement         │  │
│   │  -analyze                  plan        (per sprint)      │  │
│   │      │           │           │             │              │  │
│   │      ▼           ▼           ▼             ▼              │  │
│   │   ┌─────┐    ┌─────┐    ┌─────┐    ┌───────────┐         │  │
│   │   │ PRD │───▶│ SDD │───▶│Sprint│───▶│ Code +    │         │  │
│   │   └─────┘    └─────┘    └─────┘    │ Inline    │         │  │
│   │                                     │ Learning  │         │  │
│   │                                     └─────┬─────┘         │  │
│   │                                           │               │  │
│   │  /review-    /audit-     /deploy-        │               │  │
│   │  sprint      sprint      production      │               │  │
│   │      │           │           │           │               │  │
│   │      ▼           ▼           ▼           │               │  │
│   │   ┌─────┐    ┌─────┐    ┌─────┐         │               │  │
│   │   │Review│───▶│Audit │───▶│Deploy│        │               │  │
│   │   └─────┘    └─────┘    └─────┘         │               │  │
│   │                             │            │               │  │
│   └─────────────────────────────┼────────────┼───────────────┘  │
│                                 │            │                   │
│   NEW PHASE                     ▼            ▼                   │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │  /compound                                                │  │
│   │  ┌────────────────────────────────────────────────────┐  │  │
│   │  │ 1. Review entire cycle's trajectory logs           │  │  │
│   │  │ 2. Batch extract learnings missed by inline        │  │  │
│   │  │ 3. Update NOTES.md with cycle-level insights       │  │  │
│   │  │ 4. Promote skills-pending → skills                 │  │  │
│   │  │ 5. Generate cycle changelog                        │  │  │
│   │  │ 6. Archive cycle artifacts                         │  │  │
│   │  │ 7. Prepare fresh context for next PRD              │  │  │
│   │  └────────────────────────────────────────────────────┘  │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                 │                                │
│                                 │ LEARNINGS FEED FORWARD         │
│                                 ▼                                │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │  NEXT CYCLE: /plan-and-analyze (with cycle N learnings)  │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Compound Learning Data Flow**:

```
┌─────────────────────────────────────────────────────────────────┐
│                  Compound Learning Data Flow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Trajectory Logs          Pattern Detector        Skill Library  │
│  (JSONL)                  (Semantic Analysis)     (Markdown)     │
│       │                         │                      │         │
│       └──────────┬──────────────┘                      │         │
│                  │                                     │         │
│                  ▼                                     │         │
│         ┌───────────────┐                              │         │
│         │ Compound      │◀─────────────────────────────┘         │
│         │ Review Engine │                                        │
│         └───────┬───────┘                                        │
│                 │                                                │
│         ┌───────┴───────┐                                        │
│         │               │                                        │
│         ▼               ▼                                        │
│  ┌─────────────┐ ┌─────────────┐      ┌───────────────┐         │
│  │ NOTES.md   │ │ skills-     │─────▶│ Synthesis     │         │
│  │ Learnings  │ │ pending/    │      │ Engine        │         │
│  └──────┬──────┘ └─────────────┘      └───────┬───────┘         │
│         │                                     │                  │
│         │  loaded at                          ▼                  │
│         │  ship time            ┌───────────────┐               │
│         └──────────────────────▶│ AGENTS.md     │               │
│                                 │ Proposals     │               │
│                                 └───────────────┘               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Integrations

| System | Integration Type | Purpose |
|--------|------------------|---------|
| Trajectory Logs | File I/O | Source for pattern analysis |
| Skill Library | File I/O | Target for new skills, source for synthesis |
| NOTES.md | File I/O | Cross-reference, session continuity |
| AGENTS.md | File I/O (gated) | Target for synthesis proposals |

### Dependencies
- Existing continuous-learning skill (extend, not replace)
- Trajectory JSONL infrastructure (already present)
- Shell scripts for batch processing (bash)
- Optional: Embedding model for semantic similarity (can use keyword fallback)

### Technical Constraints
- No external API calls (must work offline)
- Zone compliance enforced (State Zone writes only)
- Human approval for AGENTS.md (no auto-commit)
- JSONL streaming for large log files

### Two-Mode Coexistence Model

The compound learning system uses TWO extraction modes that coexist:

| Mode | Existing/New | When | What It Catches |
|------|--------------|------|-----------------|
| **Inline** | Existing (`continuous-learning`) | During implementation | Obvious "aha!" moments, clear discoveries |
| **Batch** | New (`compound-review`) | End of day | Everything inline missed, subtle patterns |

**Why both?**
- Inline catches obvious wins in real-time
- Batch reviews full trajectory, finds patterns agent didn't recognize
- The combination is more powerful than either alone

**Integration**:
- Batch review checks for existing inline-extracted skills (no duplicates)
- Both write to same skill library (`skills-pending/`)
- Both use same quality gates
- Batch may upgrade/consolidate multiple inline skills

> Source: compound-effect-philosophy.md

---

## Scope & Prioritization

### In Scope (MVP - Sprint 1-2)
- FR-1: Compound Command (`/compound`) - Core end-of-cycle extraction
- FR-2: Cross-Session Pattern Detector (keyword-based)
- Quality gates for compound patterns
- Trajectory logging for compound events
- Sprint Ledger integration for cycle tracking

### In Scope (Phase 2 - Sprint 3-4)
- FR-1b: Batch Retrospective Mode (`/retrospective --batch`)
- FR-3: Learning Application Tracking
- FR-4: Learning Effectiveness Feedback Loop
- FR-7: Learning Context Loading for Next Cycle
- FR-8: Cycle Changelog Generation

### In Scope (Phase 3 - Sprint 5-6)
- FR-5: Learning Synthesis Engine (AGENTS.md proposals)
- FR-6: Morning Context Loading (per-session)
- FR-9: Cycle Archive Management
- Semantic similarity upgrade (embeddings optional)

### In Scope (Future Extensions)
- **Notifications**: Slack/Discord webhooks for cycle completion
- **Cross-Project Learning**: Share patterns across related repositories
- **Autonomous Scheduling**: Optional cron/launchd for fully autonomous operation (Ryan Carson mode)
- **Interactive Changelog**: Web view of cycle history and learnings

> Source: cycle-based-compounding.md

### Explicitly Out of Scope
- Cloud sync of learnings - Reason: Privacy, offline requirement
- Real-time collaboration - Reason: Single-developer focus for MVP
- GUI/Web interface - Reason: CLI-first, consistent with Loa
- LLM-based synthesis - Reason: Should work without external APIs

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1: /compound Command | P0 | M | High |
| FR-2: Pattern Detector | P0 | L | High |
| FR-1b: Batch Retrospective | P1 | M | Med |
| FR-7: Next Cycle Context Loading | P1 | S | High |
| FR-8: Cycle Changelog | P1 | S | Med |
| FR-3: Application Tracking | P1 | M | Med |
| FR-4: Feedback Loop | P1 | M | High |
| FR-5: Synthesis Engine | P2 | L | Med |
| FR-6: Morning Context | P2 | S | Med |
| FR-9: Cycle Archive | P2 | S | Low |

---

## Success Criteria

### Launch Criteria (MVP)
- [ ] `/retrospective --batch` functional with 7-day default
- [ ] At least 1 compound pattern detected in test project
- [ ] Trajectory logs include compound learning events
- [ ] Documentation updated in CLAUDE.md
- [ ] No regression in existing `/retrospective` behavior

### Post-Launch Success (30 days)
- [ ] 3+ compound patterns detected across projects
- [ ] User feedback collected (at least 2 users)
- [ ] No critical bugs reported
- [ ] Synthesis engine functional (P1 features)

### Long-term Success (90 days)
- [ ] 30%+ skill reuse rate achieved
- [ ] AGENTS.md proposals generating value
- [ ] Apply-verify loop closing (measurable effectiveness)
- [ ] Community contributions to pattern library

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| Pattern detection has high false positives | Med | High | Quality gates, confidence thresholds, human approval |
| Performance degrades with large log files | Med | Med | Streaming analysis, time-bounded queries |
| Semantic similarity is inaccurate | Med | Med | Start with keywords, add embeddings later |
| Users don't run batch retrospectives | High | Med | Prompt after sprints, integrate with `/run` |
| AGENTS.md proposals are low quality | Med | Med | Human approval required, show evidence |

### Assumptions
- Trajectory logs are consistently structured
- Skill files follow the existing template
- Users complete multiple sessions per project
- Claude Code environment supports file I/O

### Dependencies on External Factors
- Loa framework continues active development
- No breaking changes to trajectory format
- Claude Code API remains stable

---

## Timeline & Milestones

| Milestone | Target | Deliverables |
|-----------|--------|--------------|
| M1: Architecture Design | Week 1 | SDD, protocol specs |
| M2: MVP (Batch Retro) | Week 2-3 | FR-1, FR-2, tests |
| M3: Feedback Loop | Week 4-5 | FR-3, FR-4 |
| M4: Synthesis Engine | Week 6 | FR-5, AGENTS.md integration |
| M5: Polish & Docs | Week 7 | Documentation, examples |

---

## Appendix

### A. Stakeholder Insights

**Ryan Carson's Auto-Compound Pattern** (original inspiration):

The nightly two-job architecture informed our understanding of compound learning:
- Review extracts learnings → Updates knowledge files → Ship benefits from fresh learnings
- The ORDER matters: learn first, then apply

> **Core insight**: "The agent gets smarter every cycle because it reads its own 
> updated instructions before each implementation run."

**Jani's Design Direction** (loa adaptation):

Instead of nightly scheduling, trigger compound review at **end of each PRD cycle**:
```
PRD → Architect → Sprint Plan → Implement → Review → Audit → COMPOUND
```

Benefits of cycle-based approach:
1. No external dependencies (cron/launchd)
2. Fits loa's existing phase model
3. Cycle-scoped learnings (more coherent than day boundaries)
4. Direct handoff: Cycle N learnings → Cycle N+1 context

> Source: cycle-based-compounding.md

**The Compound Philosophy applies at any timescale**:
- Ryan Carson: Daily compounding (Monday learnings → Tuesday work)
- Loa: Cycle compounding (Cycle 1 learnings → Cycle 2 work)

Both achieve the same goal: **"Stop prompting. Start compounding."**

### B. Research Foundation

- **Voyager** (Wang et al., 2023): Open-ended skill library discovery in Minecraft
- **CASCADE** (2024): Meta-skills for compound learning
- **Reflexion** (Shinn et al., 2023): Verbal reinforcement learning
- **SEAgent** (2025): Trial-and-error in software environments

> Source: compound-learning.md:86-91

### C. Existing Loa Capabilities

| Capability | File | Status |
|------------|------|--------|
| Continuous Learning Skill | `.claude/skills/continuous-learning/` | Active |
| Retrospective Command | `.claude/commands/retrospective.md` | Active |
| Trajectory Logging | `grimoires/loa/a2a/trajectory/` | Active |
| Skill Lifecycle | `skills-pending/` → `skills/` → `skills-archived/` | Active |
| NOTES.md Protocol | `.claude/protocols/structured-memory.md` | Active |

### D. Glossary

| Term | Definition |
|------|------------|
| Compound Learning | Patterns that emerge across multiple sessions, not within a single session |
| Trajectory Log | JSONL file recording agent actions, decisions, and outcomes |
| Skill | Reusable knowledge unit extracted from debugging discoveries |
| Synthesis | Consolidating multiple related skills into higher-order guidance |
| Apply-Verify Loop | Track learning application → verify effectiveness → reinforce/demote |

---

*Generated by PRD Architect Agent*
*Source: grimoires/loa/context/compound-learning.md*
