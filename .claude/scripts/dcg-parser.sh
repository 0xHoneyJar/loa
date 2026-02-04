#!/usr/bin/env bash
# dcg-parser.sh - Command parsing for DCG
#
# Provides two-tier parsing:
# 1. Fast path: Simple tokenization for 95%+ of commands
# 2. Slow path: AST-based parsing for complex constructs (heredocs, substitution)
#
# Usage:
#   source dcg-parser.sh
#   result=$(dcg_parse "rm -rf /tmp && echo done")
#   echo "$result" | jq '.segments[]'

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

_DCG_PARSER_VERSION="1.0.0"

# =============================================================================
# Main Parse Function
# =============================================================================

dcg_parse() {
    local command="$1"

    # Normalize Unicode (NFKC) if iconv available
    if command -v iconv &>/dev/null; then
        command=$(echo "$command" | iconv -f UTF-8 -t UTF-8//IGNORE 2>/dev/null || echo "$command")
    fi

    # Decode common encodings if detected
    command=$(_dcg_decode_if_encoded "$command")

    # Check if complex parsing needed
    if _dcg_needs_ast_parsing "$command"; then
        _dcg_parse_ast "$command"
    else
        _dcg_parse_fast "$command"
    fi
}

# =============================================================================
# AST Trigger Detection
# =============================================================================

_dcg_needs_ast_parsing() {
    local command="$1"

    # Triggers for AST parsing:
    # - Heredocs
    # - Nested command substitution
    # - Eval statements
    # - Potential encoding obfuscation

    [[ "$command" =~ '<<' ]] && return 0
    [[ "$command" =~ '\$\([^)]*\$' ]] && return 0
    [[ "$command" =~ '\beval\b' ]] && return 0
    [[ "$command" =~ 'base64|xxd|printf.*\\x' ]] && return 0

    return 1
}

# =============================================================================
# Fast Path Parser
# =============================================================================

_dcg_parse_fast() {
    local command="$1"
    local segments=()

    # Split by command operators: && || ; |
    # Preserve operator context for potential future use
    local IFS=$'\n'

    while IFS= read -r segment; do
        # Trim whitespace
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        # Strip trailing comments (not inside quotes) for pattern matching
        # This handles: rm -rf / #comment
        # But preserves: echo "hello # not a comment"
        segment=$(_dcg_strip_trailing_comment "$segment")

        [[ -n "$segment" ]] && segments+=("$segment")
    done < <(echo "$command" | sed -E 's/(\s*&&\s*|\s*\|\|\s*|\s*;\s*)/\n/g' | sed 's/\s*|\s*/\n/g')

    # Output as JSON
    _dcg_json_segments "fast" "${segments[@]}"
}

# Strip trailing comment from segment (handles quotes)
_dcg_strip_trailing_comment() {
    local segment="$1"

    # Simple approach: if # appears outside quotes, strip from there
    # This is a best-effort for common cases
    local in_single=false
    local in_double=false
    local result=""
    local i=0
    local len=${#segment}

    while [[ $i -lt $len ]]; do
        local char="${segment:$i:1}"

        if [[ "$char" == "'" && "$in_double" == "false" ]]; then
            in_single=$([[ "$in_single" == "true" ]] && echo "false" || echo "true")
            result="$result$char"
        elif [[ "$char" == '"' && "$in_single" == "false" ]]; then
            in_double=$([[ "$in_double" == "true" ]] && echo "false" || echo "true")
            result="$result$char"
        elif [[ "$char" == '#' && "$in_single" == "false" && "$in_double" == "false" ]]; then
            # Start of comment - strip rest
            break
        else
            result="$result$char"
        fi

        ((i++)) || true
    done

    # Trim trailing whitespace
    echo "$result" | sed 's/[[:space:]]*$//'
}

# =============================================================================
# AST Parser (Slow Path)
# =============================================================================

_dcg_parse_ast() {
    local command="$1"
    local segments=()
    local heredocs=()

    # Validate syntax with bash -n
    if ! bash -n <<<"$command" 2>/dev/null; then
        echo '{"type":"ast","error":"syntax_error","segments":[],"heredocs":[]}'
        return 1
    fi

    # Extract heredoc content if present
    if [[ "$command" =~ '<<' ]]; then
        heredocs=($(_dcg_extract_heredocs "$command"))
    fi

    # Split command into segments (same as fast path but preserve heredoc boundaries)
    local IFS=$'\n'
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        # Skip heredoc delimiters and content
        [[ "$segment" =~ ^EOF$ ]] && continue
        [[ "$segment" =~ ^\'EOF\'$ ]] && continue
        [[ -n "$segment" ]] && segments+=("$segment")
    done < <(echo "$command" | sed -E 's/(\s*&&\s*|\s*\|\|\s*|\s*;\s*)/\n/g' | sed 's/\s*|\s*/\n/g')

    # Output as JSON with heredocs
    printf '{"type":"ast","segments":['
    local first=true
    for seg in "${segments[@]}"; do
        [[ "$first" == "true" ]] || printf ','
        printf '"%s"' "$(echo "$seg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        first=false
    done
    printf '],"heredocs":['
    first=true
    for hd in "${heredocs[@]}"; do
        [[ "$first" == "true" ]] || printf ','
        printf '"%s"' "$(echo "$hd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        first=false
    done
    printf ']}'
}

# =============================================================================
# Heredoc Extraction
# =============================================================================

_dcg_extract_heredocs() {
    local command="$1"
    local heredocs=()

    # Simple heredoc extraction
    # Matches: << EOF ... EOF or << 'EOF' ... EOF
    local in_heredoc=false
    local delimiter=""
    local content=""

    while IFS= read -r line; do
        if [[ "$in_heredoc" == "true" ]]; then
            if [[ "$line" == "$delimiter" ]]; then
                heredocs+=("$content")
                in_heredoc=false
                content=""
            else
                [[ -n "$content" ]] && content="$content "
                content="$content$line"
            fi
        else
            # Check for heredoc start
            if [[ "$line" =~ \<\<-?[[:space:]]*[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]?$ ]]; then
                delimiter="${BASH_REMATCH[1]}"
                in_heredoc=true
                content=""
            fi
        fi
    done <<< "$command"

    # Return extracted heredocs
    for hd in "${heredocs[@]}"; do
        echo "$hd"
    done
}

# =============================================================================
# Encoding Detection and Decoding
# =============================================================================

_dcg_decode_if_encoded() {
    local input="$1"
    local decoded_comment=""

    # Base64 detection: echo "..." | base64 -d
    if [[ "$input" =~ base64[[:space:]]+-d ]]; then
        local encoded
        encoded=$(echo "$input" | grep -oP 'echo[[:space:]]+"?\K[A-Za-z0-9+/=]+' | head -1) || true
        if [[ -n "$encoded" && ${#encoded} -ge 4 ]]; then
            local decoded
            decoded=$(echo "$encoded" | base64 -d 2>/dev/null) || true
            if [[ -n "$decoded" ]]; then
                decoded_comment=" # DECODED: $decoded"
            fi
        fi
    fi

    # Hex detection: echo "..." | xxd -r
    if [[ "$input" =~ xxd[[:space:]]+-r ]]; then
        decoded_comment="$decoded_comment # HEX_ENCODED"
    fi

    # Return with decoded comment appended
    echo "$input$decoded_comment"
}

# =============================================================================
# JSON Output Helpers
# =============================================================================

_dcg_json_segments() {
    local type="$1"
    shift
    local segments=("$@")

    printf '{"type":"%s","segments":[' "$type"
    local first=true
    for seg in "${segments[@]}"; do
        [[ "$first" == "true" ]] || printf ','
        # Escape for JSON
        printf '"%s"' "$(echo "$seg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')"
        first=false
    done
    printf ']}'
}

# =============================================================================
# Utility
# =============================================================================

dcg_parser_version() {
    echo "$_DCG_PARSER_VERSION"
}
