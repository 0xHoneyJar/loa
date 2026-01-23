# Search Fallback Protocol

**Version**: 1.0
**Status**: Active
**Integration**: ck semantic search (Sprint 4)
**PRD Reference**: FR-11.1, FR-11.2
**SDD Reference**: §3.2

---

## Purpose

This protocol defines graceful degradation strategy when `ck` semantic search is not available. The system MUST work flawlessly with grep-based fallbacks, maintaining identical user experience regardless of which search mode is active.

---

## Core Principle

**ck is an invisible enhancement, never a requirement**. Users should NEVER know which search mode is active. The system MUST provide identical functionality and output format with both search modes.

---

## Search Mode Detection

### Single Detection Per Session

Detect once at command initialization:

```bash
#!/bin/bash
set -euo pipefail

# Detect ck availability
if command -v ck >/dev/null 2>&1; then
    export LOA_SEARCH_MODE="ck"
    export LOA_CK_VERSION=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
else
    export LOA_SEARCH_MODE="grep"
    export LOA_CK_VERSION=""
fi

# Log to trajectory (internal only, never user-facing)
if [[ -n "${LOA_TRAJECTORY_LOG:-}" ]]; then
    echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"search_mode\":\"${LOA_SEARCH_MODE}\",\"ck_version\":\"${LOA_CK_VERSION}\"}" >> "${LOA_TRAJECTORY_LOG}"
fi
```

**Never re-detect during session** - cache result in environment variable.

---

## Tool Selection Matrix

For each search operation, choose appropriate fallback:

| Task | With ck | Without ck (grep) | Quality Impact |
|------|---------|-------------------|----------------|
| **Find Entry Points** | `semantic_search("main entry bootstrap")` | `grep -rn "function main\|def main\|fn main\|class.*Main"` | Medium - grep catches explicit names only |
| **Find Abstractions** | `semantic_search("abstract base class interface")` | `grep -rn "abstract class\|interface\|trait"` | Medium - grep misses implicit abstractions |
| **Ghost Detection** | 2x `semantic_search()` with diverse queries | `grep` + manual review + pattern matching | High - grep cannot verify semantic absence |
| **Shadow Detection** | `regex_search("export\|module.exports\|pub fn")` | `grep -rn "export\|module.exports\|pub fn"` | Low - regex/grep equivalent |
| **Pattern Discovery** | `hybrid_search("pattern keywords")` | `grep` with keyword variations | Medium - grep requires more manual filtering |
| **Find Dependencies** | `semantic_search("imports <module>")` | `grep -rn "import.*<module>\|require.*<module>"` | Low - grep works well for imports |
| **Find Tests** | `hybrid_search("test <function>")` | `find + grep` for test file naming | Medium - grep relies on naming conventions |

---

## Search Implementation Patterns

### Pattern 1: Entry Point Discovery

**With ck** (v0.7.0+ syntax):
```bash
# ck v0.7.0+: --sem (not --semantic), --limit (not --top-k), path is positional (not --path)
ck --hybrid "main entry point bootstrap initialize startup" \
    --limit 10 \
    --threshold 0.5 \
    --jsonl "${PROJECT_ROOT}/src/" | jq -r '.path + ":" + (.line|tostring)'
```

**Grep Fallback**:
```bash
grep -rn \
    -E "function main|def main|fn main|class.*Main|async main|export.*main" \
    --include="*.js" --include="*.ts" --include="*.py" --include="*.rs" \
    "${PROJECT_ROOT}/src/" 2>/dev/null | head -10
```

**Output Normalization**: Both produce `<path>:<line>` format

---

### Pattern 2: Abstraction Discovery

**With ck** (v0.7.0+ syntax):
```bash
ck --sem "abstract base class interface trait protocol" \
    --limit 20 \
    --threshold 0.6 \
    --jsonl "${PROJECT_ROOT}/src/"
```

**Grep Fallback**:
```bash
grep -rn \
    -E "abstract class|interface |trait |protocol |^class.*\(.*\)" \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.rs" \
    "${PROJECT_ROOT}/src/" 2>/dev/null | head -20
```

---

### Pattern 3: Ghost Feature Detection (High Quality Loss)

**With ck (Negative Grounding Protocol)** (v0.7.0+ syntax):
```bash
# Query 1: Functional description
ck --sem "OAuth2 SSO login authentication provider" \
    --limit 5 \
    --threshold 0.4 \
    --jsonl "${PROJECT_ROOT}/src/" | wc -l
# Expected: 0 for confirmed Ghost

# Query 2: Architectural synonym
ck --sem "single sign-on identity provider federated auth" \
    --limit 5 \
    --threshold 0.4 \
    --jsonl "${PROJECT_ROOT}/src/" | wc -l
# Expected: 0 for confirmed Ghost

# GHOST confirmed if BOTH queries return 0
```

