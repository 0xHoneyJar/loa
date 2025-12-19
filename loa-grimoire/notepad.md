# Legba Notepad

> Ideas, context, and insights to revisit in future iterations.
> Trust the process - note it down, come back later.

---

## Key Decisions (PRD Phase)

### Integration Model
- **Loa = Laboratory Executor** for Hivemind OS
- Takes User Truth Canvases from seed cycle → executes as structured experiments
- Learning Memos + ADR Candidates flow back to Hivemind Library
- Organization learns → Library grows

### Technical Approach
- `.hivemind/` symlink to `../hivemind-library`
- Skills symlinked from hivemind-os to `.claude/skills/`
- Mode tracking in `.claude/.mode` with confirmation gates
- Symlinks work for Claude Code (researched)

### Mode Philosophy
- **Secure Mode**: Strictness throughout entire Loa sequence
- **Creative Mode**: HITL gates for thinking, asking good questions, finding brand alignment
- Both modes get human-in-the-loop at key decision points
- Design engineering goes back-and-forth (iteration between design + implementation)

### Scope (v1 MVP)
**P0 (Must Have)**:
- `/setup` Hivemind connection (`.hivemind/` symlink)
- Project type detection and skill loading
- Mode tracking and confirmation gates
- Context injection at PRD phase (ADRs, experiments, Learning Memos)
- Automatic ADR/Learning candidate surfacing
- Skills symlinked from hivemind-os

**P1 (Should Have)**:
- Linear Product Home integration
- Experiment linking
- Brand context loading from Linear docs
- Context injection at all phases
- Cycle ↔ sprint mapping

**Deferred (P2)**:
- Full Hivemind `/ask` command in Loa
- GAP candidate maintenance (needs Hivemind improvements)
- Agent migration from Hivemind to Loa
- Claude Chrome design iteration integration

---

## Pilot Experiment Context

### CubQuests + Set & Forgetti Integration
- **Domains**: Game design, frontend, backend, education
- **User**: Soju (context-switcher persona)
- **Philosophy**: Play → Learn → Earn (in that order)

### The Education Skill Gap
- May discover need for education/gamification skill specific to CubQuests
- Lead with **gamification as a layer over earning**
- **Learning happens as a result** of play, not before it
- "Do first, understand later" approach

---

## Gamification Research (Actionable Gamification / Octalysis)

### Prompts to Use with the Book

**Prompt 1: Core Drive Mapping for DeFi Vaults**
```
Based on the Octalysis framework, which core drives are most effective for
onboarding users to DeFi vault products like "Set & Forgetti" where users:
- Deposit assets into a vault
- Wait for yield to accumulate (set and forget)
- Harvest rewards periodically

Map each phase (deposit, wait, harvest) to specific core drives and suggest
game mechanics that would make each phase engaging rather than passive.
```

**Prompt 2: Quest Progression for Financial Literacy**
```
Using the concepts from Chapters on "Beginner's Luck" and "Scaffolding",
design a quest progression that teaches users about:
1. What a liquidity pool is
2. What impermanent loss means
3. How auto-compounding works

The quests should follow Play → Learn → Earn: users DO something first,
UNDERSTAND what they did second, and EARN rewards third. What game mechanics
from Octalysis would sequence these effectively?
```

**Prompt 3: White Hat vs Black Hat for Retention**
```
For a "quest platform" (CubQuests) integrated with a DeFi vault (Set & Forgetti):

Which White Hat core drives should dominate the ONBOARDING experience?
Which Black Hat core drives (if any) are ethical for RETENTION without
creating addiction patterns?

How do we use gamification to create "sticky" behavior around healthy
financial habits (regular harvesting, not panic selling)?
```

**Prompt 4: The "Tutorial Island" Problem**
```
Many DeFi apps fail at onboarding because they either:
- Dump information (learning before doing)
- Skip explanation entirely (doing without understanding)

Using the Octalysis framework's concept of "Discovery Phase" and
"Scaffolding", design a quest sequence where:
- First action: User deposits a small amount into S&F vault
- Revelation: They see their first yield accumulate
- Understanding: They learn WHY that happened
- Mastery: They optimize their strategy

What specific game techniques from the book support this "do first,
understand later" approach?
```

