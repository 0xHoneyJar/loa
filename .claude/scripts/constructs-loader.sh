#!/usr/bin/env bash
# constructs-loader.sh - Main skill loader for Loa Constructs
#
# Usage:
#   constructs-loader.sh list                 - Show all skills with status
#   constructs-loader.sh list-packs           - Show all packs with status
#   constructs-loader.sh loadable             - Return paths of loadable skills
#   constructs-loader.sh validate <skill-dir> - Validate single skill's license
#   constructs-loader.sh validate-pack <dir>  - Validate a pack's license
#   constructs-loader.sh preload <skill-dir>  - Pre-load hook for skill loading
#   constructs-loader.sh list-pack-skills <d> - List skills in a pack
#   constructs-loader.sh get-pack-version <d> - Get pack version from manifest
#   constructs-loader.sh check-updates        - Check for available updates
#
# Exit Codes (for validate/preload):
#   0 = valid
#   1 = expired (in grace period)
#   2 = expired (beyond grace)
#   3 = missing license file
#   4 = invalid signature
#   5 = other error
#
# Environment Variables:
#   LOA_CONSTRUCTS_DIR   - Override registry directory (default: .claude/constructs)
#   LOA_CACHE_DIR      - Override cache directory (default: ~/.loa/cache)
#   LOA_OFFLINE        - Set to 1 for offline-only mode
#   NO_COLOR           - Disable colored output
#
# Sources: sdd.md:§5.1 (Registry Loader Script), prd.md:FR-SCR-01, FR-SCR-02

set -euo pipefail

# Get script directory for sourcing dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [[ -f "$SCRIPT_DIR/constructs-lib.sh" ]]; then
    source "$SCRIPT_DIR/constructs-lib.sh"
else
    echo "ERROR: constructs-lib.sh not found" >&2
    exit 5
fi

# Source safe yq library (HIGH-001 fix)
if [[ -f "$SCRIPT_DIR/yq-safe.sh" ]]; then
    source "$SCRIPT_DIR/yq-safe.sh"
fi

# =============================================================================
# Constants
# =============================================================================

EXIT_VALID=0
EXIT_GRACE=1
EXIT_EXPIRED=2
EXIT_MISSING=3
EXIT_INVALID_SIG=4
EXIT_ERROR=5

# License validator script
LICENSE_VALIDATOR="$SCRIPT_DIR/license-validator.sh"

# =============================================================================
# Directory Management
# =============================================================================

# Get registry directory (with environment override)
get_registry_dir() {
    if [[ -n "${LOA_CONSTRUCTS_DIR:-}" ]]; then
        echo "$LOA_CONSTRUCTS_DIR"
    else
        echo ".claude/constructs"
    fi
}

# Get skills directory within registry
get_skills_dir() {
    echo "$(get_registry_dir)/skills"
}

# Get packs directory within registry
get_packs_dir() {
    echo "$(get_registry_dir)/packs"
}

# =============================================================================
# Skill Discovery
# =============================================================================

# Find all skill directories in registry
# Returns: List of skill directories (vendor/name format)
discover_skills() {
    local skills_dir
    skills_dir=$(get_skills_dir)

    if [[ ! -d "$skills_dir" ]]; then
        return 0
    fi

    # Find all directories that look like skills (have index.yaml or SKILL.md)
    find "$skills_dir" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | while read -r skill_dir; do
        # Check if it looks like a skill directory
        if [[ -f "$skill_dir/index.yaml" ]] || [[ -f "$skill_dir/SKILL.md" ]]; then
            # Extract vendor/skill name from path
            local relative_path="${skill_dir#$skills_dir/}"
            echo "$relative_path"
        fi
    done
}

# Get full path to skill directory
# Args:
#   $1 - Skill slug (vendor/name)
# Returns: Full path to skill directory
get_skill_path() {
    local skill_slug="$1"
    echo "$(get_skills_dir)/$skill_slug"
}

# Get skill version from index.yaml
# Args:
#   $1 - Skill directory path
# Returns: Version string or "unknown"
get_skill_version() {
    local skill_dir="$1"
    local index_file="$skill_dir/index.yaml"

    if [[ ! -f "$index_file" ]]; then
        echo "unknown"
        return 0
    fi

    # HIGH-001 fix: Use safe_yq_version if available
    if type safe_yq_version &>/dev/null; then
        safe_yq_version '.version' "$index_file" "unknown"
        return 0
    elif command -v yq &>/dev/null; then
        local version
        local yq_version_output
        yq_version_output=$(yq --version 2>&1 || echo "")

        if echo "$yq_version_output" | grep -q "mikefarah\|version.*4"; then
            # mikefarah/yq v4 syntax
            version=$(yq eval '.version // "unknown"' "$index_file" 2>/dev/null || echo "unknown")
        else
            # Python yq (jq wrapper) - file comes before filter
            version=$(yq '.version // "unknown"' "$index_file" 2>/dev/null || echo "unknown")
        fi
        # Handle python yq returning quoted values
        version="${version#\"}"
        version="${version%\"}"

        # HIGH-001 fix: Validate version format before returning
        if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ && "$version" != "unknown" ]]; then
            echo "unknown"
            return 0
        fi

        echo "$version"
    else
        # Fallback: grep for version line
        grep -E "^version:" "$index_file" 2>/dev/null | sed 's/version:[[:space:]]*//' | tr -d '"' || echo "unknown"
    fi
}

