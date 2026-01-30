---
name: iterating-feedback
description: Close the feedback loop by updating upstream artifacts from test results. Use when test failures need to be traced back to canvases, journeys, or diagrams.
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Edit
---

# Iterating Feedback

Close the feedback loop by analyzing test results and proposing updates to upstream artifacts (canvases, journeys, diagrams, tests).

---

## Triggers

```
/iterate {journey-id}                        # Analyze latest results, propose updates
/iterate {journey-id} --add-gap "{description}"  # Add gap from visual testing
/iterate {journey-id} --apply                # Apply proposed updates
```

**Examples:**
```bash
/iterate deposit-flow
/iterate rewards-display --add-gap "spinner persists after completion"
/iterate deposit-flow --apply
```

---

## Analyze Mode (Default)

### Step 1: Load Latest Results

Find most recent results:
```bash
grimoires/crucible/results/*-{journey-id}/
```

Read:
- `report.md` - Test summary
- `screenshots/` - Failure screenshots
- `traces/` - Playwright traces (if available)

### Step 2: Load Journey Context

Read related files:
- `grimoires/lens/journeys/{journey-id}.md`
- `grimoires/crucible/diagrams/{journey-id}-diagram.md`
- `grimoires/crucible/tests/{journey-id}.spec.ts`
- Source canvases from journey frontmatter

### Step 3: Classify Issues

Analyze failures and classify:

| Issue Type | Pattern | Root Cause |
|------------|---------|------------|
| **Selector Not Found** | `locator.toBeVisible() failed` | Selector mismatch or missing element |
| **Timeout** | `Timeout 30000ms exceeded` | Slow load or missing element |
| **Unexpected Text** | `toContainText("X") received "Y"` | Copy change or wrong expectation |
| **Visual Diff** | Screenshot mismatch | UI change or regression |
| **Assertion Failed** | `expect received: false` | Logic error or state issue |
| **Network Error** | `net::ERR_*` | API failure or CORS |

### Step 4: Map Issues to Root Causes

For each classified issue, determine upstream artifact:

```markdown
## Issue Analysis

### Issue 1: Selector Not Found

**Error**: `locator('[data-testid="deposit-success"]').toBeVisible()`
**Classification**: Selector Not Found

**Root Cause Investigation**:
1. Check if selector exists in codebase
2. Check if selector changed
3. Check if component rendered

**Upstream Impact**:
- Diagram: Update state mapping table (selector column)
- Test: Update selector in test file

### Issue 2: Timeout on Approval

**Error**: `Timeout 120000ms exceeded waiting for approval`
**Classification**: Timeout

**Root Cause Investigation**:
1. Wallet interaction required (expected)
2. Check if marked as ACTION REQUIRED
3. Check if timeout appropriate

**Upstream Impact**:
- Journey: Add known gap "Wallet timeout in automated tests"
- Test: Add skip condition for CI
```

### Step 5: Generate Proposals

Create update proposals:

```markdown
## Proposed Updates

### 1. Update Diagram State Mapping

**File**: grimoires/crucible/diagrams/deposit-flow-diagram.md

**Current**:
| State | Selector | Assertion |
|-------|----------|-----------|
| Complete | `[data-testid="deposit-success"]` | `toBeVisible()` |

**Proposed**:
| State | Selector | Assertion |
|-------|----------|-----------|
| Complete | `[data-testid="deposit-complete-message"]` | `toBeVisible()` |

**Reason**: Selector changed in commit abc123

---

### 2. Update Test Selector

**File**: grimoires/crucible/tests/deposit-flow.spec.ts

**Current**:
```typescript
await expect(page.locator('[data-testid="deposit-success"]')).toBeVisible();
```

**Proposed**:
```typescript
await expect(page.locator('[data-testid="deposit-complete-message"]')).toBeVisible();
```

**Reason**: Match actual DOM element

---

### 3. Add Known Gap to Journey

**File**: grimoires/lens/journeys/deposit-flow.md

**Add to Known Gaps table**:
| Gap | Type | Source Canvas | Resolution |
|-----|------|---------------|------------|
| Wallet timeout in automated tests | Limitation | - | Mark ACTION REQUIRED in tests |

**Reason**: Wallet interactions cannot be automated without mocks
```

### Step 6: Display Analysis

```
┌─────────────────────────────────────────────────────────────────┐
│ REFINE ANALYSIS: deposit-flow                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Latest Test: 2026-01-29T10:35:00Z                             │
│  Status: FAILED (2/3 passed)                                   │
│                                                                 │
│  Issues Found:                                                  │
│  ─────────────                                                  │
│  1. Selector Not Found                                         │
│     - [data-testid="deposit-success"]                          │
│     - Impact: Diagram, Test                                    │
│                                                                 │
│  Proposed Updates:                                              │
│  ─────────────────                                              │
│  1. Diagram: Update state mapping (Complete state)             │
│  2. Test: Update selector line 45                              │
│  3. Journey: Add known gap (wallet timeout)                    │
│                                                                 │
│  Confidence: HIGH (selector change detected in codebase)       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Next Steps:
  - Review proposals above
  - Apply updates: /iterate deposit-flow --apply
  - Or manually edit files
```

### Step 7: Track in Refinements Log

Create/update `grimoires/crucible/refinements/{journey-id}-refinements.md`:

