#!/usr/bin/env bats
# =============================================================================
# tests/unit/ledger-isolation-discovery.bats
#
# cycle-124 FR-6 AC-6.4 — structural guard: every test source that SPAWNS
# cheval.py, model-adapter.sh or the BB cheval-delegate must redirect both
# production ledgers (LOA_COST_LEDGER_PATH + LOA_MODELINV_LOG_PATH) or inherit
# the redirect from a shared setup helper. Without this the next new suite
# pollutes .run/ long before tools/check-ledger-hygiene.sh (which only sees
# .run/ AFTER the CI test steps) or the pre-push hook can notice.
#
# Detector contract — heuristic, tripwire-grade; over-flagging costs two export
# lines in a setup(), under-flagging costs a polluted ledger, so it leans
# towards flagging:
#   candidate  *.bats / *.sh / *.py / *.ts under tests/, .claude/adapters/tests/
#              and .claude/skills/**/__tests__/ that mentions an entry point
#   bats/sh    backslash-continued lines are joined; a non-comment line runs an
#              entry point when it appears in command position (line start,
#              after ; & | ( or =$(, after run / bash / python[3] / timeout N /
#              "$PYTHON*" / an env assignment) — optionally behind a path
#              prefix ending in "/" — and the line is not a --dry-run /
#              --print-* / --validate-bindings / --help / --version call, a
#              grep or file test, `bash -n`, shellcheck, a variable
#              definition, an @test title, or a file-manipulation command
#   py         subprocess.* present AND a repo-rooted reference
#              (REPO*/ROOT*/PROJECT*/parents[…] … cheval.py|model-adapter.sh,
#              or the CHEVAL / MODEL_ADAPTER identifier); bare basenames in
#              sets and fake scripts written into a scratch workspace do not
#   ts         references .claude/adapters/cheval.py (the unit tests inject
#              spawnFn fakes with /tmp/fake-cheval.py and never reach it)
#   covered    both env names appear in the file; OR a pytest file under
#              .claude/adapters/tests/ (conftest.py autouse fixture); OR a .ts
#              file that assigns both through process.env
#
#   DS-1: repo scan — every spawner is covered or on KNOWN_UNCOVERED
#   DS-2: KNOWN_UNCOVERED only shrinks — each entry still exists, still spawns,
#         still lacks coverage (fixing one forces its removal here)
#   DS-3: conftest premise — .claude/adapters/tests/conftest.py names both vars
#   DS-4: positive control — synthetic uncovered bats / sh / py spawners flag
#   DS-5: negative control — dry-run-only, mention-only, grep, @test titles,
#         fake-script heredocs and a covered spawner do not flag
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    CONFTEST="$PROJECT_ROOT/.claude/adapters/tests/conftest.py"
    CONTROL_DIR="$BATS_TEST_TMPDIR/control"
    mkdir -p "$CONTROL_DIR"
}

# Entry points and the execution shapes that reach them (see header).
# cycle-124 Sprint 2: adversarial-review.sh and flatline-orchestrator.sh are INDIRECT
# spawners (they exec model-adapter → cheval); a suite that runs them for real,
# even in FLATLINE_MOCK_MODE, writes MODELINV + cost rows through cheval's
# mock path — found live 2026-09-18 (adversarial-review-e2e.bats).
ENTRY_RE='(cheval\.py|\$\{?[A-Za-z_]*[Cc][Hh][Ee][Vv][Aa][Ll][A-Za-z_]*\}?|model-adapter\.sh|\$\{?MODEL_ADAPTER[A-Z_]*\}?|\$\{?ADAPTER\}?|adversarial-review\.sh|\$\{?ADVERSARIAL[A-Z_]*\}?|flatline-orchestrator\.sh|\$\{?ORCH(ESTRATOR)?[A-Z_]*\}?)'
EXEC_RE='(^[[:space:]]*|[;&|(][[:space:]]*|=\$\([[:space:]]*|(^|[[:space:]])(run|bash|python3?|timeout[[:space:]]+[0-9]+|"?\$\{?PYTHON[A-Za-z_]*\}?"?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)'
AFTER_RE='([[:space:]";)]|$)'
# Non-spawning shapes: dry-run/print flags; grep / git / file-manipulation
# commands in command position (also behind run / if / ! / $( ); file tests;
# variable definitions (assignment-only lines — an env-prefixed command such as
# `KEY="" run "$CHEVAL" …` IS a spawn, cycle-124 Sprint 4); @test titles; a line that is only a quoted path (an
# array element or argument continuation — a spawn always carries arguments).
NOT_SPAWN_RE='--dry-run|--print-effective-config|--print-config|--validate-bindings|--help|--version|(^[[:space:]]*((if|elif|while|until)[[:space:]]+|![[:space:]]*)?(run[[:space:]]+(--[a-z-]+[[:space:]]+)*)?|[(;&][[:space:]]*|=\$\([[:space:]]*)(grep|git|skip|echo|printf|cat|cp|ln|chmod|mkdir|touch|rm|sed|awk|head|tail|wc|ls|diff|cmp|stat|source|\.)[[:space:]]|\[\[?[[:space:]]+!?[[:space:]]*-[a-z][[:space:]]|bash -n|shellcheck|^[[:space:]]*((local|export)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'\''[^'\'']*'\''|[^[:space:]$(]*)[[:space:]]*$|^[[:space:]]*@test|^[[:space:]]*"[^"]*"[[:space:]]*$'

