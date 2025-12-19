# Candidate Surfacer Library

This library provides patterns for detecting ADR and Learning candidates during Loa phase execution and surfacing them to Linear for team review.

---

## Overview

The candidate surfacer automatically detects significant architectural decisions and proven patterns during Loa execution. Candidates are collected during phase execution and presented to the user at phase end for optional submission to Linear.

**Flow**:
```
Phase Execution → Candidate Detection → Batch Collection → User Review → Linear Submission
```

**Non-Blocking Principle**: Candidate surfacing NEVER blocks phase execution. The phase completes normally, then candidates are presented for optional action.

---

## ADR Candidate Detection

### What Qualifies as an ADR Candidate?

An ADR (Architecture Decision Record) candidate is a significant technical decision that:
- Affects system architecture or design
- Has considered alternatives
- Has clear rationale and trade-offs
- Would benefit from documentation for future reference

### Detection Patterns

Scan agent output for these patterns:

#### Pattern 1: Explicit Decision Statement
```
Triggers:
- "We decided to use X instead of Y"
- "Choosing X over Y because Z"
- "After evaluating, we selected X"
- "The decision is to use X"
- "Going with X rather than Y"
```

#### Pattern 2: Trade-off Discussion
```
Triggers:
- "The trade-off is..."
- "Pros and cons of..."
- "On one hand... on the other hand..."
- "While X offers... Y provides..."
- "Considered alternatives:"
```

#### Pattern 3: Architecture Phase Decisions
```
Triggers:
- Major technology selections (database, framework, infrastructure)
- Integration approach decisions
- API design choices
- Data model decisions
- Security architecture choices
```

### ADR Extraction Format

When a candidate is detected, extract:

```json
{
  "type": "adr-candidate",
  "decision": "{What was decided}",
  "context": "{Why this decision was needed}",
  "alternatives": [
    {
      "option": "{Alternative 1}",
      "reason_rejected": "{Why not chosen}"
    },
    {
      "option": "{Alternative 2}",
      "reason_rejected": "{Why not chosen}"
    }
  ],
  "rationale": "{Why this approach was chosen}",
  "trade_offs": {
    "pros": ["{Benefit 1}", "{Benefit 2}"],
    "cons": ["{Drawback 1}", "{Drawback 2}"]
  },
  "source": {
    "phase": "architect",
    "file": "loa-grimoire/sdd.md",
    "section": "{Section reference}"
  },
  "confidence": "high|medium|low"
}
```

### False Positive Filters

**Ignore These**:
- Minor implementation choices (variable names, formatting)
- Obvious defaults with no alternatives considered
- Configuration choices with no architectural impact
- Temporary decisions marked as "for now" or "placeholder"
- Style/preference choices without technical rationale

**Confidence Scoring**:
| Factor | Score Impact |
|--------|--------------|
| Explicit "decided" language | +2 |
| Multiple alternatives discussed | +2 |
| Trade-offs documented | +1 |
| Cross-component impact | +1 |
| Minor/localized impact | -1 |
| Missing rationale | -2 |

Candidates with score < 2 are filtered as low confidence.

---

## Learning Candidate Detection

### What Qualifies as a Learning Candidate?

A Learning candidate is a proven pattern that:
- Emerged from actual implementation
- Solved a real problem effectively
- Has evidence of success (working code, tests, metrics)
- Would help others facing similar challenges

### Detection Patterns

Scan implementation reports and review feedback for these patterns:

#### Pattern 1: Discovery Statement
```
Triggers:
- "We discovered that X works better"
- "This approach proved more effective"
- "Lesson learned: X"
- "Key insight: X"
- "Found that X solves Y"
```

#### Pattern 2: Pattern Emergence
```
Triggers:
- "This pattern emerged..."
- "The successful approach was..."
- "What worked well: X"
- "This technique consistently..."
- "Recommended approach: X"
```

#### Pattern 3: Implementation Insight
```
Triggers:
- Performance improvements with specific numbers
- Bug fixes revealing deeper patterns
- Refactoring outcomes with measurable results
- Testing insights about edge cases
```

### Learning Extraction Format

When a candidate is detected, extract:

