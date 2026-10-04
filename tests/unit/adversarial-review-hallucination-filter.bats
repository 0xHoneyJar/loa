#!/usr/bin/env bats
# =============================================================================
# adversarial-review-hallucination-filter.bats — cycle-093 T1.3 / #618
# =============================================================================
# Verifies _apply_hallucination_filter + _normalize_doc_content_tokens in
# adversarial-review.sh correctly downgrade findings that claim a
# `{{DOCUMENT_CONTENT}}`-family token that is absent from the source diff.
#
# Bidirectional match per Flatline IMP-003:
#   diff_has=no  + finding_has=yes → DOWNGRADE
#   diff_has=no  + finding_has=no  → no-op
#   diff_has=yes + finding_has=yes → no-op (legitimate)
#   diff_has=yes + finding_has=no  → no-op
#
# Normalization per SDD §3.7:
#   canonical, escaped, spaced, case variants, bare DOCUMENT_CONTENT
# =============================================================================

setup() {
    export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR:?BATS_TEST_TMPDIR not set — needs bats-core >= 1.4}"   # the CLI lock is this test's own, never the per-user one a live dissent holds (run 23)
    export TEST_WORKDIR
    TEST_WORKDIR=$(mktemp -d)
    cd "$TEST_WORKDIR"

    # Source only the filter + normalizer functions from adversarial-review.sh.
    # Use a small extraction pattern: read from the anchor comment to the end
    # of _apply_hallucination_filter. The file uses `set -euo pipefail`, so we
    # cannot source the whole thing (it parses CLI args at load).
    local repo_root
    repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    local script_path="$repo_root/.claude/scripts/adversarial-review.sh"
    # Extract the filter block between the cycle-093 anchor and the next major
    # section banner (Finding ID Computation).
    sed -n '/# Dissenter Hallucination Filter/,/# Finding ID Computation/p' "$script_path" > ext.sh
    # Provide the log() helper the filter depends on
    # the extraction is whole — the column-0 `}` that ends the range is the function's own, the script line after it no
    # indented body (thirty-third run, e3 DISS-C-004) — checked BEFORE the source, so a cut inside the body is named here and
    # never surfaces as source's "unexpected end of file" (thirty-sixth run, e3 DISS-C-003)
    _jq_pair_extracted_whole "$script_path"
    {
        echo 'log() { echo "[test] $*" >&2; }'
        # sprint-bug-208 (#1025): the filter now routes verdict-bearing jq
        # through jq_strict from compat-lib.sh; provide it to the extracted
        # function set (same pre-source pattern as adversarial-review.bats).
        echo "source \"$repo_root/.claude/scripts/compat-lib.sh\""
        cat ext.sh
        # (the filter's appends go through _adv_jq_pair — payloads on stdin, never argv: twenty-ninth run, a1 DISS-C-003)
        sed -n '/^_adv_jq_pair() {/,/^}/p' "$script_path"
    } > filter-fns.sh
    source filter-fns.sh
    [ "$(type -t _adv_jq_pair)" = function ] || { echo "setup: _adv_jq_pair was not extracted" >&2; return 1; }
}

_jq_pair_extracted_whole() {  # <script> — the column-0 `}` that ends the extraction is the function's own: the next line is no
    # indented body; a blank or whitespace-only one is blank (thirty-fourth run, e3 DISS-C-001)
    local _end _next _x
    _end="$(awk '/^_adv_jq_pair\(\) \{/{f=1} f && /^}/{print NR; exit}' "$1")"
    # (a function that is not there is named so — thirty-eighth run, e3 DISS-C-001)
    [[ -n "$_end" ]] || { echo "setup: _adv_jq_pair() not found in $1" >&2; return 1; }
    _next="$(sed -n "$((_end + 1))p" "$1")"
    [[ -z "${_next//[[:space:]]/}" || "$_next" != [[:space:]]* ]] \
        || { echo "setup: _adv_jq_pair's extraction ended inside its body (line $_end)" >&2; return 1; }
    # (the extracted text itself parses whole: a column-0 brace inside a quoted program or a heredoc, followed by a
    # blank line, passes the next-line read but leaves an open quote or heredoc — thirty-eighth run, e3 DISS-C-002)
    _x="$(sed -n '/^_adv_jq_pair() {/,/^}/p' "$1" | bash -n 2>&1)" \
        || { echo "setup: _adv_jq_pair's extraction does not parse whole: ${_x:-bash -n failed}" >&2; return 1; }
}

