#!/usr/bin/env bash
# =============================================================================
# red-team-model-adapter.sh — Model adapter for red team pipeline
# =============================================================================
# Thin adapter between pipeline phases and model invocation.
# Currently: returns mock responses from fixtures.
# Future: delegates to cheval.py via Hounfour model routing.
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
  --mock               Use fixture data (default)
  --live               Use real model via cheval.py (not yet implemented)
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

invoke_mock() {
    local role="$1"
    local model="$2"
    local prompt_file="$3"
    local output_file="$4"
    local budget="$5"

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
# Live invocation (future — Hounfour/cheval.py)
# =============================================================================

invoke_live() {
    local role="$1"
    local model="$2"

    error "Live model invocation requires cheval.py (Hounfour integration)"
    error "Install Hounfour and configure model routing first"
    error "See: grimoires/loa/sdd.md Section 6 — Hounfour Integration"
    return 1
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

    # Test 4: Live mode returns error
    if "$0" --role attacker --model opus --prompt-file "$tmpdir/prompt.md" --output-file "$tmpdir/out4.json" --live 2>/dev/null; then
        echo "  FAIL: Live mode should fail without cheval.py"
        fail=$((fail + 1))
    else
        echo "  PASS: Live mode correctly errors without cheval.py"
        pass=$((pass + 1))
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
    local mode="mock"
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

    # Dispatch to invocation mode
    case "$mode" in
        mock) invoke_mock "$role" "$model" "$prompt_file" "$output_file" "$budget" ;;
        live) invoke_live "$role" "$model" ;;
    esac
}

main "$@"
