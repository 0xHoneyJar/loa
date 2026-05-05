#!/usr/bin/env bats
# =============================================================================
# tests/integration/endpoint-validator-allowlist-host-validation.bats
#
# cycle-099 Sprint 1E.c.3.c — HIGH-2 deferred from sprint-1E.c.3.a:
#
#   load_allowlist() MUST reject entries with a sentinel-shaped, empty,
#   whitespace-only, or globbed `host` field at LOAD TIME — fail-closed.
#
# Why:
#   The tree-restriction landed in 1E.c.3.a (#732) closed the realistic
#   substitution vector (an attacker pointing the allowlist path elsewhere via
#   env var). HIGH-2 is the inside-the-tree defense-in-depth: an allowlist
#   that LIVES in the canonical tree but contains `host: "*"` (or `host: ""`)
#   would silently no-op the host gate. The host predicate is verbatim equality
#   (`_provider_for_host` lowercases both sides and compares with `==`), so:
#     - host == "*" never matches a real URL hostname (no glob support) →
#       silently broken allowlist. Operator may have copy-pasted a wildcard
#       form expecting glob semantics; we surface the misconfig at load.
#     - host == "" never matches a real URL hostname (step 3 catches empty
#       netloc, but the entry would still be loadable as junk).
#     - host whitespace-only — same as empty after strip; reject for clarity.
#     - host containing `*` anywhere (e.g., "*.openai.com") — operator
#       expectation mismatch; reject so they explicitly enumerate FQDNs.
#
# Pattern: positive control + negative controls + non-string-types coverage.
# All tests invoke load_allowlist directly via Python (not via the CLI URL
# path) to pin the load-time fail-closed contract.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PY_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.py"

    [[ -f "$PY_VALIDATOR" ]] || skip "endpoint-validator.py not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import idna" 2>/dev/null \
        || skip "idna not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
    LIB_DIR="$PROJECT_ROOT/.claude/scripts/lib"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Invokes load_allowlist on $1 (a path). Captures status + stderr-or-stdout.
# Uses runpy because endpoint-validator.py has a hyphen in its module name
# (cannot be `import`-ed conventionally). Per cycle-099 _python_assert pattern
# (sprint-1E.a feedback): heredoc is single-quoted, paths flow via env vars
# to defend against shell-injection in fixture filenames.
_load_allowlist() {
    LOAD_ALLOWLIST_PATH="$1" PY_VALIDATOR="$PY_VALIDATOR" "$PYTHON_BIN" -I -c '
import os, runpy, sys
ns = runpy.run_path(os.environ["PY_VALIDATOR"], run_name="endpoint_validator")
load_allowlist = ns["load_allowlist"]
try:
    result = load_allowlist(os.environ["LOAD_ALLOWLIST_PATH"])
    print(f"OK len={len(result)}")
except ValueError as exc:
    print(f"REJECTED {exc}", file=sys.stderr)
    sys.exit(78)
except Exception as exc:
    print(f"UNEXPECTED {type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(99)
'
}

# Helper: build an allowlist file with a single-entry providers map and given
# host value. The single-quoted heredoc body avoids shell interpolation of
# `*`, `$`, etc; the host literal is injected via `printf -v`.
_make_allowlist_with_host() {
    local out="$1" host_literal="$2"
    cat > "$out" <<EOF
{
  "providers": {
    "openai": [
      {"host": $host_literal, "ports": [443]}
    ]
  }
}
EOF
}

# ---------------------------------------------------------------------------
# W0 — POSITIVE CONTROL: legitimate FQDN host accepted (regression guard
# against over-zealous validation). If W0 fails, the validator has been
# tightened too far and would reject all real allowlists.
# ---------------------------------------------------------------------------

@test "W0 positive control: legitimate FQDN host loads cleanly" {
    _make_allowlist_with_host "$WORK_DIR/legit.json" '"api.openai.com"'
    run _load_allowlist "$WORK_DIR/legit.json"
    [[ "$status" -eq 0 ]] || {
        printf 'expected status=0 (OK), got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"OK len=1"* ]]
}

# ---------------------------------------------------------------------------
# W1-W4 — REJECTION CASES: each case fails-closed with ValueError at load.
# Status MUST be 78 (matches CLI EXIT_REJECTED) and the stderr must contain
# a glob-or-empty-or-wildcard signal so operators see the misconfig clearly.
# ---------------------------------------------------------------------------

@test "W1 rejects host equal to '*' (single wildcard)" {
    _make_allowlist_with_host "$WORK_DIR/star.json" '"*"'
    run _load_allowlist "$WORK_DIR/star.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78 (REJECTED), got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" == *"wildcard"* || "$output" == *"glob"* || "$output" == *"verbatim"* ]] || {
        printf 'rejection reason missing wildcard/glob/verbatim hint: %s\n' "$output" >&2
        return 1
    }
}

