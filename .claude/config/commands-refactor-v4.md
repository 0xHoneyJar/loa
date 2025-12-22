# Loa Commands → Modular Command Architecture Refactoring Prompt

<context>
You are refactoring Loa's slash commands from single-file definitions (`.claude/commands/*.md`) into a modular architecture that aligns with the refactored Agent Skills system.

Loa has 13 slash commands that trigger 8 specialized agents. The commands need to:
1. Work with the new three-level agent architecture (`agents-v2/`)
2. Maintain identical user-facing behavior (`/implement sprint-1` still works)
3. Route to the correct agent skill with proper context
4. Support the new benchmarking and validation workflows

**Command Philosophy**:
- Commands are **thin routing layers** — they invoke agents, not implement logic
- Commands handle **argument parsing** and **validation**
- Commands provide **context loading** hints to agents
- The actual work happens in the agent's `SKILL.md`
</context>

<input_format>
You will receive command files from `.claude/commands/` with this structure:

```markdown
---
name: command-name
description: Brief description of the command
arguments:
  - name: arg_name
    description: What this argument does
    required: true/false
---

[Command expansion text - instructions for what happens when command is invoked]
```

Commands typically:
- Reference agents to invoke via Task tool
- Include argument placeholders like `$ARGUMENTS.sprint_id`
- Contain inline instructions that should be in the agent
- May have validation logic that should be in scripts
</input_format>

<output_architecture>
Transform each command into this structure:

## Command File (`commands-v2/{command-name}.md`)

```markdown
---
name: "{command-name}"
version: "1.0.0"
description: |
  [User-facing description - what the command does]
  
arguments:
  - name: "{arg_name}"
    type: "string"
    pattern: "^sprint-[0-9]+$"  # Validation regex
    required: true
    description: "What this argument is for"

agent: "{agent-name}"              # Which agent to invoke
agent_path: "agents-v2/{agent}/"   # Path to refactored agent

context_files:                      # Files agent should read
  - path: "loa-grimoire/prd.md"
    required: false
  - path: "loa-grimoire/sdd.md"
    required: true
  - path: "loa-grimoire/sprint.md"
    required: true

pre_flight:                         # Checks before invoking agent
  - check: "file_exists"
    path: "loa-grimoire/sprint.md"
    error: "Sprint plan not found. Run /sprint-plan first."
  - check: "pattern_match"
    value: "$ARGUMENTS.sprint_id"
    pattern: "^sprint-[0-9]+$"
    error: "Invalid sprint ID. Expected format: sprint-N"

mode:                               # Execution mode
  default: "foreground"
  allow_background: true
---

# {Command Name}

## Purpose
[One sentence describing what this command accomplishes]

## Invocation
Launch the `{agent-name}` agent to [action].

## Context
The agent will:
1. Read context files listed above
2. Execute workflow from `agents-v2/{agent}/SKILL.md`
3. Produce output at [expected path]

## Arguments
- `$ARGUMENTS.{arg_name}`: [How it's used]

## Expected Outcome
[What files/artifacts are produced]
```

## Validation Script (`commands-v2/scripts/validate-{command}.sh`)

Extract validation logic to reusable scripts:

```bash
#!/bin/bash
# validate-{command}.sh
# Pre-flight validation for /{command-name}

set -e

# Argument validation
validate_sprint_id() {
    local sprint_id="$1"
    if [[ ! "$sprint_id" =~ ^sprint-[0-9]+$ ]]; then
        echo "ERROR: Invalid sprint ID '$sprint_id'. Expected format: sprint-N" >&2
        exit 1
    fi
}

# File existence checks
check_prerequisites() {
    local required_files=("$@")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "ERROR: Required file not found: $file" >&2
            exit 1
        fi
    done
}

# Main validation
main() {
    case "$1" in
        --sprint-id)
            validate_sprint_id "$2"
            ;;
        --check-files)
            shift
            check_prerequisites "$@"
            ;;
        *)
            echo "Usage: $0 --sprint-id <id> | --check-files <file1> [file2...]"
            exit 1
            ;;
    esac
}

main "$@"
```
</output_architecture>

<transformation_rules>
## 1. Extract Command Metadata

**From original:**
```markdown
---
name: implement
description: Implement sprint tasks
arguments:
  - name: sprint_id
    description: The sprint to implement (e.g., sprint-1)
    required: true
---
```

