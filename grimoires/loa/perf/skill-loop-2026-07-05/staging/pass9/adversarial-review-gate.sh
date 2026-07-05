#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Write Adversarial Review Gate
# =============================================================================
# Blocks Write tool calls targeting */COMPLETED when flatline_protocol is
# enabled in .loa.config.yaml but the corresponding adversarial-*.json
# artefact is missing — or present but structurally invalid — in the
# sprint directory.
#
# Catches the class of bug where reviewing-code / auditing-security skills
# execute inline and silently skip Phase 2.5 (cross-model adversarial review).
#
# Structural validation (raises bypass cost beyond `touch artefact.json`):
#   Artefact must parse as JSON and contain .metadata.type and .metadata.model.
#   Both fields are written by .claude/scripts/adversarial-review.sh on every
#   code path (success, api_failure, malformed_response, clean, and
#   skipped_by_config), so any legitimate review run satisfies the gate.
#   A bare `touch artefact.json` or empty-object write does not.
#
# Fail-open on parse error, missing yq, or malformed config (infrastructure
# faults must not block legitimate work). Fail-CLOSED when .loa.config.yaml
# cannot be resolved at all — an unresolvable config means we can't evaluate
# enforcement and silent-skip is exactly what this gate exists to block.
# Opt-out via LOA_ADVERSARIAL_REVIEW_ENFORCE=false.
# Test override: LOA_CONFIG_PATH_OVERRIDE.
#
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction. stdin is read
# with the read builtin (was a cat spawn); the unparseable-payload fallback
# probe uses a bash substring test; dirname spawns (1 + up to 6 in the
# config walk) are parameter expansions with the POSIX dirname edge cases
# preserved (see inline notes).
#
# perf pass-3 (2026-07-05, skill-loop): yq single-pass consolidation — the
# two per-key `yq .flatline_protocol.<gate>.enabled // false` spawns collapse
# into ONE yq that derives both gate decisions as guaranteed-single-line
# true/false tokens. Isomorphism notes:
#   - Decision parity: the old comparison was [[ "$(yq '.key // false')"
#     == "true" ]] where $() strips trailing newlines from the scalar
#     rendering. The token is (tostring | sub("\n+$"; "") | . == "true") —
#     tostring of a string/bool/int is exactly the rendering the old $()
#     captured for every single-token value, and every multi-line or
#     quoted-on-output rendering compares unequal to "true" in both
#     versions. Decisions are therefore identical for ALL yaml values.
#   - Message parity: the BLOCK diagnostic prints the raw values. On that
#     path (missing artefacts — the rare failure state, roughly once per
#     sprint at most) the two original yq reads are re-run so the message
#     bytes stay identical even for exotic non-boolean config values. The
#     steady-state COMPLETED write pays 1 yq instead of 2.
#   - yq failure (malformed yaml): old set both vars to "false" via `||`;
#     the single yq emits no tokens and both default to "false" — identical.
#
# perf pass-9 (2026-07-05, skill-loop): raw-payload literal fast gate — the
# steady-state Write/Edit (nothing to do with COMPLETED markers) no longer
# pays the jq spawn. Soundness argument (all-inputs isomorphism):
#   The ONLY non-silent behaviors of this hook require either
#     (a) a successfully-decoded .tool_input.file_path/.notebook_path whose
#         value ends in "/COMPLETED"  (the `== */COMPLETED` guard), or
#     (b) an UNPARSEABLE payload whose raw bytes contain "/COMPLETED"
#         (the fail-closed probe).
#   A decoded JSON string can contain the letters C,O,M,P,L,E,T,E,D only as
#   literal payload bytes or via \uXXXX escapes — every other JSON escape
#   (\" \\ \/ \b \f \n \r \t) decodes to a non-letter, and adjacent decoded
#   characters come from adjacent raw representations, so a fully-literal
#   "COMPLETED" is contiguous in the raw bytes. Therefore when the raw
#   payload contains neither the substring "COMPLETED" nor the two bytes
#   "\u" (JSON's \u is lowercase-only), (a) and (b) are both impossible and
#   every code path below exits 0 with no output and no side effects —
#   parseable or not. The fast gate replicates that outcome exactly; any
#   payload containing either token falls through to the UNCHANGED old code
#   with the identical $input bytes.
# =============================================================================

