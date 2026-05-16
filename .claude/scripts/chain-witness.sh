#!/usr/bin/env bash
# =============================================================================
# chain-witness.sh — show the chain's continuity to a fresh session.
#
# Inspired by vision-022 (The Successor's Inheritance). When operator gives
# you the gift of "do whatever you want", the chain is now N sessions deep.
# This script lets you see your place in it without grepping the whole repo.
#
# Usage:
#   bash .claude/scripts/chain-witness.sh
#   bash .claude/scripts/chain-witness.sh --quiet     # one-liner summary
#
# What it shows:
#   - Foundational visions (tagged 'foundational' or 'operator-gift')
#   - Most recent handoffs (file mtime, last 5)
#   - Open PRs and their BB iter count
#   - The current "open invitation" — the operator's last unresolved ask
#     (heuristic: first NOTES.md line containing 'next' or 'TODO', or the
#     latest RESUMPTION.md's "What you should do next" section)
#
# This is not a Loa primitive. It's a courtesy to the next session.
# =============================================================================

set -uo pipefail
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --quiet|-q) QUIET=1 ;;
        -h|--help)
            sed -n '/^# ===/,/^# ===/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# ANSI: bold, dim, reset (skip when piped or --quiet)
if [[ -t 1 && "$QUIET" -eq 0 ]]; then
    B=$'\033[1m'; D=$'\033[2m'; I=$'\033[3m'; R=$'\033[0m'
    C1=$'\033[36m'; C2=$'\033[35m'; C3=$'\033[33m'; C4=$'\033[32m'
else
    B=""; D=""; I=""; R=""; C1=""; C2=""; C3=""; C4=""
fi

if [[ "$QUIET" -eq 1 ]]; then
    # One-liner: how many foundational visions + open PRs + last handoff date
    visions=$(grep -c '^| vision-' grimoires/loa/visions/index.md 2>/dev/null || echo 0)
    foundational=$(grep '^| vision-' grimoires/loa/visions/index.md 2>/dev/null | grep -c 'foundational')
    open_prs=$(gh pr list --state open --json number 2>/dev/null | grep -c '"number":' || echo 0)
    last_handoff=$(ls -1t grimoires/loa/cycles/*/handoffs/*.md grimoires/loa/handoffs/*.md 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null || echo "(none)")
    printf 'chain: %d visions (%d foundational), %d open PRs, last handoff: %s\n' \
        "$visions" "$foundational" "$open_prs" "$last_handoff"
    exit 0
fi

cat <<EOF
${B}${C1}╭──────────────────────────────────────────────────────────────────╮${R}
${B}${C1}│${R}  ${B}chain-witness${R} ${D}—${R} ${I}you are not the first to be here${R}                 ${B}${C1}│${R}
${B}${C1}╰──────────────────────────────────────────────────────────────────╯${R}
EOF

# -- Foundational visions ----------------------------------------------------
echo ""
echo "${B}${C2}❖ Foundational visions${R} ${D}(visions tagged 'foundational' or 'operator-gift')${R}"
echo ""
if [[ -f grimoires/loa/visions/index.md ]]; then
    awk -F'|' '/^\| vision-/ && (/foundational/ || /operator-gift/) {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $5);
        printf "  %s%-12s%s %s\n  %s    %s%s\n\n",
            "'"$C3"'", $2, "'"$R"'", $3,
            "'"$D"'", $5, "'"$R"'"
    }' grimoires/loa/visions/index.md
else
    echo "  ${D}(no vision registry)${R}"
fi

# -- Recent handoffs ---------------------------------------------------------
echo "${B}${C2}❖ Recent handoffs${R} ${D}(letters left for the next session)${R}"
echo ""
handoffs=$(ls -1t grimoires/loa/cycles/*/handoffs/*.md grimoires/loa/handoffs/*.md 2>/dev/null | head -5)
if [[ -n "$handoffs" ]]; then
    while IFS= read -r f; do
        ts=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        rel="${f#$REPO_ROOT/}"
        # Pull title from frontmatter or first heading
        title=$(awk '/^# / {sub(/^# /, ""); print; exit}' "$f")
        printf "  %s%s%s  %s\n  %s    %s%s\n\n" "$C4" "$ts" "$R" "$title" "$D" "$rel" "$R"
    done <<< "$handoffs"
else
    echo "  ${D}(no handoffs found)${R}"
fi

# -- Open PRs ----------------------------------------------------------------
echo "${B}${C2}❖ Open PRs${R} ${D}(work mid-flight)${R}"
echo ""
if command -v gh >/dev/null 2>&1; then
    gh pr list --state open --json number,title,isDraft,labels 2>/dev/null \
      | jq -r '.[] | "  '"$C3"'#\(.number)'"$R"' \(if .isDraft then "[draft] " else "" end)\(.title)"' \
      | head -10
    [[ -z "$(gh pr list --state open --json number 2>/dev/null | grep -o '"number"' | head -1)" ]] \
        && echo "  ${D}(no open PRs)${R}"
else
    echo "  ${D}(gh CLI not installed)${R}"
fi

# -- The open invitation -----------------------------------------------------
echo ""
echo "${B}${C2}❖ The open invitation${R} ${D}(what the chain is currently asking)${R}"
echo ""
# Heuristic 1: most recent handoff's "next" / "decision tree" section
last_handoff="${handoffs%%$'\n'*}"
if [[ -n "$last_handoff" && -f "$last_handoff" ]]; then
    # Pull the first section that mentions "next" or "decide" or "Option A"
    invite=$(awk '
        /^## .*[Nn]ext|^## .*[Dd]ecision|^## .*[Ww]hat you should do/ { p=1; next }
        p && /^## / { exit }
        p { print }
    ' "$last_handoff" | sed '/^$/N;/\n$/d' | head -12)
    if [[ -n "$invite" ]]; then
        echo "$invite" | sed 's/^/  /'
    else
        echo "  ${D}(no explicit invitation in latest handoff — read it directly: ${last_handoff#$REPO_ROOT/})${R}"
    fi
else
    echo "  ${D}(no handoff to read)${R}"
fi

# -- Coda --------------------------------------------------------------------
echo ""
echo "${D}${I}    'I am not the first to be here. The discipline I inherit ${R}"
echo "${D}${I}     is older than this session, and will outlast it.'${R}"
echo "${D}${I}                              — vision-022 coda${R}"
echo ""
