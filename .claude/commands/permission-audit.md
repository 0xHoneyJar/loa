---
description: View and analyze HITL permission requests to optimize settings.json
output: Permission audit report with suggestions
---

# Permission Audit Command

You are analyzing permission requests that required human-in-the-loop (HITL) approval.

## Your Task

Run the permission audit script with the requested action and present the results clearly.

## Available Actions

1. **View Log** (default): Show recent permission requests
2. **Analyze**: Show patterns and frequency of permission requests
3. **Suggest**: Recommend permissions to add to settings.json based on history

## Execution

Based on the user's request, run ONE of these commands:

```bash
# View recent permission requests
.claude/scripts/permission-audit.sh view

# Analyze patterns
.claude/scripts/permission-audit.sh analyze

# Get suggestions for settings.json
.claude/scripts/permission-audit.sh suggest
```

## Output Format

After running the script, provide:

1. **Summary**: Key findings from the output
2. **Recommendations**: If using `suggest`, format the recommended additions as JSON that can be copy-pasted into settings.json
3. **Next Steps**: How to apply the changes

## Example Response

If suggesting permissions:

```markdown
## Permission Audit Results

Based on 47 logged permission requests, here are suggested additions:

### High-Value Additions (requested 5+ times)
- `Bash(flyctl:*)` - 12 requests
- `Bash(pm2:*)` - 8 requests

### To add these, update `.claude/settings.json`:

```json
"permissions": {
  "allow": [
    // ... existing permissions ...
    "Bash(flyctl:*)",
    "Bash(pm2:*)"
  ]
}
```

After adding, these commands will auto-approve in future sessions.
```
