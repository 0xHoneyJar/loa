# Flatline Protocol

> Multi-model adversarial review using Claude Opus 4.6 + GPT-5.2 for planning document quality assurance.

## Overview

The Flatline Protocol provides adversarial review of planning documents (PRD, SDD, Sprint Plans) using two frontier models that both **review** and **critique** each other's suggestions. This creates a consensus-based quality filter that surfaces high-value improvements while filtering noise.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Flatline Protocol                            │
├─────────────────────────────────────────────────────────────────────┤
│  Phase 0: Knowledge Retrieval (Two-Tier)                            │
│  ├─ Tier 1: Local learnings (.claude/loa/learnings/ + grimoires/)   │
│  └─ Tier 2: NotebookLM (optional, browser automation)               │
├─────────────────────────────────────────────────────────────────────┤
│  Phase 1: Independent Reviews (4 parallel calls)                    │
│  ├─ GPT-5.2 Review    ──┐                                           │
│  ├─ Opus Review       ──┼── Each produces improvements list         │
│  ├─ GPT-5.2 Skeptic   ──┼── Each produces concerns list             │
│  └─ Opus Skeptic      ──┘                                           │
├─────────────────────────────────────────────────────────────────────┤
│  Phase 2: Cross-Scoring (2 parallel calls)                          │
│  ├─ GPT scores Opus improvements (0-1000)                           │
│  └─ Opus scores GPT improvements (0-1000)                           │
├─────────────────────────────────────────────────────────────────────┤
│  Phase 3: Consensus Extraction                                      │
│  ├─ HIGH_CONSENSUS: Both >700 → Auto-integrate                      │
│  ├─ DISPUTED: Delta >300 → Present to user                          │
│  ├─ LOW_VALUE: Both <400 → Discard                                  │
│  └─ BLOCKERS: Skeptic concerns >700 → Must address                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Prerequisites

**Required**:
- OpenAI API key (for GPT-5.2)
- Anthropic API key (for Claude Opus)

**Optional**:
- NotebookLM setup (for Tier 2 knowledge)

### 2. Configuration

Add to `.loa.config.yaml`:

```yaml
flatline_protocol:
  enabled: true

  models:
    primary: opus           # Claude Opus 4.6
    secondary: gpt-5.2      # OpenAI GPT-5.2

  # Consensus thresholds (0-1000 scale)
  thresholds:
    high_consensus: 700     # Both >700 = auto-integrate
    dispute_delta: 300      # Delta >300 = disputed
    low_value: 400          # Both <400 = discard
    blocker: 700            # Skeptic concern >700 = blocker

  # Knowledge retrieval
  knowledge:
    local:
      enabled: true         # Tier 1: Local learnings
    notebooklm:
      enabled: false        # Tier 2: NotebookLM (optional)
      notebook_id: ""       # Your notebook ID
      timeout_ms: 30000

  # Auto-trigger on planning commands
  auto_trigger:
    enabled: false          # Set true to auto-run on /plan-and-analyze, /architect, /sprint-plan
    phases: [prd, sdd, sprint]
```

### 3. Set API Keys

```bash
# In your shell profile or .env file
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 4. Run Flatline Review

```bash
# Manual invocation
/flatline-review grimoires/loa/prd.md

# Or via CLI
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```

## End-to-End Workflow

### Step 1: Create Planning Document

```bash
/plan-and-analyze
# Creates grimoires/loa/prd.md
```

### Step 2: Run Flatline Review

```bash
/flatline-review grimoires/loa/prd.md
```

**Output**:
- HIGH_CONSENSUS items: Auto-integrated improvements
- DISPUTED items: Presented for your decision
- BLOCKERS: Must address before finalizing
- LOW_VALUE: Discarded (logged for transparency)

### Step 3: Address Results

1. **Review HIGH_CONSENSUS**: These are validated improvements both models agree on
2. **Decide on DISPUTED**: Choose which suggestions to incorporate
3. **Resolve BLOCKERS**: Address critical concerns before proceeding

### Step 4: Continue Workflow

```bash
/architect              # Review SDD with Flatline
/sprint-plan            # Review Sprint Plan with Flatline
```

## NotebookLM Setup (Optional)

NotebookLM provides Tier 2 knowledge retrieval - curated domain expertise from your own notebooks.

### Prerequisites

- Python 3.8+
- Google account (any gmail or workspace)
- NotebookLM notebook with sources (optional but recommended)

### Installation

```bash
# 1. Install patchright (browser automation)
pip install --user patchright

# 2. Install browser binaries
patchright install chromium

# 3. One-time authentication
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

The auth setup:
1. Opens a browser to notebooklm.google.com
2. Sign in with your Google account
3. Navigate to any notebook (confirms access)
4. Close browser when done
5. Session saved to `~/.claude/notebooklm-auth/`

### Create a Knowledge Notebook

