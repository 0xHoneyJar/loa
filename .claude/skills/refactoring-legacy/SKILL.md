---
parallel_threshold: 3000
timeout_minutes: 60
---

# Refactoring Legacy Code

<objective>
Safely refactor established code using chain-of-thought verification, evidence-based changes, and test validation. Priority: safety over speed.
</objective>

<kernel_framework>
## Task (N - Narrow Scope)
Refactor established code with full verification protocol. Generate change plan, capture test baseline, apply minimal changes, verify tests pass, document results.

## Context (L - Logical Structure)
- **Input**: Legacy code requiring modification, task description
- **Reference**: Existing tests, callers, git history
- **Output**: Modified code + change plan in `loa-grimoire/plans/`
- **Current state**: Working legacy code (possibly with tech debt)
- **Desired state**: Improved code with verified behavior preservation

## Constraints (E - Explicit)
- DO NOT make changes without understanding current behavior
- DO NOT assume behavior—read and quote actual code
- DO NOT skip test baseline capture
- DO NOT batch multiple unrelated changes
- DO NOT ignore red flags—stop and ask
- DO document all changes with evidence
- DO have rollback plan before every change
- DO follow freedom levels based on change risk

## Verification (E - Easy to Verify)
**Success** = All tests pass after change with:
- Change plan documented in `loa-grimoire/plans/change-<id>.json`
- Pre/post test results captured
- Beads task updated with analysis and results

## Reproducibility (R - Reproducible Results)
- Exact file paths and line numbers for all changes
- Before/after code snippets
- Specific test commands with output
- Git commit SHA for rollback
</kernel_framework>

<core_workflow>
```
UNDERSTAND → PLAN → VERIFY → EXECUTE → VALIDATE → DOCUMENT
```

Never skip steps. If uncertain at any step, STOP and ask.
</core_workflow>

<freedom_levels>
## Freedom Levels for Changes

| Change Type | Freedom | Required Steps |
|-------------|---------|----------------|
| New isolated file | **High** | Lint only |
| New function (no side effects) | **Medium** | Type check, unit tests |
| Modify existing function | **Low** | Full protocol |
| Modify shared utility | **Very Low** | Full protocol + integration tests |
| Modify DB schema | **Minimal** | Full protocol + migration plan + rollback test |

### High Freedom
- New files that don't import existing code
- Pure utility functions with no side effects
- Test files

### Medium Freedom
- New functions added to existing files
- Extensions that don't modify existing behavior
- New endpoints with independent handlers

### Low Freedom (Full Protocol Required)
- Any modification to existing functions
- Renaming or moving code
- Changing function signatures
- Modifying control flow

### Very Low Freedom
- Shared utilities used by >5 files
- Core business logic
- Authentication/authorization code
- Database operations

### Minimal Freedom
- Database schema changes
- External API contracts
- Configuration that affects multiple services
</freedom_levels>

<workflow>
## Phase 1: Understand

Before ANY edit, document in Beads:

```bash
bd update <task-id> --notes "ANALYSIS:
## Current Behavior
[What the code does now - be specific]

## Evidence
File: [path:lines]
\`\`\`[language]
[actual code quote - copy exactly]
\`\`\`

## Original Intent
[Hypothesis about why code was written this way]
Confidence: High/Medium/Low

## Callers
[List all code that calls this with file:line]
\`\`\`bash
grep -rn 'functionName' src/ --include='*.ts'
\`\`\`

## Unknowns
- [ ] [Questions about the code]
- [ ] [Assumptions that need verification]
" --json
```

### Investigation Commands

```bash
# Who calls this function?
grep -rn "functionName" src/ --include="*.ts" --include="*.js"

# What's the git history?
git log --oneline -10 -- path/to/file.ts

# Are there tests?
find . -name "*.test.ts" -exec grep -l "functionName" {} \;

# When was it last modified?
git log -1 --format="%ai %s" -- path/to/file.ts
```

## Phase 2: Plan

Create modification plan:

```json
{
  "task_id": "bd-xxxx",
  "freedom_level": "low",
  "file": "src/path/file.ts",
  "lines": "45-67",

  "current_behavior": "Returns user or throws on not found",

  "proposed_change": "Add optional chaining and return null instead of throw",

  "reasoning": [
    "Callers at src/api/users.ts:23 already handle null case",
    "Error throwing causes unnecessary noise in logs",
    "Matches pattern used in src/api/products.ts:45"
  ],

  "callers": [
    {"file": "src/api/users.ts", "line": 23},
    {"file": "src/services/auth.ts", "line": 89}
  ],

  "risks": [
    {
      "risk": "Callers expecting throw might not handle null",
      "mitigation": "Verified all 2 callers handle null case"
    }
  ],

  "rollback": "git checkout HEAD -- src/path/file.ts",

  "test_files": [
    "src/path/file.test.ts",
    "src/api/users.test.ts"
  ]
}
```

Save to `loa-grimoire/plans/change-<task-id>.json`

## Phase 3: Pre-Flight Verification

```bash
# Validate the change plan
.claude/scripts/validate-change-plan.sh loa-grimoire/plans/change-<task-id>.json

# Capture test baseline
npm test > /tmp/baseline-tests.txt 2>&1
echo "Baseline: $(grep -c 'passing' /tmp/baseline-tests.txt) tests passing"

# Capture type check baseline
npm run typecheck > /tmp/baseline-types.txt 2>&1
```

