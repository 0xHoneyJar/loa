#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/verdict-derive-failure-clause.bats — cycle-133 Sprint 274 Task 3.2 (sdd.md C-11; D-3.5 DEC-0857;
# PRD FR-11): the markdown finding grammar and the blocking rule of verdict-derive.sh.
#
#   - **SEV** (confidence: c[, speculative][, blocking]) `file:line[-end]` <dash> <title>. Failure: <scenario>.
#
# A defect-severity bullet (CRITICAL, HIGH, MEDIUM, LOW) without a valid Failure clause is a violation; a
# CRITICAL, HIGH or blocking bullet — valid or not — is counted in the blocking tally, so a file holding one can
# never be APPROVED: the gate reports a non-approving outcome with a non-zero exit, with or without a trailer.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/verdict-derive.sh"
    T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/vfc.XXXXXX")"
    GOOD="when the token cache is cold then the second request is accepted after expiry"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

trailer() {  # trailer <gate> <verdict> <c> <h> <m> <l> [extra-json-fields]
    printf '<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":%s,"high":%s,"medium":%s,"low":%s}%s,"sprint_id":"sprint-274","ts":"2026-10-24T00:00:00Z"} -->\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}"
}

@test "VFC-1 only invalid blockers: two HIGH bullets with one-word clauses ⇒ non-approving, exit 1" {
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — stale read. Failure: race.\n- **HIGH** (confidence: medium) `src/b.py:9` — leak. Failure: leaks.\n\n'
      trailer review CHANGES_REQUIRED 0 2 0 0; } > "$T/r.md"
    run --separate-stderr "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.consistent' <<<"$output")" = "false" ]
    [ "$(jq '[.violations[] | select(test("line [0-9]+: a HIGH bullet without a valid Failure clause"))] | length' <<<"$output")" -eq 2 ]
}

@test "VFC-2 valid lows mixed with one invalid blocker on an APPROVED file ⇒ non-approving, exit 1" {
    { printf 'All good\n\n## Notes\n\n- **HIGH** (confidence: high) `src/a.py:3` — token check bypass\n\n## Observations\n\n'
      printf -- '- **LOW** (confidence: low) `src/c.py:1` — naming. Failure: %s.\n- **LOW** (confidence: high) `src/d.py:2` — log level. Failure: %s.\n\n' "$GOOD" "$GOOD"
      trailer review APPROVED 0 0 0 2; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"INCONSISTENT"* ]]
    [[ "$output" == *"a HIGH bullet without a valid Failure clause"* ]]
    [[ "$output" == *"1 blocking finding bullet(s)"* ]]
}

@test "VFC-3 one malformed CRITICAL never yields APPROVE (trailer APPROVED, counts zero, first line All good)" {
    { printf 'All good\n\n## Summary\n\n- **CRITICAL** token check bypass in the login path\n\n'; trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run --separate-stderr "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -ne 0 ]
    [ "$(jq -r '.consistent' <<<"$output")" = "false" ]
    jq -e '.violations | any(test("CRITICAL bullet without a valid Failure clause")) and any(test("cannot be APPROVED"))' <<<"$output" >/dev/null
}

@test "VFC-4 a malformed CRITICAL in a file with no trailer is exit 1, never the legacy pass (exit 2)" {
    printf 'All good\n\n- **CRITICAL** (confidence: high) `src/a.py:2` — bypass. Failure: TODO.\n' > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"CRITICAL bullet without a valid Failure clause"* ]]
}

@test "VFC-5 a valid CRITICAL on an APPROVED audit is still tallied: non-approving, exit 1" {
    { printf "APPROVED - LET'S FUCKING GO\n\n## Notes\n\n- **CRITICAL** (confidence: high) \`src/a.py:2\` — bypass. Failure: %s.\n\n" "$GOOD"
      trailer audit APPROVED 0 0 0 0; } > "$T/a.md"
    run "$SCRIPT" --file "$T/a.md" --gate audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 blocking finding bullet(s)"* ]]
}

