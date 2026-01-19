#!/bin/bash
# Install beads_rust (br) if not present
# Usage: install-br.sh
#
# Part of Loa beads_rust integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check if already installed
if command -v br &>/dev/null; then
  VERSION=$(br --version 2>/dev/null || echo "unknown")
  log_info "beads_rust (br) already installed: $VERSION"
  exit 0
fi

log_info "Installing beads_rust..."

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)
    log_error "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  linux) PLATFORM="unknown-linux-gnu" ;;
  darwin) PLATFORM="apple-darwin" ;;
  *)
    log_error "Unsupported OS: $OS"
    exit 1
    ;;
esac

# Try the official install script first
if curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh" | bash; then
  log_info "beads_rust installed successfully"
else
  log_warn "Official installer failed, trying cargo install..."

  # Fallback to cargo if available
  if command -v cargo &>/dev/null; then
    cargo install --git https://github.com/Dicklesworthstone/beads_rust.git
    log_info "beads_rust installed via cargo"
  else
    log_error "Could not install beads_rust. Please install manually."
    log_error "See: https://github.com/Dicklesworthstone/beads_rust#installation"
    exit 1
  fi
fi

# Verify installation
if command -v br &>/dev/null; then
  VERSION=$(br --version 2>/dev/null || echo "unknown")
  log_info "beads_rust ready: $VERSION"
else
  log_error "Installation completed but 'br' not found in PATH"
  log_warn "You may need to add ~/.cargo/bin to your PATH"
  exit 1
fi
