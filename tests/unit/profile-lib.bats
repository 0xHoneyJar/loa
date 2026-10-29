#!/usr/bin/env bats
# =============================================================================
# tests/unit/profile-lib.bats — cycle-129 sprint-256 Task 2.7 (AC-2.9; PRD
# AC-9.1, AC-9.3; SDD D-9.1, D-9.3)
#
# .claude/data/profiles.yaml + .claude/scripts/lib/profile-lib.sh: precedence
# (explicit key > profile > fallback), every profile defines every key,
# `standard` equals the oracle captured before any reader changed
# (tests/fixtures/profiles/standard-oracle.json), unknown profile, the
# mtime-keyed cache, the overrides line, the /loa Profile line, the readers
# that route through loa_knob, and the grep lint for direct reads.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    # cycle-138 FR-1: the cache is read and written only in a directory without a group/other write bit, so
    # the fixtures must not inherit the host's umask (002 here: a 775 $T/run, 664 planted files).
    umask 022
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB="$R/.claude/scripts/lib/profile-lib.sh"
    PROFILES="$R/.claude/data/profiles.yaml"
    ORACLE="$R/tests/fixtures/profiles/standard-oracle.json"
    T="$BATS_TEST_TMPDIR"
    CFG="$T/config.yaml"
    export LOA_PROFILE_CONFIG_FILE="$CFG"
    export LOA_PROFILE_CACHE_FILE="$T/run/effective-config.json"
    : > "$CFG"
}

knob() { bash "$LIB" knob "$@"; }

@test "PL-1 every profile defines every key, and the key set is the nine optional keys" {
    run diff <(yq -r '.profiles.lean | keys | .[]' "$PROFILES" | sort) <(jq -r '.keys | keys[]' "$ORACLE" | sort)
    [ "$status" -eq 0 ]
    for p in standard full; do
        run diff <(yq -r ".profiles.$p | keys | .[]" "$PROFILES" | sort) <(yq -r '.profiles.lean | keys | .[]' "$PROFILES" | sort)
        [ "$status" -eq 0 ]
    done
    [ "$(yq -r '.profiles | keys | .[]' "$PROFILES" | sort | paste -sd, -)" = "full,lean,standard" ]
    [ "$(yq -r '.schema_version' "$PROFILES")" = "1" ]
    run bash -c "yq -r '.profiles[] | keys | .[]' '$PROFILES' | grep -qx 'interview.pacing'"
    [ "$status" -ne 0 ]
}

@test "PL-2 every profile value is a boolean; lean is all false and full all true" {
    [ "$(yq -r '[.profiles[][] | tag] | unique | .[]' "$PROFILES")" = "!!bool" ]
    [ "$(yq -r '[.profiles.lean[]] | unique | .[]' "$PROFILES")" = "false" ]
    [ "$(yq -r '[.profiles.full[]] | unique | .[]' "$PROFILES")" = "true" ]
}

@test "PL-3 standard equals the oracle captured before any reader changed" {
    local k want got
    while IFS= read -r k; do
        want=$(jq -r --arg k "$k" '.keys[$k].standard' "$ORACLE")
        got=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
        [ "$want" = "$got" ] || { echo "standard $k = $got, oracle $want"; return 1; }
    done < <(jq -r '.keys | keys[]' "$ORACLE")
    # Outside the two guardrail keys (whose default this cycle changes) the
    # oracle's standard IS the value the readers returned for the shipped example.
    run jq -r '.keys | to_entries[] | select(.key | startswith("guardrails.") | not)
               | select(.value.standard != .value.example_today) | .key' "$ORACLE"
    [ -z "$output" ]
    run jq -r '.keys | to_entries[] | select(.key | startswith("guardrails.")) | "\(.value.example_today)/\(.value.standard)"' "$ORACLE"
    [ "$output" = "$(printf 'true/false\ntrue/false')" ]
}

@test "PL-4 the example pins no profile key (r256-2): every key is null in the raw file and standard is its effective value" {
    local k ex st eff
    while IFS= read -r k; do
        # r256-2 (review round 2 HIGH-2): a copied example must follow loa.profile, so the
        # raw key is absent (a commented line) — an explicit key would beat every profile.
        ex=$(yq -r ".$k" "$R/.loa.config.yaml.example")
        [ "$ex" = "null" ] || { echo "example pins $k = $ex (must be commented: profile-governed)"; return 1; }
        st=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
        eff=$(LOA_PROFILE_CONFIG_FILE="$R/.loa.config.yaml.example" bash "$LIB" knob "$k" "unset")
        [ "$eff" = "$st" ] || { echo "effective $k under the example = $eff, standard $st"; return 1; }
    done < <(yq -r '.profiles.standard | keys | .[]' "$PROFILES")
    [ "$(yq -r '.loa.profile' "$R/.loa.config.yaml.example")" = "standard" ]
    # Under the example config the lib resolves standard and no override.
    LOA_PROFILE_CONFIG_FILE="$R/.loa.config.yaml.example" run bash "$LIB" overrides
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # A copy of the example under lean and full changes every key, with no override listed.
    local copy="$T/copy.yaml"
    for p in lean full; do
        sed "s/^  profile: standard /  profile: $p /" "$R/.loa.config.yaml.example" > "$copy"
        [ "$(yq -r '.loa.profile' "$copy")" = "$p" ]
        LOA_PROFILE_CONFIG_FILE="$copy" run bash "$LIB" overrides
        [ "$status" -eq 0 ]
        [ -z "$output" ]
        while IFS= read -r k; do
            eff=$(LOA_PROFILE_CONFIG_FILE="$copy" bash "$LIB" knob "$k" "unset")
            [ "$eff" = "$(yq -r ".profiles.$p[\"$k\"]" "$PROFILES")" ] || { echo "$p: $k = $eff"; return 1; }
        done < <(yq -r '.profiles.standard | keys | .[]' "$PROFILES")
    done
}

@test "PL-5 precedence: explicit key beats the profile, the profile beats the fallback" {
    printf 'loa:\n  profile: lean\nknown_failures:\n  surface_at_session_start: true\nkarpathy_principles:\n  diff_lines_per_task: 250\n' > "$CFG"
    [ "$(knob known_failures.surface_at_session_start false)" = "true" ]     # explicit
    [ "$(knob decisions.surface_at_session_start true)" = "false" ]          # lean, not the fallback
    [ "$(knob karpathy_principles.surgical_diff_warning true)" = "false" ]   # lean
    [ "$(knob karpathy_principles.diff_lines_per_task 100)" = "250" ]        # non-profile key, explicit
    [ "$(knob run_mode.stale_hours 7)" = "7" ]                               # non-profile key, fallback
    printf 'loa:\n  profile: full\n' > "$CFG"
    [ "$(knob decisions.surface_at_session_start false)" = "true" ]
    : > "$CFG"
    [ "$(bash "$LIB" profile)" = "standard" ]
    [ "$(bash "$LIB" source)" = "default" ]
    [ "$(knob karpathy_principles.surgical_diff_warning false)" = "true" ]   # standard, not the fallback
}

@test "PL-6 an explicit false is honoured (yq's // would read it as absent)" {
    printf 'loa:\n  profile: full\nguardrails:\n  input:\n    enabled: false\n  danger_level:\n    enforce: false\n' > "$CFG"
    [ "$(knob guardrails.input.enabled true)" = "false" ]
    [ "$(knob guardrails.danger_level.enforce true)" = "false" ]
    [ "$(knob .guardrails.input.enabled true)" = "false" ]                   # leading dot accepted
}

@test "PL-7 an unknown profile warns once on stderr and resolves standard" {
    printf 'loa:\n  profile: turbo\n' > "$CFG"
    run --separate-stderr bash "$LIB" profile
    [ "$status" -eq 0 ]
    [ "$output" = "standard" ]
    [[ "$stderr" == *'unknown loa.profile "turbo"; using standard'* ]]
    [ "$(bash "$LIB" source 2>/dev/null)" = "invalid" ]
    [ "$(knob karpathy_principles.require_success_criteria false 2>/dev/null)" = "true" ]
    # A non-string profile is unknown too.
    printf 'loa:\n  profile: [lean]\n' > "$CFG"
    [ "$(bash "$LIB" profile 2>/dev/null)" = "standard" ]
}

@test "PL-8 the cache is written once and rebuilt when the config or profiles.yaml changes" {
    printf 'loa:\n  profile: lean\n' > "$CFG"
    touch -d '2026-01-01 00:00:00' "$CFG"
    knob decisions.surface_at_session_start x >/dev/null
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    [ "$(jq -r '.profile' "$LOA_PROFILE_CACHE_FILE")" = "lean" ]
    # Same stamps → served from the cache: a planted value proves the read path.
    jq '.knobs["decisions.surface_at_session_start"].value = "from-cache"' "$LOA_PROFILE_CACHE_FILE" > "$T/c" && mv "$T/c" "$LOA_PROFILE_CACHE_FILE"
    [ "$(knob decisions.surface_at_session_start x)" = "from-cache" ]
    # A config edit with a new mtime rebuilds.
    printf 'loa:\n  profile: full\n' > "$CFG"
    touch -d '2026-01-02 00:00:00' "$CFG"
    [ "$(knob decisions.surface_at_session_start x)" = "true" ]
    [ "$(jq -r '.profile' "$LOA_PROFILE_CACHE_FILE")" = "full" ]
    # A profiles.yaml edit rebuilds too.
    cp "$PROFILES" "$T/profiles.yaml"
    export LOA_PROFILES_FILE="$T/profiles.yaml"
    knob decisions.surface_at_session_start x >/dev/null
    yq -i '.profiles.full["decisions.surface_at_session_start"] = false' "$T/profiles.yaml"
    touch -d '2026-01-03 00:00:00' "$T/profiles.yaml"
    [ "$(knob decisions.surface_at_session_start x)" = "false" ]
}

@test "PL-9 a corrupt or foreign cache file is rebuilt, never trusted" {
    mkdir -p "$T/run"
    echo 'not json' > "$LOA_PROFILE_CACHE_FILE"
    [ "$(knob karpathy_principles.surgical_diff_warning x)" = "true" ]
    jq -e '.schema_version == 1' "$LOA_PROFILE_CACHE_FILE" >/dev/null
    jq '.id = "other"' "$LOA_PROFILE_CACHE_FILE" > "$T/c" && mv "$T/c" "$LOA_PROFILE_CACHE_FILE"
    [ "$(knob karpathy_principles.surgical_diff_warning x)" = "true" ]
    [ "$(jq -r '.id' "$LOA_PROFILE_CACHE_FILE")" != "other" ]
}

@test "PL-10 a seam config without a cache seam writes no cache (the repository cache is never touched)" {
    unset LOA_PROFILE_CACHE_FILE
    mkdir -p "$T/root/.claude/data"
    cp "$PROFILES" "$T/root/.claude/data/profiles.yaml"
    LOA_PROFILE_ROOT="$T/root" run bash "$LIB" knob decisions.surface_at_session_start x
    [ "$output" = "false" ]
    [ ! -e "$T/root/.run/effective-config.json" ]
}

@test "PL-11 overrides lists the explicit profile keys that differ from the profile, sorted" {
    printf 'loa:\n  profile: lean\nguardrails:\n  input:\n    enabled: true\ndecisions:\n  surface_at_session_start: false\nstructured_handoff:\n  enabled: true\n' > "$CFG"
    run bash "$LIB" overrides
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'guardrails.input.enabled=true\nstructured_handoff.enabled=true')" ]
}

