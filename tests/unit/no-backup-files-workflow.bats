#!/usr/bin/env bats
# =============================================================================
# Unit tests for .github/workflows/no-backup-files.yml core check logic
#
# sprint-bug-141 / issue #681. The workflow's check is shell-only — we extract
# the regex + violation logic and exercise it against fixture file lists. This
# avoids spinning up a GitHub Actions runner while still pinning the contract.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    WORKFLOW="$PROJECT_ROOT_REAL/.github/workflows/no-backup-files.yml"

    [[ -f "$WORKFLOW" ]] || skip "no-backup-files.yml not present"

    export TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# Extract the violation pattern from the workflow. Single source of truth.
_workflow_pattern() {
    grep -E "grep -E" "$WORKFLOW" | head -1 | grep -oE "'[^']+'" | head -1 | tr -d "'"
}

# Run the same grep used by the workflow against a list of candidate files.
_check_violations() {
    local files="$1"
    local pattern
    pattern="$(_workflow_pattern)"
    printf '%s\n' "$files" | grep -E "$pattern" || true
}

# -----------------------------------------------------------------------------
# Match cases — these files MUST be flagged as violations
# -----------------------------------------------------------------------------
@test "no-backup: flags .bak suffix" {
    local v
    v=$(_check_violations "src/foo.sh.bak")
    [[ "$v" == "src/foo.sh.bak" ]]
}

@test "no-backup: flags -bak suffix (planning-tool pattern)" {
    local v
    v=$(_check_violations "grimoires/loa/sprint.md.cycle-096-bak")
    [[ "$v" == "grimoires/loa/sprint.md.cycle-096-bak" ]]
}

@test "no-backup: flags emacs ~ suffix" {
    local v
    v=$(_check_violations "src/foo.py~")
    [[ "$v" == "src/foo.py~" ]]
}

@test "no-backup: flags .orig suffix (merge artifact)" {
    local v
    v=$(_check_violations "README.md.orig")
    [[ "$v" == "README.md.orig" ]]
}

@test "no-backup: flags .swp / .swo (vim swap)" {
    local v
    v=$(_check_violations $'src/.foo.swp\nsrc/.bar.swo')
    # Use grep for multi-line containment (bash `[[ == * ]]` does not span \n).
    echo "$v" | grep -q '\.swp$' || { echo "missed .swp"; return 1; }
    echo "$v" | grep -q '\.swo$' || { echo "missed .swo"; return 1; }
}

# -----------------------------------------------------------------------------
# Negative cases — these MUST NOT be flagged
# -----------------------------------------------------------------------------
@test "no-backup: does NOT flag bakery/ directory" {
    local v
    v=$(_check_violations "src/bakery/oven.sh")
    [[ -z "$v" ]] || {
        echo "False positive on bakery/: $v"
        return 1
    }
}

@test "no-backup: does NOT flag legitimate .md / .yml / .sh / .py" {
    local v
    v=$(_check_violations $'README.md\n.github/workflows/foo.yml\nscripts/bar.sh\nlib/baz.py')
    [[ -z "$v" ]]
}

@test "no-backup: does NOT flag '-bak-feature' branch-style names (no trailing -bak)" {
    # Only the file's terminal suffix matters. `-bak` MUST be at end.
    local v
    v=$(_check_violations "src/feature-bakery-tools.sh")
    [[ -z "$v" ]]
}

# -----------------------------------------------------------------------------
# Workflow-shape sanity: pinned action; bypass token; env var passing
# -----------------------------------------------------------------------------
@test "no-backup: workflow uses SHA-pinned actions/checkout (cycle-098 supply-chain)" {
    grep -qE "actions/checkout@[0-9a-f]{40}" "$WORKFLOW" || {
        echo "Expected SHA-pinned actions/checkout (40-char hex)"
        return 1
    }
}

@test "no-backup: workflow declares [allow-bak] bypass token" {
    grep -qF '[allow-bak]' "$WORKFLOW"
}

@test "no-backup: workflow passes github context via env vars (NOT \${{ }} in shell)" {
    # Pre-existing security pattern: untrusted GitHub context vars must be
    # delivered to shell via env, not direct interpolation.
    grep -qF 'PR_TITLE: ${{ github.event.pull_request.title }}' "$WORKFLOW"
    grep -qF '"${PR_TITLE}"' "$WORKFLOW"
}

@test "no-backup: workflow remediation message includes git rm --cached" {
    grep -qF 'git rm --cached' "$WORKFLOW"
}
