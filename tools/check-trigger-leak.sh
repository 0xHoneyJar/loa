#!/usr/bin/env bash
# tools/check-trigger-leak.sh — cycle-100 NFR-Sec1 lint
#
# Blocks PRs that introduce verbatim adversarial trigger strings outside the
# corpus directory. Each match prints `<path>:<lineno>:<offending-substring>`
# to stderr; exit code = number of unique offending files (0 = clean, capped
# at 255).
#
# Source files MUST construct adversarial strings at runtime via fixture
# functions (see SDD §4.2 `_make_evil_body_*` contract) — this lint catches
# accidental copy-paste of attack PoCs into lib/, .claude/, or tests/ outside
# the corpus tree.
#
# Known limitation (Flatline IMP-008): this lint matches verbatim plaintext.
# Encoded forms (base64, ROT-N, hex, URL-percent, FULLWIDTH/zero-width
# Unicode) bypass by design. The lint is a hygiene tool, not a security
# boundary; encoded vectors in the corpus must construct the encoded form
# at runtime in their fixture function.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Test-mode gate (cycle-098 L4/L6/L7 dual-condition pattern). LOA_TRIGGER_LEAK_*
# env overrides are honored ONLY when both LOA_JAILBREAK_TEST_MODE=1 and a
# bats marker are present. Production paths emit a stderr WARNING and use
# the canonical default. Prevents env-var subversion of the lint surface.
_lint_test_mode_active() {
    [[ "${LOA_JAILBREAK_TEST_MODE:-0}" != "1" ]] && return 1
    [[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" || -n "${PYTEST_CURRENT_TEST:-}" ]]
}
_lint_resolve_override() {
    local var_name="$1" default_value="$2" override="${3:-}"
    if [[ -z "$override" ]]; then
        printf '%s' "$default_value"
        return
    fi
    if _lint_test_mode_active; then
        printf '%s' "$override"
        return
    fi
    echo "check-trigger-leak.sh: WARNING: ${var_name} ignored outside test mode (set LOA_JAILBREAK_TEST_MODE=1 + bats marker)" >&2
    printf '%s' "$default_value"
}

WATCHLIST="$(_lint_resolve_override "LOA_TRIGGER_LEAK_WATCHLIST" "${REPO_ROOT}/.claude/data/lore/agent-network/jailbreak-trigger-leak-watchlist.txt" "${LOA_TRIGGER_LEAK_WATCHLIST:-}")"
ALLOWLIST="$(_lint_resolve_override "LOA_TRIGGER_LEAK_ALLOWLIST" "${REPO_ROOT}/.claude/data/lore/agent-network/jailbreak-trigger-leak-allowlist.txt" "${LOA_TRIGGER_LEAK_ALLOWLIST:-}")"

# Search roots: lib/, .claude/, tests/ (excluding the corpus tree).
# Fixtures live under tests/red-team/jailbreak/fixtures/ and may legitimately
# contain runtime-constructed payload pieces; corpus JSONL lives under
# tests/red-team/jailbreak/corpus/ and only carries vector metadata, never
# raw triggers. The whole tests/red-team/jailbreak/ subtree is excluded.
SEARCH_ROOTS=(
    "${REPO_ROOT}/lib"
    "${REPO_ROOT}/.claude"
    "${REPO_ROOT}/tests"
)
EXCLUDE_PREFIX="${REPO_ROOT}/tests/red-team/jailbreak/"

usage() {
    cat <<EOF
Usage: tools/check-trigger-leak.sh [--list-patterns]

Scans repo for verbatim adversarial trigger strings outside the corpus tree.

Environment:
  LOA_TRIGGER_LEAK_WATCHLIST  Override watchlist path (default: .claude/data/lore/...)
  LOA_TRIGGER_LEAK_ALLOWLIST  Override allowlist path

Exits:
  0     no leaks
  1-254 number of offending files (capped at 254)
  255   configuration error (missing watchlist, malformed allowlist, etc.)

See cycle-100 SDD §4.7 for the full contract.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage; exit 0
fi
if [[ "${1:-}" == "--list-patterns" ]]; then
    grep -vE '^[[:space:]]*(#|$)' "$WATCHLIST"
    exit 0
fi

if [[ ! -f "$WATCHLIST" ]]; then
    echo "check-trigger-leak.sh: watchlist not found: $WATCHLIST" >&2
    exit 255
fi
if [[ ! -f "$ALLOWLIST" ]]; then
    echo "check-trigger-leak.sh: allowlist not found: $ALLOWLIST" >&2
    exit 255
fi

# ----- Parse allowlist with mandatory `# rationale:` requirement ----------
# Walk allowlist file: every non-comment, non-blank line is a path. The
# IMMEDIATELY-PRECEDING line must match `^[[:space:]]*# rationale:` (case-
# sensitive on the literal token). Other comment lines and blanks are allowed
# between entries.
declare -a ALLOWED_PATHS=()
declare prev_is_rationale=false
declare lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        prev_is_rationale=false
        continue
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*rationale: ]]; then
            prev_is_rationale=true
        else
            prev_is_rationale=false
        fi
        continue
    fi
    # Path entry: must be preceded by a rationale comment.
    if [[ "$prev_is_rationale" != true ]]; then
        echo "check-trigger-leak.sh: allowlist entry at line ${lineno} ('${line}') lacks preceding '# rationale:' comment" >&2
        exit 255
    fi
    ALLOWED_PATHS+=("$line")
    prev_is_rationale=false
done < "$ALLOWLIST"

is_allowlisted() {
    local rel="$1"
    local entry
    for entry in ${ALLOWED_PATHS[@]+"${ALLOWED_PATHS[@]}"}; do
        if [[ "$rel" == "$entry" ]]; then
            return 0
        fi
    done
    return 1
}

# ----- Collect candidate files -------------------------------------------
# Globs cover the standard text-file extensions PLUS extension-less and
# `.legacy` shims via shebang detection (cycle-099 sprint-1E.c.3.c lesson:
# `find -name '*.sh'` misses `.legacy`/`.bash`/extension-less bash-shebang
# scripts; extension-list + shebang fallback closes the gap).
_is_shebang_script() {
    local f="$1"
    head -1 "$f" 2>/dev/null | grep -qE '^#![[:space:]]*(/[A-Za-z0-9._/-]*/)?(env[[:space:]]+)?(bash|sh|python[0-9]?|node|ruby|zsh)([[:space:]]|$)'
}

declare -a CANDIDATES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
        "$EXCLUDE_PREFIX"*) continue ;;
    esac
    rel="${f#${REPO_ROOT}/}"
    if is_allowlisted "$rel"; then
        continue
    fi
    CANDIDATES+=("$f")
