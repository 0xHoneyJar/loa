#!/usr/bin/env bash
# =============================================================================
# tools/check-no-raw-curl.sh
#
# cycle-099 sprint-1E.c.3.c — strict scan: NO raw curl/wget invocations in
# bash scripts outside the canonical exemption set. All HTTP calls in Loa
# bash code MUST funnel through `endpoint_validator__guarded_curl` (the
# wrapper in `.claude/scripts/lib/endpoint-validator.sh`) so URL allowlist
# enforcement, smuggling defenses, redirect chain validation, and DNS-
# rebinding defense apply uniformly.
#
# **Tripwire scope (NOT exhaustive defense)**: the scanner enforces the
# `curl|wget` literal-token contract for files that look like bash scripts.
# It is one layer of a multi-layer defense. The wrapper itself, the
# allowlist, the redirect chain, and DNS-rebinding defense are the
# load-bearing security boundaries. Specifically OUT of scope for the
# scanner (cypherpunk review C2/C3 — accepted risks):
#   - Variable-expanded invocations (`CMD=curl; $CMD ...`)
#   - eval / printf-assembled curl (`eval "${EVIL}..."`)
#   - bash builtins like `exec 3<>/dev/tcp/<host>/<port>`
#   - Out-of-process exfil (nc, python urlopen, perl LWP, etc.)
#   - Content-blind exempt-file growth (BB iter-1 F17): once on the
#     EXEMPT_FILES list, ALL raw curl/wget in the file is unscanned.
#     A future PR adding a third raw curl to mount-loa.sh would not be
#     caught. Mitigation: per-exempt-file PR review (each exempt file is
#     listed in this scanner with rationale); each exempt file is
#     hardened with --proto =https / --max-redirs / --max-time / etc.
#     in its own source. Scanner-level enforcement of those defenses
#     is a follow-up sprint candidate.
# These are policy-violation patterns; PR review remains the gate.
#
# Exempt files (each with rationale):
#   - .claude/scripts/lib/endpoint-validator.sh
#       The wrapper itself.
#   - .claude/scripts/mount-loa.sh
#       Bootstrap; .venv may not be installed yet. Hardened with
#       --proto =https, --proto-redir =https, --max-redirs 10, plus a
#       dot-dot regex defense on caller-supplied refs.
#   - .claude/scripts/model-health-probe.sh
#       Legacy alert webhook path; operator-supplied dynamic webhook URL
#       cannot be statically allowlisted. Opt-in to wrapper-routed dispatch
#       via .loa.config.yaml::model_health_probe.alert_webhook_endpoint_validator_enabled.
#   - .claude/scripts/model-adapter.sh.legacy
#       Deprecated legacy adapter shim. New code MUST not add raw curl here;
#       migration to the wrapper is deferred to the cycle-099 legacy sunset
#       path (Sprint 4 gate). Tracked in cycle-099 sprint plan.
#
# Detection logic (in order):
#   1. File-type filter: scan `.sh` / `.bash` / `.legacy` extensions PLUS
#      extension-less files with a bash/sh shebang. Other files (binaries,
#      READMEs, docs) are skipped — addresses cypherpunk C1 (legacy file
#      blindness) + M2 (.bash extension blindness).
#   2. Heredoc state tracker — `<<EOF` / `<<'EOF'` / `<<-EOF` / etc. The
#      opener regex is gated by an "in-quoted-string" check so that string
#      mentions of `<<EOF` do NOT push the scanner into heredoc state
#      (gp HIGH H1 fix). The line CONTAINING the heredoc opener is also
#      scanned for raw curl AFTER the opener (gp HIGH H2 fix) — so
#      `cat <<EOF >x && curl https://x` correctly flags the curl.
#   3. Skip line-leading comments (`# ...`).
#   4. Skip `command -v curl|wget` / `which curl|wget` (existence checks).
#   5. Skip lines starting with `echo "..."` / `printf "..."` (curl-in-strings
#      is documentation).
#   6. Skip lines with `# check-no-raw-curl: ok` suppression marker (explicit
#      exception for cases the heuristics miss). Each marker is reviewer-
#      visible in PR diff.
#   7. Match `(^|[^[:alnum:]_])(curl|wget)[[:space:]]+(-|http|/|\$|"|\\)` —
#      word-boundary on the LHS (so `__guarded_curl` doesn't match), suffix
#      requiring real curl args (so passing string mentions don't match).
#
# Usage:
#   tools/check-no-raw-curl.sh                  # scan .claude/scripts/
#   tools/check-no-raw-curl.sh --root <dir>     # scan custom root
#   tools/check-no-raw-curl.sh --quiet          # exit-code only, no stdout
#
# Exit codes:
#   0  no violations
#   1  violations found (paths printed to stderr)
#   2  argument / I/O error
#
# Tested by tests/integration/cycle099-strict-curl-scan.bats.
# =============================================================================

