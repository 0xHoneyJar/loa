# Issue #242: AWS AI-DLC Comparative Analysis

> **Issue**: [FEATURE] review aws kiro harness implementation
> **Branch**: `research/issue-242-mount-integrity`
> **Date**: 2026-02-08
> **Sources**: GitHub repo, AWS re:Invent 2025 talk, AI-DLC Handbook, community analysis

---

## 1. What is AI-DLC?

AI-DLC (AI-Driven Development Life Cycle) is a **methodology** invented and open-sourced by AWS in 2025. It replaces traditional SDLC by placing AI at the center of every development phase while humans "shape direction, review outcomes, and guide quality."

**Key distinction**: AI-DLC is a *methodology*, not a *tool*. The open-source implementation (`awslabs/aidlc-workflows`) consists entirely of **Markdown rule files** — zero executable code. These files are injected into the AI agent's context window as "steering rules."

### Terminology Shifts

| Traditional | AI-DLC |
|-------------|--------|
| Sprints (2 weeks) | **Bolts** (hours/days) |
| Epics | **Units of Work** |
| Retrospectives | Continuous measurement |
| Sequential handoffs | **Mob Elaboration** (cross-functional, compressed) |

---

## 2. Architecture: Pure Declarative Rules

### Repository Structure (`awslabs/aidlc-workflows`)

```
aws-aidlc-rules/
  core-workflow.md              # ~510 lines, the entire orchestration
  common/                       # Cross-cutting rules
    error-handling.md
    overconfidence-prevention.md
    workflow-changes.md
    human-in-the-loop.md
  inception/                    # Phase 1 stages
    workspace-detection.md
    reverse-engineering.md
    requirements-analysis.md
    user-stories.md
    workflow-planning.md
    application-design.md
    units-generation.md
  construction/                 # Phase 2 stages
    functional-design.md
    nfr-requirements.md
    nfr-design.md
    infrastructure-design.md
    code-generation.md
    build-and-test.md
  operations/                   # Phase 3 (placeholder only)

aws-aidlc-rule-details/         # Extended detail files
  (mirrors above structure)
```

### Five Tenets

1. **No duplication** — Single source of truth
2. **Methodology first** — No installation required
3. **Reproducible** — Clear enough for consistent outputs across models
4. **Agnostic** — Works with Kiro, Amazon Q, Claude, any agent
5. **Human in the loop** — Critical decisions require explicit confirmation

---

## 3. Three-Phase Lifecycle

### Phase 1: INCEPTION (Planning & Architecture)

| Stage | Type | Purpose |
|-------|------|---------|
| Workspace Detection | ALWAYS | Greenfield vs brownfield, creates `aidlc-state.md` |
| Reverse Engineering | CONDITIONAL (brownfield) | 8 analysis artifacts: business overview, architecture, code structure, APIs, components, tech stack, dependencies, quality |
| Requirements Analysis | ALWAYS (adaptive depth) | Intent analysis, completeness, generates structured questions |
| User Stories | CONDITIONAL | Planning + Generation with INVEST criteria |
| Workflow Planning | ALWAYS | Stage execution plan with Mermaid visualization |
| Application Design | CONDITIONAL | Components, services, methods, dependencies |
| Units Generation | CONDITIONAL | System decomposition into deployable units |

### Phase 2: CONSTRUCTION (Design, Implementation & Test)

**Per-Unit Loop** — for each unit of work:

| Stage | Type | Purpose |
|-------|------|---------|
| Functional Design | CONDITIONAL | Business logic, domain models, rules |
| NFR Requirements | CONDITIONAL | Non-functional requirements, tech stack |
| NFR Design | CONDITIONAL | NFR patterns, logical components |
| Infrastructure Design | CONDITIONAL | Cloud/infra service mapping |
| Code Generation | ALWAYS | Two-part: Planning then Generation |

**After all units:**

| Stage | Type | Purpose |
|-------|------|---------|
| Build & Test | ALWAYS | Build instructions + test execution (unit, integration, perf, contract, security, e2e) |

### Phase 3: OPERATIONS (Deployment & Monitoring)

Currently **empty placeholder**. All build/test moved to Construction.

### Adaptive Depth

- Stage selection is binary (EXECUTE or SKIP)
- Detail level adapts: minimal / standard / comprehensive
- Based on: request clarity, complexity, scope, risk, available context, user preferences

---

## 4. Distinctive Design Patterns

### File-Based Question System

Questions are **never asked in chat** — they go to dedicated markdown files:

```markdown
## Question 1: Authentication Strategy
What authentication approach should we use?

A) OAuth2 with JWT tokens
B) Session-based authentication
C) API key authentication
D) Certificate-based authentication
E) Other (please specify)

[Answer]:
```

**Purpose**: Creates audit trail, enables team collaboration, constrains AI behavior, machine-parseable.

