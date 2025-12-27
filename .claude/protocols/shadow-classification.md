# Shadow System Classification Protocol

> Inspired by technical debt research and Google's ADK Evaluation-Driven Development (EDD).

## Purpose

Identify and classify **undocumented code** - called "Shadow Systems" - by semantic similarity to existing documentation, enabling risk-based prioritization of documentation work.

## Problem Statement

Codebases contain functionality that exists but is undocumented:
- Legacy modules with no architectural documentation
- Quick fixes that became permanent
- Internal utilities never exposed in docs
- Experimental features that graduated to production

**Shadow Systems** represent reverse drift: code exists, but documentation doesn't - creating maintenance risk and knowledge silos.

## The Protocol: Similarity-Based Classification

Classify undocumented code by measuring semantic similarity to existing documentation, revealing how far the code has drifted from documented architecture.

### Step 1: Discover Exports

```bash
# Find all exported symbols (public API surface)
exports=$(regex_search "^export|module\.exports|pub fn|public class" "src/")

# Parse into modules
while IFS= read -r result; do
    file=$(echo "${result}" | jq -r '.file')
    line=$(echo "${result}" | jq -r '.line')
    snippet=$(echo "${result}" | jq -r '.snippet')

    # Extract module name
    module_name=$(basename "${file}" | sed 's/\.[^.]*$//')

    echo "${file}:${line}:${module_name}:${snippet}"
done <<< "${exports}"
```

### Step 2: Check Documentation Coverage

```bash
# For each discovered module, check if documented
for module in $(list_discovered_modules); do
    # Search all documentation
    doc_matches=$(semantic_search "${module}" "loa-grimoire/ docs/ README.md" 5 0.3)

    if [[ $(count_search_results <<< "${doc_matches}") -eq 0 ]]; then
        # Undocumented - classify as Shadow System
        classify_shadow_system "${module}"
    fi
done
```

### Step 3: Generate Functional Description

```bash
# Extract what the module DOES from code
file="/absolute/path/to/module.ts"
code_content=$(cat "${file}")

# Analyze exports, imports, and patterns to infer purpose
functional_description=$(infer_module_purpose "${code_content}")
# Example output: "authentication token validation and user session management"
```

**Inference Heuristics**:
- **Exports**: What does the module expose?
- **Imports**: What dependencies suggest purpose?
- **Patterns**: Common code patterns (CRUD, auth, caching, etc.)
- **Naming**: Module/function names reveal intent

### Step 4: Semantic Similarity Search

```bash
# Search documentation for semantic match
query="${module_name} ${functional_description}"
doc_matches=$(semantic_search "${query}" "loa-grimoire/ docs/ README.md" 5 0.3)

# Extract max similarity score
if [[ $(count_search_results <<< "${doc_matches}") -gt 0 ]]; then
    max_similarity=$(echo "${doc_matches}" | jq -r '.score' | sort -rn | head -1)
else
    max_similarity=0.0
fi
```

### Step 5: Classification

**Classification Thresholds**:

| Similarity | Classification | Risk | Interpretation |
|------------|----------------|------|----------------|
| < 0.3 | **Orphaned** | HIGH | No doc match - completely undocumented |
| 0.3 - 0.5 | **Partial** | LOW | Some doc coverage - incomplete |
| > 0.5 | **Drifted** | MEDIUM | Docs exist but are outdated |

```bash
if (( $(echo "${max_similarity} < 0.3" | bc -l) )); then
    classification="orphaned"
    risk="HIGH"
    action="Urgent documentation required"
elif (( $(echo "${max_similarity} > 0.5" | bc -l) )); then
    classification="drifted"
    risk="MEDIUM"
    action="Update existing docs"
else
    classification="partial"
    risk="LOW"
    action="Complete documentation"
fi
```

### Step 6: Dependency Trace (Orphaned Only)

For **Orphaned** systems (highest risk), generate dependency trace to understand impact:

```bash
# Find all files that import the undocumented module
module_name=$(basename "${file}" | sed 's/\.[^.]*$//')

import_patterns="import.*${module_name}|require.*${module_name}|from.*${module_name}|use.*${module_name}"

dependents=$(regex_search "${import_patterns}" "src/")
dependent_count=$(count_search_results <<< "${dependents}")

# Extract dependent file paths
dependent_files=$(echo "${dependents}" | jq -r '.file' | sort -u)
```

