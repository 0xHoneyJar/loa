# Sprint 2 Engineer Feedback

**Reviewer**: reviewing-code (Senior Technical Lead)
**Date**: 2025-12-27
**Sprint**: Sprint 2 - Core Search Integration
**Status**: ❌ **Changes Required**

---

## Executive Summary

Sprint 2 implementation is architecturally sound but contains **6 critical functional bugs** that will cause failures in production use. The core dual-path search orchestration works, but critical details around output handling, result counting, and error handling need fixes before approval.

**Completion Level**: 80% - Core logic implemented, but execution details flawed

---

## Critical Issues (Must Fix)

### Issue #1: Search Orchestrator Missing Output
**File**: `.claude/scripts/search-orchestrator.sh`
**Lines**: 72-139 (all search types)
**Severity**: CRITICAL

**Problem**: The script executes searches but never outputs results to stdout. Results are lost.

**Evidence**:
```bash
# Line 76-81: Semantic search
ck --semantic "${QUERY}" \
    --path "${SEARCH_PATH}" \
    --top-k "${TOP_K}" \
    --threshold "${THRESHOLD}" \
    --jsonl 2>/dev/null || echo ""
RESULT_COUNT=$?
# No echo or capture of results!
```

**Impact**: Any agent calling this script will receive empty output, breaking all search functionality.

**Required Fix**:
```bash
# Capture results
SEARCH_RESULTS=$(ck --semantic "${QUERY}" \
    --path "${SEARCH_PATH}" \
    --top-k "${TOP_K}" \
    --threshold "${THRESHOLD}" \
    --jsonl 2>/dev/null || echo "")
RESULT_COUNT=$(echo "${SEARCH_RESULTS}" | grep -c '^{' || echo 0)

# Output results to stdout
echo "${SEARCH_RESULTS}"
```

**Apply this pattern to ALL search types**: semantic (line 76), hybrid (line 84), regex (line 92), and all grep fallback variants (lines 106-138).

---

### Issue #2: Incorrect Result Count Tracking
**File**: `.claude/scripts/search-orchestrator.sh`
**Lines**: 81, 89, 95, 118, 131
**Severity**: CRITICAL

**Problem**: `RESULT_COUNT` is set to exit code (`$?`), not actual result count. Trajectory logs will be incorrect.

**Evidence**:
```bash
# Line 81
RESULT_COUNT=$?  # This is 0 (success) or 1 (failure), NOT the result count!
```

**Impact**: Trajectory evaluation will have wrong metrics. Agent cannot detect >50 result pivots (FR-5.2).

**Required Fix**: Count actual JSONL lines:
```bash
RESULT_COUNT=$(echo "${SEARCH_RESULTS}" | grep -c '^{' || echo 0)
```

---

### Issue #3: Trajectory Logging Path Issues
**File**: `.claude/protocols/negative-grounding.md`
**Lines**: 89-101, 117-126
**Severity**: HIGH

**Problem**: Trajectory logging uses relative paths and missing directory creation.

**Evidence**:
```bash
# Line 101
>> loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl
# Will fail if directory doesn't exist!
```

**Impact**: Ghost detection will fail when writing trajectory logs. Silent failures in production.

**Required Fix**:
```bash
TRAJECTORY_FILE="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
mkdir -p "$(dirname "${TRAJECTORY_FILE}")"
jq -n ... >> "${TRAJECTORY_FILE}"
```

---

### Issue #4: Shadow Classification Same Logging Issues
**File**: `.claude/protocols/shadow-classification.md`
**Lines**: 149-160, 170-182, 192-203
**Severity**: HIGH

**Problem**: Same trajectory logging problems as negative-grounding.md.

**Impact**: Shadow detection will fail when writing trajectory logs.

**Required Fix**: Apply same correction pattern as Issue #3 to all trajectory logging examples in this protocol.

---

### Issue #5: grep_to_jsonl Unsafe JSON Escaping
**File**: `.claude/scripts/search-api.sh`
**Lines**: 92-111
**Severity**: HIGH

**Problem**: JSON escaping is incorrect, causing double-escaping or failure on special characters.

**Evidence**:
```bash
# Lines 102-103
snippet_escaped=$(echo "${snippet}" | jq -Rs .)
file_escaped=$(echo "${file}" | jq -Rs .)

# Line 109 - Using --argjson for pre-escaped strings causes double-escaping
--argjson snippet "${snippet_escaped}"
```

