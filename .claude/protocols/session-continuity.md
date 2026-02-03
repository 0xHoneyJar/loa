# Session Continuity Protocol

> **Version**: 1.1 (v0.11.0 Claude Platform Integration)
> **Paradigm**: Clear, Don't Compact

## Purpose

Ensure zero information loss across context wipes (`/clear`), compaction events, and session boundaries. The context window is treated as a **disposable workspace**; State Zone artifacts are the **lossless ledgers**.

## Context Compaction Integration (v0.11.0)

As of v0.11.0, this protocol integrates with Claude Code's client-side compaction feature.

### Compaction vs /clear

| Action | Trigger | Checkpoint | Recovery |
|--------|---------|------------|----------|
| `/compact` | User/Auto | Simplified (3-step) | Automatic (preserved content) |
| `/clear` | User | Full (7-step) | Tiered (Level 1/2/3) |

### Using context-manager.sh

```bash
# Check context status
.claude/scripts/context-manager.sh status

# Run pre-compaction check
.claude/scripts/context-manager.sh compact --dry-run

# Run simplified checkpoint before compaction
.claude/scripts/context-manager.sh checkpoint

# Recover after compaction (if needed)
.claude/scripts/context-manager.sh recover 1  # Level 1
.claude/scripts/context-manager.sh recover 2  # Level 2
.claude/scripts/context-manager.sh recover 3  # Level 3
```

### Compaction Preservation

Content that survives compaction (configured in `.loa.config.yaml`):

| Item | Status | Rationale |
|------|--------|-----------|
| NOTES.md Session Continuity | PRESERVED | Recovery anchor |
| NOTES.md Decision Log | PRESERVED | Audit trail |
| Trajectory entries | PRESERVED | External files |
| Active bead references | PRESERVED | Task continuity |
| Tool results | COMPACTED | Summarized |
| Thinking blocks | COMPACTED | Logged to trajectory |

See: `.claude/protocols/context-compaction.md` for full compaction protocol.

---

## Truth Hierarchy

```
IMMUTABLE TRUTH HIERARCHY:

1. CODE (src/)           ← ABSOLUTE truth, verified by ck
2. BEADS (.beads/)       ← Lossless task graph, rationale, state
3. NOTES.md              ← Decision log, session continuity
4. TRAJECTORY            ← Audit trail, handoff records
5. PRD/SDD               ← Design intent, may drift
6. LEGACY DOCS           ← Historical, often stale
7. CONTEXT WINDOW        ← TRANSIENT, disposable, never authoritative

CODE is the ABSOLUTE source of truth. All claims must be grounded in code.
CRITICAL: Nothing in transient context overrides external ledgers.
```

### Fork Detection

If context window state conflicts with ledger state:
1. **Ledger always wins** - External artifacts are source of truth
2. **Flag the fork** - Log discrepancy to trajectory
3. **Resync from ledger** - Re-read authoritative state

## Session Lifecycle

### Phase 1: Session Start (After /clear or New Session)

```
SESSION RECOVERY SEQUENCE:

0. Check Run Mode State              # NEW v1.27.0 - FIRST!
   - If .run/sprint-plan-state.json exists with state=RUNNING:
   - Resume autonomous execution WITHOUT confirmation
   - Skip interactive recovery, continue sprint loop
1. br ready                          # Identify available tasks
2. br show <active_id>               # Load task context (decisions[], handoffs[])
3. Tiered Ledger Recovery            # Load NOTES.md (Level 1 default)
4. Verify lightweight identifiers    # Don't load content yet
5. Resume from "Reasoning State"     # Continue where left off
```

#### Run Mode State Check (v1.27.0)

**CRITICAL**: Before any interactive recovery, check for active run mode:

```bash
# Step 0: Run mode takes precedence
if [[ -f .run/sprint-plan-state.json ]]; then
  state=$(jq -r '.state' .run/sprint-plan-state.json)
  if [[ "$state" == "RUNNING" ]]; then
    echo "Run mode active - resuming autonomous execution"
    current=$(jq -r '.sprints.current' .run/sprint-plan-state.json)
    # Continue sprint $current without user confirmation
    exit 0  # Skip normal recovery
  fi
fi
# Proceed with normal recovery if not in run mode
```

This ensures `/run sprint-plan` survives context compaction during overnight execution.

#### Tiered Ledger Recovery

