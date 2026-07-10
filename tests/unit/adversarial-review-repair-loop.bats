#!/usr/bin/env bats
# =============================================================================
# adversarial-review-repair-loop.bats — cycle-119 C14 (KF-004 repair loop)
# =============================================================================
# Flag: flatline_protocol.code_review.repair_loop (default OFF).
#
# Covers the 4 non-negotiable safety constraints from the adversarial
# design panel:
#   1. normalization pre-pass BEFORE validate_finding: case-fold
#      severity/category + whitespace trim ONLY, no synonym mapping.
#   2. on residual validation failure: ONE bounded same-model repair
#      round-trip sending only the offending finding JSON + the violated
#      clause.
#   3. the repaired finding re-enters the FULL pipeline (validate_finding
#      + validate_anchor), never just the failed clause.
#   4. byte-diff immutability guard: every field except the violated
#      one(s) must be byte-identical to the rejected original.
#
# Also covers: sidecar repair_attempted/repair_succeeded booleans,
# rejected+repaired counts in metadata (flag-gated), and flag-off
# byte-identical legacy behavior.
#
# Uses the same source-based testing pattern as adversarial-review.bats:
# eval-sources the whole script (main() disabled) so process_findings and
# its helpers run for real, and mocks `_repair_finding_via_model` (the
# ONE function that talks to a model) by simple bash function shadowing —
# bash resolves function calls at call time, so a redefinition after
# sourcing wins over the real implementation.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    local saved_root="$PROJECT_ROOT"

    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"

    # Source the script functions (but don't run main)
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"

    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT

    # Defaults load_adversarial_config would set — repair_loop OFF unless
    # a test explicitly turns it on.
    CONF_ENABLED="true"
    CONF_MODEL="gpt-5.3-codex"
    CONF_TIMEOUT=60
    CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"
    CONF_SECONDARY_BUDGET=12000
    CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200
    CONF_SECRET_SCANNING="true"
    CONF_SECRET_ALLOWLIST=()
    CONF_REPAIR_LOOP="false"

    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
}

teardown() {
    if [[ -n "${_REPAIR_TEST_SPRINT:-}" ]]; then
        rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${_REPAIR_TEST_SPRINT}" 2>/dev/null || true
    fi
}

# Builds a raw model-adapter envelope wrapping a {findings:[...]} content
# payload, matching process_findings' expected shape.
_raw_envelope() {
    local content_json="$1"
    jq -n --arg c "$content_json" \
        '{content: $c, tokens_input: 100, tokens_output: 50, cost_usd: 0.01, latency_ms: 500}'
}

_sidecar_path() {
    local sprint_id="$1" type="$2"
    echo "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}/adversarial-rejected-${type}.jsonl"
}

# =============================================================================
# Constraint 1 — normalization pre-pass (case-fold + trim ONLY)
# =============================================================================

@test "C14: normalization allows a whitespace/case-mismatched finding to validate directly (no repair needed)" {
    CONF_REPAIR_LOOP="true"
    _REPAIR_TEST_SPRINT="sprint-c14-norm-$$"
    # anchor + matching diff_files so validate_anchor doesn't demote the
    # BLOCKING severity we're asserting on below — that's an orthogonal,
    # pre-existing anchor-validation concern, not what this test covers.
    local content='{"findings":[{"id":"DISS-001","severity":"  blocking ","category":" Injection ","anchor":"src/foo.ts:x","anchor_type":"function","scope":"diff","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "src/foo.ts")
    local count repaired
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    [[ "$count" == "1" ]]
    # Normalization alone fixed it — no repair round-trip was needed.
    [[ "$repaired" == "0" ]]
    local sev cat
    sev=$(echo "$result" | jq -r '.findings[0].severity')
    cat=$(echo "$result" | jq -r '.findings[0].category')
    [[ "$sev" == "BLOCKING" ]]
    [[ "$cat" == "injection" ]]
}

@test "C14: normalization does NOT synonym-map (a made-up severity is still rejected)" {
    CONF_REPAIR_LOOP="true"
    # Force repair to be unavailable so we isolate the normalization step.
    _repair_finding_via_model() { return 1; }
    _REPAIR_TEST_SPRINT="sprint-c14-nosyn-$$"
    local content='{"findings":[{"id":"DISS-001","severity":"warning","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    local count
    count=$(echo "$result" | jq '.findings | length')
    [[ "$count" == "0" ]]
}

