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
# Honors LOA_TRUST_TEST_NOW for deterministic tests. Format must match
# ts_utc field of audit envelope (RFC 3339 with offset Z).
# -----------------------------------------------------------------------------
_l4_now_iso8601() {
    if [[ -n "${LOA_TRUST_TEST_NOW:-}" ]]; then
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
# Returns 0 (true) when the ledger's last entry is event_type=trust.disable.
# Per PRD §849: on disable, the ledger is preserved (immutable hash-chain);
# subsequent reads return last-known-tier per scope; no new transitions.
#
# Returns 1 (false) when ledger absent or last entry is not trust.disable.
# -----------------------------------------------------------------------------
_l4_ledger_is_sealed() {
    local ledger="${1:-$(_l4_ledger_path)}"
    [[ -f "$ledger" ]] || return 1
    [[ -s "$ledger" ]] || return 1
    local last_event
    last_event="$(tail -n 1 "$ledger" 2>/dev/null | jq -r '.event_type // ""' 2>/dev/null || true)"
    [[ "$last_event" == "trust.disable" ]]
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
    # --slurp consumes the file as a single array. --raw-input + decode would
    # be heavier; the ledger file is bounded by retention and per-line sizes.
    jq -sc \
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
              to_tier:   (.payload.to_tier // .payload.next_tier),
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
              decision_id: (.payload.decision_id // null),
              reason: (.payload.reason // "")
            }
        )
        ' "$ledger"
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

    python3 - "$history_json" "$default_tier" "$cooldown_seconds" "$now_iso" <<'PY'
import json, sys
from datetime import datetime, timedelta

history = json.loads(sys.argv[1] or "[]")
default_tier = sys.argv[2]
cooldown_seconds = int(sys.argv[3])
now_iso = sys.argv[4]

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
    if ttype == "auto_drop" and ts_utc:
        try:
            t = parse_iso(ts_utc)
            last_auto_drop_until = t + timedelta(seconds=cooldown_seconds)
        except Exception:
            pass
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
# trust_grant — TODO Sprint 4B (regular path) / 4C (--force exception path).
# -----------------------------------------------------------------------------
trust_grant() {
    _l4_log "trust_grant: not yet implemented (Sprint 4B/4C)"
    return 99
}

# -----------------------------------------------------------------------------
# trust_record_override — TODO Sprint 4B.
# -----------------------------------------------------------------------------
trust_record_override() {
    _l4_log "trust_record_override: not yet implemented (Sprint 4B)"
    return 99
}

# -----------------------------------------------------------------------------
# trust_verify_chain — TODO Sprint 4C.
# -----------------------------------------------------------------------------
trust_verify_chain() {
    _l4_log "trust_verify_chain: not yet implemented (Sprint 4C)"
    return 99
}

# -----------------------------------------------------------------------------
# trust_disable — TODO Sprint 4D.
# -----------------------------------------------------------------------------
trust_disable() {
    _l4_log "trust_disable: not yet implemented (Sprint 4D)"
    return 99
}
