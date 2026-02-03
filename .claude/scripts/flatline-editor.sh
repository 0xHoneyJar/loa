#!/usr/bin/env bash
# =============================================================================
# flatline-editor.sh - Robust document editor for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Line-based document editing with section awareness, idempotency,
# and pre/post validation. No regex-based find/replace.
#
# Usage:
#   flatline-editor.sh append_section <document> <section> <content>
#   flatline-editor.sh update_section <document> <section> <content>
#   flatline-editor.sh insert_after <document> <marker> <content>
#   flatline-editor.sh validate <document>
#
# Exit codes:
#   0 - Success
#   1 - Edit failed
#   2 - Document not found
#   3 - Invalid arguments
#   4 - Validation failed
#   5 - Duplicate content (idempotency check)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Maximum file size (10MB)
MAX_FILE_SIZE=$((10 * 1024 * 1024))

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-editor] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

warn() {
    echo "WARNING: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-editor-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_editor" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Path Validation
# =============================================================================

validate_path() {
    local path="$1"

    # Must not be empty
    if [[ -z "$path" ]]; then
        error "Path is empty"
        return 3
    fi

    # Must not contain null bytes
    if [[ "$path" == *$'\0'* ]]; then
        error "Path contains null bytes"
        return 3
    fi

    # Must not contain path traversal
    if [[ "$path" == *".."* ]]; then
        error "Path contains traversal (..) - not allowed"
        return 3
    fi

    # Resolve to absolute path
    local realpath
    realpath=$(realpath "$path" 2>/dev/null) || {
        error "Cannot resolve path: $path"
        return 3
    }

    # Must be within project directory
    if [[ ! "$realpath" == "$PROJECT_ROOT"* ]]; then
        error "Path must be within project directory: $path"
        error "Resolved to: $realpath (outside $PROJECT_ROOT)"
        return 3
    fi

    return 0
}

# =============================================================================
# Document Validation
# =============================================================================

validate_document() {
    local document="$1"
    local mode="${2:-full}"  # full | basic

    # Check file exists
    if [[ ! -f "$document" ]]; then
        error "Document not found: $document"
        return 2
    fi

    # Check file size
    local size
    size=$(stat -f%z "$document" 2>/dev/null || stat -c%s "$document" 2>/dev/null || echo "0")
    if [[ $size -gt $MAX_FILE_SIZE ]]; then
        error "Document too large: $size bytes (max: $MAX_FILE_SIZE)"
        return 4
    fi

    # Check file is readable
    if [[ ! -r "$document" ]]; then
        error "Document not readable: $document"
        return 4
    fi

    # Basic validation done
    if [[ "$mode" == "basic" ]]; then
        return 0
    fi

    # Full validation

    # Check line endings (warn on CRLF)
    if grep -q $'\r' "$document" 2>/dev/null; then
        warn "Document has CRLF line endings (Windows format)"
    fi

    # Check for valid UTF-8
    if ! file "$document" | grep -qi "utf-8\|ascii\|text" 2>/dev/null; then
        warn "Document may not be valid UTF-8 text"
    fi

    # Markdown-specific checks
    if [[ "$document" == *.md ]]; then
        # Check for unclosed code blocks
        local code_blocks
        code_blocks=$(grep -c '```' "$document" 2>/dev/null || echo "0")
        if [[ $((code_blocks % 2)) -ne 0 ]]; then
            warn "Document has unclosed code blocks (odd number of \`\`\`)"
        fi

        # Check for valid frontmatter
        if head -1 "$document" | grep -q '^---$'; then
            if ! head -20 "$document" | grep -q '^---$' | head -2 | tail -1; then
                warn "Document may have unclosed frontmatter"
            fi
        fi

        # Check for duplicate headers
        local duplicate_headers
        duplicate_headers=$(grep -E '^#+ ' "$document" 2>/dev/null | sort | uniq -d | head -1)
        if [[ -n "$duplicate_headers" ]]; then
            warn "Document has duplicate header: $duplicate_headers"
        fi
    fi

    return 0
}

# =============================================================================
# Section Detection
# =============================================================================

# Find line number of section start
find_section_line() {
    local document="$1"
    local section="$2"

    if [[ -z "$section" ]]; then
        echo "0"  # No section means end of file
        return 0
    fi

    # Look for exact header match
    local line_num
    line_num=$(grep -n "^## $section$\|^### $section$\|^# $section$" "$document" 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -z "$line_num" ]]; then
        # Try partial match
        line_num=$(grep -n "^#.*$section" "$document" 2>/dev/null | head -1 | cut -d: -f1)
    fi

    echo "${line_num:-0}"
}

