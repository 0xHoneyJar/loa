#!/usr/bin/env bats
# =============================================================================
# Issue #961 K-2 — Karpathy trajectory event schema + producer
# =============================================================================
# Pins that the hook writes schema-conforming JSON events to
# grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl, append-only, with no
# raw tool_input content leakage (NFR-Sec-1).
#
# cycle-138 FR-6 (SDD § 5.5, DEC-1168): the append goes only through a trusted
# path — TRAJ_DIR inside the checkout, no symlinked component below the root,
# every component a uid-owned directory (its mode is not tested: a checkout's
# directories inherit the clone umask; lead decision, option 2), the day file a
# uid-owned regular file with one link and no group/other write; no
# `realpath -m` → refused. A refusal skips the append silently; the warning line is printed
# regardless (KT-1 … KT-13). The hook resolves its root from its own path
# (../../.., physical), so every test runs a REAL mirror root under
# BATS_TEST_TMPDIR (copies of the hook, profile-lib and the two data files) and
# the trajectory directory lives inside it. The mirror's directories are made
# under umask 022; KT-6/KT-7 pin that a group-writable uid-owned component (an
# umask-002 checkout) still receives the append.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SRC_HOOK="$REPO_ROOT/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    SCHEMA="$REPO_ROOT/.claude/data/trajectory-schemas/karpathy-check.payload.schema.json"
    [[ -x "$SRC_HOOK" ]] || skip "hook not executable"
    [[ -f "$SCHEMA" ]] || skip "schema not found"
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v yq >/dev/null 2>&1 || skip "yq not available"

    umask 022
    TMP_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/kt.XXXXXX")"
    M="$TMP_DIR/root"
    mkdir -p "$M/.claude/hooks/quality" "$M/.claude/scripts/lib" "$M/.claude/data" "$M/grimoires/loa/a2a/trajectory"
    cp "$SRC_HOOK" "$M/.claude/hooks/quality/"
    cp "$REPO_ROOT/.claude/scripts/lib/profile-lib.sh" "$M/.claude/scripts/lib/"
    cp "$REPO_ROOT/.claude/data/profiles.yaml" "$REPO_ROOT/.claude/data/floor.yaml" "$M/.claude/data/"
    HOOK="$M/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    # cycle-129 D-4.3: per-task state under KARPATHY_STATE_DIR; with no run in
    # progress (empty LOA_RUN_DIR) the key is the session id.
    export KARPATHY_STATE_DIR="$TMP_DIR/state"
    export KARPATHY_SUMMARY_FILE="$TMP_DIR/summary.json"
    export KARPATHY_LEGACY_STATE="$TMP_DIR/legacy-task-state.jsonl"
    export LOA_RUN_DIR="$TMP_DIR/run"
    export LOA_SESSION_ID="test-session"
    unset KARPATHY_CHECKPOINT_CMD LOA_PROFILE_CONFIG_FILE LOA_PROFILE_CACHE_FILE
    KARPATHY_TASK_STATE="$KARPATHY_STATE_DIR/test-session.jsonl"
    export KARPATHY_TRAJECTORY_DIR="$M/grimoires/loa/a2a/trajectory"
    export LOA_CONFIG_OVERRIDE="$TMP_DIR/config.yaml"
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 3
EOF
    TODAY="$(date -u +%Y-%m-%d)"
    DAY="$KARPATHY_TRAJECTORY_DIR/karpathy-${TODAY}.jsonl"
    V="$TMP_DIR/victim"
    mkdir -p "$V" "$TMP_DIR/bin"
    printf 'victim-bytes\n' > "$V/file"
}

teardown() {
    chmod -R u+rwx "$TMP_DIR" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}

_trip_warn() {
    local content="line1
line2
line3
line4
line5
line6"
    local input
    input=$(jq -nc --arg c "$content" '{tool_name:"Write", tool_input:{file_path:"/tmp/x", content:$c}}')
    echo "$input" | "$HOOK" 2>&1
}

# _warn_refused: one warn-path run under a 5 s timeout (a FIFO day file must not hang the hook);
# the hook exits 0 and still prints the warning line.
_warn_refused() {
    run timeout 5 bash -c "$(declare -f _trip_warn); HOOK='$HOOK' _trip_warn"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[karpathy-surgical-warn]"* ]]
}

