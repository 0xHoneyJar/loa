#!/usr/bin/env bats
# =============================================================================
# hook-wiring.bats — bug-1002 / sprint-bug-199
# =============================================================================
# Three documented enforcement walls were inert in default installs:
#   - adversarial-review-gate.sh: template-wired (PR #552) but absent from
#     LIVE .claude/settings.json — and mount/update copy settings.json to
#     consumers, so the review-skip COMPLETED-marker wall never fired anywhere
#   - zone-write-guard.sh: documented as actively running (zones.yaml,
#     zone-hygiene runbook) but wired in NEITHER file
#   - implement-gate.sh: opt-in by design, but hooks-reference.md listed it
#     as registered (doc fix; stays PARKED below)
# Plus: the issue's "duplicate hooks" claim was a matcher-blind false
# positive — W3 pins the matcher-AWARE no-duplicates invariant so the real
# defect class (same command twice under ONE matcher) is fenced without
# breaking Write+Edit coverage.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEMPLATE="$PROJECT_ROOT/.claude/hooks/settings.hooks.json"
    LIVE="$PROJECT_ROOT/.claude/settings.json"
}

# Hooks that are deliberately NOT wired (opt-in prototypes). Adding a script
# to .claude/hooks/{safety,compliance}/ without wiring it OR parking it here
# must fail W4 — that is the activation-gap fence.
# stop-input-probe.sh (cycle-117 item A): DIAGNOSTIC, ships UNREGISTERED by
# design — gated by LOA_STOP_INPUT_PROBE=1, merged into settings.local.json for
# one cap-hitting session only, never into settings.hooks.json.
PARKED_HOOKS="implement-gate.sh stop-input-probe.sh"

@test "W1 bug-1002: every template PreToolUse command is wired in live settings.json" {
    local missing=0
    while IFS= read -r cmd; do
        if ! jq -e --arg c "$cmd" \
            '[.hooks.PreToolUse[].hooks[].command] | index($c)' "$LIVE" >/dev/null; then
            echo "template-wired but ABSENT from live: $cmd" >&2
            missing=$((missing + 1))
        fi
    done < <(jq -r '.hooks.PreToolUse[].hooks[].command' "$TEMPLATE" | sort -u)
    [ "$missing" -eq 0 ]
}

@test "W10 bd-hooks-template-sessionstart-parity: every template SessionStart command is wired in live settings.json" {
    local missing=0
    while IFS= read -r cmd; do
        if ! jq -e --arg c "$cmd" \
            '[.hooks.SessionStart[].hooks[].command] | index($c)' "$LIVE" >/dev/null; then
            echo "template-wired but ABSENT from live: $cmd" >&2
            missing=$((missing + 1))
        fi
    done < <(jq -r '.hooks.SessionStart[].hooks[].command' "$TEMPLATE" | sort -u)
    [ "$missing" -eq 0 ]
}

@test "W2 bug-1002: zone-write-guard.sh is wired for Write and Edit in BOTH files" {
    for f in "$TEMPLATE" "$LIVE"; do
        for tool in Write Edit; do
            jq -e --arg t "$tool" '
                [.hooks.PreToolUse[]
                 | select(.matcher | test("(^|\\|)" + $t + "(\\||$)"))
                 | .hooks[].command
                 | select(test("zone-write-guard\\.sh$"))] | length > 0
            ' "$f" >/dev/null || {
                echo "zone-write-guard.sh not covering $tool in $f" >&2
                return 1
            }
        done
    done
}

