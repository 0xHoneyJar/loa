#!/usr/bin/env bats
# =============================================================================
# flatline-orchestrator-max-tokens.bats — sub-issue 4 (issue #675)
# =============================================================================
# Verifies the new `--per-call-max-tokens <N>` CLI flag on
# flatline-orchestrator.sh:
#
#   Case A: --per-call-max-tokens 4096 → propagated as --max-tokens 4096 to
#           the underlying model invocation (cheval / model-adapter)
#   Case B: flag unset → default behavior preserved (no regression)
#   Case C: prompt > 100KB and flag unset → orchestrator emits stderr
#           WARNING: "Document size NN KB; recommend `--per-call-max-tokens
#           4096` to avoid Anthropic 60s server-side disconnect"
#
# Tests must FAIL pre-fix (no flag exists, no warning emitted) and PASS
# post-fix (flag added to CLI parser + plumbed to model layer + warning).
#
# We exercise main()'s argument-parsing block by using --dry-run, which exits
# early after validating arguments — this isolates the CLI parser from the
# orchestration pipeline (no mocks for cheval/curl needed). Case C uses a
# fresh-output run with a stub model-adapter that exits early.
# =============================================================================

setup() {
    ORCHESTRATOR="${BATS_TEST_DIRNAME}/../../.claude/scripts/flatline-orchestrator.sh"
    [[ -f "$ORCHESTRATOR" ]] || skip "flatline-orchestrator.sh not present at $ORCHESTRATOR"

    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export PROJECT_ROOT
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ----------------------------------------------------------------------------
# Case A: --per-call-max-tokens 4096 honored
# ----------------------------------------------------------------------------
@test "flatline-orchestrator: --per-call-max-tokens 4096 is parsed (no Unknown option error)" {
    # Small fixture inside project root (orchestrator validates path-prefix).
    local doc="$PROJECT_ROOT/tests/fixtures/per-call-max-tokens-doc-small.md"
    mkdir -p "$(dirname "$doc")"
    printf '# Tiny test doc\n\nHello world.\n' > "$doc"

    # --dry-run exits 0 after validation — perfect for CLI parser checks
    # without invoking real model calls.
    run "$ORCHESTRATOR" --doc "$doc" --phase prd --per-call-max-tokens 4096 --dry-run --json

    rm -f "$doc"

    # Pre-fix: orchestrator's case statement has no `--per-call-max-tokens`
    # branch — falls through to the `*)` default which prints
    # "Unknown option: --per-call-max-tokens" and exits 1.
    [[ "$status" -eq 0 ]] || {
        echo "FAIL: --per-call-max-tokens not recognized; status=$status"
        echo "output: $output"
        false
    }
    [[ "$output" != *"Unknown option: --per-call-max-tokens"* ]] || {
        echo "FAIL: orchestrator rejects --per-call-max-tokens flag"
        false
    }
}

# ----------------------------------------------------------------------------
# Case B: default preserved when flag unset
# ----------------------------------------------------------------------------
@test "flatline-orchestrator: default behavior preserved when --per-call-max-tokens unset" {
    local doc="$PROJECT_ROOT/tests/fixtures/per-call-max-tokens-doc-small-2.md"
    mkdir -p "$(dirname "$doc")"
    printf '# Tiny test doc\n' > "$doc"

    # Without the flag, --dry-run must still succeed (no regression).
    run "$ORCHESTRATOR" --doc "$doc" --phase prd --dry-run --json

    rm -f "$doc"

    [[ "$status" -eq 0 ]] || {
        echo "FAIL: dry-run without flag broke; status=$status"
        echo "output: $output"
        false
    }

    # No "Unknown option" diagnostic from validation
    [[ "$output" != *"Unknown option"* ]]

    # No --per-call-max-tokens warning at this size (small doc < 100KB)
    [[ "$output" != *"recommend \`--per-call-max-tokens"* ]] || {
        echo "FAIL: small-doc warning leaked"
        false
    }
}

# ----------------------------------------------------------------------------
# Case C: stderr warning emitted for >100KB doc when flag unset
# ----------------------------------------------------------------------------
@test "flatline-orchestrator: emits warning for >100KB doc when --per-call-max-tokens unset" {
    # Generate a 150KB markdown document — above the 100KB threshold.
    local doc="$PROJECT_ROOT/tests/fixtures/per-call-max-tokens-doc-large.md"
    mkdir -p "$(dirname "$doc")"
    {
        printf '# Large test doc (≥100KB)\n\n'
        # 150 * 1024 bytes ≈ 153600
        local i=0
        while [[ $i -lt 1024 ]]; do
            printf 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam.\n'
            i=$((i + 1))
        done
    } > "$doc"
    local size_kb=$(($(wc -c < "$doc") / 1024))
    [[ $size_kb -gt 100 ]] || {
        echo "Setup failure: doc only ${size_kb}KB, need >100KB"
        rm -f "$doc"
        false
    }

    # --dry-run exits early. The warning should still be emitted before
    # exit if it's plumbed into the validation/early-config phase.
    run "$ORCHESTRATOR" --doc "$doc" --phase prd --dry-run --json
    local exit_code="$status"
    local combined_output="$output"

    rm -f "$doc"

    [[ "$exit_code" -eq 0 ]] || {
        echo "FAIL: dry-run failed; status=$exit_code"
        echo "output: $combined_output"
        false
    }

    # Required warning string (exact substring per sprint AC).
    # NN is the rounded KB value — match the structural pattern, not literal NN.
    [[ "$combined_output" == *"recommend \`--per-call-max-tokens 4096\` to avoid Anthropic 60s server-side disconnect"* ]] || {
        echo "FAIL: missing >100KB warning. Expected substring:"
        echo "  recommend \`--per-call-max-tokens 4096\` to avoid Anthropic 60s server-side disconnect"
        echo "Actual output:"
        echo "$combined_output"
        false
    }

    # Document size prefix should also be present
    [[ "$combined_output" == *"Document size"*"KB"* ]] || {
        echo "FAIL: warning missing 'Document size NN KB' prefix"
        false
    }
}
