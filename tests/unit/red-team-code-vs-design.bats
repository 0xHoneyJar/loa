#!/usr/bin/env bats
# =============================================================================
# red-team-code-vs-design.bats — issues #984/#985 (KF-015): the code-vs-design
# gate silently passed degraded runs. Three defects pinned:
#   1. EXIT trap referenced function-locals under set -u (cleanup dead,
#      unbound-variable noise on every success path).
#   2. `jq .` exits 0 on EMPTY input — empty model content wrote a 0-byte
#      findings file and exited 0 (the silent-clean bypass).
#   3. Model-invoke failure (incl. exit-12 CHAIN_EXHAUSTED) exited with NO
#      artifact — unlike scoring-engine's {degraded:true} contract.
# Functional tests use the test-mode-gated adapter seam
# (LOA_RTCD_TEST_MODE=1 + bats marker -> LOA_RTCD_MODEL_ADAPTER), which is
# itself part of the fix — they fail fast pre-fix without network.
# =============================================================================

SCRIPT_REL=".claude/scripts/red-team-code-vs-design.sh"

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/$SCRIPT_REL"
    [[ -f "$SCRIPT" ]] || skip "script not found"

    FIX="$BATS_TEST_TMPDIR/rtcd"
    mkdir -p "$FIX/stub"
    cat > "$FIX/sdd.md" <<'EOF'
# SDD

## Security Design

Authentication uses short-lived tokens. All inputs are validated at the
boundary. Audit events are hash-chained.
EOF
    printf 'diff --git a/x b/x\n+++ b/x\n+token check added\n' > "$FIX/diff.txt"
    export LOA_RTCD_TEST_MODE=1
}

_run_gate() {
    LOA_RTCD_MODEL_ADAPTER="$1" run bash "$SCRIPT" \
        --sdd "$FIX/sdd.md" --diff "$FIX/diff.txt" \
        --output "$FIX/out.json" --sprint sprint-test
}

_require_seam() {
    grep -q 'LOA_RTCD_TEST_MODE' "$SCRIPT" || {
        echo "adapter test seam missing (pre-fix state)" >&2
        return 1
    }
}

# --- shape pins (red pre-fix, no execution) ---------------------------------

@test "RTC-T1: EXIT trap does not reference bare function-locals under set -u" {
    # Pre-fix: `local prompt_file stderr_tmp` + trap 'rm -f "$prompt_file" ...'
    # -> unbound at EXIT. Fix must script-scope the vars (cleanup actually runs).
    ! grep -qE 'local prompt_file stderr_tmp' "$SCRIPT"
}

@test "RTC-T2: validation requires an object with a findings array (not bare jq .)" {
    grep -q 'findings | type == "array"' "$SCRIPT"
}

@test "RTC-T3: model-failure branch writes a degraded record before exiting" {
    grep -A 12 'Model invocation failed' "$SCRIPT" | grep -q 'degradation_reason'
}

# --- functional (seam-gated; fail fast pre-fix) ------------------------------

@test "RTC-T4: happy path — valid findings produce exit 0 + computed summary" {
    _require_seam
    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
printf '{"content": "{\\"findings\\":[{\\"classification\\":\\"CONFIRMED_DIVERGENCE\\",\\"severity\\":800,\\"requirement\\":\\"tokens\\"}]}"}'
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.summary.total' "$FIX/out.json")" = "1" ]
    [ "$(jq -r '.summary.confirmed_divergence' "$FIX/out.json")" = "1" ]
    [[ "$output" != *"unbound variable"* ]]
}

@test "RTC-T5: EMPTY model content -> non-zero exit + degraded record (the #984 bypass)" {
    _require_seam
    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
printf '{"content": ""}'
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [ "$status" -ne 0 ]
    [ -s "$FIX/out.json" ]
    [ "$(jq -r '.degraded' "$FIX/out.json")" = "true" ]
    [ "$(jq -r '.findings | length' "$FIX/out.json")" = "0" ]
}

@test "RTC-T6: adapter exit-12 (CHAIN_EXHAUSTED) -> non-zero exit + degraded record with code" {
    _require_seam
    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
echo "chain exhausted: all fallbacks failed" >&2
exit 12
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [ "$status" -ne 0 ]
    [ -s "$FIX/out.json" ]
    [ "$(jq -r '.degraded' "$FIX/out.json")" = "true" ]
    [ "$(jq -r '.model_exit_code' "$FIX/out.json")" = "12" ]
    [ "$(jq -r '.degradation_reason' "$FIX/out.json")" = "model_invocation_failed" ]
}

@test "RTC-T7: success path emits no unbound-variable noise and cleans temp files" {
    _require_seam
    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
printf '{"content": "{\\"findings\\":[]}"}'
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [[ "$output" != *"unbound variable"* ]]
}

