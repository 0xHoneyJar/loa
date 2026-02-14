#!/usr/bin/env bash
# bridge-findings-parser.sh - Extract structured findings from Bridgebuilder review
# Version: 2.0.0
#
# Parses findings from Bridgebuilder review output. Supports two formats:
#   1. JSON fenced block between bridge-findings markers (v2, preferred)
#   2. Legacy markdown field-based findings (v1, fallback)
#
# Strict grammar (v2): exactly one findings block, markers required,
# JSON fence required, fail closed on violations.
#
# Usage:
#   bridge-findings-parser.sh --input review.md --output findings.json
#
# Exit Codes:
#   0 - Success
#   1 - Parse error (invalid JSON)
#   2 - Missing input
#   3 - Strict grammar violation (multiple blocks, missing fence, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Severity Weights
# =============================================================================

declare -A SEVERITY_WEIGHTS=(
  ["CRITICAL"]=10
  ["HIGH"]=5
  ["MEDIUM"]=2
  ["LOW"]=1
  ["VISION"]=0
  ["PRAISE"]=0
  ["SPECULATION"]=0
)

# =============================================================================
# Arguments
# =============================================================================

INPUT_FILE=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --input requires a value" >&2
        exit 2
      fi
      INPUT_FILE="$2"
      shift 2
      ;;
    --output)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --output requires a value" >&2
        exit 2
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: bridge-findings-parser.sh --input <markdown> --output <json>"
      echo ""
      echo "Extracts findings between <!-- bridge-findings-start --> and"
      echo "<!-- bridge-findings-end --> markers from Bridgebuilder review markdown."
      echo ""
      echo "Supports two formats:"
      echo "  JSON fenced block (v2): structured JSON inside markers"
      echo "  Legacy markdown (v1):   field-based markdown findings"
      echo ""
      echo "Options:"
      echo "  --input FILE    Input markdown file (required)"
      echo "  --output FILE   Output JSON file (required)"
      echo ""
      echo "Exit Codes:"
      echo "  0  Success"
      echo "  1  Parse error (invalid JSON)"
      echo "  2  Missing input"
      echo "  3  Strict grammar violation"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$INPUT_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
  echo "ERROR: --input and --output are required" >&2
  exit 2
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: Input file not found: $INPUT_FILE" >&2
  exit 2
fi

# =============================================================================
# Extraction
# =============================================================================

# Extract content between markers
extract_findings_block() {
  local file="$1"
  local in_block=false
  local block=""

  while IFS= read -r line; do
    if [[ "$line" == *"bridge-findings-start"* ]]; then
      in_block=true
      continue
    fi
    if [[ "$line" == *"bridge-findings-end"* ]]; then
      in_block=false
      continue
    fi
    if [[ "$in_block" == "true" ]]; then
      block+="$line"$'\n'
    fi
  done < "$file"

  echo "$block"
}

# =============================================================================
# JSON Extraction (v2 — preferred)
# =============================================================================

# Extract and validate JSON from a fenced block within the findings markers.
# Enforces strict grammar: exactly one JSON fence, valid JSON, schema_version.
# Returns findings array on stdout.
extract_and_validate_json() {
  local block="$1"

  local json_content=""
  local in_fence=false
  local fence_count=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^\`\`\`json[[:space:]]*$ ]]; then
      if [[ "$in_fence" == "true" ]]; then
        echo "ERROR: Nested JSON fence detected — strict grammar violation" >&2
        return 3
      fi
      fence_count=$((fence_count + 1))
      if [[ "$fence_count" -gt 1 ]]; then
        echo "ERROR: Multiple JSON fences detected — strict grammar requires exactly one" >&2
        return 3
      fi
      in_fence=true
      continue
    fi
    if [[ "$line" == '```' ]] && [[ "$in_fence" == "true" ]]; then
      in_fence=false
      continue
    fi
    if [[ "$in_fence" == "true" ]]; then
      json_content+="$line"$'\n'
    fi
  done <<< "$block"

  if [[ "$fence_count" -eq 0 ]]; then
    echo "ERROR: No JSON fence found in findings block — strict grammar violation" >&2
    return 3
  fi

  if [[ "$in_fence" == "true" ]]; then
    echo "ERROR: Unclosed JSON fence — truncated output" >&2
    return 3
  fi

  # Validate JSON
  if ! printf '%s' "$json_content" | jq empty 2>/dev/null; then
    echo "ERROR: Findings block contains invalid JSON" >&2
    return 1
  fi

  # Check schema_version
  local version
  version=$(printf '%s' "$json_content" | jq -r '.schema_version // empty')
  if [[ -z "$version" ]]; then
    echo "WARNING: Findings JSON missing schema_version — treating as v1" >&2
  fi

  # Return the full JSON content (findings + metadata preserved)
  printf '%s' "$json_content"
}

