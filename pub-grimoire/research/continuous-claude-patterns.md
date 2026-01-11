# Continuous-Claude-v3 Pattern Analysis

**Research Date**: 2026-01-12
**Source**: https://github.com/parcadei/Continuous-Claude-v3
**Branch**: `research/continuous-claude-patterns`

## Executive Summary

Continuous-Claude-v3 is a comprehensive Claude Code framework with **109 skills, 32 agents, and 30 hooks**. Several patterns align with and extend Loa's existing architecture. This document analyzes applicable patterns for potential adoption.

---

## 1. Handoff System (High Value)

### Pattern Description

YAML-based structured handoffs that preserve session state for cross-session continuity.

**Key Features**:
- **~400 tokens** vs ~2000 for markdown (token-efficient)
- Standardized fields: `goal:`, `now:`, `done_this_session:`, `blockers:`, `decisions:`, `findings:`
- Session outcome tracking: `SUCCEEDED`, `PARTIAL_PLUS`, `PARTIAL_MINUS`, `FAILED`
- File-based storage in `thoughts/shared/handoffs/{session-name}/`

**Example Structure**:
```yaml
---
session: auth-refactor
date: 2026-01-12
status: complete|partial|blocked
outcome: SUCCEEDED|PARTIAL_PLUS|PARTIAL_MINUS|FAILED
---

goal: {What this session accomplished - shown in statusline}
now: {What next session should do first - shown in statusline}
test: {Command to verify this work}

done_this_session:
  - task: {First completed task}
    files: [{file1.py}, {file2.py}]

blockers: [{any blocking issues}]
questions: [{unresolved questions}]

decisions:
  - {decision_name}: {rationale}

findings:
  - {key_finding}: {details}

worked: [{approaches that worked}]
failed: [{approaches that failed and why}]

next:
  - {First next step}
  - {Second next step}
```

### Applicability to Loa

**Alignment**: Loa already has `NOTES.md` for structured agentic memory. The handoff pattern is complementary but more granular.

**Potential Integration**:
| Loa Concept | Continuous-Claude Concept | Integration |
|-------------|---------------------------|-------------|
| `NOTES.md` | Continuity Ledger | Merge - NOTES.md could adopt ledger section format |
| Sprint feedback | Session outcomes | Add outcome tracking to sprint completion |
| Trajectory logs | Handoff files | Handoffs could supplement trajectories |

**Recommendation**: **Medium priority** - Consider adopting YAML handoff format for `/implement` sessions. The `worked:` and `failed:` fields are especially valuable for agent learning.

---

## 2. Pre-Mortem Risk Analysis (High Value)

### Pattern Description

Structured risk identification before implementation using Gary Klein's pre-mortem technique.

**Risk Categories**:
| Category | Symbol | Meaning |
|----------|--------|---------|
| **Tiger** | `[TIGER]` | Real threat that will hurt if not addressed |
| **Paper Tiger** | `[PAPER]` | Looks threatening but probably fine |
| **Elephant** | `[ELEPHANT]` | Thing nobody wants to talk about |

**Key Innovation**: Two-pass verification to prevent false positives:
1. **Pass 1**: Pattern-matching to identify potential risks
2. **Pass 2**: Verify each potential risk by reading context, checking for mitigations

**Verification Checklist**:
```yaml
verification:
  context_read: true    # Read ±20 lines around finding
  fallback_check: true  # Check for try/except, if exists(), else branch
  scope_check: true     # Is this in scope?
  dev_only_check: true  # Is this in tests/dev-only code?
```

### Applicability to Loa

**Alignment**: Loa's security auditor already does risk analysis, but lacks the Tiger/Paper Tiger/Elephant framework.

**Potential Integration**:
- Add `/premortem` command for pre-implementation risk analysis
- Integrate with `/architect` phase for design validation
- Use in `/audit-sprint` for structured risk categorization

**Recommendation**: **High priority** - The verification checklist pattern would reduce false positives in Loa's security audits.

---

## 3. Continuity Ledger (Medium Value)

### Pattern Description

A lightweight state section that survives `/clear` commands by living in external files.

**Philosophy**: "Clear > Compact" - Fresh context beats degraded context after multiple compactions.

**Key Sections**:
```markdown
## Ledger
**Updated:** <timestamp>
**Goal:** <one-liner success criteria>
**Branch:** <branch>
**Test:** <test command>

### Now
[->] <current focus - ONE thing only>

### This Session
- [x] <completed items>

### Next
- [ ] <upcoming priorities>

### Decisions
- <decision>: <rationale>

### Workflow State
pattern: [workflow pattern name]
phase: [current phase number]
retries: 0
max_retries: 3
```

