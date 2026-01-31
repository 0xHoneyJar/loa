# Separation of Concerns

> **Source**: PR #78 - Separation of Concerns Framework
> **Related**: PR #73 - Autonomous Agent Orchestrator, PR #82 - Implementation

## Overview

The Loa framework operates across three distinct layers, each with clear ownership and responsibilities. This separation ensures that the methodology (Loa) remains portable across different runtimes while enabling platform-specific optimizations.

## The Three-Layer Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         LOA LAYER                               │
│                    (Methodology / WHAT)                         │
│                                                                 │
│   Skills, Protocols, Quality Gates, Agentic Memory             │
│   "What should happen and why"                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Defines
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       RUNTIME LAYER                             │
│                     (Execution / HOW)                           │
│                                                                 │
│   Claude Code, Cursor, Aider, Custom Agents                    │
│   "How to execute the methodology"                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Implements
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     INTEGRATION LAYER                           │
│                        (Contract)                               │
│                                                                 │
│   Exit Codes, Checkpoint Schema, Context Signals               │
│   "The handshake protocol between layers"                       │
└─────────────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Loa Layer (Methodology)

**Ownership**: Loa framework / WHAT to do

**Responsibilities**:
- Define the 8-phase execution model
- Specify quality gates and their criteria
- Manage agentic memory (NOTES.md, trajectory)
- Define skill contracts (inputs/outputs)
- Own the PRD → SDD → Sprint → Implementation flow

**Does NOT**:
- Know how tools are invoked
- Manage token limits or API calls
- Handle runtime-specific optimizations
- Implement context compaction algorithms

**Artifacts Owned**:
- `.claude/skills/` - Skill definitions
- `.claude/protocols/` - Cross-cutting protocols
- `grimoires/loa/` - State zone artifacts
- `.loa.config.yaml` - Configuration

### Runtime Layer (Execution)

**Ownership**: Claude Code (or other runtime) / HOW to execute

**Responsibilities**:
- Invoke tools (Read, Write, Bash, etc.)
- Manage context window and token limits
- Handle API rate limiting
- Execute compaction when needed
- Provide execution environment

**Does NOT**:
- Define what constitutes "done"
- Decide which phase comes next
- Own quality criteria
- Determine when to checkpoint

**Artifacts Owned**:
- Tool implementations
- Context management
- Session handling
- API communication

### Integration Layer (Contract)

**Ownership**: Shared / The handshake protocol

**Purpose**: Enable Loa to run on any compatible runtime

**Components**:

1. **Exit Codes** (Loa → Runtime)
   ```
   0 = Success (proceed to next phase)
   1 = Retry (temporary failure, can retry)
   2 = Blocked (needs human intervention)
   ```

2. **Checkpoint Schema** (Loa → Runtime)
   ```yaml
   execution_id: string
   phase: string
   created_at: ISO8601
   exit_code: 0 | 1 | 2
   summary: string
   ```

3. **Context Signals** (Runtime → Loa)
   ```
   CONTEXT_SOFT_LIMIT: Token threshold for standard compaction
   CONTEXT_HARD_LIMIT: Token threshold for emergency compaction
   CONTEXT_CURRENT: Current token usage
   ```

4. **Escalation Protocol** (Bidirectional)
   ```
   Loa signals: "I'm stuck, need human"
   Runtime receives: Halt execution, surface report
   ```

## Decision Framework

When adding a new feature, use this framework:

### "Where does this belong?"

| Question | If Yes → | If No → |
|----------|----------|---------|
| Does it define *what* should happen? | Loa Layer | ↓ |
| Does it define *how* to execute? | Runtime Layer | ↓ |
| Is it a handshake between layers? | Integration Layer | Reconsider scope |

### Examples

| Feature | Layer | Reasoning |
|---------|-------|-----------|
| Quality gate criteria | Loa | Defines *what* passes |
| Token counting | Runtime | *How* context is managed |
| Exit code meanings | Integration | Shared contract |
| Phase ordering | Loa | Defines *what* sequence |
| Tool invocation | Runtime | *How* actions happen |
| Checkpoint format | Integration | Shared schema |
| Agentic memory | Loa | Defines *what* to remember |
| Context compaction | Runtime | *How* to manage context |
| Operator detection | Loa | Defines *what* behavior to apply |
| API rate limiting | Runtime | *How* to throttle |

## Feature Delineation

### Features Owned by Loa

1. **8-Phase Execution Model**
   - Phase definitions and ordering
   - Entry/exit criteria per phase
   - Gate validations

2. **Quality Gates (Five Gates)**
   - Gate 0: Skill Selection
   - Gate 1: Precondition Check
   - Gate 2: Execution Check
   - Gate 3: Output Check
   - Gate 4: Goal Achievement

3. **Agentic Memory**
   - NOTES.md structure
   - Trajectory logging
   - Decision tracking

4. **Skill System**
   - Skill definitions (index.yaml, SKILL.md)
   - Skill dependencies
   - Input/output contracts

5. **Feedback Loops**
   - Remediation loop logic
   - PRD iteration triggers
   - Learning capture

### Features Owned by Runtime

1. **Tool Execution**
   - Read, Write, Edit operations
   - Bash command execution
   - Search operations (Glob, Grep)

2. **Context Management**
   - Token counting
   - Compaction algorithms
   - Context window utilization

3. **Session Management**
   - Session IDs
   - Resume/restore logic
   - Timeout handling

4. **API Communication**
   - Rate limiting
   - Error handling
   - Retry logic

### Features Shared (Integration Layer)

1. **Exit Codes**
   - Defined by Loa (meanings)
   - Interpreted by Runtime (actions)

2. **Checkpoint Files**
   - Schema defined by Loa
   - Written/read by Runtime

3. **Context Signals**
   - Thresholds defined by Loa
   - Measured by Runtime

4. **Escalation**
   - Triggered by Loa
   - Surfaced by Runtime

## Practical Implications

### For Skill Authors

When writing a skill:
- Focus on the *what* (logic, criteria, outputs)
- Use Integration Layer contracts for communication
- Don't assume Runtime specifics

### For Runtime Implementers

When implementing a runtime:
- Honor the Integration Layer contracts
- Don't modify Loa Layer behavior
- Provide context signals accurately

### For Framework Maintainers

When evolving the framework:
- Changes to Loa Layer require careful migration
- Changes to Runtime Layer are runtime-specific
- Changes to Integration Layer require coordination

## Migration Path

### V1 → V2 (Current)

V2 simplifications:
- 3 exit codes (was 5)
- File existence checks (was schema validation)
- Human review for Gate 0 and Gate 4 (was LLM-as-judge)

### V2 → V3 (Future)

Planned enhancements:
- QMD for Gate 0 (automatic skill selection)
- LLM-as-judge for Gate 4 (goal validation)
- Schema validation for Gate 1 and Gate 3

## Related Documents

- [Runtime Contract](../integration/runtime-contract.md) - Integration Layer specification
- [Quality Gates](../../.claude/skills/autonomous-agent/resources/quality-gates.md) - Gate implementation
- [CLAUDE.md](../../CLAUDE.md) - Framework overview
