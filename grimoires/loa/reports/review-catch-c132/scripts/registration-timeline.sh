#!/usr/bin/env bash
# registration-timeline.sh — one table, in time order, of every pre-registration document, every REGISTRATION-N.json and every
# data look of cycle-132, so a reader can tell which addenda were registered before which look (Bridgebuilder round 1, F-009).
# Times are the first git commit that added each file (UTC; the re-taken final read: its last commit); hashes are copied from PREREGISTRATION-sha256.txt (the chain
# listing, never recomputed here). Output: grimoires/loa/reports/review-catch-c132/registration-timeline.md (deterministic).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.."
S=grimoires/loa/evals/ablation-2.0-c132; R=grimoires/loa/reports/review-catch-c132; L=grimoires/loa/reports/ablation-2.0/c132-looks
CHAIN=$R/PREREGISTRATION-sha256.txt
added() { TZ=UTC git log --diff-filter=A --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd -- "$1" | tail -1; }
last()  { TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd -- "$1"; }
sha12() { awk -v f="$1" '$1 == f && $2 == "sha256" {print substr($3, 1, 12); exit}' "$CHAIN"; }
rows=()
rows+=("$(added $S/PREREGISTRATION.md)	pre-registration	\`PREREGISTRATION.md\`	$(sha12 PREREGISTRATION.md)	—")
for n in $(seq 1 18); do f=$S/PREREGISTRATION-addendum-$n.md; [ -f "$f" ] || continue
  rows+=("$(added $f)	addendum $n	\`$(basename $f)\`	$(sha12 "$(basename $f)")	—"); done
for f in $S/REGISTRATION.json $S/REGISTRATION-{1..17}.json; do [ -f "$f" ] || continue; b=$(basename $f); n="${b#REGISTRATION-}"; n="${n%.json}"
  [ "$n" = REGISTRATION ] && ev="registration at kickoff" || ev="registration $n"
  rows+=("$(added $f)	$ev	\`$b\`	$(sha12 "$b")	\`$(jq -r '.pin | .[0:8]' $f)\`"); done
rows+=("$(added $L/look-1)	look 1 (data read)	\`c132-looks/look-1/\`	—	—")
rows+=("$(added $L/look-1-amended)	look 1 re-read under addendum 10	\`c132-looks/look-1-amended/\`	—	—")
rows+=("$(added $L/look-2)	look 2 (data read)	\`c132-looks/look-2/\`	—	—")
rows+=("$(added $L/look-3)	look 3, the final look (data read)	\`c132-looks/look-3/\`	—	—")
rows+=("$(added grimoires/loa/reports/ablation-2.0/c132-final)	final read under REGISTRATION-14	\`c132-final/\`	—	—")
rows+=("$(last $R/reads.md)	final read re-taken under REGISTRATION-15 (analysis addendum 16; every registered figure byte-identical)	\`reads.md\`	—	—")
{
  echo "## Registration timeline"
  echo
  echo "Every pre-registration document, registration and data look of the cycle, in the order git recorded them (first commit, UTC). A row that follows a look was written after that look's rows had been read; hashes are the chain listing's (\`PREREGISTRATION-sha256.txt\`)."
  echo
  echo "| committed (UTC) | event | file | sha256 (first 12) | pipeline pin |"
  echo "|---|---|---|---|---|"
  printf '%s\n' "${rows[@]}" | LC_ALL=C sort | awk -F'\t' '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}'
} > $R/registration-timeline.md
echo "wrote $R/registration-timeline.md ($(grep -c '^|' $R/registration-timeline.md) table lines)"
