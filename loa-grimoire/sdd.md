# Software Design Document: Lossless Ledger Protocol

**Project**: Loa Framework v0.9.0
**Feature**: Clear, Don't Compact - Context State Management
**Author**: designing-architecture agent
**Date**: 2025-12-27
**Status**: Draft

---

## 1. Executive Summary

The Lossless Ledger Protocol implements a paradigm shift in context state management: treating the context window as a **disposable workspace** and State Zone artifacts as **lossless external ledgers**. This enables agents to `/clear` context frequently without information loss, maintaining full attention budget while preserving complete audit trails.

### Key Design Principles

1. **Clear, Don't Compact**: Proactive context clearing replaces lossy summarization
2. **Ledger Authority**: External ledgers (Beads, NOTES.md, Trajectory) are source of truth
3. **JIT Retrieval**: Lightweight identifiers replace eager loading (97% token reduction)
4. **Hook-Based Enforcement**: Claude Code hooks enforce synthesis checkpoint before `/clear`
5. **Advisory Monitoring**: Attention budget thresholds are advisory, not blocking

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CONTEXT WINDOW (Transient)                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Current task focus + JIT-retrieved evidence + Active reasoning  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              ↕ /clear                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                     STATE ZONE (Lossless Ledgers)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐  │
│  │   .beads/    │  │  NOTES.md    │  │     trajectory/              │  │
│  │  Task Graph  │  │ Decision Log │  │     Audit Trail              │  │
│  │  decisions[] │  │ Lightweight  │  │     session_handoff          │  │
│  │  handoffs[]  │  │ Identifiers  │  │     delta_sync               │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           LOA FRAMEWORK v0.9.0                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    CONTEXT LIFECYCLE MANAGER                      │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │   │
│  │  │  Session    │  │  Synthesis  │  │  Attention Budget       │  │   │
│  │  │  Recovery   │  │  Checkpoint │  │  Monitor (Advisory)     │  │   │
│  │  │  Protocol   │  │  (Blocking) │  │                         │  │   │
│  │  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │   │
│  │         │                │                     │                 │   │
│  │         ▼                ▼                     ▼                 │   │
│  │  ┌─────────────────────────────────────────────────────────────┐│   │
│  │  │                  LEDGER ACCESS LAYER                        ││   │
│  │  │  ┌───────────┐  ┌───────────┐  ┌────────────────────────┐  ││   │
│  │  │  │  Beads    │  │  NOTES.md │  │  Trajectory Logger     │  ││   │
│  │  │  │  Client   │  │  Manager  │  │  (session_handoff)     │  ││   │
│  │  │  └───────────┘  └───────────┘  └────────────────────────┘  ││   │
│  │  └─────────────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      JIT RETRIEVAL LAYER                          │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │   │
│  │  │  ck Hybrid  │  │  Fallback   │  │  AST-Aware Snippets     │  │   │
│  │  │  Search     │  │  (grep/sed) │  │  (ck --full-section)    │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    ENFORCEMENT LAYER                              │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │   │
│  │  │  Grounding  │  │  Negative   │  │  Hook Integration       │  │   │
│  │  │  Verifier   │  │  Grounding  │  │  (pre-clear)            │  │   │
│  │  │  (>=0.95)   │  │  (Ghosts)   │  │                         │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    SELF-HEALING LAYER                             │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │   │
│  │  │  Git-Backed │  │  Template   │  │  Delta Reindex          │  │   │
│  │  │  Recovery   │  │  Fallback   │  │  (.ck/)                 │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Truth Hierarchy

The Lossless Ledger Protocol enforces a strict truth hierarchy:

```
IMMUTABLE TRUTH HIERARCHY:

1. CODE (src/)           ← Absolute truth, verified by ck
2. BEADS (.beads/)       ← Lossless task graph, rationale, state
3. NOTES.md              ← Decision log, session continuity
4. TRAJECTORY            ← Audit trail, handoff records
5. PRD/SDD               ← Design intent, may drift
6. LEGACY DOCS           ← Historical, often stale
7. CONTEXT WINDOW        ← TRANSIENT, disposable, never authoritative

CRITICAL: Nothing in transient context overrides external ledgers.
```

