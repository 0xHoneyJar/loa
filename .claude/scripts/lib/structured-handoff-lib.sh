#!/usr/bin/env bash
# =============================================================================
# structured-handoff-lib.sh — L6 structured-handoff library.
#
# cycle-098 Sprint 6A (FR-L6-1, FR-L6-2, FR-L6-3, FR-L6-6, FR-L6-7).
#
# Public API (Sprint 6A):
#   handoff_write <yaml_path>          Validate + write handoff doc + index row
#   handoff_compute_id <yaml_path>     Print sha256:<hex> content-addressable id
#   handoff_list [--unread] [--to op]  Print INDEX rows (filtered)
#   handoff_read <handoff_id>          Print body
#
# Future sprints extend this lib:
#   6B: collision suffix + verify_operators (from/to vs OPERATORS.md)
#   6C: surface_unread_handoffs <op>   SessionStart hook entry
#   6D: same-machine fingerprint + [CROSS-HOST-REFUSED] guardrail
#
# Composes-with:
#   - lib/jcs.sh                       Canonical-JSON for handoff_id
#   - audit-envelope.sh                handoff.write audit event
#   - context-isolation-lib.sh         (Sprint 6C) sanitize_for_session_start
#   - operator-identity.sh             (Sprint 6B) verify_operators
#
# Trust boundary:
#   The handoff body is UNTRUSTED (operator-supplied text). This lib NEVER
#   interprets the body as instructions. Body sanitization happens in
#   context-isolation-lib.sh::sanitize_for_session_start at SURFACING time
#   (Sprint 6C), not at write time. At write time we only validate frontmatter
#   shape and slug-safety of filesystem path components.
#
# Pre-emptive hardening (Sprint 4+5 patterns):
#   - mktemp for ALL tmp-files (no ${path}.tmp.$$)
#   - realpath canonicalize handoffs_dir
#   - reject system paths (/etc /usr /proc /sys /dev /boot)
#   - bounds-check operator-controlled ts_utc (epoch..now+24h)
#   - flock everywhere shared state is mutated
# =============================================================================

set -euo pipefail

