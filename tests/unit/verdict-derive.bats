#!/usr/bin/env bats
# Unit tests for .claude/scripts/verdict-derive.sh (cycle-119 C7)
#
# Validates the LOA-VERDICT machine trailer (C6): presence/well-formedness,
# prose<->trailer agreement, the one-way critical+high>0 => CHANGES_REQUIRED
# severity rule, and the approved-review-has-no-findings-headings rule.

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/verdict-derive.sh"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/verdict-derive-test-$$"
    mkdir -p "${TEST_TMPDIR}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Usage / argument validation
# =============================================================================

@test "verdict-derive: missing --file is a usage error (exit 1)" {
    run "$SCRIPT" --gate review
    [ "$status" -eq 1 ]
}

@test "verdict-derive: missing --gate is a usage error (exit 1)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md"
    [ "$status" -eq 1 ]
}

@test "verdict-derive: invalid --gate value is a usage error (exit 1)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate bogus
    [ "$status" -eq 1 ]
}

@test "verdict-derive: nonexistent file is a usage error (exit 1)" {
    run "$SCRIPT" --file "${TEST_TMPDIR}/nope.md" --gate review
    [ "$status" -eq 1 ]
}

@test "verdict-derive: --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# Legacy files (no trailer)
# =============================================================================

@test "verdict-derive: legacy file with no trailer exits 2 by default" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

No issues found.
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 2 ]
}

@test "verdict-derive: legacy file --json reports trailer_found=false" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --json
    [ "$status" -eq 2 ]
    trailer_found=$(echo "$output" | jq -r '.trailer_found')
    [ "$trailer_found" = "false" ]
}

@test "verdict-derive: legacy file with --require-trailer exits 1" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --require-trailer
    [ "$status" -eq 1 ]
    [[ "$output" == *"require-trailer"* ]]
}

# =============================================================================
# Consistent trailers
# =============================================================================

@test "verdict-derive: approved review with matching trailer is consistent (exit 0)" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

No issues found.
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: --json exposes verdict/counts/consistent on success" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.verdict')" = "APPROVED" ]
    [ "$(echo "$output" | jq -r '.consistent')" = "true" ]
    [ "$(echo "$output" | jq -r '.counts.medium')" = "1" ]
}

@test "verdict-derive: changes-required review with non-'All good' first line is consistent" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
## Changes Required

- fix the thing
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: approved audit with exact ritual string is consistent" {
    cat > "${TEST_TMPDIR}/f.md" <<EOF
APPROVED - LET'S FUCKING GO

Sprint is solid.
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate audit
    [ "$status" -eq 0 ]
}

# =============================================================================
# Disagreement / violation cases
# =============================================================================

@test "verdict-derive: 'All good' first line but CHANGES_REQUIRED trailer is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"CHANGES_REQUIRED"* ]]
}

@test "verdict-derive: APPROVED trailer but missing 'All good' first line is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
Looks fine to me.
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"All good"* ]]
}

@test "verdict-derive: one-way rule — critical+high>0 forces CHANGES_REQUIRED" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":2,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"counts.high=2"* ]]
    [[ "$output" == *"CHANGES_REQUIRED"* ]]
}

@test "verdict-derive: one-way rule does NOT force APPROVED when counts are zero" {
    # CHANGES_REQUIRED with zero critical/high is still valid (reviewer judgment)
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
## Changes Required
- polish the docs
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: approved review with a Findings heading is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

## Findings
- minor nit
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"Findings"* ]]
}

@test "verdict-derive: approved audit missing the exact ritual string is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
Looks good, approved.
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"LET'S FUCKING GO"* ]]
}

@test "verdict-derive: non-EOF trailer (content after it) is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->

trailing content after trailer
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"last line"* ]]
}

@test "verdict-derive: multiple trailers is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:01Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"multiple LOA-VERDICT"* ]]
}

@test "verdict-derive: malformed JSON trailer is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {gate: review, verdict: APPROVED} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "verdict-derive: trailer gate mismatch vs requested --gate is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not match requested --gate"* ]]
}

@test "verdict-derive: a TAB in the marker is a malformed-marker violation, never a legacy file" {
    printf 'APPROVED - LET'"'"'S FUCKING GO\n<!-- LOA-VERDICT\t{"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$TEST_TMPDIR/f.md"
    run "$SCRIPT" --file "$TEST_TMPDIR/f.md" --gate audit --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed"* ]]
    [[ "$output" != *"NO_TRAILER"* ]]
}

