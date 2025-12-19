# Sprint Plan: Loa + Hivemind OS Integration (Legba)

**Version**: 1.0
**Date**: 2025-12-19
**Author**: Sprint Planner Agent
**PRD Reference**: `loa-grimoire/prd.md` v2.0
**SDD Reference**: `loa-grimoire/sdd.md` v1.0

---

## Overview

### Project Summary

Integrate Loa (Laboratory Executor) with Hivemind OS (Organizational Memory) to enable:
- Bidirectional context flow between systems
- Mode-aware execution (Creative vs Secure)
- Automatic ADR/Learning candidate surfacing
- Skill integration via symlinks

### Sprint Configuration

| Setting | Value |
|---------|-------|
| Sprint Duration | 2.5 days |
| Total Sprints | 4 |
| Total Timeline | ~10 days |
| Developer | Soju |
| Testing Approach | Manual validation (pilot validates) |

### MVP Scope

**P0 (Sprints 1-3)**:
- `/setup` Hivemind connection
- Project type detection and skill loading
- Mode tracking and confirmation gates
- Context injection at PRD phase
- Automatic ADR/Learning candidate surfacing

**P1 (Sprint 4)**:
- Linear Product Home integration
- Experiment linking
- Full pilot run (CubQuests + Set & Forgetti)

---

## Sprint 1: Foundation

**Goal**: Establish core infrastructure for Hivemind connection, mode management, and skill symlinks.

**Duration**: 2.5 days

### Tasks

#### S1-T1: Extend `/setup` Command with Hivemind Connection

**Description**: Modify the existing `/setup` command to include an optional Hivemind connection phase. Detect if `../hivemind-library` exists, create `.hivemind/` symlink, and update `integration-context.md`.

**Acceptance Criteria**:
- [ ] `/setup` displays "Connect to Hivemind OS" checkbox option
- [ ] If checked, detects `../hivemind-library` or prompts for custom path
- [ ] Creates `.hivemind/` symlink pointing to Hivemind library
- [ ] Validates symlink by checking `.hivemind/library/` exists
- [ ] Updates `loa-grimoire/a2a/integration-context.md` with Hivemind section
- [ ] Gracefully continues without Hivemind if user skips or path invalid
- [ ] Adds `.hivemind/` to `.gitignore`

**Effort**: Medium (4-6 hours)

**Assigned To**: Soju

**Dependencies**: None

**Validation**: Run `/setup`, select Hivemind connection, verify symlink created and integration-context.md updated.

---

#### S1-T2: Implement Project Type Selection

**Description**: Add project type selection to `/setup` with checkbox-style UX. Options: `frontend`, `contracts`, `indexer`, `backend`, `game-design`, `cross-domain`.

**Acceptance Criteria**:
- [ ] `/setup` displays project type selection after Hivemind connection
- [ ] Single selection from 6 options presented
- [ ] Selected project type stored in `integration-context.md`
- [ ] Project type used to determine initial mode and skills

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S1-T1 (setup flow structure)

**Validation**: Run `/setup`, select "game-design", verify stored in integration-context.md.

---

#### S1-T3: Create Mode State Management

**Description**: Implement `.claude/.mode` JSON file for tracking current mode, project type, and mode switch history.

**Acceptance Criteria**:
- [ ] Create `.claude/.mode` file with schema: `{current_mode, set_at, project_type, mode_switches[]}`
- [ ] Mode initialized based on project type mapping:
  - `frontend`, `game-design`, `backend`, `cross-domain` → `creative`
  - `contracts`, `indexer` → `secure`
- [ ] Mode file created during `/setup` completion
- [ ] Add `.claude/.mode` to `.gitignore`

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S1-T2 (project type)

**Validation**: After `/setup` with "contracts" type, verify `.claude/.mode` shows `current_mode: "secure"`.

---

#### S1-T4: Implement Skill Symlink Creation

**Description**: During `/setup`, symlink relevant skills from `.hivemind/.claude/skills/` to `.claude/skills/` based on project type.

**Acceptance Criteria**:
- [ ] Create `.claude/skills/` directory if not exists
- [ ] Symlink skills based on project type mapping from SDD section 3.1.3:
  - `frontend`: `lab-frontend-design-systems`, `lab-creative-mode-operations`, brand skills
  - `contracts`: `lab-contract-lifecycle-management`, `lab-security-mode-operations`, `lib-hitl-gate-patterns`
  - `indexer`: `lab-envio-indexer-patterns`, `lab-thj-ecosystem-overview`
  - `game-design`: `lab-cubquests-game-design`, `lab-cubquests-visual-identity`, brand skills
  - `backend`: `lab-thj-ecosystem-overview`, `lib-orchestration-patterns`
  - `cross-domain`: All above + `lib-feedback-loop-design`
