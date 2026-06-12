#!/usr/bin/env bats
# bug-980 / sprint-bug-204: golden-path silently mis-detected the workflow
# phase when path-lib init failed — get_grimoire_dir echoed nothing, every
# _GP_* path became root-anchored (/prd.md), and phase detection reported
# "discovery" regardless of project state. Sourcing from an errexit-
# suppressed context (the normal skill invocation shape) disabled set -e
# for the whole file, so the empty assignment never aborted.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "GPG-T1 bug-980: get_grimoire_dir emits a stderr diagnostic on init failure" {
    run bash -c '
        cd "$1"
        source .claude/scripts/path-lib.sh
        # Force init failure: yq required + a config that cannot parse
        _init_path_lib() { return 1; }
        get_grimoire_dir
    ' _ "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"path-lib"* ]] || [[ "$output" == *"grimoire"* ]]
}

@test "GPG-T2 bug-980: golden-path guard aborts loud when get_grimoire_dir fails (shipped guard block)" {
    # golden-path.sh re-sources bootstrap (which re-sources path-lib),
    # clobbering any externally-injected poison — so we exercise the SHIPPED
    # guard block directly: extract it from the file and run it against a
    # failing get_grimoire_dir, asserting it (a) emits the diagnostic and
    # (b) returns non-zero before any _GP_PRD_FILE is derived.
    run bash -c '
        set +e
        get_grimoire_dir() { return 1; }
        # extract the guard block (the get_grimoire_dir assignment through
        # the closing fi) verbatim from the shipped script
        guard=$(awk "/^_GP_GRIMOIRE_DIR=\\$\(get_grimoire_dir\)/,/^fi\$/" "$1/.claude/scripts/golden-path.sh")
        [ -n "$guard" ] || { echo "GUARD-BLOCK-NOT-FOUND"; exit 3; }
        eval "$guard"
        echo "REACHED-PAST-GUARD prd=${_GP_PRD_FILE:-UNSET}"
    ' _ "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" != *"REACHED-PAST-GUARD"* ]]
    [[ "$output" == *"grimoire"* ]]
}

@test "GPG-T3 bug-980: empty PROJECT_ROOT does not yield root-anchored /grimoires paths" {
    run bash -c '
        cd "$1"
        source .claude/scripts/path-lib.sh
        PROJECT_ROOT="" 
        _use_defaults 2>/dev/null || exit 7
        echo "LOA_GRIMOIRE_DIR=$LOA_GRIMOIRE_DIR"
    ' _ "$PROJECT_ROOT"
    # Either the guard aborts (exit 7) or the dir is NOT root-anchored
    if [ "$status" -eq 0 ]; then
        [[ "$output" != *"LOA_GRIMOIRE_DIR=/grimoires"* ]]
    else
        [ "$status" -eq 7 ]
    fi
}

@test "GPG-T4 bug-980 iter-1: empty PROJECT_ROOT fails at init entry even via the config branch" {
    run bash -c '
        cd "$1"
        source .claude/scripts/path-lib.sh
        PROJECT_ROOT=""
        export CONFIG_FILE="$1/.loa.config.yaml"   # exists → config branch
        _path_lib_initialized=false
        _init_path_lib 2>&1
        echo "rc=$?"
        echo "GRIMOIRE=${LOA_GRIMOIRE_DIR:-UNSET}"
    ' _ "$PROJECT_ROOT"
    [[ "$output" == *"PROJECT_ROOT is empty"* ]]
    [[ "$output" != *"GRIMOIRE=/grimoires"* ]]
}

@test "GPG-T5 bug-980 iter-2: empty PROJECT_ROOT fails even in legacy-paths mode" {
    run bash -c '
        cd "$1"
        source .claude/scripts/path-lib.sh
        PROJECT_ROOT=""
        export LOA_USE_LEGACY_PATHS=1
        _path_lib_initialized=false
        _init_path_lib 2>&1
        echo "rc=$?"
        echo "GRIMOIRE=${LOA_GRIMOIRE_DIR:-UNSET}"
    ' _ "$PROJECT_ROOT"
    [[ "$output" == *"PROJECT_ROOT is empty"* ]]
    [[ "$output" != *"GRIMOIRE=/grimoires"* ]]
}
