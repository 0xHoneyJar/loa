# Grounding Enforcement Protocol

> **Version**: 1.0 (v0.9.0 Lossless Ledger Protocol)
> **Paradigm**: Clear, Don't Compact

## Purpose

Verify citation quality and enforce grounding ratio to prevent hallucinations and ungrounded claims. This protocol defines how decisions must be grounded in verifiable evidence.

## Grounding Ratio

The grounding ratio measures the proportion of decisions backed by verifiable evidence:

```
GROUNDING RATIO FORMULA:

grounding_ratio = grounded_claims / total_claims

WHERE:
  grounded_claims = decisions with:
    - Word-for-word code quote
    - ${PROJECT_ROOT} absolute path
    - Line number reference

  total_claims = all decisions made this session
```

### Threshold

| Enforcement Level | Threshold | Behavior |
|-------------------|-----------|----------|
| **strict** | >= 0.95 | Block /clear if below threshold |
| **warn** | >= 0.95 | Warn but allow /clear |
| **disabled** | N/A | No enforcement (not recommended) |

**Default**: `strict` for security-critical projects, `warn` for development.

## Citation Format

All code-grounded claims MUST follow this format:

```
REQUIRED CITATION FORMAT:

`<word-for-word code quote>` [${PROJECT_ROOT}/<path>:<line>]

COMPONENTS:
1. Code quote: Exact text from source (in backticks)
2. Absolute path: ${PROJECT_ROOT} prefix mandatory
3. Line number: Where the code exists
```

### Examples

**Correct Citation**:
```
The authentication middleware validates JWT tokens:
`export function validateToken(token: string)` [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

**Incorrect Citations**:
```
INVALID (relative path):
`validateToken(token)` [src/auth/jwt.ts:45]

INVALID (no line number):
`validateToken(token)` [${PROJECT_ROOT}/src/auth/jwt.ts]