```markdown
---
journey: {journey-id}
created: {timestamp}
updated: {timestamp}
total_refinements: {n}
---

# Refinement History: {journey-id}

## Refinement {n}: {timestamp}

### Source
- **Test Run**: grimoires/crucible/results/{timestamp}-{journey-id}/
- **Status**: Failed (2/3)

### Issues Identified
1. Selector Not Found: `[data-testid="deposit-success"]`
2. Timeout: Wallet approval step

### Updates Proposed
1. Diagram state mapping update (HIGH confidence)
2. Test selector update (HIGH confidence)
3. Journey known gap addition (MEDIUM confidence)

### Resolution
- [ ] Diagram updated
- [ ] Test updated
- [ ] Journey updated
- [ ] Re-test passed

---

## Refinement {n-1}: {timestamp}

...
```

---

## Add Gap Mode (`--add-gap`)

Manually add expectation gap from visual testing or Agentation feedback.

### Step 1: Parse Gap Description

```bash
/iterate deposit-flow --add-gap "spinner persists after completion"
```

### Step 2: Find Target Canvas

From journey `source_canvases`, select most relevant canvas.
If multiple canvases, add to all.

### Step 3: Update Canvas

Add to Expectation Gaps table:

```markdown
## Expectation Gaps

| Expected | Actual | Source | Resolution |
|----------|--------|--------|------------|
| Spinner disappears | Spinner persists | visual-testing | pending |
```

### Step 4: Update Journey

Add to Known Gaps:

```markdown
## Known Gaps

| Gap | Type | Source Canvas | Resolution |
|-----|------|---------------|------------|
| Spinner persists after completion | Bug | visual-testing | pending |
```

### Step 5: Track in Refinements Log

```markdown
## Refinement {n}: {timestamp}

### Source
- **Method**: Visual Testing (--add-gap)
- **Description**: "spinner persists after completion"

### Updates Applied
1. Canvas: Added expectation gap
2. Journey: Added known gap

### Resolution
- [x] Gap documented
- [ ] Bug filed
- [ ] Fix implemented
- [ ] Re-tested
```

### Step 6: Report Output

```
✓ Gap added to deposit-flow

Updates Applied:
  - Canvas: papa-flavio-canvas.md (Expectation Gaps table)
  - Journey: deposit-flow.md (Known Gaps table)
  - Refinements: deposit-flow-refinements.md

Gap Details:
  Expected: Normal behavior
  Actual: Spinner persists after completion
  Source: visual-testing
  Resolution: pending

Next Steps:
  - File bug if applicable
  - Update diagram with error state: /diagram deposit-flow --update
  - Re-test after fix: /validate deposit-flow --run
```

---

## Apply Mode (`--apply`)

Apply previously proposed updates.

### Step 1: Load Proposals

Read proposals from analyze mode output or refinements log.

### Step 2: Apply Updates

For each proposal:
1. Read target file
2. Apply change using Edit tool
3. Verify file valid

### Step 3: Update Refinements Log

Mark resolutions as complete:

```markdown
### Resolution
- [x] Diagram updated
- [x] Test updated
- [x] Journey updated
- [ ] Re-test passed
```

### Step 4: Prompt Re-test

```
✓ Updates applied

Files Modified:
  - grimoires/crucible/diagrams/deposit-flow-diagram.md
  - grimoires/crucible/tests/deposit-flow.spec.ts
  - grimoires/lens/journeys/deposit-flow.md

Refinement logged at: grimoires/crucible/refinements/deposit-flow-refinements.md

Next Steps:
  - Re-run tests: /validate deposit-flow --run
  - Verify fixes in browser
```

---

## Issue Classification Reference

### Selector Issues

**Symptoms**:
- `locator.toBeVisible()` failed
- `locator.click()` failed
- Element not found

**Investigation**:
1. `grep -r "data-testid" src/` to find actual selectors
2. Check git log for selector changes
3. Verify component renders

**Fixes**:
- Update selector in diagram state mapping
- Update selector in test file

### Timing Issues

**Symptoms**:
- Timeout exceeded
- Element not found (intermittent)
- Race condition

**Investigation**:
1. Check network requests
2. Check loading states
3. Check async operations

**Fixes**:
- Increase timeout
- Add wait condition
- Add loading state assertion

### Content Issues

**Symptoms**:
- Text mismatch
- Value mismatch
- Count mismatch

**Investigation**:
1. Check for copy changes
2. Check for locale/formatting
3. Check data source

**Fixes**:
- Update expected text
- Add flexible matcher
- Update test data

### State Issues

**Symptoms**:
- Wrong state reached
- Missing state
- Unexpected branch

**Investigation**:
1. Review state machine
2. Check transition triggers
3. Check guards/conditions

**Fixes**:
- Update diagram transitions
- Add missing states
- Fix journey steps

---

## Integration Points

- **validating-journeys**: Test results as input
- **diagramming-states**: Diagram updates as output
- **shaping-journeys**: Journey updates as output
- **observing-users**: Canvas updates as output
- **Agentation**: Visual feedback via `--add-gap`

---

## Validation

Before applying updates:
- [ ] Proposals reviewed by human
- [ ] Changes make sense for issue
- [ ] No breaking changes to other tests
- [ ] Refinement logged

---

## Error Handling

| Error | Resolution |
|-------|------------|
| No results found | Run /validate --run first |
| No failures to analyze | Report success, no refinement needed |
| Cannot determine root cause | Flag for manual review |
| File update failed | Report error, rollback if partial |

---

## Related

- `/validate` - Generate and run tests
- `/diagram` - Update diagrams
- `/shape` - Update journeys
- `/observe` - Update canvases
