# Decision Capture Protocol

## Purpose

Capture significant decisions during Loa execution for auditability and learning.

## When to Capture

### Capture If

- [ ] Someone might ask "why?" in 6 months
- [ ] Multiple alternatives were considered
- [ ] Tradeoffs were made
- [ ] Scope was cut or expanded
- [ ] Technology was chosen
- [ ] Architecture pattern was selected

### Skip If

- [ ] Obvious choice with no alternatives
- [ ] Routine implementation detail
- [ ] Style/formatting preference

## How to Capture

### During Execution

After making a significant decision, append to `grimoires/loa/decisions.yaml`:

```yaml
- id: DEC-{next_id}
  timestamp: "{ISO8601}"
  phase: {current_phase}
  agent: {current_skill}
  category: {architecture|technology|scope|tradeoff|security|performance|ux|process}
  summary: "{one line, max 200 chars}"
  decision: "{what was decided}"
  rationale: "{why this option}"
  alternatives_considered:
    - option: "{alternative 1}"
      rejected_because: "{reason}"
  status: active
```

### ID Assignment

IDs are sequential within a cycle: DEC-0001, DEC-0002, etc.

Get next ID:

```bash
next_id=$(yq '.decisions | length + 1' grimoires/loa/decisions.yaml | xargs printf "DEC-%04d")
```

### Grounding

Always include source grounding when available:

```yaml
grounding:
  sources:
    - file: "grimoires/loa/prd.md"
      line: 45
      quote: "exact text that informed decision"
  external_refs:
    - "https://relevant-documentation.com"
```

## Phase-Specific Guidance

### Discovery Phase

Capture:
- MVP scope decisions
- Feature prioritization
- Out-of-scope declarations

### Architecture Phase

Capture:
- Technology stack choices
- Pattern selections
- Integration decisions
- Security model

### Sprint Planning Phase

Capture:
- Task sequencing logic
- Dependency resolutions
- Parallel work splits

### Implementation Phase

Capture:
- Algorithm selections
- Library choices
- Performance tradeoffs

### Review Phase

Capture:
- Approved technical debt
- Deferred improvements
- Accepted tradeoffs with justification

## Consequences

Document expected outcomes:

```yaml
consequences:
  positive:
    - "Benefit 1"
    - "Benefit 2"
  negative:
    - "Known drawback 1"
    - "Risk to monitor"
  neutral:
    - "Side effect that's neither good nor bad"
```

## Review and Supersession

When a decision is revisited:

1. Don't delete the original
2. Add new decision with updated rationale
3. Mark original as superseded:

```yaml
# Original decision
- id: DEC-0005
  status: superseded
  superseded_by: DEC-0012
  # ... rest unchanged

# New decision
- id: DEC-0012
  summary: "Switch from X to Y"
  rationale: "Original decision DEC-0005 didn't account for Z"
  # ...
```

## Validation

Schema: `.claude/schemas/decisions.schema.json`

Required fields:
- id, timestamp, phase, category
- summary, decision, rationale
- alternatives_considered (minimum 1)