**Checkpoint System** for resumable workflows:
```markdown
### Checkpoints
**Agent:** kraken
**Task:** Replace JWT auth with session-based auth
**Started:** 2025-01-15T10:00:00Z

#### Phase Status
- Phase 1: ✓ VALIDATED
- Phase 2: → IN_PROGRESS
- Phase 3: ○ PENDING

#### Validation State
{
  "test_count": 15,
  "tests_passing": 15,
  "files_modified": [...],
  "last_test_command": "pytest tests/",
  "last_test_exit_code": 0
}
```

### Applicability to Loa

**Alignment**: Loa's `NOTES.md` serves a similar purpose but lacks:
- The `[->] current focus` single-item constraint
- Checkpoint/phase status tracking
- Validation state JSON

**Potential Integration**:
- Enhance `NOTES.md` with checkpoint tracking
- Add validation state to sprint tracking
- Consider `[->]` syntax for "Now" focus

**Recommendation**: **Medium priority** - The checkpoint system would improve long-running sprint continuity.

---

## 4. Session Hooks Architecture (High Value)

### Pattern Description

Python hooks that manage session lifecycle:

**`session_start_continuity.py`** (~30KB):
- Loads handoff context at session start
- Starts TLDR daemon for fast code search
- Starts memory daemon for learning extraction
- Terminal PID tracking for session affinity
- Cleans up orphaned processes

**`pre_compact_continuity.py`** (~15KB):
- Parses transcript JSONL before compaction
- Auto-generates handoff from transcript
- Extracts: todos, recent tool calls, files modified, errors
- Appends brief summary to ledger

**Key Pattern**: Hooks are Python (not bash) for complex logic with JSON I/O.

### Applicability to Loa

**Alignment**: Loa uses bash scripts in `.claude/scripts/`. The hook architecture is more sophisticated.

**Potential Integration**:
| Loa Script | Could Adopt | Benefit |
|------------|-------------|---------|
| `synthesis-checkpoint.sh` | pre_compact pattern | Auto-extract state before clear |
| `context-manager.sh` | session_start pattern | Auto-load context on resume |
| N/A | Terminal PID affinity | Multi-terminal session tracking |

**Recommendation**: **High priority** - Adopt transcript parsing for automatic state extraction before `/clear`.

---

## 5. Memory System (Future Consideration)

### Pattern Description

PostgreSQL + pgvector database for cross-session learning:

**Components**:
- `memory_daemon.py` - Monitors stale sessions, extracts learnings
- `extract_thinking_blocks.py` - Parses Claude's thinking for insights
- `store_learning.py` - Stores learnings with embeddings
- `recall_learnings.py` - Vector search for relevant past learnings

**Schema** (`artifact_schema.sql`):
- `handoffs` table with session tracking
- `learnings` table with embeddings
- `instance_sessions` for terminal-to-session mapping

### Applicability to Loa

**Alignment**: Loa uses file-based state (grimoire). Database approach is more powerful but heavier.

**Recommendation**: **Low priority** - Too complex for current Loa scope. Consider for v2.0 if demand exists.

---

## 6. Agent Architecture (Reference)

### Pattern Description

32+ specialized agents with JSON config + markdown instructions:

| Agent | Role |
|-------|------|
| `kraken` | TDD implementation with phase checkpoints |
| `phoenix` | Recovery from failed implementations |
| `scout` | Internal codebase research |
| `oracle` | External research (web search) |
| `architect` | System design |
| `aegis` | Security review |
| `maestro` | Meta-agent that orchestrates others |

**Structure**:
```
.claude/agents/
├── kraken.json   # Metadata: tools, triggers
└── kraken.md     # Full instructions
```

**JSON Config**:
```json
{
  "name": "kraken",
  "description": "TDD implementation agent",
  "tools": ["Bash", "Read", "Edit", "Write"],
  "triggers": ["implement", "tdd", "test-first"]
}
```

### Applicability to Loa

**Alignment**: Loa has 8 skills with 3-level architecture. Continuous-Claude's agent system is similar but with:
- JSON config alongside markdown
- Explicit tool restrictions
- Natural language triggers

**Potential Integration**:
- Add `triggers` to Loa's `index.yaml` for skill activation hints
- Consider tool restrictions per skill

**Recommendation**: **Low priority** - Current Loa skill architecture is sufficient.

---

## 7. TLDR Code Analysis (High Value)

### Pattern Description

