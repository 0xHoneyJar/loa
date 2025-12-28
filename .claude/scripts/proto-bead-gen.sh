#!/bin/bash
# proto-bead-gen.sh
# Purpose: Generate a proto-bead YAML from component JSDoc tags
# Usage: ./proto-bead-gen.sh <component-name> [--component-file <path>]
#
# Exit codes:
#   0 - Proto-bead generated successfully
#   1 - Component not found or missing required tags
#   2 - Invalid arguments
#
# Output:
#   SUCCESS|<proto-bead-path>
#   ERROR|<reason>

set -euo pipefail

# Configuration
PROTO_BEADS_DIR="${PROTO_BEADS_DIR:-loa-grimoire/proto-beads}"
COMPONENT_DIRS=("src/components" "components" "app/components" "packages/ui/src")

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
COMPONENT_NAME=""
COMPONENT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --component-file)
            COMPONENT_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: proto-bead-gen.sh <component-name> [--component-file <path>]"
            echo ""
            echo "Arguments:"
            echo "  component-name    Name of the component (e.g., JoyfulLoader)"
            echo "  --component-file  Path to component file (auto-detected if not provided)"
            echo ""
            echo "Examples:"
            echo "  ./proto-bead-gen.sh JoyfulLoader"
            echo "  ./proto-bead-gen.sh ClaimButton --component-file src/components/ClaimButton.tsx"
            exit 0
            ;;
        -*)
            echo "ERROR|Unknown option: $1"
            exit 2
            ;;
        *)
            COMPONENT_NAME="$1"
            shift
            ;;
    esac
done

# Validate component name
if [[ -z "${COMPONENT_NAME}" ]]; then
    echo "ERROR|Component name required"
    exit 2
fi

# Find component file if not provided
if [[ -z "${COMPONENT_FILE}" ]]; then
    for dir in "${COMPONENT_DIRS[@]}"; do
        if [[ -f "${dir}/${COMPONENT_NAME}.tsx" ]]; then
            COMPONENT_FILE="${dir}/${COMPONENT_NAME}.tsx"
            break
        elif [[ -f "${dir}/${COMPONENT_NAME}.jsx" ]]; then
            COMPONENT_FILE="${dir}/${COMPONENT_NAME}.jsx"
            break
        elif [[ -f "${dir}/${COMPONENT_NAME}/index.tsx" ]]; then
            COMPONENT_FILE="${dir}/${COMPONENT_NAME}/index.tsx"
            break
        fi
    done
fi

# Verify component file exists
if [[ -z "${COMPONENT_FILE}" ]] || [[ ! -f "${COMPONENT_FILE}" ]]; then
    echo "ERROR|Component file not found for ${COMPONENT_NAME}"
    exit 1
fi

# Extract JSDoc tags using grep
extract_tag() {
    local tag="$1"
    local file="$2"
    # Extract multiline content between @tag and next @tag or */
    grep -ozP "(?<=@${tag})[^@]*" "${file}" 2>/dev/null | tr '\0' '\n' | sed 's/^[[:space:]]*\*[[:space:]]*//' | sed '/^$/d' | head -50 || echo ""
}

extract_single_line_tag() {
    local tag="$1"
    local file="$2"
    grep -oP "(?<=@${tag})[^\n]*" "${file}" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo ""
}

# Check for Gold tier
TIER=$(extract_single_line_tag "tier" "${COMPONENT_FILE}")
if [[ "${TIER}" != *"gold"* ]]; then
    echo "ERROR|Component is not Gold tier (found: ${TIER:-none})"
    exit 1
fi

# Check for taste owner
TASTE_OWNER=$(extract_single_line_tag "tasteOwner" "${COMPONENT_FILE}")
if [[ -z "${TASTE_OWNER}" ]]; then
    echo "ERROR|Missing @tasteOwner tag"
    exit 1
fi

# Extract required fields
DESCRIPTION=$(extract_tag "description" "${COMPONENT_FILE}")
FEEL=$(extract_tag "feel" "${COMPONENT_FILE}")

if [[ -z "${DESCRIPTION}" ]]; then
    echo "ERROR|Missing @description tag"
    exit 1
fi

if [[ -z "${FEEL}" ]]; then
    echo "ERROR|Missing @feel tag"
    exit 1
fi

# Extract optional fields
INTENT=$(extract_single_line_tag "intent" "${COMPONENT_FILE}")
REJECTED=$(extract_single_line_tag "rejected" "${COMPONENT_FILE}")
INSPIRATION=$(extract_tag "inspiration" "${COMPONENT_FILE}")
PHYSICS=$(extract_single_line_tag "physics" "${COMPONENT_FILE}")
STATES=$(extract_tag "states" "${COMPONENT_FILE}")