### 2.3 Zone Model Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                        THREE-ZONE MODEL                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SYSTEM ZONE (.claude/)          IMMUTABLE - Framework owned     │
│  ├── protocols/                                                  │
│  │   ├── session-continuity.md   ← NEW: Recovery protocol       │
│  │   ├── synthesis-checkpoint.md ← NEW: Pre-clear validation    │
│  │   ├── jit-retrieval.md        ← NEW: Lightweight identifiers │
│  │   ├── attention-budget.md     ← NEW: Threshold monitoring    │
│  │   └── grounding-enforcement.md← NEW: Citation verification   │
│  ├── scripts/                                                    │
│  │   ├── synthesis-checkpoint.sh ← NEW: Grounding check         │
│  │   ├── grounding-check.sh      ← NEW: Ratio calculation       │
│  │   └── self-heal-state.sh      ← NEW: State Zone recovery     │
│  └── hooks/                                                      │
│      └── pre-clear.sh            ← NEW: Hook for /clear         │
│                                                                  │
│  STATE ZONE (loa-grimoire/)      MUTABLE - Project owned         │
│  ├── NOTES.md                    ← Extended: Session Continuity │
│  ├── a2a/trajectory/             ← Extended: session_handoff    │
│  └── analytics/                                                  │
│                                                                  │
│  BEADS ZONE (.beads/)            MUTABLE - Task tracking         │
│  └── *.yaml                      ← Extended: decisions[],       │
│                                    handoffs[], test_scenarios[] │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Technology Stack

### 3.1 Core Technologies

| Component | Technology | Justification |
|-----------|------------|---------------|
| Protocols | Markdown | Human-readable, version-controlled |
| Scripts | Bash | Portable, no dependencies, existing pattern |
| Hooks | Claude Code hooks | Native integration, blocking capability |
| Ledger Format | YAML (Beads), Markdown (NOTES), JSONL (Trajectory) | Existing formats, parseable |
| Search | ck (optional) | v0.8.0 integration, graceful fallback |

### 3.2 Dependencies

| Dependency | Version | Required | Notes |
|------------|---------|----------|-------|
| Claude Code | latest | Yes | Hook system for enforcement |
| Git | any | Yes | Self-healing recovery source |
| ck | 0.8.0+ | No | Enhanced JIT retrieval, fallback to grep |
| Beads (bd) | any | No | Enhanced task tracking, fallback to NOTES.md |
| jq | any | No | JSON parsing for grounding calculation |
| bc | any | No | Ratio calculation |

---

## 4. Component Design

### 4.1 Session Continuity Protocol

**Location**: `.claude/protocols/session-continuity.md`

**Purpose**: Ensure zero information loss across context wipes.