@test "verdict-derive: counts.high of 2^64 (bash wrap) is a violation, not consistent" {
    printf 'All good\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":18446744073709551616,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$TEST_TMPDIR/f.md"
    run "$SCRIPT" --file "$TEST_TMPDIR/f.md" --gate review --json
    [ "$status" -ne 0 ]
    [[ "$output" == *'"consistent": false'* ]]
    [[ "$output" == *"non-numeric"* ]]
}

# --- cycle-126 Sprint 2 (PRD FR-2.3, SDD D-2.3): the rejected-payload contract ---------------

_vd_approved_review() {  # <file> [with_section]
    {
        echo "All good"; echo
        echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        if [[ "${2:-}" == "yes" ]]; then
            echo "## Rejected dissent payloads"; echo
            echo "- DISS-x (MEDIUM, x.sh:12) — triaged: not a defect (the guard exists two lines up)."; echo
        fi
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$1"
}
_vd_envelope() {  # <file> <rejected_summary json array>
    jq -n --argjson rs "$2" '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", rejected_summary: $rs}}' > "$1"
}

@test "verdict-derive: a non-empty rejected_summary in the sibling envelope without a '## Rejected dissent payloads' section is INCONSISTENT (exit 1) with the repair text" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s1"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    _vd_envelope "$d/adversarial-review.json" '[{"severity":"MEDIUM","title":"t","anchor":"x.sh:12","reason":"missing-severity","description_head":"Something fails."}]'
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"Rejected dissent payloads"* ]]
    [[ "$output" == *"rejected_summary"* ]]
}

@test "verdict-derive: the section present, or an empty summary, or no envelope at all → CONSISTENT (exit 0)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s2"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md" yes
    _vd_envelope "$d/adversarial-review.json" '[{"severity":"MEDIUM","title":"t","anchor":"x.sh:12","reason":"missing-severity","description_head":"Something fails."}]'
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
    _vd_approved_review "$d/engineer-feedback.md"
    _vd_envelope "$d/adversarial-review.json" '[]'
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
    rm "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: --envelope names the envelope explicitly; the audit gate reads adversarial-audit.json by default" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s3"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    _vd_envelope "$d/elsewhere.json" '[{"severity":"LOW","title":"t","anchor":null,"reason":"missing-category","description_head":"x"}]'
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review --envelope "$d/elsewhere.json"
    [ "$status" -eq 1 ]
    {
        echo "# audit"; echo; echo "APPROVED - LET'S FUCKING GO"; echo
        echo '<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/auditor-sprint-feedback.md"
    _vd_envelope "$d/adversarial-audit.json" '[{"severity":"LOW","title":"t","anchor":null,"reason":"missing-category","description_head":"x"}]'
    run "$SCRIPT" --file "$d/auditor-sprint-feedback.md" --gate audit
    [ "$status" -eq 1 ]
    run bash -c "'$SCRIPT' --file '$d/auditor-sprint-feedback.md' --gate audit --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations | length) >= 1' >/dev/null
}

@test "verdict-derive: the section must carry one triage line per rejected payload — an empty or short section is INCONSISTENT (sprint-248 review, chunk b BLOCKING)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s4"; mkdir -p "$d"
    two='[{"severity":"MEDIUM","title":"a","anchor":"x.sh:1","reason":"missing-severity","description_head":"A."},{"severity":"LOW","title":"b","anchor":"y.sh:2","reason":"missing-category","description_head":"B."}]'
    _vd_envelope "$d/adversarial-review.json" "$two"
    # heading only, no entries
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        echo "## Rejected dissent payloads"; echo; echo "## Observations"; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"0 top-level triage line(s)"* ]]
    # one line for two entries
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        echo "## Rejected dissent payloads"; echo; echo "- a (MEDIUM, x.sh:1) — missing-severity: not a defect, the guard is two lines up."; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 top-level triage line(s)"*"2 rejected payload(s)"* ]]
    # two lines for two entries → consistent
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        echo "## Rejected dissent payloads"; echo
        echo "- a (MEDIUM, x.sh:1) — missing-severity: not a defect, the guard is two lines up."
        echo "- b (LOW, y.sh:2) — missing-category: real; counted under Observations as LOW."; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: the contract fails closed — an explicit --envelope that is missing is a usage error (1); an envelope that is not JSON is a violation (1) (sprint-248 review, chunk b)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s5"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review --envelope "$d/nope.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"envelope file not found"* ]]
    printf 'not json' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"not parseable"* ]]
}

