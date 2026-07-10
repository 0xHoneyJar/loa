#!/usr/bin/env bash
# =============================================================================
# validate-gitignore-state.sh — C17 (cycle-119)
# =============================================================================
# Diagnostic, WARN-only: checks whether the State-Zone roots declared in
# .claude/rules/zone-state.md (grimoires/**, .beads/**, .ck/**, .run/**) are
# wholesale-gitignored, and whether a small set of files that convention
# says should STAY tracked (grimoires/loa/zones.yaml, known-failures.md,
# ledger.json, REPO-MAP.md, runbooks/ — see .gitignore's own
# "NOT gitignored (still tracked)" comment block) have been accidentally
# swallowed by a broader ignore pattern added later. Prints the EXACT
# .gitignore pattern responsible so drift is reviewable.
#
# Deliberately NOT a recursive walk of every file under the State Zone: most
# State-Zone content (session-local .run/, .beads/, .ck/ state; most of
# grimoires/loa's own working files) is INTENTIONALLY gitignored by design
# (see zone-state.md), so an exhaustive per-file scan would be nearly all
# noise. This checks only the roots + the curated "should stay tracked" set.
#
# WARN-only, never a hard gate — always exits 0.
#
# Usage: validate-gitignore-state.sh [--json]
# =============================================================================

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: validate-gitignore-state.sh [--json]

Checks State-Zone roots (grimoires/**, .beads/**, .ck/**, .run/**, honoring
LOA_GRIMOIRE_DIR/LOA_BEADS_DIR overrides) for wholesale gitignore drift, and
checks a curated "should stay tracked" file set for accidental drift, printing
the exact .gitignore pattern responsible + a suggested fix.

WARN-only — being gitignored is often INTENTIONAL. Diagnostic, not a gate.
Always exits 0.
EOF
  exit 0
fi

json_mode=0
[[ "${1:-}" == "--json" ]] && json_mode=1

if ! command -v git >/dev/null 2>&1; then
  echo "validate-gitignore-state.sh: git not found — cannot check .gitignore state" >&2
  exit 0
fi

grimoire_dir="${LOA_GRIMOIRE_DIR:-grimoires}"
roots=("$grimoire_dir" "${LOA_BEADS_DIR:-.beads}" ".ck" ".run")

# Curated "should stay tracked" set — per .gitignore's own
# "NOT gitignored (still tracked)" comment for grimoires/loa.
tracked_set=(
  "${grimoire_dir}/loa/zones.yaml"
  "${grimoire_dir}/loa/known-failures.md"
  "${grimoire_dir}/loa/ledger.json"
  "${grimoire_dir}/loa/REPO-MAP.md"
  "${grimoire_dir}/loa/runbooks"
)

warnings=()

warn() { warnings+=("$1|$2|$3"); }

for root in "${roots[@]}"; do
  [[ -e "$root" ]] || continue
  if pattern=$(git check-ignore -v -- "$root" 2>/dev/null); then
    warn "$root" "${pattern%%$'\t'*}" \
      "whole State-Zone root is gitignored — if content here should be tracked, add a \`!${root}\` negation AFTER that .gitignore line"
  fi
done

for f in "${tracked_set[@]}"; do
  [[ -e "$f" ]] || continue
  if pattern=$(git check-ignore -v -- "$f" 2>/dev/null); then
    warn "$f" "${pattern%%$'\t'*}" \
      "this path is meant to stay tracked but is gitignored — add a \`!${f}\` negation AFTER that .gitignore line"
  fi
done

if [[ ${#warnings[@]} -eq 0 ]]; then
  if [[ $json_mode -eq 1 ]]; then
    echo '{"warnings":[]}'
  else
    echo "validate-gitignore-state: no State-Zone gitignore drift found."
  fi
  exit 0
fi

if [[ $json_mode -eq 1 ]]; then
  printf '{"warnings":['
  first=1
  for w in "${warnings[@]}"; do
    IFS='|' read -r path src_line fix <<<"$w"
    [[ $first -eq 0 ]] && printf ','
    printf '{"path":%s,"pattern":%s,"fix":%s}' \
      "$(jq -Rn --arg v "$path" '$v')" \
      "$(jq -Rn --arg v "$src_line" '$v')" \
      "$(jq -Rn --arg v "$fix" '$v')"
    first=0
  done
  printf ']}\n'
else
  for w in "${warnings[@]}"; do
    IFS='|' read -r path src_line fix <<<"$w"
    echo "WARN: $path is gitignored by: $src_line"
    echo "  Fix: $fix"
  done
fi

exit 0
