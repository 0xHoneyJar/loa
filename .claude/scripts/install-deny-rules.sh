#!/usr/bin/env bash
# =============================================================================
# Install Deny Rules — Merge recommended deny rules into ~/.claude/settings.json
# =============================================================================
# Called by /mount and /loa setup to install credential deny rules.
# Additive merge — never removes existing deny rules.
#
# Usage:
#   install-deny-rules.sh --auto       Install without prompting
#   install-deny-rules.sh --prompt     Ask before installing
#   install-deny-rules.sh --dry-run    Show what would be added
#
# Part of Loa Harness Engineering (cycle-011, issue #297)
# =============================================================================

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DENY_TEMPLATE=".claude/hooks/settings.deny.json"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)   MODE="auto"; shift ;;
    --prompt) MODE="prompt"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: install-deny-rules.sh [--auto|--prompt|--dry-run]"
      echo ""
      echo "  --auto     Install without prompting"
      echo "  --prompt   Ask before installing"
      echo "  --dry-run  Show what would be added"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" && "$DRY_RUN" == "false" ]]; then
  echo "ERROR: Specify --auto, --prompt, or --dry-run" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate template exists
# ---------------------------------------------------------------------------
if [[ ! -f "$DENY_TEMPLATE" ]]; then
  echo "ERROR: Deny rules template not found at $DENY_TEMPLATE" >&2
  exit 1
fi

# Check jq is available
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract new rules from template
# ---------------------------------------------------------------------------
new_rules=$(jq -r '.permissions.deny[]' "$DENY_TEMPLATE")

# ---------------------------------------------------------------------------
# Dry-run mode
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== Deny Rules Dry Run ==="
  echo ""
  echo "Template: $DENY_TEMPLATE"
  echo "Target:   $SETTINGS"
  echo ""

  if [[ ! -f "$SETTINGS" ]]; then
    echo "Settings file does not exist. Would create with all rules:"
  else
    echo "Existing deny rules:"
    jq -r '.permissions.deny[]? // empty' "$SETTINGS" 2>/dev/null || echo "  (none)"
    echo ""
    echo "Rules to add:"
  fi

  # Show which rules are new
  existing_rules=""
  if [[ -f "$SETTINGS" ]]; then
    existing_rules=$(jq -r '.permissions.deny[]? // empty' "$SETTINGS" 2>/dev/null)
  fi

  added=0
  while IFS= read -r rule; do
    if [[ -n "$existing_rules" ]] && echo "$existing_rules" | grep -qF "$rule"; then
      echo "  [exists] $rule"
    else
      echo "  [NEW]    $rule"
      added=$((added + 1))
    fi
  done <<< "$new_rules"

  echo ""
  echo "Would add $added new rule(s)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Prompt mode
# ---------------------------------------------------------------------------
if [[ "$MODE" == "prompt" ]]; then
  echo "Loa recommends installing deny rules to protect sensitive files."
  echo ""
  echo "This will block agent access to:"
  echo "  - SSH keys (~/.ssh/)"
  echo "  - AWS credentials (~/.aws/)"
  echo "  - Kubernetes config (~/.kube/)"
  echo "  - GPG keys (~/.gnupg/)"
  echo "  - Package registry credentials (~/.npmrc, ~/.pypirc)"
  echo "  - Git credentials (~/.git-credentials, ~/.config/gh/)"
  echo "  - Shell config edits (~/.bashrc, ~/.zshrc, ~/.profile)"
  echo ""
  read -rp "Install deny rules? [Y/n] " answer
  if [[ "$answer" =~ ^[Nn] ]]; then
    echo "Skipped. Run 'install-deny-rules.sh --auto' later to install."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Create settings directory if needed
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$SETTINGS")"

# ---------------------------------------------------------------------------
# Backup existing settings
# ---------------------------------------------------------------------------
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "${SETTINGS}.bak"
  echo "Backed up existing settings to ${SETTINGS}.bak"
fi

# ---------------------------------------------------------------------------
# Merge deny rules (additive)
# ---------------------------------------------------------------------------
if [[ ! -f "$SETTINGS" ]]; then
  # No existing settings — create from template structure
  jq '{permissions: {deny: .permissions.deny}}' "$DENY_TEMPLATE" > "$SETTINGS"
  added=$(jq '.permissions.deny | length' "$SETTINGS")
  echo "Created $SETTINGS with $added deny rules."
else
  # Merge: add rules that don't already exist (single jq pass)
  template_rules="$DENY_TEMPLATE"
  jq --slurpfile new "$template_rules" '
    .permissions.deny //= [] |
    .permissions.deny as $existing |
    ($new[0].permissions.deny | map(select(. as $r | $existing | index($r) | not))) as $to_add |
    .permissions.deny += $to_add
  ' "$SETTINGS" > "${SETTINGS}.tmp"

  # Count additions by comparing backup to merged result
  added=$(jq -r '.permissions.deny | length' "${SETTINGS}.tmp")
  existing=$(jq -r '.permissions.deny // [] | length' "${SETTINGS}.bak")
  added=$((added - existing))

  mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Added $added new deny rule(s) to $SETTINGS."
fi

# ---------------------------------------------------------------------------
# Report final state
# ---------------------------------------------------------------------------
echo ""
echo "Current deny rules ($(jq '.permissions.deny | length' "$SETTINGS")):"
jq -r '.permissions.deny[]' "$SETTINGS" | sed 's/^/  /'
