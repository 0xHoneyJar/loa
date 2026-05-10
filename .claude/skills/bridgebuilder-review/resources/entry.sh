#!/usr/bin/env bash
# Bridgebuilder Autonomous PR Review — Loa skill entry point
# Invoked by Loa when user runs /bridgebuilder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bash 4.0+ version guard
source "${SKILL_DIR}/../../scripts/bash-version-guard.sh"

# .env Trust Model (Decision Trail — Bridgebuilder Deep Review, cycle-037):
# `source .env` executes arbitrary shell code — this is by design.
# .env files are trusted local input: user-controlled, never committed (.gitignore'd).
# Same trust model as Node's dotenv and Python's python-dotenv libraries.
# API keys sourced here are available to the Node child process (exec'd below).
# Secrets in review output are stripped by the redaction pipeline
# (bridge-github-trail.sh § redact_security_content).
#
# Original: Source .env files for API keys (ANTHROPIC_API_KEY etc.) — issue #395
# set -a exports all sourced variables; set +a restores default behavior
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi
if [[ -f .env.local ]]; then
  set -a; source .env.local; set +a
fi

# Happy Eyeballs autoselection-attempt-timeout (cycle-102 sprint-1E / KF-001 fix).
#
# Node 20+ undici fetch uses RFC 8305 Happy Eyeballs to race concurrent IPv6 +
# IPv4 connection attempts. The default --network-family-autoselection-attempt-
# timeout is 250ms — when an attempt does not complete a TCP handshake within
# that window, Node aborts it and aggregates the failure. On networks where
# IPv4 TCP handshake to specific provider endpoints (api.anthropic.com,
# generativelanguage.googleapis.com) routinely takes >250ms (common with
# slow-but-reachable IPv4 paths through DDoS protection layers like Cloudflare),
# the attempt is killed before TCP completes and Node reports
# `TypeError: fetch failed; cause=AggregateError [ETIMEDOUT]`. This presented
# as full bridgebuilder degradation across 3 invocations on PR #826 (KF-001
# in grimoires/loa/known-failures.md), with anthropic + google failing while
# openai succeeded — openai's faster IPv4 path completed inside 250ms.
#
# Bumping the autoselection-attempt-timeout to 5000ms gives each connection
# attempt enough time to complete the TCP+TLS handshake on slow-but-reachable
# IPv4 paths. Effects:
#   - Users with working IPv6: no slowdown — IPv6 wins fast; autoselection
#     completes in tens of milliseconds. The 5000ms is a CEILING, not a delay.
#   - Users with broken IPv6 (EADDRNOTAVAIL or no v6 stack): autoselection
#     waits up to 5s for IPv4 to complete the handshake. Real-world IPv4
#     handshakes complete in 1-3s on this class of network.
#   - Users with both broken: waits 5s before declaring failure (vs 250ms
#     previously). Acceptable for the rare full-network-outage case.
#
# Honors existing NODE_OPTIONS (appends rather than overwrites) so operators
# who set their own NODE_OPTIONS don't get clobbered. The flag has been
# available since Node 18.18 / 20.0 — covered by the engines.node >=20.0.0
# pin in package.json. Set LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX=1 to opt out.
#
# Diagnostic evidence (commit message of this patch references upstream issue):
#   - Direct curl to api.anthropic.com IPv4 succeeds in 0.9-3s
#   - Python httpx (cheval.py) succeeds against all 3 providers
#   - Node fetch fails with: sub-error[0] ETIMEDOUT IPv4-addr,
#     sub-error[1] EADDRNOTAVAIL IPv6-addr (no v6 stack)
#   - With --network-family-autoselection-attempt-timeout=5000: Node
#     fetch returns HTTP 401 (correct auth-failure response) instantly.
#
# Upstream issue: https://github.com/0xHoneyJar/loa/issues/827
# Node CLI ref:   https://nodejs.org/api/cli.html#--network-family-autoselection-attempt-timeoutms
if [[ -z "${LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX:-}" ]]; then
  if [[ "${NODE_OPTIONS:-}" != *"--network-family-autoselection-attempt-timeout"* ]]; then
    export NODE_OPTIONS="${NODE_OPTIONS:+${NODE_OPTIONS} }--network-family-autoselection-attempt-timeout=5000"
  fi
fi

# Run compiled TypeScript via Node (no npx tsx — SKP-002)
exec node "${SKILL_DIR}/dist/main.js" "$@"
