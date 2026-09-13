#!/usr/bin/env bats
# Task 1 / AC-1: exercise the actual Oracle fetch step under CI's errexit.

setup() {
    local workflow="$BATS_TEST_DIRNAME/../../.github/workflows/oracle.yml"
    FETCH_SCRIPT="$BATS_TEST_TMPDIR/fetch.sh"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
    export ORACLE_CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    EXPECTED_SOURCES=(docs changelog api_reference blog github_claude_code github_sdk)

    python3 - "$workflow" "$FETCH_SCRIPT" <<'PY'
import sys
from pathlib import Path

import yaml

workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
[fetch] = [
    step for step in workflow["jobs"]["check-updates"]["steps"]
    if step.get("id") == "fetch"
]
Path(sys.argv[2]).write_text(fetch["run"])
PY

    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'MOCK'
#!/usr/bin/env bash
# Record attempts without accessing the network or writing curl's HOME target.
name="${!#}"
name="${name##*/}"
name="${name%.html}"
printf '%s\n' "$name" >> "$ORACLE_CURL_LOG"

case "$ORACLE_FETCH_SCENARIO" in
    success) exit 0 ;;
    partial)
        case "$name" in
            changelog|blog|github_sdk) exit 7 ;;
            *) exit 0 ;;
        esac
        ;;
    failure) exit 7 ;;
    *) exit 2 ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

run_fetch() {
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" ORACLE_FETCH_SCENARIO="$1" \
        bash --noprofile --norc -e "$FETCH_SCRIPT"
}

assert_fetch_result() {
    [ "$status" -eq 0 ]
    [ "$(cat "$ORACLE_CURL_LOG")" = "$(printf '%s\n' "${EXPECTED_SOURCES[@]}")" ]
    grep -Fxq "fetched=$1" "$GITHUB_OUTPUT"
    grep -Fxq "failed=$2" "$GITHUB_OUTPUT"
    grep -Eq '^timestamp=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$GITHUB_OUTPUT"
    [ "$(wc -l < "$GITHUB_OUTPUT")" -eq 3 ]
}

@test "oracle: all successful fetches complete under bash -e" {
    run_fetch success
    assert_fetch_result 6 0

    for source in "${EXPECTED_SOURCES[@]}"; do
        [[ "$output" == *"  ✓ $source fetched"* ]]
    done
}

@test "oracle: partial failures count both outcomes and complete the loop under bash -e" {
    run_fetch partial
    assert_fetch_result 3 3

    for source in docs api_reference github_claude_code; do
        [[ "$output" == *"  ✓ $source fetched"* ]]
    done
    for source in changelog blog github_sdk; do
        [[ "$output" == *"  ✗ $source failed"* ]]
    done
}

@test "oracle: all failed fetches are reported without aborting under bash -e" {
    run_fetch failure
    assert_fetch_result 0 6

    for source in "${EXPECTED_SOURCES[@]}"; do
        [[ "$output" == *"  ✗ $source failed"* ]]
    done
}
