# Trajectory Evaluation Protocol (ADK-Level)

**Version**: 2.0
**Status**: Active
**Last Updated**: 2025-12-27 (Enhanced for Sprint 3)

> Evaluate not just the output, but the reasoning path.

## Purpose

Google's ADK emphasizes evaluating the **step-by-step execution trajectory**, not just final results. This protocol implements Intent-First Search with comprehensive trajectory logging to prevent "fishing expeditions" and ensure every search operation has clear reasoning.

**This catches**:
- Hallucinated reasoning that happened to reach a correct answer
- Brittle approaches that work by accident
- Missed edge cases in the reasoning process
- Searches without clear goals that waste tokens
- Fishing expeditions (searching without expected outcomes)

**Source**: PRD FR-5.1, FR-5.2, SDD §4.2

## Intent-First Search Protocol

### Three Required Elements (Before Search)

Before executing ANY search, agents MUST articulate:

1. **Intent**: What are we looking for?
   - Clear, specific target (e.g., "JWT authentication entry points")
   - Not vague (e.g., "authentication stuff")

2. **Rationale**: Why do we need this for the current task?
   - Connect to current implementation goal
   - Justify why this search is necessary now
   - Not generic (e.g., "to understand the code")

3. **Expected Outcome**: What do we expect to find?
   - Specific prediction (e.g., "1-3 token validation functions")
   - Success criteria (what would make this search successful?)
   - HALT if cannot articulate expected outcome

### XML Format for Agent Reasoning

Agents must structure their search reasoning in this format:

```xml
<search_execution>
  <intent>Find JWT authentication entry points</intent>
  <rationale>Task requires extending auth; need patterns first</rationale>
  <expected_outcome>Should find 1-3 token validation functions</expected_outcome>
  <query>hybrid_search("JWT token validation authentication")</query>
  <path>${PROJECT_ROOT}/src/auth/</path>
</search_execution>
```

### HALT Conditions

**DO NOT** proceed with search if:

- ❌ Expected outcome cannot be articulated
- ❌ Rationale is vague or generic
- ❌ Intent is too broad (would return >100 results)
- ❌ Search is redundant (already searched similar query)

**Action**: Refine reasoning FIRST, then search.

---

## Trajectory Log Location

```
grimoires/loa/a2a/trajectory/
  {agent}-{date}.jsonl
```

**Examples**:
- `grimoires/loa/a2a/trajectory/implementing-tasks-2025-12-27.jsonl`
- `grimoires/loa/a2a/trajectory/reviewing-code-2025-12-27.jsonl`
- `grimoires/loa/a2a/trajectory/discovering-requirements-2025-12-27.jsonl`

## JSONL Log Format

Each line is a complete JSON object (newline-delimited):

```jsonl
{"ts":"2025-12-27T10:30:00Z","agent":"implementing-tasks","phase":"intent","intent":"Find JWT authentication entry points","rationale":"Task requires extending auth; need patterns first","expected_outcome":"Should find 1-3 token validation functions"}
{"ts":"2025-12-27T10:30:05Z","agent":"implementing-tasks","phase":"execute","mode":"ck","query":"JWT token validation authentication","path":"/abs/path/src/auth/","top_k":10,"threshold":0.5}
{"ts":"2025-12-27T10:30:07Z","agent":"implementing-tasks","phase":"result","result_count":3,"high_signal":2,"tokens_estimated":450}
{"ts":"2025-12-27T10:30:10Z","agent":"implementing-tasks","phase":"cite","citations":[{"claim":"System uses JWT validation","code":"export async function validateToken()","path":"/abs/path/src/auth/jwt.ts","line":45}]}
```

### Four Trajectory Phases for Search Operations

| Phase | When | Required Fields |
|-------|------|-----------------|
| **intent** | BEFORE search | `intent`, `rationale`, `expected_outcome` |
| **execute** | DURING search | `mode`, `query`, `path`, search parameters |
| **result** | AFTER search | `result_count`, `high_signal`, `tokens_estimated` |
| **cite** | AFTER synthesis | `citations` (array of code quotes with paths) |

### General Task Execution Format

For non-search operations, use this format:

```json
{
  "timestamp": "2024-01-10T14:30:00Z",
  "agent": "implementing-tasks",
  "step": 3,
  "action": "file_read",
  "input": {"path": "src/auth/login.ts"},
  "reasoning": "Need to understand current auth implementation before modifying",
  "grounding": {
    "type": "citation",
    "source": "sdd.md:L145",
    "quote": "Authentication must use bcrypt with cost factor 12"
  },
  "output_summary": "Found existing bcrypt implementation with cost 10",
  "next_action": "Update cost factor to 12 per SDD requirement"
}
```

## Anti-Fishing Expedition Rules

### Fishing Expedition Detection

