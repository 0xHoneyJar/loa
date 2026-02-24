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
#   MANIFEST_SKILL_SYMLINKS, MANIFEST_CMD_SYMLINKS

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
}

# Helper: Get flat list of all symlink entries from manifest
# Returns all entries combined for iteration
get_all_manifest_entries() {
  get_symlink_manifest "$@"
  ALL_MANIFEST_ENTRIES=("${MANIFEST_DIR_SYMLINKS[@]}" "${MANIFEST_FILE_SYMLINKS[@]}" "${MANIFEST_SKILL_SYMLINKS[@]}" "${MANIFEST_CMD_SYMLINKS[@]}")
}
