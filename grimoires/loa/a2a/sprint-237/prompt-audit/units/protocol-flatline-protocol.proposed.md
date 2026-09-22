# Flatline Protocol

> Adversarial review of planning documents (PRD, SDD, Sprint Plans): Claude Opus 4.7 and GPT-5.2 each review and critique the other's suggestions, and the resulting consensus filter surfaces high-value improvements while filtering noise.

## Architecture

The pipeline runs in four phases:

- **Phase 0 - Knowledge Retrieval** (two-tier): Tier 1, local learnings (`.claude/loa/learnings/` + `grimoires/`); Tier 2, NotebookLM (optional, browser automation).
- **Phase 1 - Independent Reviews** (4 parallel calls): GPT-5.2 and Opus each produce an improvements list (Review) and a concerns list (Skeptic).
- **Phase 2 - Cross-Scoring** (2 parallel calls): GPT scores Opus's improvements and Opus scores GPT's improvements, 0-1000.
- **Phase 3 - Consensus Extraction**: classifies each item as HIGH_CONSENSUS (auto-integrate), DISPUTED (present to user), LOW_VALUE (discard), or BLOCKERS (must address) - thresholds are the `thresholds:` block under Configuration below.

## Workflow

### 1. Prerequisites

**Required**: OpenAI API key (for GPT-5.2), Anthropic API key (for Claude Opus).
**Optional**: NotebookLM (Tier 2 knowledge; see below).

### 2. Configuration

Add to `.loa.config.yaml`:

```yaml
flatline_protocol:
  enabled: true

  models:
    primary: opus              # Claude Opus 4.7 (model alias)
    secondary: gpt-5.3-codex  # OpenAI GPT-5.3-codex

  max_iterations: 5            # Safety cap on Flatline loops

  # Consensus thresholds (0-1000 scale)
  thresholds:
    high_consensus: 700     # 2-of-3 >700 = auto-integrate
    dispute_delta: 300      # Delta >300 = disputed
    low_value: 400          # All <400 = discard
    blocker: 700            # Any skeptic concern >700 = blocker

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

### 4. Create the Planning Document

```bash
/plan-and-analyze
# Creates grimoires/loa/prd.md
```

### 5. Run Flatline Review

```bash
/flatline-review grimoires/loa/prd.md
# or: .claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```

Output falls into the four categories described under Architecture above; LOW_VALUE items are discarded but logged for transparency.

### 6. Continue the Planning Cycle

```bash
/architect              # Review SDD with Flatline
/sprint-plan            # Review Sprint Plan with Flatline
```

## NotebookLM Setup (Optional)

NotebookLM provides Tier 2 knowledge retrieval - curated domain expertise from your own notebooks. Requires Python 3.8+, a Google account, and (recommended) a notebook with sources.

### Installation

```bash
pip install --user patchright                 # browser automation
patchright install chromium                    # browser binaries
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

`--setup-auth` opens a browser to notebooklm.google.com for a one-time Google sign-in; the session is saved to `~/.claude/notebooklm-auth/`.

Create a notebook at [notebooklm.google.com](https://notebooklm.google.com), add sources (domain docs, specs, best-practice guides, architecture references), and copy the notebook ID from the URL (`notebooklm.google.com/notebook/YOUR_ID`) into `flatline_protocol.knowledge.notebooklm.notebook_id` (see Configuration above).

### Test NotebookLM

```bash
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --dry-run --domain "your domain" --phase prd --json          # no browser

python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --domain "your domain" --phase prd --notebook "YOUR_NOTEBOOK_ID" --json   # requires auth + notebook
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

Models: opus, gpt-5.3-codex, gemini-2.5-pro, gemini-3-pro, gpt-5.2
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

## Troubleshooting

### "No items to score in either file"

**Cause**: Model responses couldn't be parsed (often markdown-wrapped JSON)

**Fix**: The orchestrator handles markdown-wrapped JSON automatically. If the issue persists, check:
```bash
.claude/scripts/model-adapter.sh --model opus --mode review \
  --input grimoires/loa/prd.md --phase prd --json
```

### "API key not configured"

**Cause**: Missing environment variables

**Fix**: re-export the keys from Workflow -> Set API Keys above.

### NotebookLM "Could not find query input"

**Cause**: NotebookLM requires a specific notebook with sources

**Fix**:
1. Create a notebook at notebooklm.google.com
2. Add sources to the notebook
3. Configure `notebook_id` in `.loa.config.yaml`

### NotebookLM "auth_expired"

**Cause**: Google session expired

**Fix**: re-run `--setup-auth` from NotebookLM Setup -> Installation above.

## Security Considerations

1. **NotebookLM Auth**: Session stored with 0700 permissions in `~/.claude/notebooklm-auth/`
2. **Document Privacy**: Planning documents are sent to external APIs (OpenAI, Anthropic)

## Related Documentation

[INSTALLATION.md](../../INSTALLATION.md#notebooklm-optional) (NotebookLM setup); [CLAUDE.loa.md](../../.claude/loa/CLAUDE.loa.md#two-tier-learnings-architecture) (knowledge architecture).

## Provenance

Removed from `models.primary`'s example comment: cycle-082.
