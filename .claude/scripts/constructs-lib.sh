#!/usr/bin/env bash
# =============================================================================
# Loa Constructs - Shared Library Functions
# =============================================================================
# Provides shared utilities for registry skill loading and license validation.
#
# Usage:
#   source "$(dirname "$0")/constructs-lib.sh"
#
# Sources: sdd.md:§5.3 (Registry Library), prd.md:FR-CFG-01, FR-CFG-02
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Functions
# =============================================================================

# Get registry config value from .loa.config.yaml
# Usage: get_registry_config "enabled" "true"
# Args:
#   $1 - Config key under registry section (e.g., "enabled", "default_url")
#   $2 - Default value if key not found
# Returns: Config value or default
get_registry_config() {
    local key="$1"
    local default="${2:-}"
    local config_file=".loa.config.yaml"

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        echo "$default"
        return 0
    fi

    # Check if yq is available
    if ! command -v yq &>/dev/null; then
        echo "$default"
        return 0
    fi

    # Get value from config - detect yq variant
    local value
    local yq_version_output
    yq_version_output=$(yq --version 2>&1 || echo "")

    if echo "$yq_version_output" | grep -q "mikefarah\|version.*4"; then
        # mikefarah/yq v4 syntax
        value=$(yq eval ".registry.${key} // \"${default}\"" "$config_file" 2>/dev/null || echo "$default")
    elif echo "$yq_version_output" | grep -qE "^yq [0-9]"; then
        # Python yq (jq wrapper) - uses jq syntax, returns quoted strings
        value=$(yq ".registry.${key} // \"${default}\"" "$config_file" 2>/dev/null || echo "$default")
        # Remove surrounding quotes if present (python yq returns "value")
        value="${value#\"}"
        value="${value%\"}"
    else
        # Unknown variant - try jq syntax first
        value=$(yq ".registry.${key}" "$config_file" 2>/dev/null || echo "")
        value="${value#\"}"
        value="${value%\"}"
        if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
            value="$default"
        fi
    fi

    # Handle yq returning "null" string
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get registry URL (config or env override)
# LOA_REGISTRY_URL environment variable takes precedence
# Returns: Registry API URL
get_registry_url() {
    local config_url
    config_url=$(get_registry_config 'default_url' 'https://loa-constructs-api.fly.dev/v1')
    echo "${LOA_REGISTRY_URL:-$config_url}"
}

# =============================================================================
# THJ Membership Detection
# =============================================================================
# Replaces marker-file-based detection (.loa-setup-complete) with API key
# presence check. Zero network dependency - checks environment variable only.
#
# This is the canonical source for THJ membership detection across Loa.
# Other scripts should source this file and use is_thj_member().
# =============================================================================

# Check if user is a THJ member (has constructs API key)
# Returns: 0 if THJ member (API key present and non-empty), 1 otherwise
is_thj_member() {
    [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]
}

# =============================================================================
# Directory Functions
# =============================================================================

# Get registry skills directory
# Returns: Path to .claude/constructs/skills
get_registry_skills_dir() {
    echo ".claude/constructs/skills"
}

# Get registry packs directory
# Returns: Path to .claude/constructs/packs
get_registry_packs_dir() {
    echo ".claude/constructs/packs"
}

# Get user cache directory
# Returns: Path to ~/.loa/cache
get_cache_dir() {
    echo "${HOME}/.loa/cache"
}

# Get public keys cache directory
# Returns: Path to ~/.loa/cache/public-keys
get_public_keys_cache_dir() {
    echo "${HOME}/.loa/cache/public-keys"
}

# =============================================================================
# Date Handling (GNU/BSD compatible)
# =============================================================================

# Parse ISO 8601 date to Unix timestamp
# Works on both GNU (Linux) and BSD (macOS)
# Args:
#   $1 - ISO 8601 date string (e.g., "2025-01-15T12:00:00Z")
# Returns: Unix timestamp
parse_iso_date() {
    local iso_date="$1"

    # Remove trailing Z if present for consistent parsing
    local clean_date="${iso_date%Z}"

    # Try GNU date first (Linux)
    if date --version &>/dev/null 2>&1; then
        # GNU date
        date -d "$iso_date" +%s 2>/dev/null && return 0
        # Fallback: try without Z
        date -d "$clean_date" +%s 2>/dev/null && return 0
    fi

    # BSD date (macOS)
    # Try with Z suffix format
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null && return 0
    # Try without Z suffix
    date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_date" +%s 2>/dev/null && return 0

    # Last resort: use Python if available
    if command -v python3 &>/dev/null; then
        python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${clean_date}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null && return 0
    fi

    # Failed to parse
    echo "0"
    return 1
}

# Get current Unix timestamp
# Returns: Current Unix timestamp
now_timestamp() {
    date +%s
}

# Format duration in human-readable form
# Args:
#   $1 - Duration in seconds
# Returns: Human-readable string (e.g., "2 days", "5 hours")
humanize_duration() {
    local seconds="$1"
    local abs_seconds="${seconds#-}"  # Remove negative sign if present

    if [[ "$abs_seconds" -lt 60 ]]; then
        echo "${abs_seconds} seconds"
    elif [[ "$abs_seconds" -lt 3600 ]]; then
        echo "$(( abs_seconds / 60 )) minutes"
    elif [[ "$abs_seconds" -lt 86400 ]]; then
        echo "$(( abs_seconds / 3600 )) hours"
    else
        echo "$(( abs_seconds / 86400 )) days"
    fi
}

# =============================================================================
# License Helpers
# =============================================================================

# Read license file and extract field
# Args:
#   $1 - Path to license file
#   $2 - Field name to extract
# Returns: Field value or "null" if not found
get_license_field() {
    local license_file="$1"
    local field="$2"

    if [[ ! -f "$license_file" ]]; then
        echo "null"
        return 1
    fi

    jq -r ".${field} // \"null\"" "$license_file" 2>/dev/null || echo "null"
}

# Check if skill name is reserved (built-in framework skill)
# Args:
#   $1 - Skill name to check
# Returns: 0 if reserved, 1 if not reserved
is_reserved_skill_name() {
    local skill_name="$1"
    local config_file=".loa.config.yaml"

    # Empty string is not reserved (but also not valid)
    if [[ -z "$skill_name" ]]; then
        return 1
    fi

    # Check config file exists
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # Read reserved names directly using yq - detect variant
    local reserved_names
    local yq_version_output
    yq_version_output=$(yq --version 2>&1 || echo "")

    if echo "$yq_version_output" | grep -q "mikefarah\|version.*4"; then
        # mikefarah/yq v4
        reserved_names=$(yq eval '.registry.reserved_skill_names[]' "$config_file" 2>/dev/null || echo "")
    else
        # Python yq (jq wrapper) - uses jq syntax
        reserved_names=$(yq '.registry.reserved_skill_names[]' "$config_file" 2>/dev/null || echo "")
    fi

    # Check if skill name is in the list
    while IFS= read -r name; do
        # Remove surrounding quotes and trim whitespace
        name="${name#\"}"
        name="${name%\"}"
        name="${name#- }"
        name="${name#-}"
        name="${name## }"
        name="${name%% }"
        if [[ "$name" == "$skill_name" ]]; then
            return 0  # Is reserved
        fi
    done <<< "$reserved_names"

    return 1  # Not reserved
}

# Get grace period hours for a tier
# Args:
#   $1 - Tier name (free, pro, team, enterprise)
# Returns: Grace period in hours
get_grace_hours() {
    local tier="$1"

    case "$tier" in
        free|pro)
            echo "24"
            ;;
        team)
            echo "72"
            ;;
        enterprise)
            echo "168"
            ;;
        *)
            # Default to 24 hours for unknown tiers
            echo "24"
            ;;
    esac
}

