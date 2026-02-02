#!/usr/bin/env bash
# Shared test helper for GPT review tests
# Provides hermetic curl mocking and test utilities
#
# Usage in tests:
#   load '../helpers/gpt-review-setup'
#   setup() { setup_mock_curl; ... }

# Global exports for tests to check
export GPT_REVIEW_MOCK_DIR=""
export GPT_REVIEW_MOCK_SENTINEL=""
export GPT_REVIEW_MOCK_ARGS=""

# Setup hermetic curl mock that fails if called unexpectedly
setup_mock_curl() {
    # Use BATS_TEST_TMPDIR for test isolation (per-test unique directory)
    GPT_REVIEW_MOCK_DIR="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/mock-bin"
    GPT_REVIEW_MOCK_SENTINEL="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/curl-sentinel.txt"
    GPT_REVIEW_MOCK_ARGS="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/curl-args.txt"

    mkdir -p "$GPT_REVIEW_MOCK_DIR"
    rm -f "$GPT_REVIEW_MOCK_SENTINEL" "$GPT_REVIEW_MOCK_ARGS"

    # Resolve paths NOW so they're embedded as literals in the mock script
    local sentinel_path="$GPT_REVIEW_MOCK_SENTINEL"
    local args_path="$GPT_REVIEW_MOCK_ARGS"

    # Create fail-safe mock - paths are literal strings, not variables
    cat > "$GPT_REVIEW_MOCK_DIR/curl" << EOF
#!/bin/bash
# FAIL-SAFE: Error if called without explicit test override
echo "ERROR: curl called without explicit mock" >&2
echo '{"error": "unmocked curl call"}' > "$sentinel_path"
echo "\$@" > "$args_path"
exit 99
EOF
    chmod +x "$GPT_REVIEW_MOCK_DIR/curl"
    export PATH="$GPT_REVIEW_MOCK_DIR:$PATH"
}

# Helper to override mock with a specific response
# Usage: mock_curl_response "path/to/fixture.json" [http_code]
mock_curl_response() {
    local response_file="$1"
    local http_code="${2:-200}"
    local args_path="$GPT_REVIEW_MOCK_ARGS"

    cat > "$GPT_REVIEW_MOCK_DIR/curl" << EOF
#!/bin/bash
# Log args for inspection
echo "\$@" > "$args_path"
# Return fixture response
cat "$response_file"
echo ""
echo "$http_code"
exit 0
EOF
    chmod +x "$GPT_REVIEW_MOCK_DIR/curl"
}

# Helper to create mock that captures request body
# Usage: mock_curl_capture "body_capture_file" "response_fixture" [http_code]
mock_curl_capture() {
    local capture_file="$1"
    local response_file="$2"
    local http_code="${3:-200}"
    local args_path="$GPT_REVIEW_MOCK_ARGS"

    cat > "$GPT_REVIEW_MOCK_DIR/curl" << EOF
#!/bin/bash
# Capture all args
echo "\$@" > "$args_path"
# Capture request body from -d flag
prev=""
for arg in "\$@"; do
    if [[ "\$prev" == "-d" ]]; then
        echo "\$arg" > "$capture_file"
    fi
    prev="\$arg"
done
# Return response
cat "$response_file"
echo ""
echo "$http_code"
exit 0
EOF
    chmod +x "$GPT_REVIEW_MOCK_DIR/curl"
}

# Helper to check if curl was called unexpectedly
check_no_network_calls() {
    if [[ -f "$GPT_REVIEW_MOCK_SENTINEL" ]]; then
        echo "ERROR: Unexpected network call detected!"
        cat "$GPT_REVIEW_MOCK_SENTINEL"
        return 1
    fi
    return 0
}

# Get the project root directory
get_project_root() {
    local script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    cd "$script_dir/../.." && pwd
}
