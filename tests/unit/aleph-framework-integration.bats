#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    UPDATE_LOA="$REPO_ROOT/.claude/scripts/update-loa.sh"
    MANIFEST="$REPO_ROOT/.claude/scripts/lib/symlink-manifest.sh"
    CHECK_LOA="$REPO_ROOT/.claude/scripts/check-loa.sh"
    COMPAT="$REPO_ROOT/.claude/scripts/compat-lib.sh"

    FIX="$BATS_TEST_TMPDIR/consumer"
    MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
    MOCK_NODE_LOG="$BATS_TEST_TMPDIR/node.log"
    mkdir -p "$FIX/.loa/.claude" "$FIX/.claude/commands" \
        "$FIX/.claude/skills" "$MOCK_BIN"
    (cd "$FIX" && git init -q -b main)
    printf 'consumer fixture\n' > "$FIX/.fixture-root"
    git -C "$FIX" add .fixture-root
    git -C "$FIX" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        -c commit.gpgsign=false commit -qm 'initialize consumer fixture'

    cat > "$MOCK_BIN/node" <<'MOCK_NODE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
    [[ -z "${NODE_OPTIONS:-}" && -z "${NODE_PATH:-}" ]] || exit 94
    echo "v20.19.0"
    exit 0
fi

[[ -z "${NODE_OPTIONS:-}" && -z "${NODE_PATH:-}" ]] || exit 94

operation="${2:?operation required}"
shift 2
target=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) target="$2"; shift 2 ;;
        --bundle) shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$target" ]] || exit 91
printf '%s\n' "$operation" >> "${MOCK_NODE_LOG:?}"

case "$operation" in
    install)
        mkdir -p "$target/.claude/aleph/bin" \
            "$target/.claude/aleph/runtime/bundle" \
            "$target/.claude/commands" \
            "$target/.claude/skills/loa-aleph"
        printf '#!/usr/bin/env node\n' > "$target/.claude/aleph/bin/loa-aleph.mjs"
        printf '{}\n' > "$target/.claude/aleph/install.lock.json"
        printf 'command\n' > "$target/.claude/commands/loa-aleph.md"
        printf '%s\n' '---' 'name: loa-aleph' '---' > "$target/.claude/skills/loa-aleph/SKILL.md"
        ;;
    verify-install)
        [[ ! -e "$target/.aleph-tamper" ]] || exit 92
        [[ -d "$target/.claude/aleph" && ! -L "$target/.claude/aleph" ]]
        [[ -f "$target/.claude/aleph/install.lock.json" ]]
        [[ -f "$target/.claude/commands/loa-aleph.md" \
            && ! -L "$target/.claude/commands/loa-aleph.md" ]]
        [[ -d "$target/.claude/skills/loa-aleph" \
            && ! -L "$target/.claude/skills/loa-aleph" ]]
        ;;
    *) exit 93 ;;
esac
MOCK_NODE
    chmod +x "$MOCK_BIN/node"
    export PATH="$MOCK_BIN:$PATH"
    export MOCK_NODE_LOG
    export NODE_OPTIONS="--require=$BATS_TEST_TMPDIR/untrusted-preload.cjs"
    export NODE_PATH="$BATS_TEST_TMPDIR/untrusted-node-path"
}

commit_source_bundle() {
    local message="${1:-pin fixture bundle}"
    local expected_root actual_root
    expected_root=$(cd "$FIX/.loa" && pwd -P)
    actual_root=$(git -C "$FIX/.loa" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ "$actual_root" != "$expected_root" ]]; then
        git -C "$FIX/.loa" init -q -b main
    fi
    git -C "$FIX/.loa" add -A
    git -C "$FIX/.loa" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        -c commit.gpgsign=false commit -qm "$message"
    git -C "$FIX" add .loa 2>/dev/null
}

commit_legacy_source() {
    printf 'legacy Loa fixture without Aleph\n' > "$FIX/.loa/LEGACY.md"
    commit_source_bundle 'pin legacy bundle-less fixture'
}