# Parse physics JSON if present
TENSION=""
FRICTION=""
DELAY=""
DURATION=""
if [[ -n "${PHYSICS}" ]]; then
    # Extract values from JSON-like string
    TENSION=$(echo "${PHYSICS}" | grep -oP '(?<="tension":)\s*\d+' | tr -d ' ' || echo "")
    FRICTION=$(echo "${PHYSICS}" | grep -oP '(?<="friction":)\s*\d+' | tr -d ' ' || echo "")
    DELAY=$(echo "${PHYSICS}" | grep -oP '(?<="delay":)\s*\d+' | tr -d ' ' || echo "")
    DURATION=$(echo "${PHYSICS}" | grep -oP '(?<="duration":)\s*\d+' | tr -d ' ' || echo "")
fi

# Parse rejected into array
REJECTED_ARRAY=""
if [[ -n "${REJECTED}" ]]; then
    # Split by comma and format as YAML array
    IFS=',' read -ra ITEMS <<< "${REJECTED}"
    for item in "${ITEMS[@]}"; do
        item=$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        REJECTED_ARRAY="${REJECTED_ARRAY}    - \"${item}\"
"
    done
fi

# Parse inspiration into array
INSPIRATION_ARRAY=""
if [[ -n "${INSPIRATION}" ]]; then
    while IFS= read -r line; do
        line=$(echo "${line}" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "${line}" ]]; then
            INSPIRATION_ARRAY="${INSPIRATION_ARRAY}    - \"${line}\"
"
        fi
    done <<< "${INSPIRATION}"
fi

# Create proto-beads directory if needed
mkdir -p "${PROTO_BEADS_DIR}"

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Generate proto-bead YAML
PROTO_BEAD_FILE="${PROTO_BEADS_DIR}/${COMPONENT_NAME}.yaml"

cat > "${PROTO_BEAD_FILE}" << EOF
# Proto-Bead: ${COMPONENT_NAME}
# Generated: ${TIMESTAMP}
# Source: ${COMPONENT_FILE}

schema_version: "1.0.0"
id: ${COMPONENT_NAME}
created_at: "${TIMESTAMP}"
updated_at: "${TIMESTAMP}"

component:
  name: ${COMPONENT_NAME}
  file: ${COMPONENT_FILE}
  type: react

signature:
  tier: gold
  taste_owner: ${TASTE_OWNER}
  signed_at: "${TIMESTAMP}"

capture:
  description: |
$(echo "${DESCRIPTION}" | sed 's/^/    /')
  feel: |
$(echo "${FEEL}" | sed 's/^/    /')
  intent: ${INTENT:-null}
  rejected:
${REJECTED_ARRAY:-"    []"}
  inspiration:
${INSPIRATION_ARRAY:-"    []"}

physics:
  tension: ${TENSION:-null}
  friction: ${FRICTION:-null}
  delay: ${DELAY:-null}
  duration: ${DURATION:-null}
  preset: null

# THE GAP - HivemindOS fills this
why: null

hivemind:
  synced: false
  bead_id: null
  synced_at: null
EOF

# Update index
INDEX_FILE="${PROTO_BEADS_DIR}/index.yaml"

# Create index if it doesn't exist
if [[ ! -f "${INDEX_FILE}" ]]; then
    cat > "${INDEX_FILE}" << EOF
# Proto-Bead Index
# Auto-generated - do not edit manually

schema_version: "1.0.0"
last_updated: "${TIMESTAMP}"

summary:
  total: 0
  gold: 0
  silver: 0
  synced: 0

beads: []
EOF
fi

# Check if bead already exists in index
if grep -q "id: ${COMPONENT_NAME}" "${INDEX_FILE}" 2>/dev/null; then
    # Update existing entry's timestamp
    sed -i.bak "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" "${INDEX_FILE}"
    rm -f "${INDEX_FILE}.bak"
else
    # Add new entry to beads array
    # First, update summary counts
    CURRENT_TOTAL=$(grep -oP '(?<=total: )\d+' "${INDEX_FILE}" || echo "0")
    CURRENT_GOLD=$(grep -oP '(?<=gold: )\d+' "${INDEX_FILE}" || echo "0")
    NEW_TOTAL=$((CURRENT_TOTAL + 1))
    NEW_GOLD=$((CURRENT_GOLD + 1))

    sed -i.bak "s/total: ${CURRENT_TOTAL}/total: ${NEW_TOTAL}/" "${INDEX_FILE}"
    sed -i.bak "s/gold: ${CURRENT_GOLD}/gold: ${NEW_GOLD}/" "${INDEX_FILE}"
    sed -i.bak "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" "${INDEX_FILE}"
    rm -f "${INDEX_FILE}.bak"

    # Append new bead entry
    cat >> "${INDEX_FILE}" << EOF

  - id: ${COMPONENT_NAME}
    tier: gold
    taste_owner: ${TASTE_OWNER}
    file: ${COMPONENT_NAME}.yaml
    synced: false
    created_at: "${TIMESTAMP}"
EOF
fi

echo "SUCCESS|${PROTO_BEAD_FILE}"
exit 0
