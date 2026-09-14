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
