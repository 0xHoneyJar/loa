# OpenAI Agent Building Guide: Research Analysis for Loa

**Date**: 2026-02-03
**Branch**: `research/open-ai-agent-buildoors-guide`
**Source**: [A Practical Guide to Building Agents (PDF)](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf)

---

## Executive Summary

Analysis of OpenAI's "A Practical Guide to Building Agents" (34-page guide) against Loa's current architecture. The guide distills insights from numerous customer deployments into practical best practices for building agent systems.

**Key Finding**: Loa already implements most OpenAI recommendations, often with more sophisticated solutions. However, several patterns from the guide could enhance Loa's capabilities.

---

## OpenAI's Core Concepts

### Agent Definition

OpenAI defines agents as systems that:
- **Autonomously complete workflows** on behalf of users (not just automate user-initiated tasks)
- Use LLMs to **manage workflow execution and decision-making**
- Can **proactively correct behavior** when needed
- Can **abort operations** if necessary

### Three Core Components

| Component | OpenAI Definition | Loa Equivalent |
|-----------|-------------------|----------------|
| **Model (LLM)** | Drives reasoning and decision-making | Claude via skills, with `effort_hint` levels |
| **Tools** | External functions/APIs for actions | Bash, scripts, MCP servers |
| **Instructions** | Clear guidelines defining behavior | SKILL.md files (3-level architecture) |

### Tool Categories

| Category | OpenAI | Loa Equivalent |
|----------|--------|----------------|
| Data Retrieval | Databases, PDFs, web searches | Grep, Glob, Read, WebFetch, MCP servers |
| Action Execution | Emails, CRM updates | Bash, Edit, Write, gh CLI |
| Orchestration | Agents serving as tools for other agents | Subagents, Task tool with specialized agents |

---

## Orchestration Patterns Comparison

### OpenAI Patterns

| Pattern | Description | When to Use |
|---------|-------------|-------------|
| **Single-Agent** | One agent with tools in a loop | Simple workflows, clear task boundaries |
| **Multi-Agent (Manager)** | Central coordinator invoking specialists | Complex tasks requiring expertise domains |
| **Multi-Agent (Decentralized)** | Peer agents with handoffs | Flexible workflows, unclear routing |

### Loa's Current Architecture

| Pattern | Implementation | OpenAI Alignment |
|---------|----------------|------------------|
| **Single-Agent** | Individual skills (`/implement`, `/audit`) | Matches single-agent pattern |
| **Multi-Agent (Manager)** | `/autonomous` command (8-phase orchestrator) | Matches manager pattern |
| **Multi-Agent (Decentralized)** | Run Mode feedback loops (Engineer <-> Reviewer <-> Auditor) | Matches decentralized pattern |
| **Hub-and-Spoke** | `/validate` with subagents (arch, security, test) | Matches cookbook pattern |

**Assessment**: Loa covers all three orchestration patterns.

### Handoff Mechanism

**OpenAI**: "Handoffs are a one-way transfer that allow an agent to delegate to another agent."

**Loa**:
- A2A files (`reviewer.md` -> `engineer-feedback.md` -> `auditor-sprint-feedback.md`)
- Explicit handoff via file-based communication
- Stateful tracking in `.run/state.json`

**Gap Identified**: Loa's handoffs are file-based (persistent) rather than in-memory (ephemeral). This is actually an advantage for session continuity but could benefit from explicit "handoff" terminology in documentation.

---

## Guardrails Comparison

### OpenAI Guardrail Types

| Type | Purpose | Execution |
|------|---------|-----------|
| **Input Guardrails** | Validate user input before agent runs | Parallel or blocking |
| **Output Guardrails** | Validate agent output after completion | Sequential |
| **Tool Guardrails** | Validate before/after tool execution | Wraps function tools |

### Loa's Current Guardrails

| Loa Feature | OpenAI Equivalent | Implementation |
|-------------|-------------------|----------------|
| **Invisible Prompt Enhancement** | Input Guardrail | PTCF scoring < 4 triggers enhancement |
| **Quality Gates (4-gate)** | Output Guardrail | Depth, Reusability, Trigger, Verification |
| **Run Mode ICE Layer** | Tool Guardrail | Git operation safety wrapper |
| **Circuit Breaker** | Rate limiting + failure detection | Same issue 3x, no progress 5x |
| **Attention Budget** | Token exhaustion prevention | 2K single, 5K accumulated, 15K session |

### Gaps Identified

| Gap | OpenAI Pattern | Potential Loa Enhancement |
|-----|----------------|---------------------------|
| **PII Filtering** | Explicit PII filter guardrail | Currently only in retrospective sanitization (HIGH-001 fix) |
| **Relevance Classifier** | Input relevance validation | No explicit "is this relevant to the skill?" check |
| **Tool Risk Assessment** | Categorize tools by risk level | `danger_level` in skill schema exists but not enforced |
| **Tripwire Pattern** | Immediate halt on violation | Circuit breaker halts on repeated issues, not first |

---

## Specific Recommendations for Loa

### 1. Formalize Input Guardrails (HIGH VALUE)

**Current State**: Invisible Prompt Enhancement checks quality but not relevance.

