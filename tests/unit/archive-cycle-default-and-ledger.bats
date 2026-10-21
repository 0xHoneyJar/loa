#!/usr/bin/env bats
# =============================================================================
# archive-cycle-default-and-ledger.bats — sprint-bug-266 (bug 20261021-ba367a)
# =============================================================================
# Pins three archive-cycle.sh contracts (issue #1263 folded in):
#   - the default --cycle is the ledger's active cycle, else the newest cycle
#     by number (never the count of ledger entries);
#   - the default retention keeps every archive, and a pruning run never
#     deletes a directory holding a git-tracked file;
#   - a real archive updates the live ledger as .claude/commands/archive-cycle.md
#     § Ledger Changes documents (status, archived, archive_path,
#     active_cycle: null), --dry-run writes nothing, and an incomplete cycle
#     is refused unless --force.
# Every test runs a hermetic copy of the script in a scratch git repo under
# $BATS_TEST_TMPDIR; the repository's own grimoires/ and config are untouched.
# =============================================================================

setup() {
    export LOA_REPO_ROOT
    LOA_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    [[ -x "$LOA_REPO_ROOT/.claude/scripts/archive-cycle.sh" ]] || skip "archive-cycle.sh not found"
    unset PROJECT_ROOT 2>/dev/null || true

    export WORKDIR="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false

    mkdir -p .claude/scripts
    local f
    for f in archive-cycle.sh bootstrap.sh path-lib.sh ledger-lib.sh; do
        cp "$LOA_REPO_ROOT/.claude/scripts/$f" .claude/scripts/
    done
    export SCRIPT="$WORKDIR/.claude/scripts/archive-cycle.sh"

    mkdir -p grimoires/loa/archive grimoires/loa/cycles/cycle-120-active grimoires/loa/cycles/cycle-131-done
    echo "# prd 120" > grimoires/loa/cycles/cycle-120-active/prd.md
    echo "# prd 131" > grimoires/loa/cycles/cycle-131-done/prd.md

    # Modern ledger: five entries (the old default named "cycle-5"), legacy
    # short ids, zero-padded ids, an active cycle that is NOT the newest.
    cat > grimoires/loa/ledger.json <<'EOF'
{
  "version": "1.0.0",
  "schema_version": 1,
  "active_cycle": "cycle-120-active",
  "cycles": [
    {"id": "cycle-8", "status": "archived", "sprints": []},
    {"id": "cycle-087", "status": "archived", "sprints": []},
    {"id": "cycle-098-foo", "status": "archived", "sprints": []},
    {"id": "cycle-131-done", "status": "archived",
     "cycle_folder": "grimoires/loa/cycles/cycle-131-done/",
     "sprints": [{"global_id": 300, "status": "completed"}]},
    {"id": "cycle-120-active", "status": "active",
     "cycle_folder": "grimoires/loa/cycles/cycle-120-active/",
     "sprints": [{"global_id": 290, "status": "completed"},
                 {"global_id": 291, "status": "completed"}]}
  ]
}
EOF
    # No compound_learning.archive key: the retention default applies.
    touch .loa.config.yaml
}

# Seed ten archive dirs cycle-test-0..9 (index 0 is the oldest once aged).
_seed_archives() {
    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        mkdir -p "grimoires/loa/archive/cycle-test-${i}"
        echo "archive $i" > "grimoires/loa/archive/cycle-test-${i}/note.md"
    done
}

_age_archives() {
    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        touch -d "$(printf '2026-02-%02d 00:00:00' "$((10 + i))")" "grimoires/loa/archive/cycle-test-${i}"
    done
}

# Succeeds when the dry-run output lists cycle-test-$1 for deletion.
_listed_for_deletion() {
    echo "$output" | grep -qE "^  /.*archive/cycle-test-$1\$"
}

_set_ledger() {
    local filter="$1" tmp
    tmp="$(mktemp)"
    jq "$filter" grimoires/loa/ledger.json > "$tmp"
    mv "$tmp" grimoires/loa/ledger.json
}

@test "ACL-1: no --cycle with active_cycle set archives the active cycle, not cycle-<entry count>" {
    run "$SCRIPT" --dry-run --retention 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create archive at: "*"/grimoires/loa/archive/cycle-120-active"* ]]
    [[ "$output" == *"Cycle id: cycle-120-active"* ]]
    [[ "$output" != *"legacy fallback"* ]]
    [[ "$output" != *"archive/cycle-5"* ]]
}

@test "ACL-2: no --cycle with active_cycle null archives the newest unarchived cycle by number" {
    _set_ledger '.active_cycle = null
        | (.cycles[] | select(.id == "cycle-120-active")).status = "archived"
        | (.cycles[] | select(.id == "cycle-131-done")).status = "completed"'
    run "$SCRIPT" --dry-run --retention 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create archive at: "*"/grimoires/loa/archive/cycle-131-done"* ]]
    [[ "$output" == *"Cycle id: cycle-131-done"* ]]
    [[ "$output" != *"legacy fallback"* ]]
}

@test "ACL-3: no --retention and no yaml key keeps every archive (nothing to delete)" {
    _seed_archives
    _age_archives
    run "$SCRIPT" --cycle 131 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to delete"* ]]
    [[ "$output" != *"Would delete"* ]]
}

