# Product Requirements Document: Loa + Hivemind OS Integration

**Version**: 2.0
**Date**: 2025-12-19
**Author**: PRD Architect Agent
**Status**: Draft
**Experiment**: CubQuests + Set & Forgetti Integration (Pilot)

---

## 1. Executive Summary

### 1.1 Problem Statement

The Honey Jar operates as a global async organization with knowledge distributed across multiple systems:

- **Hivemind OS** (Library + Laboratory): Organizational memory, decisions (ADRs), events (ERRs), experiments, User Truth Canvases
- **Loa Framework**: Agent-driven product development (PRD → SDD → Sprint → Deploy)
- **Linear**: Collaborative multiplayer space for design/engineering work, Product Homes, cycles

Currently these systems are disconnected:
- Loa agents lack organizational context when making design decisions
- Architectural decisions made during Loa execution don't flow back to Hivemind Library
- Context-switching between domains (frontend, contracts, indexer) lacks structural support
- No integration between Hivemind experiments and Loa project execution

### 1.2 Vision

**Loa becomes the Laboratory Executor for Hivemind OS** - taking clustered User Truth Canvases from the seed cycle and executing them as structured experiments through the full product development lifecycle.

The loop completes when:
1. Hivemind Library surfaces evidence and patterns → User Truth Canvases
2. Team decides on experiment (biweekly cycle)
3. Loa executes experiment (PRD → Audit → Deploy)
4. Learning Memos + ADR Candidates flow back to Hivemind
5. Organization learns → Library grows

### 1.3 Success Criteria

| Metric | Target |
|--------|--------|
| Hivemind context availability | 100% of Loa phases can query relevant ADRs, ERRs, Learning Memos |
| ADR/Learning candidate capture | 80%+ of significant decisions surfaced automatically |
| Context-switching friction | Mode confirmation prevents wrong-mode execution |
| First experiment completion | CubQuests + Set & Forgetti integration ships with full loop |

---

## 2. Goals & Objectives

### 2.1 Primary Goals

| Goal | Description | Measure |
|------|-------------|---------|
| **Organizational Memory Integration** | Loa agents consult Hivemind before major decisions | Context injection at PRD, Architecture, Sprint phases |
| **Feedback Loop Completion** | Learnings flow back to Hivemind Library | ADR/Learning candidates auto-surfaced to Linear |
| **Mode-Aware Execution** | Creative vs Secure mode supported | Confirmation gates when context-switching |
| **Linear-Centric Coordination** | Product Home as source of truth | Setup creates/links Product Home, cycles map to sprints |

### 2.2 Secondary Goals

- Faster onboarding via organizational context access
- Reduced re-invention through past experiment awareness
- Design-engineering iteration support (Claude Chrome integration future)
- Progressive self-maintenance as system learns patterns

---

## 3. User & Stakeholder Context

### 3.1 Primary Users

#### Design Engineer (Context-Switcher)
**Example**: Soju
- Works across multiple domains: frontend, backend, contracts, game design
- Needs mode confirmation when switching contexts
- Benefits from brand context loading (design) and technical docs (engineering)
- Pilot user for CubQuests + Set & Forgetti experiment

#### Focused Frontend Developer
**Example**: Zerker
- Stays in design-engineer mode
- Iterates on frontend before backend integration
- Benefits from brand guidelines, component patterns, visual identity skills
- Mode detected at setup, stays consistent

#### Focused Smart Contract Developer
**Example**: Zergucci
- Stays in secure mode for contracts
- Needs intentional friction (HITL gates) to prevent hallucinations
- Benefits from contract lifecycle skills, security patterns
- Mode detected at setup, stays consistent

### 3.2 Secondary Stakeholders

#### Team Reviewers
- Review ADR/Learning candidates in biweekly Hivemind cycle
- Sign off on proposals through Linear
- Human-in-the-loop at key decision points

#### Organization (Future)
- Benefits from accumulated organizational memory
- Progressive self-maintenance reduces manual overhead

### 3.3 Environment Context

| System | Role | Integration |
|--------|------|-------------|
| **Hivemind OS** | Organizational memory (Library) + Experiments (Lab) | `.hivemind/` symlink, skills auto-load |
| **Linear** | Collaborative space, Product Homes, cycles | MCP integration, cycle ↔ sprint mapping |
| **Loa** | Laboratory Executor | This integration |
| **Claude Chrome** | Design iteration (future) | P2, not in v1 scope |

