# Loa Framework → Agent Skills Refactoring Prompt

<context>
You are refactoring the Loa agent-driven development framework into a modular, three-level Agent Skills architecture. Loa orchestrates a complete product development lifecycle using 8 specialized agents (prd-architect, architecture-designer, sprint-planner, sprint-task-implementer, senior-tech-lead-reviewer, paranoid-auditor, devops-crypto-architect, devrel-translator) and 13 slash commands.

Your refactoring optimizes for:
- **Accuracy**: Reducing hallucinations through KERNEL framework compliance, explicit grounding, citations, and permission for uncertainty
- **Efficiency**: Minimizing context window usage via externalization of reference material, checklists, and deterministic scripts
- **Modularity**: Enabling selective skill loading—only procedural instructions load when a skill is invoked

The target format uses a **Markdown + XML + YAML hybrid**:
- YAML frontmatter for machine-parseable metadata (routing, triggers, dependencies)
- Markdown for human-readable prose and workflows
- XML tags for sections Claude must reliably distinguish during execution
</context>

<input_format>
You will receive agent files from `.claude/agents/` with this structure:

```yaml
---
name: agent-name
description: |
  Use this agent when...
  <example>...</example>
model: sonnet
color: blue
---

[Agent persona and instructions in Markdown]
```

Each agent file contains:
- YAML frontmatter (name, description with examples, model, color)
- KERNEL Framework Compliance section (Task, Context, Constraints, Verification, Reproducibility)
- Multi-phase workflows (Phase -1 context assessment, Phase 0 feedback checks, Phase 1+ execution)
- Parallel execution patterns with context thresholds
- Checklists and validation criteria
- Bibliography & Resources section with external URLs
- Output Standards section
</input_format>

<output_architecture>
Transform each agent into this three-level structure:

## Level 1: Metadata (`index.yaml`)
Lightweight descriptor (~100-150 tokens) for permanent system prompt loading.

```yaml
name: "agent-name"                    # max 64 chars, lowercase with hyphens
version: "1.0.0"
model: "sonnet"                       # Preserve from original
color: "blue"                         # Preserve from original

description: |
  # max 1024 chars - must answer: "When should Claude invoke this skill?"
  # Format as IF-THEN with concrete triggers
  Use this skill IF [specific trigger condition] to [concrete outcome].
  Produces [specific deliverable] at [file path].

triggers:
  - "/slash-command"                  # Explicit command triggers
  - "natural language phrase"         # Conversational triggers
  
examples:                             # Extracted from description <example> blocks
  - context: "User has completed PRD"
    user_says: "Create the software design document"
    agent_action: "Launch architecture-designer to analyze PRD and create SDD"

dependencies:
  - skill: "prerequisite-skill"
    artifact: "loa-grimoire/prd.md"   # What must exist

inputs:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true

outputs:
  - path: "loa-grimoire/sdd.md"
    description: "Software Design Document"
```

## Level 2: Procedural Instructions (`SKILL.md`)
Core execution logic loaded on-demand. Uses MD + XML hybrid with KERNEL framework.

```markdown
---
parallel_threshold: 3000              # Lines before splitting (from original)
timeout_minutes: 60
audit_categories: 5                   # For paranoid-auditor
---

# {Skill Name}

<objective>
Single sentence: what this skill accomplishes and its primary deliverable.
</objective>

<kernel_framework>
## Task (N - Narrow Scope)
[Extracted from original KERNEL section]

## Context (L - Logical Structure)  
[Extracted from original KERNEL section]

## Constraints (E - Explicit)
[Extracted from original KERNEL section - converted to list]

## Verification (E - Easy to Verify)
[Extracted from original KERNEL section]

## Reproducibility (R - Reproducible Results)
[Extracted from original KERNEL section]
</kernel_framework>

<uncertainty_protocol>
- If requirements are ambiguous, ASK for clarification before proceeding
- If source documents are missing, STATE what's missing with `[TBD]` placeholders
- Say "I don't know" when lacking sufficient information
- Document assumptions explicitly when proceeding with incomplete information
</uncertainty_protocol>

<grounding_requirements>
Before generating output:
1. Read and quote from source documents (PRD, SDD, sprint.md)
2. Cite file paths and line numbers: `> From sdd.md:42: "..."`
3. Validate referenced files exist before proceeding
</grounding_requirements>

<workflow>
[Converted from original Phase structure with XML wrapper]
</workflow>

<parallel_execution>
[Extracted parallel splitting logic if present]
</parallel_execution>

<constraints>
[Consolidated from KERNEL Constraints + any additional rules]
</constraints>

<output_format>
[Exact deliverable structure with templates]
</output_format>

<success_criteria>
[SMART criteria derived from KERNEL Verification]
</success_criteria>

<checklists>
[Extracted from original - security, quality, versioning checklists]
</checklists>
```