# =============================================================================
# Legacy Markdown Parsing (v1 — fallback)
# =============================================================================

# Parse individual findings from legacy markdown format.
# This is the original parser preserved for backward compatibility.
parse_findings_legacy() {
  local block="$1"
  local tmp_findings
  tmp_findings=$(mktemp)
  trap "rm -f '$tmp_findings'" EXIT
  local current_id=""
  local current_title=""
  local current_severity=""
  local current_category=""
  local current_file=""
  local current_description=""
  local current_suggestion=""
  local current_potential=""
  local in_finding=false

  flush_finding() {
    if [[ -n "$current_id" ]]; then
      local weight=${SEVERITY_WEIGHTS[${current_severity^^}]:-0}
      # Clean values (trim newlines and trailing whitespace)
      # Note: jq --arg handles JSON string escaping automatically — no manual sed needed
      local esc_title esc_desc esc_sug esc_file esc_cat esc_pot
      esc_title=$(echo "$current_title" | tr -d '\n')
      esc_desc=$(echo "$current_description" | tr -d '\n' | sed 's/[[:space:]]*$//')
      esc_sug=$(echo "$current_suggestion" | tr -d '\n' | sed 's/[[:space:]]*$//')
      esc_file=$(echo "$current_file" | tr -d '\n')
      esc_cat=$(echo "$current_category" | tr -d '\n')
      esc_pot=$(echo "$current_potential" | tr -d '\n' | sed 's/[[:space:]]*$//')

      # Append individual finding JSON to temp file (O(1) per finding)
      jq -n -c \
        --arg id "$current_id" \
        --arg title "$esc_title" \
        --arg severity "${current_severity^^}" \
        --arg category "$esc_cat" \
        --arg file "$esc_file" \
        --arg description "$esc_desc" \
        --arg suggestion "$esc_sug" \
        --arg potential "$esc_pot" \
        --argjson weight "$weight" \
        '{id: $id, title: $title, severity: $severity, category: $category, file: $file, description: $description, suggestion: $suggestion, potential: $potential, weight: $weight}' \
        >> "$tmp_findings"
    fi

    current_id=""
    current_title=""
    current_severity=""
    current_category=""
    current_file=""
    current_description=""
    current_suggestion=""
    current_potential=""
  }

  while IFS= read -r line; do
    # Detect finding header: ### [SEVERITY-N] Title
    if [[ "$line" =~ ^###[[:space:]]+\[([A-Z]+)-([0-9]+)\][[:space:]]+(.+)$ ]]; then
      flush_finding
      current_severity="${BASH_REMATCH[1]}"
      local num="${BASH_REMATCH[2]}"
      current_title="${BASH_REMATCH[3]}"
      current_id="${current_severity,,}-${num}"
      in_finding=true
      continue
    fi

    if [[ "$in_finding" == "true" ]]; then
      # Parse field lines
      if [[ "$line" =~ ^\*\*Severity\*\*:[[:space:]]*(.+)$ ]]; then
        current_severity="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*Category\*\*:[[:space:]]*(.+)$ ]]; then
        current_category="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*File\*\*:[[:space:]]*(.+)$ ]]; then
        current_file="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*Type\*\*:[[:space:]]*(.+)$ ]]; then
        # Vision type
        current_category="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*Description\*\*:[[:space:]]*(.+)$ ]]; then
        current_description="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*Suggestion\*\*:[[:space:]]*(.+)$ ]]; then
        current_suggestion="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\*\*Potential\*\*:[[:space:]]*(.+)$ ]]; then
        current_potential="${BASH_REMATCH[1]}"
      fi
    fi
  done <<< "$block"

  # Flush last finding
  flush_finding

  # Slurp all findings into a JSON array in a single pass (O(n) total)
  local findings
  if [[ -s "$tmp_findings" ]]; then
    findings=$(jq -s '.' "$tmp_findings")
  else
    findings="[]"
  fi
  # Cleanup handled by trap EXIT — no explicit rm needed

  echo "$findings"
}

# =============================================================================
# Main
# =============================================================================

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

# Strict grammar: count markers in input file
start_count=$(grep -c 'bridge-findings-start' "$INPUT_FILE" || true)
end_count=$(grep -c 'bridge-findings-end' "$INPUT_FILE" || true)

if [[ "$start_count" -gt 1 ]] || [[ "$end_count" -gt 1 ]]; then
  echo "ERROR: Multiple findings blocks detected — strict grammar requires exactly one" >&2
  exit 3
fi

# Extract findings block
findings_block=$(extract_findings_block "$INPUT_FILE")

if [[ -z "$findings_block" ]] || [[ "$findings_block" =~ ^[[:space:]]*$ ]]; then
  # No findings markers found — output empty result
  cat > "$OUTPUT_FILE" <<'EOF'
{
  "schema_version": 1,
  "findings": [],
  "total": 0,
  "by_severity": {"critical": 0, "high": 0, "medium": 0, "low": 0, "vision": 0, "praise": 0, "speculation": 0},
  "severity_weighted_score": 0
}
EOF
  echo "No findings markers found in input"
  exit 0
fi

# Detect format: JSON fenced block (v2) vs legacy markdown (v1)
findings_array=""
schema_version=1

if printf '%s' "$findings_block" | grep -q '```json'; then
  # v2: JSON fenced block extraction
  json_content=$(extract_and_validate_json "$findings_block")
  rc=$?
  if [[ $rc -ne 0 ]]; then
    exit $rc
  fi

  # Extract schema_version from the JSON
  schema_version=$(printf '%s' "$json_content" | jq -r '.schema_version // 1')

  # Extract findings array — preserves all enriched fields
  findings_array=$(printf '%s' "$json_content" | jq -c '[.findings[] | . + {weight: (
    if .severity == "CRITICAL" then 10
    elif .severity == "HIGH" then 5
    elif .severity == "MEDIUM" then 2
    elif .severity == "LOW" then 1
    elif .severity == "VISION" then 0
    elif .severity == "PRAISE" then 0
    elif .severity == "SPECULATION" then 0
    else 0
    end
  )}]')
