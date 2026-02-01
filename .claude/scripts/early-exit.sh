#!/usr/bin/env bash
# Early Exit - Coordination protocol for parallel subagent early termination
# Part of the Loa framework's Recursive JIT Context System
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"
EARLY_EXIT_DIR="${EARLY_EXIT_DIR:-${SCRIPT_DIR}/../cache/early-exit}"

# Default configuration
DEFAULT_GRACE_PERIOD_SECONDS="5"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#######################################
# Print usage information
#######################################
usage() {
    cat << 'USAGE'
Usage: early-exit.sh <command> [options]

Early Exit - Coordination protocol for parallel subagent early termination

This script implements an atomic file-based protocol for coordinating
parallel subagents, allowing the first to find a solution to signal
others to stop work.

Commands:
  check <session_id>                 Check if early-exit signaled (exit 0 = no exit, 1 = signaled)
  signal <session_id>                Signal early-exit (atomic mkdir)
  cleanup <session_id>               Remove all session markers
  register <session_id> <agent_id>   Register subagent with session
  write-result <session_id> <agent_id> <result_file>  Write result for agent
  read-winner <session_id>           Read winning agent's result
  poll <session_id> [--timeout <ms>] Poll for winner with timeout

Options:
  --help, -h                         Show this help message
  --json                             Output as JSON

Configuration (.loa.config.yaml):
  recursive_jit:
    early_exit:
      enabled: true
      grace_period_seconds: 5

Protocol:
  1. Parent creates session: cleanup <session_id> (clean slate)
  2. Subagents register: register <session_id> <agent_id>
  3. Subagents periodically: check <session_id> (continue if exit=0)
  4. First success: signal <session_id> && write-result <session_id> <agent_id> <file>
  5. Parent: poll <session_id> --timeout 30000
  6. Parent: read-winner <session_id>
  7. Parent: cleanup <session_id>

Examples:
  # Check if should continue
  if early-exit.sh check my-session; then
    # Continue working
  else
    # Exit early - another agent won
    exit 0
  fi

  # Signal victory
  early-exit.sh signal my-session
  early-exit.sh write-result my-session agent-1 ./result.json

  # Poll with timeout
  early-exit.sh poll my-session --timeout 30000
USAGE
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}i${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}v${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1" >&2
}

print_error() {
    echo -e "${RED}x${NC} $1" >&2
}

