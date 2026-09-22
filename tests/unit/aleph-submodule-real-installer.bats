#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # bug 20260922-13a3d1: Aleph is opt-in — this suite runs only with
    # LOA_ALEPH_ENABLED=1 or aleph.enabled: true in the repo's .loa.config.yaml.
    source "$REPO_ROOT/.claude/scripts/lib/aleph-opt-in.sh"
    aleph_opt_in_enabled "$REPO_ROOT" || skip "Aleph is opt-in (set LOA_ALEPH_ENABLED=1 or aleph.enabled: true to run)"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    BUNDLE_REL=.claude/aleph/runtime/bundle
    FIX="$BATS_TEST_TMPDIR/consumer with spaces"
    mkdir -p "$FIX/.claude/commands" "$FIX/.claude/skills" "$BATS_TEST_TMPDIR/bin"
    git -C "$FIX" init -q
    # Checkout only the immutable bundle; no test commit or network required.
    git clone -q --shared --no-checkout "$REPO_ROOT" "$FIX/.loa"
    git -C "$FIX/.loa" checkout HEAD -- "$BUNDLE_REL"
    git -C "$FIX" update-index --add --cacheinfo \
        "160000,$(git -C "$FIX/.loa" rev-parse HEAD),.loa"
    export REAL_NODE="$(command -v node)"
    export STAGE_LOG="$BATS_TEST_TMPDIR/stage.log"
    cat > "$BATS_TEST_TMPDIR/bin/node" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${2:-}" == install ]]; then
    printf '%s\n' "$4" >> "$STAGE_LOG"
    [[ "${FAIL_INSTALL:-0}" == 0 ]] || exit 23
fi
exec "$REAL_NODE" "$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/node"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

run_refresh() {
    run bash -c 'cd "$1"; source "$2" --source-only; refresh_aleph_install "$3"' \
        _ "$FIX" "$MOUNT" "${1:-true}"
    echo "$output"
}

assert_stage_removed() {
    local stage
    stage=$(tail -n 1 "$STAGE_LOG")
    [ -n "$stage" ]
    [[ "$stage" != "$FIX"/* ]]
    [ ! -e "$stage" ]
    [ ! -e "$(dirname "$stage")" ]
}

@test "#1241/#1232: real immutable installer succeeds from a nested pinned submodule" {
    # Even a caller's in-repo TMPDIR must not reintroduce source overlap.
    mkdir "$FIX/tmp"
    export TMPDIR="$FIX/tmp"
    run_refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
    [ -f "$FIX/.claude/aleph/install.lock.json" ]
    [ -f "$FIX/.claude/commands/loa-aleph.md" ]
    [ -f "$FIX/.claude/skills/loa-aleph/SKILL.md" ]
    [ ! -L "$FIX/.claude/aleph" ]
    assert_stage_removed
    git -C "$FIX/.loa" diff --exit-code HEAD -- "$BUNDLE_REL"

    cp "$FIX/.claude/aleph/install.lock.json" "$BATS_TEST_TMPDIR/receipt.before"
    run_refresh
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/receipt.before" "$FIX/.claude/aleph/install.lock.json"
    assert_stage_removed
    run_refresh false
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$STAGE_LOG" | tr -d ' ')" -eq 2 ]
}

@test "#1241: failed installer propagates failure and removes external source stage" {
    export FAIL_INSTALL=1
    run_refresh
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aleph transactional installer failed"* ]]
    assert_stage_removed
    [ ! -e "$FIX/.claude/aleph" ]
}

@test "#1241: dirty pinned source is still refused before installing" {
    printf 'tamper\n' >> "$FIX/.loa/$BUNDLE_REL/bundle.lock.json"
    run_refresh
    [ "$status" -ne 0 ]
    [[ "$output" == *"differs from the pinned submodule commit"* ]]
    [ ! -e "$STAGE_LOG" ]
    [ ! -e "$FIX/.claude/aleph" ]
}

@test "#1241: check mode does not create a missing installation" {
    run_refresh false
    [ "$status" -ne 0 ]
    [[ "$output" == *"not installed"* ]]
    [ ! -e "$STAGE_LOG" ]
    [ ! -e "$FIX/.claude/aleph" ]
}

@test "#1241: real installed tamper is refused before a repeat install" {
    run_refresh
    [ "$status" -eq 0 ]
    printf 'tamper\n' >> "$FIX/.claude/commands/loa-aleph.md"
    run_refresh
    [ "$status" -ne 0 ]
    [[ "$output" == *"Existing Aleph installation failed integrity verification"* ]]
    [ "$(wc -l < "$STAGE_LOG" | tr -d ' ')" -eq 1 ]
}

@test "#1241: archive failure cannot install a partial source and removes its stage" {
    export REAL_GIT="$(command -v git)"
    export REAL_MKTEMP="$(command -v mktemp)"
    export TEMP_LOG="$BATS_TEST_TMPDIR/temp.log"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == archive ]]; then
        # Even a readable archive is insufficient when its producer fails.
        "$REAL_GIT" "$@"
        exit 23
    fi
done
exec "$REAL_GIT" "$@"
SH
    cat > "$BATS_TEST_TMPDIR/bin/mktemp" <<'SH'
#!/usr/bin/env bash
path=$("$REAL_MKTEMP" "$@") || exit
printf '%s\n' "$path" >> "$TEMP_LOG"
printf '%s\n' "$path"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/git" "$BATS_TEST_TMPDIR/bin/mktemp"
    run_refresh
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aleph transactional installer failed"* ]]
    [ ! -e "$STAGE_LOG" ]
    [ -s "$TEMP_LOG" ]
    [ ! -e "$(cat "$TEMP_LOG")" ]
    [ ! -e "$FIX/.claude/aleph" ]
}