A "fishing expedition" is a search without clear purpose. Indicators:

- ❌ No expected outcome articulated
- ❌ Broad query (>100 results)
- ❌ Repeated similar searches with slight variations
- ❌ Unexpected results ignored (keeps searching)
- ❌ Paginating through results without evaluation

### Prevention Rules

| Scenario | Action |
|----------|--------|
| Search returns unexpected results | Log discrepancy, reassess rationale |
| Search returns 0 results | Reformulate query OR flag as Ghost Feature |
| Search returns >50 results | LOG TRAJECTORY PIVOT, then narrow |
| No clear expected_outcome | STOP - clarify reasoning before searching |
| >3 similar searches in 10 min | FLAG as inefficient, require justification |

### Trajectory Pivot (>50 Results)

When search returns >50 results, MANDATORY pivot log before narrowing:

```jsonl
{
  "ts": "2025-12-27T10:35:00Z",
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

**Required pivot fields**:
- `reason`: Why query was too broad
- `original_query`: What we tried
- `result_count`: How many results
- `hypothesis_failure`: Why our hypothesis failed
- `refined_hypothesis`: Updated understanding
- `new_query`: Improved query string

---

## Grounding Types

| Type | Description | Required Fields | Example |
|------|-------------|-----------------|---------|
| `citation` | Direct quote from code | `code`, `path`, `line` | `export async function validateToken()` |
| `code_reference` | Reference to existing code (no quote) | `file`, `line` | "Auth module at src/auth/" |
| `assumption` | Ungrounded claim | `assumption`, `flag` | "Likely caches tokens [ASSUMPTION]" |
| `user_input` | Based on user's explicit request | `message_id` or `source` | "User wants JWT support" |

**[ASSUMPTION] flag required** for all ungrounded claims:
```jsonl
{
  "ts": "2025-12-27T10:55:00Z",
  "agent": "implementing-tasks",
  "phase": "assumption",
  "claim": "Tokens likely cached in Redis",
  "grounding": "assumption",
  "flag": "[ASSUMPTION: needs verification]"
}
```

## Agent Responsibilities

### Before Each Action
1. Log the intended action
2. Document the reasoning
3. Cite grounding (or flag as assumption)

### After Each Action
1. Summarize the output (not raw data)
2. State the next action and why

### On Task Completion
1. Generate trajectory summary
2. Self-evaluate: "Did I reach this conclusion through grounded reasoning?"

## Evaluation by reviewing-code Agent

When auditing a completed task:

1. Load trajectory log for the implementing agent
2. Check each step for:
   - Ungrounded assumptions
   - Reasoning jumps (conclusions without steps)
   - Contradictions with previous steps
3. Flag issues:
   ```markdown
   ## Trajectory Audit: PR #42

   Step 5: Ungrounded assumption about cache TTL
   Step 8: Reasoning jump - no explanation for architecture choice
   Steps 1-4, 6-7, 9-12: Well-grounded

   Recommendation: Request clarification on steps 5 and 8 before approval.
   ```

## Evaluation-Driven Development (EDD)

Before marking a task COMPLETE, agents must:

1. Create 3 diverse test scenarios:
   ```markdown
   ## Test Scenarios for: Implement User Authentication

   1. **Happy Path**: Valid credentials -> successful login -> JWT returned
   2. **Edge Case**: Expired password -> prompt for reset -> block login
   3. **Adversarial**: SQL injection attempt -> sanitized -> blocked with log
   ```

2. Verify each scenario is covered by implementation

3. Log test scenario creation in trajectory

## Outcome Validation

After search execution, validate results against expected outcome:

### Match (✅ Expected)

Results aligned with expected outcome:

**Example**:
- Expected: "1-3 token validation functions"
- Found: 2 functions (`validateToken`, `verifyToken`)
- **Action**: Log `"outcome_match": "match"`, proceed with synthesis

### Partial (⚠️ Some Unexpected)

Some results matched, some unexpected:

**Example**:
- Expected: "JWT validation functions"
- Found: 2 validation functions + 5 configuration files
- **Action**: Log `"outcome_match": "partial"`, extract relevant subset

### Mismatch (❌ Unexpected)

Results completely different than expected:

**Example**:
- Expected: "JWT validation in auth module"
- Found: OAuth2 flows, SAML handlers, legacy auth
- **Action**: Log `"outcome_match": "mismatch"`, reassess rationale, refine query

**Trajectory log**:
```jsonl
{
  "ts": "2025-12-27T10:40:00Z",
  "agent": "implementing-tasks",
  "phase": "mismatch",
  "expected": "JWT validation functions",
  "found": "OAuth2 and SAML implementations",
  "hypothesis": "Assumed JWT was primary auth, actually multi-provider",
  "action": "Refine query to target JWT specifically"
}
```

### Zero Results (🔍 Ghost Feature?)

No results found:

**Example**:
- Expected: "OAuth2 SSO login flow"
- Found: 0 results
- **Action**: Perform Negative Grounding (second diverse query), potentially flag as Ghost Feature

**Trajectory log**:
```jsonl
{
  "ts": "2025-12-27T10:45:00Z",
  "agent": "discovering-requirements",
  "phase": "zero_results",
  "query1": "OAuth2 SSO login flow",
  "result1": 0,
  "query2": "single sign-on identity provider",
  "result2": 0,
  "classification": "GHOST",
  "action": "Flag as Ghost Feature, track in Beads"
}
```

---

## Model Selection Rationale

When using ck with multiple embedding models, log model selection:

```jsonl
{
  "ts": "2025-12-27T11:00:00Z",
  "agent": "implementing-tasks",
  "phase": "model_selection",
  "chosen_model": "nomic-v1.5",
  "rationale": "Balance between speed and accuracy for code search",
  "alternatives_considered": ["jina-code", "bge-large"],
  "why_not_jina": "Slower, overkill for this search scope",
  "why_not_bge": "Optimized for natural language, not code"
}
```

**Required fields**:
- `chosen_model`: Model used for search
- `rationale`: Why this model is appropriate
- `alternatives_considered`: Other models evaluated
- `why_not_X`: Negative justification for each alternative

---

## Trajectory Audit

### Self-Audit Queries

Agents can query their own trajectory logs:

**Find all assumptions**:
```bash
grep '"grounding":"assumption"' grimoires/loa/a2a/trajectory/implementing-tasks-2025-12-27.jsonl
```

**Find all pivots**:
```bash
grep '"phase":"pivot"' grimoires/loa/a2a/trajectory/implementing-tasks-2025-12-27.jsonl
```

**Calculate grounding ratio**:
```bash
# Total claims
total=$(grep '"phase":"cite"' trajectory.jsonl | wc -l)

