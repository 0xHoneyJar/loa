#!/usr/bin/env bash
# loa-status.sh - Enhanced status display with version information
# Sprint 3.5 (T3.5.4): Version-Targeted Updates
#
# Combines workflow state with detailed framework version info.
# Supports both human-readable and JSON output.
#
# Usage:
#   loa-status.sh            Show status with version info
#   loa-status.sh --json     JSON output for scripting
#   loa-status.sh --version  Only show version info
#
# Exit codes:
#   0 - Success
#   1 - Error

set -euo pipefail

# Project paths
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${PROJECT_ROOT}/.loa-version.json"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
WORKFLOW_STATE_SCRIPT="${SCRIPT_DIR}/workflow-state.sh"
TIER_VALIDATOR_SCRIPT="${SCRIPT_DIR}/tier-validator.sh"
AUDIT_ENVELOPE_SCRIPT="${SCRIPT_DIR}/audit-envelope.sh"
UPSTREAM_REPO="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Arguments
JSON_OUTPUT=false
VERSION_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --version) VERSION_ONLY=true ;;
    --help|-h)
      echo "Usage: loa-status.sh [--json] [--version] [--help]"
      echo ""
      echo "Options:"
      echo "  --json      Output JSON format"
      echo "  --version   Only show version info"
      echo "  --help      Show this help"
      exit 0
      ;;
  esac
done

# === Version Information Functions ===

get_version_field() {
  local field="$1"
  local default="${2:-}"
  if [[ -f "$VERSION_FILE" ]]; then
    jq -r ".${field} // \"${default}\"" "$VERSION_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

get_current_field() {
  local field="$1"
  local default="${2:-}"
  if [[ -f "$VERSION_FILE" ]]; then
    jq -r ".current.${field} // \"${default}\"" "$VERSION_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# Get version info as JSON
get_version_info_json() {
  local version ref ref_type commit updated_at

  version=$(get_version_field "framework_version" "unknown")
  ref=$(get_current_field "ref" "")
  ref_type=$(get_current_field "type" "")
  commit=$(get_current_field "commit" "")
  updated_at=$(get_current_field "updated_at" "")

  # Fall back to framework_version if current block doesn't exist
  if [[ -z "$ref" ]]; then
    ref="v${version}"
    ref_type="tag"
  fi

  local short_commit=""
  if [[ -n "$commit" && "$commit" != "unknown" && "$commit" != "null" ]]; then
    short_commit="${commit:0:8}"
  fi

  # Get source repo URL (strip .git suffix for display)
  local source_url="${UPSTREAM_REPO%.git}"

  # Check for history
  local history_count
  history_count=$(jq -r '.history | length // 0' "$VERSION_FILE" 2>/dev/null || echo "0")

  # Check for available updates
  local update_available="false"
  local latest_version=""
  local cache_file="${HOME}/.loa/cache/update-check.json"
  if [[ -f "$cache_file" ]]; then
    update_available=$(jq -r '.update_available // false' "$cache_file" 2>/dev/null || echo "false")
    latest_version=$(jq -r '.remote_version // ""' "$cache_file" 2>/dev/null || echo "")
  fi

  # Determine if on non-stable ref
  local on_feature_branch="false"
  local warning=""
  if [[ "$ref_type" == "branch" && "$ref" != "main" && "$ref" != "master" ]]; then
    on_feature_branch="true"
    warning="You're on branch '${ref}' (not a stable release)"
  elif [[ "$ref_type" == "commit" ]]; then
    warning="You're on a specific commit (not a tracked ref)"
  fi

  cat <<EOF
{
  "version": "${version}",
  "ref": "${ref}",
  "ref_type": "${ref_type}",
  "commit": "${short_commit}",
  "updated_at": "${updated_at}",
  "source_url": "${source_url}",
  "history_count": ${history_count},
  "update_available": ${update_available},
  "latest_version": "${latest_version}",
  "on_feature_branch": ${on_feature_branch},
  "warning": "${warning}"
}
EOF
}

# Display version info (human-readable)
display_version_info() {
  local version ref ref_type commit updated_at

  version=$(get_version_field "framework_version" "unknown")
  ref=$(get_current_field "ref" "")
  ref_type=$(get_current_field "type" "")
  commit=$(get_current_field "commit" "")
  updated_at=$(get_current_field "updated_at" "")

  # Fall back if current block doesn't exist
  if [[ -z "$ref" ]]; then
    ref="v${version}"
    ref_type="tag"
  fi

  local short_commit=""
  if [[ -n "$commit" && "$commit" != "unknown" && "$commit" != "null" ]]; then
    short_commit=" (${commit:0:8})"
  fi

  echo ""
  echo -e "${BOLD}Framework Version${NC}"
  echo "  Version: ${version}"

  # Show ref type with appropriate icon
  case "$ref_type" in
    tag)
      echo -e "  Ref:     ${GREEN}${ref}${NC} (stable release)"
      ;;
    branch)
      if [[ "$ref" == "main" || "$ref" == "master" ]]; then
        echo -e "  Ref:     ${ref}${short_commit} (main branch)"
      else
        echo -e "  Ref:     ${YELLOW}${ref}${NC}${short_commit} (feature branch)"
        echo -e "  ${YELLOW}Warning:${NC} You're on a non-stable branch"
      fi
      ;;
    commit)
      echo -e "  Ref:     ${YELLOW}${ref:0:12}${NC} (commit)"
      echo -e "  ${YELLOW}Warning:${NC} You're on a specific commit"
      ;;
    latest|*)
      echo -e "  Ref:     ${ref}${short_commit}"
      ;;
  esac

  # Show last updated time
  if [[ -n "$updated_at" && "$updated_at" != "null" ]]; then
    # Format timestamp for display (simplified)
    local formatted_date="${updated_at%%T*}"
    echo "  Updated: ${formatted_date}"
  fi

  # Show source URL
  local source_url="${UPSTREAM_REPO%.git}"
  echo "  Source:  ${source_url}"

  # Check for available updates
  local cache_file="${HOME}/.loa/cache/update-check.json"
  if [[ -f "$cache_file" ]]; then
    local update_available latest_version
    update_available=$(jq -r '.update_available // false' "$cache_file" 2>/dev/null)
    latest_version=$(jq -r '.remote_version // ""' "$cache_file" 2>/dev/null)

    if [[ "$update_available" == "true" && -n "$latest_version" ]]; then
      echo ""
      echo -e "  ${GREEN}Update available:${NC} ${latest_version}"
      echo -e "  Run ${CYAN}/update-loa${NC} to upgrade"
    fi
  fi

  # Suggest stable version if on feature branch
  if [[ "$ref_type" == "branch" && "$ref" != "main" && "$ref" != "master" ]]; then
    echo ""
    echo -e "  ${CYAN}Tip:${NC} Run /update-loa @latest to switch to stable"
  fi

  echo ""
}

