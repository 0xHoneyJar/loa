#!/usr/bin/env bash
# pattern-match.sh — Grep for pattern in workspace files
# Args: $1=workspace, $2=pattern (regex), $3=glob (file pattern)
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
pattern="${2:-}"
glob="${3:-*}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ -z "$pattern" ]]; then
  echo '{"pass":false,"score":0,"details":"No pattern specified","grader_version":"1.0.0"}'
  exit 2
fi

# Search for pattern in matching files
match_count=0
matched_files=()

while IFS= read -r -d '' file; do
  if grep -qlE "$pattern" "$file" 2>/dev/null; then
    match_count=$((match_count + 1))
    matched_files+=("$(basename "$file")")
  fi
done < <(find "$workspace" -name "$glob" -type f -print0 2>/dev/null)

if [[ $match_count -gt 0 ]]; then
  files_list="$(printf '%s, ' "${matched_files[@]}")"
  echo '{"pass":true,"score":100,"details":"Pattern found in '"$match_count"' file(s): '"${files_list%, }"'","grader_version":"1.0.0"}'
  exit 0
else
  echo '{"pass":false,"score":0,"details":"Pattern not found in any '"$glob"' files","grader_version":"1.0.0"}'
  exit 1
fi
