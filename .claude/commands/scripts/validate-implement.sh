#!/bin/bash
# validate-implement.sh
# Pre-flight validation for /implement command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SPRINT_ID="$1"

# Validate arguments
if [ -z "$SPRINT_ID" ]; then
    error "Sprint ID required. Usage: /implement sprint-N"
fi

# Run validations
check_setup_complete
validate_sprint_id "$SPRINT_ID"
check_implement_prerequisites
check_sprint_in_plan "$SPRINT_ID"
check_sprint_not_completed "$SPRINT_ID"

success "Pre-flight validation passed for $SPRINT_ID"
exit 0