# =============================================================================
# Pack Discovery
# =============================================================================

# Find all pack directories in registry
# Returns: List of pack slugs
discover_packs() {
    local packs_dir
    packs_dir=$(get_packs_dir)

    if [[ ! -d "$packs_dir" ]]; then
        return 0
    fi

    # Find all directories with manifest.json
    find "$packs_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r pack_dir; do
        if [[ -f "$pack_dir/manifest.json" ]]; then
            basename "$pack_dir"
        fi
    done
}

# Get full path to pack directory
# Args:
#   $1 - Pack slug
# Returns: Full path to pack directory
get_pack_path() {
    local pack_slug="$1"
    echo "$(get_packs_dir)/$pack_slug"
}

# Get pack version from manifest.json
# Args:
#   $1 - Pack directory path
# Returns: Version string or "unknown"
get_pack_version() {
    local pack_dir="$1"
    local manifest_file="$pack_dir/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
        echo "unknown"
        return 0
    fi

    # Use jq if available, otherwise grep
    if command -v jq &>/dev/null; then
        jq -r '.version // "unknown"' "$manifest_file" 2>/dev/null || echo "unknown"
    else
        grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest_file" 2>/dev/null | \
            sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown"
    fi
}

# Get pack name from manifest.json
# Args:
#   $1 - Pack directory path
# Returns: Name string or pack directory name
get_pack_name() {
    local pack_dir="$1"
    local manifest_file="$pack_dir/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
        basename "$pack_dir"
        return 0
    fi

    if command -v jq &>/dev/null; then
        local name
        name=$(jq -r '.name // ""' "$manifest_file" 2>/dev/null)
        if [[ -n "$name" ]]; then
            echo "$name"
        else
            basename "$pack_dir"
        fi
    else
        grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest_file" 2>/dev/null | \
            sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || basename "$pack_dir"
    fi
}

# List skills in a pack from manifest.json
# Args:
#   $1 - Pack directory path
# Returns: List of skill slugs
list_pack_skills() {
    local pack_dir="$1"
    local manifest_file="$pack_dir/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
        return 0
    fi

    if command -v jq &>/dev/null; then
        jq -r '.skills[]?.slug // empty' "$manifest_file" 2>/dev/null
    else
        # Fallback: basic grep extraction
        grep -o '"slug"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest_file" 2>/dev/null | \
            sed 's/.*"slug"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    fi
}

# =============================================================================
# Registry Meta Management
# =============================================================================

# Get registry meta file path
get_registry_meta_path() {
    echo "$(get_registry_dir)/.constructs-meta.json"
}

# Initialize or read registry meta
# Returns: JSON content of registry meta
read_registry_meta() {
    local meta_path
    meta_path=$(get_registry_meta_path)

    if [[ -f "$meta_path" ]]; then
        cat "$meta_path"
    else
        # Return empty structure
        echo '{"schema_version":1,"installed_skills":{},"installed_packs":{}}'
    fi
}

# Write registry meta
# Args:
#   $1 - JSON content to write
write_registry_meta() {
    local content="$1"
    local meta_path
    meta_path=$(get_registry_meta_path)

    # Ensure registry directory exists
    mkdir -p "$(dirname "$meta_path")"

    echo "$content" > "$meta_path"
}

