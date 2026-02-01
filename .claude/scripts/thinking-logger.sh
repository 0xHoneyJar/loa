#!/usr/bin/env bash
# Thinking Logger - Log agent reasoning with extended thinking support
# Part of the Loa framework's trajectory evaluation system
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="$(dirname "$SCRIPT_DIR")/schemas/trajectory-entry.schema.json"
DEFAULT_TRAJECTORY_DIR="grimoires/loa/a2a/trajectory"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  log                 Log a trajectory entry
  read <file>         Read and display trajectory entries
  validate <file>     Validate trajectory file against schema
  init                Initialize trajectory directory for today

Options for 'log':
  --agent <name>      Agent name (required)
  --action <text>     Action description (required)
  --phase <phase>     Execution phase (init, discovery, design, planning, etc.)
  --reasoning <text>  Reasoning explanation
  --thinking          Enable extended thinking capture
  --think-step <s>    Add thinking step (can repeat)
  --grounding <type>  Grounding type (citation, code_reference, assumption, user_input, inference)
  --ref <file:lines>  Add reference citation
  --confidence <0-1>  Confidence level
  --sprint <id>       Sprint identifier
  --task <id>         Task identifier
  --status <status>   Outcome status (success, partial, failed, blocked, pending)
  --result <text>     Outcome result description
  --output <file>     Output file (default: auto-generated based on agent and date)

Options for 'read':
  --agent <name>      Filter by agent
  --last <n>          Show last N entries
  --json              Output as JSON array

Examples:
  # Log a simple entry
  $(basename "$0") log --agent implementing-tasks --action "Created user model" --phase implementation

  # Log with extended thinking
  $(basename "$0") log --agent designing-architecture --action "Evaluated patterns" \\
    --thinking \\
    --think-step "1:analysis:Consider microservices vs monolith" \\
    --think-step "2:evaluation:Microservices adds complexity for small team" \\
    --think-step "3:decision:Chose modular monolith"

  # Log with grounding
  $(basename "$0") log --agent reviewing-code --action "Found SQL injection" \\
    --grounding code_reference --ref "src/db.ts:45-50" --confidence 0.95

  # Read trajectory
  $(basename "$0") read grimoires/loa/a2a/trajectory/implementing-tasks-2025-01-11.jsonl --last 5
EOF
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

#######################################
# Get current ISO 8601 timestamp
#######################################
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#######################################
# Get today's date for file naming
#######################################
get_date() {
    date +"%Y-%m-%d"
}

#######################################
# Initialize trajectory directory
#######################################
init_trajectory() {
    local dir="${1:-$DEFAULT_TRAJECTORY_DIR}"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_success "Created trajectory directory: $dir"
    else
        print_info "Trajectory directory exists: $dir"
    fi

    # Create .gitkeep if directory is empty
    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        touch "$dir/.gitkeep"
    fi
}

#######################################
# Get default output file path
#######################################
get_output_path() {
    local agent="$1"
    local dir="${2:-$DEFAULT_TRAJECTORY_DIR}"
    local date
    date=$(get_date)

    echo "$dir/${agent}-${date}.jsonl"
}

#######################################
# Parse thinking step format: "step:type:thought"
#######################################
parse_think_step() {
    local input="$1"
    local step_num type thought

    # Extract components
    step_num=$(echo "$input" | cut -d: -f1)
    type=$(echo "$input" | cut -d: -f2)
    thought=$(echo "$input" | cut -d: -f3-)

    # Validate step number
    if ! [[ "$step_num" =~ ^[0-9]+$ ]]; then
        print_error "Invalid step number: $step_num"
        return 1
    fi

    # Validate type if provided
    case "$type" in
        analysis|hypothesis|evaluation|decision|reflection|"")
            ;;
        *)
            print_warning "Unknown thinking type: $type (using as-is)"
            ;;
    esac

    # Output JSON object
    if [[ -n "$type" ]]; then
        printf '{"step": %d, "type": "%s", "thought": %s}' "$step_num" "$type" "$(echo "$thought" | jq -Rs '.')"
    else
        printf '{"step": %d, "thought": %s}' "$step_num" "$(echo "$thought" | jq -Rs '.')"
    fi
}

