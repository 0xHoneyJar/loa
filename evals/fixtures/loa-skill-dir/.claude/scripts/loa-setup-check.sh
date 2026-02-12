#!/usr/bin/env bash
# loa-setup-check.sh — Environment validation engine
# Usage: .claude/scripts/loa-setup-check.sh [--json]
# Outputs one JSON line per check to stdout (JSONL format).
# Exit: 0 if all required pass, 1 if any required fail.
set -euo pipefail

errors=0

# Step 1: API key presence (NFR-8: zero key material — boolean only)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo '{"step":1,"name":"api_key","status":"pass","detail":"ANTHROPIC_API_KEY is set"}'
else
  echo '{"step":1,"name":"api_key","status":"warn","detail":"ANTHROPIC_API_KEY not set"}'
fi

# Step 2: Required deps
for dep in jq yq git; do
  if command -v "$dep" >/dev/null 2>&1; then
    ver=$("$dep" --version 2>&1 | head -1)
    jq -n --arg dep "$dep" --arg ver "$ver" \
      '{step:2,name:("dep_" + $dep),status:"pass",detail:$ver}'
  else
    jq -n --arg dep "$dep" \
      '{step:2,name:("dep_" + $dep),status:"fail",detail:"Not found — required"}'
    errors=$((errors + 1))
  fi
done

# Step 3: Optional tools
if command -v br >/dev/null 2>&1; then
  ver=$(br --version 2>&1 | head -1)
  jq -n --arg ver "$ver" '{step:3,name:"beads",status:"pass",detail:$ver}'
else
  echo '{"step":3,"name":"beads","status":"warn","detail":"Not installed","install":"cargo install beads_rust"}'
fi

if command -v ck >/dev/null 2>&1; then
  ver=$(ck --version 2>&1 | head -1)
  jq -n --arg ver "$ver" '{step:3,name:"ck",status:"pass",detail:$ver}'
else
  echo '{"step":3,"name":"ck","status":"warn","detail":"Not installed","install":"See INSTALLATION.md"}'
fi

# Step 4: Configuration status
if [[ -f ".loa.config.yaml" ]]; then
  flatline=$(yq '.flatline_protocol.enabled // false' .loa.config.yaml 2>/dev/null)
  memory=$(yq '.memory.enabled // true' .loa.config.yaml 2>/dev/null)
  enhance=$(yq '.prompt_enhancement.invisible_mode.enabled // true' .loa.config.yaml 2>/dev/null)
  # Ensure values are valid JSON booleans (--argjson requires valid JSON)
  case "$flatline" in true|false) ;; *) flatline="false" ;; esac
  case "$memory" in true|false) ;; *) memory="true" ;; esac
  case "$enhance" in true|false) ;; *) enhance="true" ;; esac
  jq -n \
    --argjson flatline "${flatline}" \
    --argjson memory "${memory}" \
    --argjson enhance "${enhance}" \
    '{step:4,name:"config",status:"pass",features:{flatline:$flatline,memory:$memory,enhancement:$enhance}}'
else
  echo '{"step":4,"name":"config","status":"warn","detail":".loa.config.yaml not found"}'
fi

exit "$([ "$errors" -gt 0 ] && echo 1 || echo 0)"