# Update installed skill in registry meta
# Args:
#   $1 - Skill slug (vendor/name)
#   $2 - Version
#   $3 - License expires timestamp
#   $4 - From pack (optional)
update_skill_in_meta() {
    local skill_slug="$1"
    local version="$2"
    local license_expires="$3"
    local from_pack="${4:-null}"

    local meta_path
    meta_path=$(get_registry_meta_path)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v jq &>/dev/null; then
        local current_meta
        current_meta=$(read_registry_meta)

        # Update or add skill entry
        local from_pack_json
        if [[ "$from_pack" == "null" ]]; then
            from_pack_json="null"
        else
            from_pack_json="\"$from_pack\""
        fi

        local updated_meta
        updated_meta=$(echo "$current_meta" | jq \
            --arg slug "$skill_slug" \
            --arg version "$version" \
            --arg installed_at "$now" \
            --arg license_expires "$license_expires" \
            --argjson from_pack "$from_pack_json" \
            '.installed_skills[$slug] = {
                "version": $version,
                "installed_at": $installed_at,
                "updated_at": $installed_at,
                "registry": "default",
                "license_expires": $license_expires,
                "from_pack": $from_pack
            }')

        write_registry_meta "$updated_meta"
    else
        # Fallback without jq - create simple meta file
        cat > "$meta_path" << EOF
{
    "schema_version": 1,
    "installed_skills": {
        "$skill_slug": {
            "version": "$version",
            "installed_at": "$now",
            "registry": "default",
            "license_expires": "$license_expires",
            "from_pack": $([[ "$from_pack" == "null" ]] && echo "null" || echo "\"$from_pack\"")
        }
    },
    "installed_packs": {}
}
EOF
    fi
}

# Update installed pack in registry meta
# Args:
#   $1 - Pack slug
#   $2 - Version
#   $3 - License expires timestamp
#   $4 - Skills array (space-separated)
update_pack_in_meta() {
    local pack_slug="$1"
    local version="$2"
    local license_expires="$3"
    shift 3
    local skills=("$@")

    local meta_path
    meta_path=$(get_registry_meta_path)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v jq &>/dev/null; then
        local current_meta
        current_meta=$(read_registry_meta)

        # Build skills array JSON
        local skills_json="["
        local first=true
        for skill in "${skills[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                skills_json+=","
            fi
            skills_json+="\"$skill\""
        done
        skills_json+="]"

        local updated_meta
        updated_meta=$(echo "$current_meta" | jq \
            --arg slug "$pack_slug" \
            --arg version "$version" \
            --arg installed_at "$now" \
            --arg license_expires "$license_expires" \
            --argjson skills "$skills_json" \
            '.installed_packs[$slug] = {
                "version": $version,
                "installed_at": $installed_at,
                "registry": "default",
                "license_expires": $license_expires,
                "skills": $skills
            }')

        write_registry_meta "$updated_meta"
    else
        # Fallback without jq
        local skills_json="["
        local first=true
        for skill in "${skills[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                skills_json+=","
            fi
            skills_json+="\"$skill\""
        done
        skills_json+="]"

        cat > "$meta_path" << EOF
{
    "schema_version": 1,
    "installed_skills": {},
    "installed_packs": {
        "$pack_slug": {
            "version": "$version",
            "installed_at": "$now",
            "registry": "default",
            "license_expires": "$license_expires",
            "skills": $skills_json
        }
    }
}
EOF
    fi
}

# =============================================================================
# License Validation
# =============================================================================

# Validate a skill's license
# Args:
#   $1 - Skill directory path
# Returns: Exit code from license validator
validate_skill() {
    local skill_dir="$1"
    local license_file="$skill_dir/.license.json"

    # Check directory exists
    if [[ ! -d "$skill_dir" ]]; then
        echo "ERROR: Skill directory not found: $skill_dir" >&2
        return $EXIT_ERROR
    fi

    # Check license file exists
    if [[ ! -f "$license_file" ]]; then
        return $EXIT_MISSING
    fi

    # Delegate to license validator
    if [[ -x "$LICENSE_VALIDATOR" ]]; then
        "$LICENSE_VALIDATOR" validate "$license_file"
        return $?
    else
        echo "ERROR: License validator not found or not executable" >&2
        return $EXIT_ERROR
    fi
}

# Get validation status as human-readable string
# Args:
#   $1 - Exit code from validate
# Returns: Status string
get_status_string() {
    local exit_code="$1"

    case "$exit_code" in
        0) echo "valid" ;;
        1) echo "grace" ;;
        2) echo "expired" ;;
        3) echo "missing" ;;
        4) echo "invalid" ;;
        *) echo "error" ;;
    esac
}

# Validate a pack's license
# Args:
#   $1 - Pack directory path
# Returns: Exit code from license validator
validate_pack() {
    local pack_dir="$1"
    local license_file="$pack_dir/.license.json"
    local manifest_file="$pack_dir/manifest.json"

    # Check directory exists
    if [[ ! -d "$pack_dir" ]]; then
        echo "ERROR: Pack directory not found: $pack_dir" >&2
        return $EXIT_ERROR
    fi

    # Check manifest exists
    if [[ ! -f "$manifest_file" ]]; then
        echo "ERROR: Pack manifest not found: $manifest_file" >&2
        return $EXIT_ERROR
    fi

    # Check license file exists
    if [[ ! -f "$license_file" ]]; then
        return $EXIT_MISSING
    fi

    # Delegate to license validator
    if [[ -x "$LICENSE_VALIDATOR" ]]; then
        "$LICENSE_VALIDATOR" validate "$license_file"
        return $?
    else
        echo "ERROR: License validator not found or not executable" >&2
        return $EXIT_ERROR
    fi
}

