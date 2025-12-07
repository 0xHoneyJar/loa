# Hivemind Laboratory Methodology

## Overview

The **Hivemind Laboratory** is a knowledge management and product development methodology designed for async-first, scale-ready organizations. It converts ephemeral Discord conversations into permanent organizational intelligence stored in Linear.

**Core Principle**: *"Single user feedback → permanent, reusable knowledge in the Library that makes the whole team smarter, even accounting for people who have not joined the team."*

## Why This Methodology Exists

Traditional product development loses context when:
- Team members join or leave
- People go on vacation
- Conversations happen in Discord and disappear in chat history
- Decisions lack documented rationale
- New hires have to re-ask the same questions

Hivemind Laboratory solves this by creating a **knowledge permanence layer** where every conversation, feedback, and learning becomes searchable, reusable organizational memory.

## Core Philosophy

### 1. Habitual Over Forcing Adoption
- Design systems that become natural habits, not mandates
- Let people discover value organically
- Progressive enhancement over big-bang rollouts
- "This style of workflow is a little bit of an adjustment" - accept the learning curve

### 2. Knowledge Permanence
- Every user feedback should create reusable knowledge
- Learnings outlive individual team members
- Future team members inherit accumulated wisdom
- Decisions documented with full context chains

### 3. Async-First
- Anyone can pick up work when someone else is unavailable
- Context preserved for timezone-distributed teams
- Documentation enables handoffs without meetings
- "Anyone stepping in or out for a vacation can pick it up"

### 4. Product-Focused (Not Process-Focused)
- Linear tracks product development only
- Emotions tracked only if JTBD (Jobs-To-Be-Done) relevant
- Avoid "feelings" unless they relate to user experience
- Focus on what users need, not team dynamics

### 5. Top-Down Hierarchy
- **Projects** = Big picture, strategic context
- **Issues** = Specific implementation boundaries
- **Tasks** = Granular work items
- Start with strategy, drill down to execution

## Linear Structure

### Team Organization

```
Workspace: The Honey Jar
├── LEARNINGS Team (Knowledge Library)
│   └── Issues tagged with learnings for future reference
├── FinTech Team (Product execution)
│   ├── Set & Forgetti
│   ├── Interpol
│   ├── FatBera
│   ├── Validator
│   └── VaaS
├── CultureTech Team (Product execution)
│   ├── MiBera
│   ├── Ooga Booga Bears
│   ├── Henlo
│   ├── CubQuests
│   └── Moneycomb
└── Corporate Team (Business operations)
```

### Issue Templates

#### 1. User Truth Canvas (Issue Level)
**Purpose**: Define clear development boundaries for implementation work

**Use when**: Developer needs to understand exact scope and user context

**Contains**:
- User jobs to be done
- User pains (obstacles)
- User gains (benefits)
- Acceptance criteria
- Edge cases and constraints

**Why Issue not Project**: Attached to specific implementation, granular scope

#### 2. Bug Report (Issue Level)
**Purpose**: Convert community feedback into structured bug documentation

**Flow**: Discord → CX Triage → Bug Report template

**Contains**:
- Steps to reproduce
- Expected vs actual behavior
- Environment details
- Priority/severity

#### 3. Feature Request (Issue Level)
**Purpose**: Convert community ideas into structured feature specs

**Flow**: Discord → CX Triage → Feature Request template

**Contains**:
- Problem statement
- Proposed solution
- User benefit
- Priority signals from community

#### 4. Canvas/Idea (Issue Level)
**Purpose**: Capture creative explorations from community

**Flow**: Discord → CX Triage → Canvas/Idea → Todo bucket

**Note**: These are exploratory, may evolve into features or experiments

### Project Templates

#### 1. Product Home (Project Level)
**Purpose**: Track product evolution over time

**Contains**:
- **Changelog**: Version history and updates
- **Retrospectives**: What we learned from shipping
- **Retroactives**: Historical context for decisions
- **Health Checks**: Current product status
- **Documents**: Stored under project for searchability

**Maintenance**:
- Weekly project updates (Track/Off Track/At Risk)
- Monthly health checks
- Assigned to product owner
- Updated changelog on every release

**Why Project not Issue**: Big picture evolution, cross-cutting concerns

