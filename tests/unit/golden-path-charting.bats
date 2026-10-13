#!/usr/bin/env bats
# golden-path-charting.bats: the `charting` planning phase and the multi-map rule in
# .claude/scripts/golden-path.sh (SDD D-4.5, D-4.6). Detection reads only the map doc's
# **Status**: line, so it works without br. Hermetic: golden-path.sh and its two sourced
# libraries are copied into a temp project (the shape of tests/integration/test_golden_path.bats).

setup() {
    TEST_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$TEST_DIR"
    export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
    export LOA_USE_LEGACY_PATHS=1
    unset LOA_UNATTENDED LOA_FLATLINE_MODE
    REAL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    mkdir -p "$TEST_DIR/.claude/scripts" "$TEST_DIR/grimoires/loa/a2a" "$TEST_DIR/grimoires/loa/maps" "$TEST_DIR/grimoires/loa/context"
    for f in bootstrap.sh path-lib.sh compat-lib.sh golden-path.sh; do cp "$REAL/.claude/scripts/$f" "$TEST_DIR/.claude/scripts/"; done
    (cd "$TEST_DIR" && git init -q 2>/dev/null)
    cd "$TEST_DIR"
    source "$TEST_DIR/.claude/scripts/golden-path.sh"
}

teardown() { cd /; rm -rf "$TEST_DIR"; }

# A negated command mid-test never fails a bats test (errexit ignores `!`); refute does.
refute() { if "$@"; then echo "refuted, but succeeded: $*" >&2; return 1; fi; return 0; }

map() { # slug status
    printf '# Map: %s\n\n**Slug**: %s\n**Status**: %s\n**Epic**: bd-%s\n\n## Destination\nx\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n' \
        "$1" "$1" "$2" "$1" > "$TEST_DIR/grimoires/loa/maps/$1.md"
}
tree() { (cd "$TEST_DIR" && find . -path ./.git -prune -o -print | LC_ALL=C sort); }

@test "GPC-1 a charting map with no PRD reports the charting phase" {
    map eval-workers charting
    [ "$(golden_detect_plan_phase)" = "charting" ]
}

@test "GPC-2 no map: discovery, as before" {
    [ "$(golden_detect_plan_phase)" = "discovery" ]
}

@test "GPC-3 a handed-off, closed or abandoned map: discovery again" {
    for st in handed-off closed abandoned; do
        map eval-workers "$st"
        [ "$(golden_detect_plan_phase)" = "discovery" ]
    done
}

@test "GPC-4 the README in maps/ is not a map" {
    printf '# Decision maps\n\n**Status**: charting\n' > "$TEST_DIR/grimoires/loa/maps/README.md"
    [ "$(golden_detect_plan_phase)" = "discovery" ]
    [ -z "$(golden_open_maps)" ]
}

@test "GPC-5 a PRD wins over an open map: architecture" {
    map eval-workers charting
    touch "$TEST_DIR/grimoires/loa/prd.md"
    [ "$(golden_detect_plan_phase)" = "architecture" ]
}

@test "GPC-6 detection works with no br on PATH and exits 0" {
    map eval-workers charting
    stub="$BATS_TEST_TMPDIR/nobr"; mkdir -p "$stub"
    printf '#!/bin/sh\necho "br: not installed" >&2\nexit 127\n' > "$stub/br"; chmod +x "$stub/br"
    PATH="$stub:$PATH" run golden_detect_plan_phase
    [ "$status" -eq 0 ]
    [ "$output" = "charting" ]
    map eval-workers closed
    PATH="$stub:$PATH" run golden_detect_plan_phase
    [ "$status" -eq 0 ]
    [ "$output" = "discovery" ]
}

@test "GPC-7 consumers: workflow state initial, the menu offers Continue charting, plan routes to /chart <slug>" {
    map eval-workers charting
    [ "$(golden_detect_workflow_state)" = "initial" ]
    menu="$(golden_menu_options)"
    grep -q '^Continue charting|' <<< "$menu"
    [ "$(golden_resolve_truename plan)" = "/chart eval-workers" ]
    [ "$(golden_suggest_command)" = "/plan" ]
    map other-map charting
    [ "$(golden_resolve_truename plan)" = "/chart" ]
}

@test "GPC-8 no charting map: no Continue charting entry, plan routes to /plan-and-analyze" {
    map eval-workers handed-off
    menu="$(golden_menu_options)"
    [[ "$menu" == *"Plan a new project|"* ]]
    refute grep -q '^Continue charting|' <<< "$menu"
    [ "$(golden_resolve_truename plan)" = "/plan-and-analyze" ]
}