@test "PL-12 a profiles.yaml key that names a floor key is ignored with a WARN" {
    cp "$PROFILES" "$T/profiles.yaml"
    yq -i '.profiles.standard["implement_gate.mode"] = "deny" | .profiles.standard["flatline_protocol"] = false' "$T/profiles.yaml"
    export LOA_PROFILES_FILE="$T/profiles.yaml"
    run --separate-stderr bash "$LIB" knob implement_gate.mode ask
    [ "$output" = "ask" ]
    [[ "$stderr" == *"profiles.yaml key implement_gate.mode names a floor key; ignored"* ]]
    [[ "$stderr" == *"profiles.yaml key flatline_protocol names a floor key; ignored"* ]]
    [ "$(jq -r '.profile_keys | index("implement_gate.mode")' "$LOA_PROFILE_CACHE_FILE")" = "null" ]
}

@test "PL-13 a malformed key path returns 2 with the fallback and never reaches yq" {
    printf 'a: 1\n' > "$CFG"
    run bash "$LIB" knob '.a | env' fb
    [ "$status" -eq 2 ]
    [[ "$output" == *"fb"* ]]
    run bash "$LIB" knob 'a;b' fb
    [ "$status" -eq 2 ]
}

@test "PL-14 the /loa Profile line prints the profile and the explicit overrides" {
    printf 'loa:\n  profile: lean\nguardrails:\n  input:\n    enabled: true\n' > "$CFG"
    unset LOA_PROFILE_CONFIG_FILE
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
    # The line says so when a guardrail control resolves to off (audit r256-5, DEC-0161 mitigation):
    # under lean with input pinned on, only the danger-level enforcement is off.
    [ "$line" = "Profile: lean (explicit overrides: guardrails.input.enabled=true) · danger-level enforcement off" ]
    : > "$CFG"
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
    [ "$line" = "Profile: standard (explicit overrides: none) · input guardrails off, danger-level enforcement off" ]
    # Under full both controls are on and the line carries no notice.
    printf 'loa:\n  profile: full\n' > "$CFG"
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
    [ "$line" = "Profile: full (explicit overrides: none)" ]
}

@test "PL-15 the guardrail readers route through loa_knob (knob on and off)" {
    printf 'guardrails:\n  input:\n    enabled: false\n' > "$CFG"
    run bash "$R/.claude/scripts/guardrails-orchestrator.sh" --skill implementing-tasks --input "Implement feature X"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.reason')" = "guardrails disabled in config" ]
    printf 'guardrails:\n  input:\n    enabled: true\n' > "$CFG"
    run bash "$R/.claude/scripts/guardrails-orchestrator.sh" --skill implementing-tasks --input "Implement feature X"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.reason')" != "guardrails disabled in config" ]
    printf 'guardrails:\n  danger_level:\n    enforce: false\n' > "$CFG"
    run bash "$R/.claude/scripts/danger-level-enforcer.sh" --skill deploying-infrastructure --mode autonomous
    [[ "$output" == *"danger level enforcement disabled in config"* ]]
    printf 'guardrails:\n  danger_level:\n    enforce: true\n' > "$CFG"
    run bash "$R/.claude/scripts/danger-level-enforcer.sh" --skill deploying-infrastructure --mode autonomous
    [[ "$output" != *"danger level enforcement disabled in config"* ]]
}

@test "PL-16 the SessionStart readers resolve their enable key through the profile" {
    # `full` turns the decisions and KF surfaces on without their keys; an
    # explicit false beats the profile; `standard` leaves them off.
    printf 'loa:\n  profile: full\n' > "$CFG"
    run bash "$R/.claude/hooks/session-start/loa-decisions-surface.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DECISIONS]"* ]]
    run bash "$R/.claude/hooks/loa-kf-surface.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[KF-SURFACE]"* ]]
    printf 'loa:\n  profile: full\ndecisions:\n  surface_at_session_start: false\nknown_failures:\n  surface_at_session_start: false\n' > "$CFG"
    run bash "$R/.claude/hooks/session-start/loa-decisions-surface.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash "$R/.claude/hooks/loa-kf-surface.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    : > "$CFG"
    run bash "$R/.claude/hooks/session-start/loa-decisions-surface.sh"
    [ -z "$output" ]
    # Each SessionStart reader sources the lib and names its key in loa_knob.
    for pair in "loa-kf-surface.sh:known_failures.surface_at_session_start" \
                "session-start/loa-decisions-surface.sh:decisions.surface_at_session_start" \
                "session-start/loa-l6-surface-handoffs.sh:structured_handoff.enabled" \
                "session-start/loa-l7-surface-soul.sh:soul_identity_doc.enabled"; do
        grep -q "scripts/lib/profile-lib.sh" "$R/.claude/hooks/${pair%%:*}"
        grep -q "loa_knob ${pair#*:} " "$R/.claude/hooks/${pair%%:*}"
    done
}

