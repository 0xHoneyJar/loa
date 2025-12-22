#!/bin/bash
# Git safety detection functions for Loa framework
# Prevents accidental pushes to upstream template repository

# Known Loa template repositories
KNOWN_TEMPLATES="(0xHoneyJar|thj-dev)/loa"

# Layer 1: Check cached detection from setup marker
check_cached_detection() {
    if [ -f ".loa-setup-complete" ]; then
        local cached=$(grep -o '"detected": *true' .loa-setup-complete 2>/dev/null)
        if [ -n "$cached" ]; then
            echo "Cached from setup"
            return 0
        fi
    fi
    return 1
}

# Layer 2: Check origin URL
check_origin_url() {
    local origin_url=$(git remote get-url origin 2>/dev/null)
    if echo "$origin_url" | grep -qE "$KNOWN_TEMPLATES"; then
        echo "Origin URL match"
        return 0
    fi
    return 1
}

# Layer 3: Check upstream/loa remote
check_upstream_remote() {
    if git remote -v 2>/dev/null | grep -E "^(upstream|loa)\s" | grep -qE "$KNOWN_TEMPLATES"; then
        echo "Upstream remote match"
        return 0
    fi
    return 1
}

# Layer 4: Check GitHub API (requires gh CLI)
check_github_api() {
    if command -v gh &>/dev/null; then
        local parent=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null)
        if echo "$parent" | grep -qE "$KNOWN_TEMPLATES"; then
            echo "GitHub API fork check"
            return 0
        fi
    fi
    return 1
}

# Main detection function - returns detection method or empty string
detect_template() {
    local method

    # Try each layer in order
    method=$(check_cached_detection) && { echo "$method"; return 0; }
    method=$(check_origin_url) && { echo "$method"; return 0; }
    method=$(check_upstream_remote) && { echo "$method"; return 0; }
    method=$(check_github_api) && { echo "$method"; return 0; }

    return 1
}

# Check if a specific remote points to a template
is_template_remote() {
    local remote_name="$1"
    local remote_url=$(git remote get-url "$remote_name" 2>/dev/null)
    echo "$remote_url" | grep -qE "$KNOWN_TEMPLATES"
}

# Get remote URL for display
get_remote_url() {
    local remote_name="$1"
    git remote get-url "$remote_name" 2>/dev/null
}

# Check if template detection is explicitly disabled
is_detection_disabled() {
    if [ -f ".loa-setup-complete" ]; then
        grep -q '"detected": *false' .loa-setup-complete 2>/dev/null
        return $?
    fi
    return 1
}