```json
{
  "type": "learning-candidate",
  "pattern": "{What was learned}",
  "context": "{When/where this applies}",
  "evidence": {
    "implementation": "{file}:{lines}",
    "tests": "{test file}:{lines}",
    "results": "{metrics, outcomes}"
  },
  "recommended_application": "{When others should use this pattern}",
  "source": {
    "phase": "implement|review",
    "sprint": "sprint-N",
    "file": "loa-grimoire/a2a/sprint-N/reviewer.md"
  },
  "confidence": "high|medium|low"
}
```

### False Positive Filters

**Ignore These**:
- Obvious best practices already documented
- One-off fixes without broader applicability
- Personal preferences without evidence
- Speculative improvements without validation
- Framework/library documentation (external knowledge)

**Confidence Scoring**:
| Factor | Score Impact |
|--------|--------------|
| Explicit "learned" language | +2 |
| Evidence with file references | +2 |
| Measurable outcomes | +1 |
| Cross-project applicability | +1 |
| Single instance only | -1 |
| No concrete evidence | -2 |

Candidates with score < 2 are filtered as low confidence.

---

## Batch Collection

### Collection Strategy

Candidates are accumulated during phase execution:

```markdown
## Phase Execution

1. **Start Phase**
   - Initialize empty candidate collections:
     - `adr_candidates = []`
     - `learning_candidates = []`

2. **During Phase**
   - Continuously scan agent output for patterns
   - On pattern match, extract candidate data
   - Apply false positive filter
   - If passes filter, add to appropriate collection

3. **Phase End**
   - Count collected candidates
   - Prepare summary for user review
```

### In-Memory Storage

During phase execution, store candidates temporarily:

```markdown
## Candidate Memory Structure

For each phase invocation, maintain:

```
PHASE_CANDIDATES = {
  "phase": "architect",
  "sprint": "sprint-1",
  "timestamp": "2025-12-19T10:30:00Z",
  "adr_candidates": [
    { ... candidate 1 ... },
    { ... candidate 2 ... }
  ],
  "learning_candidates": [
    { ... candidate 1 ... }
  ]
}
```

This is ephemeral - only persisted if user approves submission.
```

---

## Batch Review UX

### Summary Display

At phase end, show candidate summary:

```markdown
## Candidates Detected

After completing the Architecture phase, the following candidates were detected:

**ADR Candidates**: 2 found
- Database Selection: PostgreSQL over MongoDB
- API Design: REST over GraphQL for v1

**Learning Candidates**: 0 found

---

**What would you like to do?**

[Submit all to Linear] [Review each first] [Skip for now]
```

### Review Mode

If user selects "Review each first":

```markdown
## ADR Candidate 1 of 2

**Decision**: Use PostgreSQL over MongoDB for user data storage

**Context**: Need a database for storing user profiles and quest progress

**Alternatives Considered**:
1. MongoDB - Rejected because schema validation needs were high
2. SQLite - Rejected because multi-user concurrency needed

**Rationale**: PostgreSQL's strong typing and relational model fits our structured data needs

**Trade-offs**:
- Pros: ACID compliance, mature tooling, Supabase integration
- Cons: Less flexible schema, slightly more complex queries for nested data

---

[Include in submission] [Exclude] [Edit before submit]
```

### Skip Behavior

If user selects "Skip for now":
- Candidates are discarded
- No persistent storage
- User can manually create issues later if needed
- Phase proceeds normally

---

## Linear Issue Creation

### ADR Candidate Template

```markdown
## Linear Issue Structure

**Title**: [ADR-Candidate] {Decision Summary}

**Project**: {Product Home ID from integration-context.md}

**Labels**:
- `adr-candidate`
- `sprint:{current-sprint}`
- `agent:architect` (if from architecture phase)
- `agent:implementer` (if from implementation phase)

**Body**:
```md
## [ADR-Candidate] {Decision Title}

**Source**: Loa {Phase} Phase
**Sprint**: {sprint-name}
**Date**: {timestamp}

### Decision
{Extracted decision statement}

### Context
{Why this decision was needed}

### Alternatives Considered
1. **{Alternative 1}** - {Why rejected}
2. **{Alternative 2}** - {Why rejected}

### Rationale
{Why this approach was chosen}

### Trade-offs
**Pros**:
- {Benefit 1}
- {Benefit 2}

**Cons**:
- {Drawback 1}
- {Drawback 2}

### References
- Loa SDD: `loa-grimoire/sdd.md#{section}`
- Related ADRs: {links if referenced}

---
*Auto-surfaced by Loa. Review in biweekly Hivemind cycle.*
```
```

### Learning Candidate Template