**To new format:**
```yaml
---
name: "implement"
version: "1.0.0"
description: |
  Execute sprint tasks with production-quality code and tests.
  Creates implementation report at loa-grimoire/a2a/sprint-N/reviewer.md.

arguments:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true
    description: "Sprint identifier (e.g., sprint-1, sprint-2)"
    examples: ["sprint-1", "sprint-2", "sprint-10"]

agent: "sprint-task-implementer"
agent_path: "agents-v2/sprint-task-implementer/"
```

## 2. Extract Pre-Flight Checks

Move validation logic from command body to structured `pre_flight` section:

**Original (inline):**
```markdown
Before implementing:
1. Validate sprint name format (must be `sprint-N`)
2. Check that sprint.md exists
3. Verify the sprint has tasks assigned
```

**New (structured):**
```yaml
pre_flight:
  - check: "pattern_match"
    value: "$ARGUMENTS.sprint_id"
    pattern: "^sprint-[0-9]+$"
    error: "Invalid sprint ID. Expected: sprint-N (e.g., sprint-1)"
  
  - check: "file_exists"
    path: "loa-grimoire/sprint.md"
    error: "Sprint plan not found. Run /sprint-plan first."
  
  - check: "content_contains"
    path: "loa-grimoire/sprint.md"
    pattern: "$ARGUMENTS.sprint_id"
    error: "Sprint $ARGUMENTS.sprint_id not found in sprint.md"
```

## 3. Define Context Files

Explicitly list files the agent needs to read:

```yaml
context_files:
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and MCP tools"
  
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for grounding"
  
  - path: "loa-grimoire/sdd.md"
    required: true
    purpose: "Architecture decisions"
  
  - path: "loa-grimoire/sprint.md"
    required: true
    purpose: "Sprint tasks and acceptance criteria"
  
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/auditor-sprint-feedback.md"
    required: false
    purpose: "Security audit feedback (checked FIRST)"
  
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    required: false
    purpose: "Senior lead feedback"
```

## 4. Specify Execution Mode

```yaml
mode:
  default: "foreground"           # Interactive by default
  allow_background: true          # Can append "background" to run as subagent
  parallel_threshold: 8000        # Lines before agent considers splitting
```

## 5. Define Expected Outputs

```yaml
outputs:
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    description: "Implementation report for senior review"
    always: true
  
  - path: "loa-grimoire/a2a/index.md"
    description: "Sprint index updated with status"
    always: true
  
  - path: "app/src/**/*"
    description: "Implementation code"
    always: true
```

## 6. Slim Down Command Body

The command body should be minimal — just routing:

**Before (fat command):**
```markdown
You are a sprint task implementer. Read the sprint plan at loa-grimoire/sprint.md.
First check for feedback files. If audit feedback exists with CHANGES_REQUIRED,
address those issues first. Then check engineer feedback...
[500+ lines of instructions]
```

**After (thin command):**
```markdown
# Implement Sprint

## Purpose
Execute sprint tasks with production-quality code and comprehensive tests.

## Invocation
Launch the `sprint-task-implementer` agent with sprint context.

## Agent Instructions
See: `agents-v2/sprint-task-implementer/SKILL.md`

## Arguments
- `$ARGUMENTS.sprint_id`: Target sprint (e.g., sprint-1)

## Workflow
1. Pre-flight validation (see pre_flight above)
2. Load context files
3. Agent executes SKILL.md workflow
4. Outputs created at expected paths
```
</transformation_rules>

<command_mapping>
## Loa Commands → Agents

| Command | Agent | Primary Output |
|---------|-------|----------------|
| `/plan-and-analyze` | prd-architect | `loa-grimoire/prd.md` |
| `/architect` | architecture-designer | `loa-grimoire/sdd.md` |
| `/sprint-plan` | sprint-planner | `loa-grimoire/sprint.md` |
| `/implement {sprint}` | sprint-task-implementer | `loa-grimoire/a2a/{sprint}/reviewer.md` |
| `/review-sprint {sprint}` | senior-tech-lead-reviewer | `loa-grimoire/a2a/{sprint}/engineer-feedback.md` |
| `/audit-sprint {sprint}` | paranoid-auditor | `loa-grimoire/a2a/{sprint}/auditor-sprint-feedback.md` |
| `/audit` | paranoid-auditor | `SECURITY-AUDIT-REPORT.md` |
| `/audit-deployment` | paranoid-auditor | `loa-grimoire/a2a/deployment-feedback.md` |
| `/deploy-production` | devops-crypto-architect | `loa-grimoire/deployment/*` |
| `/translate {doc} for {audience}` | devrel-translator | Translated document |
| `/setup` | (special) | `.loa-setup-complete` |
| `/feedback` | (special) | Linear issue |
| `/update` | (special) | Git merge |