**Prompt 5: Social Mechanics for Async Teams**
```
CubQuests serves a global async community (The Honey Jar). Using the
Social Influence & Relatedness core drive:

What game mechanics create "collaborative competition" where users:
- Help each other learn (not just compete)
- Share strategies asynchronously
- Build reputation through teaching others

How does this differ from typical leaderboard mechanics?
```

---

## Open Questions (To Address in Future Iterations)

1. **Agent Isolation**: Should Hivemind agents run on separate machine, or can symlinked agents work in Loa context? (Needs technical spike)

2. **Brand Document Versioning**: How to handle brand bible updates mid-project? (Linear versioning vs snapshots)

3. **Education Skill**: If pilot surfaces need for education/gamification skill, when to create it? (During pilot or after?)

4. **Cross-Project Labels**: How to handle experiments spanning multiple products (CubQuests + Set & Forgetti)? (Jani's multi-label approach)

5. **Gamification Insights**: What patterns from "Actionable Gamification" apply to S&F + CubQuests? (Capture after reading)

---

## Process Notes

### From Jani (2025-12-19)
> "don't try and shoe horn it all in. note down stuff which you have in mind. and then after you have gone through the entire process, you run the /plan-and-analyze from the beginning and then you say you want to improve the code base and then just go through the process top to bottom again"

> "don't ponder! trust the process! run architect! if you have a moment of... oh shit i forgot this context. don't worry about it. note it down and come back to it in the next iteration."

### Iteration Philosophy
- Trust the process - get to the end
- Note ideas in this file, don't block progress
- After full cycle: run `/plan-and-analyze` again with new context
- Each iteration incorporates learnings from previous

---

## Hivemind Context References

### Key Documents to Consult
- `library/decisions/ADR-042-library-vs-laboratory-boundary.md`
- `library/ecosystem/OVERVIEW.md`
- `library/team/INDEX.md` (Knowledge Experts)
- `.claude/skills/INDEX.md`
- `.claude/skills/lab-cubquests-game-design/`

### Library vs Laboratory (from Eileen)
- **Library**: Surfaces evidence, provides useful context, knows relative reality (past)
- **Library**: CANNOT apply labels, CANNOT make decisions
- **Laboratory**: Where experiments happen, labels get applied
- Learning memos from lab → go to library after experiment
- Biweekly: Library provides potential stuff based on evidence → team reviews

---

## Architecture Decisions (SDD Phase)

### Decision 1: Implementation Strategy
**Chosen**: Modified `/setup` with modular checkbox UX
- `/setup` offers optional Hivemind connection
- Checkbox-based questions for engagement
- Clear benefits messaging for Hivemind connection
- Modular helper functions in `.claude/lib/` if needed

### Decision 2: Context Query Mechanism
**Chosen**: Use Hivemind's existing agents (symlinked)
- Reference Hivemind's `/ask` command pattern
- Spawn parallel research agents: @decision-archaeologist, @timeline-navigator, etc.
- Thorough, intentional approach to querying organizational memory
- Enables multiple perspectives on Hivemind content

### Decision 3: Mode Detection Triggers
**Chosen**: Phase-based rules (v1), hybrid in future iterations
- PRD/Architecture/Sprint → per-project type setting
- Audit/Deploy → always Secure mode
- Implementation → depends on project type
- **Future iteration**: Add keyword and file-pattern detection

### Decision 4: Candidate Surfacing Trigger
**Chosen**: Batch at end of phase, non-blocking
- ADR candidates surfaced at end of Architecture phase
- Learning candidates surfaced at end of Implementation phase
- User reviews summary before Linear submission
- Non-blocking to maintain flow state

### Decision 5: Skill Symlink Strategy
**Chosen**: Symlink folders with validation
- Symlink skill folders from `.hivemind/.claude/skills/` to `.claude/skills/`
- Startup validation checks symlinks are valid
- Graceful fallback if symlinks break

---

*Last updated: 2025-12-19*
