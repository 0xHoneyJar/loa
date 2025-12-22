#!/bin/bash
# Install Beads (bd) CLI tool
# Usage: install-beads.sh
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
#
# This script attempts multiple installation methods in order of preference.

set -euo pipefail

echo "Installing Beads (bd)..."

# Function to check if bd is available after install
verify_install() {
    if command -v bd &> /dev/null; then
        VERSION=$(bd --version 2>/dev/null || echo "unknown")
        echo "SUCCESS"
        echo "VERSION:$VERSION"
        return 0
    fi
    return 1
}

# Check if already installed
if verify_install; then
    echo "Beads is already installed"
    exit 0
fi

# Method 1: Official install script (preferred)
echo "Trying official install script..."
if curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash 2>/dev/null; then
    # Reload PATH in case install added to profile
    export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
    if verify_install; then
        exit 0
    fi
fi

# Method 2: Go install (if Go is available)
if command -v go &> /dev/null; then
    echo "Trying go install..."
    if go install github.com/steveyegge/beads/cmd/bd@latest 2>/dev/null; then
        export PATH="$HOME/go/bin:$PATH"
        if verify_install; then
            exit 0
        fi
    fi
fi

# Method 3: Check common binary locations
for dir in "$HOME/.local/bin" "$HOME/go/bin" "/usr/local/bin"; do
    if [[ -x "$dir/bd" ]]; then
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
echo "  # Option 1: Install script"
echo "  curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
echo ""
echo "  # Option 2: Go install (requires Go 1.21+)"
echo "  go install github.com/steveyegge/beads/cmd/bd@latest"
echo ""
echo "  # Option 3: Build from source"
echo "  git clone https://github.com/steveyegge/beads.git"
echo "  cd beads && go build -o bd ./cmd/bd"
echo "  sudo mv bd /usr/local/bin/"
echo ""
echo "After installing, run: bd --version"
exit 1
