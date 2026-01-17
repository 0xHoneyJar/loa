# Software Design Document: RLM-Inspired Context Improvements

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Draft
**Author**: designing-architecture agent
**PRD Reference**: `grimoires/loa/prd.md`
**Research Source**: `grimoires/pub/research/rlm-recursive-language-models.md`

---

## 1. Executive Summary

This SDD details the technical implementation of RLM-inspired patterns to improve Loa's context management. The design enhances existing scripts (`context-manager.sh`, `schema-validator.sh`) and the `/ride` skill with probe-before-load capabilities, programmatic validation, and benchmarking infrastructure.

**Key Design Principles:**
1. **Enhance, don't replace** - Build on existing infrastructure
2. **Configurable thresholds** - All behaviors tunable via `.loa.config.yaml`
3. **Graceful degradation** - New features don't break existing workflows
4. **Measurable improvements** - Benchmark framework validates claims

---

## 2. System Architecture

### 2.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Loa Context System                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │  context-manager │    │ schema-validator │    │   /ride skill    │  │
│  │      .sh         │    │       .sh        │    │    SKILL.md      │  │
│  └────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘  │
│           │                       │                       │             │
│           ▼                       ▼                       ▼             │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     Probe Layer (NEW)                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │ probe_file  │  │ probe_dir   │  │ should_load │               │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                  Configuration (.loa.config.yaml)                 │  │
│  │  context_management:                                              │  │
│  │    probe_before_load: true                                        │  │
│  │    max_eager_load_lines: 500                                      │  │
│  │    relevance_keywords: [export, class, interface]                 │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                  Benchmark Layer (NEW)                            │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                        │  │
│  │  │ rlm-benchmark.sh│  │ benchmark-data/ │                        │  │
│  │  └─────────────────┘  └─────────────────┘                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
┌─────────┐     ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Request │────▶│ Probe Phase │────▶│ Decision     │────▶│ Load/Skip   │
│ to Read │     │ (metadata)  │     │ (should_load)│     │ (selective) │
└─────────┘     └─────────────┘     └──────────────┘     └─────────────┘
                      │                    │
                      ▼                    ▼
               ┌─────────────┐     ┌──────────────┐
               │ Metrics:    │     │ Config:      │
               │ - lines     │     │ - thresholds │
               │ - size      │     │ - keywords   │
               │ - relevance │     │ - patterns   │
               └─────────────┘     └──────────────┘
```

---

## 3. Component Design

### 3.1 Context Manager Enhancements

**File**: `.claude/scripts/context-manager.sh`
**Current Size**: 809 lines
**Changes**: Add ~150 lines for probe functionality

#### 3.1.1 New Functions

```bash
#######################################
# Probe file metadata without loading content
# Arguments:
#   $1 - file path
# Outputs:
#   JSON object with file metadata
#######################################
context_probe_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo '{"error": "file_not_found"}'
        return 1
    fi

    local lines size type extension
    lines=$(wc -l < "$file" 2>/dev/null || echo 0)
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    type=$(file -b "$file" 2>/dev/null | head -c 50 || echo "unknown")
    extension="${file##*.}"

    # Estimate tokens (~4 chars per token for code)
    local estimated_tokens=$((size / 4))

    jq -n \
        --arg file "$file" \
        --argjson lines "$lines" \
        --argjson size "$size" \
        --arg type "$type" \
        --arg ext "$extension" \
        --argjson tokens "$estimated_tokens" \
        '{file: $file, lines: $lines, size_bytes: $size, type: $type, extension: $ext, estimated_tokens: $tokens}'
}

#######################################
# Probe directory for file inventory
# Arguments:
#   $1 - directory path
#   $2 - max depth (default: 3)
#   $3 - extensions filter (default: all code files)
# Outputs:
#   JSON array of file probes
#######################################
context_probe_dir() {
    local dir="$1"
    local max_depth="${2:-3}"
    local extensions="${3:-ts,js,py,go,rs,sol,sh}"

    local ext_pattern=""
    IFS=',' read -ra EXTS <<< "$extensions"
    for ext in "${EXTS[@]}"; do
        [[ -n "$ext_pattern" ]] && ext_pattern="$ext_pattern -o "
        ext_pattern="${ext_pattern}-name \"*.$ext\""
    done

    local total_lines=0
    local total_files=0
    local files_json="[]"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local probe
        probe=$(context_probe_file "$file")
        files_json=$(echo "$files_json" | jq --argjson p "$probe" '. + [$p]')
        total_files=$((total_files + 1))
        local file_lines
        file_lines=$(echo "$probe" | jq -r '.lines')
        total_lines=$((total_lines + file_lines))
    done < <(eval "find \"$dir\" -maxdepth $max_depth -type f \( $ext_pattern \) \
        -not -path '*/node_modules/*' \
        -not -path '*/.git/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        2>/dev/null | head -100")

    jq -n \
        --arg dir "$dir" \
        --argjson total_files "$total_files" \
        --argjson total_lines "$total_lines" \
        --argjson files "$files_json" \
        '{directory: $dir, total_files: $total_files, total_lines: $total_lines, files: $files}'
}

