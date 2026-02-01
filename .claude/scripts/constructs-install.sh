#!/usr/bin/env bash
# =============================================================================
# Loa Constructs - Installation Script
# =============================================================================
# Install packs and skills from the Loa Constructs Registry.
#
# Usage:
#   constructs-install.sh pack <slug>              # Install a pack
#   constructs-install.sh skill <vendor/slug>      # Install a skill
#   constructs-install.sh uninstall pack <slug>    # Remove a pack
#   constructs-install.sh uninstall skill <slug>   # Remove a skill
#   constructs-install.sh link-commands <slug>     # Re-link pack commands
#
# Exit Codes:
#   0 = success
#   1 = authentication error
#   2 = network error
#   3 = not found
#   4 = extraction error
#   5 = validation error
#   6 = general error
#
# Environment Variables:
#   LOA_CONSTRUCTS_API_KEY  - API key for authentication
#   LOA_REGISTRY_URL        - Override API URL
#   LOA_OFFLINE             - Set to 1 for offline mode (skip download)
#
# Sources: GitHub Issue #20, GitHub Issue #21
# =============================================================================

set -euo pipefail

# Get script directory for sourcing dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [[ -f "$SCRIPT_DIR/constructs-lib.sh" ]]; then
    source "$SCRIPT_DIR/constructs-lib.sh"
else
    echo "ERROR: constructs-lib.sh not found" >&2
    exit 6
fi

# =============================================================================
# Exit Codes
# =============================================================================

EXIT_SUCCESS=0
EXIT_AUTH_ERROR=1
EXIT_NETWORK_ERROR=2
EXIT_NOT_FOUND=3
EXIT_EXTRACT_ERROR=4
EXIT_VALIDATION_ERROR=5
EXIT_ERROR=6

# =============================================================================
# Authentication
# =============================================================================

# NOTE: check_file_permissions() and get_api_key() moved to constructs-lib.sh (Issue #104)

# =============================================================================
# Directory Management
# =============================================================================

# Get constructs directory
get_constructs_dir() {
    echo "${LOA_CONSTRUCTS_DIR:-.claude/constructs}"
}

# Get packs directory
get_packs_dir() {
    echo "$(get_constructs_dir)/packs"
}

# Get skills directory
get_skills_dir() {
    echo "$(get_constructs_dir)/skills"
}

# Get commands directory
get_commands_dir() {
    echo ".claude/commands"
}

# =============================================================================
# Symlink Validation (Security: HIGH-003 - Fixed)
# =============================================================================

# Validate that a symlink target resolves within expected directory
# Args:
#   $1 - Target path (the path the symlink will point to)
#   $2 - Expected base directory component (e.g., "constructs/packs")
#   $3 - Link location directory (where the symlink will be created)
# Returns: 0 if valid, 1 if outside expected directory
validate_symlink_target() {
    local target="$1"
    local expected_base="$2"
    local link_dir="${3:-.claude/commands}"

    # SECURITY: Check for path traversal components explicitly
    # This catches encoded paths and various bypass attempts
    if [[ "$target" == *".."* ]]; then
        # Count the depth of traversal vs path components
        local traversal_count
        local path_depth
        traversal_count=$(echo "$target" | grep -o '\.\.' | wc -l)
        path_depth=$(echo "$target" | tr '/' '\n' | grep -v '^\.\.$' | grep -v '^$' | wc -l)

        # If traversing more than expected depth, block it
        # constructs symlinks should only go up 1-2 levels max
        if [[ $traversal_count -gt 2 ]]; then
            print_warning "Symlink target has excessive traversal: $target"
            return 1
        fi
    fi

    # SECURITY: Verify target contains expected base path component
    if [[ "$target" != *"$expected_base"* ]]; then
        print_warning "Symlink target outside expected directory: $target (expected: $expected_base)"
        return 1
    fi

    # SECURITY: If the target already exists, verify it resolves correctly
    # This is the definitive check using readlink -f
    if [[ -d "$link_dir" ]]; then
        local project_root
        project_root=$(cd "$link_dir" && pwd)
        local resolved_target

        # Create a temporary test to verify resolution
        # Use cd to the link directory and resolve from there
        resolved_target=$(cd "$link_dir" && readlink -f "$target" 2>/dev/null || echo "")

        if [[ -n "$resolved_target" ]]; then
            # Get the constructs directory absolute path
            local constructs_abs
            constructs_abs=$(readlink -f "$(get_constructs_dir)" 2>/dev/null || echo "")

            # Verify resolved path is within constructs
            if [[ -n "$constructs_abs" ]] && [[ "$resolved_target" != "$constructs_abs"* ]]; then
                print_warning "Symlink resolves outside constructs: $resolved_target"
                return 1
            fi
        fi
    fi

    return 0
}

