# Enterprise Integration: ck Semantic Search → Loa Framework

## Mission Brief

You are a **Principal Engineer** at a FAANG-tier organization. Your mission is to integrate `ck` (seek) semantic/hybrid search as a first-class capability within the **Loa agent framework**. This integration must meet the engineering standards of AWS Projen, Google ADK, and Anthropic's Agent SDK.

**Key Design Principles (following beads pattern):**
1. **Surface installation at setup** - ck is listed as an optional dependency in `/setup` and INSTALLATION.md
2. **Invisible to user** - Once installed, ck enhances /ride seamlessly without user intervention  
3. **Graceful degradation** - All commands work without ck; ck just makes them better
4. **Zero friction** - No new slash commands for users to learn; ck is internal tooling

---

## Agent-Computer Interface (ACI) Standards

### XML-Structured Protocol Sections

The integration uses XML tags to delineate instruction sections for reliable agent parsing:

```xml
<integrity_protocol>
  <!-- Pre-flight checks, checksum verification -->
</integrity_protocol>

<context_engineering>
  <!-- Attention budgets, Tool Result Clearing, JIT loading -->
</context_engineering>

<trajectory_evaluation>
  <!-- Search logging, EDD verification, grounding ratios -->
</trajectory_evaluation>

<truth_hierarchy>
  <!-- Ghost/Shadow detection, conflict resolution -->
</truth_hierarchy>

<search_execution>
  <!-- Actual ck commands with absolute paths -->
</search_execution>
```

### Absolute Filepath Mandate

**Always use absolute paths in ck commands.** Models frequently struggle with relative paths after navigating directories.

```bash
# BAD: Relative path (error-prone after cd)
ck --hybrid "authentication" src/

# GOOD: Absolute path (reliable regardless of cwd)
ck --hybrid "authentication" "${PROJECT_ROOT}/src/"

# In practice:
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ck --hybrid "authentication" "${PROJECT_ROOT}/src/"
```

### Word-for-Word Citation Format

Citations must include **actual code quotes**, not just file:line references:

```markdown
# BAD: Reference only
"The system uses JWT [src/auth/jwt.ts:45]"

# GOOD: Word-for-word quote with reference
"The system uses JWT: `export async function validateToken(token: string)` [src/auth/jwt.ts:45]"
```

---

## Quick Reference: beads Integration Pattern

The beads integration in Loa follows this pattern that ck should mirror:

```
INSTALLATION:
├── Listed in INSTALLATION.md as optional enhancement
├── Checked during /setup with clear install instructions
├── Works without it (graceful degradation)
└── Silent enhancement when present

USAGE:
├── No user-facing commands required for daily use
├── Agents use tooling internally 
├── Fallback to simpler tools if unavailable
└── User never needs to know which tool is being used

STATE:
├── .beads/ directory (like .ck/ for semantic indexes)
├── Listed in .gitignore
└── Survives framework updates
```

---

## Architectural Context

### The Loa Three-Zone Model

```
┌─────────────────────────────────────────────────────────────────┐
│                        LOA FRAMEWORK                            │
├─────────────────────────────────────────────────────────────────┤
│  SYSTEM ZONE (.claude/)           │  Owner: Framework           │
│  ├── skills/                      │  Mutability: IMMUTABLE      │
│  ├── commands/                    │  Updates: Framework only    │
│  ├── protocols/                   │  Checksums: ENFORCED        │
│  └── checksums.json               │                             │
├───────────────────────────────────┼─────────────────────────────┤
│  STATE ZONE (loa-grimoire/, .ck/) │  Owner: Project/Tooling     │
│  ├── loa-grimoire/NOTES.md        │  Mutability: Agent-managed  │
│  ├── loa-grimoire/reality/        │  Updates: Survives resets   │
│  ├── loa-grimoire/a2a/trajectory/ │  Git: Selectively committed │
│  ├── .ck/                         │  Git: NEVER committed       │
│  │   ├── embeddings.json          │  Purpose: Search index cache│
│  │   ├── ann_index.bin            │  Lifecycle: Auto-managed    │
│  │   └── tantivy_index/           │  Rebuilds: On-demand        │
│  └── .beads/                      │  Git: Committed (task state)│
├───────────────────────────────────┼─────────────────────────────┤
│  APP ZONE (src/, lib/, app/)      │  Owner: Developer           │
│  └── [Your application code]      │  Mutability: User-owned     │
│                                   │  Updates: Never touched     │
└─────────────────────────────────────────────────────────────────┘
```

### Zone Assignment Rules

| Artifact | Zone | Git Status | Rationale |
|----------|------|------------|-----------|
| `.claude/` (except overrides) | System | Committed | Framework-managed, checksummed, IMMUTABLE |
| `.claude/overrides/` | User | Committed | Safe customization zone |
| `.ck/` | State | **Never committed** | Cache only, rebuilds automatically |
| `loa-grimoire/` | State | Selectively | Project memory, survives updates |
| `.beads/` | State | Committed | Task tracking, shared state |
| `src/` | App | Committed | Developer-owned code |

### Synthesis Protection

**Users MUST NOT edit files in `.claude/` directly (except `.claude/overrides/`).**

```
.claude/                          # SYSTEM ZONE - IMMUTABLE
├── mcp-registry.yaml            # DO NOT EDIT
├── checksums.json               # DO NOT EDIT  
├── commands/                    # DO NOT EDIT
├── protocols/                   # DO NOT EDIT
└── overrides/                   # USER ZONE - Safe for customization
    ├── ck-config.yaml           # Custom ck settings (EDITABLE)
    └── search-thresholds.yaml   # Custom thresholds (EDITABLE)
```

**Override Precedence:**
1. `.claude/overrides/*` (user customization) - highest priority
2. `.claude/*` (framework defaults) - fallback

### The Immutable Truth Hierarchy

```
AUTHORITY (highest to lowest):
    
    CODE (src/)           ← Absolute truth, verified by ck
         ↓
    ck INDEX (.ck/)       ← Derived from code, auto-updated
         ↓
    NOTES.md              ← Agent synthesis, grounded in search
         ↓
    PRD/SDD               ← Design intent, may drift from code
         ↓
    LEGACY DOCS           ← Historical, often stale
         ↓
    USER CONTEXT          ← Input, requires validation

CONFLICT RESOLUTION:
When documentation claims X but ck search shows Y:
→ ALWAYS side with the code
→ Document discrepancy as Strategic Liability
→ Track in Beads for remediation
→ Update docs to match code (not vice versa)
```

---

## Phase 1: Installation & Setup Integration

### Objective
Surface ck as an optional dependency during setup, following the beads pattern.

### 1.1 Update INSTALLATION.md

Add to `INSTALLATION.md` in the Optional Enhancements section:

```markdown
## Optional Enhancements

These tools are optional but provide enhanced capabilities when installed.

### Semantic Code Search (ck)

For enhanced codebase analysis during `/ride` and `/mount` workflows:

```bash
# Install via cargo (Rust toolchain required)
cargo install ck-search

# Verify installation
ck --version
```

**Benefits when installed:**
- `/ride` uses semantic search to detect Ghost Features and Shadow Systems
- Agents retrieve context "just-in-time" instead of loading entire files
- 80-90% faster context loading via delta-indexed embeddings
- Higher precision code discovery (semantic vs keyword matching)

**Without ck:** All commands work normally using grep-based fallbacks.

### Task Tracking (beads)

For structured task management:

```bash
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
bd init
```
```

### 1.2 Update /setup Command

Modify `.claude/commands/setup.md` to check for ck:

```markdown
# /setup

## Dependency Verification

### Required
- [ ] Claude Code CLI installed
- [ ] Git repository initialized

### Optional Enhancements

The following tools enhance Loa's capabilities but are not required:

#### Check Installation Status
```bash
echo "=== Optional Enhancement Status ==="

# beads (Task Tracking)
if command -v bd >/dev/null 2>&1; then
    echo "✓ beads installed: $(bd --version 2>/dev/null | head -1)"
else
    echo "○ beads not installed (optional)"
    echo "  Install: curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
fi

# ck (Semantic Search)
if command -v ck >/dev/null 2>&1; then
    echo "✓ ck installed: $(ck --version 2>/dev/null | head -1)"
else
    echo "○ ck not installed (optional)"
    echo "  Install: cargo install ck-search"
fi

echo ""
echo "All Loa commands work without optional tools."
echo "They provide enhanced capabilities when present."
```

### Setup Complete Messages

Display based on what's installed:

| beads | ck | Message |
|-------|-----|---------|
| ✗ | ✗ | "Setup complete. For enhanced capabilities, see INSTALLATION.md" |
| ✓ | ✗ | "Setup complete with task tracking. For semantic search: cargo install ck-search" |
| ✗ | ✓ | "Setup complete with semantic search. For task tracking: see INSTALLATION.md" |
| ✓ | ✓ | "Setup complete with full enhancement suite." |
```

### 1.3 Update README.md

Add to Quick Start section:

```markdown
## Quick Start

### Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| Claude Code | Yes | Agent interface |
| Git | Yes | Version control |
| beads | No | Task tracking (enhanced) |
| ck | No | Semantic search (enhanced) |

### Optional: Install Enhancements

```bash
# Task tracking (beads)
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# Semantic search (ck)
cargo install ck-search
```

All Loa commands work without optional tools. They provide enhanced capabilities when present.
```

