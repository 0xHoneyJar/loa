# Structured Agentic Memory Protocol (NOTES.md)

> Inspired by Anthropic's research on long-horizon agent performance.

## Purpose

Agents lose critical context after:
- Context window resets
- Compaction cycles
- Session boundaries
- Tool-heavy operations

The **NOTES.md** file provides persistent working memory that survives these events.

## Location

```
loa-grimoire/NOTES.md
```

## Structure

```markdown
# Agent Working Memory (NOTES.md)

## Active Sub-Goals
<!-- Current objectives being pursued across sessions -->
- [ ] Implement authentication flow (blocking: waiting on OAuth provider setup)
- [ ] Refactor database layer (depends on: migration script approval)

## Discovered Technical Debt
<!-- Issues found during implementation that need future attention -->
| ID | Description | Severity | Found By | Sprint |
|----|-------------|----------|----------|--------|
| TD-001 | N+1 query in user list endpoint | MEDIUM | implementing-tasks | S03 |
| TD-002 | Missing input validation on /api/upload | HIGH | auditing-security | S03 |

## Blockers & Dependencies
<!-- External factors affecting progress -->
- Waiting: OAuth provider credentials (ETA: 2024-01-15)
- Blocked: Cannot proceed with payments until legal review complete

## Session Continuity
<!-- Key context to restore on next session -->
| Timestamp | Agent | Summary |
|-----------|-------|---------|
| 2024-01-10T14:30Z | implementing-tasks | Completed user auth, starting OAuth integration |
| 2024-01-10T16:45Z | reviewing-code | Flagged 3 issues in PR #42, awaiting fixes |

## Decision Log
<!-- Major decisions with rationale for future reference -->
| Date | Decision | Rationale | Decided By |
|------|----------|-----------|------------|
| 2024-01-08 | Use PostgreSQL over MySQL | pgvector support for embeddings | designing-architecture |
| 2024-01-09 | JWT over sessions | Stateless scaling requirement | designing-architecture |
```

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
   bd add --priority medium --title "Fix N+1 query in user list" --ref "TD-001"
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
- Structural info -> `loa-grimoire/discovery/`
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