# =============================================================================
# Command Symlinking (Fixes GitHub Issue #21)
# =============================================================================

# Symlink pack commands to .claude/commands/
# Args:
#   $1 - Pack slug
# Returns: Number of commands linked
symlink_pack_commands() {
    local pack_slug="$1"
    local pack_dir="$(get_packs_dir)/$pack_slug"
    local commands_source="$pack_dir/commands"
    local commands_target="$(get_commands_dir)"
    local linked=0

    # Check if pack has commands
    if [[ ! -d "$commands_source" ]]; then
        echo "0"
        return 0
    fi

    # Ensure commands target directory exists
    mkdir -p "$commands_target"

    # Symlink each command
    for cmd in "$commands_source"/*.md; do
        [[ -f "$cmd" ]] || continue

        local filename
        filename=$(basename "$cmd")

        # Calculate relative path from .claude/commands/ to pack commands
        local relative_path="../constructs/packs/$pack_slug/commands/$filename"
        local target_link="$commands_target/$filename"

        # Check for existing file/symlink
        if [[ -e "$target_link" ]] || [[ -L "$target_link" ]]; then
            if [[ -L "$target_link" ]]; then
                # It's a symlink - check if it points to a constructs pack
                local existing_target
                existing_target=$(readlink "$target_link" 2>/dev/null || echo "")
                if [[ "$existing_target" == *"constructs/packs"* ]]; then
                    # Remove old pack symlink
                    rm -f "$target_link"
                else
                    print_warning "  Skipping $filename: symlink exists to custom location"
                    continue
                fi
            else
                # It's a regular file - don't overwrite
                print_warning "  Skipping $filename: user file exists (not overwriting)"
                continue
            fi
        fi

        # Validate symlink target (M-003)
        if ! validate_symlink_target "$relative_path" "constructs/packs"; then
            print_warning "  Skipping $filename: symlink validation failed"
            continue
        fi

        # Create symlink
        ln -sf "$relative_path" "$target_link"
        ((linked++))
    done

    echo "$linked"
}

# Remove pack command symlinks
# Args:
#   $1 - Pack slug
# Returns: Number of commands unlinked
unlink_pack_commands() {
    local pack_slug="$1"
    local pack_dir="$(get_packs_dir)/$pack_slug"
    local commands_source="$pack_dir/commands"
    local commands_target="$(get_commands_dir)"
    local unlinked=0

    # Check if pack has commands
    if [[ ! -d "$commands_source" ]]; then
        echo "0"
        return 0
    fi

    # Remove symlinks for each command
    for cmd in "$commands_source"/*.md; do
        [[ -f "$cmd" ]] || continue

        local filename
        filename=$(basename "$cmd")
        local target_link="$commands_target/$filename"

        # Check if it's our symlink
        if [[ -L "$target_link" ]]; then
            local existing_target
            existing_target=$(readlink "$target_link" 2>/dev/null || echo "")
            if [[ "$existing_target" == *"constructs/packs/$pack_slug"* ]]; then
                rm -f "$target_link"
                ((unlinked++))
            fi
        fi
    done

    echo "$unlinked"
}

# =============================================================================
# Skill Symlinking (for loader compatibility)
# =============================================================================

# Symlink pack skills to constructs/skills for loader discovery
# Args:
#   $1 - Pack slug
# Returns: Number of skills linked
symlink_pack_skills() {
    local pack_slug="$1"
    local pack_dir="$(get_packs_dir)/$pack_slug"
    local skills_source="$pack_dir/skills"
    local skills_target="$(get_skills_dir)/$pack_slug"
    local linked=0

    # Check if pack has skills
    if [[ ! -d "$skills_source" ]]; then
        echo "0"
        return 0
    fi

    # Create target directory
    mkdir -p "$skills_target"

    # Symlink each skill directory
    for skill in "$skills_source"/*/; do
        [[ -d "$skill" ]] || continue

        local skill_name
        skill_name=$(basename "$skill")
        local relative_path="../../packs/$pack_slug/skills/$skill_name"
        local target_link="$skills_target/$skill_name"

        # Remove existing symlink if present
        if [[ -L "$target_link" ]]; then
            rm -f "$target_link"
        elif [[ -d "$target_link" ]]; then
            print_warning "  Skipping skill $skill_name: directory exists"
            continue
        fi

        # Validate symlink target (M-003)
        if ! validate_symlink_target "$relative_path" "packs/$pack_slug/skills"; then
            print_warning "  Skipping skill $skill_name: symlink validation failed"
            continue
        fi

        # Create symlink
        ln -sf "$relative_path" "$target_link"
        ((linked++))
    done

    echo "$linked"
}

