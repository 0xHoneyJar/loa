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
    bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 2, #10)
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

# Claude Code PreToolUse contract: "ask" is only valid as hookSpecificOutput.permissionDecision; a top-level
# "decision" takes approve|block only (sprint-250 audit n20). Allow = silent exit 0 with empty stdout.
decision() {
    if [[ -z "$output" ]]; then echo allow
    elif jq -e '(has("decision") | not) and .hookSpecificOutput.hookEventName == "PreToolUse"
                and .hookSpecificOutput.permissionDecision == "ask"
                and (.hookSpecificOutput.permissionDecisionReason | type == "string" and length > 0)' <<<"$output" >/dev/null 2>&1; then echo ask
    else echo "invalid:$output"; fi
}

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

@test "IG-12 authoritative is strictly tighter than heuristic: with RUNNING state a non-implementation claim asks and logs one ask row, each implementation claim one heuristic row" {
    command -v yq >/dev/null || skip "yq not installed"
    printf '{"plan_id":"p","state":"RUNNING","timestamps":{"last_activity":"%s"}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ROOT/.run/sprint-plan-state.json"
    gate_with write-app-active-review.json
    [ "$(decision)" = allow ]
    [ ! -e "$ROOT/.run/audit.jsonl" ]
    opt_in
    gate_with write-app-active-review.json
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"[AUTHORITATIVE]"* ]]
    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal")] | map([.mode, .active_skill, .file_path, .decision, (.timestamp | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\\z"))])' "$ROOT/.run/audit.jsonl"
    [ "$output" = "[[\"authoritative\",\"review-sprint\",\"$ROOT/app/main.py\",\"ask\",true]]" ]
    # a claimed implementation skill never allows by itself: with RUNNING it allows (heuristic), without it asks
    gate_with write-src-active-implement.json
    [ "$(decision)" = allow ]
    rm "$ROOT/.run/sprint-plan-state.json"
    gate_with write-src-active-implement.json
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"[ADVISORY]"* ]]
    # every forged claim leaves a trace (run-2 finding 6): one ask row for the review claim, one heuristic row per implementation claim
    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal") | .decision] | sort' "$ROOT/.run/audit.jsonl"
    [ "$output" = '["ask","heuristic","heuristic"]' ]
    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal" and .decision == "heuristic") | [.mode, .active_skill, .file_path]] | unique' "$ROOT/.run/audit.jsonl"
    [ "$output" = "[[\"authoritative\",\"implement\",\"$ROOT/src/index.ts\"]]" ]
}