@test "ACL-4: a pruning run keeps git-tracked archive dirs with a WARN and deletes only untracked ones" {
    _seed_archives
    git add -- grimoires/loa/archive/cycle-test-0 grimoires/loa/archive/cycle-test-1 grimoires/loa/archive/cycle-test-2
    git commit -q --no-verify -m "track three archives"
    _age_archives

    run "$SCRIPT" --cycle 131 --retention 2 --dry-run
    [ "$status" -eq 0 ]
    local i
    for i in 0 1 2; do
        [[ "$output" == *"tracked archive kept: "*"/archive/cycle-test-${i}; prune it with git"* ]]
        if _listed_for_deletion "$i"; then false; fi
    done
    for i in 3 4 5 6 7; do
        _listed_for_deletion "$i"
    done
    for i in 8 9; do
        if _listed_for_deletion "$i"; then false; fi
    done

    run "$SCRIPT" --cycle 131 --retention 2
    [ "$status" -eq 0 ]
    for i in 0 1 2; do
        [ -f "grimoires/loa/archive/cycle-test-${i}/note.md" ]
    done
    [ ! -d grimoires/loa/archive/cycle-test-3 ]
    [ ! -d grimoires/loa/archive/cycle-test-7 ]
}

@test "ACL-5: a real archive of a complete active cycle updates the live ledger; the archived copy is pre-mutation" {
    run "$SCRIPT" --cycle 120
    [ "$status" -eq 0 ]
    local L=grimoires/loa/ledger.json
    [ "$(jq -r '.active_cycle' "$L")" = "null" ]
    [ "$(jq -r '.cycles[] | select(.id == "cycle-120-active") | .status' "$L")" = "archived" ]
    [[ "$(jq -r '.cycles[] | select(.id == "cycle-120-active") | .archived' "$L")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
    [ "$(jq -r '.cycles[] | select(.id == "cycle-120-active") | .archive_path' "$L")" = "grimoires/loa/archive/cycle-120-active" ]
    # Other cycles untouched
    [ "$(jq -r '.cycles[] | select(.id == "cycle-131-done") | .archive_path' "$L")" = "null" ]
    # The ledger copy inside the archive is the pre-archive ledger
    local C=grimoires/loa/archive/cycle-120-active/ledger.json
    [ -f "$C" ]
    [ "$(jq -r '.active_cycle' "$C")" = "cycle-120-active" ]
    [ "$(jq -r '.cycles[] | select(.id == "cycle-120-active") | .status' "$C")" = "active" ]
}

@test "ACL-6: --dry-run leaves the ledger byte-identical" {
    cp grimoires/loa/ledger.json "$BATS_TEST_TMPDIR/ledger.before"
    run "$SCRIPT" --cycle 120 --dry-run
    [ "$status" -eq 0 ]
    cmp -s "$BATS_TEST_TMPDIR/ledger.before" grimoires/loa/ledger.json
    [ ! -d grimoires/loa/archive/cycle-120-active ]
}

@test "ACL-7: an incomplete cycle is refused (exit 1, nothing written) unless --force" {
    _set_ledger '(.cycles[] | select(.id == "cycle-120-active")).sprints[1].status = "in_progress"'
    cp grimoires/loa/ledger.json "$BATS_TEST_TMPDIR/ledger.before"

    run "$SCRIPT" --cycle 120
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 incomplete sprint"* ]]
    [ ! -d grimoires/loa/archive/cycle-120-active ]
    cmp -s "$BATS_TEST_TMPDIR/ledger.before" grimoires/loa/ledger.json

    run "$SCRIPT" --cycle 120 --force
    [ "$status" -eq 0 ]
    [ -d grimoires/loa/archive/cycle-120-active ]
    [ "$(jq -r '.cycles[] | select(.id == "cycle-120-active") | .status' grimoires/loa/ledger.json)" = "archived" ]
}

@test "ACL-8: no --cycle with every cycle archived is refused (exit 1, nothing written)" {
    _set_ledger '.active_cycle = null | (.cycles[] | select(.id == "cycle-120-active")).status = "archived"'
    cp grimoires/loa/ledger.json "$BATS_TEST_TMPDIR/ledger.before"

    run "$SCRIPT" --retention 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: every cycle in the ledger is archived; pass --cycle N to re-archive one"* ]]
    cmp -s "$BATS_TEST_TMPDIR/ledger.before" grimoires/loa/ledger.json
    [ -z "$(ls -A grimoires/loa/archive)" ]
}

@test "ACL-10: no --cycle refuses when the newest cycle is archived but an older one is still open" {
    # cycle-120-active stays "active" (a stale entry); the newest, cycle-131-done, is archived.
    _set_ledger '.active_cycle = null'
    cp grimoires/loa/ledger.json "$BATS_TEST_TMPDIR/ledger.before"

    run "$SCRIPT" --retention 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: the newest cycle (cycle-131-done) is archived but an older cycle (cycle-120-active) is not; pass --cycle N"* ]]
    cmp -s "$BATS_TEST_TMPDIR/ledger.before" grimoires/loa/ledger.json
    [ -z "$(ls -A grimoires/loa/archive)" ]
}

@test "ACL-9: a missing ledger-lib.sh is refused before anything is written" {
    rm -f "$WORKDIR/.claude/scripts/ledger-lib.sh"
    cp grimoires/loa/ledger.json "$BATS_TEST_TMPDIR/ledger.before"

    run "$SCRIPT" --cycle 120 --retention 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: ledger-lib.sh not found next to archive-cycle.sh; cannot record the archive in the ledger"* ]]
    [ ! -d grimoires/loa/archive/cycle-120-active ]
    cmp -s "$BATS_TEST_TMPDIR/ledger.before" grimoires/loa/ledger.json
}