# Spawners that pre-date FR-6 and sit outside Task 1.1's file set. Each entry
# must still exist, still spawn and still lack coverage (DS-2) — fixing one
# (two export lines in its setup()) forces its removal here. New files never
# join this list: they fail DS-1.
KNOWN_UNCOVERED=(
    # Empty since cycle-124 Sprint 1: every spawner sets both vars (bats/TS
    # inline, pytest via conftest.py autouse in .claude/adapters/tests and
    # tests/replay). Add an entry ONLY with a reason; DS-2 makes it shrink-only.
)

_join_continuations() {  # <file> — fold backslash-continued lines into one
    sed -e ':a' -e '/\\[[:space:]]*$/{N; s/\\[[:space:]]*\n[[:space:]]*/ /; ba' -e '}' "$1"
}

_is_spawner() {  # <file>
    local f="$1"
    grep -qE 'cheval\.py|model-adapter\.sh|cheval-delegate|adversarial-review\.sh|flatline-orchestrator\.sh' "$f" || return 1
    case "$f" in
        *.py)
            # A repo-rooted path (REPO*/ROOT*/PROJECT*/parents[…] … cheval.py |
            # model-adapter.sh) or the CHEVAL / MODEL_ADAPTER identifier; a
            # fake script written into a scratch workspace does not count.
            grep -qE 'subprocess\.(run|Popen|check_output|check_call|call)' "$f" \
                && grep -qE '(REPO|ROOT|PROJECT|parents\[).{0,60}(cheval\.py|model-adapter\.sh)|(^|[^A-Za-z_])(CHEVAL|MODEL_ADAPTER)([^A-Za-z_]|$)' "$f"
            ;;
        *.ts)
            grep -qE '\.claude/adapters/cheval\.py' "$f"
            ;;
        *)
            _join_continuations "$f" \
                | grep -E "^[^#]*${EXEC_RE}\"?([^[:space:]\"]*/)?${ENTRY_RE}${AFTER_RE}" \
                | grep -vE -- "$NOT_SPAWN_RE" \
                | grep -q .
            ;;
    esac
}

