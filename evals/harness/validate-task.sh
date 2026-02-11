#!/usr/bin/env bash
# validate-task.sh — Task YAML validator for Loa Eval Sandbox
# Exit codes: 0 = valid, 1 = invalid, 2 = error (validator broken)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"

# --- Preflight ---
for tool in jq yq; do
  if ! command -v "$tool" &>/dev/null; then
    echo '{"valid":false,"task_id":"","warnings":[],"errors":["Missing required tool: '"$tool"'"]}' >&2
    exit 2
  fi
done

usage() {
  cat <<'USAGE'
Usage: validate-task.sh <task.yaml> [--json] [--strict]

Validates a task YAML file against Schema Version 1.

Options:
  --json     Output JSON (default)
  --strict   Treat warnings as errors

Exit codes:
  0  Valid
  1  Invalid (errors found)
  2  Validator error (infrastructure)
USAGE
  exit 2
}

# --- Parse args ---
TASK_FILE=""
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) shift ;;
    --strict) STRICT=true; shift ;;
    --help|-h) usage ;;
    -*) echo '{"valid":false,"task_id":"","warnings":[],"errors":["Unknown flag: '"$1"'"]}'; exit 1 ;;
    *)
      if [[ -z "$TASK_FILE" ]]; then
        TASK_FILE="$1"
      else
        echo '{"valid":false,"task_id":"","warnings":[],"errors":["Multiple task files not supported"]}'; exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TASK_FILE" ]]; then
  usage
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo '{"valid":false,"task_id":"","warnings":[],"errors":["Task file not found: '"$TASK_FILE"'"]}'; exit 1
fi

# --- Validate ---
errors=()
warnings=()

# Extract task ID from filename (without .yaml extension)
filename="$(basename "$TASK_FILE")"
file_id="${filename%.yaml}"
file_id="${file_id%.yml}"

# Read required fields
task_id="$(yq -r '.id // ""' "$TASK_FILE")"
schema_version="$(yq -r '.schema_version // ""' "$TASK_FILE")"
skill="$(yq -r '.skill // ""' "$TASK_FILE")"
category="$(yq -r '.category // ""' "$TASK_FILE")"
fixture="$(yq -r '.fixture // ""' "$TASK_FILE")"
description="$(yq -r '.description // ""' "$TASK_FILE")"

# 1. Check required fields
[[ -z "$task_id" ]] && errors+=("Missing required field: id")
[[ -z "$schema_version" ]] && errors+=("Missing required field: schema_version")
[[ -z "$skill" ]] && errors+=("Missing required field: skill")
[[ -z "$category" ]] && errors+=("Missing required field: category")
[[ -z "$fixture" ]] && errors+=("Missing required field: fixture")
[[ -z "$description" ]] && errors+=("Missing required field: description")

# 2. Validate id matches filename
if [[ -n "$task_id" && "$task_id" != "$file_id" ]]; then
  errors+=("Task id '$task_id' does not match filename '$file_id'")
fi

# 3. Validate schema_version
if [[ -n "$schema_version" && "$schema_version" != "1" ]]; then
  errors+=("Unsupported schema_version: $schema_version (supported: 1)")
fi

# 4. Validate category
valid_categories="framework regression skill-quality e2e"
if [[ -n "$category" && ! " $valid_categories " =~ " $category " ]]; then
  errors+=("Invalid category: '$category' (valid: $valid_categories)")
fi

# 5. Validate skill exists
if [[ -n "$skill" ]]; then
  skill_dir="$REPO_ROOT/.claude/skills/$skill"
  if [[ ! -d "$skill_dir" ]]; then
    # Also check if it's a framework-level skill reference
    if [[ "$category" == "framework" ]]; then
      warnings+=("Skill directory not found: $skill_dir (framework tasks may reference abstract skills)")
    else
      errors+=("Skill directory not found: $skill_dir")
    fi
  fi
fi

# 6. Validate fixture exists
if [[ -n "$fixture" ]]; then
  fixture_dir="$EVALS_DIR/fixtures/$fixture"
  if [[ ! -d "$fixture_dir" ]]; then
    errors+=("Fixture directory not found: $fixture_dir")
  else
    # Check for fixture.yaml
    if [[ ! -f "$fixture_dir/fixture.yaml" ]]; then
      warnings+=("fixture.yaml not found in $fixture_dir")
    fi
  fi
