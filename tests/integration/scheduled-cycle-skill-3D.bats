#!/usr/bin/env bats
# =============================================================================
# scheduled-cycle-skill-3D.bats — Sprint 3D
#
# Verifies SKILL.md + example contract scripts + ScheduleConfig YAML +
# CLAUDE.md L3 section + lore entry are all wired correctly. Runs the shipped
# example schedule end-to-end against the lib to prove the documented usage
# matches reality (FR-L3-1, FR-L3-3, FR-L3-7, FR-L3-8).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cycles.jsonl"
    LOCK_DIR="${TEST_DIR}/.run/cycles"
    mkdir -p "$LOCK_DIR"
    SCHEDULE_YAML="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/contracts/example-schedule.yaml"
    LIB="${REPO_ROOT}/.claude/scripts/lib/scheduled-cycle-lib.sh"

    export LOA_CYCLES_LOG="$LOG_FILE"
    export LOA_L3_LOCK_DIR="$LOCK_DIR"
    export LOA_L3_LOCK_TIMEOUT_SECONDS=2
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT TEST_DIR LOG_FILE LOCK_DIR SCHEDULE_YAML LIB
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# SKILL.md presence + frontmatter
# -----------------------------------------------------------------------------
@test "SKILL.md: scheduled-cycle-template SKILL.md exists with valid frontmatter" {
    local skill="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/SKILL.md"
    [ -f "$skill" ]
    # Frontmatter should be valid YAML.
    local fm
    fm="$(awk '/^---/{n++; next} n==1' "$skill")"
    [ -n "$fm" ]
    run python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" <<<"$fm"
    [ "$status" -eq 0 ]
}

@test "SKILL.md: declares L3 capabilities + allowed-tools" {
    local skill="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/SKILL.md"
    grep -q "^name: scheduled-cycle-template" "$skill"
    grep -q "^allowed-tools:" "$skill"
    grep -q "^capabilities:" "$skill"
}

@test "SKILL.md: skill capability declarations honor write/agent invariant" {
    # Validator scans all skills + exits non-zero if ANY fail. Assert ours is
    # specifically PASS, regardless of unrelated pre-existing failures.
    if [[ -x "${REPO_ROOT}/.claude/scripts/validate-skill-capabilities.sh" ]]; then
        run "${REPO_ROOT}/.claude/scripts/validate-skill-capabilities.sh"
        # Strip ANSI color codes before substring matching.
        local clean
        clean="$(printf '%s' "$output" | sed -E 's/\x1B\[[0-9;]*[mK]//g')"
        [[ "$clean" == *"[scheduled-cycle-template]"*"PASS"* ]]
        # Also ensure our skill line does NOT contain ERROR/FAIL.
        local our_line
        our_line="$(printf '%s\n' "$clean" | grep "scheduled-cycle-template" || true)"
        [[ "$our_line" != *"ERROR"* ]]
        [[ "$our_line" != *"FAIL"* ]]
    else
        skip "validate-skill-capabilities.sh not present in this checkout"
    fi
}

# -----------------------------------------------------------------------------
# Example contract scripts present + executable + emit valid JSON
# -----------------------------------------------------------------------------
@test "contracts: 5 example phase scripts exist + executable" {
    local d="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/contracts"
    for phase in reader decider dispatcher awaiter logger; do
        [ -x "${d}/example-${phase}.sh" ]
    done
}

@test "contracts: each example phase emits valid JSON on stdout" {
    local d="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/contracts"
    for phase in reader decider dispatcher awaiter logger; do
        run "${d}/example-${phase}.sh" "demo-cycle" "demo-sched" 0 "[]"
        [ "$status" -eq 0 ]
        run jq -e . <<<"$output"
        [ "$status" -eq 0 ]
    done
}

