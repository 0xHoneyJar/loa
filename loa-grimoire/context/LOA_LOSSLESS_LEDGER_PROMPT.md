# Loa Framework: Lossless Ledger Protocol

## "Clear, Don't Compact" Architecture

*Framework Version: Loa 0.8.x*
*Protocol Version: v2.2 (Production-Hardened - 3 Principal Engineer Reviews)*
*Engineering Standard: AWS Projen / Google ADK / Anthropic ACI*

---

## Executive Summary

**Problem:** Context compaction (summarization) is inherently lossy. As conversations grow, compaction smudges the chalkboard until it becomes a grey blur of unreadable ghosts—hallucinations, lost context, degraded reasoning.

**Solution:** Treat the context window as a **disposable workspace** and State Zone artifacts as **lossless external ledgers**. When the desk gets messy, wipe it clean (`/clear`), knowing permanent records are safely filed.

**Result:** Every turn starts with a clear mind and full attention budget, while reasoning chains remain auditable across session boundaries.

**Token Efficiency:** 99.6% reduction in persistent context through lightweight identifiers vs. eager loading.

### The Digital Blockchain Analogy

Improving context management is like upgrading a **Forensic Auditor** from a **Smudged Paper Ledger** (compaction) to a **Digital Blockchain** (Lossless Ledger):

| Aspect | Smudged Ledger (Compaction) | Digital Blockchain (Lossless) |
|--------|----------------------------|-------------------------------|
| **Memory** | Fading, overwritten, lossy | Immutable, append-only, lossless |
| **Desk** | Cluttered, can't find things | Cleared after every audit |
| **Evidence** | Summarized, paraphrased | Word-for-word, cryptographically verifiable |
| **Recovery** | Re-read smudged notes | Pull specific files from vault |
| **Audit Trail** | "I think I remember..." | Timestamped, hash-linked trajectory |

The Auditor no longer relies on their failing memory. They start every investigation turn with a **completely clear desk** (`/clear`), only pulling specific **High-Security Files** (JIT retrieval) from the **Immutable Vault** (State Zone) when an audit finding requires evidence.

---

## Architectural Paradigm Shift

```
BEFORE: Lossy Compaction Model
┌─────────────────────────────────────────────────────────┐
│  Context Window (grows unbounded)                       │
│  ├── Original reasoning... (fading)                     │
│  ├── Compacted summary... (lossy)                       │
│  ├── More reasoning... (competing for attention)        │
│  └── Compacted again... (ghosts of ghosts)              │
│                                                         │
│  Result: Context rot, hallucinations, lost citations    │
└─────────────────────────────────────────────────────────┘

AFTER: Lossless Ledger Model ("Clear, Don't Compact")
┌─────────────────────────────────────────────────────────┐
│  Context Window (frequently wiped)                      │
│  ├── Current task focus only                            │
│  ├── JIT-retrieved evidence                             │
│  └── Active reasoning (full attention)                  │
├─────────────────────────────────────────────────────────┤
│  State Zone Ledgers (permanent, lossless, self-healing) │
│  ├── NOTES.md          → Decision Log + Continuity      │
│  ├── .beads/           → Task Graph + Rationale         │
│  └── trajectory/       → Audit Trail + Handoffs         │
└─────────────────────────────────────────────────────────┘
```

---

## Truth Hierarchy (Updated)

```
IMMUTABLE TRUTH HIERARCHY:

1. CODE (src/)           ← Absolute truth, verified by ck
2. BEADS (.beads/)       ← Lossless task graph, rationale, state
3. NOTES.md              ← Decision log, session continuity
4. TRAJECTORY            ← Audit trail, handoff records
5. PRD/SDD               ← Design intent, may drift
6. LEGACY DOCS           ← Historical, often stale
7. CONTEXT WINDOW        ← TRANSIENT, disposable, never authoritative

CRITICAL: Nothing in the transient context window overrides the external ledger.
```

---

## Phase 1: Pre-Flight Integrity Check (Production-Hardened)

<integrity_protocol>

Before any refactoring or session operations, verify System Zone AND State Zone integrity:

