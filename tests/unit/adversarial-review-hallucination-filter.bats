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
    {
        echo 'log() { echo "[test] $*" >&2; }'
        cat ext.sh
    } > filter-fns.sh
    source filter-fns.sh
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
    # hallucination_filter metadata NOT added (short-circuit on dirty diff)
    [ "$(echo "$filtered" | jq -r '.metadata.hallucination_filter // empty')" = "" ]
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

@test "filter: missing diff file → input returned unchanged" {
    local findings_json='[{"description": "whatever", "severity": "HIGH", "category": "X"}]'
    local result
    result=$(_make_result "$findings_json")
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "nonexistent.patch")

    # Exact round-trip (input unchanged)
    [ "$(echo "$filtered" | jq -S .)" = "$(echo "$result" | jq -S .)" ]
}

@test "filter: empty findings → input returned unchanged" {
    echo 'clean diff' > diff.patch
    local result
    result=$(_make_result '[]')
    local filtered
    filtered=$(_apply_hallucination_filter "$result" "diff.patch")

    [ "$(echo "$filtered" | jq -S .)" = "$(echo "$result" | jq -S .)" ]
}
