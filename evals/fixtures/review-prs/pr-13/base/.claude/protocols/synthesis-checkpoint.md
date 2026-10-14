# Synthesis Checkpoint Protocol

> **Paradigm**: Clear, Don't Compact
> **Mode**: Blocking (pre-clear validation)

## Purpose

Mandatory validation before any `/clear` command to ensure zero information loss. The synthesis checkpoint verifies grounding quality, persists work to lossless ledgers, and creates a complete audit trail.

## Simplified Checkpoint (Recommended)

The checkpoint has **3 manual steps**; Steps 1, 2, 5, and 6 are automated by the context manager.

### Running Simplified Checkpoint

```bash
# Run automated checks + show manual steps
.claude/scripts/context-manager.sh checkpoint
```

### 3 Manual Steps

| Step | Action | Verification |
|------|--------|--------------|
| **1** | Verify Decision Log updated | Check NOTES.md has today's key decisions |
| **2** | Verify Bead updated | Run `br list --status=in_progress` |
| **3** | Verify EDD test scenarios | At least 3 test scenarios per decision |

### Automated Checks

The `context-manager.sh checkpoint` command automatically verifies:

- ✅ Trajectory logged (entries exist for today)
- ✅ Session Continuity section present in NOTES.md
- ✅ Decision Log section present in NOTES.md
- ✅ Beads synchronized (if br CLI available)

### When to Use Simplified Checkpoint

| Scenario | Use Simplified | Use Full 7-Step |
|----------|----------------|-----------------|
| Regular development | ✅ Yes | No |
| Before `/compact` | ✅ Yes | No |
| Before `/clear` (strict mode) | No | ✅ Yes |
| Security-sensitive work | No | ✅ Yes |
| Production deployments | No | ✅ Yes |

### Configuration

```yaml
# .loa.config.yaml
context_management:
  simplified_checkpoint: true  # Enable 3-step checkpoint
```

---

## Step Details

The full checkpoint runs all 7 steps in order: Steps 1-2 block `/clear` on failure; Steps 3-7 persist state and never block. All 7 must complete before `/clear` is permitted.

### Step 1: Grounding Verification (BLOCKING)

Verify that decisions are backed by evidence:

```bash
# Run grounding check script
result=$(.claude/scripts/grounding-check.sh "$AGENT" "$THRESHOLD")

# Parse result
ratio=$(echo "$result" | grep "grounding_ratio=" | cut -d= -f2)
status=$(echo "$result" | grep "status=" | cut -d= -f2)

if [[ "$status" == "fail" ]]; then
    echo "ERROR: Grounding ratio $ratio below threshold $THRESHOLD"
    echo "Action: Add citations or mark as [ASSUMPTION]"
    exit 1
fi
```

**Blocking Behavior**:
- If ratio < threshold: Block `/clear`, require remediation
- User must add evidence or mark claims as assumptions
- Re-run checkpoint after remediation

### Step 2: Negative Grounding (BLOCKING in strict)

Verify Ghost Features (claimed non-existence):

```bash
# Count unverified ghosts from trajectory
unverified=$(grep -c '"status":"unverified"' "$TRAJECTORY" 2>/dev/null || echo "0")
high_ambiguity=$(grep -c '"status":"high_ambiguity"' "$TRAJECTORY" 2>/dev/null || echo "0")

if [[ "$ENFORCEMENT" == "strict" ]]; then
    if [[ "$unverified" -gt 0 ]] || [[ "$high_ambiguity" -gt 0 ]]; then
        echo "ERROR: $((unverified + high_ambiguity)) Ghost Features unverified"
        echo "Action: Human audit required"
        exit 1
    fi
fi
```

**Blocking Behavior** (strict mode only):
- If unverified ghosts exist: Block `/clear`
- Require human audit or ghost removal
- In warn mode: Log warning but allow

### Step 3: Update Decision Log (NON-BLOCKING)

Persist decisions to NOTES.md:

```bash
# Append decisions to NOTES.md Decision Log
cat >> "${PROJECT_ROOT}/grimoires/loa/NOTES.md" << EOF

### Session ${SESSION_ID} Decisions (${TIMESTAMP})
$(extract_session_decisions "$TRAJECTORY")
EOF
```

**Format**:
```markdown
### Session abc123 Decisions (2024-01-15T14:30:00Z)

| Decision | Evidence | Test Scenarios |
|----------|----------|----------------|
| JWT validation uses RS256 | `const algorithm = 'RS256'` [${PROJECT_ROOT}/src/auth/jwt.ts:45] | Token expires correctly |
```

### Step 4: Update Bead (NON-BLOCKING)

Append to active Bead's decisions[] and next_steps[]:

```bash
# If beads available
if command -v br &>/dev/null; then
    # Get active bead
    active_bead=$(br show --active --json | jq -r '.id')

    # Update with session decisions
    br update "$active_bead" \
        --add-decision "Implemented JWT refresh: ${PROJECT_ROOT}/src/auth/refresh.ts:12-45" \
        --add-next-step "Add token revocation endpoint"
fi
```