**Recommendation**: Add explicit input guardrail layer to skills.

```yaml
# Proposed addition to skill index.yaml
input_guardrails:
  relevance_check: true      # Is this request relevant to this skill?
  pii_filter: true           # Block/redact PII before processing
  injection_detection: true  # Detect prompt injection attempts
```

**Implementation**: Add `<input_guardrails>` section to SKILL.md files (mirroring `<retrospective_postlude>` pattern).

### 2. Enforce Tool Risk Classification (MEDIUM VALUE)

**Current State**: `danger_level` exists in skill schema but is "config prep only."

**OpenAI Pattern**: Tool guardrails can `allow()` or `reject_content("reason")` based on risk.

**Recommendation**: Activate `danger_level` enforcement:

```yaml
# Skill risk levels
danger_level: safe      # No confirmation needed
danger_level: moderate  # Log to trajectory
danger_level: high      # Require explicit confirmation
danger_level: critical  # Block in autonomous mode
```

### 3. Add Explicit Handoff Terminology (LOW VALUE)

**Current State**: Feedback loops use A2A files for state transfer.

**Recommendation**: Document as "handoff" pattern, add explicit handoff logging:

```json
// In trajectory log
{
  "type": "handoff",
  "from_agent": "implementing-tasks",
  "to_agent": "reviewing-code",
  "handoff_type": "file_based",
  "artifacts": ["reviewer.md"],
  "timestamp": "..."
}
```

### 4. Implement Parallel vs Blocking Guardrail Modes (MEDIUM VALUE)

**OpenAI Pattern**: Input guardrails support parallel (async) or blocking (sync) execution.

**Loa Current**: All checks are synchronous/blocking.

**Recommendation**: Add async guardrail mode for non-critical checks:

```yaml
# .loa.config.yaml
guardrails:
  input:
    pii_filter:
      mode: blocking      # Must complete before skill runs
    relevance_check:
      mode: parallel      # Runs concurrently, can tripwire
    injection_detection:
      mode: blocking
```

### 5. First-Violation Tripwire Option (LOW VALUE)

**Current State**: Circuit breaker triggers after 3 repeated issues.

**OpenAI Pattern**: Tripwires halt immediately on first violation for critical guardrails.

**Recommendation**: Add tripwire mode for critical checks:

```yaml
# .loa.config.yaml
circuit_breaker:
  same_issue_threshold: 3      # Existing behavior
  tripwire_on_critical: true   # NEW: Halt on first CRITICAL finding
```

---

## Alignment Summary

### What Loa Does Better Than OpenAI Guide

| Aspect | Loa Advantage |
|--------|---------------|
| **Memory Persistence** | NOTES.md + trajectory logs survive sessions (OpenAI guide doesn't cover) |
| **Learning Loop** | Invisible Retrospective extracts learnings automatically |
| **Quality Gates** | 4-gate filter more sophisticated than simple pass/fail |
| **File-Based Handoffs** | Auditable, persistent, recoverable after crashes |
| **Three-Zone Model** | Clear ownership model (System/State/App) |
| **Effort Parameter** | Token budget control per skill |

### What Loa Could Adopt from OpenAI Guide

| Pattern | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Input Guardrails (relevance + PII) | HIGH | Medium | Prevents wasted execution |
| Tool Risk Enforcement | MEDIUM | Low | Safety improvement |
| Parallel Guardrail Mode | MEDIUM | Medium | Performance |
| Tripwire on Critical | LOW | Low | Faster failure detection |
| Handoff Terminology | LOW | Low | Documentation clarity |

---

## Implementation Roadmap

### Phase 1: Input Guardrails (Sprint)

1. Create `input-guardrails.md` protocol
2. Add `<input_guardrails>` prelude to high-risk skills
3. Implement relevance check using fast model
4. Add PII filter (extend HIGH-001 sanitization patterns)

### Phase 2: Tool Risk Enforcement (Sprint)

1. Activate `danger_level` checking in skill loader
2. Add confirmation prompt for `high` level
3. Block `critical` tools in Run Mode
4. Add trajectory logging for all tool risk decisions

### Phase 3: Performance Optimization (Sprint)

1. Add parallel guardrail mode
2. Implement async execution for non-blocking checks
3. Add tripwire pattern for critical violations

---

## References

**Primary Sources**:
- [OpenAI Guide (PDF)](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf)
- [OpenAI Agents SDK Guardrails](https://openai.github.io/openai-agents-python/guardrails/)
- [OpenAI Multi-Agent Cookbook](https://cookbook.openai.com/examples/agents_sdk/multi-agent-portfolio-collaboration/multi_agent_portfolio_collaboration)
- [AIBase Summary](https://www.aibase.com/news/17299)

**Loa Internal References**:
- `.claude/protocols/run-mode.md` - Safety model, circuit breaker
- `.claude/protocols/feedback-loops.md` - Quality gates
- `.claude/protocols/subagent-invocation.md` - Multi-agent patterns
- `.claude/schemas/skill-index.schema.json` - danger_level field

---

*Research conducted by Claude Opus 4.5 for Loa Framework improvement analysis*
