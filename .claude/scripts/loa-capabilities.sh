#!/usr/bin/env bash
# loa-capabilities.sh - Machine-readable contract surface for loa's
# agent-facing scripts (R-006, bd-m1o6, agent-ergonomics pass 1).
#
# One call answers: which scripts exist for agents, which speak JSON, which
# have --help, what the exit-code and env conventions are — without reading
# 373 scripts' source. The table is curated; a bats drift gate
# (tests/unit/agent-ergonomics-capabilities.bats) verifies every listed
# script exists and every help:"true" claim still holds.
#
# Usage:
#   loa-capabilities.sh            Human-readable table
#   loa-capabilities.sh --json     Full JSON contract (stdout, single doc)
#   loa-capabilities.sh --help     This help
#
# Exit codes:
#   0 - Success
#   2 - Usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)
VERSION_FILE="${PROJECT_ROOT}/.loa-version.json"

usage() {
  # Print the comment header verbatim, stopping at the first code line —
  # robust to header edits (fresh-eyes r4: a fixed sed range bled
  # 'set -euo pipefail' into --help).
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } /^$/ { print; next } { exit }' "${BASH_SOURCE[0]}"
}

framework_version() {
  jq -r '.framework_version // "unknown"' "$VERSION_FILE" 2>/dev/null || echo "unknown"
}

