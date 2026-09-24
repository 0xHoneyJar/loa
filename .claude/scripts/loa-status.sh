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
#   2 - Usage error (unknown option outside --economy forwarding)

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

# Colors — respect NO_COLOR (https://no-color.org/) and non-TTY stdout, same
# guard shape as lib/dx-utils.sh (R-001, bd-m1o6: piped output previously
# carried raw ANSI escapes into agent pipelines).
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  NC=''
fi

# Arguments
JSON_OUTPUT=false
VERSION_ONLY=false
TRIAGE_MODE=false
STALE_CHECK=true
ECONOMY_MODE=false
ECONOMY_ARGS=()
UNKNOWN_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --economy) ECONOMY_MODE=true ;;
    --json) JSON_OUTPUT=true; ECONOMY_ARGS+=("--json") ;;
    --version) VERSION_ONLY=true ;;
    --triage) TRIAGE_MODE=true ;;
    --no-stale-check) STALE_CHECK=false ;;
    --help|-h)
      echo "Usage: loa-status.sh [--json] [--triage] [--version] [--no-stale-check] [--economy [...]] [--help]"
      echo ""
      echo "Options:"
      echo "  --json                Output JSON format"
      echo "  --triage              One-call triage: workflow state + health (loa-doctor"
      echo "                          --quick) + suggested next command. Combine with"
      echo "                          --json for a machine-readable envelope."
      echo "  --version             Only show version info"
      echo "  --no-stale-check      Skip the local cached-upstream worktree check"
      echo "  --economy             Show model-economy roll-up (cycle-112 FR-2)"
      echo "                          Accepts: --window <h|d|m>, --skill <substr>,"
      echo "                          --model <substr>, --cost-snapshot <git-ref>,"
      echo "                          --log-path <path>, --json"
      echo "                        See: grimoires/loa/runbooks/model-economy.md"
      echo "  --help                Show this help"
      exit 0
      ;;
    *)
      # In --economy mode, forward unknown args to the roll-up tool.
      # Outside economy mode they are usage errors (R-001, bd-m1o6: a typo'd
      # '--jsno' previously fell through silently and produced full human
      # output with exit 0 — the worst possible outcome for a JSON consumer).
      ECONOMY_ARGS+=("$arg")
      UNKNOWN_ARGS+=("$arg")
      ;;
  esac
done

