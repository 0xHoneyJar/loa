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
    SPRINT="sprint-fr7-$$"   # first: teardown runs after a failed setup (twenty-eighth run, c2e DISS-C-001)
    FR7_OWN_DIRS=()          # the suffixed a2a directories a test makes, for teardown (thirty-first run, c2e DISS-C-001)
    : "${BATS_TEST_TMPDIR:?BATS_TEST_TMPDIR not set — needs bats-core >= 1.4}"   # one per-test base bats removes; no mktemp fallback a teardown never sweeps (thirty-first run, c2e DISS-C-002)
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"   # the CLI lock is this test's own, never the per-user one a live dissent holds (run 23)
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="$BATS_TEST_TMPDIR"
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
    # repair must never run on the enforced branch — the stub leaves a canary
    # file that FR7-6 asserts absent (an echo to stderr cannot fail a test)
    REPAIR_CANARY="$TEST_DIR/repair-called-$$"
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
}

teardown() {
    local d
    # (twenty-eighth run, c2e DISS-C-001: never without this suite's own sprint id — an empty SPRINT made the first path the a2a
    # root itself, gitignored and unrecoverable; and every path is checked to be one of this suite's own)
    [[ -n "${SPRINT:-}" && "$SPRINT" == sprint-fr7-* && -n "${PROJECT_ROOT:-}" ]] || return 0
    # this test's directory only — never a sibling it did not make (twenty-ninth run, c2a; as c1a DISS-001)
    d="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}"
    if [[ -d "$d" && ! -L "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi   # (never a link: the sweep's rule — twenty-seventh run, c2a DISS-C-002)
    # …and each suffixed directory the test registered: a name of this id, one path component, a real directory (thirty-first run,
    # c2e DISS-C-001)
    local n
    for n in "${FR7_OWN_DIRS[@]}"; do
        [[ "$n" == "$SPRINT"-* && "$n" != */* && "$n" != *..* ]] || continue
        d="$PROJECT_ROOT/grimoires/loa/a2a/$n"
        if [[ -d "$d" && ! -L "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
    return 0
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
    [ ! -e "$REPAIR_CANARY" ]
}

@test "late-S2 LOW: an enforced content that is a two-object stream is malformed_response, never clean-zero" {
    local stream='{"findings":[]}{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}]}'
    result=$(process_findings "$(_env "$stream" true)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "malformed_response" ]
    [ "$(jq -r '.metadata.parse_path' <<<"$result")" = "schema_enforced" ]
}

@test "late-S2 MEDIUM: the unenforced repair loop stops after ADV_REPAIR_MAX_PER_RUN round-trips and reports the remainder" {
    local i items=""
    for i in 1 2 3 4 5 6 7; do
        items+="{\"id\":\"DISS-00$i\",\"severity\":\"bogus\",\"category\":\"injection\",\"description\":\"d\",\"failure_mode\":\"fm\"},"
    done
    local content="{\"findings\":[${items%,}]}"
    result=$(process_findings "$(_env "$content" false)" "review" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.rejected_count' <<<"$result")" = "7" ]
    [ "$(jq -r '.metadata.repair_budget_exhausted' <<<"$result")" = "2" ]
    local sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-review.jsonl"
    [ "$(jq -s '[.[] | select(.repair_attempted == true)] | length' "$sidecar")" = "5" ]
    [ "$(jq -s '[.[] | select(.repair_attempted == false)] | length' "$sidecar")" = "2" ]
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
    # cycle-126 sprint-248: the call goes through _adv_invoke_hop (per-binary lock for *-headless hops), same arguments
    grep -q '_adv_invoke_hop "\$try_model" "\$_ADVERSARIAL_WORKDIR/system-prompt.txt" "\$_ADVERSARIAL_WORKDIR/user-prompt.txt" "\$try_model" "\$timeout" "\$vq_sidecar" "\$type" "\$SCRIPT_DIR/../schemas/wire/dissent-\${type}.wire.json"' "$ADVERSARIAL_REVIEW"
    grep -q '_adv_with_cli_lock "\$model" invoke_dissenter "\$@"' "$ADVERSARIAL_REVIEW"   # …and _adv_invoke_hop hands them to invoke_dissenter unchanged (under the CLI lock)
}

@test "FR7-10: the KF-004 corpus + the truncated payload — every fixture lands where _expect says on both parse paths; enforced-valid ones reject nothing" {
    local corpus="$PROJECT_ROOT/tests/fixtures/structured-outputs"
    # the unenforced path DOES try the repair round-trip; a quiet failing stub = "repair unavailable"
    _repair_finding_via_model() { return 1; }
    local n=0 f
    for f in "$corpus"/kf004/*.json "$corpus"/truncated.json; do
        n=$((n + 1))
        local typ raw_u raw_e result_u result_e fsprint
        # one sprint dir (⇒ one sidecar) per fixture and per path, so the
        # "no sidecar row" assertion never depends on loop order or on the
        # per-invocation truncation (round-1 dissent DISS-001)
        fsprint="${SPRINT}-$(basename "$f" .json)"
        typ=$(jq -r '._type // "review"' "$f")
        raw_u=$(jq -c 'del(._case, ._type, ._expect)' "$f")
        raw_e=$(jq -c 'del(._case, ._type, ._expect) + {schema_enforced: true}' "$f")
        FR7_OWN_DIRS+=("${fsprint}-u" "${fsprint}-e")   # teardown removes exactly these (thirty-first run, c2e DISS-C-001)
        result_u=$(process_findings "$raw_u" "$typ" "m" "${fsprint}-u" "0" "")
        result_e=$(process_findings "$raw_e" "$typ" "m" "${fsprint}-e" "0" "")
        [ "$(jq -r '.metadata.status' <<<"$result_u")" = "$(jq -r '._expect.unenforced' "$f")" ] \
            || { echo "$f unenforced: $(jq -c .metadata <<<"$result_u")" >&2; return 1; }
        [ "$(jq -r '.metadata.status' <<<"$result_e")" = "$(jq -r '._expect.enforced' "$f")" ] \
            || { echo "$f enforced: $(jq -c .metadata <<<"$result_e")" >&2; return 1; }
        [ "$(jq -r '.metadata.parse_path // "-"' <<<"$result_e")" = "schema_enforced" ]
        if [ "$(jq -r '._expect.enforced_rejected // empty' "$f")" != "" ]; then
            [ "$(jq -r '.metadata.rejected_count // 0' <<<"$result_e")" = "$(jq -r '._expect.enforced_rejected' "$f")" ] || { echo "$f enforced rejected_count" >&2; return 1; }
            local sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${fsprint}-e/adversarial-rejected-${typ}.jsonl"
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
    # (thirty-eighth run, c2e DISS-C-001: neg-missing-id is the review wire shape but for its id — every other required key, a
    # review-enum category — so it tests id derivation alone, never a category or anchor laxity of validate_finding)
    jq -e --slurpfile w "$PROJECT_ROOT/.claude/schemas/wire/dissent-review.wire.json" '(.content | fromjson | .findings[0]) as $x
        | ($w[0] | [.. | objects | select(has("required") and (.required | index("failure_mode")))][0]) as $s
        | ($x | has("id") | not) and ([$s.required[] | select(. != "id")] - ($x | keys) == [])
        and ($x.category | IN($s.properties.category.enum[]))' "$corpus/kf004/neg-missing-id.json" >/dev/null \
        || { echo "neg-missing-id is not the review wire shape but for its id"; return 1; }
    # every directory of this run's id the loop left is one teardown will remove (thirty-first run, c2e DISS-C-001: the
    # suffixed per-fixture directories leaked into the live a2a after the sibling rule narrowed teardown to the exact id)
    # (read-only, and through find: NRM-42 bans the a2a sibling glob in these suites outright)
    local d own
    while IFS= read -r d; do
        own=0; for f in "${FR7_OWN_DIRS[@]}"; do [[ "${d##*/}" == "$f" ]] && own=1; done
        [ "$own" = 1 ] || { echo "an unregistered directory: ${d##*/}"; return 1; }
    done < <(find "$PROJECT_ROOT/grimoires/loa/a2a" -mindepth 1 -maxdepth 1 -name "${SPRINT}-*")
}

@test "slice-C MEDIUM: a model id carrying a command substitution never executes it, even when the maps file is unsourceable" {
    local bad_dir="$TEST_DIR/badscripts"; mkdir -p "$bad_dir"
    printf 'this is not bash (\n' > "$bad_dir/generated-model-maps.sh"
    local canary="$TEST_DIR/pwned"
    local out
    out=$(SCRIPT_DIR="$bad_dir" _adv_input_budget_for_model "x[\$(touch $canary)]")
    [ ! -e "$canary" ]
    [ "$out" = "$DEFAULT_PRIMARY_TOKEN_BUDGET" ]
    # a valid alias against the real maps still resolves
    [ "$(SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts" _adv_input_budget_for_model opus)" = "$_ANTHROPIC_DISPATCH_INPUT_BUDGET" ]
    # and an unsourceable maps file yields the default for a valid id (no silent indexed lookup)
    [ "$(SCRIPT_DIR="$bad_dir" _adv_input_budget_for_model opus)" = "$DEFAULT_PRIMARY_TOKEN_BUDGET" ]
}

@test "FR7-11: a teardown after a setup that failed before the sprint id was set never deletes the a2a root nor a foreign sprint (twenty-eighth run, c2e DISS-C-001)" {
    local root="$TEST_DIR/fake-root" rc=0 s
    mkdir -p "$root/grimoires/loa/a2a/sprint-1"; : > "$root/grimoires/loa/a2a/sprint-1/keep"
    for s in "" "sprint-1" "x"; do
        ( set -e; PROJECT_ROOT="$root"; SPRINT="$s"; [[ -n "$s" ]] || unset SPRINT; teardown ) 3>&- & wait $! || rc=$?
        [ "$rc" -eq 0 ] || { echo "SPRINT='$s': the teardown failed (rc $rc)"; return 1; }
        [ -e "$root/grimoires/loa/a2a/sprint-1/keep" ] || { echo "SPRINT='$s': the teardown deleted a record that is not its own"; return 1; }
    done
    # its own id reaches the delete: a link there is never followed, a sibling never taken, the real directory removed
    # (twenty-ninth run, c2e DISS-C-001: the legs above all stop at the id guard)
    local a="$root/grimoires/loa/a2a"
    ln -s "$a/sprint-1" "$a/sprint-fr7-probe"
    rc=0; ( set -e; PROJECT_ROOT="$root"; SPRINT=sprint-fr7-probe; teardown ) 3>&- & wait $! || rc=$?
    [ "$rc" -eq 0 ] && [ -e "$a/sprint-1/keep" ] && [ -L "$a/sprint-fr7-probe" ] || { echo "a link at the own path (rc $rc)"; return 1; }
    command rm -f -- "$a/sprint-fr7-probe"
    mkdir -p "$a/sprint-fr7-probe/sub" "$a/sprint-fr7-probe-x"; : > "$a/sprint-fr7-probe/sub/f"; : > "$a/sprint-fr7-probe-x/keep"
    rc=0; ( set -e; PROJECT_ROOT="$root"; SPRINT=sprint-fr7-probe; teardown ) 3>&- & wait $! || rc=$?
    [ "$rc" -eq 0 ] && [ ! -e "$a/sprint-fr7-probe" ] && [ -e "$a/sprint-fr7-probe-x/keep" ] || { echo "the own directory or a sibling (rc $rc)"; return 1; }
    # the directories a test registered are removed — only names of this id, never a link, never an unregistered sibling
    # (thirty-first run, c2e DISS-C-001)
    mkdir -p "$a/sprint-fr7-probe-a-u/s" "$a/sprint-fr7-probe-b-u"; : > "$a/sprint-fr7-probe-a-u/s/f"; : > "$a/sprint-fr7-probe-b-u/keep"
    ln -s "$a/sprint-1" "$a/sprint-fr7-probe-l"
    rc=0; ( set -e; PROJECT_ROOT="$root"; SPRINT=sprint-fr7-probe
            FR7_OWN_DIRS=(sprint-fr7-probe-a-u sprint-fr7-probe-l sprint-1 "sprint-fr7-probe-../sprint-1" sprint-fr7-probe-gone); teardown ) 3>&- & wait $! || rc=$?
    [ "$rc" -eq 0 ] || { echo "the registered-directory teardown failed (rc $rc)"; return 1; }
    [ ! -e "$a/sprint-fr7-probe-a-u" ]
    [ -e "$a/sprint-fr7-probe-b-u/keep" ] && [ -L "$a/sprint-fr7-probe-l" ] && [ -e "$a/sprint-1/keep" ] || { echo "a name not its own was removed"; return 1; }
    command rm -f -- "$a/sprint-fr7-probe-l"
    # setup names the sprint before anything that can fail
    [ "$(awk '/^setup\(\) \{/{getline; print; exit}' "$BATS_TEST_FILENAME")" = '    SPRINT="sprint-fr7-$$"   # first: teardown runs after a failed setup (twenty-eighth run, c2e DISS-C-001)' ]
}
