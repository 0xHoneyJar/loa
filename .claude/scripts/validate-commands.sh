#!/usr/bin/env bash
# validate-commands.sh - Command namespace validation
#
# Checks all Loa commands against Claude Code reserved commands
# and auto-renames conflicts with -loa suffix.
#
# Usage: ./validate-commands.sh
# Exit codes: 0 = success, 1 = conflicts detected and renamed

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RESERVED_FILE="${PROJECT_ROOT}/.claude/reserved-commands.yaml"
COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"

# Check for required tools
if ! command -v yq >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: yq not found. Falling back to grep parsing.${NC}" >&2
    YQ_AVAILABLE=false
else
    YQ_AVAILABLE=true
fi

# Load reserved commands
declare -a RESERVED_COMMANDS=()

if [[ "$YQ_AVAILABLE" == "true" ]]; then
    # Use yq for YAML parsing
    while IFS= read -r cmd; do
        RESERVED_COMMANDS+=("$cmd")
    done < <(yq eval '.reserved_commands[].name' "$RESERVED_FILE")
else
    # Fallback: grep parsing (less reliable but works without yq)
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"(.+)\" ]]; then
            RESERVED_COMMANDS+=("${BASH_REMATCH[1]}")
        fi
    done < "$RESERVED_FILE"
fi

# Track conflicts
declare -a CONFLICTS=()
declare -a RENAMED=()

# Check each command file
for cmd_file in "${COMMANDS_DIR}"/*.md; do
    [[ ! -f "$cmd_file" ]] && continue

    # Extract command name from filename
    filename=$(basename "$cmd_file" .md)

    # Check against reserved list
    for reserved in "${RESERVED_COMMANDS[@]}"; do
        if [[ "$filename" == "$reserved" ]]; then
            CONFLICTS+=("$filename")

            # Auto-rename with -loa suffix
            new_name="${filename}-loa"
            new_file="${COMMANDS_DIR}/${new_name}.md"

            echo -e "${YELLOW}Conflict detected: /$filename conflicts with Claude Code built-in${NC}" >&2
            echo -e "${YELLOW}Auto-renaming to: /$new_name${NC}" >&2

            # Read file content
            content=$(cat "$cmd_file")

            # Update name field in YAML frontmatter
            updated_content=$(echo "$content" | sed "s/^name: *\"$filename\"/name: \"$new_name\"/")

            # Write to new file
            echo "$updated_content" > "$new_file"

            # Delete old file
            rm "$cmd_file"

            RENAMED+=("$filename -> $new_name")

            break
        fi
    done
done

# Report results
if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}=== Command Namespace Conflicts Resolved ===${NC}" >&2
    echo ""
    for rename in "${RENAMED[@]}"; do
        echo -e "  ${GREEN}✓${NC} $rename" >&2
    done
    echo ""
    echo -e "${YELLOW}Please update any documentation or references to these commands.${NC}" >&2
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ No command namespace conflicts detected${NC}" >&2
    exit 0
fi
