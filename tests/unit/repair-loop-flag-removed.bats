#!/usr/bin/env bats
# cycle-124 Sprint 2 Task 2.4 (FR-7): the `repair_loop` config key and the
# CONF_REPAIR_LOOP variable are gone from the framework tree and both configs
# (PRD FR-7 success metric: the grep returns nothing).

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
}

@test "RL-1: no repair_loop key in .loa.config.yaml or the example" {
    ! grep -nE '^\s*repair_loop:' "$PROJECT_ROOT/.loa.config.yaml" "$PROJECT_ROOT/.loa.config.yaml.example"
}

@test "RL-2: the PRD AC-7.3 grep is empty — no repair_loop or CONF_REPAIR_LOOP under .claude/ or either config" {
    ! grep -rn 'repair_loop\|CONF_REPAIR_LOOP' "$PROJECT_ROOT/.claude" "$PROJECT_ROOT/.loa.config.yaml" "$PROJECT_ROOT/.loa.config.yaml.example"
}

@test "RL-3: no yq read of a repair_loop key under .claude/scripts" {
    ! grep -rn '\.repair_loop' "$PROJECT_ROOT/.claude/scripts"
}
