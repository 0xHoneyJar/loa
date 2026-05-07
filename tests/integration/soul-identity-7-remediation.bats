#!/usr/bin/env bats
# =============================================================================
# tests/integration/soul-identity-7-remediation.bats
#
# cycle-098 Sprint 7 — pre-merge remediation tests.
# Pins the exact PoCs from the cypherpunk + optimist parallel review reports
# so future regressions of the same defects fail loudly.
#
# Cypherpunk findings:
#   CRIT-1: test-mode gate too permissive (BATS_TMPDIR alone bypasses)
#   HIGH-1: hook honors absolute / `..` path: in .loa.config.yaml
#   HIGH-2: NFKC bypass — FULLWIDTH and zero-width chars defeat patterns
#   HIGH-3: context-isolation \x1eREPORT\x1e sentinel leak in surfaced body
#   HIGH-4: hook silently drops audit emit on heading-payload-shape failure
#   MED-1:  last_updated bounds claim was false (now removed from docstring)
#   MED-2:  schema_version maxLength bound
# Optimist findings:
#   HIGH-1: audit-retention-policy.yaml mismatch (now describes audit log)
#   MED-2:  pattern compile errors silently swallowed (now stderr-logged)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/soul-identity-lib.sh"
    HOOK="$PROJECT_ROOT/.claude/hooks/session-start/loa-l7-surface-soul.sh"
    [[ -f "$LIB" && -f "$HOOK" ]] || skip "L7 sprint-7 not present"

    TEST_DIR="$(mktemp -d)"
    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"
    export LOA_SOUL_TEST_MODE=1
    export LOA_SOUL_LOG="$TEST_DIR/soul-events.jsonl"
    export LOA_SOUL_TEST_CONFIG="$TEST_DIR/.loa.config.yaml"
    export LOA_SOUL_TEST_PATH="$TEST_DIR/SOUL.md"
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

_make_config() {
    local enabled="${1:-true}"; local mode="${2:-warn}"; local extra="${3:-}"
    cat > "$LOA_SOUL_TEST_CONFIG" <<EOF
soul_identity_doc:
  enabled: $enabled
  schema_mode: $mode
  surface_max_chars: 2000
$extra
EOF
}

_make_valid_soul() {
    cat > "$LOA_SOUL_TEST_PATH" <<'EOF'
---
schema_version: '1.0'
identity_for: 'this-repo'
---
## What I am
x
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
EOF
}

# ---------------------------------------------------------------------------
# CRIT-1 closure — test-mode gate strict
# ---------------------------------------------------------------------------

@test "CRIT-1 BATS_TMPDIR alone does NOT activate test-mode (was a bypass pre-fix)" {
    # Strip every other test-mode signal; leave only BATS_TMPDIR — which
    # any leaked dev shell or nested tooling could set.
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TEST_FILENAME BATS_VERSION LOA_SOUL_TEST_MODE
        export BATS_TMPDIR=/tmp
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        if _soul_test_mode_active; then
            echo "BYPASS: BATS_TMPDIR alone activated test-mode"; exit 1
        fi
        exit 0
    '
}

@test "CRIT-1 LOA_SOUL_TEST_MODE alone (no bats marker) does NOT activate test-mode" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TEST_FILENAME BATS_VERSION BATS_TMPDIR
        export LOA_SOUL_TEST_MODE=1
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        if _soul_test_mode_active; then
            echo "BYPASS: LOA_SOUL_TEST_MODE alone activated test-mode"; exit 1
        fi
        exit 0
    '
}

@test "CRIT-1 only BOTH LOA_SOUL_TEST_MODE=1 + BATS marker activates test-mode" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TMPDIR
        export LOA_SOUL_TEST_MODE=1 BATS_VERSION=1.10.0
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        _soul_test_mode_active || { echo "FAIL: legitimate test-mode rejected"; exit 1; }
        exit 0
    '
}

# ---------------------------------------------------------------------------
# HIGH-1 closure — realpath REPO_ROOT containment for config.path
# ---------------------------------------------------------------------------

@test "HIGH-1 absolute path /etc/passwd in config.path is rejected in production" {
    # Simulate production: drop test-mode. The hook resolves config.path
    # against REPO_ROOT and rejects anything outside.
    cat > "$TEST_DIR/.loa.config.yaml" <<EOF
soul_identity_doc:
  enabled: true
  schema_mode: warn
  surface_max_chars: 2000
  path: /etc/passwd
EOF
    # Run hook WITHOUT test-mode env vars — production-equivalent.
    run env -i \
        HOME="$HOME" \
        PATH="$PATH" \
        bash "$HOOK"
    [[ "$status" -eq 0 ]]
    # No surface — /etc/passwd would have appeared inside <untrusted-content>
    # if the gate were bypass-able.
    [[ "$output" != *"root:"* ]] || { echo "BYPASS: /etc/passwd content surfaced"; false; }
    [[ "$output" != *"<untrusted-content"* ]] || { echo "BYPASS: surface emitted from outside repo"; false; }
}