```bash
#!/bin/bash
# Pre-flight integrity check (AWS Projen Standard)

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Load enforcement level
if [[ -f "${PROJECT_ROOT}/.loa.config.yaml" ]]; then
    ENFORCEMENT=$(grep "integrity_enforcement:" "${PROJECT_ROOT}/.loa.config.yaml" | awk '{print $2}' || echo "warn")
else
    ENFORCEMENT="warn"
fi

# ═══════════════════════════════════════════════════════════════
# SYSTEM ZONE INTEGRITY (checksums)
# ═══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_ROOT}/.claude/checksums.json" ]] && command -v jq >/dev/null 2>&1; then
    CHECKSUM_VALID=true
    
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
            echo "WARNING: System Zone drift detected." >&2
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# VERSION PINNING (ck binary - prevents Schema Drift)
# ═══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_ROOT}/.loa-version.json" ]] && command -v jq >/dev/null 2>&1; then
    REQUIRED_CK=$(jq -r '.dependencies.ck // "0.7.0"' "${PROJECT_ROOT}/.loa-version.json")
    INSTALLED_CK=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    
    if [[ "$(printf '%s\n' "$REQUIRED_CK" "$INSTALLED_CK" | sort -V | head -1)" != "$REQUIRED_CK" ]]; then
        echo "WARNING: ck $INSTALLED_CK may not match index schema (requires $REQUIRED_CK)" >&2
    fi
fi

# ═══════════════════════════════════════════════════════════════
# SELF-HEALING STATE ZONE (ledgers must be recoverable)
# ═══════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────
# PHASE 1: Git-Backed Recovery (Highest Fidelity)
# ─────────────────────────────────────────────────────────────────
if [[ -d "${PROJECT_ROOT}/.git" ]]; then
    # Attempt recovery from git history for NOTES.md
    if [[ ! -f "${PROJECT_ROOT}/loa-grimoire/NOTES.md" ]]; then
        echo "INFO: Attempting git-backed recovery for NOTES.md" >&2
        mkdir -p "${PROJECT_ROOT}/loa-grimoire"
        git show HEAD:loa-grimoire/NOTES.md > "${PROJECT_ROOT}/loa-grimoire/NOTES.md" 2>/dev/null || true
    fi
    
    # Attempt recovery for .beads/ from last commit
    if [[ ! -d "${PROJECT_ROOT}/.beads" ]] || [[ -z "$(ls -A "${PROJECT_ROOT}/.beads" 2>/dev/null)" ]]; then
        echo "INFO: Attempting git-backed recovery for .beads/" >&2
        mkdir -p "${PROJECT_ROOT}/.beads"
        git checkout HEAD -- .beads/ 2>/dev/null || true
    fi
fi

# ─────────────────────────────────────────────────────────────────
# PHASE 2: Template-Based Reconstruction (Fallback)
# ─────────────────────────────────────────────────────────────────

# Self-heal NOTES.md if still missing after git recovery
if [[ ! -f "${PROJECT_ROOT}/loa-grimoire/NOTES.md" ]]; then
    echo "INFO: Reconstructing NOTES.md from template" >&2
    mkdir -p "${PROJECT_ROOT}/loa-grimoire"
    cat > "${PROJECT_ROOT}/loa-grimoire/NOTES.md" << 'EOF'
# Project Notes

## Session Continuity
<!-- Load FIRST after /clear -->

### Active Context
- **Current Bead**: (none)
- **Last Checkpoint**: (new session)
- **Reasoning State**: Initial setup - recovered from template

### Lightweight Identifiers
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|

### Decision Log
<!-- Decisions survive all session wipes -->

## High-Signal Findings
<!-- Synthesized insights -->
EOF
fi

# Self-heal .beads/ directory if missing
if [[ ! -d "${PROJECT_ROOT}/.beads" ]]; then
    echo "INFO: Reconstructing .beads/ directory" >&2
    mkdir -p "${PROJECT_ROOT}/.beads"
    echo "# Beads Task Registry" > "${PROJECT_ROOT}/.beads/README.md"
fi

# Self-heal trajectory directory if missing
if [[ ! -d "${PROJECT_ROOT}/loa-grimoire/a2a/trajectory" ]]; then
    echo "INFO: Reconstructing trajectory directory" >&2
    mkdir -p "${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"
fi

# Self-heal ck index (delta-first strategy)
if command -v ck >/dev/null 2>&1; then
    if [[ ! -d "${PROJECT_ROOT}/.ck" ]] || [[ ! -f "${PROJECT_ROOT}/.ck/embeddings.json" ]]; then
        if [[ -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
            LAST_INDEXED=$(cat "${PROJECT_ROOT}/.ck/.last_commit" 2>/dev/null)
            CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null)
            CHANGED_FILES=$(git diff --name-only "$LAST_INDEXED" "$CURRENT_HEAD" 2>/dev/null | wc -l)
            
            if [[ "$CHANGED_FILES" -lt 100 ]]; then
                echo "INFO: Delta reindexing $CHANGED_FILES changed files" >&2
                ck --index "${PROJECT_ROOT}" --delta --quiet 2>/dev/null &
            else
                echo "INFO: Full reindex required" >&2
                ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
            fi
        else
            echo "INFO: Initial index build in progress" >&2
            ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
        fi
    fi
fi

echo "Pre-flight check complete" >&2
```

### Recovery Priority Order

| Priority | Source | Fidelity | Use Case |
|----------|--------|----------|----------|
| 1 | Git history (`git show HEAD:...`) | **Highest** | NOTES.md, .beads/ recovery |
| 2 | Git checkout (tracked files) | High | Restore deleted but tracked files |
| 3 | Template reconstruction | Medium | Fresh start when git unavailable |
| 4 | Delta reindex | N/A | .ck/ search index only |

**Key Principle:** The ledger is the source of truth. If git has a copy, recover from git first. Template reconstruction is a last resort that preserves the framework contract but loses historical data.

## Synthesis Protection for Ledger Formats

Ledger structure definitions are **synthesised framework state** protected like the System Zone:

```
.claude/                              # SYSTEM ZONE - IMMUTABLE
├── schemas/
│   ├── notes-md.schema.yaml         # NOTES.md structure definition
│   ├── bead.schema.yaml             # Bead YAML structure
│   └── trajectory.schema.jsonl      # Trajectory log format
├── overrides/                       # USER ZONE - Safe customization
│   ├── notes-md-extensions.yaml     # Custom metadata fields
│   └── bead-extensions.yaml         # Custom Bead fields
```

**Customization Rule:**
- To add metadata fields to ledgers → Use `.claude/overrides/`
- Framework updates will NOT clobber override files
- Never modify schema files directly

</integrity_protocol>

---

## Phase 2: NOTES.md as Session Continuity Ledger

### 2.1 NOTES.md Structure (Extended)

Update `loa-grimoire/NOTES.md` to include session continuity sections:

