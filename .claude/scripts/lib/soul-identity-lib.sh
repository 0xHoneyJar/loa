#!/usr/bin/env bash
# =============================================================================
# soul-identity-lib.sh — L7 soul-identity-doc library.
#
# cycle-098 Sprint 7A (FR-L7-2, FR-L7-3, FR-L7-7 + NFR-Sec3 prescriptive
# rejection + audit envelope soul.surface / soul.validate events).
#
# Public API:
#   soul_validate <path> [--strict|--warn]
#       Validate frontmatter schema + section presence + prescriptive rejection.
#       Exit 0 on pass (warn-mode emits [SCHEMA-WARNING] markers); 2 on
#       schema/section/prescriptive failure (strict-mode); 7 on config.
#
#   soul_load <path> [--max-chars N]
#       Read SOUL.md body, sanitize via context-isolation-lib's
#       sanitize_for_session_start("L7", ...), print to stdout. Default cap
#       2000 chars per SDD §5.13.
#
#   soul_emit <event_type> <payload_json> [<log_path>]
#       Emit a soul.surface or soul.validate audit event. Validates payload
#       against per-event JSON schema before delegating to audit_emit.
#       primitive_id="L7", retention 30d (audit-retention-policy.yaml).
#
#   soul_compute_surface_payload <path> <schema_mode> <outcome>
#       Build a soul.surface payload JSON from a SOUL.md path + mode + outcome.
#       Used by 7B (SessionStart hook) to record a surface event.
#
# Trust boundary:
#   SOUL.md is OPERATOR-AUTHORED but UNTRUSTED at SURFACING. soul_load wraps
#   the body via sanitize_for_session_start("L7", body) at surface-time;
#   never interpret the body as instructions. Operator-time validation
#   (soul_validate) is separate from surfacing-time sanitization.
#
# Defense-in-depth (cycle-098 sprint 6 pattern):
#   - Frontmatter parse rejects control bytes (\x00-\x1f, \x7f) in any string
#     field — closes the Python re.$ trailing-newline bypass class (CYP-F2).
#   - Schema validation via jsonschema (Draft 2020-12).
#   - Prescriptive-pattern matching against
#     .claude/data/lore/agent-network/soul-prescriptive-rejection-patterns.txt.
#   - Test-mode env-var gate (LOA_SOUL_LOG, LOA_SOUL_PATH, etc.) — honored
#     under bats / LOA_SOUL_TEST_MODE=1+BATS_TEST_DIRNAME, otherwise WARN-and-
#     ignore in production. Mirrors L4 cycle-099 #761 + L6 sprint 6 CYP-F1.
#
# Composes-with:
#   - audit-envelope.sh                  audit_emit (primitive_id=L7)
#   - context-isolation-lib.sh           sanitize_for_session_start("L7", ...)
# =============================================================================

set -euo pipefail