# _victim_unchanged: the victim directory holds exactly its one file with its original bytes.
_victim_unchanged() {
    [ "$(ls -A "$V")" = "file" ]
    [ "$(cat "$V/file")" = "victim-bytes" ]
}

# _shim <tool> <body>: a command shim first on PATH (the real tool stays reachable as REAL_<tool>).
_shim() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP_DIR/bin/$1"
    chmod +x "$TMP_DIR/bin/$1"
    export PATH="$TMP_DIR/bin:$PATH"
}

@test "#961 K-2: trajectory file path follows convention" {
    _trip_warn >/dev/null
    [ -f "$DAY" ]
}

@test "#961 K-2: event has required fields per schema" {
    _trip_warn >/dev/null
    local event
    event=$(tail -1 "$DAY")

    # Required: phase, principle, verdict, timestamp
    [ "$(echo "$event" | jq -r '.phase')" = "karpathy_check" ]
    [ "$(echo "$event" | jq -r '.principle')" = "surgical_changes" ]
    [ "$(echo "$event" | jq -r '.verdict')" = "warn" ]
    [ "$(echo "$event" | jq -r '.timestamp')" != "null" ]
}

@test "#961 K-2: schema is valid JSON Schema 2020-12" {
    # Light validation: schema parses as JSON and declares 2020-12
    # Use --arg to pass the $-key safely (avoid shell + jq double-escape pain)
    [ "$(jq -r --arg k '$schema' '.[$k]' "$SCHEMA")" = "https://json-schema.org/draft/2020-12/schema" ]
    [ "$(jq -r '.type' "$SCHEMA")" = "object" ]
    [ "$(jq -r '.additionalProperties' "$SCHEMA")" = "false" ]
}

@test "#961 K-2: events are append-only (multiple warns → multiple events)" {
    _trip_warn >/dev/null
    _trip_warn >/dev/null  # second invocation, threshold already crossed
    local n
    n=$(wc -l < "$DAY")
    [ "$n" -ge 2 ]
}

@test "KT-1 FR-6 a fresh trajectory directory is created 0700 (each new component) and the event appended" {
    find "$M/grimoires" -mindepth 0 -delete
    _warn_refused
    [ "$(wc -l < "$DAY")" -eq 1 ]
    local d
    for d in "$M/grimoires" "$M/grimoires/loa" "$M/grimoires/loa/a2a" "$KARPATHY_TRAJECTORY_DIR"; do
        [ "$(stat -c '%a' "$d" 2>/dev/null || stat -f '%Lp' "$d")" = "700" ]
    done
    [ "$(stat -c '%a' "$DAY" 2>/dev/null || stat -f '%Lp' "$DAY")" = "600" ]
}

@test "KT-2 FR-6 TRAJ_DIR replaced by a symlink to a victim directory → nothing written through it" {
    rmdir "$KARPATHY_TRAJECTORY_DIR"
    ln -s "$V" "$KARPATHY_TRAJECTORY_DIR"
    _warn_refused
    _victim_unchanged
}

@test "KT-3 FR-6 a symlinked ancestor component (grimoires/loa/a2a → elsewhere) → nothing written" {
    mkdir -p "$V/trajectory"
    find "$M/grimoires/loa/a2a" -mindepth 0 -delete
    ln -s "$V" "$M/grimoires/loa/a2a"
    _warn_refused
    [ -z "$(ls -A "$V/trajectory")" ]
    [ "$(cat "$V/file")" = "victim-bytes" ]
}

@test "KT-4 FR-6 TRAJ_DIR outside the checkout root → refused (warning still printed)" {
    export KARPATHY_TRAJECTORY_DIR="$V"
    _warn_refused
    _victim_unchanged
}

@test "KT-5 FR-6 a foreign-owned intermediate component (stat shim answers uid+1 for grimoires/loa) → refused" {
    local real; real="$(command -v stat)"
    _shim stat "\"$real\" \"\$@\" | awk -F'|' -v OFS='|' -v p='$M/grimoires/loa' -v u='$((EUID + 1))' '\$1 == p { \$2 = u } { print }'"
    _warn_refused
    [ ! -e "$DAY" ]
}

