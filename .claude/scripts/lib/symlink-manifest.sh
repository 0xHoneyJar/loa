#!/usr/bin/env bash
# === Authoritative Symlink Manifest (DRY — Bridgebuilder Tension 1) ===
# Single source of truth for the complete symlink topology.
# All code paths that create, verify, migrate, or eject symlinks MUST read from this function.
# To add a new symlink target, change ONLY this file — no other code paths.
#
# FAANG parallel: Google's Blaze/Bazel uses single BUILD files as authoritative manifests;
# Kubernetes uses CRDs. Same principle — one declaration, multiple consumers.
#
# Consumers: mount-submodule.sh (create, verify), mount-loa.sh (migrate), loa-eject.sh (eject)
#
# Output format: Each entry is "link_path:target_path" where target is relative from link parent.
# Populates global arrays: MANIFEST_DIR_SYMLINKS, MANIFEST_FILE_SYMLINKS,
#   MANIFEST_SKILL_SYMLINKS, MANIFEST_CMD_SYMLINKS, MANIFEST_CONSTRUCT_SYMLINKS
#
# Construct Extension (Sprint 50, vision-008):
#   Construct packs can declare their own symlink requirements via .loa-construct-manifest.json
#   files in their pack directory. These are merged into MANIFEST_CONSTRUCT_SYMLINKS after
#   validation (boundary enforcement, conflict detection, dependency check).
#   Like Kubernetes CRDs extending the API or npm peerDependencies declaring requirements.