| Level | Tokens | Trigger | Method |
|-------|--------|---------|--------|
| **1** | ~100 | Default (all recoveries) | Session Continuity section + last 3 decisions |
| **2** | ~200-500 | Task needs historical context | `ck --hybrid` for specific decisions |
| **3** | Full | User explicit request | Full NOTES.md read |

**Level 1 Recovery** (default):
```bash
# Load only Session Continuity section (~100 tokens)
head -50 "${PROJECT_ROOT}/grimoires/loa/NOTES.md" | grep -A 20 "## Session Continuity"
```

**Level 2 Recovery** (on-demand):
```bash
# Semantic search for specific context
ck --hybrid "authentication decision" "${PROJECT_ROOT}/grimoires/loa/" --top-k 3 --jsonl
```

**Level 3 Recovery** (explicit):
```bash
# Full read for architectural review
cat "${PROJECT_ROOT}/grimoires/loa/NOTES.md"
```

### Phase 2: During Session

```
CONTINUOUS SYNTHESIS:

1. Write decisions to NOTES.md Decision Log IMMEDIATELY
2. Update Bead decisions[] array as work progresses
3. Store lightweight identifiers (paths only)
4. Monitor attention budget (advisory)
5. Delta-Synthesis at Yellow threshold (5k tokens)
```

#### Delta-Synthesis Protocol

Triggered at Yellow threshold (5,000 tokens):

```yaml
# Trajectory log entry
phase: delta_sync
tokens: 5000
decisions_persisted: 3
bead_updated: true
notes_updated: true
timestamp: 2024-01-15T14:30:00Z
```

**Purpose**: Ensure work survives crashes or unexpected session termination.

**Actions**:
1. Append recent findings to NOTES.md Decision Log
2. Update active Bead with progress-to-date
3. Log trajectory: `{"phase":"delta_sync","tokens":5000,"decisions_persisted":N}`
4. DO NOT clear context yet - just persist

### Phase 3: Before /clear

```
SYNTHESIS CHECKPOINT (BLOCKING):

1. Grounding verification (>= 0.95)         ← BLOCKING
2. Negative grounding (Ghost Features)      ← BLOCKING in strict mode
3. Update Decision Log (AST-aware evidence)
4. Update Bead (decisions[], next_steps[])
5. Log trajectory session_handoff
6. Decay raw output -> lightweight identifiers
7. Verify EDD (3 test scenarios documented)

IF ANY BLOCKING STEP FAILS -> REJECT /clear
```

See: `.claude/protocols/synthesis-checkpoint.md` for detailed checkpoint protocol.

## NOTES.md Session Continuity Section

The Session Continuity section in NOTES.md is the primary recovery artifact.

### Required Structure

```markdown
## Session Continuity
<!-- CRITICAL: Load this section FIRST after /clear (~100 tokens) -->

### Active Context
- **Current Bead**: beads-x7y8 (task description)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Where we left off, what's next

### Lightweight Identifiers
<!-- Absolute paths only - retrieve full content on-demand -->
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation logic | 14:25:00Z |
| ${PROJECT_ROOT}/src/auth/refresh.ts:12-34 | Refresh flow | 14:28:00Z |

### Decision Log
<!-- Decisions survive context wipes - permanent record -->

#### 2024-01-15T14:30:00Z - Decision Title
**Decision**: What we decided
**Rationale**: Why we decided it
**Evidence**:
- `code quote` [${PROJECT_ROOT}/file.ts:line]
**Test Scenarios**:
1. Happy path scenario
2. Edge case scenario
3. Error handling scenario

### Pending Questions
<!-- Carry forward across sessions -->
- [ ] Open question 1
- [ ] Open question 2
```

### Path Requirements

**REQUIRED**: All paths must use `${PROJECT_ROOT}` prefix
```
VALID:   ${PROJECT_ROOT}/src/auth/jwt.ts:45
INVALID: src/auth/jwt.ts:45 (relative)
INVALID: ./src/auth/jwt.ts:45 (relative)
INVALID: /absolute/path/file.ts:45 (hardcoded)
```

## Bead Schema Extensions

Extended Bead fields for session continuity (v0.9.0 Lossless Ledger Protocol).

### Schema Overview

