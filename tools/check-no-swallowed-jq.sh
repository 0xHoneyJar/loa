#!/usr/bin/env bash
# =============================================================================
# tools/check-no-swallowed-jq.sh
#
# sprint-bug-208 / #1025 — tripwire scan: NO output-swallowing jq/yq shapes on
# gate-critical scripts. The shape `jq … 2>/dev/null || echo <default>` (and
# its `|| echo`-without-stderr-suppression variant) converts a jq parse or
# extraction failure into a clean default with exit 0 — the literal mechanism
# behind KF-004 (zero-findings canonical verdicts masking real findings,
# recurrence ≥20) and KF-015 (silent-clean red-team gate pass, 4/4 sprints).
# See grimoires/loa/known-failures.md.
#
# Verdict/finding/count-bearing jq extraction MUST funnel through `jq_strict`
# (.claude/scripts/compat-lib.sh) so parse failures stay LOUD. The repo
# already forbids the analogous shape for `git stash`
# (.claude/rules/stash-safety.md, #555); this scanner fences the jq class.
# Modeled on tools/check-no-raw-sha256sum.sh (KF-012 precedent).
#
# Detection logic (in order):
#   1. Default mode scans the ENFORCED_FILES gate-critical set plus the
#      extension-agnostic .claude/scripts/red-team-* glob (new red-team
#      scripts are auto-enforced even without a .sh extension — DISS-001;
#      the _is_script filter below decides scriptness, not the glob). `--root <dir>` scans a directory tree instead (used
#      by the bats contract tests and the incremental #1025 sweep).
#   2. File-type filter (--root mode): .sh/.bash/.legacy/.bats extensions or
#      a bash/sh shebang — same approach as check-no-raw-sha256sum.sh, so
#      extensionless shell scripts can't slip through (DISS-002 class).
#   3. Skip line-leading comments (`# ...`).
#   4. Skip lines with the `# check-no-swallowed-jq: ok` suppression marker.
#      Un-migrated legacy sites on the enforced set carry this marker with a
#      tracking note (`pending #1025 sweep`); NEW sites are flagged at PR
#      time. Use sparingly, with reviewer rationale.
#   5. Match: a jq OR yq invocation followed on the same line by `|| echo` or
#      `|| printf`. `2>/dev/null` is deliberately NOT required for the
#      match — stderr suppression only hides diagnostics; the `||` default
#      is what swallows the verdict. yq joined the matcher in cycle-123
#      (#1065): construct-index-gen.sh's swallow sites are ALL yq, so a
#      jq-only matcher made its enforcement vacuous — a fence reporting
#      safety it did not provide.
#
# **Tripwire scope (NOT exhaustive defense)**: same caveats as
# check-no-raw-sha256sum.sh — variable-expanded/eval/printf-assembled jq,
# multi-line forms, and the sibling `|| true` shape are out of scope here.
# The jq_strict helper + its bats contract (tests/unit/compat-lib-jq-strict
# .bats) are the load-bearing boundary; this scanner is one tripwire layer.
# Remaining repo-wide sites are follow-up sweep work tracked in #1025.
#
# Usage:
#   tools/check-no-swallowed-jq.sh                 # scan enforced gate-critical set
#   tools/check-no-swallowed-jq.sh --root <dir>    # scan custom root (recursive)
#   tools/check-no-swallowed-jq.sh --quiet         # exit-code only
#
# Exit codes:
#   0  no violations
#   1  violations found (paths printed to stderr)
#   2  argument / I/O error
#
# Tested by tests/integration/check-no-swallowed-jq.bats.
# =============================================================================

set -euo pipefail

# Gate-critical scripts where the swallow shape is forbidden — the #1025
# scoped enforcement set (adversarial-review, flatline-orchestrator,
# scoring-engine, post-pr-triage, construct-index-gen; red-team-* resolved by
# the extension-agnostic glob below).
# Paths are repo-root-relative; default mode assumes invocation from the
# project root (as CI does).
ENFORCED_FILES=(
    ".claude/scripts/adversarial-review.sh"
    ".claude/scripts/flatline-orchestrator.sh"
    ".claude/scripts/scoring-engine.sh"
    ".claude/scripts/post-pr-triage.sh"
    ".claude/scripts/construct-index-gen.sh"
)