- [ ] Log each symlink created
- [ ] Handle missing source skills gracefully (warn, continue)
- [ ] Record loaded skills in `integration-context.md`

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S1-T1 (Hivemind symlink), S1-T2 (project type)

**Validation**: Run `/setup` with "game-design", verify `.claude/skills/lab-cubquests-game-design` symlink exists and works.

---

#### S1-T5: Add Skill Validation on Phase Start

**Description**: Create shared utility logic that validates skill symlinks at the start of each Loa phase command, with automatic repair attempt for broken symlinks.

**Acceptance Criteria**:
- [ ] Create `.claude/lib/hivemind-connection.md` with validation instructions
- [ ] Validation checks each symlink in `.claude/skills/`
- [ ] Broken symlinks logged with warning
- [ ] Automatic repair attempted (re-symlink from `.hivemind/.claude/skills/`)
- [ ] If repair fails, log error but don't block phase execution

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S1-T4 (symlinks exist)

**Validation**: Manually break a symlink, run `/plan-and-analyze`, verify warning shown and repair attempted.

---

### Sprint 1 Success Criteria

| Metric | Target |
|--------|--------|
| Hivemind connection works | Symlink created, validated |
| Project type stored | In integration-context.md |
| Mode initialized | Based on project type |
| Skills symlinked | Based on project type |
| Validation runs | Broken symlinks detected |

---

## Sprint 2: Context Injection

**Goal**: Implement parallel research agent pattern to query Hivemind and inject organizational context into Loa phases.

**Duration**: 2.5 days

### Tasks

#### S2-T1: Create Context Injector Library

**Description**: Create `.claude/lib/context-injector.md` documenting the pattern for spawning parallel research agents to query Hivemind content.

**Acceptance Criteria**:
- [ ] Document describes parallel agent spawning pattern (from Hivemind `/ask`)
- [ ] Defines 3 core research agents:
  - `@decision-archaeologist`: Search ADRs
  - `@timeline-navigator`: Search ERRs, experiments
  - `@technical-reference-finder`: Search ecosystem docs, Learning Memos
- [ ] Each agent has: purpose, search paths, return format
- [ ] Synthesis pattern: deduplicate, rank, format for injection

**Effort**: Medium (3-4 hours)

**Assigned To**: Soju

**Dependencies**: S1-T1 (Hivemind connected)

**Validation**: Document complete and follows Hivemind `/ask` pattern.

---

#### S2-T2: Implement Keyword Extraction

**Description**: Add logic to extract keywords from problem statements, project type, and experiment context for targeted Hivemind queries.

**Acceptance Criteria**:
- [ ] Extract keywords from PRD problem statement (if exists)
- [ ] Include project type as keyword
- [ ] Include experiment hypothesis keywords (if linked)
- [ ] Filter common words, keep domain-specific terms
- [ ] Return keyword list for agent queries

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S2-T1 (context injector pattern)

**Validation**: Given sample problem statement, verify relevant keywords extracted.

---

#### S2-T3: Extend `/plan-and-analyze` with Context Injection

**Description**: Modify the PRD architect command to spawn parallel research agents before discovery, injecting Hivemind context into the agent prompt.

**Acceptance Criteria**:
- [ ] On `/plan-and-analyze` start, check if Hivemind connected
- [ ] If connected, extract keywords from any existing context
- [ ] Spawn parallel research agents using Task tool
- [ ] Collect results: relevant ADRs, past experiments, Learning Memos
- [ ] Inject summary into PRD architect prompt:
  ```
  Based on organizational context:
  - ADR-XXX establishes...
  - Previous experiment ERR-XXX showed...
  - Learning Memo suggests...
  ```
- [ ] If Hivemind not connected, proceed without injection (log notice)

**Effort**: Large (6-8 hours)

**Assigned To**: Soju

**Dependencies**: S2-T1, S2-T2, Sprint 1 complete

**Validation**: Run `/plan-and-analyze` with Hivemind connected, verify ADRs referenced in agent output.

---

#### S2-T4: Implement Graceful Fallback for Disconnected State

**Description**: Ensure all context injection gracefully handles Hivemind being unavailable or symlink broken.

