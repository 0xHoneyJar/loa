#!/usr/bin/env bats
# Tests for .claude/settings.json permission patterns

setup() {
    export SETTINGS_FILE="${BATS_TEST_DIRNAME}/../../.claude/settings.json"
}

# =============================================================================
# JSON Validity Tests
# =============================================================================

@test "settings.json is valid JSON" {
    run jq '.' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

@test "settings.json has permissions object" {
    run jq -e '.permissions' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

@test "settings.json has allow array" {
    run jq -e '.permissions.allow' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

@test "settings.json has deny array" {
    run jq -e '.permissions.deny' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Allow Pattern Count Tests
# =============================================================================

@test "allow list has at least 150 patterns" {
    local count
    count=$(jq '.permissions.allow | length' "$SETTINGS_FILE")
    [ "$count" -ge 150 ]
}

@test "allow list has fewer than 500 patterns (sanity check)" {
    local count
    count=$(jq '.permissions.allow | length' "$SETTINGS_FILE")
    [ "$count" -lt 500 ]
}

# =============================================================================
# Package Manager Patterns
# =============================================================================

@test "npm commands are allowed" {
    run jq -e '.permissions.allow | any(test("npm"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "pnpm commands are allowed" {
    run jq -e '.permissions.allow | any(test("pnpm"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "yarn commands are allowed" {
    run jq -e '.permissions.allow | any(test("yarn"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "bun commands are allowed" {
    run jq -e '.permissions.allow | any(test("bun"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "cargo commands are allowed" {
    run jq -e '.permissions.allow | any(test("cargo"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "pip commands are allowed" {
    run jq -e '.permissions.allow | any(test("pip"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "poetry commands are allowed" {
    run jq -e '.permissions.allow | any(test("poetry"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Git Patterns
# =============================================================================

@test "git add is allowed" {
    run jq -e '.permissions.allow | any(test("git add"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git commit is allowed" {
    run jq -e '.permissions.allow | any(test("git commit"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git push is allowed" {
    run jq -e '.permissions.allow | any(test("git push"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git pull is allowed" {
    run jq -e '.permissions.allow | any(test("git pull"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git branch is allowed" {
    run jq -e '.permissions.allow | any(test("git branch"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git merge is allowed" {
    run jq -e '.permissions.allow | any(test("git merge"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git rebase is allowed" {
    run jq -e '.permissions.allow | any(test("git rebase"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "git stash is allowed" {
    run jq -e '.permissions.allow | any(test("git stash"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "gh (GitHub CLI) is allowed" {
    run jq -e '.permissions.allow | any(test("gh"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Container Patterns
# =============================================================================

@test "docker commands are allowed" {
    run jq -e '.permissions.allow | any(test("docker"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "kubectl commands are allowed" {
    run jq -e '.permissions.allow | any(test("kubectl"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "helm commands are allowed" {
    run jq -e '.permissions.allow | any(test("helm"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Testing Framework Patterns
# =============================================================================

@test "jest is allowed" {
    run jq -e '.permissions.allow | any(test("jest"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "vitest is allowed" {
    run jq -e '.permissions.allow | any(test("vitest"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "pytest is allowed" {
    run jq -e '.permissions.allow | any(test("pytest"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "bats is allowed" {
    run jq -e '.permissions.allow | any(test("bats"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deploy CLI Patterns
# =============================================================================

@test "vercel commands are allowed" {
    run jq -e '.permissions.allow | any(test("vercel"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "fly commands are allowed" {
    run jq -e '.permissions.allow | any(test("fly"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "aws commands are allowed" {
    run jq -e '.permissions.allow | any(test("aws"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "terraform commands are allowed" {
    run jq -e '.permissions.allow | any(test("terraform"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Privilege Escalation
# =============================================================================

@test "sudo is denied" {
    run jq -e '.permissions.deny | any(test("sudo"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "su is denied" {
    run jq -e '.permissions.deny | any(test("su:"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "doas is denied" {
    run jq -e '.permissions.deny | any(test("doas"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Destructive Operations
# =============================================================================

@test "rm -rf / is denied" {
    run jq -e '.permissions.deny | any(test("rm -rf /"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "rm -rf ~ is denied" {
    run jq -e '.permissions.deny | any(test("rm -rf ~"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Fork Bombs
# =============================================================================

@test "fork bomb pattern is denied" {
    run jq -e '.permissions.deny | any(test(":\\(\\)"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Remote Code Execution
# =============================================================================

@test "curl|bash is denied" {
    run jq -e '.permissions.deny | any(test("curl.*bash"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "wget|sh is denied" {
    run jq -e '.permissions.deny | any(test("wget.*sh"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "eval curl is denied" {
    run jq -e '.permissions.deny | any(test("eval.*curl"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Device Attacks
# =============================================================================

@test "dd to /dev is denied" {
    run jq -e '.permissions.deny | any(test("dd if=/dev"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "mkfs is denied" {
    run jq -e '.permissions.deny | any(test("mkfs"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "fdisk is denied" {
    run jq -e '.permissions.deny | any(test("fdisk"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - Permission Attacks
# =============================================================================

@test "chmod 777 / is denied" {
    run jq -e '.permissions.deny | any(test("chmod -R 777 /"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - System Control
# =============================================================================

@test "reboot is denied" {
    run jq -e '.permissions.deny | any(test("reboot"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "shutdown is denied" {
    run jq -e '.permissions.deny | any(test("shutdown"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "poweroff is denied" {
    run jq -e '.permissions.deny | any(test("poweroff"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny Pattern Tests - User Management
# =============================================================================

@test "passwd is denied" {
    run jq -e '.permissions.deny | any(test("passwd"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "useradd is denied" {
    run jq -e '.permissions.deny | any(test("useradd"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "visudo is denied" {
    run jq -e '.permissions.deny | any(test("visudo"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =============================================================================
# Deny List Count Tests
# =============================================================================

@test "deny list has at least 30 patterns" {
    local count
    count=$(jq '.permissions.deny | length' "$SETTINGS_FILE")
    [ "$count" -ge 30 ]
}

@test "deny list has fewer than 100 patterns (sanity check)" {
    local count
    count=$(jq '.permissions.deny | length' "$SETTINGS_FILE")
    [ "$count" -lt 100 ]
}

# =============================================================================
# Pattern Format Tests
# =============================================================================

@test "all allow patterns use Bash() format" {
    local bad_patterns
    bad_patterns=$(jq -r '.permissions.allow[] | select(startswith("Bash(") | not)' "$SETTINGS_FILE" | wc -l)
    [ "$bad_patterns" -eq 0 ]
}

@test "all deny patterns use Bash() format" {
    local bad_patterns
    bad_patterns=$(jq -r '.permissions.deny[] | select(startswith("Bash(") | not)' "$SETTINGS_FILE" | wc -l)
    [ "$bad_patterns" -eq 0 ]
}

# =============================================================================
# Hooks Tests
# =============================================================================

@test "hooks object exists" {
    run jq -e '.hooks' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

@test "SessionStart hook exists" {
    run jq -e '.hooks.SessionStart' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
}

@test "SessionStart includes update check" {
    run jq -e '.hooks.SessionStart | any(test("check-updates"))' "$SETTINGS_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}
