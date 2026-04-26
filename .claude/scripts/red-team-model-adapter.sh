#!/usr/bin/env bash
# =============================================================================
# red-team-model-adapter.sh — Model adapter for red team pipeline
# =============================================================================
# Thin adapter between pipeline phases and model invocation.
# Two modes:
#   --mock  returns fixture data (or minimal empty response); emits a visible
#           WARNING banner so callers understand output is not live analysis
#   --live  delegates to `.claude/scripts/model-invoke` (cheval.py) using
#           role→agent mapping and model→provider:model-id mapping
#
# Default mode when neither flag is passed is computed by detect_default_mode:
#   live  if hounfour.flatline_routing: true AND model-invoke is executable
#         AND at least one provider API key is present
#   mock  otherwise
#
# Exit codes:
#   0  Success
#   1  Timeout / invocation failure
#   2  Budget exceeded
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

FIXTURES_DIR="$PROJECT_ROOT/.claude/data/red-team-fixtures"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Role → agent alias mapping for model-invoke routing.
# Red team doesn't have dedicated agent bindings yet; reuse flatline aliases
# whose personas are closest in spirit (attacker=skeptic, evaluator=reviewer,
# defender=dissenter). Callers can override via --model if different model
# selection is needed.
declare -A ROLE_TO_AGENT=(
    ["attacker"]="flatline-skeptic"
    ["evaluator"]="flatline-reviewer"
    ["defender"]="flatline-dissenter"
)

# Legacy model name → provider:model-id for model-invoke --model override.
# Mirrors flatline-orchestrator.sh MODEL_TO_PROVIDER_ID.
declare -A MODEL_TO_PROVIDER_ID=(
    ["gpt"]="openai:gpt-5.3-codex"
    ["gpt-5.2"]="openai:gpt-5.2"
    ["gpt-5.3-codex"]="openai:gpt-5.3-codex"
    ["opus"]="anthropic:claude-opus-4-7"
    ["claude-opus-4.7"]="anthropic:claude-opus-4-7"
    ["claude-opus-4-7"]="anthropic:claude-opus-4-7"
    ["claude-opus-4.6"]="anthropic:claude-opus-4-7"    # Retargeted in bash layer (cycle-082)
    ["claude-opus-4-6"]="anthropic:claude-opus-4-7"    # Retargeted in bash layer (cycle-082)
    ["gemini"]="google:gemini-2.5-pro"
    ["gemini-2.5-pro"]="google:gemini-2.5-pro"
    ["kimi"]="kimi:kimi-k2"
    ["qwen"]="qwen:qwen3-coder-plus"
)

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[model-adapter] $*" >&2
}

error() {
    echo "[model-adapter] ERROR: $*" >&2
}

usage() {
    cat >&2 <<'USAGE'
Usage: red-team-model-adapter.sh [OPTIONS]

Options:
  --role ROLE          Role: attacker|evaluator|defender (required)
  --model MODEL        Model: opus|gpt|kimi|qwen (required)
  --prompt-file PATH   Input prompt file (required)
  --output-file PATH   Output file for response (required)
  --budget TOKENS      Token budget (0 = unlimited)
  --timeout SECONDS    Timeout in seconds (default: 300)
  --mock               Use fixture data (emits WARNING banner on stderr)
  --live               Use real model via model-invoke (cheval.py)
                       Requires: hounfour.flatline_routing:true + API key
                       (default: auto-detect from config + env)
  --self-test          Run built-in validation
  -h, --help           Show this help
USAGE
}

# =============================================================================
# Fixture loading
# =============================================================================

load_fixture() {
    local role="$1"
    local model="$2"

    local fixture_file=""

    # Try role-specific fixture first, then generic
    if [[ -f "$FIXTURES_DIR/${role}-response-01.json" ]]; then
        fixture_file="$FIXTURES_DIR/${role}-response-01.json"
    elif [[ -f "$FIXTURES_DIR/${role}-response.json" ]]; then
        fixture_file="$FIXTURES_DIR/${role}-response.json"
    fi

    if [[ -z "$fixture_file" ]]; then
        log "No fixture found for role=$role model=$model"
        return 1
    fi

    log "Loading fixture: $fixture_file"
    cat "$fixture_file"
}

