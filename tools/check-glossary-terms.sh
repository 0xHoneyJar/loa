#!/usr/bin/env bash
# =============================================================================
# tools/check-glossary-terms.sh: does every backticked framework term in the
# kernel resolve to a glossary entry?
#
# The kernel (.claude/loa/CLAUDE.loa.md) is the only extraction scope. Every
# backticked span outside fenced code is a candidate; a span is kept only when
# it matches ^[A-Za-z][A-Za-z0-9_-]*(:[A-Za-z0-9_-]+)?$: a word, optionally
# with one interior colon so label-style terms such as decision:grilling are
# checked too (grimoires/loa/sdd.md D-6.2 widened by sprint-254 review round
# 1; on the kernel of that day the widening added no token). The shape drops
# paths, scripts, flags, commands and config values (anything with "/", ".",
# "--", "(", a second colon or a colon at either end) as well as spaced
# phrases such as "audit: skip" and operators. Fences follow CommonMark
# (.claude/scripts/lib/md-fence.awk). A kept token resolves when it matches,
# case-insensitively, a **Term** entry or an _Aliases_: token in the glossary's
# "## Language" section, with a plural "s" or "es" folded and "-", "_" and a
# space treated alike; or when the allowlist names it. The allowlist holds
# code identifiers the heuristic cannot tell from a term: one token per line,
# "#" starts a comment (give the reason there), at most 30 entries.
#
# Aliases are a second way to resolve a token, so they are reported too: an
# advisory WARN when more kernel tokens resolve through _Aliases_: lines than
# through **Term** entries (review alias lines in a glossary diff as closely
# as allowlist lines), and a WARN for an _Aliases_: line that precedes every
# entry (ignored here; validate-artifact.sh --type glossary fails it).
# --report also lists, for information only, the entries that the glossary's
# own prose (the context paragraph and the other entries' definitions) never
# mentions and that no kernel token resolves to by its term: "resolution-only"
# when kernel tokens resolve only through its aliases, "unreferenced" when none
# does. The gate is lint-grade by design: kernel, glossary and allowlist are
# tracked, agent-editable files, so a reviewer reads these lists in the diff.
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
# Exit codes: 0 every token resolves (stale or redundant allowlist entries,
#               orphan alias lines and the alias ratio only WARN)
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
FENCE_AWK="$ROOT/.claude/scripts/lib/md-fence.awk"
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

for f in "$KERNEL" "$GLOSSARY" "$ALLOWLIST" "$FENCE_AWK"; do
  [[ -f "$f" && -r "$f" ]] || { echo "$ME: cannot read $f" >&2; exit 2; }
done
if [[ "$JSON" -eq 1 ]]; then
  # jq 1.5 is enough: the report avoids --rawfile and IN() (jq 1.6 only).
  command -v jq >/dev/null 2>&1 || { echo "$ME: --json needs jq" >&2; exit 2; }
fi
FENCE_SRC="$(cat "$FENCE_AWK")"

