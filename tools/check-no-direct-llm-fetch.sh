#!/usr/bin/env bash
# =============================================================================
# tools/check-no-direct-llm-fetch.sh
#
# cycle-103 sprint-1 T1.7 — drift gate enforcing the "one HTTP boundary"
# invariant: NO direct provider URLs in TS / bash / Python files outside the
# canonical exempt set. All LLM-API HTTP calls in Loa MUST funnel through the
# cheval Python substrate (`.claude/adapters/cheval.py` → `loa_cheval/`).
#
# Closes AC-1.4 and ships the CI enforcer for the M1 (BB → cheval) and M2
# (Flatline → cheval) cycle-exit invariants.
#
# **Tripwire scope** (mirrors cycle-099 sprint-1E.c.3.c precedent — see
# tools/check-no-raw-curl.sh): the scanner enforces a literal-substring
# contract for files that look like bash / TS / Python source. It is ONE
# layer of a multi-layer defense:
#   - The cheval substrate is the load-bearing unification.
#   - call_flatline_chat / ChevalDelegateAdapter are the routing chokepoints.
#   - This scanner is a regression-catcher.
#
# Out of scope (cypherpunk-review-style accepted risks):
#   - String-interpolated URLs (`base="https://api.${provider}.com"`).
#   - URLs assembled from env vars (`"$OPENAI_API_BASE/v1/chat"`).
#   - URLs read from config files at runtime.
#   - Embeddings (cheval has no embeddings substrate — see audit doc).
# PR review remains the gate for these.
#
# Detection logic (in order):
#   1. File-type filter: scan `.sh` / `.bash` / `.ts` / `.tsx` / `.py`
#      extensions PLUS extension-less files with a bash/sh/python3 shebang.
#      Other files (binaries, READMEs, .md, .json) are skipped.
#   2. Exempt-file filter: read tools/check-no-direct-llm-fetch.allowlist
#      (one path per line, `#` for comments, blank lines OK). Path-match
#      is exact, rooted at PROJECT_ROOT.
#   3. Skip line-leading comments — `^[[:space:]]*#` (bash, Python) AND
#      `^[[:space:]]*//` (TS) AND `^[[:space:]]*\*` (TS / Python block
#      comment continuation).
#   4. Skip lines with the suppression marker
#      (`# check-no-direct-llm-fetch: ok` or `// check-no-direct-llm-fetch: ok`).
#      Each marker is reviewer-visible in PR diff.
#   5. Match the three provider URL substrings:
#        - api.anthropic.com
#        - api.openai.com
#        - generativelanguage.googleapis.com
#      The match is plain substring — no word-boundary needed (these are
#      DNS hosts; no false-positive class).
#
# Usage:
#   tools/check-no-direct-llm-fetch.sh             # scan default scope
#   tools/check-no-direct-llm-fetch.sh --root <d>  # scan one root
#   tools/check-no-direct-llm-fetch.sh --quiet     # exit-code only
#   tools/check-no-direct-llm-fetch.sh --help
#
# Exit codes:
#   0  no violations
#   1  violations found (paths printed to stderr)
#   2  argument / I/O error
#
# Tested by tests/unit/check-no-direct-llm-fetch.bats.
# =============================================================================

set -euo pipefail

# Path to the allowlist file (mode 0644, git-tracked).
ALLOWLIST_FILE="${LOA_T17_ALLOWLIST_FILE:-tools/check-no-direct-llm-fetch.allowlist}"

# Default scan roots. Sprint T1.7 spec:
#   .claude/skills/**/*.{ts,sh,py}
#   .claude/scripts/**/*.{sh,py}
# We accept multiple --root arguments (additive) for test isolation.
DEFAULT_ROOTS=(
    ".claude/skills"
    ".claude/scripts"
)

# Provider URL patterns. ERE alternation — passed verbatim to grep -E.
URL_PATTERN='api\.anthropic\.com|api\.openai\.com|generativelanguage\.googleapis\.com'

# Suppression marker (per-line opt-out). Mirrors the precedent — must be a
# COMMENT, not a string-literal mention, so callers cannot smuggle it via a
# crafted string. Detected by checking the line text after stripping
# surrounding whitespace.
SUPPRESSION_MARKER='check-no-direct-llm-fetch: ok'