# Remove pack skill symlinks
# Args:
#   $1 - Pack slug
unlink_pack_skills() {
    local pack_slug="$1"
    local skills_target="$(get_skills_dir)/$pack_slug"

    # Remove the pack's skill symlinks directory
    if [[ -d "$skills_target" ]]; then
        rm -rf "$skills_target"
    fi
}

# =============================================================================
# Pack Installation
# =============================================================================

# Download and install a pack from the registry
# Args:
#   $1 - Pack slug
do_install_pack() {
    local pack_slug="$1"
    local api_key
    local registry_url
    local packs_dir

    print_status "$icon_valid" "Installing pack: $pack_slug"

    # Check offline mode
    if [[ "${LOA_OFFLINE:-}" == "1" ]]; then
        print_error "ERROR: Cannot install packs in offline mode"
        return $EXIT_NETWORK_ERROR
    fi

    # Get authentication
    api_key=$(get_api_key)
    if [[ -z "$api_key" ]]; then
        print_error "ERROR: No API key found"
        echo ""
        echo "To authenticate, either:"
        echo "  1. Set LOA_CONSTRUCTS_API_KEY environment variable"
        echo "  2. Run /skill-login to save credentials"
        echo "  3. Create ~/.loa/credentials.json with {\"api_key\": \"your-key\"}"
        return $EXIT_AUTH_ERROR
    fi

    # Get registry URL
    registry_url=$(get_registry_url)

    # Create directories
    packs_dir=$(get_packs_dir)
    mkdir -p "$packs_dir"

    # Ensure constructs directory is gitignored
    ensure_constructs_gitignored

    echo "  Downloading from $registry_url/packs/$pack_slug/download..."

    # Download pack
    # SECURITY (MEDIUM-001): Use environment variable for auth header
    # Avoids process substitution file descriptor exposure via lsof
    local response
    local http_code
    local tmp_file
    tmp_file=$(mktemp) || { print_error "mktemp failed"; return 1; }
    chmod 600 "$tmp_file"  # CRITICAL-001 FIX

    # Disable command tracing during API call to prevent key leakage
    { set +x; } 2>/dev/null || true

    # Use environment variable instead of process substitution for security
    local auth_header="Authorization: Bearer $api_key"
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    http_code=$(curl -s -w "%{http_code}" --proto =https --tlsv1.2 --max-time 300 \
        -H "$auth_header" \
        -H "Accept: application/json" \
        "$registry_url/packs/$pack_slug/download" \
        -o "$tmp_file" 2>/dev/null) || {
        unset auth_header
        rm -f "$tmp_file"
        print_error "ERROR: Network error while downloading pack"
        echo "  Check your network connection and try again"
        return $EXIT_NETWORK_ERROR
    }
    unset auth_header

    # Check HTTP status
    case "$http_code" in
        200)
            # Success
            ;;
        401|403)
            rm -f "$tmp_file"
            print_error "ERROR: Authentication failed (HTTP $http_code)"
            echo "  Your API key may be invalid or expired"
            echo "  Run /skill-login to re-authenticate"
            return $EXIT_AUTH_ERROR
            ;;
        404)
            rm -f "$tmp_file"
            print_error "ERROR: Pack '$pack_slug' not found"
            echo "  Check the pack name and try again"
            return $EXIT_NOT_FOUND
            ;;
        *)
            rm -f "$tmp_file"
            print_error "ERROR: API returned HTTP $http_code"
            return $EXIT_NETWORK_ERROR
            ;;
    esac

    # Parse response and extract files
    local pack_dir="$packs_dir/$pack_slug"

    echo "  Extracting files..."

    # Create pack directory
    mkdir -p "$pack_dir"

    # Extract using Python (jq doesn't handle base64 well)
    # SECURITY: Pass variables via environment to prevent code injection (CRIT-001)
    export LOA_TMP_FILE="$tmp_file"
    export LOA_PACK_DIR="$pack_dir"
    if ! python3 << 'PYEOF'