**Rationale**: Orphaned systems with many dependents are highest priority - they're critical but undocumented.

### Step 7: Tracking & Logging

#### If ORPHANED (High Risk):

```bash
# Track in Beads with high priority
if command -v bd >/dev/null 2>&1; then
    bd create "SHADOW (orphaned): ${module_name}" \
        --type debt \
        --priority 1 \
        --metadata "file=${file},similarity=${max_similarity},dependents=${dependent_count}"
fi

# Log to trajectory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME}" \
    --arg phase "shadow_detection" \
    --arg module "${file}" \
    --arg module_name "${module_name}" \
    --arg classification "orphaned" \
    --argjson similarity "${max_similarity}" \
    --argjson dependents "${dependent_count}" \
    --arg risk "HIGH" \
    '{ts: $ts, agent: $agent, phase: $phase, module: $module, module_name: $module_name, classification: $classification, similarity: $similarity, dependents: $dependents, risk: $risk}' \
    >> "${TRAJECTORY_FILE}"

# Write to drift report
echo "| ${module_name} | ${file} | Orphaned | HIGH | ${dependent_count} files | bd-124 | **Urgent: Document or remove** |" \
    >> loa-grimoire/drift-report.md
```

#### If DRIFTED (Medium Risk):

```bash
# Log to trajectory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME}" \
    --arg phase "shadow_detection" \
    --arg module "${file}" \
    --arg module_name "${module_name}" \
    --arg classification "drifted" \
    --argjson similarity "${max_similarity}" \
    --arg risk "MEDIUM" \
    --arg doc_match "${best_doc_match}" \
    '{ts: $ts, agent: $agent, phase: $phase, module: $module, module_name: $module_name, classification: $classification, similarity: $similarity, risk: $risk, doc_match: $doc_match}' \
    >> "${TRAJECTORY_FILE}"

# Write to drift report
echo "| ${module_name} | ${file} | Drifted | MEDIUM | N/A | - | Update ${best_doc_match} |" \
    >> loa-grimoire/drift-report.md
```

#### If PARTIAL (Low Risk):

```bash
# Log to trajectory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME}" \
    --arg phase "shadow_detection" \
    --arg module "${file}" \
    --arg module_name "${module_name}" \
    --arg classification "partial" \
    --argjson similarity "${max_similarity}" \
    --arg risk "LOW" \
    '{ts: $ts, agent: $agent, phase: $phase, module: $module, module_name: $module_name, classification: $classification, similarity: $similarity, risk: $risk}' \
    >> "${TRAJECTORY_FILE}"

# Write to drift report
echo "| ${module_name} | ${file} | Partial | LOW | N/A | - | Complete documentation |" \
    >> loa-grimoire/drift-report.md
```

## Classification Details

### Orphaned (< 0.3 similarity)

**Characteristics**:
- No semantic match to any documentation
- Completely undocumented functionality
- Highest maintenance risk

**Common Causes**:
- Legacy code from early development
- Quick fixes that became permanent
- Internal utilities never exposed
- Code inherited from acquisition/merge

**Mitigation Priority**: P0 - Document immediately or consider removal

**Example**:
```
Module: legacyHasher.ts
Similarity: 0.15
Dependents: 3 files (auth/handler.ts, users/service.ts, admin/auth.ts)
Action: Document legacy hashing algorithm or migrate to standard lib
```

### Partial (0.3 - 0.5 similarity)

**Characteristics**:
- Some documentation exists but incomplete
- Module mentioned but not fully explained
- Moderate documentation coverage

**Common Causes**:
- Work-in-progress documentation
- Module split from documented parent
- Docs written before refactor

**Mitigation Priority**: P2 - Complete during next sprint

**Example**:
```
Module: cacheHelpers.ts
Similarity: 0.42
Best Match: "Caching mentioned in PRD §4.3"
Action: Add cacheHelpers section to SDD §6.2
```

### Drifted (> 0.5 similarity)

**Characteristics**:
- Strong documentation match
- Docs exist but are outdated
- Code evolved beyond docs

**Common Causes**:
- Rapid iteration without doc updates
- Refactoring that changed implementation
- Feature enhancement beyond original spec

**Mitigation Priority**: P1 - Update docs to match current behavior

**Example**:
```
Module: authService.ts
Similarity: 0.67
Best Match: "Authentication described in PRD §3.1"
Action: Update PRD §3.1 to reflect JWT + refresh token approach
```