@test "W2 rejects host equal to '' (empty string)" {
    _make_allowlist_with_host "$WORK_DIR/empty.json" '""'
    run _load_allowlist "$WORK_DIR/empty.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"REJECTED"* ]]
    [[ "$output" == *"empty"* || "$output" == *"whitespace"* ]] || {
        printf 'rejection reason missing empty/whitespace hint: %s\n' "$output" >&2
        return 1
    }
}

@test "W3 rejects host that is whitespace-only (' ', tabs, mixed)" {
    _make_allowlist_with_host "$WORK_DIR/ws.json" '"   \t  "'
    run _load_allowlist "$WORK_DIR/ws.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"empty"* || "$output" == *"whitespace"* ]]
}

@test "W4 rejects host with embedded '*' (glob-like e.g. '*.openai.com')" {
    _make_allowlist_with_host "$WORK_DIR/glob.json" '"*.openai.com"'
    run _load_allowlist "$WORK_DIR/glob.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"wildcard"* || "$output" == *"glob"* ]] || {
        printf 'rejection reason missing wildcard/glob hint: %s\n' "$output" >&2
        return 1
    }
}

@test "W4b rejects host with embedded '*' in middle ('api.*.openai.com')" {
    _make_allowlist_with_host "$WORK_DIR/mid.json" '"api.*.openai.com"'
    run _load_allowlist "$WORK_DIR/mid.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"wildcard"* || "$output" == *"glob"* ]]
}

# ---------------------------------------------------------------------------
# W5 — TYPE-MISMATCH cases. The verbatim-equality check coerces via str(),
# but type-confusion at load time is a configuration-bug surface. Reject
# non-string hosts cleanly so operators see the schema violation.
# ---------------------------------------------------------------------------

@test "W5 rejects host that is null" {
    _make_allowlist_with_host "$WORK_DIR/null.json" 'null'
    run _load_allowlist "$WORK_DIR/null.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"REJECTED"* ]]
}

@test "W5b rejects host that is a number" {
    _make_allowlist_with_host "$WORK_DIR/num.json" '443'
    run _load_allowlist "$WORK_DIR/num.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"REJECTED"* ]]
}

@test "W5c rejects host that is a list" {
    _make_allowlist_with_host "$WORK_DIR/list.json" '["api.openai.com"]'
    run _load_allowlist "$WORK_DIR/list.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"REJECTED"* ]]
}

# ---------------------------------------------------------------------------
# W6 — partial-corruption case: ONE bad entry contaminates the whole file.
# The semantic is "allowlist load is all-or-nothing"; do not silently load
# the legitimate entries and silently drop the wildcard one (that hides the
# misconfig from the operator). Fail closed across the file.
# ---------------------------------------------------------------------------

