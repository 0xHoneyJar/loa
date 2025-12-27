# Software Design Document: ck Semantic Search Integration

**Project**: Loa Framework - Enterprise-Grade Semantic Code Search Integration
**Version**: 1.0
**Status**: Architecture Complete
**Date**: 2025-12-26
**Agent**: designing-architecture
**PRD Reference**: `/home/merlin/Documents/thj/code/loa/loa-grimoire/prd.md`

---

## Executive Summary

This Software Design Document (SDD) defines the technical architecture for integrating `ck` semantic/hybrid search into the Loa agent framework. The design follows approved architectural decisions:

1. **ck Integration**: Direct CLI invocation (v1.0) → MCP migration (v2.0)
2. **Trajectory Retention**: Archive to compressed storage for full audit trail
3. **Beads Integration**: Minimal - Ghost/Shadow feature tracking only
4. **Multi-Repo Support**: Single repository only (v1.0)

The architecture enforces three critical invariants:
- **Truth Hierarchy**: CODE > ck INDEX > NOTES.md > PRD/SDD (PRD §2.3)
- **Invisible Enhancement**: Zero user-facing changes, identical output with/without ck (PRD FR-8.2)
- **Integrity First**: Pre-flight verification before every operation (PRD FR-2.1)

**Key Metrics**:
- Search Speed: <500ms on 1M LOC (PRD NFR-1.1)
- Cache Hit Rate: 80-90% via delta indexing (PRD NFR-1.2)
- Grounding Ratio: ≥0.95 (95%+ claims backed by code) (PRD NFR-5.2)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [Technology Stack](#technology-stack)
4. [Component Design](#component-design)
   - 4.1 Pre-Flight Integrity Checker
   - 4.2 Search Orchestrator
   - 4.3 JSONL Parser
   - 4.4 Tool Result Clearing Manager
   - 4.5 Ghost Feature Detector
   - 4.6 Shadow System Classifier
   - 4.7 **Agent Chaining Component (FR-8)**
   - 4.8 **Context Filtering Component (FR-9)**
   - 4.9 **Command Namespace Protection (FR-10)**
5. [Data Architecture](#data-architecture)
6. [API Design](#api-design)
7. [Security Architecture](#security-architecture)
8. [Integration Points](#integration-points)
9. [Scalability & Performance](#scalability--performance)
10. [Deployment Architecture](#deployment-architecture)
11. [Development Workflow](#development-workflow)
12. [Technical Risks & Mitigation](#technical-risks--mitigation)
13. [Future Considerations](#future-considerations)

---

## 1. System Architecture

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Commands                            │
│              /ride    /implement    /review-sprint               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Command Router Layer                          │
│              (.claude/commands/*.md with YAML)                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Agent Skills Layer                             │
│   discovering-requirements  │  implementing-tasks  │  reviewing  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                Search Orchestration Layer                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Pre-Flight Integrity Check (MANDATORY)                  │   │
│  │  - System Zone checksum validation                       │   │
│  │  - ck binary availability & version check                │   │
│  │  - State Zone self-healing trigger                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Search Mode Selection                                   │   │
│  │  if command -v ck; then SEMANTIC else GREP fi            │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Tool Result Clearing Manager                            │   │
│  │  - Token budget tracking (2K/5K/15K limits)              │   │
│  │  - Semantic Decay scheduler (0-5min/5-30min/30+min)      │   │
│  │  - Trajectory compaction on threshold breach             │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│   ck Search Engine        │   │   Grep Fallback Engine    │
│   (Direct CLI Invocation) │   │   (Native bash tooling)   │
└───────────┬───────────────┘   └───────────┬───────────────┘
            │                               │
            ▼                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Unified Result Stream                         │
│              JSONL Parser → Citation Extractor                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│  NOTES.md Synthesis       │   │  Trajectory Logging       │
│  (Structured Memory)      │   │  (.jsonl audit trail)     │
└───────────────────────────┘   └───────────────────────────┘
```

**Key Properties**:
- **Three-Zone Model**: System (.claude/) → State (.ck/) → App (src/) (PRD Phase 0)
- **Dual-Path Search**: Transparent fallback from ck → grep (PRD FR-8.1)
- **Pre-Flight Gate**: All operations blocked until integrity verified (PRD FR-2.1)
- **Token Budget Enforcement**: Hard limits prevent context overflow (PRD FR-4.1)

---

### 1.2 Component Interaction Flow

**Scenario: User invokes `/ride` command**

```
1. User: /ride
   ↓
2. Command Router: Load .claude/commands/ride.md
   ↓
3. Pre-Flight Check:
   ├─ Verify .claude/checksums.json (System Zone integrity)
   ├─ Check ck availability: command -v ck >/dev/null 2>&1
   ├─ Validate .ck/ state (trigger reindex if missing)
   └─ HALT if integrity_enforcement=strict + drift detected
   ↓
4. Agent Skill: discovering-requirements (mounted by /ride)
   ↓
5. Search Orchestration:
   ├─ Log Intent: "Find entry points for Code Reality Extraction"
   ├─ Select Mode: ck_available ? semantic : grep
   ├─ Execute Search: semantic_search("main entry bootstrap", path: src/)
   ├─ Parse JSONL: Drop malformed lines, continue (PRD FR-6.2)
   └─ Tool Result Clearing: Extract top 10 results → synthesize to NOTES.md
   ↓
6. Citation Extraction:
   ├─ For each result: Extract word-for-word code snippet
   ├─ Format: `"<claim>: <code> [<abs_path>:<line>]"` (PRD FR-5.3)
   └─ Log to trajectory: loa-grimoire/a2a/trajectory/discovering-{date}.jsonl
   ↓
7. Synthesis:
   ├─ Write to NOTES.md: ## Code Reality - Entry Points
   ├─ Write to loa-grimoire/reality/: Extracted code structure
   └─ Write to loa-grimoire/drift-report.md: Ghost/Shadow analysis
   ↓
8. Self-Audit Checkpoint:
   ├─ Calculate grounding_ratio = grounded_claims / total_claims
   ├─ Verify ≥0.95 (PRD FR-5.4)
   ├─ Check all paths are absolute
   └─ HALT if any check fails, remediate before completion
   ↓
9. Output: "Code reality extraction complete. Found 12 entry points,
            3 ghost features, 5 shadow systems. Details in grimoire."
```

**Critical Invariant**: User cannot tell if ck or grep was used (PRD NFR-6.1).

---

### 1.3 Three-Zone Model Enforcement

```
┌────────────────────────────────────────────────────────────────┐
│  SYSTEM ZONE (.claude/)                                         │
│  Owner: Framework | Permission: READ-ONLY (except overrides/)  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ .claude/commands/             # Command definitions       │  │
│  │ .claude/skills/               # Agent skill modules       │  │
│  │ .claude/protocols/            # Protocol specifications   │  │
│  │ .claude/scripts/              # Helper bash scripts       │  │
│  │ .claude/checksums.json        # Integrity manifest        │  │
│  │ .claude/overrides/            # USER EDITABLE             │  │
│  │   └── ck-config.yaml          # Custom ck settings        │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ⚠️  Direct edits will be OVERWRITTEN by /update               │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  STATE ZONE (.ck/, loa-grimoire/)                               │
│  Owner: Project | Permission: READ/WRITE (self-healing)        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ .ck/                          # ck index & cache          │  │
│  │   ├── index/                  # Embedding vectors         │  │
│  │   ├── cache/                  # Query cache               │  │
│  │   ├── .last_commit            # Delta indexing marker     │  │
│  │   └── config.toml             # ck runtime config         │  │
│  │                                                            │  │
│  │ loa-grimoire/                 # Agent workspace           │  │
│  │   ├── NOTES.md                # Structured memory         │  │
│  │   ├── prd.md, sdd.md, ...    # Design documents          │  │
│  │   ├── a2a/trajectory/         # Reasoning logs (JSONL)    │  │
│  │   └── reality/                # Code extraction output    │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ✓  Self-healing: Missing .ck/ triggers silent reindex         │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  APP ZONE (src/, lib/, app/)                                    │
│  Owner: Developer | Permission: READ (write requires confirm)  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ src/                          # Application code          │  │
│  │ lib/                          # Library modules           │  │
│  │ app/                          # Application entry         │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ⚡ SOURCE OF TRUTH: Code > Index > Docs (PRD §2.3)            │
└────────────────────────────────────────────────────────────────┘
```

**Zone Interaction Rules**:
1. System Zone → State Zone: Read-only (configure via overrides)
2. State Zone → App Zone: Read-only (never modify user code)
3. App Zone → State Zone: Triggers delta reindex on git commit

---

## 2. Technology Stack

### 2.1 Core Technologies

| Component | Technology | Version | Justification |
|-----------|-----------|---------|---------------|
| **Search Engine** | ck (seek) | ≥0.7.0 | Hybrid semantic+keyword search, delta indexing, sub-500ms on 1M LOC (PRD NFR-1.1) |
| **Embedding Model** | nomic-embed-text-v1.5 | v1.5 | Code-optimized, 768-dim, fast inference, SOTA on code similarity benchmarks |
| **Alternative Model** | jina-code-v2 | v2 | Longer context (8192 tokens), better for docstrings/comments |
| **Fallback Search** | grep/ripgrep | System | Zero dependencies, universal availability, reliable keyword search |
| **Output Format** | JSONL | - | Streaming-friendly, failure-tolerant (drop bad lines, continue) (PRD FR-6.2) |
| **Configuration** | YAML | - | Human-readable, overrideable, schema validation via yq |
| **Checksum** | SHA-256 | - | Cryptographic integrity verification (PRD NFR-2.2) |
| **Compression** | gzip | - | Trajectory archive compaction (v2.0 requirement) |
| **Task Tracking** | Beads (bd CLI) | Any | Optional, ghost/shadow feature tracking (PRD NFR-7.1) |

**Rationale for ck over alternatives**:
- **vs. Sourcegraph**: Requires server infrastructure, heavy deployment
- **vs. OpenGrok**: Java dependency, slower indexing
- **vs. ctags**: Syntax-only, no semantic understanding
- **vs. ripgrep**: Keyword-only, no semantic similarity

**Rationale for Direct CLI (v1.0)**:
- Simpler deployment (no MCP server complexity)
- Lower attack surface (no network protocol)
- Easier debugging (visible subprocess invocations)
- Faster iteration (no protocol marshalling overhead)

**Rationale for MCP Migration (v2.0)**:
- Better Claude Desktop integration
- Standardized tool interface
- Connection pooling & caching
- Health checks & automatic reconnection

---

### 2.2 Dependencies

```yaml
# Runtime Dependencies
required:
  - git: "≥2.0"          # Project root detection, delta indexing
  - bash: "≥4.0"         # Script execution
  - jq: "≥1.6"           # JSON parsing in scripts
  - yq: "≥4.0"           # YAML parsing for MCP registry

optional:
  - ck: "≥0.7.0"         # Semantic search (graceful fallback to grep)
  - bd: "any"            # Beads task tracking (silent skip if missing)
  - ripgrep: "≥13.0"     # Faster grep alternative (fallback to grep)

# Development Dependencies
dev:
  - shellcheck: "≥0.8"   # Bash linting
  - bats: "≥1.5"         # Bash testing
  - shfmt: "≥3.5"        # Bash formatting
```

**Dependency Resolution Strategy**:
1. **Hard Requirements**: git, bash, jq, yq → HALT if missing
2. **Soft Requirements**: ck, bd, ripgrep → WARN + fallback
3. **Detection**: Cache results in `.loa-setup-complete` to avoid repeated checks

---

## 3. Component Design

### 3.1 Pre-Flight Integrity Checker

**Location**: `.claude/scripts/preflight.sh`
**Protocol**: `.claude/protocols/preflight-integrity.md`
**Invoked By**: All ck operations (via wrapper)

**Responsibility**: Verify System Zone integrity before allowing any search operation.

```bash
#!/usr/bin/env bash
# .claude/scripts/preflight.sh

set -euo pipefail

# Establish project root (absolute path)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Load enforcement level from config
ENFORCEMENT=$(yq e '.integrity_enforcement // "warn"' "${PROJECT_ROOT}/.loa.config.yaml")

# 1. Verify System Zone Checksums
if [[ -f "${PROJECT_ROOT}/.claude/checksums.json" ]]; then
    echo "Verifying System Zone integrity..." >&2

    # Extract expected checksums
    while IFS= read -r file; do
        expected_hash=$(jq -r ".\"${file}\"" "${PROJECT_ROOT}/.claude/checksums.json")
        if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
            actual_hash=$(sha256sum "${PROJECT_ROOT}/${file}" | awk '{print $1}')

            if [[ "${expected_hash}" != "${actual_hash}" ]]; then
                echo "❌ System Zone drift detected: ${file}" >&2
                echo "   Expected: ${expected_hash}" >&2
                echo "   Actual:   ${actual_hash}" >&2

                if [[ "${ENFORCEMENT}" == "strict" ]]; then
                    echo "" >&2
                    echo "HALTING: integrity_enforcement=strict" >&2
                    echo "Run /update to restore System Zone integrity." >&2
                    exit 1
                elif [[ "${ENFORCEMENT}" == "warn" ]]; then
                    echo "⚠️  Proceeding with caution (enforcement=warn)" >&2
                fi
            fi
        fi
    done < <(jq -r 'keys[]' "${PROJECT_ROOT}/.claude/checksums.json")
fi

# 2. Check ck availability & version
if command -v ck >/dev/null 2>&1; then
    CK_VERSION=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    REQUIRED_VERSION=$(jq -r '.dependencies.ck // "0.7.0"' "${PROJECT_ROOT}/.loa-version.json")

    echo "✓ ck installed: ${CK_VERSION}" >&2

    # Version comparison (simple major.minor check)
    if [[ "${CK_VERSION}" != "unknown" ]]; then
        CK_MAJOR=$(echo "${CK_VERSION}" | cut -d. -f1)
        REQ_MAJOR=$(echo "${REQUIRED_VERSION}" | cut -d. -f1)

        if [[ "${CK_MAJOR}" -lt "${REQ_MAJOR}" ]]; then
            echo "⚠️  ck version ${CK_VERSION} < required ${REQUIRED_VERSION}" >&2
            echo "   Upgrade: cargo install ck-search --force" >&2
        fi
    fi

    # 3. Binary integrity (SHA-256 fingerprint)
    if [[ -f "${PROJECT_ROOT}/.loa-version.json" ]]; then
        EXPECTED_FINGERPRINT=$(jq -r '.binary_fingerprints.ck // ""' "${PROJECT_ROOT}/.loa-version.json")
        if [[ -n "${EXPECTED_FINGERPRINT}" ]]; then
            CK_PATH=$(command -v ck)
            ACTUAL_FINGERPRINT=$(sha256sum "${CK_PATH}" | awk '{print $1}')

            if [[ "${EXPECTED_FINGERPRINT}" != "${ACTUAL_FINGERPRINT}" ]]; then
                echo "⚠️  ck binary fingerprint mismatch" >&2
                echo "   Expected: ${EXPECTED_FINGERPRINT}" >&2
                echo "   Actual:   ${ACTUAL_FINGERPRINT}" >&2

                if [[ "${ENFORCEMENT}" == "strict" ]]; then
                    echo "" >&2
                    echo "HALTING: Binary integrity check failed" >&2
                    echo "Reinstall ck: cargo install ck-search --force" >&2
                    exit 1
                fi
            fi
        fi
    fi
else
    echo "○ ck not installed (optional - will use grep fallback)" >&2
fi

# 4. Self-Healing State Zone
if [[ ! -d "${PROJECT_ROOT}/.ck" ]] || [[ ! -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
    echo "Self-healing: .ck/ missing, triggering background reindex..." >&2

    # Background reindex (non-blocking)
    nohup ck --index "${PROJECT_ROOT}" --quiet </dev/null >/dev/null 2>&1 &

    echo "Note: First search may be slower while index builds" >&2
fi

# 5. Delta Reindex Check (if index exists)
if [[ -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
    LAST_INDEXED=$(cat "${PROJECT_ROOT}/.ck/.last_commit")
    CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

    if [[ -n "${CURRENT_HEAD}" ]] && [[ "${LAST_INDEXED}" != "${CURRENT_HEAD}" ]]; then
        # Check number of changed files
        CHANGED_FILES=$(git diff --name-only "${LAST_INDEXED}" "${CURRENT_HEAD}" 2>/dev/null | wc -l)

        if [[ "${CHANGED_FILES}" -lt 100 ]]; then
            echo "Delta indexing ${CHANGED_FILES} changed files..." >&2
            ck --index "${PROJECT_ROOT}" --delta --quiet 2>/dev/null &
        else
            echo "Full reindex triggered (${CHANGED_FILES} files changed)" >&2
            ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
        fi

        # Update marker
        echo "${CURRENT_HEAD}" > "${PROJECT_ROOT}/.ck/.last_commit"
    fi
fi

echo "✓ Pre-flight checks complete" >&2
exit 0
```

**Error Handling**:
- `exit 0`: Checks passed, proceed
- `exit 1`: Checks failed (strict mode only), HALT operation

**Integration**: All ck wrapper scripts call `preflight.sh` before search:
```bash
# In search wrapper
"${PROJECT_ROOT}/.claude/scripts/preflight.sh" || exit 1
```

---

### 3.2 Search Orchestrator

**Location**: `.claude/scripts/search-orchestrator.sh`
**Protocol**: `.claude/protocols/search-fallback.md`

**Responsibility**: Route search requests to ck or grep based on availability.

```bash
#!/usr/bin/env bash
# .claude/scripts/search-orchestrator.sh

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Pre-flight check (mandatory)
"${PROJECT_ROOT}/.claude/scripts/preflight.sh" || exit 1

# Parse arguments
SEARCH_TYPE="${1:-semantic}"  # semantic|hybrid|regex
QUERY="${2}"
SEARCH_PATH="${3:-${PROJECT_ROOT}/src}"
TOP_K="${4:-20}"
THRESHOLD="${5:-0.4}"

# Detect search mode (cached in session)
if [[ -z "${LOA_SEARCH_MODE:-}" ]]; then
    if command -v ck >/dev/null 2>&1; then
        export LOA_SEARCH_MODE="ck"
    else
        export LOA_SEARCH_MODE="grep"
    fi
fi

# Trajectory log entry (intent phase)
TRAJECTORY_FILE="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
mkdir -p "$(dirname "${TRAJECTORY_FILE}")"

# Log intent BEFORE search
jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME:-unknown}" \
    --arg phase "intent" \
    --arg query "${QUERY}" \
    --arg path "${SEARCH_PATH}" \
    --arg mode "${LOA_SEARCH_MODE}" \
    '{ts: $ts, agent: $agent, phase: $phase, query: $query, path: $path, mode: $mode}' \
    >> "${TRAJECTORY_FILE}"

# Execute search
if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
    case "${SEARCH_TYPE}" in
        semantic)
            ck --semantic "${QUERY}" \
                --path "${SEARCH_PATH}" \
                --top-k "${TOP_K}" \
                --threshold "${THRESHOLD}" \
                --jsonl
            ;;
        hybrid)
            ck --hybrid "${QUERY}" \
                --path "${SEARCH_PATH}" \
                --top-k "${TOP_K}" \
                --threshold "${THRESHOLD}" \
                --jsonl
            ;;
        regex)
            ck --regex "${QUERY}" \
                --path "${SEARCH_PATH}" \
                --jsonl
            ;;
        *)
            echo "Unknown search type: ${SEARCH_TYPE}" >&2
            exit 1
            ;;
    esac
else
    # Grep fallback
    case "${SEARCH_TYPE}" in
        semantic|hybrid)
            # Convert semantic query to keyword patterns
            # Extract words, OR them together
            KEYWORDS=$(echo "${QUERY}" | tr ' ' '\n' | grep -v '^$' | paste -sd '|')

            grep -rn -E "${KEYWORDS}" \
                --include="*.js" --include="*.ts" --include="*.py" --include="*.go" \
                --include="*.rs" --include="*.java" --include="*.cpp" --include="*.c" \
                "${SEARCH_PATH}" 2>/dev/null | head -n "${TOP_K}" || true
            ;;
        regex)
            grep -rn -E "${QUERY}" \
                --include="*.js" --include="*.ts" --include="*.py" --include="*.go" \
                --include="*.rs" --include="*.java" --include="*.cpp" --include="*.c" \
                "${SEARCH_PATH}" 2>/dev/null | head -n "${TOP_K}" || true
            ;;
    esac
fi

# Log execution result
RESULT_COUNT=$?
jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME:-unknown}" \
    --arg phase "execute" \
    --argjson result_count "${RESULT_COUNT}" \
    --arg mode "${LOA_SEARCH_MODE}" \
    '{ts: $ts, agent: $agent, phase: $phase, result_count: $result_count, mode: $mode}' \
    >> "${TRAJECTORY_FILE}"
```

**Output Format**:
- **ck mode**: JSONL with `{file, line, snippet, score}`
- **grep mode**: Plain text `file:line:snippet` (converted to JSONL downstream)

**Key Design Decisions**:
1. Search mode cached in `LOA_SEARCH_MODE` env var (avoid repeated `command -v` checks)
2. Intent logged BEFORE search (prevents fishing expeditions) (PRD FR-5.1)
3. Grep fallback uses keyword extraction from semantic query (best-effort approximation)

---

### 3.3 JSONL Parser with Failure Awareness

**Location**: Inline in agent skill logic
**Protocol**: `.claude/protocols/tool-result-clearing.md`

**Responsibility**: Parse JSONL output line-by-line, drop malformed lines without crashing.

```python
# Pseudocode (agents implement in natural language)

def parse_search_results(jsonl_stream: str) -> List[SearchResult]:
    """
    Parse JSONL search results with failure awareness.

    Drops malformed lines and continues processing.
    Logs all parse errors to trajectory for audit.
    """
    results = []
    parse_errors = []
    total_lines = 0

    for line_num, line in enumerate(jsonl_stream.splitlines(), start=1):
        total_lines += 1

        try:
            # Attempt parse
            result = json.loads(line)

            # Validate required fields
            if not all(k in result for k in ['file', 'line', 'snippet']):
                raise ValueError("Missing required fields")

            # Normalize to absolute path
            if not result['file'].startswith('/'):
                result['file'] = os.path.join(PROJECT_ROOT, result['file'])

            results.append(result)

        except (json.JSONDecodeError, ValueError) as e:
            # DROP malformed line, CONTINUE processing
            parse_errors.append({
                "line": line_num,
                "error": str(e),
                "raw": line[:100]  # First 100 chars for audit
            })
            continue  # DO NOT CRASH

    # Log parse errors to trajectory (if any)
    if parse_errors:
        data_loss_ratio = len(parse_errors) / total_lines

        log_trajectory({
            "phase": "jsonl_parse",
            "parse_errors": len(parse_errors),
            "dropped_lines": parse_errors,
            "data_loss_ratio": data_loss_ratio,
            "total_lines": total_lines
        })

        # Warn if data loss significant (>10%)
        if data_loss_ratio > 0.1:
            print(f"⚠️  High data loss: {data_loss_ratio:.1%} of lines dropped")

    return results
```

**Failure Modes**:
1. **Malformed JSON**: Drop line, log error, continue
2. **Missing fields**: Drop line, log validation error, continue
3. **Relative paths**: Convert to absolute, log warning, continue
4. **Empty results**: Valid (no matches), log to trajectory

**Audit Trail**: All dropped lines logged to `loa-grimoire/a2a/trajectory/{agent}-{date}.jsonl` (PRD FR-6.2).

---

### 3.4 Tool Result Clearing Manager

**Location**: Inline in agent skill logic
**Protocol**: `.claude/protocols/tool-result-clearing.md`

**Responsibility**: Enforce attention budgets, trigger synthesis when thresholds breached.

```python
# Pseudocode (agents implement in natural language)

class TokenBudgetManager:
    """
    Tracks token usage and enforces clearing thresholds.

    Budgets (PRD FR-4.1):
    - Single search: 2,000 tokens max
    - Accumulated results: 5,000 tokens → mandatory clearing
    - Full file loads: 3,000 tokens → single file only
    - Session total: 15,000 tokens → stop and synthesize
    """

    def __init__(self):
        self.single_search_budget = 2000
        self.accumulated_budget = 5000
        self.file_load_budget = 3000
        self.session_budget = 15000

        self.current_search_tokens = 0
        self.accumulated_tokens = 0
        self.session_tokens = 0
        self.decay_queue = []

    def on_search_start(self, query: str):
        """Log intent before search (prevents fishing)."""
        self.current_search_tokens = 0
        log_trajectory({
            "phase": "intent",
            "query": query,
            "expected_outcome": self.articulate_expected_outcome(query)
        })

    def on_search_complete(self, results: List[SearchResult]):
        """Process results and enforce budgets."""
        # Estimate token count (rough: 4 chars = 1 token)
        result_tokens = sum(len(r['snippet']) // 4 for r in results)

        self.current_search_tokens += result_tokens
        self.accumulated_tokens += result_tokens
        self.session_tokens += result_tokens

        # Check thresholds
        if len(results) > 20:
            print("⚠️  >20 results, triggering Tool Result Clearing")
            self.synthesize_and_clear(results)

        if self.accumulated_tokens > self.accumulated_budget:
            print("⚠️  Accumulated token budget exceeded, forcing synthesis")
            self.synthesize_and_clear(results)

        if self.session_tokens > self.session_budget:
            print("⚠️  Session token budget exceeded, HALT and summarize")
            self.finalize_session()

    def synthesize_and_clear(self, results: List[SearchResult]):
        """
        Extract high-signal findings, write to NOTES.md, clear raw results.

        Keeps only:
        - Top 10 files (by relevance score)
        - 20-word summary per file
        - Absolute file:line references
        """
        # Sort by relevance
        top_results = sorted(results, key=lambda r: r.get('score', 0.0), reverse=True)[:10]

        # Generate synthesis
        synthesis = "## Search Synthesis\n\n"
        for r in top_results:
            # Extract 20-word snippet
            words = r['snippet'].split()[:20]
            summary = ' '.join(words) + ('...' if len(words) == 20 else '')

            synthesis += f"- `{summary}` [{r['file']}:{r['line']}]\n"

        # Write to NOTES.md
        append_to_notes(synthesis)

        # Clear raw results from working memory
        # (Keep only single-line summary)
        log_trajectory({
            "phase": "clearing",
            "cleared_tokens": self.current_search_tokens,
            "synthesis_tokens": len(synthesis) // 4,
            "summary": f"Cleared {len(results)} results, kept {len(top_results)} references"
        })

        # Reset counters
        self.current_search_tokens = 0
        self.accumulated_tokens = 0

    def schedule_decay(self, file_path: str, timestamp: float):
        """
        Schedule semantic decay for a file reference.

        Stages (PRD FR-4.2):
        - Active (0-5 min): Full synthesis with code snippets
        - Decayed (5-30 min): Absolute paths only (lightweight identifiers)
        - Archived (30+ min): Single-line summary in trajectory
        """
        self.decay_queue.append({
            "file": file_path,
            "loaded_at": timestamp,
            "decay_stage": "active"
        })
```

**Integration**: Agents call `TokenBudgetManager` methods at search boundaries:
```python
budget_mgr = TokenBudgetManager()

# Before search
budget_mgr.on_search_start("JWT authentication entry points")

# Execute search
results = search_orchestrator("hybrid", "JWT auth validate token", "src/auth/")

# After search
budget_mgr.on_search_complete(results)
```

---

### 3.5 Ghost Feature Detector (Negative Grounding)

**Location**: `.claude/skills/discovering-requirements/ghost-detection.md`
**Protocol**: `.claude/protocols/negative-grounding.md`

**Responsibility**: Detect features documented in PRD but missing from code.

```python
# Pseudocode (agents implement in natural language)

def detect_ghost_feature(feature_name: str, feature_description: str) -> GhostStatus:
    """
    Determine if a feature is a Ghost (documented but not implemented).

    Protocol (PRD FR-3.2):
    1. Perform TWO diverse semantic queries
    2. Both must return 0 results
    3. Check for High Ambiguity (0 code + >3 doc mentions)
    4. Track in Beads if confirmed Ghost
    """

    # Query 1: Functional description
    query1 = feature_description  # e.g., "OAuth2 SSO login flow"
    results1 = search_orchestrator("semantic", query1, "src/", top_k=10, threshold=0.4)

    # Query 2: Architectural synonym
    query2 = generate_synonym(feature_description)  # e.g., "single sign-on identity provider"
    results2 = search_orchestrator("semantic", query2, "src/", top_k=10, threshold=0.4)

    # Count code results
    code_results = len(results1) + len(results2)

    # Count doc mentions
    doc_mentions = count_doc_mentions(feature_name, [
        "loa-grimoire/prd.md",
        "loa-grimoire/sdd.md",
        "README.md",
        "ARCHITECTURE.md"
    ])

    # Classification
    if code_results == 0 and doc_mentions <= 2:
        # CONFIRMED GHOST
        status = "confirmed_ghost"
        action = "Track in Beads, remove from docs"

        # Track in Beads (if available)
        if command_exists("bd"):
            subprocess.run([
                "bd", "create",
                f"GHOST: {feature_name}",
                "--type", "liability",
                "--priority", "2"
            ])

        # Log to trajectory
        log_trajectory({
            "phase": "ghost_detection",
            "feature": feature_name,
            "query1": query1,
            "results1": 0,
            "query2": query2,
            "results2": 0,
            "doc_mentions": doc_mentions,
            "status": "confirmed_ghost"
        })

    elif code_results == 0 and doc_mentions > 2:
        # HIGH AMBIGUITY
        status = "high_ambiguity"
        action = "Request human audit"

        log_trajectory({
            "phase": "ghost_detection",
            "feature": feature_name,
            "status": "high_ambiguity",
            "reason": f"0 code results but {doc_mentions} doc mentions - manual review needed"
        })

    else:
        # NOT GHOST (feature exists)
        status = "exists"
        action = "Feature exists, verify alignment"

        log_trajectory({
            "phase": "ghost_detection",
            "feature": feature_name,
            "status": "exists",
            "code_results": code_results
        })

    return GhostStatus(
        feature=feature_name,
        status=status,
        code_results=code_results,
        doc_mentions=doc_mentions,
        action=action
    )
```

**Output**: Written to `loa-grimoire/drift-report.md`:

```markdown
## Strategic Liabilities (Ghost Features)

| Feature | Doc Source | Search Evidence | Ambiguity | Beads ID | Action |
|---------|-----------|-----------------|-----------|----------|--------|
| OAuth2 SSO | PRD §3.2 | Query1: 0, Query2: 0 | Low | bd-123 | Remove from docs |
| Email Notifications | PRD §5.1 | Query1: 0, Query2: 0 | High (5 mentions) | - | **Human audit required** |
```

---

### 3.6 Shadow System Classifier

**Location**: `.claude/skills/discovering-requirements/shadow-detection.md`

**Responsibility**: Identify undocumented code and classify by risk.

```python
# Pseudocode (agents implement in natural language)

def classify_shadow_system(module_path: str, exports: List[str]) -> ShadowClassification:
    """
    Classify undocumented code by semantic similarity to documentation.

    Classification (PRD FR-3.3):
    - Orphaned (<0.3 similarity): HIGH risk, no doc match
    - Drifted (>0.5 similarity): MEDIUM risk, docs outdated
    - Partial (0.3-0.5 similarity): LOW risk, incomplete docs
    """

    # Load all documentation
    docs = load_docs([
        "loa-grimoire/prd.md",
        "loa-grimoire/sdd.md",
        "loa-grimoire/legacy/INVENTORY.md",
        "README.md"
    ])

    # Extract module name and functionality
    module_name = os.path.basename(module_path).replace('.ts', '')

    # Generate functional description from code
    code_content = read_file(module_path)
    func_description = extract_functional_description(code_content)

    # Search docs for semantic match
    doc_matches = search_orchestrator(
        "semantic",
        f"{module_name} {func_description}",
        "loa-grimoire/",
        top_k=5,
        threshold=0.3
    )

    # Calculate max similarity score
    if not doc_matches:
        max_similarity = 0.0
    else:
        max_similarity = max(r.get('score', 0.0) for r in doc_matches)

    # Classify
    if max_similarity < 0.3:
        classification = "orphaned"
        risk = "HIGH"
        action = "Urgent documentation required"

        # Generate dependency trace
        dependents = find_dependents(module_path)

        # Track in Beads
        if command_exists("bd"):
            subprocess.run([
                "bd", "create",
                f"SHADOW (orphaned): {module_name}",
                "--type", "debt",
                "--priority", "1"
            ])

    elif max_similarity > 0.5:
        classification = "drifted"
        risk = "MEDIUM"
        action = "Update existing docs"
        dependents = []

    else:
        classification = "partial"
        risk = "LOW"
        action = "Complete documentation"
        dependents = []

    # Log to trajectory
    log_trajectory({
        "phase": "shadow_detection",
        "module": module_path,
        "classification": classification,
        "similarity": max_similarity,
        "exports": exports,
        "dependents": len(dependents)
    })

    return ShadowClassification(
        module=module_path,
        classification=classification,
        risk=risk,
        similarity=max_similarity,
        dependents=dependents,
        action=action
    )

def find_dependents(module_path: str) -> List[str]:
    """
    Find all files that import the undocumented module.

    Uses regex search for import statements.
    """
    module_name = os.path.basename(module_path).replace('.ts', '')

    # Search for imports
    import_patterns = f"import.*{module_name}|require.*{module_name}|from.*{module_name}"

    results = search_orchestrator("regex", import_patterns, "src/")

    return [r['file'] for r in results]
```

**Output**: Written to `loa-grimoire/drift-report.md`:

```markdown
## Technical Debt (Shadow Systems)

| Module | Location | Classification | Risk | Dependents | Beads ID | Action |
|--------|----------|----------------|------|------------|----------|--------|
| legacyHasher | src/auth/legacy.ts | Orphaned | HIGH | 3 files | bd-124 | **Urgent: Document or remove** |
| cacheUtils | src/utils/cache.ts | Drifted | MEDIUM | 12 files | - | Update PRD §4.3 |
| debugHelpers | src/dev/debug.ts | Partial | LOW | 1 file | - | Add to SDD §6.2 |
```

---

### 3.7 Agent Chaining Component (Workflow Automation)

**Location**: `.claude/scripts/suggest-next-step.sh`, `.claude/workflow-chain.yaml`
**Protocol**: N/A (new feature)
**PRD Reference**: FR-8

**Responsibility**: Automatically suggest the next logical command after phase completion, enabling seamless workflow progression.

**Design Overview**:

The Agent Chaining system uses a declarative workflow definition to determine the next step based on current phase completion and validation conditions. This maintains workflow momentum without requiring users to memorize command sequences.

**Workflow Chain Definition**:

```yaml
# .claude/workflow-chain.yaml
version: 1.0

workflow:
  plan-and-analyze:
    next: architect
    condition:
      type: file_exists
      path: loa-grimoire/prd.md
    message: "Ready for architectural design."

  architect:
    next: sprint-plan
    condition:
      type: file_exists
      path: loa-grimoire/sdd.md
    message: "Ready for sprint planning."

  sprint-plan:
    next: implement sprint-1
    condition:
      type: file_exists
      path: loa-grimoire/sprint.md
    message: "Ready to begin implementation."

  implement:
    next: review-sprint {sprint}
    condition:
      type: file_exists
      path: loa-grimoire/a2a/sprint-{sprint}/reviewer.md
    message: "Implementation complete. Ready for code review."

  review-sprint:
    next_on_approval: audit-sprint {sprint}
    next_on_feedback: implement {sprint}
    condition:
      type: file_content_match
      path: loa-grimoire/a2a/sprint-{sprint}/engineer-feedback.md
      patterns:
        approval: "All good"
        feedback: "(CHANGES_REQUIRED|TODO|FIXME)"
    message_approval: "Code review passed. Ready for security audit."
    message_feedback: "Code review feedback provided. Ready to address issues."

  audit-sprint:
    next_on_approval: implement sprint-{N+1}
    next_on_changes: implement {sprint}
    condition:
      type: file_content_match
      path: loa-grimoire/a2a/sprint-{sprint}/auditor-sprint-feedback.md
      patterns:
        approval: "APPROVED - LETS FUCKING GO"
        changes: "CHANGES_REQUIRED"
    message_approval: "Security audit passed! Ready for next sprint."
    message_changes: "Security feedback provided. Ready to address issues."
```

**Suggestion Engine**:

```bash
#!/usr/bin/env bash
# .claude/scripts/suggest-next-step.sh

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
WORKFLOW_FILE="${PROJECT_ROOT}/.claude/workflow-chain.yaml"

# Parse arguments
CURRENT_PHASE="${1}"
SPRINT_ID="${2:-}"

# Load workflow definition
if [[ ! -f "${WORKFLOW_FILE}" ]]; then
    echo "No workflow chain configured" >&2
    exit 0
fi

# Extract next step for current phase
NEXT_STEP=$(yq e ".workflow.${CURRENT_PHASE}.next" "${WORKFLOW_FILE}")

if [[ "${NEXT_STEP}" == "null" ]] || [[ -z "${NEXT_STEP}" ]]; then
    # Check for conditional routing (approval vs feedback)
    NEXT_ON_APPROVAL=$(yq e ".workflow.${CURRENT_PHASE}.next_on_approval" "${WORKFLOW_FILE}")
    NEXT_ON_FEEDBACK=$(yq e ".workflow.${CURRENT_PHASE}.next_on_feedback" "${WORKFLOW_FILE}")

    if [[ "${NEXT_ON_APPROVAL}" != "null" ]]; then
        # Determine which path based on feedback file content
        FEEDBACK_FILE="${PROJECT_ROOT}/loa-grimoire/a2a/sprint-${SPRINT_ID}/engineer-feedback.md"

        if [[ -f "${FEEDBACK_FILE}" ]]; then
            if grep -q "All good" "${FEEDBACK_FILE}"; then
                NEXT_STEP="${NEXT_ON_APPROVAL}"
                MESSAGE=$(yq e ".workflow.${CURRENT_PHASE}.message_approval" "${WORKFLOW_FILE}")
            else
                NEXT_STEP="${NEXT_ON_FEEDBACK}"
                MESSAGE=$(yq e ".workflow.${CURRENT_PHASE}.message_feedback" "${WORKFLOW_FILE}")
            fi
        fi
    fi
fi

# Variable substitution for sprint IDs
if [[ -n "${SPRINT_ID}" ]]; then
    NEXT_STEP="${NEXT_STEP//\{sprint\}/${SPRINT_ID}}"

    # Handle {N+1} pattern for next sprint
    if [[ "${NEXT_STEP}" =~ \{N\+1\} ]]; then
        NEXT_SPRINT=$((SPRINT_ID + 1))
        NEXT_STEP="${NEXT_STEP//sprint-\{N+1\}/sprint-${NEXT_SPRINT}}"
    fi
fi

# Get default message if not already set
if [[ -z "${MESSAGE:-}" ]]; then
    MESSAGE=$(yq e ".workflow.${CURRENT_PHASE}.message" "${WORKFLOW_FILE}")
fi

# Validate condition before suggesting
CONDITION_TYPE=$(yq e ".workflow.${CURRENT_PHASE}.condition.type" "${WORKFLOW_FILE}")
CONDITION_PATH=$(yq e ".workflow.${CURRENT_PHASE}.condition.path" "${WORKFLOW_FILE}")

# Replace variables in path
CONDITION_PATH="${CONDITION_PATH//\{sprint\}/${SPRINT_ID}}"

case "${CONDITION_TYPE}" in
    file_exists)
        if [[ ! -f "${PROJECT_ROOT}/${CONDITION_PATH}" ]]; then
            echo "Condition not met: ${CONDITION_PATH} does not exist" >&2
            exit 1
        fi
        ;;
    file_content_match)
        # Already handled above in conditional routing
        ;;
esac

# Output suggestion in structured format
cat <<EOF

## Next Step

${MESSAGE}

**Recommended**: \`/${NEXT_STEP}\`

Would you like to proceed?
EOF
```

**Agent Integration**:

Each agent skill's completion includes:

```markdown
# In agent skill completion (e.g., .claude/skills/discovering-requirements/SKILL.md)

## Completion Protocol

After successfully completing the PRD:

1. Verify all deliverables:
   - loa-grimoire/prd.md exists
   - All functional requirements documented
   - Stakeholder context captured

2. Log completion to trajectory

3. Suggest next step:
   ```bash
   .claude/scripts/suggest-next-step.sh "plan-and-analyze"
   ```
```

**User Interaction Flow**:

```
Agent: "PRD generation complete. All 75 functional requirements documented."

[Agent internally calls: suggest-next-step.sh plan-and-analyze]

## Next Step

Ready for architectural design.

**Recommended**: `/architect`

Would you like to proceed?

User: [Types `/architect` to accept, or provides different command]
```

**Key Design Properties**:

1. **Declarative Configuration**: Workflow chain defined in YAML, not hardcoded
2. **Conditional Routing**: Different next steps based on approval vs feedback
3. **Variable Substitution**: Dynamic sprint IDs, user context
4. **Validation Before Suggestion**: Check conditions before suggesting
5. **Non-Blocking**: User can always decline or choose different command
6. **Extensible**: Users can customize workflow in `.claude/overrides/workflow-chain.yaml`

**Configuration Precedence**:

```
1. .claude/overrides/workflow-chain.yaml (highest priority)
2. .claude/workflow-chain.yaml (framework default)
```

**Backward Compatibility**:

- Workflow chain is purely additive (suggestions only)
- All commands work independently (no forced chaining)
- Users who ignore suggestions experience no change
- No breaking changes to existing command structure

---

### 3.8 Context Filtering Component (Pollution Prevention)

**Location**: `.claude/scripts/filter-search-results.sh`, configuration in `.loa.config.yaml`
**Protocol**: N/A (new feature)
**PRD Reference**: FR-9

**Responsibility**: Filter low-signal documents from search results to maintain agent focus and prevent context window pollution.

**Design Overview**:

The Context Filtering system provides multiple mechanisms to exclude low-signal content from search operations:

1. **Signal Markers**: Frontmatter-based filtering (high/medium/low)
2. **Archive Zone**: Explicit exclusion of `loa-grimoire/archive/`
3. **Pattern Excludes**: Configurable glob patterns for session artifacts
4. **Watch Paths**: Configurable drift detection scope

**Configuration Schema**:

```yaml
# .loa.config.yaml
drift_detection:
  watch_paths:
    - ".claude/"           # Framework files
    - "loa-grimoire/"      # Agent workspace
    - "docs/architecture/" # Custom documentation
    - ".meta/"             # Custom workflow directory (user-added)
  exclude_patterns:
    - "**/node_modules/**"
    - "**/*.log"
    - "**/target/**"       # Rust build artifacts
    - "**/dist/**"         # Build output

context_filtering:
  archive_zone: "loa-grimoire/archive/"  # Excluded from all searches

  default_excludes:
    - "**/brainstorm-*.md"
    - "**/session-notes-*.md"
    - "**/meeting-*.md"
    - "**/draft-*.md"
    - "**/scratch-*.md"

  signal_threshold: "medium"   # Exclude 'low' signal by default

  draft_ttl_days: 30           # Auto-suggest archival after 30 days

  enable_filtering: true       # Master toggle
```

**Signal Marker Format**:

```markdown
---
signal: low
type: brainstorm
date: 2024-01-15
archived: false
---

# Brainstorm Session Notes

Random thoughts that should not pollute search results...
```

**Signal Levels**:

| Level | Description | Search Behavior |
|-------|-------------|-----------------|
| `high` | Core architectural docs, PRD, SDD | Always included |
| `medium` | Sprint plans, implementation notes | Included by default |
| `low` | Brainstorms, meeting notes, drafts | Excluded by default (configurable) |
| (no marker) | Treated as `medium` | Included by default |

**Search Integration**:

```bash
#!/usr/bin/env bash
# .claude/scripts/filter-search-results.sh

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG="${PROJECT_ROOT}/.loa.config.yaml"

# Parse configuration
ARCHIVE_ZONE=$(yq e '.context_filtering.archive_zone // "loa-grimoire/archive/"' "${CONFIG}")
SIGNAL_THRESHOLD=$(yq e '.context_filtering.signal_threshold // "medium"' "${CONFIG}")
ENABLE_FILTERING=$(yq e '.context_filtering.enable_filtering // true' "${CONFIG}")

# Master toggle
if [[ "${ENABLE_FILTERING}" != "true" ]]; then
    cat  # Pass through unfiltered
    exit 0
fi

# Build exclude patterns for ck
build_ck_excludes() {
    local excludes=()

    # Archive zone
    excludes+=("--exclude" "${ARCHIVE_ZONE}")

    # Default exclude patterns
    while IFS= read -r pattern; do
        if [[ -n "${pattern}" ]] && [[ "${pattern}" != "null" ]]; then
            excludes+=("--exclude" "${pattern}")
        fi
    done < <(yq e '.context_filtering.default_excludes[]' "${CONFIG}" 2>/dev/null)

    echo "${excludes[@]}"
}

# Build exclude patterns for grep
build_grep_excludes() {
    local excludes=()

    # Archive zone (convert path to dir name)
    archive_dir=$(basename "${ARCHIVE_ZONE}")
    excludes+=("--exclude-dir=${archive_dir}")

    # Pattern excludes
    while IFS= read -r pattern; do
        if [[ -n "${pattern}" ]] && [[ "${pattern}" != "null" ]]; then
            # Convert glob to grep exclude
            pattern_name=$(basename "${pattern}")
            excludes+=("--exclude=${pattern_name}")
        fi
    done < <(yq e '.context_filtering.default_excludes[]' "${CONFIG}" 2>/dev/null)

    echo "${excludes[@]}"
}

# Filter by signal marker (post-processing)
filter_by_signal() {
    local file="$1"

    # Extract signal marker from frontmatter
    if [[ -f "${file}" ]]; then
        signal=$(awk '/^---$/,/^---$/ {if ($1 == "signal:") print $2}' "${file}" | head -1)

        # If no signal marker, treat as medium
        signal="${signal:-medium}"

        case "${SIGNAL_THRESHOLD}" in
            high)
                # Only high signal
                [[ "${signal}" == "high" ]]
                ;;
            medium)
                # high or medium
                [[ "${signal}" == "high" ]] || [[ "${signal}" == "medium" ]]
                ;;
            low)
                # Include all (no filtering)
                true
                ;;
        esac
    fi
}

# Export functions for use in search scripts
export -f filter_by_signal
export ARCHIVE_ZONE SIGNAL_THRESHOLD
```

**Drift Detection Integration**:

```bash
#!/usr/bin/env bash
# .claude/scripts/detect-drift.sh (enhanced)

PROJECT_ROOT=$(git rev-parse --show-toplevel)
CONFIG="${PROJECT_ROOT}/.loa.config.yaml"

# Load configured watch paths
readarray -t WATCH_PATHS < <(yq e '.drift_detection.watch_paths[]' "${CONFIG}")

# Default watch paths if not configured
if [[ ${#WATCH_PATHS[@]} -eq 0 ]]; then
    WATCH_PATHS=(
        ".claude/"
        "loa-grimoire/"
    )
fi

echo "Detecting drift in configured watch paths..." >&2

# Check git status for each watch path
for path in "${WATCH_PATHS[@]}"; do
    if [[ -d "${PROJECT_ROOT}/${path}" ]]; then
        echo "Checking: ${path}" >&2

        # Get unstaged/uncommitted changes
        git -C "${PROJECT_ROOT}" status --porcelain "${path}" | while read -r status file; do
            echo "  ${status} ${file}"
        done
    fi
done
```

**Search Wrapper Enhancement**:

```bash
# In .claude/scripts/search-orchestrator.sh

# Build exclude arguments
source "${PROJECT_ROOT}/.claude/scripts/filter-search-results.sh"

if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
    # Get ck excludes
    readarray -t CK_EXCLUDES < <(build_ck_excludes)

    ck --semantic "${QUERY}" \
        --path "${SEARCH_PATH}" \
        "${CK_EXCLUDES[@]}" \
        --jsonl
else
    # Get grep excludes
    readarray -t GREP_EXCLUDES < <(build_grep_excludes)

    grep -rn "${QUERY}" \
        "${GREP_EXCLUDES[@]}" \
        "${SEARCH_PATH}"
fi
```

**Draft TTL Automation** (future):

```bash
#!/usr/bin/env bash
# .claude/scripts/check-draft-ttl.sh

PROJECT_ROOT=$(git rev-parse --show-toplevel)
CONFIG="${PROJECT_ROOT}/.loa.config.yaml"
TTL_DAYS=$(yq e '.context_filtering.draft_ttl_days // 30' "${CONFIG}")

# Find drafts older than TTL
find loa-grimoire/ -name "draft-*.md" -mtime +${TTL_DAYS} | while read -r draft; do
    echo "Draft older than ${TTL_DAYS} days: ${draft}"
    echo "Consider archiving: mv \"${draft}\" loa-grimoire/archive/"
done
```

**Key Design Properties**:

1. **Multi-Layered Filtering**: Signal markers + archive zone + pattern excludes
2. **Configurable**: All exclusions defined in `.loa.config.yaml`
3. **Backward Compatible**: Filtering can be disabled entirely
4. **Tool-Agnostic**: Works with both ck and grep
5. **Extensible Watch Paths**: Users can add custom directories to drift detection

**Impact on Existing Components**:

- **Search Orchestrator**: Add exclude pattern building
- **Drift Detection**: Use configured watch paths instead of hardcoded
- **/ride Command**: Apply filtering to all searches
- **Trajectory Logging**: Log which files were excluded (audit trail)

---

### 3.9 Command Namespace Protection Component

**Location**: `.claude/scripts/validate-commands.sh`, `.claude/reserved-commands.yaml`
**Protocol**: N/A (new feature)
**PRD Reference**: FR-10 (P0 BLOCKER)

**Responsibility**: Prevent Loa custom commands from conflicting with Claude Code built-in commands by validating command names and enforcing reserved namespace.

**Design Overview**:

The Command Namespace Protection system maintains a list of Claude Code reserved commands and validates all Loa commands against this list during setup and updates. Conflicts are automatically resolved by renaming with a `-loa` suffix.

**Reserved Commands Registry**:

```yaml
# .claude/reserved-commands.yaml
version: 1.0

# Claude Code built-in commands (enshrined/protected)
reserved:
  - config              # Claude Code settings management
  - help                # Claude Code help system
  - clear               # Clear conversation history
  - compact             # Compact context window
  - cost                # Show API cost
  - doctor              # System diagnostics
  - init                # Initialize Claude Code project
  - login               # Authentication
  - logout              # Sign out
  - memory              # Memory management
  - model               # Model selection
  - pr-comments         # Pull request review
  - review              # Code review (built-in)
  - terminal-setup      # Terminal configuration
  - vim                 # Vim mode toggle

  # Additional reserved commands (future-proofing)
  - settings
  - preferences
  - debug
  - test
  - build
  - deploy

# Metadata
last_updated: "2025-12-26"
source: "Claude Code built-in commands"
```

**Validation Script**:

```bash
#!/usr/bin/env bash
# .claude/scripts/validate-commands.sh

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RESERVED_FILE="${PROJECT_ROOT}/.claude/reserved-commands.yaml"
COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"

# Load reserved command list
readarray -t RESERVED < <(yq e '.reserved[]' "${RESERVED_FILE}")

echo "Validating command namespace against Claude Code reserved commands..." >&2

# Track conflicts
CONFLICTS=()
RENAMED=()

# Check each command file
for cmd_file in "${COMMANDS_DIR}"/*.md; do
    if [[ ! -f "${cmd_file}" ]]; then
        continue
    fi

    cmd_name=$(basename "${cmd_file}" .md)

    # Check against reserved list
    for reserved in "${RESERVED[@]}"; do
        if [[ "${cmd_name}" == "${reserved}" ]]; then
            CONFLICTS+=("${cmd_name}")

            # Auto-rename with -loa suffix
            new_name="${cmd_name}-loa"
            new_file="${COMMANDS_DIR}/${new_name}.md"

            echo "" >&2
            echo "❌ CONFLICT: /${cmd_name} conflicts with Claude Code built-in" >&2
            echo "   Renaming to: /${new_name}" >&2

            # Rename file
            mv "${cmd_file}" "${new_file}"

            # Update internal references in frontmatter
            sed -i "s/command: ${cmd_name}/command: ${new_name}/g" "${new_file}"

            RENAMED+=("${cmd_name} → ${new_name}")
            break
        fi
    done
done

# Report results
echo "" >&2
if [[ ${#CONFLICTS[@]} -eq 0 ]]; then
    echo "✓ No command conflicts detected" >&2
    exit 0
else
    echo "⚠️  ${#CONFLICTS[@]} conflict(s) resolved:" >&2
    for rename in "${RENAMED[@]}"; do
        echo "   - ${rename}" >&2
    done

    echo "" >&2
    echo "Please update your workflows to use the new command names." >&2
    exit 0  # Exit 0 after auto-fix (not a hard failure)
fi
```

**Pre-flight Integration**:

```bash
#!/usr/bin/env bash
# .claude/scripts/preflight.sh (enhanced)

# ... existing pre-flight checks ...

# Command namespace validation (new)
if [[ -f "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh" ]]; then
    echo "Validating command namespace..." >&2
    "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh"
fi
```

**Setup Integration**:

```markdown
# .claude/commands/setup.md (enhanced)

## Phase 3: Command Validation

After synthesizing framework files:

1. Validate command namespace:
   ```bash
   .claude/scripts/validate-commands.sh
   ```

2. If conflicts detected:
   - Commands automatically renamed with `-loa` suffix
   - User notified of changes
   - Documentation updated with new names

3. Log validation results to setup report
```

**Update Integration**:

```bash
#!/usr/bin/env bash
# .claude/scripts/update.sh (enhanced)

# ... existing update logic ...

# Validate commands after framework update
echo "Validating command namespace after update..." >&2
"${PROJECT_ROOT}/.claude/scripts/validate-commands.sh"

# If conflicts resolved, regenerate checksums
if [[ $? -eq 0 ]]; then
    "${PROJECT_ROOT}/.claude/scripts/generate-checksums.sh"
fi
```

**Current Conflict Resolution**:

```bash
# Immediate action required:
# Rename /config to /config-loa or /mcp-config

mv .claude/commands/config.md .claude/commands/mcp-config.md

# Update frontmatter
sed -i 's/command: config/command: mcp-config/g' .claude/commands/mcp-config.md

# Update documentation references
grep -rl "/config" README.md INSTALLATION.md PROCESS.md | xargs sed -i 's/\/config/\/mcp-config/g'
```

**User Communication**:

When conflicts are detected during setup:

```
❌ CONFLICT: /config conflicts with Claude Code built-in
   Renaming to: /mcp-config

⚠️  1 conflict(s) resolved:
   - config → mcp-config

Please update your workflows to use the new command names.

To access Claude Code settings, use the built-in /config command.
To configure Loa MCP servers, use /mcp-config.
```

**CI Integration**:

```yaml
# .github/workflows/validate-commands.yml
name: Validate Command Namespace

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Validate command namespace
        run: |
          .claude/scripts/validate-commands.sh

          # Check if any conflicts exist
          if [[ $(find .claude/commands/ -name "*-loa.md" | wc -l) -gt 0 ]]; then
            echo "::error::Command conflicts detected and auto-fixed"
            echo "::warning::Please review renamed commands"
            exit 1
          fi
```

**Key Design Properties**:

1. **P0 Blocker Prevention**: Validation runs during setup and updates (cannot be skipped)
2. **Auto-Resolution**: Conflicts automatically renamed with `-loa` suffix
3. **Non-Breaking**: Existing workflows updated but not broken
4. **Extensible Registry**: Reserved list can grow as Claude Code adds features
5. **CI Enforcement**: Pull requests fail if conflicts detected
6. **Clear Communication**: Users informed of renames with actionable guidance

**Impact on Existing Components**:

- **Setup Command**: Add namespace validation phase
- **Update Command**: Re-validate after framework updates
- **Pre-flight Check**: Include validation in pre-flight checks
- **CI/CD**: Add validation job to GitHub Actions
- **Documentation**: Update all references from `/config` → `/mcp-config`

**Backward Compatibility**:

- Existing `/config` command automatically renamed to `/mcp-config`
- Users with old workflows will see clear error messages pointing to new names
- Reserved list additions trigger automatic renames (non-breaking updates)

---

## 4. Data Architecture

### 4.1 ck Index Structure

**Location**: `.ck/` (State Zone, gitignored)

```
.ck/
├── index/
│   ├── embeddings.bin        # Vector embeddings (nomic-v1.5: 768-dim floats)
│   ├── metadata.db           # SQLite: file paths, line numbers, hashes
│   └── inverted_index.db     # Keyword inverted index (for hybrid search)
├── cache/
│   ├── query_cache.db        # SQLite: query → results mapping (80-90% hit rate)
│   └── result_cache.json     # Hot cache (recent queries, <5min)
├── config.toml               # Runtime config (model, thresholds)
├── .last_commit              # Git commit hash of last index (for delta)
└── .index_lock               # Prevent concurrent reindex

# Size estimates:
# - embeddings.bin: ~3MB per 1000 files (768 floats * 4 bytes * ~1000 vectors)
# - metadata.db: ~1MB per 10,000 files
# - query_cache.db: ~10MB typical (unbounded, pruned on space pressure)
```

**Schema: `metadata.db`**
```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL,          -- Absolute path
    hash TEXT NOT NULL,           -- SHA-256 of file content
    indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    size_bytes INTEGER,
    language TEXT                 -- Detected language (js, py, rs, etc.)
);

CREATE TABLE chunks (
    id INTEGER PRIMARY KEY,
    file_id INTEGER REFERENCES files(id),
    line_start INTEGER,
    line_end INTEGER,
    content TEXT,                 -- Raw code snippet
    embedding_id INTEGER,         -- Foreign key to embeddings.bin offset
    ast_type TEXT                 -- function, class, import, etc.
);

CREATE INDEX idx_files_path ON files(path);
CREATE INDEX idx_files_hash ON files(hash);
CREATE INDEX idx_chunks_file ON chunks(file_id);
```

**Schema: `inverted_index.db`**
```sql
CREATE TABLE tokens (
    id INTEGER PRIMARY KEY,
    token TEXT UNIQUE NOT NULL
);

CREATE TABLE postings (
    token_id INTEGER REFERENCES tokens(id),
    chunk_id INTEGER REFERENCES chunks(id),
    frequency INTEGER,            -- TF-IDF term frequency
    PRIMARY KEY (token_id, chunk_id)
);

CREATE INDEX idx_postings_token ON postings(token_id);
```

**Schema: `query_cache.db`**
```sql
CREATE TABLE cache_entries (
    query_hash TEXT PRIMARY KEY,  -- SHA-256 of (query, path, top_k, threshold)
    query TEXT,
    results_json TEXT,            -- JSONL results (compressed)
    hit_count INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Eviction: LRU when cache size exceeds 100MB
CREATE INDEX idx_cache_lru ON cache_entries(last_accessed);
```

---

### 4.2 Trajectory Log Format

**Location**: `loa-grimoire/a2a/trajectory/{agent}-{YYYY-MM-DD}.jsonl`

**Schema**:
```jsonl
{"ts": "2025-12-26T10:30:00Z", "agent": "implementing-tasks", "phase": "intent", "query": "JWT validation", "expected_outcome": "Find 1-3 token validation functions", "rationale": "Need to extend auth with refresh tokens"}

{"ts": "2025-12-26T10:30:05Z", "agent": "implementing-tasks", "phase": "execute", "mode": "ck", "search_type": "hybrid", "query": "JWT validation", "path": "/home/user/project/src/auth/", "top_k": 20, "threshold": 0.4, "result_count": 3}

{"ts": "2025-12-26T10:30:06Z", "agent": "implementing-tasks", "phase": "cite", "claim": "Uses JWT validation", "code": "export async function validateToken(token: string): Promise<TokenPayload>", "file": "/home/user/project/src/auth/jwt.ts", "line": 45, "score": 0.89}

{"ts": "2025-12-26T10:30:10Z", "agent": "implementing-tasks", "phase": "pivot", "reason": "Initial query too broad", "original_query": "authentication", "result_count": 127, "hypothesis_failure": "Captured all auth code, not just entry points", "refined_hypothesis": "Target initialization patterns", "new_query": "auth initialization bootstrap"}

{"ts": "2025-12-26T10:35:00Z", "agent": "implementing-tasks", "phase": "clearing", "cleared_tokens": 1850, "synthesis_tokens": 120, "summary": "Cleared 23 results, kept 10 references"}

{"ts": "2025-12-26T10:40:00Z", "agent": "implementing-tasks", "phase": "jsonl_parse", "parse_errors": 2, "dropped_lines": [{"line": 15, "error": "Expecting value"}, {"line": 23, "error": "Invalid control character"}], "data_loss_ratio": 0.087, "total_lines": 23}

{"ts": "2025-12-26T10:45:00Z", "agent": "implementing-tasks", "phase": "ghost_detection", "feature": "OAuth2 SSO", "query1": "OAuth2 SSO login flow", "results1": 0, "query2": "single sign-on identity provider", "results2": 0, "doc_mentions": 2, "status": "confirmed_ghost", "beads_id": "bd-123"}

{"ts": "2025-12-26T10:50:00Z", "agent": "implementing-tasks", "phase": "shadow_detection", "module": "/home/user/project/src/auth/legacy.ts", "classification": "orphaned", "similarity": 0.15, "exports": ["hashLegacy", "verifyLegacy"], "dependents": 3, "beads_id": "bd-124"}
```

**Retention Policy** (User Decision: Archive to compressed storage):
```yaml
# .loa.config.yaml
trajectory:
  retention:
    active_days: 30          # Keep raw JSONL for 30 days
    archive_after_days: 30   # Compress to .jsonl.gz
    delete_after_days: 365   # Purge after 1 year
  compression:
    enabled: true
    format: gzip
    level: 6                 # Balance speed vs. size
```

**Compaction Script**: `.claude/scripts/compact-trajectory.sh`
```bash
#!/usr/bin/env bash
# Compress trajectories older than 30 days

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"

# Find files older than 30 days
find "${TRAJECTORY_DIR}" -name "*.jsonl" -mtime +30 | while read -r file; do
    echo "Compressing: ${file}"
    gzip -9 "${file}"  # Creates file.jsonl.gz, removes original
done

# Purge archives older than 365 days
find "${TRAJECTORY_DIR}" -name "*.jsonl.gz" -mtime +365 -delete
```

---

### 4.3 NOTES.md Structure (Structured Memory)

**Location**: `loa-grimoire/NOTES.md`
**Protocol**: `.claude/protocols/structured-memory.md`

**Format**:
```markdown
# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.

## Active Sub-Goals
<!-- Current objectives being pursued -->

**Sprint 2: Authentication Refactor**
- Extend JWT validation with refresh tokens
- Add rate limiting to auth endpoints
- Status: In progress (3/5 tasks complete)

## Discovered Technical Debt
<!-- Issues found during implementation -->

**Shadow System: legacyHasher module**
- Location: src/auth/legacy.ts
- Classification: Orphaned (similarity: 0.15)
- Dependents: 3 files (src/auth/handler.ts, src/users/service.ts, src/admin/auth.ts)
- Risk: HIGH - undocumented, unclear purpose
- Action: Request human audit - remove or document immediately
- Beads: bd-124

## Blockers & Dependencies
<!-- External factors affecting progress -->

**Blocker: OAuth2 library selection**
- Need to choose between passport-oauth2 vs. custom implementation
- Waiting on architect agent recommendation
- Impacts: Sprint 3 tasks

## Session Continuity
<!-- Key context to restore on next session -->

| Timestamp | Agent | Summary |
|-----------|-------|---------|
| 2025-12-26 10:30 | implementing-tasks | JWT refactor complete. Extended validateToken() with refresh logic. Tests passing. |
| 2025-12-26 10:45 | implementing-tasks | Discovered legacy hasher module (orphaned). Tracked as bd-124. Needs immediate attention. |

## Decision Log
<!-- Major decisions with rationale -->

**Decision: Use refresh token rotation**
- Rationale: Mitigates token theft (OWASP recommendation)
- Evidence: `validateToken()` already supports expiry checks [src/auth/jwt.ts:45]
- Implementation: Store refresh token hash in DB, rotate on use
- Source: PRD §3.2.1

**Decision: Reuse existing JWT library**
- Rationale: jsonwebtoken@9.0 already integrated, battle-tested
- Evidence: `import jwt from 'jsonwebtoken'` [src/auth/jwt.ts:1]
- Alternative considered: jose (rejected: overkill for simple JWT)
- Source: SDD §3.1
```

**Update Frequency**:
- After every search synthesis (Tool Result Clearing)
- Before session end (continuity log)
- On major decisions (decision log)

**Compaction**: When NOTES.md exceeds 5,000 lines → archive older sections to `loa-grimoire/a2a/notes-archive/{date}.md`

---

## 5. API Design

### 5.1 Internal Search API (Bash Functions)

**Location**: `.claude/scripts/search-api.sh`
**Sourced By**: All agent skills

```bash
#!/usr/bin/env bash
# .claude/scripts/search-api.sh
# Internal API for semantic/hybrid/regex search

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Public API Functions

semantic_search() {
    # Usage: semantic_search <query> [path] [top_k] [threshold]
    local query="${1}"
    local path="${2:-${PROJECT_ROOT}/src}"
    local top_k="${3:-20}"
    local threshold="${4:-0.4}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "semantic" "${query}" "${path}" "${top_k}" "${threshold}"
}

hybrid_search() {
    # Usage: hybrid_search <query> [path] [top_k] [threshold]
    local query="${1}"
    local path="${2:-${PROJECT_ROOT}/src}"
    local top_k="${3:-20}"
    local threshold="${4:-0.5}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "hybrid" "${query}" "${path}" "${top_k}" "${threshold}"
}

regex_search() {
    # Usage: regex_search <pattern> [path]
    local pattern="${1}"
    local path="${2:-${PROJECT_ROOT}/src}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "regex" "${pattern}" "${path}" "100" "0.0"
}

# Helper: Convert grep output to JSONL
grep_to_jsonl() {
    # Input: file:line:snippet format from grep
    # Output: {"file": "...", "line": ..., "snippet": "...", "score": 0.0}

    while IFS=: read -r file line snippet; do
        # Normalize to absolute path
        if [[ ! "${file}" =~ ^/ ]]; then
            file="${PROJECT_ROOT}/${file}"
        fi

        jq -n \
            --arg file "${file}" \
            --argjson line "${line}" \
            --arg snippet "${snippet}" \
            --argjson score 0.0 \
            '{file: $file, line: $line, snippet: $snippet, score: $score}'
    done
}

# Helper: Extract code snippet from file at line
extract_snippet() {
    local file="${1}"
    local line="${2}"
    local context="${3:-5}"  # Lines of context before/after

    sed -n "$((line - context)),$((line + context))p" "${file}" 2>/dev/null || echo ""
}

# Helper: Count token estimate (4 chars ≈ 1 token)
estimate_tokens() {
    local text="${1}"
    echo $(( ${#text} / 4 ))
}

# Export functions for use in subshells
export -f semantic_search
export -f hybrid_search
export -f regex_search
export -f grep_to_jsonl
export -f extract_snippet
export -f estimate_tokens
```

**Usage in Agent Skills**:
```bash
# In .claude/skills/implementing-tasks/SKILL.md

# Source search API
source "${PROJECT_ROOT}/.claude/scripts/search-api.sh"

# Find JWT validation functions
results=$(semantic_search "JWT token validation authentication" "src/auth/" 10 0.5)

# Parse JSONL and extract top result
top_result=$(echo "${results}" | head -n 1 | jq -r '.file + ":" + (.line | tostring)')

# Load snippet with context
snippet=$(extract_snippet "${file}" "${line}" 10)
```

---

### 5.2 CLI Interface (ck Commands)

**Direct Invocation** (v1.0):
```bash
# Semantic search
ck --semantic "query string" \
    --path /absolute/path/to/search \
    --top-k 20 \
    --threshold 0.4 \
    --jsonl

# Hybrid search (semantic + keyword)
ck --hybrid "query string" \
    --path /absolute/path/to/search \
    --top-k 20 \
    --threshold 0.5 \
    --jsonl

# Regex search
ck --regex "pattern" \
    --path /absolute/path/to/search \
    --jsonl

# Indexing
ck --index /absolute/path/to/project \
    [--delta]           # Incremental (only changed files)
    [--quiet]           # Suppress output
    [--model nomic-v1.5]  # Embedding model
```

**MCP Server Interface** (v2.0 roadmap):
```json
// MCP Tool Definition
{
  "name": "semantic_search",
  "description": "Find code by meaning using embeddings",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {"type": "string", "minLength": 3, "maxLength": 500},
      "path": {"type": "string", "default": "."},
      "top_k": {"type": "integer", "default": 20, "minimum": 1, "maximum": 100},
      "threshold": {"type": "number", "default": 0.4, "minimum": 0.0, "maximum": 1.0}
    },
    "required": ["query"],
    "additionalProperties": false
  }
}

// MCP Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "semantic_search",
    "arguments": {
      "query": "JWT validation",
      "path": "/home/user/project/src/auth/",
      "top_k": 10,
      "threshold": 0.5
    }
  }
}

// MCP Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"file\":\"/home/user/project/src/auth/jwt.ts\",\"line\":45,\"snippet\":\"export async function validateToken(token: string)\",\"score\":0.89}\n..."
      }
    ]
  }
}
```

---

## 6. Security Architecture

### 6.1 Integrity Verification

**Threat Model**:
1. **System Zone Tampering**: Malicious modification of `.claude/` files
2. **Binary Replacement**: ck binary swapped with malicious version
3. **Index Poisoning**: `.ck/` directory corrupted or injected with fake results
4. **Supply Chain Attack**: Compromised ck release from cargo

**Mitigation Layers**:

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: System Zone Checksum Verification                      │
│ - SHA-256 hashes in .claude/checksums.json                      │
│ - Verified on every ck invocation (pre-flight)                  │
│ - Enforcement: strict (HALT) | warn (LOG) | disabled            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Binary Fingerprint Verification                        │
│ - SHA-256 of ck binary in .loa-version.json                     │
│ - Checked on first invocation per session                       │
│ - Enforcement: strict (HALT) | warn (LOG)                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: State Zone Self-Healing                                │
│ - .ck/ directory regenerated if missing/corrupted               │
│ - Index validated via hash comparison                           │
│ - Automatic delta reindex on git commit                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 4: Trajectory Audit Trail                                 │
│ - All search operations logged to immutable JSONL               │
│ - reviewing-code agent verifies reasoning chains                │
│ - Compressed archives prevent tampering detection              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 5: Command Namespace Protection (FR-10)                   │
│ - Reserved command list prevents Claude Code conflicts          │
│ - Pre-flight validation during setup and updates               │
│ - Auto-rename conflicting commands with -loa suffix            │
│ - CI enforcement prevents introduction of new conflicts        │
└─────────────────────────────────────────────────────────────────┘
```

**Checksum Generation** (during `/update`):
```bash
#!/usr/bin/env bash
# .claude/scripts/generate-checksums.sh

PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Generate checksums for all System Zone files
find .claude/ -type f \
    -not -path ".claude/overrides/*" \
    -not -path ".claude/checksums.json" \
    -not -path ".claude/.git/*" \
    | while read -r file; do
        hash=$(sha256sum "${file}" | awk '{print $1}')
        echo "\"${file}\": \"${hash}\""
    done | jq -s 'from_entries' > .claude/checksums.json
```

**Binary Fingerprint Recording**:
```bash
# After cargo install ck-search
CK_PATH=$(command -v ck)
CK_FINGERPRINT=$(sha256sum "${CK_PATH}" | awk '{print $1}')

# Update .loa-version.json
jq --arg fp "${CK_FINGERPRINT}" \
    '.binary_fingerprints.ck = $fp' \
    .loa-version.json > .loa-version.json.tmp
mv .loa-version.json.tmp .loa-version.json
```

---

### 6.2 Sandboxing & Isolation

**Execution Model**: Direct subprocess invocation (no network)

```python
# Safe subprocess invocation (Python pseudocode)

import subprocess
import os

def safe_ck_search(query: str, path: str) -> str:
    """
    Execute ck in sandboxed environment.

    Safety measures:
    - No shell=True (prevents injection)
    - Explicit PATH (prevents binary hijacking)
    - Timeout enforcement (prevents DoS)
    - Absolute paths only (prevents traversal)
    """

    # Validate inputs
    if not os.path.isabs(path):
        raise ValueError(f"Path must be absolute: {path}")

    if not os.path.exists(path):
        raise ValueError(f"Path does not exist: {path}")

    # Explicit ck binary path (prevent PATH hijacking)
    ck_binary = "/usr/local/bin/ck"  # Or: shutil.which("ck")

    # Build command (NO shell=True)
    cmd = [
        ck_binary,
        "--semantic", query,
        "--path", path,
        "--top-k", "20",
        "--threshold", "0.4",
        "--jsonl"
    ]

    # Execute with timeout (prevent DoS)
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30.0,  # 30 second timeout
            check=False,   # Don't raise on non-zero exit
            env={"PATH": "/usr/local/bin:/usr/bin"}  # Explicit PATH
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("Search timed out (>30s)")

    # Handle errors
    if result.returncode != 0:
        # Log error to trajectory, fallback to grep
        log_trajectory({
            "phase": "error",
            "command": " ".join(cmd),
            "returncode": result.returncode,
            "stderr": result.stderr[:500]  # First 500 chars
        })
        return ""

    return result.stdout
```

**Key Safety Properties**:
1. No `shell=True` → Prevents command injection
2. Absolute paths → Prevents directory traversal
3. Explicit PATH → Prevents binary hijacking
4. Timeout enforcement → Prevents DoS
5. Error logging → Audit trail for failures

---

### 6.3 Secrets & Credentials

**ck has NO network access** → No API keys, no tokens, no credentials.

**Potential Future Risk** (v2.0 MCP migration):
- MCP servers may have network access (embeddings API)
- **Mitigation**: Environment variable isolation, secret scanning

```yaml
# .loa.config.yaml (v2.0)
ck_mcp:
  embeddings_api:
    provider: "local"  # local | openai | anthropic
    api_key_env: "CK_EMBEDDINGS_API_KEY"  # Environment variable (never committed)
    endpoint: "https://api.openai.com/v1/embeddings"
```

**Secret Scanning** (pre-commit hook):
```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash

# Check for secrets in staged files
if git diff --cached | grep -iE 'api_key|password|secret|token' | grep -vE '(env|example|placeholder)'; then
    echo "❌ Potential secret detected in commit"
    echo "Remove sensitive data before committing"
    exit 1
fi
```

---

## 7. Integration Points

### 7.1 Command Integration

**Modified Commands**:

| Command | Integration Point | ck Usage | Fallback |
|---------|------------------|----------|----------|
| `/ride` | Code Reality Extraction | Semantic search for entry points, abstractions, exports | grep patterns |
| `/implement sprint-N` | Context loading | Hybrid search for related code, patterns | grep + manual review |
| `/review-sprint sprint-N` | Impact analysis | Find dependents, test coverage | grep imports |
| `/architect` | Pattern discovery | Semantic search for architectural patterns | grep class/interface |
| `/audit-sprint sprint-N` | Security analysis | Semantic search for auth/crypto/validation patterns | grep keywords |

**Example: `/ride` Enhancement**:

```markdown
# .claude/commands/ride.md

agent: discovering-requirements
agent_path: .claude/skills/discovering-requirements/

---

You are mounting an **existing codebase** to extract Code Reality...

## Phase A: Entry Point Discovery

**With ck (semantic mode)**:
```bash
# Find entry points semantically
semantic_search "main entry point bootstrap initialize startup" "src/" 10 0.5

# Cross-validate with keyword search
hybrid_search "main function init start" "src/" 10 0.5
```

**Without ck (grep fallback)**:
```bash
# Pattern-based entry point detection
grep -rn "function main\|def main\|fn main\|public static void main\|Main.main" \
    --include="*.js" --include="*.ts" --include="*.py" --include="*.go" \
    --include="*.rs" --include="*.java" \
    src/ 2>/dev/null | head -20
```

**Output format (identical for both modes)**:
```markdown
## Entry Points

- `main()` [src/index.ts:45] - Express server initialization
- `bootstrap()` [src/app.ts:12] - Application bootstrapper
- `start()` [src/server.ts:78] - HTTP server start
```
```

---

### 7.2 Skill Integration

**Enhanced Skills**:

**1. `implementing-tasks`** (Context Loading)

```markdown
# .claude/skills/implementing-tasks/context-retrieval.md

## Context Loading Protocol

Before implementing ANY task, load relevant context:

### Step 1: Understand Task Scope
- Read task description from loa-grimoire/sprint.md
- Extract key concepts (e.g., "JWT authentication", "rate limiting")

### Step 2: Find Related Code (Semantic)
```bash
# Source search API
source .claude/scripts/search-api.sh

# Find semantically related code
results=$(semantic_search "<task_key_concepts>" "src/" 20 0.5)

# Example: "Implement refresh token rotation"
results=$(semantic_search "JWT refresh token authentication validation" "src/auth/" 20 0.5)
```

### Step 3: Find Similar Patterns (Hybrid)
```bash
# Find architectural patterns
patterns=$(hybrid_search "token validation middleware error handling" "src/" 15 0.4)
```

### Step 4: Synthesize to NOTES.md
```markdown
## Context Load: <timestamp>
**Task**: sprint-2/task-3 (Refresh token rotation)

**Key Files**:
- `src/auth/jwt.ts:45-67` - Primary JWT validation logic
- `src/middleware/auth.ts:23-34` - Auth middleware pattern
- `src/utils/errors.ts:12` - Error handling pattern

**Patterns Found**:
- All validation functions return Promise<T | null>
- Errors thrown as custom AuthError class
- Middleware uses next(err) for error propagation

**Ready to implement**: Yes
```

### Step 5: Apply Tool Result Clearing
If search returned >20 results, synthesize and clear (PRD FR-4.1).
```

---

**2. `reviewing-code`** (Impact Analysis)

```markdown
# .claude/skills/reviewing-code/impact-analysis.md

## Impact Analysis Protocol

Before reviewing sprint implementation, analyze full impact:

### Step 1: Find Dependents
```bash
# Changed file: src/auth/jwt.ts
# Find all imports of this module

results=$(regex_search "import.*jwt|require.*jwt|from.*['\"].*jwt" "src/")

# Parse unique files
dependents=$(echo "${results}" | jq -r '.file' | sort -u)
```

### Step 2: Find Test Coverage
```bash
# Find test files covering changed module
test_results=$(hybrid_search "jwt validation test spec describe it" "test/" 10 0.5)
```

### Step 3: Check Pattern Consistency
```bash
# Compare implementation to existing patterns
pattern_query="token validation error handling promise async"
similar_code=$(semantic_search "${pattern_query}" "src/" 10 0.6)

# Verify new code follows same patterns
```

### Step 4: Generate Review Report
Write to loa-grimoire/a2a/sprint-N/engineer-feedback.md:

```markdown
## Impact Analysis

**Changed Files**: 3
- src/auth/jwt.ts (extended validateToken)
- src/middleware/auth.ts (added refreshToken middleware)
- src/types/auth.ts (added RefreshTokenPayload type)

**Dependents**: 12 files import jwt.ts
- ✓ All imports updated to handle new signature
- ⚠️  src/admin/auth.ts still uses old pattern (needs update)

**Test Coverage**: 85%
- ✓ Unit tests added for refresh token rotation
- ✓ Integration test covers full auth flow
- ❌ Missing edge case: expired refresh token

**Pattern Consistency**: Good
- ✓ Follows existing Promise<T | null> pattern
- ✓ Uses AuthError for validation failures
- ✓ Middleware uses next(err) correctly

## Verdict
**Status**: Changes required

**Issues**:
1. Update src/admin/auth.ts to new validateToken signature
2. Add edge case test: expired refresh token
3. Update JSDoc comments in jwt.ts (missing @throws)

**Once fixed**: Re-request review
```
```

---

### 7.3 Beads Integration (Optional)

**Detection**: `.claude/scripts/check-beads.sh`
```bash
#!/usr/bin/env bash
# Check if Beads (bd CLI) is available

if command -v bd >/dev/null 2>&1; then
    echo "✓ Beads installed: $(bd --version 2>/dev/null || echo 'unknown')"
    export LOA_BEADS_AVAILABLE=1
else
    echo "○ Beads not installed (optional - Ghost/Shadow tracking will use grimoire only)"
    export LOA_BEADS_AVAILABLE=0
fi
```

**Usage in Ghost/Shadow Detection**:
```bash
# In ghost-detection logic
if [[ "${LOA_BEADS_AVAILABLE}" == "1" ]]; then
    # Create Beads task
    bd create "GHOST: ${feature_name}" \
        --type liability \
        --priority 2 \
        --tags "loa,ghost-feature,${sprint_id}" \
        --note "Documented in PRD ${prd_section}, 0 code results" \
        2>/dev/null || true  # Silent failure if Beads errors

    # Capture Beads ID for grimoire
    beads_id=$(bd list --filter "GHOST: ${feature_name}" --format json | jq -r '.[-1].id')
else
    # No Beads: Track in grimoire only
    beads_id="N/A"
fi

# Write to drift-report.md (works with or without Beads)
echo "| ${feature_name} | PRD §${section} | 0 results | Low | ${beads_id} | Remove from docs |" \
    >> loa-grimoire/drift-report.md
```

**Key Property**: Beads is **invisible degradation** - system works identically without it (PRD §1.3).

---

## 8. Scalability & Performance

### 8.1 Caching Strategy

**Cache Hierarchy**:

```
┌─────────────────────────────────────────────────────────────────┐
│ L1: Hot Cache (In-Memory, <5 min)                               │
│ - Last 10 queries + results                                     │
│ - Hit latency: ~1ms                                             │
│ - Eviction: LRU on size limit (10MB)                            │
└─────────────────────────────────────────────────────────────────┘
        │ miss
        ▼
┌─────────────────────────────────────────────────────────────────┐
│ L2: Query Cache (SQLite, persistent)                            │
│ - Hash(query + path + top_k + threshold) → results             │
│ - Hit latency: ~5-10ms                                          │
│ - Eviction: LRU on size limit (100MB)                           │
│ - Hit rate target: 80-90% (PRD NFR-1.2)                        │
└─────────────────────────────────────────────────────────────────┘
        │ miss
        ▼
┌─────────────────────────────────────────────────────────────────┐
│ L3: Index (Embeddings + Inverted Index)                         │
│ - Vector similarity search (ANN via HNSW)                       │
│ - Keyword search (inverted index)                               │
│ - Latency: ~50-200ms (depends on corpus size)                  │
│ - Target: <500ms on 1M LOC (PRD NFR-1.1)                       │
└─────────────────────────────────────────────────────────────────┘
```

**Cache Invalidation Strategy**:
1. **On git commit**: Mark all cached queries as stale if ANY file changed
2. **Delta reindex**: Recompute only embeddings for changed files
3. **Selective purge**: Drop cache entries referencing changed files
4. **Background refresh**: Recompute stale entries on next query (async)

```python
# Pseudocode: Cache invalidation on git commit

def on_git_commit(commit_hash: str):
    """Invalidate cache entries affected by code changes."""

    # Get changed files in this commit
    changed_files = git_diff(last_commit, commit_hash)

    # Mark embeddings for recomputation
    for file in changed_files:
        mark_stale(file)

    # Purge cache entries that reference changed files
    for cache_entry in query_cache:
        if any(file in cache_entry.results for file in changed_files):
            delete_cache_entry(cache_entry)

    # Trigger delta reindex (background)
    schedule_delta_reindex(changed_files)
```

---

### 8.2 Search Optimization

**Technique 1: Two-Stage Retrieval**
```
Stage 1: Fast Candidate Retrieval (Top 100)
- Vector search with loose threshold (0.3)
- Inverted index search for keywords
- Union of results

Stage 2: Re-Ranking (Top 20)
- Cross-encoder for semantic relevance
- Boost exact keyword matches
- Boost recently modified files
- Boost files in same directory
```

**Technique 2: AST-Aware Chunking**
```python
# Instead of fixed-size chunks (bad for code)
# Chunk by AST boundaries (functions, classes, etc.)

def chunk_code_by_ast(file_path: str) -> List[Chunk]:
    """
    Parse AST and create semantic chunks.

    Chunk types:
    - function: Include full signature + body
    - class: Include class declaration + public methods
    - import: Group all imports together
    - comment: Include docstrings with next function
    """

    tree = parse_ast(file_path)
    chunks = []

    for node in tree:
        if node.type == "function":
            # Include signature + body + docstring
            chunk = Chunk(
                content=extract_code(node),
                type="function",
                name=node.name,
                line_start=node.line_start,
                line_end=node.line_end
            )
            chunks.append(chunk)

    return chunks
```

**Technique 3: Incremental Indexing**
```bash
# Delta indexing (only changed files)
# Target: <1s for typical commit (5-10 files)

LAST_INDEXED=$(cat .ck/.last_commit)
CURRENT_HEAD=$(git rev-parse HEAD)

CHANGED_FILES=$(git diff --name-only "${LAST_INDEXED}" "${CURRENT_HEAD}")

# Parallel embedding generation (4 workers)
echo "${CHANGED_FILES}" | xargs -P 4 -I {} ck --index-file {}

# Update index
ck --merge-index
```

**Performance Benchmarks** (Target):

| Corpus Size | Index Time | Search Latency | Cache Hit Rate |
|-------------|-----------|----------------|----------------|
| 10K LOC | <5s | <50ms | 85% |
| 100K LOC | <30s | <100ms | 82% |
| 1M LOC | <5min | <500ms | 80% |
| 10M LOC | <30min | <2s | 75% |

---

## 9. Deployment Architecture

### 9.1 Installation Workflow

**User Journey**:

```
1. Clone Loa repository
   ↓
2. Run setup: /setup
   ↓
3. Setup checks dependencies:
   ├─ git ✓ (required)
   ├─ jq ✓ (required)
   ├─ yq ✓ (required)
   ├─ ck ○ (optional - install with: cargo install ck-search)
   └─ bd ○ (optional - install from: github.com/steveyegge/beads)
   ↓
4. Validate command namespace (FR-10):
   - Run: .claude/scripts/validate-commands.sh
   - Check for conflicts with Claude Code reserved commands
   - Auto-rename any conflicts (e.g., /config → /mcp-config)
   - Display warnings if renames occurred
   ↓
5. If ck installed:
   - Display: "✓ ck installed: 0.7.2"
   - Trigger background index: ck --index . --quiet &
   - Display: "Note: First search may be slower while index builds"
   ↓
6. If ck NOT installed:
   - Display: "○ ck not installed (optional)"
   - Display: "For enhanced semantic search: cargo install ck-search"
   - Display: "All commands work normally using grep fallback"
   ↓
7. Initialize configuration files (FR-8, FR-9):
   - Create .claude/workflow-chain.yaml (if missing)
   - Initialize drift_detection.watch_paths in .loa.config.yaml
   - Initialize context_filtering defaults in .loa.config.yaml
   ↓
8. Create .loa-setup-complete marker
   ↓
9. Display setup summary:
   "Setup complete with: [ck, beads, full suite]"
   [If command renames occurred, display list of changes]
```

**Installation Script**: `.claude/scripts/install-ck.sh` (referenced in INSTALLATION.md)

```bash
#!/usr/bin/env bash
# .claude/scripts/install-ck.sh

set -euo pipefail

echo "Installing ck semantic search..."

# Check if Rust toolchain installed
if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Rust toolchain required. Install with:"
    echo "   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

# Install ck
echo "Running: cargo install ck-search"
cargo install ck-search

# Verify installation
if command -v ck >/dev/null 2>&1; then
    CK_VERSION=$(ck --version 2>/dev/null || echo "unknown")
    echo "✓ ck installed: ${CK_VERSION}"

    # Record binary fingerprint
    CK_PATH=$(command -v ck)
    CK_FINGERPRINT=$(sha256sum "${CK_PATH}" | awk '{print $1}')

    echo ""
    echo "Binary fingerprint: ${CK_FINGERPRINT}"
    echo "Add to .loa-version.json if running in strict integrity mode"
else
    echo "❌ Installation failed"
    exit 1
fi
```

---

### 9.2 Update & Migration

**Framework Update Flow** (`/update` command):

```
1. User: /update
   ↓
2. Check current version:
   CURRENT=$(jq -r '.version' .loa-version.json)
   LATEST=$(curl -s https://api.github.com/repos/thj/loa/releases/latest | jq -r '.tag_name')
   ↓
3. If CURRENT == LATEST:
   - Display: "Already on latest version (${CURRENT})"
   - Exit
   ↓
4. If update available:
   - Display: "Update available: ${CURRENT} → ${LATEST}"
   - Show changelog
   - Prompt: "Proceed with update? [y/N]"
   ↓
5. Backup .claude/overrides/:
   tar -czf .claude/overrides-backup-$(date +%s).tar.gz .claude/overrides/
   ↓
6. Pull latest System Zone:
   git fetch origin
   git checkout origin/main -- .claude/
   ↓
7. Restore overrides:
   tar -xzf .claude/overrides-backup-*.tar.gz -C .claude/
   ↓
8. Regenerate checksums:
   .claude/scripts/generate-checksums.sh
   ↓
9. Trigger reindex (if ck installed):
   ck --index . --quiet &
   ↓
10. Display: "Update complete: ${CURRENT} → ${LATEST}"
```

**Migration Gates** (for breaking changes):

```yaml
# .loa-version.json
{
  "version": "0.7.0",
  "migrations": [
    {
      "from": "0.6.x",
      "to": "0.7.0",
      "breaking": true,
      "script": ".claude/scripts/migrate-0.6-to-0.7.sh",
      "description": "ck integration requires reindex"
    }
  ]
}
```

```bash
# .claude/scripts/migrate-0.6-to-0.7.sh
#!/usr/bin/env bash

echo "Migrating from v0.6 to v0.7..."

# 1. Add .ck/ to .gitignore
if ! grep -q "^\.ck/$" .gitignore; then
    echo ".ck/" >> .gitignore
fi

# 2. Create trajectory directory
mkdir -p loa-grimoire/a2a/trajectory

# 3. Trigger full reindex (not delta)
if command -v ck >/dev/null 2>&1; then
    echo "Reindexing codebase (this may take a few minutes)..."
    ck --index . --quiet
fi

echo "Migration complete"
```

---

### 9.3 Version Pinning

**Dependency Versions**:

```json
// .loa-version.json
{
  "version": "0.7.0",
  "schema_version": "1.0",
  "dependencies": {
    "ck": ">=0.7.0",
    "jq": ">=1.6",
    "yq": ">=4.0",
    "git": ">=2.0",
    "bash": ">=4.0"
  },
  "optional_dependencies": {
    "bd": "any",
    "ripgrep": ">=13.0"
  },
  "binary_fingerprints": {
    "ck": "abc123..."  // SHA-256 of known good ck binary (optional)
  }
}
```

**Version Check** (in pre-flight):
```bash
# Check ck version meets minimum requirement
CK_VERSION=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
REQUIRED_VERSION=$(jq -r '.dependencies.ck' .loa-version.json | sed 's/>=//')

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$CK_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "⚠️  ck version ${CK_VERSION} < required ${REQUIRED_VERSION}"
    echo "   Upgrade: cargo install ck-search --force"
fi
```

---

## 10. Development Workflow

### 10.1 Testing Strategy

**Test Pyramid**:

```
                         ┌─────────────┐
                         │  E2E Tests  │  (10% - /ride, /implement flows)
                         └─────────────┘
                    ┌───────────────────────┐
                    │ Integration Tests     │  (30% - search + trajectory)
                    └───────────────────────┘
              ┌─────────────────────────────────┐
              │     Unit Tests                  │  (60% - individual functions)
              └─────────────────────────────────┘
```

**Unit Tests** (Bash + BATS):

```bash
# test/unit/test-search-orchestrator.bats

#!/usr/bin/env bats

load '../test_helper'

@test "search-orchestrator: semantic mode with ck installed" {
    # Mock ck availability
    export LOA_SEARCH_MODE="ck"

    # Mock ck output
    function ck() {
        echo '{"file":"/test/src/foo.ts","line":10,"snippet":"function test()","score":0.9}'
    }
    export -f ck

    # Run search
    run bash .claude/scripts/search-orchestrator.sh semantic "test function" "/test/src" 10 0.5

    # Assert
    assert_success
    assert_output --partial '"file":"/test/src/foo.ts"'
}

@test "search-orchestrator: grep fallback when ck missing" {
    # Mock ck unavailable
    export LOA_SEARCH_MODE="grep"

    # Create test file
    mkdir -p /tmp/test-loa/src
    echo "function testFunc() {}" > /tmp/test-loa/src/test.js

    # Run search
    run bash .claude/scripts/search-orchestrator.sh semantic "testFunc" "/tmp/test-loa/src" 10 0.5

    # Assert
    assert_success
    assert_output --partial "test.js"

    # Cleanup
    rm -rf /tmp/test-loa
}

@test "pre-flight: HALT on strict + drift detected" {
    # Create test repo
    mkdir -p /tmp/test-loa/.claude
    echo '{"foo.txt": "abc123"}' > /tmp/test-loa/.claude/checksums.json
    echo "modified content" > /tmp/test-loa/.claude/foo.txt
    echo "integrity_enforcement: strict" > /tmp/test-loa/.loa.config.yaml

    # Run pre-flight
    cd /tmp/test-loa
    run bash .claude/scripts/preflight.sh

    # Assert HALT
    assert_failure
    assert_output --partial "HALTING: integrity_enforcement=strict"

    # Cleanup
    rm -rf /tmp/test-loa
}
```

**Integration Tests** (End-to-End Search + Trajectory):

```python
# test/integration/test_ghost_detection.py

import subprocess
import json
import os

def test_ghost_detection_confirmed():
    """Test Ghost Feature detection with 0 code results."""

    # Setup: Create test repo with PRD but no code
    os.makedirs("test-repo/loa-grimoire", exist_ok=True)
    os.makedirs("test-repo/src", exist_ok=True)

    # PRD mentions OAuth2
    with open("test-repo/loa-grimoire/prd.md", "w") as f:
        f.write("## Authentication\nOAuth2 SSO login required.")

    # Empty src directory (no OAuth2 code)

    # Run ghost detection
    result = subprocess.run(
        ["bash", ".claude/scripts/detect-ghosts.sh", "OAuth2 SSO", "test-repo"],
        capture_output=True,
        text=True
    )

    # Assert: Confirmed Ghost
    assert result.returncode == 0
    assert "confirmed_ghost" in result.stdout

    # Assert: Trajectory logged
    trajectory_file = "test-repo/loa-grimoire/a2a/trajectory/*.jsonl"
    with open(trajectory_file) as f:
        logs = [json.loads(line) for line in f]
        ghost_log = next(l for l in logs if l["phase"] == "ghost_detection")
        assert ghost_log["status"] == "confirmed_ghost"
        assert ghost_log["results1"] == 0
        assert ghost_log["results2"] == 0

    # Cleanup
    subprocess.run(["rm", "-rf", "test-repo"])
```

---

### 10.2 CI Integration

**GitHub Actions Workflow**:

```yaml
# .github/workflows/loa-ci.yml

name: Loa CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq yq shellcheck
          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
          source $HOME/.cargo/env
          cargo install ck-search

      - name: Verify System Zone integrity
        run: |
          bash .claude/scripts/preflight.sh
        env:
          LOA_ENFORCEMENT: strict

      - name: Run unit tests
        run: |
          npm install -g bats
          bats test/unit/*.bats

      - name: Run integration tests
        run: |
          pytest test/integration/

      - name: Lint bash scripts
        run: |
          shellcheck .claude/scripts/*.sh

      - name: Check for secrets
        run: |
          git diff --cached | grep -iE 'api_key|password|secret|token' | grep -vE '(env|example|placeholder)' && exit 1 || exit 0
```

---

## 11. Technical Risks & Mitigation

### 11.1 Risk Register

| Risk ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---------|------|------------|--------|------------|-------|
| **R-1** | ck binary not available | Medium | High | Graceful fallback to grep, clear installation docs | Framework |
| **R-2** | Context window exhaustion | High | High | Tool Result Clearing protocol, token budgets | Agents |
| **R-3** | JSONL parse failures | Medium | High | Failure-aware parsing (drop bad lines, continue) | Agents |
| **R-4** | Integrity check false positives | Low | Medium | Three enforcement levels (strict/warn/disabled) | Framework |
| **R-5** | Search precision degradation (grep fallback) | High | Medium | Document ck benefits, easy installation | Documentation |
| **R-6** | Index corruption | Low | High | Self-healing State Zone, automatic reindex | Framework |
| **R-7** | Trajectory log disk usage | Medium | Low | Compression + retention policy (30d active, 365d archive) | Framework |
| **R-8** | Agent hallucinations (low grounding) | Medium | High | Self-audit checkpoint, grounding ratio ≥0.95 | Agents |
| **R-9** | Fishing expeditions (wasted tokens) | Medium | Medium | Intent-First Search protocol, mandatory expected_outcome | Agents |
| **R-10** | Binary hijacking | Low | Critical | Binary fingerprint verification, explicit PATH | Security |

**Mitigation Details**:

**R-2: Context Window Exhaustion**
- **Detection**: Token budget manager tracks accumulated tokens
- **Prevention**: Hard limits (2K/5K/15K) with mandatory clearing
- **Recovery**: Semantic Decay (Active → Decayed → Archived)

**R-8: Agent Hallucinations**
- **Detection**: Self-audit checkpoint calculates grounding_ratio
- **Prevention**: Mandatory word-for-word citations, [ASSUMPTION] tagging
- **Recovery**: HALT task completion if ratio < 0.95, remediate before finishing

**R-10: Binary Hijacking**
- **Detection**: SHA-256 fingerprint mismatch on pre-flight
- **Prevention**: Explicit PATH in subprocess invocation, no shell=True
- **Recovery**: HALT (strict mode), re-download ck binary

---

### 11.2 Rollback Plan

**Scenario: ck integration breaks existing workflows**

```bash
# Disable ck without uninstalling (emergency rollback)

# 1. Force grep mode globally
echo "export LOA_SEARCH_MODE=grep" >> ~/.bashrc
source ~/.bashrc

# 2. OR: Uninstall ck (clean rollback)
cargo uninstall ck-search

# 3. Verify fallback working
/ride  # Should complete using grep

# 4. Framework still functional (graceful degradation)
# All commands work identically, just lower precision
```

**Scenario: Trajectory logs filling disk**

```bash
# Emergency compaction + purge

# 1. Compress all trajectory logs
find loa-grimoire/a2a/trajectory -name "*.jsonl" -exec gzip -9 {} \;

# 2. Purge archives older than 90 days (instead of 365)
find loa-grimoire/a2a/trajectory -name "*.jsonl.gz" -mtime +90 -delete

# 3. Update retention policy
yq e '.trajectory.retention.delete_after_days = 90' -i .loa.config.yaml
```

---

## 12. Future Considerations (v2.0+)

### 12.1 MCP Migration Roadmap

**Current: Direct CLI (v1.0)**
```
Agent → search-orchestrator.sh → ck binary → JSONL
```

**Future: MCP Server (v2.0)**
```
Agent → MCP Client → MCP Server (ck) → JSONL
```

**Migration Benefits**:
1. **Connection Pooling**: Reuse ck process across multiple searches
2. **Health Checks**: MCP server monitors ck process, auto-restart on crash
3. **Caching**: MCP server implements L1 cache (not possible with CLI)
4. **Standardization**: Claude Desktop native integration

**Migration Path**:
1. Create `.claude/mcp-registry.yaml` (already designed in SDD §5.2)
2. Implement MCP wrapper server: `ck-mcp-server` (Rust or Node.js)
3. Update `search-orchestrator.sh` to detect MCP vs. CLI mode
4. Test parity (MCP results == CLI results)
5. Gradual rollout (opt-in flag: `ck_mode: mcp` in config)

**MCP Server Implementation** (pseudocode):

```rust
// ck-mcp-server (Rust)

use mcp_server::{Server, Tool, ToolResult};

struct CkMcpServer {
    index_path: PathBuf,
    cache: LruCache<QueryHash, Vec<SearchResult>>,
}

impl Server for CkMcpServer {
    fn list_tools(&self) -> Vec<Tool> {
        vec![
            Tool {
                name: "semantic_search",
                description: "Find code by meaning using embeddings",
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "minLength": 3},
                        "path": {"type": "string", "default": "."},
                        "top_k": {"type": "integer", "default": 20},
                        "threshold": {"type": "number", "default": 0.4}
                    },
                    "required": ["query"]
                }),
            },
            // ... hybrid_search, regex_search
        ]
    }

    fn call_tool(&mut self, name: &str, args: Value) -> ToolResult {
        match name {
            "semantic_search" => {
                let query = args["query"].as_str().unwrap();
                let path = args["path"].as_str().unwrap_or(".");
                let top_k = args["top_k"].as_i64().unwrap_or(20);
                let threshold = args["threshold"].as_f64().unwrap_or(0.4);

                // Check L1 cache
                let query_hash = hash_query(query, path, top_k, threshold);
                if let Some(cached) = self.cache.get(&query_hash) {
                    return ToolResult::success(serialize_jsonl(cached));
                }

                // Execute search
                let results = ck::semantic_search(
                    query,
                    &self.index_path.join(path),
                    top_k,
                    threshold
                )?;

                // Update cache
                self.cache.put(query_hash, results.clone());

                ToolResult::success(serialize_jsonl(&results))
            }
            _ => ToolResult::error("Unknown tool")
        }
    }
}
```

---

### 12.2 Multi-Repository Support

**Current: Single Repository (v1.0)**
- `PROJECT_ROOT` = single git repository
- `.ck/` index for one codebase

**Future: Multi-Repo Workspaces (v2.0+)**

```yaml
# .loa.config.yaml (v2.0)
workspace:
  mode: multi-repo
  repositories:
    - name: "frontend"
      path: "/home/user/projects/frontend"
      index: ".ck/"
    - name: "backend"
      path: "/home/user/projects/backend"
      index: ".ck/"
    - name: "shared"
      path: "/home/user/projects/shared-lib"
      index: ".ck/"

# Search across all repos
ck:
  search_scope: all  # all | current | [frontend, backend]
```

**Federated Search**:
```bash
# Search all repositories in workspace
for repo in "${WORKSPACE_REPOS[@]}"; do
    ck --semantic "JWT validation" \
        --path "${repo}/src/" \
        --jsonl
done | jq -s 'flatten | sort_by(.score) | reverse | .[0:20]'
```

**Challenge**: Cross-repo dependency tracking, unified trajectory logs.

---

### 12.3 Real-Time Index Updates (git hooks)

**Current: Manual Trigger (v1.0)**
- Reindex on next search if `.last_commit` outdated

**Future: Automatic Reindex (v2.0+)**

```bash
# .git/hooks/post-commit

#!/usr/bin/env bash
# Trigger incremental index update after every commit

PROJECT_ROOT=$(git rev-parse --show-toplevel)

if command -v ck >/dev/null 2>&1; then
    # Get changed files in this commit
    CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

    # Incremental reindex (background, non-blocking)
    echo "${CHANGED_FILES}" | xargs -P 4 -I {} \
        ck --index-file "${PROJECT_ROOT}/{}" --quiet 2>/dev/null &

    # Update last commit marker
    git rev-parse HEAD > "${PROJECT_ROOT}/.ck/.last_commit"
fi
```

**Benefit**: Zero-latency searches (index always current)
**Cost**: CPU usage on every commit

---

### 12.4 Advanced Grounding Techniques

**Current: Word-for-Word Citations (v1.0)**
- Agents extract exact code snippets
- Manual verification by reviewing-code agent

**Future: Automated Grounding Verification (v2.0+)**

```python
# Automated grounding verification

def verify_citation(claim: str, code_snippet: str, file_path: str, line: int) -> bool:
    """
    Verify that citation supports claim.

    Uses smaller model (Claude Haiku) to check:
    1. Is code_snippet actually in file at line?
    2. Does code_snippet semantically support claim?
    """

    # Check 1: Exact match
    actual_code = read_file_lines(file_path, line, line + 10)
    if code_snippet not in actual_code:
        return False  # Code snippet not found at location

    # Check 2: Semantic support (use Haiku for speed)
    prompt = f"""
    Claim: {claim}
    Code: {code_snippet}

    Does the code support the claim? Answer yes/no with brief reason.
    """

    response = call_haiku(prompt)

    return response.lower().startswith("yes")
```

**Integration**: Run on self-audit checkpoint, HALT if ≥5% citations fail verification.

---

## 13. Appendix

### 13.1 Configuration Reference

**Complete `.loa.config.yaml` with ck settings**:

```yaml
# Loa Framework Configuration
version: "1.0"

# Integrity Enforcement
integrity_enforcement: strict  # strict | warn | disabled

# ck Configuration
ck:
  enabled: true               # Auto-detected (presence of ck binary)
  model: "nomic-v1.5"         # nomic-v1.5 | jina-code-v2
  thresholds:
    semantic: 0.4             # Lower = more results
    hybrid: 0.5               # Balanced semantic + keyword
    negative_grounding: 0.4   # For Ghost Feature detection
  cache:
    enabled: true
    max_size_mb: 100
    eviction: "lru"           # lru | lfu
  index:
    auto_reindex: true        # Trigger on git commit
    delta_threshold: 100      # Full reindex if >100 files changed

# Trajectory Logging
trajectory:
  enabled: true
  retention:
    active_days: 30           # Keep raw JSONL for 30 days
    archive_after_days: 30    # Compress to .jsonl.gz
    delete_after_days: 365    # Purge after 1 year
  compression:
    enabled: true
    format: gzip              # gzip | zstd
    level: 6                  # 1 (fast) to 9 (best compression)

# Token Budgets
token_budgets:
  single_search: 2000         # Max tokens per search
  accumulated: 5000           # Trigger clearing threshold
  file_load: 3000             # Max tokens per file load
  session: 15000              # Stop and synthesize threshold

# Beads Integration (optional)
beads:
  enabled: auto               # auto | true | false (auto = detect bd CLI)
  tracking:
    ghost_features: true      # Track Ghost Features in Beads
    shadow_systems: true      # Track Shadow Systems in Beads
  priority:
    ghost: 2                  # Beads priority for Ghost Features
    shadow_orphaned: 1        # Beads priority for Orphaned Shadows
    shadow_drifted: 2         # Beads priority for Drifted Shadows

# Analytics (THJ only)
analytics:
  enabled: false              # OSS users: always false
  tracking:
    usage: false
    errors: false
  opt_in_sharing: false       # /feedback command
```

---

### 13.2 Glossary

| Term | Definition | Reference |
|------|------------|-----------|
| **ck** | Semantic/hybrid code search CLI tool (seek) | PRD Executive Summary |
| **Ghost Feature** | Documented in PRD/SDD but missing from code (Strategic Liability) | PRD FR-3.2 |
| **Shadow System** | Code exists but undocumented (Technical Debt) | PRD FR-3.3 |
| **Negative Grounding** | Proving absence via TWO diverse queries returning 0 results | PRD FR-3.2 |
| **Tool Result Clearing** | Synthesizing search results to NOTES.md, clearing raw output | PRD FR-4.1 |
| **Trajectory Log** | JSONL audit trail of agent reasoning (intent → execute → cite) | PRD FR-5.1 |
| **Grounding Ratio** | grounded_decisions / total_decisions (target ≥0.95) | PRD NFR-5.2 |
| **Semantic Decay** | Progressive compaction of search results (Active → Decayed → Archived) | PRD FR-4.2 |
| **Pre-Flight Check** | System Zone integrity verification before ck operations | PRD FR-2.1 |
| **Three-Zone Model** | System (.claude/) → State (.ck/) → App (src/) | PRD Phase 0 |
| **Truth Hierarchy** | CODE > ck INDEX > NOTES.md > PRD/SDD (immutable priority) | PRD §2.3 |
| **Beads Pattern** | Optional enhancement: surface → invisible → graceful → zero friction | PRD Phase 0 |
| **MCP** | Model Context Protocol (Anthropic standard for tool servers) | SDD §5.2 |
| **JSONL** | JSON Lines (newline-delimited JSON for streaming) | PRD FR-6.2 |
| **Delta Indexing** | Incremental reindex (only changed files, not full corpus) | PRD NFR-3.1 |
| **EDD** | Evaluation-Driven Development (Google ADK: 3 test scenarios per decision) | PRD FR-5.5 |
| **Attention Budget** | Token limit for agent working memory (prevent context overflow) | PRD FR-4.1 |
| **Fishing Expedition** | Broad search without clear expected_outcome (anti-pattern) | PRD FR-5.1 |

---

### 13.3 References

1. **LOA_CK_INTEGRATION_PROMPT.md**: Complete integration specification (74,246 bytes)
2. **LOA_CK_CLI_PROMPT.md**: Executive summary and core principles (21,204 bytes)
3. **PRD**: `/home/merlin/Documents/thj/code/loa/loa-grimoire/prd.md` (60,362 bytes)
4. **CLAUDE.md**: Framework conventions and protocols
5. **AWS Projen**: Managed scaffolding, synthesis protection patterns
6. **Google ADK**: Trajectory evaluation, EDD standards
7. **Anthropic Agent SDK**: Context engineering, attention budgets

---

### 13.4 Diagrams

**Search Execution Flow (Sequence Diagram)**:

```
Agent              Orchestrator      Pre-Flight      ck/grep         Trajectory
  │                    │                 │              │                │
  │──semantic_search──>│                 │              │                │
  │                    │──verify────────>│              │                │
  │                    │                 │──checksums───┤                │
  │                    │                 │──ck version──┤                │
  │                    │                 │<─✓ OK────────┤                │
  │                    │<─✓ proceed──────│              │                │
  │                    │──log intent────────────────────┼───────────────>│
  │                    │─────execute────────────────────>│                │
  │                    │                 │              │──ANN search───>│
  │                    │<────JSONL results───────────────│                │
  │                    │──parse (drop bad lines)──────────────────────────│
  │                    │──log execute───────────────────┼───────────────>│
  │<───results─────────│                 │              │                │
  │──extract citations─┤                 │              │                │
  │──synthesize NOTES──┤                 │              │                │
  │──log citations────────────────────────────────────────────────────>│
  │──clear raw results─┤                 │              │                │
```

---

## Conclusion

This Software Design Document provides a comprehensive architecture for integrating ck semantic search into the Loa framework as an invisible, optional enhancement, plus three critical workflow improvements from GitHub issues.

**Core Integration Features** (ck semantic search):

1. **Truth Hierarchy**: CODE > ck INDEX > NOTES.md > PRD/SDD
2. **Invisible Enhancement**: Zero user-facing changes
3. **Integrity First**: Pre-flight verification mandatory
4. **Performance Targets**: <500ms search, 80-90% cache hit, ≥0.95 grounding ratio
5. **Graceful Degradation**: Full functionality with grep fallback

**New Workflow Features** (GitHub Issues #9, #10, #11):

1. **Agent Chaining (FR-8)**: Automatic next-step suggestions after phase completion
   - Declarative workflow chain in YAML
   - Conditional routing based on approval/feedback
   - Non-blocking, user can decline
   - Maintains workflow momentum

2. **Context Filtering (FR-9)**: Prevention of search result pollution
   - Signal markers (high/medium/low) for document filtering
   - Configurable watch paths for drift detection
   - Archive zone exclusion
   - Default exclude patterns for session artifacts

3. **Command Namespace Protection (FR-10 - P0 BLOCKER)**: Prevents Claude Code conflicts
   - Reserved command registry
   - Pre-flight validation during setup/update
   - Auto-rename conflicts with -loa suffix
   - Current conflict: /config → /mcp-config

**Key Architectural Decisions**:
- Direct CLI invocation (v1.0) for simplicity, MCP migration (v2.0) for integration
- Archive trajectory logs to compressed storage for full audit trail
- Minimal Beads integration (Ghost/Shadow tracking only)
- Single repository scope (v1.0), multi-repo in future
- Workflow chain as opt-in enhancement (suggestions, not forced)
- Context filtering configurable and backward compatible
- Command namespace validation mandatory (P0)

**Implementation Priority**:
1. **P0 (Immediate)**: Command namespace protection - resolve /config conflict
2. **P0**: Core ck integration (Installation, Pre-Flight, /ride)
3. **P1**: Agent chaining for workflow momentum
4. **P1**: Context filtering for search quality

**Next Steps**:
1. **Immediate**: Rename /config to /mcp-config (FR-10)
2. Review SDD with THJ team
3. Proceed to `/sprint-plan` for task breakdown
4. Begin implementation in Sprint 1 (Installation & Pre-Flight)

**Document Status**: Ready for sprint planning phase.

---

*Generated by: designing-architecture agent*
*Date: 2025-12-26*
*PRD Reference: /home/merlin/Documents/thj/code/loa/loa-grimoire/prd.md*
*Word Count: ~15,000*
*Diagrams: 6 (ASCII)*
*Code Examples: 25+*
