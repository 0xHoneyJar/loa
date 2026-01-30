---
name: walking-through
description: Interactive dev browser walkthrough for validating user journeys against live application. Use when manually testing user flows, capturing gaps, or verifying fix implementations.
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Edit, Bash, Skill
---

# Walking Through

Interactive walkthrough skill using agent-browser for manual testing of user journeys with guided prompts and automatic documentation.

---

## Trigger

```
/walkthrough {journey-id}                    # Start interactive walkthrough
/walkthrough {journey-id} --wallet {alias}   # Use specific test wallet
/walkthrough {journey-id} --state {combo}    # Select wallet state combination
/walkthrough {journey-id} --step {N}         # Start from specific step
/walkthrough {journey-id} --headless         # Run without visible browser
```

**Examples:**
```bash
/walkthrough reward-understanding
/walkthrough deposit-flow --wallet test-rewards-ready
/walkthrough deposit-flow --state active+rewards
/walkthrough reward-understanding --step 3
```

---

## Prerequisites

1. **agent-browser installed**: `npm install -g agent-browser`
2. **Local app running**: `bun dev` on port 3003
3. **Wallet extension**: Rabby configured in agent-browser profile (optional for Web3 flows)

---

## Workflow

### Step 1: Load Journey

Read journey file:
```bash
grimoires/lens/journeys/{journey-id}.md
```

Parse:
- Steps (trigger, action, expected, selector)
- Success condition
- Known gaps
- Source canvases

### Step 2: Load Mock Registry

Read mock registry:
```bash
grimoires/crucible/mocks/registry.yaml
```

Select wallet based on:
1. `--wallet {alias}` flag if provided
2. `--state {combo}` flag to match lifecycle+balance
3. Default: first wallet matching journey user type

**Wallet Selection Matrix:**

| User Type | Default Wallet | State |
|-----------|----------------|-------|
| new-user | test-new-user | new + zero |
| trust-checker | test-rewards-ready | active + rewards |
| decision-maker | test-migrated | migrated + balance |

### Step 3: Load Coverage Matrix (if exists)

Check for existing coverage:
```bash
grimoires/crucible/tests/coverage/{journey-id}-coverage.md
```

If exists:
- Show tested combinations
- Highlight untested states
- Suggest priority combinations

### Step 4: Initialize Session

Create session transcript:
```bash
grimoires/crucible/walkthroughs/{journey-id}-{timestamp}.md
```

**Initial Content:**
```markdown
---
type: walkthrough-session
journey: {journey-id}
wallet: {wallet-alias}
wallet_address: {address}
state: {lifecycle}+{balance}
started: {timestamp}
completed: null
status: in_progress
total_steps: {n}
completed_steps: 0
gaps_discovered: 0
---

# Walkthrough: {journey-title}

## Session Info

| Field | Value |
|-------|-------|
| Journey | {journey-id} |
| Wallet | {wallet-alias} |
| State | {state-combo} |
| Started | {timestamp} |

---

## Session Log

{steps will be appended here}
```

### Step 5: Launch Browser

```bash
agent-browser open http://localhost:3003 --headed
agent-browser wait --load networkidle
```

**Optional: Set QA fixture (if using mock wallet)**
```bash
# Via browser console or localStorage
agent-browser run "localStorage.setItem('sf-qa-effective-address', JSON.stringify({effectiveAddress: '{address}', fixtureName: '{fixture}'}))"
agent-browser reload
agent-browser wait --load networkidle
```

### Step 6: Execute Steps Interactively

For each journey step:

#### 6.1: Display Expected Behavior

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP {N}/{TOTAL}: {Step Name}                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Trigger: {trigger}                                             │
│  Action: {action}                                               │
│  Expected: {expected}                                           │
│  Selector: {selector}                                           │
│                                                                 │
│  Known Gaps at this step:                                       │
│  - {gap description if any}                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 6.2: Take Pre-Action Screenshot

```bash
agent-browser screenshot grimoires/crucible/walkthroughs/screenshots/{journey-id}-{timestamp}-step{N}-before.png
```

#### 6.3: Execute Action (if automatable)

For automatable actions:
```bash
agent-browser snapshot -i
agent-browser click @{ref}  # Based on selector
agent-browser wait --load networkidle
```

For wallet interactions:
```
┌─────────────────────────────────────────────────────────────────┐
│ ACTION REQUIRED: Wallet Interaction                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Type: {wallet action type}                                     │
│  Expected: {what should happen}                                 │
│                                                                 │
│  Please complete the wallet interaction manually.               │
│  Press ENTER when complete, or type 'skip' to skip.            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 6.4: Take Post-Action Screenshot

```bash
agent-browser screenshot grimoires/crucible/walkthroughs/screenshots/{journey-id}-{timestamp}-step{N}-after.png
```

#### 6.5: Prompt for Observation

```
┌─────────────────────────────────────────────────────────────────┐
│ OBSERVE                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Expected: {expected behavior}                                  │
│                                                                 │
│  What did you observe?                                          │
│  [1] Matched expected behavior                                  │
│  [2] Partial match (describe difference)                        │
│  [3] Did not match (describe actual)                            │
│  [4] Discovered new gap                                         │
│  [5] Skip this step                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 6.6: Record Observation

