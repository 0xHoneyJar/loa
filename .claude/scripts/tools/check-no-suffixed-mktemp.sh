#!/usr/bin/env bash
# =============================================================================
# check-no-suffixed-mktemp.sh — fence against BSD-fatal mktemp templates
# =============================================================================
# bug-978 (#978) / sprint-bug-198. BSD/macOS mktemp only expands a template's
# X-run when it is the TRAILING token. `mktemp foo.XXXXXX.json` creates a
# LITERAL foo.XXXXXX.json on the first call and fails "File exists" on the
# next — observed as flatline's 3-voice review silently degrading to
# voices=1/3 on macOS.
#
# Detects: any mktemp invocation whose template has an X-run (3+) followed by
# a dot-suffix. Trailing-X templates (`vq-input.XXXXXX`) pass.
#
# Fix pattern: put the X-run last; when a real extension is required
# (yq format detection, tsx imports), create-then-rename:
#     f=$(mktemp "${TMPDIR:-/tmp}/prefix-XXXXXX") && mv "$f" "$f.json" && f="$f.json"
# or use make_temp from .claude/scripts/compat-lib.sh.
#
# Iteration-1 (review): a SECOND portability class joined the fence — the
# GNU-only/divergent flags. `mktemp -p DIR` does not exist on BSD at all,
# and `-t` means "deprecated template" on GNU but "prefix" on BSD. After the
# sprint-bug-198 sweep the tree has zero legitimate uses of either, so the
# invariant is simply: no `mktemp -p` / `mktemp -t` anywhere. Scope also
# widened to tests/ (*.bats included) — the red-team jailbreak suite runs on
# operator macOS machines.
#
# Usage: check-no-suffixed-mktemp.sh [scan-root ...]
#   (default scan roots: .claude/scripts + tests, relative to repo root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

roots=("$@")
if [[ ${#roots[@]} -eq 0 ]]; then
    roots=("$REPO_ROOT/.claude/scripts" "$REPO_ROOT/tests")
fi

# Class 1: X-run of 3+ followed by .<alpha> — the non-trailing-suffix shape.
# Class 2: GNU-only -p / GNU-vs-BSD-divergent -t flags.
pattern='mktemp[^#]*XXX+\.[A-Za-z]|mktemp[[:space:]]+-[pt][[:space:]"]'

# mktemp-bsd-portability.bats plants hazard strings on purpose (the
# scanner-not-toothless tests) — excluded like the scanner itself.
hits=$(grep -rnE "$pattern" "${roots[@]}" --include='*.sh' --include='*.bats' 2>/dev/null \
    | grep -v 'check-no-suffixed-mktemp' \
    | grep -v 'mktemp-bsd-portability\.bats' || true)

if [[ -n "$hits" ]]; then
    echo "ERROR: BSD-incompatible mktemp usage found (#978):" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Fix: plain trailing-X templates only — no -p/-t flags, X-run last" >&2
    echo "(create-then-rename when an extension is required; see make_temp" >&2
    echo "in .claude/scripts/compat-lib.sh)." >&2
    exit 1
fi

echo "OK: no BSD-incompatible mktemp usage under: ${roots[*]}"