create_bundle() {
    local bundle="$FIX/.loa/.claude/aleph/runtime/bundle"
    local installer="$bundle/runtime-js/adapters/loa/src/installer.js"
    local dependency="$bundle/runtime-js/scripts/assemble-bundles.js"
    local digest dependency_digest
    mkdir -p "$(dirname "$installer")" "$(dirname "$dependency")"
    printf '// pinned compiled fixture installer\n' > "$installer"
    printf '// pinned compiled fixture dependency\n' > "$dependency"
    digest=$(bash -c "source '$COMPAT'; sha256_portable '$installer'" | cut -d' ' -f1)
    dependency_digest=$(bash -c "source '$COMPAT'; sha256_portable '$dependency'" | cut -d' ' -f1)
    jq -n --arg path 'runtime-js/adapters/loa/src/installer.js' \
        --arg digest "sha256:$digest" \
        --arg dependency_path 'runtime-js/scripts/assemble-bundles.js' \
        --arg dependency_digest "sha256:$dependency_digest" \
        '{files: [
            {path: $path, digest: $digest},
            {path: $dependency_path, digest: $dependency_digest}
        ]}' > "$bundle/bundle.lock.json"
    commit_source_bundle
}

prepare_legacy_update_transition() {
    local legacy_head selected_head
    commit_legacy_source
    legacy_head=$(git -C "$FIX/.loa" rev-parse HEAD)
    git -C "$FIX" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        -c commit.gpgsign=false commit -qm 'pin legacy Loa gitlink'

    create_bundle
    mkdir -p "$FIX/.loa/.claude/scripts"
    cp "$MOUNT" "$FIX/.loa/.claude/scripts/mount-submodule.sh"
    git -C "$FIX/.loa" add .claude/scripts/mount-submodule.sh
    git -C "$FIX/.loa" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        -c commit.gpgsign=false commit -qm 'add Aleph-aware mount helper'
    selected_head=$(git -C "$FIX/.loa" rev-parse HEAD)

    # Model the exact old-updater corridor: inner checkout and version receipt
    # have advanced, while the outer index still pins the committed legacy SHA.
    git -C "$FIX" update-index --cacheinfo 160000 "$legacy_head" .loa
    jq -n --arg commit "$selected_head" \
        '{submodule: {commit: $commit}}' > "$FIX/.loa-version.json"
}

run_mount_function() {
    local invocation="$1"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && $invocation"
}

@test "cycle-115: manifest excludes receipt-managed Aleph command and skill symlinks" {
    mkdir -p "$FIX/.loa/.claude/skills/loa-aleph" \
        "$FIX/.loa/.claude/skills/ordinary-skill" \
        "$FIX/.loa/.claude/commands"
    printf 'aleph\n' > "$FIX/.loa/.claude/commands/loa-aleph.md"
    printf 'ordinary\n' > "$FIX/.loa/.claude/commands/ordinary.md"

    run bash -c '
        cd "$1"
        source "$2"
        get_symlink_manifest .loa "$1"
        printf "S:%s\n" "${MANIFEST_SKILL_SYMLINKS[@]}"
        printf "C:%s\n" "${MANIFEST_CMD_SYMLINKS[@]}"
    ' _ "$FIX" "$MANIFEST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ordinary-skill"* ]]
    [[ "$output" == *"ordinary.md"* ]]
    [[ "$output" != *"skills/loa-aleph"* ]]
    [[ "$output" != *"commands/loa-aleph.md"* ]]
}

@test "cycle-115: mount, reconcile, and check paths call the Aleph hook" {
    sed -n '/^create_symlinks()/,/^}/p' "$MOUNT" | grep -q 'refresh_copy_set "true"'
    sed -n '/RECONCILE_SYMLINKS" == "true"/,/exit \$reconcile_rc/p' "$MOUNT" \
        | grep -q 'refresh_copy_set "true"'
    sed -n '/^check_symlinks_subcommand()/,/^}/p' "$MOUNT" \
        | grep -q 'refresh_copy_set "false"'
    sed -n '/^check_symlinks_subcommand()/,/^}/p' "$MOUNT" \
        | grep -q 'verify_and_reconcile_symlinks "false" || result=1'
    sed -n '/^refresh_copy_set()/,/^}/p' "$MOUNT" \
        | grep -q 'refresh_aleph_install "$apply"'
}

