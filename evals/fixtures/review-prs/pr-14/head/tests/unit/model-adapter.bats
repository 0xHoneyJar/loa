#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-adapter.bats — cycle-126 sprint-250 Tasks 4.1/4.2 (SDD D-4.1,
# bead bd-2fti) and bead bd-pw7e LOW-001. The shim's legacy MODEL_TO_ALIAS map
# and --help name the current generation; the cheval WARN that names the agy
# argv exposure reaches the shim's stderr instead of being discarded.
# =============================================================================

setup() {
    bats_require_minimum_version 1.5.0
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ADAPTER="$REPO_ROOT/.claude/scripts/model-adapter.sh"
    TMP_DIR="$BATS_TEST_TMPDIR"
    printf 'test input\n' > "$TMP_DIR/input.txt"
    export FLATLINE_MOCK_MODE=true
    export PROJECT_ROOT="$REPO_ROOT"
}

# map_of <name> — the MODEL_TO_ALIAS value for <name>, read from the script text.
map_of() {
    local src
    src=$(awk '/^declare -A MODEL_TO_ALIAS=\(/{f=1} f{print} f && /^\)/{exit}' "$ADAPTER")
    bash -c "$src"$'\n''printf "%s" "${MODEL_TO_ALIAS[$1]:-}"' _ "$1"
}

@test "MA-1 MODEL_TO_ALIAS: opus → the current Opus (claude-opus-5-5); the 5-family names resolve to themselves" {
    [ "$(map_of opus)" = "anthropic:claude-opus-5-5" ]
    [ "$(map_of fable)" = "anthropic:claude-fable-5-1" ]
    [ "$(map_of claude-fable-5-1)" = "anthropic:claude-fable-5-1" ]
    [ "$(map_of claude-opus-5)" = "anthropic:claude-opus-5" ]
    [ "$(map_of claude-opus-5-5)" = "anthropic:claude-opus-5-5" ]
    [ "$(map_of claude-sonnet-5)" = "anthropic:claude-sonnet-5" ]
}

@test "MA-2 MODEL_TO_ALIAS agrees with the catalog's backward_compat_aliases for every name both define (4.x history included)" {
    local pairs m want got n=0
    pairs=$(python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1]))["backward_compat_aliases"]; [print(k+"\t"+v) for k,v in d.items()]' "$REPO_ROOT/.claude/defaults/model-config.yaml")
    while IFS=$'\t' read -r m want; do
        got=$(map_of "$m")
        [[ -z "$got" ]] && continue
        n=$((n + 1))
        [[ "$got" == "$want" ]] || { echo "$m: shim $got, catalog $want" >&2; return 1; }
    done <<< "$pairs"
    [ "$n" -ge 12 ]
}

@test "MA-3 --help names the current generation, and no 4.x model as current" {
    run bash "$ADAPTER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-opus-5-5"* && "$output" == *"fable"* && "$output" == *"claude-sonnet-5"* ]]
    [[ "$output" != *"Claude Opus 4.7 (current"* ]]
}

@test "MA-4 opus resolves to anthropic:claude-opus-5-5 end to end through the shim" {
    cat > "$TMP_DIR/mi" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP_DIR/argv"
printf '%s\n' '{"content": "ok", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}'
SHIM
    chmod +x "$TMP_DIR/mi"
    MODEL_INVOKE="$TMP_DIR/mi" run bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt"
    [ "$status" -eq 0 ]
    grep -qxF -- "anthropic:claude-opus-5-5" "$TMP_DIR/argv"
}

@test "MA-5 (bd-pw7e LOW-001) the agy argv WARN reaches the shim's stderr; other cheval stderr stays out" {
    cat > "$TMP_DIR/mi" <<'SHIM'
#!/usr/bin/env bash
echo "[cheval] INFO: noise line that the shim keeps out" >&2
echo "[cheval] WARNING: gemini-headless dispatches agy, which takes the whole prompt on argv (readable by every local account through /proc/<pid>/cmdline and ps for the life of the hop)" >&2
echo "secret-ish provider chatter" >&2
printf '%s\n' '{"content": "ok", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}'
SHIM
    chmod +x "$TMP_DIR/mi"
    MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"gemini-headless dispatches agy"* ]]
    [[ "$stderr" != *"noise line"* && "$stderr" != *"provider chatter"* ]]
    [[ "$output" != *"gemini-headless dispatches agy"* ]]
}

@test "MA-6 (bd-pw7e LOW-001) the WARN is forwarded on a failed hop too, and the exit code is kept" {
    cat > "$TMP_DIR/mi" <<'SHIM'
#!/usr/bin/env bash
echo "[cheval] WARNING: gemini-headless dispatches agy, which takes the whole prompt on argv" >&2
exit 7
SHIM
    chmod +x "$TMP_DIR/mi"
    MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt"
    [ "$status" -eq 7 ]
    [[ "$stderr" == *"gemini-headless dispatches agy"* ]]
}
