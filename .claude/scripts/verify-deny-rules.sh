#!/usr/bin/env bash
# =============================================================================
# Verify Deny Rules — Check actual vs intended permission state
# =============================================================================
# Compares deny rules from the template (.claude/hooks/settings.deny.json)
# against the live settings (~/.claude/settings.json). Reports missing,
# present, and extra rules.
#
# Inspired by AWS IAM simulate-principal-policy: verify the ACTUAL permission
# state matches the INTENDED permission state.
#
# Usage:
#   verify-deny-rules.sh          # Human-readable output
#   verify-deny-rules.sh --json   # Machine-readable JSON
#
# Exit codes:
#   0 = all template rules are present
#   1 = one or more template rules are missing
#
# Source: Bridgebuilder Deep Review Critical 2
# Part of Loa Harness Engineering (cycle-011, issue #297)
# =============================================================================

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DENY_TEMPLATE=".claude/hooks/settings.deny.json"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    -h|--help)
      echo "Usage: verify-deny-rules.sh [--json]"
      echo ""
      echo "  --json  Machine-readable JSON output"
      echo ""
      echo "Compares deny rules in ~/.claude/settings.json against"
      echo "the template in .claude/hooks/settings.deny.json."
      exit 0
      ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate template exists
# ---------------------------------------------------------------------------
if [[ ! -f "$DENY_TEMPLATE" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -cn '{"status":"error","message":"Template not found","template_path":""}'
    exit 1
  else
    echo "ERROR: Deny rules template not found at $DENY_TEMPLATE" >&2
    exit 1
  fi
fi

# Check jq is available
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Handle missing settings.json gracefully
# ---------------------------------------------------------------------------
if [[ ! -f "$SETTINGS" ]]; then
  template_count=$(jq '.permissions.deny | length' "$DENY_TEMPLATE")
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -cn \
      --argjson missing "$template_count" \
      --arg settings_path "$SETTINGS" \
      '{
        status: "missing_settings",
        settings_path: $settings_path,
        present: 0,
        missing: $missing,
        extra: 0,
        missing_rules: [],
        extra_rules: []
      }'
  else
    echo "Deny Rule Verification"
    echo "======================"
    echo ""
    echo "Settings file not found: $SETTINGS"
    echo "All $template_count template rules are missing."
    echo ""
    echo "Run: bash .claude/scripts/install-deny-rules.sh --auto"
  fi
  exit 1
fi

# ---------------------------------------------------------------------------
# Compare template rules against live settings
# ---------------------------------------------------------------------------
# Get template rules as array
template_rules=$(jq -r '.permissions.deny[]' "$DENY_TEMPLATE" | sort)
template_count=$(echo "$template_rules" | wc -l | tr -d ' ')

# Get live rules as array
live_rules=$(jq -r '.permissions.deny[]? // empty' "$SETTINGS" 2>/dev/null | sort)
live_count=0
if [[ -n "$live_rules" ]]; then
  live_count=$(echo "$live_rules" | wc -l | tr -d ' ')
fi

# Find missing rules (in template but not in live)
missing_rules=""
missing_count=0
while IFS= read -r rule; do
  if [[ -n "$live_rules" ]]; then
    if ! echo "$live_rules" | grep -qxF "$rule"; then
      missing_rules="${missing_rules}${rule}"$'\n'
      missing_count=$((missing_count + 1))
    fi
  else
    missing_rules="${missing_rules}${rule}"$'\n'
    missing_count=$((missing_count + 1))
  fi
done <<< "$template_rules"

# Find extra rules (in live but not in template)
extra_rules=""
extra_count=0
if [[ -n "$live_rules" ]]; then
  while IFS= read -r rule; do
    if ! echo "$template_rules" | grep -qxF "$rule"; then
      extra_rules="${extra_rules}${rule}"$'\n'
      extra_count=$((extra_count + 1))
    fi
  done <<< "$live_rules"
fi

present_count=$((template_count - missing_count))

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Build JSON arrays for missing and extra rules
  missing_json="[]"
  if [[ -n "$missing_rules" ]]; then
    missing_json=$(echo -n "$missing_rules" | head -c -1 | jq -R -s 'split("\n") | map(select(length > 0))')
  fi

  extra_json="[]"
  if [[ -n "$extra_rules" ]]; then
    extra_json=$(echo -n "$extra_rules" | head -c -1 | jq -R -s 'split("\n") | map(select(length > 0))')
  fi

  jq -cn \
    --argjson present "$present_count" \
    --argjson missing "$missing_count" \
    --argjson extra "$extra_count" \
    --argjson missing_rules "$missing_json" \
    --argjson extra_rules "$extra_json" \
    '{
      status: (if $missing == 0 then "pass" else "fail" end),
      present: $present,
      missing: $missing,
      extra: $extra,
      missing_rules: $missing_rules,
      extra_rules: $extra_rules
    }'
else
  echo "Deny Rule Verification"
  echo "======================"
  echo ""
  echo "Template: $DENY_TEMPLATE ($template_count rules)"
  echo "Settings: $SETTINGS ($live_count rules)"
  echo ""
  printf "  Present: %d\n" "$present_count"
  printf "  Missing: %d\n" "$missing_count"
  printf "  Extra:   %d\n" "$extra_count"

  if [[ "$missing_count" -gt 0 ]]; then
    echo ""
    echo "Missing rules:"
    echo "$missing_rules" | while IFS= read -r r; do
      [[ -n "$r" ]] && echo "  - $r"
    done
  fi

  if [[ "$extra_count" -gt 0 ]]; then
    echo ""
    echo "Extra rules (not in template):"
    echo "$extra_rules" | while IFS= read -r r; do
      [[ -n "$r" ]] && echo "  + $r"
    done
  fi

  echo ""
  if [[ "$missing_count" -eq 0 ]]; then
    echo "All template rules are active."
  else
    echo "Run: bash .claude/scripts/install-deny-rules.sh --auto"
  fi
fi

# Exit code
if [[ "$missing_count" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
