#!/bin/bash
# validate-audit-sprint.sh
# Pre-flight validation for /audit-sprint command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SPRINT_ID="$1"

# Validate arguments
if [ -z "$SPRINT_ID" ]; then
    error "Sprint ID required. Usage: /audit-sprint sprint-N"
fi

# Run validations
check_setup_complete
validate_sprint_id "$SPRINT_ID"
check_audit_prerequisites "$SPRINT_ID"
check_sprint_not_completed "$SPRINT_ID"

success "Pre-flight validation passed for $SPRINT_ID"
exit 0
