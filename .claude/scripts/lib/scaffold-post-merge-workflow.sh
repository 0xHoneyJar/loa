#!/usr/bin/env bash
# =============================================================================
# scaffold-post-merge-workflow.sh — single source of truth for #669 scaffold
# =============================================================================
# Bridgebuilder F2 + F6 (PR #671): the scaffold helper used to live in three
# places (mount-loa.sh, mount-submodule.sh, and an inline copy in
# tests/unit/mount-workflow-scaffold.bats), held together by a "keep in sync"
# comment. Three-way duplication is exactly the maintenance hazard the
# Bridgebuilder flagged — drift between test fixture and production passes
# tests while breaking users.
#
# This lib is the canonical implementation. Sourced by both installer
# scripts AND the test file so the test exercises the same code that runs
# in production. Pattern mirrors lib/portable-realpath.sh and
# lib/flatline-exit-classifier.sh.
#
# Usage (sourced):
#   source scaffold-post-merge-workflow.sh
#   scaffold_post_merge_workflow [source_path]
#
# Args:
#   $1 — optional absolute path to a workflow file. When empty/absent,
#        the helper falls through to `git checkout
#        $LOA_REMOTE_NAME/$LOA_BRANCH -- .github/workflows/post-merge.yml`.
#
# Behavior:
#   - Idempotent: if `.github/workflows/post-merge.yml` already exists,
#     preserves it (matches sync_optional_file semantics)
#   - Mode-agnostic: direct mode passes empty (uses git checkout fallback);
#     submodule mode passes the in-tree submodule path
#   - Always returns 0 (best-effort scaffold; never aborts the installer)
#   - Re-mount legacy-guard check (cycle-136 C-1, bd-akkgq, DEC-1078 …
#     DEC-1081): when the target already exists, the `simple-release` job's
#     own single-line `if:` is read with one awk pass (no yq) — job-scoped,
#     at the job's child indentation, outside block scalars, comments and
#     other jobs. If it is the legacy guard (`pr_type != 'cycle' && …`, which
#     sends cycle-135 `housekeeping` merges to the orchestrator — bd-nr5i6),
#     one WARN on stderr names the allowlist replacement; the file is never
#     modified. The allowlist guard and anything customised stay silent.
#
# Environment:
#   LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 — opt-in: rewrite exactly that one
#     physical `if:` line to the allowlist guard (indentation, quoting style,
#     a trailing comment and CRLF kept; symlink refused; the line re-read just
#     before the write; temp file in the same directory, mode kept, `mv -f`)
#     and print a one-line notice. Anything it cannot rewrite safely (no
#     single job-level legacy `if:`, a `${{ }}` wrapper, a symlink, a write
#     failure) is a WARN with the file left unchanged — still return 0.
# =============================================================================

# The two guard texts (sdd.md § 5.1); the allowlist is the shipped
# .github/workflows/post-merge.yml simple-release guard since cycle-135.
_LOA_SCAFFOLD_LEGACY_GUARD="needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''"
_LOA_SCAFFOLD_ALLOWLIST_GUARD="(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''"

