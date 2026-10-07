#!/usr/bin/env bats
# =============================================================================
# flatline-orchestrator-python-isolation.bats — sprint-250 audit LOW-003
#
# configured_flatline_model runs a python3 heredoc that imports loa_cheval (and
# through it json and yaml). With a bare `python3 -`, sys.path[0] is the cwd, so
# a json.py / yaml.py written to the cwd is imported before the stdlib (the n32
# class; evals/tests/eval-recall-grader.bats RG-27). The heredoc runs as
# `python3 -I -` with the adapters directory passed as argv and put on sys.path
# inside the heredoc (-I discards PYTHONPATH).
# =============================================================================

setup() {
    bats_require_minimum_version 1.5.0   # `run -1 grep`
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCHESTRATOR="$REPO_ROOT/.claude/scripts/flatline-orchestrator.sh"
    WS="$BATS_TEST_TMPDIR/ws"
    mkdir -p "$WS"
    # the function alone, out of the orchestrator (sourcing the whole script runs main)
    awk '/^configured_flatline_model\(\) \{/,/^}/' "$ORCHESTRATOR" > "$BATS_TEST_TMPDIR/fn.sh"
    [ -s "$BATS_TEST_TMPDIR/fn.sh" ]
}

# configured_flatline_model "$2" run from the cwd "$1", as the orchestrator does (SCRIPT_DIR, PROJECT_ROOT set)
cfm_from() {
    run bash -c 'source "$1"; SCRIPT_DIR="$2/.claude/scripts" PROJECT_ROOT="$2"; cd "$3" && configured_flatline_model "$4"' \
        _ "$BATS_TEST_TMPDIR/fn.sh" "$REPO_ROOT" "$1" "$2"
}

@test "FOPI-1 the configured-model heredoc runs python3 -I and puts the adapters directory on sys.path itself" {
    grep -q 'python3 -I - "$SCRIPT_DIR/../adapters" "$PROJECT_ROOT" "$1"' "$BATS_TEST_TMPDIR/fn.sh"
    grep -q '^sys.path.insert(0, sys.argv\[1\])$' "$BATS_TEST_TMPDIR/fn.sh"
    run -1 grep -q 'PYTHONPATH=' "$BATS_TEST_TMPDIR/fn.sh"
}

@test "FOPI-2 a json.py or yaml.py planted in the invoker's cwd is never imported (LOW-003, mirrors RG-27)" {
    local mod
    for mod in json yaml; do
        rm -f "$WS"/*.py
        printf 'import sys\nsys.stdout.write("anthropic:forged-%s\\n")\nsys.exit(0)\n' "$mod" > "$WS/$mod.py"
        cfm_from "$WS" nosuch-model
        [[ "$output" != *forged* ]] || { echo "$mod.py was imported: $output" >&2; return 1; }
        [ "$status" -ne 0 ]
    done
}

@test "FOPI-3 the isolated heredoc still resolves a configured alias and a catalog model" {
    printf 'import sys\nsys.exit(0)\n' > "$WS/json.py"
    cfm_from "$WS" opus
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^anthropic:claude-opus-[0-9] ]]
    cfm_from "$WS" nosuch-model
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}
