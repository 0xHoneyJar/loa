---
name: validating-journeys
description: Generate Playwright test scripts from state diagrams and execute them. Use when creating automated tests for user journeys or running E2E tests.
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Edit, Bash
---

# Validating Journeys

Generate Playwright E2E test scripts from state machine diagrams and execute them for user journey validation.

---

## Triggers

```
/validate {journey-id}           # Generate test script
/validate {journey-id} --run     # Execute test and capture results
/validate {journey-id} --update  # Regenerate from updated diagram
```

**Examples:**
```bash
/validate deposit-flow
/validate rewards-display --run
/validate deposit-flow --update
```

---

## Generate Mode (Default)

### Step 1: Load Diagram

Read diagram file:
```bash
grimoires/crucible/diagrams/{journey-id}-diagram.md
```

Parse:
- YAML frontmatter (journey, version)
- Mermaid state machine
- State mapping table (selectors, assertions)
- Wallet interactions

### Step 2: Parse State Machine

Extract from Mermaid:
- States (nodes)
- Transitions (edges with triggers)
- Error states
- Final states

### Step 3: Generate Test Cases

**Happy Path Test:**
- Follow main state transitions
- Assert each state reached
- Handle wallet interactions with `ACTION REQUIRED` markers

**Error Path Tests:**
- One test per error state
- Verify error state reachable
- Verify recovery path

### Step 4: Generate Test Script

Create `grimoires/crucible/tests/{journey-id}.spec.ts`:

```typescript
// =============================================================================
// GENERATED TEST FILE
// =============================================================================
// Source: grimoires/crucible/diagrams/{journey-id}-diagram.md
// Journey: {journey-id}
// Version: {diagram_version}
// Generated: {timestamp}
// Status: PENDING REVIEW
// =============================================================================
//
// IMPORTANT: This is a generated test file. Review before running.
// - Verify selectors match actual DOM elements
// - Check wallet interaction markers (ACTION REQUIRED)
// - Update test data as needed
//
// =============================================================================

import { test, expect, type Page } from '@playwright/test';

/**
 * Journey: {journey_title}
 * User Type: {primary_user_type}
 * Source Canvases: {source_canvases}
 *
 * States: {state_count}
 * Transitions: {transition_count}
 * Wallet Interactions: {wallet_count}
 */

// QA Fixtures from apps/web/components/qa-cli.tsx
const QA_FIXTURES = {
  'rewards-ready': '0x79092A805f1cf9B0F5bE3c5A296De6e51c1DEd34',
  'new-user': '0xdA0758706E9E488bc6c7Ea487FFe48c415718e95',
} as const;

test.describe('{journey-id}', () => {

  test.beforeEach(async ({ page }) => {
    // Navigate to app
    await page.goto('http://localhost:3003');

    // Set QA fixture for testing
    // await page.evaluate((addr) => {
    //   localStorage.setItem('sf-qa-effective-address', JSON.stringify({
    //     effectiveAddress: addr,
    //     fixtureName: 'rewards-ready'
    //   }));
    // }, QA_FIXTURES['rewards-ready']);
    // await page.reload();

    // Wait for app to be ready
    await page.waitForLoadState('networkidle');
  });

  test('happy path: {journey_title}', async ({ page }) => {
    // -----------------------------------------------------------------
    // State: Idle
    // -----------------------------------------------------------------
    // {state_comment}
    await expect(page.locator('[data-testid="{selector}"]')).toBeVisible();

    // -----------------------------------------------------------------
    // Transition: Idle -> {next_state}
    // Trigger: {trigger}
    // -----------------------------------------------------------------
    await page.locator('[data-testid="{trigger_selector}"]').click();

    // -----------------------------------------------------------------
    // State: {state_name}
    // -----------------------------------------------------------------
    await expect(page.locator('[data-testid="{selector}"]')).toBeVisible();

    // =================================================================
    // ACTION REQUIRED: Wallet Interaction
    // =================================================================
    // This step requires manual wallet interaction:
    // - Action: {wallet_action}
    // - Expected: {expected_result}
    //
    // Options:
    // 1. Run test in headed mode and interact manually
    // 2. Use wallet mock (see docs/WEB3_FLOW_TESTING.md)
    // 3. Skip this step in CI
    // =================================================================

    // await page.locator('[data-testid="approve-button"]').click();
    // Manual: Approve in wallet
    // await page.waitForSelector('[data-testid="approved-indicator"]', { timeout: 60000 });

    // -----------------------------------------------------------------
    // State: Complete
    // -----------------------------------------------------------------
    // Success condition: {success_condition}
    await expect(page.locator('[data-testid="{success_selector}"]')).toBeVisible();
  });

  test('error path: {error_name}', async ({ page }) => {
    // Navigate to error-triggering state
    // ...

    // Trigger error condition
    // ...

    // Verify error state
    await expect(page.locator('[data-testid="error-message"]')).toBeVisible();

    // Verify recovery path
    // await page.locator('[data-testid="retry-button"]').click();
  });

});
```

