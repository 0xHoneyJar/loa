# /gpt-review Command

Cross-model review using GPT 5.2 to catch issues Claude might miss.

## Usage

```bash
/gpt-review <type> [file]
/gpt-review toggle
```

**Types:**
- `code` - Review code changes (git diff or specified files)
- `prd` - Review Product Requirements Document
- `sdd` - Review Software Design Document
- `sprint` - Review Sprint Plan
- `toggle` - Toggle GPT review on/off

**Examples:**
```bash
/gpt-review toggle                  # Toggle enabled/disabled
/gpt-review code                    # Review git diff
/gpt-review code src/auth.ts        # Review specific file
/gpt-review prd                     # Review grimoires/loa/prd.md
/gpt-review sdd grimoires/loa/sdd.md  # Review specific SDD
```

## Toggle Command

The `toggle` subcommand flips the `gpt_review.enabled` setting in `.loa.config.yaml`.

**Just run the script:**
```bash
.claude/scripts/gpt-review-toggle.sh
```

The script handles everything automatically:
- Adds `gpt_review.enabled` to config if missing
- Flips the value: `true` → `false` or `false` → `true`
- Creates/removes the context file
- Reports the new state

**After toggling:** Restart Claude session for the context file changes to take effect.

## How It Works

1. Run the script: `.claude/scripts/gpt-review-api.sh <type> <file>`
2. Script checks config - if disabled, returns `{"verdict": "SKIPPED", ...}`
3. If enabled, script calls GPT 5.2 API and returns review
4. Handle the verdict:
   - **SKIPPED** → GPT review is disabled, continue normally
   - **APPROVED** → Review passed, continue
   - **CHANGES_REQUIRED** → Fix issues and re-run review
   - **DECISION_NEEDED** → Ask user the question, then continue

## Execution Steps

### Step 1: Prepare Content

**For code reviews:**
```bash
# Get git diff or file content
if [[ -n "$file" ]]; then
  content_file="$file"
else
  git diff HEAD > /tmp/gpt-review-content.txt
  content_file="/tmp/gpt-review-content.txt"
fi
```

**For document reviews:**
```bash
# Default paths
case "$type" in
  prd) content_file="${file:-grimoires/loa/prd.md}" ;;
  sdd) content_file="${file:-grimoires/loa/sdd.md}" ;;
  sprint) content_file="${file:-grimoires/loa/sprint.md}" ;;
esac
```

### Step 2: Run Review Script (First Iteration)

```bash
# First review - no iteration params needed (defaults to iteration 1)
response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file")
verdict=$(echo "$response" | jq -r '.verdict')

# IMPORTANT: Save findings for potential re-review
echo "$response" > /tmp/gpt-review-findings-1.json
iteration=1
```

### Step 3: Handle Verdict

```bash
case "$verdict" in
  SKIPPED)
    echo "GPT review disabled - continuing"
    # Done, no action needed
    ;;

  APPROVED)
    echo "GPT review passed"
    # Done, continue with next step
    ;;

  CHANGES_REQUIRED)
    # Fix the issues, then go to Step 4 (Re-Review Loop)
    ;;

  DECISION_NEEDED)
    # Extract question and ask user
    question=$(echo "$response" | jq -r '.question')
    # Use AskUserQuestion tool to get user input
    # Continue with user's answer
    ;;
esac
```

### Step 4: Re-Review Loop (CRITICAL for CHANGES_REQUIRED)

When GPT returns `CHANGES_REQUIRED`, you MUST:

1. Fix the issues GPT identified
2. Run a re-review with **iteration number** and **previous findings**

```bash
# After fixing issues from iteration N, run iteration N+1:
iteration=$((iteration + 1))
previous_findings="/tmp/gpt-review-findings-$((iteration - 1)).json"

response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file" \
  --iteration "$iteration" \
  --previous "$previous_findings")

verdict=$(echo "$response" | jq -r '.verdict')

# Save this iteration's findings for potential next iteration
echo "$response" > "/tmp/gpt-review-findings-${iteration}.json"

# Loop until APPROVED or max iterations reached
```