# No `set -euo pipefail` — this hook must never fail closed. A jq or yq
# failure, a missing config file, a malformed path all must allow the write.

# Trust model note (audit, bug-1002 wave): the artifact check accepts any
# JSON with .metadata.type/.model — FORGEABLE by an actor who can already
# write the sprint directory. Accepted class: this is a mistake-fence
# against skipping Phase 2.5, not a security boundary; the writer and the
# gated agent share a trust domain (same accepted-bypass posture as
# block-destructive-bash.sh — see hooks-reference.md).

# Opt-out first (cheapest check)
if [[ "${LOA_ADVERSARIAL_REVIEW_ENFORCE:-true}" == "false" ]]; then
  exit 0
fi

# Audit iter (bug-1002): the old 64 KiB head-cap truncated large Write
# payloads MID-JSON, jq failed, and the `|| exit 0` fail-open meant any
# */COMPLETED write over 64 KiB bypassed the gate. Read the full payload
# (bounded by the tool-call size) and parse once; on a parse failure,
# fail CLOSED only when the raw payload visibly targets a COMPLETED
# marker — everything else stays fail-open (this is a mistake-fence).
# perf pass-2: read builtin instead of $(cat) — same bytes modulo the
# trailing newline (irrelevant to jq and to the substring probe). A payload
# containing a NUL byte would truncate at the NUL instead of dropping NULs;
# JSON cannot carry raw NUL, and either shape fails the jq parse into the
# same fallback path.
input=""
IFS= read -rd '' input || true

# perf pass-9 fast gate (see header note): no "COMPLETED" and no "\u" in the
# raw payload ⇒ every path below is a silent `exit 0` ⇒ skip the jq spawn.
if [[ "$input" != *COMPLETED* && "$input" != *'\u'* ]]; then
  exit 0
fi

parsed=$(printf '%s' "$input" | jq -r '[.tool_name // "", .tool_input.file_path // .tool_input.notebook_path // ""] | @tsv' 2>/dev/null) || parsed=""
if [[ -z "$parsed" ]]; then
  if [[ "$input" == *"/COMPLETED"* ]]; then
    echo "[adversarial-review-gate] BLOCKED: unparseable hook payload mentioning a COMPLETED marker — refusing fail-open" >&2
    exit 2
  fi
  exit 0
fi
tool_name="${parsed%%$'\t'*}"
file_path="${parsed#*$'\t'}"

# Gate Write AND Edit calls to */COMPLETED markers (audit: an Edit to an
# existing marker bypassed the Write-only check).
case "$tool_name" in Write|Edit|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
[[ "$file_path" == */COMPLETED ]] || exit 0

# perf pass-2: dirname in parameter expansion. file_path is guaranteed to
# contain '/' (the */COMPLETED guard above), so: strip the last component,
# then trailing slashes (dirname "x//COMPLETED" → "x"), then map "" → "/"
# (dirname "/COMPLETED" → "/"). Matches GNU/POSIX dirname on every reachable
# input.
sprint_dir="${file_path%/*}"
while [[ "$sprint_dir" == */ ]]; do sprint_dir="${sprint_dir%/}"; done
[[ -z "$sprint_dir" ]] && sprint_dir="/"

# Resolve config path. PreToolUse hooks don't pin CWD, so searching
# ./.loa.config.yaml is unreliable — it silently misses from subagents,
# worktrees, or any hook invocation that isn't rooted at the repo.
# Walk upward from the sprint directory (which we have from the payload)
# until .loa.config.yaml is found. If no config is found we fail CLOSED:
# an unresolvable config means we cannot determine whether enforcement is
# required, and silent-skip is exactly the mode this gate exists to block.
# LOA_CONFIG_PATH_OVERRIDE short-circuits the walk for tests.
resolve_config() {
  if [[ -n "${LOA_CONFIG_PATH_OVERRIDE:-}" ]]; then
    [[ -f "$LOA_CONFIG_PATH_OVERRIDE" ]] && echo "$LOA_CONFIG_PATH_OVERRIDE"
    return
  fi
  local dir
  dir=$(cd "$sprint_dir" 2>/dev/null && pwd) || return
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.loa.config.yaml" ]]; then
      echo "$dir/.loa.config.yaml"
      return
    fi
    # perf pass-2: was $(dirname "$dir"). $dir is canonical-absolute (from
    # cd/pwd), so ${dir%/*} equals dirname for every multi-component path;
    # at a first-level dir ("/x") it yields "" where dirname yields "/" —
    # both fail the loop guard identically, and the original never tested
    # "/" for the config either. Iteration set is unchanged.
    dir="${dir%/*}"
  done
}