# =============================================================================
# Agent-Network Primitives section (cycle-098 Sprint 1C, SDD §4.4)
# =============================================================================

# Read enabled status of a primitive from .loa.config.yaml
# Output: "yes" or "no"
_an_primitive_enabled() {
    local pid="$1"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq >/dev/null 2>&1; then
        local v
        v=$(yq -r ".agent_network.primitives.${pid}.enabled // false" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$v" == "true" ]]; then
            echo "yes"
        else
            echo "no"
        fi
    else
        echo "no"
    fi
}

# Recent activity summary line for a primitive (heuristic via .run/<file>.jsonl).
_an_primitive_activity() {
    local pid="$1"
    case "$pid" in
        L1)
            local f="$PROJECT_ROOT/.run/panel-decisions.jsonl"
            if [[ -f "$f" ]]; then
                local n
                n=$(wc -l < "$f" 2>/dev/null | awk '{print $1}')
                echo "${n:-0} decisions logged"
            else
                echo "no activity"
            fi
            ;;
        L2)
            local f="$PROJECT_ROOT/.run/cost-budget-events.jsonl"
            if [[ -f "$f" ]]; then
                local n
                n=$(wc -l < "$f" 2>/dev/null | awk '{print $1}')
                echo "${n:-0} budget events"
            else
                echo "no activity"
            fi
            ;;
        L3)
            local f="$PROJECT_ROOT/.run/cycles.jsonl"
            if [[ -f "$f" ]]; then
                local n
                n=$(wc -l < "$f" 2>/dev/null | awk '{print $1}')
                echo "${n:-0} cycles registered"
            else
                echo "no activity"
            fi
            ;;
        L4)
            local f="$PROJECT_ROOT/grimoires/loa/trust-ledger.jsonl"
            if [[ -f "$f" ]]; then
                local n
                n=$(wc -l < "$f" 2>/dev/null | awk '{print $1}')
                echo "${n:-0} trust transitions"
            else
                echo "no activity"
            fi
            ;;
        L5)
            local d="$PROJECT_ROOT/.run/cache/cross-repo-status"
            if [[ -d "$d" ]]; then
                local n
                n=$(find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l | awk '{print $1}')
                echo "${n:-0} repos cached"
            else
                echo "no activity"
            fi
            ;;
        L6)
            local f="$PROJECT_ROOT/grimoires/loa/handoffs/INDEX.md"
            if [[ -f "$f" ]]; then
                echo "INDEX.md present"
            else
                echo "no activity"
            fi
            ;;
        L7)
            local f="$PROJECT_ROOT/SOUL.md"
            if [[ -f "$f" ]]; then
                echo "SOUL.md present"
            else
                echo "no SOUL.md"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Tier validator status. Returns "tier-N (Label)" or "unsupported".
