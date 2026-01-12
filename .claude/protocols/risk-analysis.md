# Pre-Mortem Risk Analysis Protocol

This protocol defines structured risk identification using the Tiger/Paper Tiger/Elephant framework with two-pass verification to minimize false positives.

## Overview

Pre-mortem analysis asks: "Imagine this implementation has failed. What caused it?"

This inverts traditional risk assessment from "What might go wrong?" to "What DID go wrong?" - which surfaces risks that optimism bias typically hides.

---

## Risk Categories

### Tiger 🐅

**Definition**: Real threat that will cause harm if not addressed.

**Characteristics**:
- High likelihood of occurrence
- Significant negative impact
- No existing mitigation in place
- Within scope of current work

**Action**: Must address before proceeding OR explicitly accept with documented rationale.

**Examples**:
- Unvalidated user input passed to SQL query
- API endpoint missing authentication
- Race condition in concurrent write operation
- Hardcoded credentials in configuration

---

### Paper Tiger 📄🐅

**Definition**: Looks threatening but is actually fine upon investigation.

**Characteristics**:
- Initial pattern match suggests risk
- But mitigation already exists
- Or risk is out of scope
- Or risk is theoretical only

**Action**: Document why it's not a real risk. No code changes needed.

**Examples**:
- SQL query that looks vulnerable but uses parameterized queries
- File path that appears user-controlled but is validated upstream
- Error that appears unhandled but has global exception handler
- Credential that appears hardcoded but is a placeholder in tests

---

### Elephant 🐘

**Definition**: The thing nobody wants to talk about - known issues that are being ignored.

**Characteristics**:
- Team is aware but avoiding
- Often involves technical debt
- May require significant refactoring
- Political or organizational sensitivity

**Action**: Surface for explicit discussion. May defer but must acknowledge.

**Examples**:
- "We know the auth system needs rewriting but..."
- "The database schema is wrong but migrating would take weeks"
- "That API is deprecated but we're still using it"
- "The tests don't actually test the critical path"

---

## Two-Pass Verification

### Pass 1: Pattern Identification

Scan for potential risks using pattern matching:

```yaml
patterns:
  sql_injection:
    - "execute.*%s"
    - "cursor.execute.*f\""
    - "query.*\\+.*input"

  path_traversal:
    - "open.*input"
    - "os.path.join.*user"
    - "file_path.*request"

  hardcoded_secrets:
    - "password.*=.*['\"]"
    - "api_key.*=.*['\"]"
    - "secret.*=.*['\"]"

  missing_auth:
    - "@app.route.*def.*:$"  # Route without decorator
    - "def.*handler.*:"       # Handler without auth check
```

### Pass 2: Context Verification

For each potential risk from Pass 1, verify:

```yaml
verification_checklist:
  context_read:
    description: "Read ±20 lines around the finding"
    required: true

  mitigation_check:
    description: "Check for try/except, validation, sanitization"
    required: true
    checks:
      - "Is there input validation upstream?"
      - "Is there a try/except block?"
      - "Is there a fallback/default?"
      - "Is there a guard clause?"

  scope_check:
    description: "Is this in scope for current work?"
    required: true
    questions:
      - "Is this file being modified in this sprint?"
      - "Does this affect the feature being implemented?"
      - "Is this a pre-existing issue outside scope?"

  dev_only_check:
    description: "Is this in test/dev-only code?"
    required: true
    paths_to_check:
      - "tests/"
      - "test_*.py"
      - "*_test.go"
      - "*.test.ts"
      - "fixtures/"
      - "mocks/"
```

---

## Risk Assessment Template

```markdown
## Pre-Mortem Risk Analysis

**Feature**: [Feature name]
**Date**: [Date]
**Analyst**: [Agent/Human]

### Tigers (Must Address)

#### TIGER-001: [Risk Title]

**Location**: `path/to/file.py:123`

**Pattern Match**: SQL query with string concatenation

**Verification**:
- [x] Context read: Lines 100-145 reviewed
- [x] Mitigation check: No parameterization found
- [x] Scope check: File is being modified in this sprint
- [ ] Dev-only check: Production code

**Impact**: SQL injection vulnerability allowing data exfiltration

**Recommendation**: Use parameterized queries

**Decision**: [ ] Address | [ ] Accept with rationale: ___

---

### Paper Tigers (Acknowledged, No Action)

#### PAPER-001: [Risk Title]

**Location**: `path/to/file.py:456`

**Pattern Match**: Hardcoded string looks like credential

**Why It's Paper**:
- [x] Context read: This is a test fixture placeholder
- [x] Mitigation check: Real credentials loaded from environment
- Value is `"test_api_key"` not a real credential

**Conclusion**: False positive - no action needed

---

### Elephants (Surface for Discussion)

#### ELEPHANT-001: [Risk Title]

**The Uncomfortable Truth**: [What everyone knows but isn't saying]

**Why It's Being Avoided**: [Political/technical/resource reasons]

**Impact If Ignored**: [What happens if we keep ignoring it]

**Recommendation**: [Acknowledge | Schedule | Escalate]

---

## Summary

| Category | Count | Action Items |
|----------|-------|--------------|
| Tigers | X | [List actions] |
| Paper Tigers | Y | None |
| Elephants | Z | [List discussions needed] |
```

---

## Integration Points

### With `/architect`

Run pre-mortem on design before implementation:
- Identify architectural risks early
- Surface Elephants during design phase
- Validate security assumptions

### With `/audit-sprint`

Use Tiger/Paper Tiger/Elephant categorization:
- Tigers → Blocking issues
- Paper Tigers → Documented in "No Action" section
- Elephants → Technical debt tracking

### With `/implement`

Check pre-mortem before starting sprint:
- Are all Tigers addressed?
- Are Elephants acknowledged?
- Are Paper Tigers documented?

---

## Automation

### Risk Pattern Scanner

```bash
#!/usr/bin/env bash
# .claude/scripts/scan-risks.sh

PATTERNS=(
    "password.*=.*['\"]"
    "execute.*%s"
    "os.system"
    "eval("
    "pickle.loads"
)

for pattern in "${PATTERNS[@]}"; do
    echo "=== Pattern: $pattern ==="
    grep -rn "$pattern" src/ --include="*.py" 2>/dev/null || echo "No matches"
done
```

### Verification Prompt

When a potential risk is identified, ask:

```
Before classifying this as a Tiger, verify:
1. Did you read ±20 lines of context?
2. Is there mitigation upstream/downstream?
3. Is this in scope for current work?
4. Is this test/dev-only code?

If all checks pass and risk remains → Tiger
If mitigation exists → Paper Tiger
If out of scope but important → Elephant
```

---

## References

- [Pre-Mortems by Gary Klein](https://hbr.org/2007/09/performing-a-project-premortem)
- [Pre-Mortems Template by Shreyas Doshi](https://coda.io/@shreyas/pre-mortems)
- [Continuous-Claude-v3 Risk Framework](https://github.com/parcadei/Continuous-Claude-v3)
