# Prompt Analyzer

Reference documentation for component detection and quality scoring.

## Component Detection Patterns

### Persona Detection

Patterns that indicate a persona specification:

```regex
^(act as|you are|as a|pretend|imagine you're|behave like|take the role of)
```

**Examples**:
- "Act as a security expert" → ✅ Persona detected
- "You are a senior engineer" → ✅ Persona detected
- "Review the code" → ❌ No persona

**Weight**: 2 points

### Task Detection

Action verbs that indicate a clear task:

```regex
\b(create|review|analyze|fix|summarize|write|debug|refactor|optimize|draft|investigate|compare|explain|implement|design|test|validate|check|audit|improve|generate|build|develop|describe)\b
```

**Examples**:
- "Review the authentication code" → ✅ Task detected (review)
- "The auth code has issues" → ❌ No task verb
- "Fix the bug in line 42" → ✅ Task detected (fix)

**Weight**: 3 points (required for valid prompt)

### Context Detection

Patterns indicating relevant context:

```regex
# File references
\.(ts|js|py|md|yaml|json|go|rs|java|cpp|c|h|rb|php)\b

# @mentions
@\w+

# Context phrases
\b(given that|based on|from the|in the|using the|with the|according to|as shown in)\b

# Specific references
\b(file|function|class|method|module|component|service|api|endpoint)\b
```

**Examples**:
- "Review auth.ts" → ✅ Context detected (file reference)
- "@sarah mentioned issues" → ✅ Context detected (@mention)
- "Based on the user requirements" → ✅ Context detected (phrase)
- "Review the code" → ❌ No specific context

**Weight**: 3 points

### Format Detection

Patterns indicating output format:

```regex
\b(as bullets|in JSON|formatted as|limit to|with examples|step by step|list|table|markdown|numbered|concise|detailed|brief|comprehensive)\b
```

**Examples**:
- "List the issues as bullets" → ✅ Format detected
- "Return the results in JSON" → ✅ Format detected
- "Review the code" → ❌ No format specified

**Weight**: 2 points

## Quality Score Calculation

```python
def calculate_quality_score(components):
    score = 0

    if components.task:
        score += 3  # Task is most important
    else:
        return 0  # No task = invalid prompt

    if components.context:
        score += 3  # Context grounds the task

    if components.format:
        score += 2  # Format clarifies expectations

    if components.persona:
        score += 2  # Persona sets expertise level

    return score  # Range: 0-10
```

### Score Interpretation

| Score | Quality | Description |
|-------|---------|-------------|
| 0-1 | Invalid | Missing task verb |
| 2-3 | Minimal | Has task only |
| 4-5 | Acceptable | Has task + some context |
| 6-7 | Good | Has task + context + format |
| 8-10 | Excellent | All components present |

## Gap Analysis

For each missing component, suggest specific improvements:

### Missing Persona

**Suggestion**: "Consider specifying who the AI should act as (e.g., 'As a security expert...', 'You are a senior engineer...')"

**Benefit**: Sets expertise level and perspective for the response.

### Missing Context

**Suggestion**: "Add relevant files, constraints, or background (e.g., specific file names, project constraints, related requirements)"

**Benefit**: Grounds the task in specific details, reducing ambiguity.

### Missing Format

**Suggestion**: "Specify desired output structure (e.g., 'as a bulleted list', 'in JSON format', 'step by step')"

**Benefit**: Clarifies expectations for the response format.

## Enhancement Priority

When enhancing prompts, apply improvements in this order:

1. **Persona** (prepend) - Sets the context for expertise
2. **Task** (preserve) - Original task verb is always kept
3. **Context** (merge) - Add constraints without overriding
4. **Format** (append) - Add output specification at end