# Grounded claims (citations)
grounded=$(grep '"grounding":"citation"' trajectory.jsonl | wc -l)

# Ratio
echo "scale=2; $grounded / $total" | bc
```

---

## Configuration

In `.loa.config.yaml`:

```yaml
edd:
  enabled: true
  min_test_scenarios: 3
  trajectory_audit: true
  require_citations: true

trajectory:
  retention_days: 30
  archive_days: 365
  compression_level: 6
```

## Retention

Trajectory logs stored in `grimoires/loa/a2a/trajectory/` with retention:

| Age | Status | Action |
|-----|--------|--------|
| 0-30 days | Active | Keep as .jsonl |
| 30-365 days | Archived | Compress to .jsonl.gz (via compact-trajectory.sh) |
| >365 days | Purged | Delete archives |

**Compaction script**: `.claude/scripts/compact-trajectory.sh` (Task 3.8)

To preserve a trajectory permanently:
```bash
mkdir -p grimoires/loa/a2a/trajectory/archive/
mv grimoires/loa/a2a/trajectory/implementing-2024-01-10.jsonl \
   grimoires/loa/a2a/trajectory/archive/
```

## Communication Guidelines

### What Agents Should Say (User-Facing)

✅ **CORRECT**:
- "Searching for JWT authentication entry points..."
- "Found 3 high-relevance files for authentication work."
- "No results found for OAuth2 SSO - flagging as potential Ghost Feature."

❌ **INCORRECT** (internal details exposed):
- "Logging intent phase to trajectory before searching..."
- "Expected outcome: 1-3 functions. Let me validate against actual results..."
- "Trajectory pivot required due to >50 results..."

### Internal State (Not Shown to User)

Agents should internally track:
- Trajectory log file path
- Current phase being logged
- Grounding type for each claim
- Outcome validation results

**All internal state logged to trajectory only, never shown to user.**

---

## Integration with Other Protocols

### Tool Result Clearing

After logging `phase: "result"`, apply Tool Result Clearing if:
- `result_count > 20` OR
- `tokens_estimated > 2000`

**Trajectory entry**:
```jsonl
{
  "ts": "2025-12-27T11:05:00Z",
  "agent": "implementing-tasks",
  "phase": "clear",
  "result_count": 47,
  "high_signal": 3,
  "tokens_before": 2100,
  "tokens_after": 50,
  "reduction_ratio": 0.976
}
```

### Self-Audit Checkpoint

Before completing task, verify trajectory log:

- [ ] All searches have intent phase logged
- [ ] All results have outcome validation
- [ ] All citations logged with code quotes
- [ ] Zero unflagged assumptions
- [ ] Grounding ratio ≥ 0.95

### Negative Grounding Protocol

When detecting Ghost Features:

```jsonl
{
  "ts": "2025-12-27T11:10:00Z",
  "agent": "discovering-requirements",
  "phase": "negative_grounding",
  "feature": "OAuth2 SSO",
  "query1": "OAuth2 SSO login flow",
  "result1": 0,
  "threshold1": 0.4,
  "query2": "single sign-on identity provider",
  "result2": 0,
  "threshold2": 0.4,
  "classification": "CONFIRMED GHOST",
  "doc_mentions": 5,
  "ambiguity": "high"
}
```

---

## Why This Matters

Traditional evaluation checks only:
- Did the output compile?
- Did tests pass?
- Does the feature work?

Trajectory evaluation also checks:
- Was the reasoning sound?
- Were assumptions made explicit?
- Would this approach generalize?
- Did the agent understand *why*, not just *what*?
- Were searches goal-directed or fishing expeditions?
- Were all claims properly grounded in code?

This catches "lucky guesses" and ensures reproducible quality.

---

## Session Handoff Phase (v0.9.0)

> **Protocol**: See `.claude/protocols/session-continuity.md`
> **Paradigm**: Clear, Don't Compact

The `session_handoff` phase is logged when context is cleared via `/clear`.

### Session Handoff Log Format

```jsonl
{"ts":"2024-01-15T14:30:00Z","agent":"implementing-tasks","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"beads-x7y8","notes_refs":["grimoires/loa/NOTES.md:68-92"],"edd_verified":true,"grounding_ratio":0.97,"test_scenarios":3,"next_session_ready":true}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Always `"session_handoff"` |
| `session_id` | string | Unique session identifier |
| `root_span_id` | string | Root span for lineage tracking |
| `bead_id` | string | Active Bead being worked on |
| `notes_refs` | array | Line references to NOTES.md sections |
| `edd_verified` | boolean | EDD test scenarios documented |
| `grounding_ratio` | number | Ratio at handoff (>= 0.95 required) |
| `test_scenarios` | number | Count of test scenarios documented |
| `next_session_ready` | boolean | State Zone ready for recovery |

### Lineage Tracking

The `root_span_id` enables tracking work across session boundaries:

```
Session 1: span-abc (initial work)
    └── Session 2: span-def (continues from span-abc)
        └── Session 3: span-ghi (continues from span-def)
```

Query lineage:
```bash
grep '"root_span_id":"span-abc"' grimoires/loa/a2a/trajectory/*.jsonl
```

---

## Delta Sync Phase (v0.9.0)

> **Protocol**: See `.claude/protocols/attention-budget.md`

The `delta_sync` phase is logged at Yellow threshold (5,000 tokens) for partial persistence.

### Delta Sync Log Format

```jsonl
{"ts":"2024-01-15T12:00:00Z","agent":"implementing-tasks","phase":"delta_sync","tokens":5000,"decisions_persisted":3,"bead_updated":true,"notes_updated":true}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Always `"delta_sync"` |
| `tokens` | number | Approximate token count at sync |
| `decisions_persisted` | number | Number of decisions written to NOTES.md |
| `bead_updated` | boolean | Whether active Bead was updated |
| `notes_updated` | boolean | Whether NOTES.md was updated |

### Purpose

Delta sync provides crash recovery:
- Work persisted before session terminates unexpectedly
- Partial progress saved even without explicit `/clear`
- Recovery can resume from delta-synced state

---

## Grounding Check Phase (v0.9.0)

> **Protocol**: See `.claude/protocols/grounding-enforcement.md`

The `grounding_check` phase is logged during synthesis checkpoint.

### Grounding Check Log Format

```jsonl
{"ts":"2024-01-15T14:29:00Z","agent":"implementing-tasks","phase":"grounding_check","total_claims":20,"grounded_claims":19,"assumptions":1,"grounding_ratio":0.95,"threshold":0.95,"status":"pass"}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Always `"grounding_check"` |
| `total_claims` | number | Total decisions/claims in session |
| `grounded_claims` | number | Claims with code citations |
| `assumptions` | number | Claims marked as [ASSUMPTION] |
| `grounding_ratio` | number | grounded_claims / total_claims |
| `threshold` | number | Required minimum (default 0.95) |
| `status` | string | `"pass"` or `"fail"` |

### Enforcement

- **strict mode**: `/clear` blocked if status = "fail"
- **warn mode**: Warning shown but `/clear` permitted
- **disabled**: No enforcement

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01-10 | Initial protocol creation |
| 2.0 | 2025-12-27 | Enhanced for Sprint 3: Intent-First Search, Anti-Fishing Rules, Outcome Validation |
| 2.1 | 2025-12-27 | v0.9.0 Lossless Ledger: session_handoff, delta_sync, grounding_check phases |

---

**Status**: ✅ Protocol Enhanced
**Paradigm**: Clear, Don't Compact
**Next**: Integrate into search orchestrator (Sprint 4)