USAGE_LINE="Usage: loa-status.sh [--json] [--triage] [--version] [--no-stale-check] [--economy [...]] [--help]"
if [[ "$ECONOMY_MODE" != "true" ]] && [[ ${#UNKNOWN_ARGS[@]} -gt 0 ]]; then
  # shellcheck source=lib/dx-utils.sh
  source "${SCRIPT_DIR}/lib/dx-utils.sh" 2>/dev/null || true
  if declare -F dx_unknown_flag >/dev/null 2>&1; then
    dx_unknown_flag "${UNKNOWN_ARGS[0]}" "$USAGE_LINE" --json --triage --version --no-stale-check --economy --help
  else
    echo "Unknown option: ${UNKNOWN_ARGS[0]}" >&2
    echo "$USAGE_LINE" >&2
  fi
  exit 2
fi

# Economy mode: short-circuit to the model-economy roll-up tool.
# Single source of truth — loa-status.sh never reimplements aggregation.
if [[ "$ECONOMY_MODE" == "true" ]]; then
  ECONOMY_TOOL="${PROJECT_ROOT}/tools/model-economy-roll-up.sh"
  if [[ ! -x "$ECONOMY_TOOL" ]]; then
    echo "[loa-status] error: model-economy roll-up tool not found at $ECONOMY_TOOL" >&2
    exit 1
  fi
  exec "$ECONOMY_TOOL" ${ECONOMY_ARGS[@]+"${ECONOMY_ARGS[@]}"}
fi

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

# A linked worktree can retain an active cycle after a squash merge/archive.
# Compare exact cycle IDs against local remote-tracking refs; never fetch or
# infer shipment merely because the upstream active_cycle is null/different.
get_stale_worktree_json() {
  [[ "$STALE_CHECK" == "true" ]] || return 0
  local git_dir common_dir cycle upstream ledger record
  git_dir=$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  common_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null) || return 0
  [[ "$common_dir" == /* ]] || common_dir="$PROJECT_ROOT/$common_dir"
  [[ "$git_dir" != "$common_dir" ]] || return 0

  cycle=$(jq -er '.active_cycle | select(type == "string" and length > 0)' \
    "$PROJECT_ROOT/grimoires/loa/ledger.json" 2>/dev/null) || return 0
  upstream=$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    || upstream="origin/main"
  ledger=$(git -C "$PROJECT_ROOT" show "${upstream}:grimoires/loa/ledger.json" 2>/dev/null) || return 0
  record=$(jq -ce --arg cycle "$cycle" \
    '[.cycles[] | select(.id == $cycle and (.status == "archived" or .status == "closed"))] |
     if length == 1 then .[0] else empty end' <<< "$ledger" 2>/dev/null) || return 0
  jq -nc --arg cycle "$cycle" --arg upstream "$upstream" --argjson record "$record" \
    '{cycle_id: $cycle, upstream_ref: $upstream, upstream_status: $record.status,
      archive_path: ($record.archive_path // null),
      warning: ("This worktree is a stale snapshot: cycle " + $cycle + " is " +
        $record.status + " in cached " + $upstream +
        ". Inspect the worktree before retiring it; the local workflow state is historical.")}'
}

annotate_workflow_status() {
  local workflow_json="$1" stale_json
  stale_json=$(get_stale_worktree_json)
  if [[ -n "$stale_json" ]]; then
    jq --argjson stale "$stale_json" \
      '. + {stale_worktree: $stale, suggested_command: "git worktree list"}' <<< "$workflow_json"
  else
    printf '%s\n' "$workflow_json"
  fi
}

display_stale_warning() {
  local warning
  warning=$(jq -r '.stale_worktree.warning // empty' <<< "$1")
  [[ -z "$warning" ]] || printf '  Warning: %s\n' "$warning"
}

# === Main Logic ===

main() {
  # Triage mode (R-007, bd-m1o6): one call answering "where am I, is the
  # system healthy, what next" — composes existing surfaces (workflow-state
  # --json + loa-doctor --quick --json + suggested_command), no new logic.
  if [[ "$TRIAGE_MODE" == "true" ]]; then
    local workflow_json doctor_json
    # Capture-then-validate: loa-doctor exits nonzero on DEGRADED *by design*
    # (it doubles as a health gate), so 'cmd || echo fallback' would append a
    # second JSON doc to perfectly valid output. Trust content, not exit code.
    if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
      workflow_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null) || true
    else
      workflow_json=''
    fi
    echo "$workflow_json" | jq -e 'type == "object"' >/dev/null 2>&1 || workflow_json='{}'
    workflow_json=$(annotate_workflow_status "$workflow_json")
    doctor_json=$(timeout 45 bash "${SCRIPT_DIR}/loa-doctor.sh" --quick --json 2>/dev/null) || true
    echo "$doctor_json" | jq -e 'type == "object"' >/dev/null 2>&1 || doctor_json='{"status":"unavailable"}'
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      jq -n --argjson s "$workflow_json" --argjson h "$doctor_json" \
        '{schema_version: "1",
          status: $s,
          health: {status: ($h.status // "unavailable"),
                   issues: ($h.issues // []),
                   warnings: ($h.warnings // []),
                   recommendations: ($h.recommendations // [])},
          next: {suggested_command: ($s.suggested_command // "")}}'
    else
      local t_state t_suggested t_health
      t_state=$(echo "$workflow_json" | jq -r '.state // "unknown"')
      t_suggested=$(echo "$workflow_json" | jq -r '.suggested_command // ""')
      t_health=$(echo "$doctor_json" | jq -r '.status // "unavailable"')
      echo "Loa triage"
      display_stale_warning "$workflow_json"
      echo "  state:  ${t_state}"
      echo "  health: ${t_health}"
      [[ -n "$t_suggested" ]] && echo "  next:   ${t_suggested}"
      echo "  detail: loa-status.sh --triage --json | loa-doctor.sh --json"
    fi
    exit 0
  fi

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
    workflow_json=$(annotate_workflow_status "$workflow_json")

    version_json=$(get_version_info_json)
    agent_network_json=$(get_agent_network_json)
    providers_json=$(get_providers_json)

    # Merge the JSON objects: workflow base + framework + agent_network + providers
    jq -s '.[0] * { "framework": .[1], "agent_network": .[2], "providers": .[3] }' \
      <(echo "$workflow_json") \
      <(echo "$version_json") \
      <(echo "$agent_network_json") \
      <(echo "$providers_json")
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
      state_json=$(annotate_workflow_status "$state_json")
      display_stale_warning "$state_json"

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
      display_artefacts_line
      display_run_line

      echo ""
      echo "───────────────────────────────────────────────────────────────"
      [[ -n "$suggested" ]] && echo -e " ${BOLD}Suggested:${NC} ${CYAN}${suggested}${NC}"
    else
      echo ""
      echo "  Workflow state detection unavailable"
      echo "  (workflow-state.sh not found)"
    fi

    # Providers section (cycle-125 FR-4, SDD §1.5): breakers, credential presence, CLI hops.
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    display_providers_section

    # Agent-Network Primitives section (cycle-098 Sprint 1C, SDD §4.4).
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    display_agent_network_section

    echo "═══════════════════════════════════════════════════════════════"
    echo ""
  fi
}

# cycle-125 FR-2: planning-artefact sizes with the 100 KiB warn line, so an
# agent learns to read by section BEFORE a blind Read is rejected. Uses the
# same `notes-guard.sh check` verdict as the NOTES fences (warn ≥ 100 KiB).
display_artefacts_line() {
  local g="${LOA_GRIMOIRE_DIR:-$PROJECT_ROOT/grimoires/loa}" guard="${SCRIPT_DIR}/notes-guard.sh"
  local f b line="" warn=""
  for f in prd.md sdd.md sprint.md NOTES.md; do
    [[ -f "$g/$f" ]] || continue
    b=$(stat -c%s "$g/$f" 2>/dev/null || echo 0)
    line+=" ${f%.md} $(( (b + 1023) / 1024 ))K"
    if [[ -f "$guard" ]] && bash "$guard" check --file "$g/$f" 2>&1 >/dev/null | grep -q 'NOTES-WARN\|NOTES-BLOCK'; then
      warn+=" $f"
    fi
  done
  [[ -n "$line" ]] || return 0
  echo "  Artefacts:${line}"
  if [[ -n "$warn" ]]; then
    echo "  ⚠ ≥ 100 KiB:${warn} — read by section: notes-guard.sh read --file <F> --section <H> (or --index)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Providers (cycle-125 FR-4, SDD §1.5): one glance at provider health.
# Per provider: credential PRESENT/absent (env only — the value is never read
# into a variable here), CLI hop on PATH, and every breaker bucket with its
# state, age and probe timing from `breaker_cli --list --json` (jq fallback
# over the state files when the Python substrate is unavailable).
# Test seam (bats-gated): LOA_STATUS_RUN_DIR points at a fixture .run/.
# ---------------------------------------------------------------------------
_providers_run_dir() {
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_STATUS_RUN_DIR:-}" ]]; then
    echo "$LOA_STATUS_RUN_DIR"
  else
    echo "$PROJECT_ROOT/.run"
  fi
}
_providers_reset_timeout() {
  local rt=""
  if command -v yq >/dev/null 2>&1 && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
    rt=$(yq eval '.routing.circuit_breaker.reset_timeout_seconds // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null)
  fi
  [[ "$rt" =~ ^[0-9]+$ ]] && echo "$rt" || echo 60
}
# Snapshot JSON: {"reset_timeout_seconds":N,"buckets":{prov:{auth:{state,failure_count,opened_at,age_s,probe_due_in_s}}}}
_providers_snapshot() {
  local run_dir rt py out
  run_dir=$(_providers_run_dir); rt=$(_providers_reset_timeout)
  if [[ -x "${PROJECT_ROOT}/.venv/bin/python" ]]; then py="${PROJECT_ROOT}/.venv/bin/python"; else py="$(command -v python3 || true)"; fi
  if [[ -n "$py" ]]; then
    out=$(cd "$PROJECT_ROOT/.claude/adapters" 2>/dev/null && PYTHONPATH="$PROJECT_ROOT/.claude/adapters" "$py" -m loa_cheval.routing.breaker_cli --list --json --run-dir "$run_dir" --reset-timeout "$rt" 2>/dev/null) || out=""
    if printf '%s' "$out" | jq -e '.buckets | type == "object"' >/dev/null 2>&1; then printf '%s\n' "$out"; return 0; fi
  fi
  # jq fallback: same shape from the files (symlinks and the lock skipped)
  local now f b prov auth st fc opened json='{}'
  now=$(date +%s)
  for f in "$run_dir"/circuit-breaker-*.json; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    b=$(basename "$f" .json); b="${b#circuit-breaker-}"; prov="${b%%-*}"; auth="${b#*-}"; [[ "$auth" == "$b" ]] && continue
    st=$(jq -r '.state // "CLOSED"' "$f" 2>/dev/null || echo CLOSED); fc=$(jq -r '.failure_count // 0' "$f" 2>/dev/null || echo 0)
    opened=$(jq -r '.opened_at // empty' "$f" 2>/dev/null); opened="${opened%.*}"
    json=$(printf '%s' "$json" | jq -c --arg p "$prov" --arg a "$auth" --arg s "$st" --argjson fc "${fc:-0}" \
      --argjson age "$( if [[ "$st" == OPEN && "$opened" =~ ^[0-9]+$ ]]; then echo $(( now - opened )); else echo null; fi )" --argjson rt "$rt" \
      '.[$p][$a] = {state:$s, failure_count:$fc, age_s:$age, probe_due_in_s:(if $age == null then null else ([$rt - $age, 0] | max) end)}')
  done
  jq -cn --argjson b "$json" --argjson rt "$rt" '{reset_timeout_seconds:$rt, buckets:$b}'
}
_provider_key_present() {  # $1 provider → "present (env)" | "present (.env.local)" | "present (.env)" | absent
  # Same rule as run-preflight.sh P3 so the two surfaces agree: the process
  # environment first, then a non-empty KEY= line in .env.local / .env
  # (cheval's DotenvProvider). Presence only — the value is never read into
  # a variable here (grep -q with a quote-aware pattern).
  local -a vars; local v f envdir
  case "$1" in
    anthropic) vars=(ANTHROPIC_API_KEY) ;;
    openai)    vars=(OPENAI_API_KEY) ;;
    google)    vars=(GOOGLE_API_KEY GEMINI_API_KEY) ;;
    *) echo "n/a"; return 0 ;;
  esac
  for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && { echo "present (env)"; return 0; }; done
  envdir="$PROJECT_ROOT"
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_STATUS_ENV_DIR:-}" ]]; then envdir="$LOA_STATUS_ENV_DIR"; fi
  for f in .env.local .env; do
    [[ -f "$envdir/$f" ]] || continue
    for v in "${vars[@]}"; do
      if grep -qE "^[[:space:]]*(export[[:space:]]+)?${v}=[\"']?[^\"'[:space:]#]" "$envdir/$f" 2>/dev/null; then echo "present ($f)"; return 0; fi
    done
  done
  echo absent
}
_provider_hop() {  # $1 provider → hop binary name or ""
  local bin=""
  case "$1" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; esac
  [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && echo "$bin" || echo ""
}
_fmt_age_s() { local s="$1"; if [[ ! "$s" =~ ^[0-9]+$ ]]; then echo "-"; elif (( s >= 86400 )); then echo "$(( s / 86400 ))d"; elif (( s >= 3600 )); then echo "$(( s / 3600 ))h"; else echo "$(( s / 60 ))m"; fi; }
get_providers_json() {
  local snap provs p
  snap=$(_providers_snapshot)
  provs=$(printf '%s' "$snap" | jq -r '.buckets | keys[]' 2>/dev/null; printf 'anthropic\nopenai\ngoogle\n')
  local out='{}'
  for p in $(printf '%s\n' $provs | sort -u); do
    out=$(printf '%s' "$out" | jq -c --arg p "$p" --arg key "$(_provider_key_present "$p")" --arg hop "$(_provider_hop "$p")" \
      --argjson buckets "$(printf '%s' "$snap" | jq -c --arg p "$p" '.buckets[$p] // {}')" \
      '.[$p] = {credential:$key, cli_hop:(if $hop == "" then null else $hop end), breakers:$buckets}')
  done
  printf '%s' "$out" | jq -c --argjson rt "$(printf '%s' "$snap" | jq '.reset_timeout_seconds // 60')" '{reset_timeout_seconds:$rt, providers:.}'
}
display_providers_section() {
  local pj p key hop line auth st age due
  pj=$(get_providers_json)
  echo -e "${BOLD}Providers${NC}"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    key=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].credential'); hop=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].cli_hop // "-"')
    line=$(printf '  %-10s key %-20s hop %-7s' "$p" "$key" "$hop")
    local buckets; buckets=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].breakers | to_entries[] | "\(.key) \(.value.state) \(.value.age_s // "-") \(.value.probe_due_in_s // "-")"')
    if [[ -z "$buckets" ]]; then line+=" no breaker state"; else
      while read -r auth st age due; do
        [[ -n "$auth" ]] || continue
        if [[ "$st" == "OPEN" ]]; then
          if [[ "$due" == "0" ]]; then line+=" · $auth OPEN $(_fmt_age_s "$age") (probe overdue → HALF_OPEN on next call)"; else line+=" · $auth OPEN $(_fmt_age_s "$age") (probe due in ${due}s)"; fi
        else line+=" · $auth $st"; fi
      done <<<"$buckets"
    fi
    echo "$line"
  done < <(printf '%s' "$pj" | jq -r '.providers | keys[]')
  echo "  reset: cheval --reset-breaker <provider>[:<auth_type>] · list: python3 -m loa_cheval.routing.breaker_cli --list"
  return 0
}

# cycle-125 FR-3: the resume line for a stale or halted run (and a passed
# session-limit reset), from the same script the SessionStart hook runs.
# Nothing is printed for a clean tree or a live run.
display_run_line() {
  local surface="${SCRIPT_DIR}/../hooks/session-start/loa-run-state-surface.sh" line
  [[ -f "$surface" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "  $line"
  done < <(bash "$surface" --line 2>/dev/null)
  return 0
}

main "$@"
