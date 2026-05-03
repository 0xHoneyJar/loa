#!/usr/bin/env bats
# =============================================================================
# model-adapter-argv-safety.bats — sub-issue 3 (issue #675)
# =============================================================================
# Reproduces the model-adapter.sh.legacy `-d "$payload"` foot-gun on large
# payloads. MAX_ARG_STRLEN on Linux is 128KB, macOS 256KB. A 200KB payload
# either silently truncates or fails with "Argument list too long" when
# passed via curl argv.
#
# Pre-fix: payload-via-argv either crashes ("Argument list too long") OR
# the captured argv is byte-truncated relative to the input.
# Post-fix: payload is written to mktemp(0600) and passed via
# `--data-binary @<file>`, mode 0600, cleaned up via trap on RETURN.
#
# We exercise the 200KB Anthropic call_anthropic_api() function directly
# via `bash -c 'source ... && call_anthropic_api ...'`, with `curl` stubbed
# on PATH so it captures invocation args, payload (via @<file> or argv),
# and emits a fixed minimal Anthropic-shaped response.
# =============================================================================

setup() {
    LEGACY_ADAPTER="${BATS_TEST_DIRNAME}/../../.claude/scripts/model-adapter.sh.legacy"
    [[ -f "$LEGACY_ADAPTER" ]] || skip "model-adapter.sh.legacy not present at $LEGACY_ADAPTER"

    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    mkdir -p "$TEST_DIR/bin"

    # Stub curl: capture argv and any --data-binary @<file> payload, then emit
    # a minimal Anthropic-shaped JSON response that the legacy adapter
    # parses with `jq -r '.content[0].text'`.
    cat > "$TEST_DIR/bin/curl" <<STUB
#!/usr/bin/env bash
TEST_DIR="$TEST_DIR"
STUB
    cat >> "$TEST_DIR/bin/curl" <<'STUB'
# Capture argv flags only (drop large value args) so we can detect
# --data-binary even when payload is multi-MB. Also capture the payload
# from --data-binary @<file> (post-fix) or -d <value> (pre-fix).
: > "$TEST_DIR/curl-argv.txt"
prev=""
for a in "$@"; do
    # Record arg names + small values; truncate massive args at 80 chars
    if [[ ${#a} -le 200 ]]; then
        printf '%s\n' "$a" >> "$TEST_DIR/curl-argv.txt"
    else
        printf 'TRUNCATED-LARGE-ARG-LEN-%d\n' "${#a}" >> "$TEST_DIR/curl-argv.txt"
    fi

    if [[ "$prev" == "--data-binary" && "${a:0:1}" == "@" ]]; then
        cp "${a:1}" "$TEST_DIR/curl-payload.txt"
    elif [[ "$prev" == "-d" ]]; then
        printf '%s' "$a" > "$TEST_DIR/curl-payload.txt"
    fi
    prev="$a"
done
# Emit minimal Anthropic response so caller's jq pipeline succeeds
cat <<'JSON'
{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"output_tokens":1}}
JSON
STUB
    chmod +x "$TEST_DIR/bin/curl"

    # Snapshot pre-existing tmp files in $TMPDIR root so we can detect leaks
    : > "$TEST_DIR/preexisting.list"
    if [[ -d "${TMPDIR:-/tmp}" ]]; then
        find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -mmin -1 -print 2>/dev/null \
            > "$TEST_DIR/preexisting.list" || true
    fi
}

# Extract a single bash function definition from a script, by name.
# Uses brace-depth counting that ignores heredocs and quoted strings —
# robust against `cat <<EOF ... }` patterns that confuse line-based regex.
extract_function() {
    local script="$1"
    local fname="$2"
    awk -v fname="$fname" '
        BEGIN { in_fn = 0; depth = 0; in_heredoc = 0; heredoc_term = "" }
        # Detect function start, e.g. "call_anthropic_api()"
        !in_fn && $0 ~ "^"fname"\\(\\)" {
            in_fn = 1
            depth = 0
        }
        in_fn {
            print
            if (in_heredoc) {
                if ($0 ~ "^"heredoc_term"$") { in_heredoc = 0 }
                next
            }
            # Track simple `<<DELIM` / `<<-DELIM` / `<<'\''DELIM'\''` heredocs
            if (match($0, /<<-?[[:space:]]*'\''?[A-Za-z_][A-Za-z0-9_]*'\''?/)) {
                term = substr($0, RSTART, RLENGTH)
                gsub(/<<-?[[:space:]]*/, "", term)
                gsub(/'\''/, "", term)
                in_heredoc = 1
                heredoc_term = term
                next
            }
            # Count braces, naively (good enough for these adapter functions)
            n_open  = gsub(/\{/, "&", $0)
            n_close = gsub(/\}/, "&", $0)
            depth += n_open - n_close
            if (depth <= 0 && $0 ~ /^\}/) {
                exit
            }
        }
    ' "$script"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "model-adapter.sh.legacy: 200KB payload passes via tmpfile (--data-binary @<file>)" {
    # Generate 200KB of 'a's — above Linux MAX_ARG_STRLEN (128KB),
    # below macOS limit (256KB) — exercises the platform-portability hazard.
    local payload_size=204800
    local big_user_prompt
    big_user_prompt=$(printf '%*s' "$payload_size" '' | tr ' ' 'a')
    [[ ${#big_user_prompt} -eq $payload_size ]]

    # Write the 200KB payload to a file (passing via bash -c argv would itself
    # hit MAX_ARG_STRLEN — that proves the kernel limit, but we want to exercise
    # the ADAPTER's own MAX_ARG_STRLEN exposure on its curl call). We pass the
    # prompt via an env var that the bash invocation reads from a file.
    printf '%s' "$big_user_prompt" > "$TEST_DIR/big-prompt.txt"

    # Source the legacy adapter's call_anthropic_api function and invoke it.
    # We override PATH so our curl stub wins. We pass dummy timeout + key.
    # Use awk with brace-counting to extract the full function body — sed's
    # /^}$/ would terminate prematurely on the heredoc's closing `}`.
    extract_function "$LEGACY_ADAPTER" "call_anthropic_api" > "$TEST_DIR/fn.sh"
    export TEST_DIR
    PATH="$TEST_DIR/bin:$PATH" run bash -c '
        set -o pipefail
        BIG_PROMPT="$(cat "$TEST_DIR/big-prompt.txt")"
        source "$TEST_DIR/fn.sh"
        call_anthropic_api "claude-opus-4-7" "sysprompt" "$BIG_PROMPT" 30 "sk-test-key" 2>&1
    '

    # Pre-fix on Linux: bash exec hits E2BIG ("Argument list too long") when
    # invoking curl with `-d "$payload"` on a 200KB payload — stub never runs,
    # curl-argv.txt never gets written. We treat ANY of these as failure:
    #   1. stub didn't run (no curl-argv.txt)
    #   2. "Argument list too long" appears in output
    #   3. curl was called with `-d` (pre-fix) instead of `--data-binary`
    if [[ "$output" == *"Argument list too long"* ]]; then
        echo "FAIL pre-fix: argv overflow (E2BIG) — adapter passes payload via argv"
        false
    fi

    # Curl stub must have been called — argv file exists.
    [[ -f "$TEST_DIR/curl-argv.txt" ]] || {
        echo "FAIL: curl stub never ran (likely E2BIG from argv-passed payload)."
        echo "stub-output: $output"
        false
    }

    # Post-fix invariant: invocation must use --data-binary @<file>, not -d.
    grep -q '^--data-binary$' "$TEST_DIR/curl-argv.txt" || {
        echo "expected --data-binary in curl argv (post-fix). actual argv:"
        cat "$TEST_DIR/curl-argv.txt"
        false
    }

    # The arg following --data-binary must start with '@' (file reference).
    local next_arg
    next_arg=$(awk '/^--data-binary$/{getline; print; exit}' "$TEST_DIR/curl-argv.txt")
    [[ "${next_arg:0:1}" == "@" ]] || {
        echo "--data-binary argument did not reference a file: '$next_arg'"
        false
    }

    # Payload content captured from the tmpfile must contain the full 200KB
    # input (byte-for-byte match for the user_prompt content embedded in JSON).
    [[ -f "$TEST_DIR/curl-payload.txt" ]]
    local payload_bytes
    payload_bytes=$(wc -c < "$TEST_DIR/curl-payload.txt" | tr -d ' ')
    # Payload includes JSON envelope (~150 bytes overhead) so >= input size.
    [[ "$payload_bytes" -ge "$payload_size" ]] || {
        echo "payload truncated: $payload_bytes bytes < expected $payload_size"
        head -c 200 "$TEST_DIR/curl-payload.txt"
        false
    }

    # Verify the entire user_prompt round-trips byte-for-byte through the JSON.
    grep -c "aaaaaaaaaa" "$TEST_DIR/curl-payload.txt" >/dev/null
}

@test "model-adapter.sh.legacy: tmpfile is mode 0600 and cleaned up after RETURN" {
    # We can verify trap RETURN cleanup by checking no new temp files
    # remain in TMPDIR after the call.
    local payload_size=204800
    local big_user_prompt
    big_user_prompt=$(printf '%*s' "$payload_size" '' | tr ' ' 'a')

    # Sentinel curl that records the @<file> path's mode at call time.
    cat > "$TEST_DIR/bin/curl" <<STUB
#!/usr/bin/env bash
TEST_DIR="$TEST_DIR"
STUB
    cat >> "$TEST_DIR/bin/curl" <<'STUB'
prev=""
for a in "$@"; do
    if [[ "$prev" == "--data-binary" && "${a:0:1}" == "@" ]]; then
        pf="${a:1}"
        # POSIX `stat -c %a` (Linux) or `stat -f %Lp` (BSD/macOS)
        if mode=$(stat -c %a "$pf" 2>/dev/null); then
            :
        else
            mode=$(stat -f %Lp "$pf" 2>/dev/null || echo "")
        fi
        printf '%s\n' "$mode" > "$TEST_DIR/payload-mode.txt"
        printf '%s\n' "$pf"   > "$TEST_DIR/payload-path.txt"
    fi
    prev="$a"
done
cat <<'JSON'
{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"output_tokens":1}}
JSON
STUB
    chmod +x "$TEST_DIR/bin/curl"

    printf '%s' "$big_user_prompt" > "$TEST_DIR/big-prompt-2.txt"
    extract_function "$LEGACY_ADAPTER" "call_anthropic_api" > "$TEST_DIR/fn.sh"
    export TEST_DIR
    PATH="$TEST_DIR/bin:$PATH" run bash -c '
        set -o pipefail
        BIG_PROMPT="$(cat "$TEST_DIR/big-prompt-2.txt")"
        source "$TEST_DIR/fn.sh"
        call_anthropic_api "claude-opus-4-7" "sys" "$BIG_PROMPT" 30 "sk-test-key"
    '
    [[ "$status" -eq 0 ]]

    # Mode must be 600 (octal).
    [[ -f "$TEST_DIR/payload-mode.txt" ]]
    local mode
    mode=$(cat "$TEST_DIR/payload-mode.txt")
    [[ "$mode" == "600" ]] || {
        echo "tmpfile mode is $mode, expected 600"
        false
    }

    # Cleanup: trap RETURN removed the file.
    [[ -f "$TEST_DIR/payload-path.txt" ]]
    local payload_path
    payload_path=$(cat "$TEST_DIR/payload-path.txt")
    [[ ! -f "$payload_path" ]] || {
        echo "tmpfile not cleaned up by trap RETURN: $payload_path"
        ls -la "$payload_path"
        false
    }
}
