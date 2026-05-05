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
# Three files are explicitly exempt:
#   - .claude/scripts/lib/endpoint-validator.sh  (the wrapper itself)
#   - .claude/scripts/mount-loa.sh               (bootstrap; the wrapper's
#                                                  Python dep may not be
#                                                  installed yet, so we
#                                                  harden mount-loa with
#                                                  --proto =https,
#                                                  --proto-redir =https,
#                                                  --max-redirs 10, plus a
#                                                  dot-dot regex defense
#                                                  on caller-supplied refs)
#   - .claude/scripts/model-health-probe.sh      (legacy webhook path;
#                                                  operator-supplied dynamic
#                                                  webhook URL cannot be
#                                                  statically allowlisted —
#                                                  opt-in to wrapper-routed
#                                                  dispatch via .loa.config.yaml
#                                                  ::model_health_probe.alert_webhook_endpoint_validator_enabled)
#
# Detection logic (in order):
#   1. Track heredoc state (`<<EOF` / `<<'EOF'` / `<<-EOF` / etc) — skip
#      heredoc bodies entirely (they are typically usage / instruction text
#      that mentions curl as documentation, not an invocation).
#   2. Skip line-leading comments (`# ...`).
#   3. Skip `command -v curl|wget` / `which curl|wget` (existence checks).
#   4. Skip lines starting with `echo "..."` / `printf "..."` / `printf '...'`
#      (curl-in-strings is documentation).
#   5. Skip lines with the `# check-no-raw-curl: ok` suppression marker
#      (explicit exception for cases the heuristics miss).
#   6. Match `(^|[^[:alnum:]_])(curl|wget)[[:space:]]+(-|http|/|\$|"|\\)` —
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

# awk program. Quoted heredoc preserves the program literally — no shell
# expansion. The program tracks heredoc state so usage/instruction-text
# heredocs that mention curl as documentation are skipped.
AWK_SCAN=$(cat <<'AWK'
BEGIN {
    in_heredoc = 0
    hd_term = ""
    hd_dash = 0
}

# When in a heredoc, swallow lines until we see the terminator.
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; next }
    if (hd_dash) {
        # <<- variant: terminator may have leading tabs that bash strips.
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; next }
    }
    next
}

# Detect heredoc opener. We match a few canonical shapes:
#   `<<EOF`          plain
#   `<<-EOF`         dash variant (tabs stripped from terminator)
#   `<<'EOF'`        single-quoted (no expansion in body)
#   `<<"EOF"`        double-quoted (no expansion in body)
# The opener can appear ANYWHERE on the line (`cat <<EOF >out` is valid).
{
    line = $0
    if (match(line, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/^<</, "", m)
        if (substr(m, 1, 1) == "-") { hd_dash = 1; m = substr(m, 2) } else { hd_dash = 0 }
        gsub(/^[ \t]+/, "", m)
        gsub(/[\047"]/, "", m)
        in_heredoc = 1
        hd_term = m
        next
    }
}

# Skip line-leading comments.
/^[[:space:]]*#/ { next }

# Skip `command -v curl|wget` and `which curl|wget` existence checks.
/command[[:space:]]+-v[[:space:]]+(curl|wget)/ { next }
/which[[:space:]]+(curl|wget)/ { next }

# Skip lines starting with echo/printf and a quoted string — those are
# typically documentation that mentions curl, not invocations.
/^[[:space:]]*(echo|printf)[[:space:]]+[\047"]/ { next }

# Skip lines with the explicit suppression marker.
/check-no-raw-curl:[[:space:]]*ok/ { next }

# Match raw curl|wget invocations.
/(^|[^[:alnum:]_])(curl|wget)[[:space:]]+(-|http|\/|\$|"|\\)/ {
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
    file_hits=$(awk "$AWK_SCAN" "$f" 2>/dev/null || true)
    if [[ -n "$file_hits" ]]; then
        violations+="$file_hits"$'\n'
    fi
done < <(find "$ROOT" -name '*.sh' -type f -print0 | sort -z)

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
