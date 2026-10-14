#!/usr/bin/env bats
# .claude/scripts/red-test-check.sh (grimoires/loa/sdd.md D-7.5..D-7.7, §5.2) against small
# fixture repositories built per test. Every case also asserts that `git worktree list` in the
# fixture shows only the main tree afterwards and that the live tree was not touched.

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/red-test-check.sh"
    R="${BATS_TEST_TMPDIR}/repo"
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "$R" "$TMPDIR"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    git -C "$R" init -q
    git -C "$R" config user.email t@example.invalid
    git -C "$R" config user.name t
    git -C "$R" config commit.gpgsign false
    # Base: a buggy add(); node_modules is ignored, as in a real project.
    printf 'node_modules/\n.venv/\n' > "$R/.gitignore"
    printf 'add() { echo $(( $1 - $2 )); }\n' > "$R/lib.sh"
    commit "base"
}

commit() { git -C "$R" add -A && git -C "$R" commit -q -m "$1"; git -C "$R" rev-parse HEAD; }

# The red test: asserts add 2 3 = 5 and prints what it got.
add_red_test() {
    mkdir -p "$R/tests"
    cat > "$R/tests/test_add.sh" <<'EOF'
. ./lib.sh
got="$(add 2 3)"
if [ "$got" = 5 ]; then echo "PASS add"; exit 0; fi
echo "FAIL: add 2 3: expected 5, got $got"
exit 1
EOF
}
fix_lib() { printf 'add() { echo $(( $1 + $2 )); }\n' > "$R/lib.sh"; }

# Status of the fixture after a run: only the main tree, no stash, the live tree as it was.
assert_clean() {
    local n
    n="$(git -C "$R" worktree list | wc -l | tr -d ' ')"
    [ "$n" -eq 1 ] || { git -C "$R" worktree list; echo "worktrees left behind"; return 1; }
    [ -z "$(git -C "$R" stash list)" ] || { echo "a stash was created"; return 1; }
    [ -z "$(ls -A "$TMPDIR")" ] || { ls -la "$TMPDIR"; echo "scratch left behind"; return 1; }
}

rtc() { (cd "$R" && "$SCRIPT" "$@"); }

@test "RTC-1 red fails by assertion, green passes: exit 0 VERIFIED with the red output printed" {
    add_red_test; red="$(commit "test(bug): failing test")"
    fix_lib; commit "fix(bug): add adds" >/dev/null
    run rtc --red "$red" --test-file tests/test_add.sh -- sh tests/test_add.sh
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"verdict: VERIFIED"* ]]
    [[ "$output" == *"--- red run (last 80 lines) ---"*"FAIL: add 2 3: expected 5, got -1"*"--- end red run ---"* ]]
    [[ "$output" != *"WARN: no non-test file changed"* ]]
    assert_clean
}

@test "RTC-2 a decoy that passes at both commits exits 3 DECOY" {
    mkdir -p "$R/tests"; printf 'echo "PASS always"\nexit 0\n' > "$R/tests/test_decoy.sh"
    red="$(commit "test: decoy")"
    fix_lib; commit "fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_decoy.sh
    [ "$status" -eq 3 ] || { echo "$output"; return 1; }
    [[ "$output" == *"verdict: DECOY"* ]]
    [[ "$output" == *"PASS always"* ]]
    assert_clean
}

@test "RTC-3 a --test-file absent at the red commit exits 4 NOT_A_RED before any worktree" {
    printf 'x\n' > "$R/README"; red="$(commit "docs")"
    add_red_test; fix_lib; commit "fix and test together" >/dev/null
    run rtc --red "$red" --test-file tests/test_add.sh -- sh tests/test_add.sh
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    [[ "$output" == *"does not exist at the red commit"* ]]
    [[ "$output" == *"verdict: NOT_A_RED"* ]]
    assert_clean
}

@test "RTC-4 a red run that exits 127 (command not found) is NOT_A_RED, exit 4" {
    mkdir -p "$R/tests"; printf 'rtc_no_such_command_xyz\n' > "$R/tests/test_missing.sh"
    red="$(commit "test: calls a missing command")"
    fix_lib; commit "fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_missing.sh
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    [[ "$output" == *"verdict: NOT_A_RED"* ]]
    assert_clean
}

@test "RTC-5 a bats file with a syntax error at red is NOT_A_RED, exit 4" {
    local bats_bin="${BATS_ROOT:-}/bin/bats"
    [ -x "$bats_bin" ] || bats_bin="$(command -v bats || true)"
    [ -n "$bats_bin" ] || skip "no bats binary to run the fixture"
    mkdir -p "$R/tests"
    printf '@test "add" {\n  if [ 1 = 1 ]; then\n    true\n}\n' > "$R/tests/add.bats"
    red="$(commit "test: broken bats file")"
    printf '@test "add" {\n  . ./lib.sh\n  [ "$(add 2 3)" = 5 ]\n}\n' > "$R/tests/add.bats"
    fix_lib; commit "fix" >/dev/null
    run rtc --red "$red" -- "$bats_bin" tests/add.bats
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    [[ "$output" == *"syntax error"* ]]
    [[ "$output" == *"verdict: NOT_A_RED"* ]]
    assert_clean
}

