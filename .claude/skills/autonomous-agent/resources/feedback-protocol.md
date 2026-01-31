# Feedback Protocol

## Overview

The Feedback Protocol enables upstream learning from autonomous execution. During Phase 7 (Learning), the orchestrator captures gaps, friction, patterns, and improvements to feed back into the methodology.

Reference: Issue #48 - Upstream Feedback Loop

## Four Learning Types

### 1. Gap

**Definition**: Missing capability or incomplete coverage discovered during execution.

```yaml
type: gap
severity: major | minor
target: skill | protocol | schema | docs
description: "What was missing"
context: "When/how it was discovered"
suggested_action: "Proposed fix"
```

**Examples**:
- PRD missing acceptance criteria for edge case
- SDD missing error handling specification
- Sprint plan missing dependency between tasks

### 2. Friction

**Definition**: Workflow impediment that slowed execution.

```yaml
type: friction
severity: high | medium | low
target: skill | workflow | tool | integration
description: "What caused the slowdown"
context: "Phase/task where encountered"
workaround: "How it was overcome (if applicable)"
suggested_action: "Proposed improvement"
```

**Examples**:
- Checkpoint format difficult to parse
- Quality gate too strict for iterative work
- Tool output format incompatible with next step

### 3. Pattern

**Definition**: Recurring solution or approach worth capturing.

```yaml
type: pattern
category: error_handling | optimization | architecture | testing
description: "The pattern observed"
trigger: "When this pattern applies"
solution: "The approach that worked"
verification: "How to verify it's working"
```

**Examples**:
- "When API returns 429, exponential backoff with jitter"
- "When testing async code, use fake timers"
- "When auditing crypto, check key derivation first"

### 4. Improvement

**Definition**: Enhancement idea discovered during execution.

```yaml
type: improvement
target: skill | protocol | schema | docs | tool
description: "Proposed improvement"
rationale: "Why this would help"
effort: high | medium | low
impact: high | medium | low
```

**Examples**:
- "Add --dry-run flag to deployment skill"
- "Include token count in checkpoint files"
- "Auto-detect language for syntax highlighting"

## Target Classification

Feedback is routed to appropriate targets:

| Target | Description | Example Feedback |
|--------|-------------|------------------|
| `skill` | Specific Loa skill | "/implement should check for uncommitted changes" |
| `protocol` | Cross-cutting protocol | "Trajectory logging should include token counts" |
| `schema` | Data structure/format | "Checkpoint schema needs 'attempts' field" |
| `docs` | Documentation | "CLAUDE.md missing /autonomous command" |
| `tool` | External tool integration | "gh CLI needs --json flag for parsing" |
| `workflow` | Multi-step process | "Audit loop should limit to 3 iterations" |
| `integration` | MCP/external service | "Linear integration needs rate limiting" |

## Aggregation Mechanism

### Session-Level

During execution, feedback is collected in memory:

```yaml
# In-memory during Phase 7
session_feedback:
  - type: gap
    ...
  - type: friction
    ...
```

### Flush to File

At end of Phase 7, flush to `grimoires/loa/feedback/{date}.yaml`:

```yaml
# grimoires/loa/feedback/2026-01-31.yaml
version: 1
execution_id: "exec-abc123"
session_id: "${CLAUDE_SESSION_ID}"
generated_at: "2026-01-31T15:00:00Z"

entries:
  - id: fb-001
    type: gap
    severity: minor
    target: skill
    skill_name: implementing-tasks
    description: "No check for existing uncommitted changes before implementation"
    context: "Phase 3 implementation, task 1.2"
    suggested_action: "Add git status check at task start"

  - id: fb-002
    type: friction
    severity: medium
    target: protocol
    protocol_name: checkpoint-and-compact
    description: "Checkpoint files grow too large with full artifact content"
    context: "Phase 4 audit, after 3 remediation loops"
    workaround: "Manually truncated checkpoint to last 2 entries"
    suggested_action: "Add rolling window to checkpoint retention"

  - id: fb-003
    type: pattern
    category: error_handling
    description: "Gate 1 failures usually indicate missing /ride"
    trigger: "Gate 1 fails on design or implementation phase"
    solution: "Run /ride --fresh before retrying"
    verification: "reality/ files have recent timestamps"
```

## Integration Points

### Phase 7 Entry

```markdown
## Phase 7: Learning

### 7.1 Collect Session Feedback

Review execution trajectory for:
- [ ] Gaps: What was missing from PRD/SDD/sprint plan?
- [ ] Friction: What slowed down execution?
- [ ] Patterns: What solutions emerged repeatedly?
- [ ] Improvements: What could be better?

### 7.2 Classify and Record

For each item:
1. Determine type (gap/friction/pattern/improvement)
2. Assign severity/priority
3. Identify target (skill/protocol/schema/etc.)
4. Write to feedback file

### 7.3 Gap Analysis

Compare PRD goals to implementation:
- [ ] Check each G-N goal against reality
- [ ] Identify unmet goals
- [ ] Classify gaps as major (PRD iteration) or minor (next sprint)

### 7.4 Trigger PRD Iteration (if needed)

If major gaps found:
- Write to `grimoires/loa/gaps.yaml`
- Recommend `/refine-prd` before next cycle
```

### Feedback Schema

```yaml
# .claude/schemas/feedback.schema.yaml
$schema: "http://json-schema.org/draft-07/schema#"
type: object
required:
  - version
  - execution_id
  - generated_at
  - entries
properties:
  version:
    type: integer
    const: 1
  execution_id:
    type: string
  session_id:
    type: string
  generated_at:
    type: string
    format: date-time
  entries:
    type: array
    items:
      type: object
      required:
        - id
        - type
        - description
      properties:
        id:
          type: string
          pattern: "^fb-[0-9]{3}$"
        type:
          enum: [gap, friction, pattern, improvement]
        severity:
          enum: [major, minor, high, medium, low]
        target:
          enum: [skill, protocol, schema, docs, tool, workflow, integration]
        description:
          type: string
        context:
          type: string
        suggested_action:
          type: string
```

## Upstream Flow

Feedback flows upstream through `/compound`:

```
Session Feedback → /compound → Pattern Detection → Skill Extraction
                                    ↓
                              Morning Context ← Skills DB
```

### Aggregation Rules

1. **Deduplication**: Similar feedback merged (Jaccard > 0.7)
2. **Frequency Tracking**: Count occurrences across sessions
3. **Priority Escalation**: Minor → Major if seen 3+ times
4. **Auto-Archive**: Addressed feedback marked resolved

### Quality Gates for Feedback

Before feedback becomes a skill:

| Gate | Criteria |
|------|----------|
| Discovery Depth | Non-trivial insight (score >= 5) |
| Reusability | Applies beyond this project |
| Trigger Clarity | Clear activation conditions |
| Verification | Testable/observable outcome |

## Configuration

In `.loa.config.yaml`:

```yaml
autonomous_agent:
  feedback:
    # Enable feedback collection
    enabled: true
    # Output directory
    output_dir: grimoires/loa/feedback
    # Auto-flush at phase end
    auto_flush: true
    # Minimum severity to capture
    min_severity: low
    # Types to collect
    collect_types:
      - gap
      - friction
      - pattern
      - improvement
```