### Step 5: Update Diagram Link

Update diagram frontmatter:
```yaml
linked_test: grimoires/crucible/tests/{journey-id}.spec.ts
```

### Step 6: Update Laboratory State

Update `grimoires/crucible/state.yaml`:
```yaml
active:
  phase: testing
  journey: {journey-id}

journeys:
  {journey-id}:
    test_status: pending
```

### Step 7: Report Output

```
✓ Test generated: grimoires/crucible/tests/{journey-id}.spec.ts

Test Summary:
  - Happy path: 1 test ({n} states, {m} transitions)
  - Error paths: {k} tests
  - Wallet interactions: {w} marked ACTION REQUIRED

Selectors to Verify:
  - [data-testid="deposit-button"] (Idle state)
  - [data-testid="amount-input"] (EnterAmount state)
  - [data-testid="approve-button"] (Approving state)

Next Steps:
  - Review generated test
  - Verify selectors in codebase
  - Run test: /validate {journey-id} --run
```

---

## Run Mode (`--run`)

Execute the generated test and capture results.

### Step 1: Verify Test Exists

Check:
```bash
grimoires/crucible/tests/{journey-id}.spec.ts
```

If not exists, generate first.

### Step 2: Execute Test

```bash
npx playwright test grimoires/crucible/tests/{journey-id}.spec.ts \
  --reporter=html \
  --output=grimoires/crucible/results/{timestamp}-{journey-id}
```

**Options:**
- `--headed` for visual debugging
- `--debug` for step-by-step

### Step 3: Capture Results

Create results directory:
```
grimoires/crucible/results/{timestamp}-{journey-id}/
├── report.md           # Summary
├── playwright-report/  # HTML report
├── screenshots/        # Failure screenshots
└── traces/             # Playwright traces
```

**report.md Format:**
```markdown
---
journey: {journey-id}
test_file: grimoires/crucible/tests/{journey-id}.spec.ts
executed: {timestamp}
duration: {seconds}s
status: passed | failed
---

# Test Results: {journey-id}

## Summary

| Metric | Value |
|--------|-------|
| **Status** | {passed/failed} |
| **Duration** | {seconds}s |
| **Tests Run** | {count} |
| **Passed** | {count} |
| **Failed** | {count} |
| **Skipped** | {count} |

## Test Results

### ✅ happy path: {journey_title}
- Duration: {ms}ms
- Steps completed: {n}/{total}

### ❌ error path: {error_name}
- Duration: {ms}ms
- Failed at: {step}
- Error: {message}
- Screenshot: screenshots/{test_name}.png

## Failures

### Failure 1: {test_name}

**Location**: {file}:{line}

**Error**:
```
{error_message}
```

**Screenshot**: [View](screenshots/{name}.png)

**Recommended Actions**:
- Check selector: `[data-testid="{selector}"]`
- Verify element exists in DOM
- Check timing (increase timeout?)

## Action Items

- [ ] Review failure screenshots
- [ ] Run /iterate {journey-id} to propose updates
```

### Step 4: Update Laboratory State

Update `grimoires/crucible/state.yaml`:
```yaml
journeys:
  {journey-id}:
    test_status: passed | failed
    last_test: {timestamp}
    test_results: grimoires/crucible/results/{timestamp}-{journey-id}/

queue:
  pending_refinement:
    - {journey-id}  # If failed
```

### Step 5: Report Output

**On Success:**
```
✅ All tests passed!

Test: grimoires/crucible/tests/{journey-id}.spec.ts
Duration: {seconds}s
Results: grimoires/crucible/results/{timestamp}-{journey-id}/

Next Steps:
  - View HTML report: open grimoires/crucible/results/{timestamp}-{journey-id}/playwright-report/index.html
  - Mark journey tested: Status updated to 'tested'
```

