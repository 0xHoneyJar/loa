#!/usr/bin/env bats
# =============================================================================
# mount-workflow-scaffold.bats — Tests for scaffold_post_merge_workflow (#669)
# =============================================================================
# sprint-bug-130. Validates that mount installs a runnable
# .github/workflows/post-merge.yml in the consumer repo and that the
# scaffolded file includes `submodules: recursive` on actions/checkout
# (required for the submodule-install mode where .claude/scripts/* are
# symlinks into the submodule).
#
# Pattern mirrors tests/unit/mount-clean.bats: function under test is
# defined inline in setup so the bats can run in isolation without
# sourcing mount-loa.sh / mount-submodule.sh (which have main "$@"
# guards that side-effect on source).

setup() {
    TEST_DIR="$(mktemp -d)"
    export TARGET_DIR="$TEST_DIR"

    # Fixture upstream workflow file — represents what `git checkout
    # $REMOTE/$BRANCH -- .github/workflows/post-merge.yml` would produce
    # OR what a submodule mode mount would copy from $SUBMODULE_PATH.
    FIXTURE_DIR="$TEST_DIR/_upstream"
    mkdir -p "$FIXTURE_DIR/.github/workflows"
    cat > "$FIXTURE_DIR/.github/workflows/post-merge.yml" <<'YAML'
name: Post-Merge Pipeline
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  classify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          fetch-depth: 0
          submodules: recursive
      - name: Classify
        run: .claude/scripts/classify-merge-pr.sh --merge-sha "$MERGE_SHA"
YAML

    cd "$TEST_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# Function under test — keep in sync with mount-loa.sh / mount-submodule.sh
# implementations. The shape is intentionally minimal: one source-aware
# helper, idempotent, mode-agnostic.
# =============================================================================
scaffold_post_merge_workflow() {
    local source_path="${1:-}"
    local target=".github/workflows/post-merge.yml"

    if [[ -f "$target" ]]; then
        return 0
    fi

    mkdir -p .github/workflows

    if [[ -n "$source_path" && -f "$source_path" ]]; then
        cp "$source_path" "$target"
        return 0
    fi

    # Fallback: not provided + no git remote → graceful no-op (caller logs)
    return 0
}

# =========================================================================
# MWS-T1..T2: idempotency (preserve user customization)
# =========================================================================

@test "MWS-T1: writes target when absent + valid source" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    [ -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

@test "MWS-T2: preserves existing target (idempotency)" {
    mkdir -p .github/workflows
    echo "# user-customized workflow" > .github/workflows/post-merge.yml
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    run cat .github/workflows/post-merge.yml
    [ "$output" = "# user-customized workflow" ]
}

# =========================================================================
# MWS-T3..T5: structural validity of the scaffolded YAML
# =========================================================================

@test "MWS-T3: scaffolded workflow names a workflow and triggers on push to main" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    run grep -E "^name:" "$TEST_DIR/.github/workflows/post-merge.yml"
    [ "$status" -eq 0 ]
    run grep -E "branches:.*\[main\]|branches: \[ main \]" "$TEST_DIR/.github/workflows/post-merge.yml"
    [ "$status" -eq 0 ]
}

@test "MWS-T4: scaffolded workflow references classify-merge-pr.sh OR post-merge-orchestrator.sh" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    grep -qE "(classify-merge-pr|post-merge-orchestrator)\.sh" "$TEST_DIR/.github/workflows/post-merge.yml"
}

@test "MWS-T5: scaffolded workflow includes submodules: recursive on actions/checkout (#669 symlink fix)" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    grep -qE "submodules:\s*recursive" "$TEST_DIR/.github/workflows/post-merge.yml"
}

# =========================================================================
# MWS-T6: empty source path → graceful no-op (mount-loa.sh git fallback path)
# =========================================================================

@test "MWS-T6: empty source path → no file written, no error" {
    scaffold_post_merge_workflow ""
    [ ! -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

# =========================================================================
# MWS-T7: nonexistent source path → graceful no-op
# =========================================================================

@test "MWS-T7: nonexistent source path → no file written, no error" {
    scaffold_post_merge_workflow "$TEST_DIR/_does_not_exist/post-merge.yml"
    [ ! -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

# =========================================================================
# MWS-T8: live source-of-truth — repo's actual upstream workflow
# (validates the submodules: recursive change to post-merge.yml landed)
# =========================================================================

@test "MWS-T8: repo's .github/workflows/post-merge.yml has submodules: recursive on every actions/checkout" {
    local upstream_workflow="$BATS_TEST_DIRNAME/../../.github/workflows/post-merge.yml"
    [ -f "$upstream_workflow" ]
    # Count actions/checkout invocations and submodules: recursive entries
    local checkout_count submodules_count
    checkout_count=$(grep -cE "uses:\s*actions/checkout" "$upstream_workflow" || echo 0)
    submodules_count=$(grep -cE "submodules:\s*recursive" "$upstream_workflow" || echo 0)
    # Every checkout must have a matching submodules: recursive
    [ "$checkout_count" -gt 0 ]
    [ "$submodules_count" -ge "$checkout_count" ]
}

# =========================================================================
# MWS-T9: mount-loa.sh defines scaffold_post_merge_workflow
# =========================================================================

@test "MWS-T9: mount-loa.sh defines scaffold_post_merge_workflow" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-loa.sh"
    grep -qE "^scaffold_post_merge_workflow\(\)" "$script"
}

# =========================================================================
# MWS-T10: mount-submodule.sh defines scaffold_post_merge_workflow
# =========================================================================

@test "MWS-T10: mount-submodule.sh defines scaffold_post_merge_workflow" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-submodule.sh"
    grep -qE "^scaffold_post_merge_workflow\(\)" "$script"
}
