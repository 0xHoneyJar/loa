---
description: Launch the architecture designer agent to review the PRD and generate a comprehensive Software Design Document (SDD)
args: [background]
---

I'm launching the architecture-designer agent to create a comprehensive Software Design Document based on your Product Requirements Document.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

The agent will:
1. **Carefully review** `docs/prd.md` to understand all requirements
2. **Analyze and design** the system architecture, components, and technical decisions
3. **Clarify uncertainties** by asking you questions with specific proposals when anything is ambiguous
4. **Validate assumptions** to ensure the design aligns with your vision
5. **Generate SDD** only when fully satisfied with all answers and has no remaining doubts
6. **Save output** to `docs/sdd.md`

The architecture designer will cover:
- System architecture and component design
- Technology stack recommendations
- Data models and database schema
- API design and integration points
- Security architecture
- Scalability and performance considerations
- Deployment architecture
- Technical risks and mitigation strategies

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="architecture-designer"
  prompt="You are tasked with creating a comprehensive Software Design Document (SDD) based on the Product Requirements Document at docs/prd.md.

Your process:
1. Carefully read and analyze docs/prd.md in its entirety
2. Design the system architecture, components, data models, APIs, and technical stack
3. For ANY uncertainties, ambiguities, or areas where multiple approaches are valid:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons for each approach
   - Explain the technical tradeoffs
   - Wait for their decision before proceeding
4. Validate all assumptions with the user
5. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the SDD
6. Generate a detailed, comprehensive Software Design Document
7. Save the final SDD to docs/sdd.md

The SDD should include:
- Executive Summary
- System Architecture (high-level components and interactions)
- Technology Stack (with justification for choices)
- Component Design (detailed breakdown of each component)
- Data Architecture (database schema, data models, storage strategies)
- API Design (endpoints, contracts, authentication)
- Security Architecture (authentication, authorization, encryption, threat mitigation)
- Integration Points (external services, APIs, third-party dependencies)
- Scalability & Performance (caching, load balancing, optimization strategies)
- Deployment Architecture (infrastructure, CI/CD, environments)
- Development Workflow (Git strategy, testing approach, code review process)
- Technical Risks & Mitigation Strategies
- Future Considerations & Technical Debt Management

Remember: Ask questions and seek clarity BEFORE writing. Only generate the SDD when you have complete confidence in the design decisions."
/>
{{ else }}
Let me begin the architectural design process.

You are tasked with creating a comprehensive Software Design Document (SDD) based on the Product Requirements Document at docs/prd.md.

Your process:
1. Carefully read and analyze docs/prd.md in its entirety
2. Design the system architecture, components, data models, APIs, and technical stack
3. For ANY uncertainties, ambiguities, or areas where multiple approaches are valid:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons for each approach
   - Explain the technical tradeoffs
   - Wait for their decision before proceeding
4. Validate all assumptions with the user
5. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the SDD
6. Generate a detailed, comprehensive Software Design Document
7. Save the final SDD to docs/sdd.md

The SDD should include:
- Executive Summary
- System Architecture (high-level components and interactions)
- Technology Stack (with justification for choices)
- Component Design (detailed breakdown of each component)
- Data Architecture (database schema, data models, storage strategies)
- API Design (endpoints, contracts, authentication)
- Security Architecture (authentication, authorization, encryption, threat mitigation)
- Integration Points (external services, APIs, third-party dependencies)
- Scalability & Performance (caching, load balancing, optimization strategies)
- Deployment Architecture (infrastructure, CI/CD, environments)
- Development Workflow (Git strategy, testing approach, code review process)
- Technical Risks & Mitigation Strategies
- Future Considerations & Technical Debt Management

Remember: Ask questions and seek clarity BEFORE writing. Only generate the SDD when you have complete confidence in the design decisions.
{{ endif }}
