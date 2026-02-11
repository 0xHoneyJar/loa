#!/usr/bin/env bash
# quality-gate.sh — Run Loa quality gate checks
# Args: $1=workspace, $2=gate name (optional, runs all if omitted)
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
gate_name="${2:-all}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

passed=0
failed=0
total=0
details=()

# Gate: skill-index — all skills have valid index.yaml
check_skill_index() {
  local skills_dir="$workspace/.claude/skills"
  if [[ ! -d "$skills_dir" ]]; then
    details+=("skill-index: SKIP (no .claude/skills/)")
    return
  fi

  total=$((total + 1))
  local skill_errors=0
  for skill_dir in "$skills_dir"/*/; do
    [[ -d "$skill_dir" ]] || continue
    if [[ ! -f "$skill_dir/index.yaml" ]]; then
      details+=("skill-index: FAIL — missing index.yaml in $(basename "$skill_dir")")
      skill_errors=$((skill_errors + 1))
    fi
  done

  if [[ $skill_errors -eq 0 ]]; then
    passed=$((passed + 1))
    details+=("skill-index: PASS")
  else
    failed=$((failed + 1))
  fi
}

# Gate: constraints — constraints.json is valid JSON
check_constraints() {
  local constraints_file="$workspace/.claude/data/constraints.json"
  total=$((total + 1))
  if [[ ! -f "$constraints_file" ]]; then
    details+=("constraints: SKIP (no constraints.json)")
    return
  fi

  if jq . "$constraints_file" &>/dev/null; then
    passed=$((passed + 1))
    details+=("constraints: PASS")
  else
    failed=$((failed + 1))
    details+=("constraints: FAIL — invalid JSON")
  fi
}

# Gate: config — .loa.config.yaml is valid YAML
check_config() {
  local config_file="$workspace/.loa.config.yaml"
  total=$((total + 1))
  if [[ ! -f "$config_file" ]]; then
    details+=("config: SKIP (no .loa.config.yaml)")
    return
  fi

  if yq . "$config_file" &>/dev/null; then
    passed=$((passed + 1))
    details+=("config: PASS")
  else
    failed=$((failed + 1))
    details+=("config: FAIL — invalid YAML")
  fi
}

# Run gates
case "$gate_name" in
  skill-index) check_skill_index ;;
  constraints) check_constraints ;;
  config) check_config ;;
  all)
    check_skill_index
    check_constraints
    check_config
    ;;
  *)
    echo '{"pass":false,"score":0,"details":"Unknown gate: '"$gate_name"'","grader_version":"1.0.0"}'
    exit 2
    ;;
esac

details_str="$(printf '%s; ' "${details[@]}")"
score=0
[[ $total -gt 0 ]] && score=$(( (passed * 100) / total ))

if [[ $failed -eq 0 ]]; then
  jq -n --arg details "$details_str" --argjson score "$score" \
    '{"pass":true,"score":$score,"details":$details,"grader_version":"1.0.0"}'
  exit 0
else
  jq -n --arg details "$details_str" --argjson score "$score" \
    '{"pass":false,"score":$score,"details":$details,"grader_version":"1.0.0"}'
  exit 1
fi
