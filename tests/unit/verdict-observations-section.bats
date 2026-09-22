#!/usr/bin/env bats
# =============================================================================
# tests/unit/verdict-observations-section.bats — cycle-124 Sprint 3 Task 3.4
# (FR-9 / AC-9.1; SDD §3.6 "verdict-derive.sh change is additive and mechanical")
#
# Coverage-first review: every finding is reported; the mechanical filter is
# verdict-derive.sh, whose rule is severity-aware and one-way so the confidence
# dimension can never demote:
#   * critical/high go under `## Changes Required` and are counted whatever
#     their confidence — the only exception is a finding tagged `speculative`
#     with `confidence: low`, which may sit under `## Observations`; the trailer
#     then carries `excluded: N` (int ≥ 0, default 0) equal to that count
#   * `critical` is NEVER excludable (a critical under Observations or tagged
#     speculative is a violation)
#   * medium/low findings live under `## Observations` (never counted)
#   * `## Findings` / `## Issues` stay blocking headings on an APPROVED file
#   * `excluded > 0` on an APPROVED review is allowed but warns
#   * `--gate audit --review-file <review>`: the audit trailer's
#     `excluded_confirmed` must equal the review's `excluded`
# Finding entries are recognised mechanically: a list item / table row / bold
# line whose first line carries an uppercase severity word (CRITICAL, HIGH,
# MEDIUM, LOW) or `severity: <level>`; the markers are the words `speculative`
# and `confidence: low` on that line.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/verdict-derive.sh"
    T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/vo.XXXXXX")"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

trailer() {  # trailer <gate> <verdict> <c> <h> <m> <l> [extra-json-fields]
    printf '<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":%s,"high":%s,"medium":%s,"low":%s}%s,"sprint_id":"sprint-3","ts":"2026-09-20T00:00:00Z"} -->\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}"
}

@test "VO-1 All good + three medium/low items under ## Observations + APPROVED 0/0 ⇒ consistent" {
    { printf 'All good\n\n## Overall Assessment\n\nFine.\n\n## Observations\n\n- **MEDIUM** `src/a.py:10` — retry loop has no jitter (confidence: high)\n- **LOW** `src/b.py:4` — naming (confidence: medium)\n- **MEDIUM** `src/c.py:9` — log level (confidence: low)\n\n'; trailer review APPROVED 0 0 2 1; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.consistent')" = "true" ]
    [ "$(echo "$output" | jq -r '.excluded')" = "0" ]
}

@test "VO-2 the same items under ## Findings on an APPROVED file ⇒ violation" {
    { printf 'All good\n\n## Findings\n\n- **MEDIUM** `src/a.py:10` — retry loop has no jitter\n\n'; trailer review APPROVED 0 0 1 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"## Findings"* ]]
}

@test "VO-3 a CRITICAL with confidence: low and no speculative marker still forces CHANGES_REQUIRED" {
    { printf '## Changes Required\n\n- **CRITICAL** `src/auth.py:33` — token check bypass (confidence: low)\n\n'; trailer review CHANGES_REQUIRED 1 0 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    { printf 'All good\n\n## Changes Required\n\n- **CRITICAL** `src/auth.py:33` — token check bypass (confidence: low)\n\n'; trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
}

@test "VO-4 a speculative, confidence: low HIGH under ## Observations is excluded and the trailer says excluded: 1" {
    { printf 'All good\n\n## Observations\n\n- **HIGH** (speculative, confidence: low) `src/q.py:80` — might race under load\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    # the warning line precedes the JSON object in the merged output
    [ "$(echo "$output" | sed -n '/^{/,$p' | jq -r '.excluded')" = "1" ]
    [ "$(echo "$output" | sed -n '/^{/,$p' | jq -r '.consistent')" = "true" ]
    # the same file without the trailer field: the demotion is invisible ⇒ violation
    { printf 'All good\n\n## Observations\n\n- **HIGH** (speculative, confidence: low) `src/q.py:80` — might race under load\n\n'; trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"excluded"* ]]
}

@test "VO-5 a speculative CRITICAL under ## Observations is a violation (critical is never excludable)" {
    { printf 'All good\n\n## Observations\n\n- **CRITICAL** (speculative, confidence: low) `src/q.py:80` — key material in logs\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"critical"* ]]
}

@test "VO-6 a HIGH under ## Observations without BOTH markers is a violation (confidence never demotes)" {
    { printf 'All good\n\n## Observations\n\n- **HIGH** (confidence: low) `src/q.py:80` — might race\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    { printf 'All good\n\n## Observations\n\n- **HIGH** (speculative, confidence: medium) `src/q.py:80` — might race\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
}

@test "VO-7 APPROVED with excluded > 0 is consistent but warns" {
    { printf 'All good\n\n## Observations\n\n- **HIGH** (speculative, confidence: low) `src/q.py:80` — might race\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '/^{/,$p' | jq -r '.warnings | length')" -ge 1 ]
    [[ "$output" == *"WARN"* ]]
}

@test "VO-8 audit cross-check: excluded_confirmed must equal the review's excluded" {
    { printf 'All good\n\n## Observations\n\n- **HIGH** (speculative, confidence: low) `src/q.py:80` — might race\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":1'; } > "$T/r.md"
    { printf '# Audit\n\nAPPROVED - LET'"'"'S FUCKING GO\n\n'; trailer audit APPROVED 0 0 0 0 ',"excluded_confirmed":1'; } > "$T/a.md"
    run "$SCRIPT" --file "$T/a.md" --gate audit --review-file "$T/r.md" --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.excluded_confirmed')" = "1" ]
    { printf '# Audit\n\nAPPROVED - LET'"'"'S FUCKING GO\n\n'; trailer audit APPROVED 0 0 0 0; } > "$T/a.md"
    run "$SCRIPT" --file "$T/a.md" --gate audit --review-file "$T/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"excluded_confirmed"* ]]
    # --review-file only makes sense for the audit gate
    run "$SCRIPT" --file "$T/r.md" --gate review --review-file "$T/r.md"
    [ "$status" -eq 2 ]
}

@test "VO-9 excluded must be a non-negative integer of at most six digits" {
    { printf 'All good\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":-1'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    { printf 'All good\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":"1"'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
    { printf 'All good\n\n'; trailer review APPROVED 0 0 0 0 ',"excluded":18446744073709551616'; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review
    [ "$status" -eq 1 ]
}

@test "VO-10 a HIGH with confidence: medium under ## Changes Required is simply counted (no demotion path)" {
    { printf '## Changes Required\n\n- **HIGH** (confidence: medium) `src/q.py:80` — unbounded retry\n\n## Observations\n\n- **LOW** `src/z.py:1` — nit\n\n'; trailer review CHANGES_REQUIRED 0 1 0 1; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.excluded')" = "0" ]
}

@test "VO-11 legacy files without Observations, excluded or --review-file behave exactly as before" {
    { printf 'All good\n\nSprint reviewed.\n\n'; trailer review APPROVED 0 0 0 0; } > "$T/r.md"
    run "$SCRIPT" --file "$T/r.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.excluded')" = "0" ]
    [ "$(echo "$output" | jq -r '.warnings | length')" = "0" ]
    { printf 'APPROVED - LET'"'"'S FUCKING GO\n\n'; trailer audit APPROVED 0 0 1 0; } > "$T/a.md"
    run "$SCRIPT" --file "$T/a.md" --gate audit
    [ "$status" -eq 0 ]
}
