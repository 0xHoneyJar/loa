# Loa Agent Skills → v4.1 Optimization Prompt

<context>
You are optimizing Loa's v4 agent skills architecture based on Anthropic's latest recommendations. The current implementation is functional but can be refined in three specific areas:

1. **Naming Conventions** - Skill names should use gerund form (verb + -ing)
2. **Deterministic Logic Extraction** - Move repetitive logic to bash scripts
3. **Conciseness** - SKILL.md files should be under 500 lines

This is a targeted optimization pass, not a full rewrite. Preserve all existing functionality.
</context>

---

## Optimization 1: Gerund Naming Convention

<rationale>
Anthropic recommends gerund form (verb + -ing) for skill names because it describes the **capability/action** rather than a role. This makes skill invocation more intuitive:
- "I need help **architecting** a system" → triggers `architecting-systems`
- "I need to **implement** sprint tasks" → triggers `implementing-sprint-tasks`
</rationale>

<current_names>
| Current Name | Problem |
|--------------|---------|
| `prd-architect` | Role-based, not action-based |
| `architecture-designer` | Role-based |
| `sprint-planner` | Role-based |
| `sprint-task-implementer` | Mixed (has verb but role-focused) |
| `senior-tech-lead-reviewer` | Role-based |
| `paranoid-auditor` | Role-based |
| `devops-crypto-architect` | Role-based |
| `devrel-translator` | Role-based |
</current_names>

<new_names>
| Current | New (Gerund) | Reasoning |
|---------|--------------|-----------|
| `prd-architect` | `discovering-requirements` | Primary action: discovery |
| `architecture-designer` | `designing-architecture` | Primary action: design |
| `sprint-planner` | `planning-sprints` | Primary action: planning |
| `sprint-task-implementer` | `implementing-tasks` | Primary action: implementation |
| `senior-tech-lead-reviewer` | `reviewing-code` | Primary action: review |
| `paranoid-auditor` | `auditing-security` | Primary action: audit |
| `devops-crypto-architect` | `deploying-infrastructure` | Primary action: deployment |
| `devrel-translator` | `translating-for-executives` | Primary action: translation |
</new_names>

<migration_tasks>
1. Rename directories: `.claude/skills/{old-name}/` → `.claude/skills/{new-name}/`
2. Update `index.yaml` → `name:` field in each skill
3. Update all command files → `agent:` and `agent_path:` fields
4. Update CLAUDE.md, PROCESS.md, README.md references
5. Update any cross-skill `dependencies:` references
6. Search codebase for old names and update

**Produce a migration script:**
```bash
#!/bin/bash
# migrate-skill-names.sh
# Renames skill directories and updates references

declare -A NAME_MAP=(
    ["prd-architect"]="discovering-requirements"
    ["architecture-designer"]="designing-architecture"
    ["sprint-planner"]="planning-sprints"
    ["sprint-task-implementer"]="implementing-tasks"
    ["senior-tech-lead-reviewer"]="reviewing-code"
    ["paranoid-auditor"]="auditing-security"
    ["devops-crypto-architect"]="deploying-infrastructure"
    ["devrel-translator"]="translating-for-executives"
)

# ... implementation
```
</migration_tasks>

---

## Optimization 2: Deterministic Logic Extraction

<rationale>
Claude performs better when deterministic logic (things with predictable, rule-based outcomes) is handled by scripts. Benefits:
- **Reliability** - Bash doesn't hallucinate file paths or git commands
- **Token savings** - Script output is compact vs. Claude reasoning through logic
- **Reproducibility** - Same input → same output, always
- **Testability** - Scripts can be unit tested independently
</rationale>

<identify_deterministic_logic>
Scan all SKILL.md files for patterns that should be scripts:

### Pattern 1: File Existence Checks
```markdown
<!-- CURRENT: In SKILL.md -->
Check if `loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md` exists.
If it contains "CHANGES_REQUIRED", address security issues first.
```

```bash
# BETTER: Script
./scripts/check-feedback-status.sh sprint-1
# Returns: AUDIT_REQUIRED | REVIEW_REQUIRED | CLEAR
```

### Pattern 2: Context Size Assessment
```markdown
<!-- CURRENT: In SKILL.md -->
Run: wc -l loa-grimoire/prd.md loa-grimoire/sdd.md ...
If total < 3000: SMALL
If total 3000-8000: MEDIUM
If total > 8000: LARGE
```

```bash
# BETTER: Script
./scripts/assess-context-size.sh --threshold 3000
# Returns: SMALL|1247 or MEDIUM|4521 or LARGE|12340
```

### Pattern 3: Git Remote Detection
```markdown
<!-- CURRENT: In SKILL.md (or protocol) -->
Check if origin URL contains "0xHoneyJar/loa"...
Check if upstream remote exists...
Check GitHub API for fork parent...
```

