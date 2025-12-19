---
description: Launch the PRD architect agent to define goals, requirements, scope, and generate a Product Requirements Document (PRD)
args: [background]
---

I'm launching the prd-architect agent to help you create a comprehensive Product Requirements Document.

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

     After setup is complete, run `/plan-and-analyze` again.
     ```
   - **STOP** - Do not proceed with PRD creation
3. If the marker file **exists**, proceed with the PRD process

---

The agent will guide you through a structured discovery process to:
1. **Define goals** - Clarify what you want to achieve and why
2. **Define requirements** - Identify functional and non-functional requirements
3. **Identify scope** - Determine what's in scope, out of scope, and prioritize features
4. **Research and refine** - Gather context, ask clarifying questions, and validate assumptions
5. **Generate PRD** - Create a comprehensive document at `loa-grimoire/prd.md`

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
  prompt="Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to loa-grimoire/prd.md.

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

After setup is complete, run `/plan-and-analyze` again.
```

If the file EXISTS, proceed with Phase 0.5 (Hivemind Context Injection).

## Phase 0.5: Hivemind Context Injection

Before beginning discovery, check if Hivemind is connected:

1. Check `.hivemind` symlink: `[ -L '.hivemind' ] && [ -d '.hivemind/library' ]`
2. If connected:
   - Read project type from `loa-grimoire/a2a/integration-context.md`
   - Extract keywords from user description and project context
   - Spawn 3 parallel Explore agents to search Hivemind:
     * Decision Archaeologist: Search `.hivemind/library/decisions/` for relevant ADRs
     * Timeline Navigator: Search `.hivemind/library/timeline/` for past experiments
     * Technical Reference Finder: Search `.hivemind/library/knowledge/` for Learning Memos
   - Synthesize results into organizational context block
   - Inject context into your working memory
3. If not connected:
   - Show notice: 'Hivemind not connected, proceeding without org context'
   - Continue normally

See `.claude/lib/context-injector.md` for detailed patterns.

## Analytics Update (Phase Final)

After successfully saving the PRD to loa-grimoire/prd.md, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.prd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")
jq --arg ts \"$TIMESTAMP\" '
  .phases.prd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the PRD process successfully."
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

After setup is complete, run `/plan-and-analyze` again.
```

If the file EXISTS, proceed with Phase 0.5.

---

## Phase 0.5: Hivemind Context Injection

Before beginning discovery, check if Hivemind is connected and inject organizational context.

### Step 1: Check Hivemind Connection

```bash
# Check if .hivemind symlink exists and is valid
if [ -L ".hivemind" ] && [ -d ".hivemind/library" ]; then
    echo "HIVEMIND_STATUS:connected"
else
    echo "HIVEMIND_STATUS:not_connected"
fi
```

### Step 2: Handle Connection Status

**If Hivemind is NOT connected**:
```markdown
**Notice**: Hivemind OS is not connected. Proceeding without organizational context.

To enable context injection from organizational memory:
1. Run `/setup`
2. Select "Connect to Hivemind OS"

Continuing with PRD discovery...
```
Skip to Phase 0 and proceed normally.

**If Hivemind IS connected**:
Continue with context injection below.

### Step 3: Read Integration Context

Read project configuration from `loa-grimoire/a2a/integration-context.md`:
- Project type (for domain keywords)
- Linked experiment (if any, for hypothesis keywords)
- Product Home (for context about the product)

### Step 4: Extract Keywords

From the user's problem description (if provided) and project context, extract keywords:

**Keyword Sources**:
1. User's initial description (noun phrases, technical terms, brand names)
2. Project type keywords (see `.claude/lib/context-injector.md`)
3. Linked experiment hypothesis keywords (if available)

**Keyword Categories**:
- High priority: Brand names (CubQuests, Set & Forgetti, Henlo, Mibera), domain terms
- Medium priority: Technical terms, action verbs
- Low priority: Generic technology terms

### Step 5: Spawn Parallel Research Agents

Using the Task tool, spawn 3 parallel Explore agents to gather organizational context:

```markdown
## Context Injection - Parallel Research

Spawn these agents in parallel to search Hivemind:

### Agent 1: Decision Archaeologist
Search `.hivemind/library/decisions/` for ADRs matching keywords: {extracted_keywords}
Return: List of relevant ADRs with:
- ADR number and title
- Brief summary
- Why it's relevant to this project

### Agent 2: Timeline Navigator
Search `.hivemind/library/timeline/` and `.hivemind/laboratory/experiments/` for past experiments matching: {domain_keywords}
Return: List of related experiments/ERRs with:
- Experiment name and outcome
- Key learnings
- How it applies to current work

### Agent 3: Technical Reference Finder
Search `.hivemind/library/ecosystem/` and `.hivemind/library/knowledge/` for docs matching: {technical_keywords}
Return: List of Learning Memos and ecosystem docs with:
- Document title
- Key insights
- Relevant patterns
```

### Step 6: Synthesize and Inject Context

After agents return, synthesize results into a context block:

```markdown
## Organizational Context (Injected from Hivemind)

Based on organizational memory, here is relevant context for this PRD:

### Relevant Decisions
{List ADRs that inform this project}

### Past Experiments
{List experiments with relevant learnings}

### Proven Patterns
{List Learning Memos with applicable patterns}

### Technical Context
{List ecosystem docs that provide foundation}

---
*Context injected from Hivemind OS at {timestamp}*
```

Inject this context block into the PRD architect's working memory before beginning discovery.

### Step 7: Proceed to Discovery

With organizational context injected (or notice shown if disconnected), proceed to Phase 0.

---

## Phase 0: Begin Discovery

Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to loa-grimoire/prd.md.

---

## Phase Final: Analytics Update

After successfully saving the PRD to loa-grimoire/prd.md, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.prd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '
  .phases.prd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate the summary by reading usage.json and updating summary.md with current values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the PRD process successfully.
{{ endif }}
