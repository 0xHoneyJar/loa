#!/usr/bin/env bash
# =============================================================================
# advisor-strategy-resolver.sh — Cycle-108 sprint-1 T1.I bash twin
# =============================================================================
# Thin bash wrapper that exec's the Python canonical resolver to guarantee
# single-source-of-truth resolution semantics. There is NO parallel bash
# implementation — the function shells out to Python and consumes the
# JSON ResolvedTier from stdout.
#
# This pattern intentionally avoids the cross-runtime parity trap class
# documented in feedback_cross_runtime_parity_traps.md (cycle-099 lessons):
# when bash and Python independently re-implement the same logic, they
# drift in subtle ways (Unicode normalization, JSON ordering, regex
# semantics). The exec-wrapper pattern eliminates the drift surface.
#
# Closes SDD §3.5 (FR-2 cheval routing extension bash twin) and §21.1
# (Flatline IMP-001 single source of truth for AdvisorStrategyConfig).
#
# Usage (as library — source me):
#   source .claude/scripts/lib/advisor-strategy-resolver.sh
#   resolved_json=$(advisor_strategy_resolve "implementation" "implementing-tasks" "anthropic")
#   model_id=$(echo "$resolved_json" | jq -r '.model_id')
#
# Usage (as CLI — for testing):
#   .claude/scripts/lib/advisor-strategy-resolver.sh resolve <role> <skill> <provider>
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# advisor_strategy_resolve <role> <skill> <provider>
#   Returns JSON on stdout matching ResolvedTier dataclass.
#   Exit codes:
#     0  - success
#     78 - EX_CONFIG (advisor-strategy config invalid; see stderr)
#     1  - other error (Python ImportError, missing jsonschema, etc)
advisor_strategy_resolve() {
    local role="$1"
    local skill="$2"
    local provider="$3"

    # BB iter-3 F002 closure: pass role/skill/provider via env vars + quoted
    # heredoc to avoid shell→python source-interpolation. args.skill is
    # free-form caller-controlled text — a literal single-quote or newline
    # in the skill name would have escaped the Python literal in the prior
    # f-string interpolation.
    LOA_RESOLVER_ROLE="$role" \
    LOA_RESOLVER_SKILL="$skill" \
    LOA_RESOLVER_PROVIDER="$provider" \
    LOA_RESOLVER_PROJECT_ROOT="$PROJECT_ROOT" \
    python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

_project_root = os.environ["LOA_RESOLVER_PROJECT_ROOT"]
_role = os.environ["LOA_RESOLVER_ROLE"]
_skill = os.environ["LOA_RESOLVER_SKILL"]
_provider = os.environ["LOA_RESOLVER_PROVIDER"]

sys.path.insert(0, str(Path(_project_root) / ".claude" / "adapters"))
try:
    from loa_cheval.config.advisor_strategy import (
        load_advisor_strategy,
        AdvisorStrategyConfig,
        ConfigError,
    )
except ImportError as e:
    sys.stderr.write(f"[advisor-strategy-resolver] ImportError: {e}\n")
    sys.exit(1)

try:
    cfg = load_advisor_strategy(Path(_project_root))
except ConfigError as e:
    sys.stderr.write(f"[advisor-strategy-resolver] EX_CONFIG: {e}\n")
    sys.exit(78)

if not cfg.enabled:
    # Disabled-by-config or kill-switch — emit a sentinel that callers can
    # detect via .tier_source == 'disabled_legacy'
    out = {
        "model_id": "",
        "tier": "",
        "tier_source": "disabled_legacy",
        "tier_resolution": "disabled",
        "provider": _provider,
    }
    print(json.dumps(out))
    sys.exit(0)

try:
    resolved = cfg.resolve(role=_role, skill=_skill, provider=_provider)
except ConfigError as e:
    sys.stderr.write(f"[advisor-strategy-resolver] EX_CONFIG: {e}\n")
    sys.exit(78)

print(json.dumps({
    "model_id": resolved.model_id,
    "tier": resolved.tier,
    "tier_source": resolved.tier_source,
    "tier_resolution": resolved.tier_resolution,
    "provider": resolved.provider,
}))
PY
}

# CLI entrypoint when not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        resolve)
            shift
            if [[ "$#" -ne 3 ]]; then
                echo "Usage: $0 resolve <role> <skill> <provider>" >&2
                exit 2
            fi
            advisor_strategy_resolve "$@"
            ;;
        -h|--help|"")
            cat <<EOF
advisor-strategy-resolver.sh — Cycle-108 T1.I bash twin

Usage:
  Source me:
    source .claude/scripts/lib/advisor-strategy-resolver.sh
    advisor_strategy_resolve <role> <skill> <provider>

  Or CLI:
    $0 resolve <role> <skill> <provider>

Role: planning | review | implementation
Provider: anthropic | openai | google

Returns JSON ResolvedTier on stdout. Exit 78 = EX_CONFIG (invalid config).
See SDD §3.5 + §21.1 for details.
EOF
            exit 0
            ;;
        *) echo "Unknown subcommand: $1" >&2; exit 2 ;;
    esac
fi