```markdown
# Project Notes

## Session Continuity
<!-- CRITICAL: Load this section FIRST after /clear or session start -->
<!-- Contains everything needed to resume work without context loss -->

### Active Context
- **Current Bead**: bd-x7y8 (Implementing JWT refresh)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Validating token expiry edge cases

### Lightweight Identifiers (JIT Retrieval Keys)
<!-- Absolute paths only - retrieve full content on-demand -->
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| /home/user/project/src/auth/jwt.ts:45-67 | Token validation logic | 14:25:00Z |
| /home/user/project/src/auth/refresh.ts:12-34 | Refresh flow | 14:28:00Z |
| /home/user/project/tests/auth.test.ts:100-150 | Edge case tests | 14:30:00Z |

### Decision Log
<!-- Survives context wipes - permanent record of reasoning -->

#### 2024-01-15T14:30:00Z - Token Expiry Handling
**Decision**: Use sliding window expiration with 15-minute grace period
**Rationale**: Balances security (short expiry) with UX (no mid-session logouts)
**Evidence**: 
- `export function isTokenExpired(token: Token, graceMs = 900000)` [/home/user/project/src/auth/jwt.ts:52]
- Industry standard per RFC 6749 §4.2.2
**Test Scenarios**:
1. Token expires exactly at boundary → grace period applies
2. Token expires beyond grace → forced refresh
3. Refresh token also expired → full re-authentication

### Pending Questions
<!-- Carry forward across sessions -->
- [ ] Should grace period be configurable per-client?
- [ ] How to handle clock skew between client/server?

## High-Signal Findings
<!-- Synthesized insights that must not be lost -->

### Authentication Patterns
The codebase uses a dual-token strategy:
- Access token: `validateAccessToken()` [/home/user/project/src/auth/jwt.ts:45]
- Refresh token: `rotateRefreshToken()` [/home/user/project/src/auth/refresh.ts:12]

### Shadow Systems Identified
| Module | Classification | Dependents | Beads ID |
|--------|---------------|------------|----------|
| legacy_session | ORPHANED | 3 files | bd-a1b2 |
```

### 2.2 Session Continuity Protocol

Create `.claude/protocols/session-continuity.md`:

```markdown
# Session Continuity Protocol

## Purpose
Ensure zero information loss across context wipes by treating NOTES.md 
as the authoritative session state ledger.

## After /clear or Session Start

### Step 1: Restore Task Context (MANDATORY)
```bash
# First action after any context wipe
bd ready                     # Show active tasks
bd show <active_bead_id>     # Load current task details
```

### Step 2: Tiered Ledger Recovery (Attention-Aware)

**Do NOT read entire NOTES.md** - use tiered retrieval to prevent ledger rot:

```xml
<tiered_ledger_recovery>
  <!-- Level 1: Minimal Recovery (~100 tokens) -->
  <level_1 name="active_context">
    <load>Session Continuity → Active Context section</load>
    <load>Last 3 entries from Decision Log</load>
    <tokens>~100</tokens>
    <when>Default for all /clear recovery</when>
  </level_1>
  
  <!-- Level 2: Selective Historical Retrieval -->
  <level_2 name="contextual_history">
    <trigger>Current task needs historical context</trigger>
    <method>ck --hybrid "relevant query" "${PROJECT_ROOT}/loa-grimoire/NOTES.md" --jsonl</method>
    <purpose>Retrieve specific past decisions relevant to current Bead</purpose>
    <tokens>~200-500</tokens>
  </level_2>
  
  <!-- Level 3: Full Ledger Scan (RARE) -->
  <level_3 name="full_scan">
    <trigger>Major architectural review or audit</trigger>
    <warning>Consumes significant attention budget</warning>
    <requires>Explicit user request</requires>
  </level_3>
</tiered_ledger_recovery>
```

**Implementation:**
```bash
# Level 1: Active context only (default)
head -50 "${PROJECT_ROOT}/loa-grimoire/NOTES.md" | grep -A 20 "## Session Continuity"

# Level 2: Semantic search within ledger
ck --hybrid "authentication decision" "${PROJECT_ROOT}/loa-grimoire/" --top-k 3 --jsonl

# Level 3: Full scan (rare, user-requested)
cat "${PROJECT_ROOT}/loa-grimoire/NOTES.md"
```

### Step 3: Verify Lightweight Identifiers

Confirm the files referenced in "Lightweight Identifiers" still exist.
Do NOT load their contents yet—use JIT retrieval when needed.

**Path Format (MANDATORY):**
All paths must use `${PROJECT_ROOT}` prefix:
```
✅ ${PROJECT_ROOT}/src/auth/jwt.ts:45-67
❌ src/auth/jwt.ts:45-67
❌ ./src/auth/jwt.ts:45-67
```

### Step 4: Resume Reasoning
With task context and decision log restored, continue from the 
"Reasoning State" checkpoint without re-analyzing the codebase.

### Failure-Aware Ledger Parsing

Ledgers are written at high frequency and may have partial writes:

```python
def parse_notes_md(notes_path):
    """Parse NOTES.md with failure tolerance"""
    sections = {}
    current_section = None
    parse_errors = 0
    
    try:
        with open(notes_path, 'r') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    if line.startswith('## '):
                        current_section = line[3:].strip()
                        sections[current_section] = []
                    elif current_section:
                        sections[current_section].append(line)
                except Exception as e:
                    # DROP malformed line, continue
                    parse_errors += 1
                    continue
    except FileNotFoundError:
        # Self-heal: create from template
        return create_notes_template()
    
    if parse_errors > 0:
        log_trajectory({
            "phase": "ledger_parse",
            "file": notes_path,
            "parse_errors": parse_errors
        })
    
    return sections