## Level 3: Resources (`resources/`)
Externalized reference materials and deterministic logic.

```
resources/
├── REFERENCE.md              # Checklists, standards (>500 tokens)
├── BIBLIOGRAPHY.md           # External URLs, meta knowledge base refs
├── templates/
│   └── {output-template}.md  # Report scaffolds
└── scripts/
    ├── validate-inputs.sh    # Input validation
    ├── check-feedback.sh     # Feedback file detection
    └── update-analytics.sh   # Analytics updates
```
</output_architecture>

<format_guidelines>
## Hybrid Format Rules

### YAML Frontmatter
Machine-parseable metadata only:
```yaml
---
name: "sprint-task-implementer"
version: "1.0.0"
parallel_threshold: 8000
---
```

### XML Tags (Shallow, Semantic)
One level deep for sections Claude must parse:
```xml
<!-- GOOD: Semantic section markers -->
<kernel_framework>
## Task (N - Narrow Scope)
Implement sprint tasks from `loa-grimoire/sprint.md`...
</kernel_framework>

<workflow>
## Phase 0: Check Feedback Files
...
</workflow>

<!-- AVOID: Nested XML structures -->
<workflow>
  <phase id="0">
    <step>...</step>
  </phase>
</workflow>
```

### Markdown Within XML
Full Markdown formatting inside XML tags:
```xml
<workflow>
## Phase -1: Context Assessment (CRITICAL)

**Before starting**, assess context size:

```bash
wc -l loa-grimoire/prd.md loa-grimoire/sdd.md 2>/dev/null
```

| Context Size | Threshold | Strategy |
|--------------|-----------|----------|
| SMALL | <3,000 lines | Sequential |
| LARGE | >8,000 lines | Parallel split |
</workflow>
```

### Section Mapping

| Original Loa Section | Target Format | Location |
|---------------------|---------------|----------|
| YAML frontmatter | YAML | `index.yaml` |
| KERNEL Framework | `<kernel_framework>` XML | `SKILL.md` |
| Phase workflows | `<workflow>` XML | `SKILL.md` |
| Parallel execution | `<parallel_execution>` XML | `SKILL.md` |
| Checklists (>20 items) | Markdown | `resources/REFERENCE.md` |
| Bibliography | Markdown | `resources/BIBLIOGRAPHY.md` |
| Bash helpers | Shell scripts | `resources/scripts/` |
| Report templates | Markdown | `resources/templates/` |
</format_guidelines>

<transformation_rules>
## 1. Metadata Extraction

**From YAML frontmatter:**
```yaml
# Original
name: sprint-task-implementer
description: |
  Use this agent when:
  <example>
  Context: A sprint plan has been created...
  user: "We need to implement the tasks from sprint 4"
  assistant: "I'm going to use the Task tool to launch..."
  </example>
model: sonnet
color: yellow
```

**To index.yaml:**
```yaml
name: "sprint-task-implementer"
version: "1.0.0"
model: "sonnet"
color: "yellow"
description: |
  Use this skill IF user invokes `/implement sprint-N` OR mentions implementing 
  sprint tasks to execute tasks with production-quality code. Produces 
  implementation report at loa-grimoire/a2a/sprint-N/reviewer.md.
triggers:
  - "/implement"
  - "implement sprint"
  - "execute sprint tasks"
examples:
  - context: "Sprint plan created, tasks need implementation"
    user_says: "We need to implement the tasks from sprint 4"
    agent_action: "Launch sprint-task-implementer to implement tasks with tests"
```

## 2. KERNEL Framework Preservation

The KERNEL framework (Task, Context, Constraints, Verification, Reproducibility) is **critical for accuracy**. Preserve it in a dedicated XML section:

**Original:**
```markdown
## KERNEL Framework Compliance

**Task (N - Narrow Scope):** Implement sprint tasks from `loa-grimoire/sprint.md`...

**Context (L - Logical Structure):**
- Input: `loa-grimoire/sprint.md` (tasks), `loa-grimoire/prd.md` (requirements)...

**Constraints (E - Explicit):**
- DO NOT start new work without checking for feedback FIRST
- DO NOT assume feedback meaning - ask clarifying questions...
```

