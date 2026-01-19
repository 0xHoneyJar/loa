#!/bin/bash
# Sync beads state and optionally commit
# Usage: sync-and-commit.sh ["commit message"]
#
# Without argument: flushes and stages .beads/
# With argument: flushes, stages, and commits with given message
#
# Part of Loa beads_rust integration

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Navigate to project root
cd "$(git rev-parse --show-toplevel)"

# Check if .beads exists
if [ ! -d ".beads" ]; then
  log_warn "No .beads directory found. Run 'br init' first."
  exit 1
fi

# Flush SQLite to JSONL
log_info "Flushing beads state to JSONL..."
br sync --flush-only

# Check if there are changes to stage
if git diff --quiet .beads/ && git diff --cached --quiet .beads/; then
  log_info "No changes to .beads/ directory"
  exit 0
fi

# Stage .beads directory
log_info "Staging .beads/ directory..."
git add .beads/

# Show what's staged
echo ""
git diff --cached --stat .beads/
echo ""

# Commit if message provided
if [ -n "${1:-}" ]; then
  log_info "Committing: $1"
  git commit -m "$1"
  log_info "Changes committed"
else
  log_info ".beads/ staged. Run 'git commit' to finalize."
fi
