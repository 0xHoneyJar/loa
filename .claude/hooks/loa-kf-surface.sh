#!/usr/bin/env bash
# =============================================================================
# loa-kf-surface.sh — SessionStart hook (cycle-115 sprint-1, D1).
#
# Surfaces a compact symptom -> KF table from grimoires/loa/known-failures.md
# at session start so an agent sees the operational-failure log before
# triaging. DEFAULT-OFF: gated on `known_failures.surface_at_session_start`
# (default false) in .loa.config.yaml.
#
# STREAM ROUTING: Claude Code's SessionStart contract injects a hook's STDOUT
#   (on exit 0) into the session as context; STDERR is transcript-only and never
#   reaches the agent. This surface is only useful IN CONTEXT, so every ENABLED
#   path — the healthy table AND the enabled-but-degraded WARNINGs — writes to
#   STDOUT (an agent under the index-first intake contract must SEE that the KF
#   surface is degraded so it falls back to regenerating the index). Sibling
#   surfacing hooks (loa-l6-surface-handoffs.sh, loa-l7-surface-soul.sh) route
#   the same way. The DISABLED path emits nothing at all.
#
# CONTRACT (loud-but-nonblocking — this is OBSERVABILITY, never a gate):
#   - It MUST exit 0 in ALL paths. It MUST NOT block a session.
#   - When the flag is DISABLED (or config/yq absent): emit NOTHING, exit 0.
#   - When ENABLED but the surface is degraded — known-failures.md unreadable,
#     or zero KF entries parsed — emit a visible "[KF-SURFACE] WARNING ..."
#     to STDOUT and exit 0 (loud + in-context, so the agent notices a broken
#     knowledge surface; never silent on an enabled-but-broken path).
#   - When ENABLED and healthy: emit a compact symptom -> KF table to STDOUT,
#     exit 0.
#
# TRUST BOUNDARY: known-failures.md bodies are UNTRUSTED at surfacing. Every
#   field is control-byte-sanitized + length-capped before reaching session
#   context; body prose is NEVER interpreted as instructions (CLAUDE.md
#   agent-network universal invariant).
# =============================================================================
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"

# --- test-mode seam (mirrors L4/L6/L7 cycle-098 gate): the config + path
#     overrides are honored ONLY under LOA_KF_SURFACE_TEST_MODE=1 with a bats
#     marker present. In production neither override is consulted. -----------
_kf_test_mode_active() {
  [[ "${LOA_KF_SURFACE_TEST_MODE:-0}" == "1" ]] || return 1
  [[ -n "${BATS_TEST_FILENAME:-}" ]] && return 0
  [[ -n "${BATS_VERSION:-}" ]] && return 0
  return 1
}

# Sanitisation reference spec (the awk san() below is its byte-for-byte twin; it used to be
# a bash pipeline run per field, now dead and removed):
#   printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' \
#     | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-100

# --- resolve enabled flag -----------------------------------------------------
enabled="false"
if _kf_test_mode_active && [[ -n "${LOA_KF_SURFACE_TEST_CONFIG-}" ]]; then
  # In test mode the override stands in for the parsed config value.
  enabled="${LOA_KF_SURFACE_TEST_CONFIG}"
else
  config_path="${REPO_ROOT}/.loa.config.yaml"
  # No yq or no config -> the feature is opt-in and unconfigurable here: silent.
  if command -v yq >/dev/null 2>&1 && [[ -f "$config_path" ]]; then
    # Explicit key, else the loa.profile default (cycle-129 D-9.1).
    # shellcheck source=scripts/lib/profile-lib.sh
    source "${REPO_ROOT}/.claude/scripts/lib/profile-lib.sh" 2>/dev/null &&
      enabled="$(loa_knob known_failures.surface_at_session_start false 2>/dev/null || echo false)"
  fi
fi

# DISABLED (or unconfigurable) -> emit nothing, exit 0. This is the ONLY silent path.
[[ "$enabled" == "true" ]] || exit 0

# --- ENABLED: from here every exit is loud-or-table, always exit 0 -----------
KF_FILE="${REPO_ROOT}/grimoires/loa/known-failures.md"
if _kf_test_mode_active && [[ -n "${LOA_KNOWN_FAILURES_FILE:-}" ]]; then
  KF_FILE="${LOA_KNOWN_FAILURES_FILE}"
fi

if [[ ! -r "$KF_FILE" ]]; then
  echo "[KF-SURFACE] WARNING: known-failures.md is unreadable at ${KF_FILE} — the known-failures surface is enabled but degraded. Triage without it; check the file path."
  exit 0
fi