QUIET=0
ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q) QUIET=1; shift ;;
        --root)
            [[ $# -ge 2 ]] || { printf 'check-no-swallowed-jq.sh: --root requires a directory argument\n' >&2; exit 2; }
            ROOT="$2"; shift 2
            ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf 'check-no-swallowed-jq.sh: unknown arg %q\n' "$1" >&2
            exit 2
            ;;
    esac
done

# Bash/sh script detection — same approach as check-no-raw-sha256sum.sh.
_is_script() {
    local path="$1"
    case "$path" in
        *.sh|*.bash|*.legacy|*.bats) return 0 ;;
    esac
    local first_line
    first_line=$(head -c 256 "$path" 2>/dev/null | head -1 || true)
    [[ "$first_line" == "#!"*"bash"* ]] && return 0
    [[ "$first_line" == "#!"*"sh" ]] && return 0
    [[ "$first_line" == "#!"*"sh "* ]] && return 0
    return 1
}

AWK_SCAN=$(cat <<'AWK'
BEGIN {
    in_heredoc = 0
    hd_term = ""
    hd_dash = 0
    hd_exec = 0
    # Interpreters whose heredoc BODY executes: violations inside are real
    # and must stay scanned (fail-closed direction of the tripwire).
    split("sh bash zsh ksh dash ash python python2 python3 perl ruby node deno php", _il, " ")
    for (_i in _il) INTERP[_il[_i]] = 1
}

function _line_has_swallowed_jq(line) {
    return (line ~ /(^|[^[:alnum:]_])[jy]q[[:space:]].*\|\|[[:space:]]*(echo|printf)([^[:alnum:]_]|$)/)
}

# The command word governing a heredoc whose << starts at pos rs — used to
# classify the body as inert data (cat, tee, assignments) vs executed code.
function _hd_command(line, rs,    prefix, n, w, i, words) {
    prefix = substr(line, 1, rs - 1)
    # Only the simple command directly feeding the heredoc matters.
    sub(/.*[|;&(`]/, "", prefix)
    n = split(prefix, words, /[[:space:]]+/)
    for (i = 1; i <= n; i++) {
        w = words[i]
        if (w == "" || w ~ /^-/) continue                    # options / bare `-`
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue         # env assignments
        if (w == "env" || w == "sudo" || w == "command" || w == "exec" || w == "nohup" || w == "time") continue
        sub(/.*\//, "", w)                                   # strip path prefix
        return w
    }
    return ""
}

function _start_heredoc(line,    scan, pre, sq, dq, rest, term, rs, rl, cmd, post) {
    scan = line
    # `<<` inside arithmetic is a bit-shift, not a heredoc (the
    # flatline-error-handler.sh:202 false-negative class — a bogus
    # terminator silently skipped the rest of the file).
    gsub(/\$\(\(.*\)\)/, "", scan)
    gsub(/\(\(.*\)\)/, "", scan)
    # `<<<` here-strings never open a body.
    gsub(/<<<[[:space:]]*("[^"]*"|'[^']*'|[^[:space:]]+)/, "", scan)
    if (match(scan, /<<-?[[:space:]]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
        rs = RSTART; rl = RLENGTH
        # Quote-parity guard: a << inside an open string literal is a
        # mention (`echo "use <<EOF here"`), not an opener.
        pre = substr(scan, 1, rs - 1)
        sq = gsub(/\047/, "", pre)
        dq = gsub(/"/, "", pre)
        if (sq % 2 == 1 || dq % 2 == 1) return
        hd_dash = (substr(scan, rs, 3) == "<<-")
        rest = substr(scan, rs + (hd_dash ? 3 : 2), rl - (hd_dash ? 3 : 2))
        gsub(/^[[:space:]]+/, "", rest)
        term = rest
        if (substr(term, 1, 1) == "\047" || substr(term, 1, 1) == "\"") term = substr(term, 2)
        if (substr(term, length(term), 1) == "\047" || substr(term, length(term), 1) == "\"") term = substr(term, 1, length(term) - 1)
        sub(/[[:space:]].*$/, "", term)
        if (term != "") {
            hd_term = term
            in_heredoc = 1
            # A body is only truly inert when the terminator is QUOTED
            # (<<'EOF' — no expansion) AND nothing executes it. Unquoted
            # heredocs still run $() substitutions in their body, and
            # interpreter-fed bodies (bash <<EOF …, cat <<EOF | bash) run
            # verbatim — both stay scanned.
            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
            cmd = _hd_command(scan, rs)
            post = substr(scan, rs + rl)
            hd_exec = (cmd in INTERP) || !hd_quoted || \
                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
        }
    }
}

# Step 1: inside a heredoc body. Inert bodies (cat/tee/assignment fixtures,
# documentation) are skipped until the terminator — the false-positive class
# this state machine exists for. Executed bodies (bash <<EOF …) keep being
# scanned: their contents run, so a swallow shape there is a real violation.
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
    if (hd_dash) {
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
    }
    if (hd_exec) {
        if ($0 ~ /^[[:space:]]*#/) next
        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
    }
    next
}

# Step 2: skip line-leading comments (a << in a comment opens nothing).
/^[[:space:]]*#/ { next }

# Step 3: skip lines with the suppression marker — but still register a
# heredoc opener on the marker line, else `cat <<EOF  # …: ok` leaks its
# body into the scan.
/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }

# Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
# same line. LHS word-boundary so identifiers like `dijq` don't match; jq
# must be followed by whitespace (an invocation always has arguments, and
# this keeps `jq_strict` from matching). RHS word-boundary on echo/printf
# so `echo_handler` doesn't match.
{
    if (_line_has_swallowed_jq($0)) {
        print FILENAME ":" NR ":" $0
    }
    _start_heredoc($0)
}
AWK
)

# Assemble the scan file list (NUL-delimited for path safety).
_list_files() {
    if [[ -n "$ROOT" ]]; then
        find "$ROOT" -type f -print0 | sort -z
        return 0
    fi
    local f
    local found_any=0
    for f in "${ENFORCED_FILES[@]}" .claude/scripts/red-team-*; do
        # Missing enforced files are skipped (consumer installs may not ship
        # every gate script); an unmatched glob falls through the -f test.
        if [[ -f "$f" ]]; then
            found_any=1
            printf '%s\0' "$f"
        fi
    done
    if [[ "$found_any" -eq 0 ]]; then
        printf 'check-no-swallowed-jq.sh: no enforced files found — run from the project root\n' >&2
        return 1
    fi
    return 0
}

if [[ -n "$ROOT" && ! -d "$ROOT" ]]; then
    printf 'check-no-swallowed-jq.sh: scan root %q not a directory\n' "$ROOT" >&2
    exit 2
fi

_file_list_tmp="$(mktemp)"
trap 'rm -f "$_file_list_tmp"' EXIT
if ! _list_files > "$_file_list_tmp"; then
    exit 2
fi

violations=""
while IFS= read -r -d '' f; do
    if ! _is_script "$f"; then
        continue
    fi
    file_hits=$(awk "$AWK_SCAN" "$f")
    if [[ -n "$file_hits" ]]; then
        violations+="$file_hits"$'\n'
    fi
done < "$_file_list_tmp"

if [[ -n "$violations" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        printf 'sprint-bug-208 / #1025: output-swallowing jq shape detected (jq ... || echo <default>)\n' >&2
        printf 'This shape converts parse failures into clean defaults — the KF-004/KF-015 mechanism.\n' >&2
        printf 'Route verdict-bearing jq through jq_strict (.claude/scripts/compat-lib.sh) and handle\n' >&2
        printf 'the non-zero exit loudly (malformed/degraded record), never with a clean default.\n' >&2
        printf '\nSuppression marker (use sparingly, with a tracking note):\n' >&2
        printf '  # check-no-swallowed-jq: ok (<rationale / tracking ref>)\n' >&2
        printf '\nViolations:\n' >&2
        printf '%s' "$violations" | sed '/^$/d' >&2
    fi
    exit 1
fi

[[ $QUIET -eq 0 ]] && printf 'OK — no output-swallowing jq shapes on the enforced set\n'
exit 0
