#!/usr/bin/env bats
# =============================================================================
# mktemp-bsd-portability.bats — bug-978 (#978) / sprint-bug-198
# =============================================================================
# BSD/macOS mktemp only expands a template's X-run when it is the TRAILING
# token. Templates like `vq-input.XXXXXX.json` create a LITERAL file on the
# first call and die with "mkstemp ... File exists" on the next — observed in
# the field as a silently degraded 3-voice Flatline review (voices=1/3).
#
# These tests run the real helpers under a BSD-semantics mktemp shim on a
# masked PATH, plus a scanner that fences the whole script tree against the
# suffixed-template class.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$SHIM_DIR" "$WORK_DIR"

    # BSD-semantics mktemp shim (models the macOS behavior from the #978
    # field report): --suffix unsupported; a trailing X-run expands; a
    # NON-trailing X-run produces a literal file, then File-exists errors.
    cat > "$SHIM_DIR/mktemp" <<'SHIM'
#!/usr/bin/env bash
set -uo pipefail
dflag="" template="" prev="" dir=""
for a in "$@"; do
    case "$a" in
        --suffix=*) echo "mktemp: illegal option -- suffix" >&2; exit 1 ;;
        -d) dflag=1 ;;
        -p|-t) prev="$a" ;;
        *)
            if [[ "$prev" == "-p" ]]; then dir="$a"; prev=""
            else template="$a"; prev=""
            fi
            ;;
    esac