### Anti-Overconfidence Measures

Dedicated `overconfidence-prevention.md` evolved from observed AI behavior — changed from "only ask if necessary" to "when in doubt, ask the question."

### Emergent Behavior Suppression

> "NO EMERGENT BEHAVIOR: Construction phases MUST use standardized 2-option completion messages. DO NOT create 3-option menus or other emergent navigation patterns."

### State Management

- `aidlc-docs/aidlc-state.md` — Checkbox-based workflow progress
- `aidlc-docs/audit.md` — Verbatim user inputs with ISO 8601 timestamps
- Session continuity via artifact loading on return

---

## 5. Core Methodology: Plan-Verify-Generate

From re:Invent 2025 (Anupam Mishra, Raja):

1. **AI creates a plan** → Human validates and corrects → AI refines and executes → Human verifies
2. **Mob Elaboration**: Cross-functional teams (PM, dev, QA, ops) work in compressed timeframes (4 hours / half-day)
3. **Compressed Sprints ("Bolts")**: Hour-long or sub-day cycles, not 2-week sprints

### Two Anti-Patterns Identified

| Anti-Pattern | Problem |
|--------------|---------|
| **AI-Managed** | Expect AI to build everything autonomously → ambiguity, unfounded assumptions, no confidence |
| **AI-Assisted** | Narrow AI to specific tasks → humans still do heavy lifting, pre-AI meetings waste saved time |

### Best Practices

- **Code Understanding**: Developers must understand every line of AI-generated code
- **Task Decomposition**: Narrow, non-ambiguous tasks, not broad requests
- **Context Window Management**: More context ≠ better results; manage carefully
- **Reference-Based Generation**: Point AI to existing patterns, not verbal descriptions
- **Semantics-Per-Token Ratio**: "Refactor using builder pattern" > verbose descriptions
- **Contiguous Work Blocks**: Uninterrupted time for flow state + context continuity

### Customer Results

- **Wipro**: Months of planned work → 20 hours across 5 days (enterprise healthcare)
- **Dhan**: 2-month project → 48 hours (stock trading fintech)
- **General**: 10-15x productivity gains across regions/industries

---

## 6. Comparative Analysis: AI-DLC vs Loa

### Architectural Paradigm

| Dimension | AI-DLC | Loa |
|-----------|--------|-----|
| **Nature** | Methodology (pure Markdown) | Framework (scripts + protocols + skills) |
| **Code** | Zero executable code | 150+ shell scripts, TypeScript libs, JSON schemas |
| **Enforcement** | Advisory (AI reads and follows rules) | Mandatory (scripts validate, hooks enforce) |
| **Installation** | Copy 2 directories | `/mount` command with integrity verification |

### Lifecycle Comparison

| AI-DLC Phase | Loa Equivalent | Notes |
|--------------|----------------|-------|
| Workspace Detection | `/ride` (codebase riding) | Both detect greenfield/brownfield |
| Reverse Engineering | `/ride` reality extraction | Loa generates `index.md` + spoke files |
| Requirements Analysis | `/plan-and-analyze` → PRD | Both do adaptive depth, context-first |
| User Stories | PRD functional requirements | Loa uses acceptance criteria in sprint plan |
| Workflow Planning | `/sprint-plan` | Loa auto-registers in Sprint Ledger |
| Application Design | `/architect` → SDD | Loa generates full system design document |
| Units Generation | Sprint task decomposition | AI-DLC units ≈ Loa sprint tasks |
| Functional Design | Part of SDD | Loa bundles into architecture phase |
| NFR Requirements | Part of SDD | Same |
| NFR Design | Part of SDD | Same |
| Infrastructure Design | `/deploy-production` | Loa defers infra to deployment phase |
| Code Generation | `/implement sprint-N` | Loa has review+audit cycle after |
| Build & Test | Part of `/implement` | Loa runs tests during implementation |
| **— (missing)** | `/review-sprint` | **AI-DLC has no code review stage** |
| **— (missing)** | `/audit-sprint` | **AI-DLC has no security audit stage** |
| Operations (empty) | `/deploy-production` + `/ship` | Loa has full deployment pipeline |

### Safety & Quality

| Aspect | AI-DLC | Loa |
|--------|--------|-----|
| **Quality gates** | Human approval per stage | Review → Audit → Circuit breaker |
| **Code review** | None (human reviews in chat) | Structured `/review-sprint` with criteria |
| **Security audit** | None | `/audit-sprint` with OWASP coverage |
| **Multi-model review** | None | Flatline Protocol (Opus + GPT adversarial) |
| **Danger levels** | None | 4-tier: safe/moderate/high/critical |
| **Input guardrails** | None | PII filter, injection detection |
| **Constraint enforcement** | Prose instructions | 30+ coded constraints with error codes |

