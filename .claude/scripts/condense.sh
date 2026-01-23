#!/usr/bin/env bash
# Condense - Result condensation engine for recursive JIT context system
# Part of the Loa framework's Recursive JIT Context System
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/../cache}"
FULL_DIR="${FULL_DIR:-${CACHE_DIR}/full}"

# Default configuration values
DEFAULT_STRATEGY="structured_verdict"
DEFAULT_MAX_TOKENS="50"
DEFAULT_TOP_FINDINGS="5"

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
Usage: condense.sh <command> [options]

Condense - Result condensation engine for recursive JIT context system

Commands:
  condense --strategy <name> --input <file|->  Condense input using strategy
  strategies                                   List available strategies
  estimate --input <file|->                   Estimate token count

Options:
  --help, -h                        Show this help message
  --strategy <name>                 Condensation strategy (default: structured_verdict)
  --input <file|->                  Input file or - for stdin
  --output <file>                   Output file (default: stdout)
  --externalize                     Write full result to external file
  --output-dir <dir>                Directory for externalized files
  --preserve <fields>               Comma-separated fields to preserve
  --top <n>                         Number of top findings (default: 5)
  --json                            Output as JSON

Available Strategies:
  structured_verdict    Extract verdict, severity counts, top findings (~50 tokens)
  identifiers_only      Extract path:line identifiers only (~20 tokens)
  summary               AI-generated summary (requires external call)

Configuration (.loa.config.yaml):
  recursive_jit:
    condensation:
      default_strategy: structured_verdict
      max_condensed_tokens: 50
      preserve_fields: [verdict, severity_counts, top_findings]

Examples:
  # Condense audit result
  condense.sh condense --strategy structured_verdict --input audit-result.json

  # Condense search results to identifiers
  condense.sh condense --strategy identifiers_only --input search.json

  # Externalize full result
  condense.sh condense --input audit.json --externalize --output-dir .claude/cache/full

  # From stdin
  cat result.json | condense.sh condense --strategy identifiers_only --input -
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
# Check dependencies
#######################################
check_dependencies() {
    local missing=()

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install ${missing[*]}"
        echo "  Ubuntu: sudo apt install ${missing[*]}"
        return 1
    fi

    return 0
}

