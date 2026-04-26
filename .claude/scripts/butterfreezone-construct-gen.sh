#!/usr/bin/env bash
# =============================================================================
# butterfreezone-construct-gen.sh — per-pack CONSTRUCT-README.md generator (cycle-005 L6)
# =============================================================================
# Reads a construct pack directory (construct.yaml + skills/ + commands/ +
# identity/ + CLAUDE.md) and emits CONSTRUCT-README.md summarising:
#
#   - description + short_description
#   - persona handles (with identity file paths)
#   - skill inventory (slug → SKILL.md title + description)
#   - command inventory (name → description)
#   - composability (composes_with + symmetric compositions)
#   - streams reads/writes (doctrine §3 pipe compatibility)
#   - grimoires read/write paths (SEED §12 — "grimoire path IS the interface")
#   - install instructions
#   - author + provenance
#
# Idempotent: output byte-identical across re-runs modulo a single timestamp
# line in the footer (stripped by default; pass --timestamp to include).
#
# Usage:
#   butterfreezone-construct-gen.sh <pack-path> [-o OUTPUT_FILE] [--stdout]
#                                    [--dry-run] [--timestamp]
#
# Exit codes:
#   0 = success
#   1 = pack path missing / construct.yaml missing
#   2 = required tooling missing (yq, jq)
# =============================================================================
set -euo pipefail

export LC_ALL=C
export TZ=UTC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACK_PATH=""
OUTPUT=""
TO_STDOUT=0
DRY_RUN=0
WITH_TIMESTAMP=0

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -o|--output)  OUTPUT="$2"; shift 2 ;;
    --stdout)     TO_STDOUT=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --timestamp)  WITH_TIMESTAMP=1; shift ;;
    -*)           echo "[bfz-construct-gen] ERROR: unknown flag $1" >&2; exit 2 ;;
    *) if [[ -z "$PACK_PATH" ]]; then PACK_PATH="$1"; else echo "[bfz-construct-gen] ERROR: unexpected arg: $1" >&2; exit 2; fi; shift ;;
  esac
done

[[ -n "$PACK_PATH" ]] || { usage >&2; exit 1; }
PACK_PATH=$(cd "$PACK_PATH" 2>/dev/null && pwd) || { echo "[bfz-construct-gen] ERROR: pack path missing: $PACK_PATH" >&2; exit 1; }
YAML="$PACK_PATH/construct.yaml"
[[ -f "$YAML" ]] || { echo "[bfz-construct-gen] ERROR: construct.yaml not found at $YAML" >&2; exit 1; }

command -v yq >/dev/null 2>&1 || { echo "[bfz-construct-gen] ERROR: yq v4+ required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[bfz-construct-gen] ERROR: jq required" >&2; exit 2; }

PACK_JSON=$(yq -o=json '.' "$YAML")

get() { echo "$PACK_JSON" | jq -r "$1 // empty"; }

SLUG=$(get '.slug')
NAME=$(get '.name')
VERSION=$(get '.version')
DESCRIPTION=$(get '.description')
SHORT_DESCRIPTION=$(get '.short_description')
AUTHOR=$(get '.author')
LICENSE=$(get '.license')
SCHEMA_VERSION=$(get '.schema_version')

# --------------------------------------------------------------------------
# Personas — merge construct.yaml `personas:` list + identity/<HANDLE>.md
# --------------------------------------------------------------------------
mapfile -t yaml_personas < <(echo "$PACK_JSON" | jq -r '(.personas // [])[] | select(. != "")')
declare -a identity_files=()
if [[ -d "$PACK_PATH/identity" ]]; then
  while IFS= read -r f; do
    base=$(basename "$f" .md)
    # Persona handles are uppercase_letters / digits / underscores (e.g. ALEXANDER, OSTROM, KEEPER, BARTH).
    [[ "$base" =~ ^[A-Z][A-Z0-9_]+$ ]] || continue
    identity_files+=("$f")
  done < <(find "$PACK_PATH/identity" -maxdepth 1 -name '*.md' -print | LC_ALL=C sort)
fi

