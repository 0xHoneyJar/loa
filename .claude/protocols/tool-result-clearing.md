# Tool Result Clearing Protocol

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-12-27

---

## Overview

This protocol prevents context window exhaustion by implementing systematic clearing of raw search results after extracting high-signal findings. When agents perform searches returning large result sets, they must synthesize key findings into compact references and clear the raw output from working memory.

**Problem**: As token counts increase, model recall accuracy decreases. A ck search returning thousands of tokens overwhelms agent attention budgets and degrades synthesis quality.

**Solution**: Extract high-signal findings, synthesize to NOTES.md with file:line references, clear raw results, and keep only single-line summaries.

**Source**: PRD FR-4.1, SDD §3.4

---

## Attention Budget Thresholds

All agents must enforce these token limits:

| Context Type | Threshold | Action Required |
|--------------|-----------|-----------------|
| **Single search** | 2,000 tokens max | Apply Tool Result Clearing if exceeded |
| **Accumulated results** | 5,000 tokens | MANDATORY clearing |
| **Full file loads** | 3,000 tokens | Single file only, synthesize immediately |
| **Session total** | 15,000 tokens | STOP and synthesize to NOTES.md |

### Token Estimation

Use this helper function to estimate token count (rough approximation):

```bash
estimate_tokens() {
    local text="$1"
    # Rough estimate: 1 token ≈ 4 characters (conservative)
    local char_count=$(echo "$text" | wc -c)
    local estimated_tokens=$((char_count / 4))
    echo "$estimated_tokens"
}
```

**Note**: This is a conservative estimate. For precise counting, use actual tokenizer APIs, but this approximation is sufficient for clearing decisions.

---

## Tool Result Clearing Workflow

### When to Trigger Clearing

Apply Tool Result Clearing **AFTER**:

1. Any search returning >20 results
2. Any search whose output exceeds 2,000 estimated tokens
3. Accumulated search results exceeding 5,000 tokens
4. Full file reads exceeding 3,000 tokens

### 4-Step Clearing Process

#### Step 1: Extract High-Signal Findings

From raw search results, extract:
- **Maximum 10 files** (prioritize highest relevance/score)
- **20 words maximum per finding** (terse description)
- **File:line references** (absolute paths only)
- **Relevance notes** (why this result matters)

**Example extraction**:
```markdown
## High-Signal Findings
- `/abs/path/src/auth/jwt.ts:45` - JWT validation entry point (score: 0.89)
- `/abs/path/src/auth/middleware.ts:12` - Auth middleware integration (score: 0.78)
- `/abs/path/src/config/auth.ts:8` - Auth configuration schema (score: 0.72)
```

#### Step 2: Synthesize to NOTES.md

Write findings to `loa-grimoire/NOTES.md` under appropriate section:

```markdown
## Context Load: 2025-12-27 10:30:00

**Task**: Implement authentication extension
**Search**: hybrid_search("JWT authentication entry points")
**Results**: 47 files found, 3 high-signal

**Key Files**:
- `/abs/path/src/auth/jwt.ts:45-67` - Primary validation logic
- `/abs/path/src/auth/middleware.ts:12-35` - Request interception
- `/abs/path/src/config/auth.ts:8-24` - Configuration schema

**Patterns Found**: JWT tokens validated via async function, middleware applies to all routes, config uses Zod schemas

**Ready to implement**: Yes
```

#### Step 3: Clear Raw Output from Working Memory

After synthesizing to NOTES.md:

1. **DO NOT** keep raw search results in working memory
2. **DO NOT** pass raw results to subsequent operations
3. **DO** keep only the NOTES.md synthesis
4. **DO** reference NOTES.md if details needed later

**Agent internal instruction**: "I have synthesized the search results to NOTES.md. Raw results cleared from working memory. High-signal findings: 3 files identified for authentication work."

#### Step 4: Keep Single-Line Summary

Maintain only a brief summary in current context:

```
Search complete: 47 results → 3 high-signal files identified → synthesized to NOTES.md
```

---

## Semantic Decay Protocol

For long-running sessions (>30 minutes), progressively decay older search results to free attention budget.

### Three Decay Stages

