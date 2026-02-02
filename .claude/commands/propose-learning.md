---
name: propose-learning
description: Propose an eligible learning for upstream contribution to Loa framework
agent: implementing-tasks
agent_path: .claude/skills/implementing-tasks
allowed-tools: Read, Bash, Write, Edit
---

# /propose-learning Command

## Purpose

Submit an eligible project learning as a proposal to the upstream Loa framework repository. This command handles:
1. Eligibility validation (score ≥ 70, applications ≥ 3, success rate ≥ 80%)
2. Duplicate detection via Jaccard similarity (threshold 0.7)
3. PII anonymization before submission
4. GitHub Issue creation with `learning-proposal` label
5. Learning status tracking

## Usage

```bash
/propose-learning <learning-id>
/propose-learning <learning-id> --dry-run
/propose-learning <learning-id> --force
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<learning-id>` | ID of the learning to propose (e.g., `L-0001`) |
| `--dry-run` | Preview proposal without creating Issue |
| `--force` | Skip eligibility check |

## Prerequisites

1. **Learning exists** in `grimoires/loa/a2a/compound/learnings.json`
2. **Learning is eligible** (unless `--force` is used):
   - `upstream_score` ≥ 70
   - `applications` ≥ 3
   - `success_rate` ≥ 80%
3. **GitHub CLI authenticated** (`gh auth status`)
4. **No duplicate proposals** (Jaccard similarity < 0.7)

## Workflow

```
┌────────────────────────────────────────────────────────────┐
│                    /propose-learning                       │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  1. Validate Learning Exists                               │
│     └─→ Check learnings.json for ID                       │
│                                                            │
│  2. Check Eligibility                                      │
│     └─→ upstream-score-calculator.sh --check-eligibility  │
│                                                            │
│  3. Detect Duplicates                                      │
│     └─→ jaccard-similarity.sh vs existing proposals       │
│                                                            │
│  4. Generate Proposal Body                                 │
│     └─→ Template with learning fields                     │
│                                                            │
│  5. Anonymize Content                                      │
│     └─→ anonymize-proposal.sh --stdin                     │
│                                                            │
│  6. Create GitHub Issue                                    │
│     └─→ gh-label-handler.sh create-issue                  │
│                                                            │
│  7. Update Learning Status                                 │
│     └─→ proposal.status = "submitted"                     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Proposal Template

The generated Issue follows this structure:

```markdown
## Learning Proposal

**ID:** L-0001
**Category:** pattern

### Title
[Learning title]

### Context
[When/where this was discovered]

### Trigger
[Conditions that indicate this learning applies]

### Solution
[The pattern/solution discovered]

### Effectiveness

| Metric | Value |
|--------|-------|
| Applications | 5 |
| Success Rate | 80% |
| Verified | true |
| Upstream Score | 75 |

### Tags
architecture, performance, debugging

---

### Quality Gates

| Gate | Score |
|------|-------|
| Discovery Depth | 7 |
| Reusability | 8 |
| Trigger Clarity | 6 |
| Verification | 7 |

---

*This proposal was automatically generated from a project learning...*
```

## Anonymization

Before submission, the following PII is redacted:

| Type | Pattern | Replacement |
|------|---------|-------------|
| API Keys | `sk-*`, `ghp_*` | `[REDACTED_API_KEY]` |
| Paths | `/home/user/*` | `[REDACTED_PATH]` |
| Domains | Project domains | `[REDACTED_DOMAIN]` |
| Usernames | `@mentions` | `[REDACTED_USER]` |
| Emails | `*@*.com` | `[REDACTED_EMAIL]` |
| IPs | `192.168.*` | `[REDACTED_IP]` |

## Configuration

In `.loa.config.yaml`:

```yaml
upstream_detection:
  enabled: true
  min_occurrences: 3
  min_success_rate: 0.8
  min_upstream_score: 70
  novelty_threshold: 0.7

upstream_proposals:
  target_repo: "0xHoneyJar/loa"
  label: "learning-proposal"
  anonymization:
    enabled: true
  rejection_cooldown_days: 90
```

## Status Tracking

After submission, the learning entry is updated:

```json
{
  "id": "L-0001",
  "proposal": {
    "status": "submitted",
    "issue_ref": "#123",
    "submitted_at": "2026-02-02T18:00:00Z",
    "upstream_score_at_submission": 75,
    "anonymized": true
  }
}
```

### Proposal Statuses

| Status | Description |
|--------|-------------|
| `none` | No proposal attempted |
| `draft` | Proposal created but not submitted |
| `submitted` | Issue created, awaiting review |
| `under_review` | Maintainer is reviewing |
| `accepted` | Merged into framework learnings |
| `rejected` | Not accepted (90-day cooldown) |

## Examples

### Preview a Proposal

```bash
/propose-learning L-0001 --dry-run
```

Output:
```
Proposal Generator
─────────────────────────────────────────

  Learning: L-0001
  Title: Three-Zone Model prevents framework pollution

  Checking eligibility...
  ✓ Eligible

  Checking for duplicates...
  ✓ Unique

  Generating proposal...
  ✓ Generated

─────────────────────────────────────────
Proposal Preview
─────────────────────────────────────────

Title: [Learning Proposal] Three-Zone Model prevents framework pollution
Repository: 0xHoneyJar/loa
Labels: learning-proposal

Body:
[... proposal content ...]

[DRY RUN] No Issue created
```

### Submit a Proposal

```bash
/propose-learning L-0001
```

Output:
```
Proposal Generator
─────────────────────────────────────────

  Learning: L-0001
  Title: Three-Zone Model prevents framework pollution

  Checking eligibility...
  ✓ Eligible

  Checking for duplicates...
  ✓ Unique

  Generating proposal...
  ✓ Generated

  Creating GitHub Issue...
  ✓ Issue created

  Updating learning status...
  ✓ Updated

─────────────────────────────────────────
Proposal Submitted Successfully

  Issue: https://github.com/0xHoneyJar/loa/issues/123
  Reference: #123
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Learning not found" | Invalid ID | Check learnings.json for valid IDs |
| "Not eligible" | Below thresholds | Wait for more applications or use `--force` |
| "Duplicate detected" | Similar proposal exists | Review existing proposal or use different learning |
| "Already has proposal status" | Previously submitted | Use `--force` to resubmit |
| "gh auth failed" | Not authenticated | Run `gh auth login` |

## Related Commands

- `/retrospective` - Capture learnings from development sessions
- `/compound` - Synthesize learnings across sessions
- `/skill-audit` - Review extracted skills
- `check-proposal-status.sh` - Check proposal status updates

## Scripts

- `.claude/scripts/proposal-generator.sh` - Main orchestration
- `.claude/scripts/upstream-score-calculator.sh` - Eligibility scoring
- `.claude/scripts/anonymize-proposal.sh` - PII redaction
- `.claude/scripts/jaccard-similarity.sh` - Duplicate detection
- `.claude/scripts/gh-label-handler.sh` - Issue creation