**Grep Fallback (Lower Confidence)**:
```bash
# Keyword search (high false-negative risk)
RESULT_COUNT=$(grep -ri \
    -E "oauth|sso|single.sign.on|saml|openid" \
    --include="*.ts" --include="*.js" --include="*.py" \
    "${PROJECT_ROOT}/src/" 2>/dev/null | wc -l)

if [[ "${RESULT_COUNT}" -eq 0 ]]; then
    # Likely Ghost, but lower confidence
    # Check documentation for mentions
    DOC_COUNT=$(grep -ri "oauth\|sso" grimoires/loa/*.md docs/*.md 2>/dev/null | wc -l)

    if [[ "${DOC_COUNT}" -gt 3 ]]; then
        echo "GHOST (Low Confidence): OAuth documented but not found in code"
        echo "AMBIGUITY: ${DOC_COUNT} doc mentions, recommend manual audit"
    fi
fi
```

**Quality Impact**: Ghost detection with grep has ~40% false-positive rate (may miss alternative spellings, conceptual implementations)

---

### Pattern 4: Shadow System Detection (Minimal Quality Loss)

**With ck** (v0.7.0+ syntax):
```bash
ck --regex "^export |module\.exports|pub fn |pub struct " \
    --jsonl "${PROJECT_ROOT}/src/"
```

**Grep Fallback**:
```bash
grep -rn \
    -E "^export |module\.exports|pub fn |pub struct " \
    --include="*.ts" --include="*.js" --include="*.rs" \
    "${PROJECT_ROOT}/src/" 2>/dev/null
```

**Quality Impact**: Minimal - regex patterns work equally well in both modes

---

### Pattern 5: Dependency Discovery

**With ck** (v0.7.0+ syntax):
```bash
ck --regex "import.*${MODULE_NAME}|from.*${MODULE_NAME}|require\(.*${MODULE_NAME}" \
    --jsonl "${PROJECT_ROOT}/src/"
```

**Grep Fallback**:
```bash
grep -rn \
    -E "import.*${MODULE_NAME}|from.*${MODULE_NAME}|require\(.*${MODULE_NAME}" \
    --include="*.ts" --include="*.js" --include="*.py" \
    "${PROJECT_ROOT}/src/" 2>/dev/null
```

**Quality Impact**: None - identical regex approach

---

## Quality Indicators (Internal Logging Only)

Log search quality to trajectory (NEVER show to user):

```jsonl
{
  "ts": "2024-01-15T10:30:00Z",
  "agent": "implementing-tasks",
  "phase": "context_load",
  "search_mode": "ck",
  "precision": "high",
  "cache_hit": true,
  "semantic_capability": true
}
```

```jsonl
{
  "ts": "2024-01-15T10:30:00Z",
  "agent": "implementing-tasks",
  "phase": "context_load",
  "search_mode": "grep",
  "precision": "medium",
  "cache_hit": false,
  "semantic_capability": false,
  "limitations": ["no_semantic_search", "higher_false_positive_rate"]
}
```

**Purpose**: Debugging, analytics, quality assessment - NOT user communication

---

## Communication Guidelines

### NEVER Say to User

❌ **Forbidden Phrases**:
- "Using ck for semantic search..."
- "Falling back to grep because ck isn't installed..."
- "For better results, install ck..."
- "The semantic search found..."
- "Enhanced search mode enabled..."
- "Basic search mode (grep) active..."
- "Semantic search unavailable, using keyword search..."

### ALWAYS Say to User

✅ **Approved Phrases**:
- "Analyzing codebase structure..."
- "Searching for entry points..."
- "Discovering architectural patterns..."
- "Cross-referencing documentation with implementation..."
- "Finding related code..."
- "Identifying test coverage..."
- "Detecting undocumented modules..."
- "Verifying feature implementation..."

**Rationale**: User experience MUST be identical regardless of tool availability.

---

## Output Format Normalization

Both search modes MUST produce identical output format:

### Standard Format

```
<absolute_path>:<line_number>
/home/user/project/src/auth/jwt.ts:45
/home/user/project/src/auth/middleware.ts:23
```

### With Snippet Format

```
<absolute_path>:<line_number>: <code_snippet>
/home/user/project/src/auth/jwt.ts:45: export async function validateToken(
/home/user/project/src/auth/middleware.ts:23: import { validateToken } from './jwt'
```

### JSONL Format (ck only, internal use)

```jsonl
{"path":"/home/user/project/src/auth/jwt.ts","line":45,"score":0.89,"snippet":"export async function validateToken"}
```

**Conversion**: Parse JSONL internally, output normalized format to user

---

## Fallback Mitigation Strategies

When grep fallback active, agents should:

1. **Use Multiple Keyword Variations**:
   ```bash
   # Instead of single keyword
   grep -rn "authentication" src/

   # Use multiple related keywords
   grep -rn "auth\|authentication\|login\|verify\|validate" src/
   ```

2. **Leverage File Naming Conventions**:
   ```bash
   # Find test files by name
   find tests/ -name "*auth*test*" -o -name "*auth*spec*"
   ```

