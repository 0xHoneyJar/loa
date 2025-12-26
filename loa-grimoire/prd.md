# Product Requirements Document: ck Semantic Search Integration

**Project**: Loa Framework - Enterprise-Grade Semantic Code Search Integration
**Version**: 1.0
**Status**: Discovery Complete
**Date**: 2025-12-26
**Agent**: discovering-requirements

---

## Executive Summary

This PRD defines the requirements for integrating `ck` (seek) semantic/hybrid search as a first-class capability within the Loa agent framework. The integration follows the beads pattern: surface at setup, invisible to users, graceful degradation, and zero friction. This enhancement transforms Loa agents from keyword-based search to semantic code understanding while maintaining identical user experience regardless of whether ck is installed.

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1-13, LOA_CK_CLI_PROMPT.md:1-10

---

## Phase 0: Context Synthesis

### Documents Discovered

1. **LOA_CK_INTEGRATION_PROMPT.md** (74,246 bytes)
   - Comprehensive integration specification with 9 phases
   - ACI (Agent-Computer Interface) standards
   - Trajectory evaluation protocols
   - Truth hierarchy enforcement

2. **LOA_CK_CLI_PROMPT.md** (21,204 bytes)
   - Executive summary of integration requirements
   - Core principles and success criteria
   - Anti-pattern prevention
   - Traceability verification matrix

### Key Insights from Context

**Design Pattern**: The integration follows the **beads pattern** - an existing optional enhancement in Loa that provides:
- Surface installation at setup
- Invisible to user (no new commands)
- Graceful degradation (works without it)
- Zero friction (seamless enhancement)

**Source**: LOA_CK_INTEGRATION_PROMPT.md:72-94

**Engineering Standards**: The integration must meet FAANG-tier quality standards from:
- **AWS Projen**: Infrastructure integrity, managed scaffolding, synthesis protection
- **Google ADK**: Trajectory evaluation, reasoning logging, EDD (Evaluation-Driven Development)
- **Anthropic Agent SDK**: Context engineering, attention budgets, tool result clearing

**Source**: LOA_CK_INTEGRATION_PROMPT.md:5, LOA_CK_CLI_PROMPT.md:2

---

## Phase 1: Problem & Vision

### Core Problem

**Problem Statement**: Loa agents currently use keyword-based search (grep) for code discovery, which has significant limitations:

1. **Semantic Blindness**: Cannot understand code meaning, only literal matches
2. **High False-Positive Rate**: Keyword matches don't guarantee relevance
3. **Ghost Feature Detection Failures**: Cannot reliably detect documented features missing from code
4. **Shadow System Detection Failures**: Cannot identify undocumented code through conceptual search
5. **Context Overflow**: Loading entire files overwhelms agent attention budgets

**Source**: LOA_CK_INTEGRATION_PROMPT.md:926-1050 (Tool Result Clearing Protocol)

### Vision

**Vision Statement**: Enable Loa agents to understand code semantically, not just syntactically, transforming them from "keyword librarians" to "forensic auditors" that can:

- Verify code reality against documentation claims
- Detect Ghost Features (documented but not implemented)
- Identify Shadow Systems (implemented but undocumented)
- Load minimal, high-signal context just-in-time
- Maintain full audit trails of reasoning chains

**Source**: LOA_CK_INTEGRATION_PROMPT.md:2206-2211 (Analogy)

### Mission

Integrate `ck` semantic search into Loa as an invisible enhancement that:
1. **Never breaks existing workflows** - All commands work without ck
2. **Never surfaces to users** - Users cannot tell which search mode is active
3. **Always maintains integrity** - Pre-flight checks prevent compromised operations
4. **Always grounds claims** - Every architectural decision backed by code evidence

**Source**: LOA_CK_CLI_PROMPT.md:5-10 (Core Principles)

---

## Phase 2: Goals & Success Metrics

### Business Objectives

1. **Increase Agent Precision**: Semantic search reduces false positives in code discovery
2. **Accelerate Code Analysis**: 80-90% cache hit rate via delta-indexed embeddings
3. **Improve Documentation Accuracy**: Automated Ghost/Shadow detection prevents doc drift
4. **Maintain Zero Barrier to Entry**: Optional enhancement, never required

**Source**: LOA_CK_INTEGRATION_PROMPT.md:190-217 (Installation Benefits)

### Key Performance Indicators (KPIs)

| Metric | Target | Rationale | Source |
|--------|--------|-----------|--------|
| **Search Speed** | <500ms on 1M LOC | Sub-second search enables interactive agent workflows | LOA_CK_CLI_PROMPT.md:241 |
| **Cache Hit Rate** | 80-90% | Delta indexing avoids full reindex on every change | LOA_CK_CLI_PROMPT.md:242 |
| **Grounding Ratio** | ≥0.95 | 95%+ of claims must have code evidence | LOA_CK_CLI_PROMPT.md:244, LOA_CK_INTEGRATION_PROMPT.md:1474 |
| **User Experience Parity** | 100% | Identical output with/without ck | LOA_CK_CLI_PROMPT.md:240 |
| **Zero User-Facing Errors** | 100% | No error messages when ck missing | LOA_CK_CLI_PROMPT.md:243 |
| **Attention Budget Compliance** | 100% | Tool Result Clearing after >20 results | LOA_CK_CLI_PROMPT.md:245 |

### Success Criteria

**Invisible Operation**:
- ✅ Fresh clone WITHOUT ck: `/ride` completes using grep fallbacks
- ✅ Fresh clone WITH ck: `/ride` completes with enhanced precision
- ✅ Users CANNOT tell which search mode was used
- ✅ Agent never mentions "ck", "semantic search", "grep", or "fallback"

**Source**: LOA_CK_CLI_PROMPT.md:232-237

**Grounding & Evidence**:
- ✅ Word-for-word code quotes in all citations
- ✅ Absolute paths (never relative)
- ✅ Ghost Features tracked in Beads
- ✅ Three test scenarios per architectural decision (EDD)

**Source**: LOA_CK_CLI_PROMPT.md:248-254

---

## Phase 3: User & Stakeholder Context

### Primary Stakeholders

1. **Loa Framework Users**
   - **Pain Points**: Slow code discovery, imprecise search results, documentation drift
   - **Needs**: Fast, accurate code analysis without learning new tools
   - **Journey**: Install Loa → (optionally install ck) → Use existing commands → Get better results

2. **Loa Agent Developers (THJ Team)**
   - **Pain Points**: Agent hallucinations, low grounding ratios, context overflow
   - **Needs**: Reliable code evidence chains, auditability, integrity guarantees
   - **Journey**: Build agent skills → Integrate ck search → Log trajectory → Audit reasoning

3. **Open Source Contributors**
   - **Pain Points**: High barrier to contribution, unclear integration patterns
   - **Needs**: Clear documentation, optional enhancements, no mandatory dependencies
   - **Journey**: Clone repo → Read docs → (optionally enhance) → Contribute

**Source**: LOA_CK_INTEGRATION_PROMPT.md:72-94 (Beads Pattern), LOA_CK_INTEGRATION_PROMPT.md:1980-2033 (Success Criteria)

### User Personas

**Persona 1: Enterprise Developer (Primary)**
- **Profile**: Senior engineer at fintech/crypto company using Loa for codebase analysis
- **Goal**: Understand legacy codebases quickly and accurately
- **Frustration**: grep returns hundreds of false positives, wastes time
- **Win State**: `/ride` returns precise, semantically relevant code locations

**Persona 2: Indie Developer (Secondary)**
- **Profile**: Solo developer using Loa for personal projects
- **Goal**: Fast setup, minimal dependencies, good enough results
- **Frustration**: Installation complexity, mandatory tooling
- **Win State**: Loa works out-of-box, ck is nice-to-have

**Source**: Inferred from LOA_CK_INTEGRATION_PROMPT.md:190-310 (Installation Strategy)

---

## Phase 4: Functional Requirements

### FR-1: Installation & Setup

**FR-1.1**: List ck as optional enhancement in INSTALLATION.md
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:70-74, LOA_CK_INTEGRATION_PROMPT.md:190-227

**User Story**:
```
As a Loa user
I want to see ck listed as an optional enhancement
So that I can decide whether to install it
```

**Acceptance Criteria**:
- [ ] INSTALLATION.md has "Optional Enhancements" section
- [ ] ck listed with cargo install instructions
- [ ] Benefits clearly stated (semantic search, 80-90% faster context loading)
- [ ] Explicitly states: "Without ck: All commands work normally using grep fallbacks"

---

**FR-1.2**: Check ck status during `/setup`
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:71, LOA_CK_INTEGRATION_PROMPT.md:229-281

**User Story**:
```
As a Loa user running /setup
I want to see whether ck is installed
So that I know if enhanced search is available
```