# Parse id + symptom from each ## KF-NNN: entry (source of truth), deduped by
# id. Mirrors grimoire-index.sh emit_kf field-parsing (the field shapes and the H2
# heading rule; tests/unit/kf-surface.bats pins the two copies line for line).
# The SAME awk pass sanitizes and formats the final "  - ID (rec N): symptom"
# rows (one process, not ~3 sanitiser pipelines per row). san() below is the
# byte-for-byte awk twin of the reference spec above; the symptom's leading/trailing tabs are
# trimmed first, emulating the former tab-IFS `read -r id num symptom` (last field
# keeps the remainder). Keep san() and the reference spec in lock-step.
# LC_ALL=C pins substr/length to BYTES, matching `cut -c` (GNU cut -c is
# byte-based in every locale), so old and new agree under UTF-8 and C alike.
rows="$(LC_ALL=C awk '
  # Byte cap: under LC_ALL=C substr() caps BYTES. GNU cut -c was already byte-based on Linux, so Linux
  # output is unchanged; BSD cut hosts formerly capped characters.
  function san(s) {
    gsub(/\000/, "", s)
    gsub(/[\001-\010\013\014\016-\037\177]/, "", s)
    gsub(/[\t\n\r]/, " ", s)
    gsub(/  +/, " ", s)
    sub(/^ /, "", s); sub(/ $/, "", s)
    return substr(s, 1, 100)
  }
  function fieldval(line, label,   reA, reB, reC, v) {
    # Three field-line variants, each with an optional "- " list marker:
    #   A) **Label**: value                 (colon outside the bold)
    #   B) **Label[ (suffix)]:** value       (colon inside the bold; suffix
    #      may contain spaces/parens/em-dash but no "*")
    #   C) **Label (suffix)**: value         (a space after the label, colon outside the bold),
    #      for Symptom and Recurrence count ONLY: a qualified Status ("Status (original)") is a
    #      historical annotation and never the entry status (sdd D-2.2). Keep in step with the twin.
    reA = "^(- )?\\*\\*" label "\\*\\*: ?"
    reB = "^(- )?\\*\\*" label "[^*]*:\\*\\* ?"
    reC = "^(- )?\\*\\*" label "( [^*]*)?\\*\\*: ?"
    if (line ~ reA) { v = line; sub(reA, "", v); return v }
    if (line ~ reB) { v = line; sub(reB, "", v); return v }
    if ((label == "Symptom" || label == "Recurrence count") && line ~ reC) { v = line; sub(reC, "", v); return v }
    return ""
  }
  # Every H2 heading closes the current entry; only a ## KF-NNN: heading opens one.
  /^## / { cur = "" }
  /^## KF-[0-9]+:/ {
    if (match($0, /KF-[0-9]+/)) { id = substr($0, RSTART, RLENGTH) } else { id = "" }
    if (id != "" && !(id in seen)) { order[++n] = id; seen[id] = 1 }
    cur = id; next
  }
  cur != "" {
    if (sy[cur] == "") { v = fieldval($0, "Symptom");          if (v != "") { sy[cur] = v; next } }
    if (rc[cur] == "") { v = fieldval($0, "Recurrence count"); if (v != "") { rc[cur] = v; next } }
  }
  END {
    for (i = 1; i <= n; i++) {
      id = order[i]; r = rc[id]; num = "?"; v = r
      gsub(/^([>=~ ]|\342\211\245)+/, "", v)
      if (match(v, /^[0-9]+/)) num = substr(v, RSTART, RLENGTH)
      sym = sy[id]; gsub(/\000/, "", sym); sub(/^\t+/, "", sym); sub(/\t+$/, "", sym)
      printf "  - %s (rec %s): %s\n", san(id), san(num), san(sym)
    }
  }
' "$KF_FILE" 2>/dev/null || true)"

if [[ -z "$rows" ]]; then
  echo "[KF-SURFACE] WARNING: known-failures.md at ${KF_FILE} parsed ZERO KF entries — the surface is enabled but empty/malformed. Verify the file has ## KF-NNN: entries."
  exit 0
fi

# --- healthy: emit a compact, sanitized symptom -> KF table to stdout --------
# ($rows already holds the sanitized "  - ID (rec N): symptom" lines, one per entry.)
# stdout so the SessionStart contract injects it as context (see STREAM ROUTING).
kf_count="$(printf '%s\n' "$rows" | grep -c . || true)"
{
  echo "[KF-SURFACE] ${kf_count} known-failure entries (symptom -> KF · recurrence). Read grimoires/loa/known-failures.md before triaging; recurrence >= 3 = structural."
  printf '%s\n' "$rows"
}

exit 0
