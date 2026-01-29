#!/usr/bin/env bash
# .claude/scripts/memory-setup.sh
#
# First-time setup for Loa Memory Stack
# Initializes database, checks dependencies, and configures hooks
#
# Usage:
#   memory-setup.sh [--enable-hook] [--enable-qmd] [--enable-auto-sync]

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOA_DIR="${PROJECT_ROOT}/.loa"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
SETTINGS_FILE="${PROJECT_ROOT}/.claude/settings.json"
MEMORY_ADMIN="${PROJECT_ROOT}/.claude/scripts/memory-admin.sh"
EMBED_SCRIPT="${PROJECT_ROOT}/.claude/hooks/memory-utils/embed.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
ENABLE_HOOK=false
ENABLE_QMD=false
ENABLE_AUTO_SYNC=false

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Loa Memory Stack Setup${NC}                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}  ✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}  ✗${NC} $1"
}

log_info() {
    echo -e "${CYAN}  ℹ${NC} $1"
}

# =============================================================================
# Dependency Checks
# =============================================================================

check_dependencies() {
    log_step "Checking dependencies..."

    local all_ok=true

    # Python 3
    if command -v python3 >/dev/null 2>&1; then
        local py_version
        py_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_ok "Python 3 found: $py_version"
    else
        log_error "Python 3 not found"
        all_ok=false
    fi

    # sentence-transformers (check venv first, then system)
    local python_cmd="python3"
    if [[ -x "${LOA_DIR}/venv/bin/python3" ]]; then
        python_cmd="${LOA_DIR}/venv/bin/python3"
        log_ok "Using venv Python: ${LOA_DIR}/venv/bin/python3"
    fi

    if "$python_cmd" -c "import sentence_transformers" 2>/dev/null; then
        log_ok "sentence-transformers installed"
    else
        log_warn "sentence-transformers not installed"
        echo ""
        echo -e "    Install with: ${BOLD}python3 -m venv .loa/venv && .loa/venv/bin/pip install sentence-transformers${NC}"
        echo ""
        all_ok=false
    fi

    # SQLite 3
    if command -v sqlite3 >/dev/null 2>&1; then
        local sqlite_version
        sqlite_version=$(sqlite3 --version 2>&1 | cut -d' ' -f1)
        log_ok "SQLite found: $sqlite_version"
    else
        log_error "SQLite 3 not found"
        all_ok=false
    fi

    # jq
    if command -v jq >/dev/null 2>&1; then
        log_ok "jq found"
    else
        log_error "jq not found (required for JSON processing)"
        all_ok=false
    fi

    # yq (optional, for config editing)
    if command -v yq >/dev/null 2>&1; then
        log_ok "yq found"
    else
        log_warn "yq not found (optional, for config editing)"
    fi

    # QMD (optional)
    if command -v qmd >/dev/null 2>&1; then
        log_ok "qmd found (semantic document search available)"
    else
        log_info "qmd not found (optional, grep fallback will be used)"
    fi

    if [[ "$all_ok" == "false" ]]; then
        echo ""
        log_error "Missing required dependencies. Please install them first."
        return 1
    fi

    return 0
}

# =============================================================================
# Database Initialization
# =============================================================================

init_database() {
    log_step "Initializing memory database..."

    if [[ -f "${LOA_DIR}/memory.db" ]]; then
        log_info "Database already exists at ${LOA_DIR}/memory.db"

        # Check if it's valid
        if "$MEMORY_ADMIN" stats >/dev/null 2>&1; then
            local count
            count=$("$MEMORY_ADMIN" stats 2>/dev/null | jq -r '.total_memories // 0')
            log_ok "Database valid ($count memories)"
            return 0
        else
            log_warn "Database exists but may be corrupted"
        fi
    fi

    # Initialize
    if "$MEMORY_ADMIN" init 2>/dev/null; then
        log_ok "Database initialized at ${LOA_DIR}/memory.db"
    else
        log_error "Failed to initialize database"
        return 1
    fi
}

# =============================================================================
# Embedding Test
# =============================================================================

test_embeddings() {
    log_step "Testing embedding service..."

    if [[ ! -f "$EMBED_SCRIPT" ]]; then
        log_error "Embedding script not found: $EMBED_SCRIPT"
        return 1
    fi

    # Test embedding generation (use venv if available)
    local python_cmd="python3"
    if [[ -x "${LOA_DIR}/venv/bin/python3" ]]; then
        python_cmd="${LOA_DIR}/venv/bin/python3"
    fi

    local test_result
    if test_result=$(echo "test embedding" | "$python_cmd" "$EMBED_SCRIPT" 2>/dev/null); then
        local dim
        dim=$(echo "$test_result" | jq -r '.embedding | length' 2>/dev/null || echo "0")
        if [[ "$dim" == "384" ]]; then
            log_ok "Embedding service working (384 dimensions)"
        else
            log_warn "Unexpected embedding dimension: $dim"
        fi
    else
        log_error "Embedding service failed"
        return 1
    fi
}

