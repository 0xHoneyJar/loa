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

# Run compiled TypeScript via Node (no npx tsx — SKP-002)
exec node "${SKILL_DIR}/dist/main.js" "$@"
