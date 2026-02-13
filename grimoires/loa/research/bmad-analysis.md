# BMAD-METHOD Analysis: Skills Portable to Loa

**Issue**: [#246](https://github.com/0xHoneyJar/loa/issues/246)
**Branch**: `research/bmad-analysis`
**Date**: 2026-02-08
**Status**: Research Complete

---

## Executive Summary

BMAD (Breakthrough Method of Agile AI-Driven Development) is an MIT-licensed, IDE-agnostic AI development framework at v6.0.0-Beta.7. It shares significant philosophical overlap with Loa (progressive context building, structured SDLC phases, quality gates) but differs in execution model and several unique capabilities.

**Bottom line**: 5 capabilities are worth porting to Loa or loa-constructs. 3 are novel enough to be high-priority. The rest overlaps with what Loa already does, often better.

---

## 1. System Comparison

### Shared Philosophy

| Principle | Loa | BMAD |
|-----------|-----|------|
| Progressive context building | PRD -> SDD -> Sprint -> Code | Brief -> PRD -> Architecture -> Epics -> Stories |
| Quality gates | Review -> Audit -> COMPLETED | Adversarial Review + Code Review checklist |
| Phase-based SDLC | 6 phases (plan -> deploy) | 4 phases (analysis -> implementation) |
| Multi-model review | Flatline Protocol (Opus + GPT) | Adversarial Review (different LLM recommended) |
| Structured artifacts | grimoires/loa/*.md | Implementation artifacts folder |
| Agent personas | Named agents (reviewer, auditor) | Named agents (Mary, John, Winston, etc.) |

### Key Architectural Differences

| Aspect | Loa | BMAD |
|--------|-----|------|
| **Runtime** | Claude Code native (bash + skills) | IDE-agnostic CLI installer (npm) |
| **Context model** | Single long session with compaction recovery | Fresh chat per workflow (explicit context isolation) |
| **Automation** | Run Mode (overnight autonomous) | YOLO Mode (skip confirmations in single session) |
| **Task tracking** | beads_rust (graph DB) | sprint-status.yaml (flat YAML) |
| **Cross-model** | Flatline Protocol (structured scoring 0-1000) | Adversarial review (unstructured "find 10 issues") |
| **Extensibility** | Constructs packs (licensed marketplace) | Module system (open-source npm packages) |
| **IDE support** | Claude Code only | 10+ IDEs (Claude, Cursor, Windsurf, Kiro, etc.) |
| **Persona depth** | Role-based (auditor, reviewer) | Character-based (names, personalities, communication styles) |

---

## 2. Capability Gap Analysis

### Legend
- **PORT**: Worth porting to Loa/loa-constructs
- **SKIP**: Loa already covers this, or not valuable
- **ADAPT**: Core idea valuable, needs significant adaptation

---

### 2.1 UX Design Workflow — PORT (High Priority)

**What BMAD has**: A 14-step guided UX design facilitation workflow (`create-ux-design`) producing a comprehensive UX design specification. Steps include:
1. Discovery and project understanding
2. Core experience definition (primary user action, platform strategy)
3. Emotional response design (how users should *feel*)
4. Design inspiration gathering
5. Design system foundations (typography, color, spacing)
6. Visual foundation
7. User journey mapping
8. Component strategy
9. Responsive design + accessibility
10. Final specification

Each step uses A/P/C menus (Advanced Elicitation / Party Mode / Continue) for iterative refinement.

**What Loa has**: Nothing. Loa goes PRD -> SDD -> Sprint with no UX design phase. The SDD covers technical architecture but not user experience design, interaction patterns, or visual foundations.

**Port recommendation**: Create a `/ux-design` skill for loa-constructs. Place it between `/plan-and-analyze` and `/architect` in the workflow. Focus on:
- Core experience definition (the "one thing" question)
- User journey mapping
- Component strategy
- Responsive + accessibility requirements
- Output: `grimoires/loa/ux-design.md`

**Effort**: Medium — new skill, ~500-700 lines of SKILL.md

---

### 2.2 Course Correction Workflow — PORT (High Priority)

**What BMAD has**: A structured 6-section checklist for navigating mid-sprint changes (`correct-course`):
1. **Trigger & Context**: Identify what caused the change, categorize it (technical limitation, new requirement, misunderstanding, strategic pivot, failed approach)
2. **Epic Impact Assessment**: Evaluate which epics/stories need modification, addition, removal, or resequencing
3. **Artifact Conflict Analysis**: Check PRD, Architecture, UX, deployment artifacts for conflicts
4. **Path Forward Evaluation**: Three options evaluated (Direct Adjustment, Rollback, MVP Review) with effort/risk ratings
5. **Sprint Change Proposal**: Structured proposal document
6. **Handoff Plan**: Define who executes what

**What Loa has**: Nothing explicit. When things go wrong mid-sprint, Loa relies on the engineer feedback loop (`/review-sprint` -> feedback -> `/implement` again) or the user manually intervening. There's no structured process for "we discovered the architecture is wrong" or "requirements changed."

**Port recommendation**: Create a `/correct-course` skill for loa-constructs. Should:
- Accept a trigger description (what went wrong / what changed)
- Automatically read PRD, SDD, sprint.md for conflict analysis
- Present 3 path-forward options with effort/risk matrix
- Generate a change proposal document
- Update sprint.md and beads if changes are approved
- Output: `grimoires/loa/a2a/{sprint-id}/course-correction.md`

**Effort**: Medium — new skill, ~400-600 lines

---

### 2.3 QA Test Generation Workflow — PORT (High Priority)

**What BMAD has**: A focused QA automation workflow (`qa-automate`) that:
1. Detects existing test framework from package.json/project config
2. Asks user what to test (feature, component, directory)
3. Generates API tests (status codes, response structure, happy path + errors)
4. Generates E2E tests (user workflows, semantic locators, assertions)
5. Runs tests to verify they pass
6. Creates coverage summary

Simple and practical. The checklist is lightweight (~15 items). They also have a premium "Test Architect (TEA)" module for enterprise needs.

**What Loa has**: The `/implement` skill writes tests as part of implementation, and `/audit-sprint` checks test coverage. But there's no standalone "generate tests for existing code" capability. If you have a codebase with poor test coverage, there's no Loa skill to backfill tests.

**Port recommendation**: Create a `/qa-automate` or `/test-gen` skill for loa-constructs. Should:
- Auto-detect test framework
- Accept target (file, directory, feature name)
- Generate both unit and integration tests
- Run them and fix failures
- Output test summary
- Integrate with `/audit-sprint` (auditor can recommend running this)

**Effort**: Medium — new skill, ~300-500 lines

---

### 2.4 Implementation Readiness Gate — ADAPT (Medium Priority)

**What BMAD has**: A formal `check-implementation-readiness` workflow that runs BEFORE implementation begins. It validates:
1. All required documents exist (PRD, Architecture, Epics)
2. PRD analysis complete (requirements traceable)
3. Epic coverage (all PRD requirements mapped to epics)
4. UX alignment (if UX spec exists)
5. Epic quality (acceptance criteria clear, dependencies resolved)
6. Final assessment: PASS / CONCERNS / FAIL

**What Loa has**: `/implement` does preflight checks (PRD exists, SDD exists, sprint.md exists) but doesn't validate the *quality* of these documents or check for gaps in requirements coverage. The Flatline Protocol reviews individual documents but doesn't cross-check coverage between them.

**Port recommendation**: Add a readiness check to the existing `/sprint-plan` or `/implement` preflight. Not a standalone skill — integrate as a pre-implementation gate:
- Verify all sprint tasks map to PRD requirements
- Verify SDD covers the architecture needed for sprint tasks
- Check for ambiguous acceptance criteria
- Output: READY / CONCERNS (with list) / BLOCKED

**Effort**: Low-Medium — enhancement to existing skills

---

### 2.5 Adversarial Review (Forced Finding) — ADAPT (Low Priority)

**What BMAD has**: A review technique where the reviewer is instructed to be "a cynical, jaded reviewer" and MUST find at least 10 issues. If zero findings are reported, the review HALTs as suspicious. The key insight: forcing reviewers to find problems combats confirmation bias.

**What Loa has**: The `/review-sprint` and `/audit-sprint` already use adversarial framing (the auditor is a "Paranoid Cypherpunk"). The Flatline Protocol's skeptic personas serve a similar role. GPT review also forces finding issues.

**Port recommendation**: Consider adding a "minimum findings threshold" to `/review-sprint` and `/audit-sprint`. If a reviewer finds zero issues, flag it as suspicious and require a second pass. This is a small behavioral change, not a new skill.

**Effort**: Low — configuration/prompt change

---

### 2.6 Capabilities Loa Already Has (SKIP)

| BMAD Capability | Loa Equivalent | Notes |
|----------------|----------------|-------|
| **Product Brief / PRD creation** | `/plan-and-analyze` | Loa's context ingestion + 7-phase discovery is more thorough |
| **Architecture design** | `/architect` | Equivalent depth |
| **Sprint planning** | `/sprint-plan` | Loa adds beads_rust integration |
| **Story creation + dev execution** | `/implement` | Loa's implement reads sprint.md tasks directly |
| **Code review** | `/review-sprint` | Loa's review is comparable; BMAD's checklist is slightly more granular |
| **Multi-model review** | Flatline Protocol | Loa's structured scoring (0-1000) is more sophisticated than BMAD's unstructured adversarial |
| **Autonomous execution** | `/run sprint-plan` | Loa's Run Mode with circuit breakers is more mature |
| **Brownfield analysis** | `/ride` | Loa's reality extraction is more comprehensive |
| **Progressive context** | grimoires/loa/ state zone | Both do this well |
| **Market/Domain research** | Not in Loa | BMAD has this but it's generic "research X topic" — low value for a skill |
| **Document sharding** | Not needed | Loa manages context via compaction + memory hooks |
| **Party Mode** | Not in Loa | Multi-agent conversation — interesting but complex to implement in Claude Code's single-agent model |
| **YOLO Mode** | `/run` mode | Loa's autonomous execution is more structured |
| **Document Project** | `/ride` | Loa's `/ride` produces reality extraction; BMAD's is more documentation-focused |

---

## 3. BMAD Patterns Worth Studying

These aren't skills to port, but design patterns Loa could learn from:

### 3.1 Agent Personality Depth

BMAD agents have names, communication styles, and personalities (e.g., "Mary" the analyst is an "excited treasure hunter"). Loa agents are role-based ("the auditor", "the reviewer"). Neither approach is objectively better, but BMAD's named personas create more memorable and consistent agent behavior.

**Consideration**: Could Loa's skill agents benefit from named personas? The auditor could be "Cipher" the cypherpunk, the reviewer could be "Sterling" the senior lead. This is a cosmetic enhancement but may improve prompt adherence.

### 3.2 A/P/C Menu Pattern

BMAD's workflows offer three choices at each checkpoint:
- **A**dvanced Elicitation (go deeper)
- **P**arty Mode (get more perspectives)
- **C**ontinue (save and proceed)

This is a good UX pattern for HITL workflows. Loa's `/simstim` could adopt a similar branching pattern where each phase offers "Go Deeper / Get Perspectives / Continue."

### 3.3 Fresh Context Per Workflow

BMAD explicitly recommends starting a new chat for each workflow to avoid context pollution. Loa's approach of running in a single long session with compaction is different. Both have tradeoffs — BMAD loses cross-phase context, Loa risks context pollution. Worth noting but not actionable.

### 3.4 Scale-Domain Adaptiveness

BMAD's workflows automatically adjust depth based on project scale (quick flow for <15 stories, full method for 10-50+, enterprise for 30+). Loa doesn't have this — all projects go through the same workflow regardless of size. The Quick Flow concept (lightweight spec + dev for small tasks) could be valuable for small fixes that don't warrant full PRD/SDD/Sprint.

---

## 4. Recommended Actions

### Priority 1: High-Value Ports (loa-constructs)

| # | Skill | From BMAD | Target | Effort |
|---|-------|-----------|--------|--------|
| 1 | `/ux-design` | create-ux-design | loa-constructs pack | Medium |
| 2 | `/correct-course` | correct-course | loa-constructs pack | Medium |
| 3 | `/test-gen` | qa-automate | loa-constructs pack | Medium |

### Priority 2: Enhancements to Existing Skills

| # | Enhancement | From BMAD | Target | Effort |
|---|-------------|-----------|--------|--------|
| 4 | Readiness gate | check-implementation-readiness | `/sprint-plan` or `/implement` preflight | Low-Med |
| 5 | Min-findings threshold | adversarial review | `/review-sprint`, `/audit-sprint` | Low |

### Priority 3: Design Pattern Adoption

| # | Pattern | Application | Effort |
|---|---------|-------------|--------|
| 6 | Quick Flow track | Add lightweight mode for small tasks (<5 stories) | Medium |
| 7 | A/P/C branching | Enhance `/simstim` checkpoints | Low |

---

## 5. What NOT to Port

| BMAD Feature | Why Skip |
|-------------|----------|
| Named agent personas | Cosmetic; Loa's role-based approach works fine |
| Party Mode | Claude Code is single-agent; would require significant architecture change |
| Document sharding | Loa's compaction + memory hooks solve context limits differently |
| Market/Domain/Technical research | Too generic to be a useful standalone skill |
| Module system | Loa already has Constructs packs |
| IDE-agnostic installer | Loa is Claude Code native by design |
| YOLO Mode | Loa's `/run` mode is more sophisticated |
| Sprint-status.yaml | beads_rust is superior for task tracking |
| Editorial review (prose/structure) | Niche; not aligned with Loa's code-first focus |

---

## 6. Licensing

BMAD is **MIT licensed**. All code can be freely adapted, modified, and included in Loa or loa-constructs (including commercial distribution) with attribution. A simple credit line in the skill README suffices.

---

## Appendix A: BMAD Repository Structure

```
src/
  core/          - Engine (workflow executor, adversarial review, party mode)
  bmm/           - BMad Method module (9 agents, 20+ workflows)
    agents/      - Agent YAML definitions
    workflows/   - Organized by phase (1-analysis, 2-plan, 3-solutioning, 4-implementation)
    teams/       - Team compositions
  utility/       - Agent component templates
tools/
  cli/           - npx installer for 10+ IDEs
  schema/        - Agent YAML schema validator
```

## Appendix B: BMAD Agent Roster

| Agent | Name | Module | Role |
|-------|------|--------|------|
| Business Analyst | Mary | BMM | Strategic analysis, research, product briefs |
| Product Manager | John | BMM | PRD creation, epic management, course correction |
| Architect | Winston | BMM | System architecture, readiness checks |
| Scrum Master | Bob | BMM | Sprint planning, story prep, retrospectives |
| Developer | Amelia | BMM | Code implementation, code review |
| QA Engineer | Quinn | BMM | Test automation |
| Quick Flow Solo Dev | Barry | BMM | Lightweight spec + dev for small tasks |
| UX Designer | Sally | BMM | UX design facilitation |
| Technical Writer | Paige | BMM | Documentation, brownfield project docs |
| BMad Master | — | Core | Workflow orchestrator |

## Appendix C: BMAD Workflow-to-Loa Mapping

| BMAD Workflow | Loa Equivalent | Gap? |
|--------------|----------------|------|
| Brainstorm Project | — | Low value |
| Market/Domain/Technical Research | — | Low value |
| Create Product Brief | `/plan-and-analyze` (context phase) | No |
| Create PRD | `/plan-and-analyze` | No |
| Validate PRD | Flatline Protocol (PRD) | No |
| Create UX Design | **NONE** | **YES** |
| Create Architecture | `/architect` | No |
| Create Epics & Stories | `/sprint-plan` | No |
| Check Implementation Readiness | Partial (preflight only) | **Partial** |
| Sprint Planning | `/sprint-plan` | No |
| Create Story | `/implement` (reads sprint.md) | No |
| Dev Story | `/implement` | No |
| Code Review | `/review-sprint` | No |
| QA Automate | **NONE** | **YES** |
| Correct Course | **NONE** | **YES** |
| Retrospective | `/retrospective` | No |
| Quick Spec + Quick Dev | **NONE** (partial via ad-hoc work) | **Partial** |
| Document Project | `/ride` | No |
| Generate Project Context | `/reality` | No |
| Adversarial Review | Flatline Protocol | No |
| Party Mode | — | N/A (architecture mismatch) |