#######################################
# Get configuration value
#######################################
get_config() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local exists
        exists=$(yq -r ".$key | type" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [[ "$exists" != "null" ]]; then
            local value
            value=$(yq -r ".$key" "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ "$value" != "null" ]]; then
                echo "$value"
                return 0
            fi
        fi
    fi

    echo "$default"
}

#######################################
# Check if early-exit is enabled
#######################################
is_early_exit_enabled() {
    local enabled
    enabled=$(get_config "recursive_jit.early_exit.enabled" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Get grace period in seconds
#######################################
get_grace_period() {
    get_config "recursive_jit.early_exit.grace_period_seconds" "$DEFAULT_GRACE_PERIOD_SECONDS"
}

#######################################
# Get session directory
#######################################
get_session_dir() {
    local session_id="$1"
    echo "${EARLY_EXIT_DIR}/${session_id}"
}

#######################################
# Initialize early-exit directory
#######################################
init_early_exit() {
    mkdir -p "$EARLY_EXIT_DIR"
}

#######################################
# CMD: Check if early-exit signaled
# Returns: 0 if no exit (continue working), 1 if signaled (stop)
#######################################
cmd_check() {
    local session_id="${1:-}"
    local json_output="false"

    if [[ -z "$session_id" ]]; then
        print_error "Required: session_id"
        return 2
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 2
                ;;
        esac
    done

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local winner_marker="${session_dir}/WINNER"

    if [[ -d "$winner_marker" ]]; then
        # Early exit signaled
        if [[ "$json_output" == "true" ]]; then
            local winner_agent=""
            if [[ -f "${session_dir}/winner_agent" ]]; then
                winner_agent=$(cat "${session_dir}/winner_agent")
            fi
            jq -n --arg session "$session_id" --arg winner "$winner_agent" \
                '{"signaled": true, "session_id": $session, "winner_agent": $winner}'
        fi
        return 1  # Signaled - stop working
    else
        # No exit signal
        if [[ "$json_output" == "true" ]]; then
            jq -n --arg session "$session_id" \
                '{"signaled": false, "session_id": $session}'
        fi
        return 0  # Continue working
    fi
}

#######################################
# CMD: Signal early-exit (atomic)
#######################################
cmd_signal() {
    local session_id="${1:-}"
    local agent_id="${2:-unknown}"

    if [[ -z "$session_id" ]]; then
        print_error "Required: session_id"
        return 1
    fi

    init_early_exit

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    mkdir -p "$session_dir"

    local winner_marker="${session_dir}/WINNER"

    # Atomic mkdir - only one agent can succeed
    if mkdir "$winner_marker" 2>/dev/null; then
        # We won - record our agent ID
        echo "$agent_id" > "${session_dir}/winner_agent"
        echo "$(date +%s)" > "${session_dir}/signal_time"
        print_success "Early-exit signaled by $agent_id"
        return 0
    else
        # Someone else already signaled
        local winner=""
        if [[ -f "${session_dir}/winner_agent" ]]; then
            winner=$(cat "${session_dir}/winner_agent")
        fi
        print_warning "Early-exit already signaled by $winner"
        return 1
    fi
}

#######################################
# CMD: Cleanup session markers
#######################################
cmd_cleanup() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        print_error "Required: session_id"
        return 1
    fi

    local session_dir
    session_dir=$(get_session_dir "$session_id")

    if [[ -d "$session_dir" ]]; then
        rm -rf "$session_dir"
        print_success "Cleaned up session: $session_id"
    else
        print_info "Session not found (already clean): $session_id"
    fi
}

#######################################
# CMD: Register subagent
#######################################
cmd_register() {
    local session_id="${1:-}"
    local agent_id="${2:-}"

    if [[ -z "$session_id" ]] || [[ -z "$agent_id" ]]; then
        print_error "Required: session_id agent_id"
        return 1
    fi

    init_early_exit

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    mkdir -p "${session_dir}/agents"

    # Register agent with timestamp
    echo "$(date +%s)" > "${session_dir}/agents/${agent_id}"

    print_success "Registered agent: $agent_id in session: $session_id"
}

#######################################
# CMD: Write result for agent
#######################################
cmd_write_result() {
    local session_id="${1:-}"
    local agent_id="${2:-}"
    local result_file="${3:-}"

    if [[ -z "$session_id" ]] || [[ -z "$agent_id" ]]; then
        print_error "Required: session_id agent_id [result_file]"
        return 1
    fi

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    mkdir -p "${session_dir}/results"

    local output_file="${session_dir}/results/${agent_id}.json"

    if [[ -n "$result_file" ]] && [[ -f "$result_file" ]]; then
        cp "$result_file" "$output_file"
    else
        # Read from stdin
        cat > "$output_file"
    fi

    print_success "Result written for agent: $agent_id"
}

#######################################
# CMD: Read winner result
#######################################
cmd_read_winner() {
    local session_id="${1:-}"
    local json_output="false"

    if [[ -z "$session_id" ]]; then
        print_error "Required: session_id"
        return 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local session_dir
    session_dir=$(get_session_dir "$session_id")

    # Check for winner
    if [[ ! -d "${session_dir}/WINNER" ]]; then
        print_error "No winner in session: $session_id"
        return 1
    fi

    local winner_agent=""
    if [[ -f "${session_dir}/winner_agent" ]]; then
        winner_agent=$(cat "${session_dir}/winner_agent")
    fi

    local result_file="${session_dir}/results/${winner_agent}.json"

    if [[ -f "$result_file" ]]; then
        if [[ "$json_output" == "true" ]]; then
            local result_content
            result_content=$(cat "$result_file")
            jq -n \
                --arg session "$session_id" \
                --arg winner "$winner_agent" \
                --argjson result "$result_content" \
                '{"session_id": $session, "winner_agent": $winner, "result": $result}'
        else
            cat "$result_file"
        fi
    else
        if [[ "$json_output" == "true" ]]; then
            jq -n \
                --arg session "$session_id" \
                --arg winner "$winner_agent" \
                '{"session_id": $session, "winner_agent": $winner, "result": null}'
        else
            print_warning "Winner ($winner_agent) has no result file"
        fi
    fi
}

#######################################
# CMD: Poll for winner
#######################################
cmd_poll() {
    local session_id="${1:-}"
    local timeout_ms="30000"
    local json_output="false"

    if [[ -z "$session_id" ]]; then
        print_error "Required: session_id"
        return 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout_ms="$2"; shift 2 ;;
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local winner_marker="${session_dir}/WINNER"

    local timeout_s=$((timeout_ms / 1000))
    local start_time
    start_time=$(date +%s)
    local elapsed=0

    print_info "Polling for winner (timeout: ${timeout_s}s)..."

    while [[ "$elapsed" -lt "$timeout_s" ]]; do
        if [[ -d "$winner_marker" ]]; then
            local winner_agent=""
            if [[ -f "${session_dir}/winner_agent" ]]; then
                winner_agent=$(cat "${session_dir}/winner_agent")
            fi

            # Wait grace period for result to be written
            local grace_period
            grace_period=$(get_grace_period)
            sleep "$grace_period"

            if [[ "$json_output" == "true" ]]; then
                cmd_read_winner "$session_id" --json
            else
                print_success "Winner found: $winner_agent"
                cmd_read_winner "$session_id"
            fi
            return 0
        fi

        sleep 0.5
        elapsed=$(($(date +%s) - start_time))
    done

    print_error "Timeout waiting for winner"
    if [[ "$json_output" == "true" ]]; then
        jq -n \
            --arg session "$session_id" \
            --argjson timeout "$timeout_ms" \
            '{"error": "timeout", "session_id": $session, "timeout_ms": $timeout}'
    fi
    return 1
}

#######################################
# CMD: Status - show session state
#######################################
cmd_status() {
    local session_id="${1:-}"
    local json_output="false"

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    init_early_exit

    if [[ -n "$session_id" ]]; then
        # Status for specific session
        local session_dir
        session_dir=$(get_session_dir "$session_id")

        if [[ ! -d "$session_dir" ]]; then
            if [[ "$json_output" == "true" ]]; then
                jq -n --arg session "$session_id" '{"session_id": $session, "exists": false}'
            else
                print_info "Session not found: $session_id"
            fi
            return 0
        fi

        local signaled="false"
        local winner_agent=""
        local agents=()
        local results=()

        if [[ -d "${session_dir}/WINNER" ]]; then
            signaled="true"
            if [[ -f "${session_dir}/winner_agent" ]]; then
                winner_agent=$(cat "${session_dir}/winner_agent")
            fi
        fi

        if [[ -d "${session_dir}/agents" ]]; then
            while IFS= read -r agent_file; do
                agents+=("$(basename "$agent_file")")
            done < <(find "${session_dir}/agents" -type f 2>/dev/null)
        fi

        if [[ -d "${session_dir}/results" ]]; then
            while IFS= read -r result_file; do
                results+=("$(basename "$result_file" .json)")
            done < <(find "${session_dir}/results" -name "*.json" -type f 2>/dev/null)
        fi

        if [[ "$json_output" == "true" ]]; then
            local agents_json results_json
            agents_json=$(printf '%s\n' "${agents[@]}" 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")
            results_json=$(printf '%s\n' "${results[@]}" 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")

            jq -n \
                --arg session "$session_id" \
                --argjson signaled "$signaled" \
                --arg winner "$winner_agent" \
                --argjson agents "$agents_json" \
                --argjson results "$results_json" \
                '{session_id: $session, signaled: $signaled, winner_agent: $winner, registered_agents: $agents, results: $results}'
        else
            echo ""
            echo -e "${CYAN}Session Status: $session_id${NC}"
            echo "======================="
            echo ""
            if [[ "$signaled" == "true" ]]; then
                echo -e "  Status:  ${GREEN}SIGNALED${NC}"
                echo "  Winner:  $winner_agent"
            else
                echo -e "  Status:  ${YELLOW}ACTIVE${NC}"
            fi
            echo "  Agents:  ${agents[*]:-none}"
            echo "  Results: ${results[*]:-none}"
            echo ""
        fi
    else
        # List all sessions
        local sessions=()
        while IFS= read -r session_dir; do
            sessions+=("$(basename "$session_dir")")
        done < <(find "$EARLY_EXIT_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

        if [[ "$json_output" == "true" ]]; then
            local sessions_json
            sessions_json=$(printf '%s\n' "${sessions[@]}" 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")
            jq -n --argjson sessions "$sessions_json" '{sessions: $sessions}'
        else
            echo ""
            echo -e "${CYAN}Active Sessions${NC}"
            echo "================"
            echo ""
            if [[ ${#sessions[@]} -eq 0 ]]; then
                echo "  (none)"
            else
                for s in "${sessions[@]}"; do
                    echo "  - $s"
                done
            fi
            echo ""
        fi
    fi
}

#######################################
# Main entry point
#######################################
main() {
    local command=""

    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        check)
            cmd_check "$@"
            ;;
        signal)
            cmd_signal "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        register)
            cmd_register "$@"
            ;;
        write-result)
            cmd_write_result "$@"
            ;;
        read-winner)
            cmd_read_winner "$@"
            ;;
        poll)
            cmd_poll "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
