#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/loa-harness-smoke-$$"
mkdir -p "$TMP/.loa-harness/bin" "$TMP/config"
cp "$ROOT/bin/loa_harness.py" "$TMP/.loa-harness/bin/"
cp "$ROOT/config/policy.example.json" "$TMP/.loa-harness/policy.json"
cat > "$TMP/CLAUDE.md" <<'EOF'
# Project Instructions
Use the LOA harness.
EOF
(
  cd "$TMP"
  python3 .loa-harness/bin/loa_harness.py init >/dev/null
  if echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | python3 .loa-harness/bin/loa_harness.py hook --event PreToolUse | grep -q 'permissionDecision'; then
    echo "blocked dangerous bash: ok"
  else
    echo "expected dangerous bash to be blocked" >&2
    exit 1
  fi
  python3 .loa-harness/bin/loa_harness.py request-transition --to ORIENTING --reason "bootstrap" >/dev/null
  echo '{"hook_event_name":"Stop","session_id":"smoke"}' | python3 .loa-harness/bin/loa_harness.py hook --event Stop >/dev/null
  python3 .loa-harness/bin/loa_harness.py verify
)
rm -rf "$TMP"