**Impact**: Grep fallback will produce malformed JSONL when code contains quotes, backslashes, or other special characters.

**Required Fix**:
```bash
while IFS=: read -r file line snippet; do
    # Skip empty lines
    [[ -z "${file}" ]] && continue
    [[ -z "${line}" ]] && line=0

    # Normalize to absolute path
    if [[ ! "${file}" =~ ^/ ]]; then
        file="${PROJECT_ROOT}/${file}"
    fi

    # Use --arg for all strings (jq handles escaping internally)
    jq -n \
        --arg file "${file}" \
        --argjson line "${line}" \
        --arg snippet "${snippet}" \
        '{file: $file, line: $line, snippet: $snippet, score: 0.0}'
done
```

---

### Issue #6: Missing bc Dependency Check
**File**: `.claude/scripts/search-api.sh`
**Line**: 218
**Severity**: MEDIUM

**Problem**: `filter_by_score` function uses `bc` for float comparison without checking if installed.

**Evidence**:
```bash
# Line 218
if (( $(echo "${score} >= ${min_score}" | bc -l) )); then
    echo "${line}"
fi
```

**Impact**: Script will fail with "command not found" on systems without `bc` (common on minimal Docker images).

**Required Fix**: Add dependency check and fallback:
```bash
# At top of file (after line 14)
if ! command -v bc >/dev/null 2>&1; then
    echo "Warning: bc not found, score filtering will be disabled" >&2
    export BC_AVAILABLE=false
else
    export BC_AVAILABLE=true
fi

# In filter_by_score function (line 218):
if [[ "${BC_AVAILABLE}" == "true" ]]; then
    if (( $(echo "${score} >= ${min_score}" | bc -l) )); then
        echo "${line}"
    fi
else
    # Fallback: no filtering (return all results)
    echo "${line}"
fi
```

---

## Minor Issues (Documentation)

### Documentation Discrepancies

**Implementation Report vs Actual Files**:

| File | Reported Lines | Actual Lines | Difference |
|------|----------------|--------------|------------|
| `search-orchestrator.sh` | 190 | 152 | -38 lines |
| `search-api.sh` | 272 | 253 | -19 lines |
| `negative-grounding.md` | 534 | 285 | -249 lines |
| `shadow-classification.md` | 548 | 418 | -130 lines |
| `drift-report.md` | 390 | 242 | -148 lines |

**Impact**: Low - Documentation inaccuracy, no functional impact.

**Recommendation**: Update implementation report line counts to match actual files.

---

## What Works Well

### Strengths of Implementation

1. **Architectural Integrity**: ✅
   - Three-zone model respected (System Zone read-only)
   - Pre-flight integrity check integration correct
   - Absolute path enforcement throughout

2. **Dual-Path Design**: ✅
   - Mode detection logic correct (LOA_SEARCH_MODE caching)
   - Graceful degradation to grep implemented
   - Search type routing (semantic/hybrid/regex) correct

3. **Protocol Design**: ✅
   - Negative Grounding two-query requirement correct
   - Shadow Classification thresholds correct (0.3, 0.5)
   - Ambiguity detection logic sound

4. **API Design**: ✅
   - Function signatures correct
   - Export statements present
   - Helper functions well-designed

5. **Drift Report Template**: ✅
   - All required sections present
   - Classification legends clear
   - Example entries helpful

---

## Testing Evidence Review

**Implementation Report Claims**:
- ✅ Unit testing described (functions source correctly)
- ✅ Integration testing described (pre-flight check integration)
- ✅ Fallback testing described (grep mode)
- ❌ No evidence actual tests were run (no test output provided)

**Recommendation**: After fixes, provide test execution output:
```bash
# Test 1: Search with ck
bash -c 'source .claude/scripts/search-api.sh && semantic_search "authentication" "src/" 5 0.4'

# Test 2: Search without ck (simulate)
unset LOA_SEARCH_MODE
bash -c 'source .claude/scripts/search-api.sh && semantic_search "authentication" "src/" 5 0.4'

# Test 3: JSONL format validation
semantic_search "test" "src/" 1 0.4 | jq . >/dev/null && echo "Valid JSONL" || echo "Invalid JSONL"
```

---

## Acceptance Criteria Status

**Sprint 2 Acceptance Criteria** (from sprint.md):

