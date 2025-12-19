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

## ADR Flow Review Needed (Sprint 3)

### Context (From Eileen Conversation - 2025-12-19)
Need to revisit where ADR candidates go in the Hivemind structure:

**Current Implementation**:
- ADR candidates surfaced during `/architect` phase
- Submitted to Linear for team review
- Intended to flow back to Hivemind Library after review

**Questions to Address**:
1. Should ADR candidates go to **Library** or **Laboratory**?
   - Library = organizational memory (past decisions)
   - Laboratory = experiments in progress
   - Eileen suggests Laboratory might make more sense during active work

2. Are we reading from the right place?
   - Currently querying `.hivemind/library/decisions/` for existing ADRs
   - Is this correct, or should we also check laboratory?

3. Parallel Changes in Hivemind OS
   - Hivemind OS repo is being updated in parallel
   - May cause breaking changes to symlink paths or skill locations
   - Continue as planned but note potential conflicts

**Action Items**:
- [ ] Review ADR flow diagram in SDD
- [ ] Verify symlink paths still work after Hivemind OS updates
- [ ] Discuss with team: ADR candidates → Library or Laboratory?
- [ ] Update implementation if needed in next iteration

**Temporary Decision**: Continue with current flow (ADRs to Linear, team reviews biweekly). Revisit in next iteration after Hivemind OS changes stabilize.

---

## Sprint 4: Pilot Run Guide (S4-T5)

### Prerequisites for Pilot

Before running the pilot with CubQuests + Set & Forgetti:

1. **Hivemind OS Available**: Ensure `../hivemind-library` exists with skills
2. **Linear Configured**: MCP server configured with API access
3. **Experiment Created**: Linear issue with hypothesis for CubQuests + S&F integration

### Pilot Execution Steps

#### Step 1: Run `/setup` with Full Configuration
```
/setup

Configure:
- [x] Connect to Hivemind OS → ../hivemind-library
- [x] Project Type: game-design (or cross-domain for multi-domain)
- [x] Link Product Home → CubQuests project
- [x] Link Experiment → LAB-XXX (CubQuests + S&F integration)
```

Verify:
- `.hivemind/` symlink created
- `.claude/skills/` populated with game design skills
- `.claude/.mode` shows `creative` mode
- `integration-context.md` has Product Home and Experiment sections

#### Step 2: Run `/plan-and-analyze`
```
/plan-and-analyze

Expected:
- Agent queries Hivemind for ADRs, experiments, Learning Memos
- Context from linked experiment injected into PRD discovery
- PRD generated with references to organizational context
```

Verify:
- `loa-grimoire/prd.md` references experiment hypothesis
- ADRs from Hivemind cited in requirements

#### Step 3: Run `/architect`
```
/architect

Expected:
- SDD generated based on PRD
- ADR candidates detected from architecture decisions
- Batch review prompt appears at phase end
```

Verify:
- `loa-grimoire/sdd.md` generated
- ADR candidate surfacing prompt appears
- If submitted: Linear issues created with `[ADR-Candidate]` prefix

#### Step 4: Run `/sprint-plan`
```
/sprint-plan

Expected:
- Sprint breakdown based on SDD
- Tasks with acceptance criteria
- Dependencies mapped
```

Verify:
- `loa-grimoire/sprint.md` generated
- Clear task breakdown with estimates

#### Step 5: Run Sprint Cycle (at least 1)
```
/implement sprint-1
/review-sprint sprint-1
/audit-sprint sprint-1
```

Verify:
- Implementation report generated
- Learning candidates surfaced after implementation
- Security audit passes

### Pilot Success Criteria

| Metric | Target | Verification |
|--------|--------|--------------|
| Hivemind context injected | ADRs referenced in PRD | Check prd.md citations |
| Mode switching works | Confirmation on mismatch | Switch Creative → Secure |
| ADR candidates surfaced | 2+ from architecture | Linear issues exist |
| Learning candidates surfaced | 1+ from implementation | Linear issues exist |
| Pilot completes | Full cycle executed | Sprint reports in a2a/ |
| No blocking failures | Graceful degradation | Disconnect Hivemind, verify continues |

---

## Sprint 4: Retrospective (S4-T6)

### What Worked Well

1. **Non-Blocking Design Pattern**
   - Context injection, candidate surfacing, and analytics all gracefully degrade
   - Phase execution never blocked by external system failures
   - This pattern should be applied to all future integrations

2. **Symlink-Based Skill Loading**
   - Clean separation between Hivemind skills and Loa execution
   - Easy to add/remove skills without modifying Loa core
   - Validation + repair flow handles broken symlinks gracefully

3. **Mode Confirmation Gates**
   - Clear UX for mode mismatches
   - User always in control of mode switches
   - Analytics tracking for observability

4. **Batch Review for Candidates**
   - Not spamming Linear with every potential candidate
   - User reviews and approves before submission
   - Skip option respects developer flow state

5. **Progressive Setup UX**
   - Phase-based setup with clear progress indicators
   - Optional sections don't block core setup
   - Summary at end shows complete configuration

### What Needs Improvement

1. **ADR Flow Clarity**
   - Library vs Laboratory destination still unclear
   - Need team discussion on biweekly review process
   - May need to update flow after Hivemind OS changes

2. **Experiment Context Extraction**
   - Parsing hypothesis from Linear issue body is fragile
   - Could use structured fields or templates
   - Consider adding validation for experiment format

3. **Skill Discovery**
   - Currently hard-coded skill mappings per project type
   - Could detect available skills dynamically from Hivemind
   - Allow custom skill selection in setup

4. **Mode Detection**
   - Only phase-based rules in v1
   - Could add file pattern detection (*.sol → secure)
   - Could add keyword detection in prompts

### Gap Candidates Discovered

1. **Education/Gamification Skill**
   - Not currently in Hivemind skill library
   - Needed for CubQuests quest design patterns
   - Could capture Octalysis framework concepts

2. **Brand Versioning Pattern**
   - How to handle brand bible updates mid-project
   - Linear versioning vs snapshots
   - Cross-project brand consistency

3. **Multi-Product Experiments**
   - CubQuests + S&F spans multiple repos
   - Label structure for cross-product work
   - Shared context between product teams

### Learning Candidates for Future

1. **Pattern: Non-Blocking External Calls**
   ```
   Context: When calling external systems (Linear, Hivemind)
   Pattern: Always wrap in try-catch with graceful fallback
   Evidence: Sprint 1-3 context injection implementations
   Application: Any future external integration
   ```

2. **Pattern: AskUserQuestion for Progressive Disclosure**
   ```
   Context: Complex setup with many optional features
   Pattern: Use structured questions with clear options
   Evidence: Setup phases 2.5-3.8
   Application: Any multi-step wizard workflow
   ```

3. **Pattern: Symlink Validation with Repair**
   ```
   Context: External dependencies via symlinks
   Pattern: Validate on startup, attempt repair, graceful degradation
   Evidence: .claude/lib/hivemind-connection.md
   Application: Any symlink-based integration
   ```

### Next Iteration Priorities

1. **Complete Pilot Run**: Execute full cycle with real CubQuests project
2. **Resolve ADR Flow**: Team discussion on Library vs Laboratory
3. **Dynamic Skill Loading**: Detect available skills from Hivemind
4. **File-Based Mode Detection**: Add *.sol → secure mode trigger

---

*Last updated: 2025-12-19*
