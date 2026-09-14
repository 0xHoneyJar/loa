#!/usr/bin/env bats
# =============================================================================
# Issue #865 — pipe install (curl | bash) fails: missing lib/ downloads
# =============================================================================
# Pre-fix, mount-loa.sh's pipe-detection block downloaded a fixed set of
# auxiliary scripts but didn't include lib/scaffold-post-merge-workflow.sh
# or lib/portable-realpath.sh — both sourced by the scripts that run
# after re-exec. The curl|bash install path errored with "No such file
# or directory"; the clone-then-run path worked because those files
# existed on disk.
#
# Structural test: scan mount-loa.sh + mount-submodule.sh for lib/* sources,
# then verify each one appears in the pipe-detection download list. New
# lib/ deps added in the future will fail this test until added to the
# download set.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOUNT_LOA="$REPO_ROOT/.claude/scripts/mount-loa.sh"
    MOUNT_SUBMODULE="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$MOUNT_LOA" ]] || skip "mount-loa.sh not found"
    [[ -f "$MOUNT_SUBMODULE" ]] || skip "mount-submodule.sh not found"
}

# Extract sourced lib/*.sh basenames from a script. Handles both
# `source "${SCRIPT_DIR}/lib/foo.sh"` and `. lib/foo.sh` patterns.
_sourced_libs() {
    local file="$1"
    grep -hoE 'lib/[A-Za-z0-9_.-]+\.sh' "$file" 2>/dev/null \
        | sort -u
}

@test "#865: pipe-detection download list includes scaffold-post-merge-workflow.sh" {
    grep -qE 'lib/scaffold-post-merge-workflow\.sh' "$MOUNT_LOA" \
        || {
            echo "REGRESSION: lib/scaffold-post-merge-workflow.sh not in pipe-detection block" >&2
            return 1
        }
}

@test "#865: pipe-detection download list includes portable-realpath.sh" {
    grep -qE 'lib/portable-realpath\.sh' "$MOUNT_LOA" \
        || {
            echo "REGRESSION: lib/portable-realpath.sh not in pipe-detection block" >&2
            return 1
        }
}

@test "#865: every lib/ file sourced by mount-loa.sh or mount-submodule.sh is in the download list" {
    # The auxiliary download block in mount-loa.sh (~L79-83). Extract
    # everything inside it.
    local pipe_block
    pipe_block=$(awk '/Download auxiliary scripts/,/^  done/' "$MOUNT_LOA")

    local missing=()
    local lib
    for lib in $(_sourced_libs "$MOUNT_LOA") $(_sourced_libs "$MOUNT_SUBMODULE"); do
        # symlink-manifest.sh appears in both; dedupe by skipping duplicates
        if ! echo "$pipe_block" | grep -qF "$lib"; then
            missing+=("$lib")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "REGRESSION: the following lib/ files are sourced but NOT in pipe-download list:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        echo "Add them to the 'for _f in ...' loop in mount-loa.sh ~L79 so the" >&2
        echo "curl|bash install path can fetch them. See #865 for the failure shape." >&2
        return 1
    fi
}

# Run the actual bootstrap with a local curl fixture. Its downloaded entrypoint
# only checks the dependency and records execution; no installer/network runs.
pipe_supervisor_fixture() {
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/downloads"
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) target="$2"; shift 2 ;;
        --) url="$2"; break ;;
        *) shift ;;
    esac
done
if [[ "$url" == */lib/mount-supervisor.py ]]; then
    [[ "$FIXTURE_FAIL_HELPER" != true ]] || exit 22
    cp "$FIXTURE_REPO/.claude/scripts/lib/mount-supervisor.py" "$target"
elif [[ "$url" == */mount-loa.sh ]]; then
    cat > "$target" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
cmp "$_LOA_MOUNT_TMPDIR/lib/mount-supervisor.py" \
    "$FIXTURE_REPO/.claude/scripts/lib/mount-supervisor.py"
touch "$FIXTURE_EXECUTED"
rm -rf "$_LOA_MOUNT_TMPDIR"
ENTRY
else
    printf '# local bootstrap dependency fixture\n' > "$target"
fi
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" TMPDIR="$BATS_TEST_TMPDIR/downloads" \
        FIXTURE_REPO="$REPO_ROOT" FIXTURE_FAIL_HELPER="$1" \
        FIXTURE_EXECUTED="$BATS_TEST_TMPDIR/executed" \
        bash -s -- --no-commit < "$MOUNT_LOA"
    echo "$output"
}

@test "IR-001/003: pipe bootstrap downloads the process supervisor before re-exec" {
    pipe_supervisor_fixture false
    [ "$status" -eq 0 ]
    [ -e "$BATS_TEST_TMPDIR/executed" ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/downloads")" ]
}

@test "IR-001/003: failed supervisor download prevents re-exec and removes the download directory" {
    pipe_supervisor_fixture true
    [ "$status" -ne 0 ]
    [[ "$output" == *"lib/mount-supervisor.py"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/executed" ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/downloads")" ]
}
