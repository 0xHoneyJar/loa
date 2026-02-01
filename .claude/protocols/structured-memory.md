# Structured Agentic Memory Protocol (NOTES.md)

> Inspired by Anthropic's research on long-horizon agent performance.
> Enhanced in v0.16.0 with required sections and agent discipline.

## Purpose

Agents lose critical context after:
- Context window resets
- Compaction cycles
- Session boundaries
- Tool-heavy operations

The **NOTES.md** file provides persistent working memory that survives these events.

## Location

```
grimoires/loa/NOTES.md
```

## Required Sections (v0.16.0)

Every NOTES.md **MUST** contain these sections:

| Section | Purpose | Format |
|---------|---------|--------|
| Current Focus | Active task and status | Structured fields |
| Session Log | Append-only event history | Table |
| Decisions | Architecture and implementation decisions | Table |
| Blockers | External dependencies and obstacles | Checkbox list |
| Technical Debt | Discovered issues for future attention | Table |
| Learnings | Project-specific knowledge | Bullet list |

### Section Specifications

#### Current Focus

```markdown
## Current Focus

- **Active Task**: [Task ID] - [Description]
- **Status**: [Not Started | In Progress | Blocked | Complete]
- **Blocked By**: [Blocker description or "None"]
- **Next Action**: [Specific next step to take]
```

#### Session Log

```markdown
## Session Log

<!-- Append-only - never delete entries -->

| Timestamp | Event | Outcome |
|-----------|-------|---------|
| 2024-01-15T14:30:00Z | Started implementing auth flow | In progress |
| 2024-01-15T15:45:00Z | Hit rate limit on OAuth provider | Switched to mock |
| 2024-01-15T16:30:00Z | Completed unit tests | 12 tests passing |
```

#### Decisions

```markdown
## Decisions

| Date | Decision | Rationale | Decided By |
|------|----------|-----------|------------|
| 2024-01-08 | Use PostgreSQL over MySQL | pgvector support for embeddings | designing-architecture |
| 2024-01-09 | JWT over sessions | Stateless scaling requirement | designing-architecture |
```

#### Blockers

```markdown
## Blockers

<!-- Use [RESOLVED] prefix when resolved -->
- [ ] Waiting for OAuth provider credentials (ETA: 2024-01-15)
- [ ] Blocked on legal review for payments
- [x] [RESOLVED] API rate limiting issue - fixed with exponential backoff
```

#### Technical Debt

```markdown
## Technical Debt

| ID | Description | Severity | Found By | Sprint |
|----|-------------|----------|----------|--------|
| TD-001 | N+1 query in user list endpoint | MEDIUM | implementing-tasks | S03 |
| TD-002 | Missing input validation on /api/upload | HIGH | auditing-security | S03 |
```

#### Learnings

```markdown
## Learnings

<!-- Project-specific knowledge discovered during implementation -->
- OAuth provider requires specific callback URL format: `https://domain/auth/callback`
- Database migrations must run in order; skip-migration flag breaks referential integrity
- Rate limits reset at UTC midnight, not rolling 24h
```

## Agent Discipline (v0.16.0)

Agents MUST update NOTES.md at these points:

| Event | Action | Section(s) to Update |
|-------|--------|---------------------|
| Session start | Load context, update timestamp | Session Log |
| Decision made | Log decision with rationale | Decisions, Session Log |
| Blocker hit | Document blocker | Blockers, Current Focus |
| Blocker resolved | Mark with [RESOLVED] | Blockers, Session Log |
| Session end | Summarize accomplishments | Session Log, Current Focus |
| Mistake discovered | Document as learning | Learnings, Technical Debt |
| Technical debt found | Log for future attention | Technical Debt |

## Full Structure Example

```markdown
# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.
> Updated automatically by agents. Manual edits are preserved.

## Current Focus

