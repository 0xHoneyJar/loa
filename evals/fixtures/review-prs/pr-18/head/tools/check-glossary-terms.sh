#!/usr/bin/env bash
# =============================================================================
# tools/check-glossary-terms.sh: does every backticked framework term in the
# kernel resolve to a glossary entry?
#
# The kernel (.claude/loa/CLAUDE.loa.md) is the only extraction scope. Every
# backticked span outside fenced code is a candidate; a span is kept only when
# it matches ^[A-Za-z][A-Za-z0-9_-]*$, which drops paths, scripts, flags,
# commands and config keys (anything with "/", ".", "--", ":" or "(") as well
# as spaced phrases and operators. A kept token resolves when it matches,
# case-insensitively, a **Term** entry or an _Aliases_: token in the glossary's
# "## Language" section, with a plural "s" or "es" folded and "-", "_" and a
# space treated alike; or when the allowlist names it. The allowlist holds
# code identifiers the heuristic cannot tell from a term: one token per line,
# "#" starts a comment (give the reason there), at most 30 entries.
#
# Usage:
#   tools/check-glossary-terms.sh [--kernel PATH] [--glossary PATH]
#                                 [--allowlist PATH] [--json] [--report]
#
#   --kernel PATH     default .claude/loa/CLAUDE.loa.md
#   --glossary PATH   default .claude/loa/GLOSSARY.md
#   --allowlist PATH  default .claude/data/glossary-allowlist.txt
#   --json            one JSON report on stdout
#   --report          list every kept token with its resolution
#                     (defined, alias, allowlisted or MISS)
#
# Exit codes: 0 every token resolves (a stale allowlist entry only WARNs)
#             1 a token misses, or the allowlist has more than 30 entries
#             2 usage, or an input file is unreadable
# =============================================================================
set -euo pipefail
export LC_ALL=C

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$ROOT/.claude/loa/CLAUDE.loa.md"
GLOSSARY="$ROOT/.claude/loa/GLOSSARY.md"
ALLOWLIST="$ROOT/.claude/data/glossary-allowlist.txt"
ALLOWLIST_MAX=30
JSON=0
REPORT=0
ME="check-glossary-terms.sh"

need_arg() { [[ $2 -ge 2 ]] || { echo "$ME: $1 needs a path" >&2; exit 2; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel)    need_arg "$1" $#; KERNEL="$2"; shift 2 ;;
    --glossary)  need_arg "$1" $#; GLOSSARY="$2"; shift 2 ;;
    --allowlist) need_arg "$1" $#; ALLOWLIST="$2"; shift 2 ;;
    --json)   JSON=1; shift ;;
    --report) REPORT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "$ME: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done

for f in "$KERNEL" "$GLOSSARY" "$ALLOWLIST"; do
  [[ -f "$f" && -r "$f" ]] || { echo "$ME: cannot read $f" >&2; exit 2; }
done
if [[ "$JSON" -eq 1 ]]; then
  command -v jq >/dev/null 2>&1 || { echo "$ME: --json needs jq" >&2; exit 2; }
fi