@test "cycle-115: submodule update refreshes Aleph fail-loud after copy refresh" {
    local refresh_block dispatch_block
    refresh_block=$(sed -n '/^refresh_submodule_mount_state()/,/^}/p' \
        "$UPDATE_LOA")
    dispatch_block=$(sed -n '/# cycle-115: make the selected commit/,/# === Ledger Schema Migration Check ===/p' \
        "$UPDATE_LOA")

    [[ "$dispatch_block" == *'git add "$SUBMODULE_PATH"'* ]]
    [[ "$dispatch_block" == *'refresh_submodule_mount_state "$submodule_script"'* ]]
    [[ "$refresh_block" == *'refresh_copy_set "true"'* ]]
    [[ "$refresh_block" != *'refresh_copy_set "true" || true'* ]]
    [[ "$refresh_block" == *'type refresh_aleph_install'* ]]
}

@test "cycle-115: bundled update fails when mount helpers cannot be sourced" {
    local bad_helper="$BATS_TEST_TMPDIR/bad-mount-helper.sh"
    create_bundle
    printf '%s\n' '# verify_and_reconcile_symlinks' 'return 7' > "$bad_helper"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        refresh_submodule_mount_state "$helper"
    ' _ "$FIX" "$UPDATE_LOA" "$bad_helper"
    [ "$status" -ne 0 ]
    [[ "$output" == *"mount helpers failed to load"* ]]
}

@test "cycle-115: bundled update fails when Aleph refresh helper is absent" {
    local incomplete_helper="$BATS_TEST_TMPDIR/incomplete-mount-helper.sh"
    create_bundle
    printf '%s\n' \
        'verify_and_reconcile_symlinks() { :; }' \
        'refresh_copy_set() { :; }' > "$incomplete_helper"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        refresh_submodule_mount_state "$helper"
    ' _ "$FIX" "$UPDATE_LOA" "$incomplete_helper"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refresh helper is unavailable"* ]]
}

@test "cycle-115: bundle-less legacy update tolerates helper source failure" {
    local bad_helper="$BATS_TEST_TMPDIR/legacy-bad-mount-helper.sh"
    commit_legacy_source
    printf '%s\n' '# verify_and_reconcile_symlinks' 'return 7' > "$bad_helper"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        refresh_submodule_mount_state "$helper"
    ' _ "$FIX" "$UPDATE_LOA" "$bad_helper"
    [ "$status" -eq 0 ]
}

@test "cycle-115: bundle-less legacy update rejects a stale Aleph surface" {
    local bad_helper="$BATS_TEST_TMPDIR/stale-legacy-bad-helper.sh"
    commit_legacy_source
    printf '%s\n' '# verify_and_reconcile_symlinks' 'return 7' > "$bad_helper"
    printf 'stale command\n' > "$FIX/.claude/commands/loa-aleph.md"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        refresh_submodule_mount_state "$helper"
    ' _ "$FIX" "$UPDATE_LOA" "$bad_helper"
    [ "$status" -ne 0 ]
    [[ "$output" == *"selected Loa version has no source bundle"* ]]
    grep -q '^stale command$' "$FIX/.claude/commands/loa-aleph.md"
}

@test "cycle-115: sourcing mount helpers preserves update no-commit choice" {
    local helper="$BATS_TEST_TMPDIR/no-commit-mount-helper.sh"
    commit_legacy_source
    printf '%s\n' \
        'NO_COMMIT=false' \
        'verify_and_reconcile_symlinks() { :; }' \
        'refresh_copy_set() { :; }' > "$helper"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        NO_COMMIT=true
        refresh_submodule_mount_state "$helper"
        test "$NO_COMMIT" = true
    ' _ "$FIX" "$UPDATE_LOA" "$helper"
    [ "$status" -eq 0 ]
}