#######################################
# Determine if file should be fully loaded
# Arguments:
#   $1 - file path
#   $2 - probe result (optional, will probe if not provided)
# Returns:
#   0 if should load, 1 if should skip
# Outputs:
#   Decision JSON with reasoning
#######################################
context_should_load() {
    local file="$1"
    local probe="${2:-}"

    # Get probe if not provided
    if [[ -z "$probe" ]]; then
        probe=$(context_probe_file "$file")
    fi

    # Get configuration thresholds
    local max_lines relevance_required
    max_lines=$(get_config "context_management.max_eager_load_lines" "500")
    relevance_required=$(get_config "context_management.require_relevance_check" "true")

    local lines
    lines=$(echo "$probe" | jq -r '.lines')

    # Decision logic
    local decision="load"
    local reason=""

    # Check 1: File size threshold
    if [[ "$lines" -gt "$max_lines" ]]; then
        if [[ "$relevance_required" == "true" ]]; then
            # Need relevance check for large files
            local relevance
            relevance=$(context_check_relevance "$file")
            if [[ "$relevance" -lt 3 ]]; then
                decision="skip"
                reason="Large file ($lines lines) with low relevance score ($relevance/10)"
            else
                decision="load"
                reason="Large file but high relevance ($relevance/10)"
            fi
        else
            decision="excerpt"
            reason="File exceeds threshold ($lines > $max_lines lines)"
        fi
    else
        decision="load"
        reason="File within threshold ($lines <= $max_lines lines)"
    fi

    jq -n \
        --arg file "$file" \
        --arg decision "$decision" \
        --arg reason "$reason" \
        --argjson probe "$probe" \
        '{file: $file, decision: $decision, reason: $reason, probe: $probe}'

    [[ "$decision" == "load" ]]
}

#######################################
# Check file relevance using keyword patterns
# Arguments:
#   $1 - file path
# Outputs:
#   Relevance score 0-10
#######################################
context_check_relevance() {
    local file="$1"
    local score=0

    # Get relevance keywords from config
    local keywords
    keywords=$(get_config "context_management.relevance_keywords" '["export","class","interface","function","async","api","route","handler"]')

    # Count keyword occurrences (capped contribution)
    while IFS= read -r keyword; do
        local count
        count=$(grep -c "$keyword" "$file" 2>/dev/null || echo 0)
        if [[ "$count" -gt 0 ]]; then
            # Cap at 2 points per keyword
            local points=$((count > 5 ? 2 : 1))
            score=$((score + points))
        fi
    done < <(echo "$keywords" | jq -r '.[]')

    # Cap at 10
    [[ "$score" -gt 10 ]] && score=10

    echo "$score"
}
```

#### 3.1.2 New Command: `probe`

Add to command dispatcher:

```bash
cmd_probe() {
    local target="${1:-.}"
    local json_output="false"

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *) print_error "Unknown option: $1"; return 1 ;;
        esac
    done

    if [[ -f "$target" ]]; then
        context_probe_file "$target"
    elif [[ -d "$target" ]]; then
        context_probe_dir "$target"
    else
        print_error "Target not found: $target"
        return 1
    fi
}
```

### 3.2 Schema Validator Enhancements

**File**: `.claude/scripts/schema-validator.sh`
**Current Size**: 546 lines
**Changes**: Add ~100 lines for assertion mode

#### 3.2.1 Assertion Helper Functions

```bash
#######################################
# Assert field exists in JSON data
#######################################
assert_field_exists() {
    local data="$1"
    local field="$2"

    if echo "$data" | jq -e ".$field" &>/dev/null; then
        return 0
    fi

    echo "ASSERTION_FAILED: Field '$field' does not exist"
    return 1
}

