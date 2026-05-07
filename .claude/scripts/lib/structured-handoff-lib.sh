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
# _handoff_atomic_index_update <handoffs_dir> <handoff_id> <file_basename> \
#                              <from> <to> <topic> <ts_utc>
# Atomically append a row to INDEX.md under flock. Creates INDEX.md if absent.
# Pattern: flock acquire .lock → read INDEX → write to mktemp → rename → release.
# -----------------------------------------------------------------------------
_handoff_atomic_index_update() {
    local dir="$1" id="$2" file="$3" from="$4" to="$5" topic="$6" ts="$7"
    local index="${dir}/INDEX.md"
    local lock="${dir}/.INDEX.md.lock"

    if ! command -v flock >/dev/null 2>&1; then
        _handoff_log "_handoff_atomic_index_update: flock required (CC-3)"
        return 4
    fi

    # mktemp under target dir to keep rename atomic (same filesystem).
    local tmp
    tmp="$(mktemp "${dir}/.INDEX.md.tmp.XXXXXX")"
    chmod 0644 "$tmp"

    # Acquire lock; release on subshell exit.
    (
        flock -x -w 30 9 || { _handoff_log "flock timeout on $lock"; exit 4; }

        # Read existing INDEX.md or seed with header.
        if [[ -f "$index" ]]; then
            cat "$index" > "$tmp"
            # Ensure trailing newline so append is on a fresh line.
            [[ -s "$tmp" ]] && [[ "$(tail -c 1 "$tmp" | od -An -c | awk '{print $1}')" != "\\n" ]] && printf '\n' >> "$tmp"
        else
            cat >> "$tmp" <<'HEADER'
# Handoff Index

| handoff_id | file | from | to | topic | ts_utc | read_by |
|------------|------|------|----|----|--------|---------|
HEADER
        fi

        # Append the new row. read_by starts empty; consumer marks read separately (Sprint 6C).
        printf '| %s | %s | %s | %s | %s | %s |  |\n' \
            "$id" "$file" "$from" "$to" "$topic" "$ts" >> "$tmp"

        # Atomic rename in same dir.
        mv -f "$tmp" "$index"
    ) 9>"$lock"

    local rc=$?
    # If the subshell failed before rename, clean up the tmp.
    [[ -e "$tmp" ]] && rm -f "$tmp"
    return $rc
}

# -----------------------------------------------------------------------------
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

    # Step 7: compute filename.
    local fname; fname="$(_handoff_filename "$doc_json")"
    local dest="${dest_dir}/${fname}"

    # Step 8: collision refusal (Sprint 6A only — 6B adds numeric suffix).
    if [[ -e "$dest" ]]; then
        _handoff_log "handoff_write: file collision at $dest (Sprint 6B will resolve via numeric suffix)"
        return 7
    fi

    # Step 9: write body atomically.
    _handoff_atomic_write_body "$dest" "$doc_json" "$yaml_path"

    # Step 10: index update.
    local from to topic
    from="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["from"])')"
    to="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["to"])')"
    topic="$(printf '%s' "$doc_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["topic"])')"
    if ! _handoff_atomic_index_update "$dest_dir" "$computed_id" "$fname" "$from" "$to" "$topic" "$ts"; then
        _handoff_log "handoff_write: INDEX.md atomic update failed"
        # Rollback: delete just-written body.
        rm -f "$dest"
        return 4
    fi

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
            operator_verification: "disabled"
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
        help|--help|-h)
            cat <<'USAGE'
structured-handoff-lib.sh — L6 structured-handoff (cycle-098 Sprint 6).

Subcommands:
  write <yaml_path> [--handoffs-dir <path>]
  compute-id <yaml_path>
  list [--unread] [--to <op>] [--handoffs-dir <path>]
  read <handoff_id> [--handoffs-dir <path>]
USAGE
            ;;
        *)
            echo "unknown subcommand: $cmd" >&2
            exit 2
            ;;
    esac
fi