**Acceptance Criteria**:
- [ ] `/setup` checks `command -v ck`
- [ ] Displays: "✓ ck installed: <version>" or "○ ck not installed (optional)"
- [ ] Shows install command if missing: `cargo install ck-search`
- [ ] NEVER blocks setup if ck missing
- [ ] Setup completion message varies based on what's installed:
  - Both tools: "Setup complete with full enhancement suite"
  - Only ck: "Setup complete with semantic search"
  - Only beads: "Setup complete with task tracking"
  - Neither: "Setup complete. For enhanced capabilities, see INSTALLATION.md"

---

**FR-1.3**: Update .gitignore for ck state
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:74, LOA_CK_INTEGRATION_PROMPT.md:312-323

**Technical Requirement**:
```gitignore
# Loa Framework
.beads/
.ck/
loa-grimoire/a2a/trajectory/
```

**Rationale**: `.ck/` contains cached embeddings and search indexes that are:
- Large (hundreds of MB for big codebases)
- Machine-specific (absolute paths)
- Rebuild automatically (self-healing)
- Never committed to version control

---

### FR-2: Pre-Flight Integrity Checks

**FR-2.1**: Create pre-flight integrity protocol
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:76-82, LOA_CK_INTEGRATION_PROMPT.md:325-508

**User Story**:
```
As a Loa agent
I want to verify System Zone integrity before any ck operation
So that I never operate on compromised or modified framework files
```

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/preflight-integrity.md`
- [ ] Checks `.claude/checksums.json` against actual file hashes
- [ ] Respects `integrity_enforcement` setting in `.loa.config.yaml`:
  - `strict`: HALT execution on drift, require `/update`
  - `warn`: Log warning, proceed with caution
  - `disabled`: No integrity checks
- [ ] Self-healing State Zone: If `.ck/` missing → trigger silent reindex (never fail)
- [ ] Version pinning: Verify ck version matches `.loa-version.json` requirement
- [ ] Binary integrity: Verify ck SHA-256 fingerprint (if available)
- [ ] Never surfaces integrity status to user unless explicitly asked

**Technical Specification**:
```bash
# Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Check enforcement level
ENFORCEMENT=$(grep "integrity_enforcement:" "${PROJECT_ROOT}/.loa.config.yaml" | awk '{print $2}' || echo "warn")

# Verify checksums
if [[ -f "${PROJECT_ROOT}/.claude/checksums.json" ]]; then
    # Compare expected vs actual hashes
    # HALT if enforcement=strict and drift detected
fi
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:342-387

---

**FR-2.2**: Synthesis Protection via overrides
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:213-219, LOA_CK_INTEGRATION_PROMPT.md:389-419

**User Story**:
```
As a Loa user
I want to customize ck settings without editing framework files
So that my customizations survive framework updates
```

**Acceptance Criteria**:
- [ ] Directory created: `.claude/overrides/`
- [ ] User can create `.claude/overrides/ck-config.yaml` for custom settings
- [ ] Configuration precedence enforced:
  1. `.claude/overrides/ck-config.yaml` (highest priority)
  2. `.loa.config.yaml`
  3. `.claude/mcp-registry.yaml` (framework defaults)
- [ ] Users NEVER edit `.claude/` files directly (except `.claude/overrides/`)
- [ ] Documentation clearly states what can/cannot be overridden

**Customization Example**:
```yaml
# .claude/overrides/ck-config.yaml
ck:
  model: "jina-code"  # Override default nomic-v1.5
  thresholds:
    semantic: 0.5      # Stricter than default 0.4
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1899-1976

---

### FR-3: Seamless /ride Integration

**FR-3.1**: Dual-path search in /ride command
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:83-91, LOA_CK_INTEGRATION_PROMPT.md:512-917

**User Story**:
```
As a Loa agent running /ride
I want to automatically use the best available search tool
So that code analysis is optimal regardless of user's setup
```

**Acceptance Criteria**:
- [ ] `/ride` command updated: `.claude/commands/ride.md`
- [ ] Search strategy detection at start of command:
  ```bash
  if command -v ck >/dev/null 2>&1; then
      SEARCH_MODE="semantic"
  else
      SEARCH_MODE="grep"
  fi
  ```
- [ ] For each discovery phase, implement both paths:
  - **Phase A (Entry Points)**: ck hybrid vs grep for main/def/fn patterns
  - **Phase B (Abstractions)**: ck hybrid vs grep for class/interface/trait
  - **Phase C (Ghost Features)**: ck semantic (negative grounding) vs grep + manual review
  - **Phase D (Shadow Systems)**: ck regex vs grep for exports
- [ ] Output format IDENTICAL regardless of search mode
- [ ] Agent NEVER mentions which mode was used

**Technical Specification - Entry Point Discovery**:
```bash
# With ck (using absolute paths and JSONL)
ck --hybrid "main entry point bootstrap initialize startup" \
    --path "${PROJECT_ROOT}/src/" \
    --top-k 10 \
    --threshold 0.5 \
    --jsonl

# Fallback (grep with absolute paths)
grep -rn "function main\|def main\|fn main" \
  --include="*.js" --include="*.ts" --include="*.py" \
  "${PROJECT_ROOT}/src/" 2>/dev/null | head -20
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:628-685

---

**FR-3.2**: Ghost Feature Detection with Negative Grounding
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:98-105, LOA_CK_INTEGRATION_PROMPT.md:1323-1378

**User Story**:
```
As a Loa agent
I want to reliably detect features documented in PRD but missing from code
So that I can flag them as Strategic Liabilities for the user
```

**Acceptance Criteria**:
- [ ] Requires TWO diverse semantic queries, both returning 0 results
- [ ] Query 1: Functional description (e.g., "OAuth2 SSO login flow")
- [ ] Query 2: Architectural synonym (e.g., "single sign-on identity provider")
- [ ] Both queries use threshold 0.4
- [ ] Only flag GHOST if BOTH return 0 results
- [ ] High Ambiguity check: If 0 code results BUT >3 doc mentions → flag for human audit
- [ ] Track in Beads: `bd create "GHOST: <feature>" --type liability --priority 2`
- [ ] Log to trajectory with beads_id

**Classification Table**:
| Code Results | Doc Mentions | Classification | Action |
|--------------|--------------|----------------|--------|
| 0 | 0-2 | CONFIRMED GHOST | Track in Beads, remove from docs |
| 0 | 3+ | HIGH AMBIGUITY | Request human audit |
| 1+ | Any | NOT GHOST | Feature exists, verify alignment |

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1323-1378 (Negative Grounding Protocol)

---

**FR-3.3**: Shadow System Detection with Classification
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:98-105, LOA_CK_INTEGRATION_PROMPT.md:748-846

**User Story**:
```
As a Loa agent
I want to identify undocumented code in the codebase
So that I can classify it as Orphaned, Drifted, or Partial coverage
```

**Acceptance Criteria**:
- [ ] Use regex search to find all exports: `export|module.exports|pub fn`
- [ ] Cross-reference against PRD/SDD and `loa-grimoire/legacy/INVENTORY.md`
- [ ] For each undocumented export, classify by semantic similarity to docs:
  - **Orphaned** (<0.3 similarity): HIGH risk, no doc match, urgent documentation required
  - **Drifted** (>0.5 similarity): MEDIUM risk, docs exist but outdated
  - **Partial** (0.3-0.5 similarity): LOW risk, incomplete documentation
- [ ] Generate Dependency Trace for Orphaned systems (import graph)
- [ ] Track in Beads with classification: `bd create "SHADOW (orphaned): <module>" --type debt`
- [ ] Write to `loa-grimoire/reality/drift-report.md`

**Dependency Trace (mandatory for Orphaned)**:
```bash
# Find all files that import the undocumented module
ck --regex "import.*<module_name>|require.*<module_name>" --path src/ --jsonl
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:766-846

---

**FR-3.4**: Drift Report Evolution (Auto-Resolution)
**Priority**: P1 (High)
**Source**: LOA_CK_INTEGRATION_PROMPT.md:848-898

**User Story**:
```
As a Loa agent running /ride or /update
I want to automatically move resolved items to the "Resolved" section
So that the drift report stays current without manual intervention
```

**Acceptance Criteria**:
- [ ] Re-scan all Ghost Features with Negative Grounding
- [ ] If code now found (score >0.6): Move to "Resolved" as "Ghost→Implemented"
- [ ] Re-scan all Shadow Systems for documentation matches
- [ ] If docs now found (score >0.5): Move to "Resolved" as "Shadow→Documented"
- [ ] Close associated Beads tickets with resolution note
- [ ] Update "Last Updated" timestamp in drift-report.md

**Drift Report Structure**:
```markdown
## Strategic Liabilities (Ghost Features)
| Feature | Doc Source | Search Evidence | Ambiguity | Beads ID |

## Technical Debt (Shadow Systems)
| Module | Location | Classification | Dependents | Beads ID |

## Verified Features
| Feature | Documentation | Code Location | Confidence |

## Resolved (Auto-Updated)
| Item | Type | Resolution Date | Evidence |
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:848-898

---

### FR-4: Tool Result Clearing (Context Management)

**FR-4.1**: Create Tool Result Clearing protocol
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:91-97, LOA_CK_INTEGRATION_PROMPT.md:919-1050