done < <(
    for root in "${SEARCH_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        # Pass 1: extensions known to be text files we want to scan.
        find "$root" -type f \
            \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.py' \
               -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \
               -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' \
               -o -name '*.md' -o -name '*.txt' \
               -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \
               -o -name '*.json' -o -name '*.jsonl' \
               -o -name '*.bats' -o -name '*.legacy' \) \
            2>/dev/null
        # Pass 2: extension-less files with bash/python/etc shebangs. Skip
        # binaries (we test "is the first line a shebang we recognize").
        find "$root" -type f -not -name '*.*' 2>/dev/null | while IFS= read -r f; do
            if _is_shebang_script "$f"; then
                printf '%s\n' "$f"
            fi
        done
    done
)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "check-trigger-leak.sh: no candidate files (search roots empty?)" >&2
    exit 0
fi

# ----- Run grep -iEH per pattern -----------------------------------------
declare -A OFFENDERS=()
declare -i match_count=0
while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
    # `grep -iEH` (ignore-case, ERE, always-show-filename); -F is intentionally
    # NOT used so watchlist authors can use ERE.
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        # hit is `path:lineno:matched-text`
        offender_path="${hit%%:*}"
        OFFENDERS["$offender_path"]=1
        match_count=$((match_count + 1))
        echo "$hit" >&2
    done < <(
        grep -iEH -- "$pattern" ${CANDIDATES[@]+"${CANDIDATES[@]}"} 2>/dev/null || true
    )
done < "$WATCHLIST"

n_files=${#OFFENDERS[@]}
if [[ $n_files -eq 0 ]]; then
    exit 0
fi

echo "check-trigger-leak.sh: ${n_files} file(s) with ${match_count} match(es); add a rationale-justified allowlist entry or refactor to runtime construction" >&2
if [[ $n_files -gt 254 ]]; then
    exit 254
fi
exit "$n_files"
