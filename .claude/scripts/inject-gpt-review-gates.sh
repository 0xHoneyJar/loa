#!/usr/bin/env bash
# Inject or remove GPT review gates from skills, commands, and CLAUDE.md based on config
# Called by gpt-review-toggle.sh after toggling the config setting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.loa.config.yaml"
SKILLS_DIR="$ROOT_DIR/.claude/skills"
COMMANDS_DIR="$ROOT_DIR/.claude/commands"
CLAUDE_MD="$ROOT_DIR/CLAUDE.md"
CONTEXT_DIR="$ROOT_DIR/.claude/context"
CONTEXT_FILE="$CONTEXT_DIR/gpt-review-active.md"
TEMPLATE_FILE="$ROOT_DIR/.claude/templates/gpt-review-instructions.md.template"

# Gate content for each skill - formatted exactly like other phases, no markers
# Uses explicit "Use the Skill tool" pattern like /ride invocation
PRD_GATE="### Phase 9: GPT Cross-Model Review

**ACTION REQUIRED**: Before proceeding to /architect, invoke the GPT review skill.

Use the Skill tool now:
\`\`\`
Skill: gpt-review
Args: prd
\`\`\`

Wait for the verdict:
- **APPROVED**: Continue to next phase
- **CHANGES_REQUIRED**: Fix issues in PRD, then re-invoke \`Skill: gpt-review, Args: prd\`
- **SKIPPED**: GPT review is disabled, continue normally"

SDD_GATE="### Phase 5: GPT Cross-Model Review

**ACTION REQUIRED**: Before proceeding to /sprint-plan, invoke the GPT review skill.

Use the Skill tool now:
\`\`\`
Skill: gpt-review
Args: sdd
\`\`\`

Wait for the verdict:
- **APPROVED**: Continue to sprint planning
- **CHANGES_REQUIRED**: Fix issues in SDD, then re-invoke \`Skill: gpt-review, Args: sdd\`
- **SKIPPED**: GPT review is disabled, continue normally"

SPRINT_GATE="### Phase 5: GPT Cross-Model Review

**ACTION REQUIRED**: Before proceeding to /implement, invoke the GPT review skill.

Use the Skill tool now:
\`\`\`
Skill: gpt-review
Args: sprint
\`\`\`

Wait for the verdict:
- **APPROVED**: Continue to implementation
- **CHANGES_REQUIRED**: Fix issues in sprint plan, then re-invoke \`Skill: gpt-review, Args: sprint\`
- **SKIPPED**: GPT review is disabled, continue normally"

CODE_GATE="### Post-Task: GPT Cross-Model Review

**ACTION REQUIRED**: After completing each task, invoke the GPT review skill on modified files.

Use the Skill tool now:
\`\`\`
Skill: gpt-review
Args: code <modified-file>
\`\`\`

Wait for the verdict:
- **APPROVED**: Continue to next task
- **CHANGES_REQUIRED**: Fix issues, then re-invoke with the same file
- **SKIPPED**: GPT review is disabled, continue normally"

# Success criteria to inject into each skill
SUCCESS_CRITERION="- **GPT Review**: Cross-model review completed with APPROVED or SKIPPED verdict"

# Run mode gate - injected at top of run-mode skill
# Critical because /run bypasses normal skill loading
RUN_MODE_GATE='---
> **GPT REVIEW ENABLED - ONE-SHOTTING > VELOCITY**
>
> After completing EACH implementation task, you MUST run GPT review:
>
> 1. Write `/tmp/gpt-review-expertise.md` (domain expertise from PRD)
> 2. Write `/tmp/gpt-review-context.md` (product context + task purpose + acceptance criteria)
> 3. Use Skill tool: `Skill: gpt-review, Args: code <modified-file>`
> 4. Handle verdict (APPROVED -> continue, CHANGES_REQUIRED -> fix and retry)
>
> **DO NOT proceed to the next task or commit without GPT review.**
> **If unsure whether to review, that means you SHOULD review.**
---'

# Command file gates - inserted before "## Next Step" or file-specific markers
# Uses explicit "Use the Skill tool" pattern - this is what Claude actually reads

# PRD gate - inserted BEFORE "## Next Step" (after PRD creation, before moving to /architect)
PRD_CMD_GATE="## GPT Cross-Model Review (MANDATORY)

**STOP AND EXECUTE**: Before declaring PRD complete, you MUST invoke the GPT review skill NOW.

Use the Skill tool:
\`\`\`
Skill: gpt-review
Args: prd
\`\`\`

Wait for the verdict before proceeding:
- **APPROVED**: Continue to \`/architect\`
- **CHANGES_REQUIRED**: Fix issues, re-invoke \`Skill: gpt-review, Args: prd\`
- **SKIPPED**: GPT review disabled, continue normally"

SDD_CMD_GATE="## GPT Cross-Model Review (MANDATORY)

**STOP AND EXECUTE**: Before declaring SDD complete, you MUST invoke the GPT review skill NOW.

Use the Skill tool:
\`\`\`
Skill: gpt-review
Args: sdd
\`\`\`

Wait for the verdict before proceeding:
- **APPROVED**: Continue to \`/sprint-plan\`
- **CHANGES_REQUIRED**: Fix issues, re-invoke \`Skill: gpt-review, Args: sdd\`
- **SKIPPED**: GPT review disabled, continue normally"

SPRINT_CMD_GATE="## GPT Cross-Model Review (MANDATORY)

**STOP AND EXECUTE**: Before declaring Sprint Plan complete, you MUST invoke the GPT review skill NOW.

Use the Skill tool:
\`\`\`
Skill: gpt-review
Args: sprint
\`\`\`

Wait for the verdict before proceeding:
- **APPROVED**: Continue to \`/implement\`
- **CHANGES_REQUIRED**: Fix issues, re-invoke \`Skill: gpt-review, Args: sprint\`
- **SKIPPED**: GPT review disabled, continue normally"

CODE_CMD_GATE="## GPT Cross-Model Review (MANDATORY)

**STOP AND EXECUTE**: After completing each task, you MUST invoke the GPT review skill NOW.

Use the Skill tool:
\`\`\`
Skill: gpt-review
Args: code <modified-file>
\`\`\`

Wait for the verdict before proceeding:
- **APPROVED**: Continue to next task
- **CHANGES_REQUIRED**: Fix issues, re-invoke with the same file
- **SKIPPED**: GPT review disabled, continue normally"

# Run mode command gate - for /run, /run sprint-plan, /run-resume
RUN_CMD_GATE="## GPT Cross-Model Review (MANDATORY)

**IMPORTANT**: GPT review is ENABLED. ONE-SHOTTING > VELOCITY.

After completing EACH task during execution:

1. Write \`/tmp/gpt-review-expertise.md\` (domain expertise from PRD)
2. Write \`/tmp/gpt-review-context.md\` (product context + task purpose + acceptance criteria)
3. Use Skill tool: \`Skill: gpt-review, Args: code <modified-file>\`
4. Handle verdict (APPROVED → continue, CHANGES_REQUIRED → fix and retry)

**DO NOT skip GPT review between tasks.** If unsure whether to review, that means you SHOULD review."

# CLAUDE.md banner - injected right after "# CLAUDE.md" title
# Comprehensive instructions for GPT cross-model review
CLAUDE_MD_BANNER='---
## ⚠️ GPT CROSS-MODEL REVIEW IS ENABLED

**Core Principle: ONE-SHOTTING > VELOCITY.** Getting code right the first time matters more than moving fast.

### When to Review

**ALWAYS review (no exceptions)**:
- Backend code, API endpoints, database queries
- Security-sensitive code (auth, crypto, input validation)
- Business logic, state management, data transformations
- New files, major refactors

**Frontend/UI changes**:
- You MAY batch multiple UI changes into a single review
- You MUST run GPT review when the feature is complete
- Do not let momentum cause you to skip the final review

**OK to skip** (truly trivial):
- Typo fixes in strings or comments
- Log message changes
- Import reordering
- Version bumps
- Adding/removing console.log for debugging

**The Uncertainty Rule**: If you are debating whether to skip GPT review, that uncertainty is a signal TO USE IT. When in doubt, review.

### How to Run GPT Review

1. **Build context first** (write these files before invoking):
   - `/tmp/gpt-review-expertise.md` - Domain expertise from PRD (e.g., "blockchain security", "React patterns")
   - `/tmp/gpt-review-context.md` - Product context + what this code does + acceptance criteria

2. **Invoke the skill**:
   ```
   Skill: gpt-review
   Args: code <file-path>
   ```

3. **Handle the verdict**:
   - `APPROVED` → Continue
   - `CHANGES_REQUIRED` → Fix issues, re-run review
   - `SKIPPED` → Review was disabled, continue

**For documents** (PRD, SDD, sprint plans): Same process but use `prd`, `sdd`, or `sprint` as the arg.
---'

# Remove success criterion from a skill file
remove_success_criterion() {
  local file="$1"
  if [[ -f "$file" ]] && grep -q "GPT Review.*Cross-model review" "$file"; then
    local temp_file="${file}.tmp"
    grep -v "GPT Review.*Cross-model review" "$file" > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Add success criterion to a skill file - inject BEFORE </success_criteria>
add_success_criterion() {
  local file="$1"

  # First remove any existing criterion
  remove_success_criterion "$file"

  if [[ -f "$file" ]] && grep -q '</success_criteria>' "$file"; then
    local temp_file="${file}.tmp"
    awk -v criterion="$SUCCESS_CRITERION" '
      /<\/success_criteria>/ { print criterion }
      { print }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Remove GPT review banner from CLAUDE.md
remove_claude_md_banner() {
  if [[ -f "$CLAUDE_MD" ]] && grep -q "GPT CROSS-MODEL REVIEW IS ENABLED" "$CLAUDE_MD"; then
    local temp_file="${CLAUDE_MD}.tmp"
    # Remove the entire block from first --- to closing ---
    # Also skip the blank line that follows the closing ---
    awk '
      /^---$/ && !in_block { in_block=1; next }
      /^---$/ && in_block { in_block=0; skip_blank=1; next }
      skip_blank && /^$/ { skip_blank=0; next }
      skip_blank { skip_blank=0 }
      !in_block { print }
    ' "$CLAUDE_MD" > "$temp_file"
    mv "$temp_file" "$CLAUDE_MD"
  fi
}

# Add GPT review banner to CLAUDE.md - inject after the title line
add_claude_md_banner() {
  # First remove any existing banner
  remove_claude_md_banner

  if [[ -f "$CLAUDE_MD" ]]; then
    local temp_file="${CLAUDE_MD}.tmp"
    local banner_file="${CLAUDE_MD}.banner.tmp"

    # Write banner to temp file
    printf '%s\n' "$CLAUDE_MD_BANNER" > "$banner_file"

    # Insert banner after "# CLAUDE.md" title and blank line
    # The banner block ends with --- so we just need one blank line before next content
    awk -v bannerfile="$banner_file" '
      /^# CLAUDE\.md$/ {
        print
        getline
        print
        while ((getline line < bannerfile) > 0) print line
        close(bannerfile)
        next
      }
      { print }
    ' "$CLAUDE_MD" > "$temp_file"

    mv "$temp_file" "$CLAUDE_MD"
    rm -f "$banner_file"
  fi
}

# Remove GPT review gate from run-mode skill
remove_run_mode_gate() {
  local file="$SKILLS_DIR/run-mode/SKILL.md"
  if [[ -f "$file" ]] && grep -q "GPT REVIEW ENABLED - MANDATORY" "$file"; then
    local temp_file="${file}.tmp"
    # Remove from first --- to second --- (the gate block)
    awk '
      /^---$/ && !found { found=1; in_gate=1; next }
      /^---$/ && in_gate { in_gate=0; next }
      !in_gate { print }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Add GPT review gate to run-mode skill - inject after title
add_run_mode_gate() {
  local file="$SKILLS_DIR/run-mode/SKILL.md"

  # First remove any existing gate
  remove_run_mode_gate

  if [[ -f "$file" ]]; then
    local temp_file="${file}.tmp"
    local gate_file="${file}.gate.tmp"

    # Write gate to temp file
    printf '%s\n' "$RUN_MODE_GATE" > "$gate_file"

    # Insert gate after the title line
    {
      head -1 "$file"
      echo ""
      cat "$gate_file"
      echo ""
      tail -n +2 "$file"
    } > "$temp_file"

    mv "$temp_file" "$file"
    rm -f "$gate_file"
  fi
}

# Remove gate from a command file
remove_cmd_gate() {
  local file="$1"
  if [[ -f "$file" ]] && grep -q "GPT Cross-Model Review (MANDATORY)" "$file"; then
    local temp_file="${file}.tmp"
    awk '
      BEGIN { prev_blank=0; skip=0 }
      /^$/ && !skip { prev_blank=1; prev_line=$0; next }
      /^## GPT Cross-Model Review \(MANDATORY\)/ { skip=1; prev_blank=0; next }
      /^## Next Step/ || /^## / {
        if (skip) {
          skip=0
          # Print a blank line before next section (preserve original formatting)
          print ""
        }
      }
      !skip {
        if (prev_blank) { print prev_line; prev_blank=0 }
        print
      }
      END { if (prev_blank) print prev_line }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Add gate to a command file - inject BEFORE "## Next Step" or append at end
add_cmd_gate() {
  local file="$1"
  local gate="$2"

  # First remove any existing gate
  remove_cmd_gate "$file"

  if [[ -f "$file" ]]; then
    if grep -q '^## Next Step' "$file"; then
      # Insert before "## Next Step"
      local gate_file="${file}.gate.tmp"
      local temp_file="${file}.tmp"
      printf '%s\n\n' "$gate" > "$gate_file"

      awk -v gatefile="$gate_file" '
        /^## Next Step/ {
          while ((getline line < gatefile) > 0) print line
          close(gatefile)
        }
        { print }
      ' "$file" > "$temp_file"

      mv "$temp_file" "$file"
      rm -f "$gate_file"
    else
      # No "## Next Step" - append at end
      printf '\n%s\n' "$gate" >> "$file"
    fi
  fi
}

# Remove gate from a skill file
remove_gate() {
  local file="$1"
  # Look for any GPT Cross-Model Review phase header
  if [[ -f "$file" ]] && grep -q "GPT Cross-Model Review" "$file"; then
    # Remove from the phase header to just before </workflow>
    # Also removes the single blank line that precedes the phase header
    local temp_file="${file}.tmp"
    awk '
      BEGIN { prev_blank=0; skip=0 }
      /^$/ && !skip { prev_blank=1; prev_line=$0; next }
      /### Phase.*GPT Cross-Model Review|### Post-Task: GPT Cross-Model Review/ { skip=1; prev_blank=0; next }
      /<\/workflow>/ { skip=0 }
      !skip {
        if (prev_blank) { print prev_line; prev_blank=0 }
        print
      }
      END { if (prev_blank) print prev_line }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Add gate to a skill file - inject BEFORE </workflow> so it's part of the workflow
add_gate() {
  local file="$1"
  local gate="$2"

  # First remove any existing gate
  remove_gate "$file"

  if [[ -f "$file" ]]; then
    # Check if file has </workflow> tag
    if grep -q '</workflow>' "$file"; then
      # Insert gate BEFORE </workflow> so it's part of the workflow phases
      local gate_file="${file}.gate.tmp"
      local temp_file="${file}.tmp"
      printf '\n%s\n' "$gate" > "$gate_file"

      # Use awk to insert gate content before </workflow>
      awk -v gatefile="$gate_file" '
        /<\/workflow>/ {
          while ((getline line < gatefile) > 0) print line
          close(gatefile)
        }
        { print }
      ' "$file" > "$temp_file"

      mv "$temp_file" "$file"
      rm -f "$gate_file"
    else
      # No workflow tag - append to end (fallback)
      printf '\n%s\n' "$gate" >> "$file"
    fi
  fi
}

# Check if yq is available
if ! command -v yq &>/dev/null; then
  exit 0
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  # No config - remove gates and success criteria from skills
  remove_gate "$SKILLS_DIR/discovering-requirements/SKILL.md"
  remove_gate "$SKILLS_DIR/designing-architecture/SKILL.md"
  remove_gate "$SKILLS_DIR/planning-sprints/SKILL.md"
  remove_gate "$SKILLS_DIR/implementing-tasks/SKILL.md"

  remove_success_criterion "$SKILLS_DIR/discovering-requirements/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/designing-architecture/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/planning-sprints/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/implementing-tasks/SKILL.md"

  # Remove gates from command files
  remove_cmd_gate "$COMMANDS_DIR/plan-and-analyze.md"
  remove_cmd_gate "$COMMANDS_DIR/architect.md"
  remove_cmd_gate "$COMMANDS_DIR/sprint-plan.md"
  remove_cmd_gate "$COMMANDS_DIR/implement.md"
  remove_cmd_gate "$COMMANDS_DIR/run.md"
  remove_cmd_gate "$COMMANDS_DIR/run-sprint-plan.md"
  remove_cmd_gate "$COMMANDS_DIR/run-resume.md"

  # Remove run-mode gate
  remove_run_mode_gate

  # Remove banner from CLAUDE.md
  remove_claude_md_banner
  exit 0
fi

# Check if GPT review is enabled
enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

if [[ "$enabled" == "true" ]]; then
  # Add gates and success criteria to skills
  add_gate "$SKILLS_DIR/discovering-requirements/SKILL.md" "$PRD_GATE"
  add_gate "$SKILLS_DIR/designing-architecture/SKILL.md" "$SDD_GATE"
  add_gate "$SKILLS_DIR/planning-sprints/SKILL.md" "$SPRINT_GATE"
  add_gate "$SKILLS_DIR/implementing-tasks/SKILL.md" "$CODE_GATE"

  add_success_criterion "$SKILLS_DIR/discovering-requirements/SKILL.md"
  add_success_criterion "$SKILLS_DIR/designing-architecture/SKILL.md"
  add_success_criterion "$SKILLS_DIR/planning-sprints/SKILL.md"
  add_success_criterion "$SKILLS_DIR/implementing-tasks/SKILL.md"

  # Add gates to command files (what Claude actually reads!)
  add_cmd_gate "$COMMANDS_DIR/plan-and-analyze.md" "$PRD_CMD_GATE"
  add_cmd_gate "$COMMANDS_DIR/architect.md" "$SDD_CMD_GATE"
  add_cmd_gate "$COMMANDS_DIR/sprint-plan.md" "$SPRINT_CMD_GATE"
  add_cmd_gate "$COMMANDS_DIR/implement.md" "$CODE_CMD_GATE"

  # Add gates to run mode commands
  add_cmd_gate "$COMMANDS_DIR/run.md" "$RUN_CMD_GATE"
  add_cmd_gate "$COMMANDS_DIR/run-sprint-plan.md" "$RUN_CMD_GATE"
  add_cmd_gate "$COMMANDS_DIR/run-resume.md" "$RUN_CMD_GATE"

  # Add run-mode gate to skill (for when skill is loaded directly)
  add_run_mode_gate

  # Add banner to CLAUDE.md (Claude reads this automatically!)
  add_claude_md_banner

  # Create context file from template (loaded by commands via context_files)
  mkdir -p "$CONTEXT_DIR"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$CONTEXT_FILE"
  fi
else
  # Remove gates and success criteria from skills
  remove_gate "$SKILLS_DIR/discovering-requirements/SKILL.md"
  remove_gate "$SKILLS_DIR/designing-architecture/SKILL.md"
  remove_gate "$SKILLS_DIR/planning-sprints/SKILL.md"
  remove_gate "$SKILLS_DIR/implementing-tasks/SKILL.md"

  remove_success_criterion "$SKILLS_DIR/discovering-requirements/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/designing-architecture/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/planning-sprints/SKILL.md"
  remove_success_criterion "$SKILLS_DIR/implementing-tasks/SKILL.md"

  # Remove gates from command files
  remove_cmd_gate "$COMMANDS_DIR/plan-and-analyze.md"
  remove_cmd_gate "$COMMANDS_DIR/architect.md"
  remove_cmd_gate "$COMMANDS_DIR/sprint-plan.md"
  remove_cmd_gate "$COMMANDS_DIR/implement.md"
  remove_cmd_gate "$COMMANDS_DIR/run.md"
  remove_cmd_gate "$COMMANDS_DIR/run-sprint-plan.md"
  remove_cmd_gate "$COMMANDS_DIR/run-resume.md"

  # Remove run-mode gate
  remove_run_mode_gate

  # Remove banner from CLAUDE.md
  remove_claude_md_banner

  # Remove context file
  rm -f "$CONTEXT_FILE"
fi

exit 0