# =============================================================================
# List Command
# =============================================================================

# List all registry skills with status
do_list() {
    local skills_dir
    skills_dir=$(get_skills_dir)

    # Check if registry directory exists
    if [[ ! -d "$skills_dir" ]]; then
        echo "No registry skills installed (directory not found)"
        return 0
    fi

    # Discover skills
    local skills
    skills=$(discover_skills)

    # Discover packs
    local packs
    packs=$(discover_packs)

    # Check if anything is installed
    if [[ -z "$skills" ]] && [[ -z "$packs" ]]; then
        echo "No registry skills installed"
        return 0
    fi

    # Show standalone skills if any
    if [[ -n "$skills" ]]; then
        echo "Registry Skills:"
        echo "─────────────────────────────────────────────────"

        while IFS= read -r skill_slug; do
            [[ -z "$skill_slug" ]] && continue

            local skill_dir
            skill_dir=$(get_skill_path "$skill_slug")

        # Extract just the skill name (last part after /)
        local skill_name="${skill_slug##*/}"

        # Check if reserved
        if is_reserved_skill_name "$skill_name"; then
            # Skip reserved skills or show warning
            continue
        fi

        # Get version
        local version
        version=$(get_skill_version "$skill_dir")

        # Validate license
        local exit_code=0
        local output=""
        if [[ -x "$LICENSE_VALIDATOR" ]] && [[ -f "$skill_dir/.license.json" ]]; then
            output=$("$LICENSE_VALIDATOR" validate "$skill_dir/.license.json" 2>&1) || exit_code=$?
        elif [[ ! -f "$skill_dir/.license.json" ]]; then
            exit_code=$EXIT_MISSING
        else
            exit_code=$EXIT_ERROR
        fi

        # Display based on status
        case "$exit_code" in
            0)
                print_status "$icon_valid" "$skill_slug ($version)"
                ;;
            1)
                # Extract grace period info from output
                local grace_info=""
                if [[ "$output" == *"remaining"* ]]; then
                    grace_info=" [${output##*,}]"
                else
                    grace_info=" [grace period]"
                fi
                print_status "$icon_warning" "$skill_slug ($version)$grace_info"
                ;;
            2)
                print_status "$icon_error" "$skill_slug ($version) [expired]"
                ;;
            3)
                print_status "$icon_unknown" "$skill_slug ($version) [missing license]"
                ;;
            4)
                print_status "$icon_error" "$skill_slug ($version) [invalid signature]"
                ;;
            *)
                print_status "$icon_unknown" "$skill_slug ($version) [error]"
                ;;
        esac
        done <<< "$skills"
    fi

    # Also list pack skills (packs already discovered above)
    if [[ -n "$packs" ]]; then
        echo ""
        echo "Pack Skills:"
        echo "─────────────────────────────────────────────────"

        while IFS= read -r pack_slug; do
            [[ -z "$pack_slug" ]] && continue

            local pack_dir
            pack_dir=$(get_pack_path "$pack_slug")

            # Validate pack license
            local exit_code=0
            local output=""
            if [[ -x "$LICENSE_VALIDATOR" ]] && [[ -f "$pack_dir/.license.json" ]]; then
                output=$("$LICENSE_VALIDATOR" validate "$pack_dir/.license.json" 2>&1) || exit_code=$?
            elif [[ ! -f "$pack_dir/.license.json" ]]; then
                exit_code=$EXIT_MISSING
            else
                exit_code=$EXIT_ERROR
            fi

            # Get pack version
            local pack_version
            pack_version=$(get_pack_version "$pack_dir")

            # List skills in pack with pack indicator
            local pack_skills
            pack_skills=$(list_pack_skills "$pack_dir")

            while IFS= read -r skill_name; do
                [[ -z "$skill_name" ]] && continue

                local display_name="$pack_slug/$skill_name"
                local skill_version
                if [[ -f "$pack_dir/skills/$skill_name/index.yaml" ]]; then
                    skill_version=$(get_skill_version "$pack_dir/skills/$skill_name")
                else
                    skill_version="$pack_version"
                fi

                case "$exit_code" in
                    0)
                        print_status "$icon_valid" "$display_name ($skill_version) [pack: $pack_slug]"
                        ;;
                    1)
                        print_status "$icon_warning" "$display_name ($skill_version) [pack: $pack_slug] [grace]"
                        ;;
                    2)
                        print_status "$icon_error" "$display_name ($skill_version) [pack: $pack_slug] [expired]"
                        ;;
                    3)
                        print_status "$icon_unknown" "$display_name ($skill_version) [pack: $pack_slug] [missing license]"
                        ;;
                    *)
                        print_status "$icon_unknown" "$display_name ($skill_version) [pack: $pack_slug] [error]"
                        ;;
                esac
            done <<< "$pack_skills"
        done <<< "$packs"
    fi

    echo ""
}

