# Negative Grounding Protocol (Ghost Feature Detection)

> Inspired by scientific null hypothesis testing and Google's ADK Evaluation-Driven Development (EDD).

## Purpose

Detect features that are **documented but not implemented** - called "Ghost Features" - to prevent documentation drift and identify strategic liabilities.

## Problem Statement

Traditional search approaches produce false negatives:
- Single query may miss code under different terminology
- Low threshold may exclude valid implementations
- High threshold may miss approximate matches

**Ghost Features** represent documented functionality that doesn't exist in code - a critical form of drift that creates user expectations the system cannot meet.

## The Protocol: Two-Query Verification

To confirm a feature is truly absent (not just hard to find), we require **TWO diverse semantic queries**, both returning zero results.

### Step 1: Primary Query (Functional Description)

```bash
# Query 1: Use the feature's functional description from docs
query1="OAuth2 SSO login flow single sign-on"
results1=$(semantic_search "${query1}" "src/" 10 0.4)
count1=$(echo "${results1}" | count_search_results)
```

**Rationale**: Search for how the feature is described in documentation.

### Step 2: Secondary Query (Architectural Synonym)

```bash
# Query 2: Use architectural/technical synonyms
query2="identity provider authentication SAML federation"
results2=$(semantic_search "${query2}" "src/" 10 0.4)
count2=$(echo "${results2}" | count_search_results)
```

**Rationale**: Developers may use different terminology than documentation. Cast a wider semantic net.

### Step 3: Classification

```bash
# Count total code results
total_code_results=$((count1 + count2))

# Count documentation mentions
doc_mentions=$(grep -rl "OAuth2\|SSO\|single sign-on" grimoires/loa/{prd,sdd}.md README.md docs/ 2>/dev/null | wc -l)
```

**Classification Matrix**:

| Code Results | Doc Mentions | Classification | Risk | Action |
|--------------|--------------|----------------|------|--------|
| 0 | 0-2 | **CONFIRMED GHOST** | HIGH | Track in Beads, remove from docs |
| 0 | 3+ | **HIGH AMBIGUITY** | UNKNOWN | Flag for human audit |
| 1+ | Any | **NOT GHOST** | N/A | Feature exists, verify alignment |

### Step 4: Ambiguity Detection

**High Ambiguity** occurs when:
- Zero code evidence found (both queries return 0 results)
- BUT multiple documentation references exist (3+ mentions)

This indicates either:
1. Feature is genuinely missing (ghost)
2. Feature exists under radically different naming
3. Feature is planned but not implemented yet

**Action**: Request human audit with full context.

### Step 5: Tracking & Logging

#### If CONFIRMED GHOST:

```bash
# Track in Beads (if available)
if command -v br >/dev/null 2>&1; then
    br create "GHOST: OAuth2 SSO" \
        --type liability \
        --priority 2 \
        --metadata "query1=${query1},query2=${query2},doc_refs=${doc_mentions}"
fi

# Log to trajectory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME}" \
    --arg phase "ghost_detection" \
    --arg feature "OAuth2 SSO" \
    --arg query1 "${query1}" \
    --argjson results1 "${count1}" \
    --arg query2 "${query2}" \
    --argjson results2 "${count2}" \
    --argjson doc_mentions "${doc_mentions}" \
    --arg status "confirmed_ghost" \
    '{ts: $ts, agent: $agent, phase: $phase, feature: $feature, query1: $query1, results1: $results1, query2: $query2, results2: $results2, doc_mentions: $doc_mentions, status: $status}' \
    >> "${TRAJECTORY_FILE}"

# Write to drift report
echo "| OAuth2 SSO | PRD §3.2 | Q1: 0, Q2: 0 | Low | beads-123 | Remove from docs |" \
    >> grimoires/loa/drift-report.md
```

#### If HIGH AMBIGUITY:

```bash
# Flag for human review
echo "⚠️  HIGH AMBIGUITY: OAuth2 SSO" >&2
echo "   - Code results: 0 (from 2 diverse queries)" >&2
echo "   - Doc mentions: ${doc_mentions} (≥3 references)" >&2
echo "   - Action: Human audit required" >&2

# Log to trajectory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

jq -n \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME}" \
    --arg phase "ghost_detection" \
    --arg feature "OAuth2 SSO" \
    --arg status "high_ambiguity" \
    --arg reason "0 code results but ${doc_mentions} doc mentions - manual review needed" \
    '{ts: $ts, agent: $agent, phase: $phase, feature: $feature, status: $status, reason: $reason}' \
    >> "${TRAJECTORY_FILE}"

# Write to drift report with annotation
echo "| OAuth2 SSO | PRD §3.2 | Q1: 0, Q2: 0 | **High (${doc_mentions} mentions)** | - | **Human audit required** |" \
    >> grimoires/loa/drift-report.md
```

## Query Design Guidelines

### Primary Query (Functional)
- Use exact phrasing from documentation
- Include key feature nouns and verbs
- Keep concise (4-8 words)
- Example: "OAuth2 SSO login flow"