done
[[ -z "$template" ]] && template="tmp.XXXXXXXX"
[[ -n "$dir" && "$template" != /* ]] && template="$dir/$template"
[[ "$template" != /* ]] && template="${TMPDIR:-/tmp}/$template"
if [[ "$template" =~ (X{3,})$ ]]; then
    xrun="${BASH_REMATCH[1]}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        rand=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "${#xrun}")
        cand="${template%"$xrun"}$rand"
        if [[ -n "$dflag" ]]; then
            mkdir "$cand" 2>/dev/null && { echo "$cand"; exit 0; }
        else
            ( set -C; : > "$cand" ) 2>/dev/null && { echo "$cand"; exit 0; }
        fi
    done
    echo "mktemp: mkstemp failed on $template: exhausted retries" >&2
    exit 1
else
    # Non-trailing X-run: BSD creates the template LITERALLY.
    if [[ -e "$template" ]]; then
        echo "mktemp: mkstemp failed on $template: File exists" >&2
        exit 1
    fi
    if [[ -n "$dflag" ]]; then mkdir "$template"; else : > "$template"; fi
    echo "$template"
fi
SHIM
    chmod +x "$SHIM_DIR/mktemp"
    export PATH="$SHIM_DIR:$PATH"
    export TMPDIR="$WORK_DIR"
}

# -----------------------------------------------------------------------------
# setup_invoke_log (lib/invoke-diagnostics.sh) — the loa-<role>-XXXXXX.log site
# -----------------------------------------------------------------------------

@test "bug-978: setup_invoke_log survives BSD mktemp across two calls (distinct .log files)" {
    source "$PROJECT_ROOT/.claude/scripts/lib/invoke-diagnostics.sh"

    first=$(setup_invoke_log "flatline-review-opus")
    [ -n "$first" ]
    [ -f "$first" ]

    second=$(setup_invoke_log "flatline-review-opus")
    [ -n "$second" ]
    [ -f "$second" ]

    [ "$first" != "$second" ]
}

@test "bug-978: setup_invoke_log keeps .log extension, loa-<suffix>- prefix, and 600 perms" {
    source "$PROJECT_ROOT/.claude/scripts/lib/invoke-diagnostics.sh"

    f=$(setup_invoke_log "gpt-review-call-1")
    [[ "$f" == *.log ]]
    [[ "$(basename "$f")" == loa-gpt-review-call-1-* ]]
    [ "$(stat -c '%a' "$f")" = "600" ]
}

# -----------------------------------------------------------------------------
# flatline-orchestrator vq-input — the within-run 3-voice collision site
# -----------------------------------------------------------------------------

@test "bug-978: flatline vq-input template yields three distinct files in one TEMP_DIR" {
    # Extract the orchestrator's actual mktemp invocation so the test pins
    # the shipped template shape, not a copy that can drift.
    local invocation
    invocation=$(grep -o 'mktemp "[^"]*vq-input[^"]*"' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh")
    [ -n "$invocation" ]

    export TEMP_DIR="$WORK_DIR"
    local one two three
    one=$(eval "$invocation")
    two=$(eval "$invocation")
    three=$(eval "$invocation")

    [ -f "$one" ] && [ -f "$two" ] && [ -f "$three" ]
    [ "$one" != "$two" ]
    [ "$two" != "$three" ]
    [ "$one" != "$three" ]
}

# -----------------------------------------------------------------------------
# make_temp (compat-lib.sh) — the canonical portable vehicle stays healthy
# -----------------------------------------------------------------------------

@test "bug-978: make_temp '.json' returns unique suffixed paths under BSD mktemp" {
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"

    a=$(make_temp ".json")
    b=$(make_temp ".json")
    [[ "$a" == *.json ]]
    [[ "$b" == *.json ]]
    [ -f "$a" ] && [ -f "$b" ]
    [ "$a" != "$b" ]
}

# -----------------------------------------------------------------------------
# Scanner — fences the whole script tree against the suffixed-template class
# -----------------------------------------------------------------------------

@test "bug-978: scanner reports no suffixed mktemp templates in .claude/scripts" {
    run "$PROJECT_ROOT/.claude/scripts/tools/check-no-suffixed-mktemp.sh"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "bug-978: scanner detects a planted suffixed template (not toothless)" {
    local plant_dir="$BATS_TEST_TMPDIR/plant"
    mkdir -p "$plant_dir"
    cat > "$plant_dir/bad.sh" <<'EOF'
#!/usr/bin/env bash
tmp=$(mktemp "${TMPDIR:-/tmp}/bad.XXXXXX.json")
EOF
    run "$PROJECT_ROOT/.claude/scripts/tools/check-no-suffixed-mktemp.sh" "$plant_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.sh"* ]]
}

@test "bug-978: scanner detects GNU-only -p / divergent -t flags, including in .bats files" {
    # Iteration-1: mktemp -p does not exist on BSD; -t diverges. The
    # red-team jailbreak suite (.bats) runs on operator macOS machines, so
    # the scan must cover the test tree too.
    local plant_dir="$BATS_TEST_TMPDIR/plant-flags"
    mkdir -p "$plant_dir"
    cat > "$plant_dir/flagged.bats" <<'EOF'
#!/usr/bin/env bats
@test "x" {
    a="$(mktemp -p "$TMPDIR")"
    b="$(mktemp -t "prefix-XXXXXX")"
}
EOF
    run "$PROJECT_ROOT/.claude/scripts/tools/check-no-suffixed-mktemp.sh" "$plant_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"flagged.bats"* ]]
}

@test "bug-978: scanner rejects option-shaped roots loudly (no silent fence bypass)" {
    # Audit iter-1 (MEDIUM): a root like --exclude=*.sh would otherwise be
    # eaten by grep as an option, silently neutering the fence.
    run "$PROJECT_ROOT/.claude/scripts/tools/check-no-suffixed-mktemp.sh" "--exclude=*.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a directory"* ]]
}

@test "bug-978: scanner fails loud when grep cannot read the tree (no OK-without-scanning)" {
    # Audit iter-2 (MEDIUM): grep exit 2 previously collapsed into "clean".
    local locked_dir="$BATS_TEST_TMPDIR/locked"
    mkdir -p "$locked_dir/sub"
    echo '#!/bin/bash' > "$locked_dir/sub/x.sh"
    chmod 000 "$locked_dir/sub"
    run "$PROJECT_ROOT/.claude/scripts/tools/check-no-suffixed-mktemp.sh" "$locked_dir"
    chmod 755 "$locked_dir/sub"
    [ "$status" -eq 2 ]
    [[ "$output" == *"NOT verified"* ]]
}