@test "W3 bug-1002: no command appears twice under one matcher group (matcher-aware dup check)" {
    for f in "$TEMPLATE" "$LIVE"; do
        local dups
        dups=$(jq -r '
            .hooks // {} | to_entries[] | .value[]?
            | select(type == "object" and has("hooks"))
            | (.matcher // "ALL") as $m
            | [.hooks[].command] | group_by(.) | map(select(length > 1))
            | .[] | "\($m): \(.[0])"
        ' "$f")
        if [ -n "$dups" ]; then
            echo "true duplicates in $f:" >&2
            echo "$dups" >&2
            return 1
        fi
    done
}

@test "W4 bug-1002: every safety/compliance hook script is wired or explicitly parked" {
    local unwired=0
    for script in "$PROJECT_ROOT"/.claude/hooks/safety/*.sh \
                  "$PROJECT_ROOT"/.claude/hooks/compliance/*.sh; do
        local name; name=$(basename "$script")
        case " $PARKED_HOOKS " in *" $name "*) continue ;; esac
        if ! grep -q "$name" "$TEMPLATE"; then
            echo "hook script neither template-wired nor parked: $name" >&2
            unwired=$((unwired + 1))
        fi
    done
    [ "$unwired" -eq 0 ]
}

@test "W5 bug-1002: lint-invariants is wiring-aware (fails on a synthetic template/live gap)" {
    local tmp="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$tmp/.claude/hooks/safety" "$tmp/.claude/hooks/compliance" "$tmp/.claude/scripts"
    # synthetic: template wires a hook that live lacks
    cat > "$tmp/.claude/hooks/settings.hooks.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": ".claude/hooks/safety/ghost.sh"}]}]}}
EOF
    cat > "$tmp/.claude/settings.json" <<'EOF'
{"hooks": {"PreToolUse": []}}
EOF
    touch "$tmp/.claude/hooks/safety/ghost.sh"
    run "$PROJECT_ROOT/.claude/scripts/lint-invariants.sh" --hooks-wiring-only --root "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ghost.sh"* ]]
}

@test "W6 bug-1002: hooks-reference registrations TABLE marks implement-gate.sh opt-in/unwired" {
    # The registrations table row (was :134) listed implement-gate.sh as a
    # plain PreToolUse registration — it is an opt-in prototype, wired
    # nowhere. The table row itself must carry the caveat.
    local row
    row=$(grep -E '^\|.*implement-gate\.sh' "$PROJECT_ROOT/.claude/loa/reference/hooks-reference.md" || true)
    [ -n "$row" ]
    echo "$row" | grep -qiE 'opt-in|unwired|parked'
}

@test "W7 bug-1002 iter-1: zone-write-guard BLOCKS .claude/ writes via the REAL stdin hook contract" {
    # Review iter-1 BLOCKING: the guard read CLAUDE_TOOL_FILE_PATH/$1 only —
    # under real hook execution (payload on stdin) TARGET was empty and every
    # write was ALLOWED. The wired gate was inert. Pin the stdin contract.
    # cycle-119: LOA_ZONE_GUARD_AUTH_FILE=/dev/null isolates from any live
    # framework-dev authorization marker in the repo's .run/ (ZWG-T20..T25
    # cover marker behavior; these tests pin the UNAUTHORIZED baseline).
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\".claude/scripts/x.sh\"}}" | LOA_ZONE_GUARD_AUTH_FILE=/dev/null LOA_ZONE_GUARD_TRAJECTORY_DIR=/nonexistent "$0"' \
        "$PROJECT_ROOT/.claude/hooks/safety/zone-write-guard.sh"
    # iter-2: Claude Code blocks on exit 2 (exit 1 = non-blocking hook error)
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"grimoires/loa/NOTES.md\"}}" | LOA_ZONE_GUARD_AUTH_FILE=/dev/null LOA_ZONE_GUARD_TRAJECTORY_DIR=/nonexistent "$0"' \
        "$PROJECT_ROOT/.claude/hooks/safety/zone-write-guard.sh"
    [ "$status" -eq 0 ]
}

@test "W8 bug-1002 audit: submodule physical prefix .loa/.claude/ classifies as framework (BLOCK)" {
    # In submodule mounts the .claude symlink resolves to .loa/.claude/ —
    # which matched no zone glob and fell through unclassified->ALLOW.
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\".loa/.claude/scripts/x.sh\"}}" | LOA_ZONE_GUARD_AUTH_FILE=/dev/null LOA_ZONE_GUARD_TRAJECTORY_DIR=/nonexistent "$0"' \
        "$PROJECT_ROOT/.claude/hooks/safety/zone-write-guard.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "W9 bug-1002 audit: every hook-wiring settings scope is guarded (incl. Local-scope override)" {
    # iter-4: unclassified settings.json let any actor unwire the guards.
    # iter-5: settings.local.json is Local-scope and OVERRIDES project
    # settings (hook keys included) — agent writes there were a one-shot
    # bypass. Humans edit these outside the harness; agents need
    # LOA_ZONE_GUARD_BYPASS=1 under explicit operator direction.
    for f in ".claude/settings.json" ".claude/settings.local.json"; do
        run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | LOA_ZONE_GUARD_AUTH_FILE=/dev/null LOA_ZONE_GUARD_TRAJECTORY_DIR=/nonexistent \"\$0\"" \
            "$PROJECT_ROOT/.claude/hooks/safety/zone-write-guard.sh"
        [ "$status" -eq 2 ]
    done
}
