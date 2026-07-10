#!/usr/bin/env bash
# =============================================================================
# check-installer-safety.sh — enforcing installer-safety pattern gate (#1162)
# =============================================================================
# Scans the hard-boundary installer scripts (mount-loa.sh, mount-submodule.sh)
# for the three unsafe pattern classes identified by the installer trust-root
# audit lane, and FAILS (exit 1) when any is present:
#
#   1. echo -e output helpers — interpret backslash escapes in message text
#      (user-supplied refs/paths corrupt output; not POSIX-portable).
#   2. Unguarded option-operand reads — `FLAG_VAR="$2"` in the CLI parser with
#      no require_operand guard; a missing operand silently consumes the next
#      flag or an empty string.
#   3. Bare-prefix repo-boundary comparison — `!= "$repo_root"*` accepts
#      sibling directories (/repo-evil passes a /repo check).
#
# Unlike the earlier advisory draft (PR #1152), findings are FAILURES.
# Enforced via tests/unit/installer-safety.bats under the Shell Tests gate.
#
# Usage:
#   check-installer-safety.sh [file ...]   # default: the two mount scripts
# Exit codes: 0 = clean, 1 = violations found, 2 = target file missing
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=(
        "$PROJECT_ROOT/.claude/scripts/mount-loa.sh"
        "$PROJECT_ROOT/.claude/scripts/mount-submodule.sh"
    )
fi

violations=0
missing=0

# Print each hit line prefixed with a label; return the hit count via stdout
# of the caller-side wc. No subshell writes to $violations (pipe-loop trap).
report() {
    local label="$1" hits="$2"
    [[ -z "$hits" ]] && return 0
    local n=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "VIOLATION: $label: $line" >&2
        n=$((n + 1))
    done <<< "$hits"
    violations=$((violations + n))
}

for f in ${TARGETS[@]+"${TARGETS[@]}"}; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: target not found: $f" >&2
        missing=$((missing + 1))
        continue
    fi

    # --- Pattern 1: echo -e output ------------------------------------------
    # Disallowed in these installers; printf '%b…%s' is the sanctioned form
    # (escapes interpreted only in color codes, never in message text).
    report "$f: echo -e output (use printf '%b…%b %s')" \
        "$(grep -nE '\becho[[:space:]]+-e\b' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"

    # --- Pattern 2: unguarded option-operand reads in the CLI parser --------
    # Inside the `while [[ $# -gt 0 ]] … case $1 in` parser, every case arm
    # assigning "$2" to an UPPERCASE var must call require_operand first
    # (the preceding non-blank, non-comment line).
    report "$f: unguarded option operand (call require_operand first)" \
        "$(awk '
            /while \[\[ \$# -gt 0 \]\]/ { inparser=1 }
            inparser && /^done$/        { inparser=0 }
            {
                if (inparser && $0 ~ /^[[:space:]]*[A-Z_]+="\$2"/) {
                    if (prev !~ /require_operand/) printf "%d:%s\n", NR, $0
                }
                if ($0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/) prev=$0
            }
        ' "$f")"

    # --- Pattern 3: bare-prefix repo-boundary comparison ---------------------
    # `"$repo_root"*` (no /) matches sibling dirs like /repo-evil.
    report "$f: bare-prefix boundary check (use \"\$repo_root\"/* + exact-equality)" \
        "$(grep -nE '[!=]=[[:space:]]*"\$\{?repo_root\}?"\*' "$f" || true)"
done

if [[ $missing -gt 0 ]]; then
    exit 2
fi
if [[ $violations -gt 0 ]]; then
    echo "check-installer-safety: $violations violation(s) — see above" >&2
    exit 1
fi
echo "check-installer-safety: clean (${#TARGETS[@]} file(s))"
exit 0
