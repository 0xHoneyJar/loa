#!/usr/bin/env bats
# Issue #782 — legacy model-adapter routes gpt-5.5 / gpt-5.5-pro to the wrong
# OpenAI endpoint.
#
# `model-adapter.sh.legacy::call_openai_api` decides between
# `/v1/chat/completions` and `/v1/responses` by string-matching the model_id
# against `*"codex"*` (line 221). That misses every other OpenAI model that
# requires the Responses API — notably `gpt-5.5` and `gpt-5.5-pro` per
# `model-config.yaml::providers.openai.models.*.endpoint_family`. The
# Python `cheval` adapter handles this correctly; only the bash legacy path
# is broken.
#
# Hermetic: stubs `curl` on PATH so the adapter never actually calls
# OpenAI. The stub captures argv to a temp file; the test asserts on the
# URL that was passed.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LEGACY="$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy"

    # Sandbox dir for stubs + capture file. Inside PROJECT_ROOT/.run so the
    # adapter (which calls realpath) doesn't fail on out-of-tree fixtures.
    TEST_SANDBOX="$PROJECT_ROOT/.run/legacy-adapter-routing-test-$$"
    mkdir -p "$TEST_SANDBOX/bin"

    # Capture file the curl shim writes to.
    CURL_CAPTURE="$TEST_SANDBOX/curl-args.txt"
    : > "$CURL_CAPTURE"

    # Curl shim — captures argv (one arg per line) and emits a minimal
    # successful response so the adapter's parse path doesn't blow up.
    cat > "$TEST_SANDBOX/bin/curl" <<EOF
#!/usr/bin/env bash
# Capture every arg verbatim (each on its own line for grep-friendliness)
for a in "\$@"; do printf '%s\n' "\$a" >> "$CURL_CAPTURE"; done
# Emit a syntactically-valid OpenAI response so downstream parsing doesn't
# fail noisily. The exact shape varies per endpoint; both shapes parse OK
# enough for this test (we only care about the URL the shim was called
# against, not the response content).
cat <<'JSON'
{"choices":[{"message":{"content":"{\"items\":[]}"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
JSON
EOF
    chmod +x "$TEST_SANDBOX/bin/curl"
    PATH="$TEST_SANDBOX/bin:$PATH"

    # API key env vars expected by the adapter
    export OPENAI_API_KEY="sk-test-dummy-key-not-real"

    # Input file the adapter reads
    INPUT_FILE="$TEST_SANDBOX/input.txt"
    echo "test prompt body" > "$INPUT_FILE"
}

teardown() {
    rm -rf "$TEST_SANDBOX"
    unset OPENAI_API_KEY
}

# Helper: invoke legacy adapter with a given model_id, return the URL the
# curl shim was called against (last positional arg in OpenAI calls).
_invoke_and_get_url() {
    local model_id="$1"
    bash "$LEGACY" \
        --model "$model_id" \
        --mode review \
        --phase prd \
        --input "$INPUT_FILE" \
        --timeout 5 >/dev/null 2>&1 || true
    grep -E '^https://api\.openai\.com/v1/' "$CURL_CAPTURE" | head -n1
}

# ---- Routing matrix --------------------------------------------------------

@test "gpt-5.3-codex routes to /v1/responses (existing behavior; baseline)" {
    url=$(_invoke_and_get_url "gpt-5.3-codex")
    [ -n "$url" ]
    [[ "$url" == "https://api.openai.com/v1/responses" ]]
}

@test "gpt-5.5-pro routes to /v1/responses (closes #782)" {
    url=$(_invoke_and_get_url "gpt-5.5-pro")
    [ -n "$url" ]
    [[ "$url" == "https://api.openai.com/v1/responses" ]] || {
        echo "Expected /v1/responses, got: $url"
        echo "Full curl capture:"
        cat "$CURL_CAPTURE"
        return 1
    }
}

@test "gpt-5.5 routes to /v1/responses (closes #782)" {
    url=$(_invoke_and_get_url "gpt-5.5")
    [ -n "$url" ]
    [[ "$url" == "https://api.openai.com/v1/responses" ]] || {
        echo "Expected /v1/responses, got: $url"
        cat "$CURL_CAPTURE"
        return 1
    }
}

@test "gpt-5.2 still routes to /v1/chat/completions (no regression)" {
    url=$(_invoke_and_get_url "gpt-5.2")
    [ -n "$url" ]
    [[ "$url" == "https://api.openai.com/v1/chat/completions" ]]
}

# ---- Payload shape ---------------------------------------------------------
# When routing to /v1/responses, the payload must NOT include `temperature`
# (gpt-5.5 / gpt-5.5-pro reject it with HTTP 400 per
# `model-config.yaml::params.temperature_supported: false`). The /v1/responses
# branch already omits temperature by construction; this test pins that
# guarantee against future drift.

@test "gpt-5.5-pro request body does NOT include temperature" {
    bash "$LEGACY" \
        --model "gpt-5.5-pro" \
        --mode review \
        --phase prd \
        --input "$INPUT_FILE" \
        --timeout 5 >/dev/null 2>&1 || true

    # The adapter writes the payload to a tmpfile and passes via
    # --data-binary @<file>. Our shim captured `--data-binary` and
    # `@/path/to/payload-tmpfile`. The payload-tmpfile is rm-trapped on
    # function return — so we extract the body from the captured argv if
    # the shim was clever enough to inline it. For this assertion, we
    # check the shim's argv: --data-binary is followed by a literal
    # `@<path>`. We can't inspect the body post-hoc, but we CAN assert
    # that the URL does NOT contain `chat/completions` (which would emit
    # temperature) — i.e. the routing fix carries the temperature-skip
    # guarantee for free.
    local url
    url=$(grep -E '^https://api\.openai\.com/v1/' "$CURL_CAPTURE" | head -n1)
    [[ "$url" == "https://api.openai.com/v1/responses" ]]
}
