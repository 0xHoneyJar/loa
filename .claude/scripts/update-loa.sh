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

# === Ledger Schema Migration Check ===
# After submodule update, compare upstream vs local schema_version.
# Warns when upstream has a newer schema — advisory only (no hard fail).
check_ledger_schema() {
  local upstream_ledger="$SUBMODULE_PATH/grimoires/loa/ledger.json"
  local local_ledger="grimoires/loa/ledger.json"

  # Skip if either file doesn't exist
  [[ -f "$upstream_ledger" ]] || return 0
  [[ -f "$local_ledger" ]] || return 0

  local upstream_version local_version
  upstream_version=$(jq -r '.schema_version // 0' "$upstream_ledger" 2>/dev/null) || {
    warn "Unable to parse schema_version from upstream ledger ($upstream_ledger)"
    return 0
  }
  local_version=$(jq -r '.schema_version // 0' "$local_ledger" 2>/dev/null) || {
    warn "Unable to parse schema_version from local ledger ($local_ledger)"
    return 0
  }

  # Validate both versions are non-negative integers
  if ! [[ "$upstream_version" =~ ^[0-9]+$ ]] || ! [[ "$local_version" =~ ^[0-9]+$ ]]; then
    warn "Ledger schema_version is not an integer (upstream=$upstream_version, local=$local_version) — skipping check"
    return 0
  fi

  if [[ "$upstream_version" -gt "$local_version" ]]; then
    warn "Ledger schema migration available (v${local_version} → v${upstream_version})."
    warn "Your ledger data is preserved (merge=ours) but the schema format may need updating."
    warn "Run: /ledger migrate"
  fi
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

  # === Ledger Schema Migration Check ===
  check_ledger_schema

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

# === Downstream Learning Import (FR-4) ===
# After update, check for new upstream learnings and import to local memory
import_upstream_learnings() {
  local upstream_dir=".claude/data/upstream-learnings"

  # Skip if no upstream learnings directory exists
  if [[ ! -d "$upstream_dir" ]]; then
    return 0
  fi

  # Find .yaml files
  local yaml_files
  yaml_files=$(find "$upstream_dir" -maxdepth 1 -name '*.yaml' -o -name '*.yml' 2>/dev/null)

  if [[ -z "$yaml_files" ]]; then
    return 0
  fi

  step "Checking for upstream learnings..."

  # Source path-lib for append_jsonl
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local path_lib="${script_dir}/path-lib.sh"
  if [[ -f "$path_lib" ]]; then
    source "$path_lib" 2>/dev/null || true
  fi

  # Resolve memory directory
  local memory_dir
  if type get_state_memory_dir &>/dev/null; then
    memory_dir=$(get_state_memory_dir 2>/dev/null) || memory_dir="grimoires/loa/memory"
  else
    memory_dir="grimoires/loa/memory"
  fi
  mkdir -p "$memory_dir"
  local obs_file="$memory_dir/observations.jsonl"

  local import_count=0
  local skip_count=0

  while IFS= read -r yaml_file; do
    [[ -z "$yaml_file" ]] && continue

    # Convert YAML to JSON for validation (requires yq)
    if ! command -v yq &>/dev/null; then
      warn "yq not available — cannot validate upstream learnings"
      return 0
    fi

    local learning_json
    learning_json=$(yq -o json '.' "$yaml_file" 2>/dev/null) || {
      warn "Failed to parse: $(basename "$yaml_file")"
      skip_count=$((skip_count + 1))
      continue
    }

    # Validate required fields
    local schema_ver learning_id category title
    schema_ver=$(echo "$learning_json" | jq -r '.schema_version // 0')
    learning_id=$(echo "$learning_json" | jq -r '.learning_id // ""')
    category=$(echo "$learning_json" | jq -r '.category // ""')
    title=$(echo "$learning_json" | jq -r '.title // ""')

    if [[ "$schema_ver" != "1" ]]; then
      warn "Unsupported schema version ($schema_ver): $(basename "$yaml_file")"
      skip_count=$((skip_count + 1))
      continue
    fi

    # Validate learning_id format
    if [[ ! "$learning_id" =~ ^LX-[0-9]{8}-[a-f0-9]{8,12}$ ]]; then
      warn "Invalid learning_id format: $(basename "$yaml_file")"
      skip_count=$((skip_count + 1))
      continue
    fi

    # Validate category
    case "$category" in
      pattern|anti-pattern|decision|troubleshooting|architecture|security) ;;
      *)
        warn "Invalid category ($category): $(basename "$yaml_file")"
        skip_count=$((skip_count + 1))
        continue
        ;;
    esac

    # Validate privacy fields (use explicit == false check; jq's // treats false as falsy)
    if ! echo "$learning_json" | jq -e '.privacy.contains_file_paths == false and .privacy.contains_secrets == false and .privacy.contains_pii == false' >/dev/null 2>&1; then
      warn "Privacy check failed: $(basename "$yaml_file")"
      skip_count=$((skip_count + 1))
      continue
    fi

    # Check for duplicates via learning_id
    if [[ -f "$obs_file" ]] && grep -qF "$learning_id" "$obs_file" 2>/dev/null; then
      skip_count=$((skip_count + 1))
      continue
    fi

    # Build observation entry
    local trigger solution content_text
    trigger=$(echo "$learning_json" | jq -r '.content.trigger // ""')
    solution=$(echo "$learning_json" | jq -r '.content.solution // ""')
    content_text="[upstream:$learning_id] $title — $trigger → $solution"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local obs_entry
    obs_entry=$(jq -cn \
      --arg id "$learning_id" \
      --arg ts "$timestamp" \
      --arg cat "$category" \
      --arg content "$content_text" \
      --argjson confidence 0.8 \
      --arg source "upstream-import" \
      --arg hash "$(printf '%s' "$content_text" | sha256sum | cut -d' ' -f1)" \
      '{id: $id, timestamp: $ts, category: $cat, content: $content, confidence: $confidence, source: $source, content_hash: $hash}')

    # Import via append_jsonl if available, else direct append
    if type append_jsonl &>/dev/null; then
      append_jsonl "$obs_file" "$obs_entry" || {
        warn "Failed to import: $(basename "$yaml_file")"
        skip_count=$((skip_count + 1))
        continue
      }
    else
      printf '%s\n' "$obs_entry" >> "$obs_file"
    fi

    import_count=$((import_count + 1))
  done <<< "$yaml_files"

  if [[ $import_count -gt 0 ]]; then
    log "Imported $import_count upstream learnings ($skip_count skipped)"
  elif [[ $skip_count -gt 0 ]]; then
    log "No new upstream learnings ($skip_count already imported or invalid)"
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

  # === Downstream Learning Import ===
  import_upstream_learnings

  echo ""
  log "Update complete."
  echo ""
}

main "$@"
