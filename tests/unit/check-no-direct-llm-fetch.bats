#!/usr/bin/env bats
# cycle-103 sprint-1 T1.7 — unit tests for the drift gate scanner.
#
# Tests are hermetic: each plants a fixture tree under $BATS_TEST_TMPDIR and
# runs the scanner with --root pointing at the fixture. No real repo files
# are read.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-no-direct-llm-fetch.sh"

    [[ -x "$SCANNER" ]] || skip "scanner not executable: $SCANNER"

    FIXTURE_ROOT="$BATS_TEST_TMPDIR/fixture-root"
    EMPTY_ALLOWLIST="$BATS_TEST_TMPDIR/empty.allowlist"
    : > "$EMPTY_ALLOWLIST"
    mkdir -p "$FIXTURE_ROOT"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/fixture-root" "$BATS_TEST_TMPDIR/empty.allowlist" "$BATS_TEST_TMPDIR/custom.allowlist"
}

# --------------------------------------------------------------------------
# Clean tree → exit 0
# --------------------------------------------------------------------------

@test "clean fixture tree exits 0" {
    cat > "$FIXTURE_ROOT/clean.sh" <<'EOF'
#!/usr/bin/env bash
# Just a script that does NOT touch provider URLs.
echo "hello world"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "empty tree exits 0" {
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

# --------------------------------------------------------------------------
# Violation detection — one per provider URL
# --------------------------------------------------------------------------

@test "bash violation api.anthropic.com → exit 1" {
    cat > "$FIXTURE_ROOT/bad.sh" <<'EOF'
#!/usr/bin/env bash
curl https://api.anthropic.com/v1/messages
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.anthropic.com"* ]]
}

@test "bash violation api.openai.com → exit 1" {
    cat > "$FIXTURE_ROOT/bad.sh" <<'EOF'
#!/usr/bin/env bash
fetch_url="https://api.openai.com/v1/chat/completions"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.openai.com"* ]]
}

@test "bash violation generativelanguage.googleapis.com → exit 1" {
    cat > "$FIXTURE_ROOT/bad.sh" <<'EOF'
#!/usr/bin/env bash
fetch_url="https://generativelanguage.googleapis.com/v1beta/models"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"generativelanguage.googleapis.com"* ]]
}

@test "TypeScript violation → exit 1" {
    cat > "$FIXTURE_ROOT/bad.ts" <<'EOF'
const API_URL = "https://api.anthropic.com/v1/messages";
fetch(API_URL).then(r => r.json());
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.ts"* ]]
}

@test "Python violation → exit 1" {
    cat > "$FIXTURE_ROOT/bad.py" <<'EOF'
import httpx
httpx.post("https://api.openai.com/v1/chat/completions")
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.py"* ]]
}

# --------------------------------------------------------------------------
# Comment-skip filter — comments mentioning the URLs do NOT trigger
# --------------------------------------------------------------------------