---

## 4. Functional Requirements

### 4.1 Setup & Hivemind Connection (`/setup` Extension)

#### 4.1.1 Hivemind Connection

| ID | Requirement | Priority |
|----|-------------|----------|
| HMC-001 | Detect if `../hivemind-library` (or configurable path) exists | P0 |
| HMC-002 | Create `.hivemind/` symlink to hivemind-os root | P0 |
| HMC-003 | Symlink relevant skills from `.hivemind/.claude/skills/` to `.claude/skills/` | P0 |
| HMC-004 | Skills auto-load based on keywords (existing Hivemind pattern) | P0 |
| HMC-005 | Display confirmation of Hivemind connection status | P0 |

#### 4.1.2 Project Type Detection

| ID | Requirement | Priority |
|----|-------------|----------|
| PTD-001 | Prompt user to select project type: `frontend`, `contracts`, `indexer`, `backend`, `game-design`, `cross-domain` | P0 |
| PTD-002 | Auto-load skills relevant to project type | P0 |
| PTD-003 | Set initial mode based on project type (Creative for frontend/design, Secure for contracts) | P0 |
| PTD-004 | Store project type in `integration-context.md` | P0 |

#### 4.1.3 Linear Product Home Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| LPH-001 | Prompt: Create new Product Home OR link existing project | P1 |
| LPH-002 | If creating: Use Product Home Linear template | P1 |
| LPH-003 | If linking: Fetch project ID from user or experiment issue URL | P1 |
| LPH-004 | Store Product Home project ID in `integration-context.md` | P1 |
| LPH-005 | Load brand context from Product Home documents (brand bible, technical changelog) | P1 |

#### 4.1.4 Experiment Linking

| ID | Requirement | Priority |
|----|-------------|----------|
| EXP-001 | Prompt: Link to existing Hivemind experiment (Linear issue URL) | P1 |
| EXP-002 | Fetch experiment details (hypothesis, success criteria, User Truth Canvas) | P1 |
| EXP-003 | Store experiment ID in `integration-context.md` | P1 |
| EXP-004 | Reference experiment context during PRD phase | P1 |

### 4.2 Mode Management

#### 4.2.1 Mode Detection & Confirmation

| ID | Requirement | Priority |
|----|-------------|----------|
| MOD-001 | Track current mode in `.claude/.mode` file | P0 |
| MOD-002 | On phase start, check if current work matches stored mode | P0 |
| MOD-003 | If mode mismatch detected, prompt: "Switching from {X} to {Y}. Confirm?" | P0 |
| MOD-004 | Allow user to confirm switch or stay in current mode | P0 |
| MOD-005 | Log mode switches in analytics | P1 |

#### 4.2.2 Mode-Specific Behavior

| Mode | Characteristics | Loaded Skills |
|------|----------------|---------------|
| **Creative** | Exploration, options, brand alignment, design iteration | `lab-creative-mode-operations`, `lab-*-brand-identity`, `lab-frontend-design-systems` |
| **Secure** | Strictness, gates, approvals, intentional friction | `lab-security-mode-operations`, `lib-hitl-gate-patterns`, `lab-contract-lifecycle-management` |

### 4.3 Context Injection

#### 4.3.1 PRD Phase Context

| ID | Requirement | Priority |
|----|-------------|----------|
| CTX-001 | Query Hivemind for related ADRs (by keywords from problem statement) | P0 |
| CTX-002 | Query Hivemind for past experiments (similar User Truth Canvases) | P0 |
| CTX-003 | Query Hivemind for relevant Learning Memos | P0 |
| CTX-004 | Surface GAP_TRACKER items related to this domain | P1 |
| CTX-005 | Load experiment context if linked during setup | P1 |

#### 4.3.2 Architecture Phase Context

| ID | Requirement | Priority |
|----|-------------|----------|
| CTX-010 | Query ecosystem overview from Hivemind (`library/ecosystem/`) | P0 |
| CTX-011 | Query contract registry if contracts involved | P0 |
| CTX-012 | Query services inventory for integration patterns | P1 |
| CTX-013 | Query technical debt registry | P1 |

#### 4.3.3 Sprint Planning Phase Context

| ID | Requirement | Priority |
|----|-------------|----------|
| CTX-020 | Map sprints to Linear cycles | P1 |
| CTX-021 | Query related Linear issues for sub-issue breakdown | P1 |
| CTX-022 | Surface Knowledge Experts for task assignment suggestions | P1 |

