# Kiro Analysis: Lessons for Loa

**Date**: 2026-01-12
**Branch**: `research/kiro-analysis`
**Status**: Research Complete

## Executive Summary

[Kiro](https://kiro.dev/) is AWS's agentic IDE released in public preview on July 14, 2025. It emphasizes **spec-driven development** over "vibe coding" - transforming informal requirements into structured specifications before implementation. This analysis identifies features potentially applicable to Loa.

---

## Kiro Overview

### Core Philosophy

> "Most tools are great at generating code, but Kiro gives structure to the chaos before you write a single line."

Kiro addresses the gap between prototype and production by requiring structured planning before implementation. This aligns closely with Loa's existing workflow philosophy.

### Three-Stage Workflow

| Stage | Output | Description |
|-------|--------|-------------|
| Requirements | `requirements.md` | User stories with EARS notation acceptance criteria |
| Design | `design.md` | Technical architecture and implementation approach |
| Tasks | `tasks.md` | Discrete, dependency-mapped implementation steps |

### Key Features

1. **Specs** - Structured requirements using EARS notation
2. **Agent Hooks** - Event-driven automations
3. **Steering Files** - Persistent project context
4. **Autopilot/Supervised Modes** - Autonomous vs approval-based execution
5. **MCP Integration** - Native Model Context Protocol support

---

## Feature Comparison

| Feature | Kiro | Loa | Gap Analysis |
|---------|------|-----|--------------|
| Structured requirements | EARS notation in `requirements.md` | PRD via `/plan-and-analyze` | Similar - Loa uses interview-based PRD |
| Technical design | `design.md` | SDD via `/architect` | Equivalent |
| Task breakdown | `tasks.md` with dependencies | `sprint.md` via `/sprint-plan` | Equivalent |
| Event-driven hooks | Agent hooks (file save, create, delete) | Claude Code hooks (limited) | **Gap** - Kiro has richer hook system |
| Persistent context | Steering files in `.kiro/steering/` | CLAUDE.md + skills + protocols | Similar - different organization |
| Autonomous execution | Autopilot mode | Background execution mode | Similar |
| Approval workflow | Supervised mode | Two quality gates (review + audit) | Loa is more rigorous |
| MCP support | Native | Native | Equivalent |
| Custom agents | JSON config in `.kiro/agents/` | Skills in `.claude/skills/` | Similar - different format |

---

## Applicable Lessons for Loa

### 1. EARS Notation for Requirements (HIGH VALUE)

**What Kiro Does**:
EARS (Easy Approach to Requirements Syntax) structures requirements to eliminate ambiguity:

```markdown
# EARS Format Examples

## Ubiquitous (always active)
"The system shall [action]"

## Event-Driven
"When [trigger], the system shall [action]"

## Conditional
"If [condition], the system shall [action]"

## State-Driven
"While [state], the system shall [action]"

## Optional
"Where [feature enabled], the system shall [action]"
```

**Applicability to Loa**:
- Could enhance PRD output quality
- Reduces AI misinterpretation of requirements
- Especially valuable for non-native English speakers
- Could be added to `discovering-requirements` skill as output format option

**Implementation Effort**: Low - Add EARS templates to PRD skill resources

---

### 2. Agent Hooks System (MEDIUM VALUE)

**What Kiro Does**:
Event-driven automations that trigger on file events:

```yaml
# Example hooks
- On file save: Update related tests
- On component create: Generate documentation stub
- On commit prep: Run security scan
- On API change: Refresh OpenAPI spec
```

**Applicability to Loa**:
- Claude Code already has hooks support
- Could document recommended hook patterns for Loa workflows
- Example: Auto-update NOTES.md on session end
- Example: Trigger grounding check before `/clear`

**Implementation Effort**: Low - Document patterns, users configure in Claude Code

---

### 3. Steering Files Organization (MEDIUM VALUE)

**What Kiro Does**:
`.kiro/steering/` with typed files:
- `product.md` - Purpose, users, features
- `tech.md` - Frameworks, libraries, constraints
- `structure.md` - Organization, naming, architecture

**Three inclusion modes**:
1. `always` - Every interaction
2. `fileMatch` - Conditional on file patterns
3. `manual` - On-demand via `#filename`

**Applicability to Loa**:
- Loa already has `CLAUDE.md`, skills, and protocols
- Could adopt the **conditional inclusion** pattern
- Useful for large projects where loading everything is wasteful
- Could inform skill loading optimization

**Implementation Effort**: Medium - Requires changes to skill loading system

---

### 4. Specs Synchronization (HIGH VALUE)

**What Kiro Does**:
Specs (requirements.md, design.md, tasks.md) stay synchronized with code. Developers can:
- Request spec updates when code changes
- Regenerate tasks from updated specs
- Detect drift between specs and implementation

**Applicability to Loa**:
- Loa has `/ride` for drift detection (code vs docs)
- Could enhance drift detection to be more granular
- Could add "spec refresh" capability to update PRD/SDD from code reality
- Addresses documentation rot problem

**Implementation Effort**: Medium - Enhance existing `/ride` capabilities

---

### 5. Task Dependency Mapping (MEDIUM VALUE)

**What Kiro Does**:
`tasks.md` includes explicit dependencies between tasks, enabling:
- Correct sequencing
- Parallel execution where safe
- Blockers visibility

**Applicability to Loa**:
- Loa's sprint.md has tasks but less formal dependency tracking
- Beads (bd CLI) already provides dependency graph
- Could enhance sprint planning to output Beads-compatible format
- Auto-create `bd dep add` commands in sprint output

**Implementation Effort**: Low - Update sprint planning templates

---

### 6. Autopilot vs Supervised Mode Toggle (LOW VALUE)

**What Kiro Does**:
- **Autopilot**: Agent works autonomously, user can interrupt/revert
- **Supervised**: Agent pauses for approval after each change

**Applicability to Loa**:
- Loa already has background execution mode
- Two quality gates (review + audit) provide rigor
- Less applicable since Claude Code handles execution control

**Implementation Effort**: N/A - Already covered by Claude Code

---

## Concepts NOT Applicable to Loa

| Kiro Feature | Why Not Applicable |
|--------------|-------------------|
| IDE integration | Loa is CLI-focused, IDE-agnostic |
| VS Code extensions | Claude Code is the interface |
| Credit tracking UI | Not relevant to framework |
| Built-in terminal | Claude Code handles this |

---

## Recommended Actions

### Priority 1 (Quick Wins)

1. **Add EARS templates** to `discovering-requirements` skill
   - Create `resources/templates/ears-requirements.md`
   - Update SKILL.md to offer EARS format option
   - Improves requirement clarity with minimal effort

2. **Document hook patterns** for Loa workflows
   - Create `.claude/protocols/recommended-hooks.md`
   - Patterns for: session continuity, grounding checks, auto-documentation

3. **Enhance sprint task format** with dependency hints
   - Update `planning-sprints` skill templates
   - Include `blocked_by` fields that map to Beads

### Priority 2 (Medium Effort)

4. **Add spec refresh capability** to `/ride`
   - Inverse of drift detection
   - Update PRD/SDD based on code reality
   - "Reverse-engineer" requirements from implementation

5. **Conditional skill loading**
   - Add `inclusion` mode to skill index.yaml
   - `always` | `fileMatch` | `manual`
   - Reduce context overhead for large projects

### Priority 3 (Future Consideration)

6. **Kiro-style steering directory**
   - `.loa/steering/` as alternative to overrides
   - More intuitive for users coming from Kiro
   - Lower priority - current system works

---

## Conclusion

Kiro validates many of Loa's existing design decisions:
- Structured planning before implementation ✓
- Skill/agent-based architecture ✓
- MCP integration ✓
- Quality gates ✓

Key differentiators where Loa could improve:
1. **EARS notation** for clearer requirements
2. **Better drift remediation** (not just detection)
3. **Conditional context loading** for efficiency

Kiro's success (backed by AWS) confirms market demand for spec-driven development tools. Loa's open-source, CLI-first approach serves a complementary niche.

---

## Sources

- [Kiro Homepage](https://kiro.dev/)
- [Kiro Documentation - First Project](https://kiro.dev/docs/getting-started/first-project/)
- [Kiro Documentation - Hooks](https://kiro.dev/docs/hooks/)
- [Kiro Documentation - Steering](https://kiro.dev/docs/steering/)
- [Kiro Documentation - Autopilot](https://kiro.dev/docs/chat/autopilot/)
- [Kiro Documentation - Custom Agent Configuration](https://kiro.dev/docs/cli/custom-agents/configuration-reference/)
- [Introducing Kiro Blog Post](https://kiro.dev/blog/introducing-kiro/)
- [DevClass Hands-On Review](https://devclass.com/2025/07/15/hands-on-with-kiro-the-aws-preview-of-an-agentic-ai-ide-driven-by-specifications/)
- [DEV.to - Agent Hooks and Steering Files](https://dev.to/ibrahimpima/i-stopped-fighting-my-ai-how-kiros-agent-hooks-and-steering-files-fixed-my-biggest-frustration-493m)
- [DataCamp Kiro Tutorial](https://www.datacamp.com/tutorial/kiro-ai)
