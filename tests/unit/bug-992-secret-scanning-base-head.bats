#!/usr/bin/env bats
# =============================================================================
# bug-992-secret-scanning-base-head.bats — contract test for issue #992
# =============================================================================
# secret-scanning.yml passed `base: <default_branch>` / `head: HEAD` to the
# TruffleHog action. On push-to-main and schedule events both resolve to the
# same commit and the action exits 1 with "BASE and HEAD commits are the
# same. TruffleHog won't scan anything." — every main push and the weekly
# history scan was red AND performed zero actual scanning. The action handles
# push/PR/schedule natively when base/head are omitted.
#
# Shape assertions follow the bug-887 workflow-contract precedent: yq against
# the workflow file; no GH event context needed.
# =============================================================================

WORKFLOW=".github/workflows/secret-scanning.yml"

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    WF="$REPO_ROOT/$WORKFLOW"
    [[ -f "$WF" ]] || skip "workflow file not found"
    command -v yq >/dev/null || skip "yq required"
}

@test "bug-992: TruffleHog step exists, SHA-pinned (mutable refs like @main rejected)" {
    run yq eval '.jobs.scan-secrets.steps[] | select(.id == "trufflehog") | .uses' "$WF"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^trufflesecurity/trufflehog@[0-9a-f]{40}$ ]]
}

@test "bug-992: TruffleHog step has NO with.base (base==HEAD kills push/schedule scans)" {
    run yq eval '.jobs.scan-secrets.steps[] | select(.id == "trufflehog") | .with | has("base")' "$WF"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "false" ]]
}

@test "bug-992: TruffleHog step has NO with.head (base==HEAD kills push/schedule scans)" {
    run yq eval '.jobs.scan-secrets.steps[] | select(.id == "trufflehog") | .with | has("head")' "$WF"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "false" ]]
}

@test "bug-992: regression guard — with.path and extra_args preserved" {
    run yq eval '.jobs.scan-secrets.steps[] | select(.id == "trufflehog") | .with.path' "$WF"
    [[ "$output" == "./" ]]
    run yq eval '.jobs.scan-secrets.steps[] | select(.id == "trufflehog") | .with.extra_args' "$WF"
    [[ "$output" == "--only-verified" ]]
}

@test "bug-992: regression guard — checkout fetch-depth 0 preserved (full-history scan)" {
    run yq eval '.jobs.scan-secrets.steps[] | select(.uses | test("actions/checkout")) | .with.fetch-depth' "$WF"
    [[ "$output" == "0" ]]
}

@test "bug-992: regression guard — push/pull_request/schedule triggers preserved" {
    # note: yq needs the bracket form for the "on" key and parenthesized has() chains
    run yq eval '(.["on"] | has("push")) and (.["on"] | has("pull_request")) and (.["on"] | has("schedule"))' "$WF"
    [[ "$output" == "true" ]]
    run yq eval '.["on"].schedule[0].cron' "$WF"
    [[ "$output" == "0 2 * * 1" ]]
}
