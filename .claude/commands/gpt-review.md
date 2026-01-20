# /gpt-review Command

Cross-model review using GPT 5.2 to catch issues Claude might miss.

## Usage

```bash
/gpt-review <type> [file]
```

**Types:**
- `code` - Review code changes (git diff or specified files)
- `prd` - Review Product Requirements Document
- `sdd` - Review Software Design Document
- `sprint` - Review Sprint Plan

**Examples:**
```bash
/gpt-review code                    # Review git diff
/gpt-review code src/auth.ts        # Review specific file
/gpt-review prd                     # Review grimoires/loa/prd.md
/gpt-review sdd grimoires/loa/sdd.md  # Review specific SDD
```

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

### Step 2: Run Review Script

```bash
response=$(.claude/scripts/gpt-review-api.sh "$type" "$content_file")
verdict=$(echo "$response" | jq -r '.verdict')
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
    # For code: Claude fixes issues automatically
    # For docs: Claude revises document automatically
    # Then re-run review with --iteration 2
    ;;

  DECISION_NEEDED)
    # Extract question and ask user
    question=$(echo "$response" | jq -r '.question')
    # Use AskUserQuestion tool to get user input
    # Continue with user's answer
    ;;
esac
```

## Review Loop

For CHANGES_REQUIRED, the loop continues until APPROVED or max iterations:

```
Iteration 1: First review
  ↓ CHANGES_REQUIRED
Fix issues
  ↓
Iteration 2: Re-review with --previous findings.json
  ↓ CHANGES_REQUIRED
Fix remaining issues
  ↓
Iteration 3: Re-review
  ↓ APPROVED (or auto-approve at max_iterations)
Done
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