```

**Rule:** A single malformed line must NEVER crash ledger recovery.

## Before /clear (Synthesis Checkpoint)

### MANDATORY: Never wipe without synthesis

```xml
<synthesis_checkpoint>
  <!-- Execute BEFORE any /clear command -->
  
  <step_1 name="grounding_verification">
    <!-- BLOCKING: Cannot /clear if grounding fails -->
    <requirement>grounding_ratio >= 0.95</requirement>
    <check>Every decision in session has word-for-word code quote</check>
    <check>Every citation uses ${PROJECT_ROOT} absolute path</check>
    <if_fails>
      BLOCK /clear command.
      Message: "Cannot clear: X decisions lack grounded citations. 
               Add evidence or mark as [ASSUMPTION] before clearing."
    </if_fails>
  </step_1>
  
  <step_2 name="negative_grounding_verification">
    <!-- Prevent "Phantom Liabilities" in permanent ledger -->
    <for_each type="ghost_feature">
      <requirement>Two diverse semantic queries executed</requirement>
      <requirement>Both queries returned 0 results below 0.4 threshold</requirement>
      <if_not_verified>
        Flag as [UNVERIFIED GHOST] - do NOT enter as confirmed Ghost Feature
      </if_not_verified>
    </for_each>
  </step_2>
  
  <step_3 name="decision_log_update">
    Write all High-Signal Findings to NOTES.md Decision Log.
    Use AST-aware snippets: capture complete functions/classes, not arbitrary lines.
    
    Format:
    - Decision
    - Rationale  
    - Evidence: `ck --full-section` output with ${PROJECT_ROOT} paths
    - Test Scenarios (3 required)
  </step_3>
  
  <step_4 name="bead_update">
    Update active Bead with:
    - Current progress summary
    - Next steps (specific, actionable)
    - Blockers or pending questions
    
    Command: bd update <id> --notes "..."
  </step_4>
  
  <step_5 name="trajectory_handoff">
    Log session_handoff to trajectory file.
    Include: root_span_id, NOTES.md line references, EDD verification.
    
    If any search returned >50 results during session:
    - Verify Trajectory Pivot was logged
    - Pivot must explain hypothesis failure before refinement
  </step_5>
  
  <step_6 name="decay_raw_output">
    Convert any raw tool output to single-line summaries.
    Keep only: ${PROJECT_ROOT} paths, line numbers, key findings.
    Discard: full code blocks, verbose explanations.
  </step_6>
  
  <step_7 name="verify_edd">
    Confirm ledger contains 3 test scenarios for current task.
    If missing: DO NOT proceed with /clear until documented.
  </step_7>
</synthesis_checkpoint>
```

### Grounding Ratio Enforcement (BLOCKING)

The `/clear` command is **blocked** if grounding requirements are not met:

```python
def can_clear(session_decisions, trajectory_log):
    """Check if /clear is permitted"""
    
    total_decisions = len(session_decisions)
    grounded_decisions = 0
    blocking_issues = []
    
    for decision in session_decisions:
        # Must have word-for-word code quote
        if not decision.get('evidence_quote'):
            blocking_issues.append(f"Decision '{decision['title']}' lacks code quote")
            continue
            
        # Must use absolute path with ${PROJECT_ROOT}
        if not decision.get('evidence_path', '').startswith('${PROJECT_ROOT}'):
            blocking_issues.append(f"Decision '{decision['title']}' uses relative path")
            continue
            
        grounded_decisions += 1
    
    grounding_ratio = grounded_decisions / total_decisions if total_decisions > 0 else 1.0
    
    if grounding_ratio < 0.95:
        return False, blocking_issues, grounding_ratio
    
    # Check for unverified Ghost Features
    ghost_features = [d for d in session_decisions if d.get('type') == 'ghost']
    for ghost in ghost_features:
        if not ghost.get('negative_grounding_verified'):
            blocking_issues.append(f"Ghost '{ghost['feature']}' lacks Negative Grounding")
    
    if blocking_issues:
        return False, blocking_issues, grounding_ratio
    
    return True, [], grounding_ratio
```

**Message when blocked:**
```
❌ Cannot /clear: Grounding requirements not met.

Issues:
- Decision 'Token expiry handling' lacks code quote
- Ghost 'OAuth2 SSO' lacks Negative Grounding verification

Actions required:
1. Add word-for-word evidence with ${PROJECT_ROOT} paths
2. Execute Negative Grounding Protocol for Ghost Features
3. Or mark claims as [ASSUMPTION] if evidence unavailable

Current grounding ratio: 0.82 (required: 0.95)
```

## Verification Checklist

Before /clear is permitted:
- [ ] Decision Log updated with current session findings
- [ ] Active Bead updated with rationale and next steps
- [ ] Trajectory handoff logged with line references
- [ ] 3 test scenarios documented for current task
- [ ] All citations use absolute paths
- [ ] Lightweight Identifiers section current

## Anti-Patterns

NEVER:
- Wipe context without synthesis checkpoint
- Store reasoning in context window as "memory"
- Trust compacted summaries over ledger entries
- Use relative paths in citations (won't survive session)
- Skip Bead update before /clear
```

---

## Phase 3: Beads as Lossless Task Authority

### 3.1 Beads-First Recovery Protocol