@test "IG-13 control characters in a claimed skill or path are stripped from stderr and the audit row (n21)" {
    command -v yq >/dev/null || skip "yq not installed"
    opt_in
    printf '{"tool_input":{"file_path":"%s/src/a\\u001b[31mb\\u007f.py","active_skill":"rev\\u0007iew\\r\\n"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"'$ROOT/src/a[31mb.py' detected during /review (not an implementation skill)."* ]]
    run -1 env LC_ALL=C grep -q $'[\x01-\x09\x0b-\x1f\x7f]' <<<"$stderr"
    # run-3 finding 4: the row records the raw claim faithfully, every control and non-ASCII code point \u-escaped (jq -a)
    run jq -r 'select(.event == "compliance.mode.model_signal") | (.active_skill + " " + .file_path) | @json' "$ROOT/.run/audit.jsonl"
    [ "$output" = "\"rev\\u0007iew\\r\\n $ROOT/src/a\\u001b[31mb\\u007f.py\"" ]
    run -1 env LC_ALL=C grep -q $'[\x01-\x09\x0b-\x1f\x7f-\xff]' "$ROOT/.run/audit.jsonl"
    # run-2 findings 3/12: UTF-8 C1 controls, bidi/format code points and a doubled C2 C2 9B 9B (one pass would leave a live
    # C2 9B) never reach stderr or the row; the logged skill is at most 256 bytes; legitimate UTF-8 (café) passes verbatim
    local bad=$'\xc2\x9b'$'\xe2\x80\xae'$'\xe2\x80\x8b'$'\xc2\xc2\x9b\x9b' long
    long=$(printf 'k%.0s' {1..400})
    rm -f "$ROOT/.run/audit.jsonl"
    printf '{"tool_input":{"file_path":"%s/src/caf\xc3\xa9%sx.py","active_skill":"rev%siew%s"}}\n' "$ROOT" "$bad" "$bad" "$long" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"'$ROOT/src/café"* ]]
    [[ "$stderr" == *"detected during /rev"* ]]   # jq reads the invalid doubled bytes as U+FFFD U+009B U+FFFD; only the U+009B goes
    local seq
    for seq in $'\xc2\x9b' $'\xe2\x80\xae' $'\xe2\x80\x8b'; do
        run -1 env LC_ALL=C grep -qF "$seq" <<<"$stderr"
        run -1 env LC_ALL=C grep -qF "$seq" "$ROOT/.run/audit.jsonl"
    done
    run -1 env LC_ALL=C grep -q $'\xc2[\x80-\x9f]' "$ROOT/.run/audit.jsonl"
    run jq -r 'select(.event == "compliance.mode.model_signal") | .file_path' "$ROOT/.run/audit.jsonl"
    [[ "$output" == "$ROOT/src/café"*x.py ]]
    run jq -j 'select(.event == "compliance.mode.model_signal") | .active_skill' "$ROOT/.run/audit.jsonl"
    [[ "$output" == rev* ]]
    [ "$(printf '%s' "$output" | LC_ALL=C wc -c)" -le 256 ]
    # run-3 finding 4: implement + U+200B is not an implementation claim — it asks, and the row shows the claim as written
    # (implement\u200b), never the stripped "implement" beside decision "ask"
    rm -f "$ROOT/.run/audit.jsonl"
    printf '{"tool_input":{"file_path":"%s/src/i.py","active_skill":"implement\\u200b"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    grep -qF '"active_skill":"implement\u200b"' "$ROOT/.run/audit.jsonl"
    grep -qF '"decision":"ask"' "$ROOT/.run/audit.jsonl"
    # run-3 finding 5: U+00AD, U+061C, U+206A, U+180E, U+FFF9, U+FE0F and the tag characters U+E0001/U+E0041 never reach stderr
    rm -f "$ROOT/.run/audit.jsonl"
    printf '{"tool_input":{"file_path":"%s/src/x\\u00ad\\u061c\\u206a\\u180e\\ufff9\\ufe0f\\udb40\\udc01\\udb40\\udc41y.py","active_skill":"rev\\u206fiew"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    [[ "$stderr" == *"'$ROOT/src/xy.py' detected during /review (not an implementation skill)."* ]]
    for seq in $'\xc2\xad' $'\xd8\x9c' $'\xe2\x81\xaa' $'\xe2\x81\xaf' $'\xe1\xa0\x8e' $'\xef\xbf\xb9' $'\xef\xb8\x8f' $'\xf3\xa0\x80\x81' $'\xf3\xa0\x81\x81'; do
        run -1 env LC_ALL=C grep -qF "$seq" <<<"$stderr"
    done
    # run-3 finding 5: a 256-byte cut that would split a 2-byte character drops it whole — no U+FFFD in the row or on stderr
    rm -f "$ROOT/.run/audit.jsonl"
    local pre="$ROOT/src/" pad
    pad=$(printf 'p%.0s' $(seq 1 $(( 255 - ${#pre} ))))
    printf '{"tool_input":{"file_path":"%s%s\xc3\xa9tail.py","active_skill":"review"}}\n' "$pre" "$pad" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    run -1 grep -qiF '\ufffd' "$ROOT/.run/audit.jsonl"
    run -1 env LC_ALL=C grep -qF $'\xef\xbf\xbd' <<<"$stderr"
    run jq -j 'select(.event == "compliance.mode.model_signal") | .file_path' "$ROOT/.run/audit.jsonl"
    [ "$output" = "$pre$pad" ]
}

@test "IG-14 the /loa evidence line and the refresh never carry Unicode format characters (U+202E, U+200B) and share one shape check" {
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z\\u202e","active_skill_source":"tool\\u200b_input"}\n' > "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
    [ "$output" = "Implement gate: heuristic (active_skill evidence: none; no harness skill signal)" ]
    run -1 env LC_ALL=C grep -q '[^[:print:]]' <<<"$output"
    # run-2 finding 4: --line applies the refresh's shape checks — a malformed seen_at is no evidence, an unknown source is "unknown"
    printf '{"active_skill_seen_at":"yesterday","active_skill_source":"tool_input"}\n' > "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
    [ "$output" = "Implement gate: heuristic (active_skill evidence: none; no harness skill signal)" ]
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"forged"}\n' > "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
    [ "$output" = "Implement gate: heuristic (active_skill evidence: seen 2026-01-01T00:00:00Z via unknown; no harness skill signal)" ]
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z\\u202e","active_skill_source":"tool\\u200b_input"}\n' > "$ROOT/.run/platform-features.json"
    touch -d '2 hours ago' "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2"' _ "$ROOT" "$DETECT"
    run jq -r '[.active_skill_seen_at, .active_skill_source] | map(tostring) | join(" ")' "$ROOT/.run/platform-features.json"
    [ "$output" = "null null" ]
    # a well-shaped seen_at with an unknown source keeps the seen_at only
    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"forged"}\n' > "$ROOT/.run/platform-features.json"
    touch -d '2 hours ago' "$ROOT/.run/platform-features.json"
    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2"' _ "$ROOT" "$DETECT"
    run jq -r '[.active_skill_seen_at, .active_skill_source] | map(tostring) | join(" ")' "$ROOT/.run/platform-features.json"
    [ "$output" = "2026-01-01T00:00:00Z null" ]
}

gate_path() {
    jq -nc --arg p "$1" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
}

@test "IG-15 the App-Zone check compares canonical paths: a non-canonical spelling of a src/ file asks, a canonically-outside path allows (run-2 finding 1)" {
    local p
    for p in "/proc/self/cwd/src/x.ts" "/$ROOT/src/x.ts" "$ROOT/../$(basename "$ROOT")/src/x.ts" "$ROOT/grimoires/../src/x.ts"; do
        gate_path "$p"
        [ "$(decision)" = ask ] || { echo "$p: expected ask, got $(decision)" >&2; return 1; }
    done
    ln -s "$ROOT" "$BATS_TEST_TMPDIR/link"
    gate_path "$BATS_TEST_TMPDIR/link/src/x.ts"
    [ "$(decision)" = ask ]
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere/src"
    gate_path "$BATS_TEST_TMPDIR/elsewhere/src/x.ts"
    [ "$(decision)" = allow ]
    gate_path "$ROOT/grimoires/loa/NOTES.md"
    [ "$(decision)" = allow ]
    # run-3 finding 2: on a case-insensitive filesystem LIB/ is lib/ — the patterns match a lowercased copy
    gate_path "$ROOT/LIB/x.js"
    [ "$(decision)" = ask ]
}

@test "IG-16 an unparsable payload and a NotebookEdit payload under src/ ask; a parsed payload without a path allows (run-2 finding 5)" {
    printf 'not json\n' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$status" -eq 0 ]
    [ "$(decision)" = ask ]
    [[ "$output" == *"[GATE] could not evaluate tool_input"* ]]
    printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s/src/nb.ipynb","new_source":"x"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    printf '{"tool_input":{"content":"x"}}\n' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$status" -eq 0 ]
    [ "$(decision)" = allow ]
}

@test "IG-17 an inside-out symlink (src/ itself, or a lib/ file, pointing out of the root) still asks: the logical and the physical form are both tested (run-3 finding 1)" {
    mkdir -p "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside" "$ROOT/src"
    mkdir -p "$ROOT/lib"
    ln -s ../outside/real.ts "$ROOT/lib/cfg.ts"
    gate_path "$ROOT/src/x.ts"
    [ "$(decision)" = ask ]
    gate_path "$ROOT/lib/cfg.ts"
    [ "$(decision)" = ask ]
    # the pure-bash normaliser (no realpath -s): a realpath that refuses -s forces the fallback
    mkdir -p "$BATS_TEST_TMPDIR/shim"
    printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ "$a" == -s || "$a" == --no-symlinks ]] && exit 1; done\nexec %q "$@"\n' "$(command -v realpath)" > "$BATS_TEST_TMPDIR/shim/realpath"
    chmod +x "$BATS_TEST_TMPDIR/shim/realpath"
    local p
    for p in "$ROOT/src/x.ts" "$ROOT/lib/cfg.ts" "$ROOT/grimoires/./../src//y.ts"; do
        jq -nc --arg p "$p" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
        run --separate-stderr bash -c 'cd "$1" && PATH="$4:$PATH" PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json" "$BATS_TEST_TMPDIR/shim"
        [ "$(decision)" = ask ] || { echo "fallback $p: expected ask, got $(decision)" >&2; return 1; }
    done
    jq -nc --arg p "$ROOT/grimoires/loa/../loa/NOTES.md" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PATH="$4:$PATH" PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json" "$BATS_TEST_TMPDIR/shim"
    [ "$(decision)" = allow ]
}

