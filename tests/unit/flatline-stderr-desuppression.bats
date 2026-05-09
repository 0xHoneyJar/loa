#!/usr/bin/env bats
# =============================================================================
# tests/unit/flatline-stderr-desuppression.bats
#
# cycle-102 Sprint 1 (T1.8 partial — AC-1.4) — Pipeline stderr de-suppression.
# Closes #780 Tier 1 partial.
#
# Per SDD §4.5: `flatline-orchestrator.sh` previously suppressed
# `red-team-pipeline.sh` stderr via `2>/dev/null`, masking cheval /
# model-adapter / probe-gate diagnostics during silent-degradation events.
# This test pins the de-suppression so a future refactor can't accidentally
# re-introduce the suppression.
#
# Test taxonomy:
#   T1   Orchestrator parses cleanly (no syntax regression)
#   T2   The red-team-pipeline.sh invocation NO LONGER carries `2>/dev/null`
#   T3   The de-suppression rationale comment is present (anchor)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    [[ -f "$ORCHESTRATOR" ]] || { printf 'FATAL: missing %s\n' "$ORCHESTRATOR" >&2; return 1; }
}

@test "T1: flatline-orchestrator.sh parses with bash -n" {
    bash -n "$ORCHESTRATOR"
}

@test "T2: rt_pipeline invocation block has NO fd-2-to-/dev/null redirect (closes FIND-007 + DISS-003)" {
    # BB iter-2 FIND-007 (low): the prior assertion only forbade same-line
    # `$rt_pipeline.*2>/dev/null`. Equivalent forms could slip through:
    #   2> /dev/null            (space)
    #   `(\$rt_pipeline ...) 2>/dev/null`   (subshell-level)
    #   `{ ...; } 2>/dev/null`  (block-level)
    # Now we extract the rt_result=$(...) block (from `rt_result=$(` line
    # through the matching `)`-after-rt_pipeline-args) and assert NO
    # fd-2 redirect appears anywhere within it.
    # cycle-102 Sprint 1C T1C.6 (closes DISS-003 BLOCKING from sprint-1B
    # cross-model review): replaced fragile `\) \|\| {` literal end-anchor
    # with a balanced-paren counter that tracks the matching `)` of the
    # `$(...)` command substitution regardless of trailing syntax. The
    # prior anchor failed open on any orchestrator refactor that changed
    # the post-`)` form (line-split, no-brace, if-then-else, etc.).
    #
    # Caveat: counts parens inside strings/heredocs as if they were code.
    # For the orchestrator's rt_pipeline block — argv is a list of literal
    # flags + `"$var"` references, no embedded parens — this approximation
    # holds. If a future refactor introduces literal parens in string args,
    # switch to a real bash parser. For sprint-1C scope, the counter is
    # sufficient and DISS-003's anchor fragility is closed.
    block="$(awk '
        BEGIN { in_blk=0; depth=0 }
        !in_blk && /rt_result=\$\("\$rt_pipeline"/ {
            in_blk=1
            line=$0
            opener_idx = index(line, "$(")
            for (i = opener_idx + 2; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "(") depth++
                else if (c == ")") depth--
            }
            depth++  # the `$(` opens depth 1
            print
            if (depth <= 0) { exit }
            next
        }
        in_blk {
            print
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "(") depth++
                else if (c == ")") depth--
            }
            if (depth <= 0) { exit }
        }
    ' "$ORCHESTRATOR")"
    [ -n "$block" ] || {
        printf 'FAIL: could not locate rt_result=$(...) block — anchor changed?\n' >&2
        return 1
    }
    # The extracted block MUST end at the closing `)`. If the counter
    # scanned to EOF (a regression), the last line wouldn't contain `)`.
    echo "$block" | tail -1 | grep -qE '\)' || {
        printf 'FAIL: balanced-paren counter ran past the closing `)` — regression\n' >&2
        printf 'Last block line:\n%s\n' "$(echo "$block" | tail -1)" >&2
        return 1
    }
    # Forbid all flavors of fd-2 → /dev/null (with or without space) within
    # the rt_pipeline call's bounds.
    ! echo "$block" | grep -qE '2>[[:space:]]*/dev/null'
}

@test "T2b: balanced-paren counter handles bare or-handle-failure end form (DISS-003 regression pin)" {
    # Synthetic: a flatline-orchestrator-shaped file ending the rt_pipeline
    # call with `) || handle_failure` (no brace) — the previous awk anchor
    # `\) \|\| {` would NOT have matched, scanning to EOF and false-flagging
    # any unrelated `2>/dev/null` later in the file. The balanced-paren
    # counter MUST find the matching `)` regardless of trailing syntax.
    local synth="$BATS_TEST_TMPDIR/synth-orchestrator.sh"
    cat > "$synth" <<'EOSCRIPT'
#!/usr/bin/env bash
function dispatch() {
    rt_result=$("$rt_pipeline" \
        --doc "$doc" \
        --json) || handle_failure
    echo "$rt_result"
}
# Unrelated suppression elsewhere — must NOT contaminate T2's check
log "done" 2>/dev/null
EOSCRIPT

    block="$(awk '
        BEGIN { in_blk=0; depth=0 }
        !in_blk && /rt_result=\$\("\$rt_pipeline"/ {
            in_blk=1
            line=$0
            opener_idx = index(line, "$(")
            for (i = opener_idx + 2; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "(") depth++
                else if (c == ")") depth--
            }
            depth++
            print
            if (depth <= 0) { exit }
            next
        }
        in_blk {
            print
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "(") depth++
                else if (c == ")") depth--
            }
            if (depth <= 0) { exit }
        }
    ' "$synth")"

    # The block must include rt_pipeline call args; must NOT include the
    # unrelated `2>/dev/null` line that appears AFTER the `)` close.
    [[ "$block" == *'rt_pipeline'* ]]
    [[ "$block" == *'--doc'* ]]
    [[ "$block" != *'log "done" 2>/dev/null'* ]] || {
        printf 'REGRESSION: counter scanned past `)` close into unrelated code\n' >&2
        printf 'Block:\n%s\n' "$block" >&2
        return 1
    }
}

@test "T3: de-suppression rationale comment anchored (regression guard)" {
    grep -qE "AC-1\.4.*pipeline stderr de-suppression" "$ORCHESTRATOR" || {
        printf 'FAIL: missing AC-1.4 de-suppression rationale comment\n' >&2
        printf 'A future refactor that re-introduces 2>/dev/null without this\n' >&2
        printf 'comment would silently revert vision-019 NFR — the rationale\n' >&2
        printf 'is the regression guard.\n' >&2
        return 1
    }
}
