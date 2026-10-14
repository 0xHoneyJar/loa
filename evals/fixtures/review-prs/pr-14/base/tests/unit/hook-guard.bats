#!/usr/bin/env bats
# =============================================================================
# hook-guard.bats — #1180 (bd-c1180-hook-brick-trlm)
# =============================================================================
# .claude/hooks/hook-guard.sh wraps each PreToolUse safety hook so a hook that
# fails to PARSE (e.g. unresolved git conflict markers) fails OPEN loudly
# instead of bricking every Bash/Edit call. When the wrapped hook parses
# clean, the guard is byte-for-byte transparent on BOTH the allow and block
# paths (exit code, stdout, stderr, stdin passthrough).

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GUARD="$PROJECT_ROOT/.claude/hooks/hook-guard.sh"
    BLOCK_HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"

    # Conflict-marker fixture, built at runtime (never typed as a 7-char run):
    # a valid shebang followed by unresolved git conflict markers, which is a
    # bash parse error.
    LT="$(printf '<%.0s' 1 2 3 4 5 6 7)"
    EQ="$(printf '=%.0s' 1 2 3 4 5 6 7)"
    GT="$(printf '>%.0s' 1 2 3 4 5 6 7)"
    BROKEN="$BATS_TEST_TMPDIR/broken-hook.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s HEAD\n' "$LT"
        printf 'echo ours\n'
        printf '%s\n' "$EQ"
        printf 'echo theirs\n'
        printf '%s upstream\n' "$GT"
    } > "$BROKEN"
    chmod +x "$BROKEN"
}

@test "guard exists and is executable" {
    [ -x "$GUARD" ]
}

# --- (a) fail-open on parse failure ----------------------------------------
@test "conflict-markered hook: guard exits 0 (ALLOW), loud WARN on stderr, stdout empty" {
    # Sanity: the fixture genuinely fails bash -n.
    run bash -n "$BROKEN"
    [ "$status" -ne 0 ]

    local out err
    out="$BATS_TEST_TMPDIR/a.out"; err="$BATS_TEST_TMPDIR/a.err"
    echo '{"tool_input":{"command":"ls"}}' | "$GUARD" "$BROKEN" >"$out" 2>"$err"
    local rc=$?
    [ "$rc" -eq 0 ]
    # stdout MUST be empty (tool is allowed, no JSON leaked)
    [ ! -s "$out" ]
    # stderr names the broken hook and warns loudly
    grep -q "hook-guard" "$err"
    grep -q "WARN" "$err"
    grep -qF "$BROKEN" "$err"
    grep -q "failing OPEN" "$err"
}

# --- (b) transparent on the clean ALLOW path -------------------------------
@test "clean allow-path hook: exit/stdout/stderr BYTE-IDENTICAL via guard vs direct" {
    local payload='{"tool_input":{"command":"ls -la"}}'

    local d_out d_err g_out g_err
    d_out="$BATS_TEST_TMPDIR/d.out"; d_err="$BATS_TEST_TMPDIR/d.err"
    g_out="$BATS_TEST_TMPDIR/g.out"; g_err="$BATS_TEST_TMPDIR/g.err"

    local d_rc=0 g_rc=0
    { echo "$payload" | "$BLOCK_HOOK" >"$d_out" 2>"$d_err"; } || d_rc=$?
    { echo "$payload" | "$GUARD" "$BLOCK_HOOK" >"$g_out" 2>"$g_err"; } || g_rc=$?

    [ "$d_rc" -eq "$g_rc" ]
    diff "$d_out" "$g_out"
    diff "$d_err" "$g_err"
}

# --- (c) transparent on the clean BLOCK path -------------------------------
@test "clean block-path hook: guard exits 2 with same BLOCKED message as direct" {
    # Reconstruct the force-push token at runtime (defensive; the outer bats
    # command is what the live hook scans, not this subprocess payload).
    local force="--force"
    local payload
    payload="$(printf '{"tool_input":{"command":"git push %s origin main"}}' "$force")"

    local d_out d_err g_out g_err
    d_out="$BATS_TEST_TMPDIR/cd.out"; d_err="$BATS_TEST_TMPDIR/cd.err"
    g_out="$BATS_TEST_TMPDIR/cg.out"; g_err="$BATS_TEST_TMPDIR/cg.err"

    local d_rc=0 g_rc=0
    { echo "$payload" | "$BLOCK_HOOK" >"$d_out" 2>"$d_err"; } || d_rc=$?
    { echo "$payload" | "$GUARD" "$BLOCK_HOOK" >"$g_out" 2>"$g_err"; } || g_rc=$?

    [ "$d_rc" -eq 2 ]
    [ "$g_rc" -eq 2 ]
    grep -q "BLOCKED" "$g_err"
    diff "$d_out" "$g_out"
    diff "$d_err" "$g_err"
}

# --- (d) large (>64KB) stdin passthrough, no truncation --------------------
@test "large stdin (>64KB) passes through the guard with zero byte loss" {
    # Probe hook: reports the exact byte count of its stdin to stderr, exits 0.
    local probe="$BATS_TEST_TMPDIR/probe.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'wc -c\n'
    } > "$probe"
    chmod +x "$probe"

    # Build a >64KB payload.
    local big="$BATS_TEST_TMPDIR/big.in"
    head -c 100000 /dev/zero | tr '\0' 'x' > "$big"
    local want; want=$(wc -c < "$big")
    [ "$want" -ge 65536 ]

    local got
    got=$("$GUARD" "$probe" < "$big")
    # wc -c prints the count; strip whitespace for the comparison
    got=$(echo "$got" | tr -d '[:space:]')
    [ "$got" -eq "$want" ]
}

# --- exit-code passthrough for arbitrary codes -----------------------------
@test "guard forwards an arbitrary child exit code unchanged" {
    local exiter="$BATS_TEST_TMPDIR/exit7.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'exit 7\n'
    } > "$exiter"
    chmod +x "$exiter"

    run "$GUARD" "$exiter"
    [ "$status" -eq 7 ]
}

# --- argument passthrough ---------------------------------------------------
@test "guard forwards positional args to the wrapped hook" {
    local echoer="$BATS_TEST_TMPDIR/echoer.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'echo "$1|$2"\n'
    } > "$echoer"
    chmod +x "$echoer"

    run "$GUARD" "$echoer" alpha beta
    [ "$status" -eq 0 ]
    [ "$output" = "alpha|beta" ]
}