teardown() {
    rm -rf "$TEST_WORKDIR"
}

_make_result() {
    local findings_json="$1"
    jq -n --argjson f "$findings_json" \
        '{findings: $f, metadata: {type: "review", model: "gpt-test", sprint_id: "s1", timestamp: "2026-04-24T00:00:00Z", status: "reviewed", degraded: false}}'
}

@test "normalize: canonical form unchanged" {
    local out
    out=$(echo "{{DOCUMENT_CONTENT}}" | _normalize_doc_content_tokens)
    [ "$out" = "{{DOCUMENT_CONTENT}}" ]
}

@test "normalize: escaped braces → canonical" {
    local out
    out=$(echo '\{\{DOCUMENT_CONTENT\}\}' | _normalize_doc_content_tokens)
    [ "$out" = "{{DOCUMENT_CONTENT}}" ]
}

@test "normalize: spaced → canonical" {
    local out
    out=$(echo "{{ DOCUMENT_CONTENT }}" | _normalize_doc_content_tokens)
    [ "$out" = "{{DOCUMENT_CONTENT}}" ]
}

@test "normalize: lowercase inside braces → canonical" {
    local out
    out=$(echo "{{document_content}}" | _normalize_doc_content_tokens)
    [ "$out" = "{{DOCUMENT_CONTENT}}" ]
}

@test "normalize: title case inside braces → canonical" {
    local out
    out=$(echo "{{Document_Content}}" | _normalize_doc_content_tokens)
    [ "$out" = "{{DOCUMENT_CONTENT}}" ]
}

@test "detect: bare DOCUMENT_CONTENT token matches" {
    run _text_contains_doc_content_token "The DOCUMENT_CONTENT literal shouldn't be there"
    [ "$status" -eq 0 ]
}

@test "detect: absent token → no match" {
    run _text_contains_doc_content_token "if [[ -n \"\$fval\" && -n \"\$ALLOW_LEGACY\" ]]; then"
    [ "$status" -eq 1 ]
}

@test "filter: clean diff + hallucinated finding → downgraded (Q1: no/yes)" {
    echo 'if [[ -n "$fval" && -n "$ALLOW_LEGACY" ]]; then' > diff.patch
    local findings_json='[{"description": "The conditional `{{DOCUMENT_CONTENT}}{{DOCUMENT_CONTENT}}` is invalid bash", "severity": "BLOCKING", "category": "CORRECTNESS"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    # Severity downgraded
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "ADVISORY" ]
    # Category retagged
    [ "$(echo "$filtered" | jq -r '.findings[0].category')" = "MODEL_ARTEFACT_SUSPECTED" ]
    # Description prefixed with downgrade marker
    [ "$(echo "$filtered" | jq -r '.findings[0].description' | grep -c '\[downgraded:')" -eq 1 ]
    # Metadata reflects filter action
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "1" ]
}

@test "filter: clean diff + clean finding → untouched (Q2: no/no)" {
    echo 'if [[ -n "$fval" && -n "$ALLOW_LEGACY" ]]; then' > diff.patch
    local findings_json='[{"description": "Missing error handling on read failure", "severity": "HIGH", "category": "ERROR_HANDLING"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    # Severity preserved
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "HIGH" ]
    # Metadata: 0 downgraded
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "0" ]
}

