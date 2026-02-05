# Runtime Contract

> **Source**: PR #78 - Separation of Concerns Framework
> **Related**: PR #73 - Autonomous Agent Orchestrator, PR #82 - Implementation

## Overview

The Runtime Contract defines the Integration Layer between Loa (methodology) and any compatible runtime (Claude Code, Cursor, Aider, etc.). Implementing this contract enables a runtime to execute Loa workflows reliably.

## Exit Code Specification

### Standard Exit Codes

| Code | Name | Meaning | Runtime Action |
|------|------|---------|----------------|
| `0` | SUCCESS | Phase completed successfully | Proceed to next phase |
| `1` | RETRY | Temporary failure, can retry | Retry with backoff (max 3) |
| `2` | BLOCKED | Permanent failure, needs intervention | Halt, surface escalation report |

### Exit Code Handling

```typescript
interface ExitCodeHandler {
  handleExitCode(code: number, context: PhaseContext): Promise<Action>;
}

enum Action {
  PROCEED,      // Continue to next phase
  RETRY,        // Retry current phase
  ESCALATE,     // Surface escalation report
  HALT          // Stop execution completely
}

// Example implementation
async function handleExitCode(code: number, context: PhaseContext): Promise<Action> {
  switch (code) {
    case 0:
      return Action.PROCEED;

    case 1:
      if (context.retryCount < 3) {
        await sleep(exponentialBackoff(context.retryCount));
        return Action.RETRY;
      }
      return Action.ESCALATE;

    case 2:
      await generateEscalationReport(context);
      return Action.HALT;

    default:
      console.warn(`Unknown exit code: ${code}`);
      return Action.ESCALATE;
  }
}
```

## Checkpoint Schema

### Schema Definition (TypeScript)

```typescript
interface Checkpoint {
  // Required fields
  execution_id: string;      // Unique execution identifier
  phase: PhaseIdentifier;    // Current phase (e.g., "discovery", "design")
  created_at: string;        // ISO 8601 timestamp
  exit_code: 0 | 1 | 2;      // Phase exit code
  summary: string;           // Human-readable summary

  // Optional fields
  decisions?: Decision[];    // Decisions made during phase
  artifacts?: Artifact[];    // Files created/modified
  errors?: Error[];          // Errors encountered
  metrics?: Metrics;         // Execution metrics
}

type PhaseIdentifier =
  | "preflight"
  | "discovery"
  | "design"
  | "implementation"
  | "audit"
  | "submit"
  | "deploy"
  | "learning";

interface Decision {
  id: string;                // e.g., "D-001"
  description: string;       // What was decided
  reasoning: string;         // Why
  timestamp: string;         // When
}

interface Artifact {
  path: string;              // File path
  action: "created" | "modified" | "deleted";
  size_bytes?: number;
}

interface Error {
  code: string;              // Error code
  message: string;           // Error message
  recoverable: boolean;      // Can be retried?
}

interface Metrics {
  duration_ms: number;       // Phase duration
  tokens_used?: number;      // Approximate token usage
  api_calls?: number;        // Number of API calls
}
```

### Checkpoint File Format (YAML)

```yaml
# .loa-checkpoint/discovery.yaml
execution_id: "exec-20260131-abc123"
phase: discovery
created_at: "2026-01-31T14:00:00Z"
exit_code: 0
summary: "PRD created with 5 goals and 9 user stories"

decisions:
  - id: D-001
    description: "Use JWT for authentication"
    reasoning: "Industry standard, stateless"
    timestamp: "2026-01-31T14:00:00Z"

artifacts:
  - path: grimoires/loa/prd.md
    action: created
    size_bytes: 12450

metrics:
  duration_ms: 45000
  tokens_used: 8500
```

### Checkpoint Operations

```typescript
interface CheckpointManager {
  // Write checkpoint after phase completion
  write(checkpoint: Checkpoint): Promise<void>;

  // Read latest checkpoint for phase
  read(phase: PhaseIdentifier): Promise<Checkpoint | null>;

  // Check if can resume from checkpoint
  canResume(): Promise<boolean>;

  // Get execution state from checkpoints
  getState(): Promise<ExecutionState>;
}

interface ExecutionState {
  execution_id: string;
  current_phase: PhaseIdentifier;
  completed_phases: PhaseIdentifier[];
  last_checkpoint: Checkpoint;
}
```

