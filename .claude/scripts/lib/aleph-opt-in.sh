#!/usr/bin/env bash
# =============================================================================
# lib/aleph-opt-in.sh — the single opt-in switch for Aleph (bug 20260922-13a3d1)
#
# Aleph (`.claude/aleph/**`, `.claude/skills/loa-aleph`, `.claude/commands/
# loa-aleph.md`, `.loa-aleph.lock.json`, `tools/aleph-release-ingest.py`) is a
# third-party, vendored component. Loa never verifies, installs, tests or syncs
# it unless the operator opts in:
#
#   LOA_ALEPH_ENABLED=1                      (environment; tests and CI matrices)
#   .loa.config.yaml:  aleph:
#                        enabled: true       (the documented switch; default false)
#
# Everything else — a missing config, any value other than the bare boolean
# `true` directly under `aleph:` — reads as DISABLED. The reader is POSIX awk
# (no yq), so no host or runner parser inventory can decide the switch. Callers: mount-submodule.sh
# (aleph_refresh_is_applicable), update-loa.sh (through it), check-loa.sh
# (check_aleph_integrity), the three tests/unit/aleph-*.bats suites, and the
# two Aleph workflows run the same awk.
#
# Usage:  source .claude/scripts/lib/aleph-opt-in.sh
#         aleph_opt_in_enabled [repo_root]      # 0 = enabled, 1 = disabled
# =============================================================================

aleph_opt_in_enabled() {
  local repo_root="${1:-.}"
  case "${LOA_ALEPH_ENABLED:-}" in
    1|true|TRUE|yes) return 0 ;;
  esac
  local cfg="${repo_root}/.loa.config.yaml"
  [[ -f "$cfg" ]] || return 1
  # POSIX awk, no yq: the switch is the bare boolean `true` directly under the
  # top-level `aleph:` key. Anything else (other keys, quoted strings, a missing
  # block) reads as disabled. The two Aleph workflows run the same awk, so no
  # host or runner parser inventory can decide the gate.
  [[ "$(awk '
    /^[A-Za-z_]/ { in_aleph = ($0 ~ /^aleph:[[:space:]]*(#.*)?$/) }
    in_aleph && /^[[:space:]]+enabled:[[:space:]]*true([[:space:]]*(#.*)?)?$/ { print "true"; exit }
  ' "$cfg" 2>/dev/null)" == "true" ]]
}
