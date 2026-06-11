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
# Usage: check-no-suffixed-mktemp.sh [scan-root ...]
#   (default scan root: .claude/scripts, relative to repo root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

roots=("$@")
if [[ ${#roots[@]} -eq 0 ]]; then
    roots=("$REPO_ROOT/.claude/scripts")
fi

# X-run of 3+ followed by .<alpha> — the non-trailing-suffix shape.
pattern='mktemp[^#]*XXX+\.[A-Za-z]'

hits=$(grep -rnE "$pattern" "${roots[@]}" --include='*.sh' 2>/dev/null \
    | grep -v 'check-no-suffixed-mktemp' || true)

if [[ -n "$hits" ]]; then
    echo "ERROR: suffixed mktemp templates found — BSD/macOS mktemp creates these literally (#978):" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Fix: make the X-run the trailing token (create-then-rename when an" >&2
    echo "extension is required; see make_temp in .claude/scripts/compat-lib.sh)." >&2
    exit 1
fi

echo "OK: no suffixed mktemp templates under: ${roots[*]}"