@test "GPC-9 multi-map helper: none, one, a named one, an unknown name" {
    run golden_resolve_open_map
    [ "$status" -eq 0 ]; [ -z "$output" ]
    map eval-workers charting
    map old-map abandoned
    run golden_resolve_open_map
    [ "$status" -eq 0 ]; [ "$output" = "eval-workers" ]
    map second handed-off
    run golden_resolve_open_map second
    [ "$status" -eq 0 ]; [ "$output" = "second" ]
    run golden_resolve_open_map old-map
    [ "$status" -eq 1 ]
}

@test "GPC-10 several open maps, interactive: exit 3 with every slug for the operator to choose" {
    map eval-workers charting
    map second handed-off
    run golden_resolve_open_map
    [ "$status" -eq 3 ]
    [ "$output" = "$(printf 'eval-workers\nsecond')" ]
}

@test "GPC-11 several open maps, unattended: exit 1 'more than one open map: name one', nothing written" {
    map eval-workers charting
    map second charting
    before="$(tree)"
    LOA_UNATTENDED=1 run golden_resolve_open_map
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than one open map: name one"* ]]
    [[ "$output" == *"eval-workers"* && "$output" == *"second"* ]]
    [ "$(tree)" = "$before" ]
}

@test "GPC-12 two chart-*.md hand-off snapshots, unattended: exit 1, nothing written" {
    printf '# Priority-1 context\n' > "$TEST_DIR/grimoires/loa/context/chart-eval-workers.md"
    printf '# Priority-1 context\n' > "$TEST_DIR/grimoires/loa/context/chart-second.md"
    before="$(tree)"
    LOA_UNATTENDED=1 run golden_resolve_open_map --snapshots
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than one open map: name one"* ]]
    [ "$(tree)" = "$before" ]
    run golden_resolve_open_map --snapshots
    [ "$status" -eq 3 ]
    rm "$TEST_DIR/grimoires/loa/context/chart-second.md"
    run golden_resolve_open_map --snapshots
    [ "$status" -eq 0 ]; [ "$output" = "eval-workers" ]
}

@test "GPC-13 with the ledger writer installed, its unattended verdict drives the rule" {
    mkdir -p "$TEST_DIR/.claude/scripts/lib"
    cp "$REAL/.claude/scripts/lib/dec-write-lib.sh" "$TEST_DIR/.claude/scripts/lib/"
    source "$TEST_DIR/.claude/scripts/golden-path.sh"
    map eval-workers charting
    map second charting
    run golden_resolve_open_map
    [ "$status" -eq 3 ]
    LOA_UNATTENDED=1 run golden_resolve_open_map
    [ "$status" -eq 1 ]
    mkdir -p "$TEST_DIR/.run"
    printf '{"state":"RUNNING"}\n' > "$TEST_DIR/.run/state.json"
    run golden_resolve_open_map
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than one open map: name one"* ]]
}

@test "GPC-13b the unattended check fails closed: an erroring writer, an autonomous PRD, LOA_UNATTENDED over the writer" {
    mkdir -p "$TEST_DIR/.claude/scripts/lib"
    map eval-workers charting
    map second charting
    # a writer that errors (prints nothing useful) counts as unattended
    printf '#!/bin/sh\necho "dec-write: boom" >&2\nexit 1\n' > "$TEST_DIR/.claude/scripts/lib/dec-write-lib.sh"
    chmod +x "$TEST_DIR/.claude/scripts/lib/dec-write-lib.sh"
    source "$TEST_DIR/.claude/scripts/golden-path.sh"
    run golden_resolve_open_map
    [ "$status" -eq 1 ]
    # a writer that prints something other than interactive counts as unattended
    printf '#!/bin/sh\necho "WARN: odd"\n' > "$TEST_DIR/.claude/scripts/lib/dec-write-lib.sh"
    run golden_resolve_open_map
    [ "$status" -eq 1 ]
    # a writer that says interactive is overruled by LOA_UNATTENDED=1
    printf '#!/bin/sh\necho interactive\n' > "$TEST_DIR/.claude/scripts/lib/dec-write-lib.sh"
    run golden_resolve_open_map
    [ "$status" -eq 3 ]
    LOA_UNATTENDED=1 run golden_resolve_open_map
    [ "$status" -eq 1 ]
    # the real writer reads this project's PRD Status line (--prd is passed)
    cp "$REAL/.claude/scripts/lib/dec-write-lib.sh" "$TEST_DIR/.claude/scripts/lib/"
    printf '# PRD\n\n**Status:** Draft, autonomous run\n' > "$TEST_DIR/grimoires/loa/prd.md"
    run golden_resolve_open_map
    [ "$status" -eq 1 ]
    [[ "$output" == *"more than one open map: name one"* ]]
}

@test "GPC-14 golden-path.sh still never reads run state for position" {
    refute grep -q 'sprint-plan-state.json' "$REAL/.claude/scripts/golden-path.sh"
}