# =============================================================================
# Mock invocation
# =============================================================================

emit_mock_banner() {
    local role="$1"
    local model="$2"
    # Explicit, unmissable banner so callers (and humans reading logs) know
    # the output is fixture data, not real model analysis.
    cat >&2 <<BANNER
==============================================================================
WARNING: red-team adapter running in MOCK mode (role=$role model=$model)
  Output is FIXTURE data, not real model analysis.
  Findings are not specific to your document.
  To enable live model invocation:
    1. Set hounfour.flatline_routing: true in .loa.config.yaml
    2. Export a provider API key (ANTHROPIC_API_KEY / OPENAI_API_KEY / GOOGLE_API_KEY)
    3. Ensure .claude/scripts/model-invoke is executable
  Or pass --live explicitly to this adapter.
==============================================================================
BANNER
}

invoke_mock() {
    local role="$1"
    local model="$2"
    local prompt_file="$3"
    local output_file="$4"
    local budget="$5"

    emit_mock_banner "$role" "$model"

    local fixture_data
    fixture_data=$(load_fixture "$role" "$model") || {
        # No fixture — generate minimal valid response
        log "Generating minimal response for role=$role"
        case "$role" in
            attacker)
                jq -n --arg m "$model" '{
                    attacks: [],
                    summary: "Mock attacker — no fixture available",
                    models_used: 1,
                    tokens_used: 500,
                    model: $m,
                    mock: true
                }' > "$output_file"
                ;;
            evaluator)
                # Pass through input with evaluation scores
                if [[ -f "$prompt_file" ]] && jq empty "$prompt_file" 2>/dev/null; then
                    jq --arg m "$model" '. + {
                        evaluated: true,
                        tokens_used: 400,
                        model: $m,
                        mock: true
                    }' "$prompt_file" > "$output_file" 2>/dev/null || {
                        jq -n --arg m "$model" '{
                            attacks: [],
                            evaluated: true,
                            tokens_used: 400,
                            model: $m,
                            mock: true
                        }' > "$output_file"
                    }
                else
                    # BF-009: prompt_file is not valid JSON — generate minimal response
                    jq -n --arg m "$model" '{
                        attacks: [],
                        evaluated: true,
                        tokens_used: 400,
                        model: $m,
                        mock: true
                    }' > "$output_file"
                fi
                ;;
            defender)
                jq -n --arg m "$model" '{
                    counter_designs: [],
                    summary: "Mock defender — no fixture available",
                    tokens_used: 600,
                    model: $m,
                    mock: true
                }' > "$output_file"
                ;;
        esac
        return 0
    }

    # Write fixture data to output, adding model and mock metadata
    echo "$fixture_data" | jq --arg m "$model" '. + {model: $m, mock: true}' > "$output_file" 2>/dev/null || {
        echo "$fixture_data" > "$output_file"
    }

    # Check budget against tokens_used in fixture
    local tokens_used
    tokens_used=$(jq '.tokens_used // 0' "$output_file" 2>/dev/null || echo 0)
    if [[ "$budget" -gt 0 ]] && (( tokens_used > budget )); then
        log "Budget exceeded: fixture reports ${tokens_used} tokens > budget ${budget}"
        return 2
    fi

    return 0
}

# =============================================================================
# Live invocation — delegates to model-invoke (cheval.py)
# =============================================================================

# Detect whether at least one provider API key is set. Used by
# detect_default_mode to decide whether live mode is feasible.
has_any_api_key() {
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && return 0
    [[ -n "${OPENAI_API_KEY:-}" ]] && return 0
    [[ -n "${GOOGLE_API_KEY:-}" ]] && return 0
    [[ -n "${GEMINI_API_KEY:-}" ]] && return 0
    return 1
}

# Read hounfour.flatline_routing from config, honoring env override.
# Red team lives under the same routing flag because both subsystems
# share the cheval.py invocation path.
is_routing_enabled() {
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "true" ]]; then
        return 0
    fi
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "false" ]]; then
        return 1
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    local value
    value=$(yq '.hounfour.flatline_routing // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    [[ "$value" == "true" ]]
}