@test "filter: dirty diff + finding-with-token → untouched (Q3: yes/yes; legitimate template file)" {
    # Diff legitimately contains the token — e.g., documentation or template
    echo 'Template: use {{DOCUMENT_CONTENT}} as placeholder for the body' > diff.patch
    local findings_json='[{"description": "The {{DOCUMENT_CONTENT}} placeholder is referenced but never substituted", "severity": "BLOCKING", "category": "CORRECTNESS"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    # No downgrade — finding is legitimate
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "BLOCKING" ]
    # G-6 (cycle-094 sprint-2): metadata IS now always present, with a reason
    # field indicating why the filter no-op'd. Distinguishes "filter ran and
    # decided not to downgrade" from "filter never ran".
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.applied')" = "false" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "0" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.reason')" = "diff_contains_token" ]
}

@test "filter: dirty diff + clean finding → untouched (Q4: yes/no)" {
    echo 'Template: {{DOCUMENT_CONTENT}} here' > diff.patch
    local findings_json='[{"description": "Missing input validation", "severity": "HIGH", "category": "SECURITY"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "HIGH" ]
}

@test "filter: mixed findings → only hallucinated downgraded" {
    echo 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"' > diff.patch
    local findings_json='[
      {"description": "Command substitution `$(cd \"$(dirname \"$0\")/..\" {{DOCUMENT_CONTENT}}{{DOCUMENT_CONTENT}} pwd)` invalid", "severity": "BLOCKING", "category": "CORRECTNESS"},
      {"description": "REPO_ROOT should be readonly", "severity": "LOW", "category": "QUALITY"}
    ]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    # First: downgraded
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "ADVISORY" ]
    [ "$(echo "$filtered" | jq -r '.findings[0].category')" = "MODEL_ARTEFACT_SUSPECTED" ]
    # Second: preserved
    [ "$(echo "$filtered" | jq -r '.findings[1].severity')" = "LOW" ]
    [ "$(echo "$filtered" | jq -r '.findings[1].category')" = "QUALITY" ]
    # Metadata: exactly 1 downgrade
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "1" ]
}

@test "filter: variant forms detected and downgraded" {
    echo 'clean shell code: a && b' > diff.patch
    # Each variant should trigger downgrade
    for variant in \
        "Issue: {{DOCUMENT_CONTENT}}" \
        "Issue: \\{\\{DOCUMENT_CONTENT\\}\\}" \
        "Issue: {{ DOCUMENT_CONTENT }}" \
        "Issue: {{document_content}}" \
        "Issue: {{Document_Content}}" \
        "Issue: bare DOCUMENT_CONTENT token in prose"; do
        local findings_json
        findings_json=$(jq -n --arg desc "$variant" '[{description: $desc, severity: "BLOCKING", category: "X"}]')
        local result
        result=$(_make_result "$findings_json")
        local filtered
        filtered=$(_apply_hallucination_filter "$result" "diff.patch")
        local sev
        sev=$(echo "$filtered" | jq -r '.findings[0].severity')
        if [[ "$sev" != "ADVISORY" ]]; then
            echo "variant '$variant' was not downgraded (got severity=$sev)"
            return 1
        fi
    done
}

@test "filter: missing diff file → input findings unchanged + metadata reason=no_diff_file" {
    local findings_json='[{"description": "whatever", "severity": "HIGH", "category": "X"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "nonexistent.patch")

    # Findings unchanged (no downgrade fired)
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "HIGH" ]
    # G-6: metadata IS present with applied=false + reason
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.applied')" = "false" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "0" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.reason')" = "no_diff_file" ]
}

@test "filter: empty findings → input findings unchanged + metadata reason=no_findings" {
    echo 'clean diff' > diff.patch
    local result
    result=$(_make_result '[]')
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    # Findings still empty
    [ "$(echo "$filtered" | jq '.findings | length')" = "0" ]
    # G-6: metadata IS present with applied=false + reason
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.applied')" = "false" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "0" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.reason')" = "no_findings" ]
}