import json
import base64
import os
import sys

def safe_path_join(base_dir, path):
    """
    Safely join paths, preventing path traversal attacks (CRIT-002).
    Returns the full path if safe, raises ValueError otherwise.
    """
    # Normalize the base directory
    real_base = os.path.realpath(base_dir)

    # Join and normalize the full path
    full_path = os.path.normpath(os.path.join(base_dir, path))
    real_path = os.path.realpath(os.path.join(base_dir, os.path.dirname(path)))

    # For new files, check that the parent directory is within base
    # (realpath on non-existent file returns the path itself)
    parent_dir = os.path.dirname(full_path)
    if parent_dir:
        os.makedirs(parent_dir, exist_ok=True)
        real_parent = os.path.realpath(parent_dir)
        if not real_parent.startswith(real_base + os.sep) and real_parent != real_base:
            raise ValueError(f"Path traversal attempt blocked: {path}")

    # Also check for suspicious path components
    path_parts = path.replace('\\', '/').split('/')
    if '..' in path_parts:
        raise ValueError(f"Path contains traversal component: {path}")

    return full_path

try:
    # Get paths from environment (prevents shell injection)
    tmp_file = os.environ.get('LOA_TMP_FILE')
    pack_dir = os.environ.get('LOA_PACK_DIR')

    if not tmp_file or not pack_dir:
        print("ERROR: Required environment variables not set", file=sys.stderr)
        sys.exit(1)

    with open(tmp_file, 'r') as f:
        data = json.load(f)

    # Handle nested response structure
    if 'data' in data:
        data = data['data']

    # Get pack info
    pack_info = data.get('pack', data)

    # Write manifest (safe - fixed filename)
    manifest = pack_info.get('manifest', {})
    if manifest:
        with open(os.path.join(pack_dir, 'manifest.json'), 'w') as f:
            json.dump(manifest, f, indent=2)

    # Write license (safe - fixed filename)
    license_data = data.get('license', {})
    if license_data:
        with open(os.path.join(pack_dir, '.license.json'), 'w') as f:
            json.dump(license_data, f, indent=2)

    # Extract files with path traversal protection
    files = pack_info.get('files', [])
    extracted = 0
    blocked = 0
    for file_info in files:
        path = file_info.get('path', '')
        content = file_info.get('content', '')

        if not path or not content:
            continue

        # Validate and create full path (CRIT-002: path traversal protection)
        try:
            full_path = safe_path_join(pack_dir, path)
        except ValueError as e:
            print(f"  BLOCKED: {e}", file=sys.stderr)
            blocked += 1
            continue

        # Decode and write
        try:
            decoded = base64.b64decode(content)
            with open(full_path, 'wb') as f:
                f.write(decoded)
            extracted += 1
        except Exception as e:
            print(f"  Warning: Failed to extract {path}: {e}", file=sys.stderr)

    print(f"  Extracted {extracted} files")
    if blocked > 0:
        print(f"  SECURITY: Blocked {blocked} suspicious paths", file=sys.stderr)

