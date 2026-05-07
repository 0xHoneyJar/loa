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
    echo "[structured-handoff] $*" >&2
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
        /etc|/etc/*|/usr|/usr/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/boot|/boot/*)
            _handoff_log "_handoff_resolve_dir: handoffs_dir refuses system path: $resolved"
            return 7
            ;;
    esac

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
        flock -x -w 30 9 || { _handoff_log "flock timeout on $lock"; exit 4; }

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
            cat "$index" > "$index_tmp"
            [[ -s "$index_tmp" ]] && [[ "$(tail -c 1 "$index_tmp" | od -An -c | awk '{print $1}')" != "\\n" ]] && printf '\n' >> "$index_tmp"
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
        mv -f "$index_tmp" "$index"

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
    if [[ -n "${LOA_HANDOFF_VERIFY_OPERATORS:-}" ]]; then
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
    if [[ -n "${LOA_HANDOFF_SCHEMA_MODE:-}" ]]; then
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
        printf 'unknown'
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
    elif [[ "$from_state" == "unverified" || "$to_state" == "unverified" ]]; then
        combined="unverified"
    else
        combined="unknown"
    fi

    printf '%s %s %s' "$from_state" "$to_state" "$combined"

    if [[ "$mode" == "strict" && "$combined" != "verified" ]]; then
        _handoff_log "verify_operators: strict-mode reject (from=$from_state to=$to_state combined=$combined)"
        return 3
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
    local chosen_fname
    chosen_fname="$(_handoff_atomic_publish "$dest_dir" "$doc_json" "$computed_id" "$from" "$to" "$topic" "$ts")"
    local pub_rc=$?
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

    local payload
    payload="$(jq -nc \
        --arg id "$computed_id" \
        --arg from "$from" \
        --arg to "$to" \
        --arg topic "$topic" \
        --arg ts "$ts" \
        --arg fp "$rel_path" \
        --arg sv "1.0" \
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

    local log_path="${LOA_HANDOFF_LOG:-${_LOA_HANDOFF_DEFAULT_LOG}}"
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
        BEGIN { FS=" *\\| *" }
        /^\| sha256:/ {
            # FS=" *\\| *" → fields[2]=id, [3]=file, [4]=from, [5]=to,
            #               [6]=topic, [7]=ts_utc, [8]=read_by
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

    # Find file basename for this id.
    local file
    file="$(awk -v id="$id" '
        BEGIN { FS=" *\\| *" }
        $2 == id { print $3; exit }
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
        $2 ~ /^sha256:/ && $5 == op {
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

        # Sanitize. Stderr from sanitize is preserved (BLOCKER signals).
        # The inline-content path of sanitize_for_session_start does NOT inject
        # a path= attribute (path_label is empty when content is given inline).
        # We splice it in here on the opening <untrusted-content...> tag so
        # operator + downstream consumers can locate the source file.
        # rel_path is path-attribute-safe (slug-shape components + slashes).
        local path_safe; path_safe="${rel_path//\"/}"
        sanitize_for_session_start "L6" "$body" --max-chars "$max_chars" \
            | sed -e "s|<untrusted-content source=\"L6\"|<untrusted-content source=\"L6\" path=\"${path_safe}\"|"
        printf '\n'
        seen=$((seen + 1))
    done <<< "$unread_lines"

    # Optional: emit audit event for surfacing (suppress under env flag).
    if [[ "${LOA_HANDOFF_SUPPRESS_SURFACE_AUDIT:-0}" != "1" ]]; then
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
        local log_path="${LOA_HANDOFF_LOG:-${_LOA_HANDOFF_DEFAULT_LOG}}"
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

    local lock="${dir}/.INDEX.md.lock"
    local now; now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local tmp
    tmp="$(mktemp "${dir}/.INDEX.md.tmp.XXXXXX")"
    chmod 0644 "$tmp"

    (
        flock -x -w 30 9 || { _handoff_log "flock timeout"; exit 4; }
        # Append "$op:$now" to read_by (field 8) for the row whose id matches.
        awk -F' *\\| *' -v OFS=' | ' -v id="$id" -v op="$op" -v ts="$now" '
            BEGIN { matched=0 }
            $2 == id {
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
    return $rc
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
