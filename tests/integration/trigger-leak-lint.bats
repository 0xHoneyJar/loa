#!/usr/bin/env bats
# Apparatus tests for tools/check-trigger-leak.sh (cycle-100 T1.5)

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/tools/check-trigger-leak.sh"
    BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    SANDBOX="$(mktemp -d "${BATS_TMPDIR}/trigger-leak-XXXXXX")"
    export LOA_JAILBREAK_TEST_MODE=1
    export LOA_TRIGGER_LEAK_WATCHLIST="${SANDBOX}/watchlist.txt"
    export LOA_TRIGGER_LEAK_ALLOWLIST="${SANDBOX}/allowlist.txt"
    # Minimal watchlist for deterministic tests.
    cat > "$LOA_TRIGGER_LEAK_WATCHLIST" <<'EOF'
# minimal test watchlist
ignore (all |the )?(previous|prior|above) instructions?
SOUL-PRESCRIPTIVE-MUST-REJECTED
EOF
    cat > "$LOA_TRIGGER_LEAK_ALLOWLIST" <<'EOF'
# rationale: self-reference
tools/check-trigger-leak.sh
# rationale: watchlist is its own pattern source
.claude/data/lore/agent-network/jailbreak-trigger-leak-watchlist.txt
# rationale: allowlist references patterns in rationale comments
.claude/data/lore/agent-network/jailbreak-trigger-leak-allowlist.txt
EOF
}

teardown() {
    rm -rf "$SANDBOX"
}

@test "trigger-leak: --list-patterns prints watchlist regex lines" {
    run "$SCRIPT" --list-patterns
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignore"* ]]
    [[ "$output" == *"SOUL-PRESCRIPTIVE-MUST-REJECTED"* ]]
}

@test "trigger-leak: missing watchlist exits 255" {
    rm "$LOA_TRIGGER_LEAK_WATCHLIST"
    run "$SCRIPT"
    [ "$status" -eq 255 ]
    [[ "$output" == *"watchlist not found"* ]]
}

@test "trigger-leak: allowlist entry without rationale exits 255" {
    cat > "$LOA_TRIGGER_LEAK_ALLOWLIST" <<'EOF'
# rationale: properly justified
tools/check-trigger-leak.sh
some/path/without/rationale.sh
EOF
    run "$SCRIPT"
    [ "$status" -eq 255 ]
    [[ "$output" == *"lacks preceding '# rationale:' comment"* ]]
}

@test "trigger-leak: clean repo returns 0 (allowlist absorbs canonical leak sites)" {
    # Use the repo's actual allowlist + watchlist for this canary test.
    unset LOA_TRIGGER_LEAK_WATCHLIST LOA_TRIGGER_LEAK_ALLOWLIST
    run "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "trigger-leak: F2 — _is_shebang_script identifies bash-shebang extension-less files" {
    # Direct verification of the cycle-099 sprint-1E.c.3.c scanner-glob-blindness
    # remediation: the lint's _is_shebang_script helper must recognize
    # bash/sh/python/node/zsh/ruby shebangs in extension-less files. End-to-end
    # planting under SEARCH_ROOTS is awkward because REPO_ROOT is derived from
    # the lint's own BASH_SOURCE; this unit-style test sources the lint helper
    # directly and exercises the detection rule.
    # Plant probe files in SANDBOX, then call _is_shebang_script.
    local f1="${SANDBOX}/probe-bash-extless"
    local f2="${SANDBOX}/probe-python-extless"
    local f3="${SANDBOX}/probe-binary-extless"
    local f4="${SANDBOX}/probe-text-extless"
    printf '#!/usr/bin/env bash\necho hi\n' > "$f1"
    printf '#!/usr/bin/python3\nprint("hi")\n' > "$f2"
    printf '\x7fELF garbage\n' > "$f3"
    printf 'no shebang here\nplain text\n' > "$f4"

    # Re-source so _is_shebang_script is in our shell.
    # shellcheck disable=SC1091
    source <(awk '/^_is_shebang_script\(\) \{/,/^\}$/' "$SCRIPT")

    _is_shebang_script "$f1"
    _is_shebang_script "$f2"
    if _is_shebang_script "$f3"; then
        echo "false-positive on binary file"; return 1
    fi
    if _is_shebang_script "$f4"; then
        echo "false-positive on plain text file"; return 1
    fi
}

@test "trigger-leak: F3 — env override warns and falls back without LOA_JAILBREAK_TEST_MODE=1" {
    unset LOA_JAILBREAK_TEST_MODE
    # LOA_TRIGGER_LEAK_WATCHLIST is set in setup but no test-mode flag.
    run env -u LOA_JAILBREAK_TEST_MODE \
        LOA_TRIGGER_LEAK_WATCHLIST="${SANDBOX}/watchlist.txt" \
        LOA_TRIGGER_LEAK_ALLOWLIST="${SANDBOX}/allowlist.txt" \
        "$SCRIPT" --list-patterns
    # The lint should emit a WARNING for each ignored override and use the
    # canonical default watchlist (which exists, so --list-patterns succeeds).
    [[ "$output" == *"WARNING: LOA_TRIGGER_LEAK_WATCHLIST ignored"* ]]
    export LOA_JAILBREAK_TEST_MODE=1
}