get_symlink_manifest() {
  local submodule="${1:-.loa}"
  local repo_root="${2:-$(pwd)}"

  # Phase 1: Directory symlinks (top-level .claude/ dirs that map 1:1 to submodule)
  MANIFEST_DIR_SYMLINKS=(
    ".claude/scripts:../${submodule}/.claude/scripts"
    ".claude/protocols:../${submodule}/.claude/protocols"
    ".claude/hooks:../${submodule}/.claude/hooks"
    ".claude/data:../${submodule}/.claude/data"
    ".claude/schemas:../${submodule}/.claude/schemas"
  )

  # Phase 2: File and nested symlinks (deeper paths with 2-level relative targets)
  MANIFEST_FILE_SYMLINKS=(
    ".claude/loa/CLAUDE.loa.md:../../${submodule}/.claude/loa/CLAUDE.loa.md"
    ".claude/loa/reference:../../${submodule}/.claude/loa/reference"
    ".claude/loa/learnings:../../${submodule}/.claude/loa/learnings"
    ".claude/loa/feedback-ontology.yaml:../../${submodule}/.claude/loa/feedback-ontology.yaml"
    ".claude/settings.json:../${submodule}/.claude/settings.json"
    ".claude/checksums.json:../${submodule}/.claude/checksums.json"
  )

  # Phase 3: Per-skill symlinks (dynamic — discovered from submodule content)
  MANIFEST_SKILL_SYMLINKS=()
  if [[ -d "${repo_root}/${submodule}/.claude/skills" ]]; then
    for skill_dir in "${repo_root}/${submodule}"/.claude/skills/*/; do
      if [[ -d "$skill_dir" ]]; then
        local skill_name
        skill_name=$(basename "$skill_dir")
        MANIFEST_SKILL_SYMLINKS+=(".claude/skills/${skill_name}:../../${submodule}/.claude/skills/${skill_name}")
      fi
    done
  fi

  # Phase 4: Per-command symlinks (dynamic — discovered from submodule content)
  MANIFEST_CMD_SYMLINKS=()
  if [[ -d "${repo_root}/${submodule}/.claude/commands" ]]; then
    for cmd_file in "${repo_root}/${submodule}"/.claude/commands/*.md; do
      if [[ -f "$cmd_file" ]]; then
        local cmd_name
        cmd_name=$(basename "$cmd_file")
        MANIFEST_CMD_SYMLINKS+=(".claude/commands/${cmd_name}:../../${submodule}/.claude/commands/${cmd_name}")
      fi
    done
  fi

  # Phase 5: Construct pack symlinks (vision-008 — ecosystem extension point)
  # Discover .loa-construct-manifest.json files in construct pack directories
  # and merge validated entries into MANIFEST_CONSTRUCT_SYMLINKS.
  MANIFEST_CONSTRUCT_SYMLINKS=()
  _discover_construct_manifests "$submodule" "$repo_root"
}

# Helper: Get flat list of all symlink entries from manifest
# Returns all entries combined for iteration
get_all_manifest_entries() {
  get_symlink_manifest "$@"
  ALL_MANIFEST_ENTRIES=("${MANIFEST_DIR_SYMLINKS[@]}" "${MANIFEST_FILE_SYMLINKS[@]}" "${MANIFEST_SKILL_SYMLINKS[@]}" "${MANIFEST_CMD_SYMLINKS[@]}" "${MANIFEST_CONSTRUCT_SYMLINKS[@]}")
}

# =============================================================================
# Construct Manifest Discovery and Validation (Sprint 50 — vision-008)
# =============================================================================
# Discovers .loa-construct-manifest.json files in construct pack directories,
# validates entries (boundary enforcement, conflict detection, dependency check),
# and merges valid entries into MANIFEST_CONSTRUCT_SYMLINKS.
#
# Like npm peerDependencies: constructs declare what they need, but the
# framework validates and installs. Like Kubernetes CRDs: constructs extend
# the topology without modifying the core manifest.

_discover_construct_manifests() {
  local submodule="${1:-.loa}"
  local repo_root="${2:-$(pwd)}"

  # Build core link set for conflict detection (O(n) lookup via associative array)
  local -A _core_links=()
  local entry
  for entry in "${MANIFEST_DIR_SYMLINKS[@]}" "${MANIFEST_FILE_SYMLINKS[@]}" "${MANIFEST_SKILL_SYMLINKS[@]}" "${MANIFEST_CMD_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    _core_links["$link_path"]=1
  done

  # Search paths for construct manifests:
  # 1. Inside submodule: ${submodule}/.claude/constructs/*/
  # 2. User-installed: .claude/constructs/*/
  local search_dirs=()
  if [[ -d "${repo_root}/${submodule}/.claude/constructs" ]]; then
    search_dirs+=("${repo_root}/${submodule}/.claude/constructs")
  fi
  if [[ -d "${repo_root}/.claude/constructs" ]]; then
    search_dirs+=("${repo_root}/.claude/constructs")
  fi

  for search_dir in "${search_dirs[@]}"; do
    for pack_dir in "$search_dir"/*/; do
      [[ -d "$pack_dir" ]] || continue
      local manifest_file="$pack_dir/.loa-construct-manifest.json"
      [[ -f "$manifest_file" ]] || continue

      local pack_name
      pack_name=$(basename "$pack_dir")

      # Parse and validate the construct manifest
      _parse_construct_manifest "$manifest_file" "$pack_name" "$repo_root" "$submodule"
    done
  done
}

# Parse a single construct manifest and merge validated entries
_parse_construct_manifest() {
  local manifest_file="$1"
  local pack_name="$2"
  local repo_root="$3"
  local submodule="$4"

  # Require jq for JSON parsing (graceful skip if unavailable)
  if ! command -v jq &>/dev/null; then
    echo "[symlink-manifest] WARNING: jq not available, skipping construct manifest for $pack_name" >&2
    return 0
  fi

  # Validate JSON structure
  if ! jq empty "$manifest_file" 2>/dev/null; then
    echo "[symlink-manifest] WARNING: Invalid JSON in $manifest_file, skipping" >&2
    return 0
  fi

  # Parse directory symlinks — batched jq via process substitution (F-005)
  # Reduces from 1+2N jq forks to exactly 2 regardless of entry count.
  # Process substitution keeps while loop in current shell, preserving global array writes.
  while IFS=$'\t' read -r link target; do
    [[ -n "$link" ]] || continue
    _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
  done < <(jq -r '(.symlinks.directories // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null)

  # Parse file symlinks — same batched pattern
  while IFS=$'\t' read -r link target; do
    [[ -n "$link" ]] || continue
    _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
  done < <(jq -r '(.symlinks.files // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null)

  # Validate requires (dependency check)
  local req_count
  req_count=$(jq -r '.requires // [] | length' "$manifest_file" 2>/dev/null) || req_count=0
  for ((i=0; i<req_count; i++)); do
    local req
    req=$(jq -r ".requires[$i]" "$manifest_file" 2>/dev/null)
    if [[ -z "${_core_links[$req]:-}" ]] && [[ ! -e "$repo_root/$req" ]]; then
      echo "[symlink-manifest] WARNING: Construct '$pack_name' requires '$req' which is not in core manifest or filesystem" >&2
    fi
  done
}

# Validate a single construct symlink entry and add if valid
_validate_and_add_construct_entry() {
  local link="$1"
  local target="$2"
  local pack_name="$3"
  local repo_root="$4"

  # Validation 1: Boundary enforcement — link must be under .claude/
  if [[ "$link" != .claude/* ]]; then
    echo "[symlink-manifest] REJECTED: Construct '$pack_name' declares link '$link' outside .claude/ boundary" >&2
    return 0
  fi

  # Validation 2: Path sanitization — reject .. traversals in link path
  # Covers: leading ../, mid-path /../, and trailing /.. (F-001)
  if [[ "$link" == *../* ]] || [[ "$link" == */../* ]] || [[ "$link" == *.. ]]; then
    echo "[symlink-manifest] REJECTED: Construct '$pack_name' link '$link' contains path traversal" >&2
    return 0
  fi

  # Validation 3: Reject absolute paths
  if [[ "$link" == /* ]] || [[ "$target" == /* ]]; then
    echo "[symlink-manifest] REJECTED: Construct '$pack_name' uses absolute path (link='$link', target='$target')" >&2
    return 0
  fi

  # Validation 4: Conflict detection — cannot override core manifest entries
  if [[ -n "${_core_links[$link]:-}" ]]; then
    echo "[symlink-manifest] WARNING: Construct '$pack_name' link '$link' conflicts with core manifest entry, skipping" >&2
    return 0
  fi

  # All validations passed — add to construct symlinks
  MANIFEST_CONSTRUCT_SYMLINKS+=("${link}:${target}")
}
