---
name: "flatline-review"
version: "1.1.0"
description: |
  Manual invocation of Flatline Protocol for adversarial multi-model review.
  Use when auto-trigger is disabled or to re-run after document changes.
  Also provides rollback capability for autonomous integrations.

agent: "reviewing-code"
agent_path: ".claude/skills/reviewing-code/"

arguments:
  - name: "document"
    type: "string"
    required: false
    default: "auto"
    description: "Document to review (prd, sdd, sprint, or path)"

  - name: "--skip-knowledge"
    type: "flag"
    required: false
    description: "Skip knowledge retrieval phase"

  - name: "--skeptic-only"
    type: "flag"
    required: false
    description: "Run only skeptic reviews (faster, ~40% cost)"

  - name: "--dry-run"
    type: "flag"
    required: false
    description: "Validate without calling APIs"

  - name: "--budget"
    type: "number"
    required: false
    default: 300
    description: "Cost budget in cents (default: 300 = $3.00)"

  - name: "--rollback"
    type: "string"
    required: false
    description: "Rollback integration or run (integration-id, run-id, or snapshot-id)"

  - name: "--run-id"
    type: "string"
    required: false
    description: "Run ID for rollback operations"

  - name: "--snapshot"
    type: "string"
    required: false
    description: "Direct snapshot restore"

  - name: "--force"
    type: "flag"
    required: false
    description: "Force rollback despite divergence"

  - name: "--interactive"
    type: "flag"
    required: false
    description: "Force interactive mode (v1.22.0)"

  - name: "--autonomous"
    type: "flag"
    required: false
    description: "Force autonomous mode (v1.22.0)"

outputs:
  - path: "grimoires/loa/a2a/flatline/{phase}-review.json"
    type: "file"
    description: "Review results in JSON format"
---

# Flatline Review

## Purpose

Manually invoke the Flatline Protocol for adversarial multi-model review of planning documents.

## Usage

```bash
# Review current PRD
/flatline-review prd

# Review current SDD
/flatline-review sdd

# Review specific document
/flatline-review grimoires/loa/sdd.md

# Quick skeptic-only review
/flatline-review prd --skeptic-only

# Dry run to validate without API calls
/flatline-review sdd --dry-run
```

## When to Use

- After making significant document changes
- When auto-trigger is disabled in config
- To get a fresh perspective on a stuck decision
- Before finalizing planning documents
- When you want to re-run after addressing feedback

## Workflow

### Step 1: Resolve Document

```bash
# Auto-detect document from argument
case "$argument" in
    prd)
        doc="grimoires/loa/prd.md"
        phase="prd"
        ;;
    sdd)
        doc="grimoires/loa/sdd.md"
        phase="sdd"
        ;;
    sprint)
        doc="grimoires/loa/sprint.md"
        phase="sprint"
        ;;
    *)
        # Assume it's a path
        doc="$argument"
        # Infer phase from filename
        phase=$(basename "$doc" | sed 's/\.md$//' | grep -oE 'prd|sdd|sprint' || echo "prd")
        ;;
esac
```

### Step 2: Run Flatline Protocol

```bash
result=$(.claude/scripts/flatline-orchestrator.sh \
    --doc "$doc" \
    --phase "$phase" \
    ${skip_knowledge:+--skip-knowledge} \
    ${budget:+--budget "$budget"} \
    --json)
```

### Step 3: Display Results

Present results to user:

**HIGH_CONSENSUS items** (score >700 both models):
- These improvements have strong agreement
- Consider integrating them directly
- After integration, display: "Multi-model review working as designed. /feedback if you disagree."
  (Only when at least 1 HIGH_CONSENSUS item was integrated)

**DISPUTED items** (delta >300):
- Models disagreed significantly
- Review each one and decide

**BLOCKERS** (skeptic concern >700):
- Critical concerns that may block progress
- Must address before finalizing

### Step 4: Save Results

```bash
mkdir -p grimoires/loa/a2a/flatline
echo "$result" | jq . > "grimoires/loa/a2a/flatline/${phase}-review.json"
```

## Output Format