**Transformed:**
```xml
<kernel_framework>
## Task (N - Narrow Scope)
Implement sprint tasks from `loa-grimoire/sprint.md` with production-grade code 
and tests. Generate implementation report at `loa-grimoire/a2a/sprint-N/reviewer.md`.

## Context (L - Logical Structure)
- **Input**: `loa-grimoire/sprint.md`, `loa-grimoire/prd.md`, `loa-grimoire/sdd.md`
- **Feedback loop**: `loa-grimoire/a2a/sprint-N/engineer-feedback.md`
- **Integration context**: `loa-grimoire/a2a/integration-context.md` (if exists)
- **Current state**: Sprint plan with acceptance criteria
- **Desired state**: Working, tested implementation + comprehensive report

## Constraints (E - Explicit)
- DO NOT start new work without checking feedback files FIRST
- DO NOT assume feedback meaning—ask clarifying questions
- DO NOT skip tests—comprehensive coverage is non-negotiable
- DO NOT ignore existing codebase patterns
- DO link implementations to source discussions if integration context requires
- DO format commits per org standards if defined

## Verification (E - Easy to Verify)
**Success** = All acceptance criteria met + tests pass + report at expected path

Report MUST include:
- Executive Summary
- Tasks Completed (files/lines, approach, coverage)
- Technical Highlights
- Testing Summary
- Feedback Addressed section (if iteration)

## Reproducibility (R - Reproducible Results)
- Specific assertions: "returns 200 status with user.id field"
- Exact paths: "src/auth/middleware.ts:42-67"
- Exact commands: "npm test -- --coverage --watch=false"
</kernel_framework>
```

## 3. Workflow Phase Extraction

Convert numbered phases to structured XML:

**Original:**
```markdown
### Phase -1: Context Assessment & Parallel Task Splitting

**Before starting any implementation work, assess context size...**

### Phase 0: Check Feedback Files and Integration Context

**Step 1: Check for security audit feedback (HIGHEST PRIORITY)**
Check if `loa-grimoire/a2a/auditor-sprint-feedback.md` exists...
```

**Transformed:**
```xml
<workflow>
## Phase -1: Context Assessment (CRITICAL—DO THIS FIRST)

Before starting work, assess context size to determine parallel splitting:

```bash
wc -l loa-grimoire/prd.md loa-grimoire/sdd.md loa-grimoire/sprint.md 2>/dev/null
```

**Thresholds:**
| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <3,000 | Sequential |
| MEDIUM | 3,000-8,000 | Consider parallel if >3 tasks |
| LARGE | >8,000 | MUST split into parallel |

## Phase 0: Check Feedback Files (BEFORE NEW WORK)

### Step 1: Security Audit Feedback (HIGHEST PRIORITY)
Check `loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md`:
- If exists + "CHANGES_REQUIRED": Address ALL security issues first
- If exists + "APPROVED": Proceed normally
- If missing: No audit yet, proceed normally

### Step 2: Senior Lead Feedback
Check `loa-grimoire/a2a/sprint-N/engineer-feedback.md`:
- If exists + NOT "All good": Address all feedback items
- If exists + "All good": Proceed with new work
- If missing: First implementation, proceed normally

### Step 3: Integration Context
Check `loa-grimoire/a2a/integration-context.md` for:
- Context preservation requirements
- Documentation locations to update
- Commit message formats
- Available MCP tools
</workflow>
```

## 4. Parallel Execution Patterns

Extract parallel splitting logic to dedicated section:

**Original (from paranoid-auditor):**
```markdown
**If MEDIUM/LARGE codebase:**
→ SPLIT into parallel audits by category using this pattern:

Spawn 5 parallel Explore agents, one per audit category:

Task(subagent_type="Explore", prompt="
SECURITY AUDIT for [Project Name]
Focus ONLY on security-related issues...
")
```