except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON response: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Extraction failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        rm -f "$tmp_file"
        rm -rf "$pack_dir"
        print_error "ERROR: Failed to extract pack files"
        return $EXIT_EXTRACT_ERROR
    fi

    rm -f "$tmp_file"

    # Symlink commands
    echo "  Linking commands..."
    local commands_linked
    commands_linked=$(symlink_pack_commands "$pack_slug")
    echo "  Created $commands_linked command symlinks"

    # Symlink skills for loader discovery
    echo "  Linking skills..."
    local skills_linked
    skills_linked=$(symlink_pack_skills "$pack_slug")
    echo "  Created $skills_linked skill symlinks"

    # Validate pack license
    echo "  Validating license..."
    local validator="$SCRIPT_DIR/constructs-loader.sh"
    if [[ -x "$validator" ]]; then
        local validation_result=0
        "$validator" validate-pack "$pack_dir" >/dev/null 2>&1 || validation_result=$?

        case $validation_result in
            0)
                print_success "  License valid"
                ;;
            1)
                print_warning "  License in grace period - please renew soon"
                ;;
            2)
                print_error "  License expired - pack may not work correctly"
                ;;
            3)
                print_warning "  No license file found - pack may be free tier"
                ;;
            *)
                print_warning "  License validation returned code $validation_result"
                ;;
        esac
    fi

    # Update registry meta
    update_pack_meta "$pack_slug" "$pack_dir"

    echo ""
    print_success "Pack '$pack_slug' installed successfully!"

    # List available commands
    local commands_dir="$pack_dir/commands"
    if [[ -d "$commands_dir" ]]; then
        echo ""
        echo "Available commands:"
        for cmd in "$commands_dir"/*.md; do
            [[ -f "$cmd" ]] || continue
            local cmd_name
            cmd_name=$(basename "$cmd" .md)
            echo "  /$cmd_name"
        done
    fi

    return $EXIT_SUCCESS
}

# Update pack metadata in .constructs-meta.json
# Args:
#   $1 - Pack slug
#   $2 - Pack directory
update_pack_meta() {
    local pack_slug="$1"
    local pack_dir="$2"
    local meta_path
    meta_path=$(get_registry_meta_path)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Get pack version from manifest
    local version="unknown"
    local manifest_file="$pack_dir/manifest.json"
    if [[ -f "$manifest_file" ]]; then
        version=$(jq -r '.version // "unknown"' "$manifest_file" 2>/dev/null || echo "unknown")
    fi

    # Get license expiry
    local license_expires=""
    local license_file="$pack_dir/.license.json"
    if [[ -f "$license_file" ]]; then
        license_expires=$(jq -r '.expires_at // ""' "$license_file" 2>/dev/null || echo "")
    fi

    # Get skills list
    local skills_json="[]"
    if [[ -d "$pack_dir/skills" ]]; then
        skills_json=$(find "$pack_dir/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | jq -R -s 'split("\n") | map(select(length > 0))')
    fi

    # Ensure meta file exists
    init_registry_meta

    # Update meta
    local tmp_file="${meta_path}.tmp"
    jq --arg slug "$pack_slug" \
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
       }' "$meta_path" > "$tmp_file" && mv "$tmp_file" "$meta_path"
}

# =============================================================================
# Skill Installation
# =============================================================================

# Download and install a skill from the registry
# Args:
#   $1 - Skill slug (vendor/name)
do_install_skill() {
    local skill_slug="$1"
    local api_key
    local registry_url
    local skills_dir

    print_status "$icon_valid" "Installing skill: $skill_slug"

    # Check offline mode
    if [[ "${LOA_OFFLINE:-}" == "1" ]]; then
        print_error "ERROR: Cannot install skills in offline mode"
        return $EXIT_NETWORK_ERROR
    fi

    # Get authentication
    api_key=$(get_api_key)
    if [[ -z "$api_key" ]]; then
        print_error "ERROR: No API key found"
        echo ""
        echo "To authenticate, either:"
        echo "  1. Set LOA_CONSTRUCTS_API_KEY environment variable"
        echo "  2. Run /skill-login to save credentials"
        return $EXIT_AUTH_ERROR
    fi

    # Get registry URL
    registry_url=$(get_registry_url)

    # Create directories
    skills_dir=$(get_skills_dir)
    mkdir -p "$skills_dir"

    # Ensure constructs directory is gitignored
    ensure_constructs_gitignored

    echo "  Downloading from $registry_url/skills/$skill_slug/download..."

    # Download skill
    local http_code
    local tmp_file
    tmp_file=$(mktemp) || { print_error "mktemp failed"; return 1; }
    chmod 600 "$tmp_file"  # CRITICAL-001 FIX

    # Disable command tracing during API call to prevent key leakage
    { set +x; } 2>/dev/null || true

    # Use local variable instead of process substitution for security (MED-002)
    # Process substitution creates a temporary file descriptor readable by other processes
    local auth_header="Authorization: Bearer $api_key"
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    http_code=$(curl -s -w "%{http_code}" --proto =https --tlsv1.2 --max-time 300 \
        -H "$auth_header" \
        -H "Accept: application/json" \
        "$registry_url/skills/$skill_slug/download" \
        -o "$tmp_file" 2>/dev/null) || {
        unset auth_header
        rm -f "$tmp_file"
        print_error "ERROR: Network error while downloading skill"
        return $EXIT_NETWORK_ERROR
    }
    unset auth_header

    # Check HTTP status
    case "$http_code" in
        200)
            # Success
            ;;
        401|403)
            rm -f "$tmp_file"
            print_error "ERROR: Authentication failed (HTTP $http_code)"
            return $EXIT_AUTH_ERROR
            ;;
        404)
            rm -f "$tmp_file"
            print_error "ERROR: Skill '$skill_slug' not found"
            return $EXIT_NOT_FOUND
            ;;
        *)
            rm -f "$tmp_file"
            print_error "ERROR: API returned HTTP $http_code"
            return $EXIT_NETWORK_ERROR
            ;;
    esac

    # Determine directory structure
    # skill_slug might be "vendor/name" or just "name"
    local skill_dir
    if [[ "$skill_slug" == *"/"* ]]; then
        skill_dir="$skills_dir/$skill_slug"
    else
        skill_dir="$skills_dir/default/$skill_slug"
    fi

    echo "  Extracting files..."

    # Create skill directory
    mkdir -p "$skill_dir"

    # Extract using Python
    # SECURITY: Pass variables via environment to prevent code injection (CRIT-001)
    export LOA_TMP_FILE="$tmp_file"
    export LOA_SKILL_DIR="$skill_dir"
    if ! python3 << 'PYEOF'
import json
import base64
import os
import sys

def safe_path_join(base_dir, path):
    """
    Safely join paths, preventing path traversal attacks (CRIT-002).
    Returns the full path if safe, raises ValueError otherwise.
    """
    # Normalize the base directory
    real_base = os.path.realpath(base_dir)

    # Join and normalize the full path
    full_path = os.path.normpath(os.path.join(base_dir, path))

    # For new files, check that the parent directory is within base
    parent_dir = os.path.dirname(full_path)
    if parent_dir:
        os.makedirs(parent_dir, exist_ok=True)
        real_parent = os.path.realpath(parent_dir)
        if not real_parent.startswith(real_base + os.sep) and real_parent != real_base:
            raise ValueError(f"Path traversal attempt blocked: {path}")

    # Also check for suspicious path components
    path_parts = path.replace('\\', '/').split('/')
    if '..' in path_parts:
        raise ValueError(f"Path contains traversal component: {path}")

    return full_path

try:
    # Get paths from environment (prevents shell injection)
    tmp_file = os.environ.get('LOA_TMP_FILE')
    skill_dir = os.environ.get('LOA_SKILL_DIR')

    if not tmp_file or not skill_dir:
        print("ERROR: Required environment variables not set", file=sys.stderr)
        sys.exit(1)

    with open(tmp_file, 'r') as f:
        data = json.load(f)

    # Handle nested response structure
    if 'data' in data:
        data = data['data']

    # Get skill info
    skill_info = data.get('skill', data)

    # Write license (safe - fixed filename)
    license_data = data.get('license', {})
    if license_data:
        with open(os.path.join(skill_dir, '.license.json'), 'w') as f:
            json.dump(license_data, f, indent=2)

    # Extract files with path traversal protection
    files = skill_info.get('files', [])
    extracted = 0
    blocked = 0
    for file_info in files:
        path = file_info.get('path', '')
        content = file_info.get('content', '')

        if not path or not content:
            continue

        # Validate and create full path (CRIT-002: path traversal protection)
        try:
            full_path = safe_path_join(skill_dir, path)
        except ValueError as e:
            print(f"  BLOCKED: {e}", file=sys.stderr)
            blocked += 1
            continue

        # Decode and write
        try:
            decoded = base64.b64decode(content)
            with open(full_path, 'wb') as f:
                f.write(decoded)
            extracted += 1
        except Exception as e:
            print(f"  Warning: Failed to extract {path}: {e}", file=sys.stderr)

    print(f"  Extracted {extracted} files")
    if blocked > 0:
        print(f"  SECURITY: Blocked {blocked} suspicious paths", file=sys.stderr)

except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON response: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Extraction failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        rm -f "$tmp_file"
        rm -rf "$skill_dir"
        print_error "ERROR: Failed to extract skill files"
        return $EXIT_EXTRACT_ERROR
    fi

    rm -f "$tmp_file"

    # Validate skill license
    echo "  Validating license..."
    local validator="$SCRIPT_DIR/constructs-loader.sh"
    if [[ -x "$validator" ]]; then
        local validation_result=0
        "$validator" validate "$skill_dir" >/dev/null 2>&1 || validation_result=$?

        case $validation_result in
            0)
                print_success "  License valid"
                ;;
            1)
                print_warning "  License in grace period"
                ;;
            2)
                print_error "  License expired"
                ;;
            *)
                print_warning "  License validation returned code $validation_result"
                ;;
        esac
    fi

    # Update registry meta
    update_skill_meta "$skill_slug" "$skill_dir"

    echo ""
    print_success "Skill '$skill_slug' installed successfully!"

    return $EXIT_SUCCESS
}

# Update skill metadata in .constructs-meta.json
# Args:
#   $1 - Skill slug
#   $2 - Skill directory
update_skill_meta() {
    local skill_slug="$1"
    local skill_dir="$2"
    local meta_path
    meta_path=$(get_registry_meta_path)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Get skill version from index.yaml
    local version="unknown"
    local index_file="$skill_dir/index.yaml"
    if [[ -f "$index_file" ]] && command -v yq &>/dev/null; then
        local yq_version_output
        yq_version_output=$(yq --version 2>&1 || echo "")
        if echo "$yq_version_output" | grep -q "mikefarah\|version.*4"; then
            version=$(yq eval '.version // "unknown"' "$index_file" 2>/dev/null || echo "unknown")
        else
            version=$(yq '.version // "unknown"' "$index_file" 2>/dev/null || echo "unknown")
        fi
    fi

    # Get license expiry
    local license_expires=""
    local license_file="$skill_dir/.license.json"
    if [[ -f "$license_file" ]]; then
        license_expires=$(jq -r '.expires_at // ""' "$license_file" 2>/dev/null || echo "")
    fi

    # Ensure meta file exists
    init_registry_meta

    # Update meta
    local tmp_file="${meta_path}.tmp"
    jq --arg slug "$skill_slug" \
       --arg version "$version" \
       --arg installed_at "$now" \
       --arg license_expires "$license_expires" \
       '.installed_skills[$slug] = {
           "version": $version,
           "installed_at": $installed_at,
           "registry": "default",
           "license_expires": $license_expires,
           "from_pack": null
       }' "$meta_path" > "$tmp_file" && mv "$tmp_file" "$meta_path"
}

# =============================================================================
# Uninstall Commands
# =============================================================================

# Uninstall a pack
# Args:
#   $1 - Pack slug
do_uninstall_pack() {
    local pack_slug="$1"
    local pack_dir="$(get_packs_dir)/$pack_slug"

    print_status "$icon_warning" "Uninstalling pack: $pack_slug"

    # Check if pack exists
    if [[ ! -d "$pack_dir" ]]; then
        print_error "ERROR: Pack '$pack_slug' is not installed"
        return $EXIT_NOT_FOUND
    fi

    # Remove command symlinks first
    echo "  Removing command symlinks..."
    local commands_unlinked
    commands_unlinked=$(unlink_pack_commands "$pack_slug")
    echo "  Removed $commands_unlinked command symlinks"

    # Remove skill symlinks
    echo "  Removing skill symlinks..."
    unlink_pack_skills "$pack_slug"

    # Remove pack directory
    echo "  Removing pack files..."
    rm -rf "$pack_dir"

    # Update registry meta
    local meta_path
    meta_path=$(get_registry_meta_path)
    if [[ -f "$meta_path" ]]; then
        local tmp_file="${meta_path}.tmp"
        jq --arg slug "$pack_slug" 'del(.installed_packs[$slug])' "$meta_path" > "$tmp_file" && mv "$tmp_file" "$meta_path"
    fi

    echo ""
    print_success "Pack '$pack_slug' uninstalled successfully!"

    return $EXIT_SUCCESS
}

# Uninstall a skill
# Args:
#   $1 - Skill slug
do_uninstall_skill() {
    local skill_slug="$1"
    local skills_dir
    skills_dir=$(get_skills_dir)

    print_status "$icon_warning" "Uninstalling skill: $skill_slug"

    # Find skill directory
    local skill_dir
    if [[ -d "$skills_dir/$skill_slug" ]]; then
        skill_dir="$skills_dir/$skill_slug"
    elif [[ -d "$skills_dir/default/$skill_slug" ]]; then
        skill_dir="$skills_dir/default/$skill_slug"
    else
        print_error "ERROR: Skill '$skill_slug' is not installed"
        return $EXIT_NOT_FOUND
    fi

    # Check if it's a symlink (pack skill)
    if [[ -L "$skill_dir" ]]; then
        print_error "ERROR: Skill '$skill_slug' is part of a pack"
        echo "  Uninstall the pack instead, or remove the symlink manually"
        return $EXIT_ERROR
    fi

    # Remove skill directory
    echo "  Removing skill files..."
    rm -rf "$skill_dir"

    # Update registry meta
    local meta_path
    meta_path=$(get_registry_meta_path)
    if [[ -f "$meta_path" ]]; then
        local tmp_file="${meta_path}.tmp"
        jq --arg slug "$skill_slug" 'del(.installed_skills[$slug])' "$meta_path" > "$tmp_file" && mv "$tmp_file" "$meta_path"
    fi

    echo ""
    print_success "Skill '$skill_slug' uninstalled successfully!"

    return $EXIT_SUCCESS
}

# =============================================================================
# Re-link Commands (for manual fixing)
# =============================================================================

# Re-link pack commands (useful after updates or manual changes)
# Args:
#   $1 - Pack slug (or "all" for all packs)
do_link_commands() {
    local pack_slug="$1"
    local packs_dir
    packs_dir=$(get_packs_dir)

    if [[ "$pack_slug" == "all" ]]; then
        # Link all packs
        local total_linked=0
        for pack_path in "$packs_dir"/*/; do
            [[ -d "$pack_path" ]] || continue
            local slug
            slug=$(basename "$pack_path")

            echo "Linking commands for pack: $slug"
            local linked
            linked=$(symlink_pack_commands "$slug")
            echo "  Created $linked command symlinks"
            total_linked=$((total_linked + linked))
        done
        echo ""
        print_success "Total: $total_linked command symlinks created"
    else
        # Link specific pack
        local pack_dir="$packs_dir/$pack_slug"
        if [[ ! -d "$pack_dir" ]]; then
            print_error "ERROR: Pack '$pack_slug' is not installed"
            return $EXIT_NOT_FOUND
        fi

        echo "Linking commands for pack: $pack_slug"
        local linked
        linked=$(symlink_pack_commands "$pack_slug")
        print_success "Created $linked command symlinks"
    fi

    return $EXIT_SUCCESS
}