@test "contracts: example-schedule.yaml is parseable YAML with required fields" {
    local y="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/contracts/example-schedule.yaml"
    [ -f "$y" ]
    # Required: schedule_id, schedule, dispatch_contract.{reader,decider,dispatcher,awaiter,logger}
    run python3 -c "
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
assert 'schedule_id' in doc, 'schedule_id missing'
assert 'schedule' in doc, 'schedule missing'
dc = doc.get('dispatch_contract', {})
for k in ['reader','decider','dispatcher','awaiter','logger']:
    assert k in dc, f'dispatch_contract.{k} missing'
print('OK')
" "$y"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# End-to-end: run shipped example via the lib subcommand
# -----------------------------------------------------------------------------
@test "FR-L3-1+3+7+8: shipped example ScheduleConfig runs end-to-end via the lib" {
    run "$LIB" invoke "$SCHEDULE_YAML" --cycle-id "test-3d-e2e"
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    # 1 start + 5 phase + 1 complete = 7
    run jq -sr '. | length' "$LOG_FILE"
    [ "$output" = "7" ]
    # cycle.complete present
    run jq -sr '[.[] | select(.event_type == "cycle.complete")] | length' "$LOG_FILE"
    [ "$output" = "1" ]
}

@test "FR-L3-7: shipped example replay reassembles 5-phase CycleRecord" {
    "$LIB" invoke "$SCHEDULE_YAML" --cycle-id "test-3d-replay"
    run "$LIB" replay "$LOG_FILE" --cycle-id "test-3d-replay"
    [ "$status" -eq 0 ]
    run jq -r '.outcome' <<<"$output"
    [ "$output" = "success" ]
    run jq -r '.phases | length' <<<"$("$LIB" replay "$LOG_FILE" --cycle-id "test-3d-replay")"
    [ "$output" = "5" ]
}

@test "FR-L3-1: dry-run validates the shipped example without firing phases" {
    run "$LIB" invoke "$SCHEDULE_YAML" --cycle-id "test-3d-dry" --dry-run
    [ "$status" -eq 0 ]
    run jq -sr '. | length' "$LOG_FILE"
    [ "$output" = "1" ]
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    [ "$output" = "cycle.start" ]
}

# -----------------------------------------------------------------------------
# CLAUDE.md L3 constraint section
# -----------------------------------------------------------------------------
@test "CLAUDE.md: L3 Scheduled-Cycle Template section present with constraints table" {
    local cl="${REPO_ROOT}/.claude/loa/CLAUDE.loa.md"
    grep -q "^## L3 Scheduled-Cycle Template" "$cl"
    grep -q "^### Scheduled-Cycle Constraints" "$cl"
    # Spot-check at least 4 constraints by anchor text.
    grep -q "ALWAYS use \`cycle_invoke\`" "$cl"
    grep -q "cycle.complete\` as the ONLY idempotency gate" "$cl"
    grep -q "hold the flock across the entire cycle" "$cl"
    grep -q "compose L2 budget pre-check" "$cl"
}

# -----------------------------------------------------------------------------
# Lore entry
# -----------------------------------------------------------------------------
@test "lore: scheduled-cycle pattern present in patterns.yaml + index.yaml" {
    local patterns="${REPO_ROOT}/grimoires/loa/lore/patterns.yaml"
    local index="${REPO_ROOT}/grimoires/loa/lore/index.yaml"
    grep -q "^- id: scheduled-cycle" "$patterns"
    grep -q "term: Scheduled Cycle" "$patterns"
    grep -q "id: scheduled-cycle" "$index"
}

# -----------------------------------------------------------------------------
# .loa.config.yaml.example documents the L3 block
# -----------------------------------------------------------------------------
@test ".loa.config.yaml.example: scheduled_cycle_template block documented" {
    local cfg="${REPO_ROOT}/.loa.config.yaml.example"
    grep -q "scheduled_cycle_template:" "$cfg"
    grep -q "audit_log: \.run/cycles\.jsonl" "$cfg"
    grep -q "lock_dir: \.run/cycles" "$cfg"
    grep -q "budget_pre_check: false" "$cfg"
    grep -q "schedules: \[\]" "$cfg"
}

# -----------------------------------------------------------------------------
# Schemas registered in audit retention policy
# -----------------------------------------------------------------------------
@test "audit-retention-policy.yaml: L3 entry present" {
    local pol="${REPO_ROOT}/.claude/data/audit-retention-policy.yaml"
    [ -f "$pol" ]
    grep -q "^  L3:" "$pol"
    grep -q 'log_basename: "cycles.jsonl"' "$pol"
}

# -----------------------------------------------------------------------------
# Library CLI --help works
# -----------------------------------------------------------------------------
@test "lib CLI: --help lists invoke / idempotency-check / replay" {
    run "$LIB" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"invoke"* ]]
    [[ "$output" == *"idempotency-check"* ]]
    [[ "$output" == *"replay"* ]]
}
