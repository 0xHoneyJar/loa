# Task Classifier

Reference documentation for task type classification.

## Task Types

| Type | Description | Primary Use Case |
|------|-------------|------------------|
| `debugging` | Fix errors, bugs, issues | Error resolution |
| `code_review` | Review code quality | PR reviews, audits |
| `refactoring` | Improve code structure | Code maintenance |
| `summarization` | Condense information | Documentation, TLDRs |
| `research` | Investigate topics | Analysis, comparison |
| `generation` | Create new content | Writing, coding |
| `general` | Fallback for ambiguous | Default template |

## Classification Rules

### Priority Order

Classification is evaluated in priority order. First match with sufficient confidence wins.

### 1. Debugging (Highest Priority)

**Trigger Patterns**:
```regex
\b(fix|debug|error|broken|not working|fails|failing|crash|exception|bug|issue)\b
```

**Confidence Boosts**:
- +0.3 if error message present (stacktrace, error code)
- +0.2 if mentions line numbers
- +0.1 if mentions "doesn't work" or "won't work"

**Template Focus**: Error context, reproduction steps, root cause analysis

### 2. Code Review

**Trigger Patterns**:
```regex
\b(review|check|audit|inspect|evaluate|assess)\b
```

**Context Requirement**: Must also have code file references

**Confidence Boosts**:
- +0.2 if has file paths (.ts, .js, .py, etc.)
- +0.1 if mentions "PR" or "pull request"
- +0.1 if mentions security, performance, or quality

**Template Focus**: Structured feedback, file:line references, severity

### 3. Refactoring

**Trigger Patterns**:
```regex
\b(refactor|improve|optimize|clean up|restructure|simplify|modernize)\b
```

**Confidence Boosts**:
- +0.2 if mentions patterns (SOLID, DRY, etc.)
- +0.1 if mentions tests or testing
- +0.1 if mentions specific code smells

**Template Focus**: Scope limits, pattern application, test requirements

### 4. Summarization

**Trigger Patterns**:
```regex
\b(summarize|summary|tldr|brief|key points|overview|highlights|recap|condense)\b
```

**Confidence Boosts**:
- +0.2 if has source reference (document, meeting, etc.)
- +0.1 if mentions audience (executives, team, etc.)
- +0.1 if mentions length constraints

**Template Focus**: Length, audience, key points extraction

### 5. Research

**Trigger Patterns**:
```regex
\b(analyze|investigate|compare|research|explore|study|examine|evaluate)\b
```

**Confidence Boosts**:
- +0.2 if multiple subjects to compare
- +0.1 if mentions methodology
- +0.1 if mentions sources or citations

**Template Focus**: Sources, methodology, synthesis

### 6. Generation (Default for creation tasks)

**Trigger Patterns**:
```regex
\b(create|write|draft|generate|make|build|develop|compose|produce)\b
```

**Confidence**: Default level (no boosts needed)

**Template Focus**: Tone, format, constraints

### 7. General (Fallback)

**Trigger**: No other type matches with confidence >= 0.3

**Confidence**: Fixed at 0.5

**Template Focus**: Conservative additions, minimal changes

## Classification Algorithm

```python
def classify_prompt(prompt: str) -> tuple[str, float]:
    """
    Returns (task_type, confidence) tuple.
    """
    prompt_lower = prompt.lower()
    scores = {}

    # Evaluate each task type
    for task_type, config in TASK_TYPES.items():
        # Count pattern matches
        matches = count_matches(prompt_lower, config.patterns)
        base_score = matches / len(config.patterns)

        # Apply confidence boosts
        boost = 0.0
        for boost_condition, boost_value in config.boosts:
            if check_condition(prompt, boost_condition):
                boost += boost_value

        # Cap at 1.0
        scores[task_type] = min(1.0, base_score + boost)

    # Find best match
    best_type = max(scores, key=scores.get)
    confidence = scores[best_type]

    # Fallback to general if confidence too low
    if confidence < 0.3:
        return ("general", 0.5)

    return (best_type, confidence)
```

## Examples

### High Confidence Classifications

| Prompt | Type | Confidence | Reason |
|--------|------|------------|--------|
| "Fix the authentication error in auth.ts line 42" | debugging | 0.9 | "fix", file ref, line number |
| "Review the PR for security issues" | code_review | 0.8 | "review", "PR", "security" |
| "Summarize the meeting notes for executives" | summarization | 0.85 | "summarize", audience |
| "Create a new user registration form" | generation | 0.7 | "create" |

### Ambiguous Classifications (fallback to general)

| Prompt | Type | Confidence | Reason |
|--------|------|------------|--------|
| "Help with this" | general | 0.5 | No task verb |
| "The code doesn't look right" | general | 0.5 | Observation, not task |
| "What do you think?" | general | 0.5 | Question, no action |

## Integration with Templates

After classification, load the corresponding template:

```
resources/templates/{task_type}.yaml
```

The template provides:
- Default persona for that task type
- Recommended format structure
- Task-specific constraints
- Context hints for gathering more info
