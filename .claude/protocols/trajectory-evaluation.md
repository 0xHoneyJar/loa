# Trajectory Evaluation Protocol (ADK-Level)

> Evaluate not just the output, but the reasoning path.

## Purpose

Google's ADK emphasizes evaluating the **step-by-step execution trajectory**, not just final results. This protocol implements Intent-First Search with comprehensive trajectory logging to prevent "fishing expeditions" and ensure every search operation has clear reasoning.

**This catches**:
- Hallucinated reasoning that happened to reach a correct answer
- Brittle approaches that work by accident
- Missed edge cases in the reasoning process
- Searches without clear goals that waste tokens
- Fishing expeditions (searching without expected outcomes)

## Intent-First Search Protocol

### Before Search: State Three Things

Before running a search, state:

1. **Intent** - the specific target (e.g., "JWT authentication entry points", not "authentication stuff").
2. **Rationale** - why this search serves the current task, not a generic "to understand the code".
3. **Expected outcome** - a specific prediction and what would count as success (e.g., "1-3 token validation functions").

Record these as the search's `intent` phase log entry (see JSONL Log Format below) before the search runs. Refine the reasoning instead of searching when: the expected outcome can't be stated, the intent is broad enough to return more than 100 results, or the same search already ran with a slight variation.

## JSONL Log Format

Logs live at `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl` (e.g. `implementing-tasks-2025-12-27.jsonl`). Each line is a complete JSON object (newline-delimited):

```jsonl
{"ts":"2025-12-27T10:30:00Z","agent":"implementing-tasks","phase":"intent","intent":"Find JWT authentication entry points","rationale":"Task requires extending auth; need patterns first","expected_outcome":"Should find 1-3 token validation functions"}
{"ts":"2025-12-27T10:30:05Z","agent":"implementing-tasks","phase":"execute","mode":"ck","query":"JWT token validation authentication","path":"/abs/path/src/auth/","top_k":10,"threshold":0.5}
{"ts":"2025-12-27T10:30:07Z","agent":"implementing-tasks","phase":"result","result_count":3,"high_signal":2,"tokens_estimated":450}
{"ts":"2025-12-27T10:30:10Z","agent":"implementing-tasks","phase":"cite","citations":[{"claim":"System uses JWT validation","code":"export async function validateToken()","path":"/abs/path/src/auth/jwt.ts","line":45}]}
```

### Search Phases

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

## Fishing Expeditions

A "fishing expedition" is a search without clear purpose - also: ignoring unexpected results and continuing anyway, and paginating through results without evaluating them.

### Prevention Rules

| Scenario | Action |
|----------|--------|
| Search returns unexpected results | Log discrepancy, reassess rationale |
| Search returns 0 results | Reformulate query OR flag as Ghost Feature |
| Search returns >50 results | LOG TRAJECTORY PIVOT, then narrow |
| No clear expected_outcome | STOP - clarify reasoning before searching |
| >3 similar searches in 10 min | FLAG as inefficient, require justification |

### Trajectory Pivot (>50 Results)

When search returns >50 results, log a pivot entry before narrowing:

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

---

## Grounding Types

| Type | Description | Required Fields | Example |
|------|-------------|-----------------|---------|
| `citation` | Direct quote from code | `code`, `path`, `line` | `export async function validateToken()` |
| `code_reference` | Reference to existing code (no quote) | `file`, `line` | "Auth module at src/auth/" |
| `assumption` | Ungrounded claim | `assumption`, `flag` | "Likely caches tokens [ASSUMPTION]" |
| `user_input` | Based on user's explicit request | `message_id` or `source` | "User wants JWT support" |

Flag every ungrounded claim with `[ASSUMPTION]` and log it as its own `assumption`-phase entry (fields above).

## Evaluation by reviewing-code Agent

When auditing a completed task:

1. Load the trajectory log for the implementing agent.
2. Check each step for ungrounded assumptions, reasoning jumps (conclusions without steps), and contradictions with previous steps.
3. Flag issues in a short report naming the step, the problem, and a recommendation - e.g. "Step 5: ungrounded assumption about cache TTL. Step 8: reasoning jump, no explanation for the architecture choice. Recommendation: request clarification on steps 5 and 8 before approval."

## Evaluation-Driven Development (EDD)

Before marking a task complete, agents create 3 diverse test scenarios (happy path, edge case, adversarial), verify each is covered by the implementation, and log the scenario creation in the trajectory.

## Outcome Validation

After search execution, validate results against the expected outcome:

### Match (Expected)

**Example**: expected "1-3 token validation functions", found 2 (`validateToken`, `verifyToken`). **Action**: log `"outcome_match": "match"`, proceed with synthesis.

### Partial (Some Unexpected)

