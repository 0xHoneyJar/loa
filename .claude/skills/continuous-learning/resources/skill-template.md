# Skill Template

Use this template when extracting skills from debugging discoveries.

---

## YAML Frontmatter

```yaml
---
name: {kebab-case-skill-name}
description: |
  {One-paragraph description of the skill. Include:
  - What problem it solves
  - When to apply it (trigger summary)
  - What solution it provides}
loa-agent: {implementing-tasks | reviewing-code | auditing-security | deploying-infrastructure}
extracted-from: {sprint-N-task-M | session-date | issue-reference}
extraction-date: {YYYY-MM-DD}
version: 1.0.0
tags:
  - {technology}
  - {category}
  - {additional-tags}
---
```

### Field Definitions

| Field | Required | Description |
|-------|----------|-------------|
| `name` | YES | Unique kebab-case identifier |
| `description` | YES | Multi-line description for retrieval |
| `loa-agent` | YES | Agent that extracted this skill |
| `extracted-from` | YES | Source context (sprint, session, issue) |
| `extraction-date` | YES | ISO date of extraction |
| `version` | YES | Semver starting at 1.0.0 |
| `tags` | YES | Array of searchable tags |

---

## Problem

{Clear, specific statement of the problem. Include:
- What fails or doesn't work as expected
- Observable symptoms
- Impact on the system or workflow}

**Example**:
> Consumer stops receiving messages after process restart. All messages published during downtime are lost because consumer doesn't remember its position.

---

## Trigger Conditions

### Symptoms

{List the observable symptoms that indicate this skill applies}

- {Symptom 1}
- {Symptom 2}
- {Symptom 3}

### Error Messages

{Include any specific error messages, if applicable}

```
{Error message text}
```

### Context

{Define when this skill is applicable}

| Context | Value |
|---------|-------|
| Technology Stack | {e.g., NATS JetStream, PostgreSQL, React} |
| Environment | {e.g., Production, Docker, Kubernetes} |
| Timing | {e.g., After restart, during high load} |
| Prerequisites | {e.g., Requires X version or higher} |

---

## Root Cause

{Explain WHY the problem occurs. This is critical for understanding, not just fixing.}

**Example**:
> Ephemeral consumers don't persist their position. On restart, a new ephemeral consumer is created with no memory of previous position.

---

## Solution

### Step 1: {Action Title}

{Explanation of what this step does and why}

```{language}
{Code snippet with inline comments}
```

### Step 2: {Action Title}

{Continue with additional steps as needed}

```{language}
{Code snippet}
```

### Complete Example

{If helpful, show a complete before/after or full implementation}

```{language}
{Complete code example}
```

---

## Verification

{How to confirm the solution works}

### Command

```bash
{Verification command}
```

### Expected Output

{What success looks like}

```
{Expected output}
```

### Checklist

- [ ] {Verification step 1}
- [ ] {Verification step 2}
- [ ] {Verification step 3}

---

## Anti-Patterns

### Don't: {Bad Practice Title}

{Explain why this approach is wrong}

```{language}
// BAD - {reason}
{Bad code example}
```

### Don't: {Another Bad Practice}

{Additional anti-patterns if applicable}

---

## Related Resources

{External documentation, issues, or references}

- [{Resource Title}]({URL})
- [{Documentation Link}]({URL})

---

## Related Memory

{Cross-references to NOTES.md or other skills}

### NOTES.md References

- `## Learnings`: {Entry title if exists}
- `## Technical Debt`: {Entry if created debt awareness}

### Related Skills

- `{related-skill-name}`: {Brief description of relationship}

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | {YYYY-MM-DD} | Initial extraction |

---

## Metadata (Auto-Generated)

{This section is populated automatically during extraction}

```yaml
quality_gates:
  discovery_depth: true
  reusability: true
  trigger_clarity: true
  verification: true
extraction_source:
  agent: {loa-agent}
  phase: {/implement | /review-sprint | etc.}
  session: {session-id if available}
```