@test "W6 rejects entire allowlist when ANY entry has wildcard host" {
    cat > "$WORK_DIR/mixed.json" <<'EOF'
{
  "providers": {
    "openai": [
      {"host": "api.openai.com", "ports": [443]}
    ],
    "evil": [
      {"host": "*", "ports": [443]}
    ]
  }
}
EOF
    run _load_allowlist "$WORK_DIR/mixed.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected file-wide rejection on partial-corruption; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"evil"* ]] || {
        printf 'rejection should name the offending provider; got: %s\n' "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# W7 — provenance: the rejection MUST identify provider + entry index for
# operator triage. A "host has wildcard" without context forces the operator
# to grep the file; carrying provider_id + idx in the message saves them
# the search.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# W8 — cypherpunk HIGH H1 + MEDIUM M1: Unicode look-alikes for the wildcard
# rejection. NFKC normalization + an explicit forbidden-char set MUST catch
# these before the verbatim host predicate.
# ---------------------------------------------------------------------------

@test "W8 rejects FULLWIDTH ASTERISK U+FF0A '＊' (cypherpunk H1)" {
    cat > "$WORK_DIR/fullwidth-star.json" <<'EOF'
{"providers":{"evil":[{"host":"＊","ports":[443]}]}}
EOF
    run _load_allowlist "$WORK_DIR/fullwidth-star.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78 (REJECTED); got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"REJECTED"* ]]
}

@test "W8b rejects ASTERISK OPERATOR U+2217 '∗'" {
    # Mathematical asterisk operator — visually similar; reject by NFKC norm
    # OR by explicit forbidden set.
    cat > "$WORK_DIR/asterisk-op.json" <<'EOF'
{"providers":{"evil":[{"host":"∗","ports":[443]}]}}
EOF
    run _load_allowlist "$WORK_DIR/asterisk-op.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

@test "W9 rejects '?' glob char (cypherpunk M1)" {
    _make_allowlist_with_host "$WORK_DIR/qmark.json" '"?.openai.com"'
    run _load_allowlist "$WORK_DIR/qmark.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78 for ? glob; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"glob"* || "$output" == *"wildcard"* ]]
}

@test "W10 rejects host containing real NUL byte (cypherpunk M1)" {
    # printf %b processes octal escapes; \000 emits one literal NUL byte.
    # We bypass argv (NUL-incompatible on POSIX) by writing directly to
    # the JSON file via redirected stdout. Python's json.load decodes the
    # NUL as a real U+0000 in the host string.
    printf '%b' '{"providers":{"evil":[{"host":"api.openai.com\000.attacker.com","ports":[443]}]}}' \
        > "$WORK_DIR/nul-real.json"
    run _load_allowlist "$WORK_DIR/nul-real.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78 for real NUL byte; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"control"* || "$output" == *"0x00"* ]] || {
        printf 'rejection should mention control / 0x00; got: %s\n' "$output" >&2
        return 1
    }
}

@test "W11 rejects host containing newline (cypherpunk M1)" {
    cat > "$WORK_DIR/newline.json" <<'EOF'
{"providers":{"evil":[{"host":"api.openai.com\nevil.example.com","ports":[443]}]}}
EOF
    run _load_allowlist "$WORK_DIR/newline.json"
    [[ "$status" -eq 78 ]] || {
        printf 'expected status=78 for newline in host; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

@test "W11b rejects host containing carriage return (cypherpunk M1)" {
    cat > "$WORK_DIR/cr.json" <<'EOF'
{"providers":{"evil":[{"host":"api.openai.com\revil.example.com","ports":[443]}]}}
EOF
    run _load_allowlist "$WORK_DIR/cr.json"
    [[ "$status" -eq 78 ]]
}

@test "W11c rejects host containing tab (cypherpunk M1)" {
    cat > "$WORK_DIR/tab.json" <<'EOF'
{"providers":{"evil":[{"host":"api\topenai.com","ports":[443]}]}}
EOF
    run _load_allowlist "$WORK_DIR/tab.json"
    [[ "$status" -eq 78 ]]
}

@test "W7 rejection message identifies provider and entry index" {
    cat > "$WORK_DIR/triage.json" <<'EOF'
{
  "providers": {
    "openai": [
      {"host": "api.openai.com", "ports": [443]},
      {"host": "*", "ports": [443]}
    ]
  }
}
EOF
    run _load_allowlist "$WORK_DIR/triage.json"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"openai"* ]]
    # The wildcard is at index 1 (zero-indexed); the message must reference
    # SOME index marker so operators can pinpoint the bad entry.
    [[ "$output" == *"1"* ]] || {
        printf 'rejection should reference entry index; got: %s\n' "$output" >&2
        return 1
    }
}
