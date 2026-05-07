#!/usr/bin/env bash
# =============================================================================
# graduated-trust-lib.sh — L4 graduated-trust (cycle-098 Sprint 4)
#
# cycle-098 Sprint 4 — implementation of the L4 per-(scope, capability, actor)
# trust ledger per RFC #656, PRD FR-L4 (8 ACs), SDD §1.4.2 + §5.6.
#
# Composition (does NOT reinvent):
#   - 1A audit envelope:       audit_emit + audit_verify_chain
#   - 1B signing scheme:       audit_emit honors LOA_AUDIT_SIGNING_KEY_ID
#   - 1B protected-class:      is_protected_class("trust.force_grant")
#   - 1B operator-identity:    operator_identity_verify (when known-actor required)
#   - 1.5 trust-store check:   audit_emit auto-verifies trust-store
#
# Sprint slice that this file ships in:
#   - 4A (FOUNDATION): schemas, config getters, input validators,
#                      trust_query + ledger walker (FR-L4-1)
#   - 4B (TRANSITIONS): trust_grant, trust_record_override
#                       (FR-L4-2, FR-L4-3) — TODO Sprint 4B
#   - 4C (INTEGRITY):   trust_verify_chain, reconstruction, force-grant,
#                       auto-raise stub (FR-L4-4, FR-L4-5, FR-L4-7, FR-L4-8)
#                       — TODO Sprint 4C
#   - 4D (SEAL/CLI):    trust_disable, concurrent-write tests
#                       (FR-L4-6) — TODO Sprint 4D
#
# Verdict semantics (PRD §FR-L4 + SDD §5.6.3):
#   - First query returns default_tier (FR-L4-1).
#   - Only configured transitions allowed (FR-L4-2; arbitrary jumps return error).
#   - recordOverride auto-drops + starts cooldown (FR-L4-3).
#   - Force-grant in cooldown logged as exception with reason (FR-L4-8).
#
# Public functions (full set; some are 4B+ stubs at this stage):
#   trust_query <scope> <capability> <actor>
#       Returns TrustResponse JSON on stdout. Exit 0 on success; 2 on bad input;
#       1 on ledger / config error.
#
#   trust_grant     <scope> <capability> <actor> <new_tier> [--force] [--reason <text>] [--operator <slug>]
#                   — TODO 4B (regular) / 4C (--force exception path)
#
#   trust_record_override <scope> <capability> <actor> <decision_id> <reason>
#                   — TODO 4B
#
#   trust_verify_chain
#                   — TODO 4C
#
#   trust_disable [--reason <text>] [--operator <slug>]
#                   — TODO 4D
#
# Environment variables:
#   LOA_TRUST_LEDGER_FILE         override .run/trust-ledger.jsonl path
#   LOA_TRUST_CONFIG_FILE         override .loa.config.yaml path
#   LOA_TRUST_TEST_NOW            test-only override for "now" (ISO-8601)
#   LOA_TRUST_EMIT_QUERY_EVENTS   when "1", trust_query also emits trust.query
#                                 audit event (off by default; query traffic
#                                 high-frequency)
#   LOA_TRUST_REQUIRE_KNOWN_ACTOR when "1", actor MUST resolve via
#                                 operator-identity (OPERATORS.md). Off by
#                                 default for low-friction first install.
#   LOA_TRUST_DEFAULT_TIER        env override of graduated_trust.default_tier
#   LOA_TRUST_COOLDOWN_SECONDS    env override of graduated_trust.cooldown_seconds
#
# Exit codes:
#   0 = success
#   1 = ledger/config error (e.g., chain broken, ledger sealed [L4-DISABLED])
#   2 = invalid arguments
#   3 = configuration error (e.g., missing tier_definitions when L4 enabled)
# =============================================================================

set -euo pipefail