```markdown
## Linear Issue Structure

**Title**: [Learning-Candidate] {Pattern Summary}

**Project**: {Product Home ID from integration-context.md}

**Labels**:
- `learning-candidate`
- `sprint:{current-sprint}`
- `agent:implementer` (if from implementation phase)
- `agent:reviewer` (if from review phase)

**Body**:
```md
## [Learning-Candidate] {Pattern Title}

**Source**: Loa {Phase} Phase
**Sprint**: {sprint-name}
**Date**: {timestamp}

### Pattern Discovered
{What was learned}

### Context
{When/where this applies}

### Evidence
- Implementation: `{file}:{lines}`
- Tests: `{test file}`
- Results: {metrics, outcomes}

### Recommended Application
{When others should use this pattern}

### References
- Loa Sprint Report: `loa-grimoire/a2a/sprint-N/reviewer.md`
- Related Learning Memos: {links if any}

---
*Auto-surfaced by Loa. Review in biweekly Hivemind cycle.*
```
```

### Linear MCP Usage

```markdown
## Creating ADR Candidate Issue

Use the Linear MCP to create issues:

```typescript
mcp__linear__create_issue({
  teamId: "{from integration-context.md}",
  title: "[ADR-Candidate] {decision summary}",
  projectId: "{Product Home ID}",
  labelIds: [
    "{adr-candidate-label-id}",
    "{sprint-label-id}"
  ],
  description: "{ADR template filled}"
})
```

## Creating Learning Candidate Issue

```typescript
mcp__linear__create_issue({
  teamId: "{from integration-context.md}",
  title: "[Learning-Candidate] {pattern summary}",
  projectId: "{Product Home ID}",
  labelIds: [
    "{learning-candidate-label-id}",
    "{sprint-label-id}"
  ],
  description: "{Learning template filled}"
})
```

## Finding Labels

First, query for existing labels or create if needed:

```typescript
// Search for existing label
mcp__linear__list_labels({
  filter: { name: { eq: "adr-candidate" } }
})

// If not found, create it
mcp__linear__create_label({
  teamId: "{team-id}",
  name: "adr-candidate",
  color: "#0ea5e9"  // Blue for ADRs
})
```
```

---

## Fallback Handling

### Linear Unavailable

If Linear MCP is unavailable or request fails:

```markdown
## Fallback: Pending Candidates File

When Linear is unavailable:

1. Save candidates to `loa-grimoire/pending-candidates.json`:
```json
{
  "saved_at": "2025-12-19T10:30:00Z",
  "reason": "Linear MCP unavailable",
  "candidates": [
    {
      "type": "adr-candidate",
      "title": "[ADR-Candidate] Database Selection",
      "body": "...",
      "labels": ["adr-candidate", "sprint:sprint-1"]
    }
  ]
}
```

2. Show message to user:
```
Could not connect to Linear. 3 candidates saved to:
loa-grimoire/pending-candidates.json

To submit later:
1. Verify Linear MCP is configured (/setup)
2. Run: /submit-pending-candidates
```

3. Phase continues normally (non-blocking)
```

### No Product Home Configured

If Product Home ID is not in integration-context.md:

```markdown
## Fallback: Team Default Project

If no Product Home:
1. Use team's default project
2. Or prompt user during submission:
   "No Product Home linked. Submit to default project? [Yes] [Skip]"
```

---

## Integration Points

### Phase: Architecture (`/architect`)

```markdown
## Surfacing Integration

After SDD is written:

1. **Scan SDD content** for ADR patterns
2. **Collect candidates** in memory
3. **Complete phase normally** (SDD saved)
4. **Show batch review prompt** (non-blocking)
5. **If approved**: Create Linear issues
6. **Log to analytics**: Record surfacing activity
7. **Continue to next phase**
```

### Phase: Implementation (`/implement`)

```markdown
## Surfacing Integration

After implementation complete:

1. **Scan reviewer.md** for Learning patterns
2. **Collect candidates** in memory
3. **Complete phase normally** (report saved)
4. **Show batch review prompt** (non-blocking)
5. **If approved**: Create Linear issues
6. **Continue to review phase**
```

### Phase: Review (`/review-sprint`)

```markdown
## Surfacing Integration

After review complete:

1. **Scan engineer-feedback.md** for Learning patterns
2. **Collect candidates** in memory
3. **Complete review normally** (feedback written)
4. **Show batch review prompt** (non-blocking)
5. **If approved**: Create Linear issues
```