@test "verdict-derive: a usage error under --json is a result object (consistent false, usage_error true, exit 1), never an empty stdout (sprint-248 review r2, chunk b C-002)" {
    skip_if_no_jq
    run bash -c "\"$SCRIPT\" --file \"${TEST_TMPDIR}/nope.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and .usage_error == true and (.violations[0] | test("file not found")) and .exit_code == 1' >/dev/null
    run bash -c "\"$SCRIPT\" --file \"${TEST_TMPDIR}/nope.md\" --gate review 2>/dev/null"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run "$SCRIPT" --file "${TEST_TMPDIR}/nope.md" --gate review
    [[ "$output" == *"Error: file not found"* ]]
}

@test "verdict-derive: a rejected_summary that is not an array is its own violation, not a count (C-003)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s6"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", rejected_summary: "three"}}' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"of type string"* ]]
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", rejected_summary: 0}}' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"of type number"* ]]
}

@test "verdict-derive: only top-level bullets count as triage lines — one entry with two sub-bullets does not cover two payloads (C-003)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s7"; mkdir -p "$d"
    _vd_envelope "$d/adversarial-review.json" '[{"severity":"MEDIUM","title":"a","anchor":"x.sh:1","reason":"missing-severity","description_head":"A."},{"severity":"LOW","title":"b","anchor":"y.sh:2","reason":"missing-category","description_head":"B."}]'
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        echo "## Rejected dissent payloads"; echo
        echo "- a (MEDIUM, x.sh:1) — missing-severity: not a defect."
        echo "  - detail one"
        echo "  - detail two"; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"holds 1 top-level triage line(s)"* ]]
}

@test "verdict-derive: sidecar rows beside the envelope count when the envelope's summary is shorter — a chunked run overwrote it, or a companion's fold failed (C-004); --json names the envelope (C-005)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s8"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    _vd_envelope "$d/adversarial-review.json" '[]'
    printf '{"reject_reason":"missing-severity","payload":{"title":"a"}}\n{"reject_reason":"missing-category","payload":{"title":"b"}}\n' > "$d/adversarial-rejected-review-companion.jsonl"
    printf '{"reject_reason":"missing-severity","payload":{"title":"c"}}\n' > "$d/adversarial-rejected-review-a-chunk.jsonl"
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations[0] | test("3 schema-rejected payload") and test("sidecar rows")) and (.envelope | endswith("adversarial-review.json")) and .envelope_explicit == false' >/dev/null
    # an audit gate does not count the review's sidecars
    _vd_envelope "$d/adversarial-audit.json" '[]'
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate audit --json 2>/dev/null"
    echo "$output" | jq -e '.violations | map(select(test("sidecar"))) | length == 0' >/dev/null
    # three top-level bullets cover the three rows
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved. All acceptance criteria met."; echo
        echo "## Rejected dissent payloads"; echo
        echo "- a — missing-severity: not a defect."; echo "- b — missing-category: not a defect."; echo "- c — missing-severity: not a defect."; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$d/engineer-feedback.md"
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true and .envelope_explicit == false' >/dev/null
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json --envelope \"$d/adversarial-review.json\" 2>/dev/null"
    echo "$output" | jq -e '.envelope_explicit == true' >/dev/null
}

@test "verdict-derive: an envelope without rejected_summary (every pre-FR-2.2 envelope) or with null passes — no section required (sprint-248 review r2, chunk c C-002)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s9"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed"}}' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "api_failure", rejected_summary: null}}' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: sidecar rows with no envelope beside them are a violation, an unreadable sidecar is a violation, repaired rows never count (third run, chunk b C-002 / C-005 / C-001)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s10"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    printf '{"reject_reason":"missing-severity","payload":{"title":"a"}}\n{"reject_reason":"missing-severity","repair_attempted":true,"repair_succeeded":true,"payload":{"title":"b"}}\n' > "$d/adversarial-rejected-review.jsonl"
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations[0] | test("no dissent envelope") and test("hold 1 schema-rejected payload"))' >/dev/null
    chmod 000 "$d/adversarial-rejected-review.jsonl"
    if [[ -r "$d/adversarial-rejected-review.jsonl" ]]; then chmod 644 "$d/adversarial-rejected-review.jsonl"; skip "running as a user that can read mode-000 files"; fi
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    chmod 644 "$d/adversarial-rejected-review.jsonl"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations | map(select(test("not readable"))) | length == 1)' >/dev/null
}

