# Karpathy Principles Protocol

> **Version**: 1.0 (v1.8.0)
> **Source**: [Andrej Karpathy's LLM Coding Guidelines](https://github.com/forrestchang/andrej-karpathy-skills)
> **Purpose**: Counter common LLM coding pitfalls with structured behavioral principles

---

## Overview

This protocol codifies Andrej Karpathy's observations about common LLM coding failures:

1. **Unjustified assumptions** - Making wrong assumptions without verification
2. **Overcomplicated solutions** - Bloating code with unnecessary abstractions
3. **Unintended side effects** - Modifying unrelated code unnecessarily

Loa already addresses these through grounding enforcement and factual citation requirements. This protocol adds explicit behavioral guidelines at the skill level.

---

## The Four Core Principles

### 1. Think Before Coding

**Problem**: LLMs make assumptions and proceed without clarification.

**Principle**: Surface assumptions explicitly. When multiple interpretations exist, present them rather than choosing silently.

**Implementation in Loa**:

```markdown
BEFORE implementing, ASK:
- What am I assuming about the user's intent?
- Are there multiple valid interpretations?
- What clarifying questions would help?

IF uncertain about scope:
  → Present options with tradeoffs
  → Let user choose

IF requirements seem incomplete:
  → Ask for missing information
  → Don't infer beyond what's stated
```

**Integration Points**:
- `<uncertainty_protocol>` in skill KERNEL
- AskUserQuestion tool for clarification
- Factual grounding requirement for all claims

---

### 2. Simplicity First

**Problem**: LLMs overcomplicate code with speculative features and premature abstractions.

**Principle**: Write minimal code solving only what was requested. No features beyond what was asked.

**Implementation in Loa**:

```markdown
IMPLEMENT only what was requested:
- No speculative features
- No "just in case" error handling
- No abstractions for single-use code
- No configurability unless asked

SIMPLICITY CHECK:
- Could this be 50 lines instead of 200?
- Am I adding complexity for hypothetical futures?
- Is this abstraction earning its keep?

IF code is longer than necessary:
  → Rewrite simpler
  → Delete speculative additions
```

**Metrics**:
| Smell | Action |
|-------|--------|
| Single-use abstraction | Inline it |
| Unused parameters | Remove them |
| "Extensibility" hooks | Delete unless requested |
| Generic interfaces for specific use | Simplify to concrete |

---

### 3. Surgical Changes

**Problem**: LLMs modify adjacent code they weren't asked to change.

**Principle**: Only modify what the request requires. Preserve existing style even if you'd do it differently.

**Implementation in Loa**:

```markdown
WHEN editing existing code:
- Match existing style (even if imperfect)
- Don't "improve" adjacent code
- Don't reformat unrelated sections
- Don't add comments to unchanged code
- Don't change variable names without reason

SURGICAL DIFF RULES:
- Only touch lines necessary for the task
- Remove only imports/variables YOUR changes made unused
- Don't clean up pre-existing dead code
- Leave existing comments alone

DIFF REVIEW:
- Every changed line should relate to the request
- No "while I'm here" changes
- If you see issues elsewhere, note them separately
```

**Verification**:
```bash
# Check diff size vs. scope
git diff --stat
# Large diff for small task = SMELL
```

---

### 4. Goal-Driven Execution

**Problem**: Imperative instructions lead to meandering implementations.

**Principle**: Transform tasks into verifiable goals with clear success criteria.

**Implementation in Loa**:

```markdown
BEFORE starting:
1. Restate the goal as verifiable criteria
2. Define what "done" looks like
3. Identify how to verify success

GOAL FORMAT:
- WHAT: [concrete deliverable]
- VERIFY: [how to confirm it works]
- EVIDENCE: [specific output/behavior]

EXAMPLE:
- WHAT: Add rate limiting to /api/login
- VERIFY: Returns 429 after 5 attempts in 60 seconds
- EVIDENCE: Test passes: `npm test -- rate-limit.test.ts`
```

**Integration with EDD**:
- Maps to Evaluation-Driven Development
- min_test_scenarios enforces verification
- Acceptance criteria must be testable

---

## Skill Integration

### Embedding in SKILL.md

Add to each skill's `<constraints>` section:

```xml
<karpathy_principles>
## Karpathy Principles (MANDATORY)

1. **Think Before Coding**: Surface assumptions, ask clarifying questions
2. **Simplicity First**: No speculative features, no premature abstractions
3. **Surgical Changes**: Only modify what's requested, preserve existing style
4. **Goal-Driven**: Define verifiable success criteria before starting
</karpathy_principles>
```

### Pre-Implementation Checklist

Before writing code, verify:

```markdown
## Karpathy Pre-Implementation Check

- [ ] **Assumptions surfaced**: Listed all assumptions in reasoning
- [ ] **Clarifications sought**: Asked about ambiguities
- [ ] **Scope minimal**: No features beyond request
- [ ] **Success defined**: Clear verification criteria
- [ ] **Style matched**: Will preserve existing conventions
```

---

## Anti-Patterns to Avoid

### 1. Silent Assumption Making

```
BAD:
User: "Add authentication"
LLM: *Implements OAuth2 with JWT, refresh tokens, and 2FA*

GOOD:
User: "Add authentication"
LLM: "What type of authentication? Options:
      1. Simple API key
      2. JWT tokens
      3. OAuth2 with refresh tokens
      4. Full OAuth2 + 2FA
      Which fits your needs?"
```

### 2. Speculative Complexity

```
BAD:
User: "Add a config for the API URL"
LLM: *Creates ConfigManager class with validation, caching,
      environment detection, and hot-reload support*

GOOD:
User: "Add a config for the API URL"
LLM: *Adds single environment variable read*
     const API_URL = process.env.API_URL || 'http://localhost:3000'
```

### 3. Drive-By Improvements

```
BAD:
User: "Fix the null check on line 45"
LLM: *Fixes line 45, also reformats function, adds types,
      updates comments, and renames variables*

GOOD:
User: "Fix the null check on line 45"
LLM: *Changes only line 45*
     (Notes separately: "I noticed other potential improvements
      in this file. Want me to list them?")
```

### 4. Vague Success Criteria

```
BAD:
"I'll implement a robust authentication system"

GOOD:
"Success criteria:
 1. POST /login returns JWT on valid credentials
 2. Invalid credentials return 401
 3. Protected routes reject requests without valid JWT
 4. Tests verify all three behaviors"
```

---

## Relationship to Existing Protocols

| Karpathy Principle | Loa Protocol | Enhancement |
|-------------------|--------------|-------------|
| Think Before Coding | `<uncertainty_protocol>` | Add assumption surfacing |
| Simplicity First | None explicit | NEW - add complexity checks |
| Surgical Changes | Change Validation | Add diff scope validation |
| Goal-Driven | EDD Verification | Already aligned |

### Integration Points

1. **Grounding Enforcement** already requires factual citations - aligns with "Think Before Coding"
2. **EDD Verification** already requires test scenarios - aligns with "Goal-Driven"
3. **Change Validation** already checks file references - extend for diff scope

---

## Configuration

Add to `.loa.config.yaml`:

```yaml
# Karpathy Principles (v1.8.0)
karpathy_principles:
  # Enable explicit assumption surfacing
  surface_assumptions: true

  # Warn on large diffs for small tasks
  surgical_diff_warning: true
  diff_lines_per_task: 50  # Warn if exceeded

  # Complexity checks
  simplicity_check: true
  max_abstraction_depth: 2  # Warn on deeper nesting

  # Require success criteria before implementation
  require_success_criteria: true
```

---

## Verification

### Trajectory Logging

Log principle adherence:

```jsonl
{"phase":"karpathy_check","principle":"think_before_coding","assumptions_surfaced":3,"clarifications_asked":1}
{"phase":"karpathy_check","principle":"simplicity_first","lines_added":47,"abstractions_created":0}
{"phase":"karpathy_check","principle":"surgical_changes","files_modified":2,"unrelated_changes":0}
{"phase":"karpathy_check","principle":"goal_driven","success_criteria":["test passes","returns 200"]}
```

### Reviewer Checklist

Add to reviewer.md template:

```markdown
## Karpathy Principles Verification

- [ ] No silent assumptions (all documented in reasoning)
- [ ] No speculative features (only what was requested)
- [ ] No unrelated changes (diff matches task scope)
- [ ] Clear success criteria (testable and verified)
```

---

## Related Protocols

- [Grounding Enforcement](grounding-enforcement.md) - Factual citation requirements
- [EDD Verification](edd-verification.md) - Test-driven verification
- [Change Validation](change-validation.md) - Pre-implementation validation
- [Uncertainty Protocol](../skills/implementing-tasks/SKILL.md) - Clarification behavior

---

**Protocol Version**: 1.0
**Last Updated**: 2026-01-28
**Source**: Andrej Karpathy via forrestchang/andrej-karpathy-skills
