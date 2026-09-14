#!/usr/bin/env bats
# Keep caller coverage reachable through the normal unit Bats discovery.
setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SUITE="$REPO_ROOT/tests/unit/test_hooks_lifecycle_followups.py"
}

@test "HL-001 HL-003: configured hooks and real status/golden callers" {
    run python3 "$SUITE" \
        Callers.test_review_write_boundary_through_configured_hooks \
        Callers.test_review_phase_fallback_and_nested_cwd \
        Callers.test_review_repair_transitions_and_retained_state \
        Callers.test_review_git_wrapper_has_only_stdout_authority \
        Callers.test_workflow_json_with_cold_and_warm_cache \
        Callers.test_documented_loa_sequence_respects_stale_cycle
    [ "$status" -eq 0 ]
}

@test "HL-002: real BB entry/config consume scheduler checkout and preserve overrides" {
    local modules="${LOA_TEST_BB_NODE_MODULES:-$REPO_ROOT/.claude/skills/bridgebuilder-review/node_modules}"
    [[ -d "$modules/zod" ]] || skip "real BB config requires installed zod; set LOA_TEST_BB_NODE_MODULES"
    run python3 "$SUITE" \
        Callers.test_scheduler_real_entry_and_config_use_consumer_cwd \
        Callers.test_scheduler_mounted_entry_and_config_use_consumer_cwd \
        Callers.test_scheduler_preserves_relative_entry_override
    [ "$status" -eq 0 ]
}

@test "HL-002: standalone scheduler CI cannot silently omit its tests or dependency" {
    local workflow="$REPO_ROOT/.github/workflows/hooks-lifecycle-followups.yml"
    local document block
    document=$(yq -o=json '.' "$workflow")
    run jq -e '
      .jobs["scheduler-config"] as $job |
      ($job | has("if") | not) and
      ($job | has("continue-on-error") | not) and
      all($job.steps[]; (has("if") | not) and (has("continue-on-error") | not)) and
      any($job.steps[]; .run == "npm ci" and
          ."working-directory" == ".claude/skills/bridgebuilder-review") and
      (.on.pull_request.paths | index(".claude/skills/bridgebuilder-review/**") != null)
    ' <<< "$document"
    [ "$status" -eq 0 ]
    block=$(jq -r '.jobs["scheduler-config"].steps[] |
        select(.name == "Run scheduler entrypoint config regressions") | .run' <<< "$document")
    [ -n "$block" ]
    local fixture
    fixture="$(mktemp -d)"
    cd "$fixture"
    run bash -e -o pipefail -c "$block"
    [ "$status" -ne 0 ] # suite absent
    mkdir -p tests/unit
    printf 'import unittest\nunittest.main()\n' > tests/unit/test_hooks_lifecycle_followups.py
    run bash -e -o pipefail -c "$block"
    [ "$status" -ne 0 ] # dependency absent
    mkdir -p .claude/skills/bridgebuilder-review/node_modules/zod
    run bash -e -o pipefail -c "$block"
    [ "$status" -ne 0 ] # required methods absent
    rm -rf "$fixture"
}
