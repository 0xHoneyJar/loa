#!/usr/bin/env bash
# update-loa.sh - Unified update command for Loa framework
# Detects installation mode and routes to appropriate update mechanism.
#
# Submodule mode: fetches, checks out tag/ref, verifies symlinks, supply chain checks
# Vendored mode: delegates to update.sh
#
# Usage:
#   update-loa.sh [OPTIONS]
#
# Options:
#   --tag <tag>               Update to specific tag (e.g., v1.39.0)
#   --ref <ref>               Update to specific ref
#   --require-submodule       CI: fail if not submodule mode
#   --require-verified-origin CI: fail if remote URL doesn't match allowlist
#   --no-commit               Skip creating git commit
#   -h, --help                Show help
#
set -euo pipefail

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[loa-update]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa-update]${NC} WARNING: $*"; }
err() { echo -e "${RED}[loa-update]${NC} ERROR: $*" >&2; exit 1; }
info() { echo -e "${CYAN}[loa-update]${NC} $*"; }
step() { echo -e "${CYAN}[loa-update]${NC} -> $*"; }

# === Configuration ===
VERSION_FILE=".loa-version.json"
SUBMODULE_PATH=".loa"
UPDATE_TAG=""
UPDATE_REF=""
REQUIRE_SUBMODULE=false
REQUIRE_VERIFIED_ORIGIN=false
NO_COMMIT=false

# Expected remote URL allowlist (Flatline SKP-005)
# Configurable via .loa.config.yaml update.allowed_remotes[] for fork users (F-006)
ALLOWED_REMOTES=()
if command -v yq &>/dev/null && [[ -f ".loa.config.yaml" ]]; then
  while IFS= read -r remote; do
    [[ -n "$remote" ]] && ALLOWED_REMOTES+=("$remote")
  done < <(yq '.update.allowed_remotes[]' .loa.config.yaml 2>/dev/null || true)
fi
# Default if no config or empty
if [[ ${#ALLOWED_REMOTES[@]} -eq 0 ]]; then
  ALLOWED_REMOTES=(
    "https://github.com/0xHoneyJar/loa.git"
    "https://github.com/0xHoneyJar/loa"
    "git@github.com:0xHoneyJar/loa.git"
  )
fi

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)
      UPDATE_TAG="$2"
      shift 2
      ;;
    --ref)
      UPDATE_REF="$2"
      shift 2
      ;;
    --require-submodule)
      REQUIRE_SUBMODULE=true
      shift
      ;;
    --require-verified-origin)
      REQUIRE_VERIFIED_ORIGIN=true
      shift
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    -h|--help)
      echo "Usage: update-loa.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --tag <tag>               Update to specific tag (e.g., v1.39.0)"
      echo "  --ref <ref>               Update to specific ref"
      echo "  --require-submodule       CI: fail if not submodule mode"
      echo "  --require-verified-origin CI: fail if remote URL doesn't match allowlist"
      echo "  --no-commit               Skip creating git commit"
      echo ""
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      shift
      ;;
  esac
done

# === Mode Detection ===
detect_mode() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "unknown"
    return
  fi
  local mode
  mode=$(jq -r '.installation_mode // "standard"' "$VERSION_FILE" 2>/dev/null)
  echo "$mode"
}

