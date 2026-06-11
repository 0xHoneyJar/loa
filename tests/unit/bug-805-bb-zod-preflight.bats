#!/usr/bin/env bats
# =============================================================================
# bug-805-bb-zod-preflight.bats — issue #805 residual F7: fresh submodule
# mounts crash the bridgebuilder TS app with "Cannot find package 'zod'"
# because dist/ imports zod/v4 at runtime, node_modules/ is gitignored, and
# nothing installs deps. entry.sh is the single production entry point —
# preflight there with an actionable error (NO network install in entry path).
# =============================================================================

ENTRY=".claude/skills/bridgebuilder-review/resources/entry.sh"

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    E="$REPO_ROOT/$ENTRY"
    [[ -f "$E" ]] || skip "entry.sh not found"
}

@test "bug-805: entry.sh has a zod preflight before the node exec" {
    # The check must target node_modules/zod specifically (devDeps-present /
    # zod-absent is a real observed state), and precede the exec line.
    local pre_idx exec_idx
    pre_idx=$(grep -n 'node_modules/zod' "$E" | head -1 | cut -d: -f1)
    exec_idx=$(grep -n 'exec node' "$E" | head -1 | cut -d: -f1)
    [[ -n "$pre_idx" && -n "$exec_idx" ]]
    [[ "$pre_idx" -lt "$exec_idx" ]]
}

@test "bug-805: preflight failure message names npm ci as the remediation" {
    grep -B 2 -A 6 'node_modules/zod' "$E" | grep -q 'npm ci'
}

@test "bug-805: entry path performs NO network install (no npm ci/install execution)" {
    # npm must appear only inside the error MESSAGE, never as an executed command.
    ! grep -E '^[^#]*\b(npm (ci|install))' "$E" | grep -v 'echo\|printf\|<<' | grep -q npm
}

@test "bug-805: functional — missing zod aborts before node with actionable error" {
    # Run entry.sh from a scratch copy whose skill dir lacks node_modules/zod.
    # Mirror the real layout: <root>/.claude/skills/<skill>/ with the
    # bash-version-guard stub at <root>/.claude/scripts/ (sourced before
    # the preflight).
    local root="$BATS_TEST_TMPDIR/fixroot"
    local fix="$root/.claude/skills/bridgebuilder-review"
    mkdir -p "$fix/resources" "$fix/dist" "$root/.claude/scripts/lib"
    printf '#!/usr/bin/env bash\ntrue\n' > "$root/.claude/scripts/bash-version-guard.sh"
    # env-loader stub: entry.sh sources it and calls load_dotenv_trusted
    printf '#!/usr/bin/env bash\nload_env_file() { true; }\n' > "$root/.claude/scripts/lib/env-loader.sh"
    cp "$E" "$fix/resources/entry.sh"
    printf 'process.exit(99)\n' > "$fix/dist/main.js"
    run bash "$fix/resources/entry.sh" --help
    [ "$status" -ne 0 ]
    [ "$status" -ne 99 ]
    [[ "$output" == *"zod"* ]]
    [[ "$output" == *"npm ci"* ]]
}

@test "bug-805: regression guard — .env trust block and NODE_OPTIONS fix untouched" {
    grep -q 'LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX' "$E"
    grep -q 'network-family-autoselection-attempt-timeout' "$E"
}
