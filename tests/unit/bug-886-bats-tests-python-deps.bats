#!/usr/bin/env bats
# =============================================================================
# bug-886-bats-tests-python-deps.bats — contract test for issue #886
# =============================================================================
# bats-tests.yml ran tests/unit/ with no Python-deps install step: ~22 of the
# 68 main-red bats failures were dependency-shaped — 16 "jcs: 'rfc8785' Python
# package not installed" (lib/jcs.sh:48-49), 4 ModuleNotFoundError: rfc8785
# (trust-store-root signing), plus ruamel.yaml/jsonschema casualties.
# Canonical pattern mirrored: cycle099-sprint-1e-tests.yml (setup-python
# v5.3.0 SHA pin) + jcs-conformance.yml (rfc8785 precedent).
# Shape assertions per the bug-992 precedent (yq v4: bracket form for "on",
# parenthesized has() chains).
# =============================================================================

WORKFLOW=".github/workflows/bats-tests.yml"
SETUP_PYTHON_SHA="0b93645e9fea7318ecaed2b359559ac225c90a2b"

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    WF="$REPO_ROOT/$WORKFLOW"
    [[ -f "$WF" ]] || skip "workflow file not found"
    command -v yq >/dev/null || skip "yq required"
}

@test "bug-886: SHA-pinned setup-python step exists in bats job (mutable refs rejected)" {
    run yq eval '.jobs.bats.steps[] | select(.uses | test("actions/setup-python")) | .uses' "$WF"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^actions/setup-python@[0-9a-f]{40}$ ]]
    [[ "$output" == "actions/setup-python@${SETUP_PYTHON_SHA}" ]]
    run yq eval '.jobs.bats.steps[] | select(.uses | test("actions/setup-python")) | .with.python-version' "$WF"
    [[ "$output" == "3.13" ]]
}

@test "bug-886: pip-install step includes all four pinned packages" {
    run yq eval '.jobs.bats.steps[] | select(.name == "Install Python deps for bats suites") | .run' "$WF"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"rfc8785==0.1.4"* ]]
    [[ "$output" == *"jsonschema==4.26.0"* ]]
    [[ "$output" == *"ruamel.yaml==0.18.17"* ]]
    [[ "$output" == *"cryptography==46.0.7"* ]]
}

@test "bug-886: pip-install step runs BEFORE the unit-test step" {
    names=$(yq eval '.jobs.bats.steps[].name // .jobs.bats.steps[].uses' "$WF" 2>/dev/null || true)
    # robust index extraction: list step names with line numbers
    install_idx=$(yq eval '[.jobs.bats.steps[].name] | to_entries | .[] | select(.value == "Install Python deps for bats suites") | .key' "$WF")
    run_idx=$(yq eval '[.jobs.bats.steps[].name] | to_entries | .[] | select(.value == "Run framework unit tests") | .key' "$WF")
    [[ -n "$install_idx" && "$install_idx" != "null" ]]
    [[ -n "$run_idx" && "$run_idx" != "null" ]]
    [[ "$install_idx" -lt "$run_idx" ]]
}

@test "bug-886: regression guard — bats-core and yq install steps preserved" {
    run yq eval '[.jobs.bats.steps[].name] | contains(["Install bats-core v1.13.0"])' "$WF"
    [[ "$output" == "true" ]]
    run yq eval '[.jobs.bats.steps[].name // ""] | map(select(test("yq"))) | length > 0' "$WF"
    [[ "$output" == "true" ]]
}

@test "bug-886: regression guard — path filters still cover tests/unit and the workflow" {
    run yq eval '(.["on"].push.paths | contains(["tests/unit/**"])) and (.["on"].pull_request.paths | contains(["tests/unit/**"]))' "$WF"
    [[ "$output" == "true" ]]
    run yq eval '(.["on"].push.paths | contains([".github/workflows/bats-tests.yml"]))' "$WF"
    [[ "$output" == "true" ]]
}