### Autonomous Execution

| Aspect | AI-DLC | Loa |
|--------|--------|-----|
| **Autonomous mode** | Not supported | `/run sprint-N` with circuit breaker |
| **Overnight execution** | Not possible | Designed for it (compact hooks, state recovery) |
| **Error recovery** | Manual (human reviews audit.md) | Automatic (WAL, checkpoints, hook recovery) |
| **Session continuity** | Artifact loading on return | Pre/post-compact hooks, state files |

### Memory & Learning

| Aspect | AI-DLC | Loa |
|--------|--------|-----|
| **Cross-session memory** | None (session-limited) | Persistent observations (JSONL) |
| **Learning capture** | None | Invisible retrospective with quality gates |
| **Prompt improvement** | None | Invisible enhancement (PTCF framework) |
| **Knowledge retrieval** | None | Progressive disclosure memory queries |

### Task Tracking

| Aspect | AI-DLC | Loa |
|--------|--------|-----|
| **Primary tracking** | Markdown checkboxes | Beads (beads_rust external tool) |
| **Session display** | State file parsing | Claude TaskCreate/TaskUpdate |
| **Cross-session** | `aidlc-state.md` | `.beads/issues.jsonl` + Sprint Ledger |
| **Autonomous requirement** | N/A | Beads required for `/run` mode |

### Platform & Integration

| Aspect | AI-DLC | Loa |
|--------|--------|-----|
| **Platform** | Any AI agent (Kiro, Q, Claude, etc.) | Claude Code specific |
| **Configuration** | None (edit rules directly) | `.loa.config.yaml` (100+ params) |
| **Extensibility** | Fork and modify Markdown | Skill system with auto-loading SKILL.md |
| **External tools** | None | Beads, GPT API, NotebookLM |

---

## 7. What Loa Could Learn / Adopt / Experiment With

### High-Value Adoptions

#### 7.1 File-Based Question System
**What**: Questions as structured markdown files with multiple-choice options, not chat.
**Why**: Creates audit trail, enables async team collaboration, constrains AI hallucination.
**Loa adaptation**: Could enhance `/plan-and-analyze` discovery phases with file-based questions in `grimoires/loa/context/questions/`. Team members could answer asynchronously.

#### 7.2 Overconfidence Prevention Pattern
**What**: Explicit documentation of observed AI overconfidence behavior and countermeasures.
**Why**: AI-DLC discovered that "only ask if necessary" leads to skipped questions. Changed to "when in doubt, ask."
**Loa adaptation**: Add overconfidence prevention rules to implementation compliance protocol. Document observed failure modes and their fixes.

#### 7.3 Emergent Behavior Suppression
**What**: Explicit rules preventing AI from improvising interaction patterns.
**Why**: Without explicit constraints, AI agents create ad-hoc menus, invent workflows, deviate from prescribed patterns.
**Loa adaptation**: Skills could include `<emergent_behavior_constraints>` sections listing what the AI must NOT invent.

#### 7.4 Semantics-Per-Token Ratio Concept
**What**: Compress semantic meaning in prompts. "Refactor using builder pattern" > verbose descriptions.
**Why**: Context window management directly affects output quality.
**Loa adaptation**: Enhance the PTCF prompt enhancement framework to optimize for semantic density, not just completeness.

#### 7.5 Mob Elaboration Pattern
**What**: Cross-functional compressed sessions (4h) replacing multi-week requirement cycles.
**Why**: Eliminates dependency bottlenecks, creates rich shared context.
**Loa adaptation**: Could inform a new `/mob` or `/workshop` skill for compressed discovery with multiple stakeholders.

### Medium-Value Experiments

#### 7.6 Adaptive Stage Depth Model
**What**: ALWAYS-EXECUTE vs CONDITIONAL stages with minimal/standard/comprehensive depth.
**Why**: Simple bug fixes shouldn't go through full planning cycles.
**Loa adaptation**: `/build` golden path already auto-detects sprint, but could add adaptive depth to `/plan-and-analyze` — skip phases based on scope.

#### 7.7 Per-Unit Loop Architecture
**What**: Construction loops through each unit independently before integration.
**Why**: Natural fit for microservices; each unit gets full design treatment.
**Loa adaptation**: Sprint tasks are already per-unit, but could formalize the loop pattern for multi-service architectures.

#### 7.8 Brownfield Reverse Engineering Artifacts
**What**: AI-DLC generates 8 structured artifacts from existing codebases: business overview, architecture, code structure, APIs, components, tech stack, dependencies, quality.
**Why**: Comprehensive brownfield onboarding.
**Loa adaptation**: `/ride` already generates reality files, but the 8-artifact structure is more granular. Could extend reality spoke files to cover business overview and quality assessment.

### Low-Value / Already Covered