_is_covered() {  # <file>
    local f="$1"
    case "$f" in
        "$PROJECT_ROOT"/.claude/adapters/tests/*.py) return 0 ;;   # conftest.py autouse (DS-3)
        "$PROJECT_ROOT"/tests/replay/*.py) return 0 ;;             # tests/replay/conftest.py autouse (cycle-124 FR-6)
        *.ts)
            grep -q 'process\.env' "$f" \
                && grep -q 'LOA_COST_LEDGER_PATH' "$f" && grep -q 'LOA_MODELINV_LOG_PATH' "$f"
            ;;
        *)
            grep -q 'LOA_COST_LEDGER_PATH' "$f" && grep -q 'LOA_MODELINV_LOG_PATH' "$f"
            ;;
    esac
}

_uncovered_spawners() {  # <root>... — prints PROJECT_ROOT-relative paths
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        _is_spawner "$f" || continue
        _is_covered "$f" && continue
        printf '%s\n' "${f#"$PROJECT_ROOT"/}"
    done < <(find "$@" -type f \( -name '*.bats' -o -name '*.sh' -o -name '*.py' -o -name '*.ts' \) 2>/dev/null | LC_ALL=C sort)
}

_repo_roots() {
    printf '%s\n' "$PROJECT_ROOT/tests" "$PROJECT_ROOT/.claude/adapters/tests"
    find "$PROJECT_ROOT/.claude/skills" -type d -name __tests__ 2>/dev/null | LC_ALL=C sort
}

_in_known_uncovered() {
    local x
    for x in ${KNOWN_UNCOVERED[@]+"${KNOWN_UNCOVERED[@]}"}; do
        [[ "$x" == "$1" ]] && return 0
    done
    return 1
}

@test "DS-1: every test source that spawns cheval sets both ledger env vars (or is known-uncovered)" {
    local roots=() new=() f
    while IFS= read -r f; do roots+=("$f"); done < <(_repo_roots)
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        _in_known_uncovered "$f" || new+=("$f")
    done < <(_uncovered_spawners "${roots[@]}")
    if [[ ${#new[@]} -gt 0 ]]; then
        printf 'uncovered cheval spawner(s) — export LOA_COST_LEDGER_PATH and LOA_MODELINV_LOG_PATH in setup() (bats/sh), assign both via process.env (ts), or keep pytest under .claude/adapters/tests/ (conftest.py):\n' >&2
        printf '  %s\n' "${new[@]}" >&2
        return 1
    fi
}

@test "DS-2: KNOWN_UNCOVERED only shrinks — every entry still exists, still spawns, still lacks coverage" {
    local f stale=()
    for f in ${KNOWN_UNCOVERED[@]+"${KNOWN_UNCOVERED[@]}"}; do
        if [[ ! -f "$PROJECT_ROOT/$f" ]] || ! _is_spawner "$PROJECT_ROOT/$f" || _is_covered "$PROJECT_ROOT/$f"; then
            stale+=("$f")
        fi
    done
    if [[ ${#stale[@]} -gt 0 ]]; then
        printf 'KNOWN_UNCOVERED entries no longer apply — remove them:\n' >&2
        printf '  %s\n' "${stale[@]}" >&2
        return 1
    fi
}

@test "DS-3: conftest.py autouse fixture names both ledger env vars (the pytest coverage premise)" {
    [[ -f "$CONFTEST" ]]
    grep -q 'autouse=True' "$CONFTEST"
    grep -q 'LOA_COST_LEDGER_PATH' "$CONFTEST"
    grep -q 'LOA_MODELINV_LOG_PATH' "$CONFTEST"
}

@test "DS-4: positive control — synthetic uncovered spawners are flagged" {
    cat > "$CONTROL_DIR/spawner.bats" <<'EOF'
setup() { CHEVAL="$PROJECT_ROOT/.claude/adapters/cheval.py"; }
@test "x" {
    run python3 "$CHEVAL" --agent flatline-reviewer --prompt hi --mock-fixture-dir "$FIX"
}
EOF
    cat > "$CONTROL_DIR/continued.bats" <<'EOF'
@test "y" {
    run bash \
        .claude/scripts/model-adapter.sh \
        --model opus --mode review --input "$doc"
}
EOF
    cat > "$CONTROL_DIR/shim.sh" <<'EOF'
#!/usr/bin/env bash
out=$("$PYTHON_BIN" "$REPO_ROOT/.claude/adapters/cheval.py" --agent x --prompt y)
EOF
    cat > "$CONTROL_DIR/test_replay.py" <<'EOF'
import subprocess
CHEVAL = REPO_ROOT / ".claude" / "adapters" / "cheval.py"
subprocess.run([str(CHEVAL), "--agent", "x"])
EOF
    run _uncovered_spawners "$CONTROL_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"spawner.bats"* ]]
    [[ "$output" == *"continued.bats"* ]]
    [[ "$output" == *"shim.sh"* ]]
    [[ "$output" == *"test_replay.py"* ]]
}

@test "DS-5: negative control — mentions, dry-runs, greps, titles, fakes and covered spawners are not flagged" {
    cat > "$CONTROL_DIR/dry-run-only.bats" <<'EOF'
setup() { CHEVAL="$PROJECT_ROOT/.claude/adapters/cheval.py"; }
@test "cheval.py resolves opus" {
    run python3 "$CHEVAL" --agent reviewing-code --prompt x --dry-run
    [[ -f "$PROJECT_ROOT/.claude/scripts/model-adapter.sh" ]]
    [[ ! -f "$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy" ]]
    grep -q 'cheval.py' "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    if grep -q "MODEL_INVOKE" \
        "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"; then :; fi
    cat > "$fake_dir/model-adapter.sh" <<'FAKE'
#!/usr/bin/env bash
echo '{"content":"fake"}'
FAKE
}
EOF
    cat > "$CONTROL_DIR/covered.bats" <<'EOF'
setup() {
    TMP_DIR="$(mktemp -d)"
    export LOA_MODELINV_LOG_PATH="$TMP_DIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$TMP_DIR/cost-ledger.jsonl"
}
@test "z" { run python3 "$CHEVAL" --agent flatline-reviewer --prompt hi --mock-fixture-dir "$FIX"; }
EOF
    cat > "$CONTROL_DIR/test_mentions.py" <<'EOF'
import subprocess
ENTRYPOINTS = {"model-invoke", "model-adapter.sh", "cheval.py"}
executable(workspace / ".claude/scripts/model-adapter.sh", "#!/bin/sh\necho fake")
subprocess.run(["bash", "-c", "echo hi"])
EOF
    cat > "$CONTROL_DIR/paths-only.bats" <<'EOF'
@test "lists" {
    local files=(
        "$PROJECT_ROOT/.claude/adapters/cheval.py"
        "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    )
    run git diff --name-only "$base"...HEAD -- .claude/scripts/model-adapter.sh
    run --separate-stderr grep -q "MODEL_INVOKE" "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}
EOF
    cat > "$CONTROL_DIR/fake-spawn.test.ts" <<'EOF'
const adapter = new ChevalDelegateAdapter({ chevalScript: "/tmp/fake-cheval.py", spawnFn: fakeSpawn });
EOF
    run _uncovered_spawners "$CONTROL_DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