## Integration with /ride Command

The `/ride` command Phase D (Shadow Systems) should:

1. Discover all exports via regex search
2. For each export:
   - Check if documented
   - If not, classify via similarity
   - Generate dependency trace for orphaned
   - Track in Beads if high/medium risk
3. Write all findings to `loa-grimoire/drift-report.md`

## Search Strategy

### Documentation Sources

Search these locations in order:
1. `loa-grimoire/prd.md` - Functional requirements
2. `loa-grimoire/sdd.md` - Technical design
3. `loa-grimoire/legacy/INVENTORY.md` - Legacy docs inventory
4. `README.md` - High-level overview
5. `docs/` - Additional documentation

### Query Construction

```bash
# Build search query from module analysis
module_name="authService"
functional_description="authentication token validation user session"

# Combine for semantic search
query="${module_name} ${functional_description}"
```

## Threshold Rationale

**< 0.3 (Orphaned)**:
- Below 0.3 indicates no meaningful semantic relationship
- Docs would use completely different terminology
- Effectively undocumented

**0.3 - 0.5 (Partial)**:
- Moderate similarity suggests partial documentation
- Module mentioned but not detailed
- Mid-range coverage

**> 0.5 (Drifted)**:
- High similarity indicates strong doc match
- Code and docs refer to same concepts
- Docs exist but need updating

## Output Format

### Drift Report Entry

```markdown
## Technical Debt (Shadow Systems)

| Module | Location | Classification | Risk | Dependents | Beads ID | Action |
|--------|----------|----------------|------|------------|----------|--------|
| legacyHasher | src/auth/legacy.ts | Orphaned | HIGH | 3 files | bd-124 | **Urgent: Document or remove** |
| cacheUtils | src/utils/cache.ts | Drifted | MEDIUM | 12 files | - | Update PRD §4.3 |
| debugHelpers | src/dev/debug.ts | Partial | LOW | 1 file | - | Add to SDD §6.2 |
```

### Dependency Trace (Orphaned)

```markdown
### Orphaned System: legacyHasher

**Location**: src/auth/legacy.ts
**Similarity**: 0.15 (no doc match)
**Risk**: HIGH

**Dependent Files**:
1. src/auth/handler.ts:23 - `import { hashLegacy } from './legacy'`
2. src/users/service.ts:45 - `import { verifyLegacy } from '../auth/legacy'`
3. src/admin/auth.ts:67 - `import { hashLegacy, verifyLegacy } from '../auth/legacy'`

**Recommendation**: Document legacy hashing algorithm rationale or migrate to standard library (e.g., bcrypt).
```

## Anti-Patterns to Avoid

❌ **Keyword-Only Matching**
```bash
# BAD: Using grep instead of semantic search
if ! grep -q "${module_name}" loa-grimoire/*.md; then
    echo "Shadow System"
fi
```

✅ **Semantic Similarity**
```bash
# GOOD: Semantic search with threshold
doc_matches=$(semantic_search "${module_name} ${description}" "loa-grimoire/" 5 0.3)
max_similarity=$(echo "${doc_matches}" | jq -r '.score' | sort -rn | head -1)
```

❌ **Binary Classification**
```bash
# BAD: Only "documented" or "not documented"
if documented; then
    echo "Documented"
else
    echo "Shadow System"
fi
```

✅ **Risk-Based Classification**
```bash
# GOOD: Three-tier risk classification
if (( $(echo "${max_similarity} < 0.3" | bc -l) )); then
    risk="HIGH - Orphaned"
elif (( $(echo "${max_similarity} > 0.5" | bc -l) )); then
    risk="MEDIUM - Drifted"
else
    risk="LOW - Partial"
fi
```

## Grounding Ratio Impact

Shadow System classification contributes to grounding ratio:

- **Grounded Classification**: "Module X is orphaned (similarity=0.15, 0 doc matches)"
- **Ungrounded Classification**: "Module X seems undocumented" (no evidence)

## Related Protocols

- **Negative Grounding**: Opposite problem (docs exist, code missing)
- **Tool Result Clearing**: Apply after Shadow detection
- **Trajectory Evaluation**: Log all classifications with evidence

---

**Last Updated**: 2025-12-27
**Protocol Version**: 1.0
**PRD Reference**: FR-3.3
