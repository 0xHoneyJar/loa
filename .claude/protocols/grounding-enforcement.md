# Grounding Enforcement Protocol

## Purpose

Verify citation quality and enforce a grounding ratio to prevent hallucinated or ungrounded claims. Decisions must cite verifiable evidence — a word-for-word code quote, an absolute path, and a line number — or be flagged as an assumption.

## Grounding Ratio

```
grounding_ratio = grounded_claims / total_claims
```

`total_claims` is every decision logged this session with `"phase":"cite"`. `grounded_claims` counts entries whose `grounding` is `citation`, `code_reference`, or `user_input`; `assumption` entries do not count. Sessions with zero claims pass automatically (`grounding_ratio = 1.00`) — a read-only or exploration session makes no claims, so there is nothing to hallucinate.

| Level | Threshold | Behavior |
|-------|-----------|----------|
| `strict` | >= 0.95 | Blocks `/clear` below threshold, and blocks on any unverified Ghost Feature, until remediated. Default for security-critical projects. |
| `warn` | >= 0.95 | Warns below threshold but allows `/clear`; logs the warning to trajectory. Default for development. |
| `disabled` | N/A | No enforcement — prototyping only. |

Set the level with `grounding_enforcement` in `.loa.config.yaml` (see Configuration below).

## Citation Format

Every code-grounded claim needs all three parts — an exact quote in backticks, an absolute path with the `${PROJECT_ROOT}` prefix, and a line number:

```
`<word-for-word code quote>` [${PROJECT_ROOT}/<path>:<line>]

Correct:
`export function validateToken(token: string)` [${PROJECT_ROOT}/src/auth/jwt.ts:45]

Incorrect — relative path, missing line, or paraphrase instead of a quote:
`validateToken(token)` [src/auth/jwt.ts:45]
`validateToken(token)` [${PROJECT_ROOT}/src/auth/jwt.ts]
"The function validates tokens" [${PROJECT_ROOT}/src/auth/jwt.ts:45]
```

## Grounding Types and Trajectory Logging

| Type | Description | Evidence required |
|------|-------------|--------------------|
| `citation` | Direct code quote | Code + path + line |
| `code_reference` | Reference to existing code | Path + line |
| `user_input` | Based on the user's explicit request | Message ID or source |
| `assumption` | Ungrounded claim | Must be flagged |

Log every claim to trajectory in this shape:

```jsonl
{"phase":"cite","claim":"JWT validates expiry","grounding":"citation","evidence":{"quote":"if (isExpired(token))","path":"${PROJECT_ROOT}/src/auth/jwt.ts","line":67}}
{"phase":"cite","claim":"Users prefer dark mode","grounding":"assumption","evidence":null}
```

## Verification

`.claude/scripts/grounding-check.sh [agent] [threshold] [date]` reads the trajectory log and computes the ratio. Exit 0 = ratio meets threshold (or zero claims); exit 1 = below threshold, and it lists the ungrounded claims; exit 2 = missing dependency (`bc`) or an invalid threshold argument. `synthesis-checkpoint.sh` calls it as a blocking step — call the script and branch on its exit code and `status=` output rather than recomputing the ratio inline.

## Configuration

```yaml
grounding_enforcement: strict     # strict | warn | disabled

grounding:
  threshold: 0.95                 # Minimum ratio required
  zero_claim_passes: true
  log_ungrounded: true            # Log assumption claims to trajectory
  negative:
    enabled: true
    query_count: 2                 # Diverse queries required to prove absence
    similarity_threshold: 0.4      # Below this = no match
    doc_mention_threshold: 3       # Flag for human audit at/above this many doc mentions
    strict_mode_blocks: true       # Block /clear on unverified ghosts, in strict mode
```

## Error Messages

When the ratio check fails, name the ratio, the threshold, and every ungrounded claim so remediation is fill-in-the-blanks, not a re-investigation:

```
ERROR: Grounding ratio too low
Current ratio: 0.87 (target: >= 0.95)
Ungrounded claims:
1. "The cache expires after 24 hours" - Add code citation
2. "Users authenticate via OAuth" - Add code citation
3. "Rate limit is 100 req/min" - Add code citation
Actions: add a citation for each, or mark it [ASSUMPTION]; then retry /clear.
```

## Negative Grounding

Negative grounding verifies a claim of **non-existence** ("OAuth2 SSO is not implemented" — a "Ghost Feature": mentioned in docs, absent from code). A single query returning 0 results does not prove absence; run two lexically diverse queries, since a term missing the code's actual vocabulary produces a false negative that a synonym would catch.

```bash
# ck v0.7.0+ syntax: --sem (not --semantic), --limit (not --top-k), path is positional
results1=$(ck --sem "OAuth2 authentication SSO" --limit 10 --threshold 0.4 --jsonl "${PROJECT_ROOT}/src/")
results2=$(ck --sem "single sign-on identity provider" --limit 10 --threshold 0.4 --jsonl "${PROJECT_ROOT}/src/")
# Both must return 0 matches to count as VERIFIED GHOST.
```

Without `ck`, fall back to grep with the same two-query discipline:

```bash
grep -rn -i "oauth\|sso\|saml" "${PROJECT_ROOT}/src/" 2>/dev/null | wc -l
grep -rn -i "identity.provider\|sign.on\|auth.provider" "${PROJECT_ROOT}/src/" 2>/dev/null | wc -l
```

If both queries return 0 and the documentation mentions the feature 3+ times, flag `[UNVERIFIED GHOST]` rather than asserting non-existence outright: in `strict` mode block `/clear` for a human audit; in `warn` mode allow `/clear` with a logged warning. Log it the same way as any other claim:

```jsonl
{"phase":"negative_ground","claim":"OAuth2 SSO not implemented","query1":"OAuth2 authentication SSO","results1":0,"query2":"single sign-on identity provider","results2":0,"doc_mentions":5,"status":"high_ambiguity","action":"human_audit_required"}
```

## Anti-Patterns

**Assumption without a flag** — making a claim with no evidence and no `[ASSUMPTION]` marker.

**Bulk assumptions** — marking most decisions `[ASSUMPTION]` just to pass the ratio check defeats the purpose; investigate for evidence instead of flagging around it.

## Remediation

When the ratio is below threshold: list the ungrounded claims, search for supporting code, add citations, flag what's truly ungrounded as `[ASSUMPTION]`, and re-run the check.

```bash
ck --hybrid "validates JWT token" "${PROJECT_ROOT}/src/" --limit 5
# Fallback without ck:
grep -rn "validateToken\|JWT\|token" "${PROJECT_ROOT}/src/"
```

## Integration Points

`synthesis-checkpoint.sh` runs grounding as its first two blocking steps before permitting `/clear`: Step 1 calls `grounding-check.sh` for the ratio; Step 2 runs the negative-grounding check (blocking in `strict` mode). Ledger sync in the remaining steps is non-blocking. `trajectory-evaluation.md`'s `cite` phase is where claims get logged with their `grounding` type; `session-continuity.md` records the resulting `grounding_ratio` in the session handoff.

## Related Protocols

- [Session Continuity](session-continuity.md) - Session lifecycle including grounding handoff
- [Synthesis Checkpoint](synthesis-checkpoint.md) - Pre-clear validation including grounding
- [JIT Retrieval](jit-retrieval.md) - Token-efficient evidence retrieval
- [Trajectory Evaluation](trajectory-evaluation.md) - Logging claims with grounding type
- [Citations](citations.md) - Word-for-word citation requirements