---

## Analytics Integration

### Tracking Surfacing Activity

Log to `loa-grimoire/analytics/usage.json`:

```json
{
  "surfacing": {
    "total_adr_candidates": 5,
    "total_learning_candidates": 3,
    "submitted_to_linear": 4,
    "skipped": 4,
    "pending": 0,
    "by_sprint": {
      "sprint-1": {
        "adr_candidates": 2,
        "learning_candidates": 1,
        "submitted": 3
      }
    }
  }
}
```

---

## Configuration

### Surfacing Settings

Can be configured in `integration-context.md`:

```markdown
## Candidate Surfacing Settings

- **Auto-surface ADRs**: true
- **Auto-surface Learnings**: true
- **Confidence Threshold**: medium (score >= 2)
- **Default Action**: prompt (vs auto-submit or skip)
```

---

## Usage Example

### Full Surfacing Flow

```markdown
## During /architect Phase

1. User runs `/architect`
2. Architecture designer works through design
3. Agent discusses: "We decided to use PostgreSQL over MongoDB because..."
4. Pattern detected → ADR candidate extracted
5. Agent continues: "Choosing REST API for v1, can add GraphQL later..."
6. Another pattern detected → Second ADR candidate
7. SDD generated and saved
8. Phase output:

---

**Architecture Complete**: SDD written to loa-grimoire/sdd.md

**Candidates Detected**:
- 2 ADR candidates found
- 0 Learning candidates found

Submit to Linear? [Submit all] [Review first] [Skip]

---

9. User selects [Submit all]
10. Linear issues created:
    - LAB-101: [ADR-Candidate] Database Selection
    - LAB-102: [ADR-Candidate] API Design Approach
11. Continue to `/sprint-plan`
```

---

## Implementation Flow: ADR Detection

### Step-by-Step ADR Detection in `/architect`

```markdown
## ADR Detection Implementation

After SDD is written to `loa-grimoire/sdd.md`:

### Step 1: Read SDD Content
Read the full SDD content that was just written.

### Step 2: Pattern Matching
For each section of the SDD, check for ADR patterns:

```
PATTERNS = [
  /We decided to use (.+) instead of (.+)/i,
  /Choosing (.+) over (.+) because (.+)/i,
  /After evaluating.* we selected (.+)/i,
  /The decision is to (.+)/i,
  /Going with (.+) rather than (.+)/i,
  /Trade-off.* (.+) vs (.+)/i,
  /Pros and cons of (.+)/i,
  /Considered alternatives:/i
]
```

### Step 3: Extract Candidate Data
For each pattern match:
1. Identify the decision statement
2. Look for surrounding context (preceding paragraph)
3. Extract alternatives if mentioned
4. Extract rationale if present
5. Extract trade-offs if documented

### Step 4: Score Candidate
Apply confidence scoring:
- +2 if explicit decision language
- +2 if alternatives discussed
- +1 if trade-offs documented
- +1 if cross-component impact
- -1 if minor/localized
- -2 if no rationale

### Step 5: Filter Low Confidence
Only keep candidates with score >= 2

### Step 6: Store for Batch Review
Add passing candidates to collection:
```json
{
  "adr_candidates": [
    {
      "decision": "Use PostgreSQL over MongoDB",
      "context": "Database selection for user data storage",
      "alternatives": [...],
      "rationale": "...",
      "trade_offs": {...},
      "source": { "file": "loa-grimoire/sdd.md", "section": "3.2" },
      "confidence": "high"
    }
  ]
}
```
```

---

## Implementation Flow: Learning Detection

### Step-by-Step Learning Detection in `/implement` and `/review-sprint`