set -euo pipefail

# Files explicitly allowed to invoke `curl`/`wget` directly.
# Path-match is exact (rooted at PROJECT_ROOT), so adding entries requires a
# code edit + reviewer visibility — not env-overridable for safety.
EXEMPT_FILES=(
    ".claude/scripts/lib/endpoint-validator.sh"
    ".claude/scripts/mount-loa.sh"
    ".claude/scripts/model-health-probe.sh"
    ".claude/scripts/model-adapter.sh.legacy"
    # cycle-108 sprint-2 T2.L: cheval-network-guard.sh defines bash function
    # shims for curl/wget/nc/ftp that intercept under LOA_NETWORK_RESTRICTED=1.
    # The shims delegate to `command curl` / `command wget` after the
    # allowlist check passes — that's the same defense-in-depth pattern as
    # endpoint-validator.sh's __guarded_curl. The strict scanner flags
    # `command curl "$@"` as a raw curl invocation, but in this file the
    # delegation IS the allowlisted path.
    ".claude/scripts/lib/cheval-network-guard.sh"
)

QUIET=0
ROOT=".claude/scripts"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q) QUIET=1; shift ;;
        --root) ROOT="$2"; shift 2 ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf 'check-no-raw-curl.sh: unknown arg %q\n' "$1" >&2
            exit 2
            ;;
    esac
done

[[ -d "$ROOT" ]] || {
    printf 'check-no-raw-curl.sh: scan root %q not a directory\n' "$ROOT" >&2
    exit 2
}

_is_exempt() {
    local path="$1" ex
    for ex in "${EXEMPT_FILES[@]}"; do
        [[ "$path" == "$ex" ]] && return 0
    done
    return 1
}

# Decide whether a file is a bash/sh script that the scanner should inspect.
# Recognized: .sh / .bash / .legacy extensions, OR extension-less files with
# a bash/sh shebang. Other files (binaries, READMEs, *.md, *.json) are
# skipped — they cannot invoke curl/wget at runtime anyway.
_is_script() {
    local path="$1"
    case "$path" in
        *.sh|*.bash|*.legacy) return 0 ;;
    esac
    # Extension-less or unfamiliar extension: require bash/sh shebang.
    # head exits successfully even on binary files; grep -q returns 1 if
    # no match, which we propagate.
    local first_line
    first_line=$(head -c 256 "$path" 2>/dev/null | head -1 || true)
    [[ "$first_line" == "#!"*"bash"* ]] && return 0
    [[ "$first_line" == "#!"*"sh" ]] && return 0
    [[ "$first_line" == "#!"*"sh "* ]] && return 0
    return 1
}

# awk program. Quoted heredoc preserves the program literally — no shell
# expansion. The program tracks heredoc state and quote-state for the
# heredoc-opener gate (gp HIGH findings H1 + H2).
AWK_SCAN=$(cat <<'AWK'
BEGIN {
    in_heredoc = 0
    hd_term = ""
    hd_dash = 0
}

# Quote-state helper (gp HIGH H1 fix). Returns 1 if `prefix` ends inside an
# unclosed single- or double-quote, 0 otherwise. Backslash escapes inside
# double-quotes are honored; single-quoted bash strings cannot contain any
# escape so backslash inside ' ... ' is literal.
function _quote_state_open(prefix,    i, c, n, in_s, in_d) {
    in_s = 0
    in_d = 0
    n = length(prefix)
    for (i = 1; i <= n; i++) {
        c = substr(prefix, i, 1)
        if (in_s) {
            if (c == "\047") in_s = 0
            continue
        }
        if (in_d) {
            if (c == "\\" && i < n) { i++; continue }
            if (c == "\"") in_d = 0
            continue
        }
        if (c == "\047") in_s = 1
        else if (c == "\"") in_d = 1
    }
    return (in_s + in_d > 0)
}

# Step 1: when in heredoc, swallow lines until terminator.
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; next }
    if (hd_dash) {
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; next }
    }
    next
}