**Acceptance Criteria**:
- [ ] Check `.hivemind/` symlink exists and is valid before queries
- [ ] If broken/missing, show warning: "Hivemind disconnected, proceeding without org context"
- [ ] Context injection returns empty results (not error)
- [ ] Phase continues normally without blocking
- [ ] Suggest running `/setup` to reconnect

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S2-T3

**Validation**: Remove `.hivemind/` symlink, run `/plan-and-analyze`, verify warning shown and phase completes.

---

#### S2-T5: Add Mode Confirmation Gate

**Description**: Implement mode mismatch detection and confirmation prompt when phase requires different mode than current.

**Acceptance Criteria**:
- [ ] On phase start, read `.claude/.mode` for current mode
- [ ] Determine required mode based on phase (per SDD section 3.2.2):
  - PRD, Architecture, Sprint, Implement: Use project type setting
  - Review, Audit, Deploy: Always Secure
- [ ] If mismatch detected, prompt user:
  ```
  Mode mismatch detected.
  Current: Creative | Phase requires: Secure
  Switch to Secure mode? [Yes] [Stay in Creative]
  ```
- [ ] If confirmed, update `.claude/.mode` with switch record
- [ ] If declined, proceed with warning

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S1-T3 (mode file exists)

**Validation**: In Creative mode, run `/review-sprint`, verify confirmation prompt appears.

---

### Sprint 2 Success Criteria

| Metric | Target |
|--------|--------|
| Context injection works | ADRs surfaced in PRD phase |
| Parallel agents spawn | 3 research agents run |
| Fallback handles disconnection | Warning shown, phase continues |
| Mode confirmation gates | Prompt on mismatch |

---

## Sprint 3: Candidate Surfacing

**Goal**: Implement automatic detection and surfacing of ADR/Learning candidates to Linear.

**Duration**: 2.5 days

### Tasks

#### S3-T1: Create Candidate Surfacer Library

**Description**: Create `.claude/lib/candidate-surfacer.md` documenting patterns for detecting ADR and Learning candidates from agent output.

**Acceptance Criteria**:
- [ ] Document ADR candidate patterns:
  - "We decided to use X instead of Y"
  - "Choosing X over Y because Z"
  - Trade-off discussions in architecture
- [ ] Document Learning candidate patterns:
  - "We discovered that X works better"
  - "This pattern proved more effective"
  - Implementation insights in reviews
- [ ] Define extraction format: decision, alternatives, rationale, trade-offs
- [ ] Define batch collection approach (accumulate during phase)

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: None

**Validation**: Document complete with clear patterns and examples.

---

#### S3-T2: Implement ADR Candidate Detection

**Description**: Add logic to detect architectural decisions during `/architect` phase and collect them for surfacing.

**Acceptance Criteria**:
- [ ] Scan SDD output for decision patterns
- [ ] Extract: decision statement, alternatives, rationale, trade-offs
- [ ] Store candidates in memory during phase
- [ ] Handle multiple candidates per phase
- [ ] Ignore false positives (minor choices, obvious defaults)

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S3-T1 (patterns defined)

**Validation**: Run `/architect`, make decisions, verify candidates detected.

---

#### S3-T3: Implement Learning Candidate Detection

**Description**: Add logic to detect proven patterns during `/implement` and `/review-sprint` phases.

**Acceptance Criteria**:
- [ ] Scan implementation reports and review feedback for patterns
- [ ] Extract: pattern description, context, evidence (file refs)
- [ ] Store candidates in memory during phase
- [ ] Link to relevant code/tests when possible

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S3-T1 (patterns defined)

**Validation**: Complete implementation with insights, verify Learning candidates detected.

---

#### S3-T4: Implement Batch Review UX

**Description**: At end of phase, show summary of detected candidates and prompt user for submission decision.

**Acceptance Criteria**:
- [ ] After phase completion, display candidate summary:
  ```
  Candidates Detected:
  - 2 ADR candidates
  - 1 Learning candidate

  Submit to Linear? [Submit all] [Review first] [Skip]
  ```
- [ ] If "Review first", show each candidate with option to include/exclude
- [ ] If "Skip", candidates discarded (not persisted)
- [ ] Non-blocking: phase is already complete before this prompt

**Effort**: Medium (3-4 hours)

**Assigned To**: Soju

**Dependencies**: S3-T2, S3-T3

**Validation**: Complete architecture phase with decisions, verify prompt appears with correct count.

---

#### S3-T5: Implement Linear Issue Creation

**Description**: Create Linear issues for approved candidates using MCP, with proper templates and labels.

