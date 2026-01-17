# Product Requirements Document: RLM-Inspired Context Improvements

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Draft
**Author**: discovering-requirements agent
**Feature Branch**: `feature/rlm-context-improvements`
**Research Source**: `grimoires/pub/research/rlm-recursive-language-models.md`

---

## 1. Problem Statement

Loa's context management faces scalability challenges with large codebases and complex projects:

1. **Context Rot**: Information quality degrades as context window fills - even within limits, accuracy drops
2. **Lossy Compaction**: Current summarization loses details that may be critical later
3. **Eager Loading**: Files are fully read before determining relevance, wasting tokens
4. **Serial Processing**: Large codebases processed sequentially, missing parallelization opportunities
5. **No Programmatic Verification**: Answers validated via re-prompting rather than code assertions

**Research Foundation**: The RLM paper (Zhang, Kraska, Khattab - MIT CSAIL, Dec 2025) demonstrates:
- 28-58% improvement on information-dense tasks using "probe before load" patterns
- 2 orders of magnitude context scaling (10M+ tokens) with external variable approach
- Even within context limits (131K tokens), RLM patterns outperform by 28%

> "Compaction/summarization loses information. RLMs preserve it externally." - RLM Paper Analysis

## 2. Vision & Goals

### Vision
Apply RLM research patterns to Loa's context management, enabling accurate processing of arbitrarily large codebases without information loss.

### Goals

| Goal | Success Metric | Priority |
|------|----------------|----------|
| Reduce unnecessary token consumption | -30% tokens on `/ride` for large codebases | P0 |
| Improve accuracy on large contexts | +25% accuracy on 100K+ line codebases | P0 |
| Enable probe-before-load pattern | 100% of file reads preceded by metadata check | P1 |
| Add programmatic verification | Schema validation on all structured outputs | P1 |
| Benchmark RLM patterns | Comparative data on current vs RLM approach | P2 |

### Non-Goals

- Full REPL-style context (requires Claude API changes)
- Recursive subagent spawning beyond current Task tool limits
- Model-specific optimizations (focus on patterns, not tuning)

## 3. User Stories

### US-1: As a developer, I want `/ride` to probe before loading
**Acceptance Criteria:**
- `/ride` first counts files, sizes, types via `wc`, `file`, `find`
- Only files matching relevance criteria loaded fully
- Probe results logged to trajectory for transparency

### US-2: As a developer, I want context-manager.sh to preserve critical information
**Acceptance Criteria:**
- New "peek" mode that assesses files before full read
- Configurable thresholds for when to probe vs load
- Token savings reported on each operation

### US-3: As an agent, I want structured outputs validated programmatically
**Acceptance Criteria:**
- Schema validation runs on PRD, SDD, sprint outputs
- Code assertions used instead of re-prompting for verification
- Validation errors trigger targeted corrections, not full regeneration

### US-4: As a developer, I want benchmarks comparing current vs RLM patterns
**Acceptance Criteria:**
- Benchmark script for `/ride` on test codebases
- Metrics: accuracy, token usage, time, cost
- Results stored in `grimoires/pub/research/`

## 4. Technical Design

### 4.1 Probe-Before-Load Pattern

**Current Flow:**
```
User: /ride
Agent: Read file1.ts (5000 lines)
Agent: Read file2.ts (3000 lines)
Agent: Read file3.ts (2000 lines)
... [context fills] ...
Agent: [accuracy degrades]
```

**RLM-Inspired Flow:**
```
User: /ride
Agent: Probe codebase structure
  - 47 TypeScript files, 23,000 total lines
  - 12 test files (exclude)
  - 5 config files (low priority)
  - 30 source files (prioritize)
Agent: Grep for patterns: "export", "class", "interface"
  - file1.ts: 15 exports, high relevance
  - file2.ts: 2 exports, low relevance
Agent: Load file1.ts, file4.ts, file7.ts (high relevance only)
Agent: [accurate analysis with 40% fewer tokens]
```

### 4.2 Context Manager Enhancements

**New Functions in `context-manager.sh`:**

```bash
# Probe file metadata without loading
context_probe_file() {
  local file="$1"
  echo "lines=$(wc -l < "$file")"
  echo "size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")"
  echo "type=$(file -b "$file")"
}

# Probe directory structure
context_probe_dir() {
  local dir="$1"
  find "$dir" -type f -name "*.ts" -o -name "*.js" | head -100 | while read f; do
    context_probe_file "$f"
  done
}

# Assess before loading
context_should_load() {
  local file="$1"
  local max_lines="${2:-1000}"
  local lines=$(wc -l < "$file")
  [[ $lines -le $max_lines ]]
}
```

**Configuration (`.loa.config.yaml`):**
```yaml
context_management:
  probe_before_load: true
  max_eager_load_lines: 500
  relevance_keywords: ["export", "class", "interface", "function"]
  exclude_patterns: ["*.test.ts", "*.spec.ts", "node_modules/**"]
```

### 4.3 Schema Validation Enhancement

