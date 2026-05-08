#!/usr/bin/env bats
# tests/unit/model-adapter-responses-api-shapes.bats — sprint-bug-143 Task 2
#
# Pins the legacy bash adapter's response-parsing behavior against three
# captured `/v1/responses` and `/v1/chat/completions` shapes:
#   reasoning.json (gpt-5.5-pro)
#   codex.json     (gpt-5.3-codex)
#   chat.json      (gpt-5.5 via chat-completions)
#
# Sprint-bug-143 root-cause finding: the legacy jq filter at
# model-adapter.sh.legacy:565-570 was NOT the actual #787 trigger — all three
# shapes parse cleanly. The real #787 trigger is on the *request* side: the
# legacy adapter omits `max_output_tokens` for reasoning-class /v1/responses
# calls, causing the model to consume its visible-output budget on internal
# reasoning tokens and emit empty content. These tests pin the parser-side
# behavior so a future regression that DOES break the parse is caught.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE_DIR="${REPO_ROOT}/tests/fixtures/responses-api-shapes"
    # The exact jq filter the legacy adapter uses at lines 565-570.
    EXTRACT_FILTER='
        .choices[0].message.content //
        (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
        empty
    '
}

@test "extract_content reasoning-class /v1/responses returns non-empty" {
    run jq -r "$EXTRACT_FILTER" "${FIXTURE_DIR}/reasoning.json"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Sanity: the captured prompt was "Output exactly: ok"; expect a short
    # response containing "ok" (model may add formatting). Use case-
    # insensitive substring match.
    [[ "${output,,}" == *ok* ]]
}

@test "extract_content codex /v1/responses returns non-empty" {
    run jq -r "$EXTRACT_FILTER" "${FIXTURE_DIR}/codex.json"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "${output,,}" == *ok* ]]
}

@test "extract_content chat-completions returns non-empty" {
    run jq -r "$EXTRACT_FILTER" "${FIXTURE_DIR}/chat.json"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "${output,,}" == *ok* ]]
}

@test "reasoning fixture has expected two-item output structure" {
    # Pin the shape so a future API change that drops the reasoning item or
    # restructures `output[].content[]` shows up as a separate test failure
    # (instead of silently breaking the parser).
    run jq -r '.output | length' "${FIXTURE_DIR}/reasoning.json"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    run jq -r '.output[0].type' "${FIXTURE_DIR}/reasoning.json"
    [ "$output" = "reasoning" ]
    run jq -r '.output[1].type' "${FIXTURE_DIR}/reasoning.json"
    [ "$output" = "message" ]
    run jq -r '.output[1].content[0].type' "${FIXTURE_DIR}/reasoning.json"
    [ "$output" = "output_text" ]
}

@test "fixtures are PII-clean" {
    # Sentinel against accidental re-capture without redaction.
    for f in reasoning.json codex.json chat.json; do
        run grep -E 'sk-[A-Za-z0-9]{20,}|Bearer [A-Za-z0-9._-]+|org-[A-Za-z0-9]{10,}' "${FIXTURE_DIR}/${f}"
        # grep returns 1 when no match (which is what we want).
        [ "$status" -eq 1 ]
    done
}
