#!/usr/bin/env bats
# =============================================================================
# archive-cycle-retention.bats — cycle-104 Sprint 1 T1.8 — AC-1.3 + Q8
# =============================================================================
# Pins the #848 retention bug fix: --retention N must produce different
# deletion sets for different values of N, and --retention 0 must skip
# cleanup entirely.
#
# Previously load_config() ran AFTER parse_args() and unconditionally
# overwrote RETENTION with the yaml default (5), so `--retention 5` and
# `--retention 50` produced the same deletion set. This file pins the
# corrected behavior.
# =============================================================================

setup() {
    export LOA_REPO_ROOT
    LOA_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export SCRIPT="$LOA_REPO_ROOT/.claude/scripts/archive-cycle.sh"

    [[ -x "$SCRIPT" ]] || skip "archive-cycle.sh not found at $SCRIPT"
    unset PROJECT_ROOT 2>/dev/null || true

    export WORKDIR
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    # Hermetic copy of the script under test
    mkdir -p .claude/scripts
    cp "$LOA_REPO_ROOT/.claude/scripts/archive-cycle.sh" .claude/scripts/
    cp "$LOA_REPO_ROOT/.claude/scripts/bootstrap.sh" .claude/scripts/
    [[ -f "$LOA_REPO_ROOT/.claude/scripts/path-lib.sh" ]] && cp "$LOA_REPO_ROOT/.claude/scripts/path-lib.sh" .claude/scripts/
    SCRIPT="$WORKDIR/.claude/scripts/archive-cycle.sh"

    mkdir -p grimoires/loa/archive
    mkdir -p grimoires/loa/cycles/cycle-104-x

    echo "# prd" > grimoires/loa/cycles/cycle-104-x/prd.md
    echo "# sdd" > grimoires/loa/cycles/cycle-104-x/sdd.md
    echo "# sprint" > grimoires/loa/cycles/cycle-104-x/sprint.md

    cat > grimoires/loa/ledger.json <<'EOF'
{
  "schema_version": 1,
  "cycles": [
    {
      "id": "cycle-104-x",
      "status": "archived",
      "prd": "grimoires/loa/cycles/cycle-104-x/prd.md",
      "sdd": "grimoires/loa/cycles/cycle-104-x/sdd.md",
      "sprint_plan": "grimoires/loa/cycles/cycle-104-x/sprint.md"
    }
  ]
}
EOF

    # Seed 10 fake archive directories with controlled mtimes (newest first).
    # Names match either of the two patterns the script accepts:
    # cycle-* and 20*. Use both for realism.
    for i in 0 1 2 3 4 5 6 7 8 9; do
        mkdir -p "grimoires/loa/archive/cycle-test-${i}"
        # Date in 2026, varying day so mtimes differ predictably
        # Older directories first (lower index = older)
        local d
        d=$(printf '2026-02-%02d 00:00:00' "$((10 + i))")
        touch -d "$d" "grimoires/loa/archive/cycle-test-${i}"
    done

    touch .loa.config.yaml
}

teardown() {
    [[ -n "${WORKDIR:-}" ]] && [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

# Count how many old archives the dry-run says it would delete.
_count_deletions() {
    local output="$1"
    echo "$output" | awk '/^  \/.*archive\/cycle-test-/ {print}' | wc -l
}

@test "AC-1.3: --retention 5 with 10 archives deletes 5 (oldest)" {
    run "$SCRIPT" --cycle 104 --retention 5 --dry-run
    [ "$status" -eq 0 ]
    local n
    n=$(_count_deletions "$output")
    [ "$n" -eq 5 ]
}

@test "AC-1.3: --retention 50 with 10 archives deletes 0" {
    run "$SCRIPT" --cycle 104 --retention 50 --dry-run
    [ "$status" -eq 0 ]
    local n
    n=$(_count_deletions "$output")
    [ "$n" -eq 0 ]
    # Should say "Nothing to delete" since 10 ≤ 50
    echo "$output" | grep -qE "Nothing to delete|Would delete 0"
}

@test "AC-1.3: --retention 0 skips cleanup entirely (keeps all archives)" {
    run "$SCRIPT" --cycle 104 --retention 0 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "keeping all archives"
    local n
    n=$(_count_deletions "$output")
    [ "$n" -eq 0 ]
}

@test "AC-1.3: --retention 5 vs --retention 50 produce DIFFERENT deletion sets (regression)" {
    # This is the load-bearing regression test for #848.
    run "$SCRIPT" --cycle 104 --retention 5 --dry-run
    [ "$status" -eq 0 ]
    local n5
    n5=$(_count_deletions "$output")

    run "$SCRIPT" --cycle 104 --retention 50 --dry-run
    [ "$status" -eq 0 ]
    local n50
    n50=$(_count_deletions "$output")

    # Must be different — the cycle-104 fix
    [ "$n5" -ne "$n50" ]
    [ "$n5" -eq 5 ]
    [ "$n50" -eq 0 ]
}

@test "AC-1.3: keep-newest-N semantics — oldest mtimes get deleted" {
    # With 10 archives and retention=5, the 5 OLDEST (cycle-test-0..4) should
    # be flagged for deletion; cycle-test-5..9 (newer) should be preserved.
    run "$SCRIPT" --cycle 104 --retention 5 --dry-run
    [ "$status" -eq 0 ]

    # The 5 oldest (lowest indices) should appear in the deletion list
    for i in 0 1 2 3 4; do
        echo "$output" | grep -qE "archive/cycle-test-${i}\$"
    done
    # The 5 newest (highest indices) should NOT appear
    for i in 5 6 7 8 9; do
        ! echo "$output" | grep -qE "archive/cycle-test-${i}\$"
    done
}
