---
name: "translate"
version: "1.0.0"
description: |
  Translate technical documentation into executive-ready communications.
  Creates summaries, briefings, and presentations for non-technical stakeholders.

arguments:
  - name: "document"
    type: "file_reference"
    required: true
    description: "Technical document to translate (use @ prefix)"
    examples: ["@SECURITY-AUDIT-REPORT.md", "@loa-grimoire/sdd.md", "@loa-grimoire/sprint.md"]

  - name: "audience"
    type: "string"
    required: true
    description: "Target audience for the translation"
    examples: ["executives", "board of directors", "investors", "product team", "compliance"]

agent: "translating-for-executives"
agent_path: "skills/translating-for-executives/"

context_files:
  - path: "$ARGUMENTS.document"
    required: true
    priority: 1
    purpose: "Technical document to translate"

pre_flight: []

outputs:
  - path: "stdout"
    type: "text"
    description: "Executive-ready communication"

mode:
  default: "foreground"
  allow_background: true
---

# Translate

## Purpose

Transform technical documentation (PRDs, SDDs, audit reports, sprint updates) into executive-ready communications. Creates clear, compelling summaries for non-technical stakeholders.

## Invocation

```
/translate @document.md for [audience]
/translate @SECURITY-AUDIT-REPORT.md for board of directors
/translate @loa-grimoire/sdd.md for executives
/translate @loa-grimoire/sprint.md for investors background
```

## Agent

Launches `translating-for-executives` from `skills/translating-for-executives/`.

See: `skills/translating-for-executives/SKILL.md` for full workflow details.

## Workflow

1. **Deep Understanding**: Read and analyze provided technical documentation
2. **Audience Analysis**: Identify stakeholder needs, technical depth, decision context
3. **Value Translation**: Transform technical details into business value statements
4. **Create Communication**: Generate executive summary with all required sections
5. **Supporting Materials**: Add FAQ, visual suggestions, stakeholder-specific versions

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `document` | Technical document to translate (@ prefix) | Yes |
| `audience` | Target audience (executives, board, investors, etc.) | Yes |
| `background` | Run as subagent for parallel execution | No |

## Outputs

The translator produces executive communications containing:
- **What We Built** - Plain language summary
- **Why It Matters** - Business value and strategic alignment
- **Key Achievements** - Measurable outcomes
- **Risks & Limitations** - Honest assessment
- **What's Next** - Immediate actions and decisions needed
- **Investment Required** - Time, budget, resources
- **Risk Assessment** - Overall level with justification
- **FAQ Section** - Anticipated stakeholder questions
- **Visual Suggestions** - Diagrams, flowcharts, risk matrices

## Communication Principles

### Do's
- Lead with value: "Reduces security risk by 73%"
- Use analogies: "Like a security guard checking IDs"
- Be specific: "Saves 8 hours/week per developer"
- Show tradeoffs: "Prioritized security over speed"
- Acknowledge gaps: "Low priority issues deferred"

### Don'ts
- Don't oversimplify - Respect audience intelligence
- Don't use jargon - Define terms immediately
- Don't hide risks - Stakeholders need honest assessment
- Don't promise impossible - Be realistic

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Document not found" | File path incorrect | Verify file exists and use @ prefix |
| "Audience not specified" | Missing audience argument | Add target audience after "for" |
