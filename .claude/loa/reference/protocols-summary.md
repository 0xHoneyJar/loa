# Protocols Summary

Quick reference for Loa's key protocols. See individual files in `.claude/protocols/` for full documentation.

## Structured Agentic Memory

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:

| Section | Purpose |
|---------|---------|
| Current Focus | Active task, status, blocked by, next action |
| Session Log | Append-only event history table |
| Decisions | Architecture/implementation decisions table |
| Blockers | Checkbox list with [RESOLVED] marking |
| Technical Debt | Issues for future attention |
| Goal Status | PRD goal achievement tracking |
| Learnings | Project-specific knowledge |
| Session Continuity | Recovery anchor |

**Protocol**: `.claude/protocols/structured-memory.md`

---

## Lossless Ledger Protocol

The "Clear, Don't Compact" paradigm for context management.

### Truth Hierarchy

1. CODE (src/) - Absolute truth
2. BEADS (.beads/) - Lossless task graph
3. NOTES.md - Decision log, session continuity
4. TRAJECTORY - Audit trail, handoffs
5. PRD/SDD - Design intent

### Key Protocols

| Protocol | Purpose |
|----------|---------|
| `session-continuity.md` | Tiered recovery, fork detection |
| `grounding-enforcement.md` | Citation requirements (>=0.95 ratio) |
| `synthesis-checkpoint.md` | Pre-clear validation |
| `jit-retrieval.md` | Lightweight identifiers + cache integration |

---

## Feedback Loops

Three quality gates:

1. **Implementation Loop** (Phase 4-5): Engineer <-> Senior Lead until "All good"
2. **Security Audit Loop** (Phase 5.5): After approval -> Auditor review -> "APPROVED"
3. **Deployment Loop**: DevOps <-> Auditor until infrastructure approved

**Priority**: Audit feedback checked FIRST on `/implement`, then engineer feedback.

**Protocol**: `.claude/protocols/feedback-loops.md`

---

## Karpathy Principles (v1.8.0)

Four behavioral principles to counter common LLM coding pitfalls:

| Principle | Problem Addressed | Implementation |
|-----------|-------------------|----------------|
| **Think Before Coding** | Silent assumptions | Surface assumptions, ask clarifying questions |
| **Simplicity First** | Overcomplicated code | No speculative features, minimal abstractions |
| **Surgical Changes** | Unrelated modifications | Only touch necessary lines, preserve style |
| **Goal-Driven** | Vague success criteria | Define testable outcomes before starting |

### Pre-Implementation Checklist

- [ ] Assumptions listed
- [ ] Scope minimal (no extras)
- [ ] Success criteria defined
- [ ] Style will match existing

**Protocol**: `.claude/protocols/karpathy-principles.md`

---

## Git Safety

Prevents accidental pushes to upstream template:

- 4-layer detection (cached -> origin URL -> upstream remote -> GitHub API)
- Soft block with user confirmation via AskUserQuestion
- `/contribute` command bypasses (has own safeguards)

**Protocol**: `.claude/protocols/git-safety.md`

---

## beads_rust Integration

Optional task graph management using beads_rust (`br` CLI). Non-invasive by design:

- Never touches git (no daemon, no auto-commit)
- Explicit sync protocol
- SQLite for fast queries, JSONL for git-friendly diffs

**Sync Protocol**:
```bash
br sync --import-only    # Session start
br sync --flush-only     # Session end
```

---

## All Protocol Files

| File | Description |
|------|-------------|
| `structured-memory.md` | NOTES.md protocol |
| `trajectory-evaluation.md` | ADK-style evaluation |
| `feedback-loops.md` | Quality gates |
| `git-safety.md` | Template protection |
| `constructs-integration.md` | Loa Constructs skill loading |
| `helper-scripts.md` | Full script documentation |
| `upgrade-process.md` | Framework upgrade workflow |
| `context-compaction.md` | Compaction preservation rules |
| `run-mode.md` | Run Mode protocol |
| `recursive-context.md` | Recursive JIT Context system |
| `semantic-cache.md` | Cache operations and invalidation |
| `jit-retrieval.md` | JIT retrieval with cache integration |
| `continuous-learning.md` | Skill extraction quality gates |
| `context-editing.md` | Context editing policies |
| `memory.md` | Memory schema and lifecycle |
| `karpathy-principles.md` | LLM coding principles |
| `recommended-hooks.md` | Claude Code hooks |
| `skill-forking.md` | Skill isolation |
| `url-registry.md` | Canonical URL management |
| `visual-communication.md` | Mermaid integration |