**Problem Statement**: As token counts increase, model recall accuracy decreases. A ck search returning thousands of tokens overwhelms agent attention budgets and degrades synthesis quality.

**User Story**:
```
As a Loa agent
I want to clear raw search results after extracting high-signal findings
So that I maintain attention budget for high-level reasoning
```

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/tool-result-clearing.md`
- [ ] After EVERY search returning >20 results:
  1. Extract high-signal findings (max 10 files, 20 words each)
  2. Synthesize to NOTES.md with file:line references
  3. Clear raw output from working memory
  4. Keep only single-line summary
- [ ] Enforce attention budgets:
  - Single search: 2,000 tokens max
  - Accumulated results: 5,000 tokens → mandatory clearing
  - Full file loads: 3,000 tokens → single file only
  - Session total: 15,000 tokens → stop and synthesize
- [ ] Never keep raw search results in working memory
- [ ] Never pass raw results to subsequent operations

**Before/After Comparison**:
```
WITHOUT CLEARING:
Context: [2000 tokens raw results] + [task context]
Result: Model struggles, hallucinates, misses connections

WITH CLEARING:
Context: [50 tokens synthesis] + [task context]
Result: Model performs high-level reasoning clearly
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:919-1050

---

**FR-4.2**: Semantic Decay Protocol (Long Sessions)
**Priority**: P1 (High)
**Source**: LOA_CK_CLI_PROMPT.md:301-335, LOA_CK_INTEGRATION_PROMPT.md:1007-1050

**User Story**:
```
As a Loa agent in a long-running session
I want to progressively decay older search results to lightweight identifiers
So that I can rehydrate context on-demand while freeing attention budget
```

**Acceptance Criteria**:
- [ ] Implement three decay stages:
  - **Active (0-5 min)**: Full synthesis with code snippets in NOTES.md
  - **Decayed (5-30 min)**: Absolute paths only as "lightweight identifiers"
  - **Archived (30+ min)**: Single-line summary in trajectory log
- [ ] Paths can be rehydrated via JIT retrieval if needed
- [ ] Decay workflow:
  1. Initially: Full synthesis with snippets in active context
  2. After 5 min: Decay to paths-only (12 tokens per file)
  3. After 30 min: Archive to trajectory, single-line summary

**Example Decay**:
```
ACTIVE (0-5 min):
"JWT validation: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"

DECAYED (5-30 min):
"/abs/path/src/auth/jwt.ts:45"  (lightweight identifier, 12 tokens)

ARCHIVED (30+ min):
"Auth module analyzed: 3 files, 2 patterns found" (trajectory only)
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1007-1050

---

### FR-5: Trajectory Logging (Reasoning Audit)

**FR-5.1**: Intent-First Search Protocol (Reasoning-Before-Search)
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:106-114, LOA_CK_INTEGRATION_PROMPT.md:1277-1323

**User Story**:
```
As a Loa agent
I want to document reasoning BEFORE performing any search
So that I prevent "fishing expeditions" that waste tokens
```

**Acceptance Criteria**:
- [ ] BEFORE every search, log three required elements:
  1. **Intent**: What are we looking for?
  2. **Rationale**: Why do we need this for the current task?
  3. **Expected Outcome**: What do we expect to find?
- [ ] HALT if expected_outcome cannot be articulated
- [ ] Log to trajectory BEFORE executing search
- [ ] Validate results against expected_outcome after search
- [ ] If unexpected results → log discrepancy and reassess rationale

**Anti-Fishing Expedition Rules**:
| Scenario | Action |
|----------|--------|
| Search returns unexpected results | Log discrepancy, reassess rationale |
| Search returns 0 results | Reformulate query OR flag as Ghost Feature |
| Search returns >50 results | LOG TRAJECTORY PIVOT, then narrow |
| No clear expected_outcome | STOP - clarify reasoning before searching |

**XML Format for Agents**:
```xml
<search_execution>
  <intent>Find JWT authentication entry points</intent>
  <rationale>Task requires extending auth; need patterns first</rationale>
  <expected_outcome>Should find 1-3 token validation functions</expected_outcome>
  <query>hybrid_search("JWT token validation authentication")</query>
  <path>${PROJECT_ROOT}/src/auth/</path>
</search_execution>
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1277-1323

---

**FR-5.2**: Trajectory Pivot for >50 Results
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:117-125, LOA_CK_INTEGRATION_PROMPT.md:1302-1323

**User Story**:
```
As a Loa agent
When my search returns >50 results
I want to log why my hypothesis failed before narrowing
So that I learn from search failures and avoid repeated mistakes
```

**Acceptance Criteria**:
- [ ] If search returns >50 results → MANDATORY trajectory pivot log
- [ ] Log structure must include:
  - `original_query`: What we tried
  - `result_count`: How many results
  - `hypothesis_failure`: Why query was too broad
  - `refined_hypothesis`: How we're targeting better
  - `new_query`: Improved query string
- [ ] Agent must NOT just narrow and re-search without logging pivot
- [ ] Pivot log enables auditing of agent reasoning evolution

**Example Trajectory Pivot**:
```jsonl
{
  "ts": "2024-01-15T10:30:00Z",
  "agent": "implementing-tasks",
  "phase": "pivot",
  "reason": "Initial query too broad",
  "original_query": "authentication",
  "result_count": 127,
  "hypothesis_failure": "Query captured all auth-related code, not just entry points",
  "refined_hypothesis": "Need to target initialization patterns specifically",
  "new_query": "auth initialization bootstrap startup"
}
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1306-1323

---

**FR-5.3**: Word-for-Word Citations (Mandatory)
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:26-30, LOA_CK_INTEGRATION_PROMPT.md:1386-1420

**User Story**:
```
As a reviewing-code agent
I want every claim to include actual code quotes with absolute paths
So that I can verify evidence without re-searching
```

**Acceptance Criteria**:
- [ ] Every architectural claim must include exact code snippet
- [ ] Citation format: `"<claim>: <code_quote> [<absolute_path>:<line>]"`
- [ ] INSUFFICIENT: File:line reference only (will be rejected)
- [ ] REQUIRED: Word-for-word code quote
- [ ] All paths must be absolute (never relative)
- [ ] Log citations to trajectory in "cite" phase

**Format Comparison**:
```markdown
❌ INSUFFICIENT (reference only):
"The system uses JWT [src/auth/jwt.ts:45]"

✅ REQUIRED (word-for-word quote):
"The system uses JWT: `export async function validateToken(token: string)` [/home/user/project/src/auth/jwt.ts:45]"
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1386-1420

---

**FR-5.4**: Self-Audit Checkpoint (Completion Gate)
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:152-167, LOA_CK_INTEGRATION_PROMPT.md:1542-1629

**User Story**:
```
As a Loa agent completing /ride or /translate
I want to execute a mandatory self-audit before finishing
So that I ensure grounding ratio ≥0.95 and all claims have evidence
```

**Acceptance Criteria**:
- [ ] BEFORE completing ANY task, execute self-audit checklist:
  - [ ] Grounding ratio ≥ 0.95 (95%+ claims have evidence)
  - [ ] Zero unflagged [ASSUMPTION] claims
  - [ ] All citations have word-for-word quotes
  - [ ] All paths are absolute (${PROJECT_ROOT}/...)
  - [ ] Ghost Features tracked in Beads
  - [ ] Shadow Systems documented in drift-report.md
  - [ ] Evidence chain complete for all major conclusions
- [ ] If ANY checkbox fails → REMEDIATE before completion
- [ ] Calculate grounding ratio: `grounded_decisions / total_decisions`
- [ ] Load trajectory log to verify evidence chains
- [ ] DO NOT complete task if self-audit fails

**Claim Classification**:
```markdown
GROUNDED: "Uses JWT: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"
ASSUMPTION: "Likely caches tokens [ASSUMPTION: needs verification]"
GHOST: "OAuth2 SSO [GHOST: PRD §3.2, 0 search results]"
SHADOW: "Legacy hasher: `function hashLegacy()` [SHADOW: /abs/path/src/auth/legacy.ts, undocumented]"
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1542-1629

---

**FR-5.5**: EDD Verification (Three Test Scenarios)
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:145-150, LOA_CK_INTEGRATION_PROMPT.md:1492-1527

**User Story**:
```
As a Loa agent making an architectural decision
I want to verify three test scenarios before completing
So that I ensure my understanding of the code is correct
```

**Acceptance Criteria**:
- [ ] Every architectural decision informed by ck must have 3 test scenarios
- [ ] Scenarios must cover:
  1. **Happy Path**: Typical input and expected behavior
  2. **Edge Case**: Boundary condition handling
  3. **Error Handling**: Invalid input and error behavior
- [ ] Each scenario verified against found code
- [ ] Word-for-word evidence cited for each scenario
- [ ] No [ASSUMPTION] flags remaining before completion

**Example EDD Structure**:
```markdown
## Decision: Implement auth using existing JWT module

### Evidence Chain
- SEARCH: hybrid_search("JWT validation") @ 10:30:00
- RESULT: src/auth/jwt.ts:45 (score: 0.89)
- CITATION: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]

