#!/usr/bin/env bats
# Issue-sweep contracts: validate the instructions/capabilities actually loaded.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "issue-1244: every implementing AC gate uses the resolved owning sprint" {
    run python3 - "$REPO_ROOT" <<'PY'
import pathlib
import re
import sys
root = pathlib.Path(sys.argv[1])
text = (root / ".claude/skills/implementing-tasks/SKILL.md").read_text()
commands = re.findall(r"`(\.claude/scripts/validate-ac-verification\.sh [^`]+)`", text)
assert len(commands) == 2, commands
for command in commands:
    assert '--sprint "$SPRINT_FILE"' in command, command
assert "grimoires/loa/a2a/bug-<id>/sprint.md" in text
PY
    [ "$status" -eq 0 ]
}

@test "issue-1244: owning micro-sprint passes while unrelated root ACs fail" {
    mkdir -p "$TEST_DIR/a2a/bug-20260914-i1244-abcdef"
    printf '### Acceptance Criteria\n- [ ] Unrelated release requirement\n' > "$TEST_DIR/sprint.md"
    local owner="$TEST_DIR/a2a/bug-20260914-i1244-abcdef/sprint.md"
    printf '### Acceptance Criteria\n- [ ] Fix the observed bug\n' > "$owner"
    cat > "$TEST_DIR/reviewer.md" <<'EOF'
## AC Verification
**AC-1**: "Fix the observed bug"
- Status: ✓ Met
- Evidence: tests/regression.bats:1
EOF
    run "$REPO_ROOT/.claude/scripts/validate-ac-verification.sh" \
        --report "$TEST_DIR/reviewer.md" --sprint "$TEST_DIR/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unrelated release requirement"* ]]
    run "$REPO_ROOT/.claude/scripts/validate-ac-verification.sh" \
        --report "$TEST_DIR/reviewer.md" --sprint "$owner" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.ac_count' <<< "$output")" -eq 1 ]
}

check_report_writer() {
    local skill="$1"
    awk 'NR == 1 { next } /^---$/ { exit } { print }' \
        "$REPO_ROOT/.claude/skills/$skill/SKILL.md" | yq -o=json '.' > "$TEST_DIR/frontmatter.json"
    run jq -e '
        .capabilities.write_files == true and
        .zones.system.permission == "none" and
        .zones.app.permission == "read" and
        .zones.state.permission == "read-write" and
        (."disallowed-tools" | index("Write") == null) and
        (."disallowed-tools" | index("Edit") == null) and
        (."disallowed-tools" | index("NotebookEdit") != null) and
        (."allowed-tools" | contains("Write")) and
        (."allowed-tools" | contains("Edit")) and
        (."allowed-tools" | contains("Bash(.claude/scripts/verdict-derive.sh *)"))
    ' "$TEST_DIR/frontmatter.json"
    [ "$status" -eq 0 ]
    run "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill "$skill" --strict --json
    [ "$status" -eq 0 ]
}

@test "issue-1195: review can persist state feedback and run its verdict check" {
    check_report_writer reviewing-code
}

@test "issue-1195: audit can persist state feedback and run its verdict check" {
    check_report_writer auditing-security
}

@test "issue-1195: invariant examples classify feedback authors as State writers" {
    run python3 - "$REPO_ROOT/.claude/rules/skill-invariants.md" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
pure_review = next(line for line in text.splitlines() if line.startswith("| Pure-review"))
assert "reviewing-code" not in pure_review
assert "auditing-security" not in pure_review
report_author = next(line for line in text.splitlines() if line.startswith("| Sprint review/audit"))
assert "reviewing-code" in report_author and "auditing-security" in report_author
assert "STATE" in report_author
exceptions = text.split("**`REVIEW_WRITE_EXCEPTIONS`**", 1)[1].split("These", 1)[0]
assert "`reviewing-code`" in exceptions and "`auditing-security`" in exceptions
PY
    [ "$status" -eq 0 ]
}

@test "CI-008: strict validation rejects a required denied command in the procedure" {
    mkdir -p "$TEST_DIR/skills/auditing-security"
    cp "$REPO_ROOT/.claude/skills/auditing-security/SKILL.md" "$TEST_DIR/skills/auditing-security/"
    cat >> "$TEST_DIR/skills/auditing-security/SKILL.md" <<'EOF'

Mandatory local check:
```bash
.claude/scripts/fixture-required.sh --check
```
EOF
    run env SKILLS_DIR="$TEST_DIR/skills" \
        "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill auditing-security --strict --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"procedure command not allowed"* ]]
    [[ "$output" == *"fixture-required.sh"* ]]
}

@test "CI-008: mandatory parallel splitting cannot declare agent_spawn false" {
    mkdir -p "$TEST_DIR/skills/reviewing-code"
    sed 's/agent_spawn: true/agent_spawn: false/' \
        "$REPO_ROOT/.claude/skills/reviewing-code/SKILL.md" > "$TEST_DIR/skills/reviewing-code/SKILL.md"
    run env SKILLS_DIR="$TEST_DIR/skills" \
        "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill reviewing-code --strict --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"procedure requires agent spawning"* ]]
}