# --- DISS-001 propagation (review iteration 1) -------------------------------
# pipeline-self-review.sh must not swallow the gate's new degraded exits:
# the loop counts them (reading degradation_reason from the artifact) and the
# summary JSON carries degraded_reviews. Gate-level behavior is functionally
# covered by RTC-T5/T6; these pin the parent's propagation arithmetic.

@test "RTC-T8a: pipeline-self-review counts degraded gate exits and reads the reason" {
    local psr="$REPO_ROOT/.claude/scripts/pipeline-self-review.sh"
    [[ -f "$psr" ]] || skip "pipeline-self-review.sh not found"
    grep -q 'degraded_count=\$((degraded_count + 1))' "$psr"
    grep -q 'degradation_reason' "$psr"
    grep -qE 'DEGRADED: Red Team gate exit' "$psr"
}

@test "RTC-T8b: pipeline-self-review summary JSON carries degraded_reviews + loud WARN" {
    local psr="$REPO_ROOT/.claude/scripts/pipeline-self-review.sh"
    [[ -f "$psr" ]] || skip "pipeline-self-review.sh not found"
    grep -q 'degraded_reviews: \$degraded_reviews' "$psr"
    grep -q 'WARNING: \$degraded_count of \$sdd_count' "$psr"
}

# --- cycle-117 item D (#1177): degraded-verdict trajectory + page ----------
# Reuses the LOA_RTCD_TEST_MODE stub-adapter seam (same as RTC-T5/T6) to
# force the exact exit-12 / empty-content conditions, then asserts a
# degraded-verdict-<DATE>.jsonl record ALSO lands (in an isolated dir via
# LOA_DEGRADED_VERDICT_DIR, never the real repo tree) plus exactly one push
# via a real (non-stubbed) push-notify-lib.sh dispatch — LOA_PUSH_CONFIG
# points at a fixture enabling push_command with a command that appends a
# marker line, the same mechanism an operator would configure for real.

_write_push_fixture_config() {
    local push_log="$1"
    cat > "$FIX/push-config.yaml" <<YAML
notifications:
  push_command:
    enabled: true
    command: "printf '%s\n' \"\$LOA_PUSH_MESSAGE|\$LOA_PUSH_SOURCE|\$LOA_PUSH_STATE|\$LOA_PUSH_ID\" >> '$push_log'"
    timeout_sec: 5
YAML
}

@test "RTC-T9: adapter exit-12 (CHAIN_EXHAUSTED) -> degraded-verdict record + exactly one push" {
    _require_seam
    local traj_dir="$FIX/trajectory"
    local push_log="$FIX/push.log"
    _write_push_fixture_config "$push_log"
    export LOA_PUSH_CONFIG="$FIX/push-config.yaml"
    export LOA_DEGRADED_VERDICT_DIR="$traj_dir"

    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
echo "chain exhausted: all fallbacks failed" >&2
exit 12
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [ "$status" -ne 0 ]

    local traj
    traj="$traj_dir/degraded-verdict-"*.jsonl
    [ -f $traj ]
    [ "$(jq -r '.gate' $traj)" = "red-team:code-vs-design" ]
    [ "$(jq -r '.verdict_band' $traj)" = "DEGRADED" ]
    [ "$(jq -r '.degradation_reason' $traj)" = "model_invocation_failed" ]
    [ "$(jq -r '.model_exit_code' $traj)" = "12" ]
    [ "$(jq -r '.sprint_id' $traj)" = "sprint-test" ]

    [ -f "$push_log" ]
    [ "$(wc -l < "$push_log")" -eq 1 ]
}

@test "RTC-T10: EMPTY model content -> degraded-verdict record (null exit code) + exactly one push" {
    _require_seam
    local traj_dir="$FIX/trajectory"
    local push_log="$FIX/push.log"
    _write_push_fixture_config "$push_log"
    export LOA_PUSH_CONFIG="$FIX/push-config.yaml"
    export LOA_DEGRADED_VERDICT_DIR="$traj_dir"

    cat > "$FIX/stub/adapter" <<'STUB'
#!/usr/bin/env bash
printf '{"content": ""}'
STUB
    chmod +x "$FIX/stub/adapter"
    _run_gate "$FIX/stub/adapter"
    [ "$status" -ne 0 ]

    local traj
    traj="$traj_dir/degraded-verdict-"*.jsonl
    [ -f $traj ]
    [ "$(jq -r '.gate' $traj)" = "red-team:code-vs-design" ]
    [ "$(jq -r '.verdict_band' $traj)" = "DEGRADED" ]
    [ "$(jq -r '.degradation_reason' $traj)" = "empty_or_invalid_model_output" ]
    [ "$(jq -r '.model_exit_code' $traj)" = "null" ]

    [ -f "$push_log" ]
    [ "$(wc -l < "$push_log")" -eq 1 ]
}
