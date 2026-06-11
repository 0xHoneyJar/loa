#!/usr/bin/env bats
# =============================================================================
# bug-986-post-merge-symlink-reconcile.bats — contract test for issue #986
# =============================================================================
# On submodule mounts, mount-submodule.sh gitignores the .claude/* symlinks
# ("recreated on mount"), so a fresh CI checkout lacks them even WITH
# `submodules: recursive` (the #669 fix assumed in-tree symlinks). Every
# `.claude/scripts/*` invocation in the distributed post-merge workflow was
# exit-127/chmod-fail fleet-wide. Fix: a guarded reconcile step after each
# submodules-recursive checkout:
#   if [ -x .loa/.claude/scripts/mount-submodule.sh ]; then ... --reconcile; fi
# (no-op on vendored mounts and the Loa repo itself, where .loa/ is absent).
# Shape assertions per the bug-992 precedent (yq v4 bracket/paren forms).
# =============================================================================

WORKFLOW=".github/workflows/post-merge.yml"

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    WF="$REPO_ROOT/$WORKFLOW"
    [[ -f "$WF" ]] || skip "workflow file not found"
    command -v yq >/dev/null || skip "yq required"
}

# Helper: count reconcile steps in a job
_reconcile_count() {
    yq eval "[.jobs.$1.steps[] | select(.run // \"\" | test(\"mount-submodule.sh --reconcile\"))] | length" "$WF"
}

# Helper: assert the reconcile step in a job is guarded and ordered after
# checkout but before any .claude/scripts use.
_assert_guarded_and_ordered() {
    local job="$1"
    run yq eval ".jobs.$job.steps[] | select(.run // \"\" | test(\"mount-submodule.sh --reconcile\")) | .run" "$WF"
    [[ "$output" == *'if [ -x .loa/.claude/scripts/mount-submodule.sh ]'* ]]
    local rec_idx use_idx
    rec_idx=$(yq eval "[.jobs.$job.steps[].run // \"\"] | to_entries | .[] | select(.value | test(\"mount-submodule.sh --reconcile\")) | .key" "$WF" | head -1)
    use_idx=$(yq eval "[.jobs.$job.steps[].run // \"\"] | to_entries | .[] | select(.value | test(\"chmod \\+x .claude/scripts|\\.claude/scripts/.*\\.sh\")) | .key" "$WF" | grep -v "^${rec_idx}$" | head -1)
    [[ -n "$rec_idx" && -n "$use_idx" ]]
    [[ "$rec_idx" -lt "$use_idx" ]]
}

@test "bug-986: classify job has a guarded symlink-reconcile step before .claude/scripts use" {
    [[ "$(_reconcile_count classify)" -ge 1 ]]
    _assert_guarded_and_ordered classify
}

@test "bug-986: simple-release job has a guarded symlink-reconcile step before .claude/scripts use" {
    [[ "$(_reconcile_count "simple-release")" -ge 1 ]]
    _assert_guarded_and_ordered "simple-release"
}

@test "bug-986: full-pipeline job has a guarded symlink-reconcile step before .claude/scripts use" {
    [[ "$(_reconcile_count "full-pipeline")" -ge 1 ]]
    _assert_guarded_and_ordered "full-pipeline"
}

@test "bug-986: regression guard — all three checkouts keep submodules: recursive" {
    # yq gotcha: comma-spreads bind select() to the last expression only — use
    # a .jobs[] union with key-select instead.
    run yq eval '[.jobs[] | select(key == "classify" or key == "simple-release" or key == "full-pipeline") | .steps[] | select(.uses // "" | test("actions/checkout")) | .with.submodules] | unique | .[0]' "$WF"
    [[ "$output" == "recursive" ]]
    run yq eval '[.jobs[] | select(key == "classify" or key == "simple-release" or key == "full-pipeline") | .steps[] | select(.uses // "" | test("actions/checkout"))] | length' "$WF"
    [[ "$output" == "3" ]]
}

@test "bug-986: reconcile step does NOT use || true (partial reconcile must fail loud, #660)" {
    run yq eval '.jobs.classify.steps[] | select(.run // "" | test("mount-submodule.sh --reconcile")) | .run' "$WF"
    [[ "$output" != *"|| true"* ]]
}