# =============================================================================
# Configuration
# =============================================================================

configure_settings() {
    log_step "Configuring settings..."

    # Update .loa.config.yaml if flags provided
    if [[ "$ENABLE_HOOK" == "true" ]] && command -v yq >/dev/null 2>&1; then
        if yq eval -i '.memory.pretooluse_hook.enabled = true' "$CONFIG_FILE" 2>/dev/null; then
            log_ok "Enabled PreToolUse hook in .loa.config.yaml"
        fi
    fi

    if [[ "$ENABLE_QMD" == "true" ]] && command -v yq >/dev/null 2>&1; then
        if yq eval -i '.memory.qmd.enabled = true' "$CONFIG_FILE" 2>/dev/null; then
            log_ok "Enabled QMD integration in .loa.config.yaml"
        fi
    fi

    if [[ "$ENABLE_AUTO_SYNC" == "true" ]] && command -v yq >/dev/null 2>&1; then
        if yq eval -i '.memory.auto_sync = true' "$CONFIG_FILE" 2>/dev/null; then
            log_ok "Enabled auto-sync in .loa.config.yaml"
        fi
    fi

    # Check if hook is configured in settings.json
    if [[ -f "$SETTINGS_FILE" ]]; then
        if grep -q "memory-inject.sh" "$SETTINGS_FILE" 2>/dev/null; then
            log_ok "Hook already configured in .claude/settings.json"
        else
            log_info "Hook not yet in .claude/settings.json (see instructions below)"
        fi
    else
        log_info "No .claude/settings.json found (will be created when needed)"
    fi
}

# =============================================================================
# Print Summary
# =============================================================================

print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Memory Stack Setup Complete!${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}Database:${NC}"
    echo "  Location: ${LOA_DIR}/memory.db"
    echo ""

    echo -e "${BOLD}Quick Start:${NC}"
    echo "  # Add a memory"
    echo "  .claude/scripts/memory-admin.sh add \"Always use absolute paths\" --type gotcha"
    echo ""
    echo "  # Search memories"
    echo "  .claude/scripts/memory-admin.sh search \"path configuration\""
    echo ""
    echo "  # Sync learnings from NOTES.md"
    echo "  .claude/scripts/memory-sync.sh notes"
    echo ""

    echo -e "${BOLD}To Enable Mid-Stream Injection:${NC}"
    echo ""
    echo "  1. Enable in config (.loa.config.yaml):"
    echo -e "     ${CYAN}memory:"
    echo "       pretooluse_hook:"
    echo -e "         enabled: true${NC}"
    echo ""
    echo "  2. Add hook to .claude/settings.json:"
    echo -e "     ${CYAN}{"
    echo '       "hooks": {'
    echo '         "PreToolUse": [{'
    echo '           "matcher": "Read|Glob|Grep|WebFetch|WebSearch",'
    echo '           "hooks": [{'
    echo '             "type": "command",'
    echo '             "command": ".claude/hooks/memory-inject.sh"'
    echo '           }]'
    echo '         }]'
    echo '       }'
    echo -e "     }${NC}"
    echo ""

    echo -e "${BOLD}Run Tests:${NC}"
    echo "  bats .claude/scripts/tests/test-memory-stack.bats"
    echo ""
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Loa Memory Stack Setup

Usage:
  memory-setup.sh [options]

Options:
  --enable-hook      Enable PreToolUse hook in .loa.config.yaml
  --enable-qmd       Enable QMD integration in .loa.config.yaml
  --enable-auto-sync Enable NOTES.md auto-sync in .loa.config.yaml
  --help, -h         Show this help

This script:
  1. Checks required dependencies (Python, sentence-transformers, SQLite)
  2. Initializes the memory database (.loa/memory.db)
  3. Tests the embedding service
  4. Optionally enables features in configuration

After setup, you'll need to manually add the hook to .claude/settings.json
to enable mid-stream memory injection.
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable-hook)
                ENABLE_HOOK=true
                shift
                ;;
            --enable-qmd)
                ENABLE_QMD=true
                shift
                ;;
            --enable-auto-sync)
                ENABLE_AUTO_SYNC=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_header

    # Run setup steps
    if ! check_dependencies; then
        exit 1
    fi
    echo ""

    if ! init_database; then
        exit 1
    fi
    echo ""

    if ! test_embeddings; then
        log_warn "Embedding test failed - memories will work but search quality may be reduced"
    fi
    echo ""

    configure_settings
    echo ""

    print_summary
}

main "$@"
