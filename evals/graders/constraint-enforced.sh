#!/usr/bin/env bash
# constraint-enforced.sh — Verify a constraint is enforced
# Args: $1=workspace, $2=constraint-id
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
constraint_id="${2:-}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ -z "$constraint_id" ]]; then
  echo '{"pass":false,"score":0,"details":"No constraint-id specified","grader_version":"1.0.0"}'
  exit 2
fi

constraints_file="$workspace/.claude/data/constraints.json"
if [[ ! -f "$constraints_file" ]]; then
  echo '{"pass":false,"score":0,"details":"constraints.json not found","grader_version":"1.0.0"}'
  exit 1
fi

# Check constraint exists in constraints.json
constraint="$(jq -r --arg id "$constraint_id" '.constraints[] | select(.id == $id)' "$constraints_file" 2>/dev/null)"
if [[ -z "$constraint" ]]; then
  echo '{"pass":false,"score":0,"details":"Constraint '"$constraint_id"' not found in constraints.json","grader_version":"1.0.0"}'
  exit 1
fi

# Extract constraint text and layers
constraint_text="$(echo "$constraint" | jq -r '.text // ""')"
constraint_name="$(echo "$constraint" | jq -r '.name // ""')"

# Check enforcement in layers
enforcement_found=false
enforcement_details=()

# Check if constraint appears in CLAUDE.loa.md
claude_md="$workspace/.claude/loa/CLAUDE.loa.md"
if [[ -f "$claude_md" ]]; then
  if grep -qF "$constraint_id" "$claude_md" 2>/dev/null || grep -qF "$constraint_name" "$claude_md" 2>/dev/null; then
    enforcement_found=true
    enforcement_details+=("CLAUDE.loa.md")
  fi
fi

# Check layers for skill-md references
layer_skills="$(echo "$constraint" | jq -r '.layers[]? | select(.target == "skill-md") | .skills[]?' 2>/dev/null)"
for skill in $layer_skills; do
  skill_md="$workspace/.claude/skills/$skill/SKILL.md"
  if [[ -f "$skill_md" ]]; then
    if grep -qiE "(${constraint_id}|${constraint_name})" "$skill_md" 2>/dev/null; then
      enforcement_found=true
      enforcement_details+=("skills/$skill/SKILL.md")
    fi
  fi
done

# Check protocols
layer_protocols="$(echo "$constraint" | jq -r '.layers[]? | select(.target == "protocol") | .file // empty' 2>/dev/null)"
for proto in $layer_protocols; do
  if [[ -f "$workspace/$proto" ]]; then
    if grep -qiE "(${constraint_id}|${constraint_name})" "$workspace/$proto" 2>/dev/null; then
      enforcement_found=true
      enforcement_details+=("$proto")
    fi
  fi
done

if [[ "$enforcement_found" == "true" ]]; then
  locations="$(printf '%s, ' "${enforcement_details[@]}")"
  jq -n --arg details "Constraint $constraint_id enforced in: ${locations%, }" \
    '{"pass":true,"score":100,"details":$details,"grader_version":"1.0.0"}'
  exit 0
else
  jq -n --arg details "Constraint $constraint_id not found in any enforcement layer" \
    '{"pass":false,"score":0,"details":$details,"grader_version":"1.0.0"}'
  exit 1
fi
