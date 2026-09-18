#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-schema-enforced.bats
#
# cycle-124 Sprint 2 Task 2.4 (FR-7 / SDD §3): the dissent's two parse paths.
#   schema_enforced == true → strict parse only (jq_strict on raw content),
#     no fence strip / raw_decode rescue / normalization / repair;
#     invalid JSON or stop_reason=max_tokens ⇒ malformed_response
#     (parse_path=schema_enforced) so the chain walks.
#   otherwise → today's tolerant path byte-for-byte (parse_path=normalized),
#     repair loop always on.
# Plus: invoke_dissenter forwards the per-type wire schema; the caller line
# selects dissent-${type}.wire.json.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    CONF_ENABLED="true"; CONF_MODEL="gpt-5.3-codex"; CONF_TIMEOUT=60; CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"; CONF_SECONDARY_BUDGET=12000; CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200; CONF_SECRET_SCANNING="true"; CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
    SPRINT="sprint-fr7-$$"
    # repair must never run on the enforced branch — make it fail loudly
    _repair_finding_via_model() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
}

teardown() {
    local d="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}"
    if [[ -d "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
}

_env() {  # <content> [schema_enforced] [stop_reason]
    jq -n --arg c "$1" --argjson se "${2:-false}" --arg sr "${3:-}" \
        '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: $se}
         + (if $sr == "" then {} else {stop_reason: $sr} end)'
}

GOOD='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}]}'

@test "FR7-1: enforced + clean JSON → reviewed, parse_path=schema_enforced, schema_enforced=true, repaired_count=0" {
    result=$(process_findings "$(_env "$GOOD" true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.parse_path' <<<"$result")" = "schema_enforced" ]
    [ "$(jq -r '.metadata.schema_enforced' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.repaired_count' <<<"$result")" = "0" ]
}

@test "FR7-2: enforced + fenced content → malformed_response (no fence strip on the enforced branch)" {
    local fenced=$'```json\n'"$GOOD"$'\n```'
    result=$(process_findings "$(_env "$fenced" true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "malformed_response" ]
    [ "$(jq -r '.metadata.parse_path' <<<"$result")" = "schema_enforced" ]
    [ "$(jq -r '.metadata.schema_enforced' <<<"$result")" = "true" ]
    [[ "$(jq -r '.metadata.error' <<<"$result")" == *"not valid JSON"* ]]
}

@test "FR7-3: enforced + preamble prose → malformed_response (no raw_decode rescue on the enforced branch)" {
    local prose="Using the review skill, here is the JSON: $GOOD"
    result=$(process_findings "$(_env "$prose" true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "malformed_response" ]
}

@test "FR7-4: enforced + stop_reason=max_tokens → malformed_response naming the truncation, even when the JSON happens to parse" {
    result=$(process_findings "$(_env "$GOOD" true max_tokens)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "malformed_response" ]
    [[ "$(jq -r '.metadata.error' <<<"$result")" == *"max_tokens"* ]]
}

@test "FR7-5: unenforced + preamble prose → the normalize path still rescues it (parse_path=normalized)" {
    local prose="Using the review skill, here is the JSON: $GOOD"
    result=$(process_findings "$(_env "$prose" false)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.parse_path' <<<"$result")" = "normalized" ]
    [ "$(jq -r '.metadata.schema_enforced' <<<"$result")" = "false" ]
}

@test "FR7-6: unenforced + case-mismatched severity → normalization accepts it; enforced → rejected without repair" {
    local lower='{"findings":[{"id":"DISS-001","severity":" blocking ","category":"injection","description":"d","failure_mode":"fm"}]}'
    result=$(process_findings "$(_env "$lower" false)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    result=$(process_findings "$(_env "$lower" true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq -r '.metadata.rejected_count' <<<"$result")" = "1" ]
    local sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-review.jsonl"
    [ "$(jq -r '.parse_path' "$sidecar")" = "schema_enforced" ]
    [ "$(jq -r '.repair_attempted' "$sidecar")" = "false" ]
}

@test "FR7-7: enforced + zero findings → clean, still stamped with parse_path/schema_enforced" {
    result=$(process_findings "$(_env '{"findings":[]}' true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "clean" ]
    [ "$(jq -r '.metadata.parse_path' <<<"$result")" = "schema_enforced" ]
    [ "$(jq -r '.metadata.schema_enforced' <<<"$result")" = "true" ]
}

@test "FR7-8: invoke_dissenter forwards --json-schema <wire file> to model-adapter; absent when the file does not exist" {
    local fake_dir="$TEST_DIR/scripts"; mkdir -p "$fake_dir"
    cat > "$fake_dir/model-adapter.sh" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_DIR/ma-argv"
echo '{"content":"{\"findings\":[]}","tokens_input":1,"tokens_output":1,"cost_usd":0,"latency_ms":1,"schema_enforced":true}'
SHIM
    chmod +x "$fake_dir/model-adapter.sh"
    echo sys > "$TEST_DIR/sys.txt"; echo usr > "$TEST_DIR/usr.txt"
    local wire="$PROJECT_ROOT/.claude/schemas/wire/dissent-review.wire.json"
    SCRIPT_DIR="$fake_dir" invoke_dissenter "$TEST_DIR/sys.txt" "$TEST_DIR/usr.txt" "gpt-5.3-codex" 30 "" review "$wire" >/dev/null
    [ "$(awk -v f=--json-schema '$0==f{getline; print; exit}' "$TEST_DIR/ma-argv")" = "$wire" ]
    SCRIPT_DIR="$fake_dir" invoke_dissenter "$TEST_DIR/sys.txt" "$TEST_DIR/usr.txt" "gpt-5.3-codex" 30 "" review "$TEST_DIR/nope.json" >/dev/null
    ! grep -qx -- '--json-schema' "$TEST_DIR/ma-argv"
}

@test "FR7-9: the fallback-chain caller selects dissent-\${type}.wire.json (grep-lock)" {
    grep -q 'invoke_dissenter "\$_ADVERSARIAL_WORKDIR/system-prompt.txt" "\$_ADVERSARIAL_WORKDIR/user-prompt.txt" "\$try_model" "\$timeout" "\$vq_sidecar" "\$type" "\$SCRIPT_DIR/../schemas/wire/dissent-\${type}.wire.json"' "$ADVERSARIAL_REVIEW"
}

@test "FR7-10: the KF-004 corpus + the truncated payload — every fixture lands where _expect says on both parse paths; enforced-valid ones reject nothing" {
    local corpus="$PROJECT_ROOT/tests/fixtures/structured-outputs"
    # the unenforced path DOES try the repair round-trip; a quiet failing stub = "repair unavailable"
    _repair_finding_via_model() { return 1; }
    local n=0 f
    for f in "$corpus"/kf004/*.json "$corpus"/truncated.json; do
        n=$((n + 1))
        local typ raw_u raw_e result_u result_e
        typ=$(jq -r '._type // "review"' "$f")
        raw_u=$(jq -c 'del(._case, ._type, ._expect)' "$f")
        raw_e=$(jq -c 'del(._case, ._type, ._expect) + {schema_enforced: true}' "$f")
        result_u=$(process_findings "$raw_u" "$typ" "m" "$SPRINT" "0" "")
        result_e=$(process_findings "$raw_e" "$typ" "m" "$SPRINT" "0" "")
        [ "$(jq -r '.metadata.status' <<<"$result_u")" = "$(jq -r '._expect.unenforced' "$f")" ] \
            || { echo "$f unenforced: $(jq -c .metadata <<<"$result_u")" >&2; return 1; }
        [ "$(jq -r '.metadata.status' <<<"$result_e")" = "$(jq -r '._expect.enforced' "$f")" ] \
            || { echo "$f enforced: $(jq -c .metadata <<<"$result_e")" >&2; return 1; }
        [ "$(jq -r '.metadata.parse_path // "-"' <<<"$result_e")" = "schema_enforced" ]
        if [ "$(jq -r '._expect.enforced_rejected // empty' "$f")" != "" ]; then
            [ "$(jq -r '.metadata.rejected_count // 0' <<<"$result_e")" = "$(jq -r '._expect.enforced_rejected' "$f")" ] || { echo "$f enforced rejected_count" >&2; return 1; }
            local sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-${typ}.jsonl"
            [ ! -s "$sidecar" ] || { echo "$f: enforced-valid payload wrote a sidecar row" >&2; return 1; }
        fi
        if [ "$(jq -r '._expect.unenforced_findings // empty' "$f")" != "" ]; then
            [ "$(jq '.findings | length' <<<"$result_u")" = "$(jq -r '._expect.unenforced_findings' "$f")" ] || { echo "$f unenforced findings" >&2; return 1; }
        fi
        if [ "$(jq -r '._expect.enforced_findings // empty' "$f")" != "" ]; then
            [ "$(jq '.findings | length' <<<"$result_e")" = "$(jq -r '._expect.enforced_findings' "$f")" ] || { echo "$f enforced findings" >&2; return 1; }
        fi
    done
    [ "$n" = "11" ]
}