```
┌─────────────────────────────────────────────────────────────────┐
│                  SESSION LIFECYCLE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SESSION START                    DURING SESSION                 │
│  ┌──────────────────────┐        ┌──────────────────────┐       │
│  │ 1. bd ready          │        │ Continuous synthesis │       │
│  │ 2. bd show <id>      │        │ to ledgers           │       │
│  │ 3. Tiered Recovery   │        │                      │       │
│  │    (Level 1 default) │        │ Delta-Synthesis at   │       │
│  │ 4. Verify identifiers│        │ Yellow threshold     │       │
│  │ 5. Resume reasoning  │        └──────────┬───────────┘       │
│  └──────────┬───────────┘                   │                   │
│             │                               │                   │
│             ▼                               ▼                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   BEFORE /CLEAR                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ SYNTHESIS CHECKPOINT (BLOCKING)                     │  │  │
│  │  │ 1. Grounding verification (>= 0.95)                │  │  │
│  │  │ 2. Negative grounding (Ghost Features)             │  │  │
│  │  │ 3. Update Decision Log (AST-aware)                 │  │  │
│  │  │ 4. Update Bead (decisions[], next_steps[])         │  │  │
│  │  │ 5. Log trajectory handoff                          │  │  │
│  │  │ 6. Decay raw output -> identifiers                 │  │  │
│  │  │ 7. Verify EDD (3 test scenarios)                   │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  IF ANY FAILS -> BLOCK /CLEAR                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Tiered Ledger Recovery

| Level | Tokens | Trigger | Method |
|-------|--------|---------|--------|
| 1 | ~100 | Default (all /clear recovery) | Active Context + last 3 decisions |
| 2 | ~200-500 | Task needs historical context | `ck --hybrid` for specific decisions |
| 3 | Full scan | User explicit request | Full NOTES.md read |

**Level 1 Implementation**:
```bash
# Load only Session Continuity section (~100 tokens)
head -50 "${PROJECT_ROOT}/loa-grimoire/NOTES.md" | grep -A 20 "## Session Continuity"
```

**Level 2 Implementation**:
```bash
# Semantic search within ledger for specific decisions
ck --hybrid "authentication decision" "${PROJECT_ROOT}/loa-grimoire/" --top-k 3 --jsonl
```

### 4.2 Synthesis Checkpoint

**Location**: `.claude/protocols/synthesis-checkpoint.md`, `.claude/scripts/synthesis-checkpoint.sh`

**Purpose**: Mandatory validation before any `/clear` command.

```
┌─────────────────────────────────────────────────────────────────┐
│               SYNTHESIS CHECKPOINT PROTOCOL                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  STEP 1: GROUNDING VERIFICATION (BLOCKING)                  │ │
│  │                                                             │ │
│  │  Calculate: grounding_ratio = grounded / total_decisions   │ │
│  │  Threshold: >= 0.95 (configurable)                         │ │
│  │                                                             │ │
│  │  IF grounding_ratio < threshold:                           │ │
│  │    - BLOCK /clear                                          │ │
│  │    - Display: "Cannot clear: X decisions lack evidence"    │ │
│  │    - Show: Current ratio, required threshold               │ │
│  │    - Action: Add evidence or mark [ASSUMPTION]             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  STEP 2: NEGATIVE GROUNDING (BLOCKING)                      │ │
│  │                                                             │ │
│  │  For each Ghost Feature flagged this session:              │ │
│  │    - Verify 2 diverse semantic queries executed            │ │
│  │    - Both returned 0 results below 0.4 threshold           │ │
│  │                                                             │ │
│  │  IF any Ghost unverified:                                  │ │
│  │    - Flag as [UNVERIFIED GHOST]                            │ │
│  │    - BLOCK /clear in strict mode                           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  STEPS 3-7: LEDGER SYNC (NON-BLOCKING)                      │ │
│  │                                                             │ │
│  │  3. Update Decision Log with AST-aware evidence            │ │
│  │  4. Update Bead decisions[] and next_steps[]               │ │
│  │  5. Log trajectory session_handoff with notes_refs         │ │
│  │  6. Decay raw output to lightweight identifiers            │ │
│  │  7. Verify EDD (3 test scenarios documented)               │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ALL STEPS COMPLETE -> PERMIT /clear                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Grounding Ratio Script

**Location**: `.claude/scripts/grounding-check.sh`

```bash
#!/usr/bin/env bash
# grounding-check.sh - Calculate grounding ratio from trajectory log

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DATE=$(date +%Y-%m-%d)
AGENT="${1:-implementing-tasks}"
THRESHOLD="${2:-0.95}"

TRAJECTORY="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory/${AGENT}-${DATE}.jsonl"

if [[ ! -f "$TRAJECTORY" ]]; then
    echo "No trajectory log found for today"
    exit 0
fi

# Count claims
total_claims=$(grep -c '"phase":"cite"' "$TRAJECTORY" 2>/dev/null || echo "0")
grounded_claims=$(grep -c '"grounding":"citation"' "$TRAJECTORY" 2>/dev/null || echo "0")
assumptions=$(grep -c '"grounding":"assumption"' "$TRAJECTORY" 2>/dev/null || echo "0")

if [[ "$total_claims" -eq 0 ]]; then
    echo "grounding_ratio=1.00"
    echo "status=pass"
    exit 0
fi

# Calculate ratio
ratio=$(echo "scale=2; $grounded_claims / $total_claims" | bc)

echo "total_claims=$total_claims"
echo "grounded_claims=$grounded_claims"
echo "assumptions=$assumptions"
echo "grounding_ratio=$ratio"

# Check threshold
if (( $(echo "$ratio < $THRESHOLD" | bc -l) )); then
    echo "status=fail"
    echo "message=Grounding ratio $ratio below threshold $THRESHOLD"
    exit 1
else
    echo "status=pass"
    exit 0
fi
```