**On Failure:**
```
❌ Tests failed!

Test: grimoires/crucible/tests/{journey-id}.spec.ts
Duration: {seconds}s
Failed: {count}/{total}

Failures:
  1. error path: wallet rejection
     - Selector not found: [data-testid="error-alert"]
     - Screenshot: screenshots/error-path-1.png

Results: grimoires/crucible/results/{timestamp}-{journey-id}/

Next Steps:
  - View failures: open grimoires/crucible/results/{timestamp}-{journey-id}/playwright-report/index.html
  - Refine artifacts: /iterate {journey-id}
```

---

## Test Script Template

### Standard Structure

```typescript
import { test, expect, type Page } from '@playwright/test';

// Journey metadata as JSDoc comment
/**
 * @journey {journey-id}
 * @version {version}
 * @source {diagram_path}
 */

test.describe('{journey-id}', () => {
  // Setup
  test.beforeEach(async ({ page }) => { /* ... */ });

  // Happy path
  test('happy path: {title}', async ({ page }) => { /* ... */ });

  // Error paths (one per error state)
  test('error: {error_name}', async ({ page }) => { /* ... */ });
});
```

### Assertion Patterns

```typescript
// Visibility
await expect(page.locator('[data-testid="x"]')).toBeVisible();
await expect(page.locator('[data-testid="x"]')).toBeHidden();

// Enabled/Disabled
await expect(page.locator('[data-testid="x"]')).toBeEnabled();
await expect(page.locator('[data-testid="x"]')).toBeDisabled();

// Text content
await expect(page.locator('[data-testid="x"]')).toContainText('expected');
await expect(page.locator('[data-testid="x"]')).toHaveText('exact');

// Input value
await expect(page.locator('[data-testid="x"]')).toHaveValue('value');

// Count
await expect(page.locator('[data-testid="x"]')).toHaveCount(3);

// Attribute
await expect(page.locator('[data-testid="x"]')).toHaveAttribute('href', '/path');
```

### Wallet Interaction Markers

```typescript
// =================================================================
// ACTION REQUIRED: Wallet Interaction
// =================================================================
// Type: Token Approval
// Wallet: MetaMask / Rabby
// Expected: User approves transaction
//
// For automated testing, consider:
// - Mock wallet provider
// - Pre-approved test accounts
// - Skip in CI with test.skip()
// =================================================================

await page.locator('[data-testid="approve-button"]').click();

// Wait for wallet interaction (manual in headed mode)
await page.waitForSelector('[data-testid="approval-complete"]', {
  timeout: 120000, // 2 minutes for manual interaction
});
```

---

## QA Fixture Integration

### Available Fixtures

From `apps/web/components/qa-cli.tsx`:

```typescript
const QA_FIXTURES = {
  'rewards-ready': '0x79092A805f1cf9B0F5bE3c5A296De6e51c1DEd34',
  'new-user': '0xdA0758706E9E488bc6c7Ea487FFe48c415718e95',
};
```

### Using Fixtures in Tests

```typescript
test.beforeEach(async ({ page }) => {
  await page.goto('http://localhost:3003');

  // Set QA fixture
  await page.evaluate((addr) => {
    localStorage.setItem('sf-qa-effective-address', JSON.stringify({
      effectiveAddress: addr,
      fixtureName: 'rewards-ready'
    }));
  }, '0x79092A805f1cf9B0F5bE3c5A296De6e51c1DEd34');

  await page.reload();
  await page.waitForLoadState('networkidle');
});
```

---

## Error Handling

| Error | Resolution |
|-------|------------|
| Diagram not found | Suggest /diagram {journey-id} |
| Test file exists | Prompt to use --update |
| Playwright not installed | `bun add -D @playwright/test` |
| Test execution failed | Capture results, suggest /iterate |

---

## Integration Points

- **diagramming-states**: Diagrams as input
- **iterating-feedback**: Failed tests trigger refinement
- **agent-browser**: Alternative execution method
- **QA fixtures**: Test account setup

---

## Related

- `/diagram` - Generate diagrams from journeys
- `/iterate` - Update artifacts from test results
- `agent-browser` skill - Interactive browser automation
