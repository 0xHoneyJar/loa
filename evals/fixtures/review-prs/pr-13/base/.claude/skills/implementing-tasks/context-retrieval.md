# Context Retrieval Protocol for implementing-tasks Agent

**Version**: 1.0
**Status**: Active
**Owner**: implementing-tasks skill
**Integration**: ck semantic search (Sprint 4)

---

## Purpose

This protocol defines how the implementing-tasks agent loads relevant code context before writing any new code. Using semantic/hybrid search (when available), the agent discovers existing patterns, similar implementations, and related code to ensure consistency and avoid duplication.

---

## Core Principle

**NEVER write code blindly**. Always load context first to understand:
1. Existing patterns and conventions
2. Similar implementations already in codebase
3. Related modules that might be affected
4. Testing patterns to follow

---

## Context Loading Workflow

### Phase 1: Task Analysis
**Before any search**, analyze the task to determine what context is needed:

```xml
<context_analysis>
  <task_id>sprint-N/task-M</task_id>
  <task_type>new_feature|enhancement|bugfix|refactor</task_type>
  <affected_area>auth|api|ui|database|etc</affected_area>
  <search_intent>
    - What patterns do I need to find?
    - What existing code might this interact with?
    - What similar features already exist?
  </search_intent>
</context_analysis>
```

### Phase 2: Context Search
Execute searches based on task type:

**For New Features**:
1. **Semantic Search** for conceptually similar features:
   ```bash
   # Intent: Find similar feature implementations
   semantic_search(
     query: "<feature_description>",
     path: "src/",
     top_k: 10,
     threshold: 0.5
   )
   ```

2. **Hybrid Search** for specific patterns:
   ```bash
   # Intent: Find architectural patterns to follow
   hybrid_search(
     query: "<pattern_keywords>",
     path: "src/",
     top_k: 10,
     threshold: 0.6
   )
   ```

**For Enhancements**:
1. **Find the module** being enhanced:
   ```bash
   hybrid_search(
     query: "<module_name> <function_name>",
     path: "src/",
     top_k: 5
   )
   ```

2. **Find dependents** (who imports this):
   ```bash
   regex_search(
     pattern: "import.*<module>|require.*<module>",
     path: "src/"
   )
   ```

**For Bug Fixes**:
1. **Find the buggy code**:
   ```bash
   hybrid_search(
     query: "<error_description> <function_context>",
     path: "src/",
     top_k: 5
   )
   ```

2. **Find tests** for the module:
   ```bash
   hybrid_search(
     query: "test <module_name>",
     path: "tests/|__tests__|*.test.*|*.spec.*",
     top_k: 10
   )
   ```

### Phase 3: Tool Result Clearing
After heavy searches (>20 results or >2000 tokens):

1. **Extract high-signal findings** (max 10 files):
   - File path + line numbers
   - Brief description (max 20 words each)
   - Why relevant to task

2. **Synthesize to NOTES.md**:
   ```markdown
   ## Context Load: YYYY-MM-DD HH:MM:SS

   **Task**: sprint-N/task-M
   **Search Strategy**: [semantic|hybrid|regex]
   **Key Files**:
   - `/absolute/path/to/file.ts:45-67` - Primary implementation pattern
   - `/absolute/path/to/another.ts:123` - Error handling approach
   - `/absolute/path/to/test.ts:89-102` - Testing pattern

   **Patterns Found**: [Brief 1-2 sentence summary]
   **Architecture Notes**: [Any architectural constraints discovered]
   **Ready to implement**: Yes/No
   ```

3. **Clear raw search results** from working memory

4. **Retain only synthesis** in active context

### Phase 4: Implementation Readiness Check
Before writing code, verify:

- [ ] Loaded at least 1 relevant file (or explicit confirmation none exist)
- [ ] Understood existing patterns (or confirmed this is first instance)
- [ ] Identified testing approach
- [ ] NOTES.md updated with context load
- [ ] Raw search results cleared

If ANY checkbox fails → DO NOT proceed with implementation

---

## Search Strategy

Use search-orchestrator.sh for ck-first search with automatic grep fallback:

```bash
# Task: "Add JWT authentication"
# Use hybrid search for semantic understanding of auth patterns

.claude/scripts/search-orchestrator.sh hybrid \
  "jwt token authentication validate handler auth" \
  src/ 20 0.5
```

### Manual Fallback (if search-orchestrator unavailable)

```bash
grep -rn "jwt\|token.*valid\|auth.*handler" \
  --include="*.ts" --include="*.js" \
  src/ | head -20
```

**Note**: search-orchestrator.sh automatically falls back to grep when ck is unavailable, so manual fallback is rarely needed.

---

