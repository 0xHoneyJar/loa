---
description: Launch the architecture designer agent to review the PRD and generate a comprehensive Software Design Document (SDD)
args: [background]
---

I'm launching the architecture-designer agent to create a comprehensive Software Design Document based on your Product Requirements Document.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

## Pre-flight Check: Setup Verification

Before proceeding, verify that Loa setup is complete:

1. Check if `.loa-setup-complete` marker file exists in the project root
2. If the marker file **does NOT exist**:
   - Display this message:
     ```
     Loa setup has not been completed for this project.

     Please run `/setup` first to:
     - Configure MCP integrations
     - Initialize project analytics
     - Set up Linear project tracking

     After setup is complete, run `/architect` again.
     ```
   - **STOP** - Do not proceed with SDD creation
3. If the marker file **exists**, proceed with the architecture process

---

The agent will:
1. **Carefully review** `loa-grimoire/prd.md` to understand all requirements
2. **Analyze and design** the system architecture, components, and technical decisions
3. **Clarify uncertainties** by asking you questions with specific proposals when anything is ambiguous
4. **Validate assumptions** to ensure the design aligns with your vision
5. **Generate SDD** only when fully satisfied with all answers and has no remaining doubts
6. **Save output** to `loa-grimoire/sdd.md`

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
  prompt="You are tasked with creating a comprehensive Software Design Document (SDD) based on the Product Requirements Document at loa-grimoire/prd.md.

## CRITICAL: Setup Check (Phase -1)

BEFORE doing anything else, check if `.loa-setup-complete` marker file exists:

```bash
ls -la .loa-setup-complete 2>/dev/null
```

If the file does NOT exist, display this message and STOP:
```
Loa setup has not been completed for this project.

Please run `/setup` first to:
- Configure MCP integrations
- Initialize project analytics
- Set up Linear project tracking

After setup is complete, run `/architect` again.
```

If the file EXISTS, proceed with the SDD process.

---

Your process:
1. Carefully read and analyze loa-grimoire/prd.md in its entirety
2. Design the system architecture, components, data models, APIs, and technical stack
3. For ANY uncertainties, ambiguities, or areas where multiple approaches are valid:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons for each approach
   - Explain the technical tradeoffs
   - Wait for their decision before proceeding
4. Validate all assumptions with the user
5. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the SDD
6. Generate a detailed, comprehensive Software Design Document
7. Save the final SDD to loa-grimoire/sdd.md

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

## Phase Post-SDD: ADR Candidate Surfacing

After the SDD is written, run ADR candidate detection:
1. Scan SDD for decision patterns (see .claude/lib/candidate-surfacer.md)
2. Extract candidates with: decision, context, alternatives, rationale, trade-offs
3. Apply confidence filter (score >= 2)
4. If candidates found, prompt user: [Submit all] [Review first] [Skip]
5. If submit: Create Linear issues using integration-context.md team ID
6. If Linear fails: Save to loa-grimoire/pending-candidates.json
7. Continue to sprint planning (non-blocking)

## Analytics Update (Phase Final)

After successfully saving the SDD to loa-grimoire/sdd.md, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.sdd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")
jq --arg ts \"$TIMESTAMP\" '
  .phases.sdd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the SDD process successfully.

Remember: Ask questions and seek clarity BEFORE writing. Only generate the SDD when you have complete confidence in the design decisions."
/>
{{ else }}
## Phase -1: Setup Verification

First, check if `.loa-setup-complete` marker file exists:

```bash
ls -la .loa-setup-complete 2>/dev/null
```

If the file does NOT exist, display this message and STOP:
```
Loa setup has not been completed for this project.

Please run `/setup` first to:
- Configure MCP integrations
- Initialize project analytics
- Set up Linear project tracking

After setup is complete, run `/architect` again.
```

If the file EXISTS, proceed with Phase 0.

---

## Phase 0: Begin Architectural Design

You are tasked with creating a comprehensive Software Design Document (SDD) based on the Product Requirements Document at loa-grimoire/prd.md.

Your process:
1. Carefully read and analyze loa-grimoire/prd.md in its entirety
2. Design the system architecture, components, data models, APIs, and technical stack
3. For ANY uncertainties, ambiguities, or areas where multiple approaches are valid:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons for each approach
   - Explain the technical tradeoffs
   - Wait for their decision before proceeding
4. Validate all assumptions with the user
5. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the SDD
6. Generate a detailed, comprehensive Software Design Document
7. Save the final SDD to loa-grimoire/sdd.md

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

---

## Phase Post-SDD: ADR Candidate Surfacing

After the SDD is written and saved to `loa-grimoire/sdd.md`, run ADR candidate detection.

### Step 1: Scan SDD for Decision Patterns

Read the SDD content and look for ADR candidate patterns:

**Decision Patterns** (triggers):
- "We decided to use X instead of Y"
- "Choosing X over Y because Z"
- "After evaluating, we selected X"
- "The decision is to X"
- "Going with X rather than Y"
- "Trade-off... X vs Y"
- "Considered alternatives:"

### Step 2: Extract ADR Candidates

For each detected pattern, extract:
- **Decision**: What was decided
- **Context**: Why this decision was needed
- **Alternatives**: Other options considered and why rejected
- **Rationale**: Why this approach was chosen
- **Trade-offs**: Pros and cons

### Step 3: Apply Confidence Filter

Score each candidate:
- +2 if explicit "decided" language
- +2 if alternatives discussed
- +1 if trade-offs documented
- +1 if cross-component impact
- -1 if minor/localized
- -2 if no rationale

Keep candidates with score >= 2.

### Step 4: Show Batch Review (if candidates found)

If ADR candidates were detected, use AskUserQuestion:

```
question: "{N} ADR candidates detected in architecture. What would you like to do?"
header: "Candidates"
options:
  - "Submit all to Linear" - "Create Linear issues for team review (Recommended)"
  - "Review each first" - "Review each candidate before submitting"
  - "Skip for now" - "Discard candidates and continue"
```

### Step 5: Handle User Response

**If "Submit all to Linear"**:
1. Read `loa-grimoire/a2a/integration-context.md` for team ID
2. For each candidate, create Linear issue:
   - Title: `[ADR-Candidate] {decision summary}`
   - Labels: `adr-candidate`, `agent:architect`
   - Body: ADR candidate template (see `.claude/lib/candidate-surfacer.md`)
3. If Linear fails, save to `loa-grimoire/pending-candidates.json`
4. Show confirmation with created issue IDs

**If "Review each first"**:
For each candidate, ask:
```
question: "ADR Candidate: '{decision}'. Include?"
header: "Review"
options:
  - "Include" - "Add to submission batch"
  - "Exclude" - "Skip this candidate"
```
Then submit included candidates.

**If "Skip for now"**:
- Discard candidates
- Show: "Candidates discarded. You can manually create ADR issues later."
- Continue to next phase

### Step 6: Continue to Sprint Planning

After surfacing (or skip), the phase is complete. User can run `/sprint-plan` next.

See `.claude/lib/candidate-surfacer.md` for detailed patterns and templates.

---

## Phase Final: Analytics Update

After successfully saving the SDD to loa-grimoire/sdd.md, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.sdd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '
  .phases.sdd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate the summary by reading usage.json and updating summary.md with current values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the SDD process successfully.

Remember: Ask questions and seek clarity BEFORE writing. Only generate the SDD when you have complete confidence in the design decisions.
{{ endif }}