if [[ "${_LOA_STRUCTURED_HANDOFF_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_STRUCTURED_HANDOFF_SOURCED=1

_LOA_HANDOFF_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .claude/scripts/lib → .claude/scripts → .claude → REPO_ROOT
_LOA_HANDOFF_REPO_ROOT="$(cd "${_LOA_HANDOFF_DIR_LIB}/../../.." && pwd)"
_LOA_HANDOFF_FRONTMATTER_SCHEMA="${_LOA_HANDOFF_REPO_ROOT}/.claude/data/handoff-frontmatter.schema.json"
_LOA_HANDOFF_PAYLOAD_SCHEMA="${_LOA_HANDOFF_REPO_ROOT}/.claude/data/trajectory-schemas/handoff-events/handoff-write.payload.schema.json"
_LOA_HANDOFF_DEFAULT_DIR="${_LOA_HANDOFF_REPO_ROOT}/grimoires/loa/handoffs"
_LOA_HANDOFF_DEFAULT_LOG="${_LOA_HANDOFF_REPO_ROOT}/.run/handoff-events.jsonl"
_LOA_HANDOFF_FINGERPRINT_FILE="${_LOA_HANDOFF_REPO_ROOT}/.run/machine-fingerprint"
_LOA_HANDOFF_FINGERPRINT_HISTORY="${_LOA_HANDOFF_REPO_ROOT}/.run/machine-fingerprint.history.jsonl"
_LOA_HANDOFF_CROSS_HOST_STAGING="${_LOA_HANDOFF_REPO_ROOT}/.run/handoff-events.cross-host-staging.jsonl"

# -----------------------------------------------------------------------------
# Test-mode gate. cycle-098 follow-up #776 (CRIT-1 inheritance from sprint-7
# cypherpunk review): require BOTH `LOA_HANDOFF_TEST_MODE=1` AND a robust
# bats marker. Earlier draft permitted bypass via `BATS_TMPDIR` alone (any
# developer-leaked env or nested tooling could flip production into
# test-mode). Same regression-of-an-already-closed-pattern as cycle-099 #761
# (L4) and L7 sprint-7 CRIT-1. Strict form below; do not "or" the clauses.
# -----------------------------------------------------------------------------
_handoff_test_mode_active() {
    [[ "${LOA_HANDOFF_TEST_MODE:-0}" == "1" ]] || return 1
    [[ -n "${BATS_TEST_FILENAME:-}" ]] && return 0
    [[ -n "${BATS_VERSION:-}" ]] && return 0
    return 1
}

_handoff_check_env_override() {
    local var_name="$1" var_value="$2"
    if [[ -z "$var_value" ]]; then
        return 1
    fi
    if _handoff_test_mode_active; then
        return 0  # Honor in test mode.
    fi
    echo "[structured-handoff] WARNING: env override '$var_name' ignored in production (test-mode gate)" >&2
    return 1
}

# Source jcs.sh for canonical-JSON.
# shellcheck source=../../../lib/jcs.sh
source "${_LOA_HANDOFF_REPO_ROOT}/lib/jcs.sh"

# Source audit-envelope for emit. Idempotent guard handles re-source.
# shellcheck source=../audit-envelope.sh
source "${_LOA_HANDOFF_DIR_LIB}/../audit-envelope.sh"

# Sprint 6B: operator-identity for verify_operators. Soft-source — if absent,
# verify_operators behaves as "unknown" (warn-mode safe; strict-mode rejects).
if [[ -f "${_LOA_HANDOFF_DIR_LIB}/../operator-identity.sh" ]]; then
    # shellcheck source=../operator-identity.sh
    source "${_LOA_HANDOFF_DIR_LIB}/../operator-identity.sh"
fi

# -----------------------------------------------------------------------------
# _handoff_log — internal stderr logger.
# -----------------------------------------------------------------------------
_handoff_log() {
    # Sprint 6E (CYP-F12): strip C0 control bytes + DEL before printing so
    # operator-supplied content can't smuggle ANSI escape sequences through.
    local msg="$*"
    msg="$(printf '%s' "$msg" | tr -d '\000-\010\013-\037\177')"
    echo "[structured-handoff] $msg" >&2
}

# -----------------------------------------------------------------------------
# Machine-fingerprint guardrail (Sprint 6D — SDD §1.7.1 SKP-005)
# -----------------------------------------------------------------------------
# _handoff_compute_fingerprint — print the SHA-256 of (hostname || machine-id)
# Hostname read from `hostname` (POSIX standard).
# Machine-id read from /etc/machine-id (Linux) OR /var/lib/dbus/machine-id
# (Debian) OR `ioreg -rd1 -c IOPlatformExpertDevice` IOPlatformUUID (macOS).
# Fallback when none available: a stable hash of HOSTNAME alone (degraded —
# operator will see CROSS-HOST-REFUSED if container restart changes hostname).
# Tests inject via LOA_HANDOFF_FINGERPRINT_OVERRIDE.
# -----------------------------------------------------------------------------
_handoff_compute_fingerprint() {
    if _handoff_check_env_override LOA_HANDOFF_FINGERPRINT_OVERRIDE "${LOA_HANDOFF_FINGERPRINT_OVERRIDE:-}"; then
        printf '%s' "$LOA_HANDOFF_FINGERPRINT_OVERRIDE"
        return 0
    fi
    local host id
    host="$(hostname 2>/dev/null || echo "unknown-host")"
    if [[ -r /etc/machine-id ]]; then
        id="$(cat /etc/machine-id)"
    elif [[ -r /var/lib/dbus/machine-id ]]; then
        id="$(cat /var/lib/dbus/machine-id)"
    elif command -v ioreg >/dev/null 2>&1; then
        id="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F\" '/IOPlatformUUID/ {print $4; exit}')"
    fi
    [[ -z "${id:-}" ]] && id="hostname-only"
    printf '%s' "$(printf '%s|%s' "$host" "$id" | _audit_sha256)"
}

# _handoff_init_fingerprint — write .run/machine-fingerprint on first run.
# Idempotent: if file exists, no-op. Mode 0600.
_handoff_init_fingerprint() {
    local fpfile="$_LOA_HANDOFF_FINGERPRINT_FILE"
    if _handoff_check_env_override LOA_HANDOFF_FINGERPRINT_FILE "${LOA_HANDOFF_FINGERPRINT_FILE:-}"; then
        fpfile="$LOA_HANDOFF_FINGERPRINT_FILE"
    fi
    [[ -f "$fpfile" ]] && return 0

    mkdir -p "$(dirname "$fpfile")"
    local fp now
    fp="$(_handoff_compute_fingerprint)"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local writer; writer="${USER:-$(whoami 2>/dev/null || echo unknown)}@$(hostname 2>/dev/null || echo unknown)"

    local tmp; tmp="$(mktemp "${fpfile}.tmp.XXXXXX")"
    chmod 0600 "$tmp"
    jq -nc \
        --arg fp "$fp" \
        --arg ts "$now" \
        --arg writer "$writer" \
        '{fingerprint: $fp, first_seen_utc: $ts, writer_id_default: $writer}' > "$tmp"
    mv -f "$tmp" "$fpfile"
}

# _handoff_assert_same_machine — main guardrail entry called from handoff_write.
# Returns 0 if fingerprint matches (or no fingerprint file yet → initializes).
# Returns 6 (integrity) on mismatch + emits [CROSS-HOST-REFUSED] BLOCKER to
# the cross-host staging log (NOT the canonical chain — preserves origin's
# chain integrity).
#
# Honors LOA_HANDOFF_DISABLE_FINGERPRINT=1 (test-only escape hatch).
_handoff_assert_same_machine() {
    if [[ "${LOA_HANDOFF_DISABLE_FINGERPRINT:-0}" == "1" ]]; then
        if _handoff_test_mode_active; then
            return 0
        fi
        echo "[structured-handoff] WARNING: LOA_HANDOFF_DISABLE_FINGERPRINT=1 ignored in production (test-mode gate)" >&2
        # Fall through — proceed with fingerprint check.
    fi

    # File path env override is also test-mode gated.
    local fpfile="$_LOA_HANDOFF_FINGERPRINT_FILE"
    if _handoff_check_env_override LOA_HANDOFF_FINGERPRINT_FILE "${LOA_HANDOFF_FINGERPRINT_FILE:-}"; then
        fpfile="$LOA_HANDOFF_FINGERPRINT_FILE"
    fi
    local stage="$_LOA_HANDOFF_CROSS_HOST_STAGING"
    if _handoff_check_env_override LOA_HANDOFF_CROSS_HOST_STAGING "${LOA_HANDOFF_CROSS_HOST_STAGING:-}"; then
        stage="$LOA_HANDOFF_CROSS_HOST_STAGING"
    fi

    if [[ ! -f "$fpfile" ]]; then
        # First run — write the fingerprint and accept.
        _handoff_init_fingerprint
        return 0
    fi

    local stored current
    stored="$(jq -r '.fingerprint // ""' "$fpfile" 2>/dev/null || echo "")"
    current="$(_handoff_compute_fingerprint)"

    if [[ -z "$stored" ]]; then
        _handoff_log "machine-fingerprint file unparseable; refusing"
        return 6
    fi

    if [[ "$stored" == "$current" ]]; then
        return 0
    fi

    # Mismatch → emit [CROSS-HOST-REFUSED] BLOCKER to staging (NOT canonical).
    mkdir -p "$(dirname "$stage")"
    local now; now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    # Sprint 6E (CYP-F8): flock-guarded append + size warning. Two concurrent
    # cross-host attempts can race; without flock, JSONL line atomicity is
    # FS-dependent (PIPE_BUF on Linux but not portable). Size warn at 10MB
    # so a misconfigured CI doesn't fill disk silently.
    if command -v flock >/dev/null 2>&1; then
        local stage_lock="${stage}.lock"
        (
            flock -x -w 5 8 || exit 0
            jq -nc \
                --arg ts "$now" \
                --arg stored "$stored" \
                --arg current "$current" \
                '{event: "CROSS-HOST-REFUSED", ts_utc: $ts, expected_fingerprint: $stored, observed_fingerprint: $current, recovery_hint: "Multi-host operation is FU-6 (deferred). To migrate work to this machine, use /loa machine-fingerprint regenerate."}' \
                >> "$stage"
            local sz; sz="$(stat -c '%s' "$stage" 2>/dev/null || stat -f '%z' "$stage" 2>/dev/null || echo 0)"
            if (( sz > 10485760 )); then
                _handoff_log "[STAGING-SIZE-WARN] $stage exceeds 10MB ($sz bytes); rotate or investigate"
            fi
        ) 8>"$stage_lock"
    else
        # No flock available — best-effort append (single-machine guarantee
        # implies single PID, so race risk is bounded).
        jq -nc \
            --arg ts "$now" \
            --arg stored "$stored" \
            --arg current "$current" \
            '{event: "CROSS-HOST-REFUSED", ts_utc: $ts, expected_fingerprint: $stored, observed_fingerprint: $current, recovery_hint: "Multi-host operation is FU-6 (deferred). To migrate work to this machine, use /loa machine-fingerprint regenerate."}' \
            >> "$stage"
    fi

    _handoff_log "[CROSS-HOST-REFUSED] machine-fingerprint mismatch (stored=${stored:0:12}... current=${current:0:12}...). See $stage. BLOCKER."
    return 6
}

# -----------------------------------------------------------------------------
# _handoff_save_shell_opts / _handoff_restore_shell_opts — preserve caller's
# `set -e/-u/-o pipefail` state when this lib needs `set +e` internally.
# Pattern from cross-repo-status-lib (Sprint 5).
# -----------------------------------------------------------------------------
_handoff_save_shell_opts() {
    _LOA_HANDOFF_SAVED_OPTS="$-"
}
_handoff_restore_shell_opts() {
    if [[ -n "${_LOA_HANDOFF_SAVED_OPTS:-}" ]]; then
        case "$_LOA_HANDOFF_SAVED_OPTS" in *e*) set -e ;; *) set +e ;; esac
        case "$_LOA_HANDOFF_SAVED_OPTS" in *u*) set -u ;; *) set +u ;; esac
        unset _LOA_HANDOFF_SAVED_OPTS
    fi
}

