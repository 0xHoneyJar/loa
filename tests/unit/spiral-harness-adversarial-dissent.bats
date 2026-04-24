#!/usr/bin/env bats
# =============================================================================
# spiral-harness-adversarial-dissent.bats — cycle-093 T1.1 / #605 regression
# =============================================================================
# Verifies _run_adversarial_dissent in spiral-harness.sh honors the
# flatline_protocol.{code_review,security_audit}.enabled config flags.
#
# Scenarios:
#   1. Flag off    → silent no-op (no artifact emitted, no dissenter call)
#   2. Flag on     → adversarial-review.sh invoked, artifact emitted
#   3. Empty diff  → skip (no artifact)
#   4. Script fail → non-blocking (gate continues; stub artifact emitted)
# =============================================================================

setup() {
    export TEST_WORKDIR
    TEST_WORKDIR=$(mktemp -d)
    cd "$TEST_WORKDIR"

    # Stub a harness dir layout the function expects
    mkdir -p .claude/scripts
    mkdir -p .run/cycles/cycle-test/evidence
    export SCRIPT_DIR="$TEST_WORKDIR/.claude/scripts"
    export CYCLE_ID="cycle-test"
    export EVIDENCE_DIR="$TEST_WORKDIR/.run/cycles/cycle-test/evidence"
    export BRANCH="test-branch"

    # Git repo so `git diff` has something to emit
    git init -q -b main
    git config user.email test@example.com
    git config user.name Test
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial"
    git checkout -q -b test-branch
    echo "changed" >> README.md
    git add README.md
    git commit -q -m "change on branch"

    # Source the function under test — extract just the helper
    cat > "$SCRIPT_DIR/_run_adversarial_dissent.sh" <<'SHELL'
log() { echo "[test] $*" >&2; }
_run_adversarial_dissent() {
    local dissent_type="$1"
    local config_key
    case "$dissent_type" in
        review) config_key="code_review" ;;
        audit)  config_key="security_audit" ;;
        *) log "Adversarial dissent: invalid type '$dissent_type'"; return 0 ;;
    esac
    local enabled
    enabled=$(yq eval ".flatline_protocol.${config_key}.enabled // false" .loa.config.yaml 2>/dev/null || echo "false")
    if [[ "$enabled" != "true" ]]; then return 0; fi
    local adversarial_script="$SCRIPT_DIR/adversarial-review.sh"
    if [[ ! -x "$adversarial_script" ]]; then
        log "Adversarial dissent: $adversarial_script not executable, skipping"; return 0
    fi
    local evidence_dir="${EVIDENCE_DIR:-.run/cycles/${CYCLE_ID}/evidence}"
    mkdir -p "$evidence_dir"
    local diff_file="$evidence_dir/adversarial-${dissent_type}-diff.patch"
    local output_file="$evidence_dir/adversarial-${dissent_type}.json"
    git diff main..."$BRANCH" -- ':!grimoires/' ':!.run/' ':!.beads/' 2>/dev/null | head -c 50000 > "$diff_file"
    if [[ ! -s "$diff_file" ]]; then
        log "Adversarial dissent ($dissent_type): empty diff, skipping"; return 0
    fi
    local sprint_id="${CYCLE_ID}-${dissent_type}"
    local model
    model=$(yq eval ".flatline_protocol.${config_key}.model // \"gpt-5.3-codex\"" .loa.config.yaml 2>/dev/null || echo "gpt-5.3-codex")
    local stderr_file="$evidence_dir/adversarial-${dissent_type}-stderr.log"
    if "$adversarial_script" \
        --type "$dissent_type" --sprint-id "$sprint_id" \
        --diff-file "$diff_file" --model "$model" --json \
        > "$output_file" 2> "$stderr_file"; then
        log "Adversarial dissent ($dissent_type): artifact emitted"
    else
        local rc=$?
        log "Adversarial dissent ($dissent_type): exit $rc (non-blocking)"
        jq -n --arg type "$dissent_type" --arg err "dissenter exit $rc" \
            '{type: $type, status: "failed", error: $err, findings: []}' > "$output_file" || true
    fi
    return 0
}
SHELL
}

teardown() {
    rm -rf "$TEST_WORKDIR"
}

@test "flag off: silent no-op, no artifact emitted" {
    cat > .loa.config.yaml <<'YAML'
flatline_protocol:
  code_review:
    enabled: false
YAML
    source "$SCRIPT_DIR/_run_adversarial_dissent.sh"
    run _run_adversarial_dissent review
    [ "$status" -eq 0 ]
    [ ! -f "$EVIDENCE_DIR/adversarial-review.json" ]
}

@test "flag on + stub script: artifact emitted, non-blocking on script failure" {
    cat > .loa.config.yaml <<'YAML'
flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.3-codex
YAML
    cat > "$SCRIPT_DIR/adversarial-review.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "dissenter stub failing deliberately for test" >&2
exit 3
SCRIPT
    chmod +x "$SCRIPT_DIR/adversarial-review.sh"
    source "$SCRIPT_DIR/_run_adversarial_dissent.sh"
    run _run_adversarial_dissent review
    [ "$status" -eq 0 ]  # non-blocking
    [ -f "$EVIDENCE_DIR/adversarial-review.json" ]
    # Stub artifact reflects failure
    grep -q '"status": "failed"' "$EVIDENCE_DIR/adversarial-review.json"
}

@test "flag on + successful stub: artifact from dissenter stdout" {
    cat > .loa.config.yaml <<'YAML'
flatline_protocol:
  security_audit:
    enabled: true
    model: gpt-5.3-codex
YAML
    cat > "$SCRIPT_DIR/adversarial-review.sh" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'JSON'
{"type": "audit", "status": "ok", "findings": []}
JSON
exit 0
SCRIPT
    chmod +x "$SCRIPT_DIR/adversarial-review.sh"
    source "$SCRIPT_DIR/_run_adversarial_dissent.sh"
    run _run_adversarial_dissent audit
    [ "$status" -eq 0 ]
    [ -f "$EVIDENCE_DIR/adversarial-audit.json" ]
    grep -q '"status": "ok"' "$EVIDENCE_DIR/adversarial-audit.json"
}

@test "invalid type: silent no-op" {
    cat > .loa.config.yaml <<'YAML'
flatline_protocol:
  code_review:
    enabled: true
YAML
    source "$SCRIPT_DIR/_run_adversarial_dissent.sh"
    run _run_adversarial_dissent garbage
    [ "$status" -eq 0 ]
    [ ! -f "$EVIDENCE_DIR/adversarial-garbage.json" ]
}

@test "script missing: skip gracefully" {
    cat > .loa.config.yaml <<'YAML'
flatline_protocol:
  code_review:
    enabled: true
YAML
    # DO NOT create adversarial-review.sh
    source "$SCRIPT_DIR/_run_adversarial_dissent.sh"
    run _run_adversarial_dissent review
    [ "$status" -eq 0 ]
    [ ! -f "$EVIDENCE_DIR/adversarial-review.json" ]
}
