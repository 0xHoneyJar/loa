# Product Requirements Document: Lossless Ledger Protocol

**Project**: Loa Framework v0.9.0
**Feature**: Clear, Don't Compact - Context State Management
**Author**: discovering-requirements agent
**Date**: 2025-12-27
**Status**: Draft

---

## 1. Problem Statement

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:13-14

Context compaction (summarization) is inherently lossy. As conversations grow, compaction smudges the chalkboard until it becomes a grey blur of unreadable ghosts—hallucinations, lost context, degraded reasoning.

### Current State

The Loa framework currently relies on Claude's automatic context management, which uses summarization/compaction when the context window fills. This leads to:

1. **Information Loss**: Compacted summaries lose nuance, exact citations, and reasoning chains
2. **Hallucinations**: Agents confabulate details from degraded context
3. **Citation Rot**: Relative paths and partial quotes become unresolvable after compaction
4. **Session Discontinuity**: Reasoning state is lost across `/clear` or session boundaries
5. **Attention Degradation**: Large contexts dilute focus on current task

### The Blockchain Analogy

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:21-32

| Smudged Ledger (Compaction) | Digital Blockchain (Lossless) |
|-----------------------------|-------------------------------|
| Fading, overwritten memory | Immutable, append-only ledger |
| Cluttered desk | Clear desk after every audit |
| Summarized evidence | Word-for-word, verifiable |
| "I think I remember..." | Timestamped trajectory |

---

## 2. Goals & Success Metrics

### 2.1 Business Objectives

| Objective | Metric | Target |
|-----------|--------|--------|
| Zero information loss | Citation survival rate | 100% |
| Faster session recovery | Time to resume after /clear | < 30 seconds |
| Reduced hallucinations | Grounding ratio enforcement | >= 0.95 |
| Token efficiency | Context reduction | 99.6% via lightweight identifiers |
| Audit trail completeness | Trajectory coverage | 100% session handoffs |

### 2.2 Success Criteria

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:1148-1170

1. **Session Continuity**: Information loss after `/clear` = 0%
2. **Attention Quality**: Average context size at `/clear` < 8,000 tokens
3. **Audit Trail**: Decision traceability via trajectory = 100%
4. **EDD Compliance**: 3 test scenarios per task = 100%
5. **Reasoning Consistency**: Cross-session consistency = 100%

---

## 3. User & Stakeholder Context

### 3.1 Primary Users

| Persona | Role | Pain Point | Benefit |
|---------|------|------------|---------|
| **Agent Developer** | Uses Loa for development | Context rot during long sessions | Lossless state across `/clear` |
| **Enterprise User** | Compliance requirements | Audit trail gaps | Complete trajectory logging |
| **Framework Maintainer** | Maintains Loa | Complex state management | Clear protocols, self-healing |

### 3.2 User Journey

1. **Session Start**: Agent recovers state from Beads + NOTES.md (tiered, ~100 tokens)
2. **During Work**: Continuous synthesis to ledgers, JIT retrieval as needed
3. **Attention Warning**: At Yellow (5k tokens), Delta-Synthesis persists work
4. **Before Clear**: Synthesis checkpoint verifies grounding ratio >= 0.95
5. **After Clear**: Instant recovery from lossless ledgers, full attention restored

---

## 4. Functional Requirements

### 4.1 Core Features

#### FR-1: Truth Hierarchy Enforcement

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:67-81

Establish immutable truth hierarchy:

```
1. CODE (src/)           <- Absolute truth, verified by ck
2. BEADS (.beads/)       <- Lossless task graph, rationale, state
3. NOTES.md              <- Decision log, session continuity
4. TRAJECTORY            <- Audit trail, handoff records
5. PRD/SDD               <- Design intent, may drift
6. LEGACY DOCS           <- Historical, often stale
7. CONTEXT WINDOW        <- TRANSIENT, disposable, never authoritative
```

**Acceptance Criteria**:
- [ ] Truth hierarchy documented in protocol
- [ ] Agents never treat context window as authoritative
- [ ] Fork detection when context conflicts with ledger state

#### FR-2: Session Continuity Protocol

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:270-330, 329-598

Implement session recovery and synthesis checkpoint protocols.