@test "KT-6 FR-6 a group-writable uid-owned intermediate component (grimoires/loa 0775, an umask-002 checkout) → appended" {
    chmod 775 "$M/grimoires" "$M/grimoires/loa" "$M/grimoires/loa/a2a"
    _warn_refused
    [ "$(wc -l < "$DAY")" -eq 1 ]
    _victim_unchanged
}

@test "KT-7 FR-6 a group-writable uid-owned TRAJ_DIR (0775) → appended" {
    chmod 775 "$KARPATHY_TRAJECTORY_DIR"
    _warn_refused
    [ "$(wc -l < "$DAY")" -eq 1 ]
    _victim_unchanged
}

@test "KT-8 FR-6 the day file as a symlink to a victim file → victim bytes unchanged" {
    ln -s "$V/file" "$DAY"
    _warn_refused
    _victim_unchanged
}

@test "KT-9 FR-6 the day file as a FIFO → refused without blocking (timeout 5)" {
    command -v mkfifo >/dev/null 2>&1 || skip "mkfifo not available"
    command -v timeout >/dev/null 2>&1 || skip "timeout not available"
    mkfifo "$DAY"
    _warn_refused
    [ -p "$DAY" ]
}

@test "KT-10 FR-6 the day file as a hard link to a victim (links 2) → victim bytes unchanged" {
    ln "$V/file" "$DAY"
    _warn_refused
    _victim_unchanged
}

@test "KT-11 FR-6 a group-writable regular day file → refused, its bytes unchanged" {
    printf 'prior\n' > "$DAY"
    chmod 664 "$DAY"
    _warn_refused
    [ "$(cat "$DAY")" = "prior" ]
}

@test "KT-12 FR-6 a replacement between two runs is refused on the second" {
    _warn_refused
    [ "$(wc -l < "$DAY")" -eq 1 ]
    mv "$DAY" "$V/moved"
    ln -s "$V/moved" "$DAY"
    _warn_refused
    [ "$(wc -l < "$V/moved")" -eq 1 ]
    [ "$(cat "$V/file")" = "victim-bytes" ]
}

@test "KT-13 FR-6 no realpath -m (BSD shim) → refused with the warning printed" {
    _shim realpath 'echo "realpath: illegal option -- m" >&2; exit 1'
    _warn_refused
    [ ! -e "$DAY" ]
}

@test "KT-14 FR-6 the warn path's own spawns on an existing directory: realpath x2 + one guard stat, no mkdir" {
    : > "$TMP_DIR/empty"
    local input fd
    input=$(jq -nc --arg c "$(printf 'a\nb\nc\nd\ne')" '{tool_name:"Write", tool_input:{file_path:"/tmp/x", content:$c}}')
    printf '%s\n' "$input" > "$TMP_DIR/in.json"
    exec {fd}>"$TMP_DIR/trace"
    env PS4='+' BASH_XTRACEFD="$fd" bash -x "$HOOK" < "$TMP_DIR/in.json" > /dev/null 2> "$TMP_DIR/stderr" || true
    exec {fd}>&-
    grep -q 'karpathy-surgical-warn' "$TMP_DIR/stderr"
    [ "$(wc -l < "$DAY")" -eq 1 ]
    local rp st mk
    rp="$(grep -cE '^\++ ?realpath ' "$TMP_DIR/trace" || true)"
    st="$(grep -cE "^\++ ?stat -Lc '%n\|%u\|%a\|%h' " "$TMP_DIR/trace" || true)"
    # (profile-lib's own cache-directory mkdir is not on the trajectory path: only a mkdir of TRAJ_DIR counts)
    mk="$(grep -cE "^\++ ?mkdir .*$M/grimoires" "$TMP_DIR/trace" || true)"
    echo "realpath=$rp guard-stat=$st mkdir=$mk" >&2
    [ "$rp" -eq 2 ]
    [ "$st" -eq 1 ]
    [ "$mk" -eq 0 ]
}