@test "VFC-6 a blocking MEDIUM under ## Observations is tallied: an APPROVED file is inconsistent" {
    { printf 'All good\n\n## Observations\n\n- **MEDIUM** (confidence: medium, blocking) `src/a.py:2` — retry. Failure: %s.\n\n' "$GOOD"
      trailer review APPROVED 0 0 1 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 blocking finding bullet(s)"* ]]
}

@test "VFC-7 the green control: valid bullets everywhere, CHANGES_REQUIRED with the HIGH counted ⇒ consistent" {
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — stale read. Failure: %s.\n\n## Observations\n\n' "$GOOD"
      printf -- '- **HIGH** (speculative, confidence: low) `src/q.py:80` — might race. Failure: %s.\n- **LOW** (confidence: low) `src/c.py:1` — naming. Failure: %s.\n- **PRAISE** clean seam\n\n' "$GOOD" "$GOOD"
      trailer review CHANGES_REQUIRED 0 1 0 1 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONSISTENT"* ]]
}

@test "VFC-8 every dash variant (— – - --) parses; a range anchor parses" {
    for d in '—' '–' '-' '--'; do
        { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3-7` %s stale read. Failure: %s.\n\n' "$d" "$GOOD"
          trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/r.md"
        run "$SCRIPT" --file "$T/r.md" --gate review
        [ "$status" -eq 0 ] || { echo "dash $d: $output"; return 1; }
    done
}

@test "VFC-9 last-token disambiguation: Failure: inside backticks is not the clause; the last one outside is" {
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — the `Failure:` marker parser. Failure: %s.\n\n' "$GOOD"
      trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/ok.md"
    run "$SCRIPT" --file "$T/ok.md" --gate review
    [ "$status" -eq 0 ]
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — x. Failure: %s. Failure: race.\n\n' "$GOOD"
      trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/bad.md"
    run "$SCRIPT" --file "$T/bad.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"(failure_scenario)"* ]]
    # a clause only inside backticks is no clause at all
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — see `Failure: %s`\n\n' "$GOOD"
      trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/tick.md"
    run "$SCRIPT" --file "$T/tick.md" --gate review
    [ "$status" -eq 1 ]
}

@test "VFC-10 bullets in a code fence, under ## Rejected dissent payloads, and exempt severities are not judged" {
    { printf 'All good\n\n```\n- **CRITICAL** quoted example\n```\n\n## Observations\n\n- **INFO** context only\n- **SPECULATION** (confidence: low) `a.py:1` — maybe. Failure: maybe.\n\n## Rejected dissent payloads\n\n- **HIGH** DISS-002 not a defect: the path is test-only\n\n'
      trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 0 ]
}

@test "VFC-11 a defect bullet without the confidence item, or with an unknown paren item, is a violation" {
    { printf '## Changes Required\n\n- **HIGH** `src/a.py:3` — stale read. Failure: %s.\n\n' "$GOOD"; trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"(grammar)"* ]]
    { printf '## Changes Required\n\n- **HIGH** (confidence: high, urgent) `src/a.py:3` — stale read. Failure: %s.\n\n' "$GOOD"; trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/r2.md"
    run "$SCRIPT" --file "$T/r2.md" --gate review
    [ "$status" -eq 1 ]
}

@test "VFC-13 an unclosed code fence before the findings is a violation (fail closed): the bullets behind it cannot hide from the tally" {
    # Sprint 274 review round 1: an APPROVED-shaped file whose fence never closes used to derive consistent while a
    # CRITICAL bullet sat behind the fence
    { printf 'All good\n\n## Summary\n\nClean.\n\n```\n- **CRITICAL** (confidence: high) `src/a.py:3` — hidden. Failure: when the fence never closes then the bullet is not judged.\n\n'
      trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run --separate-stderr "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -ne 0 ]
    [ "$(jq -r '.consistent' <<<"$output")" = "false" ]
    jq -e '.violations | any(test("line 7: a code fence opened here never closes"))' <<<"$output" >/dev/null
    # control: the same file with the fence closed is judged by the tally itself
    { printf 'All good\n\n## Summary\n\nClean.\n\n```\nx\n```\n- **CRITICAL** (confidence: high) `src/a.py:3` — visible. Failure: when the fence closes then the bullet is judged.\n\n'
      trailer review APPROVED 0 0 0 0; } > "$T/c.md"
    run --separate-stderr "$SCRIPT" --file "$T/c.md" --gate review --json
    [ "$status" -ne 0 ]
    jq -e '.violations | any(test("cannot be APPROVED")) and (any(test("never closes")) | not)' <<<"$output" >/dev/null
}

@test "VFC-12 the content rule reaches the bullet: a denylisted scenario (see above) is a violation naming the code" {
    { printf '## Changes Required\n\n- **HIGH** (confidence: high) `src/a.py:3` — stale read. Failure: see above.\n\n'; trailer review CHANGES_REQUIRED 0 1 0 0; } > "$T/r.md"
    run --separate-stderr "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 1 ]
    jq -e '.violations | any(test("line 3: a HIGH bullet without a valid Failure clause \\(failure_scenario\\)"))' <<<"$output" >/dev/null
}
