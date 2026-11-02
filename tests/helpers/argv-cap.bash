# argv_capped_jq: put a jq first on PATH that refuses, as Linux's execve does, any one argument of
# 131,072 bytes or more, its terminating NUL included (MAX_ARG_STRLEN, 32 pages). A payload passed to jq
# on argv then fails with E2BIG on every host, macOS included, as it does on a Linux runner (#1310).
# Needs TEST_TMPDIR; changes PATH for the rest of the test.
argv_capped_jq() {
    export REAL_JQ
    REAL_JQ=$(command -v jq)
    mkdir -p "$TEST_TMPDIR/argv-cap"
    cat > "$TEST_TMPDIR/argv-cap/jq" <<'EOF'
#!/usr/bin/env bash
too_long() {
    local LC_ALL=C a
    for a in "$@"; do
        (( ${#a} < 131072 )) || return 0
    done
    return 1
}
if too_long "$@"; then
    echo "jq: Argument list too long" >&2
    exit 126
fi
exec "$REAL_JQ" "$@"
EOF
    chmod +x "$TEST_TMPDIR/argv-cap/jq"
    PATH="$TEST_TMPDIR/argv-cap:$PATH"
}
