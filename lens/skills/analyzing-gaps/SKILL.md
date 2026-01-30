---
name: analyzing-gaps
description: Compare user expectations (UTCs) with code reality to identify gaps. Use when you need to understand discrepancies between what users expect and what code actually does.
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Edit
---

# Analyzing Gaps

Compare user expectations captured in UTCs and journeys with actual code behavior documented in reality files. Generate structured gap reports with severity classification, JTBD impact mapping, and resolution recommendations.

---

## Trigger

```
/analyze-gap {journey-id}
/analyze-gap {journey-id} --reality {component}
/analyze-gap {journey-id} --severity-threshold {level}
```

**Examples:**
```bash
/analyze-gap reward-understanding
/analyze-gap reward-understanding --reality use-recipe-deposit-flow
/analyze-gap informed-decision --severity-threshold high
```

---

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `journey-id` | Yes | Journey identifier to analyze |
| `--reality {component}` | No | Specific reality file to compare (otherwise uses journey's linked reality) |
| `--severity-threshold {level}` | No | Filter output to show only gaps at or above this severity |
| `--update-canvases` | No | Automatically update source canvas expectation gap tables |

---

## Workflow

### Phase 1: Load Journey Context

1. Read journey file from `grimoires/lens/journeys/{journey-id}.md`
2. Extract:
   - Journey steps (trigger, action, expected, potential errors)
   - Source canvases list
   - Success condition
   - Known gaps table

### Phase 2: Load User Truth (UTCs)

For each canvas in `source_canvases`:

1. Read canvas from `grimoires/lens/canvas/{username}.md`
2. Extract:
   - Qualitative evidence (quotes)
   - JTBD (primary and secondary)
   - Expectation gap table
   - Learning status

Aggregate user expectations:
- Compile all quotes related to journey
- Map quotes to journey steps
- Identify JTBD patterns across users

### Phase 3: Load Code Reality

1. Find reality file:
   - Use `--reality {component}` if provided
   - Otherwise check journey's `reality_file` metadata
   - Otherwise search `grimoires/lens/reality/` for matches

2. Read reality file and extract:
   - States and their triggers
   - UI feedback messages
   - Error handling patterns
   - File:line evidence

### Phase 4: Step-by-Step Comparison

For each journey step:

**User Expects** (from journey + canvases):
- Expected behavior from journey step
- Related quotes from UTCs
- Implicit expectations from JTBD

**Code Does** (from reality file):
- Actual state/behavior at this step
- UI feedback provided
- Error handling in place

**Identify Gap**:
- Expectation vs implementation mismatch
- Missing functionality
- Confusing or insufficient feedback
- Error cases not handled

### Phase 5: Classify Gaps

For each identified gap, determine:

**Gap Type**:
| Type | Definition | Example |
|------|------------|---------|
| Bug | Code doesn't work as designed | Transaction fails silently |
| Feature | Functionality doesn't exist | No activity log for rebates |
| Flow | Steps are confusing or wrong order | Can't find migration button |
| Communication | Information not conveyed clearly | No explanation of what "approve" does |
| Strategy | Design decision creates friction | Too many transaction steps |

**Severity**:
| Level | Criteria |
|-------|----------|
| Critical | Blocks core functionality, data loss risk |
| High | Major friction, workaround difficult |
| Medium | Noticeable friction, workaround exists |
| Low | Minor annoyance, improvement opportunity |

**JTBD Impact**:
- Which job does this gap block or impair?
- How many users affected (from canvas learning_status)?

### Phase 6: Generate Gap Report

Create report at `grimoires/crucible/gaps/{journey-id}-gaps.md`:

```yaml
---
type: gap-report
journey: "{journey-id}"
created: "{ISO-8601}"
updated: "{ISO-8601}"
total_gaps: {N}
by_severity:
  critical: {N}
  high: {N}
  medium: {N}
  low: {N}
by_type:
  bug: {N}
  feature: {N}
  flow: {N}
  communication: {N}
  strategy: {N}
linked_reality_files:
  - {reality-file}
---
```

Include sections:
1. **Summary** - Journey metadata, analysis date
2. **Gap Registry** - Individual gap entries with full details
3. **Resolution Summary** - Table of all gaps with status
4. **Recommended Actions** - Prioritized by severity

### Phase 7: Update Linked Artifacts

1. **Update Journey** - Add `gap_report` field to frontmatter
2. **Update Source Canvases** (if `--update-canvases`):
   - Add/update entries in Expectation Gap table
   - Include file:line from reality
3. **Update state.yaml**:
   ```yaml
   gaps:
     directory: grimoires/crucible/gaps/
     count: {n+1}
     last_analysis: "{timestamp}"

   journeys:
     {journey-id}:
       gap_report: grimoires/crucible/gaps/{journey-id}-gaps.md
       gap_count: {N}
   ```

---

## Gap Entry Template

```markdown
### Gap {N}: {Short Title}

| Field | Value |
|-------|-------|
| **ID** | `GAP-{journey}-{N}` |
| **Type** | {Bug / Feature / Flow / Communication / Strategy} |
| **Severity** | {Critical / High / Medium / Low} |
| **JTBD** | `[J] {label}` |
| **Step** | {journey step number} |

**User Expects**:
> {Description of user expectation}
> Source: {canvas username}, quote: "{relevant quote}"

**Code Does**:
> {Description of actual code behavior}
> Source: `{file}:{line}` — `{code snippet or description}`

**Gap**:
{Description of the discrepancy}

**Resolution**:
| Resolution Type | Description | Status |
|-----------------|-------------|--------|
| {Bug/Feature/etc} | {What to do} | Pending / In Progress / Done |

**Linked Artifacts**:
- Canvas: `canvas/{username}.md`
- Reality: `reality/{component}-reality.md:{line}`
- Issue: `{TEAM-###}` (if filed)
```

---

## Gap Classification Reference

### Type Indicators

**Bug Indicators**:
- "X doesn't work"
- "X shows wrong value"
- "X crashes/fails"
- Error without recovery

**Feature Indicators**:
- "I wish I could..."
- "No way to see..."
- "Missing..."
- Expected functionality absent

**Flow Indicators**:
- "Couldn't find..."
- "Didn't know I had to..."
- "Too many steps"
- Navigation/discovery issues

**Communication Indicators**:
- "Didn't understand..."
- "Not clear what..."
- "No explanation"
- Information gaps

**Strategy Indicators**:
- "Why do I need to..."
- "Too complicated"
- Design-level friction

### Severity Indicators

**Critical**:
- Blocks primary user goal
- Risk of lost funds/data
- No workaround possible
- Multiple users blocked

**High**:
- Significantly impairs goal achievement
- Workaround is complex
- Primary JTBD affected

**Medium**:
- Goal achievable with friction
- Simple workaround exists
- Secondary JTBD affected

**Low**:
- Minor inconvenience
- Enhancement opportunity
- Nice-to-have

---

## Output

```
Gap Analysis Complete

Journey: {journey-id}
Source Canvases: {count} ({usernames})
Reality File: {component}

Gaps Found: {total}
  Critical: {N}
  High: {N}
  Medium: {N}
  Low: {N}

Top Priority Gaps:
  1. [Critical] {gap title} - {brief description}
  2. [High] {gap title} - {brief description}

Report: grimoires/crucible/gaps/{journey-id}-gaps.md

Next Steps:
  - File issues: /file-gap {journey-id} GAP-{journey}-1
  - Update diagram: /diagram {journey-id} --with-reality
  - Walkthrough test: /walkthrough {journey-id}
```

---

## Error Handling

| Error | Resolution |
|-------|------------|
| Journey not found | List available journeys, suggest creation |
| No source canvases | Prompt to add canvases to journey |
| Reality file not found | Suggest running `/ground` first |
| No gaps found | Report success, mark journey as aligned |
| Canvas parse error | Log error, continue with available canvases |

---

## Integration Points

- **grounding-code**: Reality files as input
- **observing-users**: UTCs as input
- **shaping-journeys**: Journeys as input
- **file-gap**: Gap reports drive issue creation
- **diagramming-states**: Gap indicators in dual diagrams
- **walking-through**: Gaps inform test focus areas

---

## Related

- `/ground` - Create reality files from code
- `/file-gap` - Create issues from gaps
- `/diagram --with-reality` - Visualize gaps in diagrams
- `/walkthrough` - Verify gaps through interactive testing
- `/iterate` - Update artifacts after gap resolution