# =============================================================================
# Output Formatting
# =============================================================================

# Colors (respect NO_COLOR environment variable)
# See: https://no-color.org/
if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'  # No Color
else
    RED=''
    YELLOW=''
    GREEN=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Status icons
icon_valid="${GREEN}✓${NC}"
icon_warning="${YELLOW}⚠${NC}"
icon_error="${RED}✗${NC}"
icon_unknown="${CYAN}?${NC}"

# Print colored message with icon
# Args:
#   $1 - Icon/prefix
#   $2 - Message
print_status() {
    local icon="$1"
    local message="$2"
    printf "  %b %s\n" "$icon" "$message"
}

# Print error message to stderr
# Args:
#   $1 - Error message
print_error() {
    printf "%b%s%b\n" "$RED" "$1" "$NC" >&2
}

# Print warning message to stderr
# Args:
#   $1 - Warning message
print_warning() {
    printf "%b%s%b\n" "$YELLOW" "$1" "$NC" >&2
}

# Print success message
# Args:
#   $1 - Success message
print_success() {
    printf "%b%s%b\n" "$GREEN" "$1" "$NC"
}

# =============================================================================
# Validation Helpers
# =============================================================================

# Check if a command exists
# Args:
#   $1 - Command name
# Returns: 0 if exists, 1 if not
command_exists() {
    command -v "$1" &>/dev/null
}

