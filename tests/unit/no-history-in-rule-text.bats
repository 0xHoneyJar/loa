#!/usr/bin/env bats
# =============================================================================
# tests/unit/no-history-in-rule-text.bats — cycle-124 FR-8 / AC-8.2
#
# History narrative does not belong in rule text: across the audited set
# (CLAUDE.loa.md, the 13 oversized skills, every protocol, the five Flatline
# personas) the tokens `cycle-NNN`, `#NNNN` and `KF-NNN` may appear only
#   * in a `## Provenance` footer (that heading to end of file),
#   * inside a `<!-- provenance: … -->` comment,
#   * as a KF pointer that IS the instruction (a line that also names
#     known-failures.md, kf-write-lib.sh or the KF surface),
#   * inside a backticked repository path (`grimoires/loa/runbooks/cycle-109-rollback.md`
#     is a pointer, not a story).
# Every surviving MUST/NEVER/ALWAYS line in the same set names the hook or
# validator that enforces it, or reads as plain rule + reason (NH-2 is the
# grep-shaped half of that rule: no bare "NEVER … (cycle-NNN)" narratives).
# Red until the Sprint 3 audit lands.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDITED=(
        .claude/loa/CLAUDE.loa.md
        .claude/skills/rtfm-testing/SKILL.md .claude/skills/bug-triaging/SKILL.md
        .claude/skills/translating-for-executives/SKILL.md .claude/skills/planning-sprints/SKILL.md
        .claude/skills/simstim-workflow/SKILL.md .claude/skills/riding-codebase/SKILL.md
        .claude/skills/autonomous-agent/SKILL.md .claude/skills/discovering-requirements/SKILL.md
        .claude/skills/deploying-infrastructure/SKILL.md .claude/skills/auditing-security/SKILL.md
        .claude/skills/reviewing-code/SKILL.md .claude/skills/implementing-tasks/SKILL.md
        .claude/skills/run-mode/SKILL.md
        .claude/skills/flatline-reviewer/persona.md .claude/skills/flatline-skeptic/persona.md
        .claude/skills/flatline-scorer/persona.md .claude/skills/flatline-attacker/persona.md
        .claude/skills/gpt-reviewer/persona.md
    )
    while IFS= read -r p; do AUDITED+=("$p"); done < <(cd "$PROJECT_ROOT" && ls .claude/protocols/*.md)
}

# Print offending lines (file:line:text) for one file.
history_hits() {
    awk '
        /^## Provenance/ { footer = 1 }
        footer { next }
        {
            if ($0 ~ /known-failures|kf-write-lib|KF surface/) next   # KF pointer IS the instruction
            line = $0
            gsub(/<!-- provenance:[^>]*-->/, "", line)   # provenance comments
            gsub(/`[^`]*\/[^`]*`/, "", line)             # backticked repo paths
            if (line ~ /cycle-[0-9][0-9][0-9]|#[0-9][0-9][0-9][0-9]?|KF-[0-9][0-9][0-9]/)
                printf "%s:%d:%s\n", FILENAME, NR, $0
        }' "$1"
}

@test "NH-1 zero cycle/PR/KF tokens outside provenance footers across the audited set" {
    local total=0 f hits
    for f in "${AUDITED[@]}"; do
        hits="$(history_hits "$PROJECT_ROOT/$f")"
        if [ -n "$hits" ]; then
            echo "$hits"
            total=$((total + $(printf '%s\n' "$hits" | wc -l)))
        fi
    done
    echo "history tokens in rule text: $total"
    [ "$total" -eq 0 ]
}

@test "NH-2 no MUST/NEVER/ALWAYS line carries a bare history token" {
    local n=0 f
    for f in "${AUDITED[@]}"; do
        n=$((n + $(history_hits "$PROJECT_ROOT/$f" | grep -cE '\b(MUST|NEVER|ALWAYS)\b' || true)))
    done
    [ "$n" -eq 0 ]
}

@test "NH-3 the exemptions are real: a provenance footer, a provenance comment, a KF pointer and a runbook path are not counted" {
    local f="$BATS_TEST_TMPDIR/x.md"
    cat > "$f" <<'MD'
# Rule
Open `grimoires/loa/known-failures.md` at the `## KF-004` heading.
Rollback per `grimoires/loa/runbooks/cycle-109-rollback.md`.
<!-- provenance: cycle-124 #1260 -->

## Provenance
cycle-119 #1189 KF-004
MD
    [ -z "$(history_hits "$f")" ]
    local g="$BATS_TEST_TMPDIR/y.md"
    printf '# Rule\nNEVER do X (cycle-122).\n\n## Provenance\ncycle-122\n' > "$g"
    [ "$(history_hits "$g" | wc -l)" -eq 1 ]
}