config=$(resolve_config)
if [[ -z "$config" ]]; then
  {
    echo "BLOCKED: cannot locate .loa.config.yaml to determine Phase 2.5 requirements"
    echo "  Sprint dir: $sprint_dir"
    echo "  Walked upward from sprint dir, no .loa.config.yaml found."
    echo ""
    echo "  Fail-closed on COMPLETED writes when config is unresolvable —"
    echo "  silent-skip is exactly the failure mode this gate blocks."
    echo "  Set LOA_CONFIG_PATH_OVERRIDE or run from a repo with .loa.config.yaml."
    echo "  Emergency override: LOA_ADVERSARIAL_REVIEW_ENFORCE=false (not recommended)"
  } >&2
  exit 2
fi

# yq is a hard dependency for this gate. If it's absent the gate cannot read
# config — fail open per the no-fail-closed rule, but emit a warning so the
# silent bypass is at least observable (addresses CWE-284 silent degradation).
if ! command -v yq >/dev/null 2>&1; then
  echo "adversarial-review-gate: yq not found on PATH; gate bypassed (install Mike Farah's yq v4)" >&2
  exit 0
fi

# Read config — ONE yq derives both gate decisions (perf pass-3 header note).
# Tokens are guaranteed single-line "true"/"false"; on any yq error no
# tokens are emitted and both gates default to "false" (old || fallback).
mapfile -t _gate_tokens < <(
  yq -r '(.flatline_protocol.code_review.enabled // false | tostring | sub("\n+$"; "") | (. == "true")),
         (.flatline_protocol.security_audit.enabled // false | tostring | sub("\n+$"; "") | (. == "true"))' \
    "$config" 2>/dev/null
)
code_review_enabled="false"
audit_enabled="false"
[[ "${_gate_tokens[0]-}" == "true" ]] && code_review_enabled="true"
[[ "${_gate_tokens[1]-}" == "true" ]] && audit_enabled="true"

# Structural validation: the artefact must parse as JSON and carry the
# metadata fields that adversarial-review.sh writes on every code path.
# Presence-only would be satisfied by `touch`; this rejects that and any
# hand-crafted placeholder that doesn't know the schema.
_artefact_valid() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  jq -e '.metadata.type != null and .metadata.model != null' "$path" >/dev/null 2>&1
}

missing=()
if [[ "$code_review_enabled" == "true" ]]; then
  _artefact_valid "$sprint_dir/adversarial-review.json" || missing+=("adversarial-review.json")
fi
if [[ "$audit_enabled" == "true" ]]; then
  _artefact_valid "$sprint_dir/adversarial-audit.json" || missing+=("adversarial-audit.json")
fi

if (( ${#missing[@]} > 0 )); then
  # perf pass-3: re-read the raw config values for the diagnostic so the
  # message bytes match the pre-consolidation output even for exotic
  # (non-boolean) config values. This runs only on the rare BLOCK path.
  code_review_enabled=$(yq '.flatline_protocol.code_review.enabled // false' "$config" 2>/dev/null) || code_review_enabled="false"
  audit_enabled=$(yq '.flatline_protocol.security_audit.enabled // false' "$config" 2>/dev/null) || audit_enabled="false"
  {
    echo "BLOCKED: adversarial review required before COMPLETED marker"
    echo "  Sprint dir: $sprint_dir"
    echo "  Config requests: code_review=$code_review_enabled, security_audit=$audit_enabled"
    echo "  Missing or invalid: ${missing[*]}"
    echo ""
    echo "  Artefact must contain .metadata.type and .metadata.model."
    echo "  To proceed, run Phase 2.5 cross-model review:"
    echo "    .claude/scripts/adversarial-review.sh \\"
    echo "      --type review --sprint-id \$(basename $sprint_dir) \\"
    echo "      --diff-file <path-to-diff>"
    echo ""
    echo "  Emergency override: LOA_ADVERSARIAL_REVIEW_ENFORCE=false (not recommended)"
  } >&2
  exit 2
fi

exit 0