@test "RTC-6 a pytest-style collection error in the red output is NOT_A_RED, exit 4" {
    mkdir -p "$R/tests"
    printf 'echo "ERROR collecting tests/test_add.py"\necho "ImportError while importing test module"\nexit 2\n' > "$R/tests/test_collect.sh"
    red="$(commit "test: does not collect")"
    fix_lib; printf 'exit 0\n' > "$R/tests/test_collect.sh"; commit "fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_collect.sh
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    [[ "$output" == *"matched 'ERROR collecting'"* ]]
    assert_clean
}

@test "RTC-7 a green that still fails exits 1 GREEN_FAILS and prints the green output" {
    add_red_test; red="$(commit "test(bug): failing test")"
    printf 'notes\n' > "$R/NOTES"; commit "not a fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_add.sh
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"verdict: GREEN_FAILS"* ]]
    [[ "$output" == *"--- green run (last 80 lines) ---"* ]]
    assert_clean
}

@test "RTC-8 a run past --timeout yields TIMEOUT, exit 5, and stops the run's children" {
    mkdir -p "$R/tests"; printf 'sleep 30 &\nwait\n' > "$R/tests/test_slow.sh"
    red="$(commit "test: slow")"
    fix_lib; commit "fix" >/dev/null
    local start=$SECONDS
    run rtc --red "$red" --timeout 1 -- sh tests/test_slow.sh
    [ "$status" -eq 5 ] || { echo "$output"; return 1; }
    [[ "$output" == *"TIMEOUT"* ]]
    [ $((SECONDS - start)) -lt 20 ]
    assert_clean
}

@test "RTC-9 without timeout/gtimeout on PATH the bash watcher yields TIMEOUT, exit 5" {
    local shim="${BATS_TEST_TMPDIR}/shim" f b
    mkdir -p "$shim"
    for f in /usr/local/bin/* /usr/bin/* /bin/*; do
        b="${f##*/}"
        case "$b" in timeout|gtimeout) continue ;; esac
        [ -e "$shim/$b" ] || ln -s "$f" "$shim/$b" 2>/dev/null || true
    done
    PATH="$shim" command -v timeout && { echo "the shim still exposes timeout"; return 1; }
    mkdir -p "$R/tests"; printf 'sleep 30\n' > "$R/tests/test_slow.sh"
    red="$(commit "test: slow")"
    fix_lib; commit "fix" >/dev/null
    local start=$SECONDS
    run env PATH="$shim" bash -c 'cd "$1" && shift && exec "$@"' _ "$R" "$SCRIPT" --red "$red" --timeout 1 -- sh tests/test_slow.sh
    [ "$status" -eq 5 ] || { echo "$output"; return 1; }
    [[ "$output" == *"verdict: TIMEOUT"* ]]
    [ $((SECONDS - start)) -lt 20 ]
    assert_clean
}

@test "RTC-10 a dependency present only in the live tree is linked by default; --no-link-deps makes it NOT_A_RED" {
    mkdir -p "$R/node_modules/dep" "$R/tests"
    printf 'dep_ok() { echo yes; }\n' > "$R/node_modules/dep/index.sh"
    cat > "$R/tests/test_dep.sh" <<'EOF'
[ -f node_modules/dep/index.sh ] || { echo "Error: Cannot find module 'dep'"; exit 1; }
. ./node_modules/dep/index.sh
. ./lib.sh
[ "$(dep_ok)" = yes ] && [ "$(add 2 3)" = 5 ] && { echo "PASS"; exit 0; }
echo "FAIL: add 2 3 = $(add 2 3)"; exit 1
EOF
    red="$(commit "test(bug): needs dep")"
    fix_lib; commit "fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_dep.sh
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"linked deps: node_modules"* ]]
    assert_clean
    # the live tree's dependency survived the cleanup
    [ -f "$R/node_modules/dep/index.sh" ]
    run rtc --red "$red" --no-link-deps -- sh tests/test_dep.sh
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    [[ "$output" == *"Cannot find module"* ]]
    assert_clean
}

@test "RTC-11 --setup runs in both worktrees before the test; a failing --setup exits 2" {
    mkdir -p "$R/tests"
    cat > "$R/tests/test_setup.sh" <<'EOF'
[ -f .setup-ran ] || { echo "ImportError while importing: setup did not run"; exit 1; }
. ./lib.sh
[ "$(add 2 3)" = 5 ] && exit 0
echo "FAIL: add"; exit 1
EOF
    red="$(commit "test(bug): needs setup")"
    fix_lib; commit "fix" >/dev/null
    run rtc --red "$red" -- sh tests/test_setup.sh
    [ "$status" -eq 4 ] || { echo "$output"; return 1; }
    assert_clean
    run rtc --red "$red" --setup "touch .setup-ran" -- sh tests/test_setup.sh
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ ! -e "$R/.setup-ran" ]
    assert_clean
    run rtc --red "$red" --setup "false" -- sh tests/test_setup.sh
    [ "$status" -eq 2 ] || { echo "$output"; return 1; }
    [[ "$output" == *"--setup exited 1"* ]]
    assert_clean
}