@test "PL-17 the grep lint passes on the tree and catches a planted direct read" {
    run bash "$R/tools/check-knob-readers.sh" --root "$R"
    echo "$output"
    [ "$status" -eq 0 ]
    mkdir -p "$T/fx/.claude/data" "$T/fx/.claude/hooks" "$T/fx/tools"
    cp "$PROFILES" "$T/fx/.claude/data/profiles.yaml"
    printf '%s\n' "x=\$(yq '.guardrails.danger_level.enforce // true' c.yaml)" > "$T/fx/.claude/hooks/bad.sh"
    printf '%s\n' 'Skip when `guardrails.danger_level.enforce: false`.' > "$T/fx/.claude/hooks/prose.md"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.sh:1"* ]]
    [[ "$output" != *"prose.md"* ]]
    # Bypass shapes (audit r256-5, DISS-C-005): a read split across a pipe and a bracket
    # form that ends in the dotted tail are caught through the trailing-components alternation.
    rm -f -- "$T/fx/.claude/hooks/bad.sh"
    printf '%s\n' "y=\$(yq '.guardrails | .input.enabled' c.yaml)" > "$T/fx/.claude/hooks/pipe.sh"
    printf '%s\n' "z=\$(yq '.[\"guardrails\"].danger_level.enforce' c.yaml)" > "$T/fx/.claude/hooks/bracket.sh"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pipe.sh:1"* ]]
    [[ "$output" == *"bracket.sh:1"* ]]
    # A fixture root without tools/ is searched without a misleading exit 2 (r256-3).
    rm -rf -- "$T/fx/tools" "$T/fx/.claude/hooks/pipe.sh" "$T/fx/.claude/hooks/bracket.sh"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 0 ]
}

@test "PL-18 the fixture exclusion is anchored to a skill's __tests__/fixtures root (Sprint 272, DISS-C-008)" {
    mkdir -p "$T/fx/.claude/data" "$T/fx/.claude/hooks/tests/fixtures" "$T/fx/.claude/skills/demo/resources/__tests__/fixtures" "$T/fx/tools"
    cp "$PROFILES" "$T/fx/.claude/data/profiles.yaml"
    # a recorded payload under a skill's fixture root may quote a direct read: excluded
    printf '%s\n' "the thread read \$(yq '.soul_identity_doc.enabled // false' c.yaml) here" > "$T/fx/.claude/skills/demo/resources/__tests__/fixtures/thread.md"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 0 ]
    # a reader smuggled under a tests/fixtures/ directory anywhere else is still caught
    printf '%s\n' "x=\$(yq '.guardrails.danger_level.enforce // true' c.yaml)" > "$T/fx/.claude/hooks/tests/fixtures/pre-tool.sh"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 1 ]
    [[ "$output" == *"hooks/tests/fixtures/pre-tool.sh:1"* ]]
    [[ "$output" != *"thread.md"* ]]
    rm -rf -- "$T/fx/tools"
}

@test "PL-19 the fixture exclusion covers data files only: a .sh reader under a skill fixtures dir is caught (Sprint 272 audit, DISS-C-003)" {
    mkdir -p "$T/fx/.claude/data" "$T/fx/.claude/skills/demo/resources/__tests__/fixtures" "$T/fx/tools"
    cp "$PROFILES" "$T/fx/.claude/data/profiles.yaml"
    printf '%s\n' "the thread read \$(yq '.soul_identity_doc.enabled // false' c.yaml) here" > "$T/fx/.claude/skills/demo/resources/__tests__/fixtures/thread.md"
    printf '%s\n' "x=\$(yq '.guardrails.danger_level.enforce // true' c.yaml)" > "$T/fx/.claude/skills/demo/resources/__tests__/fixtures/helper.sh"
    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fixtures/helper.sh:1"* ]]
    [[ "$output" != *"thread.md"* ]]
    rm -rf -- "$T/fx/tools"
}

# ---- cycle-137 FR-4 (Task 2.4, bd-h5tcn): non-profile hot knobs listed in profiles.yaml `cached_keys` ----
_pl20_trace() {  # <args to profile-lib.sh> → stdout; xtrace on a dedicated descriptor (a 2>/dev/null inside cannot hide a spawn) → $T/trace
    local xfd out
    exec {xfd}>"$T/trace"
    out=$(env PS4='+' BASH_XTRACEFD="$xfd" SHELLOPTS=xtrace bash "$LIB" "$@" 2>/dev/null)   # (env: SHELLOPTS is readonly here)
    grep -q '^+' "$T/trace" || { echo "the trace is empty — the tracer did not run" >&2; return 1; }
    exec {xfd}>&-
    printf '%s\n' "$out"
}
_pl20_yq_lines() { grep -cE '^\++ ?([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(/[^ ]*/)?yq( |$)' "$T/trace" || true; }
_pl20_live() {  # <key> <fallback> → what the LIVE read (_loa_pl_live) prints for the current config
    bash -c 'source "$1"; _loa_pl_paths; _loa_pl_live "$2" "$3"' _ "$LIB" "$1" "$2"
}

@test "PL-20 (cycle-137 FR-4) warm cache, a cached key absent from the config: the fallback, and NO yq on the read" {
    printf 'loa:\n  profile: standard\n' > "$CFG"
    knob karpathy_principles.diff_lines_per_task 100 >/dev/null   # builds the cache
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    out=$(_pl20_trace knob karpathy_principles.diff_lines_per_task 100)
    [ "$out" = 100 ] || { echo "got '$out'"; return 1; }
    [ "$(_pl20_yq_lines)" = 0 ] || { echo "yq ran on the warm read:"; grep -E 'yq' "$T/trace"; return 1; }
    jq -e '.knobs["karpathy_principles.diff_lines_per_task"] == {value: null, source: "absent", profile_value: null}' "$LOA_PROFILE_CACHE_FILE" >/dev/null \
        || { jq -c '.knobs["karpathy_principles.diff_lines_per_task"]' "$LOA_PROFILE_CACHE_FILE"; return 1; }
    # (and in the same shell: the in-memory path answers the fallback without yq as well)
    run bash -c 'source "$1"; loa_profile >/dev/null; loa_knob karpathy_principles.diff_lines_per_task 100' _ "$LIB"
    [ "$output" = 100 ]
}

@test "PL-21 (cycle-137 FR-4) an explicit value of a cached key wins on the warm path, without yq" {
    printf 'karpathy_principles:\n  diff_lines_per_task: 42\n' > "$CFG"
    knob karpathy_principles.diff_lines_per_task 100 >/dev/null
    out=$(_pl20_trace knob karpathy_principles.diff_lines_per_task 100)
    [ "$out" = 42 ]
    [ "$(_pl20_yq_lines)" = 0 ] || { grep -E 'yq' "$T/trace"; return 1; }
}

@test "PL-22 (cycle-137 FR-4) classification: the warm read of a cached key prints exactly what the live read prints" {
    local v want got n=0
    while IFS= read -r v; do
        n=$((n + 1))
        printf 'karpathy_principles:\n  diff_lines_per_task: %s\n' "$v" > "$CFG"
        touch -d "@$(( 1790000000 + n ))" "$CFG"
        want=$(_pl20_live karpathy_principles.diff_lines_per_task FB)
        knob karpathy_principles.diff_lines_per_task FB >/dev/null   # build
        got=$(knob karpathy_principles.diff_lines_per_task FB)       # warm
        [ "$got" = "$want" ] || { echo "value <$v>: warm '$got', live '$want'"; return 1; }
    done <<'VALUES'
null
~
""
''
false
true
0
42
-7
1.0
1.50
1e3
0x10
0o17
.5
100000000000000000001
"null"
"__LOA_PL_MISS__"
" padded "
{a: 1, b: [x, y]}
[]
{}
[1, "two", {three: 3}]
"line one\nline two\n"
|
VALUES
    # the multi-line block scalar, a merge key and an anchor
    printf 'karpathy_principles:\n  diff_lines_per_task: |\n    alpha\n    beta\n' > "$CFG"; touch -d '@1790001000' "$CFG"
    want=$(_pl20_live karpathy_principles.diff_lines_per_task FB); knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = "$want" ] || { echo "block scalar"; return 1; }
    printf 'base: &b\n  diff_lines_per_task: 77\nkarpathy_principles:\n  <<: *b\n' > "$CFG"; touch -d '@1790001001' "$CFG"
    want=$(_pl20_live karpathy_principles.diff_lines_per_task FB); knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = "$want" ] || { echo "merge key: live '$want'"; return 1; }
    printf 'n: &n 33\nkarpathy_principles:\n  diff_lines_per_task: *n\n' > "$CFG"; touch -d '@1790001002' "$CFG"
    want=$(_pl20_live karpathy_principles.diff_lines_per_task FB); knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = "$want" ] || { echo "anchor: live '$want'"; return 1; }
    # a non-mapping ancestor, and a config that does not parse
    printf 'karpathy_principles: 5\n' > "$CFG"; touch -d '@1790001003' "$CFG"
    want=$(_pl20_live karpathy_principles.diff_lines_per_task FB); knob karpathy_principles.diff_lines_per_task FB >/dev/null 2>&1
    [ "$(knob karpathy_principles.diff_lines_per_task FB 2>/dev/null)" = "$want" ] || { echo "scalar ancestor: live '$want'"; return 1; }
    printf 'karpathy_principles: [unclosed\n' > "$CFG"; touch -d '@1790001004' "$CFG"
    want=$(_pl20_live karpathy_principles.diff_lines_per_task FB); knob karpathy_principles.diff_lines_per_task FB >/dev/null 2>&1
    [ "$(knob karpathy_principles.diff_lines_per_task FB 2>/dev/null)" = "$want" ] || { echo "unparsable: live '$want'"; return 1; }
    # the named classes, as the brief states them
    printf 'karpathy_principles:\n  diff_lines_per_task: null\n' > "$CFG"; touch -d '@1790001005' "$CFG"; knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = FB ]
    printf 'karpathy_principles:\n  diff_lines_per_task: ""\n' > "$CFG"; touch -d '@1790001006' "$CFG"; knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = FB ]
    printf 'karpathy_principles:\n  diff_lines_per_task: false\n' > "$CFG"; touch -d '@1790001007' "$CFG"; knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = false ]
    printf 'karpathy_principles:\n  diff_lines_per_task: 0\n' > "$CFG"; touch -d '@1790001008' "$CFG"; knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = 0 ]
    printf 'karpathy_principles:\n  diff_lines_per_task: {b: 2, a: 1}\n' > "$CFG"; touch -d '@1790001009' "$CFG"; knob karpathy_principles.diff_lines_per_task FB >/dev/null
    [ "$(knob karpathy_principles.diff_lines_per_task FB)" = '{"b":2,"a":1}' ]
}