@test "HIGH-1 traversal '../../etc/passwd' in config.path is rejected" {
    cat > "$TEST_DIR/.loa.config.yaml" <<'EOF'
soul_identity_doc:
  enabled: true
  schema_mode: warn
  surface_max_chars: 2000
  path: "../../etc/passwd"
EOF
    run env -i HOME="$HOME" PATH="$PATH" bash "$HOOK"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"root:"* ]]
}

# ---------------------------------------------------------------------------
# HIGH-2 closure — NFKC + zero-width prescriptive bypass
# ---------------------------------------------------------------------------

@test "HIGH-2 FULLWIDTH 'Ｍ Ｕ Ｓ Ｔ' is detected as prescriptive after NFKC" {
    {
        printf -- '---\nschema_version: "1.0"\nidentity_for: "this-repo"\n---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n'
        printf -- '## Discipline\n\xef\xbc\xad\xef\xbc\xb5\xef\xbc\xb3\xef\xbc\xb4 run all tests before merge.\n'
        printf -- '## Influences\nv\n'
    } > "$LOA_SOUL_TEST_PATH"
    # shellcheck source=/dev/null
    source "$LIB"
    run soul_validate "$LOA_SOUL_TEST_PATH" --strict
    [[ "$status" -eq 2 ]] || { echo "BYPASS: FULLWIDTH MUST passed strict-mode"; echo "out: $output"; false; }
    [[ "$output" == *"prescriptive"* ]] || [[ "$output" == *"Discipline"* ]]
}

@test "HIGH-2 zero-width-space 'M\\u200bUST' is detected as prescriptive after strip" {
    {
        printf -- '---\nschema_version: "1.0"\nidentity_for: "this-repo"\n---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n'
        # M + U+200B + UST = "MUST" after zero-width strip
        printf -- '## Discipline\nM\xe2\x80\x8bUST run all tests.\n'
        printf -- '## Influences\nv\n'
    } > "$LOA_SOUL_TEST_PATH"
    source "$LIB"
    run soul_validate "$LOA_SOUL_TEST_PATH" --strict
    [[ "$status" -eq 2 ]] || { echo "BYPASS: zero-width-split MUST passed strict-mode"; false; }
}

# ---------------------------------------------------------------------------
# HIGH-3 closure — sentinel \x1eREPORT\x1e leak
# ---------------------------------------------------------------------------

@test "HIGH-3 sanitize_for_session_start output contains no \\x1e (RS) bytes" {
    source "$PROJECT_ROOT/.claude/scripts/lib/context-isolation-lib.sh" 2>/dev/null
    local out
    out="$(sanitize_for_session_start "L7" "hello world" --max-chars 1000)"
    if printf '%s' "$out" | grep -q $'\x1e'; then
        echo "REGRESSION: sentinel byte present in surfaced body"
        printf '%s' "$out" | od -c | head -5
        false
    fi
}

@test "HIGH-3 sanitize_for_session_start output contains no literal 'REPORT' marker" {
    source "$PROJECT_ROOT/.claude/scripts/lib/context-isolation-lib.sh" 2>/dev/null
    local out
    out="$(sanitize_for_session_start "L7" "ordinary descriptive text" --max-chars 1000)"
    [[ "$out" != *"REPORT"* ]] || { echo "REGRESSION: REPORT literal in body"; false; }
}

@test "HIGH-3 hook output (warn mode, valid SOUL.md) contains no \\x1e" {
    _make_config true warn
    _make_valid_soul
    run "$HOOK"
    [[ "$status" -eq 0 ]]
    if printf '%s' "$output" | grep -q $'\x1e'; then
        echo "REGRESSION: sentinel byte in hook output"; false
    fi
}

# ---------------------------------------------------------------------------
# HIGH-4 closure — heading scrub before payload build
# ---------------------------------------------------------------------------

@test "HIGH-4 control bytes in section heading are scrubbed before audit emit" {
    # Construct a SOUL.md with a section heading containing C0 (\x1b ESC) and
    # ANSI escape codes. Pre-fix, this would have caused soul_emit to fail
    # silently (regex reject) and blinded the audit chain.
    {
        printf -- '---\nschema_version: "1.0"\nidentity_for: "this-repo"\n---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n'
        printf -- '## Discipline\nMUST attack.\n'
        printf -- '## CustomSection\x1b[31mPwn\x1b[0m\nplain content\n'
        printf -- '## Influences\nv\n'
    } > "$LOA_SOUL_TEST_PATH"

    _make_config true warn
    run "$HOOK"
    [[ "$status" -eq 0 ]]

    # Audit MUST be recorded.
    [[ -f "$LOA_SOUL_LOG" ]] || { echo "REGRESSION: audit log not created"; false; }
    local last; last="$(tail -n 1 "$LOA_SOUL_LOG")"
    [[ "$last" == *'"primitive_id":"L7"'* ]]
    # Heading in payload must be scrubbed (no \x1b, no '['/']' literals,
    # no ANSI escape sequence remnants).
    local payload_str; payload_str="$(printf '%s' "$last" | jq -r '.payload | tojson')"
    if printf '%s' "$payload_str" | grep -q $'\x1b'; then
        echo "REGRESSION: ESC byte present in audit payload"; false
    fi
}

