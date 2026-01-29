#!/usr/bin/env bash
# Migrate from beads (bd) to beads_rust (br)
# Usage: migrate-to-br.sh [--prefix PREFIX] [--dry-run] [--force]
#
# This script handles migration from the Python-based beads (bd) CLI
# to the Rust-based beads_rust (br) CLI introduced in Loa v1.1.0.
#
# Migration handles:
#   - Schema differences between bd and br SQLite databases
#   - Prefix normalization (mixed prefixes → single prefix)
#   - JSONL format compatibility
#   - Old daemon cleanup (bd.sock, daemon.lock)
#
# Returns:
#   0 - Migration successful
#   1 - Migration failed
#   2 - Nothing to migrate

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
BEADS_DIR=".beads"
DRY_RUN=false
FORCE=false
PREFIX=""
BACKUP_DIR=""

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Migrate from beads (bd) to beads_rust (br).

Options:
    --prefix PREFIX    Set the project prefix for br (default: auto-detect or 'bd')
    --dry-run          Show what would be done without making changes
    --force            Overwrite existing br database
    --help             Show this help message

Examples:
    $(basename "$0")                    # Auto-detect prefix, migrate
    $(basename "$0") --prefix myproj    # Use 'myproj' as prefix
    $(basename "$0") --dry-run          # Preview migration
EOF
    exit 0
}

log() {
    echo -e "${BLUE}[migrate]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[warn]${NC} $1"
}

error() {
    echo -e "${RED}[error]${NC} $1"
}