@test "PL-23 (cycle-137 FR-4) a cache without the knob entry (an older profiles.yaml) reads live; a stale id rebuilds" {
    printf 'karpathy_principles:\n  diff_lines_per_task: 250\n' > "$CFG"
    knob karpathy_principles.diff_lines_per_task 100 >/dev/null
    jq -c 'del(.knobs["karpathy_principles.diff_lines_per_task"])' "$LOA_PROFILE_CACHE_FILE" > "$T/c" && mv "$T/c" "$LOA_PROFILE_CACHE_FILE"
    out=$(_pl20_trace knob karpathy_principles.diff_lines_per_task 100)
    [ "$out" = 250 ]
    [ "$(_pl20_yq_lines)" -ge 1 ] || { echo "the entry-less cache did not take the live read"; return 1; }
    jq -c '.id = "v1|stale"' "$LOA_PROFILE_CACHE_FILE" > "$T/c" && mv "$T/c" "$LOA_PROFILE_CACHE_FILE"
    [ "$(knob karpathy_principles.diff_lines_per_task 100)" = 250 ]
    [ "$(jq -r '.id' "$LOA_PROFILE_CACHE_FILE")" != "v1|stale" ]
    jq -e '.knobs["karpathy_principles.diff_lines_per_task"] == {value: 250, source: "explicit", profile_value: null}' "$LOA_PROFILE_CACHE_FILE" >/dev/null
}

@test "PL-24 (cycle-137 FR-4) cached_keys changes no profile answer: profile, source, overrides, profile_keys; the cache differs only by the knob entry" {
    printf 'loa:\n  profile: lean\nguardrails:\n  input:\n    enabled: true\nkarpathy_principles:\n  diff_lines_per_task: 9\n' > "$CFG"
    cp "$PROFILES" "$T/without.yaml"; yq -i 'del(.cached_keys)' "$T/without.yaml"
    local which
    for which in without with; do
        if [[ "$which" == without ]]; then export LOA_PROFILES_FILE="$T/without.yaml"; else export LOA_PROFILES_FILE="$PROFILES"; fi
        export LOA_PROFILE_CACHE_FILE="$T/run/cache-$which.json"
        { bash "$LIB" profile; bash "$LIB" source; bash "$LIB" overrides; bash "$LIB" json | jq -c .profile_keys; } > "$T/answers-$which" 2>&1
    done
    cmp "$T/answers-without" "$T/answers-with" || { diff "$T/answers-without" "$T/answers-with"; return 1; }
    diff <(jq -S 'del(.id)' "$T/run/cache-without.json") \
         <(jq -S 'del(.id) | del(.knobs["karpathy_principles.diff_lines_per_task"])' "$T/run/cache-with.json") \
        || { echo "the caches differ beyond the knob entry"; return 1; }
    # (and the lean profile's keys are untouched by the cached key)
    [ "$(jq -r '.profile_keys | index("karpathy_principles.diff_lines_per_task")' "$T/run/cache-with.json")" = null ]
}

@test "PL-25 (cycle-137 FR-4) a cached key that is a profile key or a floor key is not cached as non-profile; the floor one warns" {
    cp "$PROFILES" "$T/profiles.yaml"
    yq -i '.cached_keys += ["karpathy_principles.surgical_diff_warning", "implement_gate.mode"]' "$T/profiles.yaml"
    export LOA_PROFILES_FILE="$T/profiles.yaml"
    printf 'loa:\n  profile: lean\n' > "$CFG"
    run --separate-stderr bash "$LIB" knob karpathy_principles.surgical_diff_warning true
    [ "$output" = false ]   # the lean profile value, not "absent"
    [[ "$stderr" == *"profiles.yaml key implement_gate.mode names a floor key; ignored"* ]] || { echo "stderr=$stderr"; return 1; }
    jq -e '.knobs["karpathy_principles.surgical_diff_warning"].source == "profile" and (.knobs | has("implement_gate.mode") | not)' "$LOA_PROFILE_CACHE_FILE" >/dev/null
    [ "$(bash "$LIB" knob implement_gate.mode ask 2>/dev/null)" = ask ]
}

# ---- cycle-138 FR-1 (Task 1.4, bd-j34zb): the profile cache trust predicate — REFUSE, never chmod ----
# Fixtures: $T/run is the seam's directory (setup); the writer creates it 0700 when absent. Shims on PATH:
# a `stat` that rewrites the trailing mode/uid/links fields of one path's GNU row (grimoire-index.bats
# technique; a row with another shape passes through), a recording `chmod`, an `mv` without -T (BSD).
_pl_state() { bash -c 'source "$1"; loa_profile_cache_state' _ "$LIB"; }
_pl_want() { env LOA_PROFILE_CACHE_FILE= bash "$LIB" knob "$@" 2>/dev/null; }   # the resolution with no cache at all
_pl_shims() {   # writes $T/shim/{stat,chmod,mv}; select them per command with PATH="$T/shim:$PATH"
    mkdir -p "$T/shim"
    local real_stat real_chmod real_mv
    real_stat=$(command -v stat); real_chmod=$(command -v chmod); real_mv=$(command -v mv)
    cat > "$T/shim/stat" <<EOF
#!/usr/bin/env bash
out=\$("$real_stat" "\$@"); rc=\$?
[[ -z "\$out" ]] || printf '%s\n' "\$out" | awk -F'|' -v OFS='|' -v p="\${SHIM_PATH:-}" -v m="\${SHIM_MODE:-}" -v u="\${SHIM_UID:-}" -v l="\${SHIM_LINKS:-}" \\
  '\$1 == p && NF == 6 { if (m != "") \$4 = m; if (u != "") \$5 = u; if (l != "") \$6 = l } 1'
exit \$rc
EOF
    cat > "$T/shim/chmod" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/chmod.log"
exec "$real_chmod" "\$@"
EOF
    cat > "$T/shim/mv" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" != -T ]] || { echo "mv: illegal option -- T" >&2; exit 1; }; done
exec "$real_mv" "\$@"
EOF
    "$real_chmod" +x "$T/shim/stat" "$T/shim/chmod" "$T/shim/mv"
}
# _pl_planted: build the cache under a trusted $T/run, then plant a valid cache whose knob says "from-cache"
# (right id, schema 1) — a read of it prints from-cache. Its bytes are kept in $T/planted.
_pl_planted() {
    knob decisions.surface_at_session_start x >/dev/null
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    jq -c '.knobs["decisions.surface_at_session_start"].value = "from-cache"' "$LOA_PROFILE_CACHE_FILE" > "$T/planted"
    chmod 600 "$T/planted"
    cp "$T/planted" "$LOA_PROFILE_CACHE_FILE"
    [ "$(knob decisions.surface_at_session_start x)" = "from-cache" ]   # (the trusted read path works)
}

