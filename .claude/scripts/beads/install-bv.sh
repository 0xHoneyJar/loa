#!/usr/bin/env bash
# Install beads_viewer (bv) CLI tool — OPTIONAL graph-triage sidecar for br
# Usage: install-bv.sh [--check-only]
#
# Returns:
#   0 - Installation successful or already installed
#   1 - Installation failed (or NOT_INSTALLED with --check-only)
#
# bv is NOT a Loa dependency. Everything that references it
# (get-ready-work.sh --graph, the planning-sprints structural validation)
# degrades gracefully to br-only behavior when bv is absent. Install it to
# light up dependency-graph triage: parallel tracks (--robot-plan), honest
# unblock counts, PageRank/betweenness, cycle detection.
#
# AGENT NOTE: never run bare `bv` — it launches an interactive TUI that blocks
# the session. Use --robot-* flags only (start with: bv --robot-help).

set -euo pipefail

CHECK_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Function to check if bv is available
verify_install() {
    if command -v bv &> /dev/null; then
        VERSION=$(bv --version 2>/dev/null | head -1 || echo "unknown")
        echo "SUCCESS"
        echo "VERSION:$VERSION"
        return 0
    fi
    return 1
}

# Check if already installed
if verify_install; then
    echo "beads_viewer (bv) is already installed"
    exit 0
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "NOT_INSTALLED"
    exit 1
fi

echo "Installing beads_viewer (bv)..."

# Method 1: Homebrew tap (recommended by upstream for macOS/Linux)
if command -v brew &> /dev/null; then
    echo "Trying brew install..."
    if brew install dicklesworthstone/tap/bv 2>/dev/null; then
        if verify_install; then
            exit 0
        fi
    fi
fi

# Method 2: Upstream install script (pinned to the official repo; cache-busted
# per upstream README convention)
if command -v curl &> /dev/null; then
    echo "Trying upstream install script..."
    if curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash 2>/dev/null; then
        if verify_install; then
            exit 0
        fi
    fi
fi

# Method 3: go install (bv is Go)
if command -v go &> /dev/null; then
    echo "Trying go install..."
    if go install github.com/Dicklesworthstone/beads_viewer/cmd/bv@latest 2>/dev/null; then
        export PATH="$HOME/go/bin:$PATH"
        if verify_install; then
            exit 0
        fi
    fi
fi

# Method 4: Check common binary locations
for dir in "$HOME/go/bin" "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
    if [[ -x "$dir/bv" ]]; then
        export PATH="$dir:$PATH"
        if verify_install; then
            exit 0
        fi
    fi
done

# All methods failed
echo "FAILED"
echo ""
echo "Automatic installation failed. bv is OPTIONAL — Loa works without it."
echo "To install manually:"
echo ""
echo "  # Option 1: Homebrew (macOS/Linux)"
echo "  brew install dicklesworthstone/tap/bv"
echo ""
echo "  # Option 2: Windows"
echo "  scoop install bv   # see github.com/Dicklesworthstone/beads_viewer"
echo ""
echo "  # Option 3: Direct download / install script"
echo "  https://github.com/Dicklesworthstone/beads_viewer#installation"
echo ""
echo "After installing, run: bv --version  (agents: bv --robot-help)"
exit 1