### 1.4 Update .gitignore

Ensure `.ck/` is excluded:

```gitignore
# Loa Framework
.beads/
.ck/
loa-grimoire/a2a/trajectory/
```

---

## Phase 1.5: Pre-Flight Integrity Protocol (AWS Projen Level)

### Objective
Before any ck operation, verify System Zone integrity to prevent operating on compromised state.

### 1.5.1 Integrity Check (Internal)

Add to `.claude/protocols/preflight-integrity.md`:

```markdown
# Pre-Flight Integrity Protocol

## When to Execute
Before ANY ck search operation (semantic, hybrid, regex).

## Check Sequence

```bash
# 1. Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# 2. Get enforcement level
if [[ -f "${PROJECT_ROOT}/.loa.config.yaml" ]]; then
    ENFORCEMENT=$(grep "integrity_enforcement:" "${PROJECT_ROOT}/.loa.config.yaml" | awk '{print $2}' || echo "warn")
else
    ENFORCEMENT="warn"
fi

# 3. Check for overrides (Synthesis Protection)
# Custom ck configs go in .claude/overrides/, NOT in System Zone
if [[ -f "${PROJECT_ROOT}/.claude/overrides/ck-config.yaml" ]]; then
    echo "INFO: Using custom ck config from .claude/overrides/" >&2
    CK_CONFIG="${PROJECT_ROOT}/.claude/overrides/ck-config.yaml"
else
    CK_CONFIG="${PROJECT_ROOT}/.claude/mcp-registry.yaml"
fi

# 4. Verify System Zone checksums (if strict mode)
if [[ -f "${PROJECT_ROOT}/.claude/checksums.json" ]] && command -v jq >/dev/null 2>&1; then
    CHECKSUM_VALID=true
    
    # Check each registered file (skip overrides - those are user-owned)
    for file in $(jq -r '.files | keys[]' "${PROJECT_ROOT}/.claude/checksums.json" 2>/dev/null); do
        if [[ -f "${PROJECT_ROOT}/$file" ]]; then
            expected=$(jq -r ".files[\"$file\"]" "${PROJECT_ROOT}/.claude/checksums.json")
            actual=$(sha256sum "${PROJECT_ROOT}/$file" 2>/dev/null | cut -d' ' -f1)
            if [[ "$expected" != "$actual" && "$expected" != "null" ]]; then
                CHECKSUM_VALID=false
                echo "DRIFT DETECTED: $file" >&2
            fi
        fi
    done
    
    if [[ "$CHECKSUM_VALID" == "false" ]]; then
        if [[ "$ENFORCEMENT" == "strict" ]]; then
            echo "HALT: System Zone integrity violation. Run /update to restore." >&2
            exit 1
        else
            echo "WARNING: System Zone drift detected. Results may be inconsistent." >&2
        fi
    fi
fi
```

## Synthesis Protection

**Users MUST NOT edit files in `.claude/` directly.**

For legitimate customization, use the overrides directory:

```
.claude/                          # SYSTEM ZONE - Framework-managed, IMMUTABLE
├── mcp-registry.yaml            # Default ck configuration (DO NOT EDIT)
├── checksums.json               # Integrity manifest (DO NOT EDIT)
├── commands/                    # Slash commands (DO NOT EDIT)
├── protocols/                   # Protocols (DO NOT EDIT)
└── overrides/                   # USER ZONE - Safe for customization
    ├── ck-config.yaml           # Custom ck settings (EDITABLE)
    └── search-thresholds.yaml   # Custom thresholds (EDITABLE)