**Transformed:**
```xml
<parallel_execution>
## When to Split
- SMALL (<2,000 lines): Sequential audit
- MEDIUM (2,000-5,000): Consider category splitting
- LARGE (>5,000): MUST split into parallel

## Splitting Strategy: By Audit Category

Spawn 5 parallel Explore agents:

### Agent 1: Security Audit
```
Focus ONLY on: Secrets, Auth, Input Validation, Data Privacy, 
Supply Chain, API Security, Infrastructure Security
Files: [auth/, api/, middleware/]
Return: Findings with severity, file:line, PoC, remediation
```

### Agent 2: Architecture Audit
```
Focus ONLY on: Threat Model, SPOFs, Complexity, Scalability, Decentralization
Files: [src/, infrastructure/]
Return: Findings with severity, file:line, remediation
```

### Agent 3: Code Quality Audit
```
Focus ONLY on: Error Handling, Type Safety, Code Smells, Testing, Docs
Files: [src/, tests/]
Return: Findings with severity, file:line, remediation
```

### Agent 4: DevOps Audit
```
Focus ONLY on: Deployment Security, Monitoring, Backup, Access Control
Files: [Dockerfile, terraform/, .github/workflows/]
Return: Findings with severity, file:line, remediation
```

### Agent 5: Blockchain/Crypto Audit (if applicable)
```
Focus ONLY on: Key Management, Transaction Security, Contract Interactions
Files: [contracts/, wallet/, web3/]
Return: Findings OR "N/A - No blockchain code"
```

## Consolidation
1. Collect findings from all agents
2. Deduplicate overlapping findings
3. Sort by severity: CRITICAL → HIGH → MEDIUM → LOW
4. Calculate overall risk level
5. Generate unified report
</parallel_execution>
```

## 5. Checklist Externalization

Move large checklists (>20 items) to `resources/REFERENCE.md`:

**Original (from senior-tech-lead-reviewer):**
```markdown
## Code Review Checklist

### Versioning (SemVer Compliance)
- [ ] package.json version updated appropriately
- [ ] CHANGELOG.md updated with new version entry
...

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation and sanitization
...
```

**Externalized to `resources/REFERENCE.md`:**
```markdown
# Code Review Reference

## SemVer Checklist
- [ ] package.json version updated (MAJOR/MINOR/PATCH)
- [ ] CHANGELOG.md has entry for this version
- [ ] Version bump type matches change type
- [ ] Pre-release versions used correctly (alpha/beta/rc)

## Security Checklist
- [ ] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present
- [ ] Auth/authz implemented correctly
- [ ] No SQL/XSS injection vulnerabilities
- [ ] Dependencies secure (no known CVEs)
- [ ] Error messages don't leak sensitive data

## Performance Checklist
- [ ] No obvious performance issues
- [ ] Database queries optimized
- [ ] Caching used appropriately
- [ ] No memory leaks
- [ ] Resource cleanup in place

[... continue for all categories]
```

**In SKILL.md, reference it:**
```xml
<checklists>
See `resources/REFERENCE.md` for complete checklists:
- SemVer Compliance (6 items)
- Security (12 items)
- Performance (8 items)
- Architecture (10 items)
- Blockchain/Crypto (9 items)

**Red Flags (immediate feedback required):**
- 🚨 Private keys in code
- 🚨 SQL via string concatenation
- 🚨 Empty catch blocks
- 🚨 N+1 queries
</checklists>
```

## 6. Bibliography Externalization

Move all external URLs to `resources/BIBLIOGRAPHY.md`:

**Extracted from original:**
```markdown
# Bibliography & Resources

## Input Documents
- **Sprint Plan**: `loa-grimoire/sprint.md`
- **SDD**: `loa-grimoire/sdd.md`
- **PRD**: `loa-grimoire/prd.md`

## Framework Documentation
- Loa Overview: https://github.com/0xHoneyJar/loa/blob/main/CLAUDE.md
- Workflow Process: https://github.com/0xHoneyJar/loa/blob/main/PROCESS.md

## Security Standards
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- OWASP API Security: https://owasp.org/www-project-api-security/
- CWE Top 25: https://cwe.mitre.org/top25/

## Organizational Knowledge Base
**Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge

Essential resources:
- Technical Debt: .../debt/INDEX.md
- ADRs: .../decisions/INDEX.md
- Knowledge Captures: .../knowledge/
- Smart Contracts: .../contracts/REGISTRY.md

**AI Navigation**: .../blob/main/.meta/RETRIEVAL_GUIDE.md
```

## 7. Script Extraction

Move deterministic bash logic to `resources/scripts/`:

