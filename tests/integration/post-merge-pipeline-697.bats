#!/usr/bin/env bats
# =============================================================================
# Integration tests for post-merge pipeline — issue #697 E2E
#
# sprint-bug-139 (cycle-098 follow-up). Replays the cycle-105.5 ship scenario
# from the AITOBIAS04/echelon-core feedback report.
#
# Scenario:
# - Downstream repo has TWO changelogs: CHANGELOG.md (framework) +
#   ECHELON-CHANGELOG.md (project)
# - Repo has prior history with framework-zone commits (.claude/**) AND
#   project-zone commits (backend/**)
# - PR being merged is project-only (no .claude/ files touched in this commit
#   range)
# - Repo has grimoires/loa/reality/ populated (consumer of /ride)
#
# Expected post-fix behavior:
#   - gt_regen phase: completed (or gracefully skipped) — never `failed`
#   - CHANGELOG.md: receives only framework-zone commits (or nothing)
#   - ECHELON-CHANGELOG.md: receives the project-zone commits
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-merge-int-697-$$"
    mkdir -p "$TEST_TMPDIR"

    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    mkdir -p "$TEST_REPO/.run"
    mkdir -p "$TEST_REPO/backend"
    mkdir -p "$TEST_REPO/grimoires/loa/reality"

    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    cp "$PROJECT_ROOT_REAL/.claude/scripts/bootstrap.sh"          "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/path-lib.sh"           "$TEST_REPO/.claude/scripts/" 2>/dev/null || true
    cp "$PROJECT_ROOT_REAL/.claude/scripts/post-merge-orchestrator.sh" "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/semver-bump.sh"        "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/release-notes-gen.sh"  "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/classify-pr-type.sh"   "$TEST_REPO/.claude/scripts/" 2>/dev/null || true
    cp "$PROJECT_ROOT_REAL/.claude/scripts/classify-commit-zone.sh" "$TEST_REPO/.claude/scripts/" 2>/dev/null || true

    # Stub ground-truth-gen.sh so we can verify Defect 1 fix end-to-end.
    export GT_ARGV_LOG="$TEST_TMPDIR/gt-argv.log"
    cat > "$TEST_REPO/.claude/scripts/ground-truth-gen.sh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GT_ARGV_LOG:-/dev/null}"
has_output_dir=0
has_reality_dir=0
for arg in "$@"; do
    case "$arg" in
        --output-dir)  has_output_dir=1 ;;
        --reality-dir) has_reality_dir=1 ;;
    esac
done
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

    # Reality dir + index (so phase_gt_regen does not skip).
    echo "{}" > "$TEST_REPO/grimoires/loa/reality/index.md"

    # Two changelogs (the cycle-105.5 layout).
    cat > "$TEST_REPO/CHANGELOG.md" <<'CL'
# Changelog

All notable changes to Loa (framework-only).
CL
    cat > "$TEST_REPO/ECHELON-CHANGELOG.md" <<'PCL'
# Echelon Changelog

All notable Echelon project changes.
PCL

    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -m "initial: dual-changelog scaffold" --quiet
    git -C "$TEST_REPO" tag -a v1.0.0 -m "v1.0.0"

    # Simulate prior framework-zone commit (e.g., from upstream merge).
    echo "fw" > "$TEST_REPO/.claude/scripts/fw-helper.sh"
    git -C "$TEST_REPO" add .claude/scripts/fw-helper.sh
    git -C "$TEST_REPO" commit -m "feat(framework): pretend upstream cycle-027" --quiet

    # Project-zone commit (the one being released).
    echo "be" > "$TEST_REPO/backend/router.go"
    git -C "$TEST_REPO" add backend/router.go
    git -C "$TEST_REPO" commit -m "feat(backend): cycle-105.5 project work" --quiet

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
# E2E: cycle-105.5 scenario — both defects must be cleared.
# -----------------------------------------------------------------------------
@test "i697-e2e: gt_regen phase no longer fails (Defect 1 fixed)" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 114 --type cycle --sha "$MERGE_SHA" --skip-rtfm

    local gt_status
    gt_status=$(jq -r '.phases.gt_regen.status' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$gt_status" == "completed" || "$gt_status" == "skipped" ]] || {
        echo "Expected gt_regen completed/skipped, got: $gt_status"
        cat "$TEST_REPO/.run/post-merge-state.json" | jq '.phases.gt_regen, .errors'
        return 1
    }
}

@test "i697-e2e: project-zone commits route to project changelog (Defect 2 fixed)" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 114 --type cycle --sha "$MERGE_SHA" --skip-rtfm

    grep -q "cycle-105.5 project work" "$TEST_REPO/ECHELON-CHANGELOG.md" || {
        echo "Project commit missing from ECHELON-CHANGELOG.md"
        echo "--- ECHELON-CHANGELOG.md ---"
        cat "$TEST_REPO/ECHELON-CHANGELOG.md"
        echo "--- CHANGELOG.md ---"
        cat "$TEST_REPO/CHANGELOG.md"
        return 1
    }
}

@test "i697-e2e: framework CHANGELOG.md does NOT receive project-only commits" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 114 --type cycle --sha "$MERGE_SHA" --skip-rtfm

    if grep -q "cycle-105.5 project work" "$TEST_REPO/CHANGELOG.md"; then
        echo "ERROR: project-zone commit leaked into framework CHANGELOG.md"
        cat "$TEST_REPO/CHANGELOG.md"
        return 1
    fi
}