**Example**: expected "JWT validation functions", found 2 validation functions plus 5 configuration files. **Action**: log `"outcome_match": "partial"`, extract the relevant subset.

### Mismatch (Unexpected)

**Example**: expected "JWT validation in auth module", found OAuth2 flows, SAML handlers, legacy auth. **Action**: log `"outcome_match": "mismatch"`, reassess the rationale, refine the query.

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

### Zero Results (Ghost Feature?)

**Example**: expected "OAuth2 SSO login flow", found 0 results. **Action**: perform Negative Grounding (a second, diverse query), and potentially flag as a Ghost Feature.

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

## Trajectory Audit

Query trajectory logs directly:

```bash
grep '"grounding":"assumption"' grimoires/loa/a2a/trajectory/implementing-tasks-2025-12-27.jsonl   # assumptions
grep '"phase":"pivot"' grimoires/loa/a2a/trajectory/implementing-tasks-2025-12-27.jsonl             # pivots
total=$(grep '"phase":"cite"' trajectory.jsonl | wc -l); grounded=$(grep '"grounding":"citation"' trajectory.jsonl | wc -l); echo "scale=2; $grounded / $total" | bc  # grounding ratio
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
| 30-365 days | Archived | Compress to .jsonl.gz (via `.claude/scripts/compact-trajectory.sh`) |
| >365 days | Purged | Delete archives |

To preserve a trajectory permanently: `mv grimoires/loa/a2a/trajectory/<file>.jsonl grimoires/loa/a2a/trajectory/archive/`

## Communication Guidelines

State outcomes plainly to the user (e.g. "Found 3 high-relevance files for authentication work") and never expose internal logging mechanics (e.g. "Logging intent phase to trajectory..."). Track the log file path, current phase, grounding type, and outcome-validation results internally; never surface them to the user.

---

## Integration with Other Protocols

### Tool Result Clearing

After logging `phase: "result"`, apply Tool Result Clearing if `result_count > 20` or `tokens_estimated > 2000`:

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

Before completing a task, verify the trajectory log:

- [ ] All searches have an intent phase logged
- [ ] All results have outcome validation
- [ ] All citations logged with code quotes
- [ ] Zero unflagged assumptions
- [ ] Grounding ratio >= 0.95

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

## Session Handoff Phase

> **Protocol**: See `.claude/protocols/session-continuity.md`
> **Paradigm**: Clear, Don't Compact

The `session_handoff` phase is logged when context is cleared via `/clear`.

```jsonl
{"ts":"2024-01-15T14:30:00Z","agent":"implementing-tasks","phase":"session_handoff","session_id":"sess-002","root_span_id":"span-def","bead_id":"beads-x7y8","notes_refs":["grimoires/loa/NOTES.md:68-92"],"edd_verified":true,"grounding_ratio":0.97,"test_scenarios":3,"next_session_ready":true}
```

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

The `root_span_id` tracks work across session boundaries. Query lineage: `grep '"root_span_id":"span-abc"' grimoires/loa/a2a/trajectory/*.jsonl`

## Delta Sync Phase

The `delta_sync` phase is logged at the 5,000-token accumulated threshold (see `.claude/protocols/tool-result-clearing.md`) for partial persistence.

```jsonl
{"ts":"2024-01-15T12:00:00Z","agent":"implementing-tasks","phase":"delta_sync","tokens":5000,"decisions_persisted":3,"bead_updated":true,"notes_updated":true}
```

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Always `"delta_sync"` |
| `tokens` | number | Approximate token count at sync |
| `decisions_persisted` | number | Number of decisions written to NOTES.md |
| `bead_updated` | boolean | Whether active Bead was updated |
| `notes_updated` | boolean | Whether NOTES.md was updated |

Delta sync survives an unexpected session end without an explicit `/clear`; recovery resumes from this state.

## Grounding Check Phase

> **Protocol**: See `.claude/protocols/grounding-enforcement.md`

The `grounding_check` phase is logged during the synthesis checkpoint.

```jsonl
{"ts":"2024-01-15T14:29:00Z","agent":"implementing-tasks","phase":"grounding_check","total_claims":20,"grounded_claims":19,"assumptions":1,"grounding_ratio":0.95,"threshold":0.95,"status":"pass"}
```

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Always `"grounding_check"` |
| `total_claims` | number | Total decisions/claims in session |
| `grounded_claims` | number | Claims with code citations |
| `assumptions` | number | Claims marked as [ASSUMPTION] |
| `grounding_ratio` | number | grounded_claims / total_claims |
| `threshold` | number | Required minimum (default 0.95) |
| `status` | string | `"pass"` or `"fail"` |

Enforcement: **strict mode** blocks `/clear` if status is `"fail"`; **warn mode** shows a warning but permits `/clear`; **disabled** applies no enforcement.