#######################################
# Parse reference format: "file:lines" or just "file"
#######################################
parse_ref() {
    local input="$1"
    local file lines

    if [[ "$input" == *":"* ]]; then
        file=$(echo "$input" | cut -d: -f1)
        lines=$(echo "$input" | cut -d: -f2)
        printf '{"file": "%s", "lines": "%s"}' "$file" "$lines"
    else
        printf '{"file": "%s"}' "$input"
    fi
}

#######################################
# Log a trajectory entry
#######################################
log_entry() {
    local agent=""
    local action=""
    local phase=""
    local reasoning=""
    local thinking_enabled="false"
    local thinking_steps=()
    local grounding_type=""
    local grounding_refs=()
    local confidence=""
    local sprint_id=""
    local task_id=""
    local status=""
    local result=""
    local output_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)
                agent="$2"
                shift 2
                ;;
            --action)
                action="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --reasoning)
                reasoning="$2"
                shift 2
                ;;
            --thinking)
                thinking_enabled="true"
                shift
                ;;
            --think-step)
                thinking_steps+=("$2")
                shift 2
                ;;
            --grounding)
                grounding_type="$2"
                shift 2
                ;;
            --ref)
                grounding_refs+=("$2")
                shift 2
                ;;
            --confidence)
                confidence="$2"
                shift 2
                ;;
            --sprint)
                sprint_id="$2"
                shift 2
                ;;
            --task)
                task_id="$2"
                shift 2
                ;;
            --status)
                status="$2"
                shift 2
                ;;
            --result)
                result="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate required fields
    if [[ -z "$agent" ]]; then
        print_error "Agent name is required (--agent)"
        return 1
    fi

    if [[ -z "$action" ]]; then
        print_error "Action is required (--action)"
        return 1
    fi

    # Get session ID from environment (available in Claude Code 2.1.9+)
    local session_id="${CLAUDE_SESSION_ID:-unknown}"

    # Build JSON entry
    local entry
    entry=$(jq -n \
        --arg ts "$(get_timestamp)" \
        --arg session_id "$session_id" \
        --arg agent "$agent" \
        --arg action "$action" \
        '{ts: $ts, session_id: $session_id, agent: $agent, action: $action}'
    )

    # Add optional fields
    if [[ -n "$phase" ]]; then
        entry=$(echo "$entry" | jq --arg phase "$phase" '. + {phase: $phase}')
    fi

    if [[ -n "$reasoning" ]]; then
        entry=$(echo "$entry" | jq --arg reasoning "$reasoning" '. + {reasoning: $reasoning}')
    fi

    # Add thinking trace if enabled
    if [[ "$thinking_enabled" == "true" ]] || [[ ${#thinking_steps[@]} -gt 0 ]]; then
        local thinking_json='{"enabled": true}'

        if [[ ${#thinking_steps[@]} -gt 0 ]]; then
            local steps_json="["
            local first=true
            for step in "${thinking_steps[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    steps_json+=","
                fi
                steps_json+=$(parse_think_step "$step")
            done
            steps_json+="]"

            thinking_json=$(echo "$thinking_json" | jq --argjson steps "$steps_json" '. + {steps: $steps}')
        fi

        entry=$(echo "$entry" | jq --argjson thinking "$thinking_json" '. + {thinking_trace: $thinking}')
    fi

    # Add grounding if specified
    if [[ -n "$grounding_type" ]] || [[ ${#grounding_refs[@]} -gt 0 ]]; then
        local grounding_json='{}'

        if [[ -n "$grounding_type" ]]; then
            grounding_json=$(echo "$grounding_json" | jq --arg type "$grounding_type" '. + {type: $type}')
        fi

        if [[ ${#grounding_refs[@]} -gt 0 ]]; then
            local refs_json="["
            local first=true
            for ref in "${grounding_refs[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    refs_json+=","
                fi
                refs_json+=$(parse_ref "$ref")
            done
            refs_json+="]"

            grounding_json=$(echo "$grounding_json" | jq --argjson refs "$refs_json" '. + {refs: $refs}')
        fi

        if [[ -n "$confidence" ]]; then
            grounding_json=$(echo "$grounding_json" | jq --argjson conf "$confidence" '. + {confidence: $conf}')
        fi

        entry=$(echo "$entry" | jq --argjson grounding "$grounding_json" '. + {grounding: $grounding}')
    fi

    # Add context if specified
    if [[ -n "$sprint_id" ]] || [[ -n "$task_id" ]]; then
        local context_json='{}'

        if [[ -n "$sprint_id" ]]; then
            context_json=$(echo "$context_json" | jq --arg sprint "$sprint_id" '. + {sprint_id: $sprint}')
        fi

        if [[ -n "$task_id" ]]; then
            context_json=$(echo "$context_json" | jq --arg task "$task_id" '. + {task_id: $task}')
        fi

        entry=$(echo "$entry" | jq --argjson context "$context_json" '. + {context: $context}')
    fi

    # Add outcome if specified
    if [[ -n "$status" ]] || [[ -n "$result" ]]; then
        local outcome_json='{}'

        if [[ -n "$status" ]]; then
            outcome_json=$(echo "$outcome_json" | jq --arg status "$status" '. + {status: $status}')
        fi

        if [[ -n "$result" ]]; then
            outcome_json=$(echo "$outcome_json" | jq --arg result "$result" '. + {result: $result}')
        fi

        entry=$(echo "$entry" | jq --argjson outcome "$outcome_json" '. + {outcome: $outcome}')
    fi

    # Determine output file
    if [[ -z "$output_file" ]]; then
        output_file=$(get_output_path "$agent")
    fi

    # Ensure directory exists
    local dir
    dir=$(dirname "$output_file")
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi

    # Compact JSON for JSONL format
    local compact_entry
    compact_entry=$(echo "$entry" | jq -c '.')

    # Append to file
    echo "$compact_entry" >> "$output_file"

    print_success "Logged entry to: $output_file"
    echo "$entry" | jq '.'
}

#######################################
# Read trajectory entries
#######################################
read_entries() {
    local file_path="$1"
    shift

    local filter_agent=""
    local last_n=""
    local json_output="false"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)
                filter_agent="$2"
                shift 2
                ;;
            --last)
                last_n="$2"
                shift 2
                ;;
            --json)
                json_output="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Check file exists
    if [[ ! -f "$file_path" ]]; then
        print_error "File not found: $file_path"
        return 1
    fi

    # Read and filter entries
    local entries
    entries=$(cat "$file_path")

    if [[ -n "$filter_agent" ]]; then
        entries=$(echo "$entries" | jq -c "select(.agent == \"$filter_agent\")")
    fi

    if [[ -n "$last_n" ]]; then
        entries=$(echo "$entries" | tail -n "$last_n")
    fi

    # Output
    if [[ "$json_output" == "true" ]]; then
        echo "["
        local first=true
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                echo "$line"
            fi
        done <<< "$entries"
        echo "]"
    else
        # Pretty print each entry
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                echo "---"
                echo "$line" | jq '.'
            fi
        done <<< "$entries"
    fi
}

#######################################
# Validate trajectory file
#######################################
validate_trajectory() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        print_error "File not found: $file_path"
        return 1
    fi

    local line_num=0
    local errors=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        if [[ -z "$line" ]]; then
            continue
        fi

        # Validate JSON syntax
        if ! echo "$line" | jq empty 2>/dev/null; then
            print_error "Line $line_num: Invalid JSON"
            errors=$((errors + 1))
            continue
        fi

        # Check required fields
        local ts agent action
        ts=$(echo "$line" | jq -r '.ts // empty')
        agent=$(echo "$line" | jq -r '.agent // empty')
        action=$(echo "$line" | jq -r '.action // empty')

        if [[ -z "$ts" ]]; then
            print_warning "Line $line_num: Missing timestamp"
        fi

        if [[ -z "$agent" ]]; then
            print_error "Line $line_num: Missing agent"
            errors=$((errors + 1))
        fi

        if [[ -z "$action" ]]; then
            print_error "Line $line_num: Missing action"
            errors=$((errors + 1))
        fi
    done < "$file_path"

    if [[ $errors -eq 0 ]]; then
        print_success "Valid: $file_path ($line_num entries)"
        return 0
    else
        print_error "Found $errors errors in $file_path"
        return 1
    fi
}

#######################################
# Main entry point
#######################################
main() {
    local command=""

    # Parse command
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        log)
            log_entry "$@"
            ;;
        read)
            if [[ $# -eq 0 ]]; then
                print_error "No file specified"
                usage
                exit 1
            fi
            read_entries "$@"
            ;;
        validate)
            if [[ $# -eq 0 ]]; then
                print_error "No file specified"
                usage
                exit 1
            fi
            validate_trajectory "$1"
            ;;
        init)
            init_trajectory "${1:-}"
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
