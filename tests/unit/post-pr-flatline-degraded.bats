#!/usr/bin/env bats
# =============================================================================
# sprint-bug-267 (bug 20261021-4439fd, bead bd-jm55c) — the Flatline PR phase
# reads the verdict-quality envelope; a degraded or failed review never reads
# green.
# =============================================================================
# Before the fix, phase_flatline_pr ignored the Flatline orchestrator's JSON
# output: exit 0 meant `completed` + PR-VALIDATED even when the envelope said
# DEGRADED (one voice of three, fleet incident 2026-10-20), and a timeout or a
# non-blocker failure was recorded `skipped`.
#
# These tests drive the real post-pr-orchestrator.sh with --resume from
# E2E_TESTING inside a scratch project whose .claude/scripts holds copies of
# the orchestrator, the state script and their libraries plus a STUB
# flatline-orchestrator.sh (prints a chosen envelope, exits with a chosen
# code). The repository's own .run/ is never touched.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCH="$REPO_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [[ -f "$ORCH" ]] || skip "post-pr-orchestrator.sh not found"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    command -v yq >/dev/null 2>&1 || skip "yq not installed"

    PROJ="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$PROJ/.claude/scripts/lib" "$PROJ/.run"
    local f
    for f in post-pr-orchestrator.sh post-pr-state.sh compat-lib.sh; do
        cp "$REPO_ROOT/.claude/scripts/$f" "$PROJ/.claude/scripts/$f"
    done
    for f in flatline-exit-classifier.sh bridge-mediums-summary.sh; do
        cp "$REPO_ROOT/.claude/scripts/lib/$f" "$PROJ/.claude/scripts/lib/$f"
    done

    # Stub Flatline orchestrator: prints the file $STUB_OUT to stdout, logs a
    # line to stderr, optionally sleeps, exits $STUB_EXIT. Records its argv.
    cat > "$PROJ/.claude/scripts/flatline-orchestrator.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${STUB_ARGS_FILE:-/dev/null}"
echo "[flatline-stub] running" >&2
if [[ -n "${STUB_SLEEP:-}" ]]; then sleep "$STUB_SLEEP"; fi
if [[ -n "${STUB_OUT:-}" && -f "$STUB_OUT" ]]; then cat "$STUB_OUT"; fi
exit "${STUB_EXIT:-0}"
SH
    chmod +x "$PROJ/.claude/scripts/"*.sh

    printf 'flatline_protocol:\n  enabled: true\n' > "$PROJ/.loa.config.yaml"

    cd "$PROJ"
    unset STATE_DIR
    export STUB_ARGS_FILE="$BATS_TEST_TMPDIR/stub-args"
    export STUB_OUT="$BATS_TEST_TMPDIR/stub-out.json"
    bash .claude/scripts/post-pr-state.sh init \
        --pr-url "https://github.com/example/repo/pull/42" \
        --branch "fix/test" --mode autonomous 2>/dev/null
    bash .claude/scripts/post-pr-state.sh set state E2E_TESTING 2>/dev/null
    bash .claude/scripts/post-pr-state.sh update-phase e2e_testing completed 2>/dev/null

    SUMMARY="$PROJ/.run/post-pr-degraded-summary.json"
}

# Write the stub's stdout envelope (field names as flatline-orchestrator.sh
# and loa_cheval/verdict/quality.py emit them).
_envelope() {
    local status="$1" planned="$2" succeeded="$3"
    jq -n --arg s "$status" --argjson p "$planned" --argjson c "$succeeded" '{
        phase: "pr",
        blockers: [],
        degraded: ($s != "APPROVED"),
        degraded_models: (if $s == "APPROVED" then [] else ["claude-headless"] end),
        verdict_quality: {status: $s, voices_planned: $p, voices_succeeded: $c}
    }' > "$STUB_OUT"
}

_resume() {
    run bash .claude/scripts/post-pr-orchestrator.sh \
        --pr-url "https://github.com/example/repo/pull/42" --resume
}

_get() { bash .claude/scripts/post-pr-state.sh get "$1" 2>/dev/null; }
_markers() { jq -r '.markers[]' "$PROJ/.run/post-pr-state.json"; }