@test "_normalize_finding_for_validation: leaves absent keys absent (no null keys introduced)" {
    local out
    out=$(_normalize_finding_for_validation '{"id":"x"}')
    [[ "$(echo "$out" | jq 'has("severity")')" == "false" ]]
    [[ "$(echo "$out" | jq 'has("category")')" == "false" ]]
}

# =============================================================================
# Constraint 4 — byte-diff immutability guard (pure function)
# =============================================================================

@test "_repair_diff_ok: accepts a repair that only touches the allowed field" {
    local orig='{"id":"x","severity":"blocking","category":"injection","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -eq 0 ]]
}

@test "_repair_diff_ok: rejects a repair that also mutates a non-violated field" {
    local orig='{"id":"x","severity":"blocking","category":"injection","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","category":"injection","description":"CHANGED","failure_mode":"fm"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -ne 0 ]]
}

@test "_repair_diff_ok: rejects a repair that adds a new field" {
    local orig='{"id":"x","severity":"blocking","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","description":"d","failure_mode":"fm","extra":"nope"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -ne 0 ]]
}

@test "_repair_violated_field: maps known reject reasons to their field" {
    [[ "$(_repair_violated_field "missing-severity")" == "severity" ]]
    [[ "$(_repair_violated_field "severity-not-in-enum (got: warning)")" == "severity" ]]
    [[ "$(_repair_violated_field "missing-category")" == "category" ]]
    [[ "$(_repair_violated_field "category-not-in-enum (got: bogus)")" == "category" ]]
    [[ "$(_repair_violated_field "missing-or-empty-description")" == "description" ]]
    [[ "$(_repair_violated_field "missing-or-empty-failure_mode")" == "failure_mode" ]]
    [[ "$(_repair_violated_field "missing-or-non-string-id")" == "id" ]]
    [[ "$(_repair_violated_field "something-unmapped")" == "" ]]
}

# =============================================================================
# Constraints 2+3 — repair succeeds, re-enters full pipeline
# =============================================================================

@test "C14: repair succeeds — mock model fixes only the violated field, finding is accepted" {
    CONF_REPAIR_LOOP="true"
    _REPAIR_TEST_SPRINT="sprint-c14-repair-ok-$$"

    # Mock: given the offending finding + violated clause, return the
    # same finding with ONLY failure_mode filled in.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.failure_mode = "npe on line 42"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"null-safety","anchor":"src/auth.ts:validateToken","description":"d","failure_mode":""}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "src/auth.ts")

    local count repaired rejected
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "1" ]]
    [[ "$repaired" == "1" ]]
    [[ "$rejected" == "0" ]]

    # Constraint 3: repaired finding passed through validate_anchor too
    # (anchor is in-diff so it should validate cleanly, not be demoted).
    local anchor_status
    anchor_status=$(echo "$result" | jq -r '.findings[0].anchor_status')
    [[ "$anchor_status" == "valid" ]]

    # No sidecar entry for a successfully-repaired finding.
    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    if [[ -f "$sidecar" ]]; then
        [[ ! -s "$sidecar" ]]
    fi
}

@test "C14: repair mutates a non-violated field — rejected with repair-mutated-nonviolated-field" {
    CONF_REPAIR_LOOP="true"
    _REPAIR_TEST_SPRINT="sprint-c14-repair-mutate-$$"

    # Mock: "fixes" failure_mode but ALSO rewrites description — violates
    # the byte-diff immutability guard.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.failure_mode = "npe" | .description = "totally different description"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"null-safety","description":"original","failure_mode":""}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count repaired rejected
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$repaired" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    local reason attempted succeeded
    reason=$(jq -r '.reject_reason' "$sidecar")
    attempted=$(jq -r '.repair_attempted' "$sidecar")
    succeeded=$(jq -r '.repair_succeeded' "$sidecar")
    [[ "$reason" == "repair-mutated-nonviolated-field" ]]
    [[ "$attempted" == "true" ]]
    [[ "$succeeded" == "false" ]]
}

@test "C14: repair unavailable (model call fails) — rejected, original reject_reason preserved, sidecar unchanged semantics" {
    CONF_REPAIR_LOOP="true"
    _REPAIR_TEST_SPRINT="sprint-c14-repair-fail-$$"

    # Mock: repair round-trip fails outright (e.g. timeout / API error twice).
    _repair_finding_via_model() { return 1; }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count rejected
    count=$(echo "$result" | jq '.findings | length')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    local reason attempted succeeded
    reason=$(jq -r '.reject_reason' "$sidecar")
    attempted=$(jq -r '.repair_attempted' "$sidecar")
    succeeded=$(jq -r '.repair_succeeded' "$sidecar")
    # Original reason (missing-or-empty-failure_mode), NOT overwritten.
    [[ "$reason" == "missing-or-empty-failure_mode" ]]
    [[ "$attempted" == "true" ]]
    [[ "$succeeded" == "false" ]]
}