@test "IG-18 a write to one of the gate's own trust inputs asks and leaves one compliance.state_write row; other .run/ and grimoires/ files allow silently (run-3 finding 3)" {
    local rel n=0
    for rel in .run/state.json .run/sprint-plan-state.json .run/simstim-state.json .run/platform-features.json .run/audit.jsonl .loa.config.yaml; do
        gate_path "$ROOT/$rel"
        [ "$(decision)" = ask ] || { echo "$rel: expected ask, got $(decision)" >&2; return 1; }
        [[ "$stderr" == *"[GATE] write to an implement-gate trust input"* ]]
        n=$(( n + 1 ))
        run jq -sc --arg p "$ROOT/$rel" '[.[] | select(.event == "compliance.state_write" and .file_path == $p and (.timestamp | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\\z")))] | length' "$ROOT/.run/audit.jsonl"
        [ "$output" = 1 ] || { echo "$rel: expected one row, got $output" >&2; return 1; }
    done
    [ "$(jq -sc 'length' "$ROOT/.run/audit.jsonl")" = "$n" ]
    # a relative spelling of a trust input asks too
    gate_path ".run/../.run/state.json"
    [ "$(decision)" = ask ]
    rm -f "$ROOT/.run/audit.jsonl"
    gate_path "$ROOT/.run/other.json"
    [ "$(decision)" = allow ]
    gate_path "$ROOT/grimoires/loa/NOTES.md"
    [ "$(decision)" = allow ]
    [ ! -e "$ROOT/.run/audit.jsonl" ]
}