# The failed-not-green contract shared by every non-APPROVED outcome.
_assert_failed_not_green() {
    local reason="$1"
    [ "$status" -eq 0 ]
    [ "$(_get phases.flatline_pr)" = "failed" ]
    [ "$(_get state)" = "READY_FOR_HITL" ]
    _markers | grep -qx 'FLATLINE-PR-DEGRADED'
    run _markers
    [[ "$output" != *"PR-VALIDATED"* ]]
    [ ! -e "$PROJ/.run/.PR-VALIDATED" ]
    [ -f "$SUMMARY" ]
    [ "$(jq -r .state "$SUMMARY")" = "DEGRADED" ]
    [ "$(jq -r .phase "$SUMMARY")" = "flatline_pr" ]
    [ "$(jq -r .pr_number "$SUMMARY")" = "42" ]
    [ "$(jq -r .reason "$SUMMARY")" = "$reason" ]
}

@test "PFD-1: exit 0 with verdict_quality DEGRADED (1 of 3 voices) is failed + FLATLINE-PR-DEGRADED, never PR-VALIDATED" {
    _envelope DEGRADED 3 1
    export STUB_EXIT=0
    _resume
    local out="$output"
    _assert_failed_not_green "verdict_quality_degraded"
    [ "$(jq -r .status "$SUMMARY")" = "DEGRADED" ]
    [ "$(jq -r .voices_planned "$SUMMARY")" = "3" ]
    [ "$(jq -r .voices_completed "$SUMMARY")" = "1" ]
    [ "$(jq -r '.degraded_models[0]' "$SUMMARY")" = "claude-headless" ]
    # The orchestrator was asked for JSON and its output was captured.
    grep -q -- '--json' "$STUB_ARGS_FILE"
    [ -f "$PROJ/.run/post-pr-flatline-pr.json" ]
    # The HITL handoff names the degraded Flatline review.
    [[ "$out" == *"DEGRADED Flatline PR review"* ]]
}

@test "PFD-2: exit 0 with verdict_quality APPROVED (3 of 3) stays completed + PR-VALIDATED (control)" {
    _envelope APPROVED 3 3
    export STUB_EXIT=0
    _resume
    [ "$status" -eq 0 ]
    [ "$(_get phases.flatline_pr)" = "completed" ]
    [ "$(_get state)" = "READY_FOR_HITL" ]
    _markers | grep -qx 'PR-VALIDATED'
    run _markers
    [[ "$output" != *"FLATLINE-PR-DEGRADED"* ]]
    [ ! -e "$SUMMARY" ]
}

@test "PFD-3: exit 0 with verdict_quality FAILED is failed, never PR-VALIDATED" {
    _envelope FAILED 3 0
    export STUB_EXIT=0
    _resume
    _assert_failed_not_green "verdict_quality_failed"
    [ "$(jq -r .status "$SUMMARY")" = "FAILED" ]
    [ "$(jq -r .voices_completed "$SUMMARY")" = "0" ]
}

@test "PFD-4: a timed-out Flatline run is failed with reason timeout, not skipped" {
    _envelope APPROVED 3 3
    export STUB_EXIT=0 STUB_SLEEP=5 TIMEOUT_FLATLINE_PR=1
    _resume
    _assert_failed_not_green "timeout"
}

@test "PFD-5: a non-blocker Flatline failure (exit 3) is failed with reason exit_3, not skipped" {
    rm -f "$STUB_OUT"
    export STUB_EXIT=3
    _resume
    _assert_failed_not_green "exit_3"
}

@test "PFD-5b: the Flatline orchestrator's own degraded exit (6) with a DEGRADED envelope is failed, voices carried" {
    _envelope DEGRADED 3 1
    export STUB_EXIT=6
    _resume
    _assert_failed_not_green "exit_6"
    [ "$(jq -r .status "$SUMMARY")" = "DEGRADED" ]
    [ "$(jq -r .voices_completed "$SUMMARY")" = "1" ]
}