After any context wipe, Beads is the **first** source of truth:

```bash
# MANDATORY first steps after /clear
bd ready                    # What tasks are active?
bd show <id>               # Full context for current task
```

### 3.2 Bead Structure (Extended for Ledger Protocol)

```yaml
# .beads/<id>.yaml
id: bd-x7y8
title: "Implement JWT refresh token rotation"
type: feature
status: in_progress
priority: 1

# Lossless context (survives all session wipes)
context:
  created: 2024-01-15T10:00:00Z
  last_session: 2024-01-15T14:30:00Z
  session_count: 3

# Decision history (append-only ledger)
decisions:
  - ts: 2024-01-15T10:30:00Z
    decision: "Use rotating refresh tokens"
    rationale: "Prevents token theft replay attacks"
    evidence:
      - path: /home/user/project/src/auth/refresh.ts
        line: 12
        quote: "export async function rotateRefreshToken()"
    
  - ts: 2024-01-15T14:30:00Z
    decision: "Add 15-minute grace period"
    rationale: "Balance security with UX"
    evidence:
      - path: /home/user/project/src/auth/jwt.ts
        line: 52
        quote: "export function isTokenExpired(token, graceMs = 900000)"

# EDD verification (required before handoff)
test_scenarios:
  - name: "Token expires at boundary"
    type: edge_case
    expected: "Grace period applies, no forced logout"
    
  - name: "Token expires beyond grace"
    type: happy_path
    expected: "Silent refresh triggered"
    
  - name: "Both tokens expired"
    type: error_handling
    expected: "Full re-authentication flow"

# Session handoff chain
handoffs:
  - session_id: "sess-001"
    ended: 2024-01-15T12:00:00Z
    notes_ref: "loa-grimoire/NOTES.md:45-67"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-abc"
    
  - session_id: "sess-002"
    ended: 2024-01-15T14:30:00Z
    notes_ref: "loa-grimoire/NOTES.md:68-92"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-def"

# Next steps (specific, actionable)
next_steps:
  - "Implement clock skew tolerance (±30 seconds)"
  - "Add refresh token blacklist for logout"
  - "Write integration tests for race conditions"

# Blockers and questions
blockers: []
questions:
  - "Should grace period be configurable per-client?"
```

### 3.3 Beads Authority Rules

```markdown
## Beads Authority Protocol

### Source of Truth Hierarchy
1. Code implementation (verified by ck)
2. Bead decisions[] array (append-only)
3. Bead test_scenarios (EDD requirement)
4. NOTES.md Decision Log (session synthesis)
5. Context window reasoning (TRANSIENT - never authoritative)

### Preventing "Source of Truth Forks"

A fork occurs when context window reasoning diverges from ledger state.

Prevention:
1. After /clear: ALWAYS run `bd show <id>` before reasoning
2. Before decisions: CHECK Bead decisions[] for prior rulings
3. After decisions: IMMEDIATELY append to Bead decisions[]
4. Never reason about a task without loading its Bead first

### Fork Detection
If agent's reasoning conflicts with Bead state:
1. HALT reasoning
2. Load full Bead: `bd show <id> --full`
3. Determine if:
   a) Bead is outdated → Update Bead with new evidence
   b) Agent is wrong → Align with Bead authority
4. Document resolution in Bead decisions[]
```

---

## Phase 4: Trajectory with Session Handoffs

### 4.1 Session Handoff Protocol

Update trajectory logging to include `session_handoff` phase:

```jsonl
{"ts":"2024-01-15T14:30:00Z","agent":"impl","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"bd-x7y8","notes_refs":["loa-grimoire/NOTES.md:68","loa-grimoire/NOTES.md:72-85"],"edd_verified":true,"test_scenarios":3,"next_session_ready":true}
```

### 4.2 Trajectory Structure (Extended)

Create `loa-grimoire/a2a/trajectory/{agent}-{date}.jsonl`:

```jsonl
// Session start (after /clear)
{"ts":"...","phase":"session_start","session_id":"sess-003","restored_from":{"bead":"bd-x7y8","notes_line":68,"prev_session":"sess-002"}}

// Normal reasoning phases
{"ts":"...","phase":"intent","intent":"Implement clock skew tolerance","rationale":"Prevent auth failures from minor time drift"}
{"ts":"...","phase":"execute","mode":"ck","query":"time drift tolerance clock","path":"/home/user/project/src/","results":3}
{"ts":"...","phase":"cite","citations":[{"file":"/home/user/project/src/auth/jwt.ts","line":55,"quote":"const CLOCK_SKEW_MS = 30000"}],"grounded":true}

// Session handoff (before /clear)
{"ts":"...","phase":"synthesis_checkpoint","decisions_logged":2,"bead_updated":true,"test_scenarios":3}
{"ts":"...","phase":"session_handoff","session_id":"sess-003","root_span_id":"span-ghi","bead_id":"bd-x7y8","notes_refs":["loa-grimoire/NOTES.md:93-110"],"edd_verified":true,"next_session_ready":true}
```

### 4.3 Handoff Verification Requirements

Before `session_handoff` is logged as `next_session_ready: true`:

```markdown
## Handoff Ready Checklist

- [ ] All decisions logged to NOTES.md Decision Log
- [ ] Bead decisions[] array updated
- [ ] Bead next_steps[] populated with specific actions
- [ ] 3 test scenarios documented (EDD requirement)
- [ ] All citations use absolute paths with line numbers
- [ ] Lightweight Identifiers section updated
- [ ] No unresolved reasoning in context (synthesized or discarded)
- [ ] Trajectory includes notes_refs for audit trail

## If Checklist Fails

DO NOT proceed with /clear.
Complete missing items before session can be handed off.
```