```markdown
## Learning Detection Implementation

After reviewer.md or engineer-feedback.md is written:

### Step 1: Read Phase Output
Read the relevant phase output document:
- Implementation: `loa-grimoire/a2a/sprint-N/reviewer.md`
- Review: `loa-grimoire/a2a/sprint-N/engineer-feedback.md`

### Step 2: Pattern Matching
Check for Learning patterns:

```
PATTERNS = [
  /We discovered that (.+) works better/i,
  /This approach proved more effective (.+)/i,
  /Lesson learned: (.+)/i,
  /Key insight: (.+)/i,
  /Found that (.+) solves (.+)/i,
  /This pattern emerged (.+)/i,
  /The successful approach was (.+)/i,
  /What worked well: (.+)/i,
  /This technique consistently (.+)/i,
  /Recommended approach: (.+)/i
]
```

### Step 3: Extract Candidate Data
For each pattern match:
1. Identify the pattern/learning statement
2. Look for context (when/where it applies)
3. Extract evidence (file references, test results)
4. Extract recommended application

### Step 4: Score Candidate
Apply confidence scoring:
- +2 if explicit learning language
- +2 if file/line references
- +1 if measurable outcomes
- +1 if cross-project applicability
- -1 if single instance
- -2 if no evidence

### Step 5: Filter Low Confidence
Only keep candidates with score >= 2

### Step 6: Store for Batch Review
Add passing candidates to collection:
```json
{
  "learning_candidates": [
    {
      "pattern": "Non-blocking design pattern for context injection",
      "context": "When querying external systems during phase execution",
      "evidence": {
        "implementation": ".claude/lib/context-injector.md:363-392",
        "tests": null,
        "results": "Phase never blocks on context failures"
      },
      "recommended_application": "Any phase that queries external systems",
      "source": {
        "phase": "review",
        "sprint": "sprint-2",
        "file": "loa-grimoire/a2a/sprint-2/reviewer.md"
      },
      "confidence": "high"
    }
  ]
}
```
```

---

## Batch Review Implementation

### AskUserQuestion Integration

```markdown
## Showing Batch Review Prompt

Use the AskUserQuestion tool to prompt user:

### When Candidates Exist

```json
{
  "questions": [
    {
      "question": "2 ADR candidates and 1 Learning candidate detected. What would you like to do?",
      "header": "Candidates",
      "multiSelect": false,
      "options": [
        {
          "label": "Submit all to Linear",
          "description": "Create Linear issues for all detected candidates (Recommended)"
        },
        {
          "label": "Review each first",
          "description": "Review each candidate before deciding to submit"
        },
        {
          "label": "Skip for now",
          "description": "Discard candidates and continue without submission"
        }
      ]
    }
  ]
}
```

### When No Candidates

If no candidates detected, skip the prompt entirely and proceed to next phase.

### Review Mode Flow

If user selects "Review each first":

For each candidate, prompt:
```json
{
  "questions": [
    {
      "question": "ADR Candidate 1/2: 'Use PostgreSQL over MongoDB'. Include?",
      "header": "Review",
      "multiSelect": false,
      "options": [
        {
          "label": "Include",
          "description": "Add to submission batch"
        },
        {
          "label": "Exclude",
          "description": "Skip this candidate"
        }
      ]
    }
  ]
}
```
```

---

## Linear Submission Implementation

### Full Submission Flow

```markdown
## Creating Linear Issues

### Step 1: Read Integration Context
Read `loa-grimoire/a2a/integration-context.md` for:
- Team ID
- Product Home Project ID (if configured)

### Step 2: Check/Create Labels
For each label needed (`adr-candidate`, `learning-candidate`, `sprint:sprint-N`):
1. Search for existing label
2. If not found, create it

### Step 3: Create Issues
For each approved candidate:

**ADR Candidate**:
```
mcp__linear__create_issue({
  teamId: "{team_id}",
  title: "[ADR-Candidate] {decision_summary}",
  projectId: "{product_home_id or null}",
  labelIds: ["{adr-candidate-id}", "{sprint-label-id}"],
  description: "{filled_template}"
})
```

**Learning Candidate**:
```
mcp__linear__create_issue({
  teamId: "{team_id}",
  title: "[Learning-Candidate] {pattern_summary}",
  projectId: "{product_home_id or null}",
  labelIds: ["{learning-candidate-id}", "{sprint-label-id}"],
  description: "{filled_template}"
})
```

### Step 4: Handle Failures
If Linear MCP fails:
1. Save candidates to `loa-grimoire/pending-candidates.json`
2. Show warning message
3. Continue with phase (non-blocking)

### Step 5: Log Results
Update analytics with submission results.

### Step 6: Show Confirmation
```
Created 3 Linear issues:
- LAB-101: [ADR-Candidate] Database Selection
- LAB-102: [ADR-Candidate] API Design Approach
- LAB-103: [Learning-Candidate] Non-blocking Design Pattern

Candidates will be reviewed in biweekly Hivemind cycle.
```
```

---

*Library created for Sprint 3: Candidate Surfacing*
*Based on SDD section 3.4 and Hivemind feedback loop patterns*