### Test Scenarios

**Scenario 1: Happy Path**
- Input: Valid JWT token
- Expected: Token validated, payload returned
- Verified: ✓

**Scenario 2: Edge Case**
- Input: Expired token
- Expected: ValidationError thrown
- Verified: ✓

**Scenario 3: Error Handling**
- Input: Malformed token
- Expected: ParseError thrown
- Verified: ✓
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1492-1527

---

### FR-6: Technical Specifications

**FR-6.1**: MCP Registry with Zod-Compatible Schemas
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:175-179, LOA_CK_INTEGRATION_PROMPT.md:1636-1747

**User Story**:
```
As a Loa framework
I want to define strict schemas for ck MCP tools
So that malformed arguments are rejected before execution
```

**Acceptance Criteria**:
- [ ] Create `.claude/mcp-registry.yaml` (only if ck is installed)
- [ ] Use `strict: true` to enforce schema validation
- [ ] Use `additionalProperties: false` to reject unknown properties
- [ ] Define three primary tools:
  1. **semantic_search**: Find code by meaning using embeddings
  2. **hybrid_search**: Combined semantic + keyword (RRF)
  3. **regex_search**: Traditional grep-style patterns
- [ ] All schemas include:
  - `minLength`, `maxLength` constraints
  - `minimum`, `maximum` for numbers
  - `pattern` regex for paths
  - `required` fields array
- [ ] Output format: `jsonl` (streaming-friendly)

**Example Schema (semantic_search)**:
```yaml
semantic_search:
  description: "Find code by meaning using embeddings"
  strict: true
  input_schema:
    type: object
    additionalProperties: false
    properties:
      query:
        type: string
        minLength: 3
        maxLength: 500
      path:
        type: string
        default: "."
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
    required: ["query"]
  output_format: "jsonl"
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1636-1747

---

**FR-6.2**: JSONL Output with Failure-Aware Parsing
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:31-35, LOA_CK_INTEGRATION_PROMPT.md:1748-1811

**User Story**:
```
As a Loa agent
When a single line in JSONL output is malformed
I want to drop that line and continue (never crash)
So that one parse error doesn't destroy the entire search operation
```

**Acceptance Criteria**:
- [ ] All ck commands use `--jsonl` flag for output
- [ ] Agent parses JSONL line-by-line
- [ ] If single line malformed → DROP that result, CONTINUE
- [ ] Log dropped lines to trajectory with:
  - `line`: Line number
  - `error`: Parse error message
  - `data_loss_ratio`: parse_errors / total_lines
- [ ] Never crash the entire turn on malformed JSONL
- [ ] Trajectory audit trail shows all data loss events

**Failure-Aware Parsing Pseudocode**:
```python
for line_num, line in enumerate(jsonl_stream):
    try:
        result = json.loads(line)
        # Process result
    except json.JSONDecodeError as e:
        # DROP malformed line, CONTINUE
        parse_errors += 1
        dropped_lines.append({"line": line_num, "error": str(e)})
        continue  # DO NOT CRASH

# Log dropped lines to trajectory (audit trail)
if parse_errors > 0:
    trajectory_log.append({
        "phase": "jsonl_parse",
        "parse_errors": parse_errors,
        "dropped_lines": dropped_lines,
        "data_loss_ratio": parse_errors / total_processed
    })
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1748-1811

---

**FR-6.3**: Managed Pagination Protocol
**Priority**: P1 (High)
**Source**: LOA_CK_CLI_PROMPT.md:180, LOA_CK_INTEGRATION_PROMPT.md:1813-1868

**User Story**:
```
As a Loa agent
When a search returns many results
I want to paginate through them intelligently
So that I stop when sufficient high-signal results are found
```

**Acceptance Criteria**:
- [ ] Initial request specifies: `top_k` (total desired), `page_size` (per page)
- [ ] Response includes pagination cursor: `{"cursor": "...", "has_more": true}`
- [ ] Agent evaluates after each page:
  1. If sufficient high-signal results found → STOP, synthesize
  2. If insufficient → Continue to next page
  3. If 3 pages without high-signal → Reformulate query
- [ ] Never paginate beyond 5 pages (50 results) without synthesis
- [ ] Agent language: "Retrieving additional high-signal evidence" (not "paginating")

**Pagination Flow**:
```bash
# Initial request
semantic_search(
  query: "authentication",
  top_k: 100,      # Total desired
  page_size: 10    # Per-page limit
)

# Response structure
{
  "results": [...],  // 10 items
  "pagination": {
    "cursor": "eyJvZmZzZXQiOjEwfQ==",
    "has_more": true,
    "total_available": 47
  }
}

# Continuation (if needed)
semantic_search(
  query: "authentication",
  cursor: "eyJvZmZzZXQiOjEwfQ=="
)
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1813-1868

---

**FR-6.4**: Absolute Filepath Mandate
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:20-24, LOA_CK_INTEGRATION_PROMPT.md:44-56

**Rationale**: Models frequently struggle with relative paths after navigating directories.

**User Story**:
```
As a Loa agent
I want to always use absolute paths in ck commands
So that searches work reliably regardless of current working directory
```

**Acceptance Criteria**:
- [ ] ALL ck commands use absolute paths
- [ ] Setup: `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)`
- [ ] All searches use: `--path "${PROJECT_ROOT}/src/"` (not `src/`)
- [ ] All citations use absolute paths in output
- [ ] Self-audit checks: "All paths are absolute"

**Format Comparison**:
```bash
❌ BAD (relative path, error-prone after cd):
ck --hybrid "authentication" src/

✅ GOOD (absolute path, reliable):
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ck --hybrid "authentication" "${PROJECT_ROOT}/src/" --jsonl
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:44-56

---

### FR-7: Skill Integration (Internal Enhancement)

**FR-7.1**: Enhanced implementing-tasks Skill
**Priority**: P1 (High)
**Source**: LOA_CK_CLI_PROMPT.md:287-293, LOA_CK_INTEGRATION_PROMPT.md:1127-1214

**User Story**:
```
As the implementing-tasks agent
I want to use ck for context loading before writing code
So that I understand existing patterns and avoid duplicating logic
```

**Acceptance Criteria**:
- [ ] Update `.claude/skills/implementing-tasks/context-retrieval.md`
- [ ] Before writing ANY code, load relevant context
- [ ] Search strategy:
  1. Find related code: semantic_search("<task_description>")
  2. Find similar patterns: hybrid_search("<pattern_to_find>")
- [ ] Apply Tool Result Clearing after heavy searches
- [ ] Log context load to NOTES.md with format:
  ```markdown
  ## Context Load: <timestamp>
  **Task**: <task_id>
  **Key Files**:
  - `src/auth/handler.ts:45-67` - Primary implementation
  **Patterns Found**: <brief description>
  **Ready to implement**: Yes/No
  ```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1133-1214

---

**FR-7.2**: Enhanced reviewing-code Skill
**Priority**: P1 (High)
**Source**: LOA_CK_INTEGRATION_PROMPT.md:1216-1265

**User Story**:
```
As the reviewing-code agent
I want to use ck for impact analysis before reviewing
So that I understand the full impact radius of code changes
```

**Acceptance Criteria**:
- [ ] Update `.claude/skills/reviewing-code/impact-analysis.md`
- [ ] Before reviewing, find:
  1. **Dependents**: Search for imports of changed modules
  2. **Tests**: Find test files covering changed functions
- [ ] Review checklist:
  - [ ] Found related code (search completed)
  - [ ] Test coverage verified
  - [ ] Pattern consistency checked
  - [ ] Claims cite [file:line] sources

**Technical Specification - Find Dependents**:
```bash
# With ck
semantic_search(
  query: "imports <changed_module> uses <changed_function>",
  path: "src/",
  top_k: 50
)

# Fallback
grep -rn "import.*<module>\|from.*<module>\|require.*<module>" src/
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1216-1265

---

### FR-8: Agent Chaining (Next Step Automation)

**FR-8.1**: Automatic next-agent suggestion after command completion
**Priority**: P1 (High)
**Source**: GitHub Issue #9 (CubQuests Sprint 1 Complete)

**User Story**:
```
As a Loa user completing a phase
I want the agent to suggest (and optionally launch) the next logical step
So that I can maintain workflow momentum without manual command lookup
```

**Acceptance Criteria**:
- [ ] Each agent knows its position in the workflow chain
- [ ] On successful completion, agent suggests next command with clear call-to-action
- [ ] User can accept (launch next agent) or decline (end session)
- [ ] Workflow chain defined:
  1. `/plan-and-analyze` → suggests `/architect`
  2. `/architect` → suggests `/sprint-plan`
  3. `/sprint-plan` → suggests `/implement sprint-1`
  4. `/implement sprint-N` → suggests `/review-sprint sprint-N`
  5. `/review-sprint sprint-N` → suggests `/audit-sprint sprint-N` OR `/implement sprint-N` (if feedback)
  6. `/audit-sprint sprint-N` → suggests `/implement sprint-N+1` (if approved) OR `/implement sprint-N` (if changes required)
- [ ] Suggestion format:
  ```markdown
  ## Next Step

  Ready for architectural design.

  **Recommended**: `/architect`

  Would you like to proceed?
  ```

**Technical Specification**:
```yaml
# .claude/workflow-chain.yaml
workflow:
  plan-and-analyze:
    next: architect
    condition: "prd.md exists"
  architect:
    next: sprint-plan
    condition: "sdd.md exists"
  sprint-plan:
    next: "implement sprint-1"
    condition: "sprint.md exists"
  implement:
    next: "review-sprint {sprint}"
    condition: "reviewer.md exists"
  review-sprint:
    next_on_approval: "audit-sprint {sprint}"
    next_on_feedback: "implement {sprint}"
    condition: "engineer-feedback.md content"
  audit-sprint:
    next_on_approval: "implement sprint-{N+1}"
    next_on_changes: "implement {sprint}"
    condition: "auditor-sprint-feedback.md content"
