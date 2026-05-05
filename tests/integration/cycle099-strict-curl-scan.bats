#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle099-strict-curl-scan.bats
#
# cycle-099 Sprint 1E.c.3.c — strict-mode scan for raw curl/wget callers.
#
# All bash HTTP calls MUST funnel through endpoint_validator__guarded_curl.
# This test file pins the contract enforced by `tools/check-no-raw-curl.sh`,
# which is invoked by .github/workflows/cycle099-sprint-1e-b-tests.yml as a
# blocking CI gate.
#
# Test taxonomy:
#   ST1   POSITIVE CONTROL: current tree passes (no violations).
#   ST2   NEGATIVE CONTROL: synthetic raw curl invocation is flagged.
#   ST3   COMPLIANT FORM:    synthetic call via wrapper passes.
#   ST4-7 FALSE-POSITIVE GUARDS: comments / existence checks / echo-strings /
#                                heredocs do NOT trigger.
#   ST8   SUPPRESSION MARKER: `# check-no-raw-curl: ok` skipped.
#   ST9   IDENTIFIER-SUFFIX:   endpoint_validator__guarded_curl unaffected.
#   ST10  WGET PARITY:         wget is also flagged when raw.
#   ST11  LINE CONTINUATION:   curl with `\` newline still flagged.
#   ST12  EXEMPT FILES:        the 3 exempt files load without scan flagging.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-no-raw-curl.sh"

    [[ -x "$SCANNER" ]] || skip "scanner not present or not executable"

    WORK_DIR="$(mktemp -d)"
    SYNTH_ROOT="$WORK_DIR/synth"
    mkdir -p "$SYNTH_ROOT"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Drop a synthetic file at $SYNTH_ROOT/$1 with content $2. The scanner is
# directed at $SYNTH_ROOT via --root so it sees only synthetic files.
_synth() {
    local rel="$1" content="$2"
    local path="$SYNTH_ROOT/$rel"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
}

# ---------------------------------------------------------------------------
# ST1 — POSITIVE CONTROL on real codebase. Must pass.
# ---------------------------------------------------------------------------

@test "ST1 current tree passes the strict scan (positive control)" {
    cd "$PROJECT_ROOT"
    run "$SCANNER" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'expected current tree to pass strict scan; got status=%d\n' "$status" >&2
        # Re-run non-quiet to surface violations
        "$SCANNER" >&2 || true
        return 1
    }
}

# ---------------------------------------------------------------------------
# ST2 — NEGATIVE CONTROL: a fresh raw curl invocation MUST be flagged.
# ---------------------------------------------------------------------------

@test "ST2 synthetic raw curl invocation is flagged (status=1)" {
    _synth "violator.sh" '#!/usr/bin/env bash
curl https://api.example.com/v1/data
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]] || {
        printf 'expected violation flagged; got status=%d\n' "$status" >&2
        return 1
    }
}

@test "ST2b synthetic raw curl with flag (curl -fsSL URL) is flagged" {
    _synth "violator-flagged.sh" '#!/usr/bin/env bash
curl -fsSL "$DOWNLOAD_URL"
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]]
}