@test "RTC-12 red not a strict ancestor of green, or unresolvable, exits 2 and creates nothing" {
    add_red_test; red="$(commit "test")"
    fix_lib; green="$(commit "fix")"
    run rtc --red "$green" --green "$red" -- sh tests/test_add.sh
    [ "$status" -eq 2 ]; [[ "$output" == *"not a strict ancestor"* ]]
    run rtc --red "$green" -- sh tests/test_add.sh
    [ "$status" -eq 2 ]
    run rtc --red deadbeefdeadbeef -- sh tests/test_add.sh
    [ "$status" -eq 2 ]; [[ "$output" == *"does not resolve"* ]]
    run rtc --red "$red"
    [ "$status" -eq 2 ]; [[ "$output" == *"a test command is required"* ]]
    run rtc --red --upload-pack=x -- true
    [ "$status" -eq 2 ]
    assert_clean
}

@test "RTC-13 --json prints the documented object" {
    command -v jq >/dev/null || skip "jq not installed"
    mkdir -p "$R/node_modules"
    add_red_test; red="$(commit "test(bug): failing test")"
    fix_lib; green="$(commit "fix")"
    run bash -c 'cd "$1" && "$2" --red "$3" --json -- sh tests/test_add.sh 2>/dev/null' _ "$R" "$SCRIPT" "$red"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    jq -e --arg r "$red" --arg g "$green" '
        (keys == ["green","green_exit","green_tail","linked_deps","red","red_exit","red_tail","verdict"])
        and .red == $r and .green == $g and .red_exit == 1 and .green_exit == 0
        and .verdict == "VERIFIED" and (.red_tail | test("expected 5, got -1"))
        and (.green_tail | test("PASS add")) and .linked_deps == ["node_modules"]' <<< "$output"
    assert_clean
}

@test "RTC-14 a green that changes only test files WARNs" {
    add_red_test; red="$(commit "test(bug): failing test")"
    printf 'echo "PASS rewritten"\nexit 0\n' > "$R/tests/test_add.sh"; commit "weaken the test" >/dev/null
    run rtc --red "$red" -- sh tests/test_add.sh
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: no non-test file changed"* ]]
    assert_clean
}

@test "RTC-15 uncommitted live edits never count, and the live tree is left as it was" {
    add_red_test; red="$(commit "test(bug): failing test")"
    printf 'notes\n' > "$R/NOTES"; commit "not a fix" >/dev/null
    fix_lib    # the fix exists only as an uncommitted edit
    local before; before="$(git -C "$R" status --porcelain)"
    run rtc --red "$red" -- sh tests/test_add.sh
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [ "$(git -C "$R" status --porcelain)" = "$before" ]
    grep -q '+ \$2' "$R/lib.sh"
    assert_clean
}

@test "RTC-16 an interrupted run (TERM) still removes both worktrees" {
    mkdir -p "$R/tests"; printf 'sleep 30\n' > "$R/tests/test_slow.sh"
    red="$(commit "test: slow")"
    fix_lib; commit "fix" >/dev/null
    (cd "$R" && exec "$SCRIPT" --red "$red" -- sh tests/test_slow.sh) > "${BATS_TEST_TMPDIR}/int.out" 2>&1 &
    local pid=$! i=0
    while [ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" -lt 3 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    [ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" -eq 3 ]
    sleep 0.5
    kill -TERM "$pid"
    local rc=0; wait "$pid" || rc=$?
    [ "$rc" -eq 143 ] || { cat "${BATS_TEST_TMPDIR}/int.out"; echo "rc=$rc"; return 1; }
    assert_clean
}

@test "RTC-17 the micro-sprint template requires the separate red commit; reviewing-code names the script" {
    local m="$PROJECT_ROOT/.claude/skills/bug-triaging/resources/templates/micro-sprint.md"
    local t1; t1="$(awk '/^#### Task 1:/,/^#### Task 2:/' "$m")"
    grep -qF 'Committed alone (`test(<bug_id>): failing test`) before any fix commit' <<< "$t1"
    grep -qF 'Red commit: <sha>' <<< "$t1"
    awk '/^#### Task 2:/,/^### Acceptance Criteria/' "$m" | grep -qF 'The fix is a later commit and does not weaken the test'
    local r="$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md"
    awk '/^## Phase 2: Code Review/,/^## Phase 2.5/' "$r" | grep -qF '.claude/scripts/red-test-check.sh --red <Red commit from reviewer.md> -- <test command>'
    awk '/^## Phase 2: Code Review/,/^## Phase 2.5/' "$r" | grep -qF 'Tests exist at each declared `### Seams Under Test` seam'
    grep -qF 'Bash(.claude/scripts/red-test-check.sh *)' "$r"
}