### Task 2.1: Search Orchestrator
- ✅ Script created: `.claude/scripts/search-orchestrator.sh`
- ✅ Pre-flight check called before every search
- ✅ Search mode detection cached in LOA_SEARCH_MODE
- ✅ Three search types supported (semantic/hybrid/regex)
- ❌ **Output format**: NOT WORKING - results not returned to stdout
- ✅ Trajectory logging: Intent and execute phases present
- ✅ Absolute paths enforced

**Status**: 6/7 criteria met (86%)

---

### Task 2.2: Search API Functions
- ✅ Script created: `.claude/scripts/search-api.sh`
- ✅ Functions exported (semantic_search, hybrid_search, regex_search)
- ✅ Helper functions present (grep_to_jsonl, extract_snippet, estimate_tokens)
- ❌ **grep_to_jsonl**: NOT WORKING CORRECTLY - escaping issues
- ✅ Absolute path enforcement

**Status**: 4/5 criteria met (80%)

---

### Task 2.3: /ride Command Enhancement
- ⚠️ **NOT EVALUATED** - Task marked as "Integration only" in implementation report
- ⚠️ **NOTE**: Search API is ready, but /ride integration deferred

**Status**: Deferred (acceptable per implementation approach)

---

### Task 2.4: Negative Grounding Protocol
- ✅ Protocol file created: `.claude/protocols/negative-grounding.md`
- ✅ Two-query requirement documented
- ✅ Classification table correct (0/0-2, 0/3+, 1+)
- ✅ Query diversity guidelines clear
- ❌ **Trajectory logging examples**: Incorrect paths (Issue #3)
- ✅ Beads integration documented
- ✅ Drift report format correct

**Status**: 6/7 criteria met (86%)

---

### Task 2.5: Shadow System Classifier
- ✅ Protocol file created: `.claude/protocols/shadow-classification.md`
- ✅ Similarity thresholds correct (0.3, 0.5)
- ✅ Classification correct (Orphaned/Partial/Drifted)
- ✅ Dependency trace logic documented
- ❌ **Trajectory logging examples**: Incorrect paths (Issue #4)
- ✅ Beads integration documented

**Status**: 5/6 criteria met (83%)

---

### Task 2.6: Drift Report Template
- ✅ Template created: `loa-grimoire/reality/drift-report.md`
- ✅ All sections present (Ghosts, Shadows, Verified, Resolved)
- ✅ Tables with correct columns
- ✅ Auto-resolution logic documented
- ✅ Classification legends clear
- ✅ Example entries helpful

**Status**: 6/6 criteria met (100%)

---

## Overall Sprint Assessment

**Total Criteria**: 34 acceptance criteria across 6 tasks
**Met**: 27 criteria (79%)
**Failed**: 7 criteria (21%)

**Summary**:
- Core architecture: ✅ Excellent
- Protocol design: ✅ Correct
- Execution details: ❌ Critical bugs

---

## Remediation Plan

### Fix Priority Order

**Phase 1: Critical Output Issues** (30 minutes)
1. Fix search-orchestrator.sh output handling (Issue #1)
2. Fix search-orchestrator.sh result counting (Issue #2)
3. Fix search-api.sh grep_to_jsonl escaping (Issue #5)

**Phase 2: Trajectory Logging** (15 minutes)
4. Fix negative-grounding.md examples (Issue #3)
5. Fix shadow-classification.md examples (Issue #4)

**Phase 3: Dependency Handling** (10 minutes)
6. Add bc dependency check (Issue #6)

**Phase 4: Documentation** (5 minutes)
7. Update line counts in implementation report

**Total Estimated Fix Time**: 60 minutes

---

## Recommendation

**Status**: ❌ **CHANGES REQUIRED**

**Rationale**: The implementation demonstrates solid architectural understanding and protocol design, but contains critical functional bugs that will cause failures in real usage. These are straightforward fixes that should take ~1 hour.

**Next Steps**:
1. Engineer: Fix 6 critical issues listed above
2. Engineer: Update implementation report with corrected line counts
3. Engineer: Provide test execution output (semantic_search, hybrid_search, grep_to_jsonl)
4. Reviewer: Re-review after fixes (should be quick approval if fixes are correct)
5. Proceed to `/audit-sprint sprint-2` after approval

**Confidence**: Once fixed, implementation will be production-ready. The architecture is sound; only execution details need refinement.

---

**Submitted by**: reviewing-code (Senior Technical Lead)
**Date**: 2025-12-27
**Sprint**: 2 of 6
**Status**: ❌ Changes Required - Resubmit after fixes