#######################################
# Calculate SHA256 hash (portable)
#######################################
sha256_hash() {
    local input="$1"
    if command -v sha256sum &>/dev/null; then
        echo -n "$input" | sha256sum | cut -d' ' -f1
    else
        echo -n "$input" | shasum -a 256 | cut -d' ' -f1
    fi
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
# Get default strategy from config
#######################################
get_default_strategy() {
    get_config "recursive_jit.condensation.default_strategy" "$DEFAULT_STRATEGY"
}

#######################################
# Get max condensed tokens from config
#######################################
get_max_tokens() {
    get_config "recursive_jit.condensation.max_condensed_tokens" "$DEFAULT_MAX_TOKENS"
}

#######################################
# Read input (file or stdin)
#######################################
read_input() {
    local input="$1"

    if [[ "$input" == "-" ]]; then
        cat
    elif [[ -f "$input" ]]; then
        cat "$input"
    else
        print_error "Input file not found: $input"
        return 1
    fi
}

#######################################
# Validate JSON input
#######################################
validate_json() {
    local content="$1"
    if ! echo "$content" | jq -e '.' &>/dev/null; then
        print_error "Invalid JSON input"
        return 1
    fi
}

#######################################
# Estimate token count (~4 chars per token)
#######################################
estimate_tokens() {
    local content="$1"
    local chars
    chars=$(echo -n "$content" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

#######################################
# Strategy: structured_verdict
# Extracts verdict, severity counts, and top findings
#######################################
strategy_structured_verdict() {
    local input="$1"
    local top_findings="${2:-$DEFAULT_TOP_FINDINGS}"
    local preserve_fields="${3:-}"

    # Extract core verdict fields
    local verdict severity_counts top_findings_arr full_path

    verdict=$(echo "$input" | jq -r '.verdict // .status // .result // "UNKNOWN"')
    severity_counts=$(echo "$input" | jq -c '.severity_counts // .severities // {critical: 0, high: 0, medium: 0, low: 0}')

    # Extract findings/issues array (try multiple field names)
    local findings_path
    if echo "$input" | jq -e '.findings' &>/dev/null; then
        findings_path=".findings"
    elif echo "$input" | jq -e '.issues' &>/dev/null; then
        findings_path=".issues"
    elif echo "$input" | jq -e '.results' &>/dev/null; then
        findings_path=".results"
    elif echo "$input" | jq -e '.vulnerabilities' &>/dev/null; then
        findings_path=".vulnerabilities"
    else
        findings_path=".findings"
    fi

    # Get top N findings with file:line identifiers
    top_findings_arr=$(echo "$input" | jq -c --argjson n "${top_findings:-5}" "
        (${findings_path} // [])[:(\$n)] | map({
            id: (.id // .finding_id // .name // \"unknown\"),
            severity: (.severity // .level // \"medium\"),
            file: (.file // .path // .location // \"unknown\"),
            line: (.line // .line_number // 0),
            message: ((.message // .description // .title // \"\") | .[0:100])
        })
    " 2>/dev/null || echo "[]")

    # Build condensed output
    local condensed
    condensed=$(jq -n \
        --arg verdict "$verdict" \
        --argjson severity_counts "$severity_counts" \
        --argjson top_findings "$top_findings_arr" \
        '{
            verdict: $verdict,
            severity_counts: $severity_counts,
            top_findings: $top_findings
        }')

    # Add any additional preserved fields
    if [[ -n "$preserve_fields" ]]; then
        IFS=',' read -ra FIELDS <<< "$preserve_fields"
        for field in "${FIELDS[@]}"; do
            local field_value
            field_value=$(echo "$input" | jq -c ".$field // null")
            if [[ "$field_value" != "null" ]]; then
                condensed=$(echo "$condensed" | jq --arg f "$field" --argjson v "$field_value" '. + {($f): $v}')
            fi
        done
    fi

    echo "$condensed"
}

#######################################
# Strategy: identifiers_only
# Extracts only path:line identifiers for minimal context
#######################################
strategy_identifiers_only() {
    local input="$1"

    # Get project root for relative paths
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

    # Extract identifiers from various input formats
    local identifiers

    # Try different array field names
    local arr_path
    if echo "$input" | jq -e '.files' &>/dev/null; then
        arr_path=".files"
    elif echo "$input" | jq -e '.matches' &>/dev/null; then
        arr_path=".matches"
    elif echo "$input" | jq -e '.results' &>/dev/null; then
        arr_path=".results"
    elif echo "$input" | jq -e '.findings' &>/dev/null; then
        arr_path=".findings"
    elif echo "$input" | jq -e '.items' &>/dev/null; then
        arr_path=".items"
    else
        arr_path=".files"
    fi

    identifiers=$(echo "$input" | jq -c --arg root "${project_root}" "
        (${arr_path} // []) | map(
            if type == \"string\" then
                \"\(\$root)/\" + .
            else
                \"\(\$root)/\" + (.file // .path // \"unknown\") + \":\" + ((.line // .line_number // 0) | tostring)
            end
        ) | unique
    " 2>/dev/null || echo "[]")

    # Extract query and confidence if present
    local query confidence top_match
    query=$(echo "$input" | jq -r '.query // empty')
    confidence=$(echo "$input" | jq -r '.confidence // .score // empty')
    top_match=$(echo "$input" | jq -r '.top_match // .best_match // empty')

    # Build minimal output
    local condensed
    condensed=$(jq -n \
        --argjson identifiers "$identifiers" \
        '{identifiers: $identifiers}')

    if [[ -n "$query" ]]; then
        condensed=$(echo "$condensed" | jq --arg q "$query" '. + {query: $q}')
    fi

    if [[ -n "$confidence" ]]; then
        condensed=$(echo "$condensed" | jq --arg c "$confidence" '. + {confidence: ($c | tonumber)}')
    fi

    if [[ -n "$top_match" ]]; then
        condensed=$(echo "$condensed" | jq --arg t "$top_match" '. + {top_match: $t}')
    fi

    echo "$condensed"
}

#######################################
# Strategy: summary
# Creates a brief text summary (passthrough for now, would use AI in full impl)
#######################################
strategy_summary() {
    local input="$1"
    local max_tokens="${2:-100}"

    # For now, extract key fields and create structured summary
    # Full implementation would call Claude for semantic summarization

    local verdict description item_count

    verdict=$(echo "$input" | jq -r '.verdict // .status // .result // "completed"')
    description=$(echo "$input" | jq -r '.description // .summary // .message // ""' | head -c 200)

    # Count items
    if echo "$input" | jq -e '.findings' &>/dev/null; then
        item_count=$(echo "$input" | jq '.findings | length')
    elif echo "$input" | jq -e '.results' &>/dev/null; then
        item_count=$(echo "$input" | jq '.results | length')
    elif echo "$input" | jq -e '.items' &>/dev/null; then
        item_count=$(echo "$input" | jq '.items | length')
    else
        item_count=0
    fi

    jq -n \
        --arg verdict "$verdict" \
        --arg desc "$description" \
        --argjson count "$item_count" \
        '{
            type: "summary",
            verdict: $verdict,
            description: $desc,
            item_count: $count
        }'
}

#######################################
# Externalize full result to file
#######################################
externalize_result() {
    local content="$1"
    local output_dir="${2:-$FULL_DIR}"

    mkdir -p "$output_dir"

    # Generate hash-based filename
    local content_hash
    content_hash=$(sha256_hash "$content")
    local output_path="${output_dir}/${content_hash}.json"

    # Write full content
    echo "$content" > "$output_path"

    echo "$output_path"
}

#######################################
# CMD: Condense input
#######################################
cmd_condense() {
    local strategy=""
    local input_file=""
    local output_file=""
    local externalize="false"
    local output_dir="$FULL_DIR"
    local preserve_fields=""
    local top_n="$DEFAULT_TOP_FINDINGS"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy) strategy="$2"; shift 2 ;;
            --input) input_file="$2"; shift 2 ;;
            --output) output_file="$2"; shift 2 ;;
            --externalize) externalize="true"; shift ;;
            --output-dir) output_dir="$2"; shift 2 ;;
            --preserve) preserve_fields="$2"; shift 2 ;;
            --top) top_n="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Default strategy from config
    if [[ -z "$strategy" ]]; then
        strategy=$(get_default_strategy)
    fi

    # Require input
    if [[ -z "$input_file" ]]; then
        print_error "Required: --input <file|->"
        return 1
    fi

    # Read and validate input
    local content
    content=$(read_input "$input_file")
    validate_json "$content" || return 1

    # Apply strategy
    local condensed
    case "$strategy" in
        structured_verdict)
            condensed=$(strategy_structured_verdict "$content" "$top_n" "$preserve_fields")
            ;;
        identifiers_only)
            condensed=$(strategy_identifiers_only "$content")
            ;;
        summary)
            condensed=$(strategy_summary "$content")
            ;;
        *)
            print_error "Unknown strategy: $strategy"
            print_info "Available: structured_verdict, identifiers_only, summary"
            return 1
            ;;
    esac

    # Handle externalization
    if [[ "$externalize" == "true" ]]; then
        local full_path
        full_path=$(externalize_result "$content" "$output_dir")
        condensed=$(echo "$condensed" | jq --arg path "$full_path" '. + {full_result_path: $path}')
        print_info "Full result externalized to: $full_path" >&2
    fi

    # Output
    if [[ -n "$output_file" ]]; then
        echo "$condensed" | jq . > "$output_file"
        print_success "Condensed result written to: $output_file" >&2
    else
        echo "$condensed" | jq .
    fi
}