### 4.3 Attention Budget Monitor

**Location**: `.claude/protocols/attention-budget.md`

**Purpose**: Advisory monitoring of context usage with threshold recommendations.

```
┌─────────────────────────────────────────────────────────────────┐
│                 ATTENTION BUDGET THRESHOLDS                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  GREEN (0-5k tokens)                                             │
│  ├── Status: Normal operation                                   │
│  └── Action: Continue working                                   │
│                                                                  │
│  YELLOW (5k-10k tokens) ← DELTA-SYNTHESIS TRIGGER               │
│  ├── Status: Attention budget moderate                          │
│  ├── Action: Partial persist to ledgers                         │
│  │   1. Append findings to NOTES.md Decision Log               │
│  │   2. Update active Bead with progress                        │
│  │   3. Log: {"phase":"delta_sync","tokens":5000}              │
│  └── Rationale: Survive potential crashes                       │
│                                                                  │
│  ORANGE (10k-15k tokens)                                         │
│  ├── Status: Context filling                                    │
│  ├── Action: Recommend /clear to user                           │
│  └── Message: "Context is filling. Consider /clear when ready." │
│                                                                  │
│  RED (15k+ tokens)                                               │
│  ├── Status: Attention budget exhausted                         │
│  ├── Action: Strong recommendation (advisory, not blocking)     │
│  └── Message: "Attention budget high. Recommend /clear."        │
│                                                                  │
│  NOTE: All thresholds are ADVISORY, not blocking.               │
│        Synthesis checkpoint remains the enforcement point.      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Delta-Synthesis Protocol

Triggered at Yellow threshold (5k tokens):

```yaml
# Trajectory log entry
phase: delta_sync
tokens: 5000
decisions_persisted: 3
bead_updated: true
notes_updated: true
timestamp: 2024-01-15T14:30:00Z
```

**Purpose**: Ensure work survives if agent crashes or user closes session before `/clear`.

### 4.4 JIT Retrieval Layer

**Location**: `.claude/protocols/jit-retrieval.md`

**Purpose**: Token-efficient code retrieval using lightweight identifiers.

```
┌─────────────────────────────────────────────────────────────────┐
│                   JIT RETRIEVAL PROTOCOL                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  LIGHTWEIGHT IDENTIFIER FORMAT                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ | Identifier | Purpose | Last Verified |                    ││
│  │ |------------|---------|---------------|                    ││
│  │ | ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation | 14:25Z ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  TOKEN COMPARISON                                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Eager Loading (50-line block):  ~500 tokens                 ││
│  │ JIT Identifier (path + line):   ~15 tokens                  ││
│  │ Reduction:                      97%                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  RETRIEVAL METHODS                                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 1. ck --hybrid (Recommended when available)                 ││
│  │    ck --hybrid "query" "${PROJECT_ROOT}/src/" --top-k 3     ││
│  │                                                              ││
│  │ 2. ck --full-section (AST-aware)                            ││
│  │    ck --full-section "functionName" "${PROJECT_ROOT}/file"  ││
│  │                                                              ││
│  │ 3. Fallback (when ck unavailable)                           ││
│  │    sed -n '45,67p' "${PROJECT_ROOT}/path/file.ts"           ││
│  │    grep -n "pattern" "${PROJECT_ROOT}/src/"                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  PATH REQUIREMENTS                                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ REQUIRED:   ${PROJECT_ROOT}/src/auth/jwt.ts:45              ││
│  │ INVALID:    src/auth/jwt.ts:45 (relative)                   ││
│  │ INVALID:    ./src/auth/jwt.ts:45 (relative)                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.5 Grounding Enforcement

**Location**: `.claude/protocols/grounding-enforcement.md`

**Purpose**: Verify citation quality and enforce grounding ratio.