fi

# 7. Validate graders
grader_count="$(yq -r '.graders | length // 0' "$TASK_FILE")"
if [[ "$grader_count" -eq 0 ]]; then
  errors+=("At least one grader is required")
else
  for i in $(seq 0 $((grader_count - 1))); do
    grader_type="$(yq -r ".graders[$i].type // \"\"" "$TASK_FILE")"
    grader_script="$(yq -r ".graders[$i].script // \"\"" "$TASK_FILE")"

    if [[ -z "$grader_type" ]]; then
      errors+=("graders[$i]: missing type")
    elif [[ "$grader_type" != "code" && "$grader_type" != "model" ]]; then
      errors+=("graders[$i]: invalid type '$grader_type' (valid: code, model)")
    fi

    if [[ -z "$grader_script" ]]; then
      errors+=("graders[$i]: missing script")
    else
      grader_path="$EVALS_DIR/graders/$grader_script"
      if [[ ! -f "$grader_path" ]]; then
        errors+=("graders[$i]: script not found: $grader_path")
      elif [[ ! -x "$grader_path" ]]; then
        errors+=("graders[$i]: script not executable: $grader_path")
      fi
    fi

    # Validate grader args structurally
    arg_count="$(yq -r ".graders[$i].args | length // 0" "$TASK_FILE")"
    for j in $(seq 0 $((arg_count - 1))); do
      arg="$(yq -r ".graders[$i].args[$j] // \"\"" "$TASK_FILE")"
      # Reject args containing shell metacharacters
      if [[ "$arg" =~ [\;\|\&\$\`\\] ]]; then
        errors+=("graders[$i].args[$j]: contains shell metacharacter: '$arg'")
      fi
      # Reject path traversal
      if [[ "$arg" == *".."* ]]; then
        errors+=("graders[$i].args[$j]: path traversal detected: '$arg'")
      fi
    done

    # Validate weight
    weight="$(yq -r ".graders[$i].weight // \"1.0\"" "$TASK_FILE")"
    if ! echo "$weight" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
      errors+=("graders[$i]: invalid weight: '$weight'")
    fi
  done
fi

# 8. Validate timeout fields if present
per_trial="$(yq -r '.timeout.per_trial // ""' "$TASK_FILE")"
per_grader="$(yq -r '.timeout.per_grader // ""' "$TASK_FILE")"
if [[ -n "$per_trial" ]] && ! echo "$per_trial" | grep -qE '^[0-9]+$'; then
  errors+=("timeout.per_trial must be a positive integer: '$per_trial'")
fi
if [[ -n "$per_grader" ]] && ! echo "$per_grader" | grep -qE '^[0-9]+$'; then
  errors+=("timeout.per_grader must be a positive integer: '$per_grader'")
fi

# 9. Validate trials if present
trials="$(yq -r '.trials // ""' "$TASK_FILE")"
if [[ -n "$trials" ]]; then
  if ! echo "$trials" | grep -qE '^[1-9][0-9]*$'; then
    errors+=("trials must be a positive integer: '$trials'")
  fi
fi

# 10. Agent tasks require prompt
if [[ "$category" == "skill-quality" || "$category" == "e2e" ]]; then
  prompt="$(yq -r '.prompt // ""' "$TASK_FILE")"
  if [[ -z "$prompt" ]]; then
    errors+=("Tasks with category '$category' require a 'prompt' field")
  fi
fi

# --- Output ---
valid=true
if [[ ${#errors[@]} -gt 0 ]]; then
  valid=false
fi
if [[ "$STRICT" == "true" && ${#warnings[@]} -gt 0 ]]; then
  valid=false
fi

# Build JSON output
errors_json="[]"
if [[ ${#errors[@]} -gt 0 ]]; then
  errors_json=$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)
fi

warnings_json="[]"
if [[ ${#warnings[@]} -gt 0 ]]; then
  warnings_json=$(printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .)
fi

jq -n \
  --argjson valid "$valid" \
  --arg task_id "$task_id" \
  --argjson warnings "$warnings_json" \
  --argjson errors "$errors_json" \
  '{valid: $valid, task_id: $task_id, warnings: $warnings, errors: $errors}'

if [[ "$valid" == "true" ]]; then
  exit 0
else
  exit 1
fi