1. Go to [notebooklm.google.com](https://notebooklm.google.com)
2. Create a new notebook
3. Add sources:
   - PDFs of domain documentation
   - Technical specifications
   - Best practices guides
   - Architecture references
4. Copy notebook ID from URL: `notebooklm.google.com/notebook/YOUR_ID`

### Configure NotebookLM

```yaml
# .loa.config.yaml
flatline_protocol:
  knowledge:
    notebooklm:
      enabled: true
      notebook_id: "YOUR_NOTEBOOK_ID"  # From URL
      timeout_ms: 30000
```

### Test NotebookLM

```bash
# Dry run (no browser)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --dry-run --domain "your domain" --phase prd --json

# Live query (requires auth + notebook)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --domain "your domain" --phase prd --notebook "YOUR_NOTEBOOK_ID" --json
```

## CLI Reference

### Orchestrator

```bash
.claude/scripts/flatline-orchestrator.sh --doc <path> --phase <type> [options]

Required:
  --doc <path>           Document to review
  --phase <type>         Phase type: prd, sdd, sprint

Options:
  --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
  --dry-run              Validate without executing reviews
  --skip-knowledge       Skip knowledge retrieval
  --skip-consensus       Return raw reviews without consensus
  --timeout <seconds>    Overall timeout (default: 300)
  --budget <cents>       Cost budget in cents (default: 300 = $3.00)
  --json                 Output as JSON
```

### Model Adapter

```bash
.claude/scripts/model-adapter.sh --model <model> --mode <mode> --input <file> [options]

Models: opus, gpt-5.2, gpt-4o, sonnet
Modes: review, skeptic, score
```

### Scoring Engine

```bash
.claude/scripts/scoring-engine.sh --gpt-scores <file> --opus-scores <file> [options]

Options:
  --include-blockers     Include skeptic concerns in analysis
  --skeptic-gpt <file>   GPT skeptic concerns JSON
  --skeptic-opus <file>  Opus skeptic concerns JSON
```

## Output Format

### Consensus Result

```json
{
  "consensus_summary": {
    "high_consensus_count": 4,
    "disputed_count": 1,
    "low_value_count": 2,
    "blocker_count": 3,
    "model_agreement_percent": 85
  },
  "high_consensus": [
    {
      "id": "IMP-001",
      "description": "Add retry logic for API failures",
      "gpt_score": 860,
      "opus_score": 820,
      "delta": 40,
      "average_score": 840,
      "agreement": "HIGH"
    }
  ],
  "disputed": [...],
  "low_value": [...],
  "blockers": [
    {
      "id": "SKP-001",
      "concern": "No fallback when both models unavailable",
      "severity": "CRITICAL",
      "severity_score": 850,
      "recommendation": "Define explicit fallback behavior"
    }
  ],
  "metrics": {
    "total_latency_ms": 70000,
    "cost_cents": 94
  }
}
```

## Scoring Rubric

| Score Range | Classification | Criteria |
|-------------|----------------|----------|
| 800-1000 | Critical | Clear gap, low implementation cost, high ROI |
| 600-799 | Important | Real value, moderate effort, measurable impact |
| 400-599 | Nice-to-have | Some value, higher effort or unclear benefit |
| 0-399 | Skip | Speculative, already addressed, or noise |

## Cost Estimation

| Phase | Calls | Estimated Cost |
|-------|-------|----------------|
| Phase 1 | 4 parallel | ~$0.50-0.80 |
| Phase 2 | 2 parallel | ~$0.10-0.20 |
| **Total** | 6 calls | ~$0.60-1.00 per document |

Costs vary based on document size and model response length.

## Troubleshooting

### "No items to score in either file"

**Cause**: Model responses couldn't be parsed (often markdown-wrapped JSON)

**Fix**: The orchestrator now handles markdown-wrapped JSON automatically. If issue persists, check:
```bash
# Test model adapter directly
.claude/scripts/model-adapter.sh --model opus --mode review \
  --input grimoires/loa/prd.md --phase prd --json
```

### "API key not configured"

**Cause**: Missing environment variables

**Fix**:
```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

### NotebookLM "Could not find query input"

**Cause**: NotebookLM requires a specific notebook with sources

**Fix**:
1. Create a notebook at notebooklm.google.com
2. Add sources to the notebook
3. Configure `notebook_id` in `.loa.config.yaml`

### NotebookLM "auth_expired"

**Cause**: Google session expired

**Fix**:
```bash
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

## Security Considerations

1. **API Keys**: Store in environment variables, never commit to repo
2. **NotebookLM Auth**: Session stored with 0700 permissions in `~/.claude/notebooklm-auth/`
3. **Document Privacy**: Planning documents are sent to external APIs (OpenAI, Anthropic)
4. **Cost Control**: Default budget of $3.00 per review, configurable

## Related Documentation

- [INSTALLATION.md](../../INSTALLATION.md#notebooklm-optional) - NotebookLM setup
- [gpt-review-integration.md](gpt-review-integration.md) - GPT review protocol
- [Two-Tier Learnings](../../.claude/loa/CLAUDE.loa.md#two-tier-learnings-architecture) - Knowledge architecture