- **Active Task**: Sprint-3 Task 3.2 - Implement security-scanner.md
- **Status**: In Progress
- **Blocked By**: None
- **Next Action**: Add cryptography checks section

## Session Log

| Timestamp | Event | Outcome |
|-----------|-------|---------|
| 2024-01-15T14:30:00Z | Started Sprint-3 implementation | In progress |
| 2024-01-15T15:00:00Z | Completed Task 3.1 | architecture-validator created |
| 2024-01-15T15:45:00Z | Decision: Use 4 severity levels | CRITICAL/HIGH/MEDIUM/LOW |

## Decisions

| Date | Decision | Rationale | Decided By |
|------|----------|-----------|------------|
| 2024-01-08 | Use PostgreSQL over MySQL | pgvector support for embeddings | designing-architecture |
| 2024-01-15 | 4 security severity levels | Aligns with CVE classification | implementing-tasks |

## Blockers

- [ ] Waiting for OAuth provider credentials (ETA: 2024-01-15)
- [x] [RESOLVED] Rate limit issue - switched to exponential backoff

## Technical Debt

| ID | Description | Severity | Found By | Sprint |
|----|-------------|----------|----------|--------|
| TD-001 | N+1 query in user list endpoint | MEDIUM | implementing-tasks | S03 |

## Learnings

- Security scanner should run before code review, not after
- BATS tests need absolute paths for PROJECT_ROOT

## Session Continuity
<!-- CRITICAL: Load this section FIRST after /clear (~100 tokens) -->
<!-- See: .claude/protocols/session-continuity.md -->

### Active Context
- **Current Bead**: beads-x7y8 (Sprint-3 Implementation)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Completed Task 3.1, starting Task 3.2

### Lightweight Identifiers
<!-- Absolute paths only - retrieve full content on-demand via JIT -->
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/.claude/subagents/security-scanner.md | Security scanner subagent | 15:45:00Z |

### Pending Questions
<!-- Carry forward across sessions -->
- [ ] Should severity levels be configurable per-project?
```

## Session Continuity Section (v0.9.0)

> **Protocol**: See `.claude/protocols/session-continuity.md`
> **Paradigm**: Clear, Don't Compact

The Session Continuity section is loaded **FIRST** after `/clear` (~100 tokens for Level 1 recovery).

### Required Components

| Component | Purpose | Token Budget |
|-----------|---------|--------------|
| Active Context | Current task, checkpoint, reasoning state | ~30 tokens |
| Lightweight Identifiers | Path references (JIT retrieval) | ~15 tokens each |
| Decision Log (last 3) | Recent decisions with evidence | ~50 tokens |
| Pending Questions | Carry-forward items | ~10 tokens |

### Path Requirements

**REQUIRED**: All paths must use `${PROJECT_ROOT}` prefix for session-survival.

```
VALID:   ${PROJECT_ROOT}/src/auth/jwt.ts:45
INVALID: src/auth/jwt.ts:45 (relative)
INVALID: ./src/auth/jwt.ts:45 (relative)
```

### Decision Log Entry Format

Each decision entry MUST include:
1. **Timestamp** - ISO 8601 format
2. **Decision** - What was decided
3. **Rationale** - Why it was decided
4. **Evidence** - Word-for-word code quote with absolute path
5. **Test Scenarios** - 3 scenarios (happy path, edge case, error handling)

### Tiered Recovery Levels

| Level | Tokens | When Used | What's Loaded |
|-------|--------|-----------|---------------|
| 1 | ~100 | Default (all /clear) | Session Continuity section + last 3 decisions |
| 2 | ~500 | Task needs history | ck --hybrid for specific decisions |
| 3 | Full | User explicit request | Entire NOTES.md |

## Agent Responsibilities

### On Session Start
1. Read `NOTES.md` to restore context
2. Check for blockers that may have resolved
3. Update "Session Continuity" with current timestamp

### During Execution
1. Log significant decisions to "Decision Log"
2. Add discovered technical debt immediately
3. Update sub-goal status as work progresses

### On Session End / Before Compaction
1. Summarize session accomplishments in "Session Continuity"
2. Ensure all blockers are documented
3. Flag any incomplete work

### After Tool-Heavy Operations
1. Summarize tool outputs (don't retain raw data)
2. Note any new technical debt discovered
3. Update sub-goals if affected

## Integration with Beads

When technical debt is discovered:
1. Log to NOTES.md immediately
2. Create a corresponding Bead if actionable:
   ```bash
   br create --priority medium --title "Fix N+1 query in user list" --ref "TD-001"
   ```

## Why This Matters

Without structured memory:
- Agents "forget" blockers and repeat failed approaches
- Technical debt accumulates silently
- Session context is lost, causing redundant work
- Decision rationale disappears, leading to contradictory choices

With NOTES.md:
- Continuity across context boundaries
- Explicit tracking of all known issues
- Auditable decision trail
- Reduced hallucination (agents consult notes, not "recall")

---

## Tool Result Clearing (Attention Budget Management)

> Context is a finite resource. Raw tool outputs consume attention that should be reserved for reasoning.

### The Problem

Tool-heavy operations generate massive outputs:
- `grep` searches returning 500+ lines
- `tree` commands showing entire directory structures
- `cat` of large files
- API responses with verbose JSON

These outputs remain in the context window, consuming tokens that could be used for reasoning, planning, and synthesis.

### The Protocol: Semantic Memory Decay

Once a tool result has been **synthesized** into permanent storage, the raw output must be **semantically decayed** (summarized and cleared).

#### Step 1: Synthesize
Extract the meaningful information and write it to a permanent location:
- Key findings -> `NOTES.md` (Technical Debt, Decision Log)
- Structural info -> `grimoires/loa/discovery/`
- Action items -> Beads

#### Step 2: Summarize
Replace the raw output with a one-line summary in your reasoning:

```
# BEFORE (500 tokens in context)
[Full grep output: 47 matches across 12 files...]