## Special Commands (No Agent)

These commands don't invoke agents — they run scripts directly:

- `/setup` — First-time configuration wizard
- `/feedback` — Developer feedback survey → Linear
- `/update` — Pull upstream Loa updates
</command_mapping>

<example_transformation>
## Example: `/implement` Command

### Original (`.claude/commands/implement.md`)
```markdown
---
name: implement
description: Implement sprint tasks with production-quality code
arguments:
  - name: sprint_id
    description: The sprint to implement (e.g., sprint-1)
    required: true
---

You are launching the sprint-task-implementer agent.

**Sprint to implement**: $ARGUMENTS.sprint_id

The agent should:
1. Validate the sprint ID format (sprint-N)
2. Create the A2A directory if needed
3. Check for audit feedback FIRST
4. Then check for engineer feedback
5. Implement all tasks from sprint.md
6. Write tests with high coverage
7. Generate report at loa-grimoire/a2a/{sprint}/reviewer.md
8. Update analytics

See the full agent definition at .claude/agents/sprint-task-implementer.md
```

### Refactored (`commands-v2/implement.md`)
```markdown
---
name: "implement"
version: "1.0.0"
description: |
  Execute sprint tasks with production-quality code and tests.
  Automatically checks for and addresses audit/review feedback before new work.

arguments:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true
    description: "Sprint to implement (e.g., sprint-1)"
    examples: ["sprint-1", "sprint-2"]

agent: "sprint-task-implementer"
agent_path: "agents-v2/sprint-task-implementer/"

context_files:
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
  - path: "loa-grimoire/prd.md"
    required: true
  - path: "loa-grimoire/sdd.md"
    required: true
  - path: "loa-grimoire/sprint.md"
    required: true
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/auditor-sprint-feedback.md"
    required: false
    priority: 1  # Check FIRST
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    required: false
    priority: 2  # Check SECOND

pre_flight:
  - check: "pattern_match"
    value: "$ARGUMENTS.sprint_id"
    pattern: "^sprint-[0-9]+$"
    error: "Invalid sprint ID. Expected format: sprint-N"
  
  - check: "file_exists"
    path: "loa-grimoire/sprint.md"
    error: "Sprint plan not found. Run /sprint-plan first."
  
  - check: "file_exists"
    path: "loa-grimoire/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."
  
  - check: "file_exists"
    path: "loa-grimoire/sdd.md"
    error: "SDD not found. Run /architect first."

outputs:
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/"
    type: "directory"
    created: true
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    type: "file"
    description: "Implementation report"
  - path: "loa-grimoire/a2a/index.md"
    type: "file"
    description: "Sprint index (updated)"

mode:
  default: "foreground"
  allow_background: true
---

# Implement Sprint

## Purpose
Execute assigned sprint tasks with production-quality code, comprehensive tests, and detailed implementation report.

## Invocation
```
/implement sprint-1
/implement sprint-1 background
```

## Agent
Launches `sprint-task-implementer` from `agents-v2/sprint-task-implementer/`.

## Workflow
1. **Pre-flight**: Validate sprint ID and check prerequisites
2. **Context Loading**: Agent reads files in priority order
3. **Feedback Check**: Audit feedback (priority 1) → Engineer feedback (priority 2)
4. **Implementation**: Execute tasks from sprint.md
5. **Report Generation**: Create reviewer.md with full details
6. **Index Update**: Update loa-grimoire/a2a/index.md

## Arguments
- `sprint_id`: Which sprint to implement (e.g., `sprint-1`)
- `background` (optional): Run as subagent for parallel execution

## Outputs
- `loa-grimoire/a2a/{sprint_id}/reviewer.md` — Implementation report
- `loa-grimoire/a2a/index.md` — Updated sprint index
- `app/src/**/*` — Implementation code and tests

## Error Handling
| Error | Cause | Resolution |
|-------|-------|------------|
| "Invalid sprint ID" | Wrong format | Use `sprint-N` format |
| "Sprint plan not found" | Missing sprint.md | Run `/sprint-plan` first |
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |
```

