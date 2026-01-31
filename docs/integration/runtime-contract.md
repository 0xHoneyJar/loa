# Runtime Contract Specification

> This document defines what a runtime must implement to support Loa.

**Version**: 1.0.0  
**Status**: Draft

---

## Overview

The runtime contract is the interface between Loa (methodology) and any execution environment. A runtime that implements this contract can run Loa workflows.

---

## Required Capabilities

### 1. Exit Code Handling

Runtime MUST handle exit codes returned by Loa skills:

| Exit Code | Meaning | Required Runtime Action |
|-----------|---------|------------------------|
| 0 | Success | Proceed to next phase |
| 1 | Failure (retriable) | Retry up to `max_retries`, then escalate |
| 2 | Blocked | Escalate immediately to human |

Runtime SHOULD support extended exit codes (BSD sysexits.h):

| Exit Code | Meaning | Suggested Handling |
|-----------|---------|-------------------|
| 64-78 | Standard sysexits errors | Log and treat as exit code 1 |
| 126 | Not executable | Configuration error, alert operator |
| 127 | Not found | Configuration error, alert operator |

### 2. Checkpoint Persistence

Runtime MUST be able to persist and restore checkpoints.

**Persist checkpoint:**
```
Input: Checkpoint object (see schema below)
Output: Success/failure
Side effect: Checkpoint saved to durable storage
```

**Restore checkpoint:**
```
Input: Phase name or checkpoint ID
Output: Checkpoint object
Failure: Return null if checkpoint doesn't exist
```

**Checkpoint Schema:**
```typescript
interface Checkpoint {
  version: 1;
  execution_id: string;
  phase: string;
  created_at: ISO8601;
  
  // Outcome
  exit_code: 0 | 1 | 2;
  duration_ms: number;
  
  // Summary (REQUIRED)
  summary: string;  // Max 500 words
  
  // Continuity
  decisions: Array<{
    description: string;
    reasoning: string;
    timestamp: ISO8601;
  }>;
  
  // Artifact references
  artifacts: Array<{
    path: string;
    size_bytes: number;
    checksum: string;
    description: string;
  }>;
  
  // Errors
  errors: Array<{
    message: string;
    phase: string;
    recoverable: boolean;
  }>;
}
```

### 3. Context Signals

Runtime MUST provide context signals to Loa when requested:

```typescript
interface ContextSignals {
  // Token/context budget
  context_tokens_available: number;  // Remaining tokens before limit
  context_tokens_used: number;       // Tokens used so far
  
  // Time budget
  time_remaining_ms: number | null;  // null if no time limit
  
  // Retry state
  retry_count: number;               // Current retry attempt (0-indexed)
  max_retries: number;               // Configured maximum
  
  // Resource state
  is_approaching_limit: boolean;     // Any resource near limit
}
```

Runtime SHOULD trigger context management when `is_approaching_limit` is true.

### 4. Escalation Delivery

Runtime MUST deliver escalations to humans.

**Escalation request from Loa:**
```typescript
interface EscalationRequest {
  reason: string;
  phase: string;
  context: {
    last_decisions: Decision[];
    artifacts: ArtifactRef[];
    errors: Error[];
  };
  suggested_actions: string[];
}
```

**Runtime responsibilities:**
1. Format escalation appropriately for delivery channel
2. Deliver to configured human(s)
3. Capture human response
4. Return response to Loa for processing

**Escalation response:**
```typescript
interface EscalationResponse {
  responded_at: ISO8601;
  responder: string;  // Human identifier
  action: 'proceed' | 'retry' | 'abort' | 'modify';
  message: string;    // Human's response text
  modifications?: Record<string, any>;  // If action is 'modify'
}
```

### 5. File System Access

Runtime MUST provide file system access for Loa artifacts:

```typescript
interface FileSystem {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  list(directory: string): Promise<string[]>;
  delete(path: string): Promise<void>;
}
```

All paths are relative to project root.

---

## Optional Capabilities

### Context Compaction

Runtime MAY implement context compaction:

```typescript
interface ContextCompaction {
  // Estimate current token usage
  estimateTokens(): number;
  
  // Compact context (summarize, clear history)
  compact(options: {
    aggressive: boolean;
    preservePhases: string[];
  }): Promise<void>;
}
```

If not implemented, Loa will manage context through checkpointing alone.

### Structured Logging

Runtime MAY capture structured logs:

```typescript
interface StructuredLogger {
  log(event: {
    event: string;
    phase?: string;
    data?: Record<string, any>;
    timestamp: ISO8601;
  }): void;
}
```

**Standard events:**
- `phase_start`
- `phase_complete`
- `checkpoint_created`
- `escalation_triggered`
- `context_compaction`

### Cost Tracking

Runtime MAY track execution costs:

```typescript
interface CostTracker {
  recordCost(cost: {
    phase: string;
    tokens_input: number;
    tokens_output: number;
    api_calls: number;
    estimated_usd: number;
  }): void;
  
  getTotalCost(): CostSummary;
}
```

---

## Implementation Checklist

For runtime developers implementing Loa support:

### Required
- [ ] Exit codes 0, 1, 2 handled correctly
- [ ] Retry logic with configurable max_retries
- [ ] Checkpoint write implemented
- [ ] Checkpoint read implemented
- [ ] Context signals available
- [ ] Escalation delivery works
- [ ] File system access works

### Recommended
- [ ] Extended exit codes (64-78) handled
- [ ] Context compaction implemented
- [ ] Structured logging implemented
- [ ] Cost tracking implemented

### Testing
- [ ] Full Loa workflow completes successfully
- [ ] Retry triggers correctly on exit code 1
- [ ] Escalation triggers correctly on exit code 2
- [ ] Checkpoint survives runtime restart
- [ ] Resume from checkpoint works

---

## Reference Implementations

- **Clawdbot**: `0xHoneyJar/clawdbot` (primary reference)
- **Claude Code**: Native CLI support (minimal implementation)

---

## Versioning

This contract follows semantic versioning:
- **Major**: Breaking changes to required capabilities
- **Minor**: New optional capabilities
- **Patch**: Clarifications, documentation

Current version: **1.0.0**
