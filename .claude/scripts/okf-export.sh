#!/usr/bin/env bash
# =============================================================================
# okf-export.sh — read-only OKF v0.1 export skin over the grimoire corpus
#
# OKF/ICM adoption cycle, Sprint 4 (rec #4). Projects already-typed knowledge
# families (v1: handoffs + observations) into a conformant Open Knowledge Format
# v0.1 bundle at .run/okf-bundle/ (State zone, gitignored). The grimoire stays
# the SOURCE OF TRUTH; this is a DERIVED projection downstream of every gate.
#
# OKF v0.1 conformance (SPEC: GoogleCloudPlatform/knowledge-catalog okf/SPEC.md):
#   - every non-reserved .md = parseable YAML frontmatter with a NON-EMPTY `type`
#   - path-as-identity: concept id = bundle-relative path minus the .md suffix
#   - reserved index.md carries NO frontmatter, EXCEPT the bundle-ROOT index.md
#     which carries `okf_version` (the only place frontmatter is permitted in one)
#   - recommended fields: title, description, resource, tags, timestamp
#
# SECURITY: handoff (L6) + observation bodies are UNTRUSTED (CLAUDE.md invariant).
#   Every user-controlled field is secret-shape-redacted (secret-redaction.sh +
#   the butterfreezone AKIA/JWT/generic-key pattern set) AT EXTRACTION, so every
#   downstream render (frontmatter, body, index) is clean; control-byte sanitized;
#   UTF-8-safe truncated (never mid-codepoint); slugs are path-traversal-safe and
#   collision-disambiguated 1:1 with the manifest; YAML scalars quote/escape-safe;
#   the destructive write only replaces a path that is a prior OKF bundle or empty.
#   Body prose is COPIED, never interpreted as instructions.
# DETERMINISM: pure function of inputs (no wall-clock); concepts + indexes sorted
#   LC_ALL=C — two runs are byte-identical (testable, drift-safe).
#
# Flags: --json (manifest to stdout, no write) --validate (conformance check)
#        --grimoire DIR (source, default grimoires/loa) --output DIR (default .run/okf-bundle)
#        --quiet
# =============================================================================
export LC_ALL=C
export TZ=UTC
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GRIMOIRE="${PROJECT_ROOT}/grimoires/loa"
OUTPUT="${PROJECT_ROOT}/.run/okf-bundle"
LOCK="${PROJECT_ROOT}/.run/.okf-export.lock"
OKF_VERSION="0.1"
MODE="write"; QUIET=0

source "${SCRIPT_DIR}/compat-lib.sh"
source "${SCRIPT_DIR}/lib/secret-redaction.sh"

HAVE_ICONV=0; command -v iconv >/dev/null 2>&1 && HAVE_ICONV=1
require_jq(){ command -v jq >/dev/null 2>&1 || { echo "okf-export: jq required" >&2; exit 3; }; }
log(){ [[ $QUIET -eq 0 ]] && echo "$@" >&2 || true; }

parse_args(){
  while [[ $# -gt 0 ]]; do case "$1" in
    --json) MODE="json" ;;
    --validate) MODE="validate" ;;
    --grimoire) GRIMOIRE="$2"; shift ;;
    --output) OUTPUT="$2"; shift ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "okf-export: unknown arg: $1" >&2; exit 2 ;;
  esac; shift; done
}

