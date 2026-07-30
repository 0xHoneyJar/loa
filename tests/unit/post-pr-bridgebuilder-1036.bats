#!/usr/bin/env bats
# =============================================================================
# #1036 — DEGRADED Bridgebuilder triage must be visible at READY_FOR_HITL
# =============================================================================
# post-pr-triage.sh honestly records state=DEGRADED in the convergence file
# (and exits 3) when a findings artifact failed to parse. The orchestrator
# treats the triage exit as non-fatal, so pre-fix the post-loop block fell into
# the `else` arm and logged the same benign wording as an ordinary
# non-converged pass, then handed off at READY_FOR_HITL with no distinct
# marker. `grep -c DEGRADED post-pr-orchestrator.sh` was 0.
#
# `phase_bridgebuilder_review` cannot be exercised standalone (it needs a PR,
# the bridge orchestrator and the /run-bridge SIGNAL:* harness), so the branch
# contract is pinned statically — the same technique used by
# post-pr-bridgebuilder-1076.bats — and the observable state it produces is
# pinned functionally through a real post-pr-state.sh round-trip.
#
# SCOPE: visibility only. Halt semantics stay on the #969 line; the phase
# status and the iteration guard are deliberately untouched.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCH="$REPO_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    STATE="$REPO_ROOT/.claude/scripts/post-pr-state.sh"
    [[ -f "$ORCH" ]] || skip "post-pr-orchestrator.sh not found"
    [[ -f "$STATE" ]] || skip "post-pr-state.sh not found"

    TMP="$(mktemp -d)"

    # Line anchors for the post-loop convergence report block.
    L_FLAT=$(grep -n 'if \[\[ "\$convergence_state" == "FLATLINE" \]\]; then' "$ORCH" | head -1 | cut -d: -f1)
    L_DEG=$(grep -n 'elif \[\[ "\$convergence_state" == "DEGRADED" \]\]; then' "$ORCH" | head -1 | cut -d: -f1)
    L_ELSE=$(grep -n 'Max iterations (\$max_iters) reached without flatline' "$ORCH" | head -1 | cut -d: -f1)
}

