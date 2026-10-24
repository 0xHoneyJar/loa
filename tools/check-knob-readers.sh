#!/usr/bin/env bash
# =============================================================================
# tools/check-knob-readers.sh — no direct read of a profile key outside
# profile-lib.sh (cycle-129 SDD D-9.1, sprint-256 Task 2.7).
#
# Every key under any profile in .claude/data/profiles.yaml must be read
# through `loa_knob` (.claude/scripts/lib/profile-lib.sh), never by a reader's
# own `yq '.<key> // <default>'`: a direct read skips the profile, and yq's
# `//` reads an explicit `false` as absent. The check flags a line that names a
# profile key in yq-path form (a leading dot: `.guardrails.input.enabled`)
# under .claude/ (scripts, hooks, skills, data) and tools/, except
# profile-lib.sh itself. Prose that names a key without the dot
# (`guardrails.input.enabled: false`) is not a read and is not flagged.
#
# Misses: a key assembled at runtime (".guardrails.input.${x}.enabled") and a
# reader in a language that indexes the config as nested keys.
#
# Usage: tools/check-knob-readers.sh [--root DIR]
# Exit:  0 clean · 1 direct read found (each printed as path:line) · 2 usage
# =============================================================================
set -euo pipefail
export LC_ALL=C

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { echo "check-knob-readers.sh: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check-knob-readers.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done
PROFILES="$ROOT/.claude/data/profiles.yaml"
[[ -f "$PROFILES" ]] || { echo "check-knob-readers.sh: $PROFILES not found" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "check-knob-readers.sh: yq v4 required" >&2; exit 2; }

keys=$(yq -r '.profiles[] | keys | .[]' "$PROFILES" | sort -u)
[[ -n "$keys" ]] || { echo "check-knob-readers.sh: no profile keys in $PROFILES" >&2; exit 2; }
# Alternation of the ERE-escaped keys (every metacharacter, not only the dot —
# r256-2 LOW-9); each must be preceded by a dot that is not itself part of an
# identifier (start of line, quote, space, paren, ...).
alt=$(printf '%s\n' "$keys" | sed 's/[]^$.*+?(){}|[]/\\&/g' | paste -sd'|' -)
# Also the trailing two components of every three-part key (`.input.enabled`,
# `.danger_level.enforce`), so a read split across a pipe (`yq '.guardrails | .input.enabled'`)
# or a bracket form that ends in the dotted tail is caught too (audit r256-5, DISS-C-005).
suf=$(printf '%s\n' "$keys" | awk -F. 'NF>=3 {print $(NF-1)"."$NF}' | sort -u | sed 's/[]^$.*+?(){}|[]/\\&/g' | paste -sd'|' -)
if [[ -n "$suf" ]]; then
  pattern="(^|[^A-Za-z0-9_])\\.((${alt})|(${suf}))([^A-Za-z0-9_]|$)"
else
  pattern="(^|[^A-Za-z0-9_])\\.(${alt})([^A-Za-z0-9_]|$)"
fi

# grep: -I skips binaries (no "Binary file matches" pseudo-hits); exit 1 is "no
# match", exit 2 is a grep error (a bad pattern, an unreadable path) and is a
# hard failure, never an empty hit list. Only directories that exist are
# searched (.claude is required; tools/ is optional, a fixture root may lack it)
# and grep's stderr is kept apart from its hits so the message quotes it.
dirs=()
for d in .claude tools; do [[ -d "$ROOT/$d" ]] && dirs+=("$d"); done
[[ " ${dirs[*]} " == *" .claude "* ]] || { echo "check-knob-readers.sh: $ROOT/.claude not found" >&2; exit 2; }
grc=0
gerr="$(mktemp "${TMPDIR:-/tmp}/knob-readers.XXXXXX")"
raw=$(cd "$ROOT" && grep -rnIE "$pattern" "${dirs[@]}" 2>"$gerr") || grc=$?
if (( grc >= 2 )); then
  echo "check-knob-readers.sh: grep failed (exit $grc): $(tr '\n' ' ' <"$gerr")" >&2
  rm -f -- "$gerr"
  exit 2
fi
rm -f -- "$gerr"
hits=$(printf '%s\n' "$raw" \
  | grep -v -E '^(\./)?\.claude/scripts/lib/profile-lib\.sh:' \
  | grep -v -E '^(\./)?tools/check-knob-readers\.sh:' \
  | grep -v -E '^(\./)?\.claude/skills/[^/:]+/resources/__tests__/fixtures/[^:]*:' \
  | sed '/^$/d' || true)
# A skill's recorded test fixtures (.claude/skills/<skill>/resources/__tests__/fixtures/) are
# DATA — e.g. a posted review thread that quotes an offending read — never readers; the
# exclusion is anchored to that one root (Sprint 272 review, DISS-C-008: a segment-anywhere
# rule would also drop .claude/hooks/tests/fixtures/x.sh). Controls: profile-lib.bats PL-17
# (planted reader caught) and PL-18 (a reader under a hooks tests/fixtures/ dir is still
# caught; a skill fixture quoting a read is not). cycle-133 Sprint 272: the verbatim PR #1289
# comment fixtures under bridgebuilder-review/resources/__tests__/fixtures/ quote one.
if [[ -n "$hits" ]]; then
  echo "check-knob-readers.sh: direct read(s) of a profile key; use loa_knob from .claude/scripts/lib/profile-lib.sh:" >&2
  printf '%s\n' "$hits" | cut -c1-240 >&2
  exit 1
fi
echo "check-knob-readers.sh: no direct profile-key reads ($(printf '%s\n' "$keys" | wc -l | tr -d ' ') keys checked)"
