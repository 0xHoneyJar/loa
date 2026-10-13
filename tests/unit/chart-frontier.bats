#!/usr/bin/env bats
# chart-frontier.bats: the frontier of a decision map (.claude/scripts/chart-frontier.sh, SDD
# D-4.4): open, unblocked, unclaimed question children of the map epic, ordered by bv's graph
# ranks when bv is on PATH. beads is the PATH stub tests/fixtures/charting/br-stub.sh; bv is a
# stub printing fixed ranks. No real beads database is touched.

setup() {
    REAL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    F="$REAL/.claude/scripts/chart-frontier.sh"
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/grimoires/loa/maps" "$BATS_TEST_TMPDIR/bin"
    cp "$REAL/tests/fixtures/charting/br-stub.sh" "$BATS_TEST_TMPDIR/bin/br"; chmod +x "$BATS_TEST_TMPDIR/bin/br"
    export BR_STATE="$BATS_TEST_TMPDIR/state.json" BR_LOG="$BATS_TEST_TMPDIR/br.log"
    # epic E; q1 open; q2 blocked by q1; q3 claimed; q4 a task (not a question); q5 under another
    # epic; q6 open; q7 closed
    cat > "$BR_STATE" <<'JSON'
[
 {"id":"E","title":"Map: X","issue_type":"epic","status":"open","assignee":null,"labels":["map"],"parent":null,"deps":[],"priority":2},
 {"id":"q1","title":"First question","issue_type":"question","status":"open","assignee":null,"labels":["decision:grilling"],"parent":"E","deps":[],"priority":2},
 {"id":"q2","title":"Blocked question","issue_type":"question","status":"open","assignee":null,"labels":["decision:research"],"parent":"E","deps":["q1"],"priority":2},
 {"id":"q3","title":"Claimed question","issue_type":"question","status":"in_progress","assignee":"someone","labels":["decision:grilling"],"parent":"E","deps":[],"priority":2},
 {"id":"q4","title":"A task","issue_type":"task","status":"open","assignee":null,"labels":[],"parent":"E","deps":[],"priority":2},
 {"id":"q5","title":"Other map","issue_type":"question","status":"open","assignee":null,"labels":["decision:grilling"],"parent":"OTHER","deps":[],"priority":2},
 {"id":"q6","title":"Sixth\u001b[31m question","issue_type":"question","status":"open","assignee":null,"labels":["decision:unblock"],"parent":"E","deps":[],"priority":1},
 {"id":"q7","title":"Closed question","issue_type":"question","status":"closed","assignee":null,"labels":["decision:grilling"],"parent":"E","deps":[],"priority":2}
]
JSON
    printf '# Map: X\n\n**Slug**: x-map\n**Status**: charting\n**Epic**: E\n' > "$ROOT/grimoires/loa/maps/x-map.md"
    NOBV="$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# A negated command mid-test never fails a bats test (errexit ignores `!`); refute does.
refute() { if "$@"; then echo "refuted, but succeeded: $*" >&2; return 1; fi; return 0; }

ids() { cut -f1 <<< "$1" | tr '\n' ' ' | sed 's/ $//'; }

@test "CF-1 the frontier is the open, unblocked, unclaimed question children of the epic" {
    run "$F" E --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(ids "$output")" = "q1 q6" ]
}

@test "CF-2 a map slug resolves through the map doc's Epic line" {
    run "$F" x-map --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(ids "$output")" = "q1 q6" ]
    grep -q -- 'ready --parent E --type question --unassigned' "$BR_LOG"
}

@test "CF-3 titles are printed with control bytes stripped" {
    run "$F" E --root "$ROOT"
    refute grep -q $'\033' <<< "$output"
    grep -q $'^q6\tSixth \\[31m question$' <<< "$output"
}

@test "CF-4 --json prints the filtered br objects" {
    run "$F" E --json --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.[].id] | join(",")' <<< "$output")" = "q1,q6" ]
}

@test "CF-5 closing a prerequisite moves its dependent onto the frontier" {
    jq -c 'map(if .id == "q1" then .status = "closed" else . end)' "$BR_STATE" > "$BR_STATE.t" && mv "$BR_STATE.t" "$BR_STATE"
    run "$F" E --root "$ROOT"
    [ "$(ids "$output")" = "q2 q6" ]
}

@test "CF-6 with bv present, the order follows bv's graph ranks" {
    printf '#!/bin/sh\n[ "$1" = "--robot-triage" ] || exit 2\necho %s\n' "'{\"triage\":{\"recommendations\":[{\"id\":\"q6\"},{\"id\":\"q1\"}]}}'" > "$BATS_TEST_TMPDIR/bin/bv"
    chmod +x "$BATS_TEST_TMPDIR/bin/bv"
    run "$F" E --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(ids "$output")" = "q6 q1" ]
}

@test "CF-7 a bv that errors falls back to br ready order" {
    printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/bv"; chmod +x "$BATS_TEST_TMPDIR/bin/bv"
    run "$F" E --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(ids "$output")" = "q1 q6" ]
}

@test "CF-8 a ready item without a decision label is dropped; output without labels is kept" {
    jq -c 'map(if .id == "q6" then .labels = ["decision:grilling","decision:research"] else . end) | map(if .id == "q1" then del(.labels) else . end)' "$BR_STATE" > "$BR_STATE.t" && mv "$BR_STATE.t" "$BR_STATE"
    run "$F" E --root "$ROOT"
    [ "$(ids "$output")" = "q1" ]
}

@test "CF-9 an empty frontier prints nothing and exits 0" {
    jq -c 'map(if .issue_type == "question" then .status = "closed" else . end)' "$BR_STATE" > "$BR_STATE.t" && mv "$BR_STATE.t" "$BR_STATE"
    run "$F" E --root "$ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "CF-10 exit 2 when br is missing" {
    d="$BATS_TEST_TMPDIR/nobr"; mkdir -p "$d"
    for t in jq bash sed grep cut tr cat dirname; do p="$(command -v "$t")" && ln -sf "$p" "$d/$t"; done
    PATH="$d" run "$F" E --root "$ROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"br (beads_rust) is not on PATH"* ]]
}

@test "CF-11 usage errors exit 2; a map doc without an Epic line exits 1" {
    run "$F" --root "$ROOT"
    [ "$status" -eq 2 ]
    run "$F" 'bad;id' --root "$ROOT"
    [ "$status" -eq 2 ]
    printf '# Map\n**Status**: charting\n' > "$ROOT/grimoires/loa/maps/broken.md"
    run "$F" broken --root "$ROOT"
    [ "$status" -eq 1 ]
}

@test "CF-12 a failing br ready exits 1" {
    BR_FAIL_ON=ready run "$F" E --root "$ROOT"
    [ "$status" -eq 1 ]
}
