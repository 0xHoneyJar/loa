# Session Continuity Protocol

> **Paradigm**: Clear, Don't Compact

## Purpose

Ensure zero information loss across context wipes (`/clear`), compaction events, and session boundaries. The context window is treated as a **disposable workspace**; State Zone artifacts are the **lossless ledgers**.

## Context Compaction Integration

This protocol integrates with Claude Code's client-side compaction feature.

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

Compaction survival is mechanical: `pre-compact-marker.sh` (PreCompact) + `post-compact-reminder.sh` (UserPromptSubmit) inject the recovery sequence — see `.claude/loa/reference/hooks-reference.md`.

---

## Truth Hierarchy

Order of authority, highest first: code (`src/`, verified by `ck`) > Beads (`.beads/` — lossless task graph, rationale, state) > `NOTES.md` (decision log, session continuity) > trajectory (audit trail, handoff records) > PRD/SDD (design intent, may drift) > legacy docs (historical, often stale) > the context window (transient, disposable, never authoritative). All claims must be grounded in code; nothing in transient context overrides an external ledger.

### Fork Detection

When context window state conflicts with ledger state, the ledger wins: log the discrepancy to trajectory, then re-read the authoritative state and resync from the ledger.

## Session Lifecycle

### Phase 1: Session Start (after /clear or a new session)

Recovery runs in order:

0. **Run mode first.** If `.run/sprint-plan-state.json` has `state: RUNNING`, resume `sprints.current` immediately — no interactive recovery, no confirmation.
1. `br ready` — identify available tasks.
2. `br show <active_id>` — load task context (`decisions[]`, `handoffs[]`).
3. Tiered Ledger Recovery — load `NOTES.md` (Level 1 by default).
4. Verify lightweight identifiers without loading their content yet.
5. Resume from the "Reasoning State" left at the last checkpoint.

#### Run Mode State Check

Before any interactive recovery, check for an active run:

```bash
if [[ -f .run/sprint-plan-state.json ]]; then
  state=$(jq -r '.state' .run/sprint-plan-state.json)
  if [[ "$state" == "RUNNING" ]]; then
    current=$(jq -r '.sprints.current' .run/sprint-plan-state.json)
    # Resume sprint $current without confirmation; skip normal recovery below
  fi
fi
```

This is what lets `/run sprint-plan` survive context compaction during unattended execution.

#### Tiered Ledger Recovery

| Level | Tokens | Trigger | Method |
|-------|--------|---------|--------|
| **1** | ≤ 20k | Default (all recoveries) | `notes-guard.sh read`: Blockers + newest Session Continuity + 3 newest Decision Logs, ≤ 68 KiB |
| **2** | ~200-500 | Task needs historical context | `ck --hybrid` for specific decisions |
| **3** | Full | User explicit request only | `notes-guard.sh read --full` |

**Level 1 Recovery** (default):
```bash
"${PROJECT_ROOT}/.claude/scripts/notes-guard.sh" read
```

**Level 2 Recovery** (on-demand):
```bash
ck --hybrid "authentication decision" "${PROJECT_ROOT}/grimoires/loa/" --top-k 3 --jsonl
```

**Level 3 Recovery** (explicit):
```bash
"${PROJECT_ROOT}/.claude/scripts/notes-guard.sh" read --full
```

### Phase 2: During Session

Continuous synthesis:

1. Write decisions to the NOTES.md Decision Log immediately.
2. Update the Bead's `decisions[]` array as work progresses.
3. Store lightweight identifiers (paths only).
4. Monitor the attention budget (advisory).
5. Run Delta-Synthesis at the Yellow threshold (5,000 tokens).

#### Delta-Synthesis Protocol

At the Yellow threshold, persist without clearing context: append findings to the Decision Log, update the active Bead's progress, and log a trajectory entry —

```yaml
phase: delta_sync
tokens: 5000
decisions_persisted: 3
bead_updated: true
notes_updated: true
timestamp: 2024-01-15T14:30:00Z
```

This exists so work survives a crash or unexpected session termination.

### Phase 3: Before /clear

Synthesis checkpoint, blocking in order:

1. Grounding verification (>= 0.95) — **blocking**.
2. Negative grounding / Ghost Features — **blocking** in strict mode.
3. Update the Decision Log with AST-aware evidence.
4. Update the Bead's `decisions[]` and `next_steps[]`.
5. Log a `session_handoff` trajectory entry.
6. Decay raw output to lightweight identifiers.
7. Verify EDD (3 test scenarios documented).

If any blocking step fails, `/clear` is rejected. See `.claude/protocols/synthesis-checkpoint.md` for the full checkpoint protocol.

## NOTES.md Session Continuity Section

The Session Continuity section in NOTES.md is the primary recovery artifact.

### Required Structure