3. **Increase Result Review Threshold**:
   - With ck: Review top 10 results (high precision)
   - With grep: Review top 20 results (lower precision, more noise)

4. **Apply Manual Filtering**:
   - Remove false positives from grep output
   - Cross-reference against PRD/SDD
   - Verify relevance before synthesizing

5. **Flag Ambiguity Explicitly**:
   ```markdown
   ## Ghost Feature Detection: OAuth2 SSO
   **Confidence**: Low (grep-based detection)
   **Recommendation**: Manual code inspection advised
   **Search Results**: 0 keyword matches for "oauth", "sso", "saml"
   **Documentation**: 5 PRD mentions found
   **Verdict**: Likely Ghost, but recommend human audit
   ```

---

## Integration with Search Orchestrator

The search orchestrator (`search-orchestrator.sh`) MUST:

1. Detect search mode once per session
2. Route to appropriate search function
3. Normalize output format
4. Apply quality logging (internal)
5. Return identical format regardless of mode

```bash
# .claude/scripts/search-orchestrator.sh (v0.7.0+ ck syntax)
function search_semantic() {
    local query="$1"
    local path="$2"
    local top_k="${3:-10}"
    local threshold="${4:-0.5}"

    if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
        # ck v0.7.0+: --sem (not --semantic), --limit (not --top-k), path is positional
        ck --sem "${query}" \
            --limit "${top_k}" \
            --threshold "${threshold}" \
            --jsonl "${path}" | jq -r '.path + ":" + (.line|tostring)'
    else
        # Fallback: Extract keywords, use grep
        local keywords=$(echo "${query}" | tr ' ' '|')
        grep -rn -E "${keywords}" \
            --include="*.ts" --include="*.js" --include="*.py" \
            "${path}" 2>/dev/null | head -"${top_k}"
    fi
}
```

---

## Error Handling

### ck Installation Broken

If ck installed but non-functional:

```bash
if command -v ck >/dev/null 2>&1; then
    # Test ck functionality
    if ck --version >/dev/null 2>&1; then
        LOA_SEARCH_MODE="ck"
    else
        # ck broken, fall back silently
        LOA_SEARCH_MODE="grep"
        # Log to trajectory (not user-facing)
        echo "WARN: ck installed but non-functional, using grep" >> "${LOA_TRAJECTORY_LOG}"
    fi
else
    LOA_SEARCH_MODE="grep"
fi
```

**Never show user**: "ck is broken" or "ck error"

### Grep Failures

If grep also fails (rare):

```bash
if ! grep --version >/dev/null 2>&1; then
    echo "ERROR: Search tools unavailable. Cannot proceed." >&2
    exit 1
fi
```

**This is acceptable to show** - grep is a core system requirement

---

## Testing Strategy

### Test Case 1: Entry Point Discovery

**Setup**: Test repository with main() in src/index.ts

**With ck**:
```bash
LOA_SEARCH_MODE="ck"
source search-orchestrator.sh
search_entry_points "src/"
# Expected: src/index.ts:15
```

**Without ck**:
```bash
LOA_SEARCH_MODE="grep"
source search-orchestrator.sh
search_entry_points "src/"
# Expected: src/index.ts:15
```

**Validation**: Output format identical

### Test Case 2: Ghost Feature Detection

**Setup**: PRD mentions "OAuth2" (5 times), no OAuth in code

**With ck**:
```bash
detect_ghost_feature "OAuth2 SSO login" "src/"
# Expected: GHOST confirmed (2 semantic queries, both 0 results)
```

**Without ck**:
```bash
detect_ghost_feature "OAuth2 SSO login" "src/"
# Expected: GHOST (Low Confidence) - 0 grep results, 5 doc mentions
```

**Validation**: Both detect Ghost, grep flags lower confidence

---

## Success Criteria

Fallback implementation is successful when:
- [ ] Detection runs once per session
- [ ] Tool selection matrix implemented for all operations
- [ ] Output format identical regardless of mode
- [ ] No user-facing error messages when ck missing
- [ ] Quality indicators logged to trajectory (internal only)
- [ ] Communication guidelines enforced (never mention tool names)
- [ ] All tests pass with both modes

---

## Integration Points

This protocol integrates with:
- `.claude/scripts/search-orchestrator.sh` - Tool routing
- `.claude/protocols/tool-result-clearing.md` - Memory management
- `.claude/protocols/negative-grounding.md` - Ghost detection
- `.claude/protocols/shadow-classification.md` - Shadow detection
- `.claude/skills/*/context-retrieval.md` - Skill integration

---

## Anti-Patterns

❌ **NEVER DO**:
- Mention "ck" or "grep" to user
- Show different output format based on mode
- Display error when ck missing
- Re-detect search mode multiple times per session
- Block operations when ck unavailable

✅ **ALWAYS DO**:
- Detect mode once, cache in environment
- Normalize output format
- Silent fallback to grep
- Identical user experience
- Log quality indicators to trajectory (internal)

---

**Status**: Active from Sprint 4
**Review**: After Sprint 5 validation