# legacy_release_guard_check <target> — WARN about (or, on opt-in, fix) the
# legacy simple-release guard of an existing workflow. Always returns 0: both
# callers run under `set -e` and a refusal is a WARN, not a mount failure
# (DEC-1077).
legacy_release_guard_check() {
    local target="$1"
    local fix="${LOA_SCAFFOLD_FIX_RELEASE_GUARD:-}"
    local refuse_msg="[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but $target has no single job-level simple-release if: carrying the legacy guard — left unchanged"
    local rec="" kind="" lineno="" cr="" quote="" wrapped="" indent="" comment="" norm="" raw=""

    # Step 0: a regular, readable file — never follow a symlink
    if [[ -L "$target" || ! -f "$target" || ! -r "$target" ]]; then
        if [[ "$fix" == "1" ]]; then printf '%s\n' "$refuse_msg" >&2; fi
        return 0
    fi

    # Steps 1–4 in one awk pass (DEC-1078 … DEC-1080). Emits one record:
    #   none | notsingle | found SEP line SEP cr SEP quote SEP wrapped SEP indent SEP comment SEP normalised SEP raw-line
    # (\047 is a single quote: the program lives inside bash single quotes.)
    rec=$(awk '
        function ind(s) { match(s, /^ */); return RLENGTH }
        BEGIN { SEP = "\037"; phase = 0; J = -1; keys = 0; inblock = 0; C = -1; ncand = 0; inscalar = 0 }
        {
            line = $0; cr = 0
            if (sub(/\r$/, "", line)) cr = 1
            if (line ~ /^[[:space:]]*$/) next
            n = ind(line)
            # block-scalar content: every line deeper than the opener (DEC-1080)
            if (inscalar) { if (n > k) next; inscalar = 0 }
            if (line ~ /^[[:space:]]*#/) next
            if (phase == 0) { if (line ~ /^jobs:[[:space:]]*(#.*)?$/) phase = 1 }
            else if (phase == 1) {
                if (n == 0) { phase = 2; inblock = 0 }
                else {
                    if (J < 0) J = n
                    if (n <= J) {
                        # the job block ends at the first line not deeper than J (DEC-1079)
                        inblock = 0
                        if (n == J && substr(line, n + 1) ~ /^simple-release:([[:space:]]|$)/) {
                            keys++; if (keys == 1) inblock = 1
                        }
                    } else if (inblock) {
                        if (C < 0) C = n
                        if (n == C && substr(line, n + 1) ~ /^if:([[:space:]]|$)/) {
                            ncand++; cline = line; craw = $0; cnum = NR; ccr = cr
                        }
                    }
                }
            }
            v = line; sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /:[[:space:]]+[|>][-+0-9]*$/ || v ~ /^[[:space:]]*-[[:space:]]+[|>][-+0-9]*$/) { inscalar = 1; k = n }
        }
        END {
            if (keys != 1) { print "none"; exit }
            if (ncand != 1) { print "notsingle"; exit }
            ci = ind(cline); v = substr(cline, ci + 4); comment = ""
            if (match(v, /[[:space:]]+#.*$/)) { comment = substr(v, RSTART); v = substr(v, 1, RSTART - 1) }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (v == "" || v ~ /^[|>]/ || v ~ /[{[]$/) { print "notsingle"; exit }
            quote = "none"
            if (length(v) >= 2 && v ~ /^".*"$/) { quote = "double"; v = substr(v, 2, length(v) - 2) }
            else if (length(v) >= 2 && v ~ /^\047.*\047$/) { quote = "single"; v = substr(v, 2, length(v) - 2); gsub(/\047\047/, "\047", v) }
            wrapped = 0
            if (v ~ /^\$\{\{.*\}\}$/) { wrapped = 1; v = substr(v, 4, length(v) - 5) }
            gsub(/[[:space:]]+/, " ", v); gsub(/^ | $/, "", v)
            print "found" SEP cnum SEP ccr SEP quote SEP wrapped SEP ci SEP comment SEP v SEP craw
        }' "$target" 2>/dev/null) || rec=""
    IFS=$'\037' read -r kind lineno cr quote wrapped indent comment norm raw <<<"$rec" || true

    if [[ "$kind" == "found" && "$norm" == "$_LOA_SCAFFOLD_ALLOWLIST_GUARD" ]]; then
        return 0
    fi
    if [[ "$kind" != "found" || "$norm" != "$_LOA_SCAFFOLD_LEGACY_GUARD" ]]; then
        # not ours to judge (customised, multi-line, duplicated, no job)
        if [[ "$fix" == "1" ]]; then printf '%s\n' "$refuse_msg" >&2; fi
        return 0
    fi

    printf '%s\n' "[scaffold] WARN: $target keeps the legacy simple-release guard (pr_type != 'cycle' && pr_number != ''); since Loa cycle-135 housekeeping merges classify 'housekeeping' and this guard sends them to the orchestrator, which refuses. Replace it with: $_LOA_SCAFFOLD_ALLOWLIST_GUARD  — or re-run the mount with LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 to rewrite that one line (bd-nr5i6)" >&2
    if [[ "$fix" != "1" ]]; then
        return 0
    fi
    if [[ "$wrapped" == "1" ]]; then
        # a ${{ }} wrapper is detected but never rewritten (sdd.md § 7)
        printf '%s\n' "$refuse_msg" >&2
        return 0
    fi
    _legacy_release_guard_rewrite "$target" "$lineno" "$cr" "$quote" "$indent" "$comment" "$raw"
    return 0
}

# _legacy_release_guard_rewrite <target> <line> <cr> <quote> <indent> <comment> <raw-line>
# The safe write (DEC-1081). Returns 0; every failure is one WARN naming it.
_legacy_release_guard_rewrite() {
    local target="$1" lineno="$2" cr="$3" quote="$4" indent="$5" comment="$6" raw="$7"
    local dir="" tmp="" cur="" q="" sq="'" val="$_LOA_SCAFFOLD_ALLOWLIST_GUARD" newline="" nonl=0 why=""

    dir=$(dirname "$target" 2>/dev/null) || dir="."
    if [[ -L "$target" ]]; then
        why="the target is a symlink"
    elif [[ ! -w "$target" ]]; then
        why="not writable"
    else
        # re-read the physical line just before the write: it must not have moved
        cur=$(awk -v n="$lineno" 'NR == n { print; exit }' "$target" 2>/dev/null) || cur=""
        if [[ "$cur" != "$raw" ]]; then
            why="line $lineno changed since detection"
        elif ! tmp=$(mktemp "$dir/.post-merge.XXXXXX" 2>/dev/null); then
            why="no temp file in $dir"
            tmp=""
        fi
    fi

    if [[ -z "$why" ]]; then
        case "$quote" in
            double) q='"' ;;
            single) q="'"; val="${val//$sq/$sq$sq}" ;;
        esac
        printf -v newline '%*s' "$indent" ''
        newline="${newline}if: ${q}${val}${q}${comment}"
        if [[ "$cr" == "1" ]]; then newline+=$'\r'; fi
        if [[ -n "$(tail -c 1 "$target" 2>/dev/null)" ]]; then nonl=1; fi
        # cp -p gives the temp file the original mode; the redirect then keeps it
        if ! cp -p "$target" "$tmp" 2>/dev/null; then
            why="the mode could not be copied"
        elif ! LOA_SCAFFOLD_NEW_LINE="$newline" awk -v n="$lineno" -v nonl="$nonl" '
                { if (NR > 1) print prev; prev = (NR == n) ? ENVIRON["LOA_SCAFFOLD_NEW_LINE"] : $0 }
                END { if (NR > 0) printf "%s%s", prev, (nonl ? "" : "\n") }' "$target" > "$tmp" 2>/dev/null; then
            why="the temp file could not be written"
        elif ! mv -f "$tmp" "$target" 2>/dev/null; then
            why="the temp file could not be moved over the target"
        fi
        if [[ -n "$why" ]]; then rm -f "$tmp" 2>/dev/null || true; fi
    fi

    if [[ -n "$why" ]]; then
        printf '%s\n' "[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but $target could not be rewritten ($why) — left unchanged" >&2
        return 0
    fi
    printf '%s\n' "[scaffold] fixed: $target simple-release if: → allowlist guard (one line changed; bd-nr5i6)" >&2
    return 0
}

scaffold_post_merge_workflow() {
    local source_path="${1:-}"
    local target=".github/workflows/post-merge.yml"

    if [[ -f "$target" ]]; then
        # Idempotency: preserve user-customized workflow on re-mount; only
        # warn about (or, on opt-in, fix) the legacy release guard (bd-akkgq)
        legacy_release_guard_check "$target"
        return 0
    fi

    mkdir -p .github/workflows

    if [[ -n "$source_path" && -f "$source_path" ]]; then
        cp "$source_path" "$target"
        return 0
    fi

    # Fallback: git checkout from configured upstream (direct-install mode)
    if [[ -n "${LOA_REMOTE_NAME:-}" && -n "${LOA_BRANCH:-}" ]]; then
        git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- "$target" 2>/dev/null || true
    fi

    return 0
}