```json
{
    "phase": "prd",
    "document": "grimoires/loa/prd.md",
    "timestamp": "2026-02-03T12:00:00Z",
    "consensus_summary": {
        "high_consensus_count": 5,
        "disputed_count": 2,
        "low_value_count": 3,
        "blocker_count": 1,
        "model_agreement_percent": 73
    },
    "high_consensus": [...],
    "disputed": [...],
    "blockers": [...],
    "metrics": {
        "total_latency_ms": 95000,
        "cost_cents": 245
    }
}
```

## Skeptic-Only Mode

When `--skeptic-only` is specified:
- Only run skeptic reviews (no improvements)
- Faster execution (~40% of full cost)
- Focus on finding problems rather than suggestions
- Good for quick sanity checks

## Integration with Planning Commands

This command provides manual control. For automatic integration:
1. Enable in `.loa.config.yaml`:
   ```yaml
   flatline_protocol:
     enabled: true
     auto_trigger: true
   ```
2. Flatline will run automatically after `/plan-and-analyze`, `/architect`, `/sprint-plan`

## Configuration

```yaml
# .loa.config.yaml
flatline_protocol:
  enabled: true
  auto_trigger: false  # Set to true for automatic execution

  models:
    primary: "opus"
    secondary: "gpt-5.2"

  thresholds:
    high_consensus: 700
    dispute_delta: 300
    low_value: 400
    blocker: 700

  budget:
    max_tokens_per_phase: 100000
    warn_at_percent: 80
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Document not found" | Invalid path | Check document path |
| "Flatline disabled" | Config disabled | Enable in .loa.config.yaml |
| "API error" | Model unavailable | Check API keys, retry later |
| "Budget exceeded" | Cost limit hit | Increase budget or use --skeptic-only |
| "Timeout" | Slow API response | Retry or increase timeout |

## Rollback Commands (v1.22.0)

Rollback auto-integrated changes from autonomous Flatline execution.

### Usage

```bash
# Rollback single integration by ID
/flatline-review --rollback abc123-001-f7e8d9

# Rollback entire run
/flatline-review --rollback --run-id flatline-run-abc123

# Direct snapshot restore
/flatline-review --rollback --snapshot 20260203_143000_a1b2c3d4

# Force rollback despite divergence
/flatline-review --rollback abc123-001-f7e8d9 --force

# List rollback options for a run
/flatline-review --rollback --run-id flatline-run-abc123 --dry-run
```

### Rollback Workflow

When `--rollback` is specified:

```bash
if [[ -n "$rollback" ]]; then
    if [[ -n "$snapshot" ]]; then
        # Direct snapshot restore
        .claude/scripts/flatline-rollback.sh snapshot --snapshot-id "$snapshot" ${force:+--force}
    elif [[ -n "$run_id" ]]; then
        # Full run rollback
        .claude/scripts/flatline-rollback.sh run --run-id "$run_id" ${dry_run:+--dry-run} ${force:+--force}
    else
        # Single integration rollback
        .claude/scripts/flatline-rollback.sh single --integration-id "$rollback" ${run_id:+--run-id "$run_id"} ${force:+--force}
    fi
    exit $?
fi
```

### Divergence Detection

Before rollback, the system checks if the document has been modified since integration:
- **Expected hash**: Stored at integration time
- **Current hash**: Calculated from current file

If diverged:
- Without `--force`: Rollback refused with warning
- With `--force`: Creates backup and proceeds

### Backup Creation

Before any rollback, a backup is created:
- Path: `{document}.pre-rollback-{timestamp}`
- Permissions: 600 (owner only)
- Always created unless document doesn't exist

### Interactive Confirmation

In interactive mode, user confirmation is requested before rollback:

```
Document has been modified since integration.
Current hash:  a1b2c3d4...
Expected hash: e5f6g7h8...

This may overwrite changes made after the integration.
Continue with rollback? [y/N]
```

In autonomous mode, `--force` is required to override divergence.

## Related

- `/plan-and-analyze` - Creates PRD (auto-triggers Flatline if enabled)
- `/architect` - Creates SDD (auto-triggers Flatline if enabled)
- `/sprint-plan` - Creates sprint plan (auto-triggers Flatline if enabled)
- `/gpt-review` - Single-model GPT review (simpler alternative)
- `/run sprint-plan` - Autonomous sprint execution (uses autonomous Flatline)