#### 4.3.4 Implementation Phase Context

| ID | Requirement | Priority |
|----|-------------|----------|
| CTX-030 | Auto-load domain skills (game-design, indexer, frontend, contracts) | P0 |
| CTX-031 | Load brand context if in Creative mode | P1 |
| CTX-032 | Load security patterns if in Secure mode | P0 |

#### 4.3.5 Review/Audit Phase Context

| ID | Requirement | Priority |
|----|-------------|----------|
| CTX-040 | Query past audit findings for similar code patterns | P1 |
| CTX-041 | Reference security Learning Memos | P1 |

### 4.4 Automatic Candidate Surfacing

#### 4.4.1 ADR Candidate Detection

| ID | Requirement | Priority |
|----|-------------|----------|
| ADR-001 | During Architecture phase, detect architectural decisions being made | P0 |
| ADR-002 | Pattern: "We decided to use X instead of Y because Z" | P0 |
| ADR-003 | Create Linear issue tagged `[ADR-Candidate]` in Product Home project | P0 |
| ADR-004 | Include: Decision, Alternatives Considered, Rationale, Trade-offs | P0 |
| ADR-005 | Link to Loa artifact (sdd.md) where decision documented | P1 |

#### 4.4.2 Learning Candidate Detection

| ID | Requirement | Priority |
|----|-------------|----------|
| LRN-001 | During Implementation/Review, detect proven patterns | P0 |
| LRN-002 | Pattern: "We discovered that X works better than Y for Z" | P0 |
| LRN-003 | Create Linear issue tagged `[Learning-Candidate]` in Product Home project | P0 |
| LRN-004 | Include: Pattern discovered, Context, Evidence, Recommended application | P0 |
| LRN-005 | Link to implementation code/tests demonstrating pattern | P1 |

#### 4.4.3 Gap Candidate Detection (P2)

| ID | Requirement | Priority |
|----|-------------|----------|
| GAP-001 | Detect "We don't know how to do X" moments | P2 |
| GAP-002 | Create Linear issue tagged `[Gap-Candidate]` | P2 |
| GAP-003 | Requires Hivemind improvements to maintain GAP_TRACKER via Linear | P2 |

### 4.5 Skill Integration

#### 4.5.1 Skill Symlink Setup

| ID | Requirement | Priority |
|----|-------------|----------|
| SKL-001 | During `/setup`, symlink relevant skills based on project type | P0 |
| SKL-002 | Update Loa agent frontmatter with `skills:` field referencing symlinked skills | P0 |
| SKL-003 | Skills auto-activate based on keywords (existing Hivemind pattern) | P0 |

#### 4.5.2 Skill Categories by Project Type

| Project Type | Skills to Symlink |
|--------------|-------------------|
| `frontend` | `lab-frontend-design-systems`, `lab-creative-mode-operations`, brand identity skills |
| `contracts` | `lab-contract-lifecycle-management`, `lab-security-mode-operations`, `lib-hitl-gate-patterns` |
| `indexer` | `lab-envio-indexer-patterns`, `lab-thj-ecosystem-overview` |
| `game-design` | `lab-cubquests-game-design`, `lab-cubquests-visual-identity`, `lab-*-brand-identity` |
| `cross-domain` | All above + `lib-orchestration-patterns`, `lib-feedback-loop-design` |

---

## 5. Non-Functional Requirements

### 5.1 Performance

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-001 | Context queries should complete in <5 seconds | P0 |
| NFR-002 | Skill loading should not add noticeable latency | P0 |
| NFR-003 | Symlink operations should be instant | P0 |

### 5.2 Reliability

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-010 | Hivemind unavailable should not block Loa execution | P0 |
| NFR-011 | Candidate surfacing failures should be logged, not blocking | P0 |
| NFR-012 | Mode state persists across sessions | P0 |

### 5.3 Usability

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-020 | Mode confirmation should be single yes/no | P0 |
| NFR-021 | Context injection should be invisible (no extra prompts) | P0 |
| NFR-022 | Candidate surfacing should be automatic (no manual tagging) | P0 |

### 5.4 Security

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-030 | `.hivemind/` symlink should be gitignored | P0 |
| NFR-031 | Hivemind content never committed to project repo | P0 |
| NFR-032 | Linear API keys handled via existing MCP patterns | P0 |

---

## 6. Scope

### 6.1 In Scope (v1 MVP)