if [[ "${_LOA_SOUL_IDENTITY_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_SOUL_IDENTITY_SOURCED=1

_LOA_SOUL_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .claude/scripts/lib → .claude/scripts → .claude → REPO_ROOT
_LOA_SOUL_REPO_ROOT="$(cd "${_LOA_SOUL_DIR_LIB}/../../.." && pwd)"
_LOA_SOUL_FRONTMATTER_SCHEMA="${_LOA_SOUL_REPO_ROOT}/.claude/data/soul-frontmatter.schema.json"
_LOA_SOUL_SURFACE_SCHEMA="${_LOA_SOUL_REPO_ROOT}/.claude/data/trajectory-schemas/soul-events/soul-surface.payload.schema.json"
_LOA_SOUL_VALIDATE_SCHEMA="${_LOA_SOUL_REPO_ROOT}/.claude/data/trajectory-schemas/soul-events/soul-validate.payload.schema.json"
_LOA_SOUL_PRESCRIPTIVE_PATTERNS="${_LOA_SOUL_REPO_ROOT}/.claude/data/lore/agent-network/soul-prescriptive-rejection-patterns.txt"
_LOA_SOUL_DEFAULT_LOG="${_LOA_SOUL_REPO_ROOT}/.run/soul-events.jsonl"
_LOA_SOUL_DEFAULT_PATH="${_LOA_SOUL_REPO_ROOT}/SOUL.md"

# -----------------------------------------------------------------------------
# Test-mode gate (mirrors L4 graduated-trust-lib + L6 structured-handoff-lib).
# -----------------------------------------------------------------------------
_soul_test_mode_active() {
    if [[ -n "${BATS_TEST_DIRNAME:-}" ]] || [[ -n "${BATS_TMPDIR:-}" ]]; then
        return 0
    fi
    if [[ "${LOA_SOUL_TEST_MODE:-0}" == "1" ]] && [[ -n "${BATS_TEST_DIRNAME:-${BATS_TMPDIR:-}}" ]]; then
        return 0
    fi
    return 1
}

_soul_check_env_override() {
    local var_name="$1" var_value="$2"
    if [[ -z "$var_value" ]]; then
        return 1
    fi
    if _soul_test_mode_active; then
        return 0
    fi
    echo "[soul-identity] WARNING: env override '$var_name' ignored in production (test-mode gate)" >&2
    return 1
}

_soul_resolve_log() {
    local log="$_LOA_SOUL_DEFAULT_LOG"
    if [[ -n "${LOA_SOUL_LOG:-}" ]]; then
        if _soul_check_env_override LOA_SOUL_LOG "${LOA_SOUL_LOG}"; then
            log="$LOA_SOUL_LOG"
        fi
    fi
    printf '%s' "$log"
}

# -----------------------------------------------------------------------------
# Source companion libs.
# -----------------------------------------------------------------------------
# shellcheck source=../audit-envelope.sh
source "${_LOA_SOUL_DIR_LIB}/../audit-envelope.sh"
# shellcheck source=./context-isolation-lib.sh
source "${_LOA_SOUL_DIR_LIB}/context-isolation-lib.sh"

# -----------------------------------------------------------------------------
# _soul_log — internal stderr logger; strips C0 control bytes + DEL so
# operator-supplied content can't smuggle ANSI escape sequences through.
# (Mirrors L6 sprint 6 CYP-F12 closure.)
# -----------------------------------------------------------------------------
_soul_log() {
    local msg="$*"
    msg="$(printf '%s' "$msg" | tr -d '\000-\010\013-\037\177')"
    echo "[soul-identity] $msg" >&2
}

# -----------------------------------------------------------------------------
# _soul_parse_frontmatter <path>
# Print parsed frontmatter as JSON to stdout. On failure: ERR:<reason> to
# stderr + exit 2. Defense-in-depth: rejects control bytes in any scalar/list
# string value (closes the Python re.$ trailing-newline bypass class).
# -----------------------------------------------------------------------------
_soul_parse_frontmatter() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "ERR:file-missing:$path" >&2
        return 2
    fi
    LOA_SOUL_PARSE_PATH="$path" python3 - <<'PY'
import os, sys, json, re
try:
    import yaml
except Exception as e:
    print("ERR:pyyaml-missing:" + str(e)[:200], file=sys.stderr); sys.exit(7)

path = os.environ["LOA_SOUL_PARSE_PATH"]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Frontmatter: file MUST start with --- on its own line, then YAML, then ---.
m = re.match(r'^---\s*\n(.*?)\n---\s*(?:\n|$)', text, flags=re.DOTALL)
if not m:
    print("ERR:no-frontmatter", file=sys.stderr); sys.exit(2)

fm_text = m.group(1)
try:
    fm = yaml.safe_load(fm_text)
except Exception as e:
    print("ERR:yaml-parse:" + str(e).replace("\n", " | ")[:200], file=sys.stderr); sys.exit(2)

if not isinstance(fm, dict):
    print("ERR:frontmatter-not-mapping", file=sys.stderr); sys.exit(2)

# Defense-in-depth control-byte rejection.
def _has_control_byte(s):
    for ch in s:
        c = ord(ch)
        if c < 0x20 or c == 0x7f:
            return True
    return False

for k, v in fm.items():
    if isinstance(v, str) and _has_control_byte(v):
        print("ERR:control-byte-in-field:" + str(k), file=sys.stderr); sys.exit(2)
    if isinstance(v, list):
        for item in v:
            if isinstance(item, str) and _has_control_byte(item):
                print("ERR:control-byte-in-list-item:" + str(k), file=sys.stderr); sys.exit(2)

print(json.dumps(fm))
PY
}

# -----------------------------------------------------------------------------
# _soul_validate_frontmatter_schema <fm_json>
# Validate parsed frontmatter against the JSON Schema. Exit 0 on valid;
# exit 2 with ERR:schema:... lines to stderr on invalid.
# -----------------------------------------------------------------------------
_soul_validate_frontmatter_schema() {
    local fm_json="$1"
    LOA_SOUL_FM_JSON="$fm_json" \
    LOA_SOUL_FM_SCHEMA="$_LOA_SOUL_FRONTMATTER_SCHEMA" \
    python3 - <<'PY'
import os, sys, json
try:
    import jsonschema
except Exception as e:
    print("ERR:jsonschema-missing:" + str(e)[:200], file=sys.stderr); sys.exit(7)

fm = json.loads(os.environ["LOA_SOUL_FM_JSON"])
with open(os.environ["LOA_SOUL_FM_SCHEMA"], 'r') as f:
    schema = json.load(f)

validator = jsonschema.Draft202012Validator(schema)
errs = sorted(validator.iter_errors(fm), key=lambda e: list(e.path))
if errs:
    for e in errs:
        path = "/".join(str(p) for p in e.absolute_path)
        msg = e.message[:200].replace("\n", " | ")
        print("ERR:schema:" + (path or "<root>") + ":" + msg, file=sys.stderr)
    sys.exit(2)
PY
}

# -----------------------------------------------------------------------------
# _soul_extract_sections <path>
# Print JSONL: one line per `## Heading` section in the body, with heading,
# first non-empty content line, and body line count.
# -----------------------------------------------------------------------------
_soul_extract_sections() {
    local path="$1"
    LOA_SOUL_EXTRACT_PATH="$path" python3 - <<'PY'
import os, sys, json, re
path = os.environ["LOA_SOUL_EXTRACT_PATH"]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

m = re.match(r'^---\s*\n.*?\n---\s*(?:\n|$)', text, flags=re.DOTALL)
body = text[m.end():] if m else text

# Section starts at lines matching ^## (h2) followed by whitespace.
# Bigger headers (### etc.) are NOT section starts.
lines = body.split('\n')
sections = []
cur = None

h2 = re.compile(r'^##(?!#)\s+(.+?)\s*$')

for line in lines:
    mm = h2.match(line)
    if mm:
        if cur is not None:
            sections.append(cur)
        cur = {"heading": mm.group(1).strip(), "body_lines": []}
    else:
        if cur is not None:
            cur["body_lines"].append(line)
if cur is not None:
    sections.append(cur)

for s in sections:
    first_content = ""
    for ln in s["body_lines"]:
        if ln.strip() != "":
            first_content = ln
            break
    print(json.dumps({
        "heading": s["heading"],
        "first_content_line": first_content,
        "body_lines_count": len(s["body_lines"]),
        "body_lines": s["body_lines"],
    }))
PY
}

# -----------------------------------------------------------------------------
# _soul_classify_sections <path>
# Print JSON {required_present, required_missing, prescriptive_hits,
# unknown_sections}. Pattern file is .claude/data/lore/agent-network/
# soul-prescriptive-rejection-patterns.txt; rules are Python regex
# (case-insensitive, multiline).
# -----------------------------------------------------------------------------
_soul_classify_sections() {
    local path="$1"
    local sections_jsonl
    sections_jsonl="$(_soul_extract_sections "$path")" || return 1
    LOA_SOUL_SECTIONS_JSONL="$sections_jsonl" \
    LOA_SOUL_PATTERNS="$_LOA_SOUL_PRESCRIPTIVE_PATTERNS" \
    python3 - <<'PY'
import os, sys, json, re

sections = []
for line in os.environ["LOA_SOUL_SECTIONS_JSONL"].split('\n'):
    line = line.strip()
    if line:
        sections.append(json.loads(line))

required = ["What I am", "What I am not", "Voice", "Discipline", "Influences"]
optional = ["Refusals", "Glossary", "Provenance"]

patterns = []
patt_path = os.environ.get("LOA_SOUL_PATTERNS", "")
if patt_path and os.path.exists(patt_path):
    with open(patt_path, 'r', encoding='utf-8') as f:
        for ln in f:
            ln = ln.rstrip('\n')
            if not ln or ln.lstrip().startswith('#'):
                continue
            try:
                patterns.append(re.compile(ln, flags=re.IGNORECASE | re.MULTILINE))
            except re.error:
                pass

required_present = []
required_missing = []
prescriptive_hits = []
unknown_sections = []

present_headings = [s["heading"] for s in sections]
for r in required:
    if r in present_headings:
        required_present.append(r)
    else:
        required_missing.append(r)

# Apply prescriptive patterns to FULL section body (multiline). Each pattern
# already anchors with ^...$ + MULTILINE so it scans line-by-line within the
# section body. A match in any line of the section's body flags it.
for s in sections:
    body_text = '\n'.join(s["body_lines"])
    matched = False
    for p in patterns:
        if p.search(body_text):
            matched = True
            break
    if matched and s["heading"] not in prescriptive_hits:
        prescriptive_hits.append(s["heading"])

for h in present_headings:
    if h not in required and h not in optional:
        unknown_sections.append(h)

print(json.dumps({
    "required_present": required_present,
    "required_missing": required_missing,
    "prescriptive_hits": prescriptive_hits,
    "unknown_sections": unknown_sections,
}))
PY
}

# =============================================================================
# Public API
# =============================================================================

# soul_validate <path> [--strict|--warn]
soul_validate() {
    local path=""
    local mode="strict"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) mode="strict"; shift ;;
            --warn)   mode="warn"; shift ;;
            --) shift; while [[ $# -gt 0 ]]; do path="$1"; shift; done ;;
            -*) echo "soul_validate: unknown flag '$1'" >&2; return 7 ;;
            *)  path="$1"; shift ;;
        esac
    done
    if [[ -z "$path" ]]; then
        echo "soul_validate: missing <path>" >&2
        return 7
    fi
    if [[ ! -f "$path" ]]; then
        echo "soul: file missing: $path"
        return 2
    fi

    # Parse frontmatter (control-byte gated).
    local fm_json fm_err _err_tmp
    _err_tmp="$(mktemp)"
    if ! fm_json="$(_soul_parse_frontmatter "$path" 2>"$_err_tmp")"; then
        fm_err="$(cat "$_err_tmp")"
        rm -f "$_err_tmp"
        echo "soul: frontmatter parse failed: $fm_err"
        return 2
    fi
    rm -f "$_err_tmp"

    # Schema validation.
    local schema_err _se_tmp
    _se_tmp="$(mktemp)"
    if ! _soul_validate_frontmatter_schema "$fm_json" 2>"$_se_tmp"; then
        schema_err="$(cat "$_se_tmp")"
        rm -f "$_se_tmp"
        echo "soul: $schema_err"
        return 2
    fi
    rm -f "$_se_tmp"

    # Section classification.
    local class_json
    if ! class_json="$(_soul_classify_sections "$path")"; then
        echo "soul: section classification failed"
        return 2
    fi

    local missing_json hits_json has_missing has_prescriptive
    missing_json="$(printf '%s' "$class_json" | jq -c '.required_missing // []')"
    hits_json="$(printf '%s' "$class_json"    | jq -c '.prescriptive_hits  // []')"
    has_missing="$(printf '%s' "$class_json"  | jq -r '.required_missing | length')"
    has_prescriptive="$(printf '%s' "$class_json" | jq -r '.prescriptive_hits | length')"

    if [[ "$mode" == "strict" ]]; then
        if [[ "${has_missing:-0}" -gt 0 ]]; then
            echo "soul: required sections missing: $missing_json"
            return 2
        fi
        if [[ "${has_prescriptive:-0}" -gt 0 ]]; then
            echo "soul: prescriptive sections detected (NFR-Sec3): $hits_json"
            return 2
        fi
    else
        # warn mode: emit markers but pass.
        if [[ "${has_missing:-0}" -gt 0 ]]; then
            echo "[SCHEMA-WARNING] required sections missing: $missing_json"
        fi
        if [[ "${has_prescriptive:-0}" -gt 0 ]]; then
            echo "[SCHEMA-WARNING] prescriptive sections detected: $hits_json"
        fi
    fi
    return 0
}