```

---

### FR-9: Context Pollution Prevention

**FR-9.1**: Configurable watch paths for drift detection
**Priority**: P1 (High)
**Source**: GitHub Issue #10 (Drift detection blind spots)

**Problem Statement**: `/ride` focuses on standard directories (`.claude/`, `library/`) but misses custom workflow directories like `.meta/` that users may have.

**User Story**:
```
As a Loa user with custom directory structures
I want to configure which directories are watched for drift
So that all my important files are included in drift detection
```

**Acceptance Criteria**:
- [ ] `.loa.config.yaml` supports `watch_paths` configuration
- [ ] Default paths include standard Loa directories
- [ ] User can add custom paths without editing framework files
- [ ] `/ride` uses configured watch paths for drift detection
- [ ] Git status changes in watched paths are flagged in drift report

**Configuration Example**:
```yaml
# .loa.config.yaml
drift_detection:
  watch_paths:
    - ".claude/"
    - "loa-grimoire/"
    - ".meta/"           # Custom user directory
    - "docs/architecture/"
  exclude_patterns:
    - "**/node_modules/**"
    - "**/*.log"
```

---

**FR-9.2**: Session artifact filtering (signal markers)
**Priority**: P1 (High)
**Source**: GitHub Issue #10 (Context pollution from session artifacts)

**Problem Statement**: Repos accumulate low-signal documents (brainstorm notes, old session artifacts, meeting transcripts) that pollute grep results and consume context window.

**User Story**:
```
As a Loa agent
I want to filter out low-signal documents from search results
So that I maintain focus on high-signal architectural content
```

**Acceptance Criteria**:
- [ ] Support frontmatter signal markers: `signal: high|medium|low`
- [ ] Default exclude patterns for session artifacts configured in `.loa.config.yaml`
- [ ] Archive zone: `loa-grimoire/archive/` explicitly excluded from search
- [ ] Search commands respect signal filtering
- [ ] Agent can override filtering when explicitly needed

**Implementation Options** (all to be supported):

| Approach | Implementation |
|----------|----------------|
| **Signal markers** | Frontmatter `signal: high/medium/low` to filter grep/ck results |
| **Archive zone** | `loa-grimoire/archive/` excluded from all searches |
| **Grep excludes** | Default exclude patterns for session artifacts |
| **TTL on drafts** | Auto-archive marker for drafts older than configurable days |

**Frontmatter Example**:
```markdown
---
signal: low
type: brainstorm
date: 2024-01-15
---

# Brainstorm Session Notes
...
```

**Configuration Example**:
```yaml
# .loa.config.yaml
context_filtering:
  archive_zone: "loa-grimoire/archive/"
  default_excludes:
    - "**/brainstorm-*.md"
    - "**/session-notes-*.md"
    - "**/meeting-*.md"
    - "**/draft-*.md"
  signal_threshold: "medium"  # Exclude 'low' signal by default
  draft_ttl_days: 30          # Auto-suggest archival after 30 days
```

**Search Integration**:
```bash
# With ck (respects excludes)
ck --hybrid "authentication" \
    --path "${PROJECT_ROOT}/src/" \
    --exclude "loa-grimoire/archive/" \
    --exclude "**/brainstorm-*.md" \
    --jsonl

# Fallback grep (respects excludes)
grep -rn "authentication" \
    --exclude-dir="archive" \
    --exclude="brainstorm-*.md" \
    "${PROJECT_ROOT}/src/"
```

---

### FR-10: Command Namespace Protection

**FR-10.1**: Protect Claude Code built-in commands from conflicts
**Priority**: P0 (Blocker)
**Source**: GitHub Issue #11 (Slash command /config conflicts with Claude Code built-in)

**Problem Statement**: The custom `/config` slash command in Loa conflicts with Claude Code's built-in `/config` command. When users try to access Claude Code's native config functionality, the Loa command intercepts it instead.

**User Story**:
```
As a Loa user
I want Loa commands to never conflict with Claude Code built-ins
So that I can access both Claude Code features and Loa commands
```

**Acceptance Criteria**:
- [ ] Maintain list of Claude Code reserved commands (enshrined/protected)
- [ ] Pre-flight check during `/setup` validates no conflicts
- [ ] Conflicting commands auto-renamed with `-loa` suffix
- [ ] Documentation clearly lists reserved command names
- [ ] CI validation script checks for conflicts

**Reserved Command List** (Claude Code built-ins):
```yaml
# .claude/reserved-commands.yaml
reserved:
  - config      # Claude Code settings
  - help        # Claude Code help
  - clear       # Clear conversation
  - compact     # Compact context
  - cost        # Show cost
  - doctor      # Diagnostics
  - init        # Initialize project
  - login       # Authentication
  - logout      # Sign out
  - memory      # Memory management
  - model       # Model selection
  - pr-comments # PR review
  - review      # Code review
  - terminal-setup # Terminal config
  - vim         # Vim mode
  # Add new Claude Code commands as they're released
```

**Conflict Resolution Strategy**:
```
IF command_name IN reserved_commands:
    renamed_command = f"{command_name}-loa"
    WARN user: "Command /{command_name} conflicts with Claude Code built-in"
    WARN user: "Renamed to /{renamed_command}"
    CREATE .claude/commands/{renamed_command}.md
    DELETE .claude/commands/{command_name}.md (if exists)
```

**Current Conflicts to Resolve**:
| Loa Command | Conflict | Resolution |
|-------------|----------|------------|
| `/config` | Claude Code `/config` | Rename to `/config-loa` or `/mcp-config` |

**Validation Script**:
```bash
# .claude/scripts/validate-commands.sh
#!/bin/bash

RESERVED=(config help clear compact cost doctor init login logout memory model pr-comments review terminal-setup vim)

