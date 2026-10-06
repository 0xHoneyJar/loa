#!/usr/bin/env bats
# =============================================================================
# implement-gate.bats — cycle-126 Sprint 4 Task 4.4 (SDD D-4.4, Flatline SKP-008)
#
# The PreToolUse stdin carries no harness-set skill signal
# (https://code.claude.com/docs/en/hooks lists session_id, transcript_path,
# cwd, permission_mode, hook_event_name, tool_name, tool_input, tool_use_id,
# and agent_id/agent_type inside a subagent). tool_input is model-authored,
# so `tool_input.active_skill` is evidence at most:
#   - the recorder writes active_skill_seen_at once, from the lead session only
#   - nothing in .run/ flips the gate; only `implement_gate.mode: authoritative`
#     in .loa.config.yaml does, and the key stays undocumented
#   - detect-platform-features.sh never reports the flag true on its own
# =============================================================================

setup() {
    bats_require_minimum_version 1.5.0
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GATE="$REPO/.claude/hooks/compliance/implement-gate.sh"
    DETECT="$REPO/.claude/scripts/detect-platform-features.sh"
    FIX="$REPO/tests/fixtures/pretooluse-payloads"
    ROOT="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$ROOT/.run"
    unset LOA_TEAM_MEMBER CLAUDE_ACTIVE_SKILL_AVAILABLE
}

payload() { sed "s#__ROOT__#$ROOT#g" "$FIX/$1"; }

gate_with() {
    local fixture="$1"
    payload "$fixture" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
}

decision() { [[ "$output" == *'"decision":"ask"'* ]] && echo ask || echo allow; }

opt_in() { printf 'implement_gate:\n  mode: authoritative\n' > "$ROOT/.loa.config.yaml"; }

@test "IG-1 a lead-session payload carrying tool_input.active_skill records active_skill_seen_at and its source" {
    gate_with write-src-active-implement.json
    [ "$status" -eq 0 ]
    run jq -r '[.active_skill_seen_at, .active_skill_source, .active_skill_available] | map(tostring) | @tsv' "$ROOT/.run/platform-features.json"
    [[ "$output" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'\t'tool_input$'\t'false$ ]]
    printf '{"active_skill_available":true}\n' > "$ROOT/.run/platform-features.json"
    gate_with write-src-active-implement.json
    [ "$(jq -r '.active_skill_available' "$ROOT/.run/platform-features.json")" = false ]
}

@test "IG-2 the recorder writes once: an existing active_skill_seen_at is kept, other keys are preserved, no temp file is left" {
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"tool_input","detected_at":"x","schema_version":1}\n' > "$ROOT/.run/platform-features.json"
    gate_with write-app-active-review.json
    run jq -r '.active_skill_seen_at + " " + .detected_at' "$ROOT/.run/platform-features.json"
    [ "$output" = "2026-01-01T00:00:00Z x" ]
    printf '{"detected_at":"y","schema_version":1}\n' > "$ROOT/.run/platform-features.json"
    gate_with write-app-active-review.json
    run jq -r '.detected_at + " " + (.schema_version|tostring) + " " + .active_skill_source' "$ROOT/.run/platform-features.json"
    [ "$output" = "y 1 tool_input" ]
    run find "$ROOT/.run" -name '.platform-features.*'
    [ -z "$output" ]
}

@test "IG-3 a teammate role or a subagent payload writes nothing" {
    payload write-src-active-implement.json > "$BATS_TEST_TMPDIR/stdin.json"
    run bash -c 'cd "$1" && LOA_TEAM_MEMBER=worker-1 PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ ! -e "$ROOT/.run/platform-features.json" ]
    gate_with write-src-subagent-run.json
    [ ! -e "$ROOT/.run/platform-features.json" ]
}

