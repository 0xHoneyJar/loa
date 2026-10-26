#!/usr/bin/env bats
# =============================================================================
# post-merge-orchestrator-type.bats — the orchestrator refuses a PR type it
# has no phase matrix for (bd-nr5i6, cycle-135 Task 1.6; sdd.md C-4, § 6)
# =============================================================================
# classify-pr-type.sh now emits `housekeeping` for archive, ledger and
# decisions-confirm merges, and post-merge.yml runs neither prepare job for
# it. post-merge-orchestrator.sh is deliberately unchanged: its `--type`
# validation accepts cycle|bugfix|other only, so a future caller cannot
# prepare a housekeeping candidate by accident. These cases are PINS — they
# pass before and after bd-nr5i6; they fail if someone widens the accepted
# set without deciding what a housekeeping candidate prepares. PMOT-T1 also
# pins the HINT line the refusal prints for housekeeping only (review round 1).
#
# Hermetic: the orchestrator runs from a throwaway repository (as in
# post-merge-orchestrator.bats), and the refusal happens before any write.

bats_require_minimum_version 1.5.0

setup() {
    REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_REPO="$BATS_TEST_TMPDIR/repo"
    local scripts="$TEST_REPO/.claude/scripts" f
    mkdir -p "$scripts"
    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" -c user.name=t -c user.email=t@example.invalid \
        commit --quiet --allow-empty -m "initial"
    for f in bootstrap.sh path-lib.sh compat-lib.sh post-merge-orchestrator.sh; do
        if [[ -f "$REAL_ROOT/.claude/scripts/$f" ]]; then
            install -m 0644 "$REAL_ROOT/.claude/scripts/$f" "$scripts/$f"
        fi
    done
    export PROJECT_ROOT="$TEST_REPO"
    ORCH="$scripts/post-merge-orchestrator.sh"
    SHA="$(git -C "$TEST_REPO" rev-parse HEAD)"
    [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]
}

@test "PMOT-T1: --generate --type housekeeping is refused: exit 1, 'Invalid --type' on stderr (pin)" {
    cd "$TEST_REPO"
    run --separate-stderr bash "$ORCH" --generate --pr 1 --type housekeeping --sha "$SHA"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Invalid --type: housekeeping"* ]]
    # The repair hint for a downstream workflow that still carries the legacy
    # negative-list guard (post-merge-orchestrator.sh, cycle-135 C-4).
    [[ "$stderr" == *"HINT: housekeeping merges prepare nothing; refresh .github/workflows/post-merge.yml"* ]]
    [ ! -e "$TEST_REPO/.run/post-merge-candidate.json" ]
}

@test "PMOT-T2: --generate --type bogus is refused the same way (pin)" {
    cd "$TEST_REPO"
    run --separate-stderr bash "$ORCH" --generate --pr 1 --type bogus --sha "$SHA"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Invalid --type: bogus"* ]]
    # The housekeeping hint is specific to housekeeping.
    [[ "$stderr" != *"HINT: housekeeping"* ]]
    [ ! -e "$TEST_REPO/.run/post-merge-candidate.json" ]
}