@test "PL-26 (cycle-138 FR-1) a .run owned by another uid (stat shim) is neither read nor written; the knob equals the live read" {
    _pl_shims; _pl_planted
    want=$(_pl_want decisions.surface_at_session_start x)
    got=$(PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_UID=4242 bash "$LIB" knob decisions.surface_at_session_start x)
    [ "$got" = "$want" ] || { echo "foreign .run: got '$got', live '$want'"; return 1; }
    cmp "$T/planted" "$LOA_PROFILE_CACHE_FILE"                      # not rewritten
    [ "$(PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_UID=4242 _pl_state)" = "off (dir-foreign)" ]
    rm -f "$LOA_PROFILE_CACHE_FILE"
    PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_UID=4242 bash "$LIB" knob decisions.surface_at_session_start x >/dev/null
    [ ! -e "$LOA_PROFILE_CACHE_FILE" ] || { echo "a cache was written into a foreign .run"; return 1; }
}

@test "PL-27 (cycle-138 FR-1) a group-writable uid-owned .run is REFUSED: no chmod issued, mode unchanged, off (dir-writable); go-w turns it on" {
    _pl_shims; _pl_planted
    chmod 775 "$T/run"
    want=$(_pl_want decisions.surface_at_session_start x)
    got=$(PATH="$T/shim:$PATH" bash "$LIB" knob decisions.surface_at_session_start x)
    [ "$got" = "$want" ]
    [ ! -e "$T/chmod.log" ] || { echo "profile-lib issued chmod: $(cat "$T/chmod.log")"; return 1; }
    [ "$(stat -c %a "$T/run")" = 775 ]
    cmp "$T/planted" "$LOA_PROFILE_CACHE_FILE"
    [ "$(PATH="$T/shim:$PATH" _pl_state)" = "off (dir-writable)" ]
    [ ! -e "$T/chmod.log" ]
    # the repair (grimoire-index.sh's _gi_trusted_dir tightens a uid-owned .run — PL-28 runs it) turns it on
    chmod go-w "$T/run"
    [ "$(_pl_state)" = on ]
    [ "$(knob decisions.surface_at_session_start x)" = "from-cache" ]
}

@test "PL-28 (cycle-138 FR-1) a 775 .run is off before and on after one grimoire-index.sh run (the repair owner)" {
    command -v yq >/dev/null && yq --version 2>&1 | grep -q 'version v4' || skip "mikefarah yq v4 needed by grimoire-index"
    local root="$T/root"
    mkdir -p "$root/grimoires/loa" "$root/x/y" "$root/.run"
    cp "$R/.claude/scripts/grimoire-index.sh" "$R/.claude/scripts/compat-lib.sh" "$root/x/y/"
    printf 'schema_version: 1\ndecisions:\n  - id: "DEC-0001"\n    status: open\n    summary: "fixture"\n    source: "prd.md#fr-1"\n    proposed_by: agent\n' > "$root/grimoires/loa/decisions.yaml"
    export LOA_PROFILE_CACHE_FILE="$root/.run/effective-config.json"
    chmod 700 "$root/.run"
    knob decisions.surface_at_session_start x >/dev/null
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    chmod 775 "$root/.run"
    [ "$(_pl_state)" = "off (dir-writable)" ]
    env -u CI -u GITHUB_ACTIONS -u LOA_GRIMOIRE_INDEX_NO_CACHE bash "$root/x/y/grimoire-index.sh" --tsv >/dev/null
    [ "$(stat -c %a "$root/.run")" = 755 ] || { echo "grimoire-index did not tighten .run: $(stat -c %a "$root/.run")"; return 1; }
    [ "$(_pl_state)" = on ]
}

@test "PL-29 (cycle-138 FR-1) an absent .run is created 0700 by the writer and the cache file 0600 (mkdir, no -p)" {
    [ ! -e "$T/run" ]
    knob decisions.surface_at_session_start x >/dev/null
    [ "$(stat -c %a "$T/run")" = 700 ]
    [ "$(stat -c %a "$LOA_PROFILE_CACHE_FILE")" = 600 ]
    [ "$(_pl_state)" = on ]
    # a missing parent is not created (no -p): the cache is simply off
    export LOA_PROFILE_CACHE_FILE="$T/a/b/effective-config.json"
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    [ ! -e "$T/a" ]
    [ "$(_pl_state)" = "off (dir-absent)" ]
}

@test "PL-30 (cycle-138 FR-1) a symlink at the cache path is not read, its target keeps its bytes, and the next write replaces the link" {
    _pl_planted
    cp "$T/planted" "$T/victim"
    ln -sf "$T/victim" "$LOA_PROFILE_CACHE_FILE"
    [ "$(_pl_state)" = "off (file-untrusted)" ]
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]       # not from-cache
    cmp "$T/planted" "$T/victim"
    [ -f "$LOA_PROFILE_CACHE_FILE" ] && [ ! -L "$LOA_PROFILE_CACHE_FILE" ] || { ls -la "$T/run"; return 1; }
    [ "$(_pl_state)" = on ]
    # a dangling symlink is untrusted too (no stat row, but something is there)
    rm -f "$LOA_PROFILE_CACHE_FILE"; ln -s "$T/nowhere" "$LOA_PROFILE_CACHE_FILE"
    [ "$(_pl_state)" = "off (file-untrusted)" ]
    knob decisions.surface_at_session_start x >/dev/null
    [ ! -e "$T/nowhere" ]
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    [ ! -L "$LOA_PROFILE_CACHE_FILE" ]
}

@test "PL-31 (cycle-138 FR-1) a directory at the cache path is neither read nor replaced; no temp file is left behind" {
    mkdir -p "$T/run"; chmod 700 "$T/run"; mkdir "$LOA_PROFILE_CACHE_FILE"
    [ "$(_pl_state)" = "off (file-untrusted)" ]
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    [ -d "$LOA_PROFILE_CACHE_FILE" ]
    [ -z "$(ls -A "$LOA_PROFILE_CACHE_FILE")" ] || { echo "something was written into the directory: $(ls -A "$LOA_PROFILE_CACHE_FILE")"; return 1; }
    [ "$(ls -A "$T/run")" = "effective-config.json" ] || { ls -la "$T/run"; return 1; }
}

@test "PL-32 (cycle-138 FR-1) a FIFO at the cache path is never opened and is replaced by a regular file" {
    mkdir -p "$T/run"; chmod 700 "$T/run"; mkfifo "$LOA_PROFILE_CACHE_FILE"
    run timeout 5 bash "$LIB" knob decisions.surface_at_session_start x
    [ "$status" -eq 0 ] || { echo "status $status (124 = blocked on the FIFO)"; return 1; }
    [ "$output" = "$(_pl_want decisions.surface_at_session_start x)" ]
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    [ ! -p "$LOA_PROFILE_CACHE_FILE" ]
    mkfifo "$T/run/fifo2"; rm -f "$LOA_PROFILE_CACHE_FILE"; mv "$T/run/fifo2" "$LOA_PROFILE_CACHE_FILE"
    run timeout 5 bash -c 'source "$1"; loa_profile_cache_state' _ "$LIB"
    [ "$status" -eq 0 ]
    [ "$output" = "off (file-untrusted)" ]
}

@test "PL-33 (cycle-138 FR-1) a hard-linked cache (links 2) is not read and is replaced on write; the other name keeps its bytes" {
    _pl_planted
    rm -f "$LOA_PROFILE_CACHE_FILE"; cp "$T/planted" "$T/victim"; ln "$T/victim" "$LOA_PROFILE_CACHE_FILE"
    [ "$(_pl_state)" = "off (file-untrusted)" ]
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    cmp "$T/planted" "$T/victim"
    [ "$(stat -c %h "$LOA_PROFILE_CACHE_FILE")" = 1 ]
    [ "$(stat -c %h "$T/victim")" = 1 ]
    [ "$(_pl_state)" = on ]
}

@test "PL-34 (cycle-138 FR-1) a planted group-writable file is not read and is replaced 0600" {
    _pl_planted
    chmod 664 "$LOA_PROFILE_CACHE_FILE"
    [ "$(_pl_state)" = "off (file-untrusted)" ]
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    [ "$(stat -c %a "$LOA_PROFILE_CACHE_FILE")" = 600 ]
    [ "$(jq -r '.knobs["decisions.surface_at_session_start"].value' "$LOA_PROFILE_CACHE_FILE")" = "$(_pl_want decisions.surface_at_session_start x)" ]
}

