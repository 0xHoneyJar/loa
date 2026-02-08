# GPT Cross-Model Review Integration Protocol

## Overview

GPT 5.2 provides cross-model review to catch issues Claude might miss. The integration follows KISS/Unix principles:

1. **PostToolUse hook**: Fires after every Edit/Write, tells Claude which phases are enabled/disabled
2. **Standalone command**: `/gpt-review` handles the actual review
3. **Script-level config check**: The bash script validates and returns `SKIPPED` if disabled

## Architecture

```
Claude edits file
         ↓
PostToolUse hook fires
         ↓
┌─────────────────────────────────────┐
│ gpt-review-hook.sh                  │
│ - Reads phase toggles from config   │
│ - Outputs: "ENABLED: X. DISABLED: Y"│
└────────────────┬────────────────────┘
         ↓
Claude sees phase status
         ↓
┌─────────────────────────────────────┐
│ If file relates to DISABLED phase:  │
│ → Skip (no context files needed)    │
│                                     │
│ If file relates to ENABLED phase:   │
│ → Prepare context files             │
│ → Invoke /gpt-review                │
└────────────────┬────────────────────┘
         ↓
/gpt-review <type>
         ↓
gpt-review-api.sh
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

## Hook Behavior

The PostToolUse hook (`gpt-review-hook.sh`) reads all phase toggles and outputs a message like:

```
ENABLED: prd, sdd, code. DISABLED: sprint.
If file relates to DISABLED type, skip review entirely (no context files needed).
```

This prevents Claude from wasting tokens preparing expertise/context files for disabled review types.

## Configuration

In `.loa.config.yaml`:

```yaml
gpt_review:
  enabled: true              # Master toggle
  timeout_seconds: 300       # API timeout
  max_iterations: 3          # Auto-approve after this
  models:
    documents: "gpt-5.2"     # PRD, SDD, Sprint reviews
    code: "gpt-5.2-codex"    # Code reviews (gpt-5.3-codex when API available)
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
output_dir=grimoires/loa/a2a/gpt-review

Iteration 1: gpt-review-api.sh <type> <file> --output $output_dir/<type>-findings-1.json
    → Findings persisted to grimoires/loa/a2a/gpt-review/
    ↓
CHANGES_REQUIRED? → Fix issues
    ↓
Iteration 2: gpt-review-api.sh <type> <file> --iteration 2 --previous $output_dir/<type>-findings-1.json --output $output_dir/<type>-findings-2.json
    ↓
CHANGES_REQUIRED? → Fix issues
    ↓
Iteration 3: gpt-review-api.sh <type> <file> --iteration 3 --previous $output_dir/<type>-findings-2.json --output $output_dir/<type>-findings-3.json
    ↓
APPROVED (or auto-approve at max_iterations)
```

### Iteration Parameters (CRITICAL)

**For re-reviews (iteration 2+), ALWAYS pass these parameters:**

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `--iteration N` | Tells GPT which iteration this is | `--iteration 2` |
| `--previous <file>` | Previous findings for context | `--previous grimoires/loa/a2a/gpt-review/code-findings-1.json` |

**Why this matters:**
- `{{ITERATION}}` is substituted into the re-review prompt
- `{{PREVIOUS_FINDINGS}}` gives GPT the full context of what it found before
- Without these, GPT re-reviews from scratch and may find the same issues again

### Tracking Iterations

Skills must track iteration number and save findings between reviews:

```bash
output_dir="grimoires/loa/a2a/gpt-review"

# First review
response=$(.claude/scripts/gpt-review-api.sh "$type" "$file" \
  --output "${output_dir}/${type}-findings-1.json")
iteration=1

# After fixing, re-review
iteration=$((iteration + 1))
response=$(.claude/scripts/gpt-review-api.sh "$type" "$file" \
  --iteration "$iteration" \
  --previous "${output_dir}/${type}-findings-$((iteration - 1)).json" \
  --output "${output_dir}/${type}-findings-${iteration}.json")
```

The re-review prompt focuses on:
1. Were previous issues fixed?
2. Did fixes introduce new problems?
3. Converge toward approval

## Output Storage

Findings are persisted to `grimoires/loa/a2a/gpt-review/` using the `--output` flag:

```
grimoires/loa/a2a/gpt-review/
├── code-findings-1.json       # First code review
├── code-findings-2.json       # Re-review after fixes
├── prd-findings-1.json        # PRD review
├── sdd-findings-1.json        # SDD review
└── sprint-findings-1.json     # Sprint plan review
```

This ensures findings survive across sessions and are available to `/implement` for feedback.

## Files

| File | Purpose |
|------|---------|
| `.claude/scripts/gpt-review-hook.sh` | PostToolUse hook - phase-aware checkpoint |
| `.claude/scripts/gpt-review-api.sh` | API interaction, config check |
| `.claude/scripts/gpt-review-toggle.sh` | Toggle enabled/disabled |
| `.claude/scripts/inject-gpt-review-gates.sh` | Manage context file based on config |
| `.claude/commands/gpt-review.md` | Command definition |
| `.claude/commands/toggle-gpt-review.md` | Toggle command |
| `grimoires/loa/a2a/gpt-review/` | Persistent findings output (created by --output) |
| `.claude/prompts/gpt-review/base/code-review.md` | Code review prompt |
| `.claude/prompts/gpt-review/base/prd-review.md` | PRD review prompt |
| `.claude/prompts/gpt-review/base/sdd-review.md` | SDD review prompt |
| `.claude/prompts/gpt-review/base/sprint-review.md` | Sprint review prompt |
| `.claude/prompts/gpt-review/base/re-review.md` | Re-review prompt |
| `.claude/schemas/gpt-review-response.schema.json` | Response validation |
| `.claude/templates/gpt-review-instructions.md.template` | Context file template |

## Skill Integration

Skills don't need embedded GPT review logic. The PostToolUse hook provides automatic checkpoints:

1. **Hook fires** after each Edit/Write
2. **Hook outputs** which phases are enabled/disabled
3. **Claude decides** whether to invoke `/gpt-review` based on:
   - File type (design doc vs code)
   - Phase enablement (from hook output)
   - Change significance (trivial vs substantial)

**Commands load context file** via `context_files`:
```yaml
context_files:
  - path: ".claude/context/gpt-review-active.md"
    required: false
    purpose: "GPT cross-model review instructions (if enabled)"
```

The context file (created by toggle script when enabled) provides detailed instructions for preparing expertise/context files.

**Skills don't need to know about:**
- Config checking (hook + script handle it)
- API calls (script handles it)
- Retry logic (script handles it)
- Prompt loading (script handles it)
- Phase toggles (hook tells Claude directly)

## API Details

### GPT 5.2 (Documents)
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Model: `gpt-5.2`
- Format: `messages` array with system + user roles

### GPT Codex (Code)
- Endpoint: `https://api.openai.com/v1/responses`
- Model: `gpt-5.2-codex` (default; `gpt-5.3-codex` registered, awaiting API availability)
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
