#!/bin/bash
#
# Onomancer Bot - Rollback Script
#
# This script rolls back the Onomancer Bot to a previous version.
# Run as the devrel user from the application directory.
#
# Usage: ./rollback.sh [OPTIONS]
#
# Options:
#   --list           List available rollback points
#   --db-only        Only rollback database (restore from backup)
#   --code VERSION   Rollback to specific git version/tag
#   --confirm        Skip confirmation prompt
#   --help           Show this help message
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# BASE_DIR: Root installation directory (contains repo clone and data directories)
# APP_DIR: Application code directory (the cloned devrel-integration repo)
BASE_DIR="/opt/devrel-integration"
APP_DIR="$BASE_DIR/devrel-integration"
BACKUP_DIR="$BASE_DIR/backups"
DATA_DIR="$BASE_DIR/data"
PM2_HOME="$BASE_DIR/.pm2"

LIST_ONLY=false
DB_ONLY=false
CODE_VERSION=""
CONFIRM=false

export PM2_HOME

# Function definitions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

show_help() {
    head -18 "$0" | tail -14
    exit 0
}

# List available rollback points
list_rollback_points() {
    echo ""
    echo "========================================"
    echo "  Available Rollback Points"
    echo "========================================"
    echo ""

    # Database backups
    echo "Database Backups:"
    if ls "$BACKUP_DIR"/onomancer_*.db 1> /dev/null 2>&1; then
        ls -lt "$BACKUP_DIR"/onomancer_*.db | head -10 | while read -r line; do
            echo "  $line"
        done
    else
        echo "  (no backups found)"
    fi
    echo ""

    # Git versions (if git repo)
    if [[ -d "$BASE_DIR/.git" ]]; then
        echo "Git Tags:"
        cd "$BASE_DIR"
        git tag -l --sort=-v:refname | head -10 | while read -r tag; do
            echo "  $tag"
        done
        echo ""

        echo "Recent Commits:"
        git log --oneline -10
    fi
    echo ""
}

# Rollback database
rollback_database() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
    fi

    log_info "Rolling back database from: $backup_file"

    # Stop application
    log_info "Stopping application..."
    pm2 stop onomancer-bot || true

    # Backup current database (before rollback)
    local current_db="$DATA_DIR/onomancer.db"
    if [[ -f "$current_db" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local pre_rollback_backup="$BACKUP_DIR/onomancer_pre_rollback_${timestamp}.db"
        cp "$current_db" "$pre_rollback_backup"
        log_info "Current database backed up to: $pre_rollback_backup"
    fi

    # Restore backup
    cp "$backup_file" "$current_db"
    log_success "Database restored from backup"

    # Restart application
    log_info "Restarting application..."
    pm2 start onomancer-bot
}

# Rollback code
rollback_code() {
    local version="$1"

    if [[ ! -d "$BASE_DIR/.git" ]]; then
        log_error "Not a git repository. Cannot rollback code."
    fi

    cd "$BASE_DIR"

    log_info "Rolling back code to: $version"

    # Stop application
    log_info "Stopping application..."
    pm2 stop onomancer-bot || true

    # Stash any local changes
    git stash || true

    # Checkout version
    git fetch --all --tags
    git checkout "$version"

    # Rebuild
    log_info "Rebuilding application..."
    npm ci --production=false
    npm run build

    # Restart application
    log_info "Restarting application..."
    pm2 start onomancer-bot

    log_success "Code rolled back to: $version"
}

# Interactive rollback selection
interactive_rollback() {
    echo ""
    echo "========================================"
    echo "  Rollback Selection"
    echo "========================================"
    echo ""

    # List database backups
    local backups=()
    if ls "$BACKUP_DIR"/onomancer_*.db 1> /dev/null 2>&1; then
        while IFS= read -r -d $'\0' backup; do
            backups+=("$backup")
        done < <(find "$BACKUP_DIR" -name "onomancer_*.db" -print0 | sort -rz)
    fi

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warn "No database backups found"
        return
    fi

    echo "Available database backups:"
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  [$i] $(basename "$backup") ($size, $date)"
    done
    echo ""

    read -p "Select backup number to restore (or 'q' to quit): " selection

    if [[ "$selection" = "q" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ $selection -ge ${#backups[@]} ]]; then
        log_error "Invalid selection"
    fi

    local selected_backup="${backups[$selection]}"

    if [[ "$CONFIRM" = false ]]; then
        echo ""
        read -p "Are you sure you want to rollback to $(basename "$selected_backup")? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi

    rollback_database "$selected_backup"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list)
            LIST_ONLY=true
            shift
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --code)
            CODE_VERSION="$2"
            shift 2
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            # Check if it's a backup file path
            if [[ -f "$1" ]]; then
                rollback_database "$1"
                exit 0
            fi
            log_error "Unknown option: $1. Use --help for usage."
            ;;
    esac
done

# Main logic
main() {
    cd "$BASE_DIR"

    if [[ "$LIST_ONLY" = true ]]; then
        list_rollback_points
        exit 0
    fi

    if [[ -n "$CODE_VERSION" ]]; then
        if [[ "$CONFIRM" = false ]]; then
            echo ""
            read -p "Are you sure you want to rollback code to $CODE_VERSION? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_info "Rollback cancelled"
                exit 0
            fi
        fi
        rollback_code "$CODE_VERSION"
        exit 0
    fi

    # Interactive mode
    interactive_rollback
}

main
