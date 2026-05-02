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

    # Bridgebuilder F2/F6 (PR #671): test exercises the REAL production
    # function via lib/scaffold-post-merge-workflow.sh. No more inline
    # fixture copy — drift between test and production is impossible
    # because they are now the same code.
    PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    # shellcheck source=../../.claude/scripts/lib/scaffold-post-merge-workflow.sh
    source "$PROJECT_ROOT/.claude/scripts/lib/scaffold-post-merge-workflow.sh"

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

    # Ensure the lib's git-checkout fallback is inert in the test environment
    unset LOA_REMOTE_NAME LOA_BRANCH

    cd "$TEST_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
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
    # Bridgebuilder F4 (PR #671): drop the redundant `|| echo 0` from grep -c.
    # `grep -cE` already prints 0 when no matches; the `|| true` keeps
    # bash strict-mode pipefail from aborting on empty results.
    local checkout_count submodules_count
    checkout_count=$(grep -cE "uses:\s*actions/checkout" "$upstream_workflow" || true)
    submodules_count=$(grep -cE "submodules:\s*recursive" "$upstream_workflow" || true)
    # Every checkout must have a matching submodules: recursive (3 of each
    # in the live workflow as of #669)
    [ "$checkout_count" -gt 0 ]
    [ "$submodules_count" -ge "$checkout_count" ]
}

# =========================================================================
# MWS-T9: mount-loa.sh sources the canonical scaffold lib
# =========================================================================

@test "MWS-T9: mount-loa.sh sources scaffold-post-merge-workflow lib" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-loa.sh"
    grep -qE "scaffold-post-merge-workflow\.sh" "$script"
}

# =========================================================================
# MWS-T10: mount-submodule.sh sources the canonical scaffold lib
# =========================================================================

@test "MWS-T10: mount-submodule.sh sources scaffold-post-merge-workflow lib" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-submodule.sh"
    grep -qE "scaffold-post-merge-workflow\.sh" "$script"
}

# =========================================================================
# MWS-T11: lib is the single source of truth (no inline defs in installers)
# Bridgebuilder F2/F6 (PR #671): drift between test and prod is impossible
# when both source the same lib. Verify no inline scaffold_post_merge_workflow()
# function definition remains in either installer (would shadow the lib).
# =========================================================================

@test "MWS-T11: no inline scaffold_post_merge_workflow body in mount-loa.sh" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-loa.sh"
    # Allow comment references to the function name; reject standalone definitions
    ! grep -qE "^scaffold_post_merge_workflow\(\)\s*\{" "$script"
}

@test "MWS-T12: no inline scaffold_post_merge_workflow body in mount-submodule.sh" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-submodule.sh"
    ! grep -qE "^scaffold_post_merge_workflow\(\)\s*\{" "$script"
}
