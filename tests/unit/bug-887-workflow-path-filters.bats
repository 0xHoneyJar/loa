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
    # BB #917 BF-001 fix: existing_paths now includes the bats guard file
    # AND the workflow file itself, so a future workflow edit that drops
    # either self-reference (the meta-regression bug-887 was opened against)
    # fails THIS test, not just silently bypasses the workflow.
    local existing_paths=(
        ".claude/scripts/lib/log-redactor.py"
        ".claude/scripts/lib/log-redactor.sh"
        ".claude/scripts/lib/model-config-migrate.py"
        ".claude/data/schemas/model-config-v2.schema.json"
        "tests/integration/migrate-model-config.bats"
        "tests/unit/bug-887-workflow-path-filters.bats"
        ".github/workflows/cycle099-sprint-1e-tests.yml"
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
    # BB #917 BF-001 v4 fix: also mirror the self-reference paths added
    # to bug-887-3 above (bats file + workflow file).
    local existing_paths=(
        ".claude/scripts/lib/log-redactor.py"
        ".claude/scripts/lib/log-redactor.sh"
        ".claude/scripts/lib/model-config-migrate.py"
        ".claude/data/schemas/model-config-v2.schema.json"
        "tests/integration/migrate-model-config.bats"
        "tests/unit/bug-887-workflow-path-filters.bats"
        ".github/workflows/cycle099-sprint-1e-tests.yml"
    )
    for p in "${existing_paths[@]}"; do
        run yq eval ".on.push.paths | contains([\"$p\"])" "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
    done
}

@test "bug-887-3c: BF-001 / BF-001-dup — bats guard AND workflow are self-registered in BOTH triggers" {
    # BB #917 review (BF-001 + BF-001-dup, both MEDIUM): a CI workflow
    # that gates a path filter must include itself + its test in that
    # filter, on BOTH triggers. Without this assertion, a future edit
    # that drops the bats file or the workflow file from one trigger
    # would silently disable the guard — the exact meta-regression
    # bug-887 was opened to close. Pinned here so the relationship
    # outlives any header comment.
    local self_paths=(
        "tests/unit/bug-887-workflow-path-filters.bats"
        ".github/workflows/cycle099-sprint-1e-tests.yml"
    )
    for p in "${self_paths[@]}"; do
        # BB BF-002 fix: env-injected `p` decouples value from yq filter
        # expression (analogous to SQL parameterization). Defense-in-depth
        # against a future path string that contains yq-meaningful chars.
        run env p="$p" yq eval '.on.pull_request.paths | contains([env(p)])' "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
        run env p="$p" yq eval '.on.push.paths | contains([env(p)])' "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
    done
}

@test "bug-887-4: workflow YAML is structurally valid (yq parses without error)" {
    run yq eval '.' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "bug-887-5-source: workflow references BOTH bug-887 AND KF-006 in the rationale comment" {
    # BB #917 BF-002 (0.9 conf): the OR-predicate version of this test
    # exhibited "assertion erosion" (Google Testing Grouplet pattern) —
    # the contract requires BOTH ticket references (the bug and the
    # known-failure), but the OR-grep would have passed with only one.
    # Mutate to AND-predicate so a future cleanup that drops either
    # token fails the test loudly.
    # BB #917 BF-003 fix: wrap each grep with `run` so BATS captures
    # diagnostic output on failure (otherwise a missing token surfaces
    # only as a generic 'command failed' with no context).
    run grep -q 'bug-887' "$WORKFLOW"
    [ "$status" -eq 0 ]
    run grep -q 'KF-006' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "bug-887-6: parity — pull_request.paths and push.paths have the same model-config-yaml entry count" {
    pr_count=$(yq eval '[.on.pull_request.paths[] | select(. == ".claude/defaults/model-config.yaml")] | length' "$WORKFLOW")
    push_count=$(yq eval '[.on.push.paths[] | select(. == ".claude/defaults/model-config.yaml")] | length' "$WORKFLOW")
    [ "$pr_count" = "1" ]
    [ "$push_count" = "1" ]
}