Append to session log:

```markdown
### Step {N}: {Step Name}

| Field | Value |
|-------|-------|
| **Trigger** | {trigger} |
| **Action** | {action} |
| **Expected** | {expected} |
| **Observed** | {user observation} |
| **Match** | {matched/partial/mismatch} |
| **Screenshots** | [before](screenshots/{before}.png), [after](screenshots/{after}.png) |

**Notes**: {user notes if any}

---
```

### Step 7: Handle Gap Discovery

If user selects "Discovered new gap":

```
┌─────────────────────────────────────────────────────────────────┐
│ NEW GAP DISCOVERED                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Describe the gap:                                              │
│  > {user input}                                                 │
│                                                                 │
│  Gap type:                                                      │
│  [1] Bug - Something broken                                     │
│  [2] Feature - Missing functionality                            │
│  [3] Communication - Unclear messaging                          │
│  [4] Flow - Unexpected navigation                               │
│                                                                 │
│  Severity:                                                      │
│  [1] Critical - Blocking                                        │
│  [2] High - Major impact                                        │
│  [3] Medium - Notable issue                                     │
│  [4] Low - Minor issue                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Record gap and invoke `/iterate --add-gap`:

```bash
/iterate {journey-id} --add-gap "{gap description}"
```

### Step 8: Complete Session

After all steps or on early exit:

```bash
agent-browser close
```

Update session transcript:

```markdown
---

## Session Summary

| Metric | Value |
|--------|-------|
| **Status** | {completed/aborted} |
| **Duration** | {minutes}m |
| **Steps Completed** | {n}/{total} |
| **Matches** | {count} |
| **Partial Matches** | {count} |
| **Mismatches** | {count} |
| **Gaps Discovered** | {count} |

---

## Gaps Discovered

| Step | Gap | Type | Severity |
|------|-----|------|----------|
| {n} | {description} | {type} | {severity} |

---

## Actions Taken

- [x] Session transcript created
- [x] Screenshots captured
- [ ] Gaps filed as issues
- [ ] Coverage matrix updated

---

## Next Steps

- Review screenshots for UI issues
- File gaps: /file-gap {journey-id} {gap-id}
- Update coverage: Coverage matrix updated automatically
```

### Step 9: Update Coverage Matrix

If coverage matrix exists, update:

```yaml
coverage:
  {state-combo}:
    tested: true
    session: {session-path}
    result: {passed/partial/failed}
    gaps: [{gap-ids}]
```

### Step 10: Report Output

```
┌─────────────────────────────────────────────────────────────────┐
│ WALKTHROUGH COMPLETE                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Journey: {journey-id}                                          │
│  Wallet: {wallet-alias}                                         │
│  Duration: {minutes}m                                           │
│                                                                 │
│  Results:                                                       │
│  ─────────                                                      │
│  Steps: {completed}/{total}                                     │
│  Matches: {n}                                                   │
│  Partial: {n}                                                   │
│  Mismatches: {n}                                                │
│  Gaps Found: {n}                                                │
│                                                                 │
│  Session Transcript:                                            │
│  grimoires/crucible/walkthroughs/{journey-id}-{timestamp}.md  │
│                                                                 │
│  Screenshots:                                                   │
│  grimoires/crucible/walkthroughs/screenshots/                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Next Steps:
  - Review session: Read {session-path}
  - File gaps: /file-gap {journey-id} {gap-id}
  - Run again: /walkthrough {journey-id} --state {next-combo}
```

---

## State Combinations

Common wallet state combinations for testing:

| Combo | Lifecycle | Balance | Use Case |
|-------|-----------|---------|----------|
| `new+zero` | New user | Zero | First-time experience |
| `active+zero` | Active | Zero | Returning user, no funds |
| `active+balance` | Active | Has tokens | Standard user |
| `active+rewards` | Active | Has rewards | Claiming flow |
| `migrated+v1` | Migrated | V1 locker | Migration flow |

---

## Error Handling

| Error | Resolution |
|-------|------------|
| Journey not found | Suggest /shape --run |
| Mock registry not found | Create with template |
| agent-browser not found | Provide install instructions |
| App not running | Prompt to start dev server |
| Wallet not configured | Provide setup instructions |

---

## Integration Points

- **agent-browser**: Browser automation
- **iterating-feedback**: Gap discovery via --add-gap
- **validating-journeys**: Automated test generation
- **analyzing-gaps**: Gap classification
- **Coverage matrix**: Test coverage tracking

---

## Related

- `/diagram` - Generate flow diagrams
- `/validate` - Generate automated tests
- `/iterate` - Update artifacts from discoveries
- `/file-gap` - Create issues from gaps