```
┌─────────────────────────────────────────────────────────────────┐
│                 GROUNDING ENFORCEMENT                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CITATION FORMAT (REQUIRED)                                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ `export function validateToken()` [${PROJECT_ROOT}/src/auth/jwt.ts:45] │
│  │                                                              ││
│  │ Components:                                                  ││
│  │ 1. Word-for-word code quote (in backticks)                  ││
│  │ 2. Absolute path with ${PROJECT_ROOT} prefix                ││
│  │ 3. Line number                                               ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  GROUNDING RATIO CALCULATION                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ratio = grounded_decisions / total_decisions                ││
│  │                                                              ││
│  │ grounded = decisions with:                                   ││
│  │   - Word-for-word code quote                                 ││
│  │   - ${PROJECT_ROOT} absolute path                            ││
│  │   - Line number reference                                    ││
│  │                                                              ││
│  │ Threshold: >= 0.95 (configurable)                           ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  CONFIGURATION (.loa.config.yaml)                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ grounding_enforcement: strict  # strict | warn | disabled   ││
│  │                                                              ││
│  │ strict:   Block /clear if ratio < 0.95                      ││
│  │ warn:     Warn but allow /clear                              ││
│  │ disabled: No enforcement (not recommended)                   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.6 Self-Healing State Zone

**Location**: `.claude/scripts/self-heal-state.sh`

**Purpose**: Automatic recovery of State Zone files from Git or templates.

```
┌─────────────────────────────────────────────────────────────────┐
│                   SELF-HEALING PROTOCOL                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  RECOVERY PRIORITY ORDER                                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Priority │ Source                │ Fidelity │ Use Case      ││
│  │──────────┼───────────────────────┼──────────┼───────────────││
│  │ 1        │ Git history           │ Highest  │ NOTES.md,     ││
│  │          │ (git show HEAD:...)   │          │ .beads/       ││
│  │ 2        │ Git checkout          │ High     │ Deleted       ││
│  │          │ (tracked files)       │          │ tracked files ││
│  │ 3        │ Template              │ Medium   │ Fresh start   ││
│  │          │ reconstruction        │          │ (git unavail) ││
│  │ 4        │ Delta reindex         │ N/A      │ .ck/ only     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  SELF-HEALING ACTIONS                                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Missing NOTES.md:                                            ││
│  │   1. Try: git show HEAD:loa-grimoire/NOTES.md               ││
│  │   2. Fallback: Create from template                         ││
│  │                                                              ││
│  │ Missing .beads/:                                             ││
│  │   1. Try: git checkout HEAD -- .beads/                      ││
│  │   2. Fallback: Create empty directory                       ││
│  │                                                              ││
│  │ Missing/corrupted .ck/:                                      ││
│  │   If <100 files changed: Delta reindex                      ││
│  │   Else: Full reindex (background)                           ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  KEY PRINCIPLE:                                                  │
│  Never halt on missing State Zone files.                        │
│  Self-heal and continue operation.                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.7 Hook Integration

**Location**: `.claude/hooks/pre-clear.sh` (or Claude Code hooks config)

**Purpose**: Intercept `/clear` command and enforce synthesis checkpoint.

```
┌─────────────────────────────────────────────────────────────────┐
│                   HOOK-BASED ENFORCEMENT                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CLAUDE CODE HOOKS CONFIGURATION                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ # In Claude Code settings or hooks config                   ││
│  │ hooks:                                                       ││
│  │   pre-clear:                                                 ││
│  │     command: .claude/scripts/synthesis-checkpoint.sh        ││
│  │     blocking: true                                          ││
│  │     on_failure: reject                                      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  HOOK FLOW                                                       │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ User: /clear                                                 ││
│  │   │                                                          ││
│  │   ▼                                                          ││
│  │ Hook: pre-clear.sh                                           ││
│  │   │                                                          ││
│  │   ├── Run grounding-check.sh                                ││
│  │   │   └── IF ratio < 0.95 -> EXIT 1 (block)                ││
│  │   │                                                          ││
│  │   ├── Check negative grounding (strict mode)                ││
│  │   │   └── IF unverified ghosts -> EXIT 1 (block)           ││
│  │   │                                                          ││
│  │   └── All checks pass -> EXIT 0 (permit)                   ││
│  │                                                              ││
│  │ IF EXIT 0:                                                   ││
│  │   └── /clear executes normally                              ││
│  │                                                              ││
│  │ IF EXIT 1:                                                   ││
│  │   └── /clear blocked, error message shown                   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Data Architecture

### 5.1 NOTES.md Schema Extension

**Location**: `loa-grimoire/NOTES.md`

```markdown
# Agent Working Memory (NOTES.md)