teardown() {
    [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
    return 0
}

# Body of the DEGRADED arm: everything between the elif and the else arm.
_degraded_body() {
    awk -v a="$L_DEG" -v b="$L_ELSE" 'NR>a && NR<b' "$ORCH"
}

# Body of the FLATLINE arm: everything between the if and the elif.
_flatline_body() {
    awk -v a="$L_FLAT" -v b="$L_DEG" 'NR>a && NR<b' "$ORCH"
}

# The BRIDGEBUILDER_REVIEW case arm of run_orchestration (the HITL transition).
_hitl_arm() {
    awk '/^    "\$STATE_BRIDGEBUILDER_REVIEW"\)/{f=1} f{print} f && /^      ;;/{exit}' "$ORCH"
}

# Build a real state file via init so the functional round-trip is honest.
# The dir must pre-exist: cmd_init acquires its lock (a mkdir under STATE_DIR)
# before it creates STATE_DIR, so a missing dir stalls for the whole lock
# timeout instead of initializing.
_init_state() {
    mkdir -p "$TMP/state"
    STATE_DIR="$TMP/state" "$STATE" init \
        --pr-url "https://github.com/0xHoneyJar/loa/pull/1036" \
        --pr-number 1036 \
        --branch "feature/cycle-123-bug-burndown" \
        --mode autonomous >/dev/null
}

# =========================================================================
# Static branch contract (AC-1, AC-2, AC-6, AC-7 + scope guards)
# =========================================================================

@test "#1036 AC-1: a DEGRADED arm exists in the post-loop convergence block" {
    [ -n "$L_FLAT" ]
    [ -n "$L_DEG" ]
    [ -n "$L_ELSE" ]
    [ "$L_FLAT" -lt "$L_DEG" ]
}

@test "#1036 AC-1: the DEGRADED arm logs an error naming the convergence file" {
    run bash -c '_b() { awk -v a="'"$L_DEG"'" -v b="'"$L_ELSE"'" "NR>a && NR<b" "'"$ORCH"'"; }; _b | grep -c "log_error.*convergence_file"'
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "#1036 AC-1: the DEGRADED arm reads .reason out of that convergence file" {
    _degraded_body > "$TMP/body.txt"
    grep -q '\.reason' "$TMP/body.txt"
    grep -q '"\$convergence_file"' "$TMP/body.txt"
}

@test "#1036 AC-2: the DEGRADED arm precedes the non-converged wording (so it is never reached)" {
    [ "$L_DEG" -lt "$L_ELSE" ]
    # And the DEGRADED arm itself does not repeat that benign wording.
    _degraded_body > "$TMP/body.txt"
    run grep -q 'reached without flatline' "$TMP/body.txt"
    [ "$status" -ne 0 ]
}

@test "#1036 AC-3: the DEGRADED arm records the convergence field via post-pr-state.sh set" {
    _degraded_body > "$TMP/body.txt"
    grep -q 'set bridgebuilder_convergence_state DEGRADED' "$TMP/body.txt"
}

@test "#1036 AC-3/AC-4: the DEGRADED arm adds the marker via the native add-marker command" {
    _degraded_body > "$TMP/body.txt"
    grep -q 'add-marker PR-BB-DEGRADED' "$TMP/body.txt"
    # Must use the state script's own mechanism, not a hand-rolled file write.
    grep -q '"\$STATE_SCRIPT" add-marker PR-BB-DEGRADED' "$TMP/body.txt"
}

@test "#1036 AC-6: the FLATLINE arm still logs success and creates no degraded marker" {
    _flatline_body > "$TMP/flat.txt"
    grep -q 'log_success "Kaironic convergence reached' "$TMP/flat.txt"
    run grep -q 'PR-BB-DEGRADED' "$TMP/flat.txt"
    [ "$status" -ne 0 ]
}

@test "#1036 AC-7: the DEGRADED arm does not touch the bridgebuilder_review phase status" {
    _degraded_body > "$TMP/body.txt"
    run grep -q '_update_phase bridgebuilder_review' "$TMP/body.txt"
    [ "$status" -ne 0 ]
    # The completed status still comes from the bridge-exit-0 classifier.
    grep -q '_update_phase bridgebuilder_review completed' "$ORCH"
}

@test "#1036 scope: the iteration guard is unchanged (DEGRADED does not stop the loop)" {
    run grep -c 'while \[\[ \$iter -lt \$max_iters \]\] && \[\[ "\$convergence_state" != "FLATLINE" \]\]; do' "$ORCH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "#1036 scope: no new library is sourced by the orchestrator" {
    run grep -cE '^source ' "$ORCH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
}

# =========================================================================
# READY_FOR_HITL transition warning (AC-5)
# =========================================================================

@test "#1036 AC-5: the HITL transition reads the convergence field and guards on DEGRADED" {
    _hitl_arm > "$TMP/hitl.txt"
    # The arm must exist and still perform the transition.
    grep -q 'update_state "\$STATE_READY_FOR_HITL"' "$TMP/hitl.txt"
    grep -q 'get bridgebuilder_convergence_state' "$TMP/hitl.txt"
    grep -q '== "DEGRADED"' "$TMP/hitl.txt"
}

@test "#1036 AC-5: the HITL guard wraps exactly one warning line" {
    _hitl_arm > "$TMP/hitl.txt"
    run grep -cE 'log_(error|info|success) .*DEGRADED' "$TMP/hitl.txt"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "#1036 AC-5: the unconditional success line survives the added guard" {
    _hitl_arm > "$TMP/hitl.txt"
    grep -q 'log_success "Post-PR validation complete - READY_FOR_HITL"' "$TMP/hitl.txt"
}

# =========================================================================
# Functional post-pr-state.sh round-trip (AC-3, AC-4, AC-5, AC-7)
# =========================================================================

@test "#1036 AC-3: set/get round-trip persists bridgebuilder_convergence_state=DEGRADED" {
    _init_state
    run env STATE_DIR="$TMP/state" "$STATE" set bridgebuilder_convergence_state DEGRADED
    [ "$status" -eq 0 ]
    run jq -r '.bridgebuilder_convergence_state' "$TMP/state/post-pr-state.json"
    [ "$status" -eq 0 ]
    [ "$output" = "DEGRADED" ]
    run env STATE_DIR="$TMP/state" "$STATE" get bridgebuilder_convergence_state
    [ "$status" -eq 0 ]
    [ "$output" = "DEGRADED" ]
}

@test "#1036 AC-3: add-marker puts PR-BB-DEGRADED in the state markers array" {
    _init_state
    run env STATE_DIR="$TMP/state" "$STATE" add-marker PR-BB-DEGRADED
    [ "$status" -eq 0 ]
    run jq -r '.markers | index("PR-BB-DEGRADED") // "absent"' "$TMP/state/post-pr-state.json"
    [ "$status" -eq 0 ]
    [ "$output" != "absent" ]
}

@test "#1036 AC-4: add-marker creates the PR-BB-DEGRADED marker file in the state dir" {
    _init_state
    env STATE_DIR="$TMP/state" "$STATE" add-marker PR-BB-DEGRADED >/dev/null
    [ -f "$TMP/state/.PR-BB-DEGRADED" ]
    run jq -r '.marker' "$TMP/state/.PR-BB-DEGRADED"
    [ "$output" = "PR-BB-DEGRADED" ]
}

@test "#1036 AC-5: the guard predicate is false when the field is unset" {
    _init_state
    # Reproduce the orchestrator's guard read verbatim against a virgin state.
    local bb
    bb=$(env STATE_DIR="$TMP/state" "$STATE" get bridgebuilder_convergence_state 2>/dev/null || echo "")
    [ "$bb" != "DEGRADED" ]
    [ -z "$bb" ]
}

@test "#1036 AC-6: a FLATLINE run leaves no PR-BB-DEGRADED marker behind" {
    _init_state
    run jq -r '.markers | length' "$TMP/state/post-pr-state.json"
    [ "$output" -eq 0 ]
    [ ! -f "$TMP/state/.PR-BB-DEGRADED" ]
}

@test "#1036 AC-7: bridgebuilder_review stays 'completed' alongside a DEGRADED field" {
    _init_state
    env STATE_DIR="$TMP/state" "$STATE" update-phase bridgebuilder_review completed >/dev/null
    env STATE_DIR="$TMP/state" "$STATE" set bridgebuilder_convergence_state DEGRADED >/dev/null
    run jq -r '.phases.bridgebuilder_review' "$TMP/state/post-pr-state.json"
    [ "$output" = "completed" ]
    run env STATE_DIR="$TMP/state" "$STATE" validate
    [ "$status" -eq 0 ]
}