5-layer static analysis for **95% token reduction** when understanding code:

| Layer | Analysis Type | Purpose |
|-------|---------------|---------|
| AST | Abstract Syntax Tree | Structure extraction |
| Call Graph | Function relationships | Dependency mapping |
| CFG | Control Flow Graph | Execution paths |
| DFG | Data Flow Graph | Variable tracking |
| PDG | Program Dependency Graph | Combined dependencies |

**Daemon Architecture**:
- Background daemon indexes codebase
- Queries return structured summaries instead of raw code
- Semantic search with FAISS/pgvector

**Impact Analysis**:
```bash
tldr impact src/auth/login.py  # Who calls this? What does it call?
```

### Applicability to Loa

**Alignment**: Loa uses `ck` (optional) for semantic search. TLDR is more comprehensive.

**Potential Integration**:
- Replace/supplement `ck` with TLDR approach
- Add daemon for background indexing
- Implement impact analysis for change validation

**Recommendation**: **Medium priority** - The call graph and impact analysis would significantly improve change validation in `/implement`.

---

## Prioritized Recommendations

### High Priority (Consider for v0.12.0)

1. **Pre-Mortem Risk Framework**
   - Add Tiger/Paper Tiger/Elephant categorization to security audits
   - Implement two-pass verification to reduce false positives
   - New command: `/premortem` or integrate into `/architect`

2. **Transcript Parsing for Auto-State**
   - Parse JSONL transcript before compaction
   - Extract todos, files modified, errors automatically
   - Generate mini-handoff on `/clear`

3. **Session Outcome Tracking**
   - Add outcome field to sprint completion: `SUCCEEDED`, `PARTIAL_PLUS`, `PARTIAL_MINUS`, `FAILED`
   - Track in `COMPLETED` marker

### Medium Priority (Consider for v0.13.0)

4. **YAML Handoff Format**
   - Adopt compact YAML format for session handoffs
   - `worked:` and `failed:` fields for learning

5. **Checkpoint System**
   - Add phase status tracking to long sprints
   - Validation state JSON for test continuity

6. **Impact Analysis**
   - Call graph for change impact prediction
   - Pre-implementation validation enhancement

### Low Priority (Future Consideration)

7. **Memory Database**
   - PostgreSQL + pgvector for learnings
   - Only if file-based approach proves insufficient

8. **Trigger-Based Skill Activation**
   - Natural language triggers in skill metadata
   - Current command-based activation is sufficient

---

## Implementation Notes

### For Pre-Mortem Integration

```yaml
# Add to .claude/protocols/risk-analysis.md
risk_categories:
  tiger:
    severity: high
    action: must_address_or_accept
  paper_tiger:
    severity: low
    action: document_why_ok
  elephant:
    severity: varies
    action: surface_for_discussion

verification_required:
  - context_read: true
  - mitigation_check: true
  - scope_check: true
```

### For Transcript Parsing

```python
# Pseudocode for synthesis-checkpoint.sh enhancement
def parse_transcript(jsonl_path):
    todos = []
    files_modified = set()
    errors = []

    for line in jsonl_path.read_lines():
        entry = json.loads(line)
        if entry.get("tool_name") == "TodoWrite":
            todos = entry["tool_input"]["todos"]
        if entry.get("tool_name") in ("Edit", "Write"):
            files_modified.add(entry["tool_input"]["file_path"])
        if entry.get("error"):
            errors.append(entry["error"])

    return {
        "todos": todos,
        "files": list(files_modified),
        "errors": errors
    }
```

---

## Conclusion

Continuous-Claude-v3 provides several patterns that could enhance Loa:

| Pattern | Value | Effort | Recommendation |
|---------|-------|--------|----------------|
| Pre-Mortem | High | Medium | Adopt |
| Transcript Parsing | High | Low | Adopt |
| Session Outcomes | Medium | Low | Adopt |
| YAML Handoffs | Medium | Medium | Consider |
| Checkpoint System | Medium | High | Consider |
| Memory Database | High | Very High | Defer |

The "Clear > Compact" philosophy aligns with Loa's Lossless Ledger Protocol. Key differentiator: Continuous-Claude emphasizes automatic state extraction while Loa relies on manual checkpoints.

---

## References

- [Continuous-Claude-v3 Repository](https://github.com/parcadei/Continuous-Claude-v3)
- [Pre-Mortems by Shreyas Doshi](https://coda.io/@shreyas/pre-mortems)
- Loa Lossless Ledger Protocol: `.claude/protocols/session-continuity.md`
