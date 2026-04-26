#!/usr/bin/env bats
# =============================================================================
# dispatch-log-grammar.bats — validates shape table at
# grimoires/loa/proposals/dispatch-log-grammar.md
# =============================================================================
# Each test feeds a representative line to a single shape's regex and asserts
# it matches (or, for invalid fixtures, doesn't). If the harness's log()
# output drifts, these tests fail loud rather than letting monitors silently
# mis-parse a phase-transition or circuit-breaker line.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export GRAMMAR="$PROJECT_ROOT/grimoires/loa/proposals/dispatch-log-grammar.md"
}

# =========================================================================
# DLG-T1: harness lifecycle shapes
# =========================================================================

@test "harness-start line matches API shape" {
    local line='[harness] Harness starting: cycle=cycle-092 branch=feat/foo budget=$10 profile=standard'
    [[ "$line" =~ ^\[harness\]\ Harness\ starting:\ cycle=[^[:space:]]+\ branch=[^[:space:]]+\ budget=\$[^[:space:]]+\ profile=[^[:space:]]+$ ]]
}

@test "harness-complete line matches API shape with cost field" {
    local line='[harness] Harness complete: cycle=cycle-092 profile=standard cost=$24.50'
    [[ "$line" =~ ^\[harness\]\ Harness\ complete:\ cycle=[^[:space:]]+\ profile=[^[:space:]]+\ cost=\$[0-9.]+$ ]]
}

# =========================================================================
# DLG-T2: phase-transition — all 5 public phases (1–6)
# =========================================================================

@test "phase 1 DISCOVERY matches phase-transition shape" {
    local line='[harness] Phase 1: DISCOVERY'
    [[ "$line" =~ ^\[harness\]\ Phase\ [1-6]:\ [A-Z_\ ]+$ ]]
}

@test "phase 2 ARCHITECTURE matches phase-transition shape" {
    local line='[harness] Phase 2: ARCHITECTURE'
    [[ "$line" =~ ^\[harness\]\ Phase\ [1-6]:\ [A-Z_\ ]+$ ]]
}

@test "phase 3 PLANNING matches phase-transition shape" {
    local line='[harness] Phase 3: PLANNING'
    [[ "$line" =~ ^\[harness\]\ Phase\ [1-6]:\ [A-Z_\ ]+$ ]]
}

@test "phase 4 IMPLEMENTATION matches phase-transition shape" {
    local line='[harness] Phase 4: IMPLEMENTATION'
    [[ "$line" =~ ^\[harness\]\ Phase\ [1-6]:\ [A-Z_\ ]+$ ]]
}

@test "phase 5 PR CREATION matches phase-transition shape (multi-word label)" {
    local line='[harness] Phase 5: PR CREATION'
    [[ "$line" =~ ^\[harness\]\ Phase\ [1-6]:\ [A-Z_\ ]+$ ]]
}

# =========================================================================
# DLG-T3: pre-check shapes
# =========================================================================

@test "pre-check-start (SEED) matches shape" {
    local line='[harness] Pre-check: validating SEED environment'
    [[ "$line" =~ ^\[harness\]\ Pre-check:\  ]]
}

@test "pre-check-start (planning artifacts) matches shape" {
    local line='[harness] Pre-check: validating planning artifacts'
    [[ "$line" =~ ^\[harness\]\ Pre-check:\  ]]
}

@test "pre-check-start (pre-review) matches shape" {
    local line='[harness] Pre-check: validating implementation before review'
    [[ "$line" =~ ^\[harness\]\ Pre-check:\  ]]
}

# =========================================================================
# DLG-T4: gate-attempt across REVIEW and AUDIT
# =========================================================================

@test "gate-attempt REVIEW attempt 1/3 matches shape" {
    local line='[harness] Gate: REVIEW (attempt 1/3)'
    [[ "$line" =~ ^\[harness\]\ Gate:\ [^[:space:]]+\ \(attempt\ [0-9]+/[0-9]+\)$ ]]
}

@test "gate-attempt REVIEW attempt 3/3 matches shape" {
    local line='[harness] Gate: REVIEW (attempt 3/3)'
    [[ "$line" =~ ^\[harness\]\ Gate:\ [^[:space:]]+\ \(attempt\ [0-9]+/[0-9]+\)$ ]]
}

