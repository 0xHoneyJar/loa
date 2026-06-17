#!/usr/bin/env bats
# =============================================================================
# #1076 defect 2 — CONTEXT_CLEAR BSD-awk crash
# =============================================================================
# post-pr-context-clear.sh passed the multi-line $checkpoint_content to
# `awk -v checkpoint=...`. GNU awk / mawk tolerate an embedded newline in a -v
# value; BSD awk (macOS default) rejects it: "awk: newline in string" ->
# "[ERROR] Context clear failed". The CONTEXT_CLEAR phase could never run on
# macOS.
#
# Fix: the checkpoint is written to a temp file and streamed into awk with
# getline; the -v value is now only a filename (no embedded newline) -> portable
# across gawk / mawk / BSD awk.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/.claude/scripts/post-pr-context-clear.sh"
    [[ -f "$SCRIPT" ]] || skip "post-pr-context-clear.sh not found"

    # shellcheck disable=SC1090
    source "$SCRIPT"
    set +e  # the script sets -euo pipefail; relax for test-driver control

    WORK="$(mktemp -d)"
}

teardown() {
    [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# ---- static contract: the BSD-unsafe pattern must be gone -----------------

@test "#1076 d2: checkpoint is NOT passed to awk via a multi-line -v value" {
    run grep -qE 'awk -v checkpoint="\$checkpoint_content"' "$SCRIPT"
    [ "$status" -ne 0 ]  # pattern absent
}

@test "#1076 d2: checkpoint is streamed into awk from a file via getline" {
    grep -qE 'awk -v cpfile=' "$SCRIPT"
    grep -qE 'getline cpline < cpfile' "$SCRIPT"
}

# ---- functional regression: insertion still works -------------------------

@test "#1076 d2: checkpoint is inserted under the Session Continuity header" {
    cat > "$WORK/NOTES.md" <<'EOF'
# Session Notes

## Session Continuity

<!-- Checkpoints for session recovery -->

## Decision Log
EOF
    NOTES_FILE="$WORK/NOTES.md"
    run write_notes_checkpoint "pp-1" "https://github.com/o/r/pull/5" "5" "POST_PR_AUDIT"
    [ "$status" -eq 0 ]
    grep -q "### Post-PR Validation Checkpoint" "$WORK/NOTES.md"

    local cont_ln chk_ln dec_ln
    cont_ln=$(grep -n '## Session Continuity' "$WORK/NOTES.md" | head -1 | cut -d: -f1)
    chk_ln=$(grep -n '### Post-PR Validation Checkpoint' "$WORK/NOTES.md" | head -1 | cut -d: -f1)
    dec_ln=$(grep -n '## Decision Log' "$WORK/NOTES.md" | head -1 | cut -d: -f1)
    [ "$cont_ln" -lt "$chk_ln" ]
    [ "$chk_ln" -lt "$dec_ln" ]
}

@test "#1076 d2: no leftover awk checkpoint temp files after a run" {
    export TMPDIR="$WORK/tmp"
    mkdir -p "$TMPDIR"
    NOTES_FILE="$WORK/NOTES.md"
    printf '%s\n' '# Session Notes' '' '## Session Continuity' '' '<!-- x -->' > "$WORK/NOTES.md"

    local before after
    before=$(find "$TMPDIR" -type f | wc -l)
    run write_notes_checkpoint "pp-2" "https://github.com/o/r/pull/9" "9" "POST_PR_AUDIT"
    [ "$status" -eq 0 ]
    grep -q "### Post-PR Validation Checkpoint" "$WORK/NOTES.md"

    # The checkpoint + content temp files (mktemp under $TMPDIR) must be gone:
    # temp_file is mv'd onto NOTES.md and cp_file is rm'd.
    after=$(find "$TMPDIR" -type f | wc -l)
    [ "$before" -eq "$after" ]
}