# Step 2: skip line-leading comments.
/^[[:space:]]*#/ { next }

# Step 3: skip `command -v curl|wget` and `which curl|wget` existence checks.
/command[[:space:]]+-v[[:space:]]+(curl|wget)/ { next }
/which[[:space:]]+(curl|wget)/ { next }

# Step 4: skip lines starting with echo/printf and a quoted string —
# UNLESS they contain a command-substitution that could invoke curl
# (BB iter-1 F4). `echo "$(curl https://x)"` MUST still be flagged because
# the command substitution is real curl execution. Same for backticks.
/^[[:space:]]*(echo|printf)[[:space:]]+[\047"]/ {
    if (!($0 ~ /\$\(|`/)) next
}

# Step 5: skip lines with the explicit suppression marker. BB iter-1 F2:
# require a `#` comment leader so that a marker inside a string literal
# does NOT silence a real curl on the same line. The marker applies to
# its OWN line only (bats ST15 pins this scope).
/#[^\n]*check-no-raw-curl:[[:space:]]*ok/ { next }

# Step 6: detect heredoc opener. Real openers push us into heredoc state;
# string-mentioned `<<EOF` (gp H1) does NOT.
{
    if (match($0, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
        prefix = substr($0, 1, RSTART - 1)
        if (!_quote_state_open(prefix)) {
            # Real heredoc opener.
            m = substr($0, RSTART, RLENGTH)
            sub(/^<</, "", m)
            if (substr(m, 1, 1) == "-") { hd_dash = 1; m = substr(m, 2) } else { hd_dash = 0 }
            gsub(/^[ \t]+/, "", m)
            gsub(/[\047"]/, "", m)
            in_heredoc = 1
            hd_term = m

            # gp HIGH H2 fix: scan the rest of the line (after the opener)
            # for raw curl/wget. Pattern: `cat <<EOF >x && curl https://x`.
            # BB F3: suffix class also includes `'` (\047).
            rest = substr($0, RSTART + RLENGTH)
            if (rest ~ /(^|[^[:alnum:]_])(curl|wget)[[:space:]]+(-|http|\/|\$|"|\047|\\)/) {
                print FILENAME ":" NR ":" $0
            }
            next
        }
        # Else: opener is inside a quoted string → fall through and
        # process this line as a normal line for raw-curl detection.
    }
}

# Step 7: match raw curl|wget invocations. BB iter-1 F3: include `'`
# (single-quote, \047) in suffix class so `curl 'https://x'` is also flagged.
/(^|[^[:alnum:]_])(curl|wget)[[:space:]]+(-|http|\/|\$|"|\047|\\)/ {
    print FILENAME ":" NR ":" $0
}
AWK
)

violations=""
while IFS= read -r -d '' f; do
    rel="${f#./}"
    if _is_exempt "$rel"; then
        continue
    fi
    if ! _is_script "$f"; then
        continue
    fi
    file_hits=$(awk "$AWK_SCAN" "$f" 2>/dev/null || true)
    if [[ -n "$file_hits" ]]; then
        violations+="$file_hits"$'\n'
    fi
done < <(find "$ROOT" -type f -print0 | sort -z)

if [[ -n "$violations" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        printf 'cycle-099 sprint-1E.c.3.c: raw curl/wget detected outside endpoint_validator__guarded_curl\n' >&2
        printf 'All bash HTTP calls MUST funnel through .claude/scripts/lib/endpoint-validator.sh\n' >&2
        printf '\nExempt files:\n' >&2
        for ex in "${EXEMPT_FILES[@]}"; do
            printf '  - %s\n' "$ex" >&2
        done
        printf '\nViolations:\n' >&2
        printf '%s' "$violations" | sed '/^$/d' >&2
    fi
    exit 1
fi

[[ $QUIET -eq 0 ]] && printf 'OK — no raw curl/wget callers outside exempt set\n'
exit 0