for cmd_file in .claude/commands/*.md; do
    cmd_name=$(basename "$cmd_file" .md)
    for reserved in "${RESERVED[@]}"; do
        if [[ "$cmd_name" == "$reserved" ]]; then
            echo "ERROR: /$cmd_name conflicts with Claude Code built-in"
            echo "ACTION: Rename to /${cmd_name}-loa"
            exit 1
        fi
    done
done
echo "✓ No command conflicts detected"
```

**Pre-flight Integration**:
- [ ] Add to `.claude/scripts/preflight.sh`
- [ ] Run during `/setup` and `/update`
- [ ] Block synthesis if conflicts detected
- [ ] Suggest resolution commands

---

### FR-11: Graceful Fallback Protocol

**FR-11.1**: Create search fallback protocol
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:83-91, LOA_CK_INTEGRATION_PROMPT.md:1052-1111

**User Story**:
```
As a Loa agent
When ck is not installed
I want to silently fall back to grep
So that users experience no functionality loss
```

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/search-fallback.md`
- [ ] Detection runs once per session: `command -v ck >/dev/null 2>&1`
- [ ] Tool Selection Matrix implemented:
  | Task | ck Available | ck Unavailable |
  |------|--------------|----------------|
  | Find entry points | semantic_search("main") | grep "main\|bootstrap" |
  | Find patterns | semantic_search("<concept>") | grep "<keywords>" |
  | Ghost detection | Search + threshold | grep + manual review |
  | Shadow detection | regex_search(exports) | grep + cross-reference |
- [ ] Quality indicators logged to trajectory (internal only):
  - ck: `{"search_mode": "ck", "precision": "high", "cache_hit": true}`
  - grep: `{"search_mode": "grep", "precision": "medium"}`
- [ ] Communication guidelines enforced:
  - ❌ NEVER SAY: "Using ck...", "Falling back to grep..."
  - ✅ ALWAYS SAY: "Analyzing codebase...", "Searching for patterns..."

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1052-1111

---

**FR-11.2**: No User-Facing /ck Command
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:189-200, LOA_CK_INTEGRATION_PROMPT.md:1112-1124

**Rationale**: Unlike some tools, ck should have NO user-facing slash commands. ck is purely internal tooling.

**User Story**:
```
As a Loa user
I want to use existing commands like /ride
And get better results when ck is installed
Without needing to learn any new commands
```

**Acceptance Criteria**:
- [ ] DO NOT create `.claude/commands/ck.md`
- [ ] ck used internally by:
  - `/ride` - Code Reality Extraction
  - `/implement` - Context loading
  - `/review-sprint` - Finding related code
  - `/architect` - Understanding patterns
- [ ] Users interact with existing commands
- [ ] ck silently improves quality

**Source**: LOA_CK_INTEGRATION_PROMPT.md:1112-1124

---

## Phase 5: Technical & Non-Functional Requirements

### NFR-1: Performance

**NFR-1.1**: Search speed < 500ms on 1M LOC
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:241

**Requirement**: ck semantic search must complete in under 500 milliseconds on codebases up to 1 million lines of code.

**Rationale**: Sub-second search enables interactive agent workflows without user-perceptible delays.

**Validation**: Benchmark ck search on large open-source repositories (Linux kernel, Chromium, etc.)

---

**NFR-1.2**: Cache hit rate 80-90%
**Priority**: P1 (High)
**Source**: LOA_CK_CLI_PROMPT.md:242

**Requirement**: Delta-indexed embeddings must achieve 80-90% cache hit rate on typical development workflows.

**Rationale**: Avoids full reindex on every code change, dramatically improving agent responsiveness.

**Validation**: Measure cache hit rate over 100 commits in real projects.

---

### NFR-2: Security & Integrity

**NFR-2.1**: Pre-flight integrity checks
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:76-82

**Requirement**: Before ANY ck operation, verify System Zone integrity via checksums.

**Enforcement Levels**:
- `strict`: HALT execution on drift, require `/update`
- `warn`: Log warning, proceed with caution
- `disabled`: No integrity checks

**Rationale**: Prevents operating on compromised or tampered framework files.

**Validation**: Modify `.claude/` file, verify strict mode halts execution.

---

**NFR-2.2**: Binary integrity verification
**Priority**: P1 (High)
**Source**: LOA_CK_INTEGRATION_PROMPT.md:475-501

**Requirement**: Verify ck binary SHA-256 fingerprint before MCP server initialization.

**Rationale**: Elite security - prevents execution of tampered binaries.

**Validation**: Replace ck binary, verify strict mode detects mismatch.

---

### NFR-3: Reliability

**NFR-3.1**: Self-healing State Zone
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:136, LOA_CK_INTEGRATION_PROMPT.md:428-456

**Requirement**: If `.ck/` is missing or corrupted, trigger silent reindex. Never fail operations.

**Rationale**: State Zone must be self-healing, not user-managed.

**Delta-First Strategy**: Prefer delta-update (faster) over full reindex:
```bash
# Check if delta update possible
if [[ -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
    CHANGED_FILES=$(git diff --name-only "$LAST_INDEXED" "$CURRENT_HEAD" | wc -l)
    if [[ "$CHANGED_FILES" -lt 100 ]]; then
        # Fast: Delta reindex
        ck --index "${PROJECT_ROOT}" --delta --quiet 2>/dev/null &
    else
        # Slow: Full reindex
        ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
    fi
fi
```

**Source**: LOA_CK_INTEGRATION_PROMPT.md:428-456

---

**NFR-3.2**: Failure-aware JSONL parsing
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:135

**Requirement**: If single line in JSONL is malformed → DROP that result, CONTINUE (never crash).

**Rationale**: One parse error must never destroy entire search operation.

**Audit Trail**: Log all dropped lines to trajectory for review.

**Validation**: Inject malformed JSONL line, verify agent continues and logs error.

---

### NFR-4: Maintainability

**NFR-4.1**: Synthesis Protection
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:213-219

**Requirement**: Users MUST NOT edit `.claude/` files directly (except `.claude/overrides/`).

**Override Precedence**:
1. `.claude/overrides/*` (user customization) - highest priority
2. `.loa.config.yaml` (project settings)
3. `.claude/*` (framework defaults) - fallback

**Rationale**: Framework files are managed/synthesized. Direct edits will be overwritten on `/update`.

**Validation**: Documentation clearly states what can/cannot be edited.

---

**NFR-4.2**: Framework version pinning
**Priority**: P1 (High)
**Source**: LOA_CK_INTEGRATION_PROMPT.md:460-472

**Requirement**: Verify ck version matches `.loa-version.json` requirement.

**Rationale**: Prevents schema drift between ck versions and framework expectations.

**Validation**: Log warning if installed ck version < required version.

---

### NFR-5: Observability

**NFR-5.1**: Trajectory logging
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:106-114

**Requirement**: Log every search operation to `loa-grimoire/a2a/trajectory/{agent}-{date}.jsonl` with:
- `ts`: ISO timestamp
- `agent`: Agent name
- `phase`: intent|execute|cite|pivot
- `mode`: ck|grep
- `query`: Search query
- `path`: Absolute path searched
- `results`: Result count
- `citations`: Word-for-word code quotes

**Rationale**: Enables self-audit, reviewing-code agent can verify reasoning chains.

**Validation**: Run `/ride`, verify trajectory log has complete reasoning chain.

---

**NFR-5.2**: Grounding ratio tracking
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:244

**Requirement**: Calculate grounding ratio: `grounded_decisions / total_decisions`. Target ≥ 0.95.

**Rationale**: 95%+ of architectural claims must have code evidence, not assumptions.

**Validation**: Self-audit checkpoint verifies ratio before completion.

---

### NFR-6: Usability

**NFR-6.1**: User experience parity
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:240

**Requirement**: Output format must be IDENTICAL regardless of whether ck or grep is used.

**Rationale**: Users should not be able to tell which search mode was active.

**Validation**: Run `/ride` with and without ck, diff outputs (should be semantically equivalent).

---

**NFR-6.2**: Zero user-facing errors
**Priority**: P0 (Blocker)
**Source**: LOA_CK_CLI_PROMPT.md:243

**Requirement**: No error messages when ck is missing. Silent fallback to grep.

**Rationale**: ck is optional enhancement, never required.

**Validation**: Uninstall ck, run all commands, verify no errors.

---

### NFR-7: Integrations

**NFR-7.1**: Beads integration for tracking
**Priority**: P1 (High)
**Source**: LOA_CK_CLI_PROMPT.md:98-105

**Requirement**: If Beads (bd CLI) is available, track Ghost Features and Shadow Systems as structured tasks.

**Commands**:
```bash
# Ghost Feature
bd create "GHOST: <feature>" --type liability --priority 2

# Shadow System (Orphaned)
bd create "SHADOW (orphaned): <module>" --type debt --priority 1
```

**Rationale**: Structured task tracking for remediation planning.

**Validation**: Run `/ride` with Beads installed, verify bd tasks created.

---

## Phase 6: Scope & Prioritization

### MVP Definition (v1.0)

**In Scope**:
- ✅ Installation surfacing (INSTALLATION.md, /setup, README.md)
- ✅ Pre-flight integrity checks (strict/warn/disabled modes)
- ✅ Seamless /ride integration with dual-path (ck + grep)
- ✅ Ghost Feature detection (Negative Grounding protocol)
- ✅ Shadow System detection (Classification: Orphaned/Drifted/Partial)
- ✅ Tool Result Clearing protocol (attention budget management)
- ✅ Trajectory logging (intent→execute→cite phases)
- ✅ Word-for-word citations with absolute paths
- ✅ Self-audit checkpoint (completion gate)
- ✅ MCP registry with strict Zod schemas
- ✅ JSONL output with failure-aware parsing
- ✅ Graceful fallback to grep
- ✅ Synthesis Protection via .claude/overrides/

**Out of Scope (Future)**:
- ❌ Custom MCP servers beyond ck
- ❌ Multi-model embedding strategies
- ❌ Real-time index updates (git hooks)
- ❌ Distributed search across multiple machines
- ❌ GUI for trajectory visualization
- ❌ Integration with other search tools (Sourcegraph, etc.)

**Source**: LOA_CK_CLI_PROMPT.md:278-299 (Execution Order)

---

### Phasing & Milestones

**Phase 1: Installation & Setup** (Week 1)
- Update INSTALLATION.md, README.md, .gitignore
- Update /setup command to check ck status
- Create synthesis protection structure (.claude/overrides/)

**Phase 1.5: Integrity & Security** (Week 1)
- Create preflight-integrity.md protocol
- Implement checksum verification
- Add binary integrity verification
- Create self-healing State Zone logic

**Phase 2: /ride Integration** (Week 2)
- Update ride.md with dual-path logic
- Implement Ghost Feature detection (Negative Grounding)
- Implement Shadow System detection (Classification)
- Create drift-report.md with auto-resolution

**Phase 2.5: Context Management** (Week 2)
- Create tool-result-clearing.md protocol
- Implement Semantic Decay protocol
- Enforce attention budgets

**Phase 3: Trajectory Logging** (Week 3)
- Create trajectory-evaluation.md protocol
- Implement Intent-First Search protocol
- Implement Trajectory Pivot logging
- Implement Self-Audit Checkpoint
- Add EDD Verification (3 test scenarios)

**Phase 4: Technical Specs** (Week 3)
- Create mcp-registry.yaml with Zod schemas
- Implement JSONL output with failure-aware parsing
- Implement managed pagination

**Phase 5: Skill Integration** (Week 4)
- Update implementing-tasks skill
- Update reviewing-code skill
- Create search-fallback.md protocol

**Phase 6: Testing & Validation** (Week 4)
- Test /ride without ck (grep fallback)
- Test /ride with ck (semantic search)
- Verify user experience parity
- Verify grounding ratio ≥ 0.95
- Verify trajectory logs complete

**Source**: LOA_CK_CLI_PROMPT.md:278-299

---

### Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Command namespace protection | High | Low | P0 |
| Pre-flight integrity checks | High | Medium | P0 |
| /ride dual-path integration | High | High | P0 |
| Tool Result Clearing | High | Medium | P0 |
| Trajectory logging | High | Medium | P0 |
| Self-audit checkpoint | High | Low | P0 |
| Word-for-word citations | High | Low | P0 |
| JSONL failure-aware parsing | High | Low | P0 |
| Ghost Feature detection | Medium | Medium | P0 |
| Shadow System detection | Medium | Medium | P0 |
| Agent chaining (next step) | High | Medium | P1 |
| Context pollution prevention | High | Medium | P1 |
| Configurable watch paths | Medium | Low | P1 |
| Signal markers filtering | Medium | Medium | P1 |
| Binary integrity verification | Medium | Low | P1 |
| Semantic Decay protocol | Medium | Medium | P1 |
| Skill integration | Medium | High | P1 |
| Beads integration | Low | Low | P1 |
| Drift Report Evolution | Low | Medium | P1 |

---

## Phase 7: Risks & Dependencies

### Technical Risks

**R-1: ck Binary Availability**
- **Risk**: ck requires Rust toolchain (cargo install)
- **Likelihood**: Medium
- **Impact**: High (blocks semantic search)
- **Mitigation**: Graceful degradation to grep, clearly document as optional
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:190-227

**R-2: Context Window Exhaustion**
- **Risk**: Large search results overwhelm agent attention budget
- **Likelihood**: High
- **Impact**: High (model hallucinations, poor reasoning)
- **Mitigation**: Tool Result Clearing protocol, Semantic Decay, attention budgets
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:919-1050

**R-3: JSONL Parse Failures**
- **Risk**: Malformed JSONL crashes entire search operation
- **Likelihood**: Medium
- **Impact**: High (agent failures mid-task)
- **Mitigation**: Failure-Aware Parsing (drop bad lines, continue), log to trajectory
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:1748-1811

**R-4: Integrity Check False Positives**
- **Risk**: Legitimate file changes flagged as tampering
- **Likelihood**: Low
- **Impact**: Medium (user frustration)
- **Mitigation**: Three enforcement levels (strict/warn/disabled), clear error messages
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:325-508

**R-5: Search Precision Degradation**
- **Risk**: grep fallback has higher false-positive rate than ck
- **Likelihood**: High (when ck not installed)
- **Impact**: Medium (lower quality results)
- **Mitigation**: Document benefits of ck, make installation easy, accept trade-off
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:1052-1111

**R-6: Command Namespace Collision**
- **Risk**: Loa commands conflict with Claude Code built-ins (e.g., /config)
- **Likelihood**: High (already occurring with /config)
- **Impact**: High (blocks access to Claude Code features)
- **Mitigation**: Reserved command list, pre-flight validation, auto-rename with `-loa` suffix
- **Source**: GitHub Issue #11

**R-7: Context Pollution from Session Artifacts**
- **Risk**: Low-signal documents pollute search results and consume context window
- **Likelihood**: High (repos accumulate brainstorm notes, meeting transcripts)
- **Impact**: Medium (degraded agent focus, wasted tokens)
- **Mitigation**: Signal markers, archive zone, default exclude patterns, configurable filtering
- **Source**: GitHub Issue #10

**R-8: Drift Detection Blind Spots**
- **Risk**: Custom directories not included in drift detection
- **Likelihood**: Medium (users may have .meta/, docs/architecture/, etc.)
- **Impact**: Medium (missed drift in important files)
- **Mitigation**: Configurable watch_paths in .loa.config.yaml
- **Source**: GitHub Issue #10

---

### Business Risks

**R-9: Increased Complexity**
- **Risk**: Adding ck integration increases framework complexity
- **Likelihood**: High
- **Impact**: Medium (harder maintenance, steeper learning curve)
- **Mitigation**: Comprehensive documentation, clear protocols, synthesis protection
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:98-126 (Three-Zone Model)

**R-10: User Confusion**
- **Risk**: Users don't understand when to install ck
- **Likelihood**: Medium
- **Impact**: Low (sub-optimal experience)
- **Mitigation**: Clear INSTALLATION.md, /setup status display, README prerequisites table
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:190-310

---

### Dependencies

**D-1: ck Binary (External)**
- **Dependency**: ck-search Rust crate
- **Version**: 0.7.0+
- **Owner**: BeaconBay (https://github.com/BeaconBay/ck)
- **Risk**: Upstream breaking changes
- **Mitigation**: Version pinning in .loa-version.json
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:460-472

**D-2: Beads (Optional External)**
- **Dependency**: bd CLI for task tracking
- **Version**: Any recent
- **Owner**: steveyegge/beads
- **Risk**: Not available on user's system
- **Mitigation**: Optional, graceful degradation (no Beads → no structured tracking)
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:713-746

**D-3: jq (System Tool)**
- **Dependency**: Command-line JSON processor
- **Use Case**: Checksum verification, JSONL parsing in scripts
- **Risk**: Missing on minimal Linux distros
- **Mitigation**: Fallback to pure bash if jq missing
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:363-386

**D-4: yq (System Tool)**
- **Dependency**: YAML processor for reading mcp-registry.yaml
- **Use Case**: Loading MCP server configurations
- **Risk**: Not installed by default
- **Mitigation**: Document in INSTALLATION.md: `brew install yq` / `apt install yq`
- **Source**: Inferred from LOA_CK_INTEGRATION_PROMPT.md (MCP registry YAML parsing)

---

## Appendix A: Traceability Matrix

### AWS Projen Standards (Infrastructure Integrity)

| Requirement | PRD Section | Implementation | Status |
|-------------|-------------|----------------|--------|
| Pre-flight integrity check | FR-2.1 | .claude/protocols/preflight-integrity.md | ✅ |
| Cryptographic manifest | FR-2.1 | checksums.json validation | ✅ |
| HALT on strict + drift | FR-2.1 | integrity_enforcement: strict | ✅ |
| Zone-aware persistence | FR-2.1 | .ck/ in State Zone (never committed) | ✅ |
| Self-healing State Zone | NFR-3.1 | Delta-first reindexing | ✅ |
| Version pinning | NFR-4.2 | .loa-version.json ck check | ✅ |
| Binary integrity verification | NFR-2.2 | SHA-256 fingerprint check | ✅ |
| Synthesis Protection | FR-2.2 | .claude/overrides/ directory | ✅ |

**Source**: LOA_CK_INTEGRATION_PROMPT.md:2110-2125

---

### Anthropic Standards (Context Engineering)

| Requirement | PRD Section | Implementation | Status |
|-------------|-------------|----------------|--------|
| JIT retrieval | FR-4.1 | Smallest token set principle | ✅ |
| Tiered Search Protocol | FR-3.1 | Broad→Narrow→JIT | ✅ |
| Dynamic Thresholding | FR-3.1 | 0.4-0.8 based on task | ✅ |
| AST-aware snippets | FR-3.1 | --full-section flag | ✅ |
| Semantic Decay Protocol | FR-4.2 | Active→Decayed→Archived | ✅ |
| Tool Result Clearing | FR-4.1 | .claude/protocols/tool-result-clearing.md | ✅ |
| Attention budgets | FR-4.1 | 2000/5000/15000 tokens | ✅ |
| Absolute path enforcement | FR-6.4 | ${PROJECT_ROOT}/... mandate | ✅ |
| JSONL output | FR-6.2 | --jsonl flag required | ✅ |
| Failure-Aware Parsing | FR-6.2 | Drop bad lines, continue | ✅ |
| Dropped Line Logging | FR-6.2 | Audit trail to trajectory | ✅ |
| Strict Schema Enforcement | FR-6.1 | strict: true, additionalProperties: false | ✅ |

**Source**: LOA_CK_INTEGRATION_PROMPT.md:2127-2145

---

### Google ADK Standards (Trajectory Evaluation)

| Requirement | PRD Section | Implementation | Status |
|-------------|-------------|----------------|--------|
| Intent logging before search | FR-5.1 | Reasoning-Before-Search protocol | ✅ |
| Expected outcome required | FR-5.1 | Mandatory before search | ✅ |
| Model Selection Rationale | FR-5.1 | Justify bge-small vs jina-code | ✅ |
| Negative Model Justification | FR-5.1 | Why NOT using larger model | ✅ |
| Trajectory Pivot for >50 | FR-5.2 | Log hypothesis failure | ✅ |
| Negative Grounding (Ghost) | FR-3.2 | 2 diverse queries required | ✅ |
| High Ambiguity Detection | FR-3.2 | Flag if 0 code + >3 doc | ✅ |
| EDD (3 test scenarios) | FR-5.5 | Happy/Edge/Error scenarios | ✅ |
| Grounding ratio ≥ 0.95 | FR-5.4 | Self-Audit Checkpoint metric | ✅ |
| Word-for-word citations | FR-5.3 | Mandatory code quotes | ✅ |
| [ASSUMPTION] tagging | FR-5.4 | Claim Classification | ✅ |
| Self-audit checkpoint | FR-5.4 | Completion gate | ✅ |

**Source**: LOA_CK_INTEGRATION_PROMPT.md:2147-2164

---

### Loa Standards (Truth Hierarchy)

| Requirement | PRD Section | Implementation | Status |
|-------------|-------------|----------------|--------|
| CODE > Artifacts > Docs | Phase 1 (Vision) | Immutable Truth Hierarchy | ✅ |
| Ghost Feature detection | FR-3.2 | Negative Grounding Protocol | ✅ |
| Shadow System classification | FR-3.3 | Orphaned/Drifted/Partial | ✅ |
| Dependency Trace (Orphaned) | FR-3.3 | Import graph generation | ✅ |
| Drift Report Evolution | FR-3.4 | Auto-resolve items | ✅ |
| Beads integration | NFR-7.1 | Track Ghost/Shadow tasks | ✅ |
| Always side with code | Phase 1 (Vision) | Conflict resolution rule | ✅ |

**Source**: LOA_CK_INTEGRATION_PROMPT.md:2167-2179

---

## Appendix B: Anti-Patterns Checklist

### User Experience Anti-Patterns (Must NOT Exist)

- ❌ `/ck` slash command
- ❌ User-visible "semantic search" messaging
- ❌ User-visible "falling back to grep" messaging
- ❌ Error when ck not installed
- ❌ Recommendation to install ck during /ride
- ❌ Different output format based on search mode
- ❌ ck mentioned in agent responses

**Source**: LOA_CK_CLI_PROMPT.md:189-200, LOA_CK_INTEGRATION_PROMPT.md:2056-2066

---

### Fishing Expedition Anti-Patterns (Must NOT Exist)

- ❌ Searching without articulating expected_outcome
- ❌ Paginating through >50 results blindly
- ❌ Broad queries "just to see what's there"
- ❌ Repeating similar searches with slight variations
- ❌ Continuing after unexpected results without reassessing

**Source**: LOA_CK_CLI_PROMPT.md:207-213, LOA_CK_INTEGRATION_PROMPT.md:2073-2080

---

### Grounding Anti-Patterns (Must NOT Exist)

- ❌ Presenting [ASSUMPTION] as fact
- ❌ Citations without word-for-word code quotes
- ❌ Relative paths instead of absolute paths
- ❌ Decisions without 3 test scenarios (EDD)
- ❌ Siding with docs when code differs

**Source**: LOA_CK_CLI_PROMPT.md:199-205, LOA_CK_INTEGRATION_PROMPT.md:2082-2089

---

### Context Management Anti-Patterns (Must NOT Exist)

- ❌ Loading entire files when snippets suffice
- ❌ Keeping raw search results in working memory
- ❌ Skipping Tool Result Clearing after >20 results
- ❌ Exceeding attention budget without synthesis

**Source**: LOA_CK_CLI_PROMPT.md:301-335, LOA_CK_INTEGRATION_PROMPT.md:2091-2096

---

### Synthesis Protection Anti-Patterns (Must NOT Exist)

- ❌ Editing .claude/ files directly (except .claude/overrides/)
- ❌ Allowing users to modify System Zone files
- ❌ Ignoring .claude/overrides/ when loading ck config
- ❌ Storing user customizations in System Zone

**Source**: LOA_CK_CLI_PROMPT.md:213-219, LOA_CK_INTEGRATION_PROMPT.md:2098-2103

---

## Appendix C: Communication Guidelines

### Agent Language (Internal)

**NEVER SAY to User**:
- ❌ "I'm using ck for semantic search..."
- ❌ "Falling back to grep because ck isn't installed..."
- ❌ "For better results, install ck..."
- ❌ "The semantic search found..."

**ALWAYS SAY to User**:
- ✅ "Analyzing codebase structure..."
- ✅ "Searching for entry points..."
- ✅ "Cross-referencing documentation with implementation..."
- ✅ "Found the following patterns..."

**Source**: LOA_CK_CLI_PROMPT.md:383-397, LOA_CK_INTEGRATION_PROMPT.md:1097-1110

---

### Citation Format (Mandatory)

**INSUFFICIENT (will be rejected)**:
```markdown
"The system uses JWT [src/auth/jwt.ts:45]"
```

**REQUIRED (word-for-word quote)**:
```markdown
"The system uses JWT: `export async function validateToken(token: string): Promise<TokenPayload>` [/home/user/project/src/auth/jwt.ts:45]"
```

**Template**:
```markdown
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
```

**Source**: LOA_CK_CLI_PROMPT.md:407-418, LOA_CK_INTEGRATION_PROMPT.md:1386-1420

---

## Appendix D: Gaps & Clarifications Needed

### Clarification 1: ck Installation Method

**Context**: The integration assumes users install ck via `cargo install ck-search`.

**Question**: Should Loa provide alternative installation methods?
- Pre-built binaries for Linux/macOS/Windows?
- Docker container with ck pre-installed?
- Homebrew formula for macOS?

**Impact**: Affects INSTALLATION.md documentation and user adoption rate.

---

### Clarification 2: Trajectory Log Retention

**Context**: FR-5.1 specifies trajectory logs in `loa-grimoire/a2a/trajectory/`.

**Question**: What is the retention policy?
- Keep last N days (30 days mentioned in config)?
- Keep until manual cleanup?
- Auto-archive old logs?

**Impact**: Affects disk space usage and audit trail availability.

---

### Clarification 3: MCP Server Initialization

**Context**: FR-6.1 creates mcp-registry.yaml with `command: "ck"` and `args: ["--serve"]`.

**Question**: Does ck support MCP server mode natively?
- Is `ck --serve` a real command?
- Or is this a future feature assumption?
- Should we use Claude Code's MCP wrapping?

**Impact**: May require changes to ck binary or wrapper scripts.

---

### Clarification 4: Beads Integration Scope

**Context**: NFR-7.1 specifies Beads integration for Ghost/Shadow tracking.

**Question**: Should we integrate more deeply with Beads?
- Auto-create Beads tasks for all discovered technical debt?
- Sync trajectory logs to Beads for auditing?
- Use Beads for sprint planning based on drift report?

**Impact**: Affects implementation complexity and user workflow.

---

### Clarification 5: Multi-Repository Support

**Context**: Integration assumes single repository (PROJECT_ROOT from git).

**Question**: Should we support multi-repository analysis?
- Monorepo with multiple .git directories?
- Aggregated search across multiple cloned repos?
- Federated ck indexes?

**Impact**: Affects search strategy and indexing architecture.

---

## Conclusion

This PRD comprehensively documents the requirements for integrating ck semantic search into the Loa framework as an invisible, optional enhancement following FAANG-tier engineering standards. All context files have been synthesized, mapped to discovery phases, and traced to source documentation.

**Key Achievements**:
- ✅ 100% context file coverage (2 files, 95,450 bytes + 3 GitHub issues)
- ✅ All 7 discovery phases addressed
- ✅ 70+ functional requirements with citations (FR-1 through FR-11)
- ✅ 20+ non-functional requirements
- ✅ Complete traceability matrix (AWS Projen + Anthropic + Google ADK)
- ✅ Anti-pattern prevention guidelines
- ✅ 5 gaps identified for stakeholder clarification
- ✅ GitHub Issue #9: Agent chaining (FR-8)
- ✅ GitHub Issue #10: Context pollution prevention (FR-9)
- ✅ GitHub Issue #11: Command namespace protection (FR-10) - **P0 Blocker**

**New Requirements Added (from GitHub Issues)**:
| Issue | Requirement | Priority | Status |
|-------|-------------|----------|--------|
| #9 | Agent chaining - auto-suggest next command | P1 | Added as FR-8 |
| #10 | Configurable watch paths for drift detection | P1 | Added as FR-9.1 |
| #10 | Signal markers for context filtering | P1 | Added as FR-9.2 |
| #11 | Command namespace protection (reserved list) | P0 | Added as FR-10 |

**Next Steps**:
1. Review PRD with THJ team
2. **Immediate**: Rename `/config` to `/config-loa` or `/mcp-config` (Issue #11)
3. Clarify 5 identified gaps (Appendix D)
4. Proceed to `/architect` for Software Design Document
5. Begin implementation in `/sprint-plan`

**Document Status**: Ready for architectural design phase.

---

*Generated by: discovering-requirements agent*
*Date: 2025-12-26*
*Context Sources: LOA_CK_INTEGRATION_PROMPT.md (74,246 bytes), LOA_CK_CLI_PROMPT.md (21,204 bytes)*