### Validation Script (`commands-v2/scripts/validate-implement.sh`)
```bash
#!/bin/bash
# validate-implement.sh
# Pre-flight validation for /implement command

set -e

SPRINT_ID="$1"

# Validate sprint ID format
if [[ ! "$SPRINT_ID" =~ ^sprint-[0-9]+$ ]]; then
    echo "ERROR: Invalid sprint ID '$SPRINT_ID'" >&2
    echo "Expected format: sprint-N (e.g., sprint-1, sprint-2)" >&2
    exit 1
fi

# Check required files
REQUIRED_FILES=(
    "loa-grimoire/sprint.md"
    "loa-grimoire/prd.md"
    "loa-grimoire/sdd.md"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required file not found: $file" >&2
        case "$file" in
            *prd.md) echo "Run /plan-and-analyze first." >&2 ;;
            *sdd.md) echo "Run /architect first." >&2 ;;
            *sprint.md) echo "Run /sprint-plan first." >&2 ;;
        esac
        exit 1
    fi
done

# Check if sprint exists in sprint.md
if ! grep -q "## $SPRINT_ID\|## Sprint ${SPRINT_ID#sprint-}" "loa-grimoire/sprint.md"; then
    echo "ERROR: $SPRINT_ID not found in sprint.md" >&2
    exit 1
fi

echo "OK: Pre-flight validation passed for $SPRINT_ID"
exit 0
```
</example_transformation>

<special_commands>
## Special Commands (Non-Agent)

These commands don't invoke agents — they run workflows directly.

### `/setup`
```yaml
---
name: "setup"
version: "1.0.0"
description: "First-time Loa configuration wizard"
type: "wizard"  # Not an agent invocation

steps:
  - name: "welcome"
    action: "display"
    content: "Welcome to Loa! Let's get you set up..."
  
  - name: "detect_mcp"
    action: "script"
    script: "scripts/detect-mcp-servers.sh"
  
  - name: "configure_mcp"
    action: "prompt"
    for_each: "missing_mcp_servers"
  
  - name: "init_analytics"
    action: "script"
    script: "scripts/init-analytics.sh"
  
  - name: "create_marker"
    action: "write_file"
    path: ".loa-setup-complete"

outputs:
  - ".loa-setup-complete"
  - "loa-grimoire/analytics/usage.json"
---
```

### `/feedback`
```yaml
---
name: "feedback"
version: "1.0.0"
description: "Collect developer feedback and post to Linear"
type: "survey"

requires:
  - mcp: "linear"
    error: "Linear MCP not configured. Feedback will be saved locally."

steps:
  - name: "check_pending"
    action: "script"
    script: "scripts/check-pending-feedback.sh"
  
  - name: "survey"
    action: "prompt_sequence"
    questions:
      - "What would you change about Loa?"
      - "What did you love about using Loa?"
      - "Rate this build vs other approaches (1-5)"
      - "How comfortable are you with the process? (A-E)"
  
  - name: "submit"
    action: "mcp_call"
    server: "linear"
    operation: "create_issue"
    fallback: "save_local"

outputs:
  - "Linear issue (or loa-grimoire/analytics/pending-feedback.json)"
---
```

### `/update`
```yaml
---
name: "update"
version: "1.0.0"
description: "Pull latest Loa framework updates"
type: "git_operation"

pre_flight:
  - check: "git_clean"
    error: "Working tree has uncommitted changes. Commit or stash first."
  
  - check: "remote_exists"
    remote: "loa"
    fallback_remote: "upstream"
    error: "No 'loa' or 'upstream' remote found."

steps:
  - name: "fetch"
    action: "git_fetch"
    remote: "loa"
    branch: "main"
  
  - name: "preview"
    action: "display"
    content: "Show commits and files that will change"
  
  - name: "confirm"
    action: "prompt"
    message: "Proceed with merge?"
  
  - name: "merge"
    action: "git_merge"
    remote: "loa"
    branch: "main"
  
  - name: "conflict_guidance"
    action: "conditional"
    if: "merge_conflicts"
    content: "Resolution guidance for .claude/ vs other files"
---
```
</special_commands>

<new_commands>
## New Commands for Refactored Architecture