```markdown
## Session Continuity
<!-- CRITICAL: Load this section FIRST after /clear (via notes-guard.sh read) -->

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

All paths use the `${PROJECT_ROOT}` prefix — relative and hardcoded absolute paths are both invalid:

```
VALID:   ${PROJECT_ROOT}/src/auth/jwt.ts:45
INVALID: src/auth/jwt.ts:45 (relative)
INVALID: ./src/auth/jwt.ts:45 (relative)
INVALID: /absolute/path/file.ts:45 (hardcoded)
```

## Bead Schema Extensions

Extended Bead fields for session continuity.

### Schema Overview

```yaml
# .beads/<id>.yaml - Extended schema
id: beads-x7y8
title: "Task description"
status: in_progress
priority: 2
created: 2024-01-15T10:00:00Z
assignee: null

# Decision history (append-only ledger)
decisions:
  - ts: 2024-01-15T10:30:00Z
    decision: "Use rotating refresh tokens"
    rationale: "Prevents token theft replay attacks"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/refresh.ts
        line: 12
        quote: "export async function rotateRefreshToken()"

# EDD test scenario requirements
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

# Session handoff chain (lineage tracking)
handoffs:
  - session_id: "sess-001"
    ended: 2024-01-15T12:00:00Z
    notes_ref: "grimoires/loa/NOTES.md:45-67"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-abc"
    grounding_ratio: 0.97

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

### Defaults

`decisions[]`, `test_scenarios[]`, and `handoffs[]` are all optional; a missing array is treated as empty.

### Fork Detection

When context and Bead state disagree, the Bead's `decisions[]` wins: log the conflict to trajectory, discard the conflicting context claim, and resync from the Bead.

```jsonl
{"ts":"2024-01-15T15:00:00Z","agent":"implementing-tasks","phase":"fork_detected","bead_id":"beads-x7y8","context_decision":"Use stateless tokens","bead_decision":"Use rotating refresh tokens","resolution":"bead_wins"}
```

### CLI Extensions (br commands)

Extended beads_rust CLI operations:

| Operation | Command | Purpose |
|-----------|---------|---------|
| View with decisions | `br show <id>` | Displays decisions[], handoffs[] |
| Append decision | `br comments add <id> "DECISION: ..."` | Adds to comment history |
| Log handoff | `br comments add <id> "HANDOFF: ..."` | Records session handoff |
| Check fork | `br diff <id>` | Compare context vs Bead state |

Comment convention: prefix with `DECISION:` (followed by `Rationale:` and `Evidence:` lines) or `HANDOFF:` (session, NOTES ref, trajectory ref, grounding ratio):

```bash
br comments add br-x7y8 "DECISION: Use RSA256 for JWT signing
Rationale: Industry standard, key rotation support
Evidence: ${PROJECT_ROOT}/src/auth/jwt.ts:23"
```

### Fallback When beads_rust Unavailable

If `br` is not installed, decision tracking falls back to NOTES.md:

```bash
if command -v br &>/dev/null; then
    br comments add "$BEAD_ID" "DECISION: $decision"
else
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
br sync --flush-only  # Export bead changes to JSONL
git add .beads/       # Stage for git
git commit -m "..."   # Commit with code changes
git push              # Push to remote
```

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| "I'll remember this" | Write to NOTES.md now |
| Trust compacted context | Trust only ledgers |
| Relative paths | Always `${PROJECT_ROOT}` absolute paths |
| Defer synthesis | Synthesize continuously |
| Reason without Bead | Always `br show` first |
| Eager load files | Store identifiers, JIT retrieve |
| `/clear` without checkpoint | Execute synthesis checkpoint first |
| Load full Decision Log | Level 1 recovery: last 3 decisions only |

## Integration Points

### Related Protocols

- **synthesis-checkpoint.md**: Pre-clear validation (blocking)
- **tool-result-clearing.md**: Clearing thresholds + NOTES.md synthesis discipline
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

1. User runs `/clear`.
2. `synthesis-checkpoint.sh` runs.
3. Grounding ratio >= 0.95.
4. No unverified ghosts.
5. Ledgers synced.
6. `/clear` executes.
7. Session Recovery: Level 1 (`notes-guard.sh read`, ≤ 68 KiB).
8. Resume from Reasoning State.

### Scenario 2: Session Crash

1. Session terminates unexpectedly.
2. Delta-synthesis may have run (Yellow threshold).
3. New session starts.
4. `br ready` identifies the in-progress task.
5. `br show <id>` loads `decisions[]`, `handoffs[]`.
6. NOTES.md Session Continuity gives the last checkpoint.
7. Resume from last known state.
8. Some work may be lost (since the last delta-sync).

### Scenario 3: Missing State Zone Files

1. Session starts.
2. NOTES.md is missing.
3. Self-heal: `git show HEAD:grimoires/loa/NOTES.md`.
4. If git fails: create from template.
5. Log the recovery to trajectory.
6. Continue operation — never halt.

## Configuration

See `.loa.config.yaml`:

```yaml
session_continuity:
  tiered_recovery: true     # Enable Level 1/2/3 recovery
  level1_tokens: 20000      # Level 1 = notes-guard.sh read (≤ 68 KiB)
  level2_tokens: 500        # Max tokens for Level 2 (ck --hybrid)
```