@test "verdict-derive: --json anywhere in argv makes a usage error speak JSON (third run, chunk b C-004)" {
    skip_if_no_jq
    run bash -c "\"$SCRIPT\" --bogus --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.usage_error == true and (.violations[0] | test("Unknown option"))' >/dev/null
}

@test "verdict-derive: a value flag without its value is a usage error that still speaks JSON, never a failed shift (fourth run, chunk b DISS-001)" {
    skip_if_no_jq
    run bash -c "\"$SCRIPT\" --json --file \"${TEST_TMPDIR}/f.md\" --gate review --envelope 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.usage_error == true and (.violations[0] | test("--envelope requires a value"))' >/dev/null
    run "$SCRIPT" --file
    [ "$status" -eq 1 ]
    [[ "$output" == *"--file requires a value"* ]]
}

@test "verdict-derive: sidecar rows with no envelope are cleared by the same section and bullets (fourth run, chunk b C-001); a trailer-less file is held to the contract too (C-002)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s11"; mkdir -p "$d"
    printf '{"reject_reason":"missing-severity","payload":{"title":"a"}}\n{"reject_reason":"missing-category","payload":{"title":"b"}}\n' > "$d/adversarial-rejected-review.jsonl"
    # trailer-less, no section → the legacy pass is refused (exit 1, the violation on stderr / in JSON)
    printf 'All good\n\nSprint 9 has been reviewed and approved.\n' > "$d/engineer-feedback.md"
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and .trailer_found == false and (.violations[0] | test("no dissent envelope"))' >/dev/null
    # the section with two top-level bullets clears it — trailer-less → legacy exit 2; with a trailer → exit 0
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved."; echo
        echo "## Rejected dissent payloads"; echo; echo "- a — missing-severity: not a defect."; echo "- b — missing-category: not a defect."; echo
    } > "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 2 ]
    echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->' >> "$d/engineer-feedback.md"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: an envelope that names its sidecars (metadata.rejected_sidecars) scopes the count to them — a stale file beside it is not this run's (fourth run, chunk b C-003 / c C-002)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s12"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md" yes
    printf '{"reject_reason":"missing-severity","payload":{"title":"a"}}\n' > "$d/adversarial-rejected-review.jsonl"
    printf '{"reject_reason":"stale"}\n{"reject_reason":"stale"}\n{"reject_reason":"stale"}\n' > "$d/adversarial-rejected-review-companion.jsonl"
    jq -n --arg p "grimoires/loa/a2a/sprint-9/adversarial-rejected-review.jsonl" '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", rejected_summary: [], rejected_sidecars: [$p]}}' > "$d/adversarial-review.json"
    # the approved review carries one bullet under the section: one listed row → consistent; the three stale rows are ignored
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true' >/dev/null
    # without the field the glob counts every file (4 rows > 1 bullet)
    jq '.metadata |= del(.rejected_sidecars)' "$d/adversarial-review.json" > "$d/x.json" && mv "$d/x.json" "$d/adversarial-review.json"
    run bash -c "\"$SCRIPT\" --file \"$d/engineer-feedback.md\" --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.violations[0] | test("4 rejected payload")' >/dev/null
}

@test "verdict-derive: an empty rejected_sidecars list means the run produced no sidecar — a tagged file left by an earlier chunk run is not counted (sixth run, chunk b C-001)" {
    skip_if_no_jq
    d="${TEST_TMPDIR}/s13"; mkdir -p "$d"
    _vd_approved_review "$d/engineer-feedback.md"
    printf '{"reject_reason":"stale"}\n{"reject_reason":"stale"}\n' > "$d/adversarial-rejected-review-old-chunk.jsonl"
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "clean", rejected_summary: [], rejected_sidecars: []}}' > "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 0 ]
    # the field absent → the glob still counts the file
    jq '.metadata |= del(.rejected_sidecars)' "$d/adversarial-review.json" > "$d/x.json" && mv "$d/x.json" "$d/adversarial-review.json"
    run "$SCRIPT" --file "$d/engineer-feedback.md" --gate review
    [ "$status" -eq 1 ]
}