## Session Continuity
<!-- CRITICAL: Load this section FIRST after /clear (~100 tokens) -->

### Active Context
- **Current Bead**: bd-x7y8 (Implementing JWT refresh)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Validating token expiry edge cases

### Lightweight Identifiers
<!-- Absolute paths only - retrieve full content on-demand -->
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation logic | 14:25:00Z |
| ${PROJECT_ROOT}/src/auth/refresh.ts:12-34 | Refresh flow | 14:28:00Z |

### Decision Log
<!-- Decisions survive context wipes - permanent record -->

#### 2024-01-15T14:30:00Z - Token Expiry Handling
**Decision**: Use sliding window expiration with 15-minute grace period
**Rationale**: Balances security (short expiry) with UX (no mid-session logouts)
**Evidence**:
- `export function isTokenExpired(token: Token, graceMs = 900000)` [${PROJECT_ROOT}/src/auth/jwt.ts:52]
**Test Scenarios**:
1. Token expires exactly at boundary -> grace period applies
2. Token expires beyond grace -> forced refresh
3. Refresh token also expired -> full re-authentication

### Pending Questions
<!-- Carry forward across sessions -->
- [ ] Should grace period be configurable per-client?

## Active Sub-Goals
<!-- Current objectives being pursued -->

## Discovered Technical Debt
<!-- Issues found during implementation -->

## Blockers & Dependencies
<!-- External factors affecting progress -->
```

### 5.2 Bead Schema Extensions

**Location**: `.beads/<id>.yaml`

```yaml
# Extended Bead schema for Lossless Ledger Protocol
id: bd-x7y8
title: "Implement JWT refresh token rotation"
type: feature
status: in_progress
priority: 1

# Standard Bead fields...
created: 2024-01-15T10:00:00Z
assignee: null

# NEW: Decision history (append-only ledger)
decisions:
  - ts: 2024-01-15T10:30:00Z
    decision: "Use rotating refresh tokens"
    rationale: "Prevents token theft replay attacks"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/refresh.ts
        line: 12
        quote: "export async function rotateRefreshToken()"

  - ts: 2024-01-15T14:30:00Z
    decision: "Add 15-minute grace period"
    rationale: "Balance security with UX"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/jwt.ts
        line: 52
        quote: "export function isTokenExpired(token, graceMs = 900000)"

# NEW: EDD verification (required before handoff)
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

# NEW: Session handoff chain
handoffs:
  - session_id: "sess-001"
    ended: 2024-01-15T12:00:00Z
    notes_ref: "loa-grimoire/NOTES.md:45-67"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-abc"
    grounding_ratio: 0.97

  - session_id: "sess-002"
    ended: 2024-01-15T14:30:00Z
    notes_ref: "loa-grimoire/NOTES.md:68-92"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-def"
    grounding_ratio: 0.95

# Next steps (specific, actionable)
next_steps:
  - "Implement clock skew tolerance (±30 seconds)"
  - "Add refresh token blacklist for logout"

# Blockers and questions
blockers: []
questions:
  - "Should grace period be configurable per-client?"