#### 2. Experimental Project (Project Level)
**Purpose**: Big testing initiatives that might expand

**Use when**: Experiment could spawn multiple sub-tasks and learnings

**Example**: "Bera Infinity" experiment

**Contains**:
- Hypothesis being tested
- Success metrics
- Timeline and milestones
- Learnings captured as sub-issues or documents

**Why Project not Issue**: Experiments expand, need room for sub-tasks

#### 3. User Persona (Project Level)
**Purpose**: Big picture user understanding

**Contains**:
- Demographics and psychographics
- Jobs-to-be-done across products
- Pain points and gain opportunities
- Cross-product usage patterns

**Why Project not Issue**: Strategic, informs multiple products

### Label System

#### Status Labels (Project Health)
- **Track**: On schedule, healthy
- **Off Track**: Behind schedule or issues emerging
- **At Risk**: Major blockers or concerns
- **Dead**: Cancelled or shelved
- **Alive**: Active development

#### Task Labels
- Categorization for filtering
- Custom per team needs

#### Brand Labels
- Group projects by product line
- Example: MiBera, Henlo, FatBera, etc.

#### Team Labels
- **FinTech**: Financial product team
- **CultureTech**: Culture/community product team
- **Corporate**: Business operations

## Information Flow

### The Complete Journey

```
1. Discord Community Discussion
   │
   ├─ User reports bug
   ├─ User suggests feature
   ├─ User shares feedback
   └─ Team discusses idea
   │
   ↓ (Discord bot: linear-em-up)
   │
2. CX Triage (Linear Backlog)
   │
   ├─ All community input lands here
   └─ Unfiltered, unsorted queue
   │
   ↓ (CX Lead reviews and categorizes)
   │
3. Converted to Linear Template
   │
   ├─ Bug Report
   ├─ Feature Request
   ├─ User Truth Canvas
   └─ Canvas/Idea
   │
   ↓ (CX Lead assigns to team)
   │
4. Product Team Triage
   │
   ├─ FinTech Triage (for financial products)
   └─ CultureTech Triage (for community products)
   │
   ↓ (Team lead prioritizes)
   │
5. Implementation / Investigation
   │
   ├─ Developers work on bugs/features
   ├─ Designers iterate on UX
   └─ Product validates solution
   │
   ↓ (Learnings extracted)
   │
6. LEARNINGS Library (Permanent Knowledge)
   │
   ├─ What worked, what didn't
   ├─ Patterns discovered
   ├─ Context for future decisions
   └─ Searchable organizational memory
```

### Key Transition Points

**Discord → CX Triage**:
- Automated via `linear-em-up` bot
- Captures conversation context
- Preserves Discord message links

**CX Triage → Templates**:
- Manual review by CX Lead
- Human judgment on categorization
- Adds missing context from knowledge of community

**Templates → Team Triage**:
- CX Lead assigns to FinTech or CultureTech
- Based on product area and team capacity
- Includes priority signals from community

**Team Triage → Implementation**:
- Team lead prioritizes within team backlog
- Bugs assigned to developers
- Canvas/Ideas moved to Todo bucket for future review

**Implementation → LEARNINGS**:
- Completed work reviewed for learnings
- Patterns documented for future reference
- Knowledge added to searchable library

## Role Responsibilities

### CX Triage Lead (Community Experience Lead)

**Responsibilities**:
1. Review all incoming community feedback from Discord
2. Convert feedback into correct Linear template
3. Assign feedback to right product team triage (FinTech or CultureTech)
4. Manage the bridge between community and product teams
5. Ensure context isn't lost in translation

**Skills Required**:
- Deep community knowledge
- Product intuition
- Communication between technical and non-technical
- Pattern recognition for categorization

**Tools**:
- Discord access to community channels
- Linear admin for creating/editing issues
- Knowledge of existing templates and workflows

**Current Role Holder**: Prodigy (in example organization)

### Product Team Leads (FinTech / CultureTech)

**Responsibilities**:
1. Manage triage for their team
2. Prioritize and sequence work
3. Assign bugs to developers
4. Move Canvas/Ideas to Todo for future review
5. Weekly project updates (Track/Off Track/At Risk status)