## Context Signals Interface

### Signal Types

| Signal | Direction | Type | Description |
|--------|-----------|------|-------------|
| `CONTEXT_SOFT_LIMIT` | Loa → Runtime | number | Token threshold for standard compaction |
| `CONTEXT_HARD_LIMIT` | Loa → Runtime | number | Token threshold for emergency compaction |
| `CONTEXT_CURRENT` | Runtime → Loa | number | Current token usage |
| `CONTEXT_WARNING` | Runtime → Loa | enum | Warning level (none, soft, hard) |

### Interface Definition

```typescript
interface ContextSignals {
  // Configuration (from Loa)
  softLimit: number;       // Default: 80000
  hardLimit: number;       // Default: 150000

  // Runtime state
  currentTokens: number;
  warningLevel: "none" | "soft" | "hard";

  // Methods
  checkLimits(): ContextWarning;
  requestCompaction(level: "standard" | "emergency"): Promise<void>;
}

interface ContextWarning {
  level: "none" | "soft" | "hard";
  currentTokens: number;
  percentUsed: number;
  recommendation: string;
}

// Example implementation
function checkLimits(signals: ContextSignals): ContextWarning {
  const { currentTokens, softLimit, hardLimit } = signals;

  if (currentTokens >= hardLimit) {
    return {
      level: "hard",
      currentTokens,
      percentUsed: (currentTokens / hardLimit) * 100,
      recommendation: "Emergency compaction required"
    };
  }

  if (currentTokens >= softLimit) {
    return {
      level: "soft",
      currentTokens,
      percentUsed: (currentTokens / softLimit) * 100,
      recommendation: "Consider running checkpoint and compaction"
    };
  }

  return {
    level: "none",
    currentTokens,
    percentUsed: (currentTokens / softLimit) * 100,
    recommendation: "Context healthy"
  };
}
```

## Escalation Protocol

### Escalation Triggers

| Trigger | Source | Threshold |
|---------|--------|-----------|
| Max remediation loops | Loa | 3 loops |
| Same issue repeated | Loa | 3 occurrences |
| No progress | Loa | 5 cycles |
| Timeout | Runtime | 8 hours |
| Context overflow | Runtime | Hard limit |

### Escalation Report Schema

```typescript
interface EscalationReport {
  execution_id: string;
  session_id: string;
  trigger: EscalationTrigger;
  phase: PhaseIdentifier;
  timestamp: string;

  // State snapshot
  state: {
    phases: PhaseStatus[];
    last_checkpoint: Checkpoint;
    remaining_findings: Finding[];
  };

  // Context for human
  context: {
    last_decisions: Decision[];
    remediation_attempts: number;
    suggested_actions: string[];
  };
}

type EscalationTrigger =
  | "max_loops"
  | "same_issue"
  | "no_progress"
  | "timeout"
  | "context_overflow"
  | "manual";

interface PhaseStatus {
  phase: PhaseIdentifier;
  status: "completed" | "in_progress" | "failed" | "pending";
  exit_code?: 0 | 1 | 2;
}

interface Finding {
  id: string;
  severity: "critical" | "high" | "medium" | "low";
  category: string;
  description: string;
}
```

### Escalation Handling

```typescript
interface EscalationHandler {
  // Generate escalation report
  generateReport(context: EscalationContext): Promise<EscalationReport>;

  // Surface to user
  surfaceToUser(report: EscalationReport): Promise<void>;

  // Wait for human resolution
  awaitResolution(): Promise<Resolution>;
}

interface Resolution {
  action: "fix_and_resume" | "skip_phase" | "reset" | "abort";
  notes?: string;
}
```

## Implementation Checklist

### For Runtime Implementers

#### Exit Code Handling
- [ ] Interpret exit code 0 as success
- [ ] Retry on exit code 1 (max 3 times with backoff)
- [ ] Escalate on exit code 2
- [ ] Handle unknown exit codes gracefully

