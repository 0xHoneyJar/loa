#!/usr/bin/env bats
# =============================================================================
# tests/unit/hook-cache-prefix.bats — cycle-116 sprint D6
# (bd-c116-d6-cache-prefix-4yq2)
#
# Byte-determinism regression coverage for the three SessionStart /
# UserPromptSubmit surfaces that actually place text on stdout on their
# non-block path (see grimoires/loa/runbooks/hook-cache-prefix-hygiene.md for
# the full audit): loa-l6-surface-handoffs.sh (via its lib entry point,
# surface_unread_handoffs), loa-l7-surface-soul.sh, and
# post-compact-reminder.sh. Volatile content leaking into a hook's stdout
# defeats Anthropic prompt caching by mutating the cached prefix on every
# session/turn.
#
# L6 note: the wrapper hook (loa-l6-surface-handoffs.sh) resolves its own
# REPO_ROOT from its on-disk location and does git-config/operator-slug
# resolution before calling surface_unread_handoffs — that resolution layer
# has no test-mode injection point and is already covered end-to-end by
# tests/integration/structured-handoff-6*.bats. This file exercises
# surface_unread_handoffs directly (the exact function the wrapper calls,
# sourced from the same lib) against a fixed on-disk fixture, which is where
# all of the hook's actual output-shaping logic (mktemp+sed rewrite,
# sanitize_for_session_start framing) lives.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/hook-cache-prefix"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# -----------------------------------------------------------------------------
# L6 — surface_unread_handoffs (loa-l6-surface-handoffs.sh's lib call site)
# -----------------------------------------------------------------------------

@test "L6: surface_unread_handoffs is byte-deterministic across two runs against fixed state" {
    local lib="$PROJECT_ROOT/.claude/scripts/lib/structured-handoff-lib.sh"
    [[ -f "$lib" ]] || skip "structured-handoff-lib.sh not present"

    local handoffs_dir="$TEST_DIR/handoffs"
    mkdir -p "$handoffs_dir"
    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"
    export LOA_HANDOFF_TEST_MODE=1
    export LOA_HANDOFF_LOG="$TEST_DIR/handoff-events.jsonl"
    export LOA_HANDOFF_VERIFY_OPERATORS=0
    export LOA_HANDOFF_DISABLE_FINGERPRINT=1

    # shellcheck source=/dev/null
    source "$lib"

    # Seed once from the fixed, committed fixture (content-addressed write —
    # the same fixture always produces the same handoff_id/INDEX row).
    handoff_write "$FIXTURES/l6-seed-handoff.md" --handoffs-dir "$handoffs_dir" >/dev/null

    run surface_unread_handoffs reviewer --handoffs-dir "$handoffs_dir"
    [ "$status" -eq 0 ]
    local first="$output"
    [[ "$first" == *"L6 Unread handoffs to: reviewer"* ]]

    run surface_unread_handoffs reviewer --handoffs-dir "$handoffs_dir"
    [ "$status" -eq 0 ]
    local second="$output"

    [ "$first" = "$second" ]
}

# -----------------------------------------------------------------------------
# L7 — loa-l7-surface-soul.sh (the wrapper hook itself; has a real test-mode
# injection point via LOA_SOUL_TEST_MODE/_CONFIG/_PATH)
# -----------------------------------------------------------------------------

@test "L7: loa-l7-surface-soul.sh is byte-deterministic across two runs against a fixed SOUL.md" {
    local hook="$PROJECT_ROOT/.claude/hooks/session-start/loa-l7-surface-soul.sh"
    [[ -f "$hook" ]] || skip "L7 SessionStart hook not present"

    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"
    export LOA_SOUL_TEST_MODE=1
    export LOA_SOUL_LOG="$TEST_DIR/soul-events.jsonl"
    export LOA_SOUL_TEST_CONFIG="$TEST_DIR/.loa.config.yaml"
    export LOA_SOUL_TEST_PATH="$TEST_DIR/SOUL.md"
    cp "$FIXTURES/soul/config.yaml" "$LOA_SOUL_TEST_CONFIG"
    cp "$FIXTURES/soul/SOUL.md" "$LOA_SOUL_TEST_PATH"

    run "$hook"
    [ "$status" -eq 0 ]
    local first="$output"
    [[ "$first" == *"What I am"* ]]

    run "$hook"
    [ "$status" -eq 0 ]
    local second="$output"

    [ "$first" = "$second" ]
}

# -----------------------------------------------------------------------------
# post-compact-reminder.sh (UserPromptSubmit, every turn) — no bats-marker
# test-mode seam exists; the hook resolves state purely from PROJECT_ROOT/HOME
# so it is exercised hermetically via those two env vars redirected to a
# sandbox, per the hook's own documented marker-resolution order (PROJECT
# marker preferred over GLOBAL). The marker is deleted after each run
# (one-shot delivery, by design — M7 in the hook's own history) so it is
# re-seeded from the fixed fixture before each of the two runs.
# -----------------------------------------------------------------------------

_seed_compact_marker() {
    mkdir -p "$TEST_DIR/sandbox/.run"
    cp "$FIXTURES/compact-marker.json" "$TEST_DIR/sandbox/.run/compact-pending"
}

@test "post-compact-reminder.sh: byte-deterministic across two runs against a fixed marker" {
    local hook="$PROJECT_ROOT/.claude/hooks/post-compact-reminder.sh"
    [[ -x "$hook" ]]

    mkdir -p "$TEST_DIR/home"

    _seed_compact_marker
    run env PROJECT_ROOT="$TEST_DIR/sandbox" HOME="$TEST_DIR/home" bash "$hook"
    [ "$status" -eq 0 ]
    local first="$output"
    [[ "$first" == *"CONTEXT COMPACTION DETECTED"* ]]

    _seed_compact_marker
    run env PROJECT_ROOT="$TEST_DIR/sandbox" HOME="$TEST_DIR/home" bash "$hook"
    [ "$status" -eq 0 ]
    local second="$output"

    [ "$first" = "$second" ]
}

@test "post-compact-reminder.sh: output never contains a raw ISO-8601 timestamp" {
    # Regression guard: the hook's one genuine timestamp (_pc_ts) is written
    # only to grimoires/loa/a2a/trajectory/compact-events.jsonl, never into
    # the injected reminder text. A future edit that spliced $(date)/strftime
    # output into the visible reminder would defeat prompt caching on every
    # compaction event; this assertion fails loudly if that regresses.
    local hook="$PROJECT_ROOT/.claude/hooks/post-compact-reminder.sh"
    [[ -x "$hook" ]]

    mkdir -p "$TEST_DIR/home"
    _seed_compact_marker
    run env PROJECT_ROOT="$TEST_DIR/sandbox" HOME="$TEST_DIR/home" bash "$hook"
    [ "$status" -eq 0 ]

    ! grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' <<< "$output"
}
