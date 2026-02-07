#!/usr/bin/env bash
# migrate-skill-names.sh
# Renames skill directories from role-based to gerund (action-based) naming
# Usage: ./migrate-skill-names.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# Name mapping: old -> new
declare -A NAME_MAP=(
    ["prd-architect"]="discovering-requirements"
    ["architecture-designer"]="designing-architecture"
    ["sprint-planner"]="planning-sprints"
    ["sprint-task-implementer"]="implementing-tasks"
    ["senior-tech-lead-reviewer"]="reviewing-code"
    ["paranoid-auditor"]="auditing-security"
    ["devops-crypto-architect"]="deploying-infrastructure"
    ["devrel-translator"]="translating-for-executives"
)

DRY_RUN=false
SKILLS_DIR=".claude/skills"
COMMANDS_DIR=".claude/commands"

log() {
    echo "[migrate] $1"
}

# Rename skill directories
rename_directories() {
    log "Renaming skill directories..."
    for old_name in "${!NAME_MAP[@]}"; do
        local new_name="${NAME_MAP[$old_name]}"
        local old_path="${SKILLS_DIR}/${old_name}"
        local new_path="${SKILLS_DIR}/${new_name}"

        if [ -d "$old_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                log "  [dry-run] mv $old_path -> $new_path"
            else
                mv "$old_path" "$new_path"
                log "  Renamed: $old_name -> $new_name"
            fi
        else
            log "  Skipped (not found): $old_path"
        fi
    done
}

# Update index.yaml name fields
update_index_yaml() {
    log "Updating index.yaml files..."
    for old_name in "${!NAME_MAP[@]}"; do
        local new_name="${NAME_MAP[$old_name]}"
        local yaml_file="${SKILLS_DIR}/${new_name}/index.yaml"

        if [ -f "$yaml_file" ]; then
            if [ "$DRY_RUN" = true ]; then
                log "  [dry-run] Update name in $yaml_file"
            else
                sed "s/^name: ${old_name}/name: ${new_name}/" "$yaml_file" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "$yaml_file"
                log "  Updated: $yaml_file"
            fi
        fi
    done
}

# Update command files (agent: and agent_path: fields)
update_commands() {
    log "Updating command files..."
    for cmd_file in "${COMMANDS_DIR}"/*.md; do
        if [ -f "$cmd_file" ]; then
            local updated=false
            for old_name in "${!NAME_MAP[@]}"; do
                local new_name="${NAME_MAP[$old_name]}"
                if grep -q "$old_name" "$cmd_file" 2>/dev/null; then
                    if [ "$DRY_RUN" = true ]; then
                        log "  [dry-run] Update $old_name -> $new_name in $(basename "$cmd_file")"
                    else
                        sed "s/${old_name}/${new_name}/g" "$cmd_file" > "${cmd_file}.tmp" && mv "${cmd_file}.tmp" "$cmd_file"
                        updated=true
                    fi
                fi
            done
            if [ "$updated" = true ]; then
                log "  Updated: $(basename "$cmd_file")"
            fi
        fi
    done
}

# Update context-check.sh agent thresholds
update_context_check() {
    local script_file=".claude/scripts/context-check.sh"
    if [ -f "$script_file" ]; then
        log "Updating context-check.sh..."
        for old_name in "${!NAME_MAP[@]}"; do
            local new_name="${NAME_MAP[$old_name]}"
            if grep -q "$old_name" "$script_file" 2>/dev/null; then
                if [ "$DRY_RUN" = true ]; then
                    log "  [dry-run] Update $old_name -> $new_name"
                else
                    sed "s/${old_name}/${new_name}/g" "$script_file" > "${script_file}.tmp" && mv "${script_file}.tmp" "$script_file"
                fi
            fi
        done
        if [ "$DRY_RUN" = false ]; then
            log "  Updated: $script_file"
        fi
    fi
}

# Update documentation files
update_docs() {
    log "Updating documentation..."
    for doc_file in CLAUDE.md PROCESS.md README.md; do
        if [ -f "$doc_file" ]; then
            local updated=false
            for old_name in "${!NAME_MAP[@]}"; do
                local new_name="${NAME_MAP[$old_name]}"
                if grep -q "$old_name" "$doc_file" 2>/dev/null; then
                    if [ "$DRY_RUN" = true ]; then
                        log "  [dry-run] Update $old_name -> $new_name in $doc_file"
                    else
                        sed "s/${old_name}/${new_name}/g" "$doc_file" > "${doc_file}.tmp" && mv "${doc_file}.tmp" "$doc_file"
                        updated=true
                    fi
                fi
            done
            if [ "$updated" = true ]; then
                log "  Updated: $doc_file"
            fi
        fi
    done
}

# Update protocol files
update_protocols() {
    log "Updating protocol files..."
    for proto_file in .claude/protocols/*.md; do
        if [ -f "$proto_file" ]; then
            local updated=false
            for old_name in "${!NAME_MAP[@]}"; do
                local new_name="${NAME_MAP[$old_name]}"
                if grep -q "$old_name" "$proto_file" 2>/dev/null; then
                    if [ "$DRY_RUN" = true ]; then
                        log "  [dry-run] Update $old_name -> $new_name in $(basename "$proto_file")"
                    else
                        sed "s/${old_name}/${new_name}/g" "$proto_file" > "${proto_file}.tmp" && mv "${proto_file}.tmp" "$proto_file"
                        updated=true
                    fi
                fi
            done
            if [ "$updated" = true ]; then
                log "  Updated: $(basename "$proto_file")"
            fi
        fi
    done
}

main() {
    # Parse arguments
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        log "Running in dry-run mode (no changes will be made)"
    fi

    log "Starting skill name migration..."
    log "Name mapping:"
    for old_name in "${!NAME_MAP[@]}"; do
        log "  $old_name -> ${NAME_MAP[$old_name]}"
    done
    echo

    rename_directories
    update_index_yaml
    update_commands
    update_context_check
    update_docs
    update_protocols

    echo
    if [ "$DRY_RUN" = true ]; then
        log "Dry run complete. Re-run without --dry-run to apply changes."
    else
        log "Migration complete!"
    fi
}

main "$@"
