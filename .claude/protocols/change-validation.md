# Change Validation Protocol

Ensure modifications to established code don't break existing functionality.

## Purpose

When working with established codebases (`repo_mode: established`), all changes must follow a validation protocol to preserve existing behavior and prevent regressions.

## Freedom Levels

| Level | Use Case | Validation Required |
|-------|----------|---------------------|
| **High** | New isolated code | Lint only |
| **Medium** | Extensions to existing code | Type check + unit tests |
| **Low** | Modify existing functions | Full protocol |
| **Very Low** | Shared utilities, core logic | Full + integration tests |
| **Minimal** | DB/API changes | Full + migration + rollback test |

### Level Determination

```
Is this a new file with no imports from src/?
  → HIGH freedom

Is this a new function that doesn't modify existing behavior?
  → MEDIUM freedom

Does this modify an existing function?
  → LOW freedom

Is this code imported by >5 files?
  → VERY LOW freedom

Does this affect database schema or external API contracts?
  → MINIMAL freedom
```

## Low Freedom Workflow

### 1. Generate Change Plan

Before any edits, create `loa-grimoire/plans/change-<bd-id>.json`:

```json
{
  "task_id": "bd-xxxx",
  "freedom_level": "low",
  "file": "src/path/file.ts",
  "lines": "45-67",

  "current_behavior": "Description of what the code does now",

  "proposed_change": "Description of what will change",

  "reasoning": [
    "Evidence-based reason 1",
    "Evidence-based reason 2"
  ],

  "callers": [
    {"file": "src/api/handler.ts", "line": 23},
    {"file": "src/services/user.ts", "line": 89}
  ],

  "risks": [
    {
      "risk": "Description of what could go wrong",
      "mitigation": "How we prevent or detect this"
    }
  ],

  "rollback": "git checkout HEAD -- src/path/file.ts",

  "test_files": [
    "src/path/file.test.ts",
    "src/api/handler.test.ts"
  ]
}
```

### 2. Validate Plan

```bash
.claude/scripts/validate-change-plan.sh loa-grimoire/plans/change-<bd-id>.json
```

The validation script checks:
- All required fields present
- Target files exist
- No protected file markers
- Freedom level is valid
- Risks have mitigations
- Rollback command exists

### 3. Pre-Flight Baseline

Capture the current state before making changes:

```bash
# Run tests and save output
npm test > /tmp/baseline.txt 2>&1

# Record baseline metrics
echo "Tests passing: $(grep -c 'passing' /tmp/baseline.txt)"
echo "Tests failing: $(grep -c 'failing' /tmp/baseline.txt)"

# Type check baseline
npm run typecheck > /tmp/types-baseline.txt 2>&1
```

### 4. Apply Changes

- Make the minimal change necessary
- One logical change per commit
- Match existing code style exactly
- Don't fix unrelated issues ("drive-by fixes")

### 5. Post-Flight Verify

```bash
# Run tests
npm test > /tmp/result.txt 2>&1

# Compare with baseline
diff /tmp/baseline.txt /tmp/result.txt

# If different or tests fail: INVESTIGATE
# If tests pass with same count: PROCEED
```

### 6. Rollback if Failed

If anything goes wrong:

```bash
# Immediate rollback
git checkout HEAD -- <affected-files>

# Or revert commit
git revert <sha>
```

## Evidence Requirements

Every change to established code must document:

| Evidence | Format | Example |
|----------|--------|---------|
| File location | `path:lines` | `src/auth/middleware.ts:42-67` |
| Current code | Code block | Actual code snippet |
| Proposed change | Code block | New code snippet |
| Reasoning | List | Why this change is needed |
| Callers | List with file:line | Who depends on this code |
| Test results | Before/after | Test count comparison |
| Commit | SHA | `abc1234` |

## Uncertainty Protocol

When you're unsure about code behavior:

1. **State uncertainty explicitly**
   - "I'm uncertain about the edge case when X is null"

2. **Quote the ambiguous code**
   ```typescript
   // src/util.ts:45
   // What happens if user is undefined here?
   return user?.role ?? 'guest';
   ```

3. **List possible interpretations**
   - Interpretation A: Returns 'guest' for undefined users
   - Interpretation B: Throws in strict mode

4. **Ask for clarification**
   - Create Beads issue with `needs-clarification` label

5. **Do NOT proceed without clarity**

## Red Flags

Stop and ask for human guidance when you see:

| Red Flag | Why It Matters |
|----------|----------------|
| `// DO NOT MODIFY` | Previous developer knew something |
| `// HACK` or `// FIXME` | May have subtle requirements |
| No tests + many callers | Can't verify behavior preserved |
| Last modified >2 years ago | Context may be lost |
| Contains transactions | Data integrity at risk |
| External API calls | Third-party dependencies |

## Beads Integration

### Starting Work

```bash
bd update <task-id> --status in_progress --json
bd update <task-id> --notes "ANALYSIS: [findings]" --json
```

### During Work

```bash
bd update <task-id> --notes "CHANGE PLAN: [summary]" --json
bd update <task-id> --notes "PRE-FLIGHT: Tests [X] passing" --json
```

### Completing Work

```bash
bd update <task-id> --notes "POST-FLIGHT: Tests [X] passing, commit [sha]" --json
bd close <task-id> --reason "Completed in commit [sha]"
```

### Discovered Issues

```bash
NEW_ID=$(bd create "Discovered: [issue]" -t bug -p 2 -l discovered --json | jq -r '.id')
bd dep add $NEW_ID <current-task> --type discovered-from
```

## Quick Reference

| Action | Command |
|--------|---------|
| Create change plan | Edit `loa-grimoire/plans/change-<id>.json` |
| Validate plan | `.claude/scripts/validate-change-plan.sh <plan.json>` |
| Capture baseline | `npm test > /tmp/baseline.txt 2>&1` |
| Compare results | `diff /tmp/baseline.txt /tmp/result.txt` |
| Immediate rollback | `git checkout HEAD -- <files>` |
| Detect drift | `.claude/scripts/detect-drift.sh` |
