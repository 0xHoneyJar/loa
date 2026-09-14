#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRATCH="$(mktemp -d)"
    mkdir -p "$SCRATCH/.run/bridge-reviews" "$SCRATCH/scripts"
}
teardown() { rm -rf "$SCRATCH"; }

@test "#1036 DEGRADED triage is explicit in the HITL handoff marker" {
    cd "$SCRATCH"
    eval "$(sed -n '/^phase_bridgebuilder_review() {/,/^}/p' "$REPO/.claude/scripts/post-pr-orchestrator.sh")"
    SCRIPT_DIR="$SCRATCH/scripts"
    STATE_SCRIPT="$SCRIPT_DIR/state"
    STATE_BRIDGEBUILDER_REVIEW=BRIDGEBUILDER_REVIEW
    STATE_HALTED=HALTED
    TIMEOUT_BRIDGEBUILDER_REVIEW=1
    log_phase() { :; }; log_info() { echo "$*"; }; log_success() { echo "$*"; }; log_error() { echo "$*"; }
    _update_phase() { :; }; update_state() { :; }
    run_with_timeout() { return 0; }
    tally_mediums() { echo '0:'; }; emit_mediums_warning() { :; }
    yq() { case "$1" in *depth*) echo 1;; *) echo true;; esac; }
    printf '#!/bin/sh\necho 42\n' > "$STATE_SCRIPT"
    printf '#!/bin/sh\nexit 0\n' > "$SCRIPT_DIR/bridge-orchestrator.sh"
    cat > "$SCRIPT_DIR/post-pr-triage.sh" <<'SH'
#!/bin/sh
printf '%s\n' '{"state":"DEGRADED","reason":"corrupt_findings"}' > .run/bridge-triage-convergence.json
exit 3
SH
    chmod +x "$SCRIPT_DIR/"*
    run phase_bridgebuilder_review
    [ "$status" -eq 0 ]
    [[ "$output" == *DEGRADED* ]]
    [ -f .run/post-pr-degraded-summary.json ]
    [ "$(jq -r .state .run/post-pr-degraded-summary.json)" = DEGRADED ]
    [ "$(jq -r .pr_number .run/post-pr-degraded-summary.json)" = 42 ]
    eval "$(sed -n '/^surface_degraded_handoff() {/,/^}/p' "$REPO/.claude/scripts/post-pr-orchestrator.sh")"
    run surface_degraded_handoff
    [[ "$output" == *"READY_FOR_HITL includes a DEGRADED"* ]]
    # A later clean phase must clear the earlier run's marker.
    printf '#!/bin/sh\nprintf '\''%%s\n'\'' '\''{"state":"FLATLINE"}'\'' > .run/bridge-triage-convergence.json\n' > "$SCRIPT_DIR/post-pr-triage.sh"
    phase_bridgebuilder_review
    [ ! -e .run/post-pr-degraded-summary.json ]
}

bridge_fixture() {
    cd "$SCRATCH"
    mkdir -p .claude/scripts grimoires/loa
    cp "$REPO/.claude/scripts/"{bridge-orchestrator.sh,bridge-state.sh,bootstrap.sh,path-lib.sh,compat-lib.sh} .claude/scripts/
    printf 'run_bridge:\n  enabled: true\n  rtfm:\n    enabled: false\n' > .loa.config.yaml
    echo '# Sprint' > grimoires/loa/sprint.md
    git init -q -b feature/test
    git -c user.name=Fixture -c user.email=fixture@example.com commit -qm fixture --allow-empty
}

@test "#1174 unrelated findings cannot make an undriven bridge JACKED_OUT" {
    bridge_fixture
    printf '%s\n' '{"findings":[{"id":"stale"}]}' > .run/bridge-reviews/unrelated.json
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --depth 1
    [ "$status" -eq 3 ]
    [ "$(jq -r .state .run/bridge-state.json)" = HALTED ]
}

@test "#1174 current-run empty findings still halt, while --allow-empty is explicit" {
    bridge_fixture
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --depth 1 --single-iteration
    [ "$status" -eq 0 ]
    local id="$(jq -r .bridge_id .run/bridge-state.json)"
    printf '%s\n' '{"findings":[]}' > ".run/bridge-reviews/${id}-iter1-findings.json"
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume
    [ "$status" -eq 3 ]
    printf '%s\n' '{"findings":[null]}' > ".run/bridge-reviews/${id}-iter1-findings.json"
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume
    [ "$status" -eq 3 ]
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume --allow-empty
    [ "$status" -eq 0 ]
    [ "$(jq -r .state .run/bridge-state.json)" = JACKED_OUT ]
}

@test "#1174 a current-run finding is real work even without sprint changes" {
    bridge_fixture
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --depth 1 --single-iteration
    [ "$status" -eq 0 ]
    local id="$(jq -r .bridge_id .run/bridge-state.json)"
    printf '%s\n' '{"findings":[{"id":"F1","severity":"HIGH"}]}' > ".run/bridge-reviews/${id}-iter1-findings.json"
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume
    [ "$status" -eq 0 ]
}

@test "#1174 new commits since JACK_IN count as work on resume" {
    bridge_fixture
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --depth 1 --single-iteration
    [ "$status" -eq 0 ]
    echo implemented > work.txt
    git add work.txt
    git -c user.name=Fixture -c user.email=fixture@example.com commit -qm work
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume
    [ "$status" -eq 0 ]
}

@test "#1025 malformed verdict status or health forces triage DEGRADED, including empty findings" {
    cd "$SCRATCH"
    cp "$REPO/.claude/scripts/"{post-pr-triage.sh,compat-lib.sh} scripts/
    for invalid in 'false' '{"status":"APPROVED","chain_health":{}}' '[]' '{"status":{},"chain_health":"ok"}'; do
        jq -n --argjson vq "$invalid" '{findings:[],verdict_quality:$vq}' > .run/bridge-reviews/bridge-test-iter1-findings.json
        run bash scripts/post-pr-triage.sh --pr 42 --review-dir "$SCRATCH/.run/bridge-reviews"
        [ "$status" -eq 3 ]
        [ "$(jq -r .state .run/bridge-triage-convergence.json)" = DEGRADED ]
        [ "$(jq -r .parse_failures .run/bridge-triage-convergence.json)" -gt 0 ]
    done
}

@test "#1174 recorded sprint metrics count as work without findings" {
    bridge_fixture
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --depth 1 --single-iteration
    [ "$status" -eq 0 ]
    jq '.metrics.total_sprints_executed=1' .run/bridge-state.json > .run/metric.tmp
    mv .run/metric.tmp .run/bridge-state.json
    run env PROJECT_ROOT="$SCRATCH" bash .claude/scripts/bridge-orchestrator.sh --resume
    [ "$status" -eq 0 ]
}