# Check required dependencies
# Returns: 0 if all present, 1 if any missing
check_dependencies() {
    local missing=()

    if ! command_exists jq; then
        missing+=("jq")
    fi

    if ! command_exists yq; then
        missing+=("yq")
    fi

    if ! command_exists curl; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# Registry Meta Management
# =============================================================================

# Get path to registry meta file
# Returns: Path to .claude/constructs/.constructs-meta.json
get_registry_meta_path() {
    echo ".claude/constructs/.constructs-meta.json"
}

# Initialize registry meta file if it doesn't exist
# Creates empty structure with schema version
init_registry_meta() {
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

# Read value from registry meta
# Args:
#   $1 - JSON path (e.g., ".installed_skills.\"thj/skill\".version")
# Returns: Value or "null"
get_registry_meta() {
    local json_path="$1"
    local meta_path
    meta_path=$(get_registry_meta_path)

    if [[ ! -f "$meta_path" ]]; then
        echo "null"
        return 1
    fi

    jq -r "$json_path // \"null\"" "$meta_path" 2>/dev/null || echo "null"
}

# Update registry meta file
# SECURITY (MED-007): Includes backup before jq modification
# Args:
#   $1 - JSON path to update
#   $2 - New value (as JSON)
update_registry_meta() {
    local json_path="$1"
    local value="$2"
    local meta_path
    meta_path=$(get_registry_meta_path)

    init_registry_meta

    # Create backup before modification
    local backup_file="${meta_path}.bak"
    cp "$meta_path" "$backup_file" 2>/dev/null || true

    local tmp_file="${meta_path}.tmp.$$"
    if jq "$json_path = $value" "$meta_path" > "$tmp_file"; then
        mv "$tmp_file" "$meta_path"
    else
        # Restore from backup on failure
        print_warning "jq modification failed, restoring backup"
        [[ -f "$backup_file" ]] && mv "$backup_file" "$meta_path"
        rm -f "$tmp_file"
        return 1
    fi
}

# =============================================================================
# Environment Variable Overrides (Sprint 5)
# =============================================================================

# Get offline grace hours (env override or config)
# LOA_OFFLINE_GRACE_HOURS takes precedence over config
# Returns: Grace period in hours
get_offline_grace_hours() {
    if [[ -n "${LOA_OFFLINE_GRACE_HOURS:-}" ]]; then
        echo "$LOA_OFFLINE_GRACE_HOURS"
    else
        get_registry_config "offline_grace_hours" "24"
    fi
}

# Check if registry is enabled (env override or config)
# LOA_REGISTRY_ENABLED takes precedence over config
# Returns: 0 if enabled, 1 if disabled
is_registry_enabled() {
    local enabled

    if [[ -n "${LOA_REGISTRY_ENABLED:-}" ]]; then
        enabled="$LOA_REGISTRY_ENABLED"
    else
        enabled=$(get_registry_config "enabled" "true")
    fi

    # Normalize boolean
    case "$enabled" in
        true|True|TRUE|1|yes|Yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get auto-refresh threshold hours (env override or config)
# Returns: Hours before expiry to trigger refresh warning
get_auto_refresh_threshold_hours() {
    if [[ -n "${LOA_AUTO_REFRESH_THRESHOLD_HOURS:-}" ]]; then
        echo "$LOA_AUTO_REFRESH_THRESHOLD_HOURS"
    else
        get_registry_config "auto_refresh_threshold_hours" "24"
    fi
}

# Check if update checking is enabled on setup
# Returns: 0 if enabled, 1 if disabled
is_update_check_on_setup_enabled() {
    local enabled
    enabled=$(get_registry_config "check_updates_on_setup" "true")

    case "$enabled" in
        true|True|TRUE|1|yes|Yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Gitignore Management
# =============================================================================

# Ensure .claude/constructs/ is in .gitignore
# Called automatically when installing skills/packs
# Returns: 0 on success, 1 on failure
ensure_constructs_gitignored() {
    local gitignore_file=".gitignore"
    local constructs_pattern=".claude/constructs/"

    # Check if we're in a git repository
    if [[ ! -d ".git" ]]; then
        # Not a git repo, nothing to do
        return 0
    fi

    # Check if .gitignore exists
    if [[ ! -f "$gitignore_file" ]]; then
        # Create .gitignore with constructs exclusion
        cat > "$gitignore_file" << 'EOF'
# =============================================================================
# LOA CONSTRUCTS (licensed skills, user-specific)
# =============================================================================
# Constructs packs and skills are downloaded per-user with individual licenses.
# These should NOT be committed to version control:
# - Licenses are user-specific (contain watermarks, user_id)
# - Content is copyrighted and licensed per-user
# - Users should install via /skill-pack-install command
.claude/constructs/
EOF
        print_success "Created .gitignore with constructs exclusion"
        return 0
    fi

    # Check if already in .gitignore
    if grep -q "^\.claude/constructs/" "$gitignore_file" 2>/dev/null; then
        # Already present
        return 0
    fi

    # Check for partial match (e.g., commented out or different path)
    if grep -q "claude/constructs" "$gitignore_file" 2>/dev/null; then
        # Some variant exists, don't duplicate
        return 0
    fi

    # Add to .gitignore
    cat >> "$gitignore_file" << 'EOF'

# =============================================================================
# LOA CONSTRUCTS (licensed skills, user-specific)
# =============================================================================
# Constructs packs and skills are downloaded per-user with individual licenses.
# These should NOT be committed to version control:
# - Licenses are user-specific (contain watermarks, user_id)
# - Content is copyrighted and licensed per-user
# - Users should install via /skill-pack-install command
.claude/constructs/
EOF

    print_success "Added .claude/constructs/ to .gitignore"
    return 0
}

# Check if constructs directory is properly gitignored
# Returns: 0 if gitignored, 1 if not
is_constructs_gitignored() {
    local gitignore_file=".gitignore"

    # Not a git repo - considered "safe"
    if [[ ! -d ".git" ]]; then
        return 0
    fi

    # No .gitignore - not gitignored
    if [[ ! -f "$gitignore_file" ]]; then
        return 1
    fi

    # Check for the pattern
    if grep -q "^\.claude/constructs/" "$gitignore_file" 2>/dev/null; then
        return 0
    fi

    # Check using git check-ignore (more accurate)
    if command_exists git; then
        if git check-ignore -q ".claude/constructs/" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# SECURITY: Input Validation (MEDIUM-002, MEDIUM-004 fixes)
# =============================================================================
# Reusable validation functions for common input types.

# Validate API key format
# Args:
#   $1 - API key to validate
# Returns: 0 if valid, 1 if invalid
validate_api_key() {
    local key="$1"

    # Empty check
    if [[ -z "$key" ]]; then
        print_error "API key is empty"
        return 1
    fi

    # Loa API keys: sk_ prefix followed by 32 alphanumeric characters
    if [[ ! "$key" =~ ^sk_[a-zA-Z0-9]{32}$ ]]; then
        print_error "Invalid API key format (expected sk_ followed by 32 alphanumeric chars)"
        return 1
    fi

    return 0
}

# Validate URL format
# Args:
#   $1 - URL to validate
# Returns: 0 if valid, 1 if invalid
validate_url() {
    local url="$1"

    # Basic URL validation (must start with http:// or https://)
    if [[ ! "$url" =~ ^https?:// ]]; then
        print_error "Invalid URL format: must start with http:// or https://"
        return 1
    fi

    # Reject URLs with shell metacharacters
    if [[ "$url" =~ [\;\|\&\$\`\\] ]]; then
        print_error "Invalid URL: contains shell metacharacters"
        return 1
    fi

    return 0
}

# Validate identifier (safe for filesystem and shell use)
# Args:
#   $1 - Identifier to validate
# Returns: 0 if valid, 1 if invalid
validate_safe_identifier() {
    local id="$1"

    # Must be non-empty
    if [[ -z "$id" ]]; then
        print_error "Identifier cannot be empty"
        return 1
    fi

    # Must be alphanumeric with dashes and underscores only
    # Also allow forward slash for vendor/skill patterns
    if [[ ! "$id" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
        print_error "Invalid identifier: must be alphanumeric with dashes/underscores only"
        return 1
    fi

    # Cannot start or end with slash
    if [[ "$id" =~ ^/ ]] || [[ "$id" =~ /$ ]]; then
        print_error "Invalid identifier: cannot start or end with /"
        return 1
    fi

    # Cannot contain ..
    if [[ "$id" == *".."* ]]; then
        print_error "Invalid identifier: cannot contain .."
        return 1
    fi

    return 0
}

# Sanitize string for jq use (escape special characters)
# Args:
#   $1 - String to sanitize
# Returns: Sanitized string on stdout
sanitize_for_jq() {
    local input="$1"
    # Use jq's built-in escaping
    printf '%s' "$input" | jq -Rs '.'
}

# =============================================================================
# SECURITY: Content Verification (HIGH-004 fix)
# =============================================================================
# SHA256 verification for downloaded content.

# Verify file content hash
# Args:
#   $1 - File path to verify
#   $2 - Expected SHA256 hash (optional - warns if not provided)
# Returns: 0 if valid/skipped, 1 if mismatch
verify_content_hash() {
    local file="$1"
    local expected_hash="${2:-}"

    # If no hash provided, warn but allow (graceful degradation)
    if [[ -z "$expected_hash" ]]; then
        print_warning "  No content hash provided, skipping verification"
        return 0
    fi

    # Verify file exists
    if [[ ! -f "$file" ]]; then
        print_error "  Cannot verify hash: file not found: $file"
        return 1
    fi

    # Calculate SHA256 (portable: works on Linux and macOS)
    local actual_hash
    if command -v sha256sum &>/dev/null; then
        # Linux
        actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum &>/dev/null; then
        # macOS
        actual_hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        print_warning "  No SHA256 tool available, skipping verification"
        return 0
    fi

    # Compare hashes (case-insensitive)
    if [[ "${actual_hash,,}" != "${expected_hash,,}" ]]; then
        print_error "  Content hash mismatch!"
        print_error "    Expected: $expected_hash"
        print_error "    Got:      $actual_hash"
        return 1
    fi

    return 0
}

# Calculate SHA256 hash of a file
# Args:
#   $1 - File path
# Returns: SHA256 hash on stdout
calculate_file_hash() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo ""
        return 1
    fi
}

# =============================================================================
# Rate Limiting (LOW-003 fix)
# =============================================================================
# Basic rate limiting for API calls.

# Rate limit cache directory
RATE_LIMIT_DIR="${HOME}/.loa/cache/rate-limit"

# Check rate limit before making API call
# Args:
#   $1 - Operation name (e.g., "pack-download")
#   $2 - Max calls per hour (default: 100)
# Returns: 0 if allowed, 1 if rate limited
check_rate_limit() {
    local operation="${1:-default}"
    local max_per_hour="${2:-100}"
    local now
    local rate_file

    now=$(date +%s)
    mkdir -p "$RATE_LIMIT_DIR"
    rate_file="$RATE_LIMIT_DIR/${operation}.count"

    # If no rate file, allow
    if [[ ! -f "$rate_file" ]]; then
        echo "$now:1" > "$rate_file"
        return 0
    fi

    # Read last check time and count
    local last_time last_count
    IFS=':' read -r last_time last_count < "$rate_file"

    # If more than an hour passed, reset
    local elapsed=$((now - last_time))
    if [[ $elapsed -gt 3600 ]]; then
        echo "$now:1" > "$rate_file"
        return 0
    fi

    # Increment count
    last_count=$((last_count + 1))

    # Check if over limit
    if [[ $last_count -gt $max_per_hour ]]; then
        local remaining=$((3600 - elapsed))
        print_warning "Rate limit exceeded for $operation. Try again in $(humanize_duration $remaining)."
        return 1
    fi

    # Update count
    echo "$last_time:$last_count" > "$rate_file"
    return 0
}

# Reset rate limit for an operation
# Args:
#   $1 - Operation name
reset_rate_limit() {
    local operation="${1:-default}"
    local rate_file="$RATE_LIMIT_DIR/${operation}.count"
    rm -f "$rate_file"
}

# =============================================================================
# Version Comparison (Sprint 5)
# =============================================================================

# Compare two semantic version strings
# Args:
#   $1 - Current version (e.g., "1.0.0")
#   $2 - Latest version (e.g., "1.1.0")
# Returns/Outputs:
#   0 if equal
#   1 if latest > current (update available)
#  -1 if current > latest (somehow ahead)
compare_versions() {
    local current="$1"
    local latest="$2"

    # Handle empty strings
    if [[ -z "$current" ]] || [[ -z "$latest" ]]; then
        echo "0"
        return 0
    fi

    # If they're equal, return 0
    if [[ "$current" == "$latest" ]]; then
        echo "0"
        return 0
    fi

    # Split versions into components
    local IFS='.'
    read -ra current_parts <<< "$current"
    read -ra latest_parts <<< "$latest"

    # Compare each component
    local max_parts=${#current_parts[@]}
    if [[ ${#latest_parts[@]} -gt $max_parts ]]; then
        max_parts=${#latest_parts[@]}
    fi

    for ((i=0; i<max_parts; i++)); do
        local curr_part="${current_parts[i]:-0}"
        local latest_part="${latest_parts[i]:-0}"

        # Remove any non-numeric suffix (e.g., "1.0.0-beta")
        curr_part="${curr_part%%[!0-9]*}"
        latest_part="${latest_part%%[!0-9]*}"

        # Default to 0 if empty after stripping
        curr_part="${curr_part:-0}"
        latest_part="${latest_part:-0}"

        if [[ "$latest_part" -gt "$curr_part" ]]; then
            echo "1"
            return 0
        elif [[ "$curr_part" -gt "$latest_part" ]]; then
            echo "-1"
            return 0
        fi
    done

    # All parts equal
    echo "0"
    return 0
}

# Check if an update is available for a version
# Args:
#   $1 - Current version
#   $2 - Latest version
# Returns: 0 if update available, 1 if not
is_update_available() {
    local result
    result=$(compare_versions "$1" "$2")
    [[ "$result" == "1" ]]
}

# =============================================================================
# Secure File Operations (MED-005)
# =============================================================================

# Write file with secure permissions
# SECURITY (MED-005): Standardizes state file permissions
# Args:
#   $1 - File path
#   $2 - Content
#   $3 - Permission mode (default: 600 for state files)
# Returns: 0 on success, 1 on failure
secure_write_file() {
    local file_path="$1"
    local content="$2"
    local mode="${3:-600}"

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$file_path")
    mkdir -p "$parent_dir"

    # Write to temp file first
    local tmp_file="${file_path}.tmp.$$"

    # Set umask for secure file creation
    local old_umask
    old_umask=$(umask)
    umask 077  # Only owner can read/write

    if ! echo "$content" > "$tmp_file"; then
        umask "$old_umask"
        rm -f "$tmp_file"
        return 1
    fi

    # Atomic move
    if ! mv "$tmp_file" "$file_path"; then
        umask "$old_umask"
        rm -f "$tmp_file"
        return 1
    fi

    # Set explicit permissions
    chmod "$mode" "$file_path"

    umask "$old_umask"
    return 0
}

# Write JSON file with validation and secure permissions
# Args:
#   $1 - File path
#   $2 - JSON content
#   $3 - Permission mode (default: 600)
# Returns: 0 on success, 1 on failure
secure_write_json() {
    local file_path="$1"
    local content="$2"
    local mode="${3:-600}"

    # Validate JSON first
    if ! echo "$content" | jq empty 2>/dev/null; then
        print_error "Invalid JSON content"
        return 1
    fi

    # Pretty-print and write
    local formatted
    formatted=$(echo "$content" | jq '.')
    secure_write_file "$file_path" "$formatted" "$mode"
}