# Display names: repo-relative when the file sits under the repo root.
rel() { case "$1" in "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;; *) printf '%s' "$1" ;; esac; }
DK="$(rel "$KERNEL")"; DG="$(rel "$GLOSSARY")"; DA="$(rel "$ALLOWLIST")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-terms.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 1. Kept kernel tokens, "line<TAB>token", first occurrence only, in order.
awk '
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  {
    s = $0
    while (match(s, /`[^`]+`/)) {
      t = substr(s, RSTART + 1, RLENGTH - 2)
      s = substr(s, RSTART + RLENGTH)
      if (t ~ /^[A-Za-z][A-Za-z0-9_-]*$/ && !(t in seen)) { seen[t] = 1; printf "%d\t%s\n", NR, t }
    }
  }
' "$KERNEL" > "$WORK/tokens.tsv"

# 2. Glossary names, "kind<TAB>name<TAB>entry": kind is term or alias, entry is
#    the **Term** the name belongs to. Only the "## Language" section counts.
awk '
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^## / { h = $0; sub(/^## +/, "", h); sub(/[[:space:]]+$/, "", h); lang = (h == "Language"); next }
  /^# / { lang = 0; next }
  !lang { next }
  /^\*\*[^*]+\*\*:/ {
    t = $0; sub(/^\*\*/, "", t); sub(/\*\*:.*$/, "", t); gsub(/`/, "", t)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    entry = t; printf "term\t%s\t%s\n", t, entry; next
  }
  /^_Aliases_:/ {
    a = $0; sub(/^_Aliases_:[[:space:]]*/, "", a); gsub(/`/, "", a)
    n = split(a, parts, /,/)
    for (i = 1; i <= n; i++) {
      p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
      if (p != "") printf "alias\t%s\t%s\n", p, entry
    }
  }
' "$GLOSSARY" > "$WORK/names.tsv"

# 3. Allowlist entries, "line<TAB>token" (comment and blank lines dropped).
awk '
  { s = $0; sub(/#.*/, "", s); gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    if (s == "") next
    split(s, f, /[[:space:]]+/); printf "%d\t%s\n", NR, f[1] }
' "$ALLOWLIST" > "$WORK/allow.tsv"

# 4. Resolve. "resolution<TAB>token<TAB>line<TAB>entry" for each kept token
#    ("MISS" with an empty entry when nothing matches), then
#    "STALE<TAB>token<TAB>allowlist-line<TAB>" for allowlist entries that no
#    longer occur in the kernel and "REDUNDANT<TAB>…<TAB>entry" for ones the
#    glossary already resolves.
awk -F'\t' '
  function norm(x) { x = tolower(x); gsub(/[-_ ]+/, " ", x); return x }
  function put(map, k, v) { if (!(k in map)) map[k] = v }
  # every spelling a name answers to: itself, its s and es plurals, and, for
  # a plural name, its singular (the plural fold is applied here only)
  function add(map, x, v) { x = norm(x); put(map, x, v); put(map, x "s", v); put(map, x "es", v)
                            if (x ~ /es$/) put(map, substr(x, 1, length(x) - 2), v)
                            if (x ~ /s$/) put(map, substr(x, 1, length(x) - 1), v) }
  function lookup(map, x,   k) { k = norm(x); return (k in map) ? map[k] : "" }
  FILENAME == ARGV[1] { if ($1 == "term") add(term, $2, $3); else add(alias, $2, $3); next }
  FILENAME == ARGV[2] { allow[norm($2)] = $1; allowtok[norm($2)] = $2; next }
  {
    used[norm($2)] = 1
    if ((e = lookup(term, $2)) != "") r = "defined"
    else if ((e = lookup(alias, $2)) != "") r = "alias"
    else if (norm($2) in allow) { r = "allowlisted"; e = "" }
    else { r = "MISS"; e = "" }
    printf "%s\t%s\t%s\t%s\n", r, $2, $1, e
  }
  END {
    for (k in allow) {
      if (!(k in used)) printf "STALE\t%s\t%s\t\n", allowtok[k], allow[k]
      else if ((e = lookup(term, allowtok[k])) != "" || (e = lookup(alias, allowtok[k])) != "")
        printf "REDUNDANT\t%s\t%s\t%s\n", allowtok[k], allow[k], e
    }
  }
' "$WORK/names.tsv" "$WORK/allow.tsv" "$WORK/tokens.tsv" > "$WORK/resolved.tsv"

kept="$(wc -l < "$WORK/tokens.tsv" | tr -d '[:space:]')"
allow_count="$(wc -l < "$WORK/allow.tsv" | tr -d '[:space:]')"
n_of() { awk -F'\t' -v k="$1" '$1 == k' "$WORK/resolved.tsv" | wc -l | tr -d '[:space:]'; }
n_def="$(n_of defined)"; n_alias="$(n_of alias)"; n_allow="$(n_of allowlisted)"; n_miss="$(n_of MISS)"

violations=()
warnings=()
while IFS=$'\t' read -r r tok ln entry; do
  case "$r" in
    MISS) violations+=("MISS: \`$tok\` ($DK:$ln) has no glossary entry; define **$tok** in $DG, add it to an entry's _Aliases_: line, or, if it is a code identifier, allowlist it in $DA with a '# reason' comment") ;;
    STALE) warnings+=("allowlist entry '$tok' ($DA:$ln) no longer occurs in $DK; remove it") ;;
    REDUNDANT) warnings+=("allowlist entry '$tok' ($DA:$ln) is already resolved by the glossary entry **$entry**; remove it") ;;
  esac
done < "$WORK/resolved.tsv"
if [[ "$allow_count" -gt "$ALLOWLIST_MAX" ]]; then
  violations+=("the allowlist $DA has $allow_count entries, over the limit of $ALLOWLIST_MAX; define the framework terms among them in the glossary instead")
fi

if [[ "$JSON" -eq 1 ]]; then
  jq -Rn --arg kernel "$DK" --arg glossary "$DG" --arg allowlist "$DA" \
     --argjson allow_count "$allow_count" --argjson allow_max "$ALLOWLIST_MAX" \
     --rawfile v <(printf '%s\n' ${violations[@]+"${violations[@]}"}) \
     --rawfile w <(printf '%s\n' ${warnings[@]+"${warnings[@]}"}) '
    [inputs | split("\t") | {resolution: .[0], token: .[1], line: (.[2] | tonumber), entry: .[3]}] as $rows
    | ($rows | map(select(.resolution | IN("defined", "alias", "allowlisted", "MISS")))) as $tokens
    | {ok: null,
       kernel: $kernel, glossary: $glossary, allowlist: $allowlist,
       kept: ($tokens | length),
       counts: {defined: ($tokens | map(select(.resolution == "defined")) | length),
                alias: ($tokens | map(select(.resolution == "alias")) | length),
                allowlisted: ($tokens | map(select(.resolution == "allowlisted")) | length),
                missing: ($tokens | map(select(.resolution == "MISS")) | length)},
       allowlist_entries: $allow_count, allowlist_max: $allow_max,
       tokens: ($tokens | map({token, line, resolution, entry: (if .entry == "" then null else .entry end)})),
       missing: ($tokens | map(select(.resolution == "MISS") | .token)),
       stale_allowlist: ($rows | map(select(.resolution == "STALE") | .token)),
       redundant_allowlist: ($rows | map(select(.resolution == "REDUNDANT") | .token)),
       violations: ($v | split("\n") | map(select(length > 0))),
       warnings: ($w | split("\n") | map(select(length > 0)))}
    | .ok = ((.violations | length) == 0)
  ' < "$WORK/resolved.tsv"
else
  if [[ "$REPORT" -eq 1 ]]; then
    awk -F'\t' '$1 != "STALE" && $1 != "REDUNDANT" {
      printf "%-11s %-24s line %-4s %s\n", $1, $2, $3, ($4 == "" ? "" : "-> " $4) }' "$WORK/resolved.tsv"
  fi
  for w in ${warnings[@]+"${warnings[@]}"}; do echo "WARN: $w"; done
  for v in ${violations[@]+"${violations[@]}"}; do echo "$v" >&2; done
  echo "kernel tokens kept: $kept; defined: $n_def; alias: $n_alias; allowlisted: $n_allow; missing: $n_miss; allowlist entries: $allow_count/$ALLOWLIST_MAX"
  if [[ ${#violations[@]} -eq 0 ]]; then echo "PASS"; else echo "FAIL" >&2; fi
fi

[[ ${#violations[@]} -eq 0 ]] || exit 1
exit 0