else
  # v1: Legacy markdown parsing (fallback)
  findings_array=$(parse_findings_legacy "$findings_block")
fi

# Compute aggregates
total=$(printf '%s' "$findings_array" | jq 'length')
by_critical=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "CRITICAL")] | length')
by_high=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "HIGH")] | length')
by_medium=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "MEDIUM")] | length')
by_low=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "LOW")] | length')
by_vision=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "VISION")] | length')
by_praise=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "PRAISE")] | length')
by_speculation=$(printf '%s' "$findings_array" | jq '[.[] | select(.severity == "SPECULATION")] | length')
weighted_score=$(printf '%s' "$findings_array" | jq '[.[].weight] | add // 0')

# Write output
jq -n \
  --argjson schema_version "$schema_version" \
  --argjson findings "$findings_array" \
  --argjson total "$total" \
  --argjson critical "$by_critical" \
  --argjson high "$by_high" \
  --argjson medium "$by_medium" \
  --argjson low "$by_low" \
  --argjson vision "$by_vision" \
  --argjson praise "$by_praise" \
  --argjson speculation "$by_speculation" \
  --argjson score "$weighted_score" \
  '{
    schema_version: $schema_version,
    findings: $findings,
    total: $total,
    by_severity: {critical: $critical, high: $high, medium: $medium, low: $low, vision: $vision, praise: $praise, speculation: $speculation},
    severity_weighted_score: $score
  }' > "$OUTPUT_FILE"

echo "Parsed $total findings (score: $weighted_score) → $OUTPUT_FILE"
