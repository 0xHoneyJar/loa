#!/usr/bin/env bash
# normalize-json.sh — Centralized JSON response normalization library
# Version: 1.0.0
#
# Functions:
#   normalize_json_response  — strips BOM, fences, prefixes, extracts first JSON object/array
#   validate_json_field      — type-aware field validation
#   validate_agent_response  — per-agent schema validation dispatch
#
# Dependencies: jq (required), python3 3.6+ (optional, fallback to jq-only)

set -euo pipefail

# =============================================================================
# normalize_json_response
# =============================================================================
#
# Extract the first valid JSON object or array from model output.
# Handles: raw JSON, markdown fences, prose-wrapped JSON, BOM prefixes.
#
# Usage:
#   normalize_json_response "$raw_output"
#   echo "$raw_output" | normalize_json_response
#
# Returns: Clean JSON on stdout, exit 0 on success, exit 1 on failure.

normalize_json_response() {
  local input="${1:-}"

  # Support piped input
  if [[ -z "$input" ]] && [[ ! -t 0 ]]; then
    input=$(cat)
  fi

  if [[ -z "$input" ]]; then
    echo "ERROR: normalize_json_response: empty input" >&2
    return 1
  fi

  # Step 1: Strip BOM (UTF-8 BOM: EF BB BF)
  input="${input#$'\xef\xbb\xbf'}"

  # Step 2: Strip markdown fences (```json ... ```)
  # Optimization (BB-017): store fence-extracted content to avoid re-piping
  local stripped
  stripped=$(echo "$input" | sed -n '/^```[jJ][sS][oO][nN]\?[[:space:]]*$/,/^```[[:space:]]*$/{/^```/d;p}')
  if [[ -n "$stripped" ]]; then
    # Validate and format in single jq invocation
    local fenced_result
    if fenced_result=$(echo "$stripped" | jq '.' 2>/dev/null); then
      echo "$fenced_result"
      return 0
    fi
  fi

  # Step 3: Try raw input as valid JSON directly
  # Optimization (BB-017): single jq invocation for validate + format
  local raw_result
  if raw_result=$(echo "$input" | jq '.' 2>/dev/null); then
    echo "$raw_result"
    return 0
  fi

  # Step 4: Extract first JSON object/array using python3 raw_decode
  if command -v python3 &>/dev/null; then
    local extracted
    extracted=$(python3 -c '
import json, sys

text = sys.stdin.read().strip()
decoder = json.JSONDecoder()

# Find first { or [ in the text
for i, ch in enumerate(text):
    if ch in "{[":
        try:
            obj, end = decoder.raw_decode(text, i)
            print(json.dumps(obj))
            sys.exit(0)
        except json.JSONDecodeError:
            continue

sys.exit(1)
' <<< "$input" 2>/dev/null)

    if [[ $? -eq 0 ]] && [[ -n "$extracted" ]]; then
      echo "$extracted" | jq '.'
      return 0
    fi
  else
    echo "WARNING: python3 not available — using jq-only extraction path" >&2
  fi

  # Step 5: jq-only fallback — try stripping common prose prefixes
  # NOTE: This is a last-resort path that only fires when python3 is unavailable.
  # The sed pattern is greedy: it strips everything before the first { or [ and
  # after the last } or ]. This means inputs with multiple JSON-like fragments
  # (e.g., "Result: {x} and also {"real": "json"}") may select the wrong fragment.
  # Step 4 (python3 raw_decode) handles this case correctly. The sed fallback
  # trades precision for universality — it works without python3 but may fail
  # on ambiguous inputs. The jq validation below catches invalid extractions.
  local patterns=(
    's/^[^{[]*//;s/[^}\]]*$//'  # Strip everything before first { or [ and after last } or ]
  )

  for pattern in "${patterns[@]}"; do
    local attempt
    attempt=$(echo "$input" | sed "$pattern")
    if [[ -n "$attempt" ]] && echo "$attempt" | jq empty 2>/dev/null; then
      echo "$attempt" | jq '.'
      return 0
    fi
  done

  echo "ERROR: normalize_json_response: no valid JSON found in input" >&2
  return 1
}

# =============================================================================
# extract_verdict
# =============================================================================
#
# Extract verdict from a JSON response, supporting both .verdict (primary)
# and .overall_verdict (fallback) field names.
#
# Usage:
#   extract_verdict "$json"
#   echo "$json" | extract_verdict
#
# Returns: verdict string on stdout, exit 0 on success, exit 1 if neither field present.

extract_verdict() {
  local json="${1:-$(cat)}"
  local verdict
  verdict=$(echo "$json" | jq -r '
    (.verdict | select(. != null and . != "")) //
    (.overall_verdict | select(. != null and . != "")) //
    empty
  ' 2>/dev/null)
  if [[ -z "$verdict" ]]; then
    return 1
  fi
  echo "$verdict"
}

# =============================================================================
# validate_json_field
# =============================================================================
#
# Type-aware field validation using jq.
#
# Usage:
#   validate_json_field "$json" "field_name" "type"
#
# Supported types: string, number, integer, boolean, array, object, null
# Returns: exit 0 if valid, exit 1 if field missing/wrong type.

validate_json_field() {
  local json="$1"
  local field="$2"
  local expected_type="$3"

  # Check field exists and is not null
  local value
  value=$(echo "$json" | jq -e ".$field" 2>/dev/null) || {
    echo "ERROR: validate_json_field: field '.$field' missing or null" >&2
    return 1
  }

  # Type check
  local actual_type
  actual_type=$(echo "$json" | jq -r ".$field | type" 2>/dev/null)

  case "$expected_type" in
    integer)
      # jq reports integers as "number" — check it's a whole number
      if [[ "$actual_type" != "number" ]]; then
        echo "ERROR: validate_json_field: '.$field' expected integer, got $actual_type" >&2
        return 1
      fi
      local is_int
      is_int=$(echo "$json" | jq ".$field | . == (. | floor)" 2>/dev/null)
      if [[ "$is_int" != "true" ]]; then
        echo "ERROR: validate_json_field: '.$field' expected integer, got float" >&2
        return 1
      fi
      ;;
    *)
      if [[ "$actual_type" != "$expected_type" ]]; then
        echo "ERROR: validate_json_field: '.$field' expected $expected_type, got $actual_type" >&2
        return 1
      fi
      ;;
  esac

  return 0
}