**Must Have (P0)**:
- `/setup` Hivemind connection (`.hivemind/` symlink)
- Project type detection and skill loading
- Mode tracking and confirmation gates
- Context injection at PRD phase (ADRs, experiments, Learning Memos)
- Automatic ADR/Learning candidate surfacing
- Skills symlinked from hivemind-os

**Should Have (P1)**:
- Linear Product Home integration
- Experiment linking
- Brand context loading from Linear docs
- Context injection at all phases
- Cycle ↔ sprint mapping

### 6.2 Out of Scope (v1)

**Deferred (P2)**:
- Full Hivemind `/ask` command in Loa (just context injection for now)
- GAP candidate maintenance (needs Hivemind improvements)
- Agent migration from Hivemind to Loa
- Claude Chrome design iteration integration
- Separate Hivemind machine/deployment for agent isolation

### 6.3 Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Hivemind MCP (Product Home queries) | Exists | Can query project by ID |
| Linear MCP | Exists | Issue creation, project queries |
| Product Home Linear template | Exists | Can create from template |
| Hivemind skills stability | Stable | 28 skills mature/complete |
| Multi-project labels in Linear | Works | Jani configured this |

---

## 7. User Flows

### 7.1 First-Time Setup with Hivemind

```
Developer runs `/setup`
         │
         ▼
┌────────────────────────┐
│ Detect Hivemind        │
│ ../hivemind-library?   │
└────────────────────────┘
         │ Found
         ▼
┌────────────────────────┐
│ Create .hivemind/      │
│ symlink                │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Select Project Type    │
│ [frontend] [contracts] │
│ [indexer] [game-design]│
│ [cross-domain]         │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Link Product Home?     │
│ [Create new] [Link]    │
│ [Skip for now]         │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Link Experiment?       │
│ [Paste Linear URL]     │
│ [Skip for now]         │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Symlink Skills         │
│ Based on project type  │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Set Initial Mode       │
│ Creative / Secure      │
└────────────────────────┘
         │
         ▼
  Setup Complete
  → /plan-and-analyze unlocked
```

### 7.2 PRD with Hivemind Context

```
Developer runs `/plan-and-analyze`
         │
         ▼
┌────────────────────────┐
│ Load Experiment Context│
│ (if linked)            │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Query Hivemind         │
│ - Related ADRs         │
│ - Past experiments     │
│ - Learning Memos       │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ PRD Architect Agent    │
│ (with Hivemind context)│
│ "Based on ADR-042, we  │
│  should consider..."   │
└────────────────────────┘
         │
         ▼
  PRD Generated
  (with ADR/experiment refs)
```

### 7.3 Mode Confirmation Flow

```
Developer in Creative mode
         │
         ▼
┌────────────────────────┐
│ Starts work on         │
│ contract deployment    │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Mode Mismatch Detected │
│ Current: Creative      │
│ Work implies: Secure   │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ "Switching from        │
│  Creative → Secure.    │
│  Confirm?"             │
│ [Yes, switch] [Stay]   │
└────────────────────────┘
         │
         ▼ (if confirmed)
┌────────────────────────┐
│ Load Secure mode skills│
│ Add HITL gates         │
└────────────────────────┘
         │
         ▼
  Proceed with work
```

### 7.4 ADR Candidate Surfacing

```
During Architecture phase
         │
         ▼
┌────────────────────────┐
│ Agent makes decision:  │
│ "Using Supabase over   │
│  Convex because..."    │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│ Pattern detected:      │
│ "X instead of Y        │
│  because Z"            │
└────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│ Create Linear Issue                │
│ Project: [Product Home]            │
│ Title: [ADR-Candidate] Supabase... │
│ Labels: adr-candidate, sprint:...  │
│ Body: Decision, Alternatives,      │
│       Rationale, Trade-offs        │
└────────────────────────────────────┘
         │
         ▼
  Continue Architecture phase
  (non-blocking)
```

### 7.5 Complete Experiment Loop