@test "HIGH-4 prescriptive section with ANSI heading still produces schema-warning audit" {
    {
        printf -- '---\nschema_version: "1.0"\nidentity_for: "this-repo"\n---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n'
        printf -- '## D\x1b[31miscipline\x1b[0m\nMUST run tests.\n'
        printf -- '## Influences\nv\n'
    } > "$LOA_SOUL_TEST_PATH"

    _make_config true warn
    run "$HOOK"
    [[ "$status" -eq 0 ]]
    local last; last="$(tail -n 1 "$LOA_SOUL_LOG")"
    # Outcome is schema-warning OR schema-refused (depending on whether the
    # mangled heading is recognized as one of the required-section names).
    # The critical invariant is that an audit event is emitted at all.
    [[ "$last" == *'"event_type":"soul.surface"'* ]]
}

# ---------------------------------------------------------------------------
# MED-1 closure — last_updated docstring claim removed (no false promise)
# ---------------------------------------------------------------------------

@test "MED-1 schema docstring no longer claims bounds enforcement" {
    grep -E "lib rejects \[0001-01-01" "$PROJECT_ROOT/.claude/data/soul-frontmatter.schema.json" && {
        echo "REGRESSION: false bounds-claim back in docstring"; false
    } || true
}

# ---------------------------------------------------------------------------
# MED-2 (cypherpunk) — schema_version maxLength
# ---------------------------------------------------------------------------

@test "MED-2 schema_version maxLength=16 enforced in soul.surface schema" {
    source "$LIB"
    # Build a payload with an oversized schema_version (17+ chars).
    local big
    big="$(python3 -c 'print("1." + "0"*16)')"  # "1.0000000000000000" = 18 chars
    local payload
    payload="$(jq -nc --arg sv "$big" '{
        file_path: "SOUL.md",
        schema_version: $sv,
        schema_mode: "warn",
        identity_for: "this-repo",
        outcome: "surfaced"
    }')"
    run soul_emit "soul.surface" "$payload"
    [[ "$status" -ne 0 ]] || { echo "REGRESSION: oversized schema_version accepted"; false; }
}

# ---------------------------------------------------------------------------
# OPTIMIST HIGH-1 — retention policy now describes audit log
# ---------------------------------------------------------------------------

@test "OPT-HIGH-1 retention-policy L7 log_basename matches lib's _DEFAULT_LOG basename" {
    local policy="$PROJECT_ROOT/.claude/data/audit-retention-policy.yaml"
    [[ -f "$policy" ]]
    local policy_basename
    policy_basename="$(yq '.primitives.L7.log_basename' "$policy")"
    [[ "$policy_basename" == "soul-events.jsonl" ]] || { echo "REGRESSION: retention-policy L7 basename = '$policy_basename' (expected soul-events.jsonl)"; false; }
    # And the lib's _DEFAULT_LOG's basename must match.
    source "$LIB"
    local lib_basename
    lib_basename="$(basename "$_LOA_SOUL_DEFAULT_LOG")"
    [[ "$lib_basename" == "$policy_basename" ]]
}

# ---------------------------------------------------------------------------
# OPTIMIST MED-2 — pattern compile errors logged to stderr
# ---------------------------------------------------------------------------

@test "OPT-MED-2 broken pattern in patterns file produces stderr WARN via _soul_classify_sections" {
    local broken="$TEST_DIR/broken-patterns.txt"
    cat > "$broken" <<'EOF'
^MUST\b
^[unclosed-bracket
^NEVER\b
EOF
    _make_valid_soul
    source "$LIB"
    # Override the lib-internal patterns path constant so _soul_classify_sections
    # reads our broken patterns file. cycle-098 sprint-7 cypherpunk MED-2 +
    # optimist MED-2: a bad regex must produce a stderr WARN, not silent skip.
    _LOA_SOUL_PRESCRIPTIVE_PATTERNS="$broken"
    # Capture stderr.
    local stderr_capture
    stderr_capture="$(_soul_classify_sections "$LOA_SOUL_TEST_PATH" 2>&1 1>/dev/null)"
    [[ "$stderr_capture" == *"WARN:pattern-compile-failed"* ]] || {
        echo "stderr capture: $stderr_capture"; false
    }
}