@test "C14: repaired finding that is STILL invalid after repair — rejected with the repaired candidate's reason" {
    CONF_REPAIR_LOOP="true"
    _REPAIR_TEST_SPRINT="sprint-c14-repair-stillbad-$$"

    # Mock: "fixes" the field it was told about but leaves it invalid.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.severity = "SUPER_CRITICAL"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"warning","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count rejected
    count=$(echo "$result" | jq '.findings | length')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar reason
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    reason=$(jq -r '.reject_reason' "$sidecar")
    [[ "$reason" == severity-not-in-enum* ]]
}

# =============================================================================
# Flag OFF — byte-identical legacy behavior
# =============================================================================

@test "C14: flag OFF (default) — normalization never runs, repair never attempted, output byte-identical to pre-C14 shape" {
    CONF_REPAIR_LOOP="false"
    # If repair were somehow invoked, fail loudly.
    _repair_finding_via_model() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
    _REPAIR_TEST_SPRINT="sprint-c14-flagoff-$$"

    local content='{"findings":[{"id":"DISS-001","severity":"  blocking ","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    # Not normalized -> still rejected (case-mismatched severity).
    local count
    count=$(echo "$result" | jq '.findings | length')
    [[ "$count" == "0" ]]

    # No repaired_count key at all in metadata (byte-identical envelope shape).
    [[ "$(echo "$result" | jq 'has("repaired_count")')" == "false" ]] # top-level guard (should be false either way)
    [[ "$(echo "$result" | jq '.metadata | has("repaired_count")')" == "false" ]]

    # Sidecar entry has the legacy 7-field schema — no repair_attempted/succeeded.
    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    [[ "$(jq 'has("repair_attempted")' "$sidecar")" == "false" ]]
    [[ "$(jq 'has("repair_succeeded")' "$sidecar")" == "false" ]]
    local keys
    keys=$(jq -c '. | keys | sort' "$sidecar")
    [[ "$keys" == '["index","model","payload","reject_reason","sprint_id","ts_utc","type"]' ]]
}

@test "C14: flag unset entirely behaves identically to flag explicitly false" {
    unset CONF_REPAIR_LOOP
    _REPAIR_TEST_SPRINT="sprint-c14-unset-$$"
    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    local count
    count=$(echo "$result" | jq '.findings | length')
    [[ "$count" == "1" ]]
    [[ "$(echo "$result" | jq '.metadata | has("repaired_count")')" == "false" ]]
}

@test "_write_rejected_sidecar: legacy 7-arg call omits repair_attempted/repair_succeeded" {
    local sidecar="$TEST_DIR/sidecar-legacy.jsonl"
    : > "$sidecar"
    _write_rejected_sidecar "$sidecar" '{"id":"x"}' "missing-severity" "0" "sprint-x" "review" "gpt-5.3-codex"
    [[ "$(jq 'has("repair_attempted")' "$sidecar")" == "false" ]]
    [[ "$(jq 'has("repair_succeeded")' "$sidecar")" == "false" ]]
}

@test "_write_rejected_sidecar: 9-arg call adds repair_attempted/repair_succeeded booleans" {
    local sidecar="$TEST_DIR/sidecar-repair.jsonl"
    : > "$sidecar"
    _write_rejected_sidecar "$sidecar" '{"id":"x"}' "missing-severity" "0" "sprint-x" "review" "gpt-5.3-codex" "true" "false"
    [[ "$(jq -r '.repair_attempted' "$sidecar")" == "true" ]]
    [[ "$(jq -r '.repair_succeeded' "$sidecar")" == "false" ]]
}

# =============================================================================
# Degraded-verdict trajectory wiring (#1177-D)
# =============================================================================