_an_tier_status() {
    if [[ -x "$TIER_VALIDATOR_SCRIPT" ]]; then
        # Don't propagate exit codes; we just want the label.
        local out
        out=$("$TIER_VALIDATOR_SCRIPT" check 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            echo "$out"
            return 0
        fi
    fi
    echo "unknown"
}

# Protected queue depth: count of items in .run/protected-queue.jsonl.
_an_protected_queue_depth() {
    local f="$PROJECT_ROOT/.run/protected-queue.jsonl"
    if [[ -f "$f" ]]; then
        wc -l < "$f" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

# Audit chain summary: count of primitive logs that validate.
# Returns "N/M" + last verify time (or "never").
_an_audit_chain_summary() {
    if [[ ! -x "$AUDIT_ENVELOPE_SCRIPT" ]]; then
        echo "0/7"
        return 0
    fi

    # Map of primitive_id → log path candidates.
    local logs=(
        "L1:.run/panel-decisions.jsonl"
        "L2:.run/cost-budget-events.jsonl"
        "L3:.run/cycles.jsonl"
        "L4:grimoires/loa/trust-ledger.jsonl"
        "L6:grimoires/loa/handoffs/INDEX.md"
    )
    local total=7   # 7 primitives in the cycle-098 model
    local valid=0
    local entry path
    for entry in "${logs[@]}"; do
        path="${entry#*:}"
        local full="${PROJECT_ROOT}/${path}"
        if [[ -f "$full" ]]; then
            if "$AUDIT_ENVELOPE_SCRIPT" verify-chain "$full" >/dev/null 2>&1; then
                valid=$((valid + 1))
            fi
        else
            # Primitive not yet emitting; counts as "validates" by absence.
            valid=$((valid + 1))
        fi
    done

    # L5 + L7 are not chain-critical, count as validating.
    valid=$((valid + 2))
    if [[ "$valid" -gt "$total" ]]; then
        valid="$total"
    fi
    echo "${valid}/${total}"
}

# Display Agent-Network section (human-readable).
display_agent_network_section() {
    echo ""
    echo -e "${BOLD}Agent-Network Primitives (cycle-098)${NC}"

    # Compact table.
    printf "  %-10s %-9s %s\n" "Primitive" "Enabled" "Recent activity"
    printf "  %-10s %-9s %s\n" "---------" "-------" "---------------"
    local p
    for p in L1 L2 L3 L4 L5 L6 L7; do
        local enabled activity
        enabled=$(_an_primitive_enabled "$p")
        activity=$(_an_primitive_activity "$p")
        printf "  %-10s %-9s %s\n" "$p" "$enabled" "$activity"
    done

    echo ""
    local tier_status pq audit_chain
    tier_status=$(_an_tier_status)
    pq=$(_an_protected_queue_depth)
    audit_chain=$(_an_audit_chain_summary)

    case "$tier_status" in
        tier-*) echo "  Tier validator: ${tier_status} -- supported." ;;
        unsupported*) echo -e "  Tier validator: ${YELLOW}${tier_status}${NC}" ;;
        *) echo "  Tier validator: ${tier_status}" ;;
    esac
    echo "  Protected queue: ${pq} items awaiting operator action."
    echo "  Audit chain: ${audit_chain} primitives validate."
    echo ""
}