| Stage | Timeframe | Format | Token Cost |
|-------|-----------|--------|------------|
| **Active** | 0-5 minutes | Full synthesis with code snippets in NOTES.md | ~200 tokens |
| **Decayed** | 5-30 minutes | Absolute paths only (lightweight identifiers) | ~12 tokens per file |
| **Archived** | 30+ minutes | Single-line summary in trajectory log | ~20 tokens total |

### Decay Workflow

#### Active Stage (0-5 min)

Full synthesis with code snippets:

```markdown
JWT validation: `export async function validateToken(token: string): Promise<TokenPayload>` [/abs/path/src/auth/jwt.ts:45]
```

**Token cost**: ~200 tokens (includes snippet)

#### Decayed Stage (5-30 min)

After 5 minutes, decay to lightweight identifiers (paths only):

```markdown
/abs/path/src/auth/jwt.ts:45
```

**Token cost**: ~12 tokens (just the path)

**Rehydration**: If agent needs code details, can JIT-retrieve snippet via `Read` tool.

#### Archived Stage (30+ min)

After 30 minutes, archive to trajectory log with single-line summary:

```markdown
Auth module analyzed: 3 files, 2 patterns found
```

**Token cost**: ~20 tokens (entire summary)

**Trajectory log entry**:
```jsonl
{"ts":"2025-12-27T10:30:00Z","agent":"implementing-tasks","phase":"archive","summary":"Auth module analyzed: 3 files, 2 patterns found","paths":["/abs/path/src/auth/jwt.ts:45","/abs/path/src/auth/middleware.ts:12","/abs/path/src/config/auth.ts:8"]}
```

### JIT Rehydration

When agent needs code details from decayed/archived results:

1. Check if path available in NOTES.md or trajectory log
2. Use `Read` tool with file_path and line offset
3. Extract relevant snippet (max 50 lines)
4. Use snippet, then clear again
5. Log rehydration event to trajectory

**Example**:
```jsonl
{"ts":"2025-12-27T11:00:00Z","agent":"implementing-tasks","phase":"rehydrate","path":"/abs/path/src/auth/jwt.ts","reason":"Need validation logic details for implementation"}
```

---

## Before/After Comparison

### WITHOUT Clearing (Context Overload)

**Context window**:
```
[2000 tokens raw search results]
+ [500 tokens task description]
+ [1500 tokens accumulated context]
---
Total: 4000 tokens in working memory
```

**Result**: Model struggles with synthesis, hallucinates, misses connections, poor code quality

### WITH Clearing (Optimized Context)

**Context window**:
```
[50 tokens synthesis from NOTES.md]
+ [500 tokens task description]
+ [200 tokens current focus]
---
Total: 750 tokens in working memory
```

**Result**: Model performs high-level reasoning clearly, accurate citations, solid implementation

**Efficiency gain**: 81% reduction in context tokens (4000 → 750)

---

## Integration with Agent Skills

### implementing-tasks Agent

**Before writing ANY code**:
1. Load relevant context via semantic_search or hybrid_search
2. Apply Tool Result Clearing after search (>20 results or >2000 tokens)
3. Synthesize to NOTES.md with file:line references
4. Reference NOTES.md during implementation
5. JIT-retrieve code snippets only when needed

### reviewing-code Agent

**Before reviewing code**:
1. Find dependents and tests via search
2. Apply Tool Result Clearing after search
3. Synthesize findings to working memory (not NOTES.md for review)
4. Clear raw results, keep only impact summary
5. Reference impact summary during review

### discovering-requirements Agent

**During /ride execution**:
1. Search for entry points, abstractions, Ghost Features, Shadow Systems
2. Apply Tool Result Clearing after EACH search phase
3. Synthesize findings to `loa-grimoire/reality/` files
4. Clear raw results between phases
5. Keep only high-level progress in working memory

---

## Enforcement Checklist

Before completing any task, verify:

- [ ] All searches with >20 results had clearing applied
- [ ] Raw search results NOT in final agent output
- [ ] NOTES.md contains synthesized findings with file:line references
- [ ] Token budget NOT exceeded at any point
- [ ] Semantic Decay applied for sessions >30 minutes
- [ ] All citations reference NOTES.md or provide absolute paths

---

## Communication Guidelines

### What Agents Should Say (User-Facing)

✅ **CORRECT**:
- "I've analyzed the codebase and identified 3 key files for authentication work."
- "Search complete. Findings synthesized to NOTES.md for reference."
- "Located primary validation logic. Ready to proceed with implementation."