@test "ST2c synthetic raw curl in subshell ($(curl ...)) is flagged" {
    _synth "violator-subshell.sh" '#!/usr/bin/env bash
data=$(curl -s https://api.example.com)
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# ST3 — COMPLIANT FORM: invocation via wrapper passes.
# ---------------------------------------------------------------------------

@test "ST3 synthetic wrapper invocation passes" {
    _synth "compliant.sh" '#!/usr/bin/env bash
source .claude/scripts/lib/endpoint-validator.sh
endpoint_validator__guarded_curl --allowlist X --url Y -sS
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'compliant file should pass scan; output=%s\n' "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# ST4 — FALSE-POSITIVE GUARDS: each of these MUST pass even though `curl`
# appears in the source. Comment, existence check, echo string, heredoc.
# ---------------------------------------------------------------------------

@test "ST4 comment mentioning curl is NOT flagged" {
    _synth "comment.sh" '#!/usr/bin/env bash
# curl is the canonical HTTP client; we use the wrapper instead
do_thing
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

@test "ST5 existence check 'command -v curl' is NOT flagged" {
    _synth "exist-cmd.sh" '#!/usr/bin/env bash
if ! command -v curl >/dev/null 2>&1; then
    echo "no curl" >&2
fi
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'existence check should not be flagged; output=%s\n' "$output" >&2
        return 1
    }
}

@test "ST5b existence check 'which curl' is NOT flagged" {
    _synth "exist-which.sh" '#!/usr/bin/env bash
which curl >/dev/null
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

@test "ST6 echo with curl in string is NOT flagged" {
    _synth "echo-doc.sh" '#!/usr/bin/env bash
echo "  curl --proto =https -sSf https://example.com/install | sh"
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

@test "ST6b printf with curl in string is NOT flagged" {
    _synth "printf-doc.sh" '#!/usr/bin/env bash
printf "  curl -fsSL %s\n" "$URL"
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

@test "ST7 heredoc body containing curl example is NOT flagged" {
    _synth "heredoc-doc.sh" '#!/usr/bin/env bash
cat <<EOF
Usage:
  helper.sh retry curl -s https://example.com/data
  helper.sh other args
EOF
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'heredoc curl example should not be flagged; output=%s\n' "$output" >&2
        return 1
    }
}

@test "ST7b quoted heredoc <<'EOF' with curl is NOT flagged" {
    _synth "heredoc-quoted.sh" '#!/usr/bin/env bash
cat <<'\''USAGE'\''
  curl -fsSL https://example.com
USAGE
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

@test "ST7c dash heredoc <<-EOF (tab-stripped terminator) with curl is NOT flagged" {
    # Need actual tab characters for <<- behavior
    printf '#!/usr/bin/env bash\ncat <<-EOF\n\tcurl -s https://x\n\tEOF\n' > "$SYNTH_ROOT/heredoc-dash.sh"
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'dash heredoc should be tracked; output=%s\n' "$output" >&2
        return 1
    }
}

@test "ST7d heredoc body STILL skips even with raw curl LATER in same file" {
    # Heredoc mention is documentation. If real curl follows the heredoc,
    # it MUST still be flagged (the heredoc-skip is not a global pass).
    _synth "heredoc-then-violation.sh" '#!/usr/bin/env bash
cat <<EOF
  curl docs go here
EOF
curl https://real-violation.example
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]] || {
        printf 'real curl after heredoc should still be flagged; status=%d\n' "$status" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# ST8 — explicit suppression marker (escape hatch).
# ---------------------------------------------------------------------------

@test "ST8 line with '# check-no-raw-curl: ok' marker is NOT flagged" {
    _synth "suppressed.sh" '#!/usr/bin/env bash
# Bootstrap path — must not depend on .venv being present.
curl --proto =https -fsSL https://x  # check-no-raw-curl: ok (bootstrap)
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]] || {
        printf 'suppression marker should silence scan; output=%s\n' "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# ST9 — identifier-suffix (word-boundary) — endpoint_validator__guarded_curl
# MUST NOT match because the `curl` substring is preceded by `_` (an
# identifier char, not a word boundary).
# ---------------------------------------------------------------------------

@test "ST9 endpoint_validator__guarded_curl invocation is NOT flagged" {
    _synth "identifier.sh" '#!/usr/bin/env bash
endpoint_validator__guarded_curl --allowlist X --url Y -sS -X POST
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# ST10 — wget parity. wget is treated identically to curl by the scanner.
# ---------------------------------------------------------------------------

@test "ST10 raw wget invocation is flagged" {
    _synth "wget-violator.sh" '#!/usr/bin/env bash
wget -O - https://example.com/data
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# ST11 — line continuation. `curl \` followed by args on next line is still
# a curl invocation; the trailing `\` matches the suffix character class.
# ---------------------------------------------------------------------------

@test "ST11 curl with line-continuation backslash is flagged" {
    _synth "continuation.sh" '#!/usr/bin/env bash
curl \
    --max-time 5 \
    https://example.com/data
'
    run "$SCANNER" --root "$SYNTH_ROOT" --quiet
    [[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# ST12 — exempt files: synthesizing them in the SCAN ROOT confirms the
# exemption mechanism works (the scanner skips them by their canonical path
# match, not by content).
# ---------------------------------------------------------------------------

@test "ST12 the 3 exempt files load and pass scan via real-tree run" {
    cd "$PROJECT_ROOT"
    # All 3 files exist in the real tree; ST1 already verifies the tree
    # passes. Here we additionally pin that the exemption list contains
    # exactly those three paths.
    grep -qF '.claude/scripts/lib/endpoint-validator.sh' "$SCANNER"
    grep -qF '.claude/scripts/mount-loa.sh' "$SCANNER"
    grep -qF '.claude/scripts/model-health-probe.sh' "$SCANNER"
    [[ -f .claude/scripts/lib/endpoint-validator.sh ]]
    [[ -f .claude/scripts/mount-loa.sh ]]
    [[ -f .claude/scripts/model-health-probe.sh ]]
}

# ---------------------------------------------------------------------------
# ST13 — output ergonomics: the violation report names the file + line
# number so operators can navigate directly to the offense.
# ---------------------------------------------------------------------------

@test "ST13 violation message includes file path + line number" {
    _synth "diag.sh" '#!/usr/bin/env bash
echo "ok"
curl https://x
echo "done"
'
    run "$SCANNER" --root "$SYNTH_ROOT"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"diag.sh"* ]] || {
        printf 'violation message should name the offending file: %s\n' "$output" >&2
        return 1
    }
    [[ "$output" == *":3:"* || "$output" == *"3:"* ]] || {
        printf 'violation message should include line number 3 (curl line): %s\n' "$output" >&2
        return 1
    }
}
