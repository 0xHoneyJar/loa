# Example: Complete Diagnostic

Full walkthrough of the hypothesis-first observation process.

---

## Input

**Command**: `/observe @papa-flavio "Im planning some henlo burns so gud to know how much im receiving"`

**Context**: Discord #general, 2026-01-19

---

## Generated Canvas

```markdown
---
type: user-canvas
user: papa-flavio
created: 2026-01-19T10:00:00Z
updated: 2026-01-19T10:00:00Z
linked_journeys: []
linked_observations: []
status: active
---

# papa-flavio Canvas

## User Profile

| Field | Value |
|-------|-------|
| **Signals Observed** | Mentions "planning" + "burns" + wants to know "how much" |
| **Theories** | May be optimizing burn timing; may be tracking for tax/reporting; may be validating expectations |
| **Confidence** | Low (single quote, no behavioral history) |
| **Unknown** | Portfolio size; burn frequency; why timing matters to them; what "gud to know" means specifically |
| **Stakes** | Has HENLO holdings (amount unknown) |

---

## Level 3 Hypotheses

### Hypothesis 1: Optimizing burn timing based on accumulation
- **Quote anchor**: "planning some henlo burns"
- **Alternative interpretations**:
  - Could be planning burn for specific date (tax year end)
  - Could be comparing burn vs hold strategy
  - Could be following someone else's advice about burns
- **Confidence**: Low
- **What would validate**: Asks about optimal timing; mentions threshold; returns to check accumulation
- **What would invalidate**: Burns immediately without checking; says they burn randomly

### Hypothesis 2: Validating reward expectations before action
- **Quote anchor**: "gud to know how much im receiving"
- **Alternative interpretations**:
  - Could be checking if rewards match documentation
  - Could be confused about reward mechanics
  - Could just be curious (no action planned)
- **Confidence**: Low
- **What would validate**: Compares stated rewards to actual; asks clarifying questions about rates
- **What would invalidate**: Never mentions rewards again; doesn't check values

---

## Future Promises (Unvalidated)

| Promise | Date | Follow-up Trigger |
|---------|------|-------------------|
| (none in this quote) | - | - |

---

## Journey Fragments

| Trigger | Action | Expected | Actual | Emotion |
|---------|--------|----------|--------|---------|
| Planning burns | Checked rewards display | See accumulation amount | (unknown) | Positive ("gud") |

---

## Expectation Gaps

| Expected | Actual | Source | Resolution |
|----------|--------|--------|------------|
| (none identified yet) | | | |

---

## Quotes Library

> "Im planning some henlo burns so gud to know how much im receiving" — Discord #general, 2026-01-19

---

## Conversation Frameworks

**If they mention burn timing:**
- Opener: "You mentioned planning some burns. How's that going?"
- Dig deeper: "Walk me through how you decide when to burn."
- Past behavior: "When was your last burn? What triggered that decision?"

**If they mention rewards:**
- Opener: "You were checking your rewards. Did the numbers make sense?"
- Dig deeper: "What were you looking for specifically?"
- Comparison: "How does that compare to what you expected?"

**Red flags to listen for:**
- "I would probably burn when..." (hypothetical)
- "The burn feature sounds useful" (politeness without commitment)
- "I'll check back later" (another promise, not action)
```

---

## Follow-Up Example

### Second Quote (1 day later)

**Command**: `/observe @papa-flavio "I burn when I hit 50k, but sidebar stopped updating 2 days ago"`

### Updated Hypothesis Section

```markdown
### Hypothesis 1: Optimizing burn timing based on accumulation threshold
- **Quote anchor**: "I burn when I hit 50k"
- **Alternative interpretations**:
  - Could be arbitrary round number
  - Could be gas optimization strategy
  - Could be external commitment (told someone they'd burn at 50k)
- **Confidence**: Medium (specific number + past behavior pattern)
- **What would validate**: Asks about gas costs relative to threshold; checks price before burning
- **What would invalidate**: Burns at different amounts; says "I just pick a number"

### Hypothesis 2: [VALIDATED → Promoted to Observation]
The second quote confirms they do check rewards before burning. This is no longer a hypothesis.

---

## Validated Observations

### Observation 1: Uses 50k threshold for burn timing
- **Evidence**: "I burn when I hit 50k"
- **Behavior type**: Habitual, rule-based
- **Confidence**: Medium-High (stated past behavior pattern)
```

### New Gap Identified

```markdown
## Expectation Gaps

| Expected | Actual | Source | Resolution |
|----------|--------|--------|------------|
| Sidebar shows live rewards | Sidebar stale for 2 days | Quote 2026-01-20 | BUG - investigate |
```

### Updated Promises Table

```markdown
## Future Promises (Unvalidated)

| Promise | Date | Follow-up Trigger |
|---------|------|-------------------|
| (none - user described past behavior, not future intent) | - | - |
```

---

## Key Differences from Old Format

| Old Format | New Format |
|------------|------------|
| `Type: Decision-maker` | `Theories: May be optimizing timing...` |
| `Level 3 Goal: Optimize burn timing` | `Hypothesis 1: Optimizing burn timing...` |
| High confidence from single quote | Low confidence, explicit unknowns |
| "Insights Extracted" section | Removed (insights only after validation) |
| Generic Mom Test questions | Conversation Frameworks anchored to their words |

---

## Validation Checklist

After generating canvas:
- [x] No user type classification from username
- [x] "Hypothesis" language (not "Goal")
- [x] Confidence level explicit (Low/Medium)
- [x] Unknown field populated
- [x] Alternative interpretations listed
- [x] Validation/invalidation criteria specified
- [x] Conversation frameworks use their exact words
- [x] No "Insights" section (premature)