@test "PFD-6a: exit 0 with non-JSON output fails closed (no_verdict_quality)" {
    printf 'not json at all\n' > "$STUB_OUT"
    export STUB_EXIT=0
    _resume
    _assert_failed_not_green "no_verdict_quality"
}

@test "PFD-6b: exit 0 with JSON lacking verdict_quality fails closed (no_verdict_quality)" {
    printf '{"blockers":[],"phase":"pr"}\n' > "$STUB_OUT"
    export STUB_EXIT=0
    _resume
    _assert_failed_not_green "no_verdict_quality"
}

@test "PFD-6c: exit 0 with no output at all fails closed (no_verdict_quality)" {
    rm -f "$STUB_OUT"
    export STUB_EXIT=0
    _resume
    _assert_failed_not_green "no_verdict_quality"
}

@test "PFD-7: static contract — doc-comment states the rule; only the disabled branch records skipped" {
    local body
    body="$(sed -n '/^phase_flatline_pr() {/,/^}/p' "$ORCH")"
    [ -n "$body" ]
    # Exactly one 'flatline_pr skipped' write remains, in the enabled:false branch.
    [ "$(grep -c 'flatline_pr skipped' <<<"$body")" -eq 1 ]
    grep -B3 'flatline_pr skipped' <<<"$body" | grep -q 'disabled'
    # The comment block directly above the function names the rule and marker.
    local doc
    doc="$(awk '/^#/{buf=buf $0 "\n"; next} /^phase_flatline_pr\(\) \{/{printf "%s", buf; exit} {buf=""}' "$ORCH")"
    [[ "$doc" == *"verdict_quality"* ]]
    [[ "$doc" == *"FLATLINE-PR-DEGRADED"* ]]
    [[ "$doc" == *"failed"* ]]
}

# --- Round 1 (DISS-C-002, DISS-C-003) ---------------------------------------

@test "PFD-8: Flatline enabled but the orchestrator is missing fails with reason orchestrator_missing" {
    rm -f "$PROJ/.claude/scripts/flatline-orchestrator.sh"
    _resume
    local out="$output"
    _assert_failed_not_green "orchestrator_missing"
    [[ "$out" == *"Flatline orchestrator was not found at"* ]]
}

@test "PFD-9: Flatline and Bridgebuilder both DEGRADED — the Flatline summary rides under .previous and the hand-off names both" {
    _envelope DEGRADED 3 1
    export STUB_EXIT=0
    # Enable the real Bridgebuilder phase (depth 1) with stubs: the bridge
    # exits 0, triage reports a DEGRADED convergence.
    printf 'flatline_protocol:\n  enabled: true\npost_pr_validation:\n  phases:\n    bridgebuilder_review:\n      enabled: true\n      depth: 1\n' \
        > "$PROJ/.loa.config.yaml"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$PROJ/.claude/scripts/bridge-orchestrator.sh"
    cat > "$PROJ/.claude/scripts/post-pr-triage.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"state":"DEGRADED","reason":"corrupt_findings"}' > .run/bridge-triage-convergence.json
exit 0
SH
    chmod +x "$PROJ/.claude/scripts/bridge-orchestrator.sh" "$PROJ/.claude/scripts/post-pr-triage.sh"
    _resume
    local out="$output"
    [ "$status" -eq 0 ]
    [ "$(_get state)" = "READY_FOR_HITL" ]
    [ "$(_get phases.flatline_pr)" = "failed" ]
    _markers | grep -qx 'FLATLINE-PR-DEGRADED'
    [ "$(jq -r .phase "$SUMMARY")" = "bridgebuilder_review" ]
    [ "$(jq -r .state "$SUMMARY")" = "DEGRADED" ]
    [ "$(jq -r .previous.phase "$SUMMARY")" = "flatline_pr" ]
    [ "$(jq -r .previous.reason "$SUMMARY")" = "verdict_quality_degraded" ]
    [ "$(jq -r .previous.voices_completed "$SUMMARY")" = "1" ]
    [[ "$out" == *"DEGRADED Bridgebuilder review and a DEGRADED Flatline PR review"* ]]
}