# soul_load <path> [--max-chars N]
soul_load() {
    local path=""
    local max_chars=2000
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-chars) max_chars="$2"; shift 2 ;;
            -*) echo "soul_load: unknown flag '$1'" >&2; return 7 ;;
            *)  path="$1"; shift ;;
        esac
    done
    if [[ -z "$path" ]]; then
        echo "soul_load: missing <path>" >&2
        return 7
    fi
    if [[ ! -f "$path" ]]; then
        return 2
    fi

    local body
    body="$(LOA_SOUL_LOAD_PATH="$path" python3 - <<'PY'
import os, re, sys
with open(os.environ["LOA_SOUL_LOAD_PATH"], 'r', encoding='utf-8') as f:
    text = f.read()
m = re.match(r'^---\s*\n.*?\n---\s*(?:\n|$)', text, flags=re.DOTALL)
sys.stdout.write(text[m.end():] if m else text)
PY
)"
    sanitize_for_session_start "L7" "$body" --max-chars "$max_chars"
}

# soul_emit <event_type> <payload_json> [<log_path>]
soul_emit() {
    local event_type="${1:-}"
    local payload_json="${2:-}"
    local log_path="${3:-$(_soul_resolve_log)}"
    if [[ -z "$event_type" || -z "$payload_json" ]]; then
        echo "soul_emit: usage: soul_emit <event_type> <payload_json> [<log_path>]" >&2
        return 2
    fi
    local schema=""
    case "$event_type" in
        soul.surface)  schema="$_LOA_SOUL_SURFACE_SCHEMA" ;;
        soul.validate) schema="$_LOA_SOUL_VALIDATE_SCHEMA" ;;
        *) echo "soul_emit: unknown event_type '$event_type' (expected soul.surface|soul.validate)" >&2; return 2 ;;
    esac
    if ! LOA_SOUL_PAYLOAD="$payload_json" LOA_SOUL_PAYLOAD_SCHEMA="$schema" python3 - <<'PY'