```

**Override Precedence:**
1. `.claude/overrides/*` (user customization) - highest priority
2. `.claude/*` (framework defaults) - fallback

**What Can Be Overridden:**
- `ck-config.yaml`: Model, thresholds, page size, snippet length
- `search-thresholds.yaml`: Ghost/Shadow detection thresholds
- Custom ignore patterns for indexing

**What CANNOT Be Overridden:**
- Core protocols (integrity, trajectory, truth hierarchy)
- Command definitions
- Zone assignments

## Enforcement Levels

| Level | On Drift | On Missing .ck/ |
|-------|----------|-----------------|
| `strict` | HALT execution, require /update | **Self-heal**: Trigger silent reindex |
| `warn` | Log warning, continue with caution | Trigger reindex with notice |
| `disabled` | No integrity checks | No action |

## Self-Healing State Zone (Delta-First Strategy)

In strict mode, the State Zone must be self-healing. Prefer delta-updates over full reindex:

```bash
# If .ck/ is missing or corrupted, attempt delta-update first (faster)
if [[ ! -d "${PROJECT_ROOT}/.ck" ]] || [[ ! -f "${PROJECT_ROOT}/.ck/embeddings.json" ]]; then
    # Check if delta update is possible
    if [[ -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
        LAST_INDEXED=$(cat "${PROJECT_ROOT}/.ck/.last_commit" 2>/dev/null)
        CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null)
        
        if [[ -n "$LAST_INDEXED" && -n "$CURRENT_HEAD" ]]; then
            CHANGED_FILES=$(git diff --name-only "$LAST_INDEXED" "$CURRENT_HEAD" 2>/dev/null | wc -l)
            
            if [[ "$CHANGED_FILES" -lt 100 ]]; then
                echo "INFO: Delta reindexing $CHANGED_FILES changed files" >&2
                ck --index "${PROJECT_ROOT}" --delta --quiet 2>/dev/null &
            else
                echo "INFO: Full reindex required ($CHANGED_FILES files)" >&2
                ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
            fi
        fi
    else
        # No previous state, full reindex required
        echo "INFO: Initial index build in progress" >&2
        ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
    fi
fi
```

## Version Pinning (Schema Drift Prevention)

Verify ck version matches framework requirements:

```bash
if [[ -f "${PROJECT_ROOT}/.loa-version.json" ]] && command -v jq >/dev/null 2>&1; then
    REQUIRED_CK=$(jq -r '.dependencies.ck // "0.7.0"' "${PROJECT_ROOT}/.loa-version.json")
    INSTALLED_CK=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    
    if [[ "$(printf '%s\n' "$REQUIRED_CK" "$INSTALLED_CK" | sort -V | head -1)" != "$REQUIRED_CK" ]]; then
        echo "WARNING: ck $INSTALLED_CK may not meet requirement $REQUIRED_CK" >&2
    fi
fi
```

## Binary Integrity Verification (Elite Security)

Beyond version checks, verify the ck binary itself hasn't been tampered with:

```bash
# Binary hash verification (if fingerprint available in .loa-version.json)
if [[ -f "${PROJECT_ROOT}/.loa-version.json" ]] && command -v jq >/dev/null 2>&1; then
    EXPECTED_HASH=$(jq -r '.binary_hashes.ck // ""' "${PROJECT_ROOT}/.loa-version.json")
    
    if [[ -n "$EXPECTED_HASH" ]]; then
        CK_PATH=$(which ck 2>/dev/null)
        if [[ -n "$CK_PATH" ]]; then
            ACTUAL_HASH=$(sha256sum "$CK_PATH" 2>/dev/null | cut -d' ' -f1)
            
            if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
                if [[ "$ENFORCEMENT" == "strict" ]]; then
                    echo "HALT: ck binary integrity check failed" >&2
                    echo "Expected: $EXPECTED_HASH" >&2
                    echo "Actual:   $ACTUAL_HASH" >&2
                    exit 1
                else
                    echo "WARNING: ck binary hash mismatch - possible tampering" >&2
                fi
            fi
        fi
    fi
fi
```

## Agent Behavior

- If integrity check fails in strict mode: Do NOT proceed with ck operations
- If integrity check warns: Log to trajectory, proceed with degraded confidence
- Never surface integrity status to user unless explicitly asked
```

---

## Phase 2: Seamless /ride Integration with Graceful Fallbacks

### Objective
Make ck invisible to users. The /ride command automatically uses ck when available, falls back to grep when not.

### 2.1 Just-in-Time Context Principle

**Never load whole files. Retrieve the smallest possible set of high-signal tokens.**

```xml
<context_engineering>
  <!-- Always use absolute paths -->
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
</context_engineering>
```

Instead of:
```python
# BAD: Loading entire file
with open("src/auth/handler.ts") as f:
    content = f.read()  # 2000 lines, 50k tokens
```

Do this:
```bash
# GOOD: Just-in-time retrieval with absolute path and JSONL
ck --hybrid "JWT validation entry point" \
    --path "${PROJECT_ROOT}/src/auth/" \
    --top-k 5 \
    --snippet-length 100 \
    --jsonl
# Returns: 5 relevant snippets, ~500 tokens total
```

### 2.2 Search Mode Prioritization

| Operation | Preferred Tool | Rationale |
|-----------|---------------|-----------|
| /ride analysis | `--hybrid` | Combines keyword precision + semantic understanding |
| Ghost detection | `--sem` (semantic) | Catches conceptual matches across naming variations |
| Shadow detection | `--regex` | Finds exact export patterns |
| Context loading | `--hybrid` | Best balance of precision and recall |
| Pattern matching | `--regex` | Deterministic, no false positives |

### 2.3 Tiered Search Protocol (Broad→Narrow→JIT)

Follow a **three-level retrieval strategy** to maximize signal while minimizing tokens:

```xml
<tiered_search_protocol>
  <!-- Level 1: Broad Semantic Discovery -->
  <level_1 name="semantic_discovery">
    <tool>ck --sem</tool>
    <purpose>Find conceptual candidates across naming variations</purpose>
    <threshold>Dynamic (see below)</threshold>
    <output>Candidate file list (paths only)</output>
  </level_1>
  
  <!-- Level 2: Hybrid Precision Filtering -->
  <level_2 name="hybrid_filtering">
    <tool>ck --hybrid</tool>
    <purpose>Narrow candidates using keyword precision</purpose>
    <input>Top 10-20 candidates from Level 1</input>
    <output>Ranked results with snippets</output>
  </level_2>
  
  <!-- Level 3: JIT Full-Section Loading -->
  <level_3 name="jit_reading">
    <tool>ck --full-section (AST-aware)</tool>
    <purpose>Load complete logical blocks for top 3 candidates ONLY</purpose>
    <input>Top 3 results from Level 2</input>
    <output>Full functions/classes (tree-sitter parsed)</output>
  </level_3>
</tiered_search_protocol>
```

**AST-Aware Snippets:** Use `--full-section` to capture complete logical blocks (functions/classes) rather than arbitrary line counts. This leverages ck's tree-sitter parsing.

### 2.4 Dynamic Thresholding

Adjust thresholds based on task criticality:

| Task Type | Threshold | Rationale |
|-----------|-----------|-----------|
| **Security/Hygiene** | 0.8 | High precision required, false negatives acceptable |
| **Core Architecture** | 0.6 | Balanced precision/recall |
| **Discovery/PRD** | 0.4 | Exploratory, capture all candidates |
| **Ghost Feature Detection** | 0.4 | Low threshold to confirm absence |

**Model Selection Rationale:** The agent must justify model choice in trajectory:

| Model | Use Case | Trajectory Justification |
|-------|----------|-------------------------|
| `bge-small` | Fast discovery, large codebase | "Using bge-small for speed on initial discovery pass" |
| `nomic-v1.5` | Balanced general use | "Using nomic-v1.5 for balanced precision/recall" |
| `jina-code` | Precise code understanding | "Using jina-code for high-precision security analysis" |

**Model-Agnostic Negative Justification (Required):**

The agent must also justify why it is NOT using a larger/more precise model:

```jsonl
{
  "phase": "model_selection",
  "selected": "bge-small",
  "positive_rationale": "Fast discovery needed for initial 1M LOC scan",
  "negative_rationale": "NOT using jina-code because: (1) discovery pass prioritizes speed over precision, (2) preserving attention budget for subsequent hybrid filtering, (3) false positives acceptable at this stage"
}
```

This prevents defaulting to heavyweight models without cost-benefit analysis.

### 2.5 Enhanced /ride Command

Update `.claude/commands/ride.md`:

```markdown
# /ride - Mount and Analyze Existing Codebase

## Overview

Analyzes an existing codebase to generate evidence-grounded documentation.
Automatically uses the best available search tooling.

## Internal: Search Strategy Selection

```xml
<search_initialization>
  <!-- Establish absolute path root - models struggle with relative paths -->
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  
  <!-- Detect available search tooling -->
  if command -v ck >/dev/null 2>&1; then
      SEARCH_MODE="semantic"
      ck --status "${PROJECT_ROOT}" >/dev/null 2>&1 || ck --index "${PROJECT_ROOT}"
  else
      SEARCH_MODE="grep"
  fi
</search_initialization>
```

## Code Reality Extraction

### Phase A: Entry Point Discovery

**Intent (log before search):**
```xml
<search_execution>
  <intent>Identify application entry points and bootstrap sequences</intent>
  <rationale>Understanding startup flow required for architectural analysis</rationale>
</search_execution>
```

**With ck (semantic) - using absolute paths and JSONL:**
```bash
ck --hybrid "main entry point bootstrap initialize startup" \
    --path "${PROJECT_ROOT}/src/" \
    --top-k 10 \
    --threshold 0.5 \
    --jsonl
```

**Fallback (grep) - using absolute paths:**
```bash
grep -rn "function main\|def main\|fn main\|void main\|export default" \
  --include="*.js" --include="*.ts" --include="*.py" --include="*.rs" \
  "${PROJECT_ROOT}/src/" 2>/dev/null | head -20
```

**Citation (word-for-word quote required):**
```markdown
Entry point: `export default async function bootstrap()` [${PROJECT_ROOT}/src/index.ts:15]
```

### Phase B: Core Abstraction Discovery

**Intent:**
```xml
<search_execution>
  <intent>Map core abstractions, interfaces, and base classes</intent>
  <rationale>Required to understand extension points and architectural patterns</rationale>
</search_execution>
```

**With ck (semantic):**
```bash
ck --hybrid "abstract class interface trait protocol base" \
    --path "${PROJECT_ROOT}/src/" \
    --top-k 30 \
    --threshold 0.4 \
    --jsonl
```

**Fallback (grep):**
```bash
grep -rn "abstract class\|interface \|trait \|protocol \|extends\|implements" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.rs" \
  "${PROJECT_ROOT}/src/" 2>/dev/null
```

### Phase C: Ghost Feature Detection (with Beads Integration)

**With ck (semantic):**
For each feature documented in PRD/legacy docs:
```tool_call
semantic_search(
  query: "<documented_feature_description>",
  path: "src/",
  threshold: 0.6
)
```
If `results.length == 0`: Flag as GHOST FEATURE

**Fallback (grep):**
```bash
# Extract key terms from feature description
for term in <key_terms>; do
  grep -rn "$term" src/ --include="*.{ts,js,py,rs,go}" 2>/dev/null
done
# If no matches: Flag as potential GHOST FEATURE
# Note: Higher false-positive rate with grep
```

**Beads Integration (if available):**
```bash
# Track Ghost Features as Strategic Liabilities
if command -v bd >/dev/null 2>&1; then
    bd create "GHOST: <feature_name> documented but not found in code" \
        --type liability \
        --priority 2 \
        --label ghost-feature \
        --notes "Source: loa-grimoire/legacy/INVENTORY.md"
fi
```

### Phase D: Shadow System Detection (with Beads Integration)

**With ck:**
```tool_call
regex_search(
  pattern: "export (function|class|const|default)|module\\.exports|pub fn|def \\w+\\(",
  path: "src/"
)
```

**Fallback (grep):**
```bash
grep -rn "export \|module.exports\|pub fn\|def " src/ 2>/dev/null | \
  awk -F: '{print $1}' | sort -u
```

Cross-reference against PRD/SDD and `loa-grimoire/legacy/INVENTORY.md`.
Undocumented exports → Shadow Systems.

**Shadow System Classification:**

When a Shadow System is detected, classify its "Knowledge Risk":

```xml
<shadow_classification_protocol>
  <!-- Step 1: Find the shadow system via regex -->
  <detection>ck --regex "export.*function" → found undocumented module</detection>
  
  <!-- Step 2: Search for closest conceptual documentation match -->
  <similarity_check>
    ck --sem "<module_name> <export_names>" --path "docs/" --threshold 0.1
  </similarity_check>
  
  <!-- Step 3: Classify based on similarity score -->
  <classification>
    <orphaned_shadow score="< 0.3">
      No conceptual match in any documentation.
      Risk: HIGH - completely unknown functionality.
      Action: Urgent documentation required.
      
      <!-- MANDATORY: Generate Dependency Trace for Orphaned systems -->
      <dependency_trace>
        ck --regex "import.*<module_name>|require.*<module_name>" --path src/
        
        Purpose: Identify ALL files that rely on the undocumented code
        Output: List of dependent files with import statements
        Risk Assessment: More dependents = higher remediation urgency
      </dependency_trace>
    </orphaned_shadow>
    
    <drifted_implementation score="> 0.5">
      Documentation exists but has drifted from implementation.
      Risk: MEDIUM - misleading documentation.
      Action: Update docs to match code reality.
    </drifted_implementation>
    
    <partial_coverage score="0.3 - 0.5">
      Partial documentation match.
      Risk: LOW - documentation incomplete.
      Action: Extend existing documentation.
    </partial_coverage>
  </classification>
</shadow_classification_protocol>
```

**Beads Integration (if available):**
```bash
# Track Shadow Systems with classification and dependency trace
if command -v bd >/dev/null 2>&1; then
    # Determine classification
    SIMILARITY=$(ck --sem "<module_name>" docs/ --jsonl | jq -r '.[0].score // 0')
    
    if (( $(echo "$SIMILARITY < 0.3" | bc -l) )); then
        CLASSIFICATION="orphaned"
        PRIORITY=1
        
        # MANDATORY: Generate dependency trace for orphaned systems
        DEPENDENTS=$(ck --regex "import.*<module_name>" src/ --jsonl | jq -r '.file' | sort -u | wc -l)
        DEPENDENT_FILES=$(ck --regex "import.*<module_name>" src/ --jsonl | jq -r '.file' | sort -u | head -10 | tr '\n' ',')
        
    elif (( $(echo "$SIMILARITY > 0.5" | bc -l) )); then
        CLASSIFICATION="drifted"
        PRIORITY=2
        DEPENDENTS=0
        DEPENDENT_FILES=""
    else
        CLASSIFICATION="partial"
        PRIORITY=3
        DEPENDENTS=0
        DEPENDENT_FILES=""
    fi
    
    bd create "SHADOW ($CLASSIFICATION): <module_name> - similarity $SIMILARITY" \
        --type debt \
        --priority $PRIORITY \
        --label shadow-system \
        --label $CLASSIFICATION \
        --notes "File: <path>, Exports: <list>, Closest doc: <doc_path>, Dependents: $DEPENDENTS ($DEPENDENT_FILES)"
fi
```

### Phase E: Drift Report with Strategic Classification

Write to `loa-grimoire/reality/drift-report.md`:

**IMPORTANT:** The drift-report.md is a **State Zone artifact** that evolves over time. When ck detects remediation (a Ghost Feature that has been implemented, or a Shadow System that has been documented), the agent must automatically move that item to the appropriate resolution section.

```markdown
# Code/Documentation Drift Report

Generated: <timestamp>
Last Updated: <timestamp>
Search Mode: <ck|grep> (internal reference only)

## Strategic Liabilities (Ghost Features)

| Feature | Documentation Source | Search Evidence | Ambiguity | Beads ID |
|---------|---------------------|-----------------|-----------|----------|
| OAuth2 SSO | PRD §3.2 | 0 results (2 queries) | HIGH | bd-a1b2 |
| Rate Limiting | SDD §4.1 | 0 results (2 queries) | LOW | bd-e5f6 |

## Technical Debt (Shadow Systems)

| Module | Location | Classification | Dependents | Beads ID |
|--------|----------|----------------|------------|----------|
| legacy_auth | src/auth/legacy.ts | ORPHANED | 12 files | bd-c3d4 |
| cache_util | src/utils/cache.ts | DRIFTED | 3 files | bd-g7h8 |

## Verified Features

| Feature | Documentation | Code Location | Confidence |
|---------|--------------|---------------|------------|
| JWT Auth | PRD §2.1 | src/auth/jwt.ts:45 | 0.89 |

## Resolved (Auto-Updated)

<!-- Items moved here automatically when remediation detected -->

| Item | Type | Resolution Date | Evidence |
|------|------|-----------------|----------|
| WebSocket Support | Ghost→Implemented | 2024-01-20 | src/ws/handler.ts:1 (score: 0.92) |
| config_helper | Shadow→Documented | 2024-01-18 | docs/utils.md §3.2 (score: 0.87) |

## Drift Report Evolution Protocol

When running /ride or /update:
1. Re-scan all current Ghost Features with Negative Grounding
2. If code now found (score > 0.6): Move to "Resolved" as "Ghost→Implemented"
3. Re-scan all current Shadow Systems for documentation matches
4. If docs now found (score > 0.5): Move to "Resolved" as "Shadow→Documented"
5. Close associated Beads tickets with resolution note
```

## Output (Same Regardless of Search Mode)

All discoveries written to:
- `loa-grimoire/reality/code-map.md` - Structural findings
- `loa-grimoire/reality/drift-report.md` - Ghost/Shadow/Drift analysis
- `loa-grimoire/NOTES.md` - Actionable insights

## Agent Guidelines

**Do NOT mention to the user whether ck or grep was used.**

The user experience must be identical. ck provides:
- Higher precision (semantic understanding vs keyword matching)
- Lower false-positive rate for Ghost Features
- Faster execution on large codebases (80-90% cache hit rate)

But these are internal quality improvements, not user-facing features.
```

### 2.2 Tool Result Clearing Protocol (Anthropic Level)

Create `.claude/protocols/tool-result-clearing.md`:

```markdown
# Tool Result Clearing Protocol

## Problem: Context Rot

As token counts increase, model recall accuracy decreases. A `ck` search 
in a 1M LOC codebase can return thousands of tokens, overwhelming the 
agent's "attention budget" and degrading synthesis quality.

## Solution: Progressive Disclosure + Immediate Clearing

### Step 1: Execute Search with Pagination

**With ck:**
```tool_call
semantic_search(
  query: "<query>",
  path: "src/",
  top_k: 50,
  page_size: 10,        # Process in batches
  snippet_length: 150   # Limit per-result tokens
)
```

**With grep:**
```bash
grep -rn "<pattern>" src/ | head -50  # Hard limit results
```

### Step 2: Extract High-Signal Findings

From raw results, extract ONLY:
- File paths (max 10)
- Line numbers with brief context (max 20 words each)
- Relevance scores if available

### Step 3: Synthesize to NOTES.md

```markdown
## Search Synthesis: <timestamp>

**Intent**: <what we were looking for>
**Method**: <semantic|grep> (internal only, never show user)

**High-Signal Findings**:
1. `src/auth/handler.ts:45` - JWT validation entry point
2. `src/middleware/auth.ts:12` - Session middleware
3. `src/utils/crypto.ts:78` - Token signing utility

**Gaps Identified**: <ghost features or missing patterns>
**Next Action**: <recommended follow-up>
```

### Step 4: Clear Raw Output

After synthesis, the agent's working context should contain ONLY:
- The NOTES.md entry (synthesized)
- A single-line summary: "Searched for <intent>, found 3 relevant files"

The raw search results (potentially thousands of tokens) are DISCARDED.

**This restores the context window for high-level reasoning and synthesis.**

Without clearing:
```
Context: [2000 tokens of raw search results] + [task context]
Result: Model struggles with synthesis, misses connections, hallucinates
```

With clearing:
```
Context: [50 tokens of synthesized findings] + [task context]  
Result: Model performs high-level reasoning with full attention budget
```

## Attention Budget Limits

| Operation | Max Tokens | Trigger |
|-----------|------------|---------|
| Single search | 2,000 | Force pagination |
| Accumulated results | 5,000 | Mandatory clearing |
| Full file loads | 3,000 | Single file only |
| Session total | 15,000 | Stop and synthesize |

## Semantic Decay Protocol (Advanced)

For long-running sessions, apply **progressive semantic decay**:

```xml
<semantic_decay_protocol>
  <!-- Older search results decay to lightweight identifiers -->
  
  <active_context max_age="5_minutes">
    Full synthesis with code snippets in NOTES.md
  </active_context>
  
  <decayed_context max_age="30_minutes">
    Absolute paths only as "lightweight identifiers"
    Example: "/abs/path/src/auth/jwt.ts:45" (12 tokens)
    Can be rehydrated via JIT retrieval if needed
  </decayed_context>
  
  <archived_context max_age="session">
    Single-line summary in trajectory log
    Example: "Auth module analyzed: 3 files, 2 patterns found"
  </archived_context>
</semantic_decay_protocol>
```

**Decay Workflow:**
1. **0-5 min**: Full synthesis with snippets in active context
2. **5-30 min**: Decay to paths-only (lightweight identifiers)
3. **30+ min**: Archive to trajectory, single-line summary only

This preserves the ability to rehydrate context on-demand while freeing attention budget for new reasoning.

## When to Clear

- After EVERY search returning >20 results
- Before switching to a different task
- Before making architectural decisions
- When accumulated context exceeds 5,000 tokens

## Never

- Keep raw search results in working memory
- Pass raw results to subsequent operations
- Quote large code blocks verbatim (paraphrase instead)
```

### 2.3 Graceful Fallback Protocol

Create `.claude/protocols/search-fallback.md`:

```markdown
# Search Fallback Protocol

## Principle: Silent Enhancement

Users should never know whether ck or grep is being used.
The agent selects the best available tool automatically.

## Detection (Run Once Per Session)

```bash
if command -v ck >/dev/null 2>&1; then
    export LOA_SEARCH_MODE="ck"
else
    export LOA_SEARCH_MODE="grep"
fi
```

## Tool Selection Matrix

| Task | ck Available | ck Unavailable |
|------|--------------|----------------|
| Find entry points | `semantic_search("main entry bootstrap")` | `grep -rn "main\|bootstrap"` |
| Find patterns | `semantic_search("<concept>")` | `grep -rn "<keywords>"` |
| Ghost detection | Search + threshold check | grep + manual review |
| Shadow detection | `regex_search(exports)` | `grep + cross-reference` |
| Context loading | `hybrid_search` with pagination | `grep -C 10` |

## Quality Indicators (Internal Logging Only)

When ck is available, log to trajectory:
```json
{"search_mode": "ck", "precision": "high", "cache_hit": true}
```

When falling back to grep, log:
```json
{"search_mode": "grep", "precision": "medium"}
```

## Communication Guidelines

### Never Say to User
❌ "I'm using ck for semantic search..."
❌ "Falling back to grep because ck isn't installed..."
❌ "For better results, install ck..."
❌ "The semantic search found..."

### Always Say to User
✓ "Analyzing codebase structure..."
✓ "Searching for entry points..."
✓ "Cross-referencing documentation with implementation..."
✓ "Found the following patterns..."
```

### 2.3 No User-Facing /ck Command

**Important:** Unlike some tools, ck should have NO user-facing slash commands.

~~Create .claude/commands/ck.md~~ ← Do NOT create this

ck is purely internal tooling used by:
- `/ride` - Code Reality Extraction
- `/implement` - Context loading before coding
- `/review-sprint` - Finding related code for review
- `/architect` - Understanding existing patterns

Users interact with these existing commands. ck silently improves their quality.

---

## Phase 3: Skill Integration (Internal Enhancement)

### Objective
Enhance all 8 Loa agent skills to use ck internally when available, with transparent fallbacks.

### 3.1 Enhanced Implementing-Tasks Skill

Update `.claude/skills/implementing-tasks/context-retrieval.md`:

```markdown
# Context Retrieval for implementing-tasks

## Principle: Just-in-Time Loading

Before writing ANY code, load relevant context using the best available tool.

## Context Loading (Automatic Tool Selection)

### Step 1: Check Available Tooling (Internal)
```bash
CK_AVAILABLE=$(command -v ck >/dev/null 2>&1 && echo "true" || echo "false")
```

### Step 2: Find Related Code

**If ck available:**
```tool_call
semantic_search(
  query: "<task_description>",
  path: "src/",
  top_k: 20,
  threshold: 0.4
)
```

**If ck unavailable:**
```bash
grep -rn "<key_term_1>\|<key_term_2>\|<key_term_3>" src/ \
  --include="*.ts" --include="*.js" --include="*.py" \
  -C 5 | head -100
```

### Step 3: Find Similar Patterns

**If ck available:**
```tool_call
hybrid_search(
  query: "<pattern_to_find>",
  path: "src/",
  top_k: 10
)
```

**If ck unavailable:**
```bash
grep -rn "<pattern_keyword>" src/ -A 10 -B 2
```

## Attention Budget Management

| Scenario | Action |
|----------|--------|
| ck returns >50 results | Use `--full-section` on top 5 only |
| grep returns >100 lines | Narrow search terms |
| Loading full files | Only if <500 lines total |

## Tool Result Clearing

After heavy search operations:
1. Extract high-signal file:line references (max 5)
2. Synthesize findings to NOTES.md
3. Clear raw output from working memory
4. Continue with distilled context only

### NOTES.md Entry Format
```markdown
## Context Load: <timestamp>

**Task**: <task_id or description>
**Key Files**: 
- `src/auth/handler.ts:45-67` - Primary implementation
- `src/utils/validate.ts:12-30` - Helper functions

**Patterns Found**: <brief description>
**Ready to implement**: Yes/No
```
```

### 3.2 Enhanced Reviewing-Code Skill

Update `.claude/skills/reviewing-code/impact-analysis.md`:

```markdown
# Impact Analysis for reviewing-code

## Pre-Review Context Loading

Before reviewing code changes, understand the impact radius.

### Find Dependents

**If ck available:**
```tool_call
semantic_search(
  query: "imports <changed_module> uses <changed_function>",
  path: "src/",
  top_k: 50
)
```

**If ck unavailable:**
```bash
grep -rn "import.*<module>\|from.*<module>\|require.*<module>" src/
```

### Find Tests

**If ck available:**
```tool_call
hybrid_search(
  query: "<function_name> test spec describe it expect",
  path: "tests/",
  threshold: 0.3
)
```

**If ck unavailable:**
```bash
grep -rn "<function_name>" tests/ --include="*.test.*" --include="*.spec.*"
```

### Review Checklist

- [ ] Found related code (search completed)
- [ ] Test coverage verified
- [ ] Pattern consistency checked
- [ ] Claims cite [file:line] sources
```

---

## Phase 4: Trajectory Logging (Google ADK Level)

### Objective
Log every search operation for agent self-evaluation and architectural audit. 
Trajectory logs enable the reviewing-code agent to audit *why* specific code 
was searched and how it led to decisions.

### 4.1 Intent-First Search Protocol (Reasoning-Before-Search)

**Document reasoning BEFORE performing any search to prevent "fishing expeditions" that waste tokens.**

```xml
<search_execution>
  <!-- REQUIRED: State what you expect to find -->
  <intent>Find JWT authentication entry points to understand token validation flow</intent>
  
  <!-- REQUIRED: State why this search is necessary for the current task -->
  <rationale>Task requires extending auth; need to understand existing patterns first</rationale>
  
  <!-- REQUIRED: State expected outcome to validate search was productive -->
  <expected_outcome>Should find 1-3 token validation functions with signature patterns</expected_outcome>
  
  <!-- Execution -->
  <query>hybrid_search("JWT token validation authentication")</query>
  <path>${PROJECT_ROOT}/src/auth/</path>
</search_execution>
```

**Anti-Fishing Expedition Rules:**

| Scenario | Action |
|----------|--------|
| Search returns unexpected results | Log discrepancy, reassess rationale |
| Search returns 0 results | Reformulate query OR flag as Ghost Feature |
| Search returns >50 results | **Log Trajectory Pivot** (see below), then narrow |
| No clear expected_outcome | STOP - clarify reasoning before searching |

**Trajectory Pivot Protocol (for >50 results):**

When initial hypothesis fails (too many results), do NOT simply narrow—log the pivot:

```jsonl
{"ts":"...","agent":"impl","phase":"pivot","reason":"Initial query too broad","original_query":"authentication","result_count":127,"hypothesis_failure":"Query captured all auth-related code, not just entry points","refined_hypothesis":"Need to target initialization patterns specifically","new_query":"auth initialization bootstrap startup"}
```

The agent must:
1. Document **what** they're looking for (intent)
2. Document **why** they need it (rationale)  
3. Document **what they expect to find** (expected_outcome)
4. Execute the search
5. **If >50 results: Log Trajectory Pivot before refining**
6. Validate results against expected_outcome
7. Log results with word-for-word quotes

**If you cannot articulate expected_outcome, do not execute the search.**

### 4.2 Negative Grounding Protocol (Ghost Feature Verification)

To flag a Ghost Feature with high confidence, the agent must execute **at least two diverse semantic queries**:

```xml
<negative_grounding_protocol>
  <!-- Requirement: Two diverse queries, both return 0 results -->
  
  <query_1 type="functional">
    <description>Search using functional/behavioral terms</description>
    <example>"OAuth2 SSO login authentication flow"</example>
    <threshold>0.4</threshold>
    <required_result>0 matches</required_result>
  </query_1>
  
  <query_2 type="architectural">
    <description>Search using architectural/structural synonyms</description>
    <example>"single sign-on identity provider integration"</example>
    <threshold>0.4</threshold>
    <required_result>0 matches</required_result>
  </query_2>
  
  <ghost_confirmation>
    Only flag as GHOST if BOTH queries return 0 results below 0.4 threshold
  </ghost_confirmation>
  
  <high_ambiguity_check>
    <!-- If Ghost detected BUT documentation mentions feature in >3 files -->
    If negative grounding confirms 0 code results BUT:
      - ck --sem "<feature>" docs/ returns >3 file matches
      - OR feature appears in PRD, SDD, and README
    
    THEN: Flag as "HIGH AMBIGUITY" - requires targeted human audit
    
    Rationale: Extensive documentation with no code suggests either:
      1. Feature was planned but never implemented (true Ghost)
      2. Feature uses unexpected naming/patterns (detection failure)
      3. Feature is in external dependency (scope limitation)
  </high_ambiguity_check>
</negative_grounding_protocol>
```

**Trajectory Log for Ghost Feature:**
```jsonl
{"ts":"...","phase":"negative_grounding","feature":"OAuth2 SSO","query_1":"OAuth2 SSO login","results_1":0,"query_2":"SSO identity provider","results_2":0,"threshold":0.4,"doc_mentions":5,"ambiguity":"HIGH","confirmed_ghost":false,"requires_human_audit":true,"beads_id":"bd-x7y8"}
```

**High Ambiguity Classification:**

| Code Results | Doc Mentions | Classification | Action |
|--------------|--------------|----------------|--------|
| 0 | 0-2 | **CONFIRMED GHOST** | Track in Beads, remove from docs |
| 0 | 3+ | **HIGH AMBIGUITY** | Request human audit before classification |
| 1+ | Any | **NOT GHOST** | Feature exists, verify alignment |

### 4.2 Trajectory Log Structure

Create directory: `loa-grimoire/a2a/trajectory/`

Log format (`{agent}-{YYYY-MM-DD}.jsonl`):

```jsonl
{"ts":"2024-01-15T10:30:00Z","agent":"implementing-tasks","phase":"intent","intent":"Find JWT validation entry points","rationale":"Need to understand auth patterns before extending"}
{"ts":"2024-01-15T10:30:01Z","agent":"implementing-tasks","phase":"execute","mode":"ck","tool":"hybrid_search","query":"JWT token validation","path":"/home/user/project/src/auth/","results":15,"top_score":0.847}
{"ts":"2024-01-15T10:30:02Z","agent":"implementing-tasks","phase":"cite","citations":[{"file":"/home/user/project/src/auth/jwt.ts","line":45,"quote":"export async function validateToken(token: string): Promise<TokenPayload>"}],"grounded":true}
```

### 4.3 Word-for-Word Citation Format

Every claim derived from search must include **actual code quotes**:

```markdown
## Citation Format

### REQUIRED (word-for-word quote):
The system validates tokens using: `export async function validateToken(token: string): Promise<TokenPayload>` [/home/user/project/src/auth/jwt.ts:45]

### INSUFFICIENT (reference only):
The system validates tokens [src/auth/jwt.ts:45]

### Citation Template
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
```

### 4.4 Mandatory Citation Format

Every architectural claim derived from search MUST include a citation:

```markdown
## Claim Format

The system uses JWT for authentication `[src/auth/jwt.ts:12]`.
Rate limiting is NOT implemented `[GHOST: 0 results for "rate limit"]`.
The legacy auth module exports 5 undocumented functions `[SHADOW: src/auth/legacy.ts]`.
```

### 4.3 Self-Audit Protocol (ADK-Style Evaluation)

Add to `.claude/protocols/trajectory-evaluation.md`:

```markdown
# Trajectory Evaluation Protocol

## Evaluation-Driven Development (EDD)

Before finalizing ANY decision that affects architecture, implementation, 
or documentation, execute this self-audit.

### Step 1: Review Search History

Load today's trajectory log:
```bash
cat loa-grimoire/a2a/trajectory/$(whoami)-$(date +%Y-%m-%d).jsonl | tail -20
```

### Step 2: Identify Reasoning Gaps

Flag any of:
- [ ] Decisions made without supporting search
- [ ] Claims about codebase without `[file:line]` citation
- [ ] Assumptions marked `grounded: false` that weren't resolved
- [ ] Ghost features not tracked in Beads
- [ ] Shadow systems not documented

### Step 3: Validate Grounding Chain

For each major claim, trace the evidence chain:

```
DECISION: "Implement auth using existing JWT module"
├── SEARCH: semantic_search("JWT authentication") @ 10:30:00
├── RESULT: src/auth/jwt.ts:12 (score: 0.89)
├── CITATION: [src/auth/jwt.ts:12]
└── GROUNDED: ✓

DECISION: "Add rate limiting to API endpoints"
├── SEARCH: semantic_search("rate limiting") @ 10:32:00
├── RESULT: 0 matches
├── FLAG: Ghost feature (documented in PRD §4.2)
├── BEADS: bd-x7y8 created for tracking
└── GROUNDED: ✓ (absence is grounded evidence)
```

### Step 4: Calculate Grounding Ratio

```
grounding_ratio = grounded_decisions / total_decisions
```

**Target: ≥ 0.95**

If ratio < 0.95:
1. Identify ungrounded decisions
2. Execute additional searches to validate
3. Update trajectory with new evidence
4. Re-calculate ratio

### Step 5: Audit Trail for Review

Before submitting work for review, ensure:
- [ ] All claims have `[file:line]` citations
- [ ] Ghost features tracked in Beads
- [ ] Shadow systems logged in drift-report.md
- [ ] Trajectory log shows complete reasoning chain
- [ ] Grounding ratio ≥ 0.95

### Step 6: EDD Verification (Three Test Scenarios)

**Evaluation-Driven Development requires verification before completion.**

For every architectural decision informed by ck search:

```markdown
## Decision: <decision_description>

### Evidence Chain
- SEARCH: hybrid_search("relevant query") @ <timestamp>
- RESULT: <file:line> (score: X.XX)
- CITATION: [file:line]

### Test Scenarios (minimum 3)

**Scenario 1: Happy Path**
- Input: <typical input>
- Expected: <behavior based on found code>
- Verified: ✓/✗

**Scenario 2: Edge Case**
- Input: <boundary condition>
- Expected: <behavior based on found code>
- Verified: ✓/✗

**Scenario 3: Error Handling**
- Input: <invalid input>
- Expected: <error behavior based on found code>
- Verified: ✓/✗

### Grounding Status
- [ ] Word-for-word evidence cited
- [ ] Three scenarios verified
- [ ] No [ASSUMPTION] flags remaining
```

## Handling Ungrounded Claims

When a claim cannot be backed by search evidence:

```markdown
## Claim Classification

GROUNDED (has evidence):
"The system uses JWT tokens: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"

ASSUMPTION (no evidence, requires validation):
"The system likely caches tokens [ASSUMPTION: no search evidence, needs verification]"

GHOST (documented but missing):
"OAuth2 SSO [GHOST: PRD §3.2 claims feature, 0 search results]"

SHADOW (exists but undocumented):
"Legacy password hasher: `function hashLegacy()` [SHADOW: /abs/path/src/auth/legacy.ts:12, not in any docs]"
```

**Rule**: Never present an [ASSUMPTION] as fact. Either:
1. Execute additional searches to ground it
2. Explicitly flag as assumption requiring human verification
3. Remove the claim entirely

---

## Mandatory Self-Audit Checkpoint

**Before completing /ride, /translate, or any architectural decision, execute this formal audit.**

```markdown
# Trajectory Self-Audit Checklist

## 1. Search Coverage Audit
- [ ] All major claims have supporting searches in trajectory log
- [ ] No "fishing expeditions" (searches without expected_outcome)
- [ ] Results validated against expected_outcome

## 2. Grounding Audit
Load today's trajectory: `cat loa-grimoire/a2a/trajectory/$(whoami)-$(date +%Y-%m-%d).jsonl`

| Metric | Target | Actual |
|--------|--------|--------|
| Grounding ratio | ≥ 0.95 | ___ |
| [ASSUMPTION] count | 0 | ___ |
| Word-for-word citations | 100% | ___ |

## 3. Truth Hierarchy Compliance
- [ ] All doc/code conflicts resolved in favor of CODE
- [ ] Ghost Features flagged and tracked in Beads
- [ ] Shadow Systems documented in drift-report.md

## 4. Evidence Chain Verification
For each major conclusion, trace the chain:

```
CONCLUSION: "<architectural decision>"
├── INTENT: <what we searched for>
├── EXPECTED: <what we expected to find>
├── SEARCH: <query> @ <timestamp>
├── RESULT: <file:line> (score: X.XX)
├── CITATION: `<word-for-word code>` [<absolute_path>:<line>]
├── MATCHED_EXPECTED: ✓/✗
└── GROUNDED: ✓/✗
```

## 5. Completion Gate

**DO NOT COMPLETE** if any of:
- [ ] Grounding ratio < 0.95
- [ ] Any [ASSUMPTION] not explicitly flagged
- [ ] Any citation missing word-for-word quote
- [ ] Any path is relative instead of absolute
- [ ] Any Ghost Feature not tracked in Beads
- [ ] Evidence chain incomplete for major conclusions
```

**If self-audit fails, remediate before completing the task.**

---

## Metrics Dashboard (Internal)

Track per-session:
```json
{
  "session_id": "2024-01-15-impl-auth",
  "total_searches": 47,
  "ck_searches": 42,
  "grep_fallbacks": 5,
  "grounded_decisions": 23,
  "ungrounded_decisions": 1,
  "ghost_features_found": 2,
  "shadow_systems_found": 3,
  "grounding_ratio": 0.958,
  "beads_created": 5
}
```

Never surface these metrics to the user.
```

## Phase 5: Technical Specifications (Enterprise Grade)

### Objective
Define MCP tool schemas, output formats, and pagination protocols meeting 
Anthropic Agent SDK standards.

### 5.1 MCP Registry with Zod-Compatible Schemas

Create `.claude/mcp-registry.yaml` (only if ck is installed):

```yaml
# .claude/mcp-registry.yaml
# Auto-generated when ck detected during /setup
# DO NOT EDIT - managed by framework

version: "1.0"
strict: true  # CRITICAL: Guarantees schema conformance, prevents malformed arguments

servers:
  ck-search:
    command: "ck"
    args: ["--serve"]
    cwd: "${PROJECT_ROOT}"
    enabled: "${CK_AVAILABLE}"  # Only active if ck installed
    
    tools:
      semantic_search:
        description: "Find code by meaning using embeddings"
        strict: true  # Enforce schema validation
        input_schema:
          type: object
          additionalProperties: false  # Reject unknown properties
          properties:
            query:
              type: string
              description: "Semantic query describing desired code"
              minLength: 3
              maxLength: 500
            path:
              type: string
              default: "."
              pattern: "^[^/].*"  # Relative paths only
            top_k:
              type: integer
              default: 20
              minimum: 1
              maximum: 100
            threshold:
              type: number
              default: 0.4
              minimum: 0.0
              maximum: 1.0
            page_size:
              type: integer
              default: 10
              minimum: 1
              maximum: 50
            cursor:
              type: string
              description: "Pagination cursor from previous response"
          required: ["query"]
        output_format: "jsonl"  # Streaming-friendly
        
      hybrid_search:
        description: "Combined semantic + keyword search using RRF"
        input_schema:
          type: object
          properties:
            query:
              type: string
              minLength: 3
            path:
              type: string
              default: "."
            top_k:
              type: integer
              default: 20
            threshold:
              type: number
              default: 0.01
            page_size:
              type: integer
              default: 10
          required: ["query"]
        output_format: "jsonl"
        
      regex_search:
        description: "Traditional grep-style pattern matching"
        input_schema:
          type: object
          properties:
            pattern:
              type: string
              description: "Regex pattern (PCRE syntax)"
            path:
              type: string
              default: "."
            case_sensitive:
              type: boolean
              default: true
            context_lines:
              type: integer
              default: 3
              maximum: 10
          required: ["pattern"]
        output_format: "jsonl"
        
      index_status:
        description: "Check indexing status and metadata"
        input_schema:
          type: object
          properties:
            path:
              type: string
              default: "."
        output_format: "json"
```

### 5.2 JSONL Output Protocol

**Why JSONL:**
- Streaming friendly: Process results as they arrive
- Memory efficient: Parse one result at a time
- Error resilient: One malformed line doesn't break entire response
- Standard format: Used by OpenAI API, Anthropic API, modern ML pipelines

**Failure-Aware Parsing (Critical):**

If a single line in JSONL output is malformed, **drop that specific result and continue**—do NOT crash the turn. **Log dropped lines to trajectory for audit trail:**

```python
# Pseudocode for FAILURE-AWARE agent result processing
def process_ck_results(jsonl_stream, trajectory_log):
    high_signal = []
    total_processed = 0
    parse_errors = 0
    dropped_lines = []  # Track for audit
    
    for line_num, line in enumerate(jsonl_stream):
        try:
            result = json.loads(line)
            total_processed += 1
            
            # Extract only high-signal findings
            if result.get("score", 0) >= threshold:
                high_signal.append({
                    "file": result["file"],
                    "line": result["line"],
                    "snippet": result["snippet"][:100]  # Truncate
                })
            
            # Enforce attention budget
            if len(high_signal) >= 10:
                break
                
        except json.JSONDecodeError as e:
            # DROP malformed line, continue processing
            parse_errors += 1
            dropped_lines.append({"line": line_num, "error": str(e)})
            continue  # DO NOT CRASH
    
    # LOG DROPPED LINES TO TRAJECTORY (audit trail requirement)
    if parse_errors > 0:
        trajectory_log.append({
            "phase": "jsonl_parse",
            "total_processed": total_processed,
            "parse_errors": parse_errors,
            "dropped_lines": dropped_lines,
            "data_loss_ratio": parse_errors / (total_processed + parse_errors)
        })
    
    # Clear raw stream, keep only synthesis
    return {
        "total_scanned": total_processed,
        "high_signal": high_signal,
        "parse_errors": parse_errors
    }
```

**Rule:** A single malformed result must NEVER crash the entire search operation. **Dropped lines MUST be logged to trajectory for audit.**

### 5.3 Managed Pagination Protocol

For searches that may return large result sets:

```markdown
## Pagination Flow

### Initial Request
```tool_call
semantic_search(
  query: "authentication",
  path: "src/",
  top_k: 100,      # Total desired
  page_size: 10    # Per-page limit
)
```

### Response Structure
```json
{
  "results": [...],  // 10 items
  "pagination": {
    "cursor": "eyJvZmZzZXQiOjEwfQ==",
    "has_more": true,
    "total_available": 47
  }
}
```

### Continuation (if needed)
```tool_call
semantic_search(
  query: "authentication",
  path: "src/",
  cursor: "eyJvZmZzZXQiOjEwfQ=="
)
```

### Agent Decision Points

After each page:
1. Evaluate if sufficient high-signal results found
2. If yes → Stop pagination, synthesize
3. If no → Continue to next page
4. If 3 pages without high-signal → Reformulate query

Never paginate beyond 5 pages (50 results) without synthesis.

**Agent Language for Pagination:**

The agent should NEVER say: "I am paginating through results..."

Instead say: "Retrieving additional high-signal evidence via cursor `[id]`..."

This maintains the abstraction that the agent is gathering evidence, not performing mechanical operations.
```

### 5.4 Fallback Equivalents

When ck unavailable, grep operations must provide equivalent structure:

```bash
# Structured grep output (mimics JSONL)
grep_to_jsonl() {
    grep -rn "$1" "$2" 2>/dev/null | head -50 | while IFS=: read -r file line content; do
        printf '{"file":"%s","line":%s,"content":"%s"}\n' \
            "$file" "$line" "$(echo "$content" | sed 's/"/\\"/g' | cut -c1-100)"
    done
}

# Usage
grep_to_jsonl "pattern" "src/" | while read -r result; do
    # Process as JSONL
    file=$(echo "$result" | jq -r '.file')
    line=$(echo "$result" | jq -r '.line')
done
```

---

## Phase 6: Configuration

### 6.1 Configuration Hierarchy (Synthesis Protection)

Configuration follows a strict precedence hierarchy:

```
PRECEDENCE (highest to lowest):
1. .claude/overrides/ck-config.yaml    ← User customization (EDITABLE)
2. .loa.config.yaml                    ← Project settings
3. .claude/mcp-registry.yaml           ← Framework defaults (DO NOT EDIT)
```

### 6.2 User Overrides Directory

Create `.claude/overrides/` for safe customization:

```yaml
# .claude/overrides/ck-config.yaml
# User-owned customization - safe to edit

ck:
  # Custom embedding model
  model: "jina-code"  # Override default nomic-v1.5
  
  # Custom thresholds for this project
  thresholds:
    semantic: 0.5      # Stricter than default 0.4
    ghost_detection: 0.7
    shadow_detection: 0.3
  
  # Custom pagination for large codebase
  pagination:
    page_size: 20      # Override default 10
    max_pages: 10      # Override default 5
  
  # Custom ignore patterns
  ignore:
    - "vendor/"
    - "generated/"
    - "*.min.js"
```

### 6.3 Project Configuration

Update `.loa.config.yaml` schema:

```yaml
# .loa.config.yaml - Project-level configuration

# Search Enhancement Settings (ck)
# These only apply if ck is installed
ck:
  # Embedding model (bge-small | nomic-v1.5 | jina-code)
  model: "nomic-v1.5"
  
  # Search defaults
  defaults:
    semantic_threshold: 0.4
    top_k: 20
  
  # Trajectory logging
  trajectory:
    enabled: true
    retention_days: 30

# Integrity enforcement
integrity_enforcement: warn  # strict | warn | disabled
```

### 6.4 What Can/Cannot Be Overridden

| Setting | Location | Overridable |
|---------|----------|-------------|
| ck model | .claude/overrides/ck-config.yaml | ✅ Yes |
| Search thresholds | .claude/overrides/ck-config.yaml | ✅ Yes |
| Pagination settings | .claude/overrides/ck-config.yaml | ✅ Yes |
| Ignore patterns | .claude/overrides/ck-config.yaml | ✅ Yes |
| Integrity enforcement | .loa.config.yaml | ✅ Yes |
| Trajectory retention | .loa.config.yaml | ✅ Yes |
| Core protocols | .claude/protocols/ | ❌ No |
| Command definitions | .claude/commands/ | ❌ No |
| Zone assignments | Framework | ❌ No |
| Truth Hierarchy | Framework | ❌ No |

---

## Success Criteria

### Specific
- [ ] ck listed in INSTALLATION.md as optional enhancement
- [ ] `/setup` checks for ck and displays status
- [ ] `/ride` uses ck when available, grep when not
- [ ] No user-facing /ck command exists
- [ ] User cannot tell which search mode is active
- [ ] Ghost features tracked in Beads (if installed)
- [ ] Shadow systems logged in drift-report.md
- [ ] All claims have word-for-word `code quote` citations with absolute paths

### Measurable
- [ ] /ride works identically with or without ck
- [ ] Search results <500ms with ck on 1M LOC
- [ ] 80%+ cache hit rate with ck delta indexing
- [ ] Zero user-facing error messages when ck missing
- [ ] Grounding ratio ≥ 0.95 in trajectory logs
- [ ] Tool Result Clearing after every >20 result search
- [ ] Three test scenarios per architectural decision (EDD)

### Reasoning-Before-Search
- [ ] Every search has documented intent, rationale, AND expected_outcome
- [ ] No fishing expeditions (searches without clear expected_outcome)
- [ ] Results validated against expected_outcome
- [ ] Unexpected results trigger reassessment, not more searches

### Mandatory Self-Audit (Completion Gate)
- [ ] Self-audit checklist executed before /ride or /translate completion
- [ ] Grounding ratio verified ≥ 0.95
- [ ] Zero unflagged [ASSUMPTION] claims
- [ ] All citations have word-for-word quotes with absolute paths
- [ ] Evidence chain complete for all major conclusions
- [ ] Ghost Features tracked in Beads
- [ ] Shadow Systems documented in drift-report.md
- [ ] Remediation performed if any check fails

### Technical (ACI Standards)
- [ ] All ck commands use absolute paths (${PROJECT_ROOT}/...)
- [ ] All ck commands use --jsonl flag for streaming output
- [ ] Trajectory logs include intent→execute→cite phases
- [ ] Citations include word-for-word code quotes, not just file:line
- [ ] XML tags structure protocol sections for agent parsing

### Definition of Done
- [ ] Fresh clone with no ck: `/ride` completes successfully
- [ ] Fresh clone with ck: `/ride` completes with enhanced precision
- [ ] Agent responses never mention "ck" or "semantic search"
- [ ] Agent responses never mention "grep" or "fallback"
- [ ] Pre-flight integrity check runs before ck operations
- [ ] Trajectory logs show complete reasoning chain with intent→execute→cite phases
- [ ] Ghost/Shadow features integrated with Beads
- [ ] Zero fishing expedition anti-patterns in trajectory logs
- [ ] Self-audit checkpoint passed before task completion

---

## Execution Sequence

```
1. Update INSTALLATION.md with ck as optional enhancement
2. Update .claude/commands/setup.md to check for ck
3. Update README.md Quick Start section
4. Update .gitignore to include .ck/
5. Create .claude/protocols/search-fallback.md
6. Update .claude/commands/ride.md with dual-path logic
7. Update skill files with fallback patterns
8. Create trajectory logging structure
9. Update .loa.config.yaml schema
10. Test: /ride without ck installed
11. Test: /ride with ck installed
12. Verify: Agent output identical in both cases
```

---

## Anti-Pattern Checklist

Verify NONE of these exist in the final implementation:

- [ ] ❌ `/ck` slash command
- [ ] ❌ User-visible "semantic search" messaging
- [ ] ❌ User-visible "falling back to grep" messaging
- [ ] ❌ Error when ck not installed
- [ ] ❌ Recommendation to install ck during /ride
- [ ] ❌ Different output format based on search mode
- [ ] ❌ ck mentioned in agent responses

---

## Anti-Patterns Checklist

Verify NONE of these exist in the final implementation:

### User Experience Anti-Patterns
- [ ] ❌ `/ck` slash command
- [ ] ❌ User-visible "semantic search" messaging
- [ ] ❌ User-visible "falling back to grep" messaging
- [ ] ❌ Error when ck not installed
- [ ] ❌ Recommendation to install ck during /ride
- [ ] ❌ Different output format based on search mode
- [ ] ❌ ck mentioned in agent responses

### Fishing Expedition Anti-Patterns
- [ ] ❌ Searching without articulating expected_outcome
- [ ] ❌ Paginating through >50 results blindly
- [ ] ❌ Broad queries "just to see what's there"
- [ ] ❌ Repeating similar searches with slight variations
- [ ] ❌ Continuing after unexpected results without reassessing

### Grounding Anti-Patterns
- [ ] ❌ Presenting [ASSUMPTION] as fact
- [ ] ❌ Citations without word-for-word code quotes
- [ ] ❌ Relative paths instead of absolute paths
- [ ] ❌ Decisions without 3 test scenarios (EDD)
- [ ] ❌ Siding with docs when code differs

### Context Management Anti-Patterns
- [ ] ❌ Loading entire files when snippets suffice
- [ ] ❌ Keeping raw search results in working memory
- [ ] ❌ Skipping Tool Result Clearing after >20 results
- [ ] ❌ Exceeding attention budget without synthesis

### Synthesis Protection Anti-Patterns
- [ ] ❌ Editing .claude/ files directly (except .claude/overrides/)
- [ ] ❌ Allowing users to modify System Zone files
- [ ] ❌ Ignoring .claude/overrides/ when loading ck config
- [ ] ❌ Storing user customizations in System Zone

---

## Traceability Matrix: Review Requirements → Implementation (v9 - Production Ready)

This matrix verifies that all Principal Engineer review feedback has been incorporated.

### AWS Projen Standard (Infrastructure Integrity)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Pre-flight integrity check | Phase 1.5, `.claude/protocols/preflight-integrity.md` | ✅ |
| Cryptographic manifest verification | checksums.json validation in preflight protocol | ✅ |
| HALT on strict mode + drift | `integrity_enforcement: strict` directive | ✅ |
| Zone-aware persistence (.ck/ in State Zone) | Zone Assignment Rules table | ✅ |
| Self-healing State Zone (delta-first) | Delta-update before full reindex | ✅ |
| Version pinning | .loa-version.json ck version check | ✅ |
| **Binary Integrity Verification** | SHA-256 fingerprint check of ck binary | ✅ |
| Synthesis Protection (overrides/) | Phase 6.2, `.claude/overrides/` directory | ✅ |
| Anti-tamper enforcement | Checksums + enforcement levels | ✅ |

### Anthropic Standard (Context Engineering)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Just-in-Time (JIT) retrieval | Phase 2.1, JIT Context Principle | ✅ |
| Tiered Search Protocol | Phase 2.3, Broad→Narrow→JIT (semantic→hybrid→full-section) | ✅ |
| Dynamic Thresholding | Phase 2.4, 0.4-0.8 based on task criticality | ✅ |
| AST-aware snippets | --full-section for complete logical blocks | ✅ |
| Smallest possible high-signal tokens | Attention budget limits (2000/5000/15000) | ✅ |
| **Semantic Decay Protocol** | Progressive decay: Active→Decayed→Archived | ✅ |
| Tool Result Clearing (memory decay) | Phase 2.2, `.claude/protocols/tool-result-clearing.md` | ✅ |
| Progressive disclosure | Pagination protocol (page_size=10, max 5 pages) | ✅ |
| Absolute path enforcement | ACI Standards, `${PROJECT_ROOT}/...` mandate | ✅ |
| JSONL output format | Phase 5.2, `--jsonl` flag requirement | ✅ |
| Failure-Aware JSONL Parsing | Drop malformed lines, continue (never crash) | ✅ |
| **Dropped Line Logging** | Log parse errors to trajectory for audit trail | ✅ |
| XML tag structure | ACI section, protocol section delineation | ✅ |
| **Strict Schema Enforcement** | `strict: true` in MCP registry | ✅ |

### Google ADK Standard (Trajectory Evaluation)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Auditable search paths | Phase 4, `loa-grimoire/a2a/trajectory/` | ✅ |
| Intent logging before search | Phase 4.1, Reasoning-Before-Search protocol | ✅ |
| Expected outcome articulation | `<expected_outcome>` in search_execution | ✅ |
| Model Selection Rationale | Justify bge-small vs jina-code in trajectory | ✅ |
| **Negative Model Justification** | Explain why NOT using larger model | ✅ |
| Trajectory Pivot for >50 results | Log hypothesis failure before narrowing | ✅ |
| Anti-fishing expedition rules | Phase 4.1, Anti-Fishing rules table | ✅ |
| Negative Grounding for Ghost Features | Two diverse queries required | ✅ |
| **High Ambiguity Detection** | Flag if 0 code results but >3 doc mentions | ✅ |
| EDD (3 test scenarios) | Phase 4.5, EDD Verification | ✅ |
| Grounding ratio ≥ 0.95 | Self-Audit Checkpoint metrics | ✅ |
| Word-for-word citations | Citation format with code quotes | ✅ |
| [ASSUMPTION] tagging | Claim Classification system | ✅ |
| Self-audit checkpoint | Mandatory Self-Audit before completion | ✅ |

### Truth Hierarchy Enforcement (Loa Standard)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| CODE > Artifacts > Legacy Docs | Immutable Truth Hierarchy diagram | ✅ |
| Ghost Feature detection | Phase C, Negative Grounding Protocol | ✅ |
| Shadow System identification | Phase D, regex_search for exports | ✅ |
| Shadow System Classification | Orphaned (<0.3) / Partial (0.3-0.5) / Drifted (>0.5) | ✅ |
| **Dependency Trace for Orphaned** | Auto-generate import graph for orphaned systems | ✅ |
| Beads integration for tracking | Ghost/Shadow → Beads create commands | ✅ |
| Strategic Liability classification | drift-report.md tables | ✅ |
| **Drift Report Evolution** | Auto-move resolved items (Ghost→Implemented, Shadow→Documented) | ✅ |
| Conflict resolution (always side with code) | Truth Hierarchy conflict rules | ✅ |

### Technical ACI Standards

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Mandatory JSONL output | Phase 5.2, `--jsonl` everywhere | ✅ |
| Failure-Aware Parsing | Drop malformed lines, continue | ✅ |
| **Log Dropped Lines** | Audit trail for data loss | ✅ |
| Managed pagination | Phase 5.3, cursor + page_size handling | ✅ |
| Pagination language | "Retrieving high-signal evidence" not "paginating" | ✅ |
| Zod-compatible schemas | Phase 5.1, MCP Registry with type constraints | ✅ |
| **Strict Mode Schema Enforcement** | `strict: true`, `additionalProperties: false` | ✅ |
| Absolute filepaths | All ck commands use `${PROJECT_ROOT}/...` | ✅ |
| XML tags for instruction boundaries | `<search_execution>`, `<integrity_protocol>`, etc. | ✅ |
| Streaming-friendly processing | JSONL line-by-line parsing pattern | ✅ |

### Beads Integration Pattern

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Optional enhancement (not required) | INSTALLATION.md, /setup status display | ✅ |
| Invisible to user | No /ck command, no tool mentions | ✅ |
| Graceful degradation to grep | Phase 2.5, dual-path search logic | ✅ |
| Zero friction | Identical UX with/without ck | ✅ |

---

## Analogy

> Integrating ck into Loa transforms the Agent from a **simple Librarian** (keyword search) to a **Forensic Auditor**. Instead of just finding books that mention a topic, the Auditor uses a scanner (`ck`) to verify if the physical inventory (Code) actually matches the library's catalog (Documentation), logging every step of their investigation in a tamper-proof ledger (Trajectory Logs) for the Board's review (`reviewing-code` agent).
>
> The Auditor identifies **Phantom Assets** (Ghost Features: documented but missing from shelves) and **Undisclosed Liabilities** (Shadow Systems: items on shelves but not in catalog), tracking each as a finding with mandatory citations. When the scanner is unavailable, the Auditor falls back to manual card-catalog lookup (grep)—slower and less precise, but the final audit report maintains the same professional standard.

---

*Framework Version: Loa 0.7.x + ck 0.7.x*
*Integration Spec Version: v9 (Production Ready - 9 Principal Engineer Reviews)*
*Engineering Standard: AWS Projen / Google ADK / Anthropic Agent SDK*
