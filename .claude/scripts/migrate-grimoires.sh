#!/usr/bin/env bash
# migrate-grimoires.sh - Migration tool for grimoires restructure (v0.12.0)
#
# Migrates from legacy loa-grimoire/ path to new grimoires/loa/ structure
#
# Usage:
#   migrate-grimoires.sh check      # Check if migration needed
#   migrate-grimoires.sh plan       # Show migration plan (dry-run)
#   migrate-grimoires.sh run        # Execute migration
#   migrate-grimoires.sh rollback   # Rollback migration (if backup exists)
#   migrate-grimoires.sh status     # Show current grimoire status
#
# Options:
#   --force                         # Skip confirmation prompts
#   --no-backup                     # Skip backup creation (not recommended)
#   --json                          # Output in JSON format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
LEGACY_PATH="loa-grimoire"
NEW_PATH="grimoires/loa"
PUB_PATH="grimoires/pub"
BACKUP_DIR=".grimoire-migration-backup"
MIGRATION_MARKER=".grimoire-migration-complete"

# Flags
FORCE=false
NO_BACKUP=false
JSON_OUTPUT=false

# Parse flags
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) FORCE=true; shift ;;
            --no-backup) NO_BACKUP=true; shift ;;
            --json) JSON_OUTPUT=true; shift ;;
            *) shift ;;
        esac
    done
}

# Logging functions
log_info() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

log_success() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

log_warning() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

log_error() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${RED}✗${NC} $1" >&2
    fi
}

log_header() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}$1${NC}"
        echo "─────────────────────────────────────────"
    fi
}