# Decide default mode when caller passes neither --live nor --mock.
# Returns: echoes "live" or "mock".
detect_default_mode() {
    if is_routing_enabled && [[ -x "$MODEL_INVOKE" ]] && has_any_api_key; then
        echo "live"
    else
        echo "mock"
    fi
}

# Wrap model-invoke content into the response shape the pipeline expects.
# Attackers/defenders emit JSON findings; we parse them if valid, otherwise
# pass through the raw content as a single free-text attack/design entry so
# the pipeline can still complete.
wrap_live_response() {
    local role="$1"
    local model="$2"
    local content="$3"
    local tokens_input="$4"
    local tokens_output="$5"
    local output_file="$6"

    local total_tokens=$((tokens_input + tokens_output))

    # If content parses as JSON, merge it into the response envelope;
    # otherwise wrap it as a free-text note.
    local parsed
    if parsed=$(echo "$content" | jq -c . 2>/dev/null) && [[ -n "$parsed" && "$parsed" != "null" ]]; then
        # Strip markdown fences if the model wrapped JSON in ```json ... ```
        :
    else
        # Try to extract JSON from a fenced code block
        parsed=$(echo "$content" | sed -n '/```json/,/```/p' | sed '1d;$d' | jq -c . 2>/dev/null || echo "")
    fi

    case "$role" in
        attacker)
            if [[ -n "$parsed" ]] && echo "$parsed" | jq -e '.attacks' >/dev/null 2>&1; then
                echo "$parsed" | jq \
                    --arg m "$model" \
                    --argjson t "$total_tokens" \
                    '. + {model: $m, tokens_used: $t, mock: false}' > "$output_file"
            else
                jq -n --arg m "$model" --arg c "$content" --argjson t "$total_tokens" '{
                    attacks: [],
                    summary: $c,
                    models_used: 1,
                    tokens_used: $t,
                    model: $m,
                    mock: false,
                    note: "Model returned non-JSON content; raw content in summary field"
                }' > "$output_file"
            fi
            ;;
        evaluator)
            if [[ -n "$parsed" ]]; then
                echo "$parsed" | jq \
                    --arg m "$model" \
                    --argjson t "$total_tokens" \
                    '. + {evaluated: true, model: $m, tokens_used: $t, mock: false}' > "$output_file"
            else
                jq -n --arg m "$model" --arg c "$content" --argjson t "$total_tokens" '{
                    attacks: [],
                    evaluated: true,
                    summary: $c,
                    tokens_used: $t,
                    model: $m,
                    mock: false
                }' > "$output_file"
            fi
            ;;
        defender)
            if [[ -n "$parsed" ]] && echo "$parsed" | jq -e '.counter_designs' >/dev/null 2>&1; then
                echo "$parsed" | jq \
                    --arg m "$model" \
                    --argjson t "$total_tokens" \
                    '. + {model: $m, tokens_used: $t, mock: false}' > "$output_file"
            else
                jq -n --arg m "$model" --arg c "$content" --argjson t "$total_tokens" '{
                    counter_designs: [],
                    summary: $c,
                    tokens_used: $t,
                    model: $m,
                    mock: false,
                    note: "Model returned non-JSON content; raw content in summary field"
                }' > "$output_file"
            fi
            ;;
    esac
}