# =============================================================================
# List Packs Command
# =============================================================================

# List all registry packs with status
do_list_packs() {
    local packs_dir
    packs_dir=$(get_packs_dir)

    # Check if packs directory exists
    if [[ ! -d "$packs_dir" ]]; then
        echo "No packs installed"
        return 0
    fi

    # Discover packs
    local packs
    packs=$(discover_packs)

    if [[ -z "$packs" ]]; then
        echo "No packs installed"
        return 0
    fi

    echo "Registry Packs:"
    echo "─────────────────────────────────────────────────"

    while IFS= read -r pack_slug; do
        [[ -z "$pack_slug" ]] && continue

        local pack_dir
        pack_dir=$(get_pack_path "$pack_slug")

        # Get pack info
        local version
        version=$(get_pack_version "$pack_dir")
        local name
        name=$(get_pack_name "$pack_dir")

        # Count skills
        local skill_count
        skill_count=$(list_pack_skills "$pack_dir" | wc -l | tr -d ' ')

        # Validate pack license
        local exit_code=0
        local output=""
        if [[ -x "$LICENSE_VALIDATOR" ]] && [[ -f "$pack_dir/.license.json" ]]; then
            output=$("$LICENSE_VALIDATOR" validate "$pack_dir/.license.json" 2>&1) || exit_code=$?
        elif [[ ! -f "$pack_dir/.license.json" ]]; then
            exit_code=$EXIT_MISSING
        else
            exit_code=$EXIT_ERROR
        fi

        # Display based on status
        local status_info="$skill_count skills"
        case "$exit_code" in
            0)
                print_status "$icon_valid" "$pack_slug ($version) [$status_info]"
                ;;
            1)
                print_status "$icon_warning" "$pack_slug ($version) [$status_info] [grace period]"
                ;;
            2)
                print_status "$icon_error" "$pack_slug ($version) [$status_info] [expired]"
                ;;
            3)
                print_status "$icon_unknown" "$pack_slug ($version) [$status_info] [missing license]"
                ;;
            4)
                print_status "$icon_error" "$pack_slug ($version) [$status_info] [invalid signature]"
                ;;
            *)
                print_status "$icon_unknown" "$pack_slug ($version) [$status_info] [error]"
                ;;
        esac
    done <<< "$packs"

    echo ""
}

# =============================================================================
# Loadable Command
# =============================================================================

# Return paths of skills that are valid or in grace period
do_loadable() {
    local skills_dir
    skills_dir=$(get_skills_dir)

    # Check if registry directory exists
    if [[ ! -d "$skills_dir" ]]; then
        return 0
    fi

    # Discover skills
    local skills
    skills=$(discover_skills)

    # Process standalone skills if any
    if [[ -n "$skills" ]]; then
        while IFS= read -r skill_slug; do
        [[ -z "$skill_slug" ]] && continue

        local skill_dir
        skill_dir=$(get_skill_path "$skill_slug")

        # Extract just the skill name (last part after /)
        local skill_name="${skill_slug##*/}"

        # Skip reserved skills
        if is_reserved_skill_name "$skill_name"; then
            continue
        fi

        # Check license file exists
        if [[ ! -f "$skill_dir/.license.json" ]]; then
            continue
        fi

        # Validate license
        local exit_code=0
        if [[ -x "$LICENSE_VALIDATOR" ]]; then
            "$LICENSE_VALIDATOR" validate "$skill_dir/.license.json" >/dev/null 2>&1 || exit_code=$?
        else
            continue
        fi

        # Include if valid (0) or in grace period (1)
        if [[ "$exit_code" -eq 0 ]] || [[ "$exit_code" -eq 1 ]]; then
            echo "$skill_dir"
        fi
        done <<< "$skills"
    fi

    # Also include skills from valid packs
    local packs
    packs=$(discover_packs)

    if [[ -n "$packs" ]]; then
        while IFS= read -r pack_slug; do
            [[ -z "$pack_slug" ]] && continue

            local pack_dir
            pack_dir=$(get_pack_path "$pack_slug")

            # Check pack has license
            if [[ ! -f "$pack_dir/.license.json" ]]; then
                continue
            fi

            # Validate pack license
            local exit_code=0
            if [[ -x "$LICENSE_VALIDATOR" ]]; then
                "$LICENSE_VALIDATOR" validate "$pack_dir/.license.json" >/dev/null 2>&1 || exit_code=$?
            else
                continue
            fi

            # Include pack skills if valid (0) or in grace period (1)
            if [[ "$exit_code" -eq 0 ]] || [[ "$exit_code" -eq 1 ]]; then
                local pack_skills
                pack_skills=$(list_pack_skills "$pack_dir")

                while IFS= read -r skill_name; do
                    [[ -z "$skill_name" ]] && continue
                    local skill_path="$pack_dir/skills/$skill_name"
                    if [[ -d "$skill_path" ]]; then
                        echo "$skill_path"
                    fi
                done <<< "$pack_skills"
            fi
        done <<< "$packs"
    fi
}