if [[ "${_LOA_L4_LIB_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_L4_LIB_SOURCED=1

_L4_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_L4_REPO_ROOT="$(cd "${_L4_DIR}/../../.." && pwd)"
_L4_AUDIT_ENVELOPE="${_L4_REPO_ROOT}/.claude/scripts/audit-envelope.sh"
_L4_PROTECTED_ROUTER="${_L4_REPO_ROOT}/.claude/scripts/lib/protected-class-router.sh"
_L4_OPERATOR_IDENTITY="${_L4_REPO_ROOT}/.claude/scripts/operator-identity.sh"
_L4_SCHEMA_DIR="${_L4_REPO_ROOT}/.claude/data/trajectory-schemas/trust-events"

# shellcheck source=../audit-envelope.sh
source "${_L4_AUDIT_ENVELOPE}"
# shellcheck source=protected-class-router.sh
source "${_L4_PROTECTED_ROUTER}"
# shellcheck source=../operator-identity.sh
source "${_L4_OPERATOR_IDENTITY}"

_l4_log() { echo "[graduated-trust] $*" >&2; }

# -----------------------------------------------------------------------------
# Defaults (overridable via env vars or .loa.config.yaml).
# -----------------------------------------------------------------------------
_L4_DEFAULT_LEDGER=".run/trust-ledger.jsonl"
_L4_DEFAULT_TIER="T0"
_L4_DEFAULT_COOLDOWN_SECONDS="604800"   # 7 days, per SDD §5.6.3

# Hard ceiling on cooldown_until - ts_utc. Defends against ledger-write
# adversaries who craft auto_drop entries with cooldown_until in the far
# future (operator-stuck DoS) or in the distant past (cooldown nullification).
# 90 days. The resolver clamps to this window even when payload.cooldown_until
# claims otherwise. Sprint 4C cypherpunk audit CRIT-2.
_L4_MAX_COOLDOWN_SECONDS="7776000"      # 90 days

# -----------------------------------------------------------------------------
# Input validation regexes.
#
# Scope, capability, actor are operator-supplied identifiers. We pin them to a
# conservative charset (alphanumeric + . _ - / : @) that:
#   - excludes shell metacharacters ($ ` " ' \ ; & | < > ( ) { } [ ])
#   - excludes whitespace, newlines, control bytes
#   - tolerates common namespace separators ('.', '/', ':')
#
# THIS REGEX IS NOT SUFFICIENT ON ITS OWN — per cycle-099 charclass dot-dot
# memory entry, `^[A-Za-z0-9._/-]+$` accepts `..` because each dot is
# individually in class. We pair it with explicit *..* + url-shape rejection
# in `_l4_validate_token` below.
# -----------------------------------------------------------------------------
_L4_TOKEN_RE='^[A-Za-z0-9._/:@-]{1,256}$'
_L4_TIER_RE='^[A-Za-z0-9_-]{1,32}$'
_L4_INT_RE='^[0-9]+$'

# -----------------------------------------------------------------------------
# _l4_validate_token <value> <field_name>
#
# Validates an operator-supplied identifier. Rejects:
#   - empty
#   - non-matching charset
#   - dot-dot sequences (charclass-bypass defense)
#   - URL-shape sentinels (`://`, leading `//`, leading `?`) — pasted-secret defense
# -----------------------------------------------------------------------------
_l4_validate_token() {
    local value="$1"
    local field="$2"
    if [[ -z "$value" ]]; then
        _l4_log "ERROR: $field is empty"
        return 1
    fi
    if ! [[ "$value" =~ $_L4_TOKEN_RE ]]; then
        _l4_log "ERROR: $field='$value' does not match $_L4_TOKEN_RE"
        return 1
    fi
    if [[ "$value" == *..* ]]; then
        _l4_log "ERROR: $field='$value' contains '..' (path traversal sentinel)"
        return 1
    fi
    # URL-shape sentinels (cycle-099 #761 pattern). Operators sometimes paste
    # the wrong field; reject anything that looks like a URL or query string.
    if [[ "$value" == *://* ]] || [[ "$value" == //* ]] || [[ "$value" == \?* ]]; then
        _l4_log "ERROR: $field='$value' looks URL-shaped (rejected)"
        return 1
    fi
    return 0
}

_l4_validate_tier() {
    local value="$1"
    local field="$2"
    if [[ -z "$value" ]] || ! [[ "$value" =~ $_L4_TIER_RE ]]; then
        _l4_log "ERROR: $field='$value' does not match $_L4_TIER_RE"
        return 1
    fi
    return 0
}

_l4_validate_int() {
    local value="$1"
    local field="$2"
    if [[ -z "$value" ]] || ! [[ "$value" =~ $_L4_INT_RE ]]; then
        _l4_log "ERROR: $field='$value' is not a non-negative integer"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l4_validate_reason <reason> <field_name>
#
# Reason / rationale strings flow into audit envelope payloads (JSON-escaped
# so injection is safe at the parser level), but they also flow into
# downstream tooling that uses line-oriented `grep -F` against the JSONL.
# Reject control bytes (corrupt line-oriented consumers) and JSONL field
# substrings (defeat grep-based auditors). Sprint 4 cypherpunk MED-2.
# -----------------------------------------------------------------------------
_l4_validate_reason() {
    local reason="$1"
    local field="$2"
    if (( ${#reason} > 4096 )); then
        _l4_log "ERROR: $field exceeds 4096 chars"
        return 1
    fi
    if [[ "$reason" =~ [[:cntrl:]] ]]; then
        _l4_log "ERROR: $field contains control bytes"
        return 1
    fi
    if [[ "$reason" == *'"event_type":'* ]] || [[ "$reason" == *'"prev_hash":'* ]]; then
        _l4_log "ERROR: $field contains JSONL field substring (rejected to protect grep-based auditors)"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l4_config_path — return resolved .loa.config.yaml path.
# -----------------------------------------------------------------------------
_l4_config_path() {
    echo "${LOA_TRUST_CONFIG_FILE:-${_L4_REPO_ROOT}/.loa.config.yaml}"
}

# -----------------------------------------------------------------------------
# _l4_ledger_path — return resolved .run/trust-ledger.jsonl path.
# -----------------------------------------------------------------------------
_l4_ledger_path() {
    if [[ -n "${LOA_TRUST_LEDGER_FILE:-}" ]]; then
        echo "$LOA_TRUST_LEDGER_FILE"
    else
        echo "${_L4_REPO_ROOT}/${_L4_DEFAULT_LEDGER}"
    fi
}

# -----------------------------------------------------------------------------
# _l4_config_get <yaml_path> [default]
#
# Read a value from .loa.config.yaml using yq if available, else PyYAML.
# `<yaml_path>` is a yq dotted expression (e.g., '.graduated_trust.default_tier').
# -----------------------------------------------------------------------------
_l4_config_get() {
    local yq_path="$1"
    local default="${2:-}"
    local config
    config="$(_l4_config_path)"
    [[ -f "$config" ]] || { echo "$default"; return 0; }
    if command -v yq >/dev/null 2>&1; then
        local result
        result="$(yq -r "${yq_path} // \"\"" "$config" 2>/dev/null || true)"
        if [[ -z "$result" || "$result" == "null" ]]; then
            echo "$default"
        else
            echo "$result"
        fi
        return 0
    fi
    local clean_path="${yq_path#.}"
    python3 - "$config" "$clean_path" "$default" <<'PY' 2>/dev/null || echo "$default"
import sys
try:
    import yaml
except ImportError:
    print(sys.argv[3])
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print(sys.argv[3])
    sys.exit(0)
parts = sys.argv[2].split('.')
node = doc
for p in parts:
    if isinstance(node, dict) and p in node:
        node = node[p]
    else:
        print(sys.argv[3])
        sys.exit(0)
if node is None or node == "":
    print(sys.argv[3])
else:
    print(node)
PY
}

# -----------------------------------------------------------------------------
# _l4_enabled — is L4 enabled in operator config?
# Returns 0 (true) when graduated_trust.enabled is true; 1 otherwise.
# Default: false (operator must opt in).
# -----------------------------------------------------------------------------
_l4_enabled() {
    local v
    v="$(_l4_config_get '.graduated_trust.enabled' 'false')"
    [[ "$v" == "true" ]]
}

# -----------------------------------------------------------------------------
# _l4_require_enabled
#
# Sprint 4 cypherpunk audit HIGH-3: gate every write entry-point. Writes
# proceed only when graduated_trust.enabled=true. Refuses with exit 1 when
# disabled or unconfigured.
#
# Reads are NOT gated — operators can inspect prior state via trust_query
# even after disabling the primitive (matches PRD §849 read-still-works-on-
# sealed-ledger).
# -----------------------------------------------------------------------------
_l4_require_enabled() {
    if ! _l4_enabled; then
        _l4_log "graduated_trust.enabled is not true; refusing write (set graduated_trust.enabled: true in .loa.config.yaml)"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# _l4_require_chain_intact <ledger>
#
# Sprint 4 cypherpunk audit HIGH-2: refuse to APPEND to a broken chain. If
# audit_verify_chain reports breakage, the operator must run trust_recover_chain
# (FR-L4-7) before further writes. Reads are NOT gated — they may degrade
# gracefully via _l4_walk_ledger which already filters non-JSON marker lines.
#
# Empty / missing ledger is treated as intact (clean install).
# -----------------------------------------------------------------------------
_l4_require_chain_intact() {
    local ledger="$1"
    [[ -f "$ledger" ]] || return 0
    [[ -s "$ledger" ]] || return 0
    if ! audit_verify_chain "$ledger" >/dev/null 2>&1; then
        _l4_log "ledger chain integrity broken at '$ledger'; run trust_recover_chain before further writes"
        return 1
    fi
}

_l4_get_default_tier() {
    if [[ -n "${LOA_TRUST_DEFAULT_TIER:-}" ]]; then
        echo "$LOA_TRUST_DEFAULT_TIER"
        return 0
    fi
    _l4_config_get '.graduated_trust.default_tier' "$_L4_DEFAULT_TIER"
}

_l4_get_cooldown_seconds() {
    local s
    if [[ -n "${LOA_TRUST_COOLDOWN_SECONDS:-}" ]]; then
        s="$LOA_TRUST_COOLDOWN_SECONDS"
    else
        s="$(_l4_config_get '.graduated_trust.cooldown_seconds' "$_L4_DEFAULT_COOLDOWN_SECONDS")"
    fi
    if ! _l4_validate_int "$s" "cooldown_seconds"; then
        echo "$_L4_DEFAULT_COOLDOWN_SECONDS"
        return 0
    fi
    echo "$s"
}

# -----------------------------------------------------------------------------
# _l4_get_tier_definitions
#
# Returns a JSON object: { "T0": {description: "..."}, ... } from
# .loa.config.yaml::graduated_trust.tier_definitions. Returns "{}" when
# L4 is disabled or no tier_definitions are configured.
# -----------------------------------------------------------------------------
_l4_get_tier_definitions() {
    local config
    config="$(_l4_config_path)"
    if [[ ! -f "$config" ]]; then
        echo '{}'
        return 0
    fi
    if command -v yq >/dev/null 2>&1; then
        local result
        result="$(yq -o=json '.graduated_trust.tier_definitions // {}' "$config" 2>/dev/null || echo '{}')"
        if [[ -z "$result" || "$result" == "null" ]]; then
            echo '{}'
        else
            printf '%s\n' "$result" | jq -c .
        fi
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || echo '{}'
import sys, json
try:
    import yaml
except ImportError:
    print('{}'); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print('{}'); sys.exit(0)
node = ((doc or {}).get('graduated_trust') or {}).get('tier_definitions') or {}
print(json.dumps(node))
PY
}

# -----------------------------------------------------------------------------
# _l4_get_transition_rules
#
# Returns a JSON array of transition rules from
# .loa.config.yaml::graduated_trust.transition_rules. Each rule has the shape
# documented in SDD §5.6.3:
#   { from: "T0", to: "T1", requires: "operator_grant" }
#   { from: "any", to_lower: true, via: "auto_drop_on_override" }
#
# Returns "[]" when none configured.
# -----------------------------------------------------------------------------
_l4_get_transition_rules() {
    local config
    config="$(_l4_config_path)"
    if [[ ! -f "$config" ]]; then
        echo '[]'
        return 0
    fi
    if command -v yq >/dev/null 2>&1; then
        local result
        result="$(yq -o=json '.graduated_trust.transition_rules // []' "$config" 2>/dev/null || echo '[]')"
        if [[ -z "$result" || "$result" == "null" ]]; then
            echo '[]'
        else
            printf '%s\n' "$result" | jq -c .
        fi
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || echo '[]'
import sys, json
try:
    import yaml
except ImportError:
    print('[]'); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print('[]'); sys.exit(0)
node = ((doc or {}).get('graduated_trust') or {}).get('transition_rules') or []
print(json.dumps(node))
PY
}

# -----------------------------------------------------------------------------
# _l4_now_iso8601 — current UTC time, microsecond precision.
#
# Honors LOA_TRUST_TEST_NOW for deterministic tests, but ONLY when test mode
# is detected (LOA_TRUST_TEST_MODE=1, or running under bats via
# BATS_TEST_DIRNAME). Production paths ignore LOA_TRUST_TEST_NOW so that an
# adversary that can set env vars cannot rewrite history's "now" to clear
# cooldowns or pre-date force-grants. Sprint 4 cypherpunk audit MED-4.
# Format matches ts_utc field of audit envelope (RFC 3339 with offset Z).
# -----------------------------------------------------------------------------
_l4_now_iso8601() {
    if [[ -n "${LOA_TRUST_TEST_NOW:-}" ]] \
        && { [[ "${LOA_TRUST_TEST_MODE:-0}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]; }; then
        echo "$LOA_TRUST_TEST_NOW"
        return 0
    fi
    python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")'
}

# -----------------------------------------------------------------------------
# _l4_iso_to_epoch_seconds <iso8601>
#
# Convert RFC 3339 / ISO-8601 to epoch seconds (integer, truncated). Used to
# compare timestamps for cooldown enforcement. Trailing Z and offsets handled.
# Outputs the integer; exits non-zero on parse failure.
# -----------------------------------------------------------------------------
_l4_iso_to_epoch_seconds() {
    local iso="$1"
    python3 -c '
import sys
from datetime import datetime
s = sys.argv[1]
# Normalize: trailing Z -> +00:00 for fromisoformat
if s.endswith("Z"):
    s = s[:-1] + "+00:00"
try:
    dt = datetime.fromisoformat(s)
except Exception as e:
    print(f"_l4_iso_to_epoch_seconds: parse failure: {e}", file=sys.stderr)
    sys.exit(1)
print(int(dt.timestamp()))
' "$iso"
}

# -----------------------------------------------------------------------------
# _l4_ledger_is_sealed [<ledger_file>]
#
# Returns 0 (true) when the ledger contains ANY trust.disable event_type.
# Sprint 4 cypherpunk audit CRIT-1: scanning only the tail line is unsafe
# because audit_recover_chain appends `[CHAIN-BROKEN]` / `[CHAIN-RECOVERED ...]`
# marker lines after the last JSON entry. With tail-only scanning, a sealed
# ledger followed by a marker would falsely appear unsealed and accept new
# transitions after the seal.
#
# The seal is a STATE, not a tail position. Per PRD §849: on disable the
# ledger is preserved (immutable hash-chain); subsequent reads return last-
# known-tier per scope; no new transitions allowed.
#
# Returns 0 (true) on first matching trust.disable line; 1 (false) when no
# such line exists or the ledger is absent.
# -----------------------------------------------------------------------------
_l4_ledger_is_sealed() {
    local ledger="${1:-$(_l4_ledger_path)}"
    [[ -f "$ledger" ]] || return 1
    [[ -s "$ledger" ]] || return 1
    # Skip non-JSON marker lines (lines starting with `[`); for each remaining
    # line, parse event_type. Match on first trust.disable found.
    # awk over grep so an all-marker ledger doesn't trip pipefail.
    awk '!/^\[/' "$ledger" 2>/dev/null \
        | jq -r 'select(.event_type == "trust.disable") | .event_type' 2>/dev/null \
        | grep -q '^trust\.disable$'
}

# -----------------------------------------------------------------------------
# _l4_walk_ledger <ledger_file> <scope> <capability> <actor>
#
# Stream-filter the ledger and emit a transition_history JSON array on stdout.
# Each emitted item has shape:
#   { from_tier, to_tier, transition_type, ts_utc, decision_id|null, reason }
#
# Emits "[]" when no entries match. Accepts events:
#   trust.grant       -> transition_type:"operator_grant" (or "initial" when from_tier null)
#   trust.auto_drop   -> transition_type:"auto_drop"
#   trust.force_grant -> transition_type:"force_grant"
#   trust.auto_raise_eligible -> transition_type:"auto_raise_eligible"
#
# trust.disable and trust.query are ignored (not transitions).
#
# CRITICAL: filter is a jq pipeline driven by --arg (no string interpolation;
# defense per cycle-098 jq-injection memory).
# -----------------------------------------------------------------------------
_l4_walk_ledger() {
    local ledger="$1"
    local scope="$2"
    local capability="$3"
    local actor="$4"

    if [[ ! -f "$ledger" ]] || [[ ! -s "$ledger" ]]; then
        echo '[]'
        return 0
    fi

    # jq slurp-then-map: stream JSONL into array, filter by selector, project.
    # --slurp consumes the file as a single array.
    #
    # Sprint 4 cypherpunk audit HIGH-1: filter marker lines (lines starting
    # with `[` — appended by audit_recover_chain after recovery / chain-break)
    # before jq -s. Without the filter, jq -s parse-errors and the caller
    # (trust_query) silently falls back to '[]' (default-tier) — turning every
    # query into a default-tier response on a partially-recovered ledger.
    #
    # If the filtered content fails to parse (corruption beyond marker lines),
    # this function returns non-zero so the caller can refuse to act on a
    # broken ledger rather than degrading to default_tier silently.
    # awk over grep so an all-marker ledger produces empty stdout (exit 0)
    # rather than tripping pipefail (grep -v exits 1 on no match).
    awk '!/^\[/' "$ledger" 2>/dev/null \
        | jq -sc \
        --arg scope "$scope" \
        --arg capability "$capability" \
        --arg actor "$actor" \
        '
        map(
          select(
            (.payload.scope == $scope) and
            (.payload.capability == $capability) and
            (.payload.actor == $actor) and
            (.event_type == "trust.grant" or
             .event_type == "trust.auto_drop" or
             .event_type == "trust.force_grant" or
             .event_type == "trust.auto_raise_eligible")
          )
          | {
              from_tier: (.payload.from_tier // null),
              # Auto-raise-eligible is informational; do NOT carry a to_tier
              # (resolver if-to_tier guard treats null as no-op).
              to_tier: (
                if .event_type == "trust.auto_raise_eligible" then null
                else (.payload.to_tier // null)
                end
              ),
              transition_type: (
                if .event_type == "trust.grant" then
                  (if (.payload.from_tier // null) == null then "initial" else "operator_grant" end)
                elif .event_type == "trust.auto_drop" then "auto_drop"
                elif .event_type == "trust.force_grant" then "force_grant"
                elif .event_type == "trust.auto_raise_eligible" then "auto_raise_eligible"
                else "operator_grant"
                end
              ),
              ts_utc: .ts_utc,
              # Frozen cooldown_until from the auto_drop payload — preserves
              # audit-immutability when operator config changes cooldown_seconds
              # AFTER an override has been recorded. null for non-auto_drop events.
              cooldown_until: (.payload.cooldown_until // null),
              decision_id: (.payload.decision_id // null),
              reason: (.payload.reason // "")
            }
        )
        '
}

# -----------------------------------------------------------------------------
# _l4_resolve_state <transition_history_json> <default_tier> <cooldown_seconds> <now_iso>
#
# Given a transition_history JSON array, the configured default_tier, the
# cooldown window, and "now", compute:
#   - effective tier (last to_tier, else default_tier)
#   - in_cooldown_until (ISO-8601 if last *non-revoking* transition was an
#     auto_drop AND now < its cooldown_until; else null)
#
# Emits JSON: {tier, in_cooldown_until} on stdout.
#
# Cooldown semantics (matches FR-L4-3 + FR-L4-8 narrative):
#   - auto_drop sets cooldown_until = ts_utc(auto_drop) + cooldown_seconds.
#   - operator_grant DOES NOT clear cooldown_until on its own (operator must
#     use --force, which records trust.force_grant; force_grant CLEARS the
#     cooldown).
#   - force_grant therefore clears the cooldown.
# -----------------------------------------------------------------------------
_l4_resolve_state() {
    local history_json="$1"
    local default_tier="$2"
    local cooldown_seconds="$3"
    local now_iso="$4"

    local max_cooldown="${_L4_MAX_COOLDOWN_SECONDS}"
    python3 - "$history_json" "$default_tier" "$cooldown_seconds" "$now_iso" "$max_cooldown" <<'PY'
import json, sys
from datetime import datetime, timedelta

history = json.loads(sys.argv[1] or "[]")
default_tier = sys.argv[2]
cooldown_seconds = int(sys.argv[3])
now_iso = sys.argv[4]
max_cooldown_seconds = int(sys.argv[5])

def parse_iso(s):
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)

now = parse_iso(now_iso)

tier = default_tier
cooldown_until_iso = None
last_auto_drop_until = None

for entry in history:
    ttype = entry.get("transition_type")
    to_tier = entry.get("to_tier")
    ts_utc = entry.get("ts_utc")
    if to_tier:
        tier = to_tier
    if ttype == "auto_drop":
        # Audit-immutability: prefer the FROZEN cooldown_until from the event
        # payload (captured at override-time per Sprint 4B). Fall back to
        # ts_utc + current-config cooldown_seconds for legacy entries that
        # might predate the frozen field.
        #
        # Sprint 4 cypherpunk audit CRIT-2: clamp the frozen value to
        # [ts_utc, ts_utc + max_cooldown_seconds]. An adversary that can
        # write the ledger could otherwise craft a frozen cooldown_until of
        # 9999-12-31 (operator-stuck-forever DoS) or 1970-01-01 (cooldown
        # nullification). The hard ceiling defends both.
        frozen = entry.get("cooldown_until")
        candidate = None
        if frozen:
            try:
                candidate = parse_iso(frozen)
            except Exception:
                candidate = None
        if candidate is None and ts_utc:
            try:
                candidate = parse_iso(ts_utc) + timedelta(seconds=cooldown_seconds)
            except Exception:
                candidate = None
        if candidate is not None and ts_utc:
            try:
                t = parse_iso(ts_utc)
                lo = t  # cooldown cannot end before its own start
                hi = t + timedelta(seconds=max_cooldown_seconds)
                if candidate < lo:
                    candidate = lo
                elif candidate > hi:
                    candidate = hi
            except Exception:
                pass
        last_auto_drop_until = candidate
    elif ttype == "force_grant":
        # force_grant clears the cooldown
        last_auto_drop_until = None
    # operator_grant / initial / auto_raise_eligible: do NOT clear cooldown

if last_auto_drop_until is not None and now < last_auto_drop_until:
    s = last_auto_drop_until.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    cooldown_until_iso = s

print(json.dumps({"tier": tier, "in_cooldown_until": cooldown_until_iso}))
PY
}

# =============================================================================
# Public API
# =============================================================================

# -----------------------------------------------------------------------------
# trust_query <scope> <capability> <actor>
#
# FR-L4-1: First query for any (scope, capability, actor) returns default_tier.
#
# Returns TrustResponse (SDD §5.6.2 / trust-response.schema.json):
#   {
#     scope, capability, actor, tier,
#     transition_history: [...],
#     in_cooldown_until: ISO-8601 | null,
#     auto_raise_eligible: boolean
#   }
# on stdout. Exit 0 success / 2 bad input / 1 ledger or config error.
# -----------------------------------------------------------------------------
trust_query() {
    local scope="${1:-}"
    local capability="${2:-}"
    local actor="${3:-}"

    if [[ -z "$scope" || -z "$capability" || -z "$actor" ]]; then
        _l4_log "trust_query: missing required argument (scope, capability, actor)"
        return 2
    fi

    _l4_validate_token "$scope" "scope" || return 2
    _l4_validate_token "$capability" "capability" || return 2
    _l4_validate_token "$actor" "actor" || return 2

    if [[ "${LOA_TRUST_REQUIRE_KNOWN_ACTOR:-0}" == "1" ]]; then
        if ! operator_identity_lookup "$actor" >/dev/null 2>&1; then
            _l4_log "trust_query: actor='$actor' not found in OPERATORS.md (LOA_TRUST_REQUIRE_KNOWN_ACTOR=1)"
            return 2
        fi
    fi

    local default_tier cooldown_seconds now_iso ledger
    default_tier="$(_l4_get_default_tier)"
    cooldown_seconds="$(_l4_get_cooldown_seconds)"
    now_iso="$(_l4_now_iso8601)"
    ledger="$(_l4_ledger_path)"

    if ! _l4_validate_tier "$default_tier" "default_tier"; then
        return 3
    fi

    local history state tier in_cooldown_until
    history="$(_l4_walk_ledger "$ledger" "$scope" "$capability" "$actor")" || history='[]'
    state="$(_l4_resolve_state "$history" "$default_tier" "$cooldown_seconds" "$now_iso")"
    tier="$(echo "$state" | jq -r '.tier')"
    in_cooldown_until="$(echo "$state" | jq -r '.in_cooldown_until')"
    if [[ "$in_cooldown_until" == "null" ]]; then
        in_cooldown_until=""
    fi

    # Build TrustResponse JSON.
    local response
    if [[ -n "$in_cooldown_until" ]]; then
        response="$(jq -nc \
            --arg scope "$scope" \
            --arg capability "$capability" \
            --arg actor "$actor" \
            --arg tier "$tier" \
            --argjson history "$history" \
            --arg cooldown_until "$in_cooldown_until" \
            '{
                scope: $scope,
                capability: $capability,
                actor: $actor,
                tier: $tier,
                transition_history: $history,
                in_cooldown_until: $cooldown_until,
                auto_raise_eligible: false
            }')"
    else
        response="$(jq -nc \
            --arg scope "$scope" \
            --arg capability "$capability" \
            --arg actor "$actor" \
            --arg tier "$tier" \
            --argjson history "$history" \
            '{
                scope: $scope,
                capability: $capability,
                actor: $actor,
                tier: $tier,
                transition_history: $history,
                in_cooldown_until: null,
                auto_raise_eligible: false
            }')"
    fi

    # Optional emission of trust.query event.
    if [[ "${LOA_TRUST_EMIT_QUERY_EVENTS:-0}" == "1" ]]; then
        local in_cooldown_bool="false"
        [[ -n "$in_cooldown_until" ]] && in_cooldown_bool="true"
        local entries_seen
        entries_seen="$(echo "$history" | jq 'length')"
        local payload
        payload="$(jq -nc \
            --arg scope "$scope" \
            --arg capability "$capability" \
            --arg actor "$actor" \
            --arg tier "$tier" \
            --argjson in_cooldown "$in_cooldown_bool" \
            --argjson entries_seen "$entries_seen" \
            '{
                scope: $scope,
                capability: $capability,
                actor: $actor,
                tier: $tier,
                in_cooldown: $in_cooldown,
                auto_raise_eligible: false,
                ledger_entries_seen: $entries_seen
            }')"
        # Best-effort: don't fail trust_query if audit log is unwritable in
        # a test fixture without LOA_AUDIT_LOG_DIR. Errors logged to stderr.
        audit_emit "L4" "trust.query" "$payload" "$ledger" \
            || _l4_log "trust_query: audit_emit trust.query failed (non-fatal)"
    fi

    printf '%s\n' "$response"
}

# -----------------------------------------------------------------------------
# _l4_txn_lock_path <ledger>
#
# Returns the path of the transaction lock file. SEPARATE from audit_emit's
# `<log>.lock` to avoid deadlock when our transaction calls audit_emit (each
# flocks a distinct lock file). The transaction lock guards the whole
# read-validate-write atom (cooldown check vs concurrent writes).
# -----------------------------------------------------------------------------
_l4_txn_lock_path() {
    echo "$1.txn.lock"
}

# -----------------------------------------------------------------------------
# _l4_find_grant_rule <from_tier> <to_tier>
#
# Walk transition_rules JSON; emit the first rule whose (from, to) matches and
# requires == operator_grant. Returns "" when no rule matches (caller treats
# as transition rejected per FR-L4-2).
# -----------------------------------------------------------------------------
_l4_find_grant_rule() {
    local from="$1"
    local to="$2"
    local rules
    rules="$(_l4_get_transition_rules)"
    echo "$rules" | jq -c \
        --arg from "$from" \
        --arg to "$to" \
        '
        .[] | select(
            (.from == $from) and
            (.to == $to) and
            ((.requires // "") == "operator_grant")
        )
        ' | head -n 1
}

# -----------------------------------------------------------------------------
# _l4_find_auto_drop_rule <from_tier>
#
# Walk transition_rules JSON; emit the first rule whose `via` is
# `auto_drop_on_override` AND whose `from` matches (or is "any"). Returns ""
# when no rule matches (caller treats as no auto-drop available — error).
#
# Two valid shapes:
#   {from: "T2", to: "T1", via: "auto_drop_on_override"}     (explicit drop_to)
#   {from: "any", to_lower: true, via: "auto_drop_on_override"}  (drop to default_tier)
#
# When matching the "any/to_lower:true" form, the caller must compute
# `drop_to = default_tier` (this lib does not infer arbitrary tier ordering).
# -----------------------------------------------------------------------------
_l4_find_auto_drop_rule() {
    local from="$1"
    local rules
    rules="$(_l4_get_transition_rules)"
    echo "$rules" | jq -c \
        --arg from "$from" \
        '
        .[] | select(
            ((.via // "") == "auto_drop_on_override") and
            ((.from == $from) or (.from == "any"))
        )
        ' | head -n 1
}

# -----------------------------------------------------------------------------
# _l4_iso_add_seconds <iso8601> <seconds>
#
# Returns ISO-8601 of <iso> + <seconds> (UTC, ms precision). Used to compute
# cooldown_until = ts_utc + cooldown_seconds. Exits non-zero on parse failure.
# -----------------------------------------------------------------------------
_l4_iso_add_seconds() {
    local iso="$1"
    local secs="$2"
    python3 -c '
import sys
from datetime import datetime, timedelta
s = sys.argv[1]
secs = int(sys.argv[2])
if s.endswith("Z"):
    s = s[:-1] + "+00:00"
try:
    dt = datetime.fromisoformat(s)
except Exception as e:
    print(f"_l4_iso_add_seconds: parse failure: {e}", file=sys.stderr)
    sys.exit(1)
print((dt + timedelta(seconds=secs)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")
' "$iso" "$secs"
}

# -----------------------------------------------------------------------------
# trust_grant <scope> <capability> <actor> <new_tier> [--reason <text>] [--operator <slug>]
#
# FR-L4-2: Only configured transitions allowed; arbitrary jumps return error.
# FR-L4-3 interaction: cooldown blocks regular trust_grant. Operator must use
# trust_grant --force (Sprint 4C) which routes via trust.force_grant.
#
# Exit codes:
#   0 grant succeeded; trust.grant entry appended
#   2 invalid argument
#   3 transition rejected (no matching rule, or cooldown active)
#   1 ledger / audit_emit error
#
# Sprint 4B implements the regular path. --force routes to trust_force_grant
# in Sprint 4C; for now, --force returns 99 (not implemented).
# -----------------------------------------------------------------------------
trust_grant() {
    local scope="" capability="" actor="" new_tier=""
    local reason="" operator="" force=0

    # Positional first 4 args; remaining are flags.
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)         force=1; shift ;;
            --reason)        reason="${2:-}"; shift 2 ;;
            --operator)      operator="${2:-}"; shift 2 ;;
            *)               positional+=("$1"); shift ;;
        esac
    done
    # Restore positionals.
    set -- ${positional[@]+"${positional[@]}"}
    scope="${1:-}"
    capability="${2:-}"
    actor="${3:-}"
    new_tier="${4:-}"

    if [[ -z "$scope" || -z "$capability" || -z "$actor" || -z "$new_tier" ]]; then
        _l4_log "trust_grant: missing required argument (scope, capability, actor, new_tier)"
        return 2
    fi

    _l4_require_enabled || return 1

    _l4_validate_token "$scope"      "scope"      || return 2
    _l4_validate_token "$capability" "capability" || return 2
    _l4_validate_token "$actor"      "actor"      || return 2
    _l4_validate_tier  "$new_tier"   "new_tier"   || return 2

    if [[ -z "$reason" ]]; then
        _l4_log "trust_grant: --reason is required (audit-mandatory rationale)"
        return 2
    fi
    _l4_validate_reason "$reason" "reason" || return 2

    if [[ -z "$operator" ]]; then
        if (( force == 1 )); then
            # Cypherpunk HIGH-6: force-grant requires explicit --operator
            # (cannot self-force-grant). The auditor must be able to
            # distinguish operator-driven from agent-driven force-grants.
            _l4_log "trust_grant --force: --operator is required and must be distinct from actor (cannot self-force-grant)"
            return 2
        fi
        # Default to actor only if operator unspecified AND not force-grant;
        # this captures the self-grant convention used by single-operator
        # deployments (regular grants only).
        operator="$actor"
    fi
    _l4_validate_token "$operator" "operator" || return 2

    if (( force == 1 )) && [[ "$operator" == "$actor" ]]; then
        _l4_log "trust_grant --force: --operator must be distinct from actor (cypherpunk HIGH-6)"
        return 2
    fi

    if [[ "${LOA_TRUST_REQUIRE_KNOWN_ACTOR:-0}" == "1" ]]; then
        operator_identity_lookup "$operator" >/dev/null 2>&1 || {
            _l4_log "trust_grant: operator='$operator' not found in OPERATORS.md"
            return 2
        }
        operator_identity_lookup "$actor" >/dev/null 2>&1 || {
            _l4_log "trust_grant: actor='$actor' not found in OPERATORS.md"
            return 2
        }
    fi

    # FR-L4-8 force path (Sprint 4C): emits trust.force_grant with cooldown
    # remaining at grant time recorded for the auditor.
    if (( force == 1 )); then
        _trust_force_grant_impl \
            "$scope" "$capability" "$actor" "$new_tier" "$operator" "$reason"
        return $?
    fi

    local ledger lock_file
    ledger="$(_l4_ledger_path)"
    lock_file="$(_l4_txn_lock_path "$ledger")"
    mkdir -p "$(dirname "$ledger")"
    : > "$lock_file" 2>/dev/null || touch "$lock_file"

    _audit_require_flock || return 1

    # Hold txn lock for the whole read-validate-write transaction.
    # CRITICAL: this is the .txn.lock file (NOT <log>.lock), so audit_emit's
    # own flock on <log>.lock proceeds without deadlock.
    local rc=0
    {
        flock -w 30 9 || {
            _l4_log "trust_grant: failed to acquire txn lock on $lock_file"
            return 1
        }

        # Refuse if ledger sealed.
        if _l4_ledger_is_sealed "$ledger"; then
            _l4_log "trust_grant: ledger is sealed [L4-DISABLED]; no further transitions allowed"
            return 3
        fi

        # HIGH-2: refuse to append to a broken chain.
        _l4_require_chain_intact "$ledger" || return 1

        # Read current state.
        local current_tier from_tier_for_event in_cooldown_until response
        response="$(trust_query "$scope" "$capability" "$actor")" || {
            _l4_log "trust_grant: trust_query failed"
            return 1
        }
        current_tier="$(echo "$response" | jq -r '.tier')"
        in_cooldown_until="$(echo "$response" | jq -r '.in_cooldown_until')"
        if [[ "$in_cooldown_until" == "null" || -z "$in_cooldown_until" ]]; then
            in_cooldown_until=""
        fi

        # Cooldown check (FR-L4-3 enforcement).
        if [[ -n "$in_cooldown_until" ]]; then
            _l4_log "trust_grant: cooldown active until '$in_cooldown_until' for ($scope,$capability,$actor); use --force (Sprint 4C) to override"
            return 3
        fi

        # Determine from_tier_for_event:
        #   - If transition_history empty AND new_tier == default_tier: invalid
        #     (already at default_tier — no-op)
        #   - If transition_history empty: from_tier null (initial)
        #   - Else: from_tier = current_tier
        local hist_len
        hist_len="$(echo "$response" | jq '.transition_history | length')"
        if [[ "$hist_len" == "0" ]]; then
            from_tier_for_event=""
        else
            from_tier_for_event="$current_tier"
        fi

        # No-op detection: cannot transition to current tier.
        if [[ "$current_tier" == "$new_tier" ]]; then
            _l4_log "trust_grant: ($scope,$capability,$actor) is already at tier '$new_tier' (no-op)"
            return 3
        fi

        # Transition validation (FR-L4-2):
        #   - Initial transition (from_tier null) MUST match a rule with
        #     from = default_tier.
        #   - Non-initial transition MUST match a rule with from = current_tier.
        local rule rule_id from_for_rule
        if [[ -z "$from_tier_for_event" ]]; then
            from_for_rule="$(_l4_get_default_tier)"
        else
            from_for_rule="$current_tier"
        fi
        rule="$(_l4_find_grant_rule "$from_for_rule" "$new_tier")"
        if [[ -z "$rule" ]]; then
            _l4_log "trust_grant: no transition_rule allows operator_grant from '$from_for_rule' to '$new_tier' (FR-L4-2)"
            return 3
        fi
        rule_id="$(echo "$rule" | jq -r '.id // ""')"

        # Build payload + emit.
        local from_arg from_kind
        if [[ -z "$from_tier_for_event" ]]; then
            from_arg="null"
            from_kind="null"
        else
            from_arg="$from_tier_for_event"
            from_kind="string"
        fi
        local payload
        if [[ "$from_kind" == "null" ]]; then
            payload="$(jq -nc \
                --arg scope "$scope" \
                --arg capability "$capability" \
                --arg actor "$actor" \
                --arg to_tier "$new_tier" \
                --arg operator "$operator" \
                --arg reason "$reason" \
                --arg rule_id "$rule_id" \
                '{
                    scope: $scope, capability: $capability, actor: $actor,
                    from_tier: null, to_tier: $to_tier,
                    operator: $operator, reason: $reason,
                    transition_rule_id: (if $rule_id == "" then null else $rule_id end)
                }')"
        else
            payload="$(jq -nc \
                --arg scope "$scope" \
                --arg capability "$capability" \
                --arg actor "$actor" \
                --arg from_tier "$from_arg" \
                --arg to_tier "$new_tier" \
                --arg operator "$operator" \
                --arg reason "$reason" \
                --arg rule_id "$rule_id" \
                '{
                    scope: $scope, capability: $capability, actor: $actor,
                    from_tier: $from_tier, to_tier: $to_tier,
                    operator: $operator, reason: $reason,
                    transition_rule_id: (if $rule_id == "" then null else $rule_id end)
                }')"
        fi

        if ! audit_emit "L4" "trust.grant" "$payload" "$ledger"; then
            _l4_log "trust_grant: audit_emit trust.grant failed"
            return 1
        fi
    } 9>"$lock_file"
    rc=$?
    return "$rc"
}

# -----------------------------------------------------------------------------
# trust_record_override <scope> <capability> <actor> <decision_id> <reason>
#
# FR-L4-3: recordOverride produces auto-drop per rules; cooldown enforced.
#
# Auto-drop semantics:
#   - Look up auto_drop_on_override rule for from=current_tier (or any).
#   - drop_to = rule.to (when explicit) | default_tier (when from=any/to_lower)
#   - cooldown_until = ts_utc(now) + cooldown_seconds
#
# Idempotency note: a record_override at the same (scope, capability, actor)
# while ALREADY in cooldown is allowed (the override might come from a
# different decision_id). The lib emits a fresh trust.auto_drop entry with the
# new decision_id; cooldown_until is computed from the NEW ts_utc (rolling
# cooldown). This matches the operator-intuitive interpretation of "every
# override re-arms the cooldown timer."
#
# Exit codes:
#   0 override recorded; trust.auto_drop entry appended
#   2 invalid argument
#   3 no auto_drop rule configured (operator must define one to enable
#       FR-L4-3) OR ledger sealed
#   1 audit_emit / I/O error
# -----------------------------------------------------------------------------
trust_record_override() {
    local scope="${1:-}"
    local capability="${2:-}"
    local actor="${3:-}"
    local decision_id="${4:-}"
    local reason="${5:-}"

    if [[ -z "$scope" || -z "$capability" || -z "$actor" || -z "$decision_id" || -z "$reason" ]]; then
        _l4_log "trust_record_override: missing required argument (scope, capability, actor, decision_id, reason)"
        return 2
    fi

    _l4_require_enabled || return 1

    _l4_validate_token "$scope"      "scope"      || return 2
    _l4_validate_token "$capability" "capability" || return 2
    _l4_validate_token "$actor"      "actor"      || return 2

    # decision_id is opaque (panel-decision-id, PR url, audit-event id) so we
    # accept a wider charset than scope/capability/actor — but reject control
    # bytes, quote/backtick chars, and angle brackets (HTML/markdown injection
    # defense per cypherpunk MED-3; decision_ids flow into PR comments + UIs).
    if [[ -z "$decision_id" ]]; then
        _l4_log "trust_record_override: decision_id empty"; return 2
    fi
    if (( ${#decision_id} > 512 )); then
        _l4_log "trust_record_override: decision_id exceeds 512 chars"; return 2
    fi
    if [[ "$decision_id" =~ [\$\`\"\'\\\<\>] ]] || [[ "$decision_id" =~ [[:cntrl:]] ]]; then
        _l4_log "trust_record_override: decision_id contains forbidden characters"
        return 2
    fi
    _l4_validate_reason "$reason" "reason" || return 2

    local ledger lock_file
    ledger="$(_l4_ledger_path)"
    lock_file="$(_l4_txn_lock_path "$ledger")"
    mkdir -p "$(dirname "$ledger")"
    : > "$lock_file" 2>/dev/null || touch "$lock_file"

    _audit_require_flock || return 1

    local rc=0
    {
        flock -w 30 9 || {
            _l4_log "trust_record_override: failed to acquire txn lock on $lock_file"
            return 1
        }

        if _l4_ledger_is_sealed "$ledger"; then
            _l4_log "trust_record_override: ledger is sealed [L4-DISABLED]"
            return 3
        fi

        # HIGH-2: refuse to append to a broken chain.
        _l4_require_chain_intact "$ledger" || return 1

        # Read current state.
        local response current_tier
        response="$(trust_query "$scope" "$capability" "$actor")" || {
            _l4_log "trust_record_override: trust_query failed"
            return 1
        }
        current_tier="$(echo "$response" | jq -r '.tier')"

        # Find auto_drop rule (explicit from=current_tier preferred; else any).
        local rule rule_to rule_to_lower drop_to
        rule="$(_l4_find_auto_drop_rule "$current_tier")"
        if [[ -z "$rule" ]]; then
            _l4_log "trust_record_override: no auto_drop_on_override rule configured for from='$current_tier' (FR-L4-3 requires operator to define one)"
            return 3
        fi
        rule_to="$(echo "$rule" | jq -r '.to // ""')"
        rule_to_lower="$(echo "$rule" | jq -r '.to_lower // false | tostring')"

        if [[ -n "$rule_to" ]]; then
            drop_to="$rule_to"
        elif [[ "$rule_to_lower" == "true" ]]; then
            drop_to="$(_l4_get_default_tier)"
        else
            _l4_log "trust_record_override: matched rule has neither .to nor .to_lower (malformed)"
            return 3
        fi

        # Validate drop_to is a sane tier and is NOT a raise.
        _l4_validate_tier "$drop_to" "drop_to" || return 3
        if [[ "$drop_to" == "$current_tier" ]]; then
            _l4_log "trust_record_override: auto_drop computed drop_to='$drop_to' equals current_tier (no-op rule misconfigured)"
            return 3
        fi

        # Compute cooldown_until.
        local now_iso cooldown_seconds cooldown_until
        now_iso="$(_l4_now_iso8601)"
        cooldown_seconds="$(_l4_get_cooldown_seconds)"
        cooldown_until="$(_l4_iso_add_seconds "$now_iso" "$cooldown_seconds")" || {
            _l4_log "trust_record_override: cooldown_until computation failed"
            return 1
        }

        # Build payload.
        local payload
        payload="$(jq -nc \
            --arg scope "$scope" \
            --arg capability "$capability" \
            --arg actor "$actor" \
            --arg from_tier "$current_tier" \
            --arg to_tier "$drop_to" \
            --arg decision_id "$decision_id" \
            --arg reason "$reason" \
            --arg cooldown_until "$cooldown_until" \
            --argjson cooldown_seconds "$cooldown_seconds" \
            '{
                scope: $scope, capability: $capability, actor: $actor,
                from_tier: $from_tier, to_tier: $to_tier,
                decision_id: $decision_id, reason: $reason,
                cooldown_until: $cooldown_until,
                cooldown_seconds: $cooldown_seconds
            }')"

        if ! audit_emit "L4" "trust.auto_drop" "$payload" "$ledger"; then
            _l4_log "trust_record_override: audit_emit trust.auto_drop failed"
            return 1
        fi
    } 9>"$lock_file"
    rc=$?
    return "$rc"
}

# -----------------------------------------------------------------------------
# _trust_force_grant_impl <scope> <capability> <actor> <new_tier> <operator> <reason>
#
# FR-L4-8: Force-grant in cooldown logged as exception with reason.
#
# Internal implementation invoked by `trust_grant --force`. Differences vs the
# regular grant path:
#   - Reason is REQUIRED (4096 max; same as regular path).
#   - Cooldown remaining at grant-time captured into the payload (auditor
#     evidence; 0 means cooldown had already elapsed when --force fired).
#   - Routes via the protected-class taxonomy: caller is operator-bound
#     (the protected-class-router classifies trust.force_grant as a
#     protected operation per .claude/data/protected-classes.yaml).
#   - Writes trust.force_grant event type (NOT trust.grant); ledger walker
#     and resolver treat trust.force_grant as a transition that CLEARS the
#     cooldown (per _l4_resolve_state semantics already shipped in 4A).
#
# Exit codes: same as trust_grant.
# -----------------------------------------------------------------------------
_trust_force_grant_impl() {
    local scope="$1"
    local capability="$2"
    local actor="$3"
    local new_tier="$4"
    local operator="$5"
    local reason="$6"

    # Re-validation here is paranoid (trust_grant already validated). Cheap
    # defense-in-depth for the case where this gets called directly.
    _l4_validate_token "$scope"      "scope"      || return 2
    _l4_validate_token "$capability" "capability" || return 2
    _l4_validate_token "$actor"      "actor"      || return 2
    _l4_validate_token "$operator"   "operator"   || return 2
    _l4_validate_tier  "$new_tier"   "new_tier"   || return 2
    if [[ -z "$reason" ]]; then
        _l4_log "trust_grant --force: --reason is required (FR-L4-8)"
        return 2
    fi
    _l4_validate_reason "$reason" "reason" || return 2

    # Force-grant requires explicit operator distinct from actor (HIGH-6).
    if [[ -z "$operator" || "$operator" == "$actor" ]]; then
        _l4_log "trust_grant --force: --operator must be set and distinct from actor"
        return 2
    fi

    local ledger lock_file
    ledger="$(_l4_ledger_path)"
    lock_file="$(_l4_txn_lock_path "$ledger")"
    mkdir -p "$(dirname "$ledger")"
    : > "$lock_file" 2>/dev/null || touch "$lock_file"

    _audit_require_flock || return 1

    local rc=0
    {
        flock -w 30 9 || {
            _l4_log "trust_grant --force: failed to acquire txn lock on $lock_file"
            return 1
        }

        if _l4_ledger_is_sealed "$ledger"; then
            _l4_log "trust_grant --force: ledger is sealed [L4-DISABLED]"
            return 3
        fi

        # HIGH-2: refuse to append to a broken chain.
        _l4_require_chain_intact "$ledger" || return 1

        local response current_tier in_cooldown_until
        response="$(trust_query "$scope" "$capability" "$actor")" || return 1
        current_tier="$(echo "$response" | jq -r '.tier')"
        in_cooldown_until="$(echo "$response" | jq -r '.in_cooldown_until')"
        if [[ "$in_cooldown_until" == "null" || -z "$in_cooldown_until" ]]; then
            in_cooldown_until=""
        fi

        # Compute cooldown_remaining_seconds_at_grant. 0 when cooldown has
        # elapsed (operator chose to use --force redundantly — still legal,
        # but auditor sees zero-remaining and can flag).
        local now_iso now_epoch cooldown_until_epoch remaining=0
        now_iso="$(_l4_now_iso8601)"
        if [[ -n "$in_cooldown_until" ]]; then
            now_epoch="$(_l4_iso_to_epoch_seconds "$now_iso")"
            cooldown_until_epoch="$(_l4_iso_to_epoch_seconds "$in_cooldown_until")"
            if (( cooldown_until_epoch > now_epoch )); then
                remaining=$(( cooldown_until_epoch - now_epoch ))
            fi
        fi

        # No-op detection.
        if [[ "$current_tier" == "$new_tier" ]]; then
            _l4_log "trust_grant --force: ($scope,$capability,$actor) already at '$new_tier' (no-op)"
            return 3
        fi

        # Determine from_tier_for_event.
        local from_tier_for_event hist_len
        hist_len="$(echo "$response" | jq '.transition_history | length')"
        if [[ "$hist_len" == "0" ]]; then
            from_tier_for_event=""
        else
            from_tier_for_event="$current_tier"
        fi

        # Build payload.
        local payload
        if [[ -z "$from_tier_for_event" ]]; then
            if [[ -n "$in_cooldown_until" ]]; then
                payload="$(jq -nc \
                    --arg scope "$scope" --arg capability "$capability" --arg actor "$actor" \
                    --arg to_tier "$new_tier" --arg operator "$operator" --arg reason "$reason" \
                    --argjson remaining "$remaining" --arg cooldown_until "$in_cooldown_until" \
                    '{
                        scope: $scope, capability: $capability, actor: $actor,
                        from_tier: null, to_tier: $to_tier,
                        operator: $operator, reason: $reason,
                        cooldown_remaining_seconds_at_grant: $remaining,
                        cooldown_until_at_grant: $cooldown_until
                    }')"
            else
                payload="$(jq -nc \
                    --arg scope "$scope" --arg capability "$capability" --arg actor "$actor" \
                    --arg to_tier "$new_tier" --arg operator "$operator" --arg reason "$reason" \
                    --argjson remaining "$remaining" \
                    '{
                        scope: $scope, capability: $capability, actor: $actor,
                        from_tier: null, to_tier: $to_tier,
                        operator: $operator, reason: $reason,
                        cooldown_remaining_seconds_at_grant: $remaining,
                        cooldown_until_at_grant: null
                    }')"
            fi
        else
            if [[ -n "$in_cooldown_until" ]]; then
                payload="$(jq -nc \
                    --arg scope "$scope" --arg capability "$capability" --arg actor "$actor" \
                    --arg from_tier "$from_tier_for_event" --arg to_tier "$new_tier" \
                    --arg operator "$operator" --arg reason "$reason" \
                    --argjson remaining "$remaining" --arg cooldown_until "$in_cooldown_until" \
                    '{
                        scope: $scope, capability: $capability, actor: $actor,
                        from_tier: $from_tier, to_tier: $to_tier,
                        operator: $operator, reason: $reason,
                        cooldown_remaining_seconds_at_grant: $remaining,
                        cooldown_until_at_grant: $cooldown_until
                    }')"
            else
                payload="$(jq -nc \
                    --arg scope "$scope" --arg capability "$capability" --arg actor "$actor" \
                    --arg from_tier "$from_tier_for_event" --arg to_tier "$new_tier" \
                    --arg operator "$operator" --arg reason "$reason" \
                    --argjson remaining "$remaining" \
                    '{
                        scope: $scope, capability: $capability, actor: $actor,
                        from_tier: $from_tier, to_tier: $to_tier,
                        operator: $operator, reason: $reason,
                        cooldown_remaining_seconds_at_grant: $remaining,
                        cooldown_until_at_grant: null
                    }')"
            fi
        fi

        if ! audit_emit "L4" "trust.force_grant" "$payload" "$ledger"; then
            _l4_log "trust_grant --force: audit_emit trust.force_grant failed"
            return 1
        fi
    } 9>"$lock_file"
    rc=$?
    return "$rc"
}

# -----------------------------------------------------------------------------
# trust_verify_chain [<ledger_file>]
#
# FR-L4-5: hash-chain integrity validates; tampering detectable.
#
# Wraps audit_verify_chain (1A library). Honors LOA_TRUST_LEDGER_FILE override.
# Exit 0 on intact chain; non-zero with stderr explanation otherwise.
# -----------------------------------------------------------------------------
trust_verify_chain() {
    local ledger="${1:-$(_l4_ledger_path)}"
    if [[ ! -f "$ledger" ]]; then
        _l4_log "trust_verify_chain: ledger does not exist: $ledger"
        return 2
    fi
    audit_verify_chain "$ledger"
}

# -----------------------------------------------------------------------------
# trust_recover_chain [<ledger_file>]
#
# FR-L4-7: Reconstructable from git history if local file lost.
#
# Wraps audit_recover_chain (1A). Per SDD §3.7, the trust-ledger.jsonl is
# TRACKED in git; audit_recover_chain prefers the git-history recovery path
# for tracked logs. Returns 0 on successful recovery; non-zero on failure
# (and audit_recover_chain itself appends [CHAIN-BROKEN] marker).
# -----------------------------------------------------------------------------
trust_recover_chain() {
    local ledger="${1:-$(_l4_ledger_path)}"
    audit_recover_chain "$ledger"
}

# -----------------------------------------------------------------------------
# trust_auto_raise_check <scope> <capability> <actor> <next_tier>
#
# FR-L4-4 (stub per FU-3 deferral): Auto-raise eligibility check.
#
# Sprint 4 ships only the stub: returns "eligibility_required" via stdout JSON
# and emits a trust.auto_raise_eligible audit event recording that the stub
# was consulted. The auto-raise itself REQUIRES operator action (trust_grant);
# the lib will not silently raise tiers in this cycle.
#
# FU-3 follow-up will extend with an `eligible` outcome once an alignment-
# tracking detector ships (e.g., 7-consecutive-aligned).
#
# Exit codes:
#   0 stub consulted; outcome="eligibility_required" emitted to stdout
#   2 invalid argument
#   1 audit_emit failure
# -----------------------------------------------------------------------------
trust_auto_raise_check() {
    local scope="${1:-}"
    local capability="${2:-}"
    local actor="${3:-}"
    local next_tier="${4:-}"

    if [[ -z "$scope" || -z "$capability" || -z "$actor" || -z "$next_tier" ]]; then
        _l4_log "trust_auto_raise_check: missing required argument (scope, capability, actor, next_tier)"
        return 2
    fi
    _l4_validate_token "$scope"      "scope"      || return 2
    _l4_validate_token "$capability" "capability" || return 2
    _l4_validate_token "$actor"      "actor"      || return 2
    _l4_validate_tier  "$next_tier"  "next_tier"  || return 2

    local response current_tier
    response="$(trust_query "$scope" "$capability" "$actor")" || return 1
    current_tier="$(echo "$response" | jq -r '.tier')"

    local stub_message
    stub_message="auto-raise eligibility detector deferred to FU-3; operator must invoke trust_grant manually"

    local payload
    payload="$(jq -nc \
        --arg scope "$scope" \
        --arg capability "$capability" \
        --arg actor "$actor" \
        --arg current_tier "$current_tier" \
        --arg next_tier "$next_tier" \
        --arg stub_message "$stub_message" \
        '{
            scope: $scope, capability: $capability, actor: $actor,
            current_tier: $current_tier, next_tier: $next_tier,
            stub_outcome: "eligibility_required",
            stub_message: $stub_message
        }')"

    local ledger
    ledger="$(_l4_ledger_path)"
    mkdir -p "$(dirname "$ledger")"
    if ! audit_emit "L4" "trust.auto_raise_eligible" "$payload" "$ledger"; then
        _l4_log "trust_auto_raise_check: audit_emit failed"
        return 1
    fi

    # Echo the stub outcome JSON to stdout for caller convenience.
    jq -nc \
        --arg scope "$scope" \
        --arg capability "$capability" \
        --arg actor "$actor" \
        --arg current_tier "$current_tier" \
        --arg next_tier "$next_tier" \
        '{
            scope: $scope, capability: $capability, actor: $actor,
            current_tier: $current_tier, next_tier: $next_tier,
            stub_outcome: "eligibility_required"
        }'
}

# -----------------------------------------------------------------------------
# trust_disable [--reason <text>] [--operator <slug>]
#
# Sprint 4D — emits a trust.disable event sealing the ledger. Per PRD §849
# (L4 row): on disable, the ledger is preserved (immutable hash-chain);
# subsequent reads return last-known-tier; no further transitions allowed.
#
# Already-sealed ledgers reject re-disable (no double-seal).
#
# Exit codes:
#   0 disable recorded
#   1 ledger / audit_emit error
#   2 invalid argument
#   3 ledger already sealed (idempotent refusal)
# -----------------------------------------------------------------------------
trust_disable() {
    local reason="" operator=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason)   reason="${2:-}";   shift 2 ;;
            --operator) operator="${2:-}"; shift 2 ;;
            --*)
                _l4_log "trust_disable: unknown flag '$1'"
                return 2
                ;;
            *)
                _l4_log "trust_disable: unexpected positional argument '$1'"
                return 2
                ;;
        esac
    done

    if [[ -z "$reason" ]]; then
        _l4_log "trust_disable: --reason is required"
        return 2
    fi
    _l4_validate_reason "$reason" "reason" || return 2
    if [[ -z "$operator" ]]; then
        _l4_log "trust_disable: --operator is required"
        return 2
    fi
    _l4_validate_token "$operator" "operator" || return 2

    _l4_require_enabled || return 1

    local ledger lock_file
    ledger="$(_l4_ledger_path)"
    lock_file="$(_l4_txn_lock_path "$ledger")"
    mkdir -p "$(dirname "$ledger")"
    : > "$lock_file" 2>/dev/null || touch "$lock_file"

    _audit_require_flock || return 1

    local rc=0
    {
        flock -w 30 9 || {
            _l4_log "trust_disable: failed to acquire txn lock on $lock_file"
            return 1
        }

        if _l4_ledger_is_sealed "$ledger"; then
            _l4_log "trust_disable: ledger already sealed; ignoring"
            return 3
        fi

        # HIGH-2: refuse to append to a broken chain.
        _l4_require_chain_intact "$ledger" || return 1

        local sealed_at
        sealed_at="$(_l4_now_iso8601)"

        local payload
        payload="$(jq -nc \
            --arg operator "$operator" \
            --arg reason "$reason" \
            --arg sealed_at "$sealed_at" \
            '{operator: $operator, reason: $reason, sealed_at: $sealed_at}')"

        if ! audit_emit "L4" "trust.disable" "$payload" "$ledger"; then
            _l4_log "trust_disable: audit_emit failed"
            return 1
        fi
    } 9>"$lock_file"
    rc=$?
    return "$rc"
}