INVALID (paraphrased, not word-for-word):
"The function validates tokens" [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

## Grounding Types

Each decision logged to trajectory must specify its grounding type:

| Type | Description | Evidence Required |
|------|-------------|-------------------|
| `citation` | Direct code quote | Code + path + line |
| `code_reference` | Reference to existing code | Path + line |
| `user_input` | Based on user's explicit request | Message ID or source |
| `assumption` | Ungrounded claim | Must be flagged |

### Trajectory Logging

```jsonl
{"phase":"cite","claim":"JWT validates expiry","grounding":"citation","evidence":{"quote":"if (isExpired(token))","path":"${PROJECT_ROOT}/src/auth/jwt.ts","line":67}}
{"phase":"cite","claim":"Users prefer dark mode","grounding":"assumption","evidence":null}
```

## Verification Process

### Step 1: Count Claims

Parse trajectory log for all `phase: "cite"` entries:

```bash
total_claims=$(grep -c '"phase":"cite"' "$TRAJECTORY" 2>/dev/null || echo "0")
```

### Step 2: Count Grounded Claims

Count claims with valid grounding:

```bash
grounded_claims=$(grep -c '"grounding":"citation"' "$TRAJECTORY" 2>/dev/null || echo "0")
```

### Step 3: Calculate Ratio

```bash
if [[ "$total_claims" -eq 0 ]]; then
    ratio="1.00"  # Zero-claim sessions pass
else
    ratio=$(echo "scale=2; $grounded_claims / $total_claims" | bc)
fi
```

### Step 4: Enforce Threshold

```bash
if (( $(echo "$ratio < $THRESHOLD" | bc -l) )); then
    echo "FAIL: Grounding ratio $ratio below threshold $THRESHOLD"
    exit 1
fi
```

## Zero-Claim Sessions

Sessions with no claims automatically pass grounding check:

```
ZERO-CLAIM HANDLING:

IF total_claims == 0:
  grounding_ratio = 1.00
  status = PASS

RATIONALE:
- Read-only sessions (exploration, research) have no claims
- No claims = no risk of ungrounded hallucinations
- Don't block legitimate research sessions
```

## Configuration

Add to `.loa.config.yaml`:

```yaml
# Grounding enforcement configuration
grounding_enforcement: strict  # strict | warn | disabled

grounding:
  threshold: 0.95              # Minimum ratio required
  zero_claim_passes: true      # Zero-claim sessions pass
  log_ungrounded: true         # Log assumption claims to trajectory
```

### Configuration Levels

**strict** (Default for security-critical):
- Block `/clear` if ratio < threshold
- Block if unverified Ghost Features exist
- Require remediation before proceeding

**warn** (Development mode):
- Warn if ratio < threshold
- Allow `/clear` to proceed
- Log warning to trajectory

**disabled** (Not recommended):
- No enforcement
- No warnings
- Use only for prototyping

## Error Messages

### Grounding Ratio Below Threshold

```
ERROR: Grounding ratio too low

Current ratio: 0.87 (target: >= 0.95)
Ungrounded claims: 3

Ungrounded decisions requiring evidence:
1. "The cache expires after 24 hours" - Add code citation
2. "Users authenticate via OAuth" - Add code citation
3. "Rate limit is 100 req/min" - Add code citation

Actions:
- Add word-for-word code citations for each claim
- Or mark as [ASSUMPTION] if no code exists
- Then retry /clear
```

### Missing Path Prefix

```
ERROR: Invalid citation format

Citation: `validateToken(token)` [src/auth/jwt.ts:45]
Problem: Path must use ${PROJECT_ROOT} prefix

Correct format:
`validateToken(token)` [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

## Negative Grounding Protocol

Negative grounding verifies that claimed **non-existence** of features (Ghost Features) is accurate. A single query returning 0 results is insufficient - two diverse semantic queries are required.

### Ghost Feature Detection

A "Ghost Feature" is a feature mentioned in documentation but not implemented in code:

```
GHOST FEATURE VERIFICATION:

CLAIM: "OAuth2 SSO is not implemented"

VERIFICATION REQUIRES:
1. Query 1: "OAuth2 authentication SSO login"
   - Target: ${PROJECT_ROOT}/src/
   - Threshold: 0.4 similarity
   - Result: 0 matches required

2. Query 2: "single sign-on identity provider SAML"
   - Target: ${PROJECT_ROOT}/src/
   - Threshold: 0.4 similarity
   - Result: 0 matches required

BOTH queries must return 0 results below threshold.
```

### Why Two Queries?

Single queries are unreliable for proving absence:

| Query Type | Risk | Example |
|------------|------|---------|
| Single query | False negative | "OAuth" returns 0, but "SSO" would find code |
| Diverse queries | Higher confidence | Both "OAuth login" and "SSO identity" return 0 |

### Verification Steps

```bash
# ck v0.7.0+ syntax: --sem (not --semantic), --limit (not --top-k), path is positional

# Query 1: Primary terminology
results1=$(ck --sem "OAuth2 authentication SSO" --limit 10 --threshold 0.4 --jsonl "${PROJECT_ROOT}/src/")
count1=$(echo "$results1" | jq -s 'length')

# Query 2: Diverse/synonymous terminology
results2=$(ck --sem "single sign-on identity provider" --limit 10 --threshold 0.4 --jsonl "${PROJECT_ROOT}/src/")
count2=$(echo "$results2" | jq -s 'length')

# Both must return 0
if [[ "$count1" -eq 0 ]] && [[ "$count2" -eq 0 ]]; then
    echo "VERIFIED GHOST: OAuth2 SSO not implemented"
else
    echo "UNVERIFIED: Found potential matches"
fi
```

### Fallback Without ck

When semantic search unavailable:

```bash
# Query 1
results1=$(grep -rn -i "oauth\|sso\|saml" "${PROJECT_ROOT}/src/" 2>/dev/null | wc -l)

# Query 2
results2=$(grep -rn -i "identity.provider\|sign.on\|auth.provider" "${PROJECT_ROOT}/src/" 2>/dev/null | wc -l)

if [[ "$results1" -eq 0 ]] && [[ "$results2" -eq 0 ]]; then
    echo "VERIFIED GHOST (grep fallback)"
fi
```

### High Ambiguity Flag

When documentation mentions a feature but code search returns 0:

```
HIGH AMBIGUITY CONDITIONS:
- Code results: 0 (both queries)
- Doc mentions: >= 3 references

ACTION:
- Flag as [UNVERIFIED GHOST]
- In strict mode: Block /clear until human audit
- In warn mode: Warn but allow /clear
```

### Ghost Feature Trajectory Logging

```jsonl
{"phase":"negative_ground","claim":"OAuth2 SSO not implemented","query1":"OAuth2 authentication SSO","results1":0,"query2":"single sign-on identity provider","results2":0,"doc_mentions":5,"status":"high_ambiguity","action":"human_audit_required"}
```

### UNVERIFIED GHOST Flag

When negative grounding cannot be confirmed:

```markdown
## Decision Log

### OAuth2 SSO
- **Status**: [UNVERIFIED GHOST]
- **Claim**: OAuth2 SSO is not implemented
- **Query 1**: "OAuth2 authentication SSO" - 0 results
- **Query 2**: "single sign-on identity" - 0 results
- **Doc Mentions**: 5 references in PRD §3.2
- **Action Required**: Human audit before claiming non-existence
```

### Configuration

```yaml
# .loa.config.yaml
grounding:
  negative:
    enabled: true
    query_count: 2              # Number of diverse queries required
    similarity_threshold: 0.4   # Below this = no match
    doc_mention_threshold: 3    # Flag for human audit if >= mentions
    strict_mode_blocks: true    # Block /clear on unverified ghosts
```

### Strict Mode Behavior

In `grounding_enforcement: strict`:

```
IF unverified_ghosts > 0:
  BLOCK /clear
  MESSAGE: "Cannot clear: X Ghost Features unverified"
  ACTION: Human audit required OR remove ghost claims
```

In `grounding_enforcement: warn`:

```
IF unverified_ghosts > 0:
  WARN (but allow /clear)
  MESSAGE: "Warning: X Ghost Features unverified"
  LOG: Warning to trajectory
```

---

## Integration Points

### Synthesis Checkpoint

The synthesis checkpoint calls grounding enforcement before permitting `/clear`:

```
synthesis-checkpoint.sh
├── Step 1: grounding-check.sh (BLOCKING)
│   └── Calculate ratio, enforce threshold
├── Step 2: Negative grounding check (BLOCKING in strict mode)
└── Steps 3-7: Ledger sync (non-blocking)
```

### Trajectory Evaluation

All claims must be logged to trajectory with grounding type:

```
trajectory-evaluation.md
└── cite phase
    ├── grounding: citation | code_reference | user_input | assumption
    └── evidence: { quote, path, line } or null
```

### Session Continuity

Grounding ratio is recorded in session handoff:

```
session-continuity.md
└── session_handoff trajectory entry
    └── grounding_ratio: 0.97
```

## Anti-Patterns

### 1. Paraphrased Citations

```
BAD: "The function checks tokens" [${PROJECT_ROOT}/src/auth.ts:45]
GOOD: `export function checkToken()` [${PROJECT_ROOT}/src/auth.ts:45]
```

### 2. Missing Line Numbers

```
BAD: `validateToken()` [${PROJECT_ROOT}/src/auth.ts]
GOOD: `validateToken()` [${PROJECT_ROOT}/src/auth.ts:45]
```

### 3. Relative Paths

```
BAD: `validateToken()` [src/auth.ts:45]
GOOD: `validateToken()` [${PROJECT_ROOT}/src/auth.ts:45]
```

### 4. Assumption Without Flag

```
BAD: Making claims without evidence and without marking as assumption
GOOD: Marking claim as [ASSUMPTION] when no code evidence exists
```

### 5. Bulk Assumptions

```
BAD: Marking most decisions as [ASSUMPTION] to pass grounding check
RATIONALE: This defeats the purpose - investigate to find evidence
```

## Remediation Steps

When grounding ratio is below threshold:

1. **Review ungrounded claims** - List all decisions without citations
2. **Search for evidence** - Use ck or grep to find supporting code
3. **Add citations** - Update claims with word-for-word quotes
4. **Flag assumptions** - Mark truly ungrounded claims as [ASSUMPTION]
5. **Re-verify** - Run grounding check again

```bash
# Find evidence for a claim
ck --hybrid "validates JWT token" "${PROJECT_ROOT}/src/" --top-k 5

# Fallback without ck
grep -rn "validateToken\|JWT\|token" "${PROJECT_ROOT}/src/"
```

## Best Practices

1. **Cite as you go** - Don't wait until checkpoint to add citations
2. **Use JIT retrieval** - Store lightweight identifiers, retrieve full code on demand
3. **Flag assumptions early** - Be explicit about what lacks code evidence
4. **Configure appropriately** - Use `warn` during exploration, `strict` during implementation
5. **Review trajectory** - Check grounding distribution before `/clear`

---

## Related Protocols

- [Session Continuity](session-continuity.md) - Session lifecycle including grounding handoff
- [Synthesis Checkpoint](synthesis-checkpoint.md) - Pre-clear validation including grounding
- [JIT Retrieval](jit-retrieval.md) - Token-efficient evidence retrieval
- [Trajectory Evaluation](trajectory-evaluation.md) - Logging claims with grounding type
- [Citations](citations.md) - Word-for-word citation requirements

---

**Protocol Version**: 1.0
**Last Updated**: 2025-12-27
**Paradigm**: Clear, Don't Compact