# =============================================================================
# Validate Command
# =============================================================================

# Validate a single skill's license and update registry meta
do_validate() {
    local skill_dir="$1"

    # Ensure constructs directory is gitignored
    ensure_constructs_gitignored

    # Validate skill
    local exit_code=0
    validate_skill "$skill_dir" || exit_code=$?

    # On successful validation (valid or grace), update registry meta
    if [[ "$exit_code" -eq 0 ]] || [[ "$exit_code" -eq 1 ]]; then
        # Extract skill slug from path
        local skills_dir
        skills_dir=$(get_skills_dir)
        local skill_slug="${skill_dir#$skills_dir/}"

        # Get version
        local version
        version=$(get_skill_version "$skill_dir")

        # Get license expiry from license file
        local license_expires=""
        local license_file="$skill_dir/.license.json"
        if [[ -f "$license_file" ]]; then
            if command -v jq &>/dev/null; then
                license_expires=$(jq -r '.expires_at // ""' "$license_file" 2>/dev/null)
            else
                license_expires=$(grep -o '"expires_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$license_file" 2>/dev/null | \
                    sed 's/.*"expires_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
        fi

        # Update registry meta
        update_skill_in_meta "$skill_slug" "$version" "$license_expires"
    fi

    return $exit_code
}

# Validate a pack's license and update registry meta
do_validate_pack() {
    local pack_dir="$1"

    # Ensure constructs directory is gitignored
    ensure_constructs_gitignored

    # First validate the manifest is valid JSON
    local manifest_file="$pack_dir/manifest.json"
    if [[ -f "$manifest_file" ]]; then
        if command -v jq &>/dev/null; then
            if ! jq empty "$manifest_file" 2>/dev/null; then
                echo "ERROR: Invalid JSON in manifest: $manifest_file" >&2
                return $EXIT_ERROR
            fi
        fi
    fi

    # Validate pack
    local exit_code=0
    validate_pack "$pack_dir" || exit_code=$?

    # On successful validation (valid or grace), update registry meta
    if [[ "$exit_code" -eq 0 ]] || [[ "$exit_code" -eq 1 ]]; then
        # Get pack slug from path
        local packs_dir
        packs_dir=$(get_packs_dir)
        local pack_slug="${pack_dir#$packs_dir/}"
        # Handle absolute paths outside packs_dir
        if [[ "$pack_slug" == "$pack_dir" ]]; then
            pack_slug=$(basename "$pack_dir")
        fi

        # Get version
        local version
        version=$(get_pack_version "$pack_dir")

        # Get license expiry from license file
        local license_expires=""
        local license_file="$pack_dir/.license.json"
        if [[ -f "$license_file" ]]; then
            if command -v jq &>/dev/null; then
                license_expires=$(jq -r '.expires_at // ""' "$license_file" 2>/dev/null)
            else
                license_expires=$(grep -o '"expires_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$license_file" 2>/dev/null | \
                    sed 's/.*"expires_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
        fi

        # Get skills in pack
        local pack_skills_list=()
        local pack_skills
        pack_skills=$(list_pack_skills "$pack_dir")
        while IFS= read -r skill; do
            [[ -n "$skill" ]] && pack_skills_list+=("$skill")
        done <<< "$pack_skills"

        # Update pack in registry meta
        update_pack_in_meta "$pack_slug" "$version" "$license_expires" "${pack_skills_list[@]}"

        # Also update each skill in meta with from_pack reference
        for skill_name in "${pack_skills_list[@]}"; do
            local skill_path="$pack_dir/skills/$skill_name"
            local skill_version
            if [[ -f "$skill_path/index.yaml" ]]; then
                skill_version=$(get_skill_version "$skill_path")
            else
                skill_version="$version"
            fi
            update_skill_in_meta "$pack_slug/$skill_name" "$skill_version" "$license_expires" "$pack_slug"
        done
    fi

    return $exit_code
}

# =============================================================================
# Preload Command
# =============================================================================

# Pre-load hook - validate skill before loading
do_preload() {
    local skill_dir="$1"

    # Get skill slug for display
    local skills_dir
    skills_dir=$(get_skills_dir)
    local skill_slug="${skill_dir#$skills_dir/}"
    local skill_name="${skill_slug##*/}"

    # Check if reserved
    if is_reserved_skill_name "$skill_name"; then
        print_warning "WARNING: '$skill_name' conflicts with reserved skill name"
        return $EXIT_ERROR
    fi

    # Validate license
    local exit_code=0
    local output=""
    output=$(validate_skill "$skill_dir" 2>&1) || exit_code=$?

    case "$exit_code" in
        0)
            # Valid - silent success
            return 0
            ;;
        1)
            # Grace period - warn but allow
            print_warning "WARNING: $skill_slug license in grace period"
            echo "$output" >&2
            return 1
            ;;
        2)
            # Expired - block
            print_error "ERROR: $skill_slug license expired"
            return 2
            ;;
        3)
            # Missing license - block
            print_error "ERROR: $skill_slug missing license file"
            return 3
            ;;
        4)
            # Invalid signature - block
            print_error "ERROR: $skill_slug has invalid license signature"
            return 4
            ;;
        *)
            print_error "ERROR: $skill_slug validation failed"
            return $EXIT_ERROR
            ;;
    esac
}

