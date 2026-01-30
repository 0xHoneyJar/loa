#!/usr/bin/env bash
# Install beads_rust (br) CLI tool
# Usage: install-br.sh [--check-only]
#
# Returns:
#   0 - Installation successful or already installed
#   1 - Installation failed
#
# This script installs the Rust-based beads_rust CLI (br) which replaced
# the Python-based beads (bd) in Loa v1.1.0.

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

# Function to check if br is available
verify_install() {
    if command -v br &> /dev/null; then
        VERSION=$(br --version 2>/dev/null | head -1 || echo "unknown")
        echo "SUCCESS"
        echo "VERSION:$VERSION"
        return 0
    fi
    return 1
}

# Check if already installed
if verify_install; then
    echo "beads_rust (br) is already installed"
    exit 0
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "NOT_INSTALLED"
    exit 1
fi

echo "Installing beads_rust (br)..."

# Method 1: Cargo install from crates.io (if available)
if command -v cargo &> /dev/null; then
    echo "Trying cargo install..."

    # First try crates.io
    if cargo install beads_rust 2>/dev/null; then
        if verify_install; then
            exit 0
        fi
    fi

    # If not on crates.io, try from GitHub
    echo "Trying cargo install from GitHub..."
    if cargo install --git https://github.com/Dicklesworthstone/beads_rust 2>/dev/null; then
        if verify_install; then
            exit 0
        fi
    fi
fi

# Method 2: Download pre-built binary (future - when releases are available)
# ARCH=$(uname -m)
# OS=$(uname -s | tr '[:upper:]' '[:lower:]')
# ... download logic ...

# Method 3: Check common binary locations
for dir in "$HOME/.cargo/bin" "$HOME/.local/bin" "/usr/local/bin"; do
    if [[ -x "$dir/br" ]]; then
        export PATH="$dir:$PATH"
        if verify_install; then
            exit 0
        fi
    fi
done

# All methods failed
echo "FAILED"
echo ""
echo "Automatic installation failed. Please install manually:"
echo ""
echo "  # Option 1: Cargo install from GitHub (requires Rust)"
echo "  cargo install --git https://github.com/Dicklesworthstone/beads_rust"
echo ""
echo "  # Option 2: Install Rust first, then cargo install"
echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo "  source \$HOME/.cargo/env"
echo "  cargo install --git https://github.com/Dicklesworthstone/beads_rust"
echo ""
echo "After installing, run: br --version"
exit 1