**Decision Making**:
- What gets worked on this sprint
- Which bugs are critical vs nice-to-have
- When to escalate to leadership
- Resource allocation within team

**Tools**:
- Linear for triage and planning
- Discord for team coordination
- Product Home docs for context

**Current Role Holder**: Soju/CTO (in example organization)

### Project Owners

**Responsibilities**:
1. Weekly project updates (Track/Off Track/At Risk status)
2. Update Product Home documentation
3. Maintain changelog and retrospectives
4. Health checks on active projects
5. Ensure project context is preserved

**Cadence**:
- Weekly: Status updates
- Per release: Changelog updates
- Monthly: Health checks
- Per milestone: Retrospectives

**Deliverables**:
- Updated Product Home docs
- Changelogs with context
- Retrospective documents
- Status reports for leadership

### LEARNINGS Curator (Emerging Role)

**Responsibilities** (not yet fully defined):
1. Extract learnings from completed work
2. Identify patterns across multiple issues
3. Format learnings for discoverability
4. Tag and categorize in LEARNINGS team
5. Ensure knowledge permanence

**Skills Required**:
- Pattern recognition
- Technical writing
- Cross-product perspective
- Long-term thinking

**Note**: This role may be distributed across team members initially

## Key Design Decisions

### Why Projects > Issues?

**Eileen's insight**: "I think the way things should move is from a 'top down' expansion"

**Rationale**:
- Projects provide big picture context
- Issues drill into specific boundaries
- Top-down allows searching and creating views
- Every single issue being individual is too granular
- Projects = labels with big picture stuff

**Example**:
- **Project**: MiBera (product)
  - **Issue**: Add user profile customization (feature)
    - **Task**: Implement avatar upload (development)

### Why User Truth Canvas = Issue?

**Rationale**:
- Focused on actual development
- Developer needs exact boundaries
- Attached to specific implementation work
- Product-focused, not feelings

**Counter-example**: User Persona = Project
- Big picture understanding
- Informs multiple products
- Strategic, not tactical

### Why Experiments = Projects?

**Eileen's insight**: "Experiments might expand and have little things"

**Rationale**:
- Experiments spawn sub-tasks
- Need room to grow
- May become features if successful
- Require changelog and retrospective

**Counter to previous practice**: Previously experiments were simple feature requests (issues), but forward-thinking recognizes they can expand

### Why Documents Under Projects?

**Soju's explanation**: "Documents in Linear are a bit weird, they live under projects"

**Rationale**:
- Retrospectives and retroactives belong with project
- Searchable by anyone through keywords
- Attached to big picture context
- Not discoverable at workspace level easily

**Use case**: Historical context for new team members

## Integration with Agentic-Base Framework

### Where Agents Can Help

#### 1. Discord → Linear Bridge
**Agent Role**: Parse conversations, pre-populate templates

**Value**:
- Extract User Truth Canvas elements from Discord discussions
- Suggest appropriate template (Bug vs Feature vs Idea)
- Pre-fill template fields with conversation context
- Link back to original Discord messages

**Human Decision**: CX Lead reviews and approves/edits before creating

#### 2. Linear → LEARNINGS Extraction
**Agent Role**: Identify learning opportunities, format for library

**Value**:
- Monitor completed issues for patterns
- Extract "what we learned" from retrospectives
- Generate summary learnings documents
- Suggest tags for discoverability

**Human Decision**: Team validates learnings are accurate and useful

#### 3. PRD Generation from Hivemind
**Agent Role**: Query LEARNINGS, aggregate User Truth Canvas

**Value**:
- Pull historical context from LEARNINGS library
- Reference User Personas for target audience
- Aggregate multiple User Truth Canvas issues
- Include outcomes from past experiments

**Human Decision**: Product team validates PRD accuracy and completeness

#### 4. Product Home Maintenance
**Agent Role**: Generate changelogs, remind about health checks

**Value**:
- Summarize Linear activity into changelog format
- Prompt project owners for weekly status updates
- Identify projects missing recent updates
- Generate retrospective templates from completed milestones

**Human Decision**: Project owner reviews and approves changelog/updates

### What NOT to Automate