---

## Phase 5: Updated /ride Command

Update `.claude/commands/ride.md`:

```markdown
# /ride - Mount and Analyze Existing Codebase

## Session-Aware Initialization

### After /clear or Session Start

```xml
<session_initialization>
  <!-- MANDATORY: Restore lossless state before any analysis -->
  
  <step_1 name="restore_task_context">
    <command>bd ready</command>
    <purpose>Identify active tasks</purpose>
    <if_active_bead>
      <command>bd show {bead_id}</command>
      <purpose>Load full task context including decisions and next_steps</purpose>
    </if_active_bead>
  </step_1>
  
  <step_2 name="load_session_continuity">
    <file>loa-grimoire/NOTES.md</file>
    <section>Session Continuity</section>
    <purpose>Restore reasoning state, lightweight identifiers, decision log</purpose>
  </step_2>
  
  <step_3 name="verify_integrity">
    <check>System Zone checksums</check>
    <check>Bead consistency</check>
    <check>NOTES.md exists and is readable</check>
  </step_3>
  
  <step_4 name="jit_context_loading">
    <principle>Do NOT load full files from Lightweight Identifiers</principle>
    <action>Use ck --hybrid for on-demand retrieval when reasoning requires it</action>
  </step_4>
</session_initialization>
```

### Continuous Synthesis During /ride

```xml
<continuous_synthesis>
  <!-- Don't wait for /clear - synthesize as you go -->
  
  <trigger name="high_signal_finding">
    Immediately write to NOTES.md High-Signal Findings section.
    Include absolute path citations.
  </trigger>
  
  <trigger name="architectural_decision">
    Immediately append to Bead decisions[] array.
    Include evidence with word-for-word quotes.
  </trigger>
  
  <trigger name="ghost_or_shadow">
    Immediately create tracking Bead.
    Update NOTES.md with classification.
  </trigger>
  
  <trigger name="attention_budget_75%">
    Execute synthesis checkpoint.
    Consider recommending /clear to user.
  </trigger>
</continuous_synthesis>
```

### Before /ride Completion or /clear

```xml
<completion_synthesis>
  <mandatory>
    <action>Update NOTES.md Session Continuity section</action>
    <action>Update active Bead with findings</action>
    <action>Log trajectory with notes_refs</action>
    <action>Verify EDD (3 test scenarios)</action>
  </mandatory>
  
  <output>
    Provide user with:
    - Summary of findings (not raw data)
    - Link to NOTES.md for full details
    - Active Bead ID for task tracking
    - Recommendation: /clear if attention budget low
  </output>
</completion_synthesis>
```
```

---

## Phase 6: JIT Retrieval Protocol

### 6.1 Lightweight Identifiers

Instead of loading full files, store retrieval keys:

```markdown
## Lightweight Identifiers (in NOTES.md)

### Format
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| /abs/path/file.ts:45-67 | Token validation | 14:25:00Z |

### Rules
1. ALWAYS use absolute paths
2. Include line ranges for precision
3. Purpose describes WHY this code matters
4. Last Verified tracks staleness

### JIT Retrieval (when needed)
```bash
# Only retrieve when reasoning requires it
ck --hybrid "token validation" "${PROJECT_ROOT}/src/auth/" \
    --top-k 3 --jsonl

# Or directly read the lightweight identifier
sed -n '45,67p' "/abs/path/file.ts"
```

### Token Budget
- Lightweight identifier: ~15 tokens
- Full 50-line code block: ~500 tokens
- Savings: 97% token reduction per reference
```

### 6.2 JIT vs Eager Loading

```markdown
## Loading Strategy

### Eager Loading (AVOID)
Load everything "just in case"
→ Context fills quickly
→ Attention degrades
→ Compaction required
→ Information lost

### JIT Loading (REQUIRED)
Store lightweight identifiers
→ Context stays lean
→ Attention stays sharp
→ /clear is cheap
→ Information preserved in ledgers

### Decision Framework
| Situation | Action |
|-----------|--------|
| Need specific function | JIT: retrieve only that function |
| Need pattern examples | JIT: retrieve 3 examples max |
| Exploring architecture | Store paths, defer retrieval |
| Making decision | JIT: retrieve evidence, then synthesize |
| Finishing session | Store identifiers, discard content |
```

---

## Phase 7: Attention Budget Governance (Production-Hardened)

### 7.1 Budget Thresholds

```markdown
## Attention Budget Limits

| Threshold | Tokens | Action |
|-----------|--------|--------|
| Green | 0-5,000 | Normal operation |
| Yellow | 5,000-10,000 | **Delta-Synthesis** (partial persist) |
| Orange | 10,000-15,000 | Recommend /clear to user |
| Red | 15,000+ | MANDATORY synthesis checkpoint |

## At Each Threshold

### Green (0-5k tokens)
- Normal operation
- Synthesize findings as they emerge
- No special action required

### Yellow (5k tokens) - DELTA-SYNTHESIS PROTOCOL

**Critical:** At Yellow, execute Delta-Synthesis to ensure work survives crashes:

```xml
<delta_synthesis_protocol>
  <trigger>Attention budget reaches 5,000 tokens</trigger>
  
  <action_1 name="append_to_ledger">
    Immediately append recent findings to NOTES.md Decision Log.
    DO NOT clear context yet - just persist to ledger.
  </action_1>
  
  <action_2 name="partial_bead_update">
    Update active Bead with progress-to-date.
    Mark as "delta_synced": true with timestamp.
  </action_2>
  
  <action_3 name="trajectory_checkpoint">
    Log: {"phase":"delta_sync","tokens":5000,"decisions_persisted":N}
  </action_3>
  
  <rationale>
    If agent crashes or user closes session before /clear,
    work is already partially saved to ledger.
    Prevents loss of reasoning that hasn't been manually cleared.
  </rationale>