# AFTER (30 tokens in context)
"Found 47 AuthService references across 12 files. Key locations logged to NOTES.md."
```

#### Step 3: Clear
Mentally release the raw data. Do not reference specific lines from the original output - use your synthesized notes instead.

### When to Apply

| Operation | Trigger for Decay |
|-----------|-------------------|
| `grep`/`rg` with >20 results | After logging key locations |
| `cat` of file >100 lines | After extracting relevant sections |
| `tree` output | After documenting structure in discovery/ |
| API/tool JSON responses | After parsing needed fields |
| Test run output | After logging pass/fail summary |

### Attention Budget Heuristic

Think of your context window as a **budget**:
- **High-value tokens**: Reasoning, planning, user requirements, grounded citations
- **Low-value tokens**: Raw tool outputs that have already been processed

**Goal**: Maximize high-value token density by aggressively decaying low-value tokens.

### Example Workflow

```
1. Run: rg "TODO" --type ts
   -> Returns 89 matches (800 tokens)

2. Synthesize to NOTES.md:
   ## Discovered Technical Debt
   | ID | Description | File | Line |
   | TD-012 | Missing error handling | api/auth.ts | 45 |
   | TD-013 | Deprecated API usage | lib/http.ts | 112 |
   [... 8 more entries ...]

3. Summarize in context:
   "Found 89 TODOs. 10 high-priority items logged to NOTES.md Technical Debt section."

4. Continue reasoning with full attention budget restored.
```

### Integration with Compaction

Tool Result Clearing is **lightweight compaction** that happens continuously, not just at thresholds. It complements the sprint-level compaction that occurs after N closed tasks.

| Type | Trigger | Scope |
|------|---------|-------|
| Tool Result Clearing | After each tool-heavy operation | Single tool output |
| Sprint Compaction | After N closed tasks | Entire sprint context |
| Session End Summary | Before context reset | Full session |