# =============================================================================
# Check Updates Command (Sprint 5)
# =============================================================================

# Update the last_update_check timestamp in registry meta
update_last_check_timestamp() {
    local meta_path
    meta_path=$(get_registry_meta_path)

    # Ensure meta file exists
    init_registry_meta_file

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v jq &>/dev/null; then
        local tmp_file="${meta_path}.tmp"
        jq ".last_update_check = \"$timestamp\"" "$meta_path" > "$tmp_file" && mv "$tmp_file" "$meta_path"
    else
        # Fallback: sed replacement
        sed -i.bak "s/\"last_update_check\"[[:space:]]*:[[:space:]]*[^,}]*/\"last_update_check\": \"$timestamp\"/" "$meta_path"
        rm -f "${meta_path}.bak"
    fi
}

# Get registry meta path (override-aware version)
get_registry_meta_path() {
    local registry_dir
    registry_dir=$(get_registry_dir)
    echo "$registry_dir/.constructs-meta.json"
}

# Initialize registry meta file if it doesn't exist
init_registry_meta_file() {
    local meta_path
    meta_path=$(get_registry_meta_path)

    if [[ ! -f "$meta_path" ]]; then
        mkdir -p "$(dirname "$meta_path")"
        cat > "$meta_path" << 'EOF'
{
    "schema_version": 1,
    "installed_skills": {},
    "installed_packs": {},
    "last_update_check": null
}
EOF
    fi
}

# Query registry API for skill version info
# Args:
#   $1 - Skill slug (vendor/name)
# Returns: JSON response or empty on error
query_skill_versions() {
    local skill_slug="$1"
    local registry_url
    registry_url=$(get_registry_url)

    # Check if offline mode
    if [[ "${LOA_OFFLINE:-}" == "1" ]]; then
        return 1
    fi

    # Check if curl is available
    if ! command -v curl &>/dev/null; then
        return 1
    fi

    # Query the versions endpoint
    local url="${registry_url}/skills/${skill_slug}/versions"
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    curl -s --proto =https --tlsv1.2 --connect-timeout 5 --max-time 10 "$url" 2>/dev/null
}