**Current `schema-validator.sh` additions:**

```bash
# Programmatic assertion mode
validate_with_assertions() {
  local file="$1"
  local schema="$2"

  # Extract structured data
  local data=$(extract_yaml_frontmatter "$file")

  # Code-based assertions (not re-prompting)
  assert_field_exists "$data" "version"
  assert_field_matches "$data" "status" "^(Draft|Approved|Archived)$"
  assert_array_not_empty "$data" "goals"
}
```

### 4.4 Ride Skill Enhancements

**Updates to `.claude/skills/riding-codebase/SKILL.md`:**

1. **Phase 0: Probe** (NEW)
   - Count files by extension
   - Identify entry points
   - Map dependency graph (package.json, imports)
   - Estimate total tokens

2. **Phase 1: Prioritize** (ENHANCED)
   - Rank files by relevance score
   - Apply exclusion patterns
   - Set loading budget

3. **Phase 2: Targeted Load** (MODIFIED)
   - Load only high-priority files
   - Use grep excerpts for medium-priority
   - Skip low-priority entirely

### 4.5 Benchmark Framework

**New script: `.claude/scripts/rlm-benchmark.sh`:**

```bash
#!/usr/bin/env bash
# Benchmark current vs RLM-style patterns

benchmark_ride() {
  local codebase="$1"
  local mode="$2"  # "current" or "rlm"

  # Metrics
  local start_time=$(date +%s.%N)
  local tokens_before=$(context_token_count)

  # Run analysis
  if [[ "$mode" == "rlm" ]]; then
    ride_with_probing "$codebase"
  else
    ride_current "$codebase"
  fi

  # Capture results
  local end_time=$(date +%s.%N)
  local tokens_after=$(context_token_count)

  echo "mode=$mode"
  echo "time=$(echo "$end_time - $start_time" | bc)"
  echo "tokens=$(echo "$tokens_after - $tokens_before" | bc)"
}
```

## 5. Implementation Phases

### Phase 1: Probe Infrastructure (Sprint 1)
- [ ] Add probe functions to `context-manager.sh`
- [ ] Add configuration options to `.loa.config.yaml`
- [ ] Create `context_probe_file()` and `context_probe_dir()`
- [ ] Add `context_should_load()` threshold check
- [ ] Unit tests for probe functions

### Phase 2: Ride Skill Enhancement (Sprint 2)
- [ ] Update `/ride` skill with Phase 0 probing
- [ ] Implement relevance scoring
- [ ] Add targeted loading with budget
- [ ] Update skill documentation
- [ ] Integration tests

### Phase 3: Schema Validation (Sprint 3)
- [ ] Add assertion mode to `schema-validator.sh`
- [ ] Create assertion helpers
- [ ] Integrate with PRD/SDD/Sprint validation
- [ ] Add to grounding-check.sh as verification type

### Phase 4: Benchmarking (Sprint 4)
- [ ] Create `rlm-benchmark.sh`
- [ ] Collect baseline metrics on test codebases
- [ ] Run comparative analysis
- [ ] Document findings in research folder

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Probing overhead exceeds savings | Medium | Threshold config, skip for small files |
| Relevance scoring misses important files | High | Conservative defaults, user override |
| Benchmark results inconclusive | Low | Multiple test codebases, statistical significance |
| Breaking existing `/ride` behavior | High | Feature flag, fallback to current |

## 7. Success Criteria

- [ ] `/ride` uses 30% fewer tokens on codebases >50K lines
- [ ] Accuracy improves 25% on standardized test suite
- [ ] Probe functions add <5% overhead on small projects
- [ ] Schema validation catches 100% of structural errors
- [ ] Benchmark data published to research folder

## 8. Open Questions

1. **Probe depth**: How deep to probe before loading? (Current: 1 level)
2. **Caching**: Should probe results be cached across sessions?
3. **Parallelization**: Should probing use parallel subagents?

### Resolved

- **Integration with existing tools**: Enhance existing scripts, don't create parallel system
- **Configuration location**: `.loa.config.yaml` under `context_management` key

---

## Appendix A: RLM Pattern Mapping

| RLM Pattern | Loa Equivalent | Status |
|-------------|----------------|--------|
| External environment variable | `grimoires/`, `.beads/` | Exists |
| `llm_query()` recursive calls | Task tool subagents | Exists |
| Probe before load | `context_probe_file()` | **NEW** |
| Code-based verification | `schema-validator.sh` | **Enhanced** |
| Chunked aggregation | Parallel subagent pattern | Exists |

## Appendix B: Test Codebases for Benchmarking

| Codebase | Lines | Files | Complexity |
|----------|-------|-------|------------|
| loa (self) | ~15K | ~200 | Medium |
| fastify | ~50K | ~400 | High |
| next.js (subset) | ~100K | ~1000 | Very High |

---

*PRD generated by discovering-requirements agent*
*Source: RLM Research Analysis (grimoires/pub/research/rlm-recursive-language-models.md)*