@test "C14: write_output emits a repair-loop DEGRADED trajectory record when rejected_count>0 and flag ON" {
    CONF_REPAIR_LOOP="true"
    local sprint_id="sprint-c14-traj-$$"
    _REPAIR_TEST_SPRINT="$sprint_id"
    local traj_dir="$TEST_DIR/trajectory-$sprint_id"
    local pushlog="$TEST_DIR/pushlog-$sprint_id.txt"

    local runner="$TEST_DIR/runner-$sprint_id.sh"
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "review", model: "gpt-5.3-codex", sprint_id: $sid,
                   timestamp: "2026-07-07T00:00:00Z", status: "reviewed",
                   degraded: false, rejected_count: 2, repaired_count: 1}
    }')
    cat > "$runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log() { :; }
error() { printf '%s\n' "\$*" >&2; return 1; }
main() { :; }
source "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
push_notify() { echo "PUSH|\$1|\$2|\$3|\$4" >> "$pushlog"; return 0; }
export LOA_DEGRADED_VERDICT_DIR="$traj_dir"
CONF_REPAIR_LOOP="true"
write_output '$result_json' "$sprint_id" "review" "0"
EOF
    run bash "$runner"
    [[ "$status" -eq 0 ]]

    local traj
    traj="$traj_dir/degraded-verdict-"*.jsonl
    # bash glob expansion: [[ ]] does NOT expand unquoted globs, [ ] does
    # (via ordinary word-splitting) — use single-bracket here, matching
    # the existing pattern in adversarial-review-verdict-quality.bats.
    [ -f $traj ]
    local gate band
    gate=$(jq -r '.gate' $traj)
    band=$(jq -r '.verdict_band' $traj)
    [[ "$gate" == "adversarial-review:review:repair-loop" ]]
    [[ "$band" == "DEGRADED" ]]

    rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}" 2>/dev/null || true
}

@test "C14: write_output emits NOTHING repair-loop-related when flag is OFF, even if rejected_count>0 in metadata" {
    local sprint_id="sprint-c14-traj-off-$$"
    _REPAIR_TEST_SPRINT="$sprint_id"
    local traj_dir="$TEST_DIR/trajectory-off-$sprint_id"

    local runner="$TEST_DIR/runner-off-$sprint_id.sh"
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "review", model: "gpt-5.3-codex", sprint_id: $sid,
                   timestamp: "2026-07-07T00:00:00Z", status: "reviewed",
                   degraded: false, rejected_count: 3}
    }')
    cat > "$runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log() { :; }
error() { printf '%s\n' "\$*" >&2; return 1; }
main() { :; }
source "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
export LOA_DEGRADED_VERDICT_DIR="$traj_dir"
write_output '$result_json' "$sprint_id" "review" "0"
EOF
    run bash "$runner"
    [[ "$status" -eq 0 ]]

    # No trajectory record was ever written -> the directory itself was
    # never created (degraded_verdict_maybe_emit mkdir -p's it lazily).
    [[ ! -d "$traj_dir" ]]

    rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}" 2>/dev/null || true
}

# =============================================================================
# C16 — MODELINV skill attribution on adversarial-review.sh's own dispatch
# =============================================================================

@test "C16: invoke_dissenter passes --skill adversarial-<type> through to model-adapter.sh" {
    local fake_dir="$TEST_DIR/fake-adapter-review"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/model-adapter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/captured-args.txt"
echo '{"content":"{}","tokens_input":1,"tokens_output":1,"cost_usd":0,"latency_ms":1}'
EOF
    chmod +x "$fake_dir/model-adapter.sh"

    local sysfile="$fake_dir/sys.txt" userfile="$fake_dir/user.txt"
    echo "sys" > "$sysfile"
    echo "user" > "$userfile"

    SCRIPT_DIR="$fake_dir"
    invoke_dissenter "$sysfile" "$userfile" "gpt-5.3-codex" "60" "" "review" >/dev/null

    grep -qx -- "adversarial-review" "$fake_dir/captured-args.txt"
}

@test "C16: invoke_dissenter uses adversarial-audit for type=audit" {
    local fake_dir="$TEST_DIR/fake-adapter-audit"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/model-adapter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/captured-args.txt"
echo '{"content":"{}","tokens_input":1,"tokens_output":1,"cost_usd":0,"latency_ms":1}'
EOF
    chmod +x "$fake_dir/model-adapter.sh"

    local sysfile="$fake_dir/sys.txt" userfile="$fake_dir/user.txt"
    echo "sys" > "$sysfile"
    echo "user" > "$userfile"

    SCRIPT_DIR="$fake_dir"
    invoke_dissenter "$sysfile" "$userfile" "gpt-5.3-codex" "60" "" "audit" >/dev/null

    grep -qx -- "adversarial-audit" "$fake_dir/captured-args.txt"
}