@test "PL-35 (cycle-138 FR-1) malformed stat rows are refused before any arithmetic (mode abc, uid x, links 1a)" {
    _pl_shims; _pl_planted
    run --separate-stderr env PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_MODE=abc bash -c 'source "$1"; loa_profile_cache_state; loa_knob decisions.surface_at_session_start x' _ "$LIB"
    [ "$status" -eq 0 ] && [ -z "$stderr" ] || { echo "status $status stderr=$stderr"; return 1; }
    [ "$output" = "$(printf 'off (dir-stat)\n%s' "$(_pl_want decisions.surface_at_session_start x)")" ] || { echo "$output"; return 1; }
    run --separate-stderr env PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_UID=x bash -c 'source "$1"; loa_profile_cache_state' _ "$LIB"
    [ "$output" = "off (dir-stat)" ]
    [ -z "$stderr" ]
    cmp "$T/planted" "$LOA_PROFILE_CACHE_FILE"                      # a refused directory: not read, not written
    # a malformed FILE row: not read (and, the directory being trusted, replaced by the rebuild — PL-34)
    run --separate-stderr env PATH="$T/shim:$PATH" SHIM_PATH="$LOA_PROFILE_CACHE_FILE" SHIM_MODE='6;0' bash -c 'source "$1"; loa_profile_cache_state; loa_knob decisions.surface_at_session_start x' _ "$LIB"
    [ "$output" = "$(printf 'off (file-untrusted)\n%s' "$(_pl_want decisions.surface_at_session_start x)")" ] && [ -z "$stderr" ] || { echo "$output / $stderr"; return 1; }
    run --separate-stderr env PATH="$T/shim:$PATH" SHIM_PATH="$LOA_PROFILE_CACHE_FILE" SHIM_LINKS=1a bash -c 'source "$1"; loa_profile_cache_state' _ "$LIB"
    [ "$output" = "off (file-untrusted)" ]
    [ -z "$stderr" ]
}

@test "PL-36 (cycle-138 FR-1) the mv fallback (no -T, BSD) writes the cache and still refuses a directory at the cache path" {
    _pl_shims
    PATH="$T/shim:$PATH" bash "$LIB" knob decisions.surface_at_session_start x >/dev/null
    [ -f "$LOA_PROFILE_CACHE_FILE" ]
    [ "$(stat -c %a "$LOA_PROFILE_CACHE_FILE")" = 600 ]
    rm -f "$LOA_PROFILE_CACHE_FILE"; mkdir "$LOA_PROFILE_CACHE_FILE"
    PATH="$T/shim:$PATH" bash "$LIB" knob decisions.surface_at_session_start x >/dev/null
    [ -d "$LOA_PROFILE_CACHE_FILE" ]
    [ -z "$(ls -A "$LOA_PROFILE_CACHE_FILE")" ]
    [ "$(ls -A "$T/run")" = "effective-config.json" ] || { ls -la "$T/run"; return 1; }
}

@test "PL-37 (cycle-138 FR-1) a .run replaced between calls (by a symlink, then a 775 directory) is refused on the next call" {
    _pl_planted
    mv "$T/run" "$T/run.real"; ln -s "$T/run.real" "$T/run"
    [ "$(_pl_state)" = "off (dir-not-plain)" ]
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    cmp "$T/planted" "$T/run.real/effective-config.json"
    rm "$T/run"; mkdir "$T/run"; chmod 775 "$T/run"; cp "$T/planted" "$T/run/effective-config.json"; chmod 600 "$T/run/effective-config.json"
    [ "$(knob decisions.surface_at_session_start x)" = "$(_pl_want decisions.surface_at_session_start x)" ]
    cmp "$T/planted" "$T/run/effective-config.json"
}

@test "PL-38 (cycle-138 FR-1) loa_profile_cache_state: one exact line per reason" {
    _pl_shims
    unset LOA_PROFILE_CACHE_FILE
    [ "$(_pl_state)" = "off (no-cache-path)" ]
    export LOA_PROFILE_CACHE_FILE="$T/run/effective-config.json"
    [ "$(_pl_state)" = "off (dir-absent)" ]
    ln -s "$T/nowhere" "$T/run"
    [ "$(_pl_state)" = "off (dir-stat)" ]
    rm "$T/run"; mkdir "$T/real"; chmod 700 "$T/real"; ln -s "$T/real" "$T/run"
    [ "$(_pl_state)" = "off (dir-not-plain)" ]
    rm "$T/run"; : > "$T/run"
    [ "$(_pl_state)" = "off (dir-not-plain)" ]
    rm "$T/run"; mkdir "$T/run"; chmod 700 "$T/run"
    [ "$(PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_UID=4242 _pl_state)" = "off (dir-foreign)" ]
    chmod 770 "$T/run"
    [ "$(_pl_state)" = "off (dir-writable)" ]
    chmod 702 "$T/run"
    [ "$(_pl_state)" = "off (dir-writable)" ]
    chmod 700 "$T/run"
    [ "$(_pl_state)" = "off (file-absent)" ]
    knob decisions.surface_at_session_start x >/dev/null
    [ "$(_pl_state)" = on ]
    [ "$(PATH="$T/shim:$PATH" SHIM_PATH="$LOA_PROFILE_CACHE_FILE" SHIM_UID=4242 _pl_state)" = "off (file-untrusted)" ]
    # dir-symlinked-component: a redirected cache OUTSIDE bats (marker unset) under a symlinked component
    mkdir -p "$T/root/real-run"; chmod 700 "$T/root/real-run"; ln -s "$T/root/real-run" "$T/root/link"
    run --separate-stderr env -u BATS_TEST_FILENAME -u BATS_VERSION LOA_PROFILE_ROOT="$T/root" \
        LOA_PROFILE_CACHE_FILE="$T/root/link/sub/effective-config.json" bash -c 'mkdir -m 700 "$2"; source "$1"; loa_profile_cache_state' _ "$LIB" "$T/root/real-run/sub"
    [ "$output" = "off (dir-symlinked-component)" ] || { echo "got '$output'"; return 1; }
    # an ABSENT directory under the symlinked component is refused the same way and never created by the writer
    run --separate-stderr env -u BATS_TEST_FILENAME -u BATS_VERSION LOA_PROFILE_ROOT="$T/root" \
        LOA_PROFILE_CACHE_FILE="$T/root/link/new/effective-config.json" bash -c 'source "$1"; loa_profile_cache_state; loa_knob decisions.surface_at_session_start x >/dev/null' _ "$LIB"
    [ "$output" = "off (dir-symlinked-component)" ] || { echo "got '$output'"; return 1; }
    [ ! -e "$T/root/real-run/new" ] || { echo "the writer created a directory through the symlinked component"; return 1; }
    # (the same directory reached without the symlink is admitted outside bats)
    run --separate-stderr env -u BATS_TEST_FILENAME -u BATS_VERSION LOA_PROFILE_ROOT="$T/root" \
        LOA_PROFILE_CACHE_FILE="$T/root/real-run/sub/effective-config.json" bash -c 'source "$1"; loa_profile_cache_state' _ "$LIB"
    [ "$output" = "off (file-absent)" ] || { echo "got '$output'"; return 1; }
}

@test "PL-39 (cycle-138 FR-1) the anchored realpath helper: components below the trust root only, outside paths refused" {
    mkdir -p "$T/root/a/b" "$T/elsewhere"; ln -s "$T/root/a" "$T/root/l"; ln -s "$T/elsewhere" "$T/root/out"
    run env -u BATS_TEST_FILENAME -u BATS_VERSION bash -c '
        source "$1"; _LOA_PL_ROOT="$2"
        for d in "$2/a/b" "$2/l/b" "$2/out" "$2/a/../a/b" "$3" "$2/missing/x"; do
          if _loa_pl_cache_anchored "$d"; then echo "ok $d"; else echo "refused $d"; fi
        done' _ "$LIB" "$T/root" "$T/elsewhere"
    [ "$output" = "$(printf 'ok %s\nrefused %s\nrefused %s\nrefused %s\nrefused %s\nok %s' "$T/root/a/b" "$T/root/l/b" "$T/root/out" "$T/root/a/../a/b" "$T/elsewhere" "$T/root/missing/x")" ] || { echo "$output"; return 1; }
    # a root reached through a symlinked ancestor is canonicalised on both sides
    ln -s "$T/root" "$T/rootlink"
    run env -u BATS_TEST_FILENAME -u BATS_VERSION bash -c 'source "$1"; _LOA_PL_ROOT="$2"; _loa_pl_cache_anchored "$2/a/b"' _ "$LIB" "$T/rootlink"
    [ "$status" -eq 0 ]
}