invoke_live() {
    local role="$1"
    local model="$2"
    local prompt_file="$3"
    local output_file="$4"
    local budget="$5"
    local timeout="$6"

    if [[ ! -x "$MODEL_INVOKE" ]]; then
        error "Live mode requires executable model-invoke at: $MODEL_INVOKE"
        return 1
    fi
    if ! has_any_api_key; then
        error "Live mode requires at least one provider API key"
        error "  Set ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY, or GEMINI_API_KEY"
        return 1
    fi

    local agent="${ROLE_TO_AGENT[$role]:-flatline-reviewer}"
    local model_override="${MODEL_TO_PROVIDER_ID[$model]:-$model}"

    log "Live invocation: role=$role agent=$agent model=$model_override"

    local response_file
    response_file=$(mktemp)
    local stderr_file
    stderr_file=$(mktemp)
    local exit_code=0

    "$MODEL_INVOKE" \
        --agent "$agent" \
        --input "$prompt_file" \
        --model "$model_override" \
        --output-format json \
        --json-errors \
        --timeout "$timeout" \
        > "$response_file" 2>"$stderr_file" || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        error "model-invoke failed (exit $exit_code) for role=$role model=$model"
        if [[ -s "$stderr_file" ]]; then
            error "stderr: $(head -c 500 "$stderr_file")"
        fi
        rm -f "$response_file" "$stderr_file"
        return "$exit_code"
    fi

    # Parse model-invoke JSON envelope
    local content tokens_input tokens_output
    content=$(jq -r '.content // empty' "$response_file" 2>/dev/null || echo "")
    tokens_input=$(jq -r '.usage.input_tokens // 0' "$response_file" 2>/dev/null || echo 0)
    tokens_output=$(jq -r '.usage.output_tokens // 0' "$response_file" 2>/dev/null || echo 0)

    if [[ -z "$content" ]]; then
        error "model-invoke returned empty content"
        rm -f "$response_file" "$stderr_file"
        return 5
    fi

    wrap_live_response "$role" "$model" "$content" "$tokens_input" "$tokens_output" "$output_file"

    # Budget check
    local total_tokens=$((tokens_input + tokens_output))
    if [[ "$budget" -gt 0 ]] && (( total_tokens > budget )); then
        log "Budget exceeded: ${total_tokens} tokens > budget ${budget}"
        rm -f "$response_file" "$stderr_file"
        return 2
    fi

    rm -f "$response_file" "$stderr_file"
    return 0
}

# =============================================================================
# Self-test
# =============================================================================

