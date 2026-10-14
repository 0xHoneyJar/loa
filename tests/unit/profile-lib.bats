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
