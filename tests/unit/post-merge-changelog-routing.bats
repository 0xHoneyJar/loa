#!/usr/bin/env bats
# =============================================================================
# Unit tests for post-merge-orchestrator.sh::phase_changelog routing — issue #697 Defect 2
#
# sprint-bug-139 (cycle-098 follow-up). Verifies multi-changelog detection +
# path-domain routing.
#
# Pre-fix: orchestrator hard-codes the target as `${PROJECT_ROOT}/CHANGELOG.md`
# and runs `git log` without a pathspec — every commit (including upstream
# framework merges) lands in the project's CHANGELOG.md, leaking framework
# cycles into project history.
#
# Post-fix: when sibling `*-CHANGELOG.md` files exist, the orchestrator
# partitions the diff by `.claude/**` (framework) vs everything else
# (project) and routes commits into whichever changelog matches the domain.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-merge-cl-test-$$"
    mkdir -p "$TEST_TMPDIR"

    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    mkdir -p "$TEST_REPO/.run"
    mkdir -p "$TEST_REPO/backend"

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

# Helper: scaffold a tmp repo with TWO changelogs + framework-only and
# project-only commits between v1.0.0 and HEAD.
_setup_dual_changelog_repo() {
    cat > "$TEST_REPO/CHANGELOG.md" <<'CL'
# Changelog

All notable changes to Loa.
CL

    cat > "$TEST_REPO/PROJECT-CHANGELOG.md" <<'PCL'
# Project Changelog

All notable changes to the project.
PCL

    git -C "$TEST_REPO" add CHANGELOG.md PROJECT-CHANGELOG.md
    git -C "$TEST_REPO" commit -m "initial: dual changelog setup" --quiet
    git -C "$TEST_REPO" tag -a v1.0.0 -m "v1.0.0"

    # A framework-zone commit (touches .claude/).
    echo "framework-change" > "$TEST_REPO/.claude/scripts/some-fw.sh"
    git -C "$TEST_REPO" add .claude/scripts/some-fw.sh
    git -C "$TEST_REPO" commit -m "feat(framework): pretend upstream change" --quiet

    # A project-zone commit (touches backend/).
    echo "project-change" > "$TEST_REPO/backend/foo.txt"
    git -C "$TEST_REPO" add backend/foo.txt
    git -C "$TEST_REPO" commit -m "feat(backend): real project work" --quiet

    MERGE_SHA=$(git -C "$TEST_REPO" rev-parse HEAD)
}

# -----------------------------------------------------------------------------
# Pre-fix this FAILS: orchestrator routes both commits into CHANGELOG.md.
# Post-fix: framework-zone commit → CHANGELOG.md; project-zone → PROJECT-CHANGELOG.md.
# -----------------------------------------------------------------------------
@test "phase_changelog: framework commits route to framework changelog when sibling project changelog exists" {
    skip_if_deps_missing
    _setup_dual_changelog_repo

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]

    # Framework changelog should have an entry mentioning the framework commit.
    grep -q "pretend upstream change" "$TEST_REPO/CHANGELOG.md" || {
        echo "Framework commit missing from CHANGELOG.md"
        echo "--- CHANGELOG.md ---"
        cat "$TEST_REPO/CHANGELOG.md"
        return 1
    }
}

@test "phase_changelog: project commits route to project changelog (NOT framework changelog)" {
    skip_if_deps_missing
    _setup_dual_changelog_repo

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]

    # Project changelog should contain the backend commit.
    grep -q "real project work" "$TEST_REPO/PROJECT-CHANGELOG.md" || {
        echo "Project commit missing from PROJECT-CHANGELOG.md"
        echo "--- PROJECT-CHANGELOG.md ---"
        cat "$TEST_REPO/PROJECT-CHANGELOG.md"
        return 1
    }

    # Framework changelog must NOT contain the project commit.
    if grep -q "real project work" "$TEST_REPO/CHANGELOG.md"; then
        echo "ERROR: project commit leaked into framework CHANGELOG.md"
        cat "$TEST_REPO/CHANGELOG.md"
        return 1
    fi
}

@test "phase_changelog: project changelog does NOT contain framework commits" {
    skip_if_deps_missing
    _setup_dual_changelog_repo

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]

    # PROJECT-CHANGELOG.md must NOT mention the framework commit.
    if grep -q "pretend upstream change" "$TEST_REPO/PROJECT-CHANGELOG.md"; then
        echo "ERROR: framework commit leaked into project changelog"
        cat "$TEST_REPO/PROJECT-CHANGELOG.md"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Backward compat: single-changelog repos (Loa upstream itself) keep working.
# -----------------------------------------------------------------------------
@test "phase_changelog: single-changelog repo behavior unchanged (backward compat)" {
    skip_if_deps_missing

    cat > "$TEST_REPO/CHANGELOG.md" <<'CL'
# Changelog

All notable changes.
CL
    git -C "$TEST_REPO" add CHANGELOG.md
    git -C "$TEST_REPO" commit -m "init" --quiet
    git -C "$TEST_REPO" tag -a v1.0.0 -m "v1.0.0"

    echo "x" > "$TEST_REPO/x.txt"
    git -C "$TEST_REPO" add x.txt
    git -C "$TEST_REPO" commit -m "feat(api): single-changelog feature" --quiet
    MERGE_SHA=$(git -C "$TEST_REPO" rev-parse HEAD)

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]

    # Single changelog still receives the entry.
    grep -q "single-changelog feature" "$TEST_REPO/CHANGELOG.md" || {
        echo "Single-changelog backward-compat regression"
        cat "$TEST_REPO/CHANGELOG.md"
        return 1
    }
}