@test "bash comment with URL does NOT trigger" {
    cat > "$FIXTURE_ROOT/comment.sh" <<'EOF'
#!/usr/bin/env bash
# This used to call https://api.anthropic.com/v1/messages — now we use cheval.
echo "ok"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "TypeScript // comment with URL does NOT trigger" {
    cat > "$FIXTURE_ROOT/comment.ts" <<'EOF'
// Used to fetch https://api.openai.com/v1/chat/completions directly.
const noop = () => null;
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "TypeScript block-comment continuation (* line) with URL does NOT trigger" {
    cat > "$FIXTURE_ROOT/block.ts" <<'EOF'
/**
 * Historical: this module called https://api.anthropic.com/v1/messages.
 * Post-cycle-103 it routes through the delegate.
 */
const noop = () => null;
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "Python comment with URL does NOT trigger" {
    cat > "$FIXTURE_ROOT/comment.py" <<'EOF'
# Legacy note: previously hit https://generativelanguage.googleapis.com/...
def noop(): return None
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

# --------------------------------------------------------------------------
# Suppression marker
# --------------------------------------------------------------------------

@test "suppression marker bypasses single line (bash #)" {
    cat > "$FIXTURE_ROOT/suppr.sh" <<'EOF'
#!/usr/bin/env bash
fetch_url="https://api.openai.com/v1/chat"  # check-no-direct-llm-fetch: ok
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "suppression marker bypasses single line (TS //)" {
    cat > "$FIXTURE_ROOT/suppr.ts" <<'EOF'
const u = "https://api.anthropic.com/v1/messages"; // check-no-direct-llm-fetch: ok
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "suppression marker is per-line — adjacent line still flags" {
    cat > "$FIXTURE_ROOT/perline.sh" <<'EOF'
#!/usr/bin/env bash
fetch_a="https://api.openai.com/v1/chat"  # check-no-direct-llm-fetch: ok
fetch_b="https://api.anthropic.com/v1/messages"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.anthropic.com"* ]]
    # Suppressed line MUST NOT appear in violations.
    [[ "$output" != *"api.openai.com/v1/chat"* ]]
}

# --------------------------------------------------------------------------
# File-type filter
# --------------------------------------------------------------------------

@test "markdown file with URL is NOT scanned" {
    cat > "$FIXTURE_ROOT/doc.md" <<'EOF'
# Background

This module used to call `https://api.anthropic.com/v1/messages`.
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "JSON allowlist file with provider hosts is NOT scanned" {
    cat > "$FIXTURE_ROOT/hosts.json" <<'EOF'
{"hosts": ["api.openai.com", "api.anthropic.com"]}
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "extension-less file WITH bash shebang IS scanned" {
    cat > "$FIXTURE_ROOT/script-no-ext" <<'EOF'
#!/usr/bin/env bash
curl https://api.anthropic.com/v1/messages
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.anthropic.com"* ]]
}

@test "extension-less file WITHOUT shebang is NOT scanned" {
    cat > "$FIXTURE_ROOT/notes" <<'EOF'
Just a notes file — not a script.
URL: https://api.openai.com/v1/chat
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test ".bash extension IS scanned" {
    cat > "$FIXTURE_ROOT/script.bash" <<'EOF'
fetch="https://api.openai.com/v1/chat"
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
}

# --------------------------------------------------------------------------
# Allowlist
# --------------------------------------------------------------------------

@test "allowlist entry exempts a violating file" {
    cat > "$FIXTURE_ROOT/legacy.sh" <<'EOF'
#!/usr/bin/env bash
curl https://api.openai.com/v1/chat
EOF
    cat > "$BATS_TEST_TMPDIR/custom.allowlist" <<EOF
$FIXTURE_ROOT/legacy.sh
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$BATS_TEST_TMPDIR/custom.allowlist"
    [ "$status" -eq 0 ]
}

@test "allowlist comment lines and blanks are ignored" {
    cat > "$FIXTURE_ROOT/legacy.sh" <<'EOF'
#!/usr/bin/env bash
curl https://api.openai.com/v1/chat
EOF
    cat > "$BATS_TEST_TMPDIR/custom.allowlist" <<EOF
# This is a comment

# Another comment
$FIXTURE_ROOT/legacy.sh
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$BATS_TEST_TMPDIR/custom.allowlist"
    [ "$status" -eq 0 ]
}

@test "allowlist is path-exact — sibling file is NOT exempt" {
    cat > "$FIXTURE_ROOT/legacy.sh" <<'EOF'
#!/usr/bin/env bash
curl https://api.openai.com/v1/chat
EOF
    cat > "$FIXTURE_ROOT/legacy2.sh" <<'EOF'
#!/usr/bin/env bash
curl https://api.openai.com/v1/chat
EOF
    cat > "$BATS_TEST_TMPDIR/custom.allowlist" <<EOF
$FIXTURE_ROOT/legacy.sh
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$BATS_TEST_TMPDIR/custom.allowlist"
    [ "$status" -eq 1 ]
    [[ "$output" == *"legacy2.sh"* ]]
    # legacy.sh must NOT appear in violations (it IS allowlisted).
    [[ "$output" != *"$FIXTURE_ROOT/legacy.sh"* ]] || \
        [[ "$output" == *"Exempt files"*"legacy.sh"* ]]  # accepted: appears under "Exempt files:" header
}

# --------------------------------------------------------------------------
# Heredoc handling — provider URLs inside heredocs are not flagged
# --------------------------------------------------------------------------

@test "URL inside <<EOF heredoc body is NOT flagged" {
    cat > "$FIXTURE_ROOT/heredoc.sh" <<'OUTER'
#!/usr/bin/env bash
cat <<INNER
This documentation mentions https://api.anthropic.com/v1/messages.
INNER
echo done
OUTER
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 0 ]
}

@test "URL in <<EOF opener line itself IS flagged" {
    # `cat <<EOF >file && curl https://api.openai.com/v1/chat` — the curl
    # on the opener line must still be flagged. Mirrors cycle-099 H2.
    cat > "$FIXTURE_ROOT/hd-opener.sh" <<'OUTER'
#!/usr/bin/env bash
cat <<INNER >/tmp/x && curl https://api.openai.com/v1/chat
content
INNER
OUTER
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"api.openai.com"* ]]
}

# --------------------------------------------------------------------------
# CLI surface
# --------------------------------------------------------------------------

@test "--quiet suppresses stdout when clean" {
    cat > "$FIXTURE_ROOT/clean.sh" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
    run "$SCANNER" --root "$FIXTURE_ROOT" --allowlist "$EMPTY_ALLOWLIST" --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "--help prints usage and exits 0" {
    run "$SCANNER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "unknown arg exits 2" {
    run "$SCANNER" --frobnicate
    [ "$status" -eq 2 ]
}

@test "missing --root path exits 2" {
    run "$SCANNER" --root
    [ "$status" -eq 2 ]
}
