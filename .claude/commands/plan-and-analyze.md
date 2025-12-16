---
description: Launch the PRD architect agent to define goals, requirements, scope, and generate a Product Requirements Document (PRD)
args: [background]
---

I'm launching the prd-architect agent to help you create a comprehensive Product Requirements Document.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

The agent will guide you through a structured discovery process to:
1. **Define goals** - Clarify what you want to achieve and why
2. **Define requirements** - Identify functional and non-functional requirements
3. **Identify scope** - Determine what's in scope, out of scope, and prioritize features
4. **Research and refine** - Gather context, ask clarifying questions, and validate assumptions
5. **Generate PRD** - Create a comprehensive document at `docs/prd.md`

The PRD architect will ask targeted questions across these phases:
- Problem & Vision
- Goals & Success Metrics
- User & Stakeholder Context
- Functional Requirements
- Technical & Non-Functional Requirements
- Scope & Prioritization
- Risks & Dependencies

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="prd-architect"
  prompt="Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to docs/prd.md."
/>
{{ else }}
Let me begin the discovery process.

Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to docs/prd.md.
{{ endif }}
