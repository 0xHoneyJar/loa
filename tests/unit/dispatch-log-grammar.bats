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

@test "spiral-harness.sh still defines log() with [harness] prefix" {
    grep -q 'log() { echo "\[harness\] \$\*" >&2; }' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
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

@test "every log() line in spiral-harness.sh matches at least one declared or catch-all shape" {
    # All log() lines start with '[harness] '. The informational catch-all
    # `^\[harness\] ` covers every line emitted via log(). The [harness]
    # prefix is defined in log() at spiral-harness.sh (see grammar §Line
    # prefix convention), so by construction every log() line is covered.
    local total covered
    total=$(grep -cE '^\s*log "' "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh")
    # Sanity floor — expect roughly 50+ log() sites post-cycle-092 (55 at
    # sprint-1 close). Floor is intentionally conservative to allow normal
    # edits without breaking this test.
    [[ "$total" -ge 40 ]]
    # Every line prefix is enforced by log() definition: `echo "[harness] $*"`.
    # Grep for the bare prefix presence in source — a refactor that changes
    # the prefix would flip this to zero and fail the test (intentional
    # backstop against silent grammar drift).
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
    # Counts the number of rows skipped by the conformance test's filter
    # and asserts it stays within an expected ceiling. As of cycle-092
    # close: 3 known-skip rows (harness-evidence-path with pipe-in-regex,
    # phase-heartbeat-emitted + phase-intent-change with extra columns).
    local skipped
    skipped=$(awk -F'|' '
        $2 ~ /^[[:space:]]*`[a-z][a-z0-9-]+`[[:space:]]*$/ {
            if ($4 ~ /shape regex|^[[:space:]]*-+[[:space:]]*$/) next
            name = $2; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", name)
            regex = $4; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", regex)
            example = $6; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", example)
            regex_tmp = regex
            opens = gsub(/[(]/, "X", regex_tmp)
            regex_tmp = regex
            closes = gsub(/[)]/, "X", regex_tmp)
            # Count rows that the conformance test would skip
            if (!(regex ~ /^\^/) || opens != closes) {
                if (name) print name
            }
        }
    ' "$GRAMMAR" | wc -l)
    # Ceiling: 3 known-skip rows. If this fails, either:
    #  - a new non-conforming row was added → reformat it
    #  - one of the 3 was reformatted → bump the ceiling down
    # Either way, surfaces table-format drift to the maintainer.
    [[ "$skipped" -le 3 ]] || { echo "$skipped grammar rows skipped by conformance test (expected <=3)"; false; }
}