### Secondary Query (Architectural)
- Use technical synonyms and related concepts
- Include implementation patterns
- Cast wider semantic net
- Example: "identity provider authentication federation"

### Query Diversity Requirements

Queries MUST differ in:
1. **Terminology**: Different words for same concept
2. **Abstraction Level**: High-level concept vs low-level implementation
3. **Domain Language**: User-facing terms vs technical jargon

**Bad Example** (not diverse):
```bash
query1="OAuth2 SSO login"
query2="OAuth2 single sign-on authentication"  # Too similar!
```

**Good Example** (diverse):
```bash
query1="OAuth2 SSO login flow"           # Functional, doc terminology
query2="identity provider SAML federation"  # Architectural, tech terminology
```

## Integration with /ride Command

The `/ride` command Phase C (Ghost Features) should:

1. Parse PRD/SDD for feature claims
2. For each major feature:
   - Design two diverse queries
   - Execute negative grounding protocol
   - Classify result
   - Track ghosts or flag ambiguity
3. Write all findings to `grimoires/loa/drift-report.md`

## Threshold Settings

- **Search Threshold**: 0.4 (PRD requirement)
- **Ambiguity Threshold**: 3+ doc mentions
- **Query Count**: Exactly 2 (not 1, not 3+)

## Why Two Queries?

**One query** is insufficient:
- Single semantic space may miss alternate terminology
- One query could have been poorly designed

**Three+ queries** is excessive:
- Diminishing returns (if 2 fail, 3rd unlikely to succeed)
- Wastes tokens and time
- Over-fitting to find code that genuinely doesn't exist

**Two queries** is optimal:
- Balances thoroughness with efficiency
- Tests feature from different semantic angles
- Sufficient to rule out false negatives

## Anti-Patterns to Avoid

❌ **Single Query Confirmation**
```bash
# BAD: Only one query
results=$(semantic_search "OAuth2" "src/" 10 0.4)
if [[ $(count_search_results) -eq 0 ]]; then
    echo "Ghost Feature!"  # Premature conclusion
fi
```

✅ **Proper Two-Query Protocol**
```bash
# GOOD: Two diverse queries
results1=$(semantic_search "OAuth2 SSO login flow" "src/" 10 0.4)
results2=$(semantic_search "identity provider authentication" "src/" 10 0.4)

if [[ $(($(count_search_results <<< "${results1}") + $(count_search_results <<< "${results2}"))) -eq 0 ]]; then
    # Now we can confidently classify
    classify_ghost_feature "OAuth2 SSO"
fi
```

❌ **Ignoring Ambiguity**
```bash
# BAD: Not checking doc mentions
if [[ ${total_code_results} -eq 0 ]]; then
    echo "CONFIRMED GHOST"  # Maybe, maybe not
fi
```

✅ **Ambiguity Detection**
```bash
# GOOD: Check doc mentions
if [[ ${total_code_results} -eq 0 ]] && [[ ${doc_mentions} -ge 3 ]]; then
    echo "HIGH AMBIGUITY - human audit required"
elif [[ ${total_code_results} -eq 0 ]] && [[ ${doc_mentions} -lt 3 ]]; then
    echo "CONFIRMED GHOST"
fi
```

## Output Format

### Drift Report Entry (Confirmed Ghost)

```markdown
## Strategic Liabilities (Ghost Features)

| Feature | Doc Source | Search Evidence | Ambiguity | Beads ID | Action |
|---------|-----------|-----------------|-----------|----------|--------|
| OAuth2 SSO | PRD §3.2 | Q1: 0, Q2: 0 | Low | beads-123 | Remove from docs |
| Email Notifications | PRD §5.1 | Q1: 0, Q2: 0 | Low | beads-124 | Implement or remove |
```

### Drift Report Entry (High Ambiguity)

```markdown
## Strategic Liabilities (Ghost Features)

| Feature | Doc Source | Search Evidence | Ambiguity | Beads ID | Action |
|---------|-----------|-----------------|-----------|----------|--------|
| Real-time Updates | PRD §4.3 | Q1: 0, Q2: 0 | **High (5 mentions)** | - | **Human audit required** |
```

## Grounding Ratio Impact

Negative Grounding contributes to the overall grounding ratio (target ≥0.95):

- **Grounded Claim**: "Feature X exists: `code_snippet` [file:line]"
- **Grounded Ghost**: "Feature X is a ghost: Q1=0, Q2=0, doc_mentions=2"
- **Ungrounded Claim**: "Feature X probably doesn't exist" (no evidence)

**Key Insight**: A properly executed Ghost detection IS grounded (backed by search evidence of absence).

## Related Protocols

- **Tool Result Clearing**: Apply after Ghost detection (clear raw search results)
- **Trajectory Evaluation**: Log all Ghost detections with reasoning
- **Shadow System Classifier**: Opposite problem (code exists, docs missing)

---

**Last Updated**: 2025-12-27
**Protocol Version**: 1.0
**PRD Reference**: FR-3.2