@test "IG-19 a relative file_path resolves from the payload's cwd when it carries one, else from PROJECT_ROOT (run-3 finding 6)" {
    mkdir -p "$ROOT/src" "$ROOT/grimoires"
    jq -nc --arg c "$ROOT/src" '{cwd: $c, tool_input: {file_path: "index.ts", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
    jq -nc --arg c "$ROOT/grimoires" '{cwd: $c, tool_input: {file_path: "x.md", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = allow ]
    jq -nc '{tool_input: {file_path: "src/index.ts", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
}

@test "IG-20 the ask reply is built by jq: the reason is a JSON string whatever it contains (run-3 finding 7)" {
    grep -q 'jq -nc --arg r "\$1"' "$GATE"
    printf 'not json\n' > "$BATS_TEST_TMPDIR/stdin.json"
    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    [ "$(decision)" = ask ]
}

# The hook as wired in production: no PROJECT_ROOT or RUN_DIR in its environment, its process cwd wherever Claude cd'd
# (MED-001). $1 = hook path, $2 = process cwd, $3 = CLAUDE_PROJECT_DIR (empty = unset), $4 = file_path; payload cwd = $2
gate_unrooted() {
    jq -nc --arg c "$2" --arg p "$4" '{cwd: $c, tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
    if [[ -n "$3" ]]; then
        run --separate-stderr env -u PROJECT_ROOT -u RUN_DIR CLAUDE_PROJECT_DIR="$3" bash -c 'cd "$1" && bash "$2" < "$3"' _ "$2" "$1" "$BATS_TEST_TMPDIR/stdin.json"
    else
        run --separate-stderr env -u PROJECT_ROOT -u RUN_DIR -u CLAUDE_PROJECT_DIR bash -c 'cd "$1" && bash "$2" < "$3"' _ "$2" "$1" "$BATS_TEST_TMPDIR/stdin.json"
    fi
}

@test "IG-21 the root is CLAUDE_PROJECT_DIR, else the hook's own location, never the process cwd: from a subdirectory an App-Zone and a trust-input write still ask (MED-001)" {
    mkdir -p "$ROOT/src" "$ROOT/.claude/hooks/compliance"
    cp "$GATE" "$ROOT/.claude/hooks/compliance/implement-gate.sh"
    local leg hook cwd cpd
    # leg = hook|cwd|CLAUDE_PROJECT_DIR: the harness's project dir from a subdirectory, then the script-location rung
    # (the copy under $ROOT/.claude/hooks/compliance/ resolves to $ROOT) from the subdirectory and from the root
    for leg in "$GATE|$ROOT/src|$ROOT" "$ROOT/.claude/hooks/compliance/implement-gate.sh|$ROOT/src|" "$ROOT/.claude/hooks/compliance/implement-gate.sh|$ROOT|"; do
        IFS='|' read -r hook cwd cpd <<<"$leg"
        rm -f "$ROOT/.run/audit.jsonl"
        gate_unrooted "$hook" "$cwd" "$cpd" "$ROOT/src/x.ts"
        [ "$(decision)" = ask ] || { echo "$leg src/x.ts: expected ask, got $(decision)" >&2; return 1; }
        gate_unrooted "$hook" "$cwd" "$cpd" "$ROOT/.loa.config.yaml"
        [ "$(decision)" = ask ] || { echo "$leg .loa.config.yaml: expected ask, got $(decision)" >&2; return 1; }
        run jq -sc --arg p "$ROOT/.loa.config.yaml" '[.[] | select(.event == "compliance.state_write" and .file_path == $p)] | length' "$ROOT/.run/audit.jsonl"
        [ "$output" = 1 ] || { echo "$leg: expected one state_write row in \$ROOT/.run/audit.jsonl, got $output" >&2; return 1; }
    done
    [ ! -e "$ROOT/src/.run/audit.jsonl" ]
}