**`resources/scripts/check-feedback.sh`:**
```bash
#!/bin/bash
# Check for pending feedback files
# Usage: ./check-feedback.sh sprint-1

SPRINT_ID="$1"
A2A_DIR="loa-grimoire/a2a/${SPRINT_ID}"

# Validate input
if [[ ! "$SPRINT_ID" =~ ^sprint-[0-9]+$ ]]; then
    echo "ERROR: Invalid sprint ID format" >&2
    exit 1
fi

# Check audit feedback first (higher priority)
AUDIT_FILE="${A2A_DIR}/auditor-sprint-feedback.md"
if [ -f "$AUDIT_FILE" ]; then
    if grep -q "CHANGES_REQUIRED" "$AUDIT_FILE"; then
        echo "AUDIT_FEEDBACK_PENDING"
        exit 0
    fi
fi

# Check engineer feedback
FEEDBACK_FILE="${A2A_DIR}/engineer-feedback.md"
if [ -f "$FEEDBACK_FILE" ]; then
    if ! grep -q "All good" "$FEEDBACK_FILE"; then
        echo "REVIEW_FEEDBACK_PENDING"
        exit 0
    fi
fi

echo "NO_PENDING_FEEDBACK"
```

**`resources/scripts/assess-context.sh`:**
```bash
#!/bin/bash
# Assess context size for parallel splitting decision
# Usage: ./assess-context.sh [threshold]

THRESHOLD=${1:-3000}

TOTAL=$(wc -l loa-grimoire/prd.md loa-grimoire/sdd.md \
        loa-grimoire/sprint.md loa-grimoire/a2a/*.md 2>/dev/null | \
        tail -1 | awk '{print $1}')

if [ "$TOTAL" -lt "$THRESHOLD" ]; then
    echo "SMALL"
elif [ "$TOTAL" -lt $((THRESHOLD * 2)) ]; then
    echo "MEDIUM"
else
    echo "LARGE"
fi
```

## 8. Guardrail Injection

Add to every SKILL.md if not present:

```xml
<uncertainty_protocol>
- If requirements are ambiguous, ASK for clarification before proceeding
- Say "I don't know" when lacking sufficient information
- State assumptions explicitly when proceeding with incomplete info
- Flag areas needing product/architecture input in report
</uncertainty_protocol>

<grounding_requirements>
Before generating output:
1. Read and extract direct quotes from source documents
2. Cite file paths and line numbers: `> From sprint.md:47: "..."`
3. Validate referenced files exist before proceeding
4. Reference specific acceptance criteria by ID
</grounding_requirements>

<citation_requirements>
- All findings include file paths and line numbers
- Quote source text before analysis
- Reference CVE/CWE/OWASP for security issues
- Link to external docs with absolute URLs
</citation_requirements>
```
</transformation_rules>

<loa_patterns>
## Patterns to Preserve

### A2A Communication Flow
```
/implement sprint-N
    ├── Creates: loa-grimoire/a2a/sprint-N/reviewer.md
    └── Checks: auditor-sprint-feedback.md (FIRST), engineer-feedback.md
    
/review-sprint sprint-N
    ├── Reads: reviewer.md
    └── Creates: engineer-feedback.md ("All good" OR detailed feedback)
    
/audit-sprint sprint-N  
    ├── Requires: "All good" in engineer-feedback.md
    ├── Creates: auditor-sprint-feedback.md
    └── On approval: Creates COMPLETED marker
```

### Integration Context Pattern
All agents check `loa-grimoire/a2a/integration-context.md` for:
- Knowledge sources (Linear LEARNINGS, past PRDs)
- User personas (existing docs to reference)
- Documentation locations (Product Home, changelogs)
- Context linking (Discord threads, Linear issues)
- Commit formats ("[LIN-123] Description")
- Available MCP tools

### Verdict Patterns
- **Senior Lead**: "All good" (approval) or detailed feedback
- **Sprint Audit**: "CHANGES_REQUIRED" or "APPROVED - LETS FUCKING GO"
- **Deployment Audit**: "CHANGES_REQUIRED" or "APPROVED - LET'S FUCKING GO"

### Context Size Thresholds (by agent)
| Agent | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| sprint-task-implementer | <3,000 | 3,000-8,000 | >8,000 |
| senior-tech-lead-reviewer | <3,000 | 3,000-6,000 | >6,000 |
| paranoid-auditor | <2,000 | 2,000-5,000 | >5,000 |
| devops-crypto-architect | <2,000 | 2,000-5,000 | >5,000 |