# Check if migration is needed
check_migration_needed() {
    local needs_migration=false
    local reasons=()

    cd "$PROJECT_ROOT"

    # Check 1: Legacy directory exists
    if [[ -d "$LEGACY_PATH" ]]; then
        needs_migration=true
        reasons+=("Legacy directory '$LEGACY_PATH' exists")
    fi

    # Check 2: New directory doesn't exist
    if [[ ! -d "$NEW_PATH" ]]; then
        needs_migration=true
        reasons+=("New directory '$NEW_PATH' does not exist")
    fi

    # Check 3: Check for legacy references in user files
    if [[ -f ".loa.config.yaml" ]]; then
        local legacy_refs
        legacy_refs=$(grep -c "loa-grimoire" ".loa.config.yaml" 2>/dev/null) || legacy_refs=0
        if [[ "$legacy_refs" -gt 0 ]]; then
            needs_migration=true
            reasons+=("Found $legacy_refs legacy references in .loa.config.yaml")
        fi
    fi

    # Check 4: Migration marker
    if [[ -f "$MIGRATION_MARKER" ]]; then
        needs_migration=false
        reasons=("Migration already completed (marker file exists)")
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local reasons_json="[]"
        if [[ ${#reasons[@]} -gt 0 ]]; then
            reasons_json=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)
        fi
        echo "{\"needs_migration\": $needs_migration, \"reasons\": $reasons_json}"
    else
        if [[ "$needs_migration" == "true" ]]; then
            log_warning "Migration needed"
            for reason in "${reasons[@]}"; do
                echo "  - $reason"
            done
            return 0
        else
            log_success "No migration needed"
            for reason in "${reasons[@]}"; do
                echo "  - $reason"
            done
            return 1
        fi
    fi
}

# Show current status
show_status() {
    cd "$PROJECT_ROOT"

    log_header "Grimoire Status"

    # Legacy path
    if [[ -d "$LEGACY_PATH" ]]; then
        local legacy_files=$(find "$LEGACY_PATH" -type f 2>/dev/null | wc -l)
        echo -e "Legacy path:  ${YELLOW}$LEGACY_PATH${NC} (exists, $legacy_files files)"
    else
        echo -e "Legacy path:  ${GREEN}$LEGACY_PATH${NC} (not present)"
    fi

    # New path
    if [[ -d "$NEW_PATH" ]]; then
        local new_files=$(find "$NEW_PATH" -type f 2>/dev/null | wc -l)
        echo -e "New path:     ${GREEN}$NEW_PATH${NC} (exists, $new_files files)"
    else
        echo -e "New path:     ${YELLOW}$NEW_PATH${NC} (not present)"
    fi

    # Pub path
    if [[ -d "$PUB_PATH" ]]; then
        local pub_files=$(find "$PUB_PATH" -type f 2>/dev/null | wc -l)
        echo -e "Public path:  ${GREEN}$PUB_PATH${NC} (exists, $pub_files files)"
    else
        echo -e "Public path:  ${YELLOW}$PUB_PATH${NC} (not present)"
    fi

    # Migration marker
    if [[ -f "$MIGRATION_MARKER" ]]; then
        local migration_date=$(cat "$MIGRATION_MARKER" 2>/dev/null || echo "unknown")
        echo -e "Migration:    ${GREEN}Complete${NC} ($migration_date)"
    else
        echo -e "Migration:    ${YELLOW}Not performed${NC}"
    fi

    # Backup
    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "Backup:       ${GREEN}Available${NC} at $BACKUP_DIR"
    else
        echo -e "Backup:       ${BLUE}None${NC}"
    fi

    echo ""
}

# Generate migration plan
generate_plan() {
    cd "$PROJECT_ROOT"

    log_header "Migration Plan"

    local actions=()
    local file_count=0

    # Action 1: Create new directory structure
    if [[ ! -d "grimoires" ]]; then
        actions+=("CREATE directory: grimoires/")
    fi
    if [[ ! -d "$NEW_PATH" ]]; then
        actions+=("CREATE directory: $NEW_PATH")
    fi
    if [[ ! -d "$PUB_PATH" ]]; then
        actions+=("CREATE directory: $PUB_PATH")
    fi

    # Action 2: Move legacy content
    if [[ -d "$LEGACY_PATH" ]]; then
        file_count=$(find "$LEGACY_PATH" -type f 2>/dev/null | wc -l)
        actions+=("MOVE $file_count files: $LEGACY_PATH/* → $NEW_PATH/")
        actions+=("REMOVE directory: $LEGACY_PATH")
    fi

    # Action 3: Update config files
    if [[ -f ".loa.config.yaml" ]]; then
        local refs=$(grep -c "loa-grimoire" ".loa.config.yaml" 2>/dev/null || echo "0")
        if [[ "$refs" -gt 0 ]]; then
            actions+=("UPDATE .loa.config.yaml: $refs path references")
        fi
    fi

    # Action 4: Update .gitignore if needed
    if [[ -f ".gitignore" ]]; then
        local gitignore_refs=$(grep -c "loa-grimoire" ".gitignore" 2>/dev/null || echo "0")
        if [[ "$gitignore_refs" -gt 0 ]]; then
            actions+=("UPDATE .gitignore: $gitignore_refs path references")
        fi
    fi

    # Action 5: Create pub grimoire READMEs
    if [[ ! -f "$PUB_PATH/README.md" ]]; then
        actions+=("CREATE $PUB_PATH/README.md")
        actions+=("CREATE $PUB_PATH/research/README.md")
        actions+=("CREATE $PUB_PATH/docs/README.md")
        actions+=("CREATE $PUB_PATH/artifacts/README.md")
    fi

    # Display plan
    if [[ ${#actions[@]} -eq 0 ]]; then
        log_success "No actions needed - already migrated"
        return 1
    fi

    echo "The following actions will be performed:"
    echo ""
    for action in "${actions[@]}"; do
        case "${action%%:*}" in
            CREATE) echo -e "  ${GREEN}+${NC} $action" ;;
            MOVE) echo -e "  ${BLUE}→${NC} $action" ;;
            UPDATE) echo -e "  ${YELLOW}~${NC} $action" ;;
            REMOVE) echo -e "  ${RED}-${NC} $action" ;;
            *) echo "  • $action" ;;
        esac
    done
    echo ""

    if [[ "$NO_BACKUP" != "true" ]]; then
        echo -e "A backup will be created at: ${CYAN}$BACKUP_DIR${NC}"
    else
        log_warning "Backup disabled (--no-backup)"
    fi

    return 0
}