import os, json, sys
try:
    import jsonschema
except Exception as e:
    print("ERR:jsonschema-missing", file=sys.stderr); sys.exit(7)
payload = json.loads(os.environ["LOA_SOUL_PAYLOAD"])
with open(os.environ["LOA_SOUL_PAYLOAD_SCHEMA"], 'r') as f:
    schema = json.load(f)
validator = jsonschema.Draft202012Validator(schema)
errs = sorted(validator.iter_errors(payload), key=lambda e: list(e.path))
if errs:
    for e in errs:
        path = "/".join(str(p) for p in e.absolute_path) or "<root>"
        msg = e.message[:200].replace("\n", " | ")
        print("ERR:soul-payload:" + path + ":" + msg, file=sys.stderr)
    sys.exit(2)
PY
    then
        return 2
    fi
    audit_emit "L7" "$event_type" "$payload_json" "$log_path"
}

# soul_compute_surface_payload <path> [<schema_mode>] [<outcome>]
soul_compute_surface_payload() {
    local path="${1:-}"
    local schema_mode="${2:-strict}"
    local outcome="${3:-surfaced}"
    if [[ -z "$path" ]]; then
        echo "soul_compute_surface_payload: missing <path>" >&2
        return 2
    fi

    local fm_json sv idfor
    sv="1.0"
    idfor="this-repo"
    if [[ -f "$path" ]]; then
        if fm_json="$(_soul_parse_frontmatter "$path" 2>/dev/null)"; then
            sv="$(printf '%s' "$fm_json" | jq -r '.schema_version // "1.0"')"
            idfor="$(printf '%s' "$fm_json" | jq -r '.identity_for // "this-repo"')"
        fi
    fi

    local body_size=0
    if [[ -f "$path" ]]; then
        body_size="$(wc -c <"$path" | awk '{print $1}')"
    fi

    local class_json missing_json hits_json
    if [[ -f "$path" ]]; then
        class_json="$(_soul_classify_sections "$path" 2>/dev/null || echo '{}')"
    else
        class_json='{}'
    fi
    missing_json="$(printf '%s' "$class_json" | jq -c '.required_missing // []')"
    hits_json="$(printf '%s'    "$class_json" | jq -c '.prescriptive_hits  // []')"

    # Build repo-relative path when possible (defense against absolute paths
    # leaking the operator's home directory into audit logs).
    local rel_path="$path"
    if [[ "$path" == "$_LOA_SOUL_REPO_ROOT"/* ]]; then
        rel_path="${path#"$_LOA_SOUL_REPO_ROOT"/}"
    fi

    jq -nc \
        --arg fp "$rel_path" \
        --arg sv "$sv" \
        --arg sm "$schema_mode" \
        --arg idf "$idfor" \
        --arg oc "$outcome" \
        --argjson bs "$body_size" \
        --argjson missing "$missing_json" \
        --argjson hits "$hits_json" \
        '{
            file_path: $fp,
            schema_version: $sv,
            schema_mode: $sm,
            identity_for: $idf,
            outcome: $oc,
            body_byte_size: $bs,
            missing_required_sections: $missing,
            prescriptive_section_hits: $hits
        }'
}