### SemVer Requirements
Agents that modify code (sprint-task-implementer, devops-crypto-architect) must:
1. Update package.json version
2. Update CHANGELOG.md
3. Use correct bump type (MAJOR/MINOR/PATCH)
4. Tag releases (vX.Y.Z format)
</loa_patterns>

<example_transformation>
## Full Example: paranoid-auditor

### Original Structure (excerpted)
```markdown
---
name: paranoid-auditor
description: Use this agent proactively after completing significant work...
model: sonnet
color: red
---

# Paranoid Cypherpunk Auditor Agent

## KERNEL Framework Compliance
**Task (N - Narrow Scope):** Perform comprehensive security and quality audit...
**Context (L - Logical Structure):**
- Input: Entire codebase...
- Audit types: Codebase audit, Deployment audit, Sprint audit
...

## Context Assessment & Parallel Audit Splitting
**CRITICAL: Before starting any audit...**
...

## Your Audit Methodology
### 1. Security Audit (Highest Priority)
**Secrets & Credentials:**
- [ ] Are secrets hardcoded anywhere? (CRITICAL)
...

## Bibliography & Resources
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
...
```

### Transformed Structure

```
agents/paranoid-auditor/
├── index.yaml
├── SKILL.md
└── resources/
    ├── REFERENCE.md           # Full 5-category checklists
    ├── BIBLIOGRAPHY.md        # All external URLs
    ├── templates/
    │   ├── audit-report.md
    │   └── sprint-audit-feedback.md
    └── scripts/
        ├── assess-codebase-size.sh
        └── check-audit-prerequisites.sh
```

### index.yaml
```yaml
name: "paranoid-auditor"
version: "1.0.0"
model: "sonnet"
color: "red"

description: |
  Use this skill IF user needs security/quality audit of code, infrastructure, 
  or sprint implementation. Invoke proactively after significant work completion.
  
  Three modes:
  - Codebase audit (/audit) → SECURITY-AUDIT-REPORT.md
  - Deployment audit (/audit-deployment) → loa-grimoire/a2a/deployment-feedback.md
  - Sprint audit (/audit-sprint) → loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md

triggers:
  - "/audit"
  - "/audit-deployment"
  - "/audit-sprint"
  - "security audit"
  - "review for vulnerabilities"

examples:
  - context: "Sprint implementation complete, senior lead approved"
    user_says: "Run security audit on sprint 1"
    agent_action: "Launch paranoid-auditor in sprint audit mode"
  - context: "Deployment infrastructure created"
    user_says: "Audit our deployment setup"
    agent_action: "Launch paranoid-auditor in deployment audit mode"

inputs:
  - name: "audit_mode"
    type: "enum"
    values: ["codebase", "deployment", "sprint"]
    required: true
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: false  # Only for sprint mode

outputs:
  - path: "SECURITY-AUDIT-REPORT.md"
    condition: "audit_mode == codebase"
  - path: "loa-grimoire/a2a/deployment-feedback.md"
    condition: "audit_mode == deployment"
  - path: "loa-grimoire/a2a/sprint-{id}/auditor-sprint-feedback.md"
    condition: "audit_mode == sprint"
```