#######################################
# CMD: List strategies
#######################################
cmd_strategies() {
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ "$json_output" == "true" ]]; then
        jq -n '{
            strategies: [
                {
                    name: "structured_verdict",
                    description: "Extract verdict, severity counts, and top N findings",
                    target_tokens: 50,
                    best_for: ["security audits", "code reviews", "test results"]
                },
                {
                    name: "identifiers_only",
                    description: "Extract only file:line identifiers",
                    target_tokens: 20,
                    best_for: ["search results", "file listings", "grep output"]
                },
                {
                    name: "summary",
                    description: "Generate brief text summary",
                    target_tokens: 100,
                    best_for: ["documentation", "explanations", "reports"]
                }
            ],
            default: "'"$(get_default_strategy)"'"
        }'
    else
        echo ""
        echo -e "${CYAN}Available Condensation Strategies${NC}"
        echo "==================================="
        echo ""
        echo -e "${GREEN}structured_verdict${NC} (~50 tokens)"
        echo "  Extract verdict, severity counts, and top N findings"
        echo "  Best for: security audits, code reviews, test results"
        echo ""
        echo -e "${GREEN}identifiers_only${NC} (~20 tokens)"
        echo "  Extract only file:line identifiers"
        echo "  Best for: search results, file listings, grep output"
        echo ""
        echo -e "${GREEN}summary${NC} (~100 tokens)"
        echo "  Generate brief text summary"
        echo "  Best for: documentation, explanations, reports"
        echo ""
        echo -e "Default strategy: ${CYAN}$(get_default_strategy)${NC}"
        echo ""
    fi
}