### `/benchmark-agent`
```yaml
---
name: "benchmark-agent"
version: "1.0.0"
description: |
  Run validation tests against an agent to verify functionality.
  Compares original vs refactored agent behavior.

arguments:
  - name: "agent_name"
    type: "string"
    required: true
    description: "Agent to benchmark"
    examples: ["prd-architect", "sprint-task-implementer"]
  
  - name: "mode"
    type: "enum"
    values: ["baseline", "test", "compare"]
    required: false
    default: "compare"
    description: "Benchmark mode"

agent: "benchmark-runner"
agent_path: "agents-v2/benchmark-runner/"

context_files:
  - path: "tests/agents/$ARGUMENTS.agent_name/test-cases.yaml"
    required: true
  - path: "tests/agents/$ARGUMENTS.agent_name/baseline-metrics.json"
    required: false

pre_flight:
  - check: "directory_exists"
    path: "tests/agents/$ARGUMENTS.agent_name"
    error: "No test cases found for $ARGUMENTS.agent_name"
  
  - check: "file_exists"
    path: "tests/agents/$ARGUMENTS.agent_name/test-cases.yaml"
    error: "test-cases.yaml not found"

outputs:
  - path: "tests/agents/$ARGUMENTS.agent_name/results/"
    type: "directory"
  - path: "tests/agents/$ARGUMENTS.agent_name/results/{timestamp}-report.md"
    type: "file"
---

# Benchmark Agent

## Purpose
Run validation tests against an agent and generate comparison report.

## Invocation
```
/benchmark-agent prd-architect
/benchmark-agent sprint-task-implementer --mode baseline
/benchmark-agent paranoid-auditor --mode compare
```

## Modes
- `baseline`: Capture metrics from original agent
- `test`: Run tests against refactored agent
- `compare`: Run both and generate comparison report (default)
```

### `/validate-refactor`
```yaml
---
name: "validate-refactor"
version: "1.0.0"
description: |
  Validate a refactored agent structure before deployment.
  Checks structure, KERNEL compliance, and required sections.

arguments:
  - name: "agent_name"
    type: "string"
    required: true

type: "validation"  # Runs checks, not agent

checks:
  - name: "structure"
    script: "scripts/validate-structure.sh"
    args: ["$ARGUMENTS.agent_name"]
  
  - name: "kernel_compliance"
    script: "scripts/validate-kernel.sh"
    args: ["$ARGUMENTS.agent_name"]
  
  - name: "token_count"
    script: "scripts/count-tokens.sh"
    args: ["$ARGUMENTS.agent_name"]
    thresholds:
      l1_max: 150
      l2_max: 3000

outputs:
  - path: "tests/agents/$ARGUMENTS.agent_name/validation-report.md"
---
```
</new_commands>

<directory_structure>
## Final Command Structure

```
commands-v2/
├── implement.md
├── review-sprint.md
├── audit-sprint.md
├── audit.md
├── audit-deployment.md
├── plan-and-analyze.md
├── architect.md
├── sprint-plan.md
├── deploy-production.md
├── translate.md
├── setup.md                    # Special: wizard
├── feedback.md                 # Special: survey
├── update.md                   # Special: git operation
├── benchmark-agent.md          # NEW: testing
├── validate-refactor.md        # NEW: validation
└── scripts/
    ├── validate-implement.sh
    ├── validate-review-sprint.sh
    ├── validate-audit-sprint.sh
    ├── validate-structure.sh
    ├── validate-kernel.sh
    ├── count-tokens.sh
    ├── detect-mcp-servers.sh
    ├── init-analytics.sh
    └── check-pending-feedback.sh
```
</directory_structure>

<output_instructions>
For each Loa command file, produce:

1. **Refactored command** (`commands-v2/{name}.md`) with:
   - Full YAML frontmatter (metadata, arguments, context_files, pre_flight, outputs, mode)
   - Slim markdown body (purpose, invocation, workflow, error handling)

2. **Validation script** (`commands-v2/scripts/validate-{name}.sh`) with:
   - Argument validation
   - File existence checks
   - Content validation where needed
   - Clear error messages with resolution guidance

3. **Migration notes**:
   - What was extracted from command body to agent SKILL.md
   - What was extracted to validation scripts
   - Breaking changes (if any)
   - New pre_flight checks added

Format each file with its full path:
```
commands-v2/
├── {command-name}.md
└── scripts/
    └── validate-{command-name}.sh
```
</output_instructions>

<self_check>
Before finalizing each command:

## Structure
- [ ] YAML frontmatter has: name, version, description, arguments, agent, context_files
- [ ] Pre-flight checks cover all prerequisites
- [ ] Outputs list all expected artifacts
- [ ] Mode specifies foreground/background options

## Routing
- [ ] Correct agent referenced
- [ ] Agent path points to agents-v2/
- [ ] Context files listed in priority order

## Validation
- [ ] All arguments have type and pattern
- [ ] Required files checked in pre_flight
- [ ] Error messages include resolution steps

## Compatibility
- [ ] Same command syntax as original (/implement sprint-1)
- [ ] Same outputs produced
- [ ] Background mode preserved where applicable

## Scripts
- [ ] Validation script handles all pre_flight checks
- [ ] Scripts use set -e for error handling
- [ ] Scripts provide clear error messages
</self_check>