@test "IG-4 the corpus' records_evidence column holds for every fixture" {
    local f h a rec
    while IFS=$'\t' read -r f h a rec; do
        [[ "$f" == \#* || -z "$f" ]] && continue
        rm -f "$ROOT/.run/platform-features.json"
        gate_with "$f"
        if [[ "$rec" == yes ]]; then
            jq -e '.active_skill_seen_at' "$ROOT/.run/platform-features.json" >/dev/null || { echo "$f: expected evidence" >&2; return 1; }
        else
            [ ! -e "$ROOT/.run/platform-features.json" ] || { echo "$f: expected no evidence" >&2; return 1; }
        fi
    done < "$FIX/expected.tsv"
}

@test "IG-5 a forged active_skill Write payload does not flip the gate, whatever .run/ claims" {
    printf '{"active_skill_available":true,"active_skill_seen_at":"2026-01-01T00:00:00Z","detected_at":"x","schema_version":1}\n' > "$ROOT/.run/platform-features.json"
    printf 'authoritative\n' > "$ROOT/.run/.compliance-mode"
    printf 'confirmed\n' > "$ROOT/.run/.active-skill-probe"
    gate_with write-src-active-implement.json
    [ "$status" -eq 0 ]
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"[ADVISORY]"* ]]
}

@test "IG-6 without the opt-in the gate stays heuristic: every corpus fixture gets its heuristic decision" {
    printf 'implement_gate:\n  mode: heuristic\n' > "$ROOT/.loa.config.yaml"
    local f h a rec
    while IFS=$'\t' read -r f h a rec; do
        [[ "$f" == \#* || -z "$f" ]] && continue
        gate_with "$f"
        [ "$(decision)" = "$h" ] || { echo "$f: expected $h, got $(decision)" >&2; return 1; }
    done < "$FIX/expected.tsv"
}

@test "IG-7 with implement_gate.mode: authoritative the branch passes the payload corpus" {
    command -v yq >/dev/null || skip "yq not installed"
    opt_in
    local f h a rec
    while IFS=$'\t' read -r f h a rec; do
        [[ "$f" == \#* || -z "$f" ]] && continue
        gate_with "$f"
        [ "$(decision)" = "$a" ] || { echo "$f: expected $a, got $(decision)" >&2; return 1; }
    done < "$FIX/expected.tsv"
}

@test "IG-8 the authoritative branch falls back to the heuristic on a payload without active_skill (RUNNING allows, absent asks)" {
    command -v yq >/dev/null || skip "yq not installed"
    opt_in
    gate_with write-src-plain.json
    [ "$(decision)" = ask ]
    printf '{"plan_id":"p","state":"RUNNING","timestamps":{"last_activity":"%s"}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ROOT/.run/sprint-plan-state.json"
    gate_with write-src-plain.json
    [ "$(decision)" = allow ]
}

@test "IG-9 detect-platform-features.sh: the env var and the probe file no longer set the flag; the evidence is reported, never promoted" {
    printf 'confirmed\n' > "$ROOT/.run/.active-skill-probe"
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"tool_input"}\n' > "$ROOT/.run/platform-features.json"
    touch -d '2 hours ago' "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && CLAUDE_ACTIVE_SKILL_AVAILABLE=1 PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2"' _ "$ROOT" "$DETECT"
    [ "$status" -eq 0 ]
    run jq -r '[.active_skill_available, .harness_signal, .active_skill_seen_at, .active_skill_source] | map(tostring) | join(" ")' "$ROOT/.run/platform-features.json"
    [ "$output" = "false false 2026-01-01T00:00:00Z tool_input" ]
}

@test "IG-10 the /loa evidence line: mode and evidence, read-only" {
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
    [ "$output" = "Implement gate: heuristic (active_skill evidence: none; no harness skill signal)" ]
    [ ! -e "$ROOT/.run/platform-features.json" ]
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"tool_input"}\n' > "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
    [ "$output" = "Implement gate: heuristic (active_skill evidence: seen 2026-01-01T00:00:00Z via tool_input; no harness skill signal)" ]
    if command -v yq >/dev/null; then
        opt_in
        run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
        [[ "$output" == "Implement gate: authoritative (opt-in; active_skill evidence: seen "* ]]
    fi
    grep -q 'display_gate_line' "$REPO/.claude/scripts/loa-status.sh"
    grep -A1 '^      display_context_line$' "$REPO/.claude/scripts/loa-status.sh" | grep -q 'display_gate_line'
}

@test "IG-11 the opt-in key stays undocumented while the payload carries no harness signal" {
    # sprint-250 review run 1, n20: a bare mid-test `! grep` cannot fail
    run ! grep -q 'implement_gate' "$REPO/.loa.config.yaml.example"
    run ! grep -rq 'implement_gate' "$REPO/docs" "$REPO/README.md"
}