#######################################
# Assert field matches pattern
#######################################
assert_field_matches() {
    local data="$1"
    local field="$2"
    local pattern="$3"

    local value
    value=$(echo "$data" | jq -r ".$field // empty" 2>/dev/null)

    if [[ -z "$value" ]]; then
        echo "ASSERTION_FAILED: Field '$field' is empty or missing"
        return 1
    fi

    if [[ "$value" =~ $pattern ]]; then
        return 0
    fi

    echo "ASSERTION_FAILED: Field '$field' value '$value' does not match pattern '$pattern'"
    return 1
}

#######################################
# Assert array is not empty
#######################################
assert_array_not_empty() {
    local data="$1"
    local field="$2"

    local length
    length=$(echo "$data" | jq ".$field | length" 2>/dev/null || echo 0)

    if [[ "$length" -gt 0 ]]; then
        return 0
    fi

    echo "ASSERTION_FAILED: Array '$field' is empty"
    return 1
}

#######################################
# Run programmatic assertions on file
#######################################
validate_with_assertions() {
    local file_path="$1"
    local schema_name="$2"
    local failures=()

    # Extract frontmatter/data
    local data
    if ! data=$(extract_frontmatter "$file_path"); then
        echo "ASSERTION_FAILED: Could not extract data from file"
        return 1
    fi

    # Schema-specific assertions
    case "$schema_name" in
        prd)
            assert_field_exists "$data" "version" || failures+=("version")
            assert_field_matches "$data" "version" "^[0-9]+\.[0-9]+\.[0-9]+$" || failures+=("version_format")
            assert_field_matches "$data" "status" "^(Draft|Approved|Archived)$" || failures+=("status")
            ;;
        sdd)
            assert_field_exists "$data" "version" || failures+=("version")
            assert_field_exists "$data" "prd_reference" || failures+=("prd_reference")
            ;;
        sprint)
            assert_field_exists "$data" "sprint_number" || failures+=("sprint_number")
            ;;
        trajectory-entry)
            assert_field_exists "$data" "timestamp" || failures+=("timestamp")
            assert_field_exists "$data" "agent" || failures+=("agent")
            assert_field_exists "$data" "action" || failures+=("action")
            ;;
    esac

    if [[ ${#failures[@]} -gt 0 ]]; then
        return 1
    fi
    return 0
}
```

### 3.3 Ride Skill Enhancements

**File**: `.claude/skills/riding-codebase/SKILL.md`
**Current Size**: 1124 lines
**Changes**: Insert new Phase 0 (~100 lines), modify Phase 2 (~50 lines)

#### 3.3.1 New Phase 0: Probe

Insert before existing Phase 1:

```markdown
## Phase 0: Codebase Probing (NEW - RLM Pattern)

### 0.1 Probe Codebase Structure

Before loading any files, probe the codebase to understand its scope:

```bash
# Run probe on target directory
PROBE_RESULT=$(.claude/scripts/context-manager.sh probe "$TARGET_REPO" --json)

# Extract summary
TOTAL_FILES=$(echo "$PROBE_RESULT" | jq '.total_files')
TOTAL_LINES=$(echo "$PROBE_RESULT" | jq '.total_lines')
ESTIMATED_TOKENS=$((TOTAL_LINES * 3))  # ~3 tokens per line of code

echo "Codebase Summary:"
echo "  Files: $TOTAL_FILES"
echo "  Lines: $TOTAL_LINES"
echo "  Estimated tokens: $ESTIMATED_TOKENS"
```

### 0.2 Categorize Files by Loading Strategy

| Codebase Size | Estimated Tokens | Loading Strategy |
|---------------|------------------|------------------|
| Small (<10K lines) | <30K tokens | Load all |
| Medium (10K-50K) | 30K-150K tokens | Prioritized loading |
| Large (>50K) | >150K tokens | Probe + excerpts only |

### 0.3 Generate Loading Plan

Create a loading plan based on probing:

- **Will Load Fully**: High relevance, small files
- **Will Use Excerpts**: Medium relevance, large files
- **Will Skip**: Low relevance, test files, generated code

Log to trajectory:
```json
{"timestamp": "...", "agent": "riding-codebase", "phase": 0, "action": "probe", "details": {"total_files": N, "total_lines": N, "strategy": "prioritized"}}
```
```

### 3.4 Benchmark Framework

**New File**: `.claude/scripts/rlm-benchmark.sh`
**Size**: ~350 lines

Core functionality:
- `benchmark_current_pattern()` - Simulate current loading (all files)
- `benchmark_rlm_pattern()` - Simulate RLM loading (probe + selective)
- `cmd_run` - Run benchmark with configurable iterations
- `cmd_baseline` - Set baseline metrics
- `cmd_compare` - Compare against baseline
- `cmd_report` - Generate markdown report

Output stored in: `grimoires/pub/research/benchmarks/`

---

## 4. Configuration Schema

### 4.1 New Configuration Options

Add to `.loa.config.yaml`:

```yaml
# RLM-Inspired Context Management (v0.14.0+)
context_management:
  # Existing options
  client_compaction: true
  preserve_notes_md: true
  simplified_checkpoint: true
  auto_trajectory_log: true

  # NEW: Probe-before-load options
  probe_before_load: true                    # Enable probe pattern
  max_eager_load_lines: 500                  # Files under this load immediately
  require_relevance_check: true              # Check relevance for large files
  relevance_keywords:                        # Keywords that increase relevance
    - export
    - class
    - interface
    - function
    - async
    - api
    - route
    - handler
  exclude_patterns:                          # Always exclude these
    - "*.test.ts"
    - "*.spec.ts"
    - "node_modules/**"
    - "dist/**"

  # NEW: Token budgeting
  token_budget:
    small_codebase: 30000                    # < this = load all
    medium_codebase: 150000                  # < this = prioritized
    large_codebase: 500000                   # > this = excerpts only
```

---

## 5. File Changes Summary

| File | Action | Lines Changed | Description |
|------|--------|---------------|-------------|
| `.claude/scripts/context-manager.sh` | Modify | +150 | Add probe functions, probe command |
| `.claude/scripts/schema-validator.sh` | Modify | +100 | Add assertion functions, assert command |
| `.claude/scripts/rlm-benchmark.sh` | Create | +350 | New benchmark framework |
| `.claude/skills/riding-codebase/SKILL.md` | Modify | +150 | Add Phase 0 probing, modify Phase 2 |
| `.loa.config.yaml` | Modify | +30 | Add context_management options |

**Total**: ~780 lines of new/modified code

---

## 6. Testing Strategy

### 6.1 Unit Tests

**File**: `tests/unit/context-manager-probe.bats`

```bash
@test "context_probe_file returns correct metadata" {
    echo -e "line1\nline2\nline3" > "$BATS_TMPDIR/test.ts"
    run .claude/scripts/context-manager.sh probe "$BATS_TMPDIR/test.ts"
    assert_success
    assert_output --partial '"lines": 3'
}

@test "context_should_load returns false for large low-relevance files" {
    seq 1 1000 > "$BATS_TMPDIR/large.ts"
    run .claude/scripts/context-manager.sh should-load "$BATS_TMPDIR/large.ts"
    assert_failure
}
```

### 6.2 Integration Tests

**File**: `tests/integration/rlm-benchmark.bats`

```bash
@test "benchmark run produces comparison data" {
    run .claude/scripts/rlm-benchmark.sh run . --mode both --json
    assert_success
    assert_output --partial '"token_reduction_percent"'
}
```

---

## 7. Deployment & Rollout

### 7.1 Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `context_management.probe_before_load` | `true` | Enable probe pattern |
| `context_management.require_relevance_check` | `true` | Require relevance scoring |

### 7.2 Rollout Phases

1. **Sprint 1**: Probe infrastructure only
2. **Sprint 2**: Skill integration
3. **Sprint 3**: Schema validation
4. **Sprint 4**: Benchmarking + documentation

### 7.3 Rollback Plan

Set `probe_before_load: false` in config - falls back to original behavior.

---

## 8. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Token reduction | -30% | `rlm-benchmark.sh compare` |
| Accuracy on large codebases | +25% | Manual testing |
| Probe overhead | <5% | Benchmark timing data |

---

## 9. API Reference

### context-manager.sh

```
context-manager.sh probe <path>           # Probe file or directory
context-manager.sh probe <path> --json    # JSON output
context-manager.sh should-load <file>     # Check if file should load
context-manager.sh relevance <file>       # Get relevance score (0-10)
```

### schema-validator.sh

```
schema-validator.sh assert <file>              # Run assertions
schema-validator.sh assert <file> --schema prd # Override schema
schema-validator.sh assert <file> --json       # JSON output
```

### rlm-benchmark.sh

```
rlm-benchmark.sh run <path>              # Run benchmark
rlm-benchmark.sh baseline <path>         # Set baseline
rlm-benchmark.sh compare <path>          # Compare to baseline
rlm-benchmark.sh history                 # Show history
rlm-benchmark.sh report                  # Generate report
```

---

*SDD generated by designing-architecture agent*
*Source: PRD (grimoires/loa/prd.md)*