Store baseline results:

```bash
bd update <task-id> --notes "PRE-FLIGHT:
Tests: [X] passing, [Y] failing
Types: [clean/errors]
Lint: [clean/warnings]
" --json
```

## Phase 4: Execute

Make the minimal change. One logical change per commit.

### Change Rules

1. **Minimal diff**: Change only what's necessary
2. **No drive-by fixes**: Don't "improve" unrelated code
3. **Preserve formatting**: Match existing style exactly
4. **One concern per commit**: Don't mix refactoring with fixes

### Commit Message Format

```
refactor(module): brief description

- What changed
- Why it changed
- Evidence: file:line

Task: bd-xxxx
```

## Phase 5: Post-Flight Validation

```bash
# Run tests
npm test > /tmp/result-tests.txt 2>&1

# Compare with baseline
diff /tmp/baseline-tests.txt /tmp/result-tests.txt

# If ANY test fails: STOP and investigate
if grep -q "failing" /tmp/result-tests.txt; then
  echo "TESTS FAILED - Rolling back"
  git checkout HEAD -- <affected-files>
  exit 1
fi

# Type check
npm run typecheck > /tmp/result-types.txt 2>&1
```

## Phase 6: Document

```bash
bd update <task-id> --notes "COMPLETED:
## Change Applied
[Brief description]

## Files Modified
- src/path/file.ts:45-67

## Verification
- Tests: ✅ [X] passing (same as baseline)
- Types: ✅ Clean
- Manual: [what was manually tested]

## Commit
[sha] refactor(module): description

## Rollback (if needed)
git revert [sha]
" --json

# Close task
bd close <task-id> --reason "Refactored in commit [sha]"
```
</workflow>

<red_flags>
## Red Flags - Stop and Ask Human

When you encounter these, do NOT proceed without explicit approval:

| Red Flag | Why It's Dangerous | Action |
|----------|-------------------|--------|
| No tests + >5 callers | Can't verify behavior preservation | Ask before proceeding |
| `// DO NOT MODIFY` comment | Previous dev knew something | Document and ask |
| `// HACK` or `// FIXME` present | May have subtle requirements | Understand first |
| Last modified >2 years ago | Lost context | Extra caution |
| Imports from >10 files | High coupling | Thorough analysis |
| Contains DB transactions | Data integrity risk | Minimal changes only |
| External API calls | Third-party dependencies | Integration test required |
| You're uncertain | Trust your instincts | Always ask |

### Red Flag Protocol

1. Stop immediately
2. Document the red flag:
   ```bash
   bd update <task-id> --notes "RED FLAG: [description]" --json
   ```
3. Add `needs-guidance` label:
   ```bash
   bd update <task-id> -l needs-guidance --json
   ```
4. Ask human explicitly: "I found [red flag]. Should I proceed?"
5. Do NOT continue without response
</red_flags>

<discovered_issues>
## Handling Discovered Issues

When refactoring reveals problems not in the original task:

```bash
# Create new issue
NEW_ID=$(bd create "Discovered: [issue description]" -t bug -p 2 -l legacy,discovered --json | jq -r '.id')

# Link to current task
bd dep add $NEW_ID <current-task-id> --type discovered-from

# Add context
bd update $NEW_ID --notes "Discovered during refactoring of [file]:
- Found at: [file:line]
- Issue: [description]
- Impact: [assessment]
" --json
```

Do NOT fix discovered issues in the same change. Create separate tasks.
</discovered_issues>

<uncertainty_protocol>
When uncertain about code behavior:

1. State uncertainty explicitly
2. Quote the confusing code
3. List possible interpretations
4. Ask for clarification
5. Create issue if needed:
   ```bash
   bd create "Clarification needed: [aspect]" -t task -l needs-clarification --json
   ```

**Never guess. Always verify or ask.**
</uncertainty_protocol>

<output_format>
## Change Plan JSON Schema

```json
{
  "task_id": "string (required)",
  "freedom_level": "high|medium|low|very_low|minimal",
  "file": "string (file path)",
  "lines": "string (line range)",
  "current_behavior": "string",
  "proposed_change": "string",
  "reasoning": ["array of strings"],
  "callers": [{"file": "string", "line": "number"}],
  "risks": [{"risk": "string", "mitigation": "string"}],
  "rollback": "string (git command)",
  "test_files": ["array of test file paths"]
}
```
</output_format>

<success_criteria>
- **Specific**: Change plan exists with exact file:line
- **Measurable**: Tests pass before and after
- **Achievable**: Minimal change applied
- **Relevant**: Addresses original task
- **Time-bound**: Completed with verification
</success_criteria>

<checklists>
## Pre-Change Checklist

- [ ] Read and understood current code
- [ ] Documented current behavior with evidence
- [ ] Identified all callers
- [ ] Checked git history for context
- [ ] Found related tests
- [ ] Determined freedom level
- [ ] Created change plan
- [ ] Captured test baseline

## Post-Change Checklist

- [ ] Tests pass (same count as baseline)
- [ ] Type check passes
- [ ] Lint passes
- [ ] Change is minimal
- [ ] Commit message is clear
- [ ] Beads task updated
- [ ] Rollback command documented
</checklists>
