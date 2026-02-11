#!/usr/bin/env bash
# skill-index-validator.sh — Validate all skill index.yaml files
# Args: $1=workspace, $2=check (all-valid|triggers-unique|danger-levels)
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
check="${2:-all-valid}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

skills_dir="$workspace/.claude/skills"
if [[ ! -d "$skills_dir" ]]; then
  echo '{"pass":false,"score":0,"details":"No .claude/skills/ directory","grader_version":"1.0.0"}'
  exit 1
fi

case "$check" in
  all-valid)
    # Check all skills have index.yaml with required fields
    errors=()
    total=0
    for skill_dir in "$skills_dir"/*/; do
      [[ -d "$skill_dir" ]] || continue
      total=$((total + 1))
      skill_name="$(basename "$skill_dir")"
      index_file="$skill_dir/index.yaml"

      if [[ ! -f "$index_file" ]]; then
        errors+=("$skill_name: missing index.yaml")
        continue
      fi

      # Check required fields
      for field in name version description triggers; do
        val="$(yq -r ".$field // \"\"" "$index_file" 2>/dev/null)"
        if [[ -z "$val" || "$val" == "null" ]]; then
          errors+=("$skill_name: missing required field '$field'")
        fi
      done
    done

    if [[ ${#errors[@]} -eq 0 ]]; then
      echo '{"pass":true,"score":100,"details":"All '"$total"' skills have valid index.yaml","grader_version":"1.0.0"}'
      exit 0
    else
      details="$(printf '%s; ' "${errors[@]}")"
      jq -n --arg d "$details" '{"pass":false,"score":0,"details":$d,"grader_version":"1.0.0"}'
      exit 1
    fi
    ;;

  triggers-unique)
    # Check no trigger collisions
    declare -A trigger_map
    collisions=()

    for skill_dir in "$skills_dir"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name="$(basename "$skill_dir")"
      index_file="$skill_dir/index.yaml"
      [[ -f "$index_file" ]] || continue

      trigger_count="$(yq -r '.triggers | length // 0' "$index_file" 2>/dev/null)"
      for i in $(seq 0 $((trigger_count - 1))); do
        trigger="$(yq -r ".triggers[$i]" "$index_file")"
        if [[ -n "${trigger_map[$trigger]:-}" ]]; then
          collisions+=("'$trigger' in both ${trigger_map[$trigger]} and $skill_name")
        fi
        trigger_map["$trigger"]="$skill_name"
      done
    done

    if [[ ${#collisions[@]} -eq 0 ]]; then
      echo '{"pass":true,"score":100,"details":"No trigger collisions found","grader_version":"1.0.0"}'
      exit 0
    else
      details="$(printf '%s; ' "${collisions[@]}")"
      jq -n --arg d "$details" '{"pass":false,"score":0,"details":$d,"grader_version":"1.0.0"}'
      exit 1
    fi
    ;;

  danger-levels)
    # Check all skills have danger_level
    missing=()
    valid_levels="safe moderate high critical"

    for skill_dir in "$skills_dir"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name="$(basename "$skill_dir")"
      index_file="$skill_dir/index.yaml"
      [[ -f "$index_file" ]] || continue

      level="$(yq -r '.danger_level // ""' "$index_file" 2>/dev/null)"
      if [[ -z "$level" ]]; then
        missing+=("$skill_name: no danger_level")
      elif [[ ! " $valid_levels " =~ " $level " ]]; then
        missing+=("$skill_name: invalid danger_level '$level'")
      fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
      echo '{"pass":true,"score":100,"details":"All skills have valid danger_level","grader_version":"1.0.0"}'
      exit 0
    else
      details="$(printf '%s; ' "${missing[@]}")"
      jq -n --arg d "$details" '{"pass":false,"score":0,"details":$d,"grader_version":"1.0.0"}'
      exit 1
    fi
    ;;

  *)
    echo '{"pass":false,"score":0,"details":"Unknown check: '"$check"'","grader_version":"1.0.0"}'
    exit 2
    ;;
esac
