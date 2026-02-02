# Feedback Detector

Reference documentation for detecting failure signals and mapping to refinement actions.

## Feedback Types

The feedback detector identifies four categories of failure signals:

| Type | Description | Detection Method |
|------|-------------|------------------|
| `runtime_error` | Code execution failed | Exception patterns, exit codes |
| `verification_failure` | Tests or validation failed | Test failure patterns |
| `user_rejection` | User explicitly rejected output | Negative language patterns |
| `partial_success` | Output is close but needs adjustment | Partial success patterns |

## Detection Patterns

### Runtime Error

Indicates code execution failed with an error.

**Patterns**:
```regex
\b(error|exception|failed|crash|traceback|stacktrace|segfault|panic)\b
\b(exit code [1-9]|non-zero exit|command failed)\b
\b(undefined|null pointer|type error|syntax error)\b
```

**Context Signals**:
- Stack trace present
- Error message included
- Exit code mentioned
- Exception type specified

**Confidence Boost**: +0.3 if stack trace or error message present

### Verification Failure

Indicates tests or validation checks failed.

**Patterns**:
```regex
\b(test failed|tests failing|assertion failed|expect.*to|should.*but)\b
\b(validation error|schema mismatch|type check failed)\b
\b(build failed|compile error|lint error)\b
```

**Context Signals**:
- Test output format (PASS/FAIL)
- Assertion messages
- Expected vs actual values

**Confidence Boost**: +0.2 if specific test name mentioned

### User Rejection

Indicates user explicitly rejected the output.

**Patterns**:
```regex
\b(no|wrong|incorrect|not what I|try again|that's not)\b
\b(doesn't work|won't work|not working|still broken)\b
\b(completely wrong|misunderstood|missed the point)\b
```

**Context Signals**:
- Negative sentiment
- Request to redo
- Clarification of intent

**Confidence Boost**: +0.2 if explicit "try again" or similar

### Partial Success

Indicates output is close but needs adjustment.

**Patterns**:
```regex
\b(almost|close but|except for|mostly|nearly)\b
\b(just need to|one thing|small change|minor issue)\b
\b(good but|works but|fine except)\b
```

**Context Signals**:
- Positive-negative combination
- Specific adjustment requested
- Single issue mentioned

**Confidence Boost**: +0.1 if specific change requested

## Refinement Mapping

Each feedback type maps to specific refinement actions:

### Runtime Error → Actions

```yaml
runtime_error:
  actions:
    - type: add_context
      description: "Add error message to prompt context"
      template: "Given the error: {error_message}"

    - type: add_constraint
      description: "Specify language/framework constraints"
      template: "Ensure compatibility with {detected_framework}"

    - type: request_approach
      description: "Request step-by-step approach"
      template: "Approach this step by step, validating each change"

  priority_order:
    1: add_context       # Most important: include the error
    2: add_constraint    # Second: clarify technical constraints
    3: request_approach  # Third: request methodical approach
```

### Verification Failure → Actions

```yaml
verification_failure:
  actions:
    - type: add_test_context
      description: "Add test requirements to prompt"
      template: "Ensure the solution passes: {test_description}"

    - type: specify_behavior
      description: "Specify expected behavior explicitly"
      template: "Expected behavior: {expected_behavior}"

    - type: request_validation
      description: "Request validation steps"
      template: "Include validation that confirms the fix works"

  priority_order:
    1: add_test_context    # Most important: what test to pass
    2: specify_behavior    # Second: clarify expected behavior
    3: request_validation  # Third: verify before completing
```

### User Rejection → Actions

```yaml
user_rejection:
  actions:
    - type: request_clarification
      description: "Ask for clarification on intent"
      template: "To clarify the goal: {clarification_prompt}"

    - type: offer_alternatives
      description: "Offer alternative approaches"
      template: "Alternative approaches to consider: {alternatives}"

    - type: narrow_scope
      description: "Narrow the scope of the task"
      template: "Focusing specifically on: {narrowed_scope}"

  priority_order:
    1: request_clarification  # Most important: understand intent
    2: narrow_scope           # Second: reduce ambiguity
    3: offer_alternatives     # Third: try different approaches
```

### Partial Success → Actions

```yaml
partial_success:
  actions:
    - type: focus_on_gap
      description: "Focus on the specific gap"
      template: "Specifically addressing: {gap_description}"

    - type: add_targeted_constraint
      description: "Add constraint for the specific issue"
      template: "Additional constraint: {constraint}"

    - type: request_incremental_fix
      description: "Request incremental fix"
      template: "Make minimal changes to address: {issue}"

  priority_order:
    1: focus_on_gap            # Most important: address specific issue
    2: add_targeted_constraint # Second: prevent same issue
    3: request_incremental_fix # Third: minimal changes
```

## Refinement Loop

### Algorithm

```python
def refine_prompt(original_prompt, feedback, config):
    """
    Refine prompt based on feedback.

    Args:
        original_prompt: The prompt that produced the failing output
        feedback: Detected feedback signal
        config: Configuration with max_refinement_iterations

    Returns:
        refined_prompt: Improved prompt addressing the feedback
    """
    max_iterations = config.get('max_refinement_iterations', 3)

    for iteration in range(max_iterations):
        # Detect feedback type
        feedback_type = detect_feedback_type(feedback)

        if feedback_type is None:
            # No feedback signal - success or ambiguous
            return original_prompt

        # Get refinement actions for this feedback type
        actions = REFINEMENT_MAPPING[feedback_type]['actions']

        # Apply actions in priority order
        refined = original_prompt
        for action in sorted(actions, key=lambda a: a['priority']):
            refined = apply_action(refined, action, feedback)

        # Re-analyze the refined prompt
        analysis = analyze_prompt(refined)

        # If quality improved significantly, return
        if analysis.score >= 7:
            return refined

        # Otherwise, continue refining
        original_prompt = refined

    # Max iterations reached
    return refined
```

### Iteration Limits

- Default: 3 iterations maximum
- Configurable via `max_refinement_iterations` in config
- Hard limit prevents infinite loops
- Each iteration logged for analysis

## Logging

All feedback signals and refinements are logged for analysis:

```yaml
feedback_log_entry:
  timestamp: "2026-02-01T10:30:00Z"
  original_prompt: "review the code"
  feedback_type: "user_rejection"
  feedback_signal: "wrong, I meant security review"
  actions_applied:
    - request_clarification
  refined_prompt: "As a security expert, review the code for vulnerabilities"
  iteration: 1
  success: true
```

This logging enables:
- Pattern detection across sessions
- Refinement effectiveness analysis
- Continuous improvement of mapping rules
