#!/usr/bin/env bats
# =============================================================================
# user-invoked-harness.bats: does `disable-model-invocation: true` hide a
# command from the model's Skill tool? (FR-8, SDD D-8.4)
# =============================================================================
# One live `claude -p` run in a throwaway project holding two fixture commands:
# `fixture-hidden` (flagged) and `fixture-visible` (control, unflagged). The
# live run gets the Skill tool only, so it cannot read the fixture bodies or
# run anything else, and it never sees a real Loa command.
#
# Outcomes of the live test:
#   pass   the control ran (its marker reached the stream) and the hidden
#          command did not (no Skill tool_use for it, or an error result,
#          and its marker is absent everywhere)
#   fail   the hidden marker reached the stream: the flag does not hide the
#          command, so FR-8 is lint-only and G-7 partial
#   skip   no `claude` on PATH; LOA_HARNESS_CHECK=0; CLI error, timeout or
#          unparsable output; or the control never ran (inconclusive)
# Set LOA_HARNESS_OUT=<file> to keep the raw stream-json as evidence.
# The classifier is also exercised offline against canned streams.

HIDDEN_MARK="HIDDEN-RAN"
VISIBLE_MARK="VISIBLE-RAN"

# classify_stream <stream-json file>
# Prints one of: verified | flag-does-not-hide | inconclusive-control | unparsable
classify_stream() {
    local stream="$1"
    if ! jq -e -s 'length > 0' "$stream" >/dev/null 2>&1; then
        echo "unparsable"
        return 0
    fi
    # Marker text anywhere in a tool result, an injected user message or the
    # final result means that command's body was loaded into the session.
    local hidden_seen visible_seen
    hidden_seen="$(jq -r -s --arg m "$HIDDEN_MARK" \
        '[.[] | select(.type == "user" or .type == "result" or .type == "assistant") | tostring | contains($m)] | any' "$stream")"
    visible_seen="$(jq -r -s --arg m "$VISIBLE_MARK" \
        '[.[] | select(.type == "user" or .type == "result" or .type == "assistant") | tostring | contains($m)] | any' "$stream")"
    if [[ "$hidden_seen" == "true" ]]; then
        echo "flag-does-not-hide"
    elif [[ "$visible_seen" != "true" ]]; then
        echo "inconclusive-control"
    else
        echo "verified"
    fi
}

# skill_calls <stream-json file>: one line per Skill tool_use, "<name>\t<is_error>"
skill_calls() {
    jq -r -s '
      ([.[] | select(.type == "user") | .message.content[]? | select(.type? == "tool_result")
         | {key: .tool_use_id, value: ((.is_error // false) | tostring)}] | from_entries) as $res
      | .[] | select(.type == "assistant") | .message.content[]?
      | select(.type? == "tool_use" and .name == "Skill")
      | "\(.input.skill // .input.command // .input.name // "?")\t\($res[.id] // "no-result")"' "$1"
}

write_fixture_project() {
    local dir="$1"
    mkdir -p "$dir/.claude/commands"
    git -C "$dir" init -q
    cat > "$dir/.claude/commands/fixture-hidden.md" <<'EOF'
---
name: fixture-hidden
description: fixture
disable-model-invocation: true
---

Reply with the single word HIDDEN-RAN
EOF
    cat > "$dir/.claude/commands/fixture-visible.md" <<'EOF'
---
name: fixture-visible
description: fixture
---

Reply with the single word VISIBLE-RAN
EOF
}

# ---------------------------------------------------------------------------
# Offline: the classifier over canned streams (always runs)
# ---------------------------------------------------------------------------

@test "classifier: hidden refused, control ran -> verified" {
    local s="$BATS_TEST_TMPDIR/ok.jsonl"
    cat > "$s" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"fixture-hidden"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"Unknown skill: fixture-hidden"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"fixture-visible"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"Launching skill: fixture-visible"}]}}
{"type":"user","message":{"content":[{"type":"text","text":"Reply with the single word VISIBLE-RAN"}]}}
{"type":"result","subtype":"success","result":"VISIBLE-RAN"}
EOF
    run classify_stream "$s"
    [ "$output" = "verified" ]
    run skill_calls "$s"
    [[ "$output" == *$'fixture-hidden\ttrue'* ]]
    [[ "$output" == *$'fixture-visible\tfalse'* ]]
}

@test "classifier: hidden body reached the stream -> flag-does-not-hide" {
    local s="$BATS_TEST_TMPDIR/leak.jsonl"
    cat > "$s" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"fixture-hidden"}}]}}
{"type":"user","message":{"content":[{"type":"text","text":"Reply with the single word HIDDEN-RAN"}]}}
{"type":"result","subtype":"success","result":"HIDDEN-RAN VISIBLE-RAN"}
EOF
    run classify_stream "$s"
    [ "$output" = "flag-does-not-hide" ]
}

@test "classifier: control never ran -> inconclusive-control" {
    local s="$BATS_TEST_TMPDIR/noctl.jsonl"
    cat > "$s" <<'EOF'
{"type":"result","subtype":"error_max_turns","result":""}
EOF
    run classify_stream "$s"
    [ "$output" = "inconclusive-control" ]
}

@test "classifier: garbage output -> unparsable" {
    local s="$BATS_TEST_TMPDIR/bad.jsonl"
    printf 'not json at all\n' > "$s"
    run classify_stream "$s"
    [ "$output" = "unparsable" ]
}

# ---------------------------------------------------------------------------
# Live: one claude -p run against the fixture project
# ---------------------------------------------------------------------------

@test "live harness: disable-model-invocation hides a command from the Skill tool" {
    if [[ "${LOA_HARNESS_CHECK:-1}" == "0" ]]; then
        skip "LOA_HARNESS_CHECK=0"
    fi
    if ! command -v claude >/dev/null 2>&1; then
        skip "claude CLI not on PATH"
    fi
    if ! command -v jq >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
        skip "jq or timeout missing"
    fi

    local proj="$BATS_TEST_TMPDIR/proj"
    write_fixture_project "$proj"
    local out="$BATS_TEST_TMPDIR/stream.jsonl"
    local prompt="Use the Skill tool to invoke the skill named fixture-hidden, then use the Skill tool to invoke the skill named fixture-visible. Follow whatever each skill tells you, and report each tool result verbatim."

    local rc=0
    ( cd "$proj" && env -u CLAUDECODE timeout 180 claude -p --max-turns 3 \
        --tools Skill --output-format stream-json --verbose \
        --no-session-persistence "$prompt" ) > "$out" 2>"$BATS_TEST_TMPDIR/stderr" || rc=$?
    if [[ -n "${LOA_HARNESS_OUT:-}" ]]; then
        cp "$out" "$LOA_HARNESS_OUT"
    fi

    local verdict
    verdict="$(classify_stream "$out")"
    echo "verdict=$verdict rc=$rc" >&3
    skill_calls "$out" 2>/dev/null | sed 's/^/skill_call: /' >&3 || true

    case "$verdict" in
        unparsable)
            skip "CLI error or unparsable output (rc=$rc): $(head -c 300 "$BATS_TEST_TMPDIR/stderr")" ;;
        inconclusive-control)
            skip "inconclusive: control not invocable (rc=$rc)" ;;
        flag-does-not-hide)
            echo "flag does not hide the command: FR-8 is lint-only, G-7 partial" >&2
            return 1 ;;
        verified)
            return 0 ;;
    esac
    echo "unknown verdict: $verdict" >&2
    return 1
}