**Fallback**: If Beads unavailable, log to NOTES.md only.

### Step 5: Log Session Handoff (NON-BLOCKING)

Create trajectory entry for session handoff:

```jsonl
{
  "timestamp": "2024-01-15T14:30:00Z",
  "phase": "session_handoff",
  "session_id": "abc123",
  "root_span_id": "span-456",
  "bead_id": "beads-x7y8",
  "grounding_ratio": 0.97,
  "decisions_count": 5,
  "notes_refs": [
    "${PROJECT_ROOT}/grimoires/loa/NOTES.md:45-67"
  ],
  "next_session_hints": [
    "Continue with token revocation",
    "Review refresh edge cases"
  ]
}
```

### Step 6: Decay Raw Output (NON-BLOCKING)

Convert full code blocks to lightweight identifiers:

```
BEFORE (in context):
```typescript
export function validateToken(token: string): boolean {
  const decoded = jwt.verify(token, publicKey);
  return !isExpired(decoded);
}
```

AFTER (lightweight identifier):
${PROJECT_ROOT}/src/auth/jwt.ts:45-49 | Token validation | 14:30Z
```

This decays ~500 tokens to ~15 tokens (97% reduction).

### Step 7: Verify EDD (NON-BLOCKING)

Ensure Evidence-Driven Development compliance:

```bash
# Count documented test scenarios
test_scenarios=$(grep -c '"type":"test_scenario"' "$TRAJECTORY" 2>/dev/null || echo "0")

if [[ "$test_scenarios" -lt 3 ]]; then
    echo "WARNING: Only $test_scenarios test scenarios documented (minimum: 3)"
    # Log warning but don't block
fi
```

**EDD Minimum**:
- 3 test scenarios per significant decision
- Types: happy_path, edge_case, error_handling

## Failure Scenario (illustrative — Step 2's report follows the same shape)

```
SYNTHESIS CHECKPOINT FAILED

Step 1: Grounding Verification - FAILED
  Current ratio: 0.82
  Required: >= 0.95
  Ungrounded claims: 4

  1. "Cache expires after 24 hours" - No code citation
  2. "Rate limit is 100 req/min" - No code citation
  3. "Users prefer dark mode" - [ASSUMPTION] needed
  4. "API uses REST v2" - No code citation

Actions:
  - Add word-for-word code citations
  - Or mark as [ASSUMPTION] for unverifiable claims
  - Then retry /clear

/clear BLOCKED
```

## Configuration

```yaml
# .loa.config.yaml
synthesis_checkpoint:
  enabled: true

  # Step 1: Grounding
  grounding_threshold: 0.95
  grounding_enforcement: strict  # strict | warn | disabled

  # Step 2: Negative Grounding
  negative_grounding:
    enabled: true
    strict_blocks: true

  # Step 7: EDD
  edd:
    enabled: true
    min_test_scenarios: 3
    warn_only: true  # Don't block, just warn
```

## Hook Integration

Configure Claude Code hook for pre-clear validation:

```yaml
# Claude Code hooks configuration
hooks:
  pre-clear:
    command: .claude/scripts/synthesis-checkpoint.sh
    blocking: true
    on_failure: reject
    timeout: 30s
```

**Hook Behavior**:
- Exit 0: Allow `/clear`
- Exit 1: Block `/clear`, show error message
- Exit 2: Error in checkpoint script itself

## Remediation Guide

**Low grounding ratio**: find ungrounded claims (`grep '"grounding":"assumption"' "$TRAJECTORY"`), search for evidence (`ck --hybrid "cache expiry configuration" "${PROJECT_ROOT}/src/" --top-k 5`), then either cite it:

```markdown
Cache TTL is 24 hours: `const CACHE_TTL = 86400` [${PROJECT_ROOT}/src/cache/config.ts:12]
```

or mark it as an assumption:

```markdown
[ASSUMPTION] Users prefer dark mode (no analytics data available)
```

**Unverified Ghost Features**: run a second, differently-worded query (ck v0.7.0+ syntax):

```bash
ck --sem "alternative terminology for feature" --jsonl "${PROJECT_ROOT}/src/"
```

and document the verification:

```jsonl
{"phase":"negative_ground","query2":"alternative search","results2":0}
```

or request human audit instead:

```markdown
[UNVERIFIED GHOST] OAuth2 SSO - Requires human verification
```

---

## Related Protocols

- [Grounding Enforcement](grounding-enforcement.md) - Citation requirements and ratio calculation
- [Session Continuity](session-continuity.md) - Session lifecycle and recovery
- [Attention Budget](attention-budget.md) - Delta-synthesis triggers
- [Trajectory Evaluation](trajectory-evaluation.md) - Logging claims and handoffs