@test "CI-008: denying all commands cannot satisfy the real audit procedure" {
    mkdir -p "$TEST_DIR/skills/auditing-security"
    cp "$REPO_ROOT/.claude/skills/auditing-security/SKILL.md" "$TEST_DIR/skills/auditing-security/"
    python3 - "$TEST_DIR/skills/auditing-security/SKILL.md" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
p.write_text(re.sub(r"  execute_commands:\n.*?  web_access:",
                    "  execute_commands: false\n  web_access:", p.read_text(), flags=re.S))
PY
    run env SKILLS_DIR="$TEST_DIR/skills" \
        "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill auditing-security --strict --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"procedure command not allowed by execute_commands"* ]]
}

@test "CI-008: command capability alone does not satisfy the native tool declaration" {
    mkdir -p "$TEST_DIR/skills/auditing-security"
    sed 's/, Bash(.claude\/scripts\/security-audit-scope.sh)//' \
        "$REPO_ROOT/.claude/skills/auditing-security/SKILL.md" > "$TEST_DIR/skills/auditing-security/SKILL.md"
    run env SKILLS_DIR="$TEST_DIR/skills" \
        "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill auditing-security --strict --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"procedure command not allowed by allowed-tools"* ]]
}

@test "HIR-002: review declarations allow the bounded wrapper and reject raw git output options" {
    local skill
    for skill in reviewing-code auditing-security; do
        mkdir -p "$TEST_DIR/skills/$skill"
        cp "$REPO_ROOT/.claude/skills/$skill/SKILL.md" "$TEST_DIR/skills/$skill/SKILL.md"
        cat >> "$TEST_DIR/skills/$skill/SKILL.md" <<'EOF'

Mandatory check:
```bash
git diff HEAD --output=src/review-output.diff -- src/input.txt
```
EOF
        run env SKILLS_DIR="$TEST_DIR/skills" \
            "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill "$skill" --strict --json
        [ "$status" -eq 1 ]
        [[ "$output" == *"procedure command not allowed"* ]]
    done
}

@test "HIR-003: attached operators are shell syntax while quoted operators are data" {
    run python3 - "$REPO_ROOT/.claude/scripts/validate-skill-procedure.py" <<'PY'
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("procedure", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
frontmatter = {
    "capabilities": {"execute_commands": {
        "allowed": [{"command": "git", "args": ["diff", "*"]}], "deny_raw_shell": True}},
    "allowed-tools": "Bash(git diff *)",
}
for command in ("git diff HEAD; printf fixture", "git diff HEAD|printf fixture",
                "git diff HEAD>src/fixture.txt", "git diff HEAD ; printf fixture",
                "git diff HEAD&&printf fixture", "git diff HEAD&printf fixture",
                "git diff HEAD<src/fixture.txt", 'git diff "$(printf fixture)"',
                'git diff "`printf fixture`"', "git diff HEAD 2>src/fixture.txt"):
    errors = module.validate(frontmatter, "```bash\n" + command + "\n```")
    assert any("raw shell" in e for e in errors), (command, errors)
for command in ("git diff HEAD", "git diff 'literal;|<>&()'",
                "git diff '$(literal)'", 'git diff "literal;|<>&()"',
                "git diff pre';|'post", 'git diff "literal\\";data"',
                r"git diff literal\;data", "git diff HEAD # comment; ignored"):
    errors = module.validate(frontmatter, "```bash\n" + command + "\n```")
    assert not errors, (command, errors)
PY
    [ "$status" -eq 0 ]
}

@test "HIR-003: strict skill entrypoint rejects attached operators on an allowed wrapper" {
    local command
    mkdir -p "$TEST_DIR/skills/auditing-security"
    for command in \
        '.claude/scripts/review-git.sh diff; printf fixture' \
        '.claude/scripts/review-git.sh diff|printf fixture' \
        '.claude/scripts/review-git.sh diff>src/fixture.txt'; do
        cp "$REPO_ROOT/.claude/skills/auditing-security/SKILL.md" "$TEST_DIR/skills/auditing-security/SKILL.md"
        printf '\n```bash\n%s\n```\n' "$command" >> "$TEST_DIR/skills/auditing-security/SKILL.md"
        run env SKILLS_DIR="$TEST_DIR/skills" \
            "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill auditing-security --strict --json
        [ "$status" -eq 1 ]
        [[ "$output" == *"procedure requires raw shell"* ]]
    done
    cp "$REPO_ROOT/.claude/skills/auditing-security/SKILL.md" "$TEST_DIR/skills/auditing-security/SKILL.md"
    printf '\n```bash\n%s\n```\n' \
        '.claude/scripts/verdict-derive.sh --file "literal;|>name" --gate audit' \
        >> "$TEST_DIR/skills/auditing-security/SKILL.md"
    run env SKILLS_DIR="$TEST_DIR/skills" \
        "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh" --skill auditing-security --strict --json
    [ "$status" -eq 0 ]
}