# Drop a truncated trailing multibyte sequence so output is always valid UTF-8.
_utf8(){ if [[ $HAVE_ICONV -eq 1 ]]; then iconv -f UTF-8 -t UTF-8 -c 2>/dev/null; else cat; fi; }
# Combined secret redaction: shared lib (sk-/AIza/gh*/xox/Bearer/PEM) + house patterns
# (AKIA / JWT eyJ / generic key=value) so coverage matches MODELINV redaction discipline.
OKF_EXTRA_PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'gh[sr]_[A-Za-z0-9_]{30,}'
  'eyJ[A-Za-z0-9+/=_-]{20,}'
  '(password|passwd|secret|api[_-]?key|apikey|access[_-]?key|auth[_-]?token|token)[[:space:]]*[=:][[:space:]]*[A-Za-z0-9/+_.=-]{8,}'
)
okf_redact(){ local s p; s="$(_redact_secrets "${1-}")"; for p in "${OKF_EXTRA_PATTERNS[@]}"; do s="$(printf '%s' "$s" | sed -E "s/${p}/[REDACTED]/g")"; done; printf '%s' "$s"; }
# Short scalar: redact, strip control bytes (keep UTF-8 multibyte), flatten whitespace, UTF-8-safe cap.
san(){ okf_redact "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-160 | _utf8; }
# Body text: redact, strip dangerous control bytes (keep \n\t), UTF-8-safe cap per line.
san_body(){ okf_redact "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | cut -c1-4000 | _utf8; }
# YAML double-quoted scalar: sanitize, escape backslash then double-quote.
yaml_str(){ local s; s="$(san "${1-}")"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
# Path-traversal-safe slug: redact, lowercase, allowed [a-z0-9._-], collapse dotdot, trim, UTF-8-safe cap.
slugify(){ okf_redact "${1-}" | tr -d '\000-\037\177' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/\.\.+/-/g; s/-+/-/g; s/^[-.]+//; s/[-.]+$//' | cut -c1-80 | _utf8; }

# Reserve a collision-free bundle-relative concept path (no extension); keeps disk 1:1 with manifest.
uniq_rel(){ local used="$1" rel="$2" i=2 cand; cand="$rel"; while grep -qxF -- "$cand" "$used" 2>/dev/null; do cand="${rel}-${i}"; i=$((i+1)); done; printf '%s\n' "$cand" >> "$used"; printf '%s' "$cand"; }

# --- family builders: (bundle_root, used_paths_file, manifest_file) ---
build_handoffs(){
  local target="$1" used="$2" man="$3" src="${GRIMOIRE}/handoffs/INDEX.md"
  [[ -f "$src" ]] || return 0
  grep -E '^\| *sha256:[a-f0-9]+ *\|' "$src" 2>/dev/null \
    | while IFS='|' read -r _ hid file from to topic ts _rest; do
        # redact every user-controlled field AT EXTRACTION → all downstream renders are clean
        local r_topic r_from r_to r_file r_ts sha base rel title fpath
        r_topic="$(okf_redact "$topic")"; r_from="$(okf_redact "$from")"; r_to="$(okf_redact "$to")"
        r_file="$(okf_redact "$file")"; r_ts="$(okf_redact "$ts")"
        sha="$(printf '%s' "$hid" | grep -oE '[a-f0-9]{12}' | head -1)"; sha="${sha:-000000000000}"
        base="$(slugify "$(basename "$(san "$r_file")" .md)")"
        [[ -n "$base" ]] && rel="handoffs/${base}-${sha}" || rel="handoffs/handoff-${sha}"
        rel="$(uniq_rel "$used" "$rel")"
        title="$(san "$r_topic")"; [[ -z "$title" ]] && title="handoff-${sha}"
        fpath="${target}/${rel}.md"; mkdir -p "$(dirname "$fpath")"
        {
          echo "---"
          echo "type: $(yaml_str "Handoff")"
          echo "title: $(yaml_str "$title")"
          echo "description: $(yaml_str "Structured handoff from $(san "$r_from") to $(san "$r_to"): ${title}")"
          echo "resource: $(yaml_str "grimoires/loa/handoffs/$(san "$r_file")")"
          echo "tags: [$(yaml_str "handoff"), $(yaml_str "from:$(san "$r_from")"), $(yaml_str "to:$(san "$r_to")")]"
          echo "timestamp: $(yaml_str "$(san "$r_ts")")"
          echo "---"
          echo
          echo "# ${title}"
          echo
          echo "Structured handoff routed **$(san "$r_from") → $(san "$r_to")**."
          echo
          echo "- Topic: ${title}"
          echo "- Source artifact: \`grimoires/loa/handoffs/$(san "$r_file")\`"
          echo "- Recorded: $(san "$r_ts")"
        } > "$fpath"
        printf '%s\t%s\t%s\n' "$rel" "Handoff" "$title" >> "$man"
      done || true
}

build_observations(){
  local target="$1" used="$2" man="$3" src="${GRIMOIRE}/memory/observations.jsonl"
  [[ -f "$src" ]] || return 0
  local n=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n+1)); [[ -z "$line" ]] && continue
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || continue
    local ts ty cat title detail impl sha rel fpath
    ts="$(okf_redact "$(printf '%s' "$line" | jq -r '.timestamp // ""')")"
    ty="$(okf_redact "$(printf '%s' "$line"  | jq -r '.type // ""')")"
    cat="$(okf_redact "$(printf '%s' "$line" | jq -r '.category // ""')")"
    title="$(okf_redact "$(printf '%s' "$line"| jq -r '.title // ""')")"
    detail="$(okf_redact "$(printf '%s' "$line"| jq -r '.detail // ""')")"
    impl="$(okf_redact "$(printf '%s' "$line" | jq -r '.implication // ""')")"
    # hash the FULL source line → distinct rows get distinct ids; identical rows collapse (correct)
    sha="$(printf '%s' "$line" | sha256_portable | cut -c1-12)"
    rel="$(uniq_rel "$used" "observations/obs-${sha}")"
    fpath="${target}/${rel}.md"; mkdir -p "$(dirname "$fpath")"
    {
      echo "---"
      echo "type: $(yaml_str "Observation")"
      echo "title: $(yaml_str "${title:-obs-${sha}}")"
      echo "description: $(yaml_str "$(san "$ty") observation — $(san "$cat")")"
      echo "tags: [$(yaml_str "observation"), $(yaml_str "$(san "$ty")"), $(yaml_str "$(san "$cat")")]"
      echo "timestamp: $(yaml_str "$ts")"
      echo "resource: $(yaml_str "grimoires/loa/memory/observations.jsonl#L${n}")"
      echo "---"
      echo
      echo "# $(san "${title:-obs-${sha}}")"
      echo
      [[ -n "$detail" ]] && { san_body "$detail"; echo; }
      [[ -n "$impl" ]] && { printf '**Implication:** %s\n\n' "$(san_body "$impl")"; }
    } > "$fpath"
    printf '%s\t%s\t%s\n' "$rel" "Observation" "$(san "${title:-obs-${sha}}")" >> "$man"
  done < "$src"
}

render_subindex(){ # heading, manifest, subdir-prefix
  local heading="$1" man="$2" prefix="$3"
  echo "# ${heading}"
  echo
  LC_ALL=C sort "$man" | awk -F'\t' -v p="$prefix/" 'index($1,p)==1{
      rel=substr($1, length(p)+1); printf "* [%s](%s.md) - %s\n", $3, rel, $2 }'
}

render_root_index(){ # manifest
  local man="$1" hc oc
  hc="$(LC_ALL=C awk -F'\t' '$1 ~ /^handoffs\//{c++} END{print c+0}' "$man")"
  oc="$(LC_ALL=C awk -F'\t' '$1 ~ /^observations\//{c++} END{print c+0}' "$man")"
  echo "---"
  echo "okf_version: \"${OKF_VERSION}\""
  echo "---"
  echo
  echo "# Loa Grimoire — OKF Export"
  echo
  echo "Derived OKF v0.1 projection of the loa grimoire corpus (v1: handoffs + observations)."
  echo "Source of truth: \`grimoires/loa/\`. Regenerate: \`bash .claude/scripts/okf-export.sh\`."
  echo
  if [[ "$hc" -gt 0 ]]; then
    echo "## Handoffs (${hc})"; echo
    LC_ALL=C sort "$man" | awk -F'\t' '$1 ~ /^handoffs\//{ printf "* [%s](%s.md) - %s\n", $3, $1, $2 }'
    echo
  fi
  if [[ "$oc" -gt 0 ]]; then
    echo "## Observations (${oc})"; echo
    LC_ALL=C sort "$man" | awk -F'\t' '$1 ~ /^observations\//{ printf "* [%s](%s.md) - %s\n", $3, $1, $2 }'
    echo
  fi
}

# Build the full bundle into target dir; echo manifest path on stdout.
build_bundle(){
  local target="$1" man used
  man="$(mktemp)"; used="$(mktemp)"; : > "$man"; : > "$used"
  build_handoffs "$target" "$used" "$man"
  build_observations "$target" "$used" "$man"
  if LC_ALL=C grep -q '^handoffs/' "$man"; then render_subindex "Handoffs" "$man" "handoffs" > "${target}/handoffs/index.md"; fi
  if LC_ALL=C grep -q '^observations/' "$man"; then render_subindex "Observations" "$man" "observations" > "${target}/observations/index.md"; fi
  render_root_index "$man" > "${target}/index.md"
  rm -f "$used"
  printf '%s\n' "$man"
}

manifest_json(){ # manifest-file
  jq -R -s --arg v "$OKF_VERSION" '
    [ split("\n")[] | select(length>0) | split("\t") | {path:.[0], type:.[1], title:.[2]} ]
    | { okf_version: $v,
        counts: { handoffs: (map(select(.path|startswith("handoffs/")))|length),
                  observations: (map(select(.path|startswith("observations/")))|length),
                  total: length },
        duplicate_paths: ([.[].path] | group_by(.) | map(select(length>1)) | length),
        concepts: . }' "$1"
}

validate_bundle(){
  local dir="$1" rc=0 f base typ disk dups
  [[ -d "$dir" ]] || { echo "::error::[OKF] bundle not found: $dir (run okf-export first)" >&2; return 1; }
  if [[ -f "$dir/index.md" ]]; then
    grep -qE '^okf_version:' "$dir/index.md" || { echo "::error::[OKF] root index.md missing okf_version" >&2; rc=1; }
  else
    echo "::error::[OKF] root index.md missing" >&2; rc=1
  fi
  while IFS= read -r f; do
    base="$(basename "$f")"
    [[ "$base" == "index.md" || "$base" == "log.md" ]] && continue
    if ! head -1 "$f" | grep -qx -- '---'; then echo "::error::[OKF] ${f}: no opening frontmatter" >&2; rc=1; continue; fi
    typ="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^type:/{sub(/^type:[[:space:]]*/,"");print;exit}' "$f")"
    typ="$(printf '%s' "$typ" | sed -E 's/^"//; s/"$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$typ" ]] || { echo "::error::[OKF] ${f}: empty/missing required 'type' field" >&2; rc=1; }
    # UTF-8 validity (unparseable YAML guard)
    if [[ $HAVE_ICONV -eq 1 ]] && ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
      echo "::error::[OKF] ${f}: not valid UTF-8" >&2; rc=1
    fi
  done < <(find "$dir" -name '*.md' 2>/dev/null | LC_ALL=C sort)
  # path-as-identity uniqueness: no two concepts share a path
  dups="$(find "$dir" -name '*.md' ! -name index.md ! -name log.md 2>/dev/null | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ')"
  [[ "$dups" == "0" ]] || { echo "::error::[OKF] ${dups} duplicate concept paths" >&2; rc=1; }
  if [[ $rc -eq 0 ]]; then
    disk="$(find "$dir" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    log "okf-export: bundle conformant (${disk} .md files)"
  fi
  return $rc
}

# --- main ---
parse_args "$@"
require_jq
mkdir -p "${PROJECT_ROOT}/.run"

case "$MODE" in
  validate) validate_bundle "$OUTPUT"; exit $? ;;
  json)
    tmpd="$(mktemp -d)"; man="$(build_bundle "$tmpd")"
    manifest_json "$man"
    rm -rf "$tmpd" "$man" ;;
  write)
    exec 9>"$LOCK"; flock 9 2>/dev/null || true
    parent="$(dirname "$OUTPUT")"; mkdir -p "$parent"
    tmpd="$(mktemp -d "${parent}/.okf-bundle.tmp.XXXXXX")"
    man="$(build_bundle "$tmpd")"
    # destructive-replace guard: only clobber a prior OKF bundle or an empty dir
    if [[ -e "$OUTPUT" ]]; then
      if [[ -f "$OUTPUT/index.md" ]] && grep -qE '^okf_version:' "$OUTPUT/index.md" 2>/dev/null; then
        rm -rf "$OUTPUT"
      elif [[ -d "$OUTPUT" && -z "$(ls -A "$OUTPUT" 2>/dev/null)" ]]; then
        rmdir "$OUTPUT"
      else
        rm -rf "$tmpd"; rm -f "$man"
        echo "okf-export: refusing to overwrite non-bundle path: $OUTPUT (not a prior OKF bundle and not empty)" >&2
        exit 1
      fi
    fi
    mv "$tmpd" "$OUTPUT"
    total="$(wc -l < "$man" | tr -d ' ')"; rm -f "$man"
    log "okf-export: wrote ${OUTPUT#$PROJECT_ROOT/} (${total} concepts, OKF v${OKF_VERSION})" ;;
esac