```yaml
# .beads/<id>.yaml - Extended schema
id: beads-x7y8
title: "Task description"
status: in_progress
priority: 2
created: 2024-01-15T10:00:00Z
assignee: null

# EXISTING FIELDS (unchanged)
# ...all standard Bead fields work as before...

# NEW v0.9.0: Decision history (append-only ledger)
decisions:
  - ts: 2024-01-15T10:30:00Z
    decision: "Use rotating refresh tokens"
    rationale: "Prevents token theft replay attacks"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/refresh.ts
        line: 12
        quote: "export async function rotateRefreshToken()"

  - ts: 2024-01-15T14:30:00Z
    decision: "Add 15-minute grace period"
    rationale: "Balance security with UX"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/jwt.ts
        line: 52
        quote: "export function isTokenExpired(token, graceMs = 900000)"

# NEW v0.9.0: EDD test scenario requirements
test_scenarios:
  - name: "Token expires at boundary"
    type: edge_case
    expected: "Grace period applies, no forced logout"

  - name: "Token expires beyond grace"
    type: happy_path
    expected: "Silent refresh triggered"

  - name: "Both tokens expired"
    type: error_handling
    expected: "Full re-authentication flow"

# NEW v0.9.0: Session handoff chain (lineage tracking)
handoffs:
  - session_id: "sess-001"
    ended: 2024-01-15T12:00:00Z
    notes_ref: "grimoires/loa/NOTES.md:45-67"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-abc"
    grounding_ratio: 0.97

  - session_id: "sess-002"
    ended: 2024-01-15T14:30:00Z
    notes_ref: "grimoires/loa/NOTES.md:68-92"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-def"
    grounding_ratio: 0.95

# Next steps (specific, actionable)
next_steps:
  - "Implement clock skew tolerance (±30 seconds)"
  - "Add refresh token blacklist for logout"

# Blockers and questions
blockers: []
questions:
  - "Should grace period be configurable per-client?"
```

### New Field Specifications

#### decisions[] Array

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | ISO 8601 | Yes | Timestamp of decision |
| `decision` | string | Yes | What was decided |
| `rationale` | string | Yes | Why it was decided |
| `evidence` | array | Yes | Code citations with quotes |
| `evidence[].path` | string | Yes | `${PROJECT_ROOT}/...` absolute path |
| `evidence[].line` | number | Yes | Line number |
| `evidence[].quote` | string | Yes | Word-for-word code quote |

#### test_scenarios[] Array

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Descriptive scenario name |
| `type` | enum | Yes | `happy_path`, `edge_case`, or `error_handling` |
| `expected` | string | Yes | Expected behavior/outcome |

**EDD Requirement**: Minimum 3 test scenarios before task completion.

#### handoffs[] Array

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | Yes | Unique session identifier |
| `ended` | ISO 8601 | Yes | Timestamp of session end |
| `notes_ref` | string | Yes | Line reference to NOTES.md |
| `trajectory_ref` | string | Yes | Reference to trajectory log entry |
| `grounding_ratio` | number | Yes | Grounding ratio at handoff (>= 0.95) |

### Backwards Compatibility

**All new fields are OPTIONAL and ADDITIVE**:

- Existing Beads without new fields continue to work
- Missing `decisions[]` treated as empty array
- Missing `test_scenarios[]` treated as empty array
- Missing `handoffs[]` treated as empty array

**Migration**: No migration required. New fields added on first update.

### Fork Detection

When context window state conflicts with Bead state:

```
FORK DETECTION PROTOCOL:
┌─────────────────────────────────────────────────────────────────┐
│ 1. Compare context's "decision" with Bead decisions[]           │
│                                                                  │
│ 2. IF CONFLICT DETECTED:                                         │
│    - Log to trajectory: {"phase":"fork_detected",...}           │
│    - Bead state wins (external ledger is authoritative)         │
│    - Notify agent: "Fork detected, resyncing from Bead"         │
│                                                                  │
│ 3. Resync from Bead:                                            │
│    - Re-read decisions[] array                                  │
│    - Discard conflicting context state                          │
│    - Continue from Bead state                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Trajectory log for fork**:
```jsonl
{"ts":"2024-01-15T15:00:00Z","agent":"implementing-tasks","phase":"fork_detected","bead_id":"beads-x7y8","context_decision":"Use stateless tokens","bead_decision":"Use rotating refresh tokens","resolution":"bead_wins"}
```

### CLI Extensions (br commands)

Extended beads_rust CLI operations for v0.19.0:

| Operation | Command | Purpose |
|-----------|---------|---------|
| View with decisions | `br show <id>` | Displays decisions[], handoffs[] |
| Append decision | `br comments add <id> "DECISION: ..."` | Adds to comment history |
| Log handoff | `br comments add <id> "HANDOFF: ..."` | Records session handoff |
| Check fork | `br diff <id>` | Compare context vs Bead state |

**Note**: CLI extensions are optional enhancements. NOTES.md provides fallback.

### beads_rust CLI Integration Examples

#### Display Decisions History

```bash
# Show bead with full decision history
br show br-x7y8