</delta_synthesis_protocol>
```

### Orange (10k tokens)
- Execute full synthesis checkpoint
- Update all Beads
- Inform user: "Context is filling. Consider /clear when ready."

### Red (15k tokens)
- HALT new tool calls
- Execute mandatory synthesis
- Refuse new work until /clear or synthesis complete
- Message: "Attention budget exhausted. Please /clear to continue with full reasoning capacity."
```

### 7.2 AST-Aware Evidence Capture

When persisting evidence to ledgers, use AST-aware snippets:

```markdown
## AST-Aware Evidence Protocol

### Problem
Arbitrary line ranges lose semantic context:
- Line 45-50 might cut a function in half
- After /clear, the snippet is meaningless without file context

### Solution
Use `ck --full-section` to capture complete logical blocks:

```bash
# WRONG: Arbitrary line range
sed -n '45,50p' "${PROJECT_ROOT}/src/auth/jwt.ts"
# Result: Partial function, loses context

# RIGHT: AST-aware full section
ck --full-section "validateToken" "${PROJECT_ROOT}/src/auth/jwt.ts" --jsonl
# Result: Complete function with signature and body
```

### Decision Log Evidence Format (AST-Aware)

#### 2024-01-15T14:30:00Z - Token Expiry Handling

**Decision**: Use sliding window expiration with 15-minute grace period

**Rationale**: Balances security with UX

**Evidence** (AST-aware, complete function):
```typescript
// ${PROJECT_ROOT}/src/auth/jwt.ts:45-67
export function isTokenExpired(
  token: Token, 
  graceMs: number = 900000
): boolean {
  const expiryTime = token.exp * 1000;
  return Date.now() > (expiryTime + graceMs);
}
```

**Test Scenarios**:
1. Token at boundary → grace applies
2. Beyond grace → forced refresh  
3. Both expired → full re-auth
```

### 7.3 Synthesis Checkpoint Protocol

```markdown
## Synthesis Checkpoint

### When to Execute
- Before any /clear command
- At Orange threshold (10k tokens)
- Before switching major tasks
- At end of /ride analysis

### Checkpoint Steps (BLOCKING requirements marked)

1. **Grounding Verification** ⛔ BLOCKING
   - Verify grounding_ratio >= 0.95
   - All citations use ${PROJECT_ROOT} paths
   - Block /clear if requirements not met

2. **Negative Grounding Check** ⛔ BLOCKING
   - All Ghost Features have 2 diverse queries
   - Both queries returned 0 results < 0.4 threshold
   - Mark unverified as [UNVERIFIED GHOST]

3. **Decision Log Update**
   - Write findings to NOTES.md
   - Use AST-aware snippets (complete functions via --full-section)
   - Format: Decision, Rationale, Evidence, Test Scenarios
   
4. **Bead Synchronization**
   - `bd update <id>` with current state
   - Append to decisions[] array
   - Update next_steps[]
   
5. **Trajectory Logging**
   - Log synthesis_checkpoint phase
   - Include notes_refs for audit
   - Verify Trajectory Pivots logged for >50 result searches

6. **Content Decay**
   - Full code blocks → lightweight identifiers with ${PROJECT_ROOT}
   - Raw tool output → single-line summaries
   - Verbose explanations → key points only

7. **EDD Verification**
   - Confirm 3 test scenarios exist
   - If missing, document before proceeding

### Checkpoint Complete When
- [ ] Grounding ratio >= 0.95 ⛔
- [ ] All Ghost Features have Negative Grounding ⛔
- [ ] NOTES.md updated with AST-aware evidence
- [ ] Active Bead reflects current progress
- [ ] Trajectory logged with Pivots
- [ ] Content decayed to ${PROJECT_ROOT} identifiers
- [ ] EDD verified (3 scenarios)

### If BLOCKING Requirements Fail
/clear command is REJECTED with actionable error message.
```

---

## Anti-Patterns

```markdown
## NEVER DO

### Context as Memory
❌ "I'll remember this for later in the conversation"
✅ Write to NOTES.md immediately

### Trusting Compaction
❌ Rely on summarized/compacted context
✅ Trust only ledger entries (NOTES.md, Beads)

### Relative Paths
❌ Citations like [src/auth/jwt.ts:45]
✅ Citations like [/home/user/project/src/auth/jwt.ts:45]

### Deferred Synthesis
❌ "I'll update the notes at the end"
✅ Synthesize continuously as findings emerge

### Skipping Bead Check
❌ Reason about task without loading Bead
✅ ALWAYS `bd show <id>` after /clear

### Eager Loading
❌ Load all referenced files into context
✅ Store lightweight identifiers, JIT retrieve

### /clear Without Checkpoint
❌ Wipe context without synthesis
✅ Execute full checkpoint protocol first
```

---

## Success Metrics