@test "PL-40 (cycle-138 FR-1) the cache id is byte-identical to the pre-predicate id (old _loa_pl_id pasted), and the trust rows never enter it" {
    mkdir -p "$T/run"; chmod 700 "$T/run"
    run bash -c '
        source "$1"
        _old_id() {   # profile-lib.sh _loa_pl_id at 87e8bd568, verbatim
          local st
          st=$(stat -Lc "%n|%y|%s" -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" 2>/dev/null) ||
            st=$(stat -Lf "%N|%Fm|%z" -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" 2>/dev/null) || true
          if [[ -z "$st" ]] && [[ -e "$_LOA_PL_CFG" || -e "$_LOA_PL_PROF" ]]; then
            _LOA_PL_CUR_ID=""
            return 0
          fi
          _LOA_PL_CUR_ID="v1|$_LOA_PL_CFG|$_LOA_PL_PROF|$_LOA_PL_FLOOR|${st//$'"'"'\n'"'"'/;}"
        }
        _intended_id() {   # the GNU rows of the source files that exist, joined by ";"
          local p rows=""
          for p in "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR"; do
            [[ -e "$p" ]] && rows="$rows;$(stat -Lc "%n|%y|%s" -- "$p")"
          done
          _LOA_PL_CUR_ID="v1|$_LOA_PL_CFG|$_LOA_PL_PROF|$_LOA_PL_FLOOR|${rows#;}"
        }
        cmp_ids() {   # <label> <old|intended>
          _loa_pl_paths; _loa_pl_id; local new="$_LOA_PL_CUR_ID"
          if [[ "$2" == old ]]; then _old_id; else _intended_id; fi
          [[ "$new" == "$_LOA_PL_CUR_ID" ]] && echo "same $1" || echo "DIFF $1: new=<$new> $2=<$_LOA_PL_CUR_ID>"
        }
        cmp_ids "cache absent" old
        loa_knob decisions.surface_at_session_start x >/dev/null
        cmp_ids "cache present" old
        chmod 775 "$2/run"; cmp_ids "dir 775" old; chmod 700 "$2/run"
        unset LOA_PROFILE_CACHE_FILE; cmp_ids "no cache path" old
        mkdir -p "$2/odd|dir"; printf "a: 1\n" > "$2/odd|dir/c.yaml"; LOA_PROFILE_CONFIG_FILE="$2/odd|dir/c.yaml" cmp_ids "a pipe in the config path" old
        LOA_PROFILE_CONFIG_FILE="$2/no-c" LOA_PROFILES_FILE="$2/no-p" LOA_PROFILE_FLOOR_FILE="$2/no-f" cmp_ids "all absent" old
        # A missing source file: the old GNU call exited 1 and fell through to the BSD form, which GNU stat
        # reads as --file-system (filesystem free-block counts entered the id, so it never matched twice).
        # The extended call ignores the rc (SDD § 5.1), so the id is the rows of the files that exist.
        export LOA_PROFILE_CACHE_FILE="$2/run/effective-config.json"
        LOA_PROFILE_FLOOR_FILE="$2/no-floor.yaml" cmp_ids "floor absent" intended
        LOA_PROFILE_CONFIG_FILE="$2/no-config.yaml" cmp_ids "config absent" intended
        LOA_PROFILE_CONFIG_FILE="$2/no-config.yaml" LOA_PROFILES_FILE="$2/no-prof.yaml" cmp_ids "config and profiles absent" intended
    ' _ "$LIB" "$T"
    [ "$status" -eq 0 ]
    [[ "$output" != *DIFF* ]] || { echo "$output"; return 1; }
    [ "$(printf '%s\n' "$output" | grep -c '^same ')" = 9 ] || { echo "$output"; return 1; }
}

@test "PL-41 (cycle-138 FR-1) the warm-path form admits only what the reference ladders admit, and admits the healthy cache" {
    _pl_shims
    _verdicts() {   # → "<fast> <ladder>" (0 = admitted); fast = _loa_pl_cache_usable with the ladders stubbed out
        bash -c 'source "$1"; _loa_pl_paths; _loa_pl_id
                 if _loa_pl_cache_trusted && _loa_pl_cache_readable; then l=0; else l=1; fi
                 _loa_pl_cache_trusted() { return 1; }; _loa_pl_cache_readable() { return 1; }
                 if _loa_pl_cache_usable; then f=0; else f=1; fi
                 echo "$f $l"' _ "$LIB"
    }
    local v
    [ "$(_verdicts)" = "1 1" ]                                   # dir absent
    knob decisions.surface_at_session_start x >/dev/null
    [ "$(_verdicts)" = "0 0" ]                                   # healthy: the fast form answers
    chmod 750 "$T/run"; [ "$(_verdicts)" = "0 0" ]; chmod 700 "$T/run"
    chmod 640 "$LOA_PROFILE_CACHE_FILE"; [ "$(_verdicts)" = "0 0" ]; chmod 600 "$LOA_PROFILE_CACHE_FILE"
    for spec in "run 770 -" "run 701 -" "run 702 -" "file 620 -" "file 602 -" "run - 4242" "file - 4242"; do
        set -- $spec
        if [ "$1" = run ]; then p="$T/run"; else p="$LOA_PROFILE_CACHE_FILE"; fi
        if [ "$2" != - ]; then chmod "$2" "$p"; fi
        if [ "$3" != - ]; then v=$(PATH="$T/shim:$PATH" SHIM_PATH="$p" SHIM_UID="$3" _verdicts); else v=$(_verdicts); fi
        case "$2" in 701) want="0 0" ;; -|*) want="1 1" ;; esac
        [ "$v" = "$want" ] || { echo "$spec: fast/ladder = $v, want $want"; return 1; }
        chmod 700 "$T/run"; chmod 600 "$LOA_PROFILE_CACHE_FILE"
    done
    v=$(PATH="$T/shim:$PATH" SHIM_PATH="$LOA_PROFILE_CACHE_FILE" SHIM_LINKS=2 _verdicts); [ "$v" = "1 1" ]
    v=$(PATH="$T/shim:$PATH" SHIM_PATH="$T/run" SHIM_MODE=0 _verdicts); [ "$v" = "1 0" ]   # (mode 0: the fast form defers, the ladder admits)
}

@test "PL-42 (cycle-138 FR-1) drift guard: the trust check's invariant lines match grimoire-index.sh _gi_trusted_dir (it chmods, this refuses)" {
    local gi="$R/.claude/scripts/grimoire-index.sh"
    _body() { awk -v f="$2" '$0 ~ "^" f "\\(\\) ?\\{" {on = 1; next} on && /^}/ {exit} on' "$1"; }
    _inv() {   # the four invariant tests, cut at their closing ]] / )) and whitespace-normalised
        grep -E '^\s*(\[\[ -d "\$1" && ! -L "\$1" \]\]|\[\[ "\$st" =~ \^\(\[0-9\]\+\)\\ \(\[0-7\]\+\)\$ \]\]|\[\[ "\$\{BASH_REMATCH\[1\]\}" == "\$EUID" \]\]|\(\( \(8#\$\{BASH_REMATCH\[2\]\} & 8#022\) == 0 \)\))' |
            sed -E 's/(\]\]|\)\)).*/\1/; s/^[[:space:]]+//; s/[[:space:]]+/ /g' | LC_ALL=C sort
    }
    a=$(_body "$gi" _gi_trusted_dir | _inv)
    b=$(_body "$LIB" _loa_pl_trusted_dir | _inv)
    [ "$(printf '%s\n' "$a" | grep -c .)" = 4 ] || { echo "grimoire-index lines: $a"; return 1; }
    [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); return 1; }
    # the ladder uses the helper, and nothing in profile-lib issues a chmod
    _body "$LIB" _loa_pl_cache_trusted | grep -q '_loa_pl_trusted_dir "\$d"'
    if grep -nE '(^|[^_[:alnum:]])chmod([^_[:alnum:]]|$)' "$LIB" | grep -vE '^[0-9]+:\s*#'; then return 1; fi
}

@test "PL-43 (cycle-138 FR-1) the /loa Profile line names a refused cache and is unchanged while the cache is on" {
    printf 'loa:\n  profile: full\n' > "$CFG"
    unset LOA_PROFILE_CONFIG_FILE
    mkdir -p "$T/run"; chmod 775 "$T/run"
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
    [ "$line" = "Profile: full (explicit overrides: none) · profile cache off (dir-writable)" ] || { echo "line=<$line>"; return 1; }
    [ "$(stat -c %a "$T/run")" = 775 ]
    chmod 700 "$T/run"
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
    [ "$line" = "Profile: full (explicit overrides: none)" ] || { echo "line=<$line>"; return 1; }
}

