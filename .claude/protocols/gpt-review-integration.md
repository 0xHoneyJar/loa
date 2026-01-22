# GPT 5.2 Cross-Model Review Integration Protocol

## Overview

GPT 5.2 provides cross-model review to catch issues Claude might miss. The integration follows KISS/Unix principles:

1. **Standalone command**: `/gpt-review` handles everything
2. **Script-level config check**: The bash script checks if enabled and returns `SKIPPED` if disabled
3. **Skills just call the command**: No embedded logic, just "run `/gpt-review <type>`"

## Architecture

```
Skill invokes command
         ↓
/gpt-review <type>
         ↓
gpt-review-api.sh
         ↓
┌─────────────────┐
│ Config check    │ → SKIPPED (if disabled)
└────────┬────────┘
         ↓ (enabled)
┌─────────────────┐
│ Load prompt     │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Call GPT 5.2    │
│ API             │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Return verdict  │
└─────────────────┘
```

## Configuration

In `.loa.config.yaml`:

```yaml
gpt_review:
  enabled: true              # Master toggle
  timeout_seconds: 300       # API timeout
  max_iterations: 3          # Auto-approve after this
  models:
    documents: "gpt-5.2"     # PRD, SDD, Sprint reviews
    code: "gpt-5.2-codex"    # Code reviews
  phases:
    prd: true
    sdd: true
    sprint: true
    implementation: true
```

## Environment

- `OPENAI_API_KEY` - Required (can be in `.env` file)

## Verdicts

| Verdict | Code Review | Document Review | Script Behavior |
|---------|-------------|-----------------|-----------------|
| `SKIPPED` | Review disabled | Review disabled | Returns immediately, exit 0 |
| `APPROVED` | No issues | No blocking issues | Returns result, exit 0 |
| `CHANGES_REQUIRED` | Has bugs to fix | Has failure risks | Returns result, exit 0 |
| `DECISION_NEEDED` | N/A | Design choice for user | Returns result, exit 0 |

### Verdict Handling by Type

**Code Reviews:**
- `SKIPPED` → Continue normally
- `APPROVED` → Continue normally
- `CHANGES_REQUIRED` → Claude fixes automatically, re-runs review
- No `DECISION_NEEDED` - bugs are fixed, not discussed

**Document Reviews (PRD, SDD, Sprint):**
- `SKIPPED` → Continue normally
- `APPROVED` → Write final document
- `CHANGES_REQUIRED` → Claude fixes, re-runs review
- `DECISION_NEEDED` → Ask user the question, incorporate answer, re-run

## Review Loop

```
Iteration 1: gpt-review-api.sh <type> <file>
    → Save response to /tmp/gpt-review-findings-1.json
    ↓
CHANGES_REQUIRED? → Fix issues
    ↓
Iteration 2: gpt-review-api.sh <type> <file> --iteration 2 --previous /tmp/gpt-review-findings-1.json
    → Save response to /tmp/gpt-review-findings-2.json
    ↓
CHANGES_REQUIRED? → Fix issues
    ↓
Iteration 3: gpt-review-api.sh <type> <file> --iteration 3 --previous /tmp/gpt-review-findings-2.json
    ↓
APPROVED (or auto-approve at max_iterations)
```

### Iteration Parameters (CRITICAL)

**For re-reviews (iteration 2+), ALWAYS pass these parameters:**

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `--iteration N` | Tells GPT which iteration this is | `--iteration 2` |
| `--previous <file>` | Previous findings for context | `--previous /tmp/gpt-review-findings-1.json` |

**Why this matters:**
- `{{ITERATION}}` is substituted into the re-review prompt
- `{{PREVIOUS_FINDINGS}}` gives GPT the full context of what it found before
- Without these, GPT re-reviews from scratch and may find the same issues again

### Tracking Iterations

Skills must track iteration number and save findings between reviews:

```bash
# First review
response=$(.claude/scripts/gpt-review-api.sh "$type" "$file")
echo "$response" > /tmp/gpt-review-findings-1.json
iteration=1

# After fixing, re-review
iteration=$((iteration + 1))
response=$(.claude/scripts/gpt-review-api.sh "$type" "$file" \
  --iteration "$iteration" \
  --previous "/tmp/gpt-review-findings-$((iteration - 1)).json")
echo "$response" > "/tmp/gpt-review-findings-${iteration}.json"
```