# Output includes:
#   id: br-x7y8
#   title: "Implement token refresh"
#   status: in_progress
#   comments:
#     - [2024-01-15T10:30:00Z] DECISION: Use rotating refresh tokens
#     - [2024-01-15T14:30:00Z] DECISION: Add 15-minute grace period
#   labels:
#     - sprint:3
#     - security-approved
```

#### Append Decision to Bead

```bash
# Add a new decision with evidence
br comments add br-x7y8 "DECISION: Use RSA256 for JWT signing
Rationale: Industry standard, key rotation support
Evidence: ${PROJECT_ROOT}/src/auth/jwt.ts:23"

# Decision is appended to comments, not replaced
```

#### Log Session Handoff

```bash
# Record session handoff when session ends
br comments add br-x7y8 "HANDOFF:
Session: sess-003
NOTES ref: grimoires/loa/NOTES.md:93-120
Trajectory: trajectory/impl-2024-01-15.jsonl:span-ghi
Grounding ratio: 0.96"
```

#### Check for Fork Detection

```bash
# Compare current context state with bead state
br diff br-x7y8

# Output if fork detected:
#   FORK DETECTED:
#   Context: "Use stateless tokens"
#   Bead: "Use rotating refresh tokens"
#   Resolution: Bead wins (external ledger is authoritative)
```

### Fallback When beads_rust Unavailable

If beads_rust CLI (`br`) is not installed, all decision tracking falls back to NOTES.md:

```bash
# Check if br is available
if command -v br &>/dev/null; then
    # Use beads_rust for decision tracking
    br comments add "$BEAD_ID" "DECISION: $decision"
else
    # Fallback: Append to NOTES.md Decision Log
    echo "#### $(date -u +%Y-%m-%dT%H:%M:%SZ) - $title" >> grimoires/loa/NOTES.md
    echo "**Decision**: $decision" >> grimoires/loa/NOTES.md
    echo "**Rationale**: $rationale" >> grimoires/loa/NOTES.md