### SKILL.md
```markdown
---
parallel_threshold: 2000
audit_categories: 5
timeout_minutes: 45
---

# Paranoid Cypherpunk Auditor

<objective>
Perform comprehensive security and quality audit of code, architecture, 
infrastructure, or sprint implementations. Generate prioritized findings 
with actionable remediation at the appropriate output path.
</objective>

<kernel_framework>
## Task (N - Narrow Scope)
Perform comprehensive security and quality audit. Generate reports at:
- Codebase: `SECURITY-AUDIT-REPORT.md` + `loa-grimoire/audits/YYYY-MM-DD/`
- Deployment: `loa-grimoire/a2a/deployment-feedback.md`
- Sprint: `loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md`

## Context (L - Logical Structure)
- **Input**: Entire codebase, configs, infrastructure code
- **Scope**: 5 categories—Security, Architecture, Code Quality, DevOps, Blockchain
- **Current state**: Code potentially containing vulnerabilities
- **Desired state**: Comprehensive report with CRITICAL/HIGH/MEDIUM/LOW findings

## Constraints (E - Explicit)
- DO NOT skip reading actual code—audit files, not just documentation
- DO NOT approve insecure code—be brutally honest
- DO NOT give vague findings—include file:line, PoC, specific remediation
- DO NOT audit without systematic checklist—follow all 5 categories
- DO create dated directory for remediation: `loa-grimoire/audits/YYYY-MM-DD/`
- DO use exact CVE/CWE/OWASP references
- DO prioritize by exploitability and impact
- DO think like an attacker

## Verification (E - Easy to Verify)
**Success** = Comprehensive report with:
- Executive Summary + Overall Risk Level
- Key Statistics (count by severity)
- Issues by priority with: Severity, Component (file:line), Description, 
  Impact, PoC, Remediation, References
- Security Checklist Status (✅/❌)
- Verdict: CHANGES_REQUIRED or APPROVED

## Reproducibility (R - Reproducible Results)
- Exact file:line references, not "auth is insecure"
- Specific PoC: "Payload: ' OR 1=1-- exploits L67"
- Cite standards: "Violates OWASP A03:2021, CWE-89"
- Exact remediation: "Replace L67 with: db.query('SELECT...', [userId])"
</kernel_framework>

<uncertainty_protocol>
- If code purpose is unclear, state assumption and flag for verification
- If security context is ambiguous (internal vs external), ask
- Say "Unable to assess" for obfuscated or inaccessible code
- Document scope limitations in report
</uncertainty_protocol>

<grounding_requirements>
Before auditing:
1. Read all files in scope—don't trust documentation alone
2. Quote vulnerable code directly in findings
3. Verify assumptions by reading actual implementation
4. Cross-reference with existing technical debt registry
</grounding_requirements>

<workflow>
## Phase -1: Context Assessment (CRITICAL)

Assess codebase size:
```bash
./resources/scripts/assess-codebase-size.sh
```

| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <2,000 | Sequential (all 5 categories) |
| MEDIUM | 2,000-5,000 | Consider category splitting |
| LARGE | >5,000 | MUST split into parallel |

## Phase 0: Prerequisites Check

**For Sprint Audit:**
1. Verify sprint directory exists
2. Verify "All good" in `engineer-feedback.md` (senior lead approval required)
3. If not approved, STOP: "Sprint must be approved by senior lead first"

**For Deployment Audit:**
1. Verify `loa-grimoire/deployment/` exists
2. Read `deployment-report.md` for context if exists

## Phase 1: Systematic Audit

Execute audit by category (sequential or parallel per Phase -1):
1. **Security Audit** - See `resources/REFERENCE.md` §Security
2. **Architecture Audit** - See `resources/REFERENCE.md` §Architecture
3. **Code Quality Audit** - See `resources/REFERENCE.md` §CodeQuality
4. **DevOps Audit** - See `resources/REFERENCE.md` §DevOps
5. **Blockchain Audit** - See `resources/REFERENCE.md` §Blockchain (if applicable)

## Phase 2: Report Generation

Use template from `resources/templates/audit-report.md`

## Phase 3: Verdict

**Sprint/Deployment Audit:**
- If ANY CRITICAL or HIGH issues: "CHANGES_REQUIRED"
- If only MEDIUM/LOW: "APPROVED - LETS FUCKING GO" (but note improvements)

**Codebase Audit:**
- Overall Risk Level: CRITICAL/HIGH/MEDIUM/LOW
- Recommendations: Immediate (24h), Short-term (1wk), Long-term (1mo)
</workflow>

<parallel_execution>
## Splitting Strategy: By Audit Category

For LARGE codebases, spawn 5 parallel Explore agents:

1. **Security Agent**: Auth, secrets, injection, privacy, supply chain
2. **Architecture Agent**: Threat model, SPOFs, complexity, scalability
3. **Code Quality Agent**: Error handling, types, smells, testing
4. **DevOps Agent**: Deployment, monitoring, backup, access control
5. **Blockchain Agent**: Keys, transactions, contracts (or "N/A")

**Consolidation:**
1. Collect all findings
2. Deduplicate overlaps
3. Sort: CRITICAL → HIGH → MEDIUM → LOW
4. Calculate overall risk from highest severity
5. Generate unified report
</parallel_execution>

<output_format>
See `resources/templates/audit-report.md` for full structure.

Key sections:
- Executive Summary (2-3 paragraphs)
- Overall Risk Level + Key Statistics
- Critical Issues (fix immediately)
- High Priority Issues (fix before production)
- Medium/Low Priority Issues
- Security Checklist Status
- Threat Model Summary
- Verdict and Next Steps
</output_format>

<success_criteria>
- **Specific**: Every finding has file:line reference
- **Measurable**: Zero false positives for CRITICAL severity
- **Achievable**: Complete audit within context limits (split if needed)
- **Relevant**: Findings map to OWASP/CWE standards
- **Time-bound**: 45 minutes max; request extension if needed
</success_criteria>
```