**Acceptance Criteria**:
- [ ] Use Linear MCP to create issues
- [ ] ADR Candidate template (from SDD section 3.4.3):
  - Title: `[ADR-Candidate] {decision summary}`
  - Labels: `adr-candidate`, `sprint:{current}`
  - Body: Decision, Context, Alternatives, Rationale, Trade-offs, References
- [ ] Learning Candidate template:
  - Title: `[Learning-Candidate] {pattern summary}`
  - Labels: `learning-candidate`, `sprint:{current}`
  - Body: Pattern, Context, Evidence, Recommended Application
- [ ] Use Product Home project ID from `integration-context.md` (if set)
- [ ] Handle Linear unavailable: save to `loa-grimoire/pending-candidates.json`

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S3-T4, Linear MCP configured

**Validation**: Submit candidates, verify Linear issues created with correct format.

---

#### S3-T6: Extend `/architect` Command with Surfacing

**Description**: Integrate candidate detection and surfacing into the architecture phase completion flow.

**Acceptance Criteria**:
- [ ] After SDD written, run ADR candidate detection
- [ ] Show batch review prompt
- [ ] If approved, create Linear issues
- [ ] Log surfacing results to analytics
- [ ] Continue to next phase (non-blocking)

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S3-T2, S3-T4, S3-T5

**Validation**: Complete `/architect`, verify surfacing flow runs after SDD.

---

### Sprint 3 Success Criteria

| Metric | Target |
|--------|--------|
| ADR candidates detected | Decisions in SDD found |
| Learning candidates detected | Patterns in reviews found |
| Batch review works | Summary shown, user can approve |
| Linear issues created | With correct templates/labels |
| Fallback works | Pending file created if Linear unavailable |

---

## Sprint 4: Polish & Pilot

**Goal**: Add P1 features (Product Home, Experiment linking), polish UX, and complete pilot run with CubQuests + Set & Forgetti.

**Duration**: 2.5 days

### Tasks

#### S4-T1: Implement Product Home Linking

**Description**: Extend `/setup` to optionally link or create a Linear Product Home project.

**Acceptance Criteria**:
- [ ] Add "Link Product Home" checkbox to setup
- [ ] Options: "Create new" | "Link existing" | "Skip"
- [ ] If create: Use Product Home template (if available) or create blank project
- [ ] If link: Prompt for project ID or issue URL, extract project ID
- [ ] Store Product Home project ID in `integration-context.md`
- [ ] Candidates use this project ID for issue creation

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: Sprint 3 complete (candidate surfacing uses project ID)

**Validation**: Run `/setup`, link existing project, verify ID stored and used for candidates.

---

#### S4-T2: Implement Experiment Linking

**Description**: Extend `/setup` to optionally link a Hivemind experiment from Linear.

**Acceptance Criteria**:
- [ ] Add "Link Experiment" checkbox to setup
- [ ] Prompt for Linear issue URL
- [ ] Fetch experiment details via Linear MCP: hypothesis, success criteria
- [ ] Store experiment ID and details in `integration-context.md`
- [ ] Experiment context injected during PRD phase

**Effort**: Medium (4-5 hours)

**Assigned To**: Soju

**Dependencies**: S4-T1 (setup flow), S2-T3 (context injection)

**Validation**: Link experiment, run `/plan-and-analyze`, verify hypothesis referenced.

---

#### S4-T3: Add Mode Switch Analytics

**Description**: Log mode switches to `loa-grimoire/analytics/usage.json` for tracking.

**Acceptance Criteria**:
- [ ] On mode switch, record to analytics:
  - `mode_switches[]`: from, to, reason, phase, timestamp
- [ ] Update summary.md to show mode switch count
- [ ] Non-blocking: analytics failures don't affect mode switching

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S2-T5 (mode confirmation)

**Validation**: Switch modes, verify recorded in usage.json.

---

#### S4-T4: Polish Setup UX

**Description**: Improve the setup experience with better messaging, progress indicators, and summary.

**Acceptance Criteria**:
- [ ] Clear section headers for each setup phase
- [ ] Helpful descriptions for each option explaining benefits
- [ ] Progress indication (Phase 1/6, 2/6, etc.)
- [ ] Final summary showing all configured settings:
  ```
  Setup Complete!

  Hivemind: Connected (../hivemind-library)
  Project Type: game-design
  Mode: Creative
  Skills: 4 loaded
  Product Home: CubQuests (linked)
  Experiment: LAB-123 (linked)

  Next: Run /plan-and-analyze to start
  ```

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S4-T1, S4-T2

**Validation**: Run full `/setup`, verify clear UX and summary.

---

#### S4-T5: Pilot Run - CubQuests + Set & Forgetti