```

### 5.3 Trajectory Schema Extensions

**Location**: `loa-grimoire/a2a/trajectory/{agent}-{date}.jsonl`

#### New Phase: session_handoff

```jsonl
{"ts":"2024-01-15T14:30:00Z","agent":"implementing-tasks","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"bd-x7y8","notes_refs":["loa-grimoire/NOTES.md:68-92"],"edd_verified":true,"grounding_ratio":0.97,"test_scenarios":3,"next_session_ready":true}
```

#### New Phase: delta_sync

```jsonl
{"ts":"2024-01-15T12:00:00Z","agent":"implementing-tasks","phase":"delta_sync","tokens":5000,"decisions_persisted":3,"bead_updated":true,"notes_updated":true}
```

#### New Phase: grounding_check

```jsonl
{"ts":"2024-01-15T14:29:00Z","agent":"implementing-tasks","phase":"grounding_check","total_claims":20,"grounded_claims":19,"assumptions":1,"grounding_ratio":0.95,"threshold":0.95,"status":"pass"}
```

### 5.4 Configuration Schema

**Location**: `.loa.config.yaml`

```yaml
# Lossless Ledger Protocol Configuration
grounding_enforcement: strict  # strict | warn | disabled

# Attention budget thresholds (advisory)
attention_budget:
  yellow: 5000   # Delta-synthesis trigger
  orange: 10000  # Recommend /clear
  red: 15000     # Strong recommendation

# Session continuity settings
session_continuity:
  tiered_recovery: true
  level1_tokens: 100
  level2_tokens: 500

# Trajectory settings
trajectory:
  retention_days: 30
  archive_days: 365
  compression_level: 6

# EDD requirements
edd:
  enabled: true
  min_test_scenarios: 3
  require_citations: true
```

---

## 6. Integration Points

### 6.1 Command Integration

#### /ride Command Updates

Add session-aware initialization to `/ride`:

```yaml
# In .claude/commands/ride.md
session_aware:
  on_start:
    - bd ready              # Identify active tasks
    - bd show <active_id>   # Load task context
    - tiered_recovery: 1    # Level 1 NOTES.md load

  during:
    - continuous_synthesis: true
    - delta_sync_at: 5000   # Yellow threshold

  on_complete:
    - synthesis_checkpoint: true
    - trajectory_handoff: true
```

### 6.2 Skill Integration

All skills receive session continuity protocol instructions:

```yaml
# In skill index.yaml
protocols:
  - session-continuity
  - synthesis-checkpoint
  - jit-retrieval
  - attention-budget
  - grounding-enforcement
```

### 6.3 ck Integration (v0.8.0)

JIT retrieval leverages ck when available:

| Operation | ck Command | Fallback |
|-----------|------------|----------|
| Semantic search | `ck --hybrid "query" path` | `grep -rn "pattern" path` |
| AST-aware snippet | `ck --full-section "name" file` | `sed -n 'start,endp' file` |
| Negative grounding | `ck --hybrid "query" --threshold 0.4` | Manual verification |

### 6.4 Beads Integration

Extended Bead operations:

| Operation | Command | Purpose |
|-----------|---------|---------|
| Load task context | `bd show <id>` | Restore decisions[], handoffs[] |
| Append decision | `bd update <id> --decision "..."` | Update decisions[] array |
| Log handoff | `bd update <id> --handoff "..."` | Add to handoffs[] array |
| Fork detection | `bd diff <id>` | Compare context vs Bead state |

---

## 7. Security Architecture

### 7.1 Security Principles

| Principle | Implementation |
|-----------|----------------|
| No secrets in ledgers | Inherited from v0.8.0 patterns |
| Absolute paths only | `${PROJECT_ROOT}` prefix required |
| Audit trail immutability | Append-only trajectory logs |
| Safe defaults | `grounding_enforcement: strict` default |

### 7.2 Threat Mitigation

| Threat | Mitigation |
|--------|------------|
| Information leakage in ledgers | No credentials, tokens, or secrets stored |
| Path traversal | `${PROJECT_ROOT}` validation |
| Ledger tampering | Git-backed recovery, checksums |
| Incomplete audit trail | Mandatory trajectory logging |

---

## 8. Performance Architecture

### 8.1 Token Efficiency

| Metric | Target | Implementation |
|--------|--------|----------------|
| Level 1 recovery | ~100 tokens | Session Continuity section only |
| Lightweight identifier | ~15 tokens | Path + line reference |
| Full code block | ~500 tokens | Avoided via JIT retrieval |
| Token reduction | 97% | JIT vs eager loading |

### 8.2 Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Session recovery | < 30 seconds | bd show + Level 1 load |
| Grounding check | < 5 seconds | Trajectory grep |
| Delta-synthesis | < 5 seconds | Async write to ledgers |
| Synthesis checkpoint | < 10 seconds | Full validation |

---

## 9. Deployment Architecture

### 9.1 File Changes Summary

#### New Files (System Zone)

| File | Purpose |
|------|---------|
| `.claude/protocols/session-continuity.md` | Session recovery protocol |
| `.claude/protocols/synthesis-checkpoint.md` | Pre-clear validation |
| `.claude/protocols/jit-retrieval.md` | Lightweight identifier protocol |
| `.claude/protocols/attention-budget.md` | Threshold monitoring |
| `.claude/protocols/grounding-enforcement.md` | Citation verification |
| `.claude/scripts/synthesis-checkpoint.sh` | Synthesis validation script |
| `.claude/scripts/grounding-check.sh` | Ratio calculation script |
| `.claude/scripts/self-heal-state.sh` | State Zone recovery script |

#### Updated Files

| File | Changes |
|------|---------|
| `.claude/protocols/structured-memory.md` | Add Session Continuity section |
| `.claude/commands/ride.md` | Session-aware initialization |
| `.loa.config.yaml` | Add grounding_enforcement option |
| `CLAUDE.md` | Document Lossless Ledger Protocol |

#### State Zone Templates

| File | Changes |
|------|---------|
| `loa-grimoire/NOTES.md` | Session Continuity section template |

### 9.2 Migration Path

1. **v0.8.0 -> v0.9.0**: Additive changes only
2. **Backwards compatible**: Existing projects continue working
3. **Optional adoption**: Protocols can be enabled incrementally
4. **Configuration-driven**: Enforcement levels configurable

---

## 10. Development Workflow

### 10.1 Sprint Planning

| Sprint | Focus | Deliverables |
|--------|-------|--------------|
| 1 | Foundation | Protocols, core scripts |
| 2 | Enforcement | Hook integration, grounding check |
| 3 | Integration | Command updates, skill integration |
| 4 | Polish | Documentation, testing, edge cases |

### 10.2 Testing Strategy

| Test Type | Coverage |
|-----------|----------|
| Unit tests | grounding-check.sh, self-heal-state.sh |
| Integration tests | Hook flow, session recovery |
| E2E tests | Full /clear cycle with enforcement |
| Edge cases | Missing files, corrupted ledgers, ratio edge cases |

---

## 11. Technical Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Grounding enforcement too strict | Medium | User frustration | Configurable enforcement levels |
| Hook integration complexity | Medium | Delayed delivery | Start with protocol-only, add hooks |
| Delta-synthesis overhead | Low | Performance impact | Async write to ledgers |
| ck unavailability | Low | Reduced capability | Graceful fallback to grep/sed |
| Bead schema changes break existing | Low | Data loss | Additive schema changes only |

---

## 12. Future Considerations

### 12.1 v0.10.0+ Roadmap

- MCP-based ledger synchronization
- Multi-agent session handoff
- Real-time attention budget visualization
- Ledger versioning and rollback
- Cross-repository session continuity

### 12.2 Technical Debt Management

| Item | Priority | Notes |
|------|----------|-------|
| Hook system documentation | P1 | Claude Code hooks are new |
| Grounding ratio edge cases | P2 | Handle zero-claim sessions |
| Trajectory log rotation | P2 | Automated archival |

---

## 13. Appendix

### A. Protocol Dependencies

```
session-continuity.md
├── synthesis-checkpoint.md (BEFORE /clear)
├── jit-retrieval.md (Lightweight identifiers)
├── attention-budget.md (Threshold monitoring)
└── grounding-enforcement.md (Citation quality)

self-audit-checkpoint.md
└── grounding-enforcement.md (Ratio calculation)

trajectory-evaluation.md
├── session_handoff (NEW phase)
└── delta_sync (NEW phase)
```

### B. Script Dependencies

```
synthesis-checkpoint.sh
├── grounding-check.sh
├── self-heal-state.sh
└── (bd commands for Bead update)

grounding-check.sh
├── jq (optional, for JSON parsing)
└── bc (for ratio calculation)

self-heal-state.sh
├── git (for recovery)
└── ck (optional, for reindex)
```

### C. Configuration Reference

```yaml
# Complete .loa.config.yaml for v0.9.0
grounding_enforcement: strict  # strict | warn | disabled

attention_budget:
  yellow: 5000
  orange: 10000
  red: 15000

session_continuity:
  tiered_recovery: true
  level1_tokens: 100
  level2_tokens: 500

trajectory:
  retention_days: 30
  archive_days: 365
  compression_level: 6

edd:
  enabled: true
  min_test_scenarios: 3
  require_citations: true
```

---

**Document Version**: 1.0
**Protocol Version**: v2.2 (Production-Hardened)
**Engineering Standard**: AWS Projen / Google ADK / Anthropic ACI
**Paradigm**: Clear, Don't Compact