❌ **INCORRECT** (internal details exposed):
- "I'm clearing raw search results from my working memory..."
- "Applying Tool Result Clearing protocol to prevent token overflow..."
- "Decaying older results to free up attention budget..."

### Internal State (Not Shown to User)

Agents should internally track:
- Current token budget usage
- Decay stage for each synthesis
- Clearing events (logged to trajectory only)
- Rehydration events (logged to trajectory only)

**Trajectory log example**:
```jsonl
{"ts":"2025-12-27T10:30:00Z","agent":"implementing-tasks","phase":"clear","result_count":47,"high_signal":3,"tokens_before":2100,"tokens_after":50,"reduction_ratio":0.976}
```

---

## Edge Cases

### Case 1: Zero High-Signal Results

If search returns many results but none are high-signal (all scores <0.4):

**Action**:
1. Do NOT extract low-quality findings
2. Log to trajectory: "Search returned X results, 0 high-signal"
3. Reformulate query OR flag as potential Ghost Feature
4. Clear ALL raw results
5. Keep only: "Search inconclusive, reformulating query"

### Case 2: Single High-Quality File (Large)

If search returns 1 file but it's very large (>1000 lines):

**Action**:
1. Do NOT load entire file
2. Extract specific function/class via AST-aware snippet
3. Use `Read` tool with offset and limit
4. Synthesize ONLY relevant sections (max 50 lines)
5. Clear full file from memory

### Case 3: Repeated Searches (Similar Queries)

If agent makes multiple similar searches in same session:

**Action**:
1. Check NOTES.md for existing synthesis BEFORE searching
2. If existing synthesis sufficient, skip redundant search
3. If new search needed, append to existing NOTES.md section
4. Track repeated searches in trajectory (potential inefficiency)
5. Log if >3 similar searches (signals confusion)

---

## Validation

Test Tool Result Clearing implementation with these scenarios:

### Test 1: Large Result Set
```bash
# Simulate search with 50 results
semantic_search "authentication" --top-k 50
# Expected: Clearing triggered, synthesis to NOTES.md, raw results cleared
```

### Test 2: Token Budget Enforcement
```bash
# Accumulate multiple searches
semantic_search "auth" --top-k 20  # 1000 tokens
hybrid_search "JWT" --top-k 30     # 1500 tokens
semantic_search "token" --top-k 25 # 1200 tokens
# Expected: Clearing after 3rd search (total >5000 tokens)
```

### Test 3: Semantic Decay
```bash
# Simulate long session (>30 min)
# Expected: Active → Decayed → Archived transitions logged to trajectory
```

### Test 4: JIT Rehydration
```bash
# After decay, request code details from archived result
# Expected: Read tool used, snippet extracted, re-cleared after use
```

---

## Troubleshooting

### Symptom: Agent output includes raw search results

**Diagnosis**: Clearing not applied or incomplete
**Fix**: Verify clearing workflow executed after search
**Check**: Search result count, token estimation, NOTES.md synthesis

### Symptom: Agent mentions "clearing" or "decay" to user

**Diagnosis**: Internal protocol details exposed
**Fix**: Update agent instructions to use user-friendly language
**Check**: Agent output for protocol-specific terminology

### Symptom: Context window still exhausted despite clearing

**Diagnosis**: Token budget thresholds too high OR rehydration too frequent
**Fix**: Lower thresholds in protocol OR reduce rehydration calls
**Check**: Trajectory log for token usage patterns

### Symptom: Agent can't find previously discovered code

**Diagnosis**: Decayed too aggressively OR NOTES.md synthesis incomplete
**Fix**: Check NOTES.md for synthesis, adjust decay timing
**Check**: NOTES.md sections, trajectory archive entries

---

## Related Protocols

- **Trajectory Evaluation** (`.claude/protocols/trajectory-evaluation.md`) - Intent logging before search
- **Self-Audit Checkpoint** (`.claude/protocols/self-audit-checkpoint.md`) - Verify clearing applied
- **Citations** (`.claude/protocols/citations.md`) - Reference NOTES.md in citations
- **Negative Grounding** (`.claude/protocols/negative-grounding.md`) - Clear results during Ghost detection

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-27 | Initial protocol creation (Sprint 3) |

---

**Status**: ✅ Protocol Complete
**Next**: Integrate into agent skills (Sprint 4)