**Description**: Execute full Loa cycle for the pilot experiment: CubQuests quest design integrating Set & Forgetti v2.

**Acceptance Criteria**:
- [ ] Run `/setup` with:
  - Hivemind connected
  - Project type: `game-design` (or `cross-domain`)
  - Product Home linked
  - Experiment linked (if exists in Linear)
- [ ] Run `/plan-and-analyze`:
  - Verify Hivemind context injected (ADRs referenced)
  - Complete PRD for quest integration
- [ ] Run `/architect`:
  - Design quest flow architecture
  - Verify ADR candidates surfaced
- [ ] Run `/sprint-plan`:
  - Break down implementation tasks
- [ ] Run at least 1 sprint cycle:
  - `/implement sprint-1`
  - `/review-sprint sprint-1`
  - Verify Learning candidates surfaced
- [ ] Document any gaps or issues in `loa-grimoire/notepad.md`

**Effort**: Large (8-10 hours across pilot execution)

**Assigned To**: Soju

**Dependencies**: All previous tasks

**Validation**: Full cycle completes, candidates in Linear, no blocking issues.

---

#### S4-T6: Pilot Retrospective & Documentation

**Description**: Document lessons learned from pilot, update notepad, and capture any Gap candidates.

**Acceptance Criteria**:
- [ ] Review pilot execution for friction points
- [ ] Update `loa-grimoire/notepad.md` with:
  - What worked well
  - What needs improvement
  - Gap candidates (education skill? brand versioning?)
- [ ] Create Learning candidates for discovered patterns
- [ ] Update CLAUDE.md if any command behavior changed

**Effort**: Small (2-3 hours)

**Assigned To**: Soju

**Dependencies**: S4-T5 (pilot complete)

**Validation**: Notepad updated with actionable insights.

---

### Sprint 4 Success Criteria

| Metric | Target |
|--------|--------|
| Product Home linking works | Project ID stored, used for candidates |
| Experiment linking works | Hypothesis injected in PRD |
| Mode analytics tracked | Switches recorded |
| Setup UX polished | Clear flow, helpful summary |
| Pilot complete | Full cycle run for CubQuests + S&F |
| Lessons captured | Notepad updated, candidates surfaced |

---

## Dependencies Graph

```
Sprint 1
├── S1-T1: Hivemind Connection
│   └── S1-T2: Project Type Selection
│       └── S1-T3: Mode State Management
│       └── S1-T4: Skill Symlinks
│           └── S1-T5: Skill Validation

Sprint 2 (depends on Sprint 1)
├── S2-T1: Context Injector Library
│   └── S2-T2: Keyword Extraction
│       └── S2-T3: PRD Context Injection
│           └── S2-T4: Graceful Fallback
├── S2-T5: Mode Confirmation (depends on S1-T3)

Sprint 3 (parallel to Sprint 2 mostly)
├── S3-T1: Candidate Surfacer Library
│   ├── S3-T2: ADR Detection
│   └── S3-T3: Learning Detection
│       └── S3-T4: Batch Review UX
│           └── S3-T5: Linear Issue Creation
│               └── S3-T6: Architect Integration

Sprint 4 (depends on Sprint 3)
├── S4-T1: Product Home Linking
│   └── S4-T2: Experiment Linking
├── S4-T3: Mode Analytics
├── S4-T4: Setup UX Polish
└── S4-T5: Pilot Run
    └── S4-T6: Retrospective
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Hivemind skills incompatible with Loa | Low | High | Validate symlinks work in Sprint 1 |
| Linear MCP issues | Medium | Medium | Implement fallback to local file early |
| Parallel agent spawning complexity | Medium | Medium | Start simple, add agents incrementally |
| Pilot scope creep | Medium | Low | Stay focused on integration, not quest content |
| Mode confirmation too frequent | Low | Low | Only trigger on actual mismatches |

---

## Success Metrics (Overall)

| Metric | Target | Validation |
|--------|--------|------------|
| Hivemind context in PRD | ADRs referenced | Check prd.md for citations |
| Mode switching works | Confirmation on mismatch | Switch from Creative to Secure |
| ADR candidates surfaced | 2+ from architecture | Linear issues exist |
| Learning candidates surfaced | 1+ from implementation | Linear issues exist |
| Pilot completes | Full cycle executed | Sprint reports in a2a/ |
| No blocking failures | Graceful degradation | Disconnect Hivemind, verify continues |

---

*Sprint plan generated by Sprint Planner Agent*
*Ready for implementation: Run `/implement sprint-1` to begin*