# -----------------------------------------------------------------------------
# G-6 (cycle-094 sprint-2): hallucination_filter metadata is ALWAYS present
# on the result, distinguishing "filter ran and found nothing" from "filter
# never ran". Sprint-1 of cycle-094 left three early-return paths writing no
# metadata; sprint-2 closes that gap so downstream consumers (review pipelines,
# observability dashboards) can rely on the key being present.
#
# This block enumerates every code path through _apply_hallucination_filter
# and asserts the metadata shape:
#   applied: bool         — true iff filter traversed findings
#   downgraded: int       — count of downgraded findings (0 if !applied)
#   reason: string?       — present when applied=false; one of
#                            no_diff_file | no_findings | diff_contains_token
# -----------------------------------------------------------------------------
@test "G-6: metadata.hallucination_filter is ALWAYS present after _apply_hallucination_filter" {
    # Iterate every code path: missing diff, empty findings, dirty diff,
    # clean diff with downgrade, clean diff without downgrade.
    echo 'clean diff' > clean.patch
    # "Dirty" here means: the diff itself contains the {{DOCUMENT_CONTENT}}
    # canary token (e.g., a doc/template file that legitimately discusses
    # the placeholder). Token-presence-in-finding can't distinguish a
    # hallucinated finding from a legitimate citation in this case, so the
    # filter short-circuits with reason=diff_contains_token. (Iter-1 BB F6.)
    echo '{{DOCUMENT_CONTENT}} legitimate' > dirty.patch
    # Iter-1 BB F5 (LOW): the flat 4-tuple array layout is fragile to row
    # misalignment. Add a modulo-4 guard so a missing/extra column trips a
    # clear failure instead of silently shifting subsequent cases by one
    # position (which would produce nonsensical-but-passing tests).
    local cases=(
        # diff_path           findings_json                                                                                              expected_applied  expected_reason
        'no_such.patch'       '[{"description":"x","severity":"HIGH","category":"X"}]'                                                   'false'           'no_diff_file'
        'clean.patch'         '[]'                                                                                                       'false'           'no_findings'
        'dirty.patch'         '[{"description":"flag","severity":"HIGH","category":"X"}]'                                                'false'           'diff_contains_token'
        'clean.patch'         '[{"description":"flag {{DOCUMENT_CONTENT}}","severity":"BLOCKING","category":"X"}]'                       'true'            ''
        'clean.patch'         '[{"description":"normal finding","severity":"HIGH","category":"X"}]'                                      'true'            ''
    )
    (( ${#cases[@]} % 4 == 0 )) || {
        echo "cases array misaligned: length=${#cases[@]} not divisible by 4 (4 fields per case)" >&2
        return 1
    }
    local i=0
    while [[ $i -lt ${#cases[@]} ]]; do
        local diff_path="${cases[$i]}"
        local findings="${cases[$((i+1))]}"
        local expected_applied="${cases[$((i+2))]}"
        local expected_reason="${cases[$((i+3))]}"
        local result filtered
        result=$(_make_result "$findings")
        filtered=$(_apply_hallucination_filter "$result" "$diff_path")

        # Metadata key exists
        [ "$(echo "$filtered" | jq 'has("metadata") and (.metadata | has("hallucination_filter"))')" = "true" ]
        # applied field correct
        [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.applied')" = "$expected_applied" ]
        # downgraded is always an integer
        [ "$(echo "$filtered" | jq '.metadata.hallucination_filter.downgraded | type')" = '"number"' ]
        # reason present iff !applied
        if [[ "$expected_applied" = "false" ]]; then
            [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.reason')" = "$expected_reason" ]
        fi
        i=$((i+4))
    done
}

@test "G-6: planted {{DOCUMENT_CONTENT}} finding on clean diff → metadata.hallucination_filter.applied == true" {
    # The G-6 acceptance criterion verbatim: "Regression test asserts presence
    # on a known-hallucinated diff". Synthetic clean diff + planted finding
    # with the {{DOCUMENT_CONTENT}} token → filter must fire AND metadata.
    echo 'if [[ -n "$x" ]]; then echo $x; fi' > diff.patch
    local findings_json='[{"description":"The {{DOCUMENT_CONTENT}}{{DOCUMENT_CONTENT}} construct is bogus","severity":"BLOCKING","category":"CORRECTNESS"}]'
    local result filtered
    result=$(_make_result "$findings_json")
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.applied')" = "true" ]
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter.downgraded')" = "1" ]
    # Finding actually downgraded
    [ "$(echo "$filtered" | jq -r '.findings[0].severity')" = "ADVISORY" ]
    [ "$(echo "$filtered" | jq -r '.findings[0].category')" = "MODEL_ARTEFACT_SUSPECTED" ]
}

@test "the _adv_jq_pair extraction check reads a whitespace-only line after the closing brace as blank, and still refuses an indented body (thirty-fourth run, e3 DISS-C-001)" {
    local fx="$BATS_TEST_TMPDIR/jqpair.sh"
    printf '_adv_jq_pair() {\n  :\n}\n   \t\nnext\n' > "$fx"
    _jq_pair_extracted_whole "$fx" 2>/dev/null || { echo "a whitespace-only line was read as an indented body"; return 1; }
    printf '_adv_jq_pair() {\n  :\n}\n  body\n}\n' > "$fx"
    if _jq_pair_extracted_whole "$fx" 2>/dev/null; then echo "an extraction that ended inside the body passed"; return 1; fi
}

@test "the _adv_jq_pair extraction check names a missing function as missing, and refuses a cut that a blank line hides — a column-0 brace inside a quoted program or a heredoc (thirty-eighth run, e3 DISS-C-001 / DISS-C-002)" {
    local fx="$BATS_TEST_TMPDIR/jqpair38.sh" err
    printf '_adv_jq_pair_renamed() {\n  :\n}\n' > "$fx"
    err=$(_jq_pair_extracted_whole "$fx" 2>&1) && { echo "a missing function passed"; return 1; }
    [[ "$err" == *"_adv_jq_pair() not found in $fx"* ]] || { echo "the missing function was misnamed: $err"; return 1; }
    printf '%s\n' '_adv_jq_pair() {' "  jq -n '{" '}' '' "  '" '}' 'next' > "$fx"
    err=$(_jq_pair_extracted_whole "$fx" 2>&1) && { echo "a cut inside a quoted program passed"; return 1; }
    [[ "$err" == *"does not parse whole"* ]] || { echo "$err"; return 1; }
    printf '%s\n' '_adv_jq_pair() {' '  cat <<EOF' '}' '' 'EOF' '}' 'next' > "$fx"
    err=$(_jq_pair_extracted_whole "$fx" 2>&1) && { echo "a cut inside a heredoc passed"; return 1; }
    [[ "$err" == *"does not parse whole"* ]] || { echo "$err"; return 1; }
    printf '%s\n' '_adv_jq_pair() {' "  jq -n '{a: 1}'" '}' '' 'next' > "$fx"
    _jq_pair_extracted_whole "$fx" || { echo "a whole extraction was refused"; return 1; }
}

@test "setup checks the _adv_jq_pair extraction before it sources it — a cut inside the body is named, never an opaque 'unexpected end of file' from source (thirty-sixth run, e3 DISS-C-003)" {
    local f="$BATS_TEST_FILENAME" chk src
    chk="$(grep -n '^    _jq_pair_extracted_whole "$script_path"$' "$f" | head -1 | cut -d: -f1)"
    src="$(grep -n '^    source filter-fns.sh$' "$f" | head -1 | cut -d: -f1)"
    [[ -n "$chk" && -n "$src" ]] || { echo "setup's check ($chk) or source ($src) not found"; return 1; }
    (( chk < src )) || { echo "the extraction check (line $chk) runs after the source (line $src)"; return 1; }
}
