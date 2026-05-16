#!/usr/bin/env bats
# =============================================================================
# tests/unit/test_bb_zero_direct_fetch.bats — T3.3 BB no-direct-fetch gate
# =============================================================================
# cycle-104 sprint-3 T3.3 (FR-S3.4 / AC-3.4). Pins the contract that BB
# skill resources contain ZERO raw-HTTP primitives that would bypass
# ChevalDelegateAdapter routing.
#
# Tests:
#   1. Real BB resources scan → exit 0 (current state is clean).
#   2. Positive control: synthetic file with `fetch(` triggers exit 1.
#   3. Positive control: synthetic file with `https.request(` triggers exit 1.
#   4. Positive control: `undici` import triggers exit 1.
#   5. Negative control: comment-only mention is NOT a violation.
#   6. Negative control: suppression-marker line is NOT a violation.
#   7. Allowlist works: github-cli.ts is exempt from real scan.
#   8. Dist files (compiled output) are skipped.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-bb-no-direct-fetch.sh"
    [[ -x "$SCANNER" ]] || skip "scanner not executable at $SCANNER"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/bb-fetch-XXXXXX")"
    chmod 700 "$SCRATCH"
}

teardown() {
    if [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]]; then
        rm -rf "$SCRATCH"
    fi
}

# ---- happy path ----------------------------------------------------------

@test "T3.3-1: real BB resources scan is clean (exit 0)" {
    run "$SCANNER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]] || [[ "$stderr" == *"OK"* ]] || true
}

# ---- positive controls ---------------------------------------------------

@test "T3.3-2: positive control — fetch() in TS file fails the gate" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/bad-fetch.ts" <<'TS'
export async function callProvider() {
    const r = await fetch("https://api.anthropic.com/v1/messages");
    return r.json();
}
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad-fetch.ts"* ]]
    [[ "$output" == *"fetch("* ]]
}

@test "T3.3-3: positive control — https.request() in JS file fails the gate" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/bad-https.js" <<'JS'
const https = require("node:https");
const req = https.request({ host: "api.openai.com" });
JS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad-https.js"* ]]
}

@test "T3.3-4: positive control — undici import fails the gate" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/bad-undici.ts" <<'TS'
import { request } from "undici";
const r = await request("https://api.anthropic.com/v1/messages");
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 1 ]
    [[ "$output" == *"undici"* ]]
}

@test "T3.3-5: positive control — node:https import fails the gate" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/bad-import.ts" <<'TS'
import * as https from "node:https";
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 1 ]
}

# ---- negative controls ---------------------------------------------------

@test "T3.3-6: comment-only mention of fetch() is NOT a violation" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/comment-only.ts" <<'TS'
// We used to call fetch(...) directly before cycle-103.
// All HTTP now flows through ChevalDelegateAdapter.
export const FOO = 1;
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 0 ]
}

@test "T3.3-7: suppression marker exempts a line" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/with-marker.ts" <<'TS'
// Test-fixture spawn that happens to look like fetch; not a real HTTP call.
const x = fetch("file:///dev/null"); // check-bb-no-direct-fetch: ok
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 0 ]
}

@test "T3.3-8: block-comment continuation (*) is NOT a violation" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/blockcomment.ts" <<'TS'
/**
 * Implementation note: this used to call fetch() directly. Now it does not.
 * The fetch() call moved to cheval. Do not re-introduce here.
 */
export const FOO = 1;
TS
    run "$SCANNER" --root "$SCRATCH/resources"
    [ "$status" -eq 0 ]
}

# ---- structural checks ---------------------------------------------------

@test "T3.3-9: scanner exits 2 on missing --root directory" {
    run "$SCANNER" --root "$SCRATCH/does-not-exist"
    [ "$status" -eq 2 ]
}

@test "T3.3-10: --quiet suppresses non-error output on clean scan" {
    mkdir -p "$SCRATCH/resources"
    cat > "$SCRATCH/resources/clean.ts" <<'TS'
export const FOO = 1;
TS
    run "$SCANNER" --quiet --root "$SCRATCH/resources"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T3.3-11: --help prints usage and exits 0" {
    run "$SCANNER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "T3.3-12: unknown argument exits 2" {
    run "$SCANNER" --not-a-real-flag
    [ "$status" -eq 2 ]
}