# --------------------------------------------------------------------------
# Skills — pull description from SKILL.md frontmatter `description:` or first H1
# --------------------------------------------------------------------------
frontmatter_desc() {
  local md="$1"
  [[ -f "$md" ]] || { echo ""; return; }
  # Inline form: "description: foo bar"
  local desc
  desc=$(awk '/^---/{f=!f; next} f && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$md")
  # Block scalar indicators (| or >) with no value after — pull first non-empty continuation line.
  if [[ "$desc" == "|" || "$desc" == ">" || "$desc" == "|-" || "$desc" == ">-" || "$desc" == "|+" || "$desc" == ">+" ]]; then
    desc=$(awk '
      /^---/{f=!f; next}
      f && /^description:[[:space:]]*[|>]/{ in_block=1; next }
      in_block && /^[A-Za-z_][A-Za-z0-9_]*:/{ exit }
      in_block && NF{ sub(/^[[:space:]]+/,""); print; exit }
    ' "$md")
  fi
  # Fall back to first markdown H1.
  if [[ -z "$desc" ]]; then
    desc=$(awk '!/^---/ && /^#[[:space:]]/{sub(/^#+[[:space:]]*/,""); print; exit}' "$md")
  fi
  echo "$desc"
}

skill_line() {
  local skill_dir="$1" slug="$2"
  local desc
  desc=$(frontmatter_desc "$skill_dir/SKILL.md")
  [[ -z "$desc" ]] && desc="(no description)"
  printf -- "- \`%s\` — %s\n" "$slug" "$desc"
}

skills_block=""
while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  path=$(echo "$PACK_JSON" | jq -r --arg s "$slug" '(.skills // [])[] | select(.slug == $s) | .path // empty' | head -1)
  [[ -z "$path" ]] && path="skills/$slug"
  line=$(skill_line "$PACK_PATH/$path" "$slug")
  skills_block+="$line"$'\n'
done < <(echo "$PACK_JSON" | jq -r '(.skills // [])[] | .slug // empty' | LC_ALL=C sort)

# --------------------------------------------------------------------------
# Commands — name → description (from command markdown frontmatter / H1)
# --------------------------------------------------------------------------
command_line() {
  local name="$1" path="$2"
  local desc
  desc=$(frontmatter_desc "$PACK_PATH/$path")
  [[ -z "$desc" ]] && desc="(no description)"
  printf -- "- \`/%s\` — %s\n" "$name" "$desc"
}

commands_block=""
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  name=$(echo "$row" | jq -r '.name // empty')
  path=$(echo "$row" | jq -r '.path // empty')
  [[ -z "$name" ]] && continue
  line=$(command_line "$name" "$path")
  commands_block+="$line"$'\n'
done < <(echo "$PACK_JSON" | jq -c '(.commands // [])[]' | LC_ALL=C sort)

# --------------------------------------------------------------------------
# Composes with
# --------------------------------------------------------------------------
composes_block=""
while IFS= read -r x; do
  [[ -z "$x" ]] && continue
  composes_block+="- $x"$'\n'
done < <(echo "$PACK_JSON" | jq -r '(.composes_with // [])[]' | LC_ALL=C sort -u)
[[ -z "$composes_block" ]] && composes_block="_None declared._"$'\n'

# --------------------------------------------------------------------------
# Streams — reads/writes
# --------------------------------------------------------------------------
reads_list=$(echo "$PACK_JSON" | jq -r '(.reads // .streams.reads // [])[] // empty' | LC_ALL=C sort -u)
writes_list=$(echo "$PACK_JSON" | jq -r '(.writes // .streams.writes // [])[] // empty' | LC_ALL=C sort -u)

fmt_list() {
  local l="$1"
  if [[ -z "$l" ]]; then
    echo "_not declared_"
    return
  fi
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    echo "- $t"
  done <<< "$l"
}

# --------------------------------------------------------------------------
# Grimoires read/write paths (construct.yaml declarations)
# SEED §12 — "grimoire path IS the interface"
# --------------------------------------------------------------------------
grimoires_reads=$(echo "$PACK_JSON"  | jq -r '((.composition_paths.reads // .grimoires.reads // []))[] // empty'  | LC_ALL=C sort -u)
grimoires_writes=$(echo "$PACK_JSON" | jq -r '((.composition_paths.writes // .grimoires.writes // []))[] // empty' | LC_ALL=C sort -u)

# Fallback scan: if neither list is declared, grep construct.yaml for grimoires/ paths
if [[ -z "$grimoires_reads$grimoires_writes" ]]; then
  mapfile -t fallback_paths < <(grep -oE 'grimoires/[A-Za-z0-9._-]+[/A-Za-z0-9._-]*' "$YAML" 2>/dev/null | LC_ALL=C sort -u)
  if (( ${#fallback_paths[@]} > 0 )); then
    grimoires_writes=$(printf '%s\n' "${fallback_paths[@]}")
  fi
fi

# --------------------------------------------------------------------------
# Drift detection — CLAUDE.md missing explicit grimoires section
# --------------------------------------------------------------------------
drift_notice=""
if [[ -f "$PACK_PATH/CLAUDE.md" ]]; then
  if ! grep -qiE 'grimoires?/' "$PACK_PATH/CLAUDE.md"; then
    drift_notice="> ⚠ SEED §12 drift — pack \`CLAUDE.md\` does not reference \`grimoires/\`. The canonical declaration lives in \`construct.yaml\`; regenerate CLAUDE.md or add the section manually."$'\n\n'
  fi
fi

# --------------------------------------------------------------------------
# Compose document
# --------------------------------------------------------------------------
HEADER_TITLE="${NAME:-$SLUG}"
SHORT="${SHORT_DESCRIPTION:-$DESCRIPTION}"

doc=""
doc+="<!-- Generated by .claude/scripts/butterfreezone-construct-gen.sh -->"$'\n'
doc+="<!-- Canonical source: construct.yaml · do not edit by hand -->"$'\n\n'
doc+="# $HEADER_TITLE"$'\n\n'
if [[ -n "$SHORT" ]]; then
  doc+="> $SHORT"$'\n\n'
fi

if [[ -n "$drift_notice" ]]; then
  doc+="$drift_notice"
fi

doc+="## About"$'\n\n'
doc+="| field | value |"$'\n'
doc+="|---|---|"$'\n'
doc+="| slug | \`$SLUG\` |"$'\n'
doc+="| version | \`${VERSION:-?}\` |"$'\n'
doc+="| schema_version | \`${SCHEMA_VERSION:-?}\` |"$'\n'
doc+="| author | ${AUTHOR:-?} |"$'\n'
doc+="| license | ${LICENSE:-?} |"$'\n\n'

if [[ -n "$DESCRIPTION" && "$DESCRIPTION" != "$SHORT" ]]; then
  doc+="$DESCRIPTION"$'\n\n'
fi

# Personas
if (( ${#yaml_personas[@]} > 0 )) || (( ${#identity_files[@]} > 0 )); then
  doc+="## Personas"$'\n\n'
  declare -a seen=()
  for p in "${yaml_personas[@]}" "${identity_files[@]}"; do
    if [[ "$p" == *.md ]]; then
      handle=$(basename "$p" .md)
      rel=${p#$PACK_PATH/}
      line="- \`@$handle\` → [\`$rel\`]($rel)"
    else
      handle="$p"
      if [[ -f "$PACK_PATH/identity/$handle.md" ]]; then
        rel="identity/$handle.md"
        line="- \`@$handle\` → [\`$rel\`]($rel)"
      else
        line="- \`@$handle\`"
      fi
    fi
    case " ${seen[*]} " in *" $handle "*) continue ;; esac
    seen+=("$handle")
    doc+="$line"$'\n'
  done
  doc+=$'\n'
fi

# Skills
if [[ -n "$skills_block" ]]; then
  doc+="## Skills"$'\n\n'
  doc+="$skills_block"
  doc+=$'\n'
fi

# Commands
if [[ -n "$commands_block" ]]; then
  doc+="## Commands"$'\n\n'
  doc+="$commands_block"
  doc+=$'\n'
fi

# Composes with
doc+="## Composes with"$'\n\n'
doc+="$composes_block"
doc+=$'\n'

# Streams
doc+="## Streams"$'\n\n'
doc+="**Reads**:"$'\n\n'
doc+=$(fmt_list "$reads_list")
doc+=$'\n\n'
doc+="**Writes**:"$'\n\n'
doc+=$(fmt_list "$writes_list")
doc+=$'\n\n'
if [[ -z "$reads_list$writes_list" ]]; then
  doc+="> Declare \`reads:\` and \`writes:\` in \`construct.yaml\` to enable doctrine §3 pipe compatibility checks."$'\n\n'
fi

# Grimoires
doc+="## Grimoires read/write (SEED §12)"$'\n\n'
if [[ -z "$grimoires_reads$grimoires_writes" ]]; then
  doc+="_No grimoires paths declared. Without a declaration this construct cannot participate in path-based composition — see SEED §12 for the convention._"$'\n\n'
else
  if [[ -n "$grimoires_reads" ]]; then
    doc+="**Reads from**:"$'\n\n'
    while IFS= read -r p; do [[ -z "$p" ]] && continue; doc+="- \`$p\`"$'\n'; done <<< "$grimoires_reads"
    doc+=$'\n'
  fi
  if [[ -n "$grimoires_writes" ]]; then
    doc+="**Writes to**:"$'\n\n'
    while IFS= read -r p; do [[ -z "$p" ]] && continue; doc+="- \`$p\`"$'\n'; done <<< "$grimoires_writes"
    doc+=$'\n'
  fi
  doc+="> The grimoire path IS the interface — constructs writing to the same path compose automatically."$'\n\n'
fi

# Install
doc+="## Install"$'\n\n'
doc+='```bash'$'\n'
doc+="/constructs install $SLUG"$'\n'
doc+='```'$'\n\n'

doc+="## Provenance"$'\n\n'
doc+="- Canonical spec: \`construct.yaml\`"$'\n'
doc+="- Generator: \`.claude/scripts/butterfreezone-construct-gen.sh\`"$'\n'
doc+="- Conventions: typed streams (Signal/Verdict/Artifact/Intent/Operator-Model) · composition pipes · grimoires-as-interface"$'\n'
if (( WITH_TIMESTAMP )); then
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  doc+="- Generated at: $ts"$'\n'
fi

# --------------------------------------------------------------------------
# Emit
# --------------------------------------------------------------------------
if (( TO_STDOUT )); then
  printf '%s' "$doc"
  exit 0
fi

OUTPUT="${OUTPUT:-$PACK_PATH/CONSTRUCT-README.md}"
if (( DRY_RUN )); then
  echo "[bfz-construct-gen] would write → $OUTPUT (${#doc} bytes)"
  printf '%s' "$doc" | head -10
  echo "..."
  exit 0
fi

printf '%s' "$doc" > "$OUTPUT"
echo "[bfz-construct-gen] wrote $OUTPUT"
