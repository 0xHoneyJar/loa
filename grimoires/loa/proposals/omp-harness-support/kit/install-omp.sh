#!/usr/bin/env bash
# =============================================================================
# install-omp.sh — project Loa's OMP (Pi) first-class surface into a repo.
#
# Idempotent. Run from a Loa-installed repo root (or pass --root PATH). Makes a
# Claude-native Loa install work first-class under OMP by closing the three
# discovery/execution gaps OMP has for `.claude/`-only frameworks:
#
#   R1  kernel entrypoint — ensure the OMP-discovered AGENTS.md @-imports the
#       kernel (OMP reads AGENTS.md via the agents-md provider and expands
#       @imports; it does NOT read root CLAUDE.md the way Claude Code does).
#   R2  sticky invariants — install native `.omp/RULES.md` (OMP re-attaches it
#       across long sessions; `.claude/rules/*` is not an OMP rules provider).
#   R3  enforcement bridge — install `.omp/hooks/pre/loa-guards.ts`, which
#       shells Loa's canonical bash guards (OMP does not run `.claude`
#       settings.json shell hooks).
#
# Safe by design: never edits `.claude/` (System Zone); never overwrites an
# existing `.omp/RULES.md` or hook without --force; AGENTS.md edit is append-only
# and idempotent. Restart OMP after running (hooks/skills load at startup).
# =============================================================================
set -euo pipefail

ROOT="."
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KERNEL_REL=".claude/loa/CLAUDE.loa.md"
IMPORT_LINE="@${KERNEL_REL}"

echo "==> Loa OMP surface install into: $ROOT"

# ---- preflight ------------------------------------------------------------
if [ ! -e "$ROOT/$KERNEL_REL" ]; then
  echo "ERROR: $KERNEL_REL not found under $ROOT — is Loa installed here?" >&2
  exit 1
fi

# ---- R1: kernel entrypoint for OMP (AGENTS.md @import, append-only) --------
AGENTS="$ROOT/AGENTS.md"
if [ ! -e "$AGENTS" ]; then
  printf '%s\n' "$IMPORT_LINE" > "$AGENTS"
  echo "  [R1] created AGENTS.md with kernel @import"
elif grep -qF "$IMPORT_LINE" "$AGENTS"; then
  echo "  [R1] AGENTS.md already imports the kernel — skip"
else
  # OMP expands an @import anywhere it sits at line start; append a block.
  printf '\n<!-- loa: kernel entrypoint for OMP/AGENTS.md-aware tools -->\n%s\n' "$IMPORT_LINE" >> "$AGENTS"
  echo "  [R1] appended kernel @import to AGENTS.md"
fi

# ---- R2: sticky rules -----------------------------------------------------
mkdir -p "$ROOT/.omp"
RULES="$ROOT/.omp/RULES.md"
if [ -e "$RULES" ] && [ "$FORCE" -ne 1 ]; then
  echo "  [R2] .omp/RULES.md exists — skip (use --force to overwrite)"
else
  cp "$KIT/RULES.md" "$RULES"
  echo "  [R2] installed .omp/RULES.md"
fi

# ---- R3: enforcement bridge ----------------------------------------------
mkdir -p "$ROOT/.omp/hooks/pre"
HOOK="$ROOT/.omp/hooks/pre/loa-guards.ts"
if [ -e "$HOOK" ] && [ "$FORCE" -ne 1 ]; then
  echo "  [R3] .omp/hooks/pre/loa-guards.ts exists — skip (use --force to overwrite)"
else
  cp "$KIT/hooks/pre/loa-guards.ts" "$HOOK"
  echo "  [R3] installed .omp/hooks/pre/loa-guards.ts"
fi

echo
echo "Done. Restart OMP to load the kernel, sticky rules, and guard hook."
echo "Note: zone-write-guard enforces only when grimoires/loa/zones.yaml exists;"
echo "      block-destructive-bash is active immediately."