## Search Mode Detection

Detect once per session:
```bash
if command -v ck >/dev/null 2>&1; then
    LOA_SEARCH_MODE="ck"
else
    LOA_SEARCH_MODE="grep"
fi
export LOA_SEARCH_MODE
```

**Communication**:
- ❌ NEVER SAY: "Using ck...", "Falling back to grep..."
- ✅ ALWAYS SAY: "Loading relevant context...", "Searching for patterns..."

---

## Attention Budget Management

| Operation | Token Limit | Action on Exceed |
|-----------|-------------|------------------|
| Single search | 2,000 tokens | Synthesize to NOTES.md, clear results |
| Accumulated results | 5,000 tokens | MANDATORY clearing |
| Full file loads | 3,000 tokens | Load single file only, clear others |
| Session total | 15,000 tokens | Stop, synthesize all, then continue |

**Never exceed limits**. Quality degrades rapidly beyond these thresholds.

---

## Integration with Tool Result Clearing Protocol

After context loading:
1. Apply `.claude/protocols/tool-result-clearing.md`
2. Keep only lightweight identifiers (file:line)
3. Full content rehydrated JIT when needed
4. Log all clearing events to trajectory

---

## Example: Implementing New Auth Feature

**Task**: Add OAuth2 integration to existing auth system

### Step 1: Analyze
```
Task Type: Enhancement (extending existing auth)
Affected Area: src/auth/
Search Intent: Find current auth patterns, OAuth examples, token handling
```

### Step 2: Search (with ck)
```bash
# Find existing auth implementation
semantic_search("authentication handler login token", "src/auth/", 10, 0.6)
# Results: src/auth/jwt.ts, src/auth/middleware.ts, src/auth/session.ts

# Find OAuth references (if any)
semantic_search("OAuth OAuth2 SSO provider", "src/", 10, 0.4)
# Results: 0 (Ghost Feature confirmed)

# Find token handling patterns
hybrid_search("token validation parse verify", "src/auth/", 10, 0.6)
# Results: src/auth/jwt.ts:validateToken(), src/auth/utils.ts:parseHeader()
```

### Step 3: Clear & Synthesize
```markdown
## Context Load: 2024-01-15 10:30:00

**Task**: sprint-2/task-3 (Add OAuth2 integration)
**Key Files**:
- `/project/src/auth/jwt.ts:45-89` - Current JWT validation pattern
- `/project/src/auth/middleware.ts:23` - Auth middleware integration point
- `/project/src/auth/session.ts:67` - Session management approach

**Patterns Found**: Existing auth uses JWT tokens with middleware-based validation. No OAuth found (Ghost Feature).

**Architecture Notes**: Follow jwt.ts validation pattern. Add new oauth.ts module parallel to jwt.ts.

**Ready to implement**: Yes
```

### Step 4: Implement
Now write code following discovered patterns.

---

## Trajectory Logging

Log all context loads to trajectory:
```jsonl
{
  "ts": "2024-01-15T10:30:00Z",
  "agent": "implementing-tasks",
  "phase": "context_load",
  "task": "sprint-2/task-3",
  "search_mode": "ck",
  "searches": [
    {"type": "semantic", "query": "authentication handler", "results": 3},
    {"type": "semantic", "query": "OAuth OAuth2", "results": 0},
    {"type": "hybrid", "query": "token validation", "results": 2}
  ],
  "key_files": [
    "/project/src/auth/jwt.ts:45-89",
    "/project/src/auth/middleware.ts:23"
  ],
  "ready": true
}
```

---

## Success Criteria

Context loading is successful when:
- [ ] High-signal findings identified (or explicit confirmation none exist)
- [ ] Existing patterns understood
- [ ] Testing approach identified
- [ ] NOTES.md synthesis complete
- [ ] Raw results cleared from working memory
- [ ] Grounding ratio for decisions ≥ 0.95

---

## Anti-Patterns

❌ **NEVER DO**:
- Write code without loading context first
- Keep raw search results in working memory
- Exceed attention budgets
- Search without articulated intent
- Proceed when "Ready to implement" is No

✅ **ALWAYS DO**:
- Load context before every implementation
- Synthesize findings to NOTES.md
- Clear raw results after extraction
- Log to trajectory
- Verify readiness before coding

---

## Integration Points

This protocol integrates with:
- `.claude/protocols/tool-result-clearing.md` - Memory management
- `.claude/protocols/trajectory-evaluation.md` - Reasoning audit
- `.claude/protocols/citations.md` - Code evidence requirements
- `.claude/scripts/search-orchestrator.sh` - Search execution

---

**Status**: Active from Sprint 4
**Review**: After Sprint 5 validation
