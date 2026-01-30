# EDD Verification Protocol

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-12-27

---

## Overview

EDD (Evaluation-Driven Development) requires three test scenarios for every architectural decision informed by code search. This ensures agent understanding is verified against actual code behavior.

**Problem**: Agents make decisions based on partial understanding without verifying edge cases and error handling.

**Solution**: Mandatory 3-scenario verification before marking decisions complete.

**Source**: PRD FR-5.5, Google ADK EDD principles

---

## Three Test Scenarios Required

Every architectural decision informed by ck/search must have:

1. **Happy Path**: Typical input and expected behavior
2. **Edge Case**: Boundary condition handling  
3. **Error Handling**: Invalid input and error behavior

### Example EDD Structure

```markdown
## Decision: Implement auth using existing JWT module

### Evidence Chain
- SEARCH: hybrid_search("JWT validation") @ 10:30:00
- RESULT: src/auth/jwt.ts:45 (score: 0.89)
- CITATION: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]

### Test Scenarios

**Scenario 1: Happy Path**
- Input: Valid JWT token
- Expected: Token validated, payload returned
- Verified: ✓ (code shows: `return jwt.verify(token, SECRET)`)

**Scenario 2: Edge Case**
- Input: Expired token  
- Expected: ValidationError thrown
- Verified: ✓ (code shows: `if (Date.now() > payload.exp) throw new ValidationError()`)

**Scenario 3: Error Handling**
- Input: Malformed token
- Expected: ParseError thrown
- Verified: ✓ (code shows: `try { jwt.decode() } catch { throw new ParseError() }`)
```

---

## Scenario Requirements

### Scenario 1: Happy Path

**Verify**:
- Typical valid input accepted
- Expected output produced
- No errors thrown

**Code evidence**:
- Main function logic
- Return statement
- Success path

### Scenario 2: Edge Case

**Verify**:
- Boundary conditions handled
- Special cases addressed  
- Graceful degradation

**Code evidence**:
- Conditional checks
- Boundary validation
- Edge case handling

### Scenario 3: Error Handling

**Verify**:
- Invalid input rejected
- Appropriate errors thrown
- Error messages meaningful

**Code evidence**:
- Try-catch blocks
- Error constructors
- Validation logic

---

## No [ASSUMPTION] Flags Remaining

Before completion, all scenarios must be:
- ✓ Verified against actual code
- ✓ Backed by word-for-word citations
- ✓ Zero [ASSUMPTION] flags

**If cannot verify**: Mark as [ASSUMPTION: needs manual verification]

---

## Integration with Self-Audit

Self-audit checklist includes:
- [ ] All architectural decisions have 3 scenarios
- [ ] All scenarios verified against code
- [ ] All scenarios have code citations
- [ ] Zero [ASSUMPTION] flags in scenarios

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-27 | Initial protocol creation (Sprint 3) |

---

**Status**: ✅ Protocol Complete
**Next**: Enforce in implementing-tasks agent