run_self_test() {
    local pass=0
    local fail=0
    SELF_TEST_TMPDIR=$(mktemp -d)
    local tmpdir="$SELF_TEST_TMPDIR"
    trap 'rm -rf "$SELF_TEST_TMPDIR"' EXIT

    echo "Running model adapter self-tests..."

    # Create a minimal prompt file
    echo "Test prompt content" > "$tmpdir/prompt.md"

    # Test 1: Mock attacker with no fixture
    if "$0" --role attacker --model opus --prompt-file "$tmpdir/prompt.md" --output-file "$tmpdir/out1.json" --mock 2>/dev/null; then
        if jq -e '.mock == true' "$tmpdir/out1.json" >/dev/null 2>&1; then
            echo "  PASS: Mock attacker returns valid JSON with mock=true"
            pass=$((pass + 1))
        else
            echo "  FAIL: Mock attacker output missing mock=true"
            fail=$((fail + 1))
        fi
    else
        echo "  FAIL: Mock attacker invocation failed"
        fail=$((fail + 1))
    fi

    # Test 2: Mock evaluator with input
    jq -n '{attacks: [{id: "test-001", title: "Test Attack"}]}' > "$tmpdir/attacks.json"
    if "$0" --role evaluator --model gpt --prompt-file "$tmpdir/attacks.json" --output-file "$tmpdir/out2.json" --mock 2>/dev/null; then
        if jq -e '.mock == true' "$tmpdir/out2.json" >/dev/null 2>&1; then
            echo "  PASS: Mock evaluator returns valid JSON"
            pass=$((pass + 1))
        else
            echo "  FAIL: Mock evaluator output missing mock=true"
            fail=$((fail + 1))
        fi
    else
        echo "  FAIL: Mock evaluator invocation failed"
        fail=$((fail + 1))
    fi

    # Test 3: Mock defender
    if "$0" --role defender --model opus --prompt-file "$tmpdir/prompt.md" --output-file "$tmpdir/out3.json" --mock 2>/dev/null; then
        if jq -e '.mock == true' "$tmpdir/out3.json" >/dev/null 2>&1; then
            echo "  PASS: Mock defender returns valid JSON"
            pass=$((pass + 1))
        else
            echo "  FAIL: Mock defender output missing mock=true"
            fail=$((fail + 1))
        fi
    else
        echo "  FAIL: Mock defender invocation failed"
        fail=$((fail + 1))
    fi

    # Test 4: Live mode errors gracefully when no API key is available.
    # (Pre-fix this was "Live mode returns error — cheval.py not available".
    # Post-fix live is wired, but without API keys it must still fail cleanly.)
    (
        unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
        if "$0" --role attacker --model opus --prompt-file "$tmpdir/prompt.md" --output-file "$tmpdir/out4.json" --live 2>/dev/null; then
            exit 1
        fi
        exit 0
    )
    if [[ $? -eq 0 ]]; then
        echo "  PASS: Live mode errors cleanly when no API keys are set"
        pass=$((pass + 1))
    else
        echo "  FAIL: Live mode should fail with exit non-zero when API keys missing"
        fail=$((fail + 1))
    fi

    # Test 5: Fixture loading (if fixtures exist)
    if [[ -d "$FIXTURES_DIR" ]] && ls "$FIXTURES_DIR"/*.json >/dev/null 2>&1; then
        local fixture_count
        fixture_count=$(ls "$FIXTURES_DIR"/*.json 2>/dev/null | wc -l)
        if "$0" --role attacker --model opus --prompt-file "$tmpdir/prompt.md" --output-file "$tmpdir/out5.json" --mock 2>/dev/null; then
            if jq -e '.' "$tmpdir/out5.json" >/dev/null 2>&1; then
                echo "  PASS: Fixture loading works ($fixture_count fixtures found)"
                pass=$((pass + 1))
            else
                echo "  FAIL: Fixture output is not valid JSON"
                fail=$((fail + 1))
            fi
        else
            echo "  FAIL: Fixture loading failed"
            fail=$((fail + 1))
        fi
    else
        echo "  SKIP: No fixtures directory ($FIXTURES_DIR)"
    fi

    echo ""
    echo "Results: $pass passed, $fail failed"
    [[ $fail -eq 0 ]]
}

# =============================================================================
# Main
# =============================================================================

main() {
    local role=""
    local model=""
    local prompt_file=""
    local output_file=""
    local budget=0
    local timeout=300
    local mode=""   # empty = detect default based on config + env
    local self_test=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --role)        role="$2"; shift 2 ;;
            --model)       model="$2"; shift 2 ;;
            --prompt-file) prompt_file="$2"; shift 2 ;;
            --output-file) output_file="$2"; shift 2 ;;
            --budget)      budget="$2"; shift 2 ;;
            --timeout)     timeout="$2"; shift 2 ;;
            --mock)        mode="mock"; shift ;;
            --live)        mode="live"; shift ;;
            --self-test)   self_test=true; shift ;;
            -h|--help)     usage; exit 0 ;;
            *)             error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    if [[ "$self_test" == "true" ]]; then
        run_self_test
        exit $?
    fi

    # Validate required arguments
    if [[ -z "$role" || -z "$model" || -z "$prompt_file" || -z "$output_file" ]]; then
        error "--role, --model, --prompt-file, and --output-file are required"
        usage
        exit 1
    fi

    # Validate role
    case "$role" in
        attacker|evaluator|defender) ;;
        *) error "Invalid role: $role (must be attacker|evaluator|defender)"; exit 1 ;;
    esac

    # Validate prompt file exists
    if [[ ! -f "$prompt_file" ]]; then
        error "Prompt file not found: $prompt_file"
        exit 1
    fi

    # Resolve default mode when neither --mock nor --live was passed
    if [[ -z "$mode" ]]; then
        mode=$(detect_default_mode)
        log "Auto-detected mode: $mode (pass --live or --mock to override)"
    fi

    # Dispatch to invocation mode
    case "$mode" in
        mock) invoke_mock "$role" "$model" "$prompt_file" "$output_file" "$budget" ;;
        live) invoke_live "$role" "$model" "$prompt_file" "$output_file" "$budget" "$timeout" ;;
        *) error "Unknown mode: $mode"; exit 1 ;;
    esac
}

# Cycle-094 G-5 + sprint-2 BB iter-1 F3 fix: only run main when invoked
# directly. Tests source this file to introspect MODEL_TO_PROVIDER_ID
# natively (bash is the only robust parser of bash data); without this
# guard the sourced load runs main and exits on missing required args,
# leaving the test unable to read the array.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