# =============================================================================
# validate_agent_response
# =============================================================================
#
# Per-agent schema validation dispatch.
#
# Usage:
#   validate_agent_response "$json" "agent-name"
#
# Supported agents: flatline-reviewer, flatline-skeptic, flatline-scorer, gpt-reviewer
# Returns: exit 0 if valid, exit 1 if schema violation.

validate_agent_response() {
  local json="$1"
  local agent="$2"
  local errors=0

  case "$agent" in
    flatline-reviewer)
      validate_json_field "$json" "improvements" "array" || errors=$((errors + 1))
      # Validate each improvement has required fields
      local count
      count=$(echo "$json" | jq '.improvements | length' 2>/dev/null || echo "0")
      # An empty finding set is valid only when the reviewer proves it did
      # substantive work. A bare {"improvements":[]} (or generic summary)
      # is indistinguishable from truncation/refusal/default normalization and
      # must not count toward council quorum.
      if [[ "$count" -eq 0 ]]; then
        validate_json_field "$json" "no_findings_reason" "string" || errors=$((errors + 1))
        validate_json_field "$json" "reviewed_sections" "array" || errors=$((errors + 1))

        local reason_len sections_count
        reason_len=$(echo "$json" | jq -r '.no_findings_reason // "" | length' 2>/dev/null || echo "0")
        sections_count=$(echo "$json" | jq -r '.reviewed_sections // [] | length' 2>/dev/null || echo "0")

        if [[ "$reason_len" -lt 40 ]]; then
          echo "ERROR: empty flatline-reviewer response requires no_findings_reason of at least 40 characters" >&2
          errors=$((errors + 1))
        fi
        if [[ "$sections_count" -lt 1 ]]; then
          echo "ERROR: empty flatline-reviewer response requires at least one reviewed_sections entry" >&2
          errors=$((errors + 1))
        elif ! echo "$json" | jq -e 'all(.reviewed_sections[]; type == "string" and length > 0)' &>/dev/null; then
          echo "ERROR: reviewed_sections entries must be non-empty strings" >&2
          errors=$((errors + 1))
        fi
      fi
      for ((i = 0; i < count; i++)); do
        local item
        item=$(echo "$json" | jq ".improvements[$i]" 2>/dev/null)
        for field in id description priority; do
          echo "$item" | jq -e ".$field" &>/dev/null || {
            echo "ERROR: improvements[$i] missing required field: $field" >&2
            errors=$((errors + 1))
          }
        done
      done
      ;;

    flatline-skeptic)
      validate_json_field "$json" "concerns" "array" || errors=$((errors + 1))
      local count
      count=$(echo "$json" | jq '.concerns | length' 2>/dev/null || echo "0")
      for ((i = 0; i < count; i++)); do
        local item
        item=$(echo "$json" | jq ".concerns[$i]" 2>/dev/null)
        for field in id concern severity severity_score; do
          echo "$item" | jq -e ".$field" &>/dev/null || {
            echo "ERROR: concerns[$i] missing required field: $field" >&2
            errors=$((errors + 1))
          }
        done
        # Validate severity_score is integer 0-1000
        local score
        score=$(echo "$item" | jq '.severity_score // -1 | floor' 2>/dev/null)
        if [[ "$score" -lt 0 ]] || [[ "$score" -gt 1000 ]] 2>/dev/null; then
          echo "ERROR: concerns[$i].severity_score out of range (0-1000): $score" >&2
          errors=$((errors + 1))
        fi
      done
      ;;

    flatline-scorer)
      validate_json_field "$json" "scores" "array" || errors=$((errors + 1))
      local count
      count=$(echo "$json" | jq '.scores | length' 2>/dev/null || echo "0")
      for ((i = 0; i < count; i++)); do
        local item
        item=$(echo "$json" | jq ".scores[$i]" 2>/dev/null)
        for field in id score; do
          echo "$item" | jq -e ".$field" &>/dev/null || {
            echo "ERROR: scores[$i] missing required field: $field" >&2
            errors=$((errors + 1))
          }
        done
      done
      ;;

    gpt-reviewer)
      # Validate verdict field — supports .verdict and .overall_verdict fallback
      local verdict
      if verdict=$(extract_verdict "$json"); then
        case "$verdict" in
          APPROVED|CHANGES_REQUIRED|DECISION_NEEDED|SKIPPED) ;;
          *)
            echo "ERROR: invalid verdict value: '$verdict' (expected APPROVED|CHANGES_REQUIRED|DECISION_NEEDED|SKIPPED)" >&2
            errors=$((errors + 1))
            ;;
        esac
      else
        echo "ERROR: validate_json_field: field '.verdict' missing or null" >&2
        errors=$((errors + 1))
      fi
      ;;

    *)
      echo "WARNING: validate_agent_response: unknown agent '$agent' — skipping validation" >&2
      return 0
      ;;
  esac

  if [[ $errors -gt 0 ]]; then
    echo "ERROR: validate_agent_response: $errors validation error(s) for agent '$agent'" >&2
    return 1
  fi

  return 0
}
