# GPT Review Prompts

System prompts for GPT 5.2 cross-model review.

## Directory Structure

```
.claude/prompts/gpt-review/
├── README.md           # This file
└── base/               # Base prompts for each review type
    ├── code-review.md  # Code review (strict, no DECISION_NEEDED)
    ├── prd-review.md   # PRD review (with DECISION_NEEDED)
    ├── sdd-review.md   # SDD review (with DECISION_NEEDED)
    ├── sprint-review.md # Sprint review (with DECISION_NEEDED)
    └── re-review.md    # Follow-up review for iterations 2+
```

## Prompt System

### Base Prompts

Each review type has a base prompt that defines:
- GPT's role and focus
- What to flag as issues
- What to ignore
- Response format (JSON)
- Verdict rules

### Augmentation

Claude can add project-specific context to prompts:

```markdown
## Project-Specific Context (Added by Claude)

This is a DeFi trading bot project. Pay special attention to:
- Order fill calculations - must use actual order book data
- Price feeds - must come from oracles, not hardcoded
```

The API script appends augmentation content to the base prompt.

## Verdicts

### Code Reviews

| Verdict | Meaning |
|---------|---------|
| APPROVED | No bugs or security issues |
| CHANGES_REQUIRED | Has issues that need fixing |

**DECISION_NEEDED is NOT available** for code reviews. Bugs should be fixed automatically by Claude and GPT working together.

### Document Reviews (PRD, SDD, Sprint)

| Verdict | Meaning |
|---------|---------|
| APPROVED | Document would lead to success |
| CHANGES_REQUIRED | Has issues that would cause failure |
| DECISION_NEEDED | Design choice where user input is valuable |

**DECISION_NEEDED** is available for document reviews to surface design choices the user should weigh in on.

## Response Format

### Code Review Response

```json
{
  "verdict": "APPROVED" | "CHANGES_REQUIRED",
  "summary": "One sentence",
  "issues": [
    {
      "severity": "critical" | "major",
      "file": "path/to/file.ts",
      "line": 42,
      "description": "What's wrong",
      "current_code": "...",
      "fixed_code": "...",
      "explanation": "Why"
    }
  ],
  "fabrication_check": {
    "passed": true | false,
    "concerns": []
  }
}
```

### Document Review Response

```json
{
  "verdict": "APPROVED" | "CHANGES_REQUIRED" | "DECISION_NEEDED",
  "summary": "One sentence",
  "blocking_issues": [
    {
      "location": "Section",
      "issue": "What's wrong",
      "why_blocking": "Why it matters",
      "fix": "How to fix"
    }
  ],
  "question": "Only for DECISION_NEEDED - question for user"
}
```

### Re-review Response

```json
{
  "verdict": "APPROVED" | "CHANGES_REQUIRED",
  "summary": "One sentence",
  "previous_issues_status": [
    {
      "original_issue": "Description",
      "status": "fixed" | "rejected_with_valid_reason" | "not_fixed",
      "notes": "Details"
    }
  ],
  "new_blocking_concerns": []
}
```

## Key Principles

1. **Focus on failure risks** - Not style, formatting, or "could be better"
2. **Provide fixes** - For code, always include actual code fixes
3. **Converge** - On re-reviews, don't find new nitpicks
4. **Respect Claude's context** - Claude knows more about the project
5. **Default to APPROVED** - Unless something would actually cause failure

## Customization

To customize prompts:
1. Copy base prompt to `.claude/overrides/prompts/gpt-review/base/`
2. Modify as needed
3. Overrides take precedence over base prompts

## Related Files

- `.claude/scripts/gpt-review-api.sh` - API interaction script
- `.claude/schemas/gpt-review-response.schema.json` - Response validation
- `.claude/commands/gpt-review.md` - Command definition
