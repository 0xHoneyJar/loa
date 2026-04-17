#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Write Adversarial Review Gate
# =============================================================================
# Blocks Write tool calls targeting */COMPLETED when flatline_protocol is
# enabled in .loa.config.yaml but the corresponding adversarial-*.json
# artefact is missing from the sprint directory.
#
# Catches the class of bug where reviewing-code / auditing-security skills
# execute inline and silently skip Phase 2.5 (cross-model adversarial review).
#
# Fail-open on any parse error. Opt-out via LOA_ADVERSARIAL_REVIEW_ENFORCE=false.
# Test override for config path: LOA_CONFIG_PATH_OVERRIDE.
#
# Contract (hook):
#   stdin  = {tool_name, tool_input: {file_path, ...}}
#   exit 0 = allow (also emitted for unparseable input or non-Write calls)
#   exit 1 = block (with message on stderr)
# =============================================================================

# No `set -euo pipefail` — this hook must never fail closed. A jq or yq
# failure, a missing config file, a malformed path all must allow the write.

# Opt-out first (cheapest check)
if [[ "${LOA_ADVERSARIAL_REVIEW_ENFORCE:-true}" == "false" ]]; then
  exit 0
fi

# Read tool input from stdin
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Only gate Write calls to */COMPLETED markers
[[ "$tool_name" == "Write" ]] || exit 0
[[ "$file_path" == */COMPLETED ]] || exit 0

sprint_dir=$(dirname "$file_path")
config="${LOA_CONFIG_PATH_OVERRIDE:-.loa.config.yaml}"
[[ -f "$config" ]] || exit 0

# Read config — fallback to false on any yq error
code_review_enabled=$(yq '.flatline_protocol.code_review.enabled // false' "$config" 2>/dev/null) || code_review_enabled="false"
audit_enabled=$(yq '.flatline_protocol.security_audit.enabled // false' "$config" 2>/dev/null) || audit_enabled="false"

missing=()
if [[ "$code_review_enabled" == "true" ]]; then
  [[ -f "$sprint_dir/adversarial-review.json" ]] || missing+=("adversarial-review.json")
fi
if [[ "$audit_enabled" == "true" ]]; then
  [[ -f "$sprint_dir/adversarial-audit.json" ]] || missing+=("adversarial-audit.json")
fi

if (( ${#missing[@]} > 0 )); then
  {
    echo "BLOCKED: adversarial review required before COMPLETED marker"
    echo "  Sprint dir: $sprint_dir"
    echo "  Config requests: code_review=$code_review_enabled, security_audit=$audit_enabled"
    echo "  Missing: ${missing[*]}"
    echo ""
    echo "  To proceed, run Phase 2.5 cross-model review:"
    echo "    .claude/scripts/adversarial-review.sh \\"
    echo "      --type review --sprint-id \$(basename $sprint_dir) \\"
    echo "      --diff-file <path-to-diff>"
    echo ""
    echo "  Emergency override: LOA_ADVERSARIAL_REVIEW_ENFORCE=false (not recommended)"
  } >&2
  exit 1
fi

exit 0
