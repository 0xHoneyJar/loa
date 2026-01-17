# Recursive Language Models (RLMs) - Research Analysis

**Source:** Zhang, Kraska, Khattab (MIT CSAIL), arXiv:2512.24601v1, Dec 2025
**Analyzed:** 2026-01-17
**Relevance:** High - Direct implications for Loa context management

---

## Executive Summary

RLMs propose treating long prompts as **external environment variables** rather than direct context, enabling:
- 2 orders of magnitude context scaling (10M+ tokens)
- 28-58% improvement on information-dense tasks
- Comparable or lower inference cost
- Dramatically reduced "context rot"

**Key insight:** Compaction/summarization loses information. RLMs preserve it externally.

---

## Core Mechanism

```
┌─────────────────────────────────────────────────────────────┐
│  Traditional LLM                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  [System] + [Long Context] + [Query] → [Response]    │   │
│  └──────────────────────────────────────────────────────┘   │
│  Problem: Context rot, token limits, lost details           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Recursive LLM                                               │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │ Environment │    │ LLM writes code to:                 │ │
│  │ ┌─────────┐ │    │ - peek at context                   │ │
│  │ │ context │ │◄───│ - filter/chunk programmatically     │ │
│  │ │ (var)   │ │    │ - call llm_query() recursively      │ │
│  │ └─────────┘ │    │ - aggregate results                 │ │
│  │             │    └─────────────────────────────────────┘ │
│  │ llm_query() │                                            │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

## Key Results (Table 1 from paper)

| Task | Base GPT-5 | RLM(GPT-5) | Improvement |
|------|------------|------------|-------------|
| CodeQA (23K-4.2M tokens) | 24.00% | 62.00% | +158% |
| BrowseComp+ (6-11M tokens) | 0.00% | 91.33% | N/A (base failed) |
| OOLONG (131K tokens) | 44.00% | 56.50% | +28% |
| OOLONG-Pairs (32K tokens) | 0.04% | 58.00% | +145000% |

**Critical finding:** Even for inputs within context window (OOLONG at 131K), RLMs outperform by 28%.

---

## Relevance to Loa

### Current Loa Approach vs RLM

| Aspect | Loa Current | RLM Pattern |
|--------|-------------|-------------|
| Large codebases | Parallel subagents | Recursive self-calls with REPL |
| Context overflow | Compaction + NOTES.md | External variable + peek/probe |
| Document processing | JIT retrieval | Programmatic examination |
| Information density | Summarization | Full preservation external |

### Where Loa Aligns (Already)

1. **Task tool subagents** - Similar to RLM sub-calls
2. **External state** - `grimoires/loa/`, `.beads/` store state outside context
3. **Tiered recovery** - Session continuity treats state as external
4. **Trajectory logging** - Reasoning persists externally

### Where RLM Could Improve Loa

1. **`/ride` skill** - Codebase analysis with RLM-style probing
2. **PRD discovery** - Large context directory processing
3. **Security audit** - Dense code review without context rot
4. **Implementation** - Large file modifications

---

## Emergent RLM Patterns (from paper trajectories)

### Pattern 1: Probe Before Load
```python
# RLM probes with regex before full load
keywords = ["festival", "La Union", "beauty pageant"]
results = {}
for kw in keywords:
    results[kw] = find_snippets(context, keyword=kw, window=400)
```

**Loa application:** Use in `/ride` before loading full files.

### Pattern 2: Recursive Decomposition
```python
# Chunk and delegate to sub-LLMs
chunk_size = len(context) // 10
for i in range(10):
    chunk = context[i*chunk_size:(i+1)*chunk_size]
    answer = llm_query(f"Analyze chunk: {chunk}")
    answers.append(answer)
final = llm_query(f"Aggregate: {answers}")
```

**Loa application:** Task tool already supports this pattern.

### Pattern 3: Code-Based Verification
```python
# Verify answers programmatically, not via re-prompting
assert len(pairs) == expected_count
for pair in pairs:
    assert pair[0] < pair[1]  # Lower ID first
```

**Loa application:** Schema validation (`schema-validator.sh`) partially implements.

---

## Implementation Recommendations

### Immediate (v0.14.0 candidate)

1. **Update context-manager.sh**
   - Add "peek before load" mode
   - Probe file structure before full ingestion
   - Use `head`, `wc -l`, `grep -c` to assess before reading

2. **Enhance /ride skill**
   - Probe codebase structure first (file count, types, sizes)
   - Only load relevant files into full analysis
   - Use regex patterns to filter before LLM processing

3. **Add to grounding-check.sh**
   - Track "programmatic verification" as grounding type
   - Reward code-based answer validation

### Medium-term (v0.15.0+)

4. **Recursive Task pattern**
   - Add `recursive: true` option to Task tool usage
   - Allow subagent to spawn further subagents (depth limited)
   - Aggregate results at parent level

5. **REPL-style context access**
   - For large documents, offer "context as variable" mode
   - LLM writes code to examine rather than direct read

### Research Track

6. **Benchmark current vs RLM patterns**
   - Test `/ride` on large codebases (>100K lines)
   - Compare current approach vs RLM-style probing
   - Measure accuracy, cost, time

---

## Limitations (from paper)

1. **Requires coding capability** - Smaller models struggle as RLMs
2. **Thinking token limits** - Reasoning models may hit output limits
3. **Asynchronous calls needed** - Sequential sub-calls are slow
4. **Model-specific tuning** - Different models need different prompts

---

## Questions for Further Investigation

1. Does Claude exhibit similar "context rot" patterns to GPT-5?
2. Can Task tool subagents approximate `llm_query()` effectively?
3. What's the optimal chunk size for Claude's architecture?
4. Should Loa offer "RLM mode" as optional pattern for large contexts?

---

## References

- Paper: https://arxiv.org/abs/2512.24601
- Related: Context Folding (Sun et al., 2025)
- Related: ReSum (Wu et al., 2025)
- Related: Claude Code subagents documentation

---

## Action Items

- [ ] Review with team for v0.14.0 roadmap
- [ ] Prototype "peek before load" in context-manager.sh
- [ ] Test RLM-style patterns in /ride skill
- [ ] Benchmark against current approaches
