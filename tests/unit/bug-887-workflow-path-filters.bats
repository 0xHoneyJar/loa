#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-887-workflow-path-filters.bats
#
# Bug #887 — `cycle099-sprint-1e-tests.yml` path filter was too narrow:
# it only fired on migrator paths, so live-schema defects in
# `.claude/defaults/model-config.yaml` (e.g., cycle-104 added `kind: cli`
# to entries without extending the schema — KF-006 recurrence) hid from
# main until BB caught them. The workflow appears "passing" on main only
# because it never runs.
#
# Fix: extend `pull_request.paths` AND `push.paths` to include
# `.claude/defaults/model-config.yaml`. Pin the invariant via yq lint
# so a future workflow edit can't silently drop it again.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    WORKFLOW="$PROJECT_ROOT/.github/workflows/cycle099-sprint-1e-tests.yml"
    export WORKFLOW
}

@test "bug-887-1: pull_request.paths includes .claude/defaults/model-config.yaml" {
    run yq eval '.on.pull_request.paths | contains([".claude/defaults/model-config.yaml"])' "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "bug-887-2: push.paths includes .claude/defaults/model-config.yaml" {
    run yq eval '.on.push.paths | contains([".claude/defaults/model-config.yaml"])' "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "bug-887-3: existing migrator paths are preserved in pull_request.paths (no accidental removals)" {
    # Spot-check that the original entries still appear in pull_request.paths.
    local existing_paths=(
        ".claude/scripts/lib/log-redactor.py"
        ".claude/scripts/lib/log-redactor.sh"
        ".claude/scripts/lib/model-config-migrate.py"
        ".claude/data/schemas/model-config-v2.schema.json"
        "tests/integration/migrate-model-config.bats"
    )
    for p in "${existing_paths[@]}"; do
        run yq eval ".on.pull_request.paths | contains([\"$p\"])" "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
    done
}

@test "bug-887-3b: existing migrator paths are preserved in push.paths (closes #917 MEDIUM-1 — asymmetric-coverage gap)" {
    # BB #917 review (MEDIUM-1, 0.95 conf): the original defect class — a
    # path silently absent from one trigger — could recur on the push
    # trigger without bug-887-3 catching it. This test mirrors bug-887-3
    # against `push.paths` to close that asymmetry.
    local existing_paths=(
        ".claude/scripts/lib/log-redactor.py"
        ".claude/scripts/lib/log-redactor.sh"
        ".claude/scripts/lib/model-config-migrate.py"
        ".claude/data/schemas/model-config-v2.schema.json"
        "tests/integration/migrate-model-config.bats"
    )
    for p in "${existing_paths[@]}"; do
        run yq eval ".on.push.paths | contains([\"$p\"])" "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
    done
}

@test "bug-887-4: workflow YAML is structurally valid (yq parses without error)" {
    run yq eval '.' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "bug-887-5-source: workflow references bug-887 / KF-006 in the rationale comment" {
    grep -qE 'bug-887|KF-006' "$WORKFLOW"
}

@test "bug-887-6: parity — pull_request.paths and push.paths have the same model-config-yaml entry count" {
    pr_count=$(yq eval '[.on.pull_request.paths[] | select(. == ".claude/defaults/model-config.yaml")] | length' "$WORKFLOW")
    push_count=$(yq eval '[.on.push.paths[] | select(. == ".claude/defaults/model-config.yaml")] | length' "$WORKFLOW")
    [ "$pr_count" = "1" ]
    [ "$push_count" = "1" ]
}