# The contract. json: "flag" (accepts --json) | "default" (stdout IS JSON) |
# "none". help: "true" when --help exits 0 (drift-gated). All paths are
# repo-root-relative.
capabilities_json() {
  jq -n --arg v "$(framework_version)" '
{
  schema_version: "1",
  framework_version: $v,
  description: "Contract surface for loa agent-facing scripts. stdout is data, stderr is diagnostics. NO_COLOR and non-TTY stdout suppress styling on compliant scripts.",
  conventions: {
    exit_codes: {
      "0": "success",
      "1": "error, check-failed, or gate signal (loa-doctor/beads-health exit nonzero on DEGRADED by design — consume their JSON, not their exit code)",
      "2": "usage error (unknown option / missing required value)"
    },
    env: {
      NO_COLOR: "suppress ANSI styling (https://no-color.org/)",
      LOA_GRIMOIRE_DIR: "override grimoire (state) dir",
      LOA_BEADS_DIR: "override beads dir",
      LOA_UPSTREAM: "override upstream repo URL for version checks"
    },
    composition: "capture output first, validate JSON content, THEN branch — do not gate on exit codes for health surfaces"
  },
  scripts: [
    {path: ".claude/scripts/loa-status.sh",                purpose: "workflow status + framework version; --triage composes status+health+next in one call", json: "flag", help: "true", flags: ["--json","--triage","--version","--economy"]},
    {path: ".claude/scripts/loa-doctor.sh",                purpose: "system health checks (deps, config, beads, hooks)", json: "flag", help: "true", flags: ["--json","--quick","--verbose","--category"], notes: "exits nonzero when issues found — gate semantics"},
    {path: ".claude/scripts/loa-capabilities.sh",          purpose: "this contract surface", json: "flag", help: "true", flags: ["--json"]},
    {path: ".claude/scripts/workflow-state.sh",            purpose: "workflow state detection (state/sprints/progress)", json: "flag", help: "true", flags: ["--json"]},
    {path: ".claude/scripts/golden-path.sh",               purpose: "sourced function library backing /loa /plan /build /review /ship (NOT executable — teaches when executed)", json: "none", help: "false", flags: [], notes: "source it; then golden_* functions"},
    {path: ".claude/scripts/beads/beads-health.sh",        purpose: "beads (br) task-tracking health", json: "flag", help: "true", flags: ["--json"], notes: "exits nonzero on DEGRADED — gate semantics"},
    {path: ".claude/scripts/semver-bump.sh",               purpose: "compute next semver from conventional commits since last tag", json: "default", help: "true", flags: ["--from-tag","--from-changelog","--downstream"]},
    {path: ".claude/scripts/classify-merge-pr.sh",         purpose: "classify a merged PR (cycle|bugfix|other) from merge subject", json: "none", help: "true", flags: ["--merge-sha","--merge-msg","--pr-number"], notes: "key=value lines on stdout"},
    {path: ".claude/scripts/release-notes-gen.sh",         purpose: "generate release notes for a version/PR", json: "none", help: "true", flags: ["--version","--pr","--type"]},
    {path: ".claude/scripts/post-merge-orchestrator.sh",   purpose: "post-merge pipeline (classify→semver→changelog→tag→release)", json: "default", help: "true", flags: ["--pr","--type","--sha","--dry-run"]},
    {path: ".claude/scripts/grimoire-index.sh",            purpose: "regenerate the grimoire INDEX (KF/vision/lore catalog)", json: "flag", help: "true", flags: []},
    {path: ".claude/scripts/lib/kf-write-lib.sh",          purpose: "append-only known-failures writer", json: "none", help: "true", flags: [], subcommands: ["new","attempt","recur","notes-header"]},
    {path: ".claude/scripts/memory-query.sh",              purpose: "query persistent memory observations", json: "flag", help: "true", flags: ["--json"]},
    {path: ".claude/scripts/repo-map-gen.sh",              purpose: "regenerate REPO-MAP.md ranked symbol map", json: "flag", help: "true", flags: []},
    {path: ".claude/scripts/memory-admin.sh",              purpose: "memory database admin (init/add)", json: "none", help: "true", flags: [], subcommands: ["init","add"]},
    {path: ".claude/scripts/qmd-sync.sh",                  purpose: "QMD document index sync + query", json: "none", help: "true", flags: [], subcommands: ["sync","query","status"]},
    {path: ".claude/scripts/verdict-derive.sh",            purpose: "derive/validate LOA-VERDICT trailer on review/audit feedback", json: "flag", help: "true", flags: ["--file","--gate","--json","--require-trailer"]},
    {path: ".claude/scripts/validate-skill-capabilities.sh", purpose: "SKILL.md frontmatter invariant lint (MUST gate)", json: "flag", help: "true", flags: ["--json","--strict","--skill"]},
    {path: ".claude/scripts/butterfreezone-validate.sh",   purpose: "BUTTERFREEZONE.md structure/provenance validation", json: "flag", help: "true", flags: ["--json"]},
    {path: ".claude/scripts/construct-resolve.sh",         purpose: "construct name resolution + composition checks", json: "flag", help: "true", flags: ["--json"], subcommands: ["resolve","compose"]},
    {path: ".claude/scripts/session-limit-capture.sh",     purpose: "arm session-cap resume reminder from an error text", json: "none", help: "false", flags: ["--raw"], notes: "help support queued for pass 2"}
  ]
}'
}

main() {
  local json_mode=false
  for arg in "$@"; do
    case "$arg" in
      --json) json_mode=true ;;
      --help|-h|help) usage; exit 0 ;;
      *)
        echo "Unknown option: $arg" >&2
        echo "Usage: loa-capabilities.sh [--json] [--help]" >&2
        exit 2
        ;;
    esac
  done

  if [[ "$json_mode" == "true" ]]; then
    capabilities_json
  else
    echo "loa capabilities (framework $(framework_version)) — full contract: loa-capabilities.sh --json"
    echo ""
    capabilities_json | jq -r '.scripts[] | [.path, .json, (.help // "false"), .purpose] | @tsv' \
      | awk -F'\t' '{printf "  %-52s json:%-8s help:%-6s %s\n", $1, $2, $3, $4}'
    echo ""
    echo "conventions: exit 0=ok, 1=error/gate, 2=usage; NO_COLOR honored; stdout=data stderr=diagnostics"
  fi
}

main "$@"