# Find the end line of a section (next header at same or higher level)
find_section_end() {
    local document="$1"
    local start_line="$2"
    local section_level="$3"

    if [[ $start_line -eq 0 ]]; then
        # No start line, return total lines
        wc -l < "$document" | tr -d ' '
        return 0
    fi

    # Get the level of the section (count #s)
    if [[ -z "$section_level" ]]; then
        section_level=$(sed -n "${start_line}p" "$document" | grep -o '^#*' | wc -c)
    fi

    # Find next header at same or higher level
    local total_lines
    total_lines=$(wc -l < "$document" | tr -d ' ')

    local current_line=$((start_line + 1))
    while [[ $current_line -le $total_lines ]]; do
        local line
        line=$(sed -n "${current_line}p" "$document")

        # Check if it's a header
        if [[ "$line" =~ ^#+ ]]; then
            local line_level
            line_level=$(echo "$line" | grep -o '^#*' | wc -c)
            if [[ $line_level -le $section_level ]]; then
                # Found end of section
                echo $((current_line - 1))
                return 0
            fi
        fi
        ((current_line++))
    done

    # Section goes to end of file
    echo "$total_lines"
}

# =============================================================================
# Idempotency Check
# =============================================================================

check_duplicate_content() {
    local document="$1"
    local content="$2"

    # Normalize content (trim whitespace, single line)
    local normalized
    normalized=$(echo "$content" | head -1 | xargs)

    if [[ -z "$normalized" ]]; then
        return 1  # Empty content, not duplicate
    fi

    # Check if content already exists
    if grep -qF "$normalized" "$document" 2>/dev/null; then
        return 0  # Duplicate found
    fi

    return 1  # No duplicate
}

# =============================================================================
# Edit Operations
# =============================================================================

# Append content to a section (or end of file if no section)
append_section() {
    local document="$1"
    local section="$2"
    local content="$3"

    validate_path "$document" || return $?
    validate_document "$document" "basic" || return $?

    # Idempotency check
    if check_duplicate_content "$document" "$content"; then
        log "Content already exists, skipping (idempotency)"
        return 5
    fi

    local temp_file
    temp_file=$(mktemp)

    if [[ -z "$section" ]]; then
        # Append to end of file
        cat "$document" > "$temp_file"
        echo "" >> "$temp_file"
        echo "$content" >> "$temp_file"
    else
        local section_line
        section_line=$(find_section_line "$document" "$section")

        if [[ $section_line -eq 0 ]]; then
            # Section not found, add new section at end
            cat "$document" > "$temp_file"
            echo "" >> "$temp_file"
            echo "## $section" >> "$temp_file"
            echo "" >> "$temp_file"
            echo "$content" >> "$temp_file"
        else
            # Find section end
            local section_end
            section_end=$(find_section_end "$document" "$section_line")

            # Insert content at section end
            head -n "$section_end" "$document" > "$temp_file"
            echo "" >> "$temp_file"
            echo "$content" >> "$temp_file"
            tail -n +"$((section_end + 1))" "$document" >> "$temp_file"
        fi
    fi

    # Validate result
    if ! validate_document "$temp_file" "basic"; then
        error "Validation failed after edit"
        rm -f "$temp_file"
        return 4
    fi

    # Atomic move
    mv "$temp_file" "$document"

    log "Appended to section: $section"
    log_trajectory "append_section" "{\"document\": \"$document\", \"section\": \"$section\"}"

    return 0
}

# Update section content (replace entire section)
update_section() {
    local document="$1"
    local section="$2"
    local content="$3"

    validate_path "$document" || return $?
    validate_document "$document" "basic" || return $?

    if [[ -z "$section" ]]; then
        error "Section required for update_section"
        return 3
    fi

    local section_line
    section_line=$(find_section_line "$document" "$section")

    if [[ $section_line -eq 0 ]]; then
        error "Section not found: $section"
        return 2
    fi

    local section_end
    section_end=$(find_section_end "$document" "$section_line")

    local temp_file
    temp_file=$(mktemp)

    # Content before section
    head -n "$section_line" "$document" > "$temp_file"

    # New content
    echo "" >> "$temp_file"
    echo "$content" >> "$temp_file"

    # Content after section
    tail -n +"$((section_end + 1))" "$document" >> "$temp_file"

    # Validate result
    if ! validate_document "$temp_file" "basic"; then
        error "Validation failed after edit"
        rm -f "$temp_file"
        return 4
    fi

    # Atomic move
    mv "$temp_file" "$document"

    log "Updated section: $section"
    log_trajectory "update_section" "{\"document\": \"$document\", \"section\": \"$section\"}"

    return 0
}

# Insert content after a marker line
insert_after() {
    local document="$1"
    local marker="$2"
    local content="$3"

    validate_path "$document" || return $?
    validate_document "$document" "basic" || return $?

    # Idempotency check
    if check_duplicate_content "$document" "$content"; then
        log "Content already exists, skipping (idempotency)"
        return 5
    fi

    # Find marker line
    local marker_line
    marker_line=$(grep -n -F "$marker" "$document" 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -z "$marker_line" ]]; then
        warn "Marker not found: $marker, appending to end"
        marker_line=$(wc -l < "$document" | tr -d ' ')
    fi

    local temp_file
    temp_file=$(mktemp)

    # Content up to and including marker
    head -n "$marker_line" "$document" > "$temp_file"

    # New content
    echo "" >> "$temp_file"
    echo "$content" >> "$temp_file"

    # Content after marker
    tail -n +"$((marker_line + 1))" "$document" >> "$temp_file"

    # Validate result
    if ! validate_document "$temp_file" "basic"; then
        error "Validation failed after edit"
        rm -f "$temp_file"
        return 4
    fi

    # Atomic move
    mv "$temp_file" "$document"

    log "Inserted after: $marker"
    log_trajectory "insert_after" "{\"document\": \"$document\", \"marker\": \"$marker\"}"

    return 0
}

# Just validate a document
validate() {
    local document="$1"

    validate_path "$document" || return $?
    validate_document "$document" "full" || return $?

    log "Document validation passed: $document"
    echo '{"status": "valid", "document": "'"$document"'"}'

    return 0
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-editor.sh <command> <document> [args...]

Commands:
  append_section <document> <section> <content>
      Append content to a section (or end of file if no section)

  update_section <document> <section> <content>
      Replace entire section content

  insert_after <document> <marker> <content>
      Insert content after a specific line

  validate <document>
      Validate document structure

Exit codes:
  0 - Success
  1 - Edit failed
  2 - Document not found
  3 - Invalid arguments
  4 - Validation failed
  5 - Duplicate content (idempotency)

Examples:
  flatline-editor.sh append_section grimoires/loa/prd.md "Requirements" "- New requirement"
  flatline-editor.sh validate grimoires/loa/sdd.md
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 3
    fi

    local command="$1"
    shift

    case "$command" in
        append_section)
            if [[ $# -lt 2 ]]; then
                error "Usage: append_section <document> <section> <content>"
                exit 3
            fi
            local document="$1"
            local section="$2"
            local content="${3:-}"
            append_section "$document" "$section" "$content"
            ;;

        update_section)
            if [[ $# -lt 3 ]]; then
                error "Usage: update_section <document> <section> <content>"
                exit 3
            fi
            local document="$1"
            local section="$2"
            local content="$3"
            update_section "$document" "$section" "$content"
            ;;

        insert_after)
            if [[ $# -lt 3 ]]; then
                error "Usage: insert_after <document> <marker> <content>"
                exit 3
            fi
            local document="$1"
            local marker="$2"
            local content="$3"
            insert_after "$document" "$marker" "$content"
            ;;

        validate)
            if [[ $# -lt 1 ]]; then
                error "Usage: validate <document>"
                exit 3
            fi
            validate "$1"
            ;;

        -h|--help|help)
            usage
            exit 0
            ;;

        *)
            error "Unknown command: $command"
            usage
            exit 3
            ;;
    esac
}

main "$@"