The re-review prompt focuses on:
1. Were previous issues fixed?
2. Did fixes introduce new problems?
3. Converge toward approval

## Files

| File | Purpose |
|------|---------|
| `.claude/scripts/gpt-review-api.sh` | API interaction, config check |
| `.claude/commands/gpt-review.md` | Command definition |
| `.claude/prompts/gpt-review/base/code-review.md` | Code review prompt |
| `.claude/prompts/gpt-review/base/prd-review.md` | PRD review prompt |
| `.claude/prompts/gpt-review/base/sdd-review.md` | SDD review prompt |
| `.claude/prompts/gpt-review/base/sprint-review.md` | Sprint review prompt |
| `.claude/prompts/gpt-review/base/re-review.md` | Re-review prompt |
| `.claude/schemas/gpt-review-response.schema.json` | Response validation |

## Skill Integration

Each skill includes a `<gpt_review>` section with iteration tracking:

```markdown
<gpt_review>
## GPT Review Step

After [completing work], run GPT cross-model review:

\`\`\`bash
# First review (iteration 1)
response=$(.claude/scripts/gpt-review-api.sh <type> <file>)
echo "$response" > /tmp/gpt-review-findings-1.json
verdict=$(echo "$response" | jq -r '.verdict')
iteration=1
\`\`\`

**Handle the verdict:**
- \`SKIPPED\` → Continue (review is disabled)
- \`APPROVED\` → Continue with next step
- \`CHANGES_REQUIRED\` → Fix issues, then re-run with iteration tracking

**CRITICAL - Iteration Tracking for Re-Reviews:**

\`\`\`bash
# After fixing issues, run iteration 2+
iteration=$((iteration + 1))
response=$(.claude/scripts/gpt-review-api.sh <type> <file> \\
  --iteration "$iteration" \\
  --previous "/tmp/gpt-review-findings-$((iteration - 1)).json")
echo "$response" > "/tmp/gpt-review-findings-\${iteration}.json"
verdict=$(echo "$response" | jq -r '.verdict')
\`\`\`
</gpt_review>
```

Skills don't need to know about:
- Config checking (script handles it)
- API calls (script handles it)
- Retry logic (script handles it)
- Prompt loading (script handles it)

**But skills MUST track:**
- Iteration number
- Previous findings location
- Passing both `--iteration` and `--previous` on re-reviews

## API Details

### GPT 5.2 (Documents)
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Model: `gpt-5.2`
- Format: `messages` array with system + user roles

### GPT 5.2 Codex (Code)
- Endpoint: `https://api.openai.com/v1/responses`
- Model: `gpt-5.2-codex`
- Format: `input` field (not messages)
- Supports: `reasoning: {effort: "medium"}`

## Error Handling

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success (includes SKIPPED) | Continue |
| 1 | API error | Retry or skip |
| 2 | Invalid input | Check arguments |
| 3 | Timeout | Retry with longer timeout |
| 4 | Missing API key | Set OPENAI_API_KEY |
| 5 | Invalid response | Retry |

## Troubleshooting

### "GPT review disabled"
- Check `gpt_review.enabled` in `.loa.config.yaml`
- Check phase-specific toggle (e.g., `gpt_review.phases.prd`)

### "Missing API key"
- Set `OPENAI_API_KEY` environment variable
- Or add to `.env` file in project root

### "API timeout"
- Increase `gpt_review.timeout_seconds` in config
- Or set `GPT_REVIEW_TIMEOUT` environment variable

### "Invalid response"
- GPT returned non-JSON or missing verdict
- Check API response in logs
- May need to retry

### "Rate limited"
- Script retries with exponential backoff
- If persistent, reduce review frequency

## Design Decisions

1. **Script-level config check** - Fastest bailout, single source of truth
2. **SKIPPED verdict** - Valid response, not an error, exit 0
3. **No DECISION_NEEDED for code** - Bugs should be fixed, not discussed
4. **DECISION_NEEDED for docs** - Design choices benefit from user input
5. **Auto-approve at max_iterations** - Prevent infinite loops
6. **Skills don't check config** - They just call the command