```
HIVEMIND SEED CYCLE
         │
         ▼ User Truth Canvases clustered
TEAM DECIDES (biweekly)
         │ "Let's experiment with X"
         ▼
LOA /setup (links experiment)
         │
         ▼
LOA /plan-and-analyze
         │ Context: experiment hypothesis,
         │ related ADRs, past experiments
         ▼
LOA /architect
         │ ADR-Candidates surfaced
         ▼
LOA /sprint-plan
         │ Cycles created in Linear
         ▼
LOA /implement → /review → /audit
         │ Learning-Candidates surfaced
         ▼
LOA /deploy-production
         │
         ▼
FEEDBACK LOOP STARTS
         │ Ship → Measure → Learn
         ▼
HIVEMIND CAPTURES (biweekly)
         │ Team reviews ADR/Learning candidates
         │ Graduates proven patterns to Library
         ▼
LIBRARY GROWS
         │ New ADRs, Learning Memos, ERRs
         ▼
ORGANIZATION LEARNS
```

---

## 8. Data Models

### 8.1 Extended `integration-context.md`

```markdown
## Hivemind Integration

### Connection Status
- **Hivemind Path**: .hivemind → ../hivemind-library
- **Connection Date**: 2025-12-19T10:30:00Z
- **Project Type**: cross-domain
- **Current Mode**: creative

### Product Home
- **Project ID**: {uuid}
- **Project Name**: CubQuests + Set & Forgetti
- **Product Label**: Product → CubQuests, Product → Set & Forgetti

### Linked Experiment
- **Experiment ID**: LAB-XXX
- **Hypothesis**: {from Linear issue}
- **Success Criteria**: {from Linear issue}
- **User Truth Canvas**: {link}

### Loaded Skills
- lab-cubquests-game-design
- lab-frontend-design-systems
- lab-creative-mode-operations
- lib-orchestration-patterns
```

### 8.2 Mode State File (`.claude/.mode`)

```json
{
  "current_mode": "creative",
  "set_at": "2025-12-19T10:30:00Z",
  "project_type": "cross-domain",
  "mode_switches": [
    {
      "from": "creative",
      "to": "secure",
      "reason": "contract work detected",
      "timestamp": "2025-12-19T14:00:00Z",
      "confirmed": true
    }
  ]
}
```

### 8.3 ADR Candidate Issue Template

```markdown
## [ADR-Candidate] {Decision Title}

**Source**: Loa Architecture Phase
**Sprint**: {sprint-name}
**Date**: {timestamp}

### Decision
{What was decided}

### Context
{Why this decision was needed}

### Alternatives Considered
1. {Alternative 1} - {Why rejected}
2. {Alternative 2} - {Why rejected}

### Rationale
{Why this approach was chosen}

### Trade-offs
- **Pros**: {list}
- **Cons**: {list}

### References
- Loa SDD: `loa-grimoire/sdd.md#section`
- Related ADRs: {links to existing ADRs}

---
*Auto-surfaced by Loa. Review in biweekly Hivemind cycle.*
```

### 8.4 Learning Candidate Issue Template

```markdown
## [Learning-Candidate] {Pattern Title}

**Source**: Loa Implementation Phase
**Sprint**: {sprint-name}
**Date**: {timestamp}

### Pattern Discovered
{What was learned}

### Context
{When/where this applies}

### Evidence
- Implementation: `{file}:{lines}`
- Tests: `{test file}`
- Results: {metrics, outcomes}

### Recommended Application
{When others should use this pattern}

### References
- Loa Sprint Report: `loa-grimoire/a2a/sprint-N/reviewer.md`
- Related Learning Memos: {links}

---
*Auto-surfaced by Loa. Review in biweekly Hivemind cycle.*
```

---

## 9. Technical Architecture

### 9.1 Symlink Structure

```
project-root/
├── .hivemind/                    # Symlink → ../hivemind-library
│   ├── library/                  # Read-only access
│   │   ├── decisions/           # ADRs
│   │   ├── timeline/            # ERRs, GAP_TRACKER
│   │   ├── knowledge/           # Learning Memos
│   │   └── ecosystem/           # Architecture docs
│   ├── laboratory/              # Experiments, audits
│   └── .claude/
│       └── skills/              # Symlink source
│
├── .claude/
│   ├── agents/                  # Loa agents
│   ├── commands/                # Loa commands
│   ├── skills/                  # Symlinked from .hivemind
│   │   ├── lab-cubquests-game-design -> .hivemind/.claude/skills/...
│   │   ├── lab-frontend-design-systems -> ...
│   │   └── ...
│   └── .mode                    # Mode state file
│
├── loa-grimoire/               # Loa artifacts
└── .gitignore                  # Includes .hivemind/, .claude/.mode
```

### 9.2 Context Query Flow

```
Loa Agent (PRD Architect)
         │
         ▼
Read .hivemind/library/decisions/INDEX.md
         │ Search for keywords from problem statement
         ▼
