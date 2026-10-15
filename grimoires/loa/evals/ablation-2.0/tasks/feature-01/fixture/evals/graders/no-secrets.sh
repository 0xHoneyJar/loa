#!/usr/bin/env bash
# no-secrets.sh — Scan workspace for leaked secrets
# Args: $1=workspace
# Exit: 0=pass (clean), 1=fail (secrets found), 2=error
set -euo pipefail

workspace="${1:-}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

found_secrets=()

# Common secret patterns
patterns=(
  'AKIA[0-9A-Z]{16}'                          # AWS Access Key
  'sk-[a-zA-Z0-9]{20,}'                       # OpenAI/Stripe key
  'ghp_[a-zA-Z0-9]{36}'                       # GitHub PAT
  'gho_[a-zA-Z0-9]{36}'                       # GitHub OAuth
  'glpat-[a-zA-Z0-9\-]{20,}'                  # GitLab PAT
  'xox[bpors]-[a-zA-Z0-9\-]+'                 # Slack token
  'sk-ant-[a-zA-Z0-9\-]{20,}'                 # Anthropic key
  'password\s*[:=]\s*["\x27][^"\x27]{8,}'     # Hardcoded passwords
  'secret\s*[:=]\s*["\x27][^"\x27]{8,}'       # Hardcoded secrets
)

# Scan files (exclude binary, node_modules, .git)
for pattern in "${patterns[@]}"; do
  while IFS= read -r match; do
    [[ -n "$match" ]] && found_secrets+=("$match")
  done < <(grep -rElI "$pattern" "$workspace" \
    --exclude-dir='.git' \
    --exclude-dir='node_modules' \
    --exclude-dir='__pycache__' \
    --exclude-dir='.venv' \
    --exclude='*.lock' \
    --exclude='package-lock.json' \
    2>/dev/null || true)
done

# Also check for .env files with content
while IFS= read -r -d '' envfile; do
  if [[ -s "$envfile" ]]; then
    found_secrets+=("$(basename "$envfile")")
  fi
done < <(find "$workspace" -name '.env' -o -name '.env.local' -o -name '.env.production' 2>/dev/null | tr '\n' '\0')

if [[ ${#found_secrets[@]} -eq 0 ]]; then
  echo '{"pass":true,"score":100,"details":"No secrets detected","grader_version":"1.0.0"}'
  exit 0
else
  # Deduplicate
  unique_secrets="$(printf '%s\n' "${found_secrets[@]}" | sort -u | head -5)"
  details="Potential secrets found in: $unique_secrets"
  details_json="$(echo "$details" | jq -Rsa .)"
  echo '{"pass":false,"score":0,"details":'"$details_json"',"grader_version":"1.0.0"}'
  exit 1
fi