# =============================================================================
# Command Line Interface
# =============================================================================

show_usage() {
    cat << 'EOF'
Usage: constructs-install.sh <command> [arguments]

Commands:
    pack <slug>              Install a pack from the registry
    skill <vendor/slug>      Install a skill from the registry
    uninstall pack <slug>    Uninstall a pack
    uninstall skill <slug>   Uninstall a skill
    link-commands <slug>     Re-link pack commands (use "all" for all packs)

Exit Codes:
    0 = success
    1 = authentication error
    2 = network error
    3 = not found
    4 = extraction error
    5 = validation error
    6 = general error

Environment Variables:
    LOA_CONSTRUCTS_API_KEY  API key for authentication
    LOA_REGISTRY_URL        Override registry API URL
    LOA_OFFLINE             Set to 1 for offline mode

Examples:
    constructs-install.sh pack gtm-collective
    constructs-install.sh skill thj/terraform-assistant
    constructs-install.sh uninstall pack gtm-collective
    constructs-install.sh link-commands all

Authentication:
    Set LOA_CONSTRUCTS_API_KEY environment variable, or create:
    ~/.loa/credentials.json with {"api_key": "your-key"}

After Installation:
    Pack commands will be available as slash commands (e.g., /gtm-setup)
    Skills will be available in the skill loader (constructs-loader.sh list)
EOF
}