success() {
    echo -e "${GREEN}[success]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if br is installed
if ! command -v br &> /dev/null; then
    error "beads_rust (br) is not installed"
    echo ""
    echo "Install with:"
    echo "  cargo install beads_rust"
    echo ""
    echo "Or use the Loa installer:"
    echo "  .claude/scripts/beads/install-br.sh"
    exit 1
fi

# Check if .beads directory exists
if [[ ! -d "$BEADS_DIR" ]]; then
    error "No .beads directory found"
    echo "Nothing to migrate - run 'br init' to start fresh"
    exit 2
fi

log "Scanning existing beads data..."

# Detect what we're migrating from
HAS_BD_CONFIG=false
HAS_BD_DAEMON=false
HAS_JSONL=false
HAS_OLD_DB=false
JSONL_FILE=""

if [[ -f "$BEADS_DIR/config.yaml" ]]; then
    HAS_BD_CONFIG=true
fi

if [[ -S "$BEADS_DIR/bd.sock" ]] || [[ -f "$BEADS_DIR/daemon.lock" ]]; then
    HAS_BD_DAEMON=true
fi

# Find JSONL files (bd uses various names)
for f in "$BEADS_DIR/issues.jsonl" "$BEADS_DIR/beads.left.jsonl" "$BEADS_DIR/export.jsonl"; do
    if [[ -f "$f" ]]; then
        HAS_JSONL=true
        JSONL_FILE="$f"
        break
    fi
done

if [[ -f "$BEADS_DIR/beads.db" ]]; then
    HAS_OLD_DB=true
fi

# Report findings
echo ""
log "Found:"
[[ "$HAS_BD_CONFIG" == "true" ]] && echo "  - bd config.yaml (old beads config)"
[[ "$HAS_BD_DAEMON" == "true" ]] && echo "  - bd daemon artifacts (socket/lock)"
[[ "$HAS_JSONL" == "true" ]] && echo "  - JSONL export: $JSONL_FILE"
[[ "$HAS_OLD_DB" == "true" ]] && echo "  - SQLite database: beads.db"
echo ""

# If nothing to migrate
if [[ "$HAS_BD_CONFIG" == "false" ]] && [[ "$HAS_JSONL" == "false" ]] && [[ "$HAS_OLD_DB" == "false" ]]; then
    log "No bd artifacts found - nothing to migrate"
    exit 2
fi

# Auto-detect prefix from JSONL if not specified
if [[ -z "$PREFIX" ]] && [[ "$HAS_JSONL" == "true" ]]; then
    log "Auto-detecting prefix from JSONL..."

    # Extract unique prefixes from issue IDs
    PREFIXES=$(grep -oE '"id":\s*"[^"]+' "$JSONL_FILE" | sed 's/"id":\s*"//' | cut -d'-' -f1 | sort -u)
    PREFIX_COUNT=$(echo "$PREFIXES" | wc -l)

    if [[ "$PREFIX_COUNT" -eq 1 ]]; then
        PREFIX="$PREFIXES"
        log "Detected single prefix: $PREFIX"
    elif [[ "$PREFIX_COUNT" -gt 1 ]]; then
        warn "Multiple prefixes found in JSONL:"
        echo "$PREFIXES" | while read -r p; do
            COUNT=$(grep -c "\"id\":\\s*\"$p-" "$JSONL_FILE" 2>/dev/null || echo 0)
            echo "  - $p ($COUNT issues)"
        done
        echo ""
        # Use the most common prefix
        PREFIX=$(echo "$PREFIXES" | head -1)
        warn "Using first prefix: $PREFIX (specify --prefix to override)"
    fi
fi

# Default prefix if still not set
if [[ -z "$PREFIX" ]]; then
    PREFIX="bd"
    log "Using default prefix: $PREFIX"
fi

# Create backup directory
BACKUP_DIR="$BEADS_DIR/.migration-backup-$(date +%Y%m%d-%H%M%S)"

echo ""
log "Migration plan:"
echo "  - Prefix: $PREFIX"
echo "  - Backup to: $BACKUP_DIR"
[[ "$HAS_BD_DAEMON" == "true" ]] && echo "  - Clean up daemon artifacts"
[[ "$HAS_OLD_DB" == "true" ]] && echo "  - Remove old SQLite database (incompatible schema)"
[[ "$HAS_JSONL" == "true" ]] && echo "  - Filter JSONL to prefix '$PREFIX' only"
echo "  - Initialize fresh br workspace"
[[ "$HAS_JSONL" == "true" ]] && echo "  - Import filtered issues"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN - no changes made"
    exit 0
fi

# Confirm if not forced
if [[ "$FORCE" == "false" ]]; then
    read -p "Proceed with migration? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Migration cancelled"
        exit 0
    fi
fi

# Create backup
log "Creating backup..."
mkdir -p "$BACKUP_DIR"

for f in "$BEADS_DIR"/*; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == ".migration-backup-"* ]] && continue
    cp -a "$f" "$BACKUP_DIR/" 2>/dev/null || true
done

success "Backup created: $BACKUP_DIR"

# Stop bd daemon if running
if [[ "$HAS_BD_DAEMON" == "true" ]]; then
    log "Cleaning up bd daemon..."
    # Try to stop daemon gracefully
    if command -v bd &> /dev/null; then
        bd daemon stop 2>/dev/null || true
    fi
    # Remove socket and lock
    rm -f "$BEADS_DIR/bd.sock" "$BEADS_DIR/daemon.lock" 2>/dev/null || true
    success "Daemon artifacts cleaned"
fi

# Filter JSONL to single prefix if needed
FILTERED_JSONL=""
if [[ "$HAS_JSONL" == "true" ]]; then
    TOTAL_ISSUES=$(wc -l < "$JSONL_FILE")
    MATCHING_ISSUES=$(grep -c "\"id\":\\s*\"$PREFIX-" "$JSONL_FILE" 2>/dev/null || echo 0)

    if [[ "$TOTAL_ISSUES" -ne "$MATCHING_ISSUES" ]]; then
        log "Filtering JSONL ($MATCHING_ISSUES of $TOTAL_ISSUES issues match prefix '$PREFIX')..."
        FILTERED_JSONL="$BEADS_DIR/issues-filtered.jsonl"
        grep "\"id\":\\s*\"$PREFIX-" "$JSONL_FILE" > "$FILTERED_JSONL" 2>/dev/null || true

        FILTERED_COUNT=$(wc -l < "$FILTERED_JSONL" 2>/dev/null || echo 0)
        if [[ "$FILTERED_COUNT" -eq 0 ]]; then
            warn "No issues match prefix '$PREFIX' - starting fresh"
            rm -f "$FILTERED_JSONL"
            FILTERED_JSONL=""
        else
            success "Filtered to $FILTERED_COUNT issues"
        fi
    else
        log "All $TOTAL_ISSUES issues match prefix '$PREFIX'"
        FILTERED_JSONL="$JSONL_FILE"
    fi
fi

# Remove old database (schema incompatible)
if [[ "$HAS_OLD_DB" == "true" ]]; then
    log "Removing old SQLite database (schema incompatible with br)..."
    rm -f "$BEADS_DIR/beads.db" "$BEADS_DIR/beads.db-shm" "$BEADS_DIR/beads.db-wal" 2>/dev/null || true
    success "Old database removed"
fi

# Remove old bd config (br uses different format)
if [[ "$HAS_BD_CONFIG" == "true" ]]; then
    log "Removing old bd config.yaml..."
    rm -f "$BEADS_DIR/config.yaml" 2>/dev/null || true
fi

# Remove old metadata files
rm -f "$BEADS_DIR/metadata.json" "$BEADS_DIR/beads.left.meta.json" 2>/dev/null || true

# Initialize br workspace
log "Initializing br workspace with prefix '$PREFIX'..."
br init --prefix "$PREFIX" --force 2>/dev/null

# Import filtered JSONL if available
if [[ -n "$FILTERED_JSONL" ]] && [[ -f "$FILTERED_JSONL" ]]; then
    # Move filtered JSONL to expected location
    if [[ "$FILTERED_JSONL" != "$BEADS_DIR/issues.jsonl" ]]; then
        mv "$FILTERED_JSONL" "$BEADS_DIR/issues.jsonl"
    fi

    log "Importing issues from JSONL..."
    if br sync --import-only 2>&1; then
        success "Issues imported successfully"
    else
        warn "Import had issues - check 'br doctor' for details"
    fi
fi

# Verify migration
echo ""
log "Verifying migration..."
if br doctor 2>&1 | grep -q "OK"; then
    success "Migration complete!"
    echo ""
    br stats 2>/dev/null || true
else
    warn "Migration complete with warnings - run 'br doctor' for details"
fi

echo ""
log "Next steps:"
echo "  1. Run 'br ready' to see available work"
echo "  2. Run 'br stats' to see project statistics"
echo "  3. Uninstall bd if no longer needed: pip uninstall beads"
echo ""
echo "Backup location: $BACKUP_DIR"
echo "To rollback: rm -rf $BEADS_DIR && mv $BACKUP_DIR $BEADS_DIR"