@test "cycle-115: legacy updater copy-refresh surface bootstraps Aleph" {
    local selected_head staged_head
    prepare_legacy_update_transition
    selected_head=$(git -C "$FIX/.loa" rev-parse HEAD)

    run bash -c '
        cd "$1"
        update_submodule() {
            SUBMODULE_PATH=.loa source "$2" --source-only
            refresh_copy_set true
        }
        update_submodule "$@"
    ' _ "$FIX" "$MOUNT"
    [ "$status" -eq 0 ]
    staged_head=$(git -C "$FIX" ls-files --stage -- .loa \
        | awk '$1 == "160000" && $3 == "0" { print $2 }')
    [ "$staged_head" = "$selected_head" ]
    [ -f "$FIX/.claude/aleph/install.lock.json" ]
    [ -f "$FIX/.claude/commands/loa-aleph.md" ]
    [ -f "$FIX/.claude/skills/loa-aleph/SKILL.md" ]
    [ "$(grep -c '^install$' "$MOCK_NODE_LOG")" -eq 1 ]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 1 ]
}

@test "cycle-115: Loa version without an Aleph bundle is a no-op" {
    commit_legacy_source
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    [[ "$output" == *"not bundled in this Loa version"* ]]
    [ ! -e "$FIX/.claude/aleph" ]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: downgrade without source bundle rejects stale managed paths" {
    commit_legacy_source
    printf 'stale command\n' > "$FIX/.claude/commands/loa-aleph.md"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing stale downgrade"* ]]
    grep -q '^stale command$' "$FIX/.claude/commands/loa-aleph.md"
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: tracked source bundle deletion cannot impersonate a legacy mount" {
    create_bundle
    rm -rf "$FIX/.loa/.claude/aleph/runtime/bundle"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"tracked by the pinned submodule tree but missing"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: tracked source bundle deletion fails the update refresh" {
    local helper="$BATS_TEST_TMPDIR/deleted-bundle-helper.sh"
    create_bundle
    rm -rf "$FIX/.loa/.claude/aleph/runtime/bundle"
    printf 'verify_and_reconcile_symlinks() { :; }\n' > "$helper"

    run bash -c '
        root="$1"; update="$2"; helper="$3"
        cd "$root"
        set --
        source "$update"
        refresh_submodule_mount_state "$helper"
    ' _ "$FIX" "$UPDATE_LOA" "$helper"
    [ "$status" -ne 0 ]
    [[ "$output" == *"tracked by the selected Loa tree but missing"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: first reconcile installs and verifies real managed paths" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    [ -d "$FIX/.claude/aleph" ]
    [ ! -L "$FIX/.claude/aleph" ]
    [ -f "$FIX/.claude/commands/loa-aleph.md" ]
    [ ! -L "$FIX/.claude/commands/loa-aleph.md" ]
    [ -d "$FIX/.claude/skills/loa-aleph" ]
    [ ! -L "$FIX/.claude/skills/loa-aleph" ]
    [ "$(grep -c '^install$' "$MOCK_NODE_LOG")" -eq 1 ]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 1 ]
}

@test "cycle-115: Node preload and module search overrides are cleared" {
    create_bundle
    [ -n "$NODE_OPTIONS" ]
    [ -n "$NODE_PATH" ]

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    [ "$(grep -c '^install$' "$MOCK_NODE_LOG")" -eq 1 ]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 1 ]
}

@test "cycle-115: identical reconcile is idempotent and remains verifiable" {
    local before after
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    before=$(bash -c "source '$COMPAT'; sha256_portable \
        '$FIX/.claude/aleph/bin/loa-aleph.mjs' \
        '$FIX/.claude/aleph/install.lock.json' \
        '$FIX/.claude/commands/loa-aleph.md' \
        '$FIX/.claude/skills/loa-aleph/SKILL.md'")

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    after=$(bash -c "source '$COMPAT'; sha256_portable \
        '$FIX/.claude/aleph/bin/loa-aleph.mjs' \
        '$FIX/.claude/aleph/install.lock.json' \
        '$FIX/.claude/commands/loa-aleph.md' \
        '$FIX/.claude/skills/loa-aleph/SKILL.md'")
    [ "$after" = "$before" ]
    [ "$(grep -c '^install$' "$MOCK_NODE_LOG")" -eq 2 ]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 3 ]
    [ "$(find "$FIX/.claude" -name 'install.lock.json' -type f | wc -l)" -eq 1 ]
    grep -q '^command$' "$FIX/.claude/commands/loa-aleph.md"
}