❌ **Auto-assigning issues without CX Lead review**
- CX Lead has community context agents don't have
- Assignment requires judgment about team capacity and fit

❌ **Forcing template fields to be filled**
- "Habitual over forcing" - let adoption be organic
- Some fields may not apply to every issue

❌ **Auto-moving items between teams**
- Organizational decisions require human understanding
- Team boundaries can be nuanced

❌ **Generating LEARNINGS without human validation**
- Learnings must be accurate and useful
- Pattern recognition requires human judgment

❌ **Changing existing workflows without team discussion**
- Respect "what must NOT change"
- Workflow changes need buy-in for habitual adoption

### Agent Assistance Philosophy

✅ **Assist**: Help CX Lead by pre-populating templates
✅ **Suggest**: Recommend labels, teams, priorities
✅ **Pre-populate**: Fill known fields from conversation context
✅ **Remind**: Prompt for health checks and updates
✅ **Summarize**: Generate changelog drafts from Linear activity
✅ **Extract**: Pull learnings from completed work
✅ **Link**: Connect related issues, projects, learnings

**Always**: Let humans make final decisions

## Measuring Success

### Adoption Metrics
- % of community feedback converted to Linear issues (coverage)
- Time from Discord message to Linear issue creation (speed)
- % of Linear issues with complete templates (quality)
- % of completed work with learnings extracted (knowledge capture)

### Knowledge Permanence Metrics
- LEARNINGS library growth rate
- Search queries hitting LEARNINGS results
- New team member onboarding time (does it decrease?)
- Repeat questions in Discord (should decrease)

### Async Effectiveness Metrics
- Cross-timezone handoff success rate
- "I don't know, [person] was handling that" instances (should decrease)
- Context loss incidents (work restarted due to lost context)

### Habitual Adoption Metrics
- Weekly active users of Linear
- Template usage rates
- Product Home update frequency
- Voluntary vs prompted status updates

## Evolution and Iteration

This methodology is **living, not static**. Expected evolution:

### Phase 1 (Current): Setup and Initial Adoption
- Create templates and labels
- Train CX Lead and team leads
- Establish habits through use
- Iterate on templates based on feedback

### Phase 2: Organic Growth
- Team discovers value organically
- Templates refined from real usage
- LEARNINGS library starts to populate
- Patterns emerge from accumulated work

### Phase 3: Knowledge Leverage
- New team members onboard using LEARNINGS
- Repeated patterns documented and reusable
- PRDs reference historical context
- Decisions made faster due to accumulated wisdom

### Phase 4: Scale Ready
- Methodology handles team growth
- Multiple product teams operate independently
- Cross-team learnings shared effectively
- Organizational memory robust despite turnover

## Glossary of Terms

**CX Triage**: Linear backlog where all community feedback lands initially

**LEARNINGS Team**: Special Linear team for storing permanent organizational knowledge

**User Truth Canvas**: Issue template defining user jobs, pains, gains, and development boundaries

**Product Home**: Project template tracking product evolution with changelog and retrospectives

**Experimental Project**: Project template for big testing initiatives

**linear-em-up**: Discord bot that feeds community messages into CX Triage

**Track/Off Track/At Risk**: Status labels for project health

**FinTech/CultureTech**: Product team divisions (financial vs community/culture products)

**Habitual adoption**: Organic adoption through habit formation vs forced compliance

**Knowledge permanence**: Ensuring information outlives individual team members

**Async-first**: Designing for timezone-distributed teams with handoffs

**Top-down hierarchy**: Projects > Issues > Tasks structure

## Further Reading

This methodology draws inspiration from:
- Jobs-To-Be-Done (JTBD) framework
- Lean product development
- Knowledge management systems
- Async-first remote work practices

## Credits

Developed by Eileen (Product/PM) in collaboration with Soju (CTO) for The Honey Jar organization, with implementation feedback from Prodigy (CX Lead) and the broader team.

## Questions or Improvements?

This methodology is designed for continuous improvement. If you have:
- Questions about how to apply this
- Suggestions for improvements
- Examples of what worked/didn't work
- New templates or patterns to share

Document them in the LEARNINGS team for future reference.

---

*Last updated: 2025-12-07*
*Version: 1.0 (Initial documentation of existing practice)*