**MANDATORY**: Always pass both `--iteration` and `--previous` on iterations 2+. The re-review prompt uses these to:
- Show GPT what iteration this is (`{{ITERATION}}`)
- Include previous findings so GPT can verify fixes (`{{PREVIOUS_FINDINGS}}`)

## Review Loop Diagram

```
Iteration 1: .claude/scripts/gpt-review-api.sh code file.ts
  → Save response to /tmp/gpt-review-findings-1.json
  ↓ CHANGES_REQUIRED
Fix issues identified in response
  ↓
Iteration 2: .claude/scripts/gpt-review-api.sh code file.ts \
               --iteration 2 --previous /tmp/gpt-review-findings-1.json
  → Save response to /tmp/gpt-review-findings-2.json
  ↓ CHANGES_REQUIRED
Fix remaining issues
  ↓
Iteration 3: .claude/scripts/gpt-review-api.sh code file.ts \
               --iteration 3 --previous /tmp/gpt-review-findings-2.json
  → Save response to /tmp/gpt-review-findings-3.json
  ↓ APPROVED (or auto-approve at max_iterations)
Done
```

## Complete Example

```bash
# === ITERATION 1 ===
content_file="src/auth.ts"
response=$(.claude/scripts/gpt-review-api.sh code "$content_file")
echo "$response" > /tmp/gpt-review-findings-1.json
verdict=$(echo "$response" | jq -r '.verdict')
iteration=1

# If CHANGES_REQUIRED, fix issues then continue...

# === ITERATION 2 ===
if [[ "$verdict" == "CHANGES_REQUIRED" ]]; then
  # ... fix the issues ...
  iteration=2
  response=$(.claude/scripts/gpt-review-api.sh code "$content_file" \
    --iteration 2 \
    --previous /tmp/gpt-review-findings-1.json)
  echo "$response" > /tmp/gpt-review-findings-2.json
  verdict=$(echo "$response" | jq -r '.verdict')
fi

# === ITERATION 3 ===
if [[ "$verdict" == "CHANGES_REQUIRED" ]]; then
  # ... fix remaining issues ...
  iteration=3
  response=$(.claude/scripts/gpt-review-api.sh code "$content_file" \
    --iteration 3 \
    --previous /tmp/gpt-review-findings-2.json)
  echo "$response" > /tmp/gpt-review-findings-3.json
  verdict=$(echo "$response" | jq -r '.verdict')
fi

# After max_iterations, script auto-approves
```

## Configuration

The script checks `.loa.config.yaml`:

```yaml
gpt_review:
  enabled: true              # Master toggle
  timeout_seconds: 300       # API timeout
  max_iterations: 3          # Auto-approve after this many
  models:
    documents: "gpt-5.2"     # For PRD, SDD, Sprint
    code: "gpt-5.2-codex"    # For code reviews
  phases:
    prd: true                # Enable/disable per type
    sdd: true
    sprint: true
    implementation: true
```

## Environment

- `OPENAI_API_KEY` - Required (can also be in `.env` file)

## Verdicts

| Verdict | Code Review | Document Review |
|---------|-------------|-----------------|
| SKIPPED | Review disabled | Review disabled |
| APPROVED | No bugs found | No blocking issues |
| CHANGES_REQUIRED | Has bugs to fix | Has issues that would cause failure |
| DECISION_NEEDED | N/A (not used) | Design choice for user to decide |

## Output

The command outputs the review result:

```
GPT Review: APPROVED
Summary: Code looks good, no issues found.
```

Or for issues:

```
GPT Review: CHANGES_REQUIRED
Summary: Found 2 issues that need fixing.

Issues:
1. [critical] src/auth.ts:42 - SQL injection vulnerability
2. [major] src/db.ts:15 - Missing null check
```

## Error Handling

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success (includes SKIPPED) | Continue |
| 1 | API error | Retry or skip |
| 2 | Invalid input | Check arguments |
| 3 | Timeout | Retry with longer timeout |
| 4 | Missing API key | Set OPENAI_API_KEY |
| 5 | Invalid response | Retry |
