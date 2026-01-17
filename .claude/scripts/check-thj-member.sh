#!/usr/bin/env bash
# =============================================================================
# Check THJ Membership
# =============================================================================
# Pre-flight check script for THJ-only commands (e.g., /feedback).
# Uses API key presence as the detection mechanism.
#
# Exit codes:
#   0 - User is THJ member (LOA_CONSTRUCTS_API_KEY is set and non-empty)
#   1 - User is not THJ member
#
# Usage:
#   .claude/scripts/check-thj-member.sh
#
# In command pre_flight:
#   - check: "script"
#     script: ".claude/scripts/check-thj-member.sh"
#     error: "THJ membership required. Set LOA_CONSTRUCTS_API_KEY."
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the canonical is_thj_member() function
source "${SCRIPT_DIR}/constructs-lib.sh"

# Check and exit with appropriate code
is_thj_member