@test "gate-attempt AUDIT attempt 2/3 matches shape" {
    local line='[harness] Gate: AUDIT (attempt 2/3)'
    [[ "$line" =~ ^\[harness\]\ Gate:\ [^[:space:]]+\ \(attempt\ [0-9]+/[0-9]+\)$ ]]
}

@test "gate-attempt-retry matches shape" {
    local line='[harness] Gate REVIEW failed (attempt 1), will retry...'
    [[ "$line" =~ ^\[harness\]\ Gate\ [^[:space:]]+\ failed\ \(attempt\ [0-9]+\),\ will\ retry\.\.\.$ ]]
}

@test "gate-independent-review matches shape" {
    local line='[harness] Gate: Independent review (fresh session, model=opus)'
    [[ "$line" =~ ^\[harness\]\ Gate:\ Independent\ review\ \(fresh\ session,\ model=[^[:space:]]+\)$ ]]
}

@test "gate-independent-audit matches shape" {
    local line='[harness] Gate: Independent security audit (fresh session, model=opus)'
    [[ "$line" =~ ^\[harness\]\ Gate:\ Independent\ security\ audit\ \(fresh\ session,\ model=[^[:space:]]+\)$ ]]
}

# =========================================================================
# DLG-T5: review-fix-loop shapes
# =========================================================================

@test "review-fix-iteration 1/2 matches shape" {
    local line='[harness] Review fix loop: iteration 1/2'
    [[ "$line" =~ ^\[harness\]\ Review\ fix\ loop:\ iteration\ [0-9]+/[0-9]+$ ]]
}

@test "review-fix-iteration 2/2 matches shape" {
    local line='[harness] Review fix loop: iteration 2/2'
    [[ "$line" =~ ^\[harness\]\ Review\ fix\ loop:\ iteration\ [0-9]+/[0-9]+$ ]]
}

@test "review-passed-iter matches shape" {
    local line='[harness] Review PASSED on iteration 2/2'
    [[ "$line" =~ ^\[harness\]\ Review\ PASSED\ on\ iteration\ [0-9]+/[0-9]+$ ]]
}

@test "review-fix-loop-exhausted matches shape" {
    local line='[harness] Review FAILED: exhausted 2 fix iterations'
    [[ "$line" =~ ^\[harness\]\ Review\ FAILED:\ exhausted\ [0-9]+\ fix\ iterations$ ]]
}

@test "review-changes-required-dispatch matches shape" {
    local line='[harness] Review CHANGES_REQUIRED — dispatching implementation fix (iteration 2/2)'
    [[ "$line" =~ ^\[harness\]\ Review\ CHANGES_REQUIRED.*dispatching\ implementation\ fix.*iteration\ [0-9]+/[0-9]+\)$ ]]
}

# =========================================================================
# DLG-T6: circuit-breaker-trip — note ERROR: prefix (not [harness])
# =========================================================================

@test "circuit-breaker REVIEW matches shape (ERROR prefix)" {
    local line='ERROR: Circuit breaker: REVIEW failed after 3 attempts'
    [[ "$line" =~ ^ERROR:\ Circuit\ breaker:\ [^[:space:]]+\ failed\ after\ [0-9]+\ attempts$ ]]
}

@test "circuit-breaker AUDIT matches shape (ERROR prefix)" {
    local line='ERROR: Circuit breaker: AUDIT failed after 3 attempts'
    [[ "$line" =~ ^ERROR:\ Circuit\ breaker:\ [^[:space:]]+\ failed\ after\ [0-9]+\ attempts$ ]]
}

# =========================================================================
# DLG-T7: terminal verdicts
# =========================================================================

@test "review-changes-required-terminal matches shape" {
    local line='[harness] Review CHANGES_REQUIRED — implementation needs work (fix loop exhausted)'
    [[ "$line" =~ ^\[harness\]\ Review\ CHANGES_REQUIRED.*implementation\ needs\ work.*fix\ loop\ exhausted\)$ ]]
}

@test "audit-changes-required-terminal matches shape" {
    local line='[harness] Audit CHANGES_REQUIRED — security issues found'
    [[ "$line" =~ ^\[harness\]\ Audit\ CHANGES_REQUIRED.*security\ issues\ found$ ]]
}

# =========================================================================
# DLG-T8: PR creation shapes
# =========================================================================

