#!/usr/bin/env bats
# =============================================================================
# voice-drop-classifier.bats — Tests for .claude/scripts/lib/voice-drop-classifier.sh
# =============================================================================
# Cycle-104 sprint-2 T2.8 (FR-S2.5). Pins the per-exit-code classification
# of a flatline call_model result into success | dropped | failed.
#
# Hermetic: classifier is a pure function; no fixtures, no network, no I/O
# beyond stdout/stderr.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CLASSIFIER="$PROJECT_ROOT/.claude/scripts/lib/voice-drop-classifier.sh"
}

# ---- Successful voice ------------------------------------------------------

@test "VDC-T1: exit 0 → success" {
    run "$CLASSIFIER" 0
    [ "$status" -eq 0 ]
    [ "$output" = "success" ]
}

# ---- Voice-drop (cheval CHAIN_EXHAUSTED = 12) -----------------------------

@test "VDC-T2: exit 12 (CHAIN_EXHAUSTED) → dropped" {
    run "$CLASSIFIER" 12
    [ "$status" -eq 0 ]
    [ "$output" = "dropped" ]
}

# ---- NO_ELIGIBLE_ADAPTER must NOT silently drop (config error) ------------

@test "VDC-T3: exit 11 (NO_ELIGIBLE_ADAPTER) → failed, NOT dropped" {
    # Per SDD §6.3, NO_ELIGIBLE_ADAPTER is a misconfig that operators must
    # see. If the classifier ever started mapping 11 → dropped, an operator
    # who configured a typo'd headless_mode would silently lose voices
    # without a diagnostic. Pin the rule.
    run "$CLASSIFIER" 11
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

# ---- INTERACTION_PENDING (8) ----------------------------------------------

@test "VDC-T4: exit 8 (INTERACTION_PENDING) → failed (not dropped)" {
    # cycle-098 pinned 8 to INTERACTION_PENDING. cheval rejects async-mode
    # multi-entry chains upfront so 8 cannot co-occur with chain walk,
    # but if it surfaces here we treat it as failed (operator action).
    run "$CLASSIFIER" 8
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

# ---- Common failure shapes ------------------------------------------------

@test "VDC-T5: exit 1 → failed" {
    run "$CLASSIFIER" 1
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

@test "VDC-T6: exit 124 (timeout) → failed" {
    run "$CLASSIFIER" 124
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

@test "VDC-T7: exit 137 (SIGKILL) → failed" {
    run "$CLASSIFIER" 137
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

# ---- Input validation -----------------------------------------------------

@test "VDC-T8: no args → usage on stderr, status 2" {
    run "$CLASSIFIER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "VDC-T9: non-integer arg rejected (must not silently classify as failed)" {
    # A bug where the wait-loop captures an unset variable would expand to
    # ""; if the classifier silently classified "" as failed, an "all
    # failed" hard error would be masked by drops. Pin: reject anything
    # non-numeric so the orchestrator sees the bug.
    run "$CLASSIFIER" "twelve"
    [ "$status" -eq 2 ]
    [[ "$output" == *"non-negative integer"* ]]
}

@test "VDC-T10: negative number rejected" {
    run "$CLASSIFIER" "-1"
    [ "$status" -eq 2 ]
}

@test "VDC-T11: --self-test passes" {
    run "$CLASSIFIER" --self-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