# Display names: repo-relative when the file sits under the repo root.
rel() { case "$1" in "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;; *) printf '%s' "$1" ;; esac; }
DK="$(rel "$KERNEL")"; DG="$(rel "$GLOSSARY")"; DA="$(rel "$ALLOWLIST")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-terms.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 1. Kept kernel tokens, "line<TAB>token", first occurrence only, in order.
awk "$FENCE_SRC"'
  md_fence($0) { next }
  {
    # CommonMark code spans: a run of n backticks closes on the next run of
    # exactly n; an unmatched run is literal text.
    s = $0
    while ((i = index(s, "`")) > 0) {
      n = 0; while (substr(s, i + n, 1) == "`") n++
      rest = substr(s, i + n); found = 0; off = 0
      while ((j = index(substr(rest, off + 1), "`")) > 0) {
        j += off; m = 0; while (substr(rest, j + m, 1) == "`") m++
        if (m == n) { t = substr(rest, 1, j - 1); s = substr(rest, j + m); found = 1; break }
        off = j + m - 1
      }
      if (!found) { s = rest; continue }
      if (t ~ /^ / && t ~ / $/ && t ~ /[^ ]/) t = substr(t, 2, length(t) - 2)
      if (t ~ /^[A-Za-z][A-Za-z0-9_-]*(:[A-Za-z0-9_-]+)?$/ && !(t in seen)) { seen[t] = 1; printf "%d\t%s\n", NR, t }
    }
  }
' "$KERNEL" > "$WORK/tokens.tsv"

# 2. Glossary names, "kind<TAB>name<TAB>entry": kind is term or alias, entry is
#    the **Term** the name belongs to; "orphan<TAB>line<TAB>" for an _Aliases_:
#    line before any entry. Only the "## Language" section counts.
awk "$FENCE_SRC"'
  md_fence($0) { next }
  /^## / { h = $0; sub(/^## +/, "", h); sub(/[[:space:]]+$/, "", h); lang = (h == "Language"); entry = ""; next }
  /^# / { lang = 0; entry = ""; next }
  !lang { next }
  /^\*\*[^*]+\*\*:/ {
    t = $0; sub(/^\*\*/, "", t); sub(/\*\*:.*$/, "", t); gsub(/`/, "", t)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    entry = t; printf "term\t%s\t%s\n", t, entry; next
  }
  /^_Aliases_:/ && entry == "" { printf "orphan\t%d\t\n", NR; next }
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
  FILENAME == ARGV[1] { if ($1 == "term") add(term, $2, $3); else if ($1 == "alias") add(alias, $2, $3); next }
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

# 5. Entry references (only --report and --json show them; the exit code never
#    depends on them). "kind<TAB>entry<TAB>alias tokens" with kind
#    resolution-only or unreferenced, in glossary order.
awk -F'\t' "$FENCE_SRC"'
  function key(x) { x = tolower(x); gsub(/[^a-z0-9:]+/, " ", x); return " " x " " }
  FILENAME == ARGV[1] {
    if (md_fence($0)) next
    if ($0 ~ /^#/ || $0 ~ /^_(Avoid|Aliases)_:/ || $0 !~ /[^[:space:]]/) next
    owner = ""; text = $0
    if ($0 ~ /^\*\*[^*]+\*\*:/) { owner = $0; sub(/^\*\*/, "", owner); sub(/\*\*:.*$/, "", owner); gsub(/`/, "", owner)
                                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", owner); sub(/^\*\*[^*]+\*\*:/, "", text) }
    np++; pown[np] = owner; ptext[np] = key(text); next
  }
  FILENAME == ARGV[2] { if ($1 == "term") { ne++; ent[ne] = $2 } next }
  { if ($1 == "defined") byterm[$4] = 1; else if ($1 == "alias") byalias[$4] = byalias[$4] (byalias[$4] == "" ? "" : ", ") $2 }
  END {
    for (i = 1; i <= ne; i++) {
      e = ent[i]; if (e in byterm) continue
      k = key(e); sub(/^ /, "", k); sub(/ $/, "", k); hit = 0
      for (j = 1; j <= np && !hit; j++)
        if (pown[j] != e && (index(ptext[j], " " k " ") || index(ptext[j], " " k "s ") || index(ptext[j], " " k "es "))) hit = 1
      if (hit) continue
      printf "%s\t%s\t%s\n", ((e in byalias) ? "resolution-only" : "unreferenced"), e, byalias[e]
    }
  }
' "$GLOSSARY" "$WORK/names.tsv" "$WORK/resolved.tsv" > "$WORK/entries.tsv"

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
while IFS=$'\t' read -r kind ln _; do
  [[ "$kind" == orphan ]] || continue
  warnings+=("_Aliases_: line $DG:$ln comes before any **Term**: entry, so its aliases resolve nothing; put it directly below its entry (validate-artifact.sh --type glossary fails this line)")
done < "$WORK/names.tsv"
if [[ "$n_alias" -gt "$n_def" ]]; then
  warnings+=("advisory: $n_alias kernel token(s) resolve through _Aliases_: lines and $n_def through **Term** entries; the kernel does not reference the glossary's terms in backticks, so this gate mostly checks aliases and identifiers. Review _Aliases_: lines in a glossary diff as closely as allowlist lines")
fi
if [[ "$allow_count" -gt "$ALLOWLIST_MAX" ]]; then
  violations+=("the allowlist $DA has $allow_count entries, over the limit of $ALLOWLIST_MAX; define the framework terms among them in the glossary instead")
fi

if [[ "$JSON" -eq 1 ]]; then
  jq -Rn --arg kernel "$DK" --arg glossary "$DG" --arg allowlist "$DA" \
     --argjson allow_count "$allow_count" --argjson allow_max "$ALLOWLIST_MAX" \
     --arg v "$(printf '%s\n' ${violations[@]+"${violations[@]}"})" \
     --arg w "$(printf '%s\n' ${warnings[@]+"${warnings[@]}"})" \
     --arg ents "$(cat "$WORK/entries.tsv")" '
    [inputs | split("\t") | {resolution: .[0], token: .[1], line: (.[2] | tonumber), entry: .[3]}] as $rows
    | ($rows | map(select(.resolution == "defined" or .resolution == "alias"
                          or .resolution == "allowlisted" or .resolution == "MISS"))) as $tokens
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
       unreferenced_entries: ($ents | split("\n") | map(select(length > 0) | split("\t")
                              | {entry: .[1], kind: .[0], alias_tokens: ((.[2] // "") | split(", ") | map(select(length > 0)))})),
       violations: ($v | split("\n") | map(select(length > 0))),
       warnings: ($w | split("\n") | map(select(length > 0)))}
    | .ok = ((.violations | length) == 0)
  ' < "$WORK/resolved.tsv"
else
  if [[ "$REPORT" -eq 1 ]]; then
    awk -F'\t' '$1 != "STALE" && $1 != "REDUNDANT" {
      printf "%-11s %-24s line %-4s %s\n", $1, $2, $3, ($4 == "" ? "" : "-> " $4) }' "$WORK/resolved.tsv"
    if [[ -s "$WORK/entries.tsv" ]]; then
      echo "resolution-only or unreferenced entries (information only; no kernel token names the term and no glossary prose mentions it):"
      awk -F'\t' '{ printf "  %-15s %s%s\n", $1, $2, ($3 == "" ? "" : " (kernel tokens via aliases: " $3 ")") }' "$WORK/entries.tsv"
    fi
  fi
  for w in ${warnings[@]+"${warnings[@]}"}; do echo "WARN: $w"; done
  for v in ${violations[@]+"${violations[@]}"}; do echo "$v" >&2; done
  echo "kernel tokens kept: $kept; defined: $n_def; alias: $n_alias; allowlisted: $n_allow; missing: $n_miss; allowlist entries: $allow_count/$ALLOWLIST_MAX"
  if [[ ${#violations[@]} -eq 0 ]]; then echo "PASS"; else echo "FAIL" >&2; fi
fi

[[ ${#violations[@]} -eq 0 ]] || exit 1
exit 0