```bash
# BETTER: Script
./scripts/detect-template-repo.sh
# Returns: TEMPLATE|origin_url or NOT_TEMPLATE
```

### Pattern 4: User Type Checking
```markdown
<!-- CURRENT: In SKILL.md -->
Read .loa-setup-complete and check user_type field.
If "thj": enable analytics
If "oss": skip analytics
```

```bash
# BETTER: Script
./scripts/get-user-type.sh
# Returns: thj or oss
```

### Pattern 5: Sprint ID Validation
```markdown
<!-- CURRENT: In SKILL.md -->
Validate sprint ID matches pattern ^sprint-[0-9]+$
```

```bash
# BETTER: Script
./scripts/validate-sprint-id.sh sprint-1
# Returns: VALID or INVALID|reason
```

### Pattern 6: Prerequisite Checking
```markdown
<!-- CURRENT: In SKILL.md -->
Verify PRD exists, SDD exists, sprint.md exists...
```

```bash
# BETTER: Script
./scripts/check-prerequisites.sh --phase implement
# Returns: OK or MISSING|prd.md,sdd.md
```
</identify_deterministic_logic>

<scripts_to_create>
Create these scripts in `.claude/scripts/`:

| Script | Purpose | Used By |
|--------|---------|---------|
| `check-feedback-status.sh` | Check audit/review feedback state | implementing-tasks |
| `assess-context-size.sh` | Determine SMALL/MEDIUM/LARGE | All skills with parallel |
| `detect-template-repo.sh` | Git safety detection | Git operations |
| `get-user-type.sh` | THJ vs OSS check | Analytics-related |
| `validate-sprint-id.sh` | Sprint ID format check | Sprint commands |
| `check-prerequisites.sh` | Phase prerequisite files | All phase commands |
| `get-env-info.sh` | Version, user, project | Analytics |
| `update-sprint-status.sh` | Mark tasks complete | reviewing-code |

**Script template:**
```bash
#!/bin/bash
# {script-name}.sh
# Purpose: {one-line description}
# Usage: ./{script-name}.sh {args}
# Returns: {output format}
# Exit codes: 0=success, 1=error, 2=invalid input

set -euo pipefail

main() {
    # Validate inputs
    # Execute logic
    # Output result in parseable format
}

main "$@"
```
</scripts_to_create>

<update_skill_md>
After creating scripts, update each SKILL.md:

**Before:**
```markdown
## Phase 0: Check Feedback Files

### Step 1: Security Audit Feedback (HIGHEST PRIORITY)
Check if `loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md` exists.
If it exists, read the file and look for "CHANGES_REQUIRED" or "APPROVED".
If "CHANGES_REQUIRED" is found, you must address all security issues before
proceeding with any new implementation work...
[20 more lines of logic]
```

**After:**
```markdown
## Phase 0: Check Feedback Files

Run feedback check:
```bash
./.claude/scripts/check-feedback-status.sh $SPRINT_ID
```

| Result | Action |
|--------|--------|
| `AUDIT_REQUIRED` | Read audit feedback, fix security issues first |
| `REVIEW_REQUIRED` | Read engineer feedback, address all items |
| `CLEAR` | Proceed with new implementation |
```
</update_skill_md>

---

## Optimization 3: Conciseness (500-line limit)

<rationale>
Claude already knows how to code, review, audit, etc. SKILL.md should provide:
- **What** to do (task definition)
- **Where** to read/write (file paths)
- **When** to ask vs proceed (decision points)
- **How to format** output (templates)

It should NOT explain:
- What a "persona" is
- How to write good code (Claude knows)
- Basic security concepts (Claude knows)
- General best practices (Claude knows)
</rationale>

<audit_each_skill>
For each SKILL.md, identify and trim:

### Category 1: Persona Over-Explanation
```markdown
<!-- REMOVE: Claude knows what a persona is -->
You are adopting the persona of a Senior Software Architect. A persona means
you should embody the characteristics, expertise, and communication style of
this role. This includes...

<!-- KEEP: Just the persona data -->
**Persona**: Senior Software Architect (15 years, distributed systems, security-focused)
```

### Category 2: Obvious Instructions
```markdown
<!-- REMOVE: Claude knows this -->
When writing code, ensure it is readable, maintainable, and follows best
practices. Use meaningful variable names. Add comments where the code is
complex. Handle errors appropriately...

<!-- KEEP: Project-specific conventions only -->
**Code conventions**: See `.eslintrc`, prefer explicit types, 80% test coverage minimum
```

### Category 3: Redundant Explanations
```markdown
<!-- REMOVE: Explaining what KERNEL means every time -->
KERNEL stands for Keep it narrow, Explicit constraints, Reproducible results...
This framework ensures that prompts are well-structured...

<!-- KEEP: Just use KERNEL structure without meta-explanation -->
```