#### 7.9 Platform Agnosticism
AI-DLC's zero-code approach enables any-agent support. Loa's enforcement model is fundamentally Claude Code-specific. The tradeoff is intentional — Loa chooses enforcement power over portability. Not recommended to change.

#### 7.10 Waterfall-First Planning
AI-DLC's extensive upfront planning (7 inception stages + 4 construction design stages before code) is heavy for most projects. Loa's sprint-based approach is more appropriate for iterative development.

---

## 8. Key Insights from Customer Results

### What Works at Scale
- **10-15x productivity gains** reported across industries (Wipro, Dhan, S&P Global)
- **Months → Hours** compression is real but requires: mature CI/CD, working dev environments, contiguous work blocks
- **Context window management** is the #1 practical concern (more context ≠ better)
- **Model training awareness** matters: forcing unfamiliar patterns produces poor results

### What Doesn't Work
- **AI-Managed anti-pattern**: Full autonomy without structure fails
- **AI-Assisted anti-pattern**: Narrow AI role wastes potential
- **Audit.md scaling**: File-based state grows unbounded (issue #26 — hangs on edit)
- **AI overconfidence**: Models skip questions, claim completion prematurely (issues #38, #64)
- **No code review**: Direct code-gen → build without review is a gap

### Measurement Framework
Traditional metrics fail for AI-driven development. Recommended:
- Baseline: time from business decision → production launch
- Compare: AI-enabled vs traditional
- Track: velocity, quality, predictability (20% → 80%+ sprint fulfillment)

---

## 9. Community Signals

The `awslabs/aidlc-workflows` repo (378 stars, 76 forks) has active community engagement:

- **Issue #50**: Community member created Claude Code SKILL.md files for AI-DLC (bridge to our world)
- **Issue #60**: No public roadmap yet, community requesting visibility
- **Issue #38**: AI claims stage completion when incomplete (enforcement gap)
- **Issue #55**: Audit timestamp inaccuracy (state management fragility)
- **Issue #26**: `audit.md` hangs as it grows (scaling limitation)

The **AI-DLC Handbook** by AWS Hero Bhuvaneswari Subramani provides 5h theory + 15h labs.

**Kiro** (AWS's agentic IDE) is the primary implementation vehicle, using `.kiro/steering/` for rule files.

---

## 10. Summary Assessment

### AI-DLC's Greatest Strength
**Radical simplicity** — copy Markdown files, works with any agent. Zero barrier to entry. The methodology-first philosophy means teams get structure without tooling overhead.

### AI-DLC's Greatest Weakness
**Cannot enforce its own rules** — relies entirely on AI faithfully following prose instructions. No scripts, no validation, no circuit breakers. Open issues confirm enforcement gaps.

### The Core Tradeoff
> AI-DLC tells the AI "here are the rules, follow them."
> Loa gives the AI "here are the tools, invoke them."

AI-DLC is platform-agnostic but inherently limited in enforcement.
Loa is Claude Code-specific but can enforce contracts through code, scripts, hooks, and external tools.

### Recommendation
Loa should adopt AI-DLC's best *ideas* (file-based questions, overconfidence prevention, emergent behavior suppression, semantic density) without adopting its *architecture* (pure Markdown, no enforcement). The enforcement model is Loa's competitive advantage.

---

## Sources

- [awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows) — Open-source workflow rules
- [AWS DevOps Blog: AI-Driven Development Life Cycle](https://aws.amazon.com/blogs/devops/ai-driven-development-life-cycle/) — Methodology announcement
- [AWS DevOps Blog: Open-Sourcing Adaptive Workflows](https://aws.amazon.com/blogs/devops/open-sourcing-adaptive-workflows-for-ai-driven-development-life-cycle-ai-dlc/) — Workflow release
- [AWS DevOps Blog: Building with AI-DLC using Amazon Q Developer](https://aws.amazon.com/blogs/devops/building-with-ai-dlc-using-amazon-q-developer/) — Practical guide
- [AWS re:Invent 2025 DVT214 Summary](https://dev.to/kazuya_dev/aws-reinvent-2025-introducing-ai-driven-development-lifecycle-ai-dlc-dvt214-32b) — Conference talk
- [The AI-DLC Handbook](https://aidlcbook.com/) — Practical guide by AWS Hero
- [aws-samples/sample-aidlc-kiro-power](https://github.com/aws-samples/sample-aidlc-kiro-power) — Kiro implementation
- [About Amazon India: AI-DLC Announcement](https://www.aboutamazon.in/news/aws/aws-launches-new-ai-methodology-devsphere) — DevSphere 2025 coverage
- [YourStory: DevSparks Coverage](https://yourstory.com/2025/09/devsparks-hyderabad-2025-aws-unveils-ai-driven-development-lifecycle) — Industry analysis
