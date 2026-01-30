#!/usr/bin/env bash
# validate-commands.sh - Command namespace validation
#
# Checks all Loa commands against Claude Code reserved commands.
# Prevents Loa from overwriting Claude Code native commands.
#
# Usage: ./validate-commands.sh [--fix]
#   --fix: Auto-rename conflicting commands with -loa suffix
#
# Exit codes:
#   0 = success (no conflicts)
#   1 = conflicts detected (use --fix to resolve)
#   2 = error (missing dependencies, etc.)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
FIX_MODE=false
for arg in "$@"; do
    case $arg in
        --fix)
            FIX_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--fix]"
            echo ""
            echo "Validates Loa commands against Claude Code reserved commands."
            echo ""
            echo "Options:"
            echo "  --fix    Auto-rename conflicting commands with -loa suffix"
            echo "  --help   Show this help message"
            exit 0
            ;;
    esac
done

# Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RESERVED_FILE="${PROJECT_ROOT}/.claude/reserved-commands.yaml"
COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"

# Verify files exist
if [[ ! -f "$RESERVED_FILE" ]]; then
    echo -e "${RED}Error: Reserved commands file not found: $RESERVED_FILE${NC}" >&2
    exit 2
fi

if [[ ! -d "$COMMANDS_DIR" ]]; then
    echo -e "${RED}Error: Commands directory not found: $COMMANDS_DIR${NC}" >&2
    exit 2
fi

# Load reserved commands using grep (most reliable across systems)
# This avoids yq version incompatibilities (Go yq vs Python yq wrapper)
declare -a RESERVED_COMMANDS=()

while IFS= read -r line; do
    # Match: - name: "value" or - name: 'value' or - name: value
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*[\"\']?([^\"\',]+) ]]; then
        cmd="${BASH_REMATCH[1]}"
        # Trim whitespace and quotes
        cmd=$(echo "$cmd" | sed 's/^[[:space:]"'\'']*//;s/[[:space:]"'\'']*$//')
        [[ -n "$cmd" ]] && RESERVED_COMMANDS+=("$cmd")
    fi
done < "$RESERVED_FILE"

if [[ ${#RESERVED_COMMANDS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Warning: No reserved commands found in registry${NC}" >&2
fi

# Track conflicts
declare -a CONFLICTS=()
declare -a RENAMED=()

echo -e "${BLUE}Validating Loa commands against Claude Code reserved commands...${NC}"
echo ""

# Check each command file
for cmd_file in "${COMMANDS_DIR}"/*.md; do
    [[ ! -f "$cmd_file" ]] && continue

    # Extract command name from filename
    filename=$(basename "$cmd_file" .md)

    # Check against reserved list
    for reserved in "${RESERVED_COMMANDS[@]}"; do
        if [[ "$filename" == "$reserved" ]]; then
            CONFLICTS+=("$filename")

            if [[ "$FIX_MODE" == "true" ]]; then
                # Auto-rename with -loa suffix
                new_name="${filename}-loa"
                new_file="${COMMANDS_DIR}/${new_name}.md"

                echo -e "${YELLOW}Conflict: /$filename -> renaming to /$new_name${NC}"

                # Read file content
                content=$(cat "$cmd_file")

                # Update name field in YAML frontmatter
                updated_content=$(echo "$content" | sed "s/^name: *[\"']\\?$filename[\"']\\?/name: \"$new_name\"/")

                # Write to new file
                echo "$updated_content" > "$new_file"

                # Delete old file (use git mv if in git repo)
                if git rev-parse --git-dir >/dev/null 2>&1; then
                    git rm -f "$cmd_file" >/dev/null 2>&1 || rm "$cmd_file"
                    git add "$new_file" >/dev/null 2>&1 || true
                else
                    rm "$cmd_file"
                fi

                RENAMED+=("$filename -> $new_name")
            else
                echo -e "${RED}CONFLICT: /$filename overwrites Claude Code built-in command${NC}"
            fi

            break
        fi
    done
done

# Report results
echo ""

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    if [[ "$FIX_MODE" == "true" ]]; then
        echo -e "${GREEN}=== Conflicts Resolved ===${NC}"
        echo ""
        for rename in "${RENAMED[@]}"; do
            echo -e "  ${GREEN}✓${NC} /$rename"
        done
        echo ""
        echo -e "${YELLOW}Please update documentation references to these commands.${NC}"
        echo ""
        echo "Files to update:"
        echo "  - CLAUDE.md"
        echo "  - PROCESS.md"
        echo "  - README.md"
        echo "  - .claude/protocols/*.md"
        exit 0
    else
        echo -e "${RED}=== Command Namespace Conflicts Detected ===${NC}"
        echo ""
        echo "The following Loa commands conflict with Claude Code built-in commands:"
        echo ""
        for conflict in "${CONFLICTS[@]}"; do
            echo -e "  ${RED}✗${NC} /$conflict"
        done
        echo ""
        echo "Options:"
        echo "  1. Run with --fix to auto-rename: $0 --fix"
        echo "  2. Manually rename the command file to use -loa suffix"
        echo ""
        echo "Reserved commands are defined in:"
        echo "  $RESERVED_FILE"
        exit 1
    fi
else
    echo -e "${GREEN}✓ No command namespace conflicts detected${NC}"
    echo ""
    echo "Checked ${#RESERVED_COMMANDS[@]} reserved commands against $(ls -1 "${COMMANDS_DIR}"/*.md 2>/dev/null | wc -l) Loa commands"
    exit 0
fi