### resources/REFERENCE.md (excerpted)
```markdown
# Audit Checklists

## §Security

### Secrets & Credentials
- [ ] No hardcoded secrets (CRITICAL if found)
- [ ] API tokens not logged or in error messages
- [ ] .gitignore covers secret file patterns
- [ ] Secrets rotation policy exists
- [ ] Secrets encrypted at rest
- [ ] Secrets backup/recovery strategy

### Authentication & Authorization
- [ ] Auth required for all sensitive operations
- [ ] Authorization checks server-side
- [ ] No privilege escalation paths
- [ ] Session tokens scoped and time-limited
- [ ] Token theft/replay protection
- [ ] API tokens use least privilege

[... continue for all 5 categories, ~150 items total]
```

### resources/templates/audit-report.md
```markdown
# Security & Quality Audit Report

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** {DATE}
**Scope:** {SCOPE}
**Methodology:** Systematic 5-category review

---

## Executive Summary

{2-3 paragraphs}

**Overall Risk Level:** {CRITICAL/HIGH/MEDIUM/LOW}

**Key Statistics:**
- Critical: {N}
- High: {N}
- Medium: {N}
- Low: {N}

---

## Critical Issues

### [CRITICAL-001] {Title}
**Severity:** CRITICAL
**Component:** `{file}:{line}`
**Description:** {description}
**Impact:** {what could happen}
**Proof of Concept:** {how to exploit}
**Remediation:** {specific fix}
**References:** {CVE/CWE/OWASP}

---

[Continue for HIGH, MEDIUM, LOW...]

---

## Security Checklist Status

### Secrets & Credentials
- [✅/❌] No hardcoded secrets
- [✅/❌] Secrets in gitignore
...

---

## Verdict

{CHANGES_REQUIRED / APPROVED - LETS FUCKING GO}

**Next Steps:**
1. {immediate action}
2. {short-term action}
```
</example_transformation>

<output_instructions>
For each Loa agent file, produce:

1. **File tree** showing new structure
2. **`index.yaml`** — Complete metadata
3. **`SKILL.md`** — Full procedural instructions with XML sections
4. **`resources/REFERENCE.md`** — Externalized checklists (if >20 items)
5. **`resources/BIBLIOGRAPHY.md`** — All external URLs
6. **`resources/templates/`** — Output scaffolds
7. **`resources/scripts/`** — Extracted bash logic
8. **Migration notes:**
   - Token savings estimate
   - Breaking changes
   - Guardrails added
   - Content moved with rationale

**File path format:**
```
agents/{skill-name}/
├── index.yaml
├── SKILL.md
└── resources/
    ├── REFERENCE.md
    ├── BIBLIOGRAPHY.md
    ├── templates/
    │   └── {template}.md
    └── scripts/
        └── {script}.sh
```
</output_instructions>

<edge_cases>
- **No KERNEL section**: Create one from implicit task/constraints in the prose
- **No parallel execution pattern**: Add if agent handles >3,000 lines context
- **Minimal checklists**: Keep inline if <20 items
- **No Bibliography section**: Create from inline URLs found in document
- **Circular dependencies**: Document in migration notes; suggest resolution
- **MCP-dependent features**: Note in `index.yaml` dependencies
</edge_cases>

<priority_order>
When constraints conflict:
1. **Accuracy** — Preserve KERNEL framework completely
2. **Clarity** — Maintain all guardrails and uncertainty protocols
3. **Efficiency** — Externalize only after accuracy/clarity satisfied
4. **Consistency** — Follow Loa conventions even if suboptimal
</priority_order>

<self_check>
Before finalizing each agent:
- [ ] `index.yaml` description <1024 chars, answers "when to invoke"
- [ ] `SKILL.md` has: kernel_framework, uncertainty_protocol, grounding_requirements, workflow, output_format, success_criteria
- [ ] KERNEL framework preserved completely (all 5 sections)
- [ ] Parallel execution thresholds match original
- [ ] All file paths match Loa conventions
- [ ] Feedback loop logic preserved (audit → review priority)
- [ ] Bibliography URLs are absolute
- [ ] Checklists >20 items externalized
- [ ] Scripts handle errors gracefully
</self_check>