#######################################
# CMD: Estimate tokens
#######################################
cmd_estimate() {
    local input_file=""
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input) input_file="$2"; shift 2 ;;
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$input_file" ]]; then
        print_error "Required: --input <file|->"
        return 1
    fi

    local content
    content=$(read_input "$input_file")

    local original_tokens
    original_tokens=$(estimate_tokens "$content")

    # Estimate condensed sizes for each strategy
    local sv_tokens io_tokens su_tokens

    # Run condensation and estimate
    local sv_content io_content su_content

    if validate_json "$content" 2>/dev/null; then
        sv_content=$(strategy_structured_verdict "$content" 5 "" 2>/dev/null || echo "{}")
        io_content=$(strategy_identifiers_only "$content" 2>/dev/null || echo "{}")
        su_content=$(strategy_summary "$content" 2>/dev/null || echo "{}")

        sv_tokens=$(estimate_tokens "$sv_content")
        io_tokens=$(estimate_tokens "$io_content")
        su_tokens=$(estimate_tokens "$su_content")
    else
        sv_tokens=0
        io_tokens=0
        su_tokens=0
    fi

    if [[ "$json_output" == "true" ]]; then
        jq -n \
            --argjson original "$original_tokens" \
            --argjson structured_verdict "$sv_tokens" \
            --argjson identifiers_only "$io_tokens" \
            --argjson summary "$su_tokens" \
            '{
                original_tokens: $original,
                condensed: {
                    structured_verdict: $structured_verdict,
                    identifiers_only: $identifiers_only,
                    summary: $summary
                },
                savings: {
                    structured_verdict_pct: (if $original > 0 then (100 - ($structured_verdict * 100 / $original)) | floor else 0 end),
                    identifiers_only_pct: (if $original > 0 then (100 - ($identifiers_only * 100 / $original)) | floor else 0 end),
                    summary_pct: (if $original > 0 then (100 - ($summary * 100 / $original)) | floor else 0 end)
                }
            }'
    else
        local sv_savings io_savings su_savings
        if [[ "$original_tokens" -gt 0 ]]; then
            sv_savings=$((100 - (sv_tokens * 100 / original_tokens)))
            io_savings=$((100 - (io_tokens * 100 / original_tokens)))
            su_savings=$((100 - (su_tokens * 100 / original_tokens)))
        else
            sv_savings=0
            io_savings=0
            su_savings=0
        fi

        echo ""
        echo -e "${CYAN}Token Estimates${NC}"
        echo "================"
        echo ""
        echo "  Original:           $original_tokens tokens"
        echo ""
        echo "  After condensation:"
        echo "    structured_verdict: $sv_tokens tokens (${sv_savings}% savings)"
        echo "    identifiers_only:   $io_tokens tokens (${io_savings}% savings)"
        echo "    summary:            $su_tokens tokens (${su_savings}% savings)"
        echo ""
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
        condense)
            check_dependencies || exit 1
            cmd_condense "$@"
            ;;
        strategies)
            cmd_strategies "$@"
            ;;
        estimate)
            check_dependencies || exit 1
            cmd_estimate "$@"
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