# Check for updates for all installed skills
do_check_updates() {
    local registry_dir
    registry_dir=$(get_registry_dir)
    local meta_path
    meta_path=$(get_registry_meta_path)

    # Check offline mode
    if [[ "${LOA_OFFLINE:-}" == "1" ]]; then
        print_warning "Skipping update check: offline mode enabled"
        return 0
    fi

    # Initialize meta if needed
    init_registry_meta_file

    # Discover installed skills
    local skills
    skills=$(discover_skills)

    if [[ -z "$skills" ]]; then
        echo "No registry skills installed"
        update_last_check_timestamp
        return 0
    fi

    echo "Checking for updates..."
    echo "─────────────────────────────────────────────────"

    local updates_available=0
    local skills_checked=0
    local errors=0

    while IFS= read -r skill_slug; do
        [[ -z "$skill_slug" ]] && continue

        local skill_dir
        skill_dir=$(get_skill_path "$skill_slug")

        # Get current version
        local current_version
        current_version=$(get_skill_version "$skill_dir")

        # Query registry for latest version
        local response
        response=$(query_skill_versions "$skill_slug" 2>/dev/null)

        if [[ -z "$response" ]]; then
            # Network error or skill not found
            print_status "$icon_unknown" "$skill_slug ($current_version) [unable to check]"
            ((errors++))
            continue
        fi

        # Extract latest version from response
        local latest_version
        if command -v jq &>/dev/null; then
            latest_version=$(echo "$response" | jq -r '.latest_version // .version // ""' 2>/dev/null)
        else
            # Fallback: grep extraction
            latest_version=$(echo "$response" | grep -o '"latest_version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
            if [[ -z "$latest_version" ]]; then
                latest_version=$(echo "$response" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            fi
        fi

        if [[ -z "$latest_version" ]]; then
            print_status "$icon_unknown" "$skill_slug ($current_version) [parse error]"
            ((errors++))
            continue
        fi

        # Compare versions
        local comparison
        comparison=$(compare_versions "$current_version" "$latest_version")

        case "$comparison" in
            1)
                # Update available
                print_status "$icon_warning" "$skill_slug: $current_version → $latest_version (update available)"
                ((updates_available++))
                ;;
            0)
                # Up to date
                print_status "$icon_valid" "$skill_slug ($current_version) [up to date]"
                ;;
            -1)
                # Ahead of registry (dev version?)
                print_status "$icon_valid" "$skill_slug ($current_version) [ahead of registry: $latest_version]"
                ;;
        esac

        ((skills_checked++))
    done <<< "$skills"

    echo ""

    # Update last check timestamp
    update_last_check_timestamp

    # Summary
    if [[ "$updates_available" -gt 0 ]]; then
        echo "${YELLOW}${updates_available} update(s) available${NC}"
        echo ""
        echo "To update skills, re-install from the registry."
    elif [[ "$errors" -gt 0 ]]; then
        echo "Checked $skills_checked skill(s), $errors could not be checked"
    else
        echo "${GREEN}All $skills_checked skill(s) are up to date${NC}"
    fi

    return 0
}

# =============================================================================
# Command Line Interface
# =============================================================================

show_usage() {
    cat << 'EOF'
Usage: constructs-loader.sh <command> [arguments]

Commands:
    list                    Show all skills with license status
    list-packs              Show all packs with status
    loadable                Return paths of loadable skills (valid or grace)
    validate <skill-dir>    Validate a single skill's license
    validate-pack <dir>     Validate a pack's license
    preload <skill-dir>     Pre-load hook for skill loading integration
    list-pack-skills <dir>  List skills in a pack
    get-pack-version <dir>  Get pack version from manifest
    check-updates           Check for available updates
    ensure-gitignore        Add .claude/constructs/ to .gitignore if missing

Exit Codes (validate/preload):
    0 = valid
    1 = expired (in grace period)
    2 = expired (beyond grace)
    3 = missing license file
    4 = invalid signature
    5 = other error

Environment Variables:
    LOA_CONSTRUCTS_DIR   Override registry directory (.claude/constructs)
    LOA_CACHE_DIR      Override cache directory (~/.loa/cache)
    LOA_OFFLINE        Set to 1 for offline-only mode
    NO_COLOR           Disable colored output

Note: Installing skills/packs automatically adds .claude/constructs/ to .gitignore

Examples:
    constructs-loader.sh list
    constructs-loader.sh list-packs
    constructs-loader.sh loadable | xargs -I {} echo "Loading: {}"
    constructs-loader.sh validate .claude/constructs/skills/vendor/skill
    constructs-loader.sh validate-pack .claude/constructs/packs/my-pack
    constructs-loader.sh preload .claude/constructs/skills/vendor/skill
    constructs-loader.sh ensure-gitignore
EOF
}

main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        show_usage
        exit $EXIT_ERROR
    fi

    case "$command" in
        list)
            do_list
            ;;
        list-packs)
            do_list_packs
            ;;
        loadable)
            do_loadable
            ;;
        validate)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing skill directory argument" >&2; exit $EXIT_ERROR; }
            do_validate "$2"
            ;;
        validate-pack)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing pack directory argument" >&2; exit $EXIT_ERROR; }
            do_validate_pack "$2"
            ;;
        preload)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing skill directory argument" >&2; exit $EXIT_ERROR; }
            do_preload "$2"
            ;;
        list-pack-skills)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing pack directory argument" >&2; exit $EXIT_ERROR; }
            list_pack_skills "$2"
            ;;
        get-pack-version)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing pack directory argument" >&2; exit $EXIT_ERROR; }
            get_pack_version "$2"
            ;;
        check-updates)
            do_check_updates
            ;;
        ensure-gitignore)
            ensure_constructs_gitignored
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown command: $command" >&2
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