### Category 4: Generic Security/Quality Advice
```markdown
<!-- REMOVE: Claude knows OWASP -->
SQL injection is a type of security vulnerability where an attacker can
insert malicious SQL code into queries. This happens when user input is
not properly sanitized. To prevent this...

<!-- KEEP: Just the checklist -->
- [ ] No SQL via string concatenation (use parameterized queries)
```

### Category 5: Workflow Prose → Tables
```markdown
<!-- VERBOSE -->
First, you should check if the audit feedback file exists. If it does exist,
you need to read it and determine whether it says CHANGES_REQUIRED or
APPROVED. If it says CHANGES_REQUIRED, then you must address all the
security issues before doing anything else. If it says APPROVED, you can
proceed normally. If the file doesn't exist, that means no audit has been
performed yet, so you should also proceed normally.

<!-- CONCISE -->
| File State | Action |
|------------|--------|
| Contains "CHANGES_REQUIRED" | Fix security issues first |
| Contains "APPROVED" | Proceed normally |
| Missing | Proceed normally (not yet audited) |
```
</audit_each_skill>

<target_structure>
Each SKILL.md should follow this concise structure (~300-400 lines):

```markdown
---
# YAML frontmatter (10-20 lines)
---

# {Skill Name}

<objective>
{1-2 sentences max}
</objective>

<persona>
{Role}: {Experience} | {Specialties}
</persona>

<kernel_framework>
## Task
{2-3 sentences}

## Context
{Bullet list of inputs/outputs with paths}

## Constraints
{Bullet list, no explanations}

## Verification
{Success criteria as checklist}
</kernel_framework>

<workflow>
## Phase -1: Context Assessment
{Script call + decision table}

## Phase 0: Prerequisites
{Script call + decision table}

## Phase 1-N: Execution
{Steps as numbered list, not prose}
</workflow>

<output_format>
{Template reference or brief structure}
</output_format>

<success_criteria>
{S.M.A.R.T. bullets - 5 lines}
</success_criteria>
```
</target_structure>

<line_count_targets>
| Section | Max Lines |
|---------|-----------|
| Frontmatter | 20 |
| Objective + Persona | 10 |
| KERNEL Framework | 60 |
| Workflow | 150 |
| Parallel Execution | 50 |
| Output Format | 30 |
| Success Criteria | 20 |
| Checklists (inline) | 40 |
| **Total** | **~380** |

If a skill exceeds 500 lines after trimming:
1. Move checklists (>20 items) → `resources/REFERENCE.md`
2. Move templates → `resources/templates/`
3. Move examples → `resources/examples/`
</line_count_targets>

---

## Execution Plan

<phase_1>
### Phase 1: Create Scripts (Do First)
1. Create `.claude/scripts/` directory structure
2. Implement all scripts from Optimization 2
3. Test each script independently
4. Document script interface (inputs/outputs)

**Deliverables:**
- 8 bash scripts with tests
- `scripts/README.md` documenting all scripts
</phase_1>

<phase_2>
### Phase 2: Trim SKILL.md Files
For each skill:
1. Count current lines: `wc -l SKILL.md`
2. Apply Category 1-5 trimming rules
3. Replace inline logic with script calls
4. Convert prose to tables where possible
5. Move overflow content to resources/
6. Verify under 500 lines

**Deliverables:**
- 8 trimmed SKILL.md files
- Updated resources/ directories
</phase_2>

<phase_3>
### Phase 3: Rename Skills
1. Run migration script (from Optimization 1)
2. Update all references across codebase
3. Verify commands still work
4. Update documentation

**Deliverables:**
- Renamed skill directories
- Updated command files
- Updated docs
</phase_3>

---

## Validation Checklist

### Scripts
- [ ] All scripts have shebang, set -euo pipefail
- [ ] All scripts document usage and return format
- [ ] All scripts handle edge cases (missing files, bad input)
- [ ] Scripts tested with sample inputs

### SKILL.md Files
- [ ] Each file under 500 lines (`wc -l` check)
- [ ] No persona explanations (just persona data)
- [ ] No generic coding/security advice
- [ ] Deterministic logic replaced with script calls
- [ ] Prose converted to tables where applicable
- [ ] Large checklists moved to resources/

### Naming
- [ ] All skills use gerund form (verb + -ing)
- [ ] All command references updated
- [ ] All documentation updated
- [ ] No broken cross-references

### Functionality
- [ ] All commands still work after changes
- [ ] Scripts return expected output formats
- [ ] Parallel execution patterns preserved

---

## Output Format

Produce changes in this order:

1. **`.claude/scripts/`** - All new scripts with tests
2. **Skill-by-skill diffs** - Show before/after line counts, what was removed
3. **Rename migration script** - Complete bash script
4. **Updated index.yaml files** - With new names
5. **Documentation updates** - CLAUDE.md, PROCESS.md, README.md diffs
6. **Summary report:**
   - Total lines removed per skill
   - Scripts created
   - Naming changes applied
   - Breaking changes (if any)