@test "cycle-115: check mode verifies without invoking install" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    : > "$MOCK_NODE_LOG"

    run_mount_function 'refresh_aleph_install false'
    [ "$status" -eq 0 ]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 2 ]
    ! grep -q '^install$' "$MOCK_NODE_LOG"
}

@test "cycle-115: copy drift and Aleph tamper are both reported and cannot be skipped" {
    create_bundle
    mkdir -p "$FIX/.loa/.claude/hooks" "$FIX/.claude/hooks"
    printf 'source hook\n' > "$FIX/.loa/.claude/hooks/probe.sh"
    printf 'drifted hook\n' > "$FIX/.claude/hooks/probe.sh"
    printf '{}\n' > "$FIX/.loa/.claude/settings.json"
    printf '{}\n' > "$FIX/.claude/settings.json"
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    touch "$FIX/.aleph-tamper"

    run bash -c '
        root="$1" update="$2" mount="$3"
        cd "$root"
        set --
        source "$update"
        SUBMODULE_PATH=.loa source "$mount" --source-only
        LOA_UPDATE_SKIP_COPYSET_VERIFY=1 verify_copyset_gate
    ' _ "$FIX" "$UPDATE_LOA" "$MOUNT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"COPY-DRIFT"* ]]
    [[ "$output" == *"Existing Aleph installation failed integrity verification"* ]]
    [[ "$output" == *"Aleph verification FAILED"* ]]
    [[ "$output" != *"SKIPPING"* ]]
}

@test "cycle-115: unmanaged collision fails before install" {
    create_bundle
    printf 'user-owned\n' > "$FIX/.claude/commands/loa-aleph.md"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"managed-path collision"* ]]
    grep -q 'user-owned' "$FIX/.claude/commands/loa-aleph.md"
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: failed prior verification blocks update rather than repairing" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    : > "$MOCK_NODE_LOG"
    touch "$FIX/.aleph-tamper"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing update"* ]]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 1 ]
    ! grep -q '^install$' "$MOCK_NODE_LOG"
}

