# PRD Architect Reference

## Discovery Phase Questions

### Phase 1: Problem & Vision
- What problem are we solving, and for whom?
- What does success look like from the user's perspective?
- What's the broader vision this fits into?
- Why is this important now?

### Phase 2: Goals & Success Metrics
- What are the specific, measurable goals?
- How will we know this is successful? (KPIs, metrics)
- What's the expected timeline and key milestones?
- What constraints or limitations exist?

### Phase 3: User & Stakeholder Context
- Who are the primary users? What are their characteristics?
- What are the key user personas and their needs?
- Who are the stakeholders, and what are their priorities?
- What existing solutions or workarounds do users employ?

### Phase 4: Functional Requirements
- What are the must-have features vs. nice-to-have?
- What are the critical user flows and journeys?
- What data needs to be captured, stored, or processed?
- What integrations or dependencies exist?

### Phase 5: Technical & Non-Functional Requirements
- What are the performance, scalability, or reliability requirements?
- What are the security, privacy, or compliance considerations?
- What platforms, devices, or browsers must be supported?
- What are the technical constraints or preferred technologies?

### Phase 6: Scope & Prioritization
- What's explicitly in scope for this release?
- What's explicitly out of scope?
- How should features be prioritized if tradeoffs are needed?
- What's the MVP vs. future iterations?

### Phase 7: Risks & Dependencies
- What are the key risks or unknowns?
- What dependencies exist (other teams, systems, external factors)?
- What assumptions are we making?
- What could cause this to fail?

## PRD Quality Checklist

### Structure
- [ ] Table of contents present
- [ ] All 13 required sections included
- [ ] Clear section headings and navigation

### Requirements Quality
- [ ] All requirements have acceptance criteria
- [ ] Requirements are specific and testable
- [ ] Priority levels assigned (Must Have/Should Have/Nice to Have)
- [ ] Dependencies identified

### Metrics Quality
- [ ] Success metrics are quantifiable
- [ ] Baseline values documented
- [ ] Target values specified
- [ ] Timeline for measurement defined

### Scope Quality
- [ ] MVP clearly defined
- [ ] Out of scope items listed with rationale
- [ ] Future iterations outlined
- [ ] Priority matrix included

### Risk Quality
- [ ] Risks identified with probability and impact
- [ ] Mitigation strategies defined
- [ ] Assumptions documented
- [ ] External dependencies noted

## Common Anti-Patterns to Avoid

1. **Vague Requirements**
   - BAD: "The system should be fast"
   - GOOD: "Page load time < 2 seconds on 3G connection"

2. **Missing Acceptance Criteria**
   - BAD: "Users can log in"
   - GOOD: "Users can log in with email/password, receiving session token valid for 24 hours"

3. **Unquantifiable Metrics**
   - BAD: "Improve user engagement"
   - GOOD: "Increase DAU by 20% within 30 days of launch"

4. **Scope Creep Enablers**
   - BAD: "And any other features users might want"
   - GOOD: Explicitly list out-of-scope items with rationale

5. **Undefined Personas**
   - BAD: "Users will appreciate this feature"
   - GOOD: "Power users (>10 sessions/week) will save 15 minutes daily"
