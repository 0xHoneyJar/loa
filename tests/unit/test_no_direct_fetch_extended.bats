#!/usr/bin/env bats
# =============================================================================
# tests/unit/test_no_direct_fetch_extended.bats — T3.2 drift-gate extension
# =============================================================================
# cycle-104 sprint-3 T3.2 (FR-S3.2 / AC-3.2). Extends the cycle-103
# `tools/check-no-direct-llm-fetch.sh` regression suite to:
#
#   1. Pin that the cycle-104 BB additions (multi-model-pipeline.ts +
#      headless adapter siblings) ARE scanned by the existing recursive
#      `.claude/skills/**` glob — no glob bump required, but a regression
#      check ensures it stays that way.
#   2. Pin a POSITIVE CONTROL fixture: scanning
#      `tests/fixtures/parallel-dispatch-fetch-positive.ts` MUST exit 1
#      with violation output. Catches the regression class where the
#      scanner's URL-pattern detection silently breaks.
#   3. Pin shebang-detection still works for extension-less bash/python
#      files containing provider URLs (cycle-099 sprint-1E.c.3.c
#      glob-blindness lesson).
#   4. Pin that the real project tree scan stays clean (exit 0).

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-no-direct-llm-fetch.sh"
    FIXTURE="$PROJECT_ROOT/tests/fixtures/parallel-dispatch-fetch-positive.ts"
    [[ -x "$SCANNER" ]] || skip "scanner not at $SCANNER"
    [[ -f "$FIXTURE" ]] || skip "positive-control fixture not at $FIXTURE"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/extfetch-XXXXXX")"
    chmod 700 "$SCRATCH"
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# ---- happy path: real tree is clean --------------------------------------

@test "T3.2-1: full-repo default scan is clean (exit 0)" {
    cd "$PROJECT_ROOT"
    run "$SCANNER" --quiet
    [ "$status" -eq 0 ]
}

# ---- positive control fixture --------------------------------------------

@test "T3.2-2: scanning the positive-control fixture exits 1" {
    # Copy the fixture into a scan root so the scanner picks it up
    # (the fixture's real path is in tests/fixtures/ which is outside
    # the default scan roots — intentional, so the fixture doesn't
    # self-trigger on a full-repo scan).
    cp "$FIXTURE" "$SCRATCH/parallel-dispatch-fetch-positive.ts"
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 1 ]
}

@test "T3.2-3: positive control violation names api.anthropic.com" {
    cp "$FIXTURE" "$SCRATCH/parallel-dispatch-fetch-positive.ts"
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.anthropic.com"* ]]
}

@test "T3.2-4: positive control violation also catches openai + google" {
    cp "$FIXTURE" "$SCRATCH/parallel-dispatch-fetch-positive.ts"
    run "$SCANNER" --root "$SCRATCH"
    [[ "$output" == *"api.openai.com"* ]]
    [[ "$output" == *"generativelanguage.googleapis.com"* ]]
}

# ---- BB-resources coverage by the existing recursive glob ----------------

@test "T3.2-5: BB multi-model-pipeline.ts is covered by the recursive glob" {
    # Plant a synthetic violation in a BB-shaped path and confirm the
    # scanner finds it. Catches the regression class where a future
    # glob refactor accidentally excludes the BB resources dir.
    mkdir -p "$SCRATCH/skills/bridgebuilder-review/resources/core"
    cat > "$SCRATCH/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts" <<'TS'
export async function call() {
    return fetch("https://api.openai.com/v1/responses");
}
TS
    run "$SCANNER" --root "$SCRATCH/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"multi-model-pipeline.ts"* ]]
}

@test "T3.2-6: BB headless adapter siblings are covered too" {
    mkdir -p "$SCRATCH/skills/bridgebuilder-review/resources/adapters"
    cat > "$SCRATCH/skills/bridgebuilder-review/resources/adapters/sneaky-adapter.ts" <<'TS'
const url = "https://api.anthropic.com/v1/messages";
TS
    run "$SCANNER" --root "$SCRATCH/skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sneaky-adapter.ts"* ]]
}

# ---- shebang detection (cycle-099 sprint-1E.c.3.c lesson) ----------------

@test "T3.2-7: extension-less bash file with shebang IS scanned" {
    cat > "$SCRATCH/runner" <<'BASH'
#!/usr/bin/env bash
curl https://api.anthropic.com/v1/messages
BASH
    chmod +x "$SCRATCH/runner"
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runner"* ]]
}

@test "T3.2-8: extension-less python file with shebang IS scanned" {
    cat > "$SCRATCH/probe" <<'PY'
#!/usr/bin/env python3
import urllib.request
urllib.request.urlopen("https://api.openai.com/v1/chat/completions")
PY
    chmod +x "$SCRATCH/probe"
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"probe"* ]]
}

@test "T3.2-9: extension-less file WITHOUT shebang is NOT scanned" {
    # A README or text fixture mentioning the URL should not trip the gate.
    cat > "$SCRATCH/NOTES" <<'TXT'
Historical note: we used to call api.anthropic.com directly.
TXT
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 0 ]
}

# ---- suppression marker + comments still skipped -------------------------

@test "T3.2-10: per-line suppression marker exempts a real-looking URL" {
    cat > "$SCRATCH/legit.ts" <<'TS'
// Documented endpoint reference for the runbook; not a runtime call.
const ANTHROPIC_BASE = "https://api.anthropic.com/v1"; // check-no-direct-llm-fetch: ok
TS
    run "$SCANNER" --root "$SCRATCH"
    [ "$status" -eq 0 ]
}