#### Checkpoint Management
- [ ] Create `.loa-checkpoint/` directory on first run
- [ ] Write checkpoint YAML after each phase
- [ ] Include all required fields
- [ ] Support optional fields when provided
- [ ] Enable resume from checkpoint

#### Context Signals
- [ ] Read soft/hard limits from config
- [ ] Track current token usage
- [ ] Emit warnings at thresholds
- [ ] Trigger compaction when needed

#### Escalation Protocol
- [ ] Detect escalation triggers
- [ ] Generate escalation report
- [ ] Surface report to user
- [ ] Halt execution cleanly
- [ ] Support resume after resolution

### Validation

```bash
# Validate checkpoint schema
.claude/scripts/schema-validator.sh .loa-checkpoint/discovery.yaml checkpoint

# Test exit code handling
echo "exit 1" | bash  # Should retry
echo "exit 2" | bash  # Should escalate

# Check context signals
cat .loa-checkpoint/context-state.yaml
```

## Compatibility Matrix

| Runtime | Exit Codes | Checkpoints | Context Signals | Escalation |
|---------|------------|-------------|-----------------|------------|
| Claude Code | Full | Full | Full | Full |
| Cursor | Full | Partial | Partial | Manual |
| Aider | Full | Manual | Manual | Manual |
| Custom | Implement | Implement | Implement | Implement |

## Anthropic Context Features (v1.13.0)

### Effort Parameter

Runtimes should read effort configuration from `.loa.config.yaml` and pass to API:

```typescript
interface EffortConfig {
  default_level: "low" | "medium" | "high";
  budget_ranges: {
    low: { min: number; max: number };
    medium: { min: number; max: number };
    high: { min: number; max: number };
  };
  per_skill: Record<string, "low" | "medium" | "high">;
}

// Read config and determine effective budget
function getEffortBudget(skillName: string, config: EffortConfig): number {
  const level = config.per_skill[skillName] || config.default_level;
  const range = config.budget_ranges[level];
  return range.max; // or use midpoint: (range.min + range.max) / 2
}

// Pass to API
const request = {
  model: "claude-opus-4-6",
  thinking: {
    budget_tokens: getEffortBudget("auditing-security", config)
  },
  // ... other params
};
```

### Context Editing Signals

Runtime should emit signals when context thresholds are reached:

```typescript
interface ContextEditingConfig {
  enabled: boolean;
  compact_threshold_percent: number;
  preserve_recent_turns: number;
  clear_targets: string[];
  preserve_artifacts: string[];
}

// Signal when threshold reached
interface ContextNearLimitSignal {
  type: "CONTEXT_NEAR_LIMIT";
  current_tokens: number;
  limit_tokens: number;
  percent_used: number;
}

// Loa responds with compaction request
interface CompactionRequest {
  type: "COMPACTION_REQUEST";
  clear_targets: string[];
  preserve: string[];
}

// Runtime confirms completion
interface CompactionCompleteSignal {
  type: "COMPACTION_COMPLETE";
  tokens_freed: number;
  items_cleared: number;
  new_percent: number;
}
```

**API Integration**: Use beta header `context-management-2025-06-27` for context editing features.

### Memory Schema

Memory persistence is Loa's responsibility (grimoire files), but runtime may:

1. **Read** memories from `grimoires/loa/memory/*.yaml` on session start
2. **Validate** entries against `.claude/schemas/memory.schema.json`
3. **Surface** relevant memories during retrieval operations

Memory files follow the schema at `.claude/schemas/memory.schema.json`.

### Graceful Degradation

When features are disabled (default), runtimes should:

- **Effort**: Use model default (no `thinking.budget_tokens`)
- **Context Editing**: Standard context management (no compaction signals)
- **Memory**: Ignore memory directory (file operations are optional)

## Related Documents

- [Separation of Concerns](../architecture/separation-of-concerns.md) - Layer model
- [Quality Gates](../../.claude/skills/autonomous-agent/resources/quality-gates.md) - Gate implementation
- [Checkpoint Protocol](../../.claude/protocols/checkpoint-and-compact.md) - Checkpoint details
- [Context Editing Protocol](../../.claude/protocols/context-editing.md) - Compaction policies
- [Memory Protocol](../../.claude/protocols/memory.md) - Memory lifecycle