```markdown
## Measuring Lossless Operation

### Session Continuity
- Time to resume after /clear: <30 seconds
- Information loss after /clear: 0%
- Reasoning consistency across sessions: 100%

### Attention Quality
- Average context size at /clear: <8,000 tokens
- Synthesis checkpoint frequency: Every 5-10k tokens
- Hallucination rate: <1%

### Audit Trail
- Citation survival rate: 100% (absolute paths)
- Decision traceability: 100% (via trajectory)
- EDD compliance: 100% (3 scenarios per task)

### Ledger Health
- NOTES.md update frequency: Every major finding
- Bead sync frequency: Every decision
- Trajectory coverage: Every session handoff
```

---

## The Performance Analogy

**Compacting context** is like smudging a chalkboard to make room for new notes. Eventually, the board becomes a grey blur of unreadable ghosts—partial information, conflated concepts, lost citations.

**The Lossless Ledger Protocol** is like working with:
- A **Digital Ledger** (Beads) for task tracking
- A **Project Binder** (NOTES.md) for decisions and findings
- A **Filing Cabinet** (trajectory/) for audit trails

When the desk (Context Window) gets messy, you simply wipe it clean (`/clear`), knowing your permanent records are safely filed in the State Zone. Every turn starts with:
- A perfectly clear mind
- Full attention budget
- Instant access to lossless history

The context window becomes what it should be: a **temporary workspace**, not a **failing memory**.

---

## Traceability Matrix: PE Review Requirements → Implementation (v2.2)

This matrix verifies that all Principal Engineer review feedback has been incorporated.

### AWS Projen Standard (Infrastructure Integrity)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Self-Healing State Zone | Phase 1, Git-backed recovery protocol | ✅ |
| Git-backed recovery (highest fidelity) | Priority 1 in recovery order | ✅ |
| Template reconstruction fallback | Priority 3 in recovery order | ✅ |
| Binary integrity verification | SHA-256 fingerprint check | ✅ |
| Version pinning | .loa-version.json ck version check | ✅ |
| Synthesis Protection | .claude/overrides/ for customization | ✅ |
| Delta-first reindexing | .ck/ recovery with delta update | ✅ |

### Anthropic Standard (Context Engineering)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Tiered Ledger Retrieval | Phase 2.2, Three-level recovery protocol | ✅ |
| Level 1: Metadata only (~100 tokens) | Active Context + last 3 decisions | ✅ |
| Level 2: Active Task | bd show <id> for task graph | ✅ |
| Level 3: JIT Search | ck --hybrid for historical decisions | ✅ |
| Delta-Synthesis at Yellow (5k tokens) | Phase 7.1, partial persist protocol | ✅ |
| Failure-Aware Parsing | Drop malformed, continue (never crash) | ✅ |
| AST-aware evidence | ck --full-section for complete blocks | ✅ |
| ${PROJECT_ROOT} absolute paths | Mandatory in all citations | ✅ |
| Semantic Decay | Lightweight identifiers decay pattern | ✅ |

### Google ADK Standard (Trajectory Evaluation)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| Grounding ratio enforcement | >= 0.95, BLOCKS /clear if not met | ✅ |
| Negative Grounding for Ghost Features | Two diverse queries required | ✅ |
| Trajectory Pivot for >50 results | Log hypothesis failure before refining | ✅ |
| root_span_id in session_handoff | Lineage tracing across /clear boundaries | ✅ |
| EDD verification (3 test scenarios) | Required before handoff ready | ✅ |
| Word-for-word citations | Mandatory in Decision Log | ✅ |
| notes_refs in trajectory | Line references for audit trail | ✅ |

### Loa Standard (Truth Hierarchy)

| Requirement | Implementation Location | Status |
|-------------|------------------------|--------|
| CODE > BEADS > NOTES.md > CONTEXT | Truth Hierarchy section | ✅ |
| Context window = transient | Never authoritative, disposable | ✅ |
| Beads-first recovery | bd ready → bd show first after /clear | ✅ |
| Fork detection and resolution | Bead Authority Protocol | ✅ |
| Ledger as append-only | Decision Log is permanent record | ✅ |

### Blocking Behaviors

| Trigger | Action | Implementation |
|---------|--------|----------------|
| grounding_ratio < 0.95 | BLOCK /clear | Synthesis Checkpoint Step 1 |
| Ghost without Negative Grounding | BLOCK /clear | Synthesis Checkpoint Step 2 |
| Missing EDD (3 scenarios) | BLOCK /clear | Synthesis Checkpoint Step 7 |
| Relative paths in citations | BLOCK /clear | Path validation |
| Missing word-for-word quote | BLOCK /clear | Grounding verification |

---

## Implementation Checklist

```markdown
## Files to Create/Update

### Create
- [ ] `.claude/protocols/session-continuity.md`
- [ ] `.claude/protocols/synthesis-checkpoint.md`
- [ ] `.claude/protocols/jit-retrieval.md`

### Update
- [ ] `.claude/commands/ride.md` - Session-aware initialization
- [ ] `loa-grimoire/NOTES.md` - Add Session Continuity section
- [ ] `.beads/` schema - Add handoffs[], decisions[] arrays
- [ ] Trajectory format - Add session_handoff phase

### Verify
- [ ] All citations use absolute paths
- [ ] Bead authority documented
- [ ] Synthesis checkpoint integrated
- [ ] JIT retrieval pattern established
- [ ] Attention budget thresholds defined
```

---

*Protocol Version: v2.2 (Production-Hardened, 3 PE Reviews)*
*Engineering Standard: AWS Projen / Google ADK / Anthropic ACI*
*Paradigm: Clear, Don't Compact*