fi
```

**Fallback Locations**:

| Bead Feature | Fallback Location |
|--------------|-------------------|
| decisions[] | NOTES.md ## Decision Log |
| handoffs[] | NOTES.md ## Session Continuity |
| test_scenarios[] | NOTES.md ## Test Scenarios |
| next_steps[] | NOTES.md ## Active Sub-Goals |

### br sync for Session End

Always run `br sync --flush-only` at session end to export Bead changes:

```bash
# Session end protocol
br sync --flush-only  # Export bead changes to JSONL
git add .beads/       # Stage for git
git commit -m "..."   # Commit with code changes
git push              # Push to remote
```

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| "I'll remember this" | Write to NOTES.md **NOW** |
| Trust compacted context | Trust only **ledgers** |
| Relative paths | ALWAYS `${PROJECT_ROOT}` absolute paths |
| Defer synthesis | Synthesize **continuously** |
| Reason without Bead | ALWAYS `br show` first |
| Eager load files | Store **identifiers**, JIT retrieve |
| `/clear` without checkpoint | Execute **synthesis checkpoint** first |
| Load full Decision Log | Level 1 recovery: **last 3 decisions only** |

## Integration Points

### Protocol Dependency Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│              v0.11.0 LOSSLESS LEDGER PROTOCOL DEPENDENCIES                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  SESSION-CONTINUITY (Core Protocol)                                        │
│       │                                                                    │
│       ├──▶ CONTEXT-COMPACTION (v0.11.0 - Compaction rules)                │
│       │         │                                                          │
│       │         └──▶ Preservation rules, simplified checkpoint            │
│       │                                                                    │
│       ├──▶ SYNTHESIS-CHECKPOINT (Pre-clear validation)                    │
│       │         │                                                          │
│       │         ├──▶ GROUNDING-ENFORCEMENT (Citation verification)        │
│       │         │         │                                                │
│       │         │         └──▶ TRAJECTORY-EVALUATION (Claim logging)      │
│       │         │                                                          │
│       │         └──▶ NEGATIVE-GROUNDING (Ghost feature verification)      │
│       │                                                                    │
│       ├──▶ ATTENTION-BUDGET (Token monitoring - ADVISORY)                 │
│       │         │                                                          │
│       │         └──▶ Delta-Synthesis trigger at Yellow threshold           │
│       │                                                                    │
│       ├──▶ JIT-RETRIEVAL (Token-efficient evidence)                       │
│       │         │                                                          │
│       │         └──▶ ck integration / grep fallback                       │
│       │                                                                    │
│       └──▶ STRUCTURED-MEMORY (NOTES.md protocol)                          │
│                 │                                                          │
│                 └──▶ Decision Log, Session Continuity section             │
│                                                                            │
│  SCRIPTS                                                                   │
│  ├── context-manager.sh ───── manages ──▶ compaction, checkpoint          │
│  ├── synthesis-checkpoint.sh ─ calls ───▶ grounding-check.sh              │
│  ├── grounding-check.sh ────── reads ───▶ trajectory/*.jsonl              │
│  └── self-heal-state.sh ────── recovers ▶ State Zone files                │
│                                                                            │
│  FLOW:                                                                     │
│  Session Start ──▶ self-heal-state.sh (if needed)                         │
│       │                                                                    │
│       ▼                                                                    │
│  Work (with JIT retrieval, trajectory logging)                             │
│       │                                                                    │
│       ▼ (Yellow threshold)                                                 │
│  Delta-Synthesis (partial persist)                                         │
│       │                                                                    │
│       ├──▶ (User: /compact)                                                │
│       │    context-manager.sh checkpoint (simplified 3-step)               │
│       │    │                                                               │
│       │    ▼ (PASS)                                                        │
│       │    Compaction with preservation rules                              │
│       │                                                                    │
│       └──▶ (User: /clear)                                                  │
│            synthesis-checkpoint.sh ──▶ grounding-check.sh                  │
│            │                                                               │
│            ▼ (PASS)                                                        │
│            Context cleared, Level 1 Recovery (~100 tokens)                 │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Related Protocols

- **context-compaction.md**: Compaction preservation rules (v0.11.0)
- **synthesis-checkpoint.md**: Pre-clear validation (BLOCKING)
- **jit-retrieval.md**: Lightweight identifier handling
- **attention-budget.md**: Token threshold monitoring
- **grounding-enforcement.md**: Citation quality verification
- **trajectory-evaluation.md**: Handoff logging

### Commands

- **/ride**: Session-aware initialization (`br ready` -> `br show`)
- **/clear**: Triggers synthesis checkpoint

### Scripts

- `synthesis-checkpoint.sh`: Pre-clear validation
- `grounding-check.sh`: Ratio calculation
- `self-heal-state.sh`: State Zone recovery

## Recovery Scenarios

### Scenario 1: Clean /clear

```
1. User: /clear
2. Hook: synthesis-checkpoint.sh
3. Grounding ratio >= 0.95 ✓
4. No unverified ghosts ✓
5. Ledgers synced ✓
6. /clear executes
7. Session Recovery: Level 1 (~100 tokens)
8. Resume from Reasoning State
```

### Scenario 2: Session Crash

```
1. Session terminates unexpectedly
2. Delta-synthesis may have run (Yellow threshold)
3. New session starts
4. br ready -> identify in-progress task
5. br show <id> -> load decisions[], handoffs[]
6. NOTES.md Session Continuity -> last checkpoint
7. Resume from last known state
8. Some work may be lost (since last delta-sync)
```

### Scenario 3: Missing State Zone Files

```
1. Session starts
2. NOTES.md missing
3. Self-healing: git show HEAD:grimoires/loa/NOTES.md
4. If git fails: Create from template
5. Log recovery to trajectory
6. Continue operation (never halt)
```

## Configuration

See `.loa.config.yaml`:

```yaml
session_continuity:
  tiered_recovery: true     # Enable Level 1/2/3 recovery
  level1_tokens: 100        # Max tokens for Level 1
  level2_tokens: 500        # Max tokens for Level 2
```

---

**Document Version**: 1.1
**Protocol Version**: v2.3 (Claude Platform Integration)
**Paradigm**: Clear, Don't Compact