@test "pr-created matches shape with github URL" {
    local line='[harness] PR created: https://github.com/0xHoneyJar/loa/pull/597'
    [[ "$line" =~ ^\[harness\]\ PR\ created:\ https://[^[:space:]]+$ ]]
}

@test "pr-reused matches shape with github URL" {
    local line='[harness] Reusing existing PR: https://github.com/0xHoneyJar/loa/pull/597'
    [[ "$line" =~ ^\[harness\]\ Reusing\ existing\ PR:\ https://[^[:space:]]+$ ]]
}

# =========================================================================
# DLG-T9: reserved shapes (Sprints 2/3/4 will emit these)
# =========================================================================
# These are regex fixtures that the downstream sprint must adhere to.
# Failing tests here means a downstream sprint drifted from the reserved shape
# — grammar spec amendment required first.

@test "reserved impl-evidence-missing matches reserved shape" {
    local line='[harness] IMPL_EVIDENCE_MISSING — 2 sprint-plan paths not produced: src/lib/scenes/Reliquary.svelte,src/routes/(rooms)/reliquary/+page.svelte'
    [[ "$line" =~ ^\[harness\]\ IMPL_EVIDENCE_MISSING.*[0-9]+\ sprint-plan\ paths ]]
}

@test "reserved impl-evidence-trivial matches reserved shape" {
    local line='[harness] IMPL_EVIDENCE_TRIVIAL — 1 paths below content threshold: src/lib/stub.ts'
    [[ "$line" =~ ^\[harness\]\ IMPL_EVIDENCE_TRIVIAL.*[0-9]+\ paths\ below\ content\ threshold ]]
}

@test "reserved phase-heartbeat-emitted matches reserved shape" {
    local line='[HEARTBEAT 2026-04-19T07:22:00Z] phase=REVIEW phase_verb=reviewing phase_elapsed_sec=180 total_elapsed_sec=3900 cost_usd=70.00 budget_usd=80 files=44 ins=7696 del=4882 activity=quiet confidence=attempt_2_of_3 pace=on_pace'
    [[ "$line" =~ ^\[HEARTBEAT\ [^]]+\]\ phase=[^[:space:]]+\ phase_verb=[^[:space:]]+ ]]
}

@test "reserved phase-intent-change matches reserved shape" {
    local line='[INTENT 2026-04-19T07:22:00Z] phase=REVIEW intent="checking amendment compliance against the implementation" source=grimoires/loa/a2a/engineer-feedback.md'
    [[ "$line" =~ ^\[INTENT\ [^]]+\]\ phase=[^[:space:]]+\ intent=\".+\"\ source=[^[:space:]]+$ ]]
}

@test "reserved phase-current-cleared matches reserved shape" {
    local line='[harness] .phase-current cleared'
    [[ "$line" =~ ^\[harness\]\ \.phase-current\ cleared$ ]]
}

# =========================================================================
# DLG-T10: grammar spec document structure (sanity)
# =========================================================================

@test "dispatch-log-grammar.md document exists and contains shape table" {
    [[ -f "$GRAMMAR" ]]
    run grep -c '^| `' "$GRAMMAR"
    # Should have 20+ shape table rows across sections
    [ "$status" -eq 0 ]
    [[ "$output" -gt 20 ]]
}

@test "grammar spec declares all 5 reserved shapes" {
    local reserved=(impl-evidence-missing impl-evidence-trivial phase-heartbeat-emitted phase-intent-change phase-current-cleared)
    for shape in "${reserved[@]}"; do
        grep -q "$shape" "$GRAMMAR" || return 1
    done
}

@test "grammar spec declares path migration from harness-stderr.log to dispatch.log" {
    grep -q "harness-stderr.log" "$GRAMMAR"
    grep -q "dispatch.log" "$GRAMMAR"
}

@test "grammar spec declares phase_label enum with >=10 phases" {
    # Check at least these core phases are named
    local phases=(PRE_CHECK_SEED DISCOVERY ARCHITECTURE PLANNING IMPLEMENT REVIEW AUDIT PR_CREATION)
    for p in "${phases[@]}"; do
        grep -q "$p" "$GRAMMAR" || return 1
    done
}

# =========================================================================
# DLG-T11: actual harness log() output shape verification
# =========================================================================
# Sanity check: actual spiral-harness.sh still emits the shapes declared.
# Not a full run — just verify the format strings in source match the
# regex fixtures above.

@test "log() helper produces [harness]-prefixed output to stderr (behavioral, source-and-call)" {
    # Iter-6 BB F-001-codex: previous version was `grep -q 'log() { echo "\[harness\] \$\*" >&2; }'`,
    # which fails on harmless reformat (printf instead of echo, function keyword,
    # shellcheck-friendly quote nudges). Tests the byte shape, not behavior.
    #
    # Iter-7 BB F-001-codex (HIGH_CONSENSUS, security): the iter-6 version of
    # this test extracted the function body via awk and executed it via
    # `bash -c "$fn_body; log ..."` — repository-controlled text becoming
    # test-runtime code. Any extraction drift (heredoc, nested brace, etc.)
    # would silently change what executes; an unrelated edit could turn the
    # test from "assert log() shape" into "execute whatever log()-region
    # extraction returned".
    #
    # Now: source spiral-harness.sh directly. The script has a BASH_SOURCE
    # guard at the bottom (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`)
    # that prevents main() from running when sourced. Top-level statements
    # (`set -euo pipefail`, source bootstrap/evidence/compat-lib) are safe
    # under source. log() is then a normal function call — no eval, no
    # text-extraction, no test/impl-boundary drift surface.
    local stdout_capture stderr_capture
    stdout_capture=$(bash -c "source '$PROJECT_ROOT/.claude/scripts/spiral-harness.sh'; log 'TEST_MESSAGE_42'" 2>/dev/null)
    stderr_capture=$(bash -c "source '$PROJECT_ROOT/.claude/scripts/spiral-harness.sh'; log 'TEST_MESSAGE_42'" 2>&1 >/dev/null)

    # Behavioral assertions: contract verified by direct invocation.
    [ -z "$stdout_capture" ]                                  # nothing on stdout
    [[ "$stderr_capture" == "[harness] TEST_MESSAGE_42" ]]    # prefixed + verbatim payload, on stderr
}

@test "spiral-harness.sh still emits 'Phase N:' transitions" {
    grep -qE 'log "Phase [1-6]:' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

@test "spiral-harness.sh still emits 'Pre-check:' lines" {
    grep -qE 'log "Pre-check:' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

@test "spiral-harness.sh still emits 'Gate: X (attempt N/M)' via _run_gate" {
    grep -qE 'log "Gate: \$gate_name \(attempt' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

@test "spiral-harness.sh still emits 'Circuit breaker:' via error()" {
    grep -qE 'Circuit breaker: \$gate_name failed' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

# =========================================================================
# DLG-T12: grammar coverage — every log() line falls under some shape
# =========================================================================
# cycle-092 Sprint 1 review F-2: AC "enumerates every current log() line"
# is satisfied via the named shapes + informational passthrough catch-alls.
# This test validates total-line count vs declared/catch-all coverage.

@test "grammar spec declares informational-passthrough catch-all shapes" {
    grep -q 'warning-passthrough' "$GRAMMAR"
    grep -q 'error-passthrough' "$GRAMMAR"
    # `informational` appears as a shape name in backticks inside a table row
    grep -qE '\| +`informational` +\|' "$GRAMMAR"
}

# cycle-092 Sprint 2 (#600) — promoted shapes: impl-evidence-missing + impl-evidence-trivial
@test "impl-evidence-missing is declared API shape (promoted from reserved)" {
    # Should appear in Evidence gates section (declared), not Reserved shapes
    grep -q "### Evidence gates" "$GRAMMAR"
    grep -qE "impl-evidence-missing.*API.*IMPL_EVIDENCE_MISSING" "$GRAMMAR"
    # Should NOT appear as "reserved →" in the Reserved shapes table
    ! grep -qE "^\| \`impl-evidence-missing\` \| 2.*reserved → API" "$GRAMMAR"
}

@test "impl-evidence-trivial is declared API shape (promoted from reserved)" {
    grep -qE "impl-evidence-trivial.*API.*IMPL_EVIDENCE_TRIVIAL" "$GRAMMAR"
    ! grep -qE "^\| \`impl-evidence-trivial\` \| 2.*reserved → API" "$GRAMMAR"
}

@test "grammar phase enum includes PRE_CHECK_IMPL_EVIDENCE (Sprint 2 addition)" {
    grep -q "PRE_CHECK_IMPL_EVIDENCE" "$GRAMMAR"
}

@test "spiral-harness.sh has >=40 log() call sites and a [harness]-prefix helper (floor sanity)" {
    # Iter-6 BB F-002-codex (HIGH_CONSENSUS) fix: previously named "every log()
    # line matches at least one declared or catch-all shape" — that name promised
    # behavioral grammar conformance, but the body only checked (1) log() helper
    # exists (2) call-site count >= floor. This is a FLOOR SANITY CHECK, not a
    # conformance pass. Renaming to match what it actually does.
    #
    # The real per-row conformance pass is DLG-T13 ("every declared grammar
    # shape: regex matches its own example line") below — which iterates the
    # grammar table and validates each declared regex against its example.
    #
    # This test remains as a backstop: if log() ever loses its [harness] prefix
    # OR the call-site count crashes below 40, that's a structural change worth
    # surfacing separately from the row-by-row conformance pass.
    local total covered
    total=$(grep -cE '^\s*log "' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh")
    [[ "$total" -ge 40 ]]
    covered=$(grep -cE 'echo "\[harness\] \$\*"' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh")
    [[ "$covered" -ge 1 ]]
}

# =========================================================================
# DLG-T13: behavioral grammar-conformance test (Iter-5 BB F-001 fix)
# =========================================================================
# Every row in the grammar table provides a regex AND an example line. Both
# are part of the documented contract. This test parses the table and asserts
# that each example line matches its declared regex — closing the loop on
# "grammar coverage" as a behavioral assertion rather than a source-grep
# tautology. If a future edit weakens a regex or breaks an example, this
# test surfaces it specifically (which row, which regex, which example).
#
# Replaces the previous DLG-T12 "log() helper exists" tautology with an
# actual contract verification.
# =========================================================================

@test "every declared grammar shape: regex matches its own example line" {
    # Iter-6 BB F-005-low fix: PCRE-grep probe with explicit skip rather than
    # silent vacuous-pass. macOS BSD grep + minimal Alpine lack -P; without
    # this probe, the test's `grep -qP` invocations would silently fail and
    # every row would skip into "no mismatch" — a false-green. The probe
    # actually exercises a known-good PCRE pattern; if it fails, skip loudly.
    if ! echo 'test1' | grep -qP '\d' 2>/dev/null; then
        skip "grep -P (PCRE) not supported in this environment — grammar conformance test requires PCRE syntax (\\d, \\S) used in spec"
    fi

    # Extract grammar rows of shape: | `name` | line(s) | `regex` | API/internal | `example` |
    # awk parses the markdown table, splits on `|`, strips backticks,
    # and emits one "name<TAB>regex<TAB>example" per row to stdout.
    #
    # The example column may itself contain pipe characters (rare —
    # used in error messages quoting alternatives). Empirically the
    # grammar today uses one pipe per example, but to be robust we
    # take everything between the 4th and final `|` as the example.
    local extracted
    extracted=$(awk -F'|' '
        # Match table rows starting with | `name` |
        $2 ~ /^[[:space:]]*`[a-z][a-z0-9-]+`[[:space:]]*$/ {
            # Skip the table header separator and example column header
            if ($4 ~ /shape regex|^[[:space:]]*-+[[:space:]]*$/) next
            name = $2; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", name)
            regex = $4; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", regex)
            example = $6; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", example)
            # Only emit rows that look like the standard 5-column shape:
            # regex must look like a regex (starts with `^` after trim) AND
            # have balanced parens (truncation by awks `|` field-split is
            # detected via paren imbalance).
            # This filters out:
            #  - rows where the regex contains a literal `|` that splits awk fields
            #    (e.g. flight recorder example). Those would have
            #    unbalanced parens after extraction
            #  - rows with extra columns (Sprint 4 entries) where field 4 is not the regex
            regex_tmp = regex
            opens = gsub(/[(]/, "X", regex_tmp)
            regex_tmp = regex
            closes = gsub(/[)]/, "X", regex_tmp)
            if (name && regex && example && regex ~ /^\^/ && opens == closes) {
                print name "\t" regex "\t" example
            }
        }
    ' "$GRAMMAR")
    [ -n "$extracted" ]

    # Sanity floor: expect at least 30 conforming rows in the grammar
    local row_count
    row_count=$(echo "$extracted" | wc -l)
    [[ "$row_count" -ge 30 ]] || { echo "expected >=30 grammar rows, got $row_count"; false; }

    # For each row, assert example matches regex. Failure prints the
    # offending row so the maintainer sees exactly which contract broke.
    # Uses grep -P (PCRE) because the grammar regexes use PCRE syntax
    # (\d, \S) — POSIX ERE (bash =~, grep -E) doesn't support those
    # character classes. This matches the runtime monitor contract:
    # grammar regexes are parsed by PCRE-aware consumers.
    command -v grep >/dev/null  # ensure grep available
    local failures=0
    while IFS=$'\t' read -r name regex example; do
        # Skip rows where the example column is genuinely a placeholder
        # (em-dash means "no example yet"). Those are doc-todo, not test
        # failures — flagged separately by an explicit no-em-dash test.
        local trimmed
        trimmed=$(echo "$example" | sed 's/^ *//; s/ *$//')
        [[ "$trimmed" == "—" ]] && continue
        if ! echo "$example" | grep -qP "$regex" 2>/dev/null; then
            echo "GRAMMAR DRIFT: shape='$name' example='$example' does not match regex='$regex'"
            failures=$((failures + 1))
        fi
    done <<< "$extracted"
    [ "$failures" -eq 0 ] || { echo "$failures grammar row(s) have regex/example mismatch"; false; }
}

@test "grammar regex column survives extraction without truncation (table-format invariant)" {
    # Sibling check to the conformance test: catch grammar rows whose
    # extracted regex has unbalanced parens (a sign that awk's pipe-split
    # truncated mid-regex due to a literal `|` in an alternation), or
    # whose row has extra columns shifting the regex out of position.
    # If this test fails, the doc's table format has drifted and the
    # conformance test silently dropped rows from coverage.
    #
    # Iter-6 BB F-003-codex fix: previously the test asserted skip-count <= 3
    # without naming the rows, so a NEW non-conforming row could replace a
    # known-skip row and the test would still pass. Now we enumerate the
    # known-skip rows by name and assert exact set equality. Any deviation
    # — new row, removal, rename — surfaces here for explicit reconciliation.
    #
    # Known skip set as of cycle-092 close (3 rows):
    #   harness-evidence-path     — regex contains literal `|` alternation
    #                               (`(Flight recorder|Evidence|PR)`) which
    #                               awk -F'|' splits incorrectly
    #   phase-heartbeat-emitted   — Sprint 4 row has extra column ("Sprint 4
    #                               `spiral-heartbeat.sh`") shifting regex out
    #                               of field 4
    #   phase-intent-change       — same Sprint 4 column-shift as above
    local known_skips=(harness-evidence-path phase-heartbeat-emitted phase-intent-change)
    local actual_skips
    actual_skips=$(awk -F'|' '
        $2 ~ /^[[:space:]]*`[a-z][a-z0-9-]+`[[:space:]]*$/ {
            if ($4 ~ /shape regex|^[[:space:]]*-+[[:space:]]*$/) next
            name = $2; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", name)
            regex = $4; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", regex)
            example = $6; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", example)
            regex_tmp = regex
            opens = gsub(/[(]/, "X", regex_tmp)
            regex_tmp = regex
            closes = gsub(/[)]/, "X", regex_tmp)
            if (!(regex ~ /^\^/) || opens != closes) {
                if (name) print name
            }
        }
    ' "$GRAMMAR" | sort -u)

    # Build expected sorted list
    local expected_skips
    expected_skips=$(printf '%s\n' "${known_skips[@]}" | sort -u)

    # Exact set equality. Asymmetric diff prints both directions for clarity.
    if [[ "$actual_skips" != "$expected_skips" ]]; then
        echo "Expected skipped rows:"
        printf '  %s\n' "${known_skips[@]}"
        echo "Actual skipped rows:"
        printf '  %s\n' $actual_skips
        echo "diff (expected vs actual):"
        diff <(echo "$expected_skips") <(echo "$actual_skips") || true
        false
    fi
    # the test fails loudly with a name-level diff. The maintainer must
    # then update the known_skips list AND ideally fix the underlying
    # table format so the row CAN be conformance-tested.
}
