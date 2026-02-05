# Beads TypeScript Runtime Patterns

> Production-hardened TypeScript utilities for beads_rust integration.
>
> **Version**: 1.0.0
> **Origin**: Extracted from [loa-beauvoir](https://github.com/openclaw/openclaw) production implementation
> **Related**: [Issue #186](https://github.com/0xHoneyJar/loa/issues/186)

## Overview

This module provides type-safe, security-first utilities for developers building TypeScript/Node.js tools that integrate with [beads_rust](https://github.com/0xHoneyJar/beads_rust) (`br` CLI).

These patterns complement Loa's shell-based beads infrastructure (v1.29.0) by providing:

- **Security validation** for beadIds, labels, and paths
- **Shell escaping** for safe command construction
- **Label constants** for run-mode state tracking
- **State derivation** utilities for run and sprint lifecycle

## Installation

These utilities are built into the Loa framework. No additional installation required.

```typescript
// Import from the beads module
import {
  validateBeadId,
  shellEscape,
  LABELS,
  deriveRunState
} from '.claude/lib/beads';
```

## Quick Start

```typescript
import { validateBeadId, shellEscape, LABELS, deriveRunState } from '.claude/lib/beads';

// 1. Validate user input
validateBeadId(userProvidedId); // throws if invalid

// 2. Safely construct shell commands
const cmd = `br show ${shellEscape(beadId)}`;

// 3. Use semantic labels
await execBr(`label add ${beadId} ${LABELS.RUN_CURRENT}`);

// 4. Derive state from labels
const state = deriveRunState(bead.labels); // "READY" | "RUNNING" | "HALTED" | "COMPLETE"
```

## API Reference

### validation.ts

Security validation functions to prevent command injection and path traversal.

#### `validateBeadId(beadId: unknown): asserts beadId is string`

Validates bead ID against safe pattern. **Must be called before using beadId in shell commands or file paths.**

```typescript
validateBeadId('task-123');     // OK
validateBeadId('../etc');       // throws Error
validateBeadId('task;rm -rf'); // throws Error
```

**Pattern**: `/^[a-zA-Z0-9_-]+$/`
**Max Length**: 128 characters

#### `validateLabel(label: unknown): asserts label is string`

Validates label format (allows colons for namespaced labels).

```typescript
validateLabel('sprint:in_progress'); // OK
validateLabel('label with spaces');  // throws Error
```

**Pattern**: `/^[a-zA-Z0-9_:-]+$/`
**Max Length**: 64 characters

#### `validatePath(path: unknown): asserts path is string`

Validates path does not contain traversal sequences.

```typescript
validatePath('/home/user/file.txt'); // OK
validatePath('../etc/passwd');        // throws Error
```

#### `shellEscape(str: string): string`

Escapes string for safe shell execution using single-quote technique.

```typescript
shellEscape('hello');           // "'hello'"
shellEscape("it's");            // "'it'\\''s'"
shellEscape('$(rm -rf /)');     // "'$(rm -rf /)'"  (safe - not executed)
```

**SECURITY**: This is the only safe way to include user input in shell commands.

#### `validateBrCommand(cmd: unknown): asserts cmd is string`

Validates br command path is safe (only 'br' or absolute paths without shell metacharacters).

```typescript
validateBrCommand('br');                    // OK
validateBrCommand('/usr/local/bin/br');     // OK
validateBrCommand('/bin/br; whoami');       // throws Error
```

#### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `BEAD_ID_PATTERN` | `/^[a-zA-Z0-9_-]+$/` | Valid beadId characters |
| `MAX_BEAD_ID_LENGTH` | 128 | Maximum beadId length |
| `MAX_STRING_LENGTH` | 1024 | Maximum shell argument length |
| `LABEL_PATTERN` | `/^[a-zA-Z0-9_:-]+$/` | Valid label characters |
| `MAX_LABEL_LENGTH` | 64 | Maximum label length |
| `ALLOWED_TYPES` | Set | Valid bead types |
| `ALLOWED_OPERATIONS` | Set | Valid operation types |

#### Safe Coercion

```typescript
// Returns valid type or fallback
safeType('invalid');      // 'task' (default)
safeType('epic');         // 'epic'
safeType(null, 'bug');    // 'bug' (custom fallback)

// Returns valid priority or fallback
safePriority(-1);         // 2 (default)
safePriority(5);          // 5
safePriority('5', 3);     // 3 (custom fallback)

// Filter array to valid labels only
filterValidLabels(['valid', 'has spaces', 123]); // ['valid']
```

### labels.ts

Semantic label constants for run-mode state tracking.

#### `LABELS`

```typescript
const LABELS = {
  // Run Lifecycle
  RUN_CURRENT: 'run:current',        // Active run epic
  RUN_EPIC: 'run:epic',              // Run epic (may be historical)

  // Sprint State
  SPRINT_IN_PROGRESS: 'sprint:in_progress',
  SPRINT_PENDING: 'sprint:pending',
  SPRINT_COMPLETE: 'sprint:complete',

  // Circuit Breaker
  CIRCUIT_BREAKER: 'circuit-breaker',
  SAME_ISSUE_PREFIX: 'same-issue-',  // e.g., 'same-issue-3x'

  // Session Tracking
  SESSION_PREFIX: 'session:',        // e.g., 'session:abc123'
  HANDOFF_PREFIX: 'handoff:',        // e.g., 'handoff:abc123'

  // Type Labels
  TYPE_EPIC: 'epic',
  TYPE_SPRINT: 'sprint',
  TYPE_TASK: 'task',

  // Status Labels
  STATUS_BLOCKED: 'blocked',
  STATUS_READY: 'ready',
  SECURITY: 'security',
} as const;
```

#### State Derivation

```typescript
// Derive run state from labels
deriveRunState(labels: string[]): RunState
// Returns: 'READY' | 'RUNNING' | 'HALTED' | 'COMPLETE'

// Priority: HALTED > COMPLETE > RUNNING > READY

// Derive sprint state from labels
deriveSprintState(labels: string[]): SprintState
// Returns: 'pending' | 'in_progress' | 'complete'

// Priority: complete > in_progress > pending
```

#### Label Utilities

```typescript
// Same-issue tracking
createSameIssueLabel(3);              // 'same-issue-3x'
parseSameIssueCount('same-issue-3x'); // 3

// Session tracking
createSessionLabel('abc123');    // 'session:abc123'
createHandoffLabel('abc123');    // 'handoff:abc123'

// Label queries
hasLabel(labels, 'run:current');           // true/false
hasLabelWithPrefix(labels, 'sprint:');     // true/false
getLabelsWithPrefix(labels, 'session:');   // string[]
```

#### Types

```typescript
type BeadLabel = (typeof LABELS)[keyof typeof LABELS];
type RunState = 'READY' | 'RUNNING' | 'HALTED' | 'COMPLETE';
type SprintState = 'pending' | 'in_progress' | 'complete';
```

## Security Considerations

### Command Injection Prevention

All user-controllable values **must** be validated before use in shell commands:

```typescript
// WRONG - vulnerable to injection
const cmd = `br show ${userInput}`;

// CORRECT - validate first
validateBeadId(userInput);
const cmd = `br show ${shellEscape(userInput)}`;
```

### Path Traversal Prevention

Always validate paths before file operations:

```typescript
// WRONG - vulnerable to traversal
const path = `/data/beads/${userInput}.json`;

// CORRECT - validate first
validatePath(userInput);
const path = `/data/beads/${userInput}.json`;
```

### Shell Escaping

The `shellEscape()` function uses single-quote escaping, which is safe for all content:

- Command substitution (`$()`, backticks) is not evaluated
- Variable expansion (`$VAR`) is not performed
- Shell metacharacters are treated literally

```typescript
// All of these are safe after shellEscape()
shellEscape('$(whoami)');     // '$(whoami)' - not executed
shellEscape('`id`');          // '`id`'      - not executed
shellEscape('foo; rm -rf /'); // 'foo; rm -rf /' - semicolon is literal
```

## Examples

### Safe br Command Execution

```typescript
import { exec } from 'child_process';
import { promisify } from 'util';
import { validateBeadId, shellEscape, validateBrCommand } from '.claude/lib/beads';

const execAsync = promisify(exec);

async function execBr(args: string, brCommand = 'br'): Promise<string> {
  validateBrCommand(brCommand);
  const { stdout } = await execAsync(`${brCommand} ${args}`);
  return stdout.trim();
}

async function showBead(beadId: string): Promise<object> {
  validateBeadId(beadId);
  const result = await execBr(`show ${shellEscape(beadId)} --json`);
  return JSON.parse(result);
}
```

### Run State Management

```typescript
import { LABELS, deriveRunState } from '.claude/lib/beads';

async function getCurrentRunState(brCommand = 'br'): Promise<RunState> {
  const result = await execBr(`list --label ${LABELS.RUN_CURRENT} --json`);
  const beads = JSON.parse(result);

  if (beads.length === 0) {
    return 'READY';
  }

  return deriveRunState(beads[0].labels);
}
```

### Circuit Breaker Tracking

```typescript
import {
  LABELS,
  createSameIssueLabel,
  parseSameIssueCount,
  getLabelsWithPrefix
} from '.claude/lib/beads';

async function recordCircuitBreaker(runId: string, issueHash: string): Promise<void> {
  validateBeadId(runId);

  // Check for existing same-issue labels
  const bead = await showBead(runId);
  const sameIssueLabels = getLabelsWithPrefix(bead.labels, LABELS.SAME_ISSUE_PREFIX);

  let count = 1;
  for (const label of sameIssueLabels) {
    const existing = parseSameIssueCount(label);
    if (existing && existing >= count) {
      count = existing + 1;
    }
  }

  // Add circuit breaker and same-issue labels
  await execBr(`label add ${shellEscape(runId)} ${LABELS.CIRCUIT_BREAKER}`);
  await execBr(`label add ${shellEscape(runId)} ${createSameIssueLabel(count)}`);
}
```

## Testing

Tests are located in `__tests__/` and can be run with Vitest:

```bash
# From the loa repository root
npx vitest run .claude/lib/beads/__tests__/
```

Test coverage includes:
- Security validation against injection payloads
- Path traversal attack prevention
- Label manipulation and state derivation
- Type safety verification

## Contributing

This module was extracted from production usage in loa-beauvoir. Contributions should:

1. Maintain zero external dependencies
2. Include comprehensive tests (especially security tests)
3. Follow existing TypeScript strict mode settings
4. Document security implications of changes

## License

MIT - See [LICENSE.md](../../LICENSE.md)