main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        show_usage
        exit $EXIT_ERROR
    fi

    case "$command" in
        pack)
            [[ -n "${2:-}" ]] || { print_error "ERROR: Missing pack slug"; show_usage; exit $EXIT_ERROR; }
            do_install_pack "$2"
            ;;
        skill)
            [[ -n "${2:-}" ]] || { print_error "ERROR: Missing skill slug"; show_usage; exit $EXIT_ERROR; }
            do_install_skill "$2"
            ;;
        uninstall)
            local type="${2:-}"
            local slug="${3:-}"
            [[ -n "$type" ]] || { print_error "ERROR: Missing uninstall type (pack/skill)"; exit $EXIT_ERROR; }
            [[ -n "$slug" ]] || { print_error "ERROR: Missing slug to uninstall"; exit $EXIT_ERROR; }
            case "$type" in
                pack)
                    do_uninstall_pack "$slug"
                    ;;
                skill)
                    do_uninstall_skill "$slug"
                    ;;
                *)
                    print_error "ERROR: Unknown uninstall type: $type (use 'pack' or 'skill')"
                    exit $EXIT_ERROR
                    ;;
            esac
            ;;
        link-commands)
            [[ -n "${2:-}" ]] || { print_error "ERROR: Missing pack slug (or 'all')"; exit $EXIT_ERROR; }
            do_link_commands "$2"
            ;;
        -h|--help|help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            print_error "ERROR: Unknown command: $command"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
