# Self-Audit Checkpoint Protocol

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-12-27

---

## Overview

This protocol creates a mandatory self-audit checkpoint that agents execute BEFORE task completion to ensure grounding ratio ≥0.95 and all claims have proper evidence.

**Problem**: Agents complete tasks with assumptions, unflagged claims, and low evidence ratios.

**Solution**: Mandatory checklist before marking any task as complete. If ANY checkbox fails → REMEDIATE before completion.

**Source**: PRD FR-5.4

---

## Self-Audit Checklist

BEFORE completing ANY task, execute this checklist:

- [ ] **Grounding ratio ≥ 0.95** (95%+ claims have evidence)
- [ ] **Zero unflagged [ASSUMPTION] claims**
- [ ] **All citations have word-for-word quotes**
- [ ] **All paths are absolute** (${PROJECT_ROOT}/...)
- [ ] **Ghost Features tracked in Beads** (if bd installed)
- [ ] **Shadow Systems documented in drift-report.md**
- [ ] **Evidence chain complete for all major conclusions**

## Grounding Ratio Calculation

```bash
# Calculate from trajectory log
total_claims=$(grep '"phase":"cite"' trajectory.jsonl | wc -l)
grounded_claims=$(grep '"grounding":"citation"' trajectory.jsonl | wc -l)

# Calculate ratio
ratio=$(echo "scale=2; $grounded_claims / $total_claims" | bc)

# Check threshold
if (( $(echo "$ratio < 0.95" | bc -l) )); then
    echo "ERROR: Grounding ratio $ratio below threshold 0.95"
    exit 1
fi
```

**Target**: ≥ 0.95 (95% of claims must be grounded)

---

## Claim Classification

### GROUNDED (Citation)

Claim backed by word-for-word code quote:

```markdown
"Uses JWT: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"
```

**Trajectory**: `"grounding": "citation"`

### ASSUMPTION (Flagged)

Ungrounded claim with explicit flag:

```markdown
"Likely caches tokens [ASSUMPTION: needs verification]"
```

**Trajectory**: `"grounding": "assumption"`, `"flag": "[ASSUMPTION: needs verification]"`

### GHOST

Feature in docs but not in code:

```markdown
"OAuth2 SSO [GHOST: PRD §3.2, 0 search results]"
```

**Trajectory**: Logged in negative_grounding phase

### SHADOW

Code exists but undocumented:

```markdown
"Legacy hasher: `function hashLegacy()` [SHADOW: /abs/path/src/auth/legacy.ts, undocumented]"
```

**Trajectory**: Logged in shadow_detection phase

---

## Remediation Actions

If self-audit FAILS:

### Low Grounding Ratio (<0.95)

**Problem**: Too many assumptions, insufficient code citations

**Action**:
1. Review all claims in output
2. Search for code evidence for each claim
3. Convert [ASSUMPTION] to citations with code quotes
4. Re-calculate grounding ratio
5. Retry self-audit

### Unflagged Assumptions

**Problem**: Ungrounded claims without [ASSUMPTION] flag

**Action**:
1. Grep trajectory for `"grounding":"assumption"` without `"flag"`
2. Add [ASSUMPTION: needs verification] to each claim
3. Update output document
4. Retry self-audit

### Relative Paths

**Problem**: Citations use relative paths

**Action**:
1. Grep for `\[.*\.ts:` or `\[src/` patterns
2. Convert all to absolute paths: `/abs/path/...`
3. Update citations
4. Retry self-audit

### Missing Code Quotes

**Problem**: Citations without backtick-quoted code

**Action**:
1. Grep for file:line references without backticks
2. Read each file, extract code quote
3. Update citation format: `"claim: `code` [path:line]"`
4. Retry self-audit

---

## Load Trajectory for Verification

```bash
# Load agent's trajectory log
AGENT="implementing-tasks"
DATE=$(date +%Y-%m-%d)
TRAJECTORY="loa-grimoire/a2a/trajectory/${AGENT}-${DATE}.jsonl"

# Verify evidence chains
grep '"phase":"intent"' "$TRAJECTORY" | wc -l  # Searches initiated
grep '"phase":"cite"' "$TRAJECTORY" | wc -l   # Citations created
grep '"grounding":"citation"' "$TRAJECTORY" | wc -l  # Grounded claims
grep '"grounding":"assumption"' "$TRAJECTORY" | wc -l  # Assumptions

# Calculate ratio
echo "Grounding Ratio: grounded_claims / total_claims"
```

---

## DO NOT Complete Task If

- ❌ Grounding ratio < 0.95
- ❌ Any [ASSUMPTION] unflagged
- ❌ Any relative paths in citations
- ❌ Any citations without code quotes
- ❌ Ghost Features not tracked in Beads
- ❌ Shadow Systems not documented in drift-report.md
- ❌ Evidence chains incomplete

**Action**: REMEDIATE issues, then retry self-audit.

---

## Example Self-Audit Report

```markdown
## Self-Audit Checkpoint

**Task**: Implement JWT authentication extension
**Agent**: implementing-tasks
**Date**: 2025-12-27

### Checklist

- [x] Grounding ratio: 19/20 = 0.95 ✓
- [x] Zero unflagged assumptions ✓
- [x] All citations have code quotes ✓
- [x] All paths absolute ✓
- [x] Ghost Features tracked (0 found) ✓
- [x] Shadow Systems documented (1 found) ✓
- [x] Evidence chain complete ✓

### Summary

**Pass**: All checkboxes passed. Task ready for review.

**Evidence**:
- Total claims: 20
- Grounded (citations): 19
- Assumptions (flagged): 1
- Grounding ratio: 0.95 (meets threshold)
```

---

## Integration with Reviewing-Code Agent

The reviewing-code agent will:

1. Load implementing agent's trajectory log
2. Calculate grounding ratio independently
3. Verify all [ASSUMPTION] claims are flagged
4. Check citation format (code quotes + absolute paths)
5. Audit evidence chains for completeness
6. REJECT if self-audit missed issues

**Example rejection**:

```markdown
## Review Feedback: Sprint 3 Implementation

**Status**: CHANGES REQUIRED

**Issues**:
1. Grounding ratio 0.88 (below threshold 0.95)
2. Two unflagged assumptions found in output
3. Three citations missing code quotes
4. One relative path: `src/auth/jwt.ts`

**Action**: Fix 4 issues, run self-audit again, re-submit for review.
```

---

## Communication Guidelines

### What Agents Should Say (User-Facing)

✅ **CORRECT**:
- "Implementation complete. All claims backed by code evidence."
- "Self-audit passed. Ready for review."

❌ **INCORRECT** (exposing protocol details):
- "Running self-audit checkpoint before completion..."
- "Calculated grounding ratio: 0.95..."
- "All checkboxes passed in self-audit checklist..."

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-27 | Initial protocol creation (Sprint 3) |

---

**Status**: ✅ Protocol Complete
**Next**: Enforce in all agent completions