# A state file under .run/ named $1, aged $2 hours (0 = now), the jq object $3 plus .timestamps.last_activity
state_aged() {
    jq -nc --argjson h "$2" "$3"' + {timestamps: {last_activity: (now - $h * 3600 | floor | todate)}}' > "$ROOT/.run/$1"   # jq todate: portable, no GNU date -d
}

@test "IG-22 state.json RUNNING, simstim-state.json implementation and sprint-plan-state.json RUNNING allow only while fresh: older than 24 h, more than 24 h ahead, with no timestamp or an unparsable one, asks (LOW-004, LOW-006)" {
    local f body
    for f in state.json simstim-state.json; do
        case "$f" in state.json) body='{state: "RUNNING"}' ;; *) body='{state: "RUNNING", phase: "implementation"}' ;; esac
        rm -f "$ROOT/.run/state.json" "$ROOT/.run/simstim-state.json"
        state_aged "$f" 25 "$body"
        gate_path "$ROOT/src/x.ts"
        [ "$(decision)" = ask ] || { echo "$f 25 h: expected ask, got $(decision)" >&2; return 1; }
        state_aged "$f" 0 "$body"
        gate_path "$ROOT/src/x.ts"
        [ "$(decision)" = allow ] || { echo "$f fresh: expected allow, got $(decision)" >&2; return 1; }
        jq -nc "$body" > "$ROOT/.run/$f"
        gate_path "$ROOT/src/x.ts"
        [ "$(decision)" = ask ] || { echo "$f no timestamp: expected ask, got $(decision)" >&2; return 1; }
    done
    # state.json's .updated_at (the run-preflight fallback) counts as its timestamp
    rm -f "$ROOT/.run/simstim-state.json"
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{state: "RUNNING", updated_at: $ts}' > "$ROOT/.run/state.json"
    gate_path "$ROOT/src/x.ts"
    [ "$(decision)" = allow ]
    # sprint-250 audit LOW-006: the window is bounded in both directions — a last_activity 48 h ahead is not fresh forever
    for f in state.json simstim-state.json sprint-plan-state.json; do
        case "$f" in
            state.json) body='{state: "RUNNING"}' ;;
            simstim-state.json) body='{state: "RUNNING", phase: "implementation"}' ;;
            *) body='{plan_id: "p", state: "RUNNING"}' ;;
        esac
        rm -f "$ROOT/.run/state.json" "$ROOT/.run/simstim-state.json" "$ROOT/.run/sprint-plan-state.json"
        state_aged "$f" -48 "$body"
        gate_path "$ROOT/src/x.ts"
        [ "$(decision)" = ask ] || { echo "$f 48 h ahead: expected ask, got $(decision)" >&2; return 1; }
    done
    # and sprint-plan-state.json RUNNING + plan_id with no timestamp, or one that does not parse, is stale too
    # (not-a-date, not yesterday: GNU date -d parses yesterday)
    rm -f "$ROOT/.run/sprint-plan-state.json"
    jq -nc '{plan_id: "p", state: "RUNNING"}' > "$ROOT/.run/sprint-plan-state.json"
    gate_path "$ROOT/src/x.ts"
    [ "$(decision)" = ask ] || { echo "sprint-plan no timestamp: expected ask, got $(decision)" >&2; return 1; }
    jq -nc '{plan_id: "p", state: "RUNNING", timestamps: {last_activity: "not-a-date"}}' > "$ROOT/.run/sprint-plan-state.json"
    gate_path "$ROOT/src/x.ts"
    [ "$(decision)" = ask ] || { echo "sprint-plan not-a-date: expected ask, got $(decision)" >&2; return 1; }
    state_aged sprint-plan-state.json 0 '{plan_id: "p", state: "RUNNING"}'
    gate_path "$ROOT/src/x.ts"
    [ "$(decision)" = allow ] || { echo "sprint-plan fresh: expected allow, got $(decision)" >&2; return 1; }
}

@test "IG-11 the opt-in key stays undocumented while the payload carries no harness signal" {
    # sprint-250 review run 1, n20: a bare mid-test `! grep` cannot fail
    run -1 grep -q 'implement_gate' "$REPO/.loa.config.yaml.example"
    run -1 grep -rq 'implement_gate' "$REPO/docs" "$REPO/README.md"
}