# -----------------------------------------------------------------------------
# _handoff_resolve_dir [override] — return the absolute, canonicalized
# handoffs directory. Order: explicit override > LOA_HANDOFFS_DIR env >
# .loa.config.yaml::structured_handoff.handoffs_dir > default.
#
# Refuses paths that resolve to system roots (/etc /usr /proc /sys /dev /boot).
# -----------------------------------------------------------------------------
_handoff_resolve_dir() {
    local override="${1:-}"
    local raw=""

    if [[ -n "$override" ]]; then
        raw="$override"
    elif [[ -n "${LOA_HANDOFFS_DIR:-}" ]]; then
        raw="$LOA_HANDOFFS_DIR"
    elif command -v yq >/dev/null 2>&1 && [[ -f "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" ]]; then
        raw="$(yq '.structured_handoff.handoffs_dir // ""' "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" 2>/dev/null || echo "")"
    fi

    if [[ -z "$raw" || "$raw" == "null" ]]; then
        raw="$_LOA_HANDOFF_DEFAULT_DIR"
    fi

    # Make absolute relative to repo root.
    if [[ "$raw" != /* ]]; then
        raw="${_LOA_HANDOFF_REPO_ROOT}/${raw}"
    fi

    # mkdir -p, then realpath canonicalize.
    mkdir -p "$raw"
    local resolved
    resolved="$(cd "$raw" && pwd -P)"

    # System-path rejection.
    case "$resolved" in
        /etc|/etc/*|/usr|/usr/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/boot|/boot/*|/var|/var/*|/root|/root/*|/srv|/srv/*)
            _handoff_log "_handoff_resolve_dir: handoffs_dir refuses system path: $resolved"
            return 7
            ;;
    esac

    # Sprint 6E (CYP-F9): inverted allowlist — dest_dir MUST be under
    # repo root (or under a configured tmp dir for tests). Mirrors
    # cycle-099 sprint-1E.c.3 allowlist-tree-restriction pattern. Test-mode
    # honors $TMPDIR / /tmp prefix as a deliberate escape.
    local repo_real; repo_real="$(cd "$_LOA_HANDOFF_REPO_ROOT" && pwd -P)"
    if [[ "$resolved" != "$repo_real"/* ]] && [[ "$resolved" != "$repo_real" ]]; then
        if _handoff_test_mode_active; then
            case "$resolved" in
                /tmp/*|"${TMPDIR:-/tmp}"/*) ;;  # honor test tmp
                *)
                    _handoff_log "_handoff_resolve_dir: outside repo root and outside tmp (test-mode): $resolved"
                    return 7
                    ;;
            esac
        else
            _handoff_log "_handoff_resolve_dir: handoffs_dir must be under repo root in production: $resolved"
            return 7
        fi
    fi

    printf '%s' "$resolved"
}

# -----------------------------------------------------------------------------
# _handoff_validate_ts_utc <ts_utc>
# Bounds-check operator-supplied ts_utc:
#   - matches RFC 3339 UTC pattern (already enforced by JSON schema, double-check)
#   - >= 1970-01-01T00:00:00Z (epoch)
#   - <= now + 24h (clamp future-dating)
# Returns 0 on valid, 2 on out-of-bounds.
# -----------------------------------------------------------------------------
_handoff_validate_ts_utc() {
    local ts="$1"
    if [[ ! "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$ ]]; then
        _handoff_log "ts_utc malformed: $ts"
        return 2
    fi
    local ts_epoch now_epoch max_epoch
    ts_epoch="$(date -u -d "$ts" +%s 2>/dev/null || true)"
    if [[ -z "$ts_epoch" ]]; then
        # macOS BSD date fallback
        ts_epoch="$(LC_ALL=C date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${ts%.*}" +%s 2>/dev/null || true)"
        # Strip fractional seconds for BSD parser.
        if [[ -z "$ts_epoch" ]]; then
            ts_epoch="$(LC_ALL=C date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$(printf '%s' "$ts" | sed -E 's/\.[0-9]+Z$/Z/')" +%s 2>/dev/null || true)"
        fi
    fi
    if [[ -z "$ts_epoch" ]]; then
        _handoff_log "ts_utc unparseable: $ts"
        return 2
    fi
    now_epoch="$(date -u +%s)"
    max_epoch=$((now_epoch + 86400))
    if (( ts_epoch < 0 )); then
        _handoff_log "ts_utc before epoch: $ts"
        return 2
    fi
    if (( ts_epoch > max_epoch )); then
        _handoff_log "ts_utc more than 24h in the future: $ts"
        return 2
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _handoff_parse_doc <yaml_path>
# Split a handoff markdown-with-frontmatter doc into:
#   stdout: JSON object {schema_version,from,to,topic,ts_utc,handoff_id,
#                        references[],tags[],body}
# Frontmatter is YAML between two `---` lines. Body is everything after the
# second `---`.
# Exits non-zero on malformed input. Returns parsed JSON on stdout.
# -----------------------------------------------------------------------------
_handoff_parse_doc() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        _handoff_log "input not found: $path"
        return 2
    fi
    LOA_HANDOFF_INPUT_PATH="$path" python3 - <<'PY'
import json, os, re, sys

path = os.environ["LOA_HANDOFF_INPUT_PATH"]
with open(path, "r", encoding="utf-8") as f:
    raw = f.read()

# Frontmatter must start at byte 0 with '---' and a newline.
m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", raw, flags=re.DOTALL)
if not m:
    print("parse: missing frontmatter delimiters", file=sys.stderr)
    sys.exit(2)
fm_text, body = m.group(1), m.group(2)

try:
    import yaml
except ImportError:
    print("parse: PyYAML not installed (pip install PyYAML)", file=sys.stderr)
    sys.exit(3)

try:
    fm = yaml.safe_load(fm_text)
except yaml.YAMLError as exc:
    print(f"parse: YAML error: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(fm, dict):
    print("parse: frontmatter is not a mapping", file=sys.stderr)
    sys.exit(2)

# Defaults for optional list fields. references + tags must be arrays for
# canonicalization stability — coerce missing → [].
fm.setdefault("references", [])
fm.setdefault("tags", [])
# Strings, not None. Schema validation will reject other types.
for k in ("schema_version", "from", "to", "topic", "ts_utc"):
    if k in fm and fm[k] is None:
        fm[k] = ""

# Preserve body verbatim (FR-L6-7 + body is UNTRUSTED — no normalization).
out = {
    "schema_version": fm.get("schema_version", ""),
    "from": fm.get("from", ""),
    "to": fm.get("to", ""),
    "topic": fm.get("topic", ""),
    "ts_utc": fm.get("ts_utc", ""),
    "references": fm.get("references", []),
    "tags": fm.get("tags", []),
    "body": body,
}
if "handoff_id" in fm:
    out["handoff_id"] = fm["handoff_id"]

# Pass-through unknown frontmatter keys are REJECTED (schema additionalProperties:false)
known = {"schema_version", "handoff_id", "from", "to", "topic", "ts_utc",
         "references", "tags"}
unknown = [k for k in fm.keys() if k not in known]
if unknown:
    print(f"parse: unknown frontmatter keys: {sorted(unknown)}", file=sys.stderr)
    sys.exit(2)

# Sprint 6E (CYP-F2 cypherpunk remediation): defense-in-depth.
# JSONSchema regex with $ accepts trailing \n (Python re.$ matches before
# trailing newline). PyYAML safe_load("from: \"alice\\n\"") returns the literal
# "alice\n". Reject ANY control byte (C0 \x00-\x1f, plus DEL \x7f) in slug-shape
# fields so a forged frontmatter cannot inject INDEX rows by smuggling \n into
# from/to/topic/schema_version/handoff_id/ts_utc.
import re as _re
_control = _re.compile(r"[\x00-\x1f\x7f]")
_slug_fields = ("schema_version", "handoff_id", "from", "to", "topic", "ts_utc")
for _f in _slug_fields:
    _v = out.get(_f, "")
    if isinstance(_v, str) and _control.search(_v):
        print(f"parse: control byte in '{_f}' — refused", file=sys.stderr)
        sys.exit(2)
# Also scan references[] entries (preserved verbatim per FR-L6-7, but a
# control byte in a reference string would propagate into the rendered
# YAML and break parsers). Permit \t in the body (FR-L6-7 verbatim) but
# reject in frontmatter scalars.
for _r in out.get("references", []):
    if isinstance(_r, str) and _control.search(_r):
        print("parse: control byte in references[] — refused", file=sys.stderr)
        sys.exit(2)
for _t in out.get("tags", []):
    if isinstance(_t, str) and _control.search(_t):
        print("parse: control byte in tags[] — refused", file=sys.stderr)
        sys.exit(2)

sys.stdout.write(json.dumps(out, ensure_ascii=False))
PY
}

# -----------------------------------------------------------------------------
# _handoff_validate_frontmatter <frontmatter_json>
# Schema validation against handoff-frontmatter.schema.json. Strict
# additionalProperties:false. Excludes the "body" field (not part of
# frontmatter schema).
# -----------------------------------------------------------------------------
_handoff_validate_frontmatter() {
    local doc_json="$1"
    LOA_HANDOFF_DOC_JSON="$doc_json" \
    LOA_HANDOFF_FRONTMATTER_SCHEMA="$_LOA_HANDOFF_FRONTMATTER_SCHEMA" \
    python3 - <<'PY'
import json, os, sys

schema_path = os.environ["LOA_HANDOFF_FRONTMATTER_SCHEMA"]
with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)

doc = json.loads(os.environ["LOA_HANDOFF_DOC_JSON"])
fm = {k: v for k, v in doc.items() if k != "body"}

try:
    import jsonschema
except ImportError:
    print("validate: jsonschema not installed (pip install jsonschema)",
          file=sys.stderr)
    sys.exit(3)

validator = jsonschema.Draft202012Validator(schema)
errors = list(validator.iter_errors(fm))
if errors:
    for e in errors:
        path = "/".join(str(p) for p in e.absolute_path) or "(root)"
        print(f"frontmatter validation: {path}: {e.message}", file=sys.stderr)
    sys.exit(2)
PY
}

# -----------------------------------------------------------------------------
# _handoff_canonical_for_id <doc_json>
# Build the canonical content object that gets hashed for handoff_id.
# Excludes handoff_id (self-referential). Pipes through jcs_canonicalize
# (RFC 8785) for byte-deterministic output. Prints canonical bytes on stdout.
# -----------------------------------------------------------------------------
_handoff_canonical_for_id() {
    local doc_json="$1"
    local subset
    subset="$(printf '%s' "$doc_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = {k: d[k] for k in (
    "schema_version","from","to","topic","ts_utc",
    "references","tags","body",
) if k in d}
sys.stdout.write(json.dumps(out, ensure_ascii=False))
')"
    printf '%s' "$subset" | jcs_canonicalize
}

# -----------------------------------------------------------------------------
# handoff_compute_id <yaml_path>
# Print "sha256:<64-hex>" — content-addressable handoff_id.
# -----------------------------------------------------------------------------
handoff_compute_id() {
    local path="$1"
    local doc_json
    doc_json="$(_handoff_parse_doc "$path")" || return $?
    local canonical hex
    canonical="$(_handoff_canonical_for_id "$doc_json")" || return 1
    hex="$(printf '%s' "$canonical" | _audit_sha256)"
    printf 'sha256:%s' "$hex"
}

# -----------------------------------------------------------------------------
# _handoff_filename <doc_json>
# Compute the handoff filename component: <date>-<from>-<to>-<topic>.md
# where <date> is YYYY-MM-DD derived from ts_utc.
# Slug safety is already enforced by frontmatter schema regex on from/to/topic.
# -----------------------------------------------------------------------------
_handoff_filename() {
    local doc_json="$1"
    printf '%s' "$doc_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
date = d["ts_utc"][:10]
sys.stdout.write("{}-{}-{}-{}.md".format(date, d["from"], d["to"], d["topic"]))
'
}

# -----------------------------------------------------------------------------
# _handoff_resolve_collision <dir> <base_fname>
# Sprint 6B (FR-L6-4 + IMP-010 v1.1): same-day collision protocol.
# When base.md exists, return base-2.md; when base-2.md exists too, base-3.md;
# up to base-100.md. Caller MUST hold the INDEX.md flock during this call —
# otherwise two writers could pick the same suffix.
#
# Returns the chosen basename on stdout. Exits non-zero (7) if all 100 slots
# are taken (operator must intervene).
# -----------------------------------------------------------------------------
_handoff_resolve_collision() {
    local dir="$1" base="$2"
    if [[ ! -e "${dir}/${base}" ]]; then
        printf '%s' "$base"
        return 0
    fi
    local stem="${base%.md}"
    local i=2
    while (( i <= 100 )); do
        local cand="${stem}-${i}.md"
        if [[ ! -e "${dir}/${cand}" ]]; then
            printf '%s' "$cand"
            return 0
        fi
        i=$((i + 1))
    done
    _handoff_log "_handoff_resolve_collision: 100+ collisions for $base in $dir"
    return 7
}

# -----------------------------------------------------------------------------
# _handoff_atomic_publish <handoffs_dir> <doc_json> <id> <from> <to> <topic> <ts>
# Sprint 6B: combined critical section that under ONE flock:
#   1. Reads existing INDEX.md (or seeds header)
#   2. Resolves filename collision (numeric suffix)
#   3. Writes body to mktemp + renames to chosen filename
#   4. Appends INDEX row (with chosen filename) + renames INDEX
#
# Prints the chosen basename to stdout for the caller to use in audit emit.
# Exit codes: 0 ok, 4 concurrency (flock), 7 collision-exhausted.
# -----------------------------------------------------------------------------
_handoff_atomic_publish() {
    local dir="$1" doc_json="$2" id="$3" from="$4" to="$5" topic="$6" ts="$7"
    local index="${dir}/INDEX.md"
    local lock="${dir}/.INDEX.md.lock"

    if ! command -v flock >/dev/null 2>&1; then
        _handoff_log "_handoff_atomic_publish: flock required (CC-3)"
        return 4
    fi

    local base; base="$(_handoff_filename "$doc_json")"

    # Tempfiles allocated up-front in same dir → same filesystem rename atomicity.
    local index_tmp body_tmp
    index_tmp="$(mktemp "${dir}/.INDEX.md.tmp.XXXXXX")"
    chmod 0644 "$index_tmp"
    body_tmp="$(mktemp "${dir}/.handoff.tmp.XXXXXX")"
    chmod 0644 "$body_tmp"

    # Critical section.
    (
        # Sprint 6E (BB-F6): caller's set -e state may be off (bats `run`
        # disables it). Explicitly re-enable inside the subshell so ERR
        # trap fires on any failed command.
        set -e
        flock -x -w 30 9 || { _handoff_log "flock timeout on $lock"; exit 4; }

        # Sprint 6E (MEDIUM-1): idempotency check by handoff_id. If the same
        # content (same id) was already published, return the existing file
        # path without writing anything new. Defends against a fail-and-retry
        # path that would otherwise create duplicate INDEX rows.
        if [[ -f "$index" ]]; then
            local existing
            existing="$(awk -v id="$id" -F' *\\| *' '$2 == id { print $3; exit }' "$index" 2>/dev/null || true)"
            if [[ -n "$existing" ]]; then
                printf '%s' "$existing"
                exit 0
            fi
        fi

        # 1. Resolve collision (must be inside flock; no other writer can race).
        local chosen
        chosen="$(_handoff_resolve_collision "$dir" "$base")" || exit 7
        local dest="${dir}/${chosen}"

        # 2. Write body to body_tmp via Python (same renderer as Sprint 6A).
        LOA_HANDOFF_DOC_JSON="$doc_json" python3 - > "$body_tmp" <<'PY'
import json, os, sys
d = json.loads(os.environ["LOA_HANDOFF_DOC_JSON"])
out = []
out.append("---")
key_order = ["schema_version", "handoff_id", "from", "to", "topic", "ts_utc", "references", "tags"]
for k in key_order:
    if k not in d:
        continue
    v = d[k]
    if isinstance(v, list):
        if not v:
            out.append("{}: []".format(k))
        else:
            out.append("{}:".format(k))
            for item in v:
                s = str(item).replace("'", "''")
                out.append("  - '{}'".format(s))
    else:
        s = str(v).replace("'", "''")
        out.append("{}: '{}'".format(k, s))
out.append("---")
out.append("")
out.append(d.get("body", ""))
sys.stdout.write("\n".join(out))
PY

        # 3. Rename body to chosen path (same filesystem → atomic).
        mv -f "$body_tmp" "$dest"

        # 4. Build new INDEX content.
        if [[ -f "$index" ]]; then
            if ! cat "$index" > "$index_tmp"; then
                rm -f "$dest"
                _handoff_log "atomic_publish: failed to read existing INDEX"
                exit 4
            fi
            # Sprint 6E (MEDIUM-7): direct shell newline test, no od pipeline.
            local _last; _last="$(tail -c 1 "$index_tmp")"
            [[ -s "$index_tmp" ]] && [[ "$_last" != $'\n' ]] && printf '\n' >> "$index_tmp"
        else
            cat > "$index_tmp" <<'HEADER'
# Handoff Index

| handoff_id | file | from | to | topic | ts_utc | read_by |
|------------|------|------|----|----|--------|---------|
HEADER
        fi
        printf '| %s | %s | %s | %s | %s | %s |  |\n' \
            "$id" "$chosen" "$from" "$to" "$topic" "$ts" >> "$index_tmp"

        # 5. Rename INDEX (atomic).
        # Sprint 6E (CYP-F6): explicit rollback when INDEX rename fails.
        # The prior `trap ... ERR` approach proved fragile under bats `run`
        # (set -e state inheritance is environment-dependent). Inline the
        # rollback so the all-or-nothing invariant holds regardless of
        # caller shell-options state.
        if ! mv -f "$index_tmp" "$index"; then
            rm -f "$dest"
            _handoff_log "atomic_publish: INDEX rename failed; body rolled back"
            exit 4
        fi

        # Emit chosen basename for caller capture.
        printf '%s' "$chosen"
    ) 9>"$lock"

    local rc=$?
    # Clean up any leftover tempfiles.
    [[ -e "$index_tmp" ]] && rm -f "$index_tmp"
    [[ -e "$body_tmp" ]] && rm -f "$body_tmp"
    return $rc
}

# -----------------------------------------------------------------------------
# _handoff_should_verify_operators
# Sprint 6B: read .loa.config.yaml::structured_handoff.verify_operators.
# Default: true (per SDD §5.13). Honors LOA_HANDOFF_VERIFY_OPERATORS env
# override (1=on, 0=off) for tests.
# Returns 0 (verify) or 1 (skip).
# -----------------------------------------------------------------------------
_handoff_should_verify_operators() {
    if _handoff_check_env_override LOA_HANDOFF_VERIFY_OPERATORS "${LOA_HANDOFF_VERIFY_OPERATORS:-}"; then
        [[ "$LOA_HANDOFF_VERIFY_OPERATORS" == "1" ]] && return 0 || return 1
    fi
    if command -v yq >/dev/null 2>&1 && [[ -f "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" ]]; then
        local v
        v="$(yq '.structured_handoff.verify_operators // true' "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" 2>/dev/null || echo "true")"
        [[ "$v" == "true" ]] && return 0 || return 1
    fi
    return 0  # default true
}

# -----------------------------------------------------------------------------
# _handoff_schema_mode
# Sprint 6B: read .loa.config.yaml::structured_handoff.schema_mode.
# "strict" | "warn"; default "strict" (SDD §5.13). Honors LOA_HANDOFF_SCHEMA_MODE.
# Echoes the chosen mode on stdout.
# -----------------------------------------------------------------------------
_handoff_schema_mode() {
    if _handoff_check_env_override LOA_HANDOFF_SCHEMA_MODE "${LOA_HANDOFF_SCHEMA_MODE:-}"; then
        printf '%s' "$LOA_HANDOFF_SCHEMA_MODE"
        return 0
    fi
    if command -v yq >/dev/null 2>&1 && [[ -f "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" ]]; then
        local v
        v="$(yq '.structured_handoff.schema_mode // "strict"' "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" 2>/dev/null || echo "strict")"
        printf '%s' "$v"
        return 0
    fi
    printf 'strict'
}

# -----------------------------------------------------------------------------
# _handoff_verify_operator_state <slug>
# Sprint 6B: wrap operator_identity_verify into a state string for the audit
# payload. Emits one of: verified | unverified | unknown | disabled.
#
# When operator-identity.sh is not sourced (lib unavailable), returns "unknown".
# -----------------------------------------------------------------------------
_handoff_verify_operator_state() {
    local slug="$1"
    if ! declare -F operator_identity_verify >/dev/null 2>&1; then
        printf 'bootstrap-pending'
        return 0
    fi
    # Sprint 6E (HIGH-2): if OPERATORS.md is absent, return bootstrap-pending
    # rather than "unknown" so strict-mode can permit the write (mirrors
    # audit-envelope BOOTSTRAP-PENDING gate). An empty/un-authored OPERATORS.md
    # is a deployment-time configuration state, not an attack signal.
    local op_file="${LOA_OPERATORS_FILE:-${_LOA_HANDOFF_REPO_ROOT}/grimoires/loa/operators.md}"
    if [[ ! -f "$op_file" ]]; then
        printf 'bootstrap-pending'
        return 0
    fi
    local rc
    operator_identity_verify "$slug" >/dev/null 2>&1 || rc=$?
    rc="${rc:-0}"
    case "$rc" in
        0) printf 'verified' ;;
        1) printf 'unverified' ;;
        2) printf 'unknown' ;;
        *) printf 'unknown' ;;
    esac
}

# -----------------------------------------------------------------------------
# _handoff_resolve_verification <from> <to>
# Sprint 6B: combined verification gate.
# Returns:
#   stdout: "from_state to_state combined_state" (space-separated)
#   exit 0 = pass (warn-mode always passes; strict-mode passes only on verified)
#   exit 3 = strict-mode auth failure
# -----------------------------------------------------------------------------
_handoff_resolve_verification() {
    local from="$1" to="$2"
    if ! _handoff_should_verify_operators; then
        printf 'disabled disabled disabled'
        return 0
    fi
    local from_state to_state
    from_state="$(_handoff_verify_operator_state "$from")"
    to_state="$(_handoff_verify_operator_state "$to")"

    local mode; mode="$(_handoff_schema_mode)"
    local combined
    if [[ "$from_state" == "verified" && "$to_state" == "verified" ]]; then
        combined="verified"
    elif [[ "$from_state" == "bootstrap-pending" && "$to_state" == "bootstrap-pending" ]]; then
        # Sprint 6E (HIGH-2): both states bootstrap-pending → OPERATORS.md
        # not yet authored. Treat permissively in strict mode so a fresh
        # install isn't blocked from its first handoff.
        combined="bootstrap-pending"
    elif [[ "$from_state" == "unverified" || "$to_state" == "unverified" ]]; then
        combined="unverified"
    else
        combined="unknown"
    fi

    printf '%s %s %s' "$from_state" "$to_state" "$combined"

    if [[ "$mode" == "strict" ]]; then
        case "$combined" in
            verified|bootstrap-pending) ;;  # accept
            *)
                _handoff_log "verify_operators: strict-mode reject (from=$from_state to=$to_state combined=$combined)"
                return 3
                ;;
        esac
    fi
    return 0
}

# -----------------------------------------------------------------------------
# (Legacy 6A function — kept for the CLI single-shot path; production writes
# go through _handoff_atomic_publish in 6B.)
# _handoff_atomic_write_body <dest_path> <doc_json> <original_input>
# Re-emit the handoff document with handoff_id pinned in frontmatter, atomically.
# Pattern: write to mktemp in dest dir → rename.
# -----------------------------------------------------------------------------
_handoff_atomic_write_body() {
    local dest="$1" doc_json="$2" original="$3"
    local dir; dir="$(dirname "$dest")"
    local tmp
    tmp="$(mktemp "${dir}/.handoff.tmp.XXXXXX")"
    chmod 0644 "$tmp"

    # Re-render: frontmatter (with handoff_id) + body verbatim.
    LOA_HANDOFF_DOC_JSON="$doc_json" python3 - > "$tmp" <<'PY'
import json, os, sys
d = json.loads(os.environ["LOA_HANDOFF_DOC_JSON"])
out = []
out.append("---")
# Stable frontmatter key order for human readability:
key_order = ["schema_version", "handoff_id", "from", "to", "topic", "ts_utc", "references", "tags"]
for k in key_order:
    if k not in d:
        continue
    v = d[k]
    if isinstance(v, list):
        if not v:
            out.append(f"{k}: []")
        else:
            out.append(f"{k}:")
            for item in v:
                # YAML-safe string (block-scalar of single-quoted form).
                s = str(item).replace("'", "''")
                out.append(f"  - '{s}'")
    else:
        s = str(v).replace("'", "''")
        out.append(f"{k}: '{s}'")
out.append("---")
out.append("")
out.append(d.get("body", ""))
sys.stdout.write("\n".join(out))
PY

    mv -f "$tmp" "$dest"
}

# -----------------------------------------------------------------------------
# handoff_write <yaml_path> [--handoffs-dir <path>]
#
# Validate + write a handoff document. Steps:
#   1. Parse frontmatter+body
#   2. Schema-validate frontmatter (strict)
#   3. Bounds-check ts_utc
#   4. Compute content-addressable handoff_id
#   5. Cross-check supplied handoff_id (if any) matches computed
#   6. Resolve dest dir (system-path rejection)
#   7. Compute file basename: <date>-<from>-<to>-<topic>.md
#   8. Refuse if dest file already exists (collision handled in Sprint 6B)
#   9. Atomically write handoff body
#  10. Atomically update INDEX.md (flock + rename)
#  11. Emit handoff.write audit event
#
# Stdout: JSON object {handoff_id, file_path, ts_utc}
# Stderr: progress + error messages
# Exit codes (per SDD §6.1):
#   0 ok
#   2 validation
#   3 authorization (deferred to 6B/6D)
#   4 concurrency (flock fail)
#   6 integrity (computed != supplied id)
#   7 configuration (system-path rejection / dest collision in 6A)
# -----------------------------------------------------------------------------
handoff_write() {
    local yaml_path=""
    local handoffs_dir_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --handoffs-dir) handoffs_dir_override="$2"; shift 2 ;;
            -*) _handoff_log "handoff_write: unknown flag '$1'"; return 2 ;;
            *)
                if [[ -z "$yaml_path" ]]; then yaml_path="$1"
                else _handoff_log "handoff_write: extra arg '$1'"; return 2; fi
                shift
                ;;
        esac
    done
    if [[ -z "$yaml_path" ]]; then
        _handoff_log "handoff_write: usage: handoff_write <yaml_path> [--handoffs-dir <path>]"
        return 2
    fi

    # Sprint 6D: same-machine guardrail. Refuses cross-host writes BEFORE
    # parsing the doc (no point validating content the host can't publish).
    _handoff_assert_same_machine || return $?

    # Step 1: parse.
    local doc_json
    doc_json="$(_handoff_parse_doc "$yaml_path")" || return 2

    # Step 2: schema-validate frontmatter.
    _handoff_validate_frontmatter "$doc_json" || return 2

    # Step 3: ts_utc bounds.
    local ts; ts="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["ts_utc"])')"
    _handoff_validate_ts_utc "$ts" || return 2

    # Step 4: compute id.
    local canonical hex computed_id
    canonical="$(_handoff_canonical_for_id "$doc_json")" || return 1
    hex="$(printf '%s' "$canonical" | _audit_sha256)"
    computed_id="sha256:${hex}"

    # Step 5: cross-check supplied id.
    local supplied_id
    supplied_id="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("handoff_id",""))')"
    if [[ -n "$supplied_id" && "$supplied_id" != "$computed_id" ]]; then
        _handoff_log "handoff_id mismatch: supplied=$supplied_id computed=$computed_id"
        return 6
    fi

    # Pin computed id back into doc_json for re-emit.
    doc_json="$(printf '%s' "$doc_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d["handoff_id"] = "'"$computed_id"'"
sys.stdout.write(json.dumps(d, ensure_ascii=False))
')"

    # Step 6: resolve dest dir.
    local dest_dir
    dest_dir="$(_handoff_resolve_dir "$handoffs_dir_override")" || return 7

    # Extract from/to/topic for verification + publish.
    local from to topic
    from="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["from"])')"
    to="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["to"])')"
    topic="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["topic"])')"

    # Step 7 (Sprint 6B): operator verification.
    local verif_states verif_rc=0
    verif_states="$(_handoff_resolve_verification "$from" "$to")" || verif_rc=$?
    if [[ "$verif_rc" -ne 0 ]]; then
        return "$verif_rc"
    fi
    # Parse "from_state to_state combined_state".
    local from_state to_state combined_state
    read -r from_state to_state combined_state <<< "$verif_states"

    # Step 8+9+10 (Sprint 6B): combined critical section under one flock —
    # collision-resolve + body write + INDEX update.
    local chosen_fname pub_rc
    # Sprint 6E (bash gotcha): `local pub_rc=$?` would lose the rc because
    # `local` returns 0. Split declaration from capture.
    chosen_fname="$(_handoff_atomic_publish "$dest_dir" "$doc_json" "$computed_id" "$from" "$to" "$topic" "$ts")" || pub_rc=$?
    pub_rc="${pub_rc:-0}"
    if [[ "$pub_rc" -ne 0 ]]; then
        _handoff_log "handoff_write: publish failed (rc=$pub_rc)"
        return "$pub_rc"
    fi
    local dest="${dest_dir}/${chosen_fname}"

    # Step 11: emit audit event.
    local rel_path="${dest#${_LOA_HANDOFF_REPO_ROOT}/}"
    local refs_count tags_json body_size
    refs_count="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("references",[])))')"
    tags_json="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(json.load(sys.stdin).get("tags",[]),ensure_ascii=False))')"
    body_size="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; b=json.load(sys.stdin).get("body",""); print(len(b.encode("utf-8")))')"

    # Sprint 6E (CYP-F5): propagate doc's schema_version, not hardcoded "1.0",
    # so a future v1.1 doc emits a faithful audit payload.
    local doc_sv
    doc_sv="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("schema_version",""))')"
    local payload
    payload="$(jq -nc \
        --arg id "$computed_id" \
        --arg from "$from" \
        --arg to "$to" \
        --arg topic "$topic" \
        --arg ts "$ts" \
        --arg fp "$rel_path" \
        --arg sv "$doc_sv" \
        --arg verif "$combined_state" \
        --argjson refs "$refs_count" \
        --argjson tags "$tags_json" \
        --argjson bsz "$body_size" \
        '{
            handoff_id: $id,
            from: $from,
            to: $to,
            topic: $topic,
            ts_utc: $ts,
            file_path: $fp,
            schema_version: $sv,
            references_count: $refs,
            tags: $tags,
            body_byte_size: $bsz,
            operator_verification: $verif
        }')"

    local log_path="$_LOA_HANDOFF_DEFAULT_LOG"
    if _handoff_check_env_override LOA_HANDOFF_LOG "${LOA_HANDOFF_LOG:-}"; then
        log_path="$LOA_HANDOFF_LOG"
    fi
    mkdir -p "$(dirname "$log_path")"
    if ! audit_emit "L6" "handoff.write" "$payload" "$log_path" >/dev/null; then
        _handoff_log "handoff_write: audit_emit failed (handoff written but unaudited)"
        return 1
    fi

    # Stdout result for caller.
    jq -nc \
        --arg id "$computed_id" \
        --arg fp "$rel_path" \
        --arg ts "$ts" \
        '{handoff_id: $id, file_path: $fp, ts_utc: $ts}'
}

# -----------------------------------------------------------------------------
# handoff_list [--unread] [--to <operator>] [--handoffs-dir <path>]
# Print INDEX.md table rows (optionally filtered). Empty output when INDEX
# absent or no matches.
# -----------------------------------------------------------------------------
handoff_list() {
    local unread_only=0 to_filter="" handoffs_dir_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unread) unread_only=1; shift ;;
            --to) to_filter="$2"; shift 2 ;;
            --handoffs-dir) handoffs_dir_override="$2"; shift 2 ;;
            *) _handoff_log "handoff_list: unknown flag '$1'"; return 2 ;;
        esac
    done

    local dir; dir="$(_handoff_resolve_dir "$handoffs_dir_override")" || return 7
    local index="${dir}/INDEX.md"
    [[ -f "$index" ]] || return 0

    awk -v unread="$unread_only" -v tf="$to_filter" '
        BEGIN {
            FS=" *\\| *"
            # Sprint 6E (CYP-F7): pin filename-column shape.
            file_re = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+(-[0-9]+)?\\.md$"
            id_re   = "^sha256:[a-f0-9]{64}$"
        }
        /^\| sha256:/ {
            if ($2 !~ id_re)   next
            if ($3 !~ file_re) next
            if (tf != "" && $5 != tf) next
            if (unread == 1 && $8 != "" ) next
            print
        }
    ' "$index"
}

# -----------------------------------------------------------------------------
# handoff_read <handoff_id> [--handoffs-dir <path>]
# Print the body of a handoff (frontmatter excluded). Looks up file via INDEX.
# -----------------------------------------------------------------------------
handoff_read() {
    local id="$1"; shift || true
    local handoffs_dir_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --handoffs-dir) handoffs_dir_override="$2"; shift 2 ;;
            *) _handoff_log "handoff_read: unknown flag '$1'"; return 2 ;;
        esac
    done

    if [[ -z "$id" ]]; then
        _handoff_log "handoff_read: usage: handoff_read <handoff_id>"
        return 2
    fi

    local dir; dir="$(_handoff_resolve_dir "$handoffs_dir_override")" || return 7
    local index="${dir}/INDEX.md"
    if [[ ! -f "$index" ]]; then
        _handoff_log "handoff_read: INDEX.md absent at $index"
        return 2
    fi

    # Sprint 6E (CYP-F15): require id to match content-addressable shape
    # before parsing INDEX. Defends against forged callers passing junk.
    if [[ ! "$id" =~ ^sha256:[a-f0-9]{64}$ ]]; then
        _handoff_log "handoff_read: invalid handoff_id shape"
        return 2
    fi

    # Find file basename for this id.
    local file
    file="$(awk -v id="$id" '
        BEGIN {
            FS=" *\\| *"
            file_re = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+(-[0-9]+)?\\.md$"
        }
        $2 == id && $3 ~ file_re { print $3; exit }
    ' "$index")"

    if [[ -z "$file" ]]; then
        _handoff_log "handoff_read: id not in INDEX: $id"
        return 2
    fi

    local path="${dir}/${file}"
    if [[ ! -f "$path" ]]; then
        _handoff_log "handoff_read: file missing on disk: $path"
        return 2
    fi

    # Strip frontmatter — print body only.
    awk '
        BEGIN { in_fm=0; past=0 }
        /^---[[:space:]]*$/ {
            if (past==0 && in_fm==0) { in_fm=1; next }
            if (in_fm==1) { in_fm=0; past=1; next }
        }
        past==1 { print }
    ' "$path"
}

# -----------------------------------------------------------------------------
# surface_unread_handoffs <operator_id> [--handoffs-dir <path>] [--max-bytes N]
#
# Sprint 6C (FR-L6-5): SessionStart hook entry. Reads INDEX.md, filters
# unread handoffs to <operator_id>, reads each body, sanitizes via
# context-isolation-lib.sh::sanitize_for_session_start("L6", body),
# and emits a framed banner block on stdout. Read-only — does NOT mark
# handoffs as read (operator/skill calls handoff_mark_read explicitly).
#
# Trust boundary: every body passes through Layer 1+2 sanitization before
# reaching session context. The banner explicitly states that the
# enclosed content is descriptive, not instructional.
#
# Output (when 1+ unread handoffs):
#   [L6 Unread handoffs to: <operator_id>]
#   <untrusted-content source="L6" path="...">
#   <sanitized body>
#   </untrusted-content>
#   ... (repeated per handoff)
#
# Output (when none): empty. Exit 0.
#
# Args:
#   $1                  operator_id (required)
#   --handoffs-dir P    override default handoffs dir
#   --max-bytes N       per-handoff body byte cap (default: SDD §5.13
#                       structured_handoff.surface_max_chars or 4000)
# -----------------------------------------------------------------------------
surface_unread_handoffs() {
    local op="${1:-}"; shift || true
    local handoffs_dir_override=""
    local max_chars=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --handoffs-dir) handoffs_dir_override="$2"; shift 2 ;;
            --max-bytes) max_chars="$2"; shift 2 ;;
            *) _handoff_log "surface_unread_handoffs: unknown flag '$1'"; return 2 ;;
        esac
    done
    if [[ -z "$op" ]]; then
        _handoff_log "surface_unread_handoffs: missing <operator_id>"
        return 2
    fi
    # Slug shape (matches frontmatter regex).
    if [[ ! "$op" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
        _handoff_log "surface_unread_handoffs: invalid operator slug shape"
        return 2
    fi

    # Resolve max_chars: explicit flag > config > default 4000.
    if [[ -z "$max_chars" ]]; then
        if command -v yq >/dev/null 2>&1 && [[ -f "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" ]]; then
            max_chars="$(yq '.structured_handoff.surface_max_chars // 4000' "${_LOA_HANDOFF_REPO_ROOT}/.loa.config.yaml" 2>/dev/null || echo 4000)"
        else
            max_chars=4000
        fi
    fi

    local dir; dir="$(_handoff_resolve_dir "$handoffs_dir_override")" || return 7
    local index="${dir}/INDEX.md"
    [[ -f "$index" ]] || return 0  # No INDEX → no surfaced handoffs.

    # Source context-isolation-lib for sanitize_for_session_start. Soft-source.
    if ! declare -F sanitize_for_session_start >/dev/null 2>&1; then
        if [[ -f "${_LOA_HANDOFF_DIR_LIB}/context-isolation-lib.sh" ]]; then
            # shellcheck source=context-isolation-lib.sh
            source "${_LOA_HANDOFF_DIR_LIB}/context-isolation-lib.sh"
        fi
    fi
    if ! declare -F sanitize_for_session_start >/dev/null 2>&1; then
        _handoff_log "surface_unread_handoffs: context-isolation-lib not available"
        return 1
    fi

    # Filter unread for operator_id. INDEX format:
    # | id | file | from | to | topic | ts_utc | read_by |
    # read_by is comma-separated "<op>:<ts>" entries; "unread for op"
    # means op's slug not present in read_by.
    local unread_lines
    unread_lines="$(awk -F' *\\| *' -v op="$op" '
        BEGIN {
            id_re   = "^sha256:[a-f0-9]{64}$"
            # Sprint 6E (CYP-F7): pin filename shape.
            file_re = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+(-[0-9]+)?\\.md$"
        }
        $2 ~ id_re && $3 ~ file_re && $5 == op {
            # read_by is field 8 — empty when nobody has read.
            rb = $8
            sub(/^[[:space:]]+/, "", rb)
            sub(/[[:space:]]+$/, "", rb)
            if (rb == "" || index(","rb",", ","op":") == 0) {
                print
            }
        }
    ' "$index")"

    [[ -n "$unread_lines" ]] || return 0

    # Header banner (only emitted when there is content).
    printf '[L6 Unread handoffs to: %s]\n' "$op"

    # Iterate; sanitize + frame each body.
    local seen=0
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        local file
        file="$(printf '%s' "$row" | awk -F' *\\| *' '{print $3}')"
        local rel_path="${dir#${_LOA_HANDOFF_REPO_ROOT}/}/${file}"
        local body_path="${dir}/${file}"
        if [[ ! -f "$body_path" ]]; then
            _handoff_log "surface: file missing on disk: $body_path"
            continue
        fi
        # Extract body via the same awk pattern as handoff_read.
        local body
        body="$(awk '
            BEGIN { in_fm=0; past=0 }
            /^---[[:space:]]*$/ {
                if (past==0 && in_fm==0) { in_fm=1; next }
                if (in_fm==1) { in_fm=0; past=1; next }
            }
            past==1 { print }
        ' "$body_path")"

        # Sprint 6E (MEDIUM-2 + CYP-F11): write body to a same-dir tempfile
        # and pass the path to sanitize_for_session_start so its native
        # path-label branch handles attribute escaping. Eliminates the prior
        # sed post-process which broke on dest_dir paths containing `<` or
        # control bytes. We then post-process to override the temp path with
        # the canonical handoff file path for operator legibility, escaping
        # any HTML-attribute-special characters first.
        local body_tmp_for_sanitize
        body_tmp_for_sanitize="$(mktemp "${dir}/.surface-body.tmp.XXXXXX")"
        printf '%s' "$body" > "$body_tmp_for_sanitize"
        # HTML-attribute-safe rel_path: drop control bytes + escape special chars.
        local path_safe
        path_safe="$(printf '%s' "$rel_path" | tr -d '\000-\037\177' \
            | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
        # Escape sed-replacement metacharacters in path_safe before using it
        # in the substitution (& and \ are special on the RHS of s|||).
        local path_sed
        path_sed="$(printf '%s' "$path_safe" | sed -e 's/[\\&|]/\\&/g')"
        sanitize_for_session_start "L6" "$body_tmp_for_sanitize" --max-chars "$max_chars" \
            | sed -e "s|path=\"${body_tmp_for_sanitize}\"|path=\"${path_sed}\"|"
        rm -f "$body_tmp_for_sanitize"
        printf '\n'
        seen=$((seen + 1))
    done <<< "$unread_lines"

    # Optional: emit audit event for surfacing (suppress under env flag).
    local _suppress_audit=0
    if [[ "${LOA_HANDOFF_SUPPRESS_SURFACE_AUDIT:-0}" == "1" ]] && _handoff_test_mode_active; then
        _suppress_audit=1
    fi
    if [[ "$_suppress_audit" -eq 0 ]]; then
        local op_state; op_state="$(_handoff_verify_operator_state "$op" 2>/dev/null || echo "unknown")"
        local payload
        payload="$(jq -nc \
            --arg op "$op" \
            --arg sv "1.0" \
            --argjson cnt "$seen" \
            --arg ostate "$op_state" \
            '{
                operator_id: $op,
                schema_version: $sv,
                handoffs_surfaced: $cnt,
                operator_verification: $ostate,
                event_subtype: "surface"
            }')"
        local log_path="$_LOA_HANDOFF_DEFAULT_LOG"
        if _handoff_check_env_override LOA_HANDOFF_LOG "${LOA_HANDOFF_LOG:-}" 2>/dev/null; then
            log_path="$LOA_HANDOFF_LOG"
        fi
        mkdir -p "$(dirname "$log_path")"
        audit_emit "L6" "handoff.surface" "$payload" "$log_path" >/dev/null 2>&1 || true
    fi

    return 0
}

# -----------------------------------------------------------------------------
# handoff_mark_read <handoff_id> <operator_id> [--handoffs-dir <path>]
#
# Sprint 6C: append "<op>:<ts>" to read_by column for the matching INDEX row.
# Atomic via flock. No-op when already marked.
# -----------------------------------------------------------------------------
handoff_mark_read() {
    local id="${1:-}"; shift || true
    local op="${1:-}"; shift || true
    local handoffs_dir_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --handoffs-dir) handoffs_dir_override="$2"; shift 2 ;;
            *) _handoff_log "handoff_mark_read: unknown flag '$1'"; return 2 ;;
        esac
    done
    if [[ -z "$id" || -z "$op" ]]; then
        _handoff_log "handoff_mark_read: usage: handoff_mark_read <id> <operator>"
        return 2
    fi
    if [[ ! "$op" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
        _handoff_log "handoff_mark_read: invalid operator slug"
        return 2
    fi

    local dir; dir="$(_handoff_resolve_dir "$handoffs_dir_override")" || return 7
    local index="${dir}/INDEX.md"
    [[ -f "$index" ]] || { _handoff_log "INDEX.md absent"; return 2; }

    if ! command -v flock >/dev/null 2>&1; then
        _handoff_log "handoff_mark_read: flock required"
        return 4
    fi

    # Sprint 6E (HIGH-1): also require id-shape on the requested id.
    if [[ ! "$id" =~ ^sha256:[a-f0-9]{64}$ ]]; then
        _handoff_log "handoff_mark_read: invalid handoff_id shape"
        return 2
    fi

    local lock="${dir}/.INDEX.md.lock"
    local now; now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local tmp
    tmp="$(mktemp "${dir}/.INDEX.md.tmp.XXXXXX")"
    chmod 0644 "$tmp"

    # Sprint 6E (HIGH-1): capture already_marked status for audit emit. Done
    # outside the awk pass so we can include it in the handoff.mark_read event.
    local already_marked
    already_marked="$(awk -F' *\\| *' -v id="$id" -v op="$op" '
        BEGIN { found="false" }
        $2 == id {
            rb = $8
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", rb)
            if (index(","rb",", ","op":") != 0) found="true"
        }
        END { print found }
    ' "$index")"

    (
        flock -x -w 30 9 || { _handoff_log "flock timeout"; exit 4; }
        # Append "$op:$now" to read_by (field 8) for the row whose id matches.
        awk -F' *\\| *' -v OFS=' | ' -v id="$id" -v op="$op" -v ts="$now" '
            BEGIN {
                matched=0
                # Sprint 6E (CYP-F7): pin filename + id shapes for defense-in-depth.
                file_re = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+(-[0-9]+)?\\.md$"
                id_re   = "^sha256:[a-f0-9]{64}$"
            }
            $2 == id && $2 ~ id_re && $3 ~ file_re {
                # Check op already in read_by.
                rb = $8
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", rb)
                # Look for ",op:" in normalized form ",rb,".
                if (index(","rb",", ","op":") == 0) {
                    if (rb == "") rb = op":"ts
                    else rb = rb","op":"ts
                    $8 = " " rb " "
                    matched=1
                    print $0; next
                }
                # Already marked — emit unchanged.
                print $0; next
            }
            { print }
        ' "$index" > "$tmp"
        mv -f "$tmp" "$index"
    ) 9>"$lock"

    local rc=$?
    [[ -e "$tmp" ]] && rm -f "$tmp"
    if [[ "$rc" -ne 0 ]]; then
        return "$rc"
    fi

    # Sprint 6E (HIGH-1): emit handoff.mark_read audit event for state mutation.
    local payload
    payload="$(jq -nc \
        --arg id "$id" \
        --arg op "$op" \
        --arg ts "$now" \
        --argjson am "$already_marked" \
        '{handoff_id: $id, operator_id: $op, ts_utc: $ts, already_marked: $am}')"
    local log_path="$_LOA_HANDOFF_DEFAULT_LOG"
    if _handoff_check_env_override LOA_HANDOFF_LOG "${LOA_HANDOFF_LOG:-}" 2>/dev/null; then
        log_path="$LOA_HANDOFF_LOG"
    fi
    mkdir -p "$(dirname "$log_path")"
    audit_emit "L6" "handoff.mark_read" "$payload" "$log_path" >/dev/null 2>&1 || true
    return 0
}

# -----------------------------------------------------------------------------
# CLI entrypoint when sourced as script.
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-help}"
    shift || true
    case "$cmd" in
        write)         handoff_write "$@" ;;
        compute-id)    handoff_compute_id "$@" ;;
        list)          handoff_list "$@" ;;
        read)          handoff_read "$@" ;;
        surface)       surface_unread_handoffs "$@" ;;
        mark-read)     handoff_mark_read "$@" ;;
        help|--help|-h)
            cat <<'USAGE'
structured-handoff-lib.sh — L6 structured-handoff (cycle-098 Sprint 6).

Subcommands:
  write <yaml_path> [--handoffs-dir <path>]
  compute-id <yaml_path>
  list [--unread] [--to <op>] [--handoffs-dir <path>]
  read <handoff_id> [--handoffs-dir <path>]
  surface <operator> [--handoffs-dir <path>] [--max-bytes N]
  mark-read <handoff_id> <operator> [--handoffs-dir <path>]
USAGE
            ;;
        *)
            echo "unknown subcommand: $cmd" >&2
            exit 2
            ;;
    esac
fi
