# Maintainer Guide: Learning Proposals

This guide documents how to review and process learning proposals submitted via the Upstream Learning Flow (v1.16.0+).

## Overview

The Upstream Learning Flow allows users to contribute high-value learnings discovered in their projects back to the Loa framework. Proposals arrive as GitHub Issues with the `learning-proposal` label.

## Proposal Format

Each proposal Issue follows this structure:

```markdown
## Learning Proposal

**ID:** L-0001
**Category:** pattern | anti-pattern | decision | troubleshooting

### Title
[Brief title describing the learning]

### Context
[When/where this was discovered]

### Trigger
[Conditions that indicate this learning applies]

### Solution
[The pattern/solution discovered]

### Effectiveness

| Metric | Value |
|--------|-------|
| Applications | N |
| Success Rate | XX% |
| Verified | true/false |
| Upstream Score | XX |

### Quality Gates

| Gate | Score |
|------|-------|
| Discovery Depth | X |
| Reusability | X |
| Trigger Clarity | X |
| Verification | X |
```

## Review Criteria

### Acceptance Criteria

Accept proposals that meet ALL of these criteria:

1. **Novel**: Not a duplicate of existing framework learnings
   - Check `.claude/loa/learnings/*.json` for similar content
   - Use semantic similarity, not just exact match

2. **General**: Applicable beyond the submitter's specific project
   - Should help users across different tech stacks
   - Domain-specific learnings (React-only, AWS-only) have lower priority

3. **Verified**: Has evidence of working
   - Applications ≥ 3
   - Success Rate ≥ 80%
   - Upstream Score ≥ 70

4. **Well-Structured**: Clear trigger and solution
   - Trigger describes when to apply
   - Solution provides actionable guidance
   - Quality gates average ≥ 5/10

5. **Anonymized**: No PII visible
   - Check for paths, usernames, domains
   - All should be `[REDACTED_*]` placeholders

### Rejection Reasons

Use these standardized codes when rejecting:

| Code | Label | Description |
|------|-------|-------------|
| `duplicate` | `duplicate` | Already exists in framework learnings |
| `too_specific` | `project-specific` | Too narrow for general use |
| `insufficient_evidence` | `needs-evidence` | Not enough applications or low success rate |
| `low_quality` | `needs-improvement` | Quality gates too low or unclear |
| `out_of_scope` | `wontfix` | Doesn't fit Loa's domain |
| `other` | - | Explain in comment |

## Review Workflow

### Step 1: Triage

1. Check `learning-proposal` label exists
2. Verify proposal follows expected format
3. Add `under-review` label

### Step 2: Duplicate Check

```bash
# Search existing learnings for similar content
.claude/scripts/loa-learnings-index.sh query "<key terms from title>"
```

If similarity > 70%, likely duplicate.

### Step 3: Quality Assessment

Review:
- Upstream Score (should be ≥ 70)
- Applications (should be ≥ 3)
- Success Rate (should be ≥ 80%)
- Quality Gates (should average ≥ 5/10)

### Step 4: Decision

#### To Accept

1. Convert proposal to learning entry:
   ```json
   {
     "id": "FRAMEWORK-XXX",
     "tier": "framework",
     "type": "pattern",
     "version_added": "1.X.0",
     "source_origin": "community",
     "title": "...",
     "context": "Contributed via learning proposal #123",
     "trigger": "...",
     "solution": "...",
     "verified": true,
     "tags": ["..."],
     "quality_gates": {
       "discovery_depth": X,
       "reusability": X,
       "trigger_clarity": X,
       "verification": X
     }
   }
   ```

2. Add to appropriate file in `.claude/loa/learnings/`:
   - `patterns.json` - for patterns
   - `anti-patterns.json` - for anti-patterns
   - `decisions.json` - for architecture decisions
   - `troubleshooting.json` - for troubleshooting

3. Update `index.json` counts

4. Add `accepted` label to Issue

5. Close Issue with comment:
   ```
   ✅ **Accepted**

   This learning has been merged into Loa v1.X.0 framework learnings.

   Thank you for your contribution!
   ```

#### To Reject

1. Add appropriate rejection label (see table above)

2. Close Issue with comment:
   ```
   ❌ **Rejected: [reason_code]**

   [Detailed explanation]

   You may resubmit after 90 days with improvements.
   ```

## Batch Processing

For multiple proposals:

```bash
# List all open proposals
gh issue list --repo 0xHoneyJar/loa --label "learning-proposal" --state open

# View specific proposal
gh issue view <number> --repo 0xHoneyJar/loa
```

## Configuration

Maintainers can adjust thresholds in `.loa.config.yaml`:

```yaml
upstream_detection:
  min_occurrences: 3
  min_success_rate: 0.8
  min_upstream_score: 70
```

## Cooldown Period

Rejected proposals trigger a 90-day cooldown for the same learning. This is enforced client-side via the `resubmit_blocked_until` field.

## Related Documentation

- [PRD: Upstream Learning Flow](grimoires/loa/prd.md)
- [SDD: Upstream Learning Flow](grimoires/loa/sdd.md)
- [continuous-learning SKILL.md](.claude/skills/continuous-learning/SKILL.md)