QUIET=0
declare -a ROOTS=()
declare -a EXEMPT_PATHS=()

# --------------------------------------------------------------------------
# CLI arg parsing
# --------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q) QUIET=1; shift ;;
        --root)
            if [[ $# -lt 2 ]]; then
                printf 'check-no-direct-llm-fetch.sh: --root requires a path\n' >&2
                exit 2
            fi
            ROOTS+=("$2")
            shift 2
            ;;
        --allowlist)
            if [[ $# -lt 2 ]]; then
                printf 'check-no-direct-llm-fetch.sh: --allowlist requires a path\n' >&2
                exit 2
            fi
            ALLOWLIST_FILE="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf 'check-no-direct-llm-fetch.sh: unknown arg %q\n' "$1" >&2
            exit 2
            ;;
    esac
done

# Use defaults if no --root passed.
if [[ ${#ROOTS[@]} -eq 0 ]]; then
    ROOTS=("${DEFAULT_ROOTS[@]}")
fi

# --------------------------------------------------------------------------
# Allowlist loader
# --------------------------------------------------------------------------

if [[ -f "$ALLOWLIST_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip whitespace and skip comments / blanks.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        EXEMPT_PATHS+=("$line")
    done < "$ALLOWLIST_FILE"
fi

_is_exempt() {
    local path="$1" ex
    if [[ ${#EXEMPT_PATHS[@]} -eq 0 ]]; then
        return 1
    fi
    for ex in "${EXEMPT_PATHS[@]}"; do
        [[ "$path" == "$ex" ]] && return 0
    done
    return 1
}

# --------------------------------------------------------------------------
# File-type filter
# --------------------------------------------------------------------------

# Decide whether a file is a TS / bash / Python source that the scanner
# should inspect. Extensions are checked first; extension-less files fall
# through to shebang detection.
_is_in_scope() {
    local path="$1"
    case "$path" in
        *.sh|*.bash|*.ts|*.tsx|*.py) return 0 ;;
        # Out-of-band extensions we know cannot be in scope. Listing them
        # short-circuits the shebang probe so we don't read binary content.
        *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.txt|*.log|*.jsonl) return 1 ;;
        *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.tar|*.gz) return 1 ;;
        *.html|*.css|*.svg|*.xml|*.csv) return 1 ;;
        *.pyc|*.so|*.o|*.a|*.bin) return 1 ;;
    esac
    # Extension-less or unfamiliar extension: read first line via dd to a
    # tempfile, strip null bytes (binary files), then check for a shebang.
    # tr -d '\0' protects bash's command-substitution from null bytes —
    # bash warns and strips them otherwise, polluting stderr.
    local first_line
    first_line=$(head -c 256 -- "$path" 2>/dev/null | tr -d '\0' | head -1 2>/dev/null || true)
    [[ "$first_line" == "#!"*"bash"* ]] && return 0
    [[ "$first_line" == "#!"*"sh" ]] && return 0
    [[ "$first_line" == "#!"*"sh "* ]] && return 0
    [[ "$first_line" == "#!"*"python"* ]] && return 0
    return 1
}

# --------------------------------------------------------------------------
# Line scanner (awk program)
# --------------------------------------------------------------------------
#
# Tracks heredoc state for bash files only (provider URLs inside `<<EOF`
# blocks are typically docs/examples, not active fetches). For TS / Python
# files, all non-comment lines are scanned.
#
# The awk program is in a single-quoted heredoc so no shell expansion.

AWK_SCAN=$(cat <<'AWK'
BEGIN {
    in_heredoc = 0
    hd_term = ""
    hd_dash = 0
}

# Heredoc body — swallow until terminator.
in_heredoc {
    if ($0 == hd_term) { in_heredoc = 0; next }
    if (hd_dash) {
        no_tabs = $0
        gsub(/^\t+/, "", no_tabs)
        if (no_tabs == hd_term) { in_heredoc = 0; next }
    }
    next
}

# Skip line-leading comment markers (bash, Python, TS line, TS/Python block).
/^[[:space:]]*(#|\/\/|\*)/ { next }

# Skip lines with the suppression marker. Marker MUST appear inside a
# comment (`#`, `//`, or `/*...*/` style) — bare string literals containing
# the marker text don't count. Detection: require comment-start somewhere
# on the line BEFORE the marker text.
$0 ~ /(#|\/\/)[^"']*check-no-direct-llm-fetch:[[:space:]]*ok/ { next }

# Detect heredoc opener for shell files (best-effort — Python and TS don't
# have heredocs in this sense). False-trigger on TS/Python is harmless
# because their heredoc-terminator regex won't match either.
{
    if (match($0, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
        m = substr($0, RSTART, RLENGTH)
        sub(/^<</, "", m)
        if (substr(m, 1, 1) == "-") { hd_dash = 1; m = substr(m, 2) } else { hd_dash = 0 }
        gsub(/^[ \t]+/, "", m)
        gsub(/[\047"]/, "", m)
        in_heredoc = 1
        hd_term = m

        # Also scan the opener line AFTER the opener for a URL match —
        # mirrors the cycle-099 H2 fix.
        rest = substr($0, RSTART + RLENGTH)
        if (rest ~ URL_PAT) {
            print FILENAME ":" NR ":" $0
        }
        next
    }
}

# Match URL substrings.
$0 ~ URL_PAT {
    print FILENAME ":" NR ":" $0
}
AWK
)

# --------------------------------------------------------------------------
# Main scan
# --------------------------------------------------------------------------

violations=""
scanned=0
skipped_exempt=0
skipped_oos=0

for root in "${ROOTS[@]}"; do
    if [[ ! -d "$root" ]]; then
        printf 'check-no-direct-llm-fetch.sh: scan root %q not a directory (skipping)\n' "$root" >&2
        continue
    fi

    while IFS= read -r -d '' f; do
        rel="${f#./}"
        if _is_exempt "$rel"; then
            skipped_exempt=$((skipped_exempt + 1))
            continue
        fi
        if ! _is_in_scope "$f"; then
            skipped_oos=$((skipped_oos + 1))
            continue
        fi
        scanned=$((scanned + 1))
        file_hits=$(awk -v URL_PAT="$URL_PATTERN" "$AWK_SCAN" "$f" 2>/dev/null || true)
        if [[ -n "$file_hits" ]]; then
            violations+="$file_hits"$'\n'
        fi
    done < <(find "$root" -type f -print0 2>/dev/null | sort -z)
done

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

if [[ -n "$violations" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        printf 'cycle-103 sprint-1 T1.7: direct provider-API URLs detected outside the cheval substrate\n' >&2
        printf 'All LLM-API calls in TS / bash / Python MUST funnel through .claude/adapters/cheval.py\n' >&2
        printf 'See grimoires/loa/cycles/cycle-103-provider-unification/sprint.md (T1.7 / AC-1.4 / M1 + M2)\n' >&2
        printf '\nAllowlist file: %s\n' "$ALLOWLIST_FILE" >&2
        if [[ ${#EXEMPT_PATHS[@]} -gt 0 ]]; then
            printf 'Exempt files (matched in this run):\n' >&2
            for ex in "${EXEMPT_PATHS[@]}"; do
                printf '  - %s\n' "$ex" >&2
            done
        fi
        printf '\nViolations:\n' >&2
        printf '%s' "$violations" | sed '/^$/d' >&2
        printf '\nIf a violation is intentional (operator probe, documented exception):\n' >&2
        printf '  1. Add a per-line suppression marker: `# check-no-direct-llm-fetch: ok`\n' >&2
        printf '  2. OR add the file path to %s with rationale\n' "$ALLOWLIST_FILE" >&2
    fi
    exit 1
fi

if [[ $QUIET -eq 0 ]]; then
    printf 'OK — no direct provider-API URLs outside the cheval substrate\n'
    printf '(scanned=%d, skipped_exempt=%d, skipped_out_of_scope=%d)\n' \
        "$scanned" "$skipped_exempt" "$skipped_oos"
fi
exit 0