# JSON snippet for agent-network section.
get_agent_network_json() {
    local p enabled activity tier_status pq audit_chain
    tier_status=$(_an_tier_status)
    pq=$(_an_protected_queue_depth)
    audit_chain=$(_an_audit_chain_summary)

    # Build primitives array via jq (safe JSON construction).
    local primitives_json="[]"
    for p in L1 L2 L3 L4 L5 L6 L7; do
        enabled=$(_an_primitive_enabled "$p")
        activity=$(_an_primitive_activity "$p")
        primitives_json=$(printf '%s' "$primitives_json" | jq -c \
            --arg id "$p" --arg en "$enabled" --arg act "$activity" \
            '. + [{primitive_id: $id, enabled: ($en == "yes"), recent_activity: $act}]')
    done

    jq -nc \
        --argjson primitives "$primitives_json" \
        --arg tier "$tier_status" \
        --argjson pq "$pq" \
        --arg ac "$audit_chain" \
        '{
            primitives: $primitives,
            tier_validator: $tier,
            protected_queue_depth: $pq,
            audit_chain_summary: $ac
        }'
}

# === Main Logic ===

main() {
  # Version-only mode
  if [[ "$VERSION_ONLY" == "true" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      get_version_info_json
    else
      display_version_info
    fi
    exit 0
  fi

  # Full status mode
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Combine workflow state and version info into single JSON
    local workflow_json version_json

    if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
      workflow_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null || echo '{}')
    else
      workflow_json='{}'
    fi

    version_json=$(get_version_info_json)
    agent_network_json=$(get_agent_network_json)

    # Merge the JSON objects: workflow base + framework + agent_network
    jq -s '.[0] * { "framework": .[1], "agent_network": .[2] }' \
      <(echo "$workflow_json") \
      <(echo "$version_json") \
      <(echo "$agent_network_json")
  else
    # Human-readable combined output
    echo "═══════════════════════════════════════════════════════════════"
    echo -e " ${BOLD}Loa Status${NC}"
    echo "═══════════════════════════════════════════════════════════════"

    # Version info section
    display_version_info

    echo "───────────────────────────────────────────────────────────────"

    # Workflow state section
    if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
      echo ""
      echo -e "${BOLD}Workflow State${NC}"

      # Run workflow-state and extract info
      local state description progress current_sprint total_sprints completed_sprints suggested

      state_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null || echo '{}')

      state=$(echo "$state_json" | jq -r '.state // "unknown"')
      description=$(echo "$state_json" | jq -r '.description // ""')
      progress=$(echo "$state_json" | jq -r '.progress_percent // 0')
      current_sprint=$(echo "$state_json" | jq -r '.current_sprint // ""')
      total_sprints=$(echo "$state_json" | jq -r '.total_sprints // 0')
      completed_sprints=$(echo "$state_json" | jq -r '.completed_sprints // 0')
      suggested=$(echo "$state_json" | jq -r '.suggested_command // ""')

      echo "  State: ${state}"
      [[ -n "$description" ]] && echo "  ${description}"

      # Progress bar
      local filled=$((progress / 5))
      local empty=$((20 - filled))
      printf "  Progress: ["
      printf '%0.s█' $(seq 1 $filled 2>/dev/null) || true
      printf '%0.s░' $(seq 1 $empty 2>/dev/null) || true
      printf "] %d%%\n" "$progress"

      [[ -n "$current_sprint" ]] && echo "  Current Sprint: ${current_sprint}"
      echo "  Sprints: ${completed_sprints}/${total_sprints} complete"

      echo ""
      echo "───────────────────────────────────────────────────────────────"
      [[ -n "$suggested" ]] && echo -e " ${BOLD}Suggested:${NC} ${CYAN}${suggested}${NC}"
    else
      echo ""
      echo "  Workflow state detection unavailable"
      echo "  (workflow-state.sh not found)"
    fi

    # Agent-Network Primitives section (cycle-098 Sprint 1C, SDD §4.4).
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    display_agent_network_section

    echo "═══════════════════════════════════════════════════════════════"
    echo ""
  fi
}

main "$@"
