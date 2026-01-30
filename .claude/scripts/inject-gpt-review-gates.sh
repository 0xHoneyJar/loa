#!/usr/bin/env bash
# Inject or remove GPT review gates from skill files based on config
# Called by SessionStart hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.loa.config.yaml"
SKILLS_DIR="$ROOT_DIR/.claude/skills"
COMMANDS_DIR="$ROOT_DIR/.claude/commands"
CLAUDE_MD="$ROOT_DIR/CLAUDE.md"

# Gate content for each skill - formatted exactly like other phases, no markers
PRD_GATE="### Phase 9: GPT Cross-Model Review

Run the GPT review skill on the PRD:

/gpt-review prd

Handle the verdict before proceeding to the next phase."

SDD_GATE="### Phase 5: GPT Cross-Model Review

Run the GPT review skill on the SDD:

/gpt-review sdd

Handle the verdict before proceeding to sprint planning."

SPRINT_GATE="### Phase 5: GPT Cross-Model Review

Run the GPT review skill on the sprint plan:

/gpt-review sprint

Handle the verdict before proceeding to implementation."

CODE_GATE="### Post-Task: GPT Cross-Model Review

Run the GPT review skill on modified files:

/gpt-review code <modified-file>

Handle the verdict before proceeding to the next task."

# Success criteria to inject into each skill
SUCCESS_CRITERION="- **GPT Review**: Cross-model review completed with APPROVED or SKIPPED verdict"

# Command file gates - these go BEFORE "## Next Step" section
PRD_CMD_GATE="## Phase 8: GPT Cross-Model Review (MANDATORY)

**STOP: Before declaring PRD complete, you MUST run GPT review.**

\`\`\`bash
/gpt-review prd
\`\`\`

Handle the verdict:
- **APPROVED**: Proceed to \`/architect\`
- **CHANGES_REQUIRED**: Fix issues, re-run \`/gpt-review prd\`
- **SKIPPED**: GPT review disabled, proceed normally"

SDD_CMD_GATE="## Phase 5: GPT Cross-Model Review (MANDATORY)

**STOP: Before declaring SDD complete, you MUST run GPT review.**

\`\`\`bash
/gpt-review sdd
\`\`\`

Handle the verdict:
- **APPROVED**: Proceed to \`/sprint-plan\`
- **CHANGES_REQUIRED**: Fix issues, re-run \`/gpt-review sdd\`
- **SKIPPED**: GPT review disabled, proceed normally"

SPRINT_CMD_GATE="## Phase 6: GPT Cross-Model Review (MANDATORY)

**STOP: Before declaring Sprint Plan complete, you MUST run GPT review.**

\`\`\`bash
/gpt-review sprint
\`\`\`

Handle the verdict:
- **APPROVED**: Proceed to \`/implement\`
- **CHANGES_REQUIRED**: Fix issues, re-run \`/gpt-review sprint\`
- **SKIPPED**: GPT review disabled, proceed normally"

CODE_CMD_GATE="## Post-Task: GPT Cross-Model Review (MANDATORY)

**After completing each task, run GPT review on modified files.**

\`\`\`bash
/gpt-review code <modified-file>
\`\`\`

Handle the verdict:
- **APPROVED**: Proceed to next task
- **CHANGES_REQUIRED**: Fix issues, re-run \`/gpt-review code\`
- **SKIPPED**: GPT review disabled, proceed normally"

# CLAUDE.md banner - injected right after "Dynamic instructions" line
CLAUDE_MD_BANNER="> ⚠️ **GPT REVIEW IS ENABLED** - After creating/modifying PRD, SDD, sprint plans, or code files, you MUST run \`/gpt-review <type>\` before marking the phase complete. Types: \`prd\`, \`sdd\`, \`sprint\`, \`code\`. This is MANDATORY - check your success criteria."

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
  if [[ -f "$CLAUDE_MD" ]] && grep -q "GPT REVIEW IS ENABLED" "$CLAUDE_MD"; then
    local temp_file="${CLAUDE_MD}.tmp"
    # Simply remove the banner line - nothing else
    grep -v "GPT REVIEW IS ENABLED" "$CLAUDE_MD" > "$temp_file"
    mv "$temp_file" "$CLAUDE_MD"
  fi
}

# Add GPT review banner to CLAUDE.md - inject after blank line following "Dynamic instructions"
add_claude_md_banner() {
  # First remove any existing banner
  remove_claude_md_banner

  if [[ -f "$CLAUDE_MD" ]] && grep -q "Dynamic instructions" "$CLAUDE_MD"; then
    local temp_file="${CLAUDE_MD}.tmp"
    # Insert banner after the blank line that follows "Dynamic instructions"
    # Pattern: "Dynamic instructions" line → blank line → insert banner here
    awk -v banner="$CLAUDE_MD_BANNER" '
      /Dynamic instructions/ { found=1 }
      found && /^$/ { print; print banner; found=0; next }
      { print }
    ' "$CLAUDE_MD" > "$temp_file"
    mv "$temp_file" "$CLAUDE_MD"
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
      /^## (Phase [0-9]+|Post-Task): GPT Cross-Model Review \(MANDATORY\)/ { skip=1; prev_blank=0; next }
      /^## Next Step/ {
        skip=0
        # Print a blank line before "## Next Step" (preserve original formatting)
        print ""
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

  # Add banner to CLAUDE.md (Claude reads this automatically!)
  add_claude_md_banner
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

  # Remove banner from CLAUDE.md
  remove_claude_md_banner
fi

exit 0