# Create backup
create_backup() {
    cd "$PROJECT_ROOT"

    if [[ "$NO_BACKUP" == "true" ]]; then
        log_warning "Skipping backup (--no-backup)"
        return 0
    fi

    log_info "Creating backup..."

    # Remove old backup if exists
    if [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup legacy directory
    if [[ -d "$LEGACY_PATH" ]]; then
        cp -r "$LEGACY_PATH" "$BACKUP_DIR/"
        log_success "Backed up $LEGACY_PATH"
    fi

    # Backup config files
    for file in .loa.config.yaml .gitignore .loa-version.json; do
        if [[ -f "$file" ]]; then
            cp "$file" "$BACKUP_DIR/"
        fi
    done

    # Store backup metadata
    echo "$(date -Iseconds)" > "$BACKUP_DIR/.backup-timestamp"

    log_success "Backup created at $BACKUP_DIR"
}

# Execute migration
run_migration() {
    cd "$PROJECT_ROOT"

    log_header "Executing Migration"

    # Step 1: Create new directory structure
    log_info "Creating directory structure..."
    mkdir -p "$NEW_PATH"
    mkdir -p "$PUB_PATH/research"
    mkdir -p "$PUB_PATH/docs"
    mkdir -p "$PUB_PATH/artifacts"
    log_success "Created grimoires/ structure"

    # Step 2: Move legacy content
    if [[ -d "$LEGACY_PATH" ]]; then
        log_info "Moving legacy content..."

        # Move all contents
        if [[ -n "$(ls -A "$LEGACY_PATH" 2>/dev/null)" ]]; then
            cp -r "$LEGACY_PATH"/* "$NEW_PATH/" 2>/dev/null || true
            log_success "Copied content to $NEW_PATH"
        fi

        # Remove legacy directory
        rm -rf "$LEGACY_PATH"
        log_success "Removed legacy $LEGACY_PATH"
    fi

    # Step 3: Update config files
    if [[ -f ".loa.config.yaml" ]]; then
        if grep -q "loa-grimoire" ".loa.config.yaml" 2>/dev/null; then
            log_info "Updating .loa.config.yaml..."
            sed 's|loa-grimoire|grimoires/loa|g' ".loa.config.yaml" > ".loa.config.yaml.tmp" && mv ".loa.config.yaml.tmp" ".loa.config.yaml"
            log_success "Updated .loa.config.yaml"
        fi
    fi

    # Step 4: Update .gitignore
    if [[ -f ".gitignore" ]]; then
        if grep -q "loa-grimoire" ".gitignore" 2>/dev/null; then
            log_info "Updating .gitignore..."
            sed 's|loa-grimoire|grimoires/loa|g' ".gitignore" > ".gitignore.tmp" && mv ".gitignore.tmp" ".gitignore"
            log_success "Updated .gitignore"
        fi
    fi

    # Step 5: Create pub grimoire READMEs
    if [[ ! -f "$PUB_PATH/README.md" ]]; then
        log_info "Creating pub grimoire READMEs..."

        cat > "$PUB_PATH/README.md" << 'PUBREADME'
# Public Grimoire

Public documents from the Loa framework that are tracked in git.

## Purpose

| Directory | Git Status | Purpose |
|-----------|------------|---------|
| `grimoires/loa/` | Ignored | Project-specific state (PRD, SDD, notes, trajectories) |
| `grimoires/pub/` | Tracked | Public documents (research, shareable artifacts) |

## Directory Structure

```
grimoires/pub/
├── research/     # Research and analysis documents
├── docs/         # Shareable documentation
└── artifacts/    # Public build artifacts
```

## Usage

When creating documents, choose based on visibility:

- **Private/project-specific** → `grimoires/loa/`
- **Public/shareable** → `grimoires/pub/`
PUBREADME

        echo "# Research" > "$PUB_PATH/research/README.md"
        echo "" >> "$PUB_PATH/research/README.md"
        echo "Research and analysis documents." >> "$PUB_PATH/research/README.md"

        echo "# Documentation" > "$PUB_PATH/docs/README.md"
        echo "" >> "$PUB_PATH/docs/README.md"
        echo "Shareable documentation files." >> "$PUB_PATH/docs/README.md"

        echo "# Artifacts" > "$PUB_PATH/artifacts/README.md"
        echo "" >> "$PUB_PATH/artifacts/README.md"
        echo "Public build artifacts and exports." >> "$PUB_PATH/artifacts/README.md"

        log_success "Created pub grimoire structure"
    fi

    # Step 6: Create migration marker
    echo "$(date -Iseconds)" > "$MIGRATION_MARKER"
    log_success "Created migration marker"

    log_header "Migration Complete"
    echo ""
    echo "Your grimoires have been restructured:"
    echo "  • Private state: grimoires/loa/"
    echo "  • Public docs:   grimoires/pub/"
    echo ""
    echo "Next steps:"
    echo "  1. Review the migrated content"
    echo "  2. Update any custom scripts that reference loa-grimoire"
    echo "  3. Commit the changes: git add grimoires/ && git commit -m 'chore: migrate to grimoires structure'"
    echo ""

    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "Backup available at: ${CYAN}$BACKUP_DIR${NC}"
        echo "Run 'migrate-grimoires.sh rollback' to revert if needed"
    fi
}

# Rollback migration
rollback_migration() {
    cd "$PROJECT_ROOT"

    log_header "Rolling Back Migration"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "No backup found at $BACKUP_DIR"
        log_error "Cannot rollback without backup"
        exit 1
    fi

    # Confirm rollback
    if [[ "$FORCE" != "true" ]]; then
        echo "This will:"
        echo "  • Remove grimoires/ directory"
        echo "  • Restore $LEGACY_PATH from backup"
        echo "  • Restore config files from backup"
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi

    # Remove new structure
    if [[ -d "grimoires" ]]; then
        rm -rf "grimoires"
        log_success "Removed grimoires/"
    fi

    # Restore from backup
    if [[ -d "$BACKUP_DIR/$LEGACY_PATH" ]]; then
        cp -r "$BACKUP_DIR/$LEGACY_PATH" "./"
        log_success "Restored $LEGACY_PATH"
    fi

    # Restore config files
    for file in .loa.config.yaml .gitignore .loa-version.json; do
        if [[ -f "$BACKUP_DIR/$file" ]]; then
            cp "$BACKUP_DIR/$file" "./"
            log_success "Restored $file"
        fi
    done

    # Remove migration marker
    rm -f "$MIGRATION_MARKER"

    log_header "Rollback Complete"
    echo ""
    echo "Your project has been restored to the pre-migration state."
    echo ""
    echo -e "Backup preserved at: ${CYAN}$BACKUP_DIR${NC}"
    echo "You can remove it manually when ready: rm -rf $BACKUP_DIR"
}

# Main
main() {
    local command="${1:-help}"
    shift || true

    # Parse remaining flags
    parse_flags "$@"

    case "$command" in
        check)
            check_migration_needed
            ;;
        status)
            show_status
            ;;
        plan)
            if check_migration_needed > /dev/null 2>&1; then
                generate_plan
            else
                log_success "No migration needed"
            fi
            ;;
        run)
            # Check if migration needed
            if ! check_migration_needed > /dev/null 2>&1; then
                log_success "No migration needed - already using new structure"
                exit 0
            fi

            # Show plan
            generate_plan

            # Confirm
            if [[ "$FORCE" != "true" ]]; then
                echo ""
                read -p "Proceed with migration? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Migration cancelled"
                    exit 0
                fi
            fi

            # Create backup and run
            create_backup
            run_migration
            ;;
        rollback)
            rollback_migration
            ;;
        help|--help|-h)
            echo "migrate-grimoires.sh - Migration tool for grimoires restructure"
            echo ""
            echo "Usage: migrate-grimoires.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  check      Check if migration is needed"
            echo "  status     Show current grimoire status"
            echo "  plan       Show migration plan (dry-run)"
            echo "  run        Execute migration"
            echo "  rollback   Rollback migration (requires backup)"
            echo "  help       Show this help message"
            echo ""
            echo "Options:"
            echo "  --force      Skip confirmation prompts"
            echo "  --no-backup  Skip backup creation (not recommended)"
            echo "  --json       Output in JSON format (for check command)"
            echo ""
            echo "Examples:"
            echo "  migrate-grimoires.sh check          # Check if migration needed"
            echo "  migrate-grimoires.sh plan           # Preview what will change"
            echo "  migrate-grimoires.sh run            # Run migration interactively"
            echo "  migrate-grimoires.sh run --force    # Run without prompts"
            echo "  migrate-grimoires.sh rollback       # Undo migration"
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run 'migrate-grimoires.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
