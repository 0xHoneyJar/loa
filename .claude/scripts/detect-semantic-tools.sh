#!/bin/bash
# =============================================================================
# detect-semantic-tools.sh - Semantic Tool Detection for Compound Learning
# =============================================================================
# Detects available semantic search tools and exports SEMANTIC_TOOLS variable.
# Used by compound learning scripts for layered similarity strategy.
#
# Available tools:
#   - ck: Code semantic search (ck --hybrid)
#   - memory_stack: Text embeddings via sentence-transformers
#   - qmd: Grimoire/skill search (BM25 + vector + rerank)
#
# Usage:
#   source .claude/scripts/detect-semantic-tools.sh
#   echo "Available tools: $SEMANTIC_TOOLS"
#
# Or call directly:
#   .claude/scripts/detect-semantic-tools.sh --json
#
# SDD Reference: grimoires/loa/sdd.md §1 Semantic Search Integration
# =============================================================================

set -euo pipefail

# Configuration file path
CONFIG_FILE="${LOA_CONFIG:-.loa.config.yaml}"

# -----------------------------------------------------------------------------
# Tool Detection Functions
# -----------------------------------------------------------------------------

detect_ck() {
    # Check if ck binary is available
    if command -v ck &> /dev/null; then
        # Verify it works
        if ck --version &> /dev/null 2>&1; then
            echo "ck"
            return 0
        fi
    fi
    return 1
}

detect_memory_stack() {
    # Check if sentence-transformers is available
    if python3 -c "import sentence_transformers" 2>/dev/null; then
        # Check if memory is enabled in config (need yq)
        if [ -f "$CONFIG_FILE" ] && command -v yq &> /dev/null; then
            local memory_enabled
            memory_enabled=$(yq -r '.memory.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
            if [ "$memory_enabled" = "true" ]; then
                echo "memory_stack"
                return 0
            fi
            # Also check compound_learning.similarity.memory_stack.enabled
            local compound_memory_enabled
            compound_memory_enabled=$(yq -r '.compound_learning.similarity.memory_stack.enabled // "auto"' "$CONFIG_FILE" 2>/dev/null || echo "auto")
            if [ "$compound_memory_enabled" = "true" ] || [ "$compound_memory_enabled" = "auto" ]; then
                echo "memory_stack"
                return 0
            fi
        else
            # No config check needed if sentence_transformers is available and config has auto
            echo "memory_stack"
            return 0
        fi
    fi
    return 1
}

detect_qmd() {
    # Check if qmd binary is available
    if command -v qmd &> /dev/null; then
        # Check if qmd is enabled in config (need yq)
        if [ -f "$CONFIG_FILE" ] && command -v yq &> /dev/null; then
            local qmd_enabled
            qmd_enabled=$(yq -r '.memory.qmd.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
            if [ "$qmd_enabled" = "true" ]; then
                echo "qmd"
                return 0
            fi
            # Also check compound_learning.similarity.qmd.enabled
            local compound_qmd_enabled
            compound_qmd_enabled=$(yq -r '.compound_learning.similarity.qmd.enabled // "auto"' "$CONFIG_FILE" 2>/dev/null || echo "auto")
            if [ "$compound_qmd_enabled" = "true" ] || [ "$compound_qmd_enabled" = "auto" ]; then
                echo "qmd"
                return 0
            fi
        else
            # qmd binary exists and config defaults to auto
            echo "qmd"
            return 0
        fi
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Main Detection Logic
# -----------------------------------------------------------------------------

detect_all_tools() {
    local tools=()
    
    # Detect each tool
    local ck_result
    ck_result=$(detect_ck 2>/dev/null || true)
    [ -n "$ck_result" ] && tools+=("$ck_result")
    
    local memory_result
    memory_result=$(detect_memory_stack 2>/dev/null || true)
    [ -n "$memory_result" ] && tools+=("$memory_result")
    
    local qmd_result
    qmd_result=$(detect_qmd 2>/dev/null || true)
    [ -n "$qmd_result" ] && tools+=("$qmd_result")
    
    # Return space-separated list
    echo "${tools[*]:-}"
}

# -----------------------------------------------------------------------------
# Get Similarity Threshold for Tool
# -----------------------------------------------------------------------------

get_threshold() {
    local tool="$1"
    
    # Default thresholds
    local default_ck="0.7"
    local default_memory="0.35"
    local default_qmd="0.5"
    local default_jaccard="0.6"
    
    # If no config or yq not available, use defaults
    if [ ! -f "$CONFIG_FILE" ] || ! command -v yq &> /dev/null; then
        case "$tool" in
            ck) echo "$default_ck" ;;
            memory_stack) echo "$default_memory" ;;
            qmd) echo "$default_qmd" ;;
            jaccard) echo "$default_jaccard" ;;
            *) echo "0.5" ;;
        esac
        return
    fi
    
    # Read from config with fallback to defaults
    case "$tool" in
        ck)
            yq -r ".compound_learning.similarity.ck.threshold // $default_ck" "$CONFIG_FILE" 2>/dev/null || echo "$default_ck"
            ;;
        memory_stack)
            yq -r ".compound_learning.similarity.memory_stack.threshold // $default_memory" "$CONFIG_FILE" 2>/dev/null || echo "$default_memory"
            ;;
        qmd)
            yq -r ".compound_learning.similarity.qmd.threshold // $default_qmd" "$CONFIG_FILE" 2>/dev/null || echo "$default_qmd"
            ;;
        jaccard)
            yq -r ".compound_learning.similarity.fallback.jaccard_threshold // $default_jaccard" "$CONFIG_FILE" 2>/dev/null || echo "$default_jaccard"
            ;;
        *)
            echo "0.5"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Get Best Available Tool for Event Type
# -----------------------------------------------------------------------------

