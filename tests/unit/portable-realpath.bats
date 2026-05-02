#!/usr/bin/env bats
# =============================================================================
# portable-realpath.bats — Tests for GNU/BSD portable path resolver (Issue #660)
# =============================================================================
# sprint-bug-129. Validates that resolve_path_portable returns sane output
# under both GNU and BSD realpath behaviors. Specifically, when `realpath -m`
# is unavailable (BSD/macOS), the resolver still produces a usable path
# rather than silently degrading to empty string (which mount-submodule.sh
# was using to falsely declare "0 fixed" on every macOS reconcile).

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export LIB="$PROJECT_ROOT/.claude/scripts/lib/portable-realpath.sh"

    export TMPDIR_TEST="$(mktemp -d)"
    export STUB_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# =========================================================================
# PRP-T1..T2: GNU realpath path (with -m flag works)
# =========================================================================

@test "PRP-T1: existing path resolves correctly" {
    local f="$TMPDIR_TEST/file"
    : >"$f"
    run bash -c "source '$LIB' && resolve_path_portable '$f'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$f" ]]
}

@test "PRP-T2: relative path resolves against current dir" {
    cd "$TMPDIR_TEST"
    : >file
    run bash -c "source '$LIB' && resolve_path_portable 'file'"
    [ "$status" -eq 0 ]
    [[ "$output" == */"file" ]]
}

# =========================================================================
# PRP-T3..T4: BSD-stub case — the #660 defect
# =========================================================================

@test "PRP-T3: BSD-stub realpath (no -m) → existing path still resolves" {
    # Bridgebuilder F007 (PR #670): the previous BSD stub delegated to
    # /usr/bin/realpath, which is absent on Homebrew-only macOS systems
    # and on minimal Alpine images. Replace with a pure-shell BSD
    # equivalent (cd + pwd + basename) — works without /usr/bin/realpath
    # being present on the target host.
    cat >"$STUB_BIN/realpath" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-m" ]]; then
    echo "realpath: illegal option -- m" >&2
    exit 1
fi
# Pure-shell BSD-equivalent canonical resolution (POSIX-portable)
target="$1"
if [[ -d "$target" ]]; then
    cd "$target" 2>/dev/null && pwd
elif [[ -e "$target" ]]; then
    parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd)"
    [[ -n "$parent" ]] && echo "$parent/$(basename "$target")"
else
    exit 1
fi
STUB
    chmod +x "$STUB_BIN/realpath"

    local f="$TMPDIR_TEST/realfile"
    : >"$f"
    run env PATH="$STUB_BIN:/usr/bin:/bin" \
        bash -c "unset _PORTABLE_REALPATH_HAS_M; source '$LIB' && resolve_path_portable '$f'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$f" ]]
    [ -n "$output" ]
}

@test "PRP-T4: BSD-stub + non-existent file in existing parent → manual resolution" {
    # Bridgebuilder F007 (PR #670): pure-shell BSD stub (no /usr/bin/realpath dep).
    cat >"$STUB_BIN/realpath" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-m" ]]; then
    echo "realpath: illegal option -- m" >&2
    exit 1
fi
target="$1"
if [[ -d "$target" ]]; then
    cd "$target" 2>/dev/null && pwd
elif [[ -e "$target" ]]; then
    parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd)"
    [[ -n "$parent" ]] && echo "$parent/$(basename "$target")"
else
    exit 1
fi
STUB
    chmod +x "$STUB_BIN/realpath"

    local missing="$TMPDIR_TEST/not-yet-created"
    run env PATH="$STUB_BIN:/usr/bin:/bin" \
        bash -c "unset _PORTABLE_REALPATH_HAS_M; source '$LIB' && resolve_path_portable '$missing'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not-yet-created" ]]
    [[ "$output" == "$TMPDIR_TEST"* ]]
}

# =========================================================================
# PRP-T5: empty input → exit 1
# =========================================================================

@test "PRP-T5: empty input → exit 1" {
    run bash -c "source '$LIB' && resolve_path_portable ''"
    [ "$status" -eq 1 ]
}

# =========================================================================
# PRP-T6: probe variable detected the right flavor on host
# =========================================================================

@test "PRP-T6: _PORTABLE_REALPATH_HAS_M is set after sourcing" {
    run bash -c "source '$LIB' && echo \"\${_PORTABLE_REALPATH_HAS_M:-unset}\""
    [ "$status" -eq 0 ]
    [[ "$output" == "0" || "$output" == "1" ]]
}