# === Supply Chain Integrity (Flatline SKP-005) ===
verify_submodule_integrity() {
  step "Verifying supply chain integrity..."

  if [[ ! -d "$SUBMODULE_PATH" ]]; then
    err "Submodule directory $SUBMODULE_PATH not found."
  fi

  # Check remote URL against allowlist
  local remote_url
  remote_url=$(cd "$SUBMODULE_PATH" && git remote get-url origin 2>/dev/null || echo "")

  if [[ -z "$remote_url" ]]; then
    err "Cannot determine submodule remote URL."
  fi

  local url_verified=false
  for allowed in "${ALLOWED_REMOTES[@]}"; do
    if [[ "$remote_url" == "$allowed" ]]; then
      url_verified=true
      break
    fi
  done

  if [[ "$url_verified" == "false" ]]; then
    if [[ "$REQUIRE_VERIFIED_ORIGIN" == "true" ]]; then
      err "Supply chain verification FAILED: Remote URL '$remote_url' not in allowlist.
Expected one of:
  ${ALLOWED_REMOTES[*]}"
    else
      warn "Remote URL '$remote_url' not in allowlist. Proceeding anyway."
    fi
  else
    log "Supply chain: Remote URL verified"
  fi

  # Enforce HTTPS
  if [[ "$remote_url" == http://* ]]; then
    err "Insecure transport: submodule uses HTTP. HTTPS or SSH required."
  fi

  log "Supply chain integrity verified"
}

# === Submodule Update ===
update_submodule() {
  step "Updating Loa submodule..."

  # Determine target ref
  local target_ref=""
  if [[ -n "$UPDATE_TAG" ]]; then
    target_ref="$UPDATE_TAG"
  elif [[ -n "$UPDATE_REF" ]]; then
    target_ref="$UPDATE_REF"
  fi

  # Fetch latest
  (cd "$SUBMODULE_PATH" && git fetch origin --tags --quiet)

  if [[ -n "$target_ref" ]]; then
    # Checkout specific ref/tag
    step "Checking out ref: $target_ref..."
    (cd "$SUBMODULE_PATH" && git checkout "$target_ref" --quiet)
  else
    # Pin to latest tag (not branch HEAD) by default
    local latest_tag
    latest_tag=$(cd "$SUBMODULE_PATH" && git tag -l 'v*' --sort=-v:refname 2>/dev/null | head -1)
    if [[ -n "$latest_tag" ]]; then
      step "Checking out latest tag: $latest_tag..."
      (cd "$SUBMODULE_PATH" && git checkout "$latest_tag" --quiet)
      target_ref="$latest_tag"
    else
      # No tags available — update to latest branch HEAD
      step "No tags found. Updating to latest main..."
      (cd "$SUBMODULE_PATH" && git pull origin main --quiet 2>/dev/null || true)
      target_ref="main"
    fi
  fi

  # Get new commit hash
  local new_commit
  new_commit=$(cd "$SUBMODULE_PATH" && git rev-parse HEAD)
  local new_version
  new_version=$(cd "$SUBMODULE_PATH" && git describe --tags --always 2>/dev/null || echo "$target_ref")

  log "Submodule updated to: $new_version ($new_commit)"

  # Update .loa-version.json
  step "Updating version manifest..."
  local old_commit
  old_commit=$(jq -r '.submodule.commit // "unknown"' "$VERSION_FILE" 2>/dev/null)

  local tmp_version
  tmp_version=$(mktemp)
  jq --arg v "$new_version" \
     --arg c "$new_commit" \
     --arg r "$target_ref" \
     --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.framework_version = $v | .submodule.commit = $c | .submodule.ref = $r | .last_sync = $t' \
     "$VERSION_FILE" > "$tmp_version" && mv "$tmp_version" "$VERSION_FILE"

  log "Version manifest updated"

  # Verify and reconcile symlinks
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local submodule_script="${script_dir}/mount-submodule.sh"
  if [[ -f "$submodule_script" ]]; then
    # Source verify_and_reconcile_symlinks if available
    if grep -q "verify_and_reconcile_symlinks" "$submodule_script" 2>/dev/null; then
      source "$submodule_script" --source-only 2>/dev/null || true
      if type verify_and_reconcile_symlinks &>/dev/null; then
        step "Reconciling symlinks..."
        verify_and_reconcile_symlinks
      fi
    fi
  fi

  # Commit if requested
  if [[ "$NO_COMMIT" != "true" ]]; then
    step "Committing update..."
    git add "$SUBMODULE_PATH" "$VERSION_FILE" 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "chore(loa): update framework ${old_commit:0:8} -> ${new_commit:0:8}

- Updated .loa submodule to $new_version
- Ref: $target_ref
- Commit: $new_commit

Generated by Loa update-loa.sh" \
        --no-verify 2>/dev/null || {
        # --no-verify: Submodule pointer update — no app code touched. User hooks would fail.
        warn "Auto-commit failed. Please commit manually."
      }
    else
      log "No changes to commit (already up to date)"
    fi
  fi
}

# === Main ===
main() {
  echo ""
  log "======================================================================="
  log "  Loa Framework Update"
  log "======================================================================="
  echo ""

  local mode
  mode=$(detect_mode)
  log "Detected mode: $mode"

  # CI enforcement flags
  if [[ "$REQUIRE_SUBMODULE" == "true" ]] && [[ "$mode" != "submodule" ]]; then
    err "CI check failed: --require-submodule but installation mode is '$mode'.
Install in submodule mode: mount-loa.sh (default)"
  fi

  case "$mode" in
    submodule)
      verify_submodule_integrity
      update_submodule
      ;;
    standard)
      # Delegate to existing update.sh for vendored mode
      local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      local update_script="${script_dir}/update.sh"
      if [[ -x "$update_script" ]]; then
        log "Delegating to update.sh (vendored mode)..."
        exec "$update_script" "$@"
      else
        err "update.sh not found at: $update_script"
      fi
      ;;
    *)
      err "Cannot determine installation mode. Is Loa installed?
Run: mount-loa.sh"
      ;;
  esac

  echo ""
  log "Update complete."
  echo ""
}

main "$@"