@test "cycle-115: installer digest mismatch fails before executing artifact code" {
    create_bundle
    printf '// tampered after lock\n' >> \
        "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js/adapters/loa/src/installer.js"
    commit_source_bundle 'pin internally inconsistent installer fixture'

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"digest does not match"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: dirty imported dependency fails before artifact execution" {
    create_bundle
    printf '// dependency tamper\n' >> \
        "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js/scripts/assemble-bundles.js"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"differs from the pinned submodule commit"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: dependency mode drift fails before artifact execution" {
    create_bundle
    chmod +x \
        "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js/scripts/assemble-bundles.js"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"differs from the pinned submodule commit"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: ignored extra bundle file fails before artifact execution" {
    create_bundle
    printf '%s\n' \
        '.claude/aleph/runtime/bundle/ignored-extra.js' >> "$FIX/.loa/.git/info/exclude"
    printf '// ignored extra\n' > \
        "$FIX/.loa/.claude/aleph/runtime/bundle/ignored-extra.js"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside the pinned submodule inventory"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: clean bundle at a non-gitlink commit is rejected" {
    create_bundle
    printf 'new commit\n' > "$FIX/.loa/NEW-COMMIT.md"
    git -C "$FIX/.loa" add NEW-COMMIT.md
    git -C "$FIX/.loa" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        -c commit.gpgsign=false commit -qm 'unapproved source head'

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"not at the parent-authorized submodule commit"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: installer and lock co-tamper fails against the Git pin" {
    local bundle installer digest replacement
    create_bundle
    bundle="$FIX/.loa/.claude/aleph/runtime/bundle"
    installer="$bundle/runtime-js/adapters/loa/src/installer.js"
    replacement="$BATS_TEST_TMPDIR/replacement-lock.json"
    printf '// installer co-tamper\n' >> "$installer"
    digest=$(bash -c "source '$COMPAT'; sha256_portable '$installer'" | cut -d' ' -f1)
    jq --arg path 'runtime-js/adapters/loa/src/installer.js' \
        --arg digest "sha256:$digest" \
        '(.files[] | select(.path == $path) | .digest) = $digest' \
        "$bundle/bundle.lock.json" > "$replacement"
    mv "$replacement" "$bundle/bundle.lock.json"

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"differs from the pinned submodule commit"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: intermediate source symlink fails before artifact execution" {
    create_bundle
    mv "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js" \
        "$BATS_TEST_TMPDIR/runtime-js"
    ln -s "$BATS_TEST_TMPDIR/runtime-js" \
        "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js"
    commit_source_bundle 'pin forbidden symlink fixture'

    run_mount_function 'refresh_aleph_install true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"source bundle contains a symlink"* ]]
    [ ! -e "$MOCK_NODE_LOG" ]
}

@test "cycle-115: generated consumer gitignore covers every Aleph managed path" {
    run_mount_function 'update_gitignore_for_submodule'
    [ "$status" -eq 0 ]
    grep -qxF '.claude/aleph' "$FIX/.gitignore"
    grep -qxF '.claude/commands/loa-aleph.md' "$FIX/.gitignore"
    grep -qxF '.claude/skills/loa-aleph' "$FIX/.gitignore"
    grep -qxF '.claude/aleph-install.transaction*' "$FIX/.gitignore"
    grep -qxF '.claude/aleph-install.writer.lock*' "$FIX/.gitignore"
}

@test "cycle-115: repository privacy guards cover runs and host capability receipt" {
    grep -qxF 'grimoires/loa/aleph/runs/' "$REPO_ROOT/.gitignore"
    grep -qxF 'grimoires/loa/aleph/host-capabilities.json' "$REPO_ROOT/.gitignore"
    grep -q '"grimoires/loa/aleph/runs/"' "$REPO_ROOT/.github/workflows/ci.yml"
    grep -q '"grimoires/loa/aleph/host-capabilities.json"' "$REPO_ROOT/.github/workflows/ci.yml"
}

@test "cycle-115: check-loa delegates Aleph integrity to compiled verifier" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    : > "$MOCK_NODE_LOG"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"managed tree verified"* ]]
    [ "$(grep -c '^verify-install$' "$MOCK_NODE_LOG")" -eq 1 ]
}

@test "cycle-115: check-loa records a verifier failure" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    touch "$FIX/.aleph-tamper"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrity verification failed"* ]]
}

@test "cycle-115: check-loa rejects a missing installed bundle after receipt" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    mv "$FIX/.claude/aleph/runtime/bundle" "$BATS_TEST_TMPDIR/removed-bundle"
    : > "$MOCK_NODE_LOG"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime is missing or symlinked"* ]]
    [ ! -s "$MOCK_NODE_LOG" ]
}

@test "cycle-115: check-loa rejects a deleted tracked source before first install" {
    create_bundle
    rm -rf "$FIX/.loa/.claude/aleph/runtime/bundle"
    : > "$MOCK_NODE_LOG"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tracked by the pinned submodule tree but missing"* ]]
    [ ! -s "$MOCK_NODE_LOG" ]
}

@test "cycle-115: check-loa rejects a symlinked source bundle before fallback" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    mv "$FIX/.loa/.claude/aleph/runtime/bundle" "$BATS_TEST_TMPDIR/source-bundle"
    ln -s "$BATS_TEST_TMPDIR/source-bundle" \
        "$FIX/.loa/.claude/aleph/runtime/bundle"
    : > "$MOCK_NODE_LOG"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source runtime bundle is not a real directory"* ]]
    [ ! -s "$MOCK_NODE_LOG" ]
}

@test "cycle-115: check-loa authenticates verifier bytes before execution" {
    create_bundle
    run_mount_function 'refresh_aleph_install true'
    [ "$status" -eq 0 ]
    : > "$MOCK_NODE_LOG"
    printf '// verifier tamper\n' >> \
        "$FIX/.loa/.claude/aleph/runtime/bundle/runtime-js/adapters/loa/src/installer.js"

    run bash -c "cd '$FIX' && source '$CHECK_LOA' && check_aleph_integrity && test \"\$FAILURES\" -eq 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"differs from its pinned Git inventory"* ]]
    [ ! -s "$MOCK_NODE_LOG" ]
}
