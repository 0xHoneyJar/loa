#!/usr/bin/env bats
# =============================================================================
# skill-capabilities.bats — Tests for validate-skill-capabilities.sh
# =============================================================================
# Part of cycle-050: Multi-Model Permission Architecture (FR-1, FR-3)

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/validate-skill-capabilities.sh"
    FIXTURE_DIR="$BATS_TEST_TMPDIR/skills"
    mkdir -p "$FIXTURE_DIR/test-skill"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/skills" 2>/dev/null || true
}

create_skill() {
    local name="$1"
    local content="$2"
    mkdir -p "$FIXTURE_DIR/$name"
    echo "$content" > "$FIXTURE_DIR/$name/SKILL.md"
}

# =========================================================================
# SC-T1: Valid capabilities pass validation
# =========================================================================

@test "valid capabilities with schema_version 1 passes" {
    create_skill "good-skill" "---
name: good
description: A good skill
allowed-tools: Read, Grep, Glob
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---
# Good Skill"

    # Override SKILLS_DIR for test
    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill good-skill
    [ "$status" -eq 0 ]
}

# =========================================================================
# SC-T2: Missing capabilities fails (deny-all default)
# =========================================================================

@test "missing capabilities field fails validation" {
    create_skill "no-caps" "---
name: nocaps
description: No capabilities
allowed-tools: Read
cost-profile: lightweight
---
# No Caps"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill no-caps
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing capabilities field"* ]]
}

# =========================================================================
# SC-T3: capabilities: all sentinel rejected
# =========================================================================

@test "capabilities: all sentinel is rejected" {
    create_skill "all-sentinel" "---
name: allcaps
description: All caps sentinel
capabilities: all
cost-profile: unbounded
---
# All Sentinel"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill all-sentinel
    [ "$status" -eq 1 ]
    [[ "$output" == *"sentinel prohibited"* ]]
}

# =========================================================================
# SC-T4: Raw shell pattern in execute_commands rejected
# =========================================================================

@test "raw shell pattern in execute_commands is rejected" {
    create_skill "raw-shell" "---
name: rawshell
description: Raw shell
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: false
  execute_commands:
    - pattern: \"git diff *\"
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Raw Shell"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill raw-shell
    [ "$status" -eq 1 ]
    [[ "$output" == *"raw pattern format"* ]]
}

# =========================================================================
# SC-T5: capabilities vs allowed-tools mismatch: ERROR case
# =========================================================================

@test "write_files false with Write in allowed-tools is ERROR" {
    create_skill "sec-violation" "---
name: secviol
description: Security violation
allowed-tools: Read, Write, Glob
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Sec Violation"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill sec-violation
    [ "$status" -eq 1 ]
    [[ "$output" == *"security violation"* ]]
}

# =========================================================================
# SC-T6: capabilities vs allowed-tools mismatch: WARNING case
# =========================================================================

@test "write_files true without Write in allowed-tools is WARNING" {
    create_skill "overestimate" "---
name: overest
description: Overestimate
allowed-tools: Read, Grep
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Overestimate"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill overestimate
    [ "$status" -eq 0 ]
    [[ "$output" == *"overestimate"* ]]
}

# =========================================================================
# SC-T7: --strict mode promotes warnings to errors
# =========================================================================

@test "strict mode promotes overestimate warning to error" {
    create_skill "overestimate2" "---
name: overest2
description: Overestimate strict
allowed-tools: Read, Grep
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Overestimate Strict"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --strict --skill overestimate2
    [ "$status" -eq 1 ]
    [[ "$output" == *"strict: promoted from warning"* ]]
}

# =========================================================================
# SC-T8: --json output is valid JSON
# =========================================================================

@test "json output is valid JSON" {
    create_skill "json-test" "---
name: jsontest
description: JSON test
allowed-tools: Read
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---
# JSON Test"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --json --skill json-test
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.total == 1' > /dev/null
    echo "$output" | jq -e '.passed == 1' > /dev/null
}

# =========================================================================
# SC-T9: Missing schema_version fails
# =========================================================================

@test "missing schema_version fails validation" {
    create_skill "no-version" "---
name: noversion
description: No schema version
capabilities:
  read_files: true
  search_code: false
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---
# No Version"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill no-version
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing capabilities.schema_version"* ]]
}

# =========================================================================
# SC-T10: Lightweight cost-profile with write_files true warns
# =========================================================================

@test "lightweight cost-profile with write_files warns" {
    create_skill "cost-mismatch" "---
name: costmismatch
description: Cost mismatch
allowed-tools: Read, Write
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---
# Cost Mismatch"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill cost-mismatch
    [ "$status" -eq 0 ]
    [[ "$output" == *"correlation mismatch"* ]]
}

# =========================================================================
# SC-T-AGENT-1: write_files true + agent: Plan → ERROR (Issue #553)
# =========================================================================

@test "write_files true with agent: Plan is ERROR" {
    create_skill "plan-write-conflict" "---
name: planwrite
description: Plan agent with write capability
agent: Plan
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Plan Write Conflict"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill plan-write-conflict
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent type 'Plan'"* ]]
    [[ "$output" == *"Write"* ]]
}

# =========================================================================
# SC-T-AGENT-2: write_files true + agent: Explore → ERROR (Issue #553)
# =========================================================================

@test "write_files true with agent: Explore is ERROR" {
    create_skill "explore-write-conflict" "---
name: explorewrite
description: Explore agent with write capability
agent: Explore
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Explore Write Conflict"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill explore-write-conflict
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent type 'Explore'"* ]]
}

# =========================================================================
# SC-T-AGENT-3: write_files true + agent: general-purpose → PASS
# =========================================================================

@test "write_files true with agent: general-purpose passes" {
    create_skill "gp-write-ok" "---
name: gpwrite
description: General-purpose agent with write capability
agent: general-purpose
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# GP Write OK"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill gp-write-ok
    [ "$status" -eq 0 ]
}

# =========================================================================
# SC-T-AGENT-4: write_files true + no agent key → PASS (foreground has Write)
# =========================================================================

@test "write_files true with no agent key passes" {
    create_skill "no-agent-write-ok" "---
name: noagent
description: No agent type declared
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# No Agent Write OK"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill no-agent-write-ok
    [ "$status" -eq 0 ]
}

# =========================================================================
# SC-T-AGENT-5: write_files false + agent: Plan → PASS (no contradiction)
# =========================================================================

@test "write_files false with agent: Plan passes" {
    create_skill "plan-read-only" "---
name: planro
description: Plan agent read-only
agent: Plan
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Plan Read Only"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill plan-read-only
    [ "$status" -eq 0 ]
}

# =========================================================================
# SC-T-AGENT-6: allowed-tools: Write + agent: Plan → ERROR
# =========================================================================

@test "allowed-tools contains Write with agent: Plan is ERROR" {
    create_skill "plan-allowed-tools-write" "---
name: planallowedwrite
description: Plan agent with Write in allowed-tools
agent: Plan
allowed-tools: Read, Grep, Write
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
---
# Plan Allowed-Tools Write Conflict"

    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill plan-allowed-tools-write
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent type 'Plan'"* ]]
}