get_best_tool() {
    local event_type="${1:-text}"
    local available_tools
    available_tools=$(detect_all_tools)
    
    if [ -z "$available_tools" ]; then
        echo "jaccard"
        return
    fi
    
    case "$event_type" in
        code|code_event|implementation)
            # Prefer ck for code-related events
            if [[ "$available_tools" == *"ck"* ]]; then
                echo "ck"
            elif [[ "$available_tools" == *"memory_stack"* ]]; then
                echo "memory_stack"
            else
                echo "jaccard"
            fi
            ;;
        text|learning|skill)
            # Prefer Memory Stack for text/learning similarity
            if [[ "$available_tools" == *"memory_stack"* ]]; then
                echo "memory_stack"
            elif [[ "$available_tools" == *"qmd"* ]]; then
                echo "qmd"
            else
                echo "jaccard"
            fi
            ;;
        grimoire|search)
            # Prefer qmd for document search
            if [[ "$available_tools" == *"qmd"* ]]; then
                echo "qmd"
            elif [[ "$available_tools" == *"memory_stack"* ]]; then
                echo "memory_stack"
            else
                echo "jaccard"
            fi
            ;;
        *)
            # Default: prefer memory_stack, then ck, then qmd, then jaccard
            if [[ "$available_tools" == *"memory_stack"* ]]; then
                echo "memory_stack"
            elif [[ "$available_tools" == *"ck"* ]]; then
                echo "ck"
            elif [[ "$available_tools" == *"qmd"* ]]; then
                echo "qmd"
            else
                echo "jaccard"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Output Formats
# -----------------------------------------------------------------------------

output_json() {
    local tools
    tools=$(detect_all_tools)
    
    local best_code
    best_code=$(get_best_tool "code")
    local best_text
    best_text=$(get_best_tool "text")
    local best_grimoire
    best_grimoire=$(get_best_tool "grimoire")
    
    # Build JSON array of tools
    local tools_json="[]"
    if [ -n "$tools" ]; then
        tools_json=$(echo "$tools" | tr ' ' '\n' | jq -R . | jq -s .)
    fi
    
    cat <<EOF
{
  "available_tools": $tools_json,
  "best_for": {
    "code": "$best_code",
    "text": "$best_text",
    "grimoire": "$best_grimoire"
  },
  "thresholds": {
    "ck": $(get_threshold ck),
    "memory_stack": $(get_threshold memory_stack),
    "qmd": $(get_threshold qmd),
    "jaccard": $(get_threshold jaccard)
  },
  "fallback": "jaccard"
}
EOF
}

output_env() {
    local tools
    tools=$(detect_all_tools)
    
    echo "export SEMANTIC_TOOLS=\"$tools\""
    echo "export SEMANTIC_TOOL_CODE=\"$(get_best_tool code)\""
    echo "export SEMANTIC_TOOL_TEXT=\"$(get_best_tool text)\""
    echo "export SEMANTIC_TOOL_GRIMOIRE=\"$(get_best_tool grimoire)\""
    echo "export SEMANTIC_THRESHOLD_CK=\"$(get_threshold ck)\""
    echo "export SEMANTIC_THRESHOLD_MEMORY=\"$(get_threshold memory_stack)\""
    echo "export SEMANTIC_THRESHOLD_QMD=\"$(get_threshold qmd)\""
    echo "export SEMANTIC_THRESHOLD_JACCARD=\"$(get_threshold jaccard)\""
}

# -----------------------------------------------------------------------------
# CLI Interface
# -----------------------------------------------------------------------------

show_help() {
    cat <<EOF
detect-semantic-tools.sh - Semantic Tool Detection for Compound Learning

USAGE:
    detect-semantic-tools.sh [OPTIONS]

OPTIONS:
    --json          Output as JSON
    --env           Output as shell exports (can be eval'd)
    --check TOOL    Check if specific tool is available (exit 0/1)
    --best TYPE     Get best tool for type (code|text|grimoire)
    --threshold     Get threshold for tool
    --list          List available tools (space-separated)
    --help          Show this help

EXAMPLES:
    # Source to set environment variables
    source .claude/scripts/detect-semantic-tools.sh

    # Get JSON summary
    .claude/scripts/detect-semantic-tools.sh --json

    # Check if ck is available
    if .claude/scripts/detect-semantic-tools.sh --check ck; then
        echo "ck is available"
    fi

    # Get best tool for code similarity
    TOOL=\$(.claude/scripts/detect-semantic-tools.sh --best code)

ENVIRONMENT:
    LOA_CONFIG      Path to .loa.config.yaml (default: .loa.config.yaml)
    SEMANTIC_TOOLS  Set after sourcing (space-separated tool list)

EOF
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

main() {
    case "${1:-}" in
        --json)
            output_json
            ;;
        --env)
            output_env
            ;;
        --check)
            local tool="${2:-}"
            if [ -z "$tool" ]; then
                echo "Error: --check requires a tool name" >&2
                exit 1
            fi
            local available
            available=$(detect_all_tools)
            if [[ "$available" == *"$tool"* ]]; then
                exit 0
            else
                exit 1
            fi
            ;;
        --best)
            local event_type="${2:-text}"
            get_best_tool "$event_type"
            ;;
        --threshold)
            local tool="${2:-jaccard}"
            get_threshold "$tool"
            ;;
        --list)
            detect_all_tools
            ;;
        --help|-h)
            show_help
            ;;
        "")
            # When sourced, just export the variable
            export SEMANTIC_TOOLS
            SEMANTIC_TOOLS=$(detect_all_tools)
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    # When sourced, set up exports
    export SEMANTIC_TOOLS
    SEMANTIC_TOOLS=$(detect_all_tools 2>/dev/null || echo "")
fi