**After `/clear` or Session Start**:
1. Restore task context: `bd ready` -> `bd show <id>`
2. Tiered ledger recovery (Level 1: ~100 tokens default)
3. Verify lightweight identifiers exist (don't load content)
4. Resume from "Reasoning State" checkpoint

**Before `/clear`**:
1. Grounding verification (BLOCKING if < 0.95)
2. Negative grounding verification for Ghost Features
3. Update Decision Log with AST-aware evidence
4. Update Bead with decisions[], next_steps[]
5. Log trajectory handoff with notes_refs
6. Decay raw output to lightweight identifiers
7. Verify EDD (3 test scenarios)

**Acceptance Criteria**:
- [ ] `/clear` blocked if grounding_ratio < 0.95
- [ ] Session recovery completes in < 30 seconds
- [ ] All citations use `${PROJECT_ROOT}` absolute paths
- [ ] Synthesis checkpoint logged to trajectory

#### FR-3: Tiered Ledger Recovery

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:353-390

Implement attention-aware ledger retrieval:

| Level | Tokens | Trigger | Method |
|-------|--------|---------|--------|
| 1 | ~100 | Default | Active Context + last 3 decisions |
| 2 | ~200-500 | Task needs history | `ck --hybrid` for specific decisions |
| 3 | Full scan | User-requested | Major architectural review |

**Acceptance Criteria**:
- [ ] Level 1 recovery loads < 100 tokens by default
- [ ] Level 2 uses ck semantic search for JIT retrieval
- [ ] Level 3 requires explicit user request
- [ ] Graceful fallback when ck unavailable

#### FR-4: Attention Budget Governance

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:934-995

Implement token threshold monitoring and actions:

| Threshold | Tokens | Action |
|-----------|--------|--------|
| Green | 0-5,000 | Normal operation |
| Yellow | 5,000-10,000 | **Delta-Synthesis** (partial persist) |
| Orange | 10,000-15,000 | Recommend `/clear` to user |
| Red | 15,000+ | MANDATORY synthesis, halt new work |

**Delta-Synthesis Protocol** (at Yellow):
1. Append recent findings to NOTES.md Decision Log
2. Update active Bead with progress-to-date
3. Log trajectory: `{"phase":"delta_sync","tokens":5000,"decisions_persisted":N}`
4. DO NOT clear context yet - just persist

**Acceptance Criteria**:
- [ ] Delta-synthesis triggers at 5k tokens
- [ ] User notification at Orange threshold
- [ ] Mandatory halt at Red threshold
- [ ] Work survives crashes via partial persist

#### FR-5: JIT Retrieval Protocol

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:867-930

Replace eager loading with lightweight identifiers:

| Approach | Tokens | Result |
|----------|--------|--------|
| Eager (50-line block) | ~500 | Context fills, attention degrades |
| JIT (path + line) | ~15 | 97% reduction, retrieve on-demand |

**Lightweight Identifier Format**:
```
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation | 14:25:00Z |
```

**Retrieval Methods**:
- `ck --hybrid "query" "${PROJECT_ROOT}/src/" --top-k 3 --jsonl`
- `sed -n '45,67p' "${PROJECT_ROOT}/path/file.ts"`
- `ck --full-section "functionName" "${PROJECT_ROOT}/path/file.ts"` (AST-aware)

**Acceptance Criteria**:
- [ ] All paths use `${PROJECT_ROOT}` prefix
- [ ] Evidence uses AST-aware snippets (`ck --full-section`)
- [ ] Token budget tracks lightweight vs full retrieval
- [ ] Graceful fallback to sed/grep when ck unavailable

#### FR-6: Grounding Ratio Enforcement

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:522-578

Implement citation quality verification:

**Requirements**:
- Every decision must have word-for-word code quote
- Every citation must use `${PROJECT_ROOT}` absolute path
- Grounding ratio = grounded_decisions / total_decisions
- BLOCKING: `/clear` rejected if ratio < 0.95

**Configurable Enforcement** (in `.loa.config.yaml`):
```yaml
grounding_enforcement: strict  # strict | warn | disabled
```

- **strict**: Block `/clear` if grounding < 0.95
- **warn**: Warn but allow `/clear`
- **disabled**: No enforcement (not recommended)

**Acceptance Criteria**:
- [ ] Grounding ratio calculated correctly
- [ ] `/clear` blocked in strict mode when < 0.95
- [ ] Clear error message with actionable remediation
- [ ] Configuration option in `.loa.config.yaml`

#### FR-7: Negative Grounding Protocol

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:469-478

Verify Ghost Features don't create "Phantom Liabilities":

**Requirements**:
- Execute 2 diverse semantic queries for each Ghost Feature
- Both queries must return 0 results below 0.4 similarity threshold
- If not verified, flag as `[UNVERIFIED GHOST]`

**Acceptance Criteria**:
- [ ] Ghost Features require negative grounding verification
- [ ] Unverified ghosts flagged appropriately
- [ ] `/clear` blocked if unverified ghosts in strict mode
- [ ] Trajectory logs negative grounding attempts

#### FR-8: Trajectory Handoff Protocol

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:720-768

Extend trajectory logging for session handoffs:

**Session Handoff Log Format**:
```jsonl
{"ts":"...","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"bd-x7y8","notes_refs":["NOTES.md:68-92"],"edd_verified":true,"grounding_ratio":0.97,"next_session_ready":true}
```

**Trajectory Pivot Protocol** (for >50 result searches):
```jsonl
{"phase":"pivot","reason":"query too broad","result_count":127,"hypothesis_failure":"...","refined_hypothesis":"..."}
```

**Acceptance Criteria**:
- [ ] Session handoff logged with root_span_id for lineage
- [ ] notes_refs point to specific NOTES.md lines
- [ ] Trajectory Pivot logged for >50 result searches
- [ ] EDD verification status included

#### FR-9: Self-Healing State Zone

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:85-232

Implement production-hardened recovery:

**Recovery Priority Order**:
| Priority | Source | Fidelity | Use Case |
|----------|--------|----------|----------|
| 1 | Git history (`git show HEAD:...`) | **Highest** | NOTES.md, .beads/ recovery |
| 2 | Git checkout (tracked files) | High | Restore deleted but tracked files |
| 3 | Template reconstruction | Medium | Fresh start when git unavailable |
| 4 | Delta reindex | N/A | .ck/ search index only |

**Self-Healing Actions**:
- Missing NOTES.md -> Recover from git, then template
- Missing .beads/ -> Recover from git checkout
- Missing .ck/ -> Delta reindex if <100 files changed, else full reindex

**Acceptance Criteria**:
- [ ] Git-backed recovery attempted first
- [ ] Template reconstruction as fallback
- [ ] Never halt on missing State Zone files
- [ ] Recovery logged to trajectory

#### FR-10: NOTES.md Session Continuity Section

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:270-327

Add structured session continuity to NOTES.md:

```markdown
## Session Continuity
<!-- Load FIRST after /clear -->

### Active Context
- **Current Bead**: bd-x7y8 (task description)
- **Last Checkpoint**: 2024-01-15T14:30:00Z
- **Reasoning State**: Where we left off

### Lightweight Identifiers
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/src/auth/jwt.ts:45-67 | Token validation | 14:25:00Z |

### Decision Log
#### 2024-01-15T14:30:00Z - Decision Title
**Decision**: What we decided
**Rationale**: Why
**Evidence**: `code quote` [${PROJECT_ROOT}/file.ts:line]
**Test Scenarios**: 1) happy 2) edge 3) error
```

**Acceptance Criteria**:
- [ ] NOTES.md template includes Session Continuity section
- [ ] Lightweight Identifiers table format standardized
- [ ] Decision Log format includes evidence and test scenarios
- [ ] All paths use `${PROJECT_ROOT}` prefix

#### FR-11: Bead Schema Extensions

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:602-684

Extend Bead YAML schema for lossless protocol:

```yaml
# Extended Bead fields
decisions:
  - ts: 2024-01-15T14:30:00Z
    decision: "Use rotating refresh tokens"
    rationale: "Prevents token theft replay attacks"
    evidence:
      - path: ${PROJECT_ROOT}/src/auth/refresh.ts
        line: 12
        quote: "export async function rotateRefreshToken()"

test_scenarios:
  - name: "Token at boundary"
    type: edge_case
    expected: "Grace period applies"

handoffs:
  - session_id: "sess-001"
    ended: 2024-01-15T12:00:00Z
    notes_ref: "loa-grimoire/NOTES.md:45-67"
    trajectory_ref: "trajectory/impl-2024-01-15.jsonl:span-abc"
```

**Acceptance Criteria**:
- [ ] decisions[] array captures decision history
- [ ] test_scenarios[] captures EDD requirements
- [ ] handoffs[] tracks session boundaries
- [ ] Schema backwards-compatible with existing Beads

---

### 4.2 Integration Requirements

#### IR-1: ck Semantic Search Integration

The Lossless Ledger Protocol integrates with ck (v0.8.0) for:

- **JIT Retrieval**: `ck --hybrid` for semantic search
- **AST-Aware Snippets**: `ck --full-section` for complete functions
- **Negative Grounding**: Semantic queries for Ghost Feature verification

**Fallback Behavior** (when ck unavailable):
- JIT retrieval: `grep -n` + `sed -n`
- AST-aware: Line ranges only (degraded)
- Negative grounding: Manual verification required

#### IR-2: Beads Integration

Extend existing Beads CLI (`bd`) for:
- `bd show <id>` displays decisions[] and handoffs[]
- `bd update <id>` appends to decisions[]
- Fork detection when context conflicts with Bead state

---

## 5. Technical & Non-Functional Requirements

### 5.1 Performance

| Metric | Target |
|--------|--------|
| Session recovery time | < 30 seconds |
| Level 1 ledger load | < 100 tokens |
| Delta-synthesis overhead | < 5 seconds |
| Lightweight identifier size | ~15 tokens |

### 5.2 Reliability

| Requirement | Implementation |
|-------------|----------------|
| Self-healing State Zone | Git-backed recovery + template fallback |
| Crash recovery | Delta-synthesis at Yellow preserves work |
| Malformed ledger tolerance | Drop bad lines, continue parsing |
| Graceful degradation | Works without ck (reduced capability) |

### 5.3 Security

| Requirement | Implementation |
|-------------|----------------|
| No secrets in ledgers | Inherited from v0.8.0 patterns |
| Absolute paths only | `${PROJECT_ROOT}` prefix required |
| Audit trail immutability | Append-only trajectory logs |

---

## 6. Scope & Prioritization

### 6.1 MVP (v0.9.0)

| Priority | Feature | Rationale |
|----------|---------|-----------|
| P0 | Session Continuity Protocol | Core paradigm shift |
| P0 | Synthesis Checkpoint | Prevents data loss |
| P0 | Tiered Ledger Recovery | Attention-aware loading |
| P0 | Grounding Ratio Enforcement | Quality gate |
| P1 | Attention Budget Governance | Proactive management |
| P1 | JIT Retrieval Protocol | Token efficiency |
| P1 | Self-Healing State Zone | Production reliability |
| P2 | Negative Grounding Protocol | Ghost Feature verification |
| P2 | Bead Schema Extensions | Enhanced tracking |

### 6.2 Future Scope (v0.10.0+)

- MCP-based ledger synchronization
- Multi-agent session handoff
- Real-time attention budget visualization
- Ledger versioning and rollback

### 6.3 Explicitly Out of Scope

- Changes to Claude's internal context management
- Modifications to the ck binary
- External database integration
- Cloud-based ledger storage

---

## 7. Risks & Dependencies

### 7.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Grounding enforcement too strict | Medium | User frustration | Configurable enforcement levels |
| Delta-synthesis overhead | Low | Performance impact | Async write to ledgers |
| ck unavailability | Low | Reduced capability | Graceful fallback to grep/sed |

### 7.2 Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| ck Semantic Search (v0.8.0) | Available | Optional but recommended |
| Beads CLI (`bd`) | Available | Requires schema extensions |
| Git | Required | For self-healing recovery |

---

## 8. Implementation Checklist

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:1256-1278, LOA_LOSSLESS_LEDGER_CLI_PROMPT.md:339-352

### Files to Create

- [ ] `.claude/protocols/session-continuity.md`
- [ ] `.claude/protocols/synthesis-checkpoint.md`
- [ ] `.claude/protocols/jit-retrieval.md`
- [ ] `.claude/protocols/attention-budget.md`
- [ ] `.claude/protocols/grounding-enforcement.md`

### Files to Update

- [ ] `.claude/commands/ride.md` - Session-aware initialization
- [ ] `.claude/protocols/structured-memory.md` - Session Continuity section
- [ ] `.loa.config.yaml` - Add grounding_enforcement option
- [ ] Bead schema - Add decisions[], handoffs[], test_scenarios[]
- [ ] Trajectory format - Add session_handoff, delta_sync phases

### Scripts to Create

- [ ] `.claude/scripts/synthesis-checkpoint.sh` - Pre-clear validation
- [ ] `.claude/scripts/grounding-check.sh` - Ratio calculation
- [ ] `.claude/scripts/self-heal-state.sh` - State Zone recovery

---

## 9. Appendix

### A. Citation Format Standard

**Required Format** (survives session wipes):
```
`export function validateToken()` [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

**Insufficient Format** (loses context):
```
validateToken [src/auth/jwt.ts:45]
```

**Rule**: `${PROJECT_ROOT}` prefix + absolute path + line number + word-for-word quote

### B. Anti-Patterns

> Sources: LOA_LOSSLESS_LEDGER_PROMPT.md:1110-1143

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| "I'll remember this" | Write to NOTES.md NOW |
| Trust compacted context | Trust only ledgers |
| Relative paths | ALWAYS `${PROJECT_ROOT}` absolute paths |
| Defer synthesis | Synthesize continuously |
| Reason without Bead | ALWAYS `bd show` first |
| Eager load files | Store identifiers, JIT retrieve |
| `/clear` without checkpoint | Execute protocol first |

### C. Traceability Matrix

Production-hardened requirements from 3 Principal Engineer reviews:

| Standard | Requirements | Status |
|----------|--------------|--------|
| AWS Projen | Self-healing, Git recovery, Version pinning | Included |
| Anthropic ACI | Tiered recovery, Delta-synthesis, AST-aware | Included |
| Google ADK | Grounding ratio, Negative grounding, Trajectory | Included |
| Loa Standard | Truth hierarchy, Beads-first, Fork detection | Included |

---

**Document Version**: 1.0
**Protocol Version**: v2.2 (Production-Hardened)
**Engineering Standard**: AWS Projen / Google ADK / Anthropic ACI
**Paradigm**: Clear, Don't Compact
