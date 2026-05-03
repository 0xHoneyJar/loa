#!/usr/bin/env bats
# =============================================================================
# Unit tests for post-merge-orchestrator.sh::phase_gt_regen — issue #697 Defect 1
#
# sprint-bug-139 (cycle-098 follow-up). Verifies that the orchestrator passes
# the required --reality-dir AND --output-dir flags to ground-truth-gen.sh.
# Pre-fix: orchestrator calls `--mode checksums 2>/dev/null` only; the real
# script exits 2 with "ERROR: --reality-dir is required for checksums mode";
# the `2>/dev/null` swallows the diagnostic. Result: gt_regen has been
# silently failing on every cycle ship since the script's flag requirement
# was introduced.
#
# Test strategy: PATH-shadow `ground-truth-gen.sh` with a stub that captures
# argv to a file and exits non-zero if the required flags are missing.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-merge-gt-test-$$"
    mkdir -p "$TEST_TMPDIR"

    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    mkdir -p "$TEST_REPO/.run"

    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    # Copy required scripts.
    cp "$PROJECT_ROOT_REAL/.claude/scripts/bootstrap.sh"          "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/path-lib.sh"           "$TEST_REPO/.claude/scripts/" 2>/dev/null || true
    cp "$PROJECT_ROOT_REAL/.claude/scripts/post-merge-orchestrator.sh" "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/semver-bump.sh"        "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/release-notes-gen.sh"  "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/classify-pr-type.sh"   "$TEST_REPO/.claude/scripts/" 2>/dev/null || true
    cp "$PROJECT_ROOT_REAL/.claude/scripts/classify-commit-zone.sh" "$TEST_REPO/.claude/scripts/" 2>/dev/null || true

    # Stub ground-truth-gen.sh: captures argv, asserts required flags, exits 0.
    # Pre-fix orchestrator omits --output-dir + --reality-dir → stub exits 64.
    # Post-fix orchestrator passes both → stub exits 0.
    export GT_ARGV_LOG="$TEST_TMPDIR/gt-argv.log"
    cat > "$TEST_REPO/.claude/scripts/ground-truth-gen.sh" <<'STUB'
#!/usr/bin/env bash
# Test stub: ground-truth-gen.sh. Captures argv + asserts flags.
echo "$*" >> "${GT_ARGV_LOG:-/dev/null}"
has_output_dir=0
has_reality_dir=0
mode=""
i=1
for arg in "$@"; do
    case "$arg" in
        --output-dir)  has_output_dir=1 ;;
        --reality-dir) has_reality_dir=1 ;;
        --mode) ;;
        checksums|scaffold|validate|all)
            # value-of-mode (or any positional)
            mode="$arg"
            ;;
    esac
done
# Mirror real script's flag requirements: checksums mode needs both flags.
if [[ "$has_output_dir" -eq 0 ]]; then
    echo "ERROR: --output-dir is required for checksums mode" >&2
    exit 64
fi
if [[ "$has_reality_dir" -eq 0 ]]; then
    echo "ERROR: --reality-dir is required for checksums mode" >&2
    exit 64
fi
exit 0
STUB
    chmod +x "$TEST_REPO/.claude/scripts/ground-truth-gen.sh"

    # Set up a reality dir so gt_regen does not graceful-skip.
    mkdir -p "$TEST_REPO/grimoires/loa/reality"
    echo "{}" > "$TEST_REPO/grimoires/loa/reality/index.md"

    # Initial commit + tag so semver can bump.
    echo "init" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add README.md grimoires
    git -C "$TEST_REPO" commit -m "initial" --quiet
    git -C "$TEST_REPO" tag -a v1.0.0 -m "v1.0.0"

    # Add a feat commit so semver produces a new version.
    echo "feature" > "$TEST_REPO/feat.txt"
    git -C "$TEST_REPO" add feat.txt
    git -C "$TEST_REPO" commit -m "feat: new feature" --quiet
    MERGE_SHA=$(git -C "$TEST_REPO" rev-parse HEAD)

    export PROJECT_ROOT="$TEST_REPO"
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/post-merge-orchestrator.sh"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# -----------------------------------------------------------------------------
# Pre-fix this test FAILS: orchestrator omits --output-dir and --reality-dir.
# Post-fix: both flags present → stub exits 0 → phase completes.
# -----------------------------------------------------------------------------
@test "phase_gt_regen: passes --output-dir to ground-truth-gen.sh" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-rtfm
    [ -f "$TEST_REPO/.run/post-merge-state.json" ]

    local gt_status
    gt_status=$(jq -r '.phases.gt_regen.status' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$gt_status" == "completed" ]] || {
        echo "Expected gt_regen completed, got: $gt_status"
        echo "argv captured: $(cat "$GT_ARGV_LOG" 2>/dev/null || echo '(empty)')"
        echo "result: $(jq '.phases.gt_regen' "$TEST_REPO/.run/post-merge-state.json")"
        return 1
    }

    [[ -f "$GT_ARGV_LOG" ]]
    grep -q -- '--output-dir' "$GT_ARGV_LOG" || {
        echo "Expected --output-dir in argv, got: $(cat "$GT_ARGV_LOG")"
        return 1
    }
}

@test "phase_gt_regen: passes --reality-dir to ground-truth-gen.sh" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-rtfm
    [ -f "$GT_ARGV_LOG" ]
    grep -q -- '--reality-dir' "$GT_ARGV_LOG"
}

@test "phase_gt_regen: gracefully skips when reality dir is missing" {
    skip_if_deps_missing
    rm -rf "$TEST_REPO/grimoires/loa/reality"
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-rtfm

    local gt_status
    gt_status=$(jq -r '.phases.gt_regen.status' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$gt_status" == "skipped" ]] || {
        echo "Expected skipped when reality dir absent, got: $gt_status"
        echo "result: $(jq '.phases.gt_regen' "$TEST_REPO/.run/post-merge-state.json")"
        return 1
    }

    local reason
    reason=$(jq -r '.phases.gt_regen.result.reason // empty' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$reason" == *"reality"* ]]
}

@test "phase_gt_regen: surfaces stderr from ground-truth-gen.sh on failure" {
    skip_if_deps_missing
    # Replace stub with one that writes a recognizable error to stderr and exits 1.
    cat > "$TEST_REPO/.claude/scripts/ground-truth-gen.sh" <<'STUB'
#!/usr/bin/env bash
echo "GT_FAILURE_DIAGNOSTIC_MARKER" >&2
exit 1
STUB
    chmod +x "$TEST_REPO/.claude/scripts/ground-truth-gen.sh"

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-rtfm

    # The phase failure should be recorded.
    local gt_status
    gt_status=$(jq -r '.phases.gt_regen.status' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$gt_status" == "failed" ]]

    # The orchestrator must surface the underlying stderr in the errors array
    # (post-fix removes 2>/dev/null swallowing).
    local err_blob
    err_blob=$(jq -r '.errors[] | select(.phase == "gt_regen") | .message' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$err_blob" == *"GT_FAILURE_DIAGNOSTIC_MARKER"* ]] || {
        echo "Expected stderr marker in errors[]; got: $err_blob"
        return 1
    }
}