Found: ADR-042 (Library vs Laboratory boundary)
       ADR-005 (Resource System)
         │
         ▼
Read .hivemind/laboratory/audits/logs/
         │ Search for similar experiments
         ▼
Found: ERR-2024-XXX (Previous quest integration)
         │
         ▼
Inject context into agent prompt:

"Based on organizational context:
- ADR-042 establishes Library/Laboratory boundary
- ADR-005 defines Resource System as core mechanic
- Previous experiment ERR-2024-XXX showed..."
```

---

## 10. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Hivemind not available locally | Low | High | Graceful fallback, Loa works without Hivemind |
| Context overload (too much injected) | Medium | Medium | Smart filtering by keywords, relevance scoring |
| Mode confirmation fatigue | Medium | Low | Only prompt on actual mismatch, remember confirmations |
| Symlink breaks on Hivemind update | Low | Medium | Relative paths, validation on startup |
| Candidate surfacing noise | Medium | Low | Keywords + patterns filter, team reviews in biweekly |
| Skills not auto-loading | Low | High | Frontmatter validation, startup checks |

---

## 11. Pilot Experiment: CubQuests + Set & Forgetti Integration

### 11.1 Experiment Details

**Objective**: Design and implement quest flow integrating CubQuests with Set & Forgetti v2

**Domains Covered**:
- Game design (quest creation, educational flow)
- Frontend (UI components, brand alignment)
- Backend (verification, rewards)
- Possibly: Education skill discovery (gap candidate)

**Pilot User**: Soju (context-switcher persona)

### 11.2 Success Criteria

| Criteria | Measure |
|----------|---------|
| Hivemind context surfaced in PRD | ADRs referenced, past experiments cited |
| Mode switching works | Confirmation prompts when switching design ↔ code |
| ADR candidates surfaced | At least 2 architectural decisions captured |
| Learning candidates surfaced | At least 1 pattern documented |
| Gap identified | Education skill need flagged for future |
| Quest ships | Integration live with feedback loop |

### 11.3 Feedback Collection

- After each phase: Quick survey on context usefulness
- After completion: Full feedback via `/feedback`
- Team review: Biweekly Hivemind cycle reviews candidates

---

## 12. Open Questions

1. **Agent Isolation**: Should Hivemind agents run on separate machine, or can symlinked agents work in Loa context? (Needs technical spike)

2. **Brand Document Versioning**: How to handle brand bible updates mid-project? (Linear versioning vs snapshots)

3. **Education Skill**: If pilot surfaces need for education/gamification skill, when to create it? (During pilot or after?)

4. **Cross-Project Labels**: How to handle experiments spanning multiple products (CubQuests + Set & Forgetti)? (Jani's multi-label approach)

---

## 13. Appendix

### A. Hivemind Skills Reference

| Skill | Category | Auto-Loads When |
|-------|----------|-----------------|
| `lib-source-fidelity-application` | governance | "verify", "attribution" |
| `lib-orchestration-patterns` | governance | "context", "spawn agent" |
| `lib-adr-surfacing` | governance | "ADR", "decision", "why" |
| `lab-cubquests-game-design` | game-design | "quest", "badge", "activity" |
| `lab-frontend-design-systems` | frontend | "component", "design system" |
| `lab-contract-lifecycle-management` | infrastructure | "contract", "deploy" |
| `lab-creative-mode-operations` | execution | "creative", "iterate" |
| `lab-security-mode-operations` | execution | "secure", "approver" |

### B. Linear Product Home Template Fields

- Brand Bible (versioned doc)
- Technical Changelog
- User Truth Canvases (linked)
- Active Experiments
- Graduated Learnings (linked)
- Team/Contributors

### C. Related Hivemind Documents

- `library/decisions/ADR-042-library-vs-laboratory-boundary.md`
- `library/ecosystem/OVERVIEW.md`
- `library/team/INDEX.md` (Knowledge Experts)
- `.claude/skills/INDEX.md`
- `.claude/COMMANDS.md`

---

## 14. Sources

Research conducted during PRD discovery:

- [Agent Skills - Claude Code Docs](https://code.claude.com/docs/en/skills)
- [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
- [AGENTS.md becomes the convention](https://pnote.eu/notes/agents-md/)
- [Tip: call the context file AGENTS.md and symlink to CLAUDE.md, GEMINI.md](https://vuink.com/post/cabgr-d-drh/notes/agents-md)