@test "PL-44 (cycle-138 FR-1) a BSD-style stat (no -c; -f with %N|%Fm|%z|%Lp|%u|%l) feeds the same rows: cache on, same id" {
    mkdir -p "$T/bsd"
    local real_stat; real_stat=$(command -v stat)
    # the simulated BSD stat: rejects -c like BSD does, and answers -Lf by translating the format to GNU's
    cat > "$T/bsd/stat" <<SH
#!/usr/bin/env bash
case "\$1" in
  -Lc) echo "stat: illegal option -- c" >&2; exit 1 ;;
  -Lf) fmt=\$(printf '%s' "\$2" | sed -e 's/%N/%n/; s/%Fm/%y/; s/%z/%s/; s/%Lp/%a/; s/%l/%h/'); shift 2; exec "$real_stat" -Lc "\$fmt" "\$@" ;;
  *) exec "$real_stat" "\$@" ;;
esac
SH
    chmod +x "$T/bsd/stat"
    knob decisions.surface_at_session_start x >/dev/null
    gnu_id=$(bash -c 'source "$1"; _loa_pl_paths; _loa_pl_id; printf "%s" "$_LOA_PL_CUR_ID"' _ "$LIB")
    bsd_id=$(PATH="$T/bsd:$PATH" bash -c 'source "$1"; _loa_pl_paths; _loa_pl_id; printf "%s" "$_LOA_PL_CUR_ID"' _ "$LIB")
    [ -n "$gnu_id" ] && [ "$gnu_id" = "$bsd_id" ] || { echo "gnu=<$gnu_id> bsd=<$bsd_id>"; return 1; }
    [ "$(PATH="$T/bsd:$PATH" _pl_state)" = on ]
    chmod 775 "$T/run"
    [ "$(PATH="$T/bsd:$PATH" _pl_state)" = "off (dir-writable)" ]
}

# ---- cycle-138 FR-11 (Task 3.1, bd-y5fy4): presence travels as a kind token on the LAST line, never a sentinel ----
# The three read paths of a cached key: WARM (a fresh process, the cache file), MEMO (the same process after a
# resolution: _LOA_PL_JSON) and LIVE (_loa_pl_live: yq | jq on the config). Each fixture gets its own mtime.
_pl45_cfg() {  # <n> <yaml value> → the config sets the cached key to it
    printf 'karpathy_principles:\n  diff_lines_per_task: %s\n' "$2" > "$CFG"
    touch -d "@$(( 1790002000 + $1 ))" "$CFG"
}
_pl45_memo() { bash -c 'source "$1"; loa_profile >/dev/null; loa_knob "$2" "$3"' _ "$LIB" "$@"; }
_pl45_jq_lines() { grep -cE '^\++ ?([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(/[^ ]*/)?jq( |$)' "$T/trace" || true; }
_pl45_three() {  # <n> <yaml value> <expected stdout> — warm (one jq, no yq), memo and live all print it
    local k=karpathy_principles.diff_lines_per_task got
    _pl45_cfg "$1" "$2"
    got=$(_pl20_live "$k" FB);  [ "$got" = "$3" ] || { echo "live <$2>: got '$got' want '$3'"; return 1; }
    knob "$k" FB >/dev/null    # build the cache
    got=$(_pl20_trace knob "$k" FB); [ "$got" = "$3" ] || { echo "warm <$2>: got '$got' want '$3'"; return 1; }
    [ "$(_pl20_yq_lines)" = 0 ] || { echo "warm <$2>: the read went live"; return 1; }
    [ "$(_pl45_jq_lines)" = 1 ] || { echo "warm <$2>: $(_pl45_jq_lines) jq calls (fell through to a rebuild)"; return 1; }
    got=$(_pl45_memo "$k" FB);  [ "$got" = "$3" ] || { echo "memo <$2>: got '$got' want '$3'"; return 1; }
}

@test "PL-45 (cycle-138 FR-11) a value equal to the former ABSENT sentinel round-trips on the warm, memo and live paths" {
    # (before: warm and memo printed the fallback FB; live printed the value)
    _pl45_three 1 '"__LOA_PL_ABSENT__"' '__LOA_PL_ABSENT__'
}

@test "PL-46 (cycle-138 FR-11) a value equal to the former MISS sentinel round-trips on the warm, memo and live paths" {
    # (before: all three printed the fallback FB — warm took a live read, which misread it again)
    _pl45_three 2 '"__LOA_PL_MISS__"' '__LOA_PL_MISS__'
}

@test "PL-47 (cycle-138 FR-11) a value equal to the former STALE sentinel round-trips, and the warm read does not fall through" {
    # (before: the value printed on every path, but the warm read treated it as a stale cache — 3 jq, not 1)
    _pl45_three 3 '"__LOA_PL_STALE__"' '__LOA_PL_STALE__'
}

@test "PL-48 (cycle-138 FR-11) an EMPTY present value prints what it printed before on all three paths: the fallback" {
    # (pinned bytes: a configured "" is not a usable value — the warm read falls through, the memo read goes
    # live, the live read prints the fallback; this is unchanged by the kind token)
    local k=karpathy_principles.diff_lines_per_task v n=10
    for v in '""' "''"; do
        n=$((n + 1)); _pl45_cfg "$n" "$v"
        [ "$(_pl20_live "$k" FB)" = FB ] || { echo "live <$v>"; return 1; }
        knob "$k" FB >/dev/null
        [ "$(knob "$k" FB)" = FB ] || { echo "warm <$v>"; return 1; }
        [ "$(_pl45_memo "$k" FB)" = FB ] || { echo "memo <$v>"; return 1; }
        [ "$(knob "$k" '')" = '' ] || { echo "warm <$v>, empty fallback"; return 1; }
    done
}

@test "PL-49 (cycle-138 FR-11) trailing newlines are stripped as before on all three paths; an all-newline value is empty" {
    local k=karpathy_principles.diff_lines_per_task
    # (pinned bytes: command substitution stripped the trailing newlines, printf added one)
    _pl45_three 21 '"line one\nline two\n\n"' $'line one\nline two'
    _pl45_three 22 '"\nlead\n"' $'\nlead'
    _pl45_three 23 '|
    alpha
    beta' $'alpha\nbeta'
    # an all-newline value strips to empty → the empty rule (PL-48): the fallback on every path
    _pl45_cfg 24 '"\n\n"'
    [ "$(_pl20_live "$k" FB)" = FB ]
    knob "$k" FB >/dev/null
    [ "$(knob "$k" FB)" = FB ]
    [ "$(_pl45_memo "$k" FB)" = FB ]
    # (the exact bytes: one value line + printf's newline)
    _pl45_cfg 25 '"x\n\n\n"'; knob "$k" FB >/dev/null
    [ "$(knob "$k" FB | od -An -c | tr -d ' \n')" = 'x\n' ]
}

@test "PL-50 (cycle-138 FR-11) values equal to the kind tokens, or ending in one, are values on all three paths" {
    _pl45_three 31 'present' 'present'
    _pl45_three 32 'absent' 'absent'
    _pl45_three 33 'miss' 'miss'
    _pl45_three 34 'stale' 'stale'
    _pl45_three 35 '"x\nmiss"' $'x\nmiss'
    _pl45_three 36 '"x\nabsent\n"' $'x\nabsent'
    _pl45_three 37 '"\npresent"' $'\npresent'
}

@test "PL-51 (cycle-138 FR-11) structural: no __LOA_PL_ sentinel string is left in profile-lib.sh" {
    run grep -c '__LOA_PL_' "$LIB"
    [ "$output" = 0 ] || { grep -n '__LOA_PL_' "$LIB"; return 1; }
}

@test "PL-52 (cycle-138 FR-11) a multi-document config: a key null in every document reads the fallback live; set keys print one line per document" {
    # (before: each null document leaked a __LOA_PL_MISS__ line into the printed value)
    printf 'a: 1\n---\nb: 2\n' > "$CFG"
    [ "$(_pl20_live run_mode.enabled FB)" = FB ] || { echo "got '$(_pl20_live run_mode.enabled FB)'"; return 1; }
    printf 'run_mode:\n  enabled: one\n---\nrun_mode:\n  enabled: two\n' > "$CFG"
    [ "$(_pl20_live run_mode.enabled FB)" = $'one\ntwo' ]